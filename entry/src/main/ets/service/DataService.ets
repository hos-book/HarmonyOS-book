import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { Book, Chapter } from '../model/Book';
import { BookPresentation } from '../model/BookPresentation';
import { LocalTextImage } from './text/LocalTextImage';
import { BookStorageCompat } from '../utils/BookStorageCompat';
import { BookCoverPolicy } from '../utils/BookCoverPolicy';
import { PreferenceService } from './PreferenceService';
import { TextReadingProgressService } from './text/TextReadingProgressService';
import { StorageMigrationService } from './StorageMigrationService';
import { OnlineTextContentCache } from './text/OnlineTextContentCache';
import { parseCachedChapters } from './ChapterCacheWorker';
import { ChapterCacheCodec } from './ChapterCacheCodec';

/** 缓存书"索引":只放元数据壳(无 chapters),小且冷启动读取飞快 */
const CACHED_BOOKS_FILE = 'cached_books_v1.json';
/** 旧版章节目录(sidecar):cached_toc/<id>.json,按需懒加载,命中即瞬时无网络 */
const CACHED_TOC_DIR = 'cached_toc';
/** 旧 preferences 缓存超过此字节数即判定含整章 TOC 巨值,合并进文件后压成元数据壳 */
const LEGACY_SLIM_THRESHOLD = 100 * 1024;
/** 缓存书上限 */
const MAX_CACHED_BOOKS = 200;

interface CacheRead {
  json: string;
  /** 文件是否存在 */
  existed: boolean;
  /** 读取是否成功(false = 文件在但读 IO 失败) */
  ok: boolean;
}

/**
 * 数据服务:承载本地导入的书 + 来自搜索的"缓存书"快照。
 * 缓存书让搜索得到的书也能被收藏 / 出现在书架 / 历史里。
 *
 * 存储分层(都在主进程内写,卡片 FormExtension 进程只读 preferences、不碰这些文件):
 *  - 索引 files/library_books_v1.json:全部缓存书的"元数据壳"(无 chapters),冷启动一次性读入内存,小而快。
 *  - sidecar files/library_toc/<id>.json:每本书的整章目录,单独一个小文件,打开某本书时才懒加载(瞬时,无网络)。
 *  这样"全部书的章节都本地缓存"与"冷启动不卡"二者兼得 —— 不再像单一大文件那样把几 MB 的整章
 *  TOC 在启动时全部读+解析(卡顿),也不像"瘦身丢章节"那样让旧书每次点开都要联网重拉。
 *
 * 文件写入三重保护:
 *  1) 串行化:所有写经 writeChain 排队,杜绝并发 TRUNC 交错损坏(冷启动收藏丢失的元凶)。
 *  2) 原子替换:先写 .tmp 再 moveFile 覆盖,进程被杀/崩溃也不会留半截文件。
 *  3) 读失败保护:区分 不存在(合法空)/ 读 IO 失败(本会话禁写,防冲掉好数据)/ 解析损坏(可重建)。
 */
export class DataService {
  private static cache: Book[] | null = null;
  private static cachedBooksMem: Book[] | null = null;
  private static ctx: common.Context | null = null;
  /** 写串行化链:每次写都接在上一个之后,避免并发写交错损坏文件 */
  private static writeChain: Promise<void> = Promise.resolve();
  /** 现有索引文件读 IO 失败过 → 本会话禁止覆盖写,防止把可能完好的磁盘数据冲成空 */
  private static persistUnsafe: boolean = false;
  /** sidecar 目录是否已确保存在(避免每次写都 mkdir) */
  private static tocDirReady: boolean = false;
  private static migrationPromise: Promise<void> | null = null;
  private static chapterReads: Map<string, Promise<Chapter[]>> = new Map();

  /** 由 EntryAbility 启动时注入,用于缓存书文件读写 */
  static setContext(c: common.Context): void {
    LocalTextImage.setRoot(c.filesDir);
    DataService.ctx = c;
    if (DataService.migrationPromise === null) {
      DataService.migrationPromise = DataService.migrateLegacyStorage();
      DataService.migrationPromise.catch((): void => { /* 读取入口会报告失败，不写入空书架。 */ });
    }
    OnlineTextContentCache.migrateStorage(c).catch((): void => { /* 正文读取时重试迁移。 */ });
  }

