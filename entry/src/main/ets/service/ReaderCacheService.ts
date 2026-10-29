import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { emitter } from '@kit.BasicServicesKit';
import { PerformanceTrace } from '../utils/PerformanceTrace';

export enum ReaderCacheKind { Text, Comic }

export class ReaderCacheUsage {
  textBytes: number = 0;
  comicBytes: number = 0;
}

export class ReaderCacheCleanup {
  releasedBytes: number = 0;
  removed: number = 0;
  protectedCount: number = 0;
  failed: number = 0;
}

class ReaderCacheEntry {
  path: string = '';
  bytes: number = 0;
  usedAt: number = 0;
}

/** Shared by the TypeScript source bridge and ArkTS readers. Only disposable directories are admitted. */
export class ReaderCacheService {
  static readonly TEXT_LIMIT: number = 1024 * 1024 * 1024;
  static readonly COMIC_LIMIT: number = 5 * 1024 * 1024 * 1024;
  private static context: common.Context | null = null;
  private static entries: Map<string, ReaderCacheEntry> = new Map();
  private static owners: Map<string, Set<string>> = new Map();
  private static holds: Map<string, number> = new Map();
  private static chain: Promise<void> = Promise.resolve();
  private static initialized: boolean = false;
  private static comicWriters: number = 0;
  private static timer: number = -1;
  private static sequence: number = 0;
  private static textBytes: number = 0;
  private static comicBytes: number = 0;
  private static readonly SCAN_CONCURRENCY: number = 4;

  static owner(): string { return `reader-cache-${++ReaderCacheService.sequence}`; }

  static configure(context: common.Context): void {
    ReaderCacheService.context = context;
  }

  static reconcile(): void { ReaderCacheService.initialized = false; ReaderCacheService.scheduleTrim(); }

  static async initialize(context: common.Context): Promise<void> {
    ReaderCacheService.configure(context);
    await ReaderCacheService.enqueue(async (): Promise<void> => {
      await ReaderCacheService.ensureIndex();
      await ReaderCacheService.trim(ReaderCacheKind.Text, false);
      await ReaderCacheService.trim(ReaderCacheKind.Comic, false);
    });
  }

  static protect(owner: string, paths: string[]): void {
    const safe = new Set<string>();
    for (const raw of paths) {
      const path = ReaderCacheService.localPath(raw);
      if (ReaderCacheService.kind(path) !== undefined) safe.add(path);
    }
    ReaderCacheService.owners.set(owner, safe);
  }

  static release(owner: string): void {
    ReaderCacheService.owners.delete(owner);
    ReaderCacheService.scheduleTrim();
  }

  static hold(raw: string): void {
    const path = ReaderCacheService.localPath(raw);
    if (ReaderCacheService.kind(path) === undefined) return;
    ReaderCacheService.holds.set(path, (ReaderCacheService.holds.get(path) ?? 0) + 1);
  }

  static unhold(raw: string): void {
    const path = ReaderCacheService.localPath(raw);
    const count = ReaderCacheService.holds.get(path) ?? 0;
    if (count <= 1) ReaderCacheService.holds.delete(path);
    else ReaderCacheService.holds.set(path, count - 1);
    ReaderCacheService.scheduleTrim();
  }

  // Upstream image transport owns its writes. Do not unlink partial or not-yet-published images.
  static beginComicWrite(): void { ReaderCacheService.comicWriters++; }
  static endComicWrite(): void {
    ReaderCacheService.comicWriters = Math.max(0, ReaderCacheService.comicWriters - 1);
    ReaderCacheService.scheduleTrim();
  }

  static async record(paths: string[]): Promise<void> {
    await ReaderCacheService.enqueue(async (): Promise<void> => {
      await ReaderCacheService.ensureIndex();
      for (const raw of paths) {
        const path = ReaderCacheService.localPath(raw);
        if (ReaderCacheService.kind(path) === undefined) continue;
        try {
          const stat = await fileIo.stat(path);
          if (!stat.isFile()) continue;
          const entry = new ReaderCacheEntry();
          entry.path = path;
          entry.bytes = stat.size;
          entry.usedAt = Date.now();
          ReaderCacheService.forget(path);
          ReaderCacheService.entries.set(path, entry);
          if (ReaderCacheService.kind(path) === ReaderCacheKind.Text) ReaderCacheService.textBytes += entry.bytes;
          else ReaderCacheService.comicBytes += entry.bytes;
          // Persist recency across process restarts; this API takes milliseconds.
          if (entry.usedAt - stat.mtime * 1000 >= 60000) {
            try { fileIo.utimes(path, entry.usedAt); } catch (_error) { /* In-memory recency remains valid. */ }
          }
        } catch (_error) { ReaderCacheService.forget(path); }
      }
    });
    ReaderCacheService.scheduleTrim();
  }

