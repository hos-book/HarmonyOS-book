import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { Book, Chapter } from '../model/Book';
import { DownloadBookDerivedStatus, DownloadChapterDerivedStatus, DownloadFailureCode,
  DownloadFileProbeResult, DownloadPolicy } from './DownloadPolicy';
import { StorageMigrationService } from './StorageMigrationService';

export type DownloadBookStatus = DownloadBookDerivedStatus;
export type DownloadChapterStatus = DownloadChapterDerivedStatus;

export interface DownloadChapterRecord {
  chapterId: string;
  chapterIndex: number;
  title: string;
  durationSec?: number;
  pageUrl: string;
  audioUrl: string;
  filePath: string;
  bytes: number;
  status: DownloadChapterStatus;
  failureReason: string;
  failureCode?: DownloadFailureCode;
  updatedAt: number;
  variables?: Record<string, string>;
}

export interface DownloadBookRecord {
  bookId: string;
  title: string;
  author: string;
  cover: string;
  sourceUrl: string;
  bookUrl: string;
  contentType: string;
  chapterCount: number;
  downloadedCount: number;
  failedCount: number;
  totalBytes: number;
  status: DownloadBookStatus;
  updatedAt: number;
  chapters: DownloadChapterRecord[];
  variables?: Record<string, string>;
  /** 网络策略暂停可自动恢复，用户主动暂停仍保持暂停。 */
  waitingForWifi?: boolean;
}

interface DownloadStoreRead {
  ok: boolean;
  existed: boolean;
  json: string;
}

export class DownloadChapterIndex {
  private chapters: DownloadChapterRecord[];
  private positions: Map<string, number[]> = new Map();

  constructor(chapters: DownloadChapterRecord[]) {
    this.chapters = chapters;
    for (let position = 0; position < chapters.length; position++) this.update(position);
  }

  find(chapterId: string, pageUrl: string): number {
    const url = pageUrl.trim();
    if (!url) return this.positions.get(`id:${chapterId}`)?.[0] ?? -1;
    const byUrl = this.positions.get(`url:${url}`)?.[0] ?? -1;
    const byId = this.positions.get(`empty:${chapterId}`)?.[0] ?? -1;
    return byUrl < 0 ? byId : byId < 0 ? byUrl : Math.min(byUrl, byId);
  }

  update(position: number, previousId?: string, previousUrl?: string): void {
    const chapter = this.chapters[position];
    const keys = this.keys(chapter.chapterId, chapter.pageUrl);
    const previous: string[] = previousId === undefined ? [] : this.keys(previousId, previousUrl ?? '');
    for (const key of previous) {
      if (keys.includes(key)) continue;
      const positions = this.positions.get(key);
      if (positions) {
        positions.splice(positions.indexOf(position), 1);
        if (positions.length === 0) this.positions.delete(key);
      }
    }
    for (const key of keys) {
      if (previous.includes(key)) continue;
      let positions = this.positions.get(key);
      if (positions === undefined) {
        positions = [];
        this.positions.set(key, positions);
      }
      let insert = positions.length;
      while (insert > 0 && positions[insert - 1] > position) insert--;
      positions.splice(insert, 0, position);
    }
  }

  private keys(chapterId: string, pageUrl: string): string[] {
    const url = (pageUrl || '').trim();
    return [`id:${chapterId}`, url ? `url:${url}` : `empty:${chapterId}`];
  }
}

export class DownloadBookProgress {
  totalCount: number = 0;
  chaptersByTask: Map<string, number[]> = new Map();
}

const DOWNLOAD_ROOT_DIR = 'downloads';
const DOWNLOAD_AUDIO_DIR = 'audio';
const DOWNLOAD_STORE_FILE = 'download_store.json';

export class DownloadStore {
  private static ctx: common.Context | null = null;
  private static records: DownloadBookRecord[] | null = null;
  private static progressByBook: Map<string, DownloadBookProgress> = new Map();
  private static writeChain: Promise<void> = Promise.resolve();
  private static persistUnsafe: boolean = false;
  private static migrationPromise: Promise<void> | null = null;