  private static cachedFilePath(): string | null {
    return DataService.ctx ? `${DataService.ctx.filesDir}/library_books_v1.json` : null;
  }

  private static tocDirPath(): string | null {
    return DataService.ctx ? `${DataService.ctx.filesDir}/library_toc` : null;
  }

  private static legacyCachedFilePath(): string | null {
    return DataService.ctx ? `${DataService.ctx.filesDir}/${CACHED_BOOKS_FILE}` : null;
  }

  private static legacyTocDirPath(): string | null {
    return DataService.ctx ? `${DataService.ctx.filesDir}/${CACHED_TOC_DIR}` : null;
  }

  private static legacyTocPath(id: string): string | null {
    const dir = DataService.legacyTocDirPath();
    if (!dir || !id) return null;
    const safe = id.replace(/[^A-Za-z0-9_.-]/g, '_');
    return `${dir}/${safe}.json`;
  }

  private static ensureStorageMigrated(): Promise<void> {
    if (DataService.migrationPromise === null) {
      DataService.migrationPromise = DataService.migrateLegacyStorage();
    }
    return DataService.migrationPromise;
  }

  private static async migrateLegacyStorage(): Promise<void> {
    // 新目录避免旧 filesDir 残留覆盖当前 cacheDir 中较新的书架数据。
    const ctx = DataService.ctx;
    if (ctx !== null) {
      await StorageMigrationService.migrateFileChecked(`${ctx.cacheDir}/${CACHED_BOOKS_FILE}`,
        `${ctx.filesDir}/library_books_v1.json`);
      await StorageMigrationService.migrateDirectory(`${ctx.cacheDir}/${CACHED_TOC_DIR}`,
        `${ctx.filesDir}/library_toc`, true);
    }
    const legacyFile = DataService.legacyCachedFilePath();
    const cacheFile = DataService.cachedFilePath();
    if (legacyFile && cacheFile) {
      await StorageMigrationService.migrateFileChecked(legacyFile, cacheFile);
    }
    const legacyToc = DataService.legacyTocDirPath();
    const cacheToc = DataService.tocDirPath();
    if (legacyToc && cacheToc) {
      await StorageMigrationService.migrateDirectory(legacyToc, cacheToc, true);
    }
  }

  private static tocPath(id: string): string | null {
    const dir = DataService.tocDirPath();
    if (!dir || !id) return null;
    // id 一般是 search_audio_<hash> 等安全字符,仍兜底过滤掉路径分隔符等
    const safe = id.replace(/[^A-Za-z0-9_.-]/g, '_');
    return `${dir}/${safe}.json`;
  }

  // ───────────────────────── 底层文件读写(串行 + 原子) ─────────────────────────

  /**
   * 安全读取:区分"不存在 / 读成功 / 读 IO 失败"。
   * 不能像旧实现那样把所有异常吞成空字符串 —— 那会让"读挂了"和"本来就空"无法区分,
   * 进而导致下一次写用空内容把磁盘上的完好数据覆盖掉。
   */
  private static async readFileSafe(path: string | null): Promise<CacheRead> {
    if (!path) return { json: '', existed: false, ok: true };
    let existed = false;
    try {
      existed = await fileIo.access(path);
    } catch (_e) {
      existed = false; // access 异常按"不存在"处理
    }
    if (!existed) return { json: '', existed: false, ok: true };
    try {
      const json = await fileIo.readText(path);
      return { json, existed: true, ok: true };
    } catch (_e) {
      return { json: '', existed: true, ok: false }; // 文件在但读失败
    }
  }