  static forget(path: string): void {
    const previous = ReaderCacheService.entries.get(path);
    if (!previous) return;
    if (ReaderCacheService.kind(path) === ReaderCacheKind.Text) ReaderCacheService.textBytes -= previous.bytes;
    else ReaderCacheService.comicBytes -= previous.bytes;
    ReaderCacheService.entries.delete(path);
  }

  static async usage(): Promise<ReaderCacheUsage> {
    const usage = new ReaderCacheUsage();
    await ReaderCacheService.enqueue(async (): Promise<void> => {
      await ReaderCacheService.scan();
      for (const entry of ReaderCacheService.entries.values()) {
        if (ReaderCacheService.kind(entry.path) === ReaderCacheKind.Text) usage.textBytes += entry.bytes;
        else usage.comicBytes += entry.bytes;
      }
    });
    return usage;
  }

  static async clear(kind: ReaderCacheKind): Promise<ReaderCacheCleanup> {
    let result = new ReaderCacheCleanup();
    await ReaderCacheService.enqueue(async (): Promise<void> => {
      await ReaderCacheService.scan();
      result = await ReaderCacheService.trim(kind, true);
    });
    return result;
  }

  private static enqueue(action: () => Promise<void>): Promise<void> {
    const task = ReaderCacheService.chain.then(action);
    ReaderCacheService.chain = task.catch((): void => {});
    return task;
  }

  private static scheduleTrim(): void {
    if (!ReaderCacheService.context || ReaderCacheService.timer !== -1) return;
    // One deferred sweep for a burst of reads/writes, not one filesystem scan per image.
    ReaderCacheService.timer = setTimeout((): void => {
      ReaderCacheService.timer = -1;
      ReaderCacheService.enqueue(async (): Promise<void> => {
        await ReaderCacheService.ensureIndex();
        await ReaderCacheService.trim(ReaderCacheKind.Text, false);
        await ReaderCacheService.trim(ReaderCacheKind.Comic, false);
      }).catch((): void => {});
    }, 1000);
  }

  private static async ensureIndex(): Promise<void> {
    if (!ReaderCacheService.initialized) await ReaderCacheService.scan();
  }

  private static async scan(): Promise<void> {
    const trace = PerformanceTrace.begin('reader.cache.scan');
    try {
      await ReaderCacheService.scanIndex();
    } finally {
      PerformanceTrace.end('reader.cache.scan', trace);
    }
  }

  private static async scanIndex(): Promise<void> {
    const context = ReaderCacheService.context;
    if (!context) return;
    const next = new Map<string, ReaderCacheEntry>();
    const roots = [`${context.filesDir}/online_text_content`, `${context.cacheDir}/comic_images`,
      `${context.cacheDir}/comic_super_resolution_v1`, `${context.cacheDir}/comic_colorization_v1`];
    for (const root of roots) {
      let names: string[];
      try { names = await fileIo.listFile(root); } catch (_error) { continue; }
      // 只保留四个在途 stat，避免大缓存逐文件串行等待或创建全量 Promise。
      let cursor = 0;
      const scanNext = async (): Promise<void> => {
        while (cursor < names.length) {
          const path = `${root}/${names[cursor++]}`;
          if (ReaderCacheService.kind(path) === undefined) continue;
          try {
            const stat = await fileIo.stat(path);
            if (!stat.isFile()) continue;
            const entry = new ReaderCacheEntry();
            entry.path = path;
            entry.bytes = stat.size;
            entry.usedAt = ReaderCacheService.entries.get(path)?.usedAt ?? stat.mtime * 1000;
            next.set(path, entry);
          } catch (_error) { /* Concurrent cache deletion is a cache miss. */ }
        }
      };
      const workers: Promise<void>[] = [];
      for (let worker = 0; worker < Math.min(ReaderCacheService.SCAN_CONCURRENCY, names.length); worker++) {
        workers.push(scanNext());
      }
      await Promise.all(workers);
    }
    ReaderCacheService.entries = next;
    ReaderCacheService.textBytes = 0;
    ReaderCacheService.comicBytes = 0;
    for (const entry of next.values()) {
      if (ReaderCacheService.kind(entry.path) === ReaderCacheKind.Text) ReaderCacheService.textBytes += entry.bytes;
      else ReaderCacheService.comicBytes += entry.bytes;
    }
    ReaderCacheService.initialized = true;
  }