  /**
   * 启动轻量初始化：只建目录 + 读 JSON。
   * 完整文件校验（stat 每个 completed 章节）放到 normalizeInterruptedTasks，
   * 必须延后到首帧之后，否则章节一多会主线程卡死触发 AppFreeze。
   */
  static async init(ctx: common.Context): Promise<void> {
    DownloadStore.setContext(ctx);
    await DownloadStore.ensureStorageMigrated();
    await DownloadStore.ensureBaseDirs();
    await DownloadStore.ensureLoaded();
  }

  /** 冷启动后异步执行：校验已下载文件、复位中断任务。可安全重复调用。 */
  static async normalizeInterruptedTasks(): Promise<void> {
    await DownloadStore.ensureLoaded();
    let changed = false;
    let probeCount = 0;
    const list = DownloadStore.records ?? [];
    for (const book of list) {
      const shouldResume = book.status === 'downloading' || book.status === 'queued';
      for (const chapter of book.chapters) {
        if (chapter.status === 'completed') {
          const probe = DownloadStore.probeCompletedFile(chapter.filePath, chapter.bytes);
          probeCount++;
          // 每扫一批就让出主线程，避免启动/恢复阶段 AppFreeze
          if (probeCount % 20 === 0) {
            await DownloadStore.yieldToMain();
          }
          if (probe === 'ok' || probe === 'stat_error') {
            // stat 暂时失败时保留 completed，避免冷启动误删整批已下载文件
            continue;
          }
          if (probe === 'size_mismatch' || probe === 'too_small' || probe === 'missing') {
            await DownloadStore.deleteFileSafely(chapter.filePath);
            chapter.status = 'failed';
            chapter.failureCode = 'invalid_response';
            chapter.failureReason = probe === 'missing'
              ? '已下载文件缺失'
              : (probe === 'size_mismatch'
                ? '已下载文件不完整（大小与记录不符）'
                : '已下载文件过小或不完整');
            chapter.bytes = 0;
            chapter.filePath = '';
            changed = true;
          }
        }
        if (chapter.status === 'resolving' || chapter.status === 'downloading') {
          chapter.status = 'pending';
          changed = true;
        }
      }
      const statusBeforeRecalculate = book.status;
      DownloadStore.recalculateBook(book);
      if (book.status !== statusBeforeRecalculate) changed = true;
      if (shouldResume
        && book.chapters.some((chapter: DownloadChapterRecord) => chapter.status === 'pending')) {
        if (book.status !== 'queued') changed = true;
        book.status = 'queued';
      }
      // 每本书之间也让出一次，防止单书章节极多时长时间占满事件循环
      await DownloadStore.yieldToMain();
    }
    if (changed) await DownloadStore.saveAll();
  }