  /** 串行 + 原子写。persistUnsafe 时只更新内存、跳过落盘以保护磁盘上的好数据。 */
  private static writeFileSerial(path: string | null, json: string): Promise<void> {
    if (DataService.persistUnsafe || !path) {
      return Promise.resolve();
    }
    const task = DataService.writeChain.then(() => DataService.atomicWrite(path, json));
    // 链不能因单次失败而断:用 then(ok, err) 都吞掉,后续写仍能排队执行
    DataService.writeChain = task.then(() => {}, () => {});
    // 返回给调用方的也吞掉错误:写失败不应让上层的读/加载流程崩(数据仍在内存,下次重试,旧文件保持完整)
    return task.catch(() => {});
  }

  private static async atomicWrite(finalPath: string, json: string): Promise<void> {
    const tmp = finalPath + '.tmp';
    let f: fileIo.File | null = null;
    try {
      f = await fileIo.open(tmp, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.write(f.fd, json);
      try { await fileIo.fsync(f.fd); } catch (_e) { /* 部分文件系统不支持,忽略 */ }
    } finally {
      if (f) {
        try { await fileIo.close(f); } catch (_e) { /* ignore */ }
      }
    }
    // moveFile 默认 mode=0 = 覆盖目标(官方文档明确语义)。同目录内为原子替换:
    // 读者要么看到旧的完整文件,要么看到新的完整文件,不会读到半截。
    await fileIo.moveFile(tmp, finalPath);
  }

  private static async ensureTocDir(): Promise<void> {
    if (DataService.tocDirReady) return;
    const dir = DataService.tocDirPath();
    if (!dir) return;
    try { await fileIo.mkdir(dir); } catch (_e) { /* 已存在 */ }
    DataService.tocDirReady = true;
  }

  // ───────────────────────── sidecar 章节目录 ─────────────────────────

  /** 读取某本书的本地章节目录(瞬时,无网络)。没有则返回空数组。 */
  static async getChaptersForBook(id: string): Promise<Chapter[]> {
    const active = DataService.chapterReads.get(id);
    if (active !== undefined) return active;
    const task = DataService.readChaptersForBook(id);
    DataService.chapterReads.set(id, task);
    try { return await task; }
    finally { if (DataService.chapterReads.get(id) === task) DataService.chapterReads.delete(id); }
  }

  private static async readChaptersForBook(id: string): Promise<Chapter[]> {
    if (id.startsWith('import_') && DataService.ctx) {
      const imported = await DataService.readFileSafe(`${DataService.ctx.filesDir}/imported_toc/${id}.json`);
      if (imported.ok && imported.json) {
        const chapters = await taskpool.execute<[string], Chapter[]>(parseCachedChapters, imported.json);
        return chapters;
      }
    }
    await DataService.ensureStorageMigrated();
    let read = await DataService.readFileSafe(DataService.tocPath(id));
    if (!read.existed || !read.ok || !read.json) {
      const legacyRead = await DataService.readFileSafe(DataService.legacyTocPath(id));
      if (legacyRead.existed && legacyRead.ok && legacyRead.json) read = legacyRead;
    }
    if (!read.ok || !read.json) return [];
    try {
      return await taskpool.execute<[string], Chapter[]>(parseCachedChapters, read.json);
    } catch (_e) {
      return [];
    }
  }

  private static async writeToc(id: string, chapters: Chapter[]): Promise<void> {
    const path = DataService.tocPath(id);
    if (!path || DataService.persistUnsafe) return;
    await DataService.ensureTocDir();
    // Serialize only after earlier writes finish, and bound each write buffer.
    const task = DataService.writeChain.then(() => DataService.atomicWriteToc(path, chapters));
    DataService.writeChain = task.then(() => {}, () => {});
    await task.catch(() => {});
  }

  private static async atomicWriteToc(path: string, chapters: Chapter[]): Promise<void> {
    const tmp = path + '.tmp';
    const file = await fileIo.open(tmp, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      let chunk = '[';
      for (let i = 0; i < chapters.length; i++) {
        chunk += (i > 0 ? ',' : '') + ChapterCacheCodec.stringify(chapters[i]);
        if (chunk.length >= 64 * 1024) {
          await fileIo.write(file.fd, chunk);
          chunk = '';
        }
      }
      await fileIo.write(file.fd, chunk + ']');
      try { await fileIo.fsync(file.fd); } catch (_e) { /* 不支持 fsync 时仍原子替换。 */ }
    } finally { await fileIo.close(file); }
    await fileIo.moveFile(tmp, path);
  }

  private static async deleteToc(id: string): Promise<void> {
    const path = DataService.tocPath(id);
    if (!path) return;
    try { await fileIo.unlink(path); } catch (_e) { /* ignore */ }
    try { await fileIo.unlink(path + '.tmp'); } catch (_e) { /* ignore */ }
  }

  /** 给所有带章节的书各写一份 sidecar(迁移 / 恢复用) */
  private static async persistChaptersForBooks(books: Book[]): Promise<void> {
    for (const b of books) {
      if (b && b.id && !b.id.startsWith('import_') && b.chapters && b.chapters.length > 0) {
        await DataService.writeToc(b.id, b.chapters);
      }
    }
  }

  // ───────────────────────── 索引(元数据壳) ─────────────────────────

  /** 索引落盘:统一写成元数据壳(去 chapters/intro),章节单独走 sidecar */
  private static writeIndex(books: Book[]): Promise<void> {
    const slim: Book[] = books.map((b: Book): Book => DataService.slimBook(b));
    return DataService.writeFileSerial(DataService.cachedFilePath(), JSON.stringify(slim));
  }

  /**
   * 旧格式(章节内联在索引大文件里)→ 一次性拆分到 sidecar 并把索引瘦身。
   * 迁移后内存仍保留完整数据,仅磁盘索引变小,后续冷启动飞快。
   */
  private static async migrateInlineChaptersIfAny(books: Book[]): Promise<void> {
    let hasInline = false;
    for (const b of books) {
      if (b && b.chapters && b.chapters.length > 0) { hasInline = true; break; }
    }
    if (!hasInline) return;
    await DataService.persistChaptersForBooks(books);
    await DataService.writeIndex(books);
  }

  private static async load(): Promise<Book[]> {
    if (DataService.cache) return DataService.cache;
    DataService.cache = await DataService.getImportedBooks();
    return DataService.cache;
  }

  private static async loadCachedBooks(): Promise<Book[]> {
    if (DataService.cachedBooksMem) return DataService.cachedBooksMem;
    await DataService.ensureStorageMigrated();

    const primaryRead = await DataService.readFileSafe(DataService.cachedFilePath());
    let read = primaryRead;
    let usingLegacyFile = false;
    if (!primaryRead.existed || !primaryRead.ok || !primaryRead.json) {
      const legacyRead = await DataService.readFileSafe(DataService.legacyCachedFilePath());
      if (legacyRead.existed && legacyRead.ok && legacyRead.json) {
        read = legacyRead;
        usingLegacyFile = true;
      }
    }
    let fileBooks = DataService.parseBookList(read.json);

    // 现有索引存在但读 IO 失败:本会话禁止覆盖写,避免把可能完好的磁盘数据冲掉。
    if (primaryRead.existed && !primaryRead.ok) {
      DataService.persistUnsafe = true;
    }
    // 读到内容但解析为空、且原文不是合法空数组 → 文件损坏(旧版本并发写遗留)。
    const corrupt = read.existed && read.ok &&
      read.json.length > 0 && read.json.trim() !== '[]' && fileBooks.length === 0;

    const favoriteIds = await DataService.safeFavoriteIds();
    if (read.ok && !corrupt && fileBooks.length > 0 && DataService.containsAll(fileBooks, favoriteIds)) {
      DataService.cachedBooksMem = fileBooks;
      // 旧格式(章节内联)→ 拆 sidecar + 瘦身索引(一次性)
      await DataService.migrateInlineChaptersIfAny(fileBooks);
      if (usingLegacyFile) await DataService.writeIndex(fileBooks);
      return DataService.cachedBooksMem;
    }

    // 从旧 preferences 迁移 / 在文件损坏时据此重建。
    let legacyRaw = '';
    let legacyBooks: Book[] = [];
    try {
      legacyRaw = await PreferenceService.getCachedBooks();
      legacyBooks = DataService.parseBookList(legacyRaw);
    } catch (_e) { /* ignore */ }

    if (legacyBooks.length > 0) {
      const merged = DataService.mergeBookLists(fileBooks, legacyBooks);
      if (merged.length !== fileBooks.length || corrupt) {
        fileBooks = merged;
        await DataService.persistChaptersForBooks(fileBooks); // 带章节的写 sidecar
        await DataService.writeIndex(fileBooks);              // 索引瘦身
      }
      // 一次性根治旧 preferences 巨值:并入后压成壳,体积降到几十 KB(消并发损坏隐患,留卡片兜底标题/封面)。
      if (legacyRaw.length > LEGACY_SLIM_THRESHOLD) {
        try {
          const slim: Book[] = legacyBooks.map((b: Book): Book => DataService.slimBook(b));
          await PreferenceService.putCachedBookJson(JSON.stringify(slim));
        } catch (_e) { /* 压缩失败保持原值,下次冷启动重试 */ }
      }
    } else if (corrupt) {
      // 文件损坏且无可恢复来源:用合法空数组原子覆盖,清掉坏文件。收藏 id 仍在 → 书架占位卡,重搜即自愈。
      await DataService.writeIndex([]);
      fileBooks = [];
    }

    DataService.cachedBooksMem = fileBooks;
    await DataService.migrateInlineChaptersIfAny(fileBooks);
    if (usingLegacyFile) await DataService.writeIndex(fileBooks);
    return DataService.cachedBooksMem;
  }

  private static parseBookList(json: string): Book[] {
    if (!json || json === '[]') return [];
    try {
      const parsed: Book[] = JSON.parse(json);
      if (!Array.isArray(parsed)) return [];
      return parsed.filter((book: Book): boolean => !!book && typeof book === 'object' && typeof book.id === 'string')
        .map((book: Book): Book => BookStorageCompat.restoreMetadata(book));
    } catch (_e) {
      return [];
    }
  }

  private static async safeFavoriteIds(): Promise<string[]> {
    try {
      return await PreferenceService.getFavorites();
    } catch (_e) {
      return [];
    }
  }

  private static containsAll(books: Book[], ids: string[]): boolean {
    if (ids.length === 0) return true;
    const set = new Set<string>();
    for (const book of books) {
      if (book && book.id) set.add(book.id);
    }
    for (const id of ids) {
      if (!set.has(id)) return false;
    }
    return true;
  }

  private static mergeBookLists(primary: Book[], legacy: Book[]): Book[] {
    const seen = new Set<string>();
    const merged: Book[] = [];
    for (const book of primary) {
      if (!book || !book.id || seen.has(book.id)) continue;
      merged.push(book);
      seen.add(book.id);
    }
    for (const book of legacy) {
      if (!book || !book.id || seen.has(book.id)) continue;
      merged.push(book);
      seen.add(book.id);
    }
    return merged.map((book: Book): Book => BookPresentation.apply(book));
  }

  /** 元数据壳:索引/卡片兜底只用 id/标题/作者/封面/章数,去掉 chapters + intro 砍掉绝大部分体积 */
  private static slimBook(b: Book): Book {
    return {
      id: b.id,
      contentType: b.contentType,
      title: b.title,
      author: b.author,
      narrator: b.narrator,
      cover: b.cover,
      coverFromDetail: b.coverFromDetail,
      coverFallback: b.coverFallback,
      category: b.category,
      intro: '',
      wordCount: b.wordCount,
      latestChapterTitle: b.latestChapterTitle,
      updateTime: b.updateTime,
      completed: b.completed,
      totalDuration: b.totalDuration,
      chapterCount: b.chapterCount,
      rating: b.rating,
      tags: b.tags,
      chapters: [],
      tocComplete: b.tocComplete,
      bookUrl: b.bookUrl,
      sourceUrl: b.sourceUrl,
      variables: b.variables,
      skipIntro: b.skipIntro,
      skipOutro: b.skipOutro
    };
  }

  /** 返回:本地导入书 + 缓存书(去重,本地优先)。缓存书为元数据壳,章节按需用 getChaptersForBook 懒加载。 */
  static async getBooks(_context: common.Context): Promise<Book[]> {
    const local = await DataService.load();
    const cached = await DataService.loadCachedBooks();
    const seen = new Set<string>();
    const merged: Book[] = [];
    for (const b of local) {
      if (!seen.has(b.id)) {
        merged.push(b);
        seen.add(b.id);
      }
    }
    for (const b of cached) {
      if (!seen.has(b.id)) {
        merged.push(b);
        seen.add(b.id);
      }
    }
    return merged.map((book: Book): Book => BookPresentation.apply(book));
  }

  /** 按 id 取书,并补齐章节:本地导入书自带章节;缓存书章节缺失时从 sidecar 懒加载(瞬时,无网络)。 */
  static async getBookById(_context: common.Context, id: string): Promise<Book | undefined> {
    const local = await DataService.load();
    const fromLocal = local.find((b) => b.id === id);
    if (fromLocal) {
      if (fromLocal.chapters.length === 0) fromLocal.chapters = await DataService.getChaptersForBook(id);
      return BookPresentation.apply(fromLocal);
    }
    const cached = await DataService.loadCachedBooks();
    const book = cached.find((b) => b.id === id);
    if (!book) return undefined;
    if (!book.chapters || book.chapters.length === 0) {
      const toc = await DataService.getChaptersForBook(id);
      if (toc.length > 0) {
        // 回填到内存对象(引用持有,后续访问直接命中,不再读 sidecar)
        book.chapters = toc;
        if (!book.chapterCount || book.chapterCount < toc.length) book.chapterCount = toc.length;
      }
    }
    return BookPresentation.apply(book);
  }

  static async getImportedBooks(): Promise<Book[]> {
    try {
      const json = await PreferenceService.getImportedBooks();
      return DataService.parseBookList(json);
    } catch (_e) {
      return [];
    }
  }

  static async addImportedBook(book: Book): Promise<void> {
    if (!DataService.ctx) throw new Error('本地存储尚未初始化');
    const directory = `${DataService.ctx.filesDir}/imported_toc`;
    if (!await fileIo.access(directory)) {
      try { await fileIo.mkdir(directory, true); }
      catch (error) {
        if (!await fileIo.access(directory)) throw new Error(error instanceof Error ? error.message : String(error));
      }
    }
    await DataService.atomicWrite(`${directory}/${book.id}.json`, JSON.stringify(book.chapters));
    const list = await DataService.getImportedBooks();
    list.unshift(DataService.slimBook(book));
    await PreferenceService.saveImportedBooks(JSON.stringify(list));
    DataService.cache = list;
  }

  static async removeImportedBook(bookId: string): Promise<void> {
    const list = await DataService.getImportedBooks();
    const filtered = list.filter((b) => b.id !== bookId);
    await PreferenceService.saveImportedBooks(JSON.stringify(filtered));
    DataService.cache = filtered;
    if (DataService.ctx && /^import_[A-Za-z0-9_]+$/.test(bookId)) {
      for (const directory of ['audio', 'ebooks']) {
        try { await fileIo.rmdir(`${DataService.ctx.filesDir}/${directory}/${bookId}`); } catch (_error) { /* 文件可能已删除 */ }
      }
      try { await fileIo.unlink(`${DataService.ctx.filesDir}/imported_toc/${bookId}.json`); } catch (_error) { /* 旧书无独立目录 */ }
    }
  }

  static async readImportedText(book: Book, chapterUrl: string): Promise<string> {
    if (!DataService.ctx || !/^import_[A-Za-z0-9_]+$/.test(book.id) || book.sourceUrl.length > 0) {
      throw new Error('本地电子书不可用');
    }
    const root = `${DataService.ctx.filesDir}/ebooks/${book.id}/`;
    const filename = chapterUrl.substring(root.length);
    if (!chapterUrl.startsWith(root) || !/^[0-9]+\.txt$/.test(filename)) throw new Error('无效的本地章节路径');
    return fileIo.readText(chapterUrl);
  }

  /** 把搜索 / 在线源的书写入缓存池(去重,新数据覆盖旧的;无历史引用的临时书最多 200 本)。索引存壳,章节存 sidecar。 */
  static async upsertCachedBook(book: Book): Promise<void> {
    if (!book || !book.id) return;
    if (book.id.startsWith('import_')) return;
    const protectedIds = await DataService.historyBookIds();
    const list = await DataService.loadCachedBooks();
    const idx = list.findIndex((b) => b.id === book.id);
    if (idx >= 0) {
      BookCoverPolicy.merge(book, list[idx]);
      list.splice(idx, 1);
    }
    list.unshift(book); // 内存保留完整书(含章节),本会话内访问瞬时
    if (protectedIds !== null) {
      let disposableCount = 0;
      for (let index = 0; index < list.length; index++) {
        if (protectedIds.has(list[index].id)) continue;
        disposableCount++;
        if (disposableCount <= MAX_CACHED_BOOKS) continue;
        const removed = list.splice(index--, 1)[0];
        await DataService.deleteToc(removed.id);
      }
    }
    DataService.cachedBooksMem = list;
    await DataService.writeIndex(list);
    // 仅在确有章节时写 sidecar:空章节的 upsert(如时长回写前)不覆盖已存的好目录
    if (book.tocComplete !== false && book.chapters && book.chapters.length > 0) {
      await DataService.writeToc(book.id, book.chapters);
    }
  }

  /** 收藏/历史属于用户数据；读取引用失败时暂停淘汰，不能按空历史处理。 */
  static async historyBookIds(): Promise<Set<string> | null> {
    if (!DataService.ctx) return null;
    try {
      const ids = new Set<string>(await PreferenceService.getFavorites());
      for (const item of await PreferenceService.getHistory()) ids.add(item.bookId);
      for (const item of await TextReadingProgressService.getAll(DataService.ctx)) ids.add(item.bookId);
      return ids;
    } catch (_e) { return null; }
  }

  /** Replacing a source discards requests and content while keeping favorite/history book identities. */
  static async invalidateSourceCaches(sourceUrls: Set<string>,
    beforeInvalidate?: (bookId: string, chapters: Chapter[]) => void): Promise<string[]> {
    const list = await DataService.loadCachedBooks();
    const ids: string[] = [];
    const protectedIds = await DataService.historyBookIds();
    const protectedBooks: string[] = [];
    const discardedIds: string[] = [];
    for (const book of list) {
      if (!sourceUrls.has(book.sourceUrl)) continue;
      if (beforeInvalidate !== undefined) {
        const chapters = book.chapters.length > 0 ? book.chapters : await DataService.getChaptersForBook(book.id);
        beforeInvalidate(book.id, chapters);
      }
      if (protectedIds === null || protectedIds.has(book.id)) {
        protectedBooks.push(OnlineTextContentCache.key(book.sourceUrl, book.bookUrl, ''));
      } else {
        book.chapters = [];
        book.totalDuration = 0;
        discardedIds.push(book.id);
      }
      book.tocComplete = false;
      book.variables = {};
      ids.push(book.id);
    }
    await DataService.writeIndex(list);
    const task = DataService.writeChain.then(async (): Promise<void> => {
      for (const id of discardedIds) {
        await DataService.deleteToc(id);
        const legacy = DataService.legacyTocPath(id);
        if (legacy && await fileIo.access(legacy)) await fileIo.unlink(legacy);
      }
    });
    DataService.writeChain = task.then(() => {}, () => {});
    await task;
    if (DataService.ctx !== null) {
      await OnlineTextContentCache.invalidateSources(DataService.ctx, sourceUrls, new Set(protectedBooks));
    }
    return ids;
  }

  /** 清空缓存书池(索引 + sidecar 目录 + 内存),用于"清空书架"。 */
  static async clearCachedBooks(): Promise<void> {
    const task = DataService.writeChain.then(async () => {
      await DataService.ensureStorageMigrated();
      DataService.cachedBooksMem = [];
      DataService.persistUnsafe = false;
      const path = DataService.cachedFilePath();
      if (path) {
        try { await fileIo.unlink(path); } catch (_e) { /* ignore */ }
        try { await fileIo.unlink(path + '.tmp'); } catch (_e) { /* ignore */ }
      }
      const dir = DataService.tocDirPath();
      if (dir) {
        try { await fileIo.rmdir(dir); } catch (_e) { /* ignore */ }
      }
      const legacyPath = DataService.legacyCachedFilePath();
      if (legacyPath) {
        try { await fileIo.unlink(legacyPath); } catch (_e) { /* ignore */ }
        try { await fileIo.unlink(legacyPath + '.tmp'); } catch (_e) { /* ignore */ }
      }
      const legacyDir = DataService.legacyTocDirPath();
      if (legacyDir) {
        try { await fileIo.rmdir(legacyDir); } catch (_e) { /* ignore */ }
      }
      DataService.tocDirReady = false;
    });
    DataService.writeChain = task.then(() => {}, () => {});
    await task;
  }

  static async removeCachedBook(bookId: string): Promise<void> {
    const list = await DataService.loadCachedBooks();
    const filtered = list.filter((b) => b.id !== bookId);
    DataService.cachedBooksMem = filtered;
    await DataService.writeIndex(filtered);
    await DataService.deleteToc(bookId);
  }

  /** 系统备份只带在线书元数据壳，章节在目标设备按需重新获取。 */
  static async exportBackupBookShells(): Promise<Book[]> {
    const books = await DataService.loadCachedBooks();
    return books
      .filter((book: Book) => !!book && !!book.id && !book.id.startsWith('import_'))
      .map((book: Book): Book => DataService.slimBook(book));
  }

  static async restoreBackupBookShells(books: Book[], strict: boolean = false): Promise<void> {
    const current = await DataService.loadCachedBooks();
    const restored = books
      .filter((book: Book) => !!book && !!book.id && !book.id.startsWith('import_'))
      .map((book: Book): Book => DataService.slimBook(BookStorageCompat.restoreMetadata(book)));
    const merged = DataService.mergeBookLists(restored, current);
    if (strict) {
      const path = DataService.cachedFilePath();
      if (!path || DataService.persistUnsafe) throw new Error('Book storage is unavailable');
      const slim: Book[] = merged.map((book: Book): Book => DataService.slimBook(book));
      const task = DataService.writeChain.then(() => DataService.atomicWrite(path, JSON.stringify(slim)));
      DataService.writeChain = task.then(() => {}, () => {});
      await task;
      DataService.cachedBooksMem = merged;
    } else {
      DataService.cachedBooksMem = merged;
      await DataService.writeIndex(merged);
    }
  }

  /**
   * 在 book.chapters 中定位历史记录对应的章节索引。
   * 章节 id 是位置型(`${book.id}-c${idx}`),连载更新/TOC 重排后会漂移,
   * 优先同时匹配 id 与标题，避免重名章节跳到第一条同名记录。
   * 目录变动时仅用唯一标题纠正位置；标题重复时保留 id 对应的位置。
   * 返回 -1 表示定位失败(章节已不存在)。
   */
  static resolveChapterIndex(book: Book, chapterId: string, chapterTitle?: string): number {
    if (!book || !book.chapters || book.chapters.length === 0) return -1;
    const byId = chapterId ? book.chapters.findIndex((c: Chapter) => c.id === chapterId) : -1;
    if (byId >= 0 && (!chapterTitle || book.chapters[byId].title === chapterTitle)) return byId;
    // 只有唯一标题才能纠正目录重排，不能把第一条重名章节当成目标。
    if (chapterTitle) {
      let byTitle: number = -1;
      for (let i = 0; i < book.chapters.length; i++) {
        if (book.chapters[i].title !== chapterTitle) continue;
        if (byTitle >= 0) return byId;
        byTitle = i;
      }
      if (byTitle >= 0) return byTitle;
    }
    return byId;
  }
}