  private static localPath(raw: string): string {
    try { return raw.startsWith('file://') ? new fileUri.FileUri(raw).path : raw; }
    catch (_error) { return ''; }
  }

  private static kind(path: string): ReaderCacheKind | undefined {
    const context = ReaderCacheService.context;
    if (!context || path.includes('..') || path.includes('\\')) return undefined;
    const textRoot = `${context.filesDir}/online_text_content/`;
    if (path.startsWith(textRoot) && /^search_text_[a-z0-9]+\.json$/.test(path.substring(textRoot.length))) return ReaderCacheKind.Text;
    const engineRoot = `${context.cacheDir}/comic_images/`;
    // 固定 HAR 使用版本号 + SHA256 命名；仅接纳该目录中的完整 JPEG，不接纳 .part。
    if (path.startsWith(engineRoot) && /^color_alac-fp16-v\d+_[a-f0-9]{64}\.jpg$/.test(path.substring(engineRoot.length))) {
      return ReaderCacheKind.Comic;
    }
    for (const root of [`${context.cacheDir}/comic_images/`, `${context.cacheDir}/comic_super_resolution_v1/`,
      `${context.cacheDir}/comic_colorization_v1/`]) {
      if (path.startsWith(root) && /^[a-f0-9]+\.(jpg|jpeg|png|webp|gif|bmp|avif)$/.test(path.substring(root.length))) return ReaderCacheKind.Comic;
    }
    return undefined;
  }

  private static isProtected(path: string, kind: ReaderCacheKind): boolean {
    if (kind === ReaderCacheKind.Comic && ReaderCacheService.comicWriters > 0) return true;
    if (ReaderCacheService.holds.has(path)) return true;
    for (const paths of ReaderCacheService.owners.values()) if (paths.has(path)) return true;
    return false;
  }

  private static async trim(kind: ReaderCacheKind, clear: boolean): Promise<ReaderCacheCleanup> {
    const result = new ReaderCacheCleanup();
    const limit = kind === ReaderCacheKind.Text ? ReaderCacheService.TEXT_LIMIT : ReaderCacheService.COMIC_LIMIT;
    const knownBytes = kind === ReaderCacheKind.Text ? ReaderCacheService.textBytes : ReaderCacheService.comicBytes;
    // Reads and releases schedule this every second. A cache below its limit needs no full map traversal.
    if (!clear && knownBytes <= limit) return result;
    const entries = Array.from(ReaderCacheService.entries.values()).filter((entry: ReaderCacheEntry): boolean =>
      ReaderCacheService.kind(entry.path) === kind);
    let total = entries.reduce((sum: number, entry: ReaderCacheEntry): number => sum + entry.bytes, 0);
    if (!clear && total <= limit) return result;
    const target = clear ? 0 : Math.floor(limit * 0.9);
    entries.sort((left: ReaderCacheEntry, right: ReaderCacheEntry): number => left.usedAt - right.usedAt);
    for (const entry of entries) {
      if (total <= target) break;
      // Re-check at deletion time: readers can acquire a lease while async stat/unlink yields.
      if (ReaderCacheService.isProtected(entry.path, kind)) { result.protectedCount++; continue; }
      try {
        await fileIo.unlink(entry.path);
        total -= entry.bytes;
        result.releasedBytes += entry.bytes;
        result.removed++;
        ReaderCacheService.forget(entry.path);
      } catch (_error) {
        let exists: boolean = true;
        try { exists = await fileIo.access(entry.path); } catch (_accessError) { /* Report unreadable files as failures. */ }
        if (!exists) {
          total -= entry.bytes;
          ReaderCacheService.forget(entry.path);
        } else result.failed++;
      }
    }
    if (result.removed > 0) emitter.emit('app.chapter.cache.updated', { data: {} });
    return result;
  }
}