  private static async yieldToMain(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 0);
    });
  }

  static setContext(ctx: common.Context): void {
    DownloadStore.ctx = ctx;
    if (DownloadStore.migrationPromise === null) {
      DownloadStore.migrationPromise = DownloadStore.migrateLegacyStorage();
    }
  }

  static getDownloadRootPath(): string | null {
    return DownloadStore.ctx ? `${DownloadStore.ctx.filesDir}/${DOWNLOAD_ROOT_DIR}` : null;
  }

  static getCacheDownloadRootPath(): string | null {
    return DownloadStore.ctx ? `${DownloadStore.ctx.cacheDir}/${DOWNLOAD_ROOT_DIR}` : null;
  }

  static getAudioRootPath(): string | null {
    const root = DownloadStore.getDownloadRootPath();
    return root ? `${root}/${DOWNLOAD_AUDIO_DIR}` : null;
  }

  static getBookDir(bookId: string): string | null {
    const root = DownloadStore.getAudioRootPath();
    if (!root || !bookId) return null;
    return `${root}/${DownloadStore.hash(bookId)}`;
  }

  static getAudioFilePath(bookId: string, pageUrl: string): string | null {
    const dir = DownloadStore.getBookDir(bookId);
    if (!dir || !pageUrl) return null;
    return `${dir}/${DownloadStore.hash(`${bookId}|${pageUrl}`)}.mp3`;
  }

  static async ensureBookDir(bookId: string): Promise<string | null> {
    await DownloadStore.ensureBaseDirs();
    const dir = DownloadStore.getBookDir(bookId);
    if (!dir) return null;
    await DownloadStore.ensureDir(dir);
    return dir;
  }

  static async getBooks(): Promise<DownloadBookRecord[]> {
    await DownloadStore.ensureLoaded();
    return DownloadStore.records ?? [];
  }

  static getBooksSync(): DownloadBookRecord[] {
    return DownloadStore.records ?? [];
  }

  static async getBook(bookId: string): Promise<DownloadBookRecord | null> {
    await DownloadStore.ensureLoaded();
    return DownloadStore.getBookSync(bookId);
  }

  static getBookSync(bookId: string): DownloadBookRecord | null {
    const list = DownloadStore.records ?? [];
    return list.find((item: DownloadBookRecord) => item.bookId === bookId) ?? null;
  }

  static getChapterSync(bookId: string, chapter: Chapter): DownloadChapterRecord | null {
    const book = DownloadStore.getBookSync(bookId);
    if (!book) return null;
    return DownloadStore.findChapterRecord(book, chapter);
  }

  static findChapterRecord(book: DownloadBookRecord, chapter: Chapter): DownloadChapterRecord | null {
    const pageUrl = DownloadPolicy.stablePageUrl(chapter);
    return book.chapters.find((item: DownloadChapterRecord) => DownloadPolicy.matchesChapter(
      item.chapterId, item.pageUrl, chapter.id, pageUrl)) ?? null;
  }

  static async ensureBookRecord(book: Book): Promise<DownloadBookRecord> {
    await DownloadStore.ensureLoaded();
    const record = DownloadStore.ensureBookRecordInMemory(book);
    DownloadStore.recalculateBook(record);
    await DownloadStore.saveAll();
    return record;
  }

  static async prepareChapters(book: Book, chapters: Chapter[], canApply?: () => boolean):
    Promise<DownloadChapterRecord[]> {
    await DownloadStore.ensureLoaded();
    if (canApply && !canApply()) return [];
    const bookRecord = DownloadStore.ensureBookRecordInMemory(book);
    const prepared: DownloadChapterRecord[] = [];
    const index = new DownloadChapterIndex(bookRecord.chapters);
    for (const chapter of chapters) {
      prepared.push(DownloadStore.upsertChapterInMemory(bookRecord, chapter, 'pending', '', '', 0, '', 'unknown', index));
    }
    DownloadStore.recalculateBook(bookRecord);
    if (prepared.length > 0) bookRecord.status = 'queued';
    bookRecord.updatedAt = Date.now();
    await DownloadStore.saveAll();
    return prepared;
  }

  private static ensureBookRecordInMemory(book: Book): DownloadBookRecord {
    const list = DownloadStore.records ?? [];
    let record = list.find((item: DownloadBookRecord) => item.bookId === book.id);
    if (!record) {
      record = {
        bookId: book.id,
        title: book.title,
        author: book.author,
        cover: book.cover,
        sourceUrl: book.sourceUrl,
        bookUrl: book.bookUrl,
        contentType: book.contentType ?? '',
        chapterCount: book.chapters.length || book.chapterCount || 0,
        downloadedCount: 0,
        failedCount: 0,
        totalBytes: 0,
        status: 'idle',
        updatedAt: Date.now(),
        chapters: [],
        variables: book.variables
      };
      list.push(record);
      DownloadStore.records = list;
    } else {
      record.title = book.title || record.title;
      record.author = book.author || record.author;
      record.cover = book.cover || record.cover;
      record.sourceUrl = book.sourceUrl || record.sourceUrl;
      record.bookUrl = book.bookUrl || record.bookUrl;
      record.contentType = book.contentType ?? record.contentType;
      record.chapterCount = book.chapters.length || book.chapterCount || record.chapterCount;
      record.updatedAt = Date.now();
    }
    return record;
  }

  static async upsertChapter(book: Book, chapter: Chapter, status: DownloadChapterStatus,
    audioUrl: string = '', filePath: string = '', bytes: number = 0, failureReason: string = '',
    canApply?: () => boolean, failureCode: DownloadFailureCode = 'unknown'): Promise<DownloadChapterRecord | null> {
    await DownloadStore.ensureLoaded();
    if (canApply && !canApply()) return null;
    const bookRecord = DownloadStore.ensureBookRecordInMemory(book);
    const record = DownloadStore.upsertChapterInMemory(bookRecord, chapter, status,
      audioUrl, filePath, bytes, failureReason, failureCode);
    bookRecord.updatedAt = Date.now();
    DownloadStore.recalculateBook(bookRecord);
    await DownloadStore.saveAll();
    return record;
  }

  private static upsertChapterInMemory(bookRecord: DownloadBookRecord, chapter: Chapter,
    status: DownloadChapterStatus, audioUrl: string = '', filePath: string = '', bytes: number = 0,
    failureReason: string = '', failureCode: DownloadFailureCode = 'unknown',
    index?: DownloadChapterIndex): DownloadChapterRecord {
    const pageUrl = DownloadPolicy.stablePageUrl(chapter);
    let position = index ? index.find(chapter.id, pageUrl) : bookRecord.chapters.findIndex(
      (item: DownloadChapterRecord): boolean => DownloadPolicy.matchesChapter(item.chapterId, item.pageUrl, chapter.id, pageUrl));
    let record = bookRecord.chapters[position];
    const previousId = record?.chapterId;
    const previousUrl = record?.pageUrl;
    if (!record) {
      record = {
        chapterId: chapter.id,
        chapterIndex: chapter.index,
        title: chapter.title,
        durationSec: chapter.duration > 0 ? chapter.duration : undefined,
        pageUrl,
        audioUrl,
        filePath,
        bytes,
        status,
        failureReason,
        failureCode: status === 'failed' ? failureCode : undefined,
        updatedAt: Date.now(),
        variables: chapter.variables
      };
      position = bookRecord.chapters.length;
      bookRecord.chapters.push(record);
    } else {
      record.chapterId = chapter.id;
      record.chapterIndex = chapter.index;
      record.title = chapter.title;
      if (chapter.duration > 0) record.durationSec = chapter.duration;
      record.pageUrl = pageUrl || record.pageUrl;
      record.audioUrl = audioUrl || record.audioUrl;
      record.filePath = filePath || record.filePath;
      record.bytes = bytes > 0 ? bytes : record.bytes;
      record.status = status;
      record.failureReason = failureReason;
      record.failureCode = status === 'failed' ? failureCode : undefined;
      record.updatedAt = Date.now();
      record.variables = chapter.variables;
    }
    index?.update(position, previousId, previousUrl);
    return record;
  }

  static async saveBook(record: DownloadBookRecord): Promise<void> {
    await DownloadStore.ensureLoaded();
    DownloadStore.recalculateBook(record);
    record.updatedAt = Date.now();
    await DownloadStore.saveAll();
  }

  static async removeBook(bookId: string): Promise<void> {
    await DownloadStore.ensureLoaded();
    const list = DownloadStore.records ?? [];
    DownloadStore.records = list.filter((item: DownloadBookRecord) => item.bookId !== bookId);
    DownloadStore.progressByBook.delete(bookId);
    await DownloadStore.saveAll();
  }

  static async clearAll(): Promise<void> {
    DownloadStore.records = [];
    DownloadStore.progressByBook.clear();
    DownloadStore.persistUnsafe = false;
    await DownloadStore.saveAll();
  }

  static async deleteFileSafely(path: string): Promise<void> {
    if (!path) return;
    const paths = [path, `${path}.part`, `${path}.swap`];
    for (const current of paths) {
      try {
        await fileIo.unlink(current);
      } catch (_e) {
        // ignore
      }
    }
  }

  static isUsableFile(path: string): boolean {
    if (!path) return false;
    try {
      return fileIo.statSync(path).size > 1024;
    } catch (_e) {
      return false;
    }
  }

  static isExpectedFile(path: string, expectedBytes: number): boolean {
    return DownloadStore.probeCompletedFile(path, expectedBytes) === 'ok';
  }

  /**
   * 探测已完成文件状态：
   * - ok: 可用
   * - missing: 路径空或不存在
   * - size_mismatch: 存在但与记录字节数不一致（常见于写入错误导致只剩最后一块）
   * - too_small: 存在但过小
   * - stat_error: 暂时无法 stat（不要当成损坏去删）
   */
  static probeCompletedFile(path: string, expectedBytes: number): DownloadFileProbeResult {
    if (!path) return 'missing';
    try {
      const size = fileIo.statSync(path).size;
      if (size <= 1024) return 'too_small';
      if (expectedBytes > 0 && size !== expectedBytes) return 'size_mismatch';
      return 'ok';
    } catch (err) {
      const error = err as BusinessError;
      return DownloadPolicy.classifyFileProbeErrorCode(error.code);
    }
  }

  static hash(s: string): string {
    let h = 0;
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) - h + s.charCodeAt(i)) | 0;
    }
    return Math.abs(h).toString(16);
  }

  private static recalculateBook(book: DownloadBookRecord): void {
    let downloaded = 0;
    let failed = 0;
    let totalBytes = 0;
    const progress = new DownloadBookProgress();
    for (let position = 0; position < book.chapters.length; position++) {
      const chapter = book.chapters[position];
      if (chapter.status === 'completed') downloaded++;
      if (chapter.status === 'failed') failed++;
      if (chapter.status === 'completed') totalBytes += chapter.bytes;
      DownloadStore.appendBookProgress(progress, book, position);
    }
    book.downloadedCount = downloaded;
    book.failedCount = failed;
    book.totalBytes = totalBytes;
    DownloadStore.progressByBook.set(book.bookId, progress);
    book.status = DownloadPolicy.deriveBookStatus(book.status,
      book.chapters.map((chapter: DownloadChapterRecord): DownloadChapterDerivedStatus => chapter.status));
  }

  static getBookProgress(book: DownloadBookRecord): DownloadBookProgress {
    let progress = DownloadStore.progressByBook.get(book.bookId);
    if (progress === undefined) {
      progress = DownloadStore.createBookProgress(book);
      DownloadStore.progressByBook.set(book.bookId, progress);
    }
    return progress;
  }

  private static createBookProgress(book: DownloadBookRecord): DownloadBookProgress {
    const progress = new DownloadBookProgress();
    for (let position = 0; position < book.chapters.length; position++) {
      DownloadStore.appendBookProgress(progress, book, position);
    }
    return progress;
  }

  private static appendBookProgress(progress: DownloadBookProgress, book: DownloadBookRecord, position: number): void {
    const chapter = book.chapters[position];
    if (chapter.status === 'deleted') return;
    progress.totalCount++;
    if (chapter.status === 'completed') return;
    const key = DownloadPolicy.taskKey(book.bookId, chapter.pageUrl);
    let positions = progress.chaptersByTask.get(key);
    if (positions === undefined) {
      positions = [];
      progress.chaptersByTask.set(key, positions);
    }
    positions.push(position);
  }

  private static storePath(): string | null {
    const root = DownloadStore.getDownloadRootPath();
    return root ? `${root}/${DOWNLOAD_STORE_FILE}` : null;
  }

  private static async ensureLoaded(): Promise<void> {
    if (DownloadStore.records !== null) return;
    await DownloadStore.ensureStorageMigrated();
    const primaryRead = await DownloadStore.readFileSafe(DownloadStore.storePath());
    let read = primaryRead;
    let usingLegacyFile = false;
    if (!primaryRead.existed || !primaryRead.ok || !primaryRead.json) {
      const legacyRead = await DownloadStore.readFileSafe(DownloadStore.legacyStorePath());
      if (legacyRead.existed && legacyRead.ok && legacyRead.json) {
        read = legacyRead;
        usingLegacyFile = true;
      }
    }
    if (primaryRead.existed && !primaryRead.ok) DownloadStore.persistUnsafe = true;
    if (!read.ok) {
      DownloadStore.persistUnsafe = true;
      DownloadStore.records = [];
      return;
    }
    if (!read.existed || !read.json) {
      DownloadStore.records = [];
      return;
    }
    try {
      const parsed: Object = JSON.parse(read.json) as Object;
      DownloadStore.records = Array.isArray(parsed) ? parsed as DownloadBookRecord[] : [];
    } catch (_e) {
      DownloadStore.persistUnsafe = true;
      DownloadStore.records = [];
      return;
    }
    const pathsRebased = await DownloadStore.rebaseLegacyPaths(DownloadStore.records);
    if (pathsRebased || usingLegacyFile) {
      try { await DownloadStore.saveAll(); } catch (_e) {}
    }
  }

  private static async readFileSafe(path: string | null): Promise<DownloadStoreRead> {
    if (!path) return { ok: true, existed: false, json: '' };
    let existed = false;
    try {
      existed = await fileIo.access(path);
    } catch (_e) {
      existed = false;
    }
    if (!existed) return { ok: true, existed: false, json: '' };
    try {
      return { ok: true, existed: true, json: await fileIo.readText(path) };
    } catch (_e) {
      return { ok: false, existed: true, json: '' };
    }
  }

  private static saveAll(): Promise<void> {
    if (DownloadStore.persistUnsafe) return Promise.reject(new Error('下载记录文件不可安全写入'));
    const path = DownloadStore.storePath();
    const json = JSON.stringify(DownloadStore.records ?? []);
    const task = DownloadStore.writeChain.then(() => DownloadStore.atomicWrite(path, json));
    DownloadStore.writeChain = task.catch((_e: Error): void => {});
    return task;
  }

  private static async atomicWrite(finalPath: string | null, json: string): Promise<void> {
    if (!finalPath) return;
    await DownloadStore.ensureBaseDirs();
    const tmp = finalPath + '.tmp';
    let f: fileIo.File | null = null;
    try {
      f = await fileIo.open(tmp, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.write(f.fd, json);
      try { await fileIo.fsync(f.fd); } catch (_e) { /* ignore */ }
    } finally {
      if (f) {
        try { await fileIo.close(f); } catch (_e) { /* ignore */ }
      }
    }
    await fileIo.moveFile(tmp, finalPath);
  }

  private static async ensureBaseDirs(): Promise<void> {
    const root = DownloadStore.getDownloadRootPath();
    const audio = DownloadStore.getAudioRootPath();
    if (root) await DownloadStore.ensureDir(root);
    if (audio) await DownloadStore.ensureDir(audio);
  }

  private static async ensureDir(dir: string): Promise<void> {
    try {
      const ok = await fileIo.access(dir);
      if (ok) return;
    } catch (_e) {
      // mkdir below
    }
    try {
      await fileIo.mkdir(dir);
    } catch (_e) {
      // already exists or unavailable; later file operations will surface real errors
    }
  }

  static getLegacyDownloadRootPath(): string | null {
    return DownloadStore.getCacheDownloadRootPath();
  }

  private static legacyStorePath(): string | null {
    const root = DownloadStore.getCacheDownloadRootPath();
    return root ? `${root}/${DOWNLOAD_STORE_FILE}` : null;
  }

  private static ensureStorageMigrated(): Promise<void> {
    if (DownloadStore.migrationPromise === null) {
      DownloadStore.migrationPromise = DownloadStore.migrateLegacyStorage();
    }
    return DownloadStore.migrationPromise;
  }

  private static async migrateLegacyStorage(): Promise<void> {
    const legacyRoot = DownloadStore.getLegacyDownloadRootPath();
    const cacheRoot = DownloadStore.getDownloadRootPath();
    if (legacyRoot && cacheRoot) {
      await StorageMigrationService.migrateDirectory(legacyRoot, cacheRoot);
    }
  }

  private static async rebaseLegacyPaths(records: DownloadBookRecord[]): Promise<boolean> {
    const legacyRoot = DownloadStore.getLegacyDownloadRootPath();
    const cacheRoot = DownloadStore.getDownloadRootPath();
    if (!legacyRoot || !cacheRoot) return false;
    let changed = false;
    for (const book of records) {
      for (const chapter of book.chapters) {
        const rebased = DownloadPolicy.rebaseStoragePath(chapter.filePath, legacyRoot, cacheRoot);
        if (rebased !== chapter.filePath && await DownloadStore.isMigratedFile(rebased)) {
          chapter.filePath = rebased;
          changed = true;
        }
      }
    }
    return changed;
  }

  private static async isMigratedFile(path: string): Promise<boolean> {
    try {
      const stat = await fileIo.stat(path);
      return !stat.isDirectory() && stat.size > 0;
    } catch (_e) {
      return false;
    }
  }
}
