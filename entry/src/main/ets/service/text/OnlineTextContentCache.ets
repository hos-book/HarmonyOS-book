import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageMigrationService } from '../StorageMigrationService';
import { BookIdentity } from '../../utils/BookIdentity';
import { ReaderCacheService, ReaderCacheKind, ReaderCacheCleanup } from '../ReaderCacheService';

class CachedTextChapter {
  version: number = 1;
  key: string = '';
  content: string = '';
}

export class CachedTextBookIdentity {
  bookId: string = '';
  sourceUrl: string = '';
  bookUrl: string = '';
}

/** 正文按章节落盘，不随进程退出丢失；损坏或缺失时由调用方重新获取。 */
export class OnlineTextContentCache {
  private static writeChain: Promise<void> = Promise.resolve();
  private static readonly MAX_FILE_BYTES: number = 8 * 1024 * 1024;

  private static migrations: Map<string, Promise<void>> = new Map();

  static migrateStorage(context: common.Context): Promise<void> {
    ReaderCacheService.configure(context);
    const existing = OnlineTextContentCache.migrations.get(context.filesDir);
    if (existing !== undefined) return existing;
    const task = StorageMigrationService.migrateDirectory(
      `${context.cacheDir}/online_text_content`, `${context.filesDir}/online_text_content`, true)
      .catch((error: Error): void => {
        OnlineTextContentCache.migrations.delete(context.filesDir);
        throw error;
      });
    OnlineTextContentCache.migrations.set(context.filesDir, task);
    return task;
  }

  static key(sourceUrl: string, bookUrl: string, chapterUrl: string): string {
    return JSON.stringify([sourceUrl, bookUrl, chapterUrl]);
  }

  private static path(context: common.Context, key: string): string {
    return `${context.filesDir}/online_text_content/${BookIdentity.onlineTextBookId(key, '')}.json`;
  }

  static protect(context: common.Context, owner: string, keys: string[]): void {
    ReaderCacheService.configure(context);
    ReaderCacheService.protect(owner, keys.map((key: string): string => OnlineTextContentCache.path(context, key)));
  }

  static async clear(context: common.Context): Promise<ReaderCacheCleanup> {
    let result = new ReaderCacheCleanup();
    const task = OnlineTextContentCache.writeChain.then(async (): Promise<void> => {
      await OnlineTextContentCache.migrateStorage(context);
      result = await ReaderCacheService.clear(ReaderCacheKind.Text);
    });
    OnlineTextContentCache.writeChain = task.catch((): void => {});
    await task;
    return result;
  }

  static async contains(context: common.Context, key: string): Promise<boolean> {
    await OnlineTextContentCache.migrateStorage(context);
    try {
      const stat = await fileIo.stat(OnlineTextContentCache.path(context, key));
      return stat.size > 0 && stat.size <= OnlineTextContentCache.MAX_FILE_BYTES;
    } catch (_e) { return false; }
  }

  static async read(context: common.Context, key: string): Promise<string | undefined> {
    await OnlineTextContentCache.migrateStorage(context);
    const path = OnlineTextContentCache.path(context, key);
    ReaderCacheService.hold(path);
    try {
      const stat = await fileIo.stat(path);
      if (stat.size <= 0 || stat.size > OnlineTextContentCache.MAX_FILE_BYTES) return undefined;
      const record: CachedTextChapter = JSON.parse(await fileIo.readText(path));
      // 校验完整身份，哈希碰撞也不能返回另一本书/另一个来源的正文。
      if (record !== null && record.version === 1 && record.key === key &&
        typeof record.content === 'string' && record.content.trim().length > 0) {
        await ReaderCacheService.record([path]);
        return record.content;
      }
    } catch (_e) { /* 缺失、损坏或读取失败均回退在线获取 */ }
    finally { ReaderCacheService.unhold(path); }
    return undefined;
  }

  /** 旧进度只有 bookId，从正文的完整身份恢复地址；只扫描一次且限制总读取量。 */
  static async recoverBookIdentities(context: common.Context,
    bookIds: string[]): Promise<CachedTextBookIdentity[]> {
    await OnlineTextContentCache.migrateStorage(context);
    const wanted = new Set<string>(bookIds);
    const found = new Map<string, CachedTextBookIdentity>();
    const ambiguous = new Set<string>();
    if (wanted.size === 0) return [];
    const directory = `${context.filesDir}/online_text_content`;
    let names: string[];
    try { names = await fileIo.listFile(directory); } catch (_e) { return []; }
    let bytesRead = 0;
    for (const name of names.slice(0, 10000)) {
      if (!/^search_text_[a-z0-9]+\.json$/.test(name)) continue;
      try {
        const path = `${directory}/${name}`;
        const stat = await fileIo.stat(path);
        if (stat.size <= 0 || stat.size > OnlineTextContentCache.MAX_FILE_BYTES) continue;
        bytesRead += stat.size;
        if (bytesRead > 64 * 1024 * 1024) break;
        const record: CachedTextChapter = JSON.parse(await fileIo.readText(path));
        if (!record || record.version !== 1 || typeof record.key !== 'string') continue;
        if (`${BookIdentity.onlineTextBookId(record.key, '')}.json` !== name) continue;
        const parts: string[] = JSON.parse(record.key);
        if (!Array.isArray(parts) || parts.length !== 3 ||
          typeof parts[0] !== 'string' || typeof parts[1] !== 'string' ||
          !parts[0] || !parts[1]) continue;
        const id = BookIdentity.onlineTextBookId(parts[0], parts[1]);
        if (!wanted.has(id) || ambiguous.has(id)) continue;
        const previous = found.get(id);
        if (previous && (previous.sourceUrl !== parts[0] || previous.bookUrl !== parts[1])) {
          found.delete(id);
          ambiguous.add(id);
          continue;
        }
        const identity = new CachedTextBookIdentity();
        identity.bookId = id;
        identity.sourceUrl = parts[0];
        identity.bookUrl = parts[1];
        found.set(id, identity);
      } catch (_e) { /* 单个坏缓存不能影响其余记录 */ }
    }
    return Array.from(found.values());
  }

  static write(context: common.Context, key: string, content: string): Promise<void> {
    if (content.trim().length === 0) return Promise.resolve();
    const record = new CachedTextChapter();
    record.key = key;
    record.content = content;
    const bytes = buffer.from(JSON.stringify(record), 'utf-8').buffer;
    if (bytes.byteLength > OnlineTextContentCache.MAX_FILE_BYTES) return Promise.resolve();
    const task = OnlineTextContentCache.writeChain.then(async (): Promise<void> => {
      await OnlineTextContentCache.migrateStorage(context);
      const dir = `${context.filesDir}/online_text_content`;
      try { await fileIo.mkdir(dir); } catch (_e) { /* 已存在 */ }
      const path = OnlineTextContentCache.path(context, key);
      ReaderCacheService.hold(path);
      const temp = path + '.tmp';
      let file: fileIo.File | null = null;
      try {
        file = await fileIo.open(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE |
          fileIo.OpenMode.TRUNC);
        let offset = 0;
        while (offset < bytes.byteLength) {
          const written = await fileIo.write(file.fd, bytes.slice(offset));
          if (written <= 0) throw new Error('正文缓存写入未完成');
          offset += written;
        }
        await fileIo.fsync(file.fd);
        await fileIo.close(file);
        file = null;
        await fileIo.moveFile(temp, path);
        await ReaderCacheService.record([path]);
      } finally {
        if (file !== null) {
          try { await fileIo.close(file); } catch (_e) { /* ignore */ }
        }
        try { await fileIo.unlink(temp); } catch (_e) { /* 已移动或未创建 */ }
        ReaderCacheService.unhold(path);
      }
    }).catch((): void => {
      hilog.warn(0x0000, 'OnlineTextContentCache', 'chapter cache write failed');
    });
    OnlineTextContentCache.writeChain = task;
    return task;
  }

  static async removeChapter(context: common.Context, key: string): Promise<void> {
    const task = OnlineTextContentCache.writeChain.then(async (): Promise<void> => {
      await OnlineTextContentCache.migrateStorage(context);
      try { await fileIo.unlink(OnlineTextContentCache.path(context, key)); } catch (_error) { /* cache miss */ }
      ReaderCacheService.forget(OnlineTextContentCache.path(context, key));
    });
    OnlineTextContentCache.writeChain = task.catch((): void => {});
    await task;
  }

  static async invalidateSources(context: common.Context, sourceUrls: Set<string>,
    protectedBooks: Set<string> = new Set()): Promise<void> {
    await OnlineTextContentCache.removeMatching(context, sourceUrls, undefined, protectedBooks);
  }

  static async removeBook(context: common.Context, sourceUrl: string, bookUrl: string): Promise<void> {
    if (!sourceUrl || !bookUrl) return;
    await OnlineTextContentCache.removeMatching(context, new Set<string>([sourceUrl]), bookUrl);
  }

  private static async removeMatching(context: common.Context, sourceUrls: Set<string>,
    bookUrl?: string, protectedBooks: Set<string> = new Set()): Promise<void> {
    const task = OnlineTextContentCache.writeChain.then(async (): Promise<void> => {
      await OnlineTextContentCache.migrateStorage(context);
      const directory = `${context.filesDir}/online_text_content`;
      let names: string[];
      try { names = await fileIo.listFile(directory); } catch (_e) { return; }
      for (const name of names) {
        if (!/^search_text_[a-z0-9]+\.json$/.test(name)) continue;
        const path = `${directory}/${name}`;
        const stat = await fileIo.stat(path);
        if (stat.size <= 0 || stat.size > OnlineTextContentCache.MAX_FILE_BYTES) continue;
        let parts: string[];
        try {
          const record: CachedTextChapter = JSON.parse(await fileIo.readText(path));
          parts = JSON.parse(record.key);
        } catch (_e) { continue; }
        if (Array.isArray(parts) && !protectedBooks.has(OnlineTextContentCache.key(parts[0], parts[1], '')) &&
          sourceUrls.has(parts[0]) &&
            (bookUrl === undefined || parts[1] === bookUrl)) {
          await fileIo.unlink(path);
          ReaderCacheService.forget(path);
        }
      }
    });
    OnlineTextContentCache.writeChain = task.catch((): void => {});
    await task;
  }
}
