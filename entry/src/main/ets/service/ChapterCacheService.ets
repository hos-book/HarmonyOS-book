import { ChapterRuleContext } from './rulesource/ChapterRuleContext';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';
import { Book, Chapter } from '../model/Book';
import { BookSource } from '../model/BookSource';
import { AudioRequestInfo, BookSourceService } from './BookSourceService';
import { SourceDataService } from './SourceDataService';
import { DownloadPolicy } from './DownloadPolicy';
import { StorageMigrationService } from './StorageMigrationService';
import { AudioDownloadTransport } from './AudioDownloadTransport';
import { BackgroundTaskService } from './BackgroundTaskService';
import { DiagnosticLogService } from './DiagnosticLogService';
import { LightSourceRequest } from './rulesource/light/LightSourceRequestPolicy';

const DOMAIN = 0x0001;
const TAG = 'ChapterCache';

export const EVT_CHAPTER_DURATION_UPDATED = 'app.chapter.duration.updated';
export const EVT_CHAPTER_CACHE_UPDATED = 'app.chapter.cache.updated';

let PRE_DOWNLOAD_FORWARD = 1;
let PRE_DOWNLOAD_BACKWARD = 0;
const MAX_CONCURRENT = 1; // 按播放距离串行解析并下载，给当前播放保留带宽。
const MAX_URL_CACHE_SIZE = 50;
const AUDIO_URL_TTL_MS = 5 * 60 * 1000;
const MAX_FILE_CACHE_BYTES = 1024 * 1024 * 1024; // 章节临时音频缓存上限 1GB
const PRELOAD_FAILURE_COOLDOWN_MS = 30000;
const PRELOAD_RESOLVE_TIMEOUT_MS = 15000;

class PendingAudioResolve {
  request: LightSourceRequest = new LightSourceRequest(0);
  bookId: string = '';
  sourceUrl: string = '';
  chapter: Chapter;
  clearGen: number = 0;
  preloadGen: number = 0;
  promise: Promise<void> = Promise.resolve();

  constructor(chapter: Chapter) {
    this.chapter = chapter;
  }
}

class ClearCacheResult {
  deleted: number = 0;
  failed: number = 0;
  releasedBytes: number = 0;
  protectedCount: number = 0;
}

interface CacheEntry {
  resolvedUrl: string;
  headers: Record<string, string>;
  timestamp: number;
}

interface FileCacheEntry {
  /** 沙箱内的绝对路径 */
  filePath: string;
  /** 对应章节页 URL（书源解析的入口）— 用于命中校验 */
  pageUrl: string;
  bytes: number;
  timestamp: number;
}

interface DiskCacheEntry {
  filePath: string;
  bytes: number;
  timestamp: number;
}

export class ChapterCacheService {
  static readonly CACHE_LIMIT: number = MAX_FILE_CACHE_BYTES;
  private static instance: ChapterCacheService | null = null;
  private audioCache: Map<string, CacheEntry> = new Map();
  /** 章节 → 已下载到本地的音频文件 */
  private fileCache: Map<string, FileCacheEntry> = new Map();
  /** 章节 → 解析出的真实时长（秒）。来自缓存音频文件的元数据 */
  private durationCache: Map<string, number> = new Map();
  private pendingTasks: Set<string> = new Set();
  private runningTaskGenerations: Map<string, number> = new Map();
  private invalidatedResolves: Set<string> = new Set();
  private audioResolves: Map<string, PendingAudioResolve> = new Map();
  private preloadFailureAt: Map<string, number> = new Map();
  private runningCount: number = 0;
  private queue: Map<string, () => Promise<void>> = new Map();
  private appContext: common.UIAbilityContext | null = null;
  private transferHeld: boolean = false;
  private storageMigration: Promise<void> = Promise.resolve();
  private storageReady: boolean = true;
  private clearGen: number = 0;
  private preloadSuspended: boolean = false;
  private activeDownloads: Map<string, AudioDownloadTransport> = new Map();
  private fileTasks: Map<string, Promise<void>> = new Map();
  private priorityChapterId: string = '';
  private preloadGen: number = 0;
  private playingFilePath: string = '';
  private activeFilePaths: Set<string> = new Set();
  private diskCleanupTask: Promise<void> | null = null;
  private diskCleanupRequested: boolean = false;
  private cacheCleanupTask: Promise<ClearCacheResult> | null = null;

  setPlayingFile(filePath: string = ''): void {
    this.playingFilePath = filePath;
  }

  suspendPreload(keepChapterId: string = ''): void {
    this.preloadSuspended = true;
    this.priorityChapterId = keepChapterId;
    this.queue.clear();
    this.preloadGen++;
    if (!keepChapterId) this.clearGen++;
    for (const task of this.audioResolves.values()) {
      if (task.chapter.id === keepChapterId) task.request.promote();
      else task.request.cancel();
    }
    for (const id of this.activeDownloads.keys()) {
      if (id !== keepChapterId) {
        this.activeDownloads.get(id)?.cancel();
        this.activeDownloads.delete(id);
      }
    }
  }

  resumePreload(): void {
    this.preloadSuspended = false;
    this.priorityChapterId = '';
    this.drain();
  }

  static getInstance(): ChapterCacheService {
    if (!ChapterCacheService.instance) {
      ChapterCacheService.instance = new ChapterCacheService();
    }
    return ChapterCacheService.instance;
  }

  setPreloadCount(forward: number, backward: number = 0): void {
    this.suspendPreload();
    PRE_DOWNLOAD_FORWARD = Number.isFinite(forward) ? Math.max(0, Math.min(50, Math.round(forward))) : 1;
    PRE_DOWNLOAD_BACKWARD = Number.isFinite(backward) ? Math.max(0, Math.min(50, Math.round(backward))) : 0;
    this.queue.clear();
    if (!this.isPreloadEnabled()) {
      // 清除队列并使在途解析失效，避免关闭后又追加下载。
      this.clearGen++;
      this.preloadGen++;
      this.priorityChapterId = '';
      for (const download of this.activeDownloads.values()) download.cancel();
      this.activeDownloads.clear();
    }
    hilog.info(DOMAIN, TAG, 'preload settings forward=%{public}d backward=%{public}d',
      PRE_DOWNLOAD_FORWARD, PRE_DOWNLOAD_BACKWARD);
    this.resumePreload();
  }

  getPreloadForward(): number {
    return PRE_DOWNLOAD_FORWARD;
  }

  isPreloadEnabled(): boolean {
    return PRE_DOWNLOAD_FORWARD > 0;
  }

  isChapterCached(chapterId: string): boolean {
    return this.getAudioUrl(chapterId) !== null || this.fileCache.has(chapterId);
  }

  isAudioChapterCached(book: Book, chapter: Chapter): boolean {
    if (chapter.source.type === 'rawfile') return true;
    if (chapter.source.type === 'file' && this.isUsableFile(chapter.source.value)) return true;
    return this.getAudioFilePath(book.id, chapter.id, chapter.originSourceValue || chapter.source.value) !== null;
  }

  /** 已解析的章节真实时长（秒）。仅在音频文件下载完成后才有值。 */
  getChapterDuration(chapterId: string): number {
    return this.durationCache.get(chapterId) ?? 0;
  }

  /** 完整预加载音频的实际磁盘占用，不含主动下载和正在写入的临时文件。 */
  async getCacheUsage(): Promise<number> {
    await this.storageMigration;
    if (this.cacheCleanupTask !== null) await this.cacheCleanupTask;
    if (this.diskCleanupTask !== null) await this.diskCleanupTask;
    const ctx = this.appContext;
    if (!ctx) throw new Error('音频缓存尚未初始化');
    let bytes: number = 0;
    const names = await fileIo.listFile(ctx.filesDir);
    for (const name of names) {
      if (!name.startsWith('chap_') || !name.endsWith('.mp3')) continue;
      const filePath = `${ctx.filesDir}/${name}`;
      try {
        const stat = await fileIo.stat(filePath);
        if (stat.isFile()) bytes += Math.max(0, stat.size);
      } catch (error) {
        // 正在淘汰/取消的文件可能已消失；其他统计错误交给设置页提示。
        if (await fileIo.access(filePath)) throw new Error(error instanceof Error ? error.message : String(error));
      }
    }
    return bytes;
  }

  clearAllCache(): Promise<ClearCacheResult> {
    if (this.cacheCleanupTask !== null) return this.cacheCleanupTask;
    const task = this.clearCacheFiles().finally((): void => {
      this.cacheCleanupTask = null;
      this.drain();
      this.stopBackgroundTransferIfIdle();
    });
    this.cacheCleanupTask = task;
    return task;
  }

  private async clearCacheFiles(): Promise<ClearCacheResult> {
    // 取消传输后发布标记会异步撤销，本次清理仍保留开始时在使用的文件。
    const protectedPaths: Set<string> = new Set<string>(this.activeFilePaths);
    if (this.playingFilePath) protectedPaths.add(this.playingFilePath);
    this.clearGen++;
    this.preloadGen++;
    for (const task of this.audioResolves.values()) task.request.cancel();
    for (const download of this.activeDownloads.values()) download.cancel();
    this.audioCache.clear();
    this.durationCache.clear();
    this.preloadFailureAt.clear();
    this.activeDownloads.clear();
    this.queue.clear();
    await this.storageMigration;
    if (this.diskCleanupTask !== null) await this.diskCleanupTask;
    const result = new ClearCacheResult();
    const ctx = this.appContext;
    if (!ctx) throw new Error('音频缓存尚未初始化');
    const names = await fileIo.listFile(ctx.filesDir);
    for (const name of names) {
      if (!name.startsWith('chap_') || !name.endsWith('.mp3')) continue;
      const filePath = `${ctx.filesDir}/${name}`;
      try {
        const stat = await fileIo.stat(filePath);
        if (!stat.isFile()) continue;
        if (protectedPaths.has(filePath) || this.isProtectedFile(filePath)) {
          result.protectedCount++;
          continue;
        }
        await fileIo.unlink(filePath);
        result.deleted++;
        result.releasedBytes += Math.max(0, stat.size);
        this.removeFileCacheEntry(filePath);
      } catch (_e) {
        try {
          if (await fileIo.access(filePath)) result.failed++;
          else this.removeFileCacheEntry(filePath);
        } catch (_accessError) {
          result.failed++;
        }
      }
    }
    return result;
  }

  /**
   * 物理清除磁盘上的章节音频与图片缓存，并顺带清理旧版本遗留的 reader 文件。
   */
  async wipeDiskCaches(): Promise<void> {
    await this.clearAllCache();
    const ctx = this.appContext;
    if (!ctx) return;
    await ChapterCacheService.deleteEntries(ctx.filesDir, true);
    await ChapterCacheService.deleteEntries(ctx.cacheDir, false);
  }

  /** readerScope=true:删 filesDir 里的旧缓存;false:删 cacheDir 里的章节/图片/卡片封面缓存 */
  private static async deleteEntries(dir: string, readerScope: boolean): Promise<void> {
    let names: string[] = [];
    try {
      names = await fileIo.listFile(dir);
    } catch (_e) {
      return;
    }
    for (const name of names) {
      const hit = readerScope
        ? (name.startsWith('reader_') || name.startsWith('widget_cover_'))
        : (name.startsWith('chap_') || name.startsWith('widget_cover_') || name === 'image_file_cache' ||
          name === 'comic_images' || name === 'comic_super_resolution_v1');
      if (!hit) continue;
      const p = `${dir}/${name}`;
      try {
        const st = await fileIo.stat(p);
        if (st.isDirectory()) {
          await fileIo.rmdir(p);
        } else {
          await fileIo.unlink(p);
        }
      } catch (_e) { /* ignore */ }
    }
  }

  setContext(ctx: common.UIAbilityContext): void {
    this.appContext = ctx;
    this.storageReady = false;
    this.storageMigration = StorageMigrationService.migrateFilesWithPrefix(ctx.cacheDir, ctx.filesDir, 'chap_', true)
      .then((): void => {
        this.fileCache.clear();
        this.storageReady = true;
      });
    this.storageMigration.then((): Promise<void> => this.enforceDiskCacheLimit()).catch((): void => {
      hilog.warn(DOMAIN, TAG, 'audio storage migration failed; legacy files retained');
    });
  }

  getAudioUrl(chapterId: string): string | null {
    const entry = this.getFreshAudioEntry(chapterId);
    return entry ? entry.resolvedUrl : null;
  }

  getAudioHeaders(chapterId: string): Record<string, string> {
    const entry = this.getFreshAudioEntry(chapterId);
    return entry ? entry.headers : {};
  }

  /** 切章接手已经开始的解析，只等待地址，不等待整章下载。 */
  getPendingAudioResolve(book: Book, chapter: Chapter): Promise<void> | undefined {
    const task = this.audioResolves.get(chapter.id);
    if (!task || task.request.isCancelled() || task.bookId !== book.id || task.sourceUrl !== book.sourceUrl ||
      (task.chapter.originSourceValue || task.chapter.source.value) !==
      (chapter.originSourceValue || chapter.source.value) ||
      !this.isResolveCurrent(chapter.id, task.clearGen, task.preloadGen)) return undefined;
    return task.promise;
  }

  rememberAudioRequest(chapterId: string, resolvedUrl: string, headers: Record<string, string>): void {
    if (!this.isPreloadEnabled() || !resolvedUrl.startsWith('http')) return;
    if (!this.audioCache.has(chapterId)) this.evictUrlCache();
    const entry: CacheEntry = { resolvedUrl: resolvedUrl, headers: headers, timestamp: Date.now() };
    this.audioCache.set(chapterId, entry);
  }

  private getFreshAudioEntry(chapterId: string): CacheEntry | undefined {
    const entry = this.audioCache.get(chapterId);
    if (entry && (!Number.isFinite(entry.timestamp) || Date.now() - entry.timestamp >= AUDIO_URL_TTL_MS)) {
      this.audioCache.delete(chapterId);
      return undefined;
    }
    return entry;
  }

  async waitForAudioFile(book: Book, chapter: Chapter): Promise<string | null> {
    await this.storageMigration;
    const completed = this.getAudioFilePath(book.id, chapter.id, chapter.originSourceValue || chapter.source.value);
    if (completed === null) {
      // 不等待整章文件：直接交给 AVPlayer 拉流，释放重复下载占用的带宽。
      this.activeDownloads.get(chapter.id)?.cancel();
      this.activeDownloads.delete(chapter.id);
      // 保留目标解析的接手资格；下载取消不应使已经开始的解析失效。
    }
    return completed;
  }

  /** 章节是否已经有完整音频文件落盘，命中后 AudioService 直接 fdSrc 播放 */
  getAudioFilePath(bookId: string, chapterId: string, pageUrl: string): string | null {
    const safePageUrl = pageUrl || '';
    const entry = this.fileCache.get(chapterId);
    if (entry) {
      // pageUrl 不一致说明缓存对应的章节不同（书源 toc 重排过），失效
      if (entry.pageUrl === safePageUrl && this.isUsableFile(entry.filePath)) {
        entry.timestamp = Date.now();
        try {
          fileIo.utimes(entry.filePath, entry.timestamp);
        } catch (_e) { /* 文件可能刚被系统缓存清理 */ }
        return entry.filePath;
      }
      this.fileCache.delete(chapterId);
    }

    const stablePath = this.audioFilePath(bookId, safePageUrl);
    const restored = this.restoreFileCacheEntry(chapterId, safePageUrl, stablePath);
    if (restored) return restored;

    // 兼容旧版本已经下载到磁盘的 chap_<hash(bookId|chapterId)>.mp3。
    const legacyPath = this.legacyAudioFilePath(bookId, chapterId);
    return this.restoreFileCacheEntry(chapterId, safePageUrl, legacyPath);
  }

  preloadAudioChapters(book: Book, currentIndex: number, currentAudioUrl: string = '',
    currentHeaders: Record<string, string> = {}): void {
    if (!book.sourceUrl || !this.isPreloadEnabled() || this.preloadSuspended) return;
    if (currentIndex < 0 || currentIndex >= book.chapters.length) return;
    hilog.info(DOMAIN, TAG, 'preload trigger index=%{public}d count=%{public}d generation=%{public}d',
      currentIndex, PRE_DOWNLOAD_FORWARD, this.preloadGen);
    // 按正文顺序优先预取下一章；目录倒序不改变预取方向。
    for (let distance = 1; distance <= PRE_DOWNLOAD_FORWARD + PRE_DOWNLOAD_BACKWARD; distance++) {
      const i = distance <= PRE_DOWNLOAD_FORWARD ? currentIndex + distance :
        currentIndex - (distance - PRE_DOWNLOAD_FORWARD);
      if (i >= 0 && i < book.chapters.length) {
        const ch = book.chapters[i];
        const pageUrl = ch.originSourceValue || ch.source.value;
        if (ch.source.type === 'url' && !this.isPreloadCoolingDown(ch.id) &&
          !this.getAudioFilePath(book.id, ch.id, pageUrl)) {
          this.enqueue(ch.id, () => this.resolveAudioAndDownload(book, ch));
        }
      }
      // 下一集先准备，当前集随后保存供回听，不被远处的预取窗口拖到最后。
      if (distance === 1 && currentAudioUrl) {
        this.ensureFileCached(book, book.chapters[currentIndex], currentAudioUrl, currentHeaders);
      }
    }
  }

  clearBook(bookId: string, chapters: Chapter[] = []): void {
    const prefix = bookId + '-c';
    for (const chapter of chapters) {
      this.clearChapter(chapter.id, bookId, chapter.originSourceValue || chapter.source.value);
    }
    for (const key of this.audioCache.keys()) {
      if (key.startsWith(prefix)) this.audioCache.delete(key);
    }
    for (const key of this.durationCache.keys()) {
      if (key.startsWith(prefix)) this.durationCache.delete(key);
    }
    for (const key of this.preloadFailureAt.keys()) {
      if (key.startsWith(prefix)) this.preloadFailureAt.delete(key);
    }
    for (const key of this.fileCache.keys()) {
      if (key.startsWith(prefix)) {
        const entry = this.fileCache.get(key);
        if (entry) this.deleteFileSafely(entry.filePath);
        this.fileCache.delete(key);
      }
    }
  }

  /** 清除某个章节的所有缓存（临时签名 URL 失效时用） */
  clearChapter(chapterId: string, bookId: string = '', pageUrl: string = ''): void {
    if (!this.storageReady) {
      this.storageMigration.then((): void => this.clearChapter(chapterId, bookId, pageUrl))
        .catch((): void => { /* 迁移失败保留旧文件 */ });
    }
    if (this.pendingTasks.has(`audio_${chapterId}`)) this.invalidatedResolves.add(chapterId);
    this.queue.delete(chapterId);
    this.activeDownloads.get(chapterId)?.cancel();
    this.activeDownloads.delete(chapterId);
    this.audioCache.delete(chapterId);
    this.durationCache.delete(chapterId);
    this.preloadFailureAt.delete(chapterId);
    const entry = this.fileCache.get(chapterId);
    if (entry) this.deleteFileSafely(entry.filePath);
    this.fileCache.delete(chapterId);
    // Cold-start files have no in-memory entry yet; remove both naming formats.
    const paths: Array<string | null> = [this.audioFilePath(bookId, pageUrl),
      this.legacyAudioFilePath(bookId, chapterId)];
    for (const path of paths) {
      if (path === null) continue;
      try { fileIo.unlinkSync(path); } catch (_e) { /* already absent */ }
    }
  }

  /** 播放稳定后保存当前章，完整文件供切章后的回听复用。 */
  ensureFileCached(book: Book, chapter: Chapter, resolvedUrl: string,
    headers: Record<string, string> = {}): void {
    if (!this.isPreloadEnabled()) return;
    if (!resolvedUrl || !resolvedUrl.startsWith('http')) return;
    if (this.isPreloadCoolingDown(chapter.id)) return;
    const pageUrl = chapter.originSourceValue || chapter.source.value;
    if (this.getAudioFilePath(book.id, chapter.id, pageUrl)) return;
    this.enqueue(chapter.id, () => this.downloadFile(book, chapter, resolvedUrl, headers));
  }

  /* ───────────── 内部：URL 解析队列 ───────────── */

  private enqueue(chapterId: string, task: () => Promise<void>): void {
    if (this.cacheCleanupTask !== null || !this.isPreloadEnabled() || this.preloadSuspended ||
      this.queue.has(chapterId) || this.runningTaskGenerations.get(chapterId) === this.preloadGen) return;
    this.queue.set(chapterId, task);
    this.drain();
  }

  private drain(): void {
    if (this.cacheCleanupTask !== null || this.preloadSuspended || !this.isPreloadEnabled()) return;
    while (this.runningCount < MAX_CONCURRENT && this.queue.size > 0) {
      const first = this.queue.keys().next();
      if (first.done) return;
      const chapterId = first.value;
      const task = this.queue.get(chapterId);
      this.queue.delete(chapterId);
      if (!task) continue;
      this.pendingTasks.add(chapterId);
      this.runningTaskGenerations.set(chapterId, this.preloadGen);
      this.runningCount++;
      this.runQueuedTask(chapterId, task, this.preloadGen).catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'preload task failed: %{public}s', error.message);
      }).finally((): void => {
        this.pendingTasks.delete(chapterId);
        this.runningTaskGenerations.delete(chapterId);
        this.runningCount--;
        this.drain();
        this.stopBackgroundTransferIfIdle();
      });
    }
  }

  /** 预缓存与手动下载分别持有 dataTransfer，暂停音频不会中断已经安排的有限队列。 */
  private async runQueuedTask(chapterId: string, task: () => Promise<void>, generation: number): Promise<void> {
    const clearGeneration = this.clearGen;
    const context = this.appContext;
    if (context && !this.transferHeld) {
      this.transferHeld = true;
      await BackgroundTaskService.startDataTransfer(context, 'preload');
    }
    if (clearGeneration !== this.clearGen || this.cacheCleanupTask !== null || !this.isPreloadEnabled() ||
      (generation !== this.preloadGen && chapterId !== this.priorityChapterId)) return;
    await task();
  }

  private stopBackgroundTransferIfIdle(): void {
    if (!this.transferHeld || this.runningCount > 0 || this.queue.size > 0 || !this.appContext) return;
    this.transferHeld = false;
    BackgroundTaskService.stopDataTransfer(this.appContext, 'preload').catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'release preload background task failed: %{public}s', error.message);
    });
  }

  /* ───────────── 内部：解析 + 下载 ───────────── */

  private async resolveAudioAndDownload(book: Book, chapter: Chapter): Promise<void> {
    const myClearGen = this.clearGen;
    const myPreloadGen = this.preloadGen;
    if (!this.getFreshAudioEntry(chapter.id)) {
      const task = new PendingAudioResolve(chapter);
      task.bookId = book.id;
      task.sourceUrl = book.sourceUrl;
      task.clearGen = myClearGen;
      task.preloadGen = myPreloadGen;
      task.promise = this.resolvePreloadAudio(book, chapter, myClearGen, myPreloadGen, task.request);
      this.audioResolves.set(chapter.id, task);
      try {
        await task.promise;
      } finally {
        if (this.audioResolves.get(chapter.id) === task) this.audioResolves.delete(chapter.id);
      }
    }
    const cached = this.getFreshAudioEntry(chapter.id);
    if (cached && this.isResolveCurrent(chapter.id, myClearGen, myPreloadGen)) {
      await this.downloadFileCheckGen(book, chapter, cached.resolvedUrl, cached.headers, myClearGen);
    }
  }

  private async resolvePreloadAudio(book: Book, chapter: Chapter,
    myClearGen: number, myPreloadGen: number, request: LightSourceRequest): Promise<void> {
    const taskKey = 'audio_' + chapter.id;
    this.pendingTasks.add(taskKey);
    let timerId: number = -1;
    let expired: boolean = false;
    request.cancelCheck = (): boolean => expired || !this.isResolveCurrent(chapter.id, myClearGen, myPreloadGen);
    try {
      const source = await this.findSource(book.sourceUrl);
      if (!this.isResolveCurrent(chapter.id, myClearGen, myPreloadGen)) return;
      if (!source) throw new Error('预加载书源不可用');
      const timeoutMs = BookSourceService.getAudioResolveTimeoutMs(source, PRELOAD_RESOLVE_TIMEOUT_MS);
      const timeout = new Promise<AudioRequestInfo | null>((_resolve, reject): void => {
        timerId = setTimeout((): void => {
          request.cancel();
          reject(new Error('预解析音频地址超时'));
        }, timeoutMs);
      });
      const resolve = async (): Promise<AudioRequestInfo | null> => {
        await BookSourceService.prepareAudioChapter(source, book, chapter);
        if (expired || !this.isResolveCurrent(chapter.id, myClearGen, myPreloadGen)) return null;
        return BookSourceService.resolveAudioRequest(source, chapter.originSourceValue || chapter.source.value,
          book.variables, ChapterRuleContext.create(chapter.title, chapter.index - 1, chapter.variables), request);
      };
      const requestInfo = await Promise.race([resolve(), timeout]);
      if (requestInfo === null || !this.isResolveCurrent(chapter.id, myClearGen, myPreloadGen)) return;
      const pageUrl = chapter.originSourceValue || chapter.source.value;
      if (!DownloadPolicy.isResolvedAudioUrl(pageUrl, requestInfo.url, requestInfo.resolved)) {
        throw new Error('预加载未获取到有效音频地址');
      }
      this.preloadFailureAt.delete(chapter.id);
      this.rememberAudioRequest(chapter.id, requestInfo.url, requestInfo.headers);
    } catch (err) {
      if (this.isResolveCurrent(chapter.id, myClearGen, myPreloadGen)) this.markPreloadFailure(chapter.id);
      const message = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'resolve preload failed [%{public}s]: %{public}s', chapter.title, message);
    } finally {
      expired = true;
      request.cancel();
      if (timerId >= 0) clearTimeout(timerId);
      this.pendingTasks.delete(taskKey);
      this.invalidatedResolves.delete(chapter.id);
    }
  }

  private isResolveCurrent(chapterId: string, clearGen: number, preloadGen: number): boolean {
    return this.isPreloadEnabled() && !this.invalidatedResolves.has(chapterId) && clearGen === this.clearGen &&
      (preloadGen === this.preloadGen || chapterId === this.priorityChapterId);
  }

  private downloadFileCheckGen(book: Book, chapter: Chapter, audioUrl: string,
    headers: Record<string, string>, gen: number): Promise<void> {
    if (gen !== this.clearGen || !this.isPreloadEnabled() || this.preloadSuspended) return Promise.resolve();
    return this.downloadFile(book, chapter, audioUrl, headers);
  }

  private downloadFile(book: Book, chapter: Chapter, audioUrl: string,
    headers: Record<string, string> = {}): Promise<void> {
    const existing = this.fileTasks.get(chapter.id);
    if (existing !== undefined) return existing;
    const task = this.downloadFileStrict(book, chapter, audioUrl, headers).finally((): void => {
      if (this.fileTasks.get(chapter.id) === task) this.fileTasks.delete(chapter.id);
    });
    this.fileTasks.set(chapter.id, task);
    return task;
  }

  private async downloadFileStrict(book: Book, chapter: Chapter, audioUrl: string,
    headers: Record<string, string> = {}): Promise<void> {
    if (this.cacheCleanupTask !== null || !this.isPreloadEnabled() ||
      (this.preloadSuspended && this.priorityChapterId !== chapter.id)) return;
    // HLS 是播放清单，不能作为完整音频写入 mp3 缓存（包含点播与直播）。
    if (DownloadPolicy.isHls(audioUrl, '')) return;
    if (!this.appContext) return;
    if (!audioUrl || !audioUrl.startsWith('http')) return;
    if (this.fileCache.has(chapter.id)) return;
    const capturedGen = this.clearGen;
    const taskKey = `file_${chapter.id}`;
    this.pendingTasks.add(taskKey);
    let transport: AudioDownloadTransport | null = null;
    let activePath = '';
    try {
      if (!this.storageReady) await this.storageMigration;
      if (capturedGen !== this.clearGen || !this.isPreloadEnabled() ||
        (this.preloadSuspended && this.priorityChapterId !== chapter.id)) return;
      const pageUrl = chapter.originSourceValue || chapter.source.value;
      const filePath = this.audioFilePath(book.id, pageUrl);
      if (!filePath) return;
      // 已存在直接复用（避免重复下）
      const restored = this.restoreFileCacheEntry(chapter.id, pageUrl, filePath)
        ?? this.restoreFileCacheEntry(chapter.id, pageUrl, this.legacyAudioFilePath(book.id, chapter.id));
      if (restored) {
        this.extractDuration(chapter, restored);
        return;
      }

      transport = new AudioDownloadTransport();
      activePath = filePath;
      this.activeFilePaths.add(filePath);
      this.activeDownloads.set(chapter.id, transport);
      const bytes = await transport.download({ url: audioUrl, headers: headers, finalPath: filePath });
      if (capturedGen !== this.clearGen || this.activeDownloads.get(chapter.id) !== transport) {
        if (filePath !== this.playingFilePath) this.deleteFileSafely(filePath);
        return;
      }
      this.fileCache.set(chapter.id, {
        filePath,
        pageUrl,
        bytes: bytes,
        timestamp: Date.now(),
      });
      this.preloadFailureAt.delete(chapter.id);
      hilog.info(DOMAIN, TAG, 'file cached chapter=%{public}s bytes=%{public}d', chapter.id, bytes);
      DiagnosticLogService.info('audio.cache', `complete; bytes=${bytes}`);
      emitter.emit(EVT_CHAPTER_CACHE_UPDATED, { data: { chapterId: chapter.id } });
      this.evictFileCache();
      await this.enforceDiskCacheLimit();
      this.extractDuration(chapter, filePath);
    } catch (err) {
      if (capturedGen === this.clearGen && transport !== null &&
        this.activeDownloads.get(chapter.id) === transport && this.isPreloadEnabled()) {
        this.audioCache.delete(chapter.id);
        this.markPreloadFailure(chapter.id);
      }
      const message = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'downloadFile failed: %{public}s', message);
      DiagnosticLogService.info('audio.cache', `incomplete; ${message}`);
    } finally {
      if (activePath) this.activeFilePaths.delete(activePath);
      if (transport !== null && this.activeDownloads.get(chapter.id) === transport) this.activeDownloads.delete(chapter.id);
      this.pendingTasks.delete(taskKey);
    }
  }

  private isPreloadCoolingDown(chapterId: string): boolean {
    const failedAt = this.preloadFailureAt.get(chapterId) ?? 0;
    if (failedAt <= 0) return false;
    if (Date.now() - failedAt < PRELOAD_FAILURE_COOLDOWN_MS) return true;
    this.preloadFailureAt.delete(chapterId);
    return false;
  }

  private markPreloadFailure(chapterId: string): void {
    this.preloadFailureAt.set(chapterId, Date.now());
  }

  private async findSource(sourceUrl: string): Promise<BookSource | null> {
    return await SourceDataService.getSourceByUrl(sourceUrl) ?? null;
  }

  private evictUrlCache(): void {
    if (this.audioCache.size < MAX_URL_CACHE_SIZE) return;
    const first = this.audioCache.keys().next();
    if (!first.done) this.audioCache.delete(first.value);
  }

  /** 文件缓存超过 1GB 后，按最近访问时间淘汰最久未使用的章节。 */
  private evictFileCache(): void {
    if (this.cacheCleanupTask !== null) return;
    let totalBytes: number = 0;
    for (const entry of this.fileCache.values()) {
      totalBytes += Math.max(0, entry.bytes);
    }
    while (totalBytes > MAX_FILE_CACHE_BYTES) {
      let oldestId: string | null = null;
      let oldestTimestamp: number = Number.MAX_SAFE_INTEGER;
      for (const id of this.fileCache.keys()) {
        const candidate = this.fileCache.get(id);
        if (candidate && !this.isProtectedFile(candidate.filePath) && candidate.timestamp < oldestTimestamp) {
          oldestId = id;
          oldestTimestamp = candidate.timestamp;
        }
      }
      if (oldestId === null) return;
      const entry = this.fileCache.get(oldestId);
      if (entry) {
        totalBytes -= Math.max(0, entry.bytes);
        this.deleteFileSafely(entry.filePath);
      }
      this.fileCache.delete(oldestId);
    }
  }

  /** 冷启动时按磁盘实际大小执行 1GB 上限，避免上个进程遗留文件脱离内存索引。 */
  private async enforceDiskCacheLimit(): Promise<void> {
    if (this.cacheCleanupTask !== null) return;
    this.diskCleanupRequested = true;
    if (this.diskCleanupTask !== null) return this.diskCleanupTask;
    const task = this.drainDiskCleanup();
    this.diskCleanupTask = task;
    try {
      await task;
    } finally {
      this.diskCleanupTask = null;
    }
  }

  private async drainDiskCleanup(): Promise<void> {
    while (this.diskCleanupRequested) {
      this.diskCleanupRequested = false;
      await this.scanDiskCacheLimit();
    }
  }

  private isProtectedFile(filePath: string): boolean {
    return filePath === this.playingFilePath || this.activeFilePaths.has(filePath);
  }

  private async scanDiskCacheLimit(): Promise<void> {
    const ctx = this.appContext;
    if (!ctx) return;
    let names: string[] = [];
    try {
      names = await fileIo.listFile(ctx.filesDir);
    } catch (_e) {
      return;
    }
    const entries: DiskCacheEntry[] = [];
    let totalBytes: number = 0;
    for (const name of names) {
      if (!name.startsWith('chap_') || !name.endsWith('.mp3')) continue;
      const filePath = `${ctx.filesDir}/${name}`;
      try {
        const stat = await fileIo.stat(filePath);
        if (stat.isDirectory()) continue;
        const entry: DiskCacheEntry = {
          filePath,
          bytes: Math.max(0, stat.size),
          timestamp: stat.mtime,
        };
        entries.push(entry);
        totalBytes += entry.bytes;
      } catch (_e) { /* 文件可能被系统并发清理 */ }
    }
    if (totalBytes <= MAX_FILE_CACHE_BYTES) return;
    entries.sort((left: DiskCacheEntry, right: DiskCacheEntry): number => left.timestamp - right.timestamp);
    for (const entry of entries) {
      if (totalBytes <= MAX_FILE_CACHE_BYTES) return;
      if (this.isProtectedFile(entry.filePath)) continue;
      try {
        await fileIo.unlink(entry.filePath);
        totalBytes -= entry.bytes;
        this.removeFileCacheEntry(entry.filePath);
      } catch (_e) { /* 正在使用或已经被系统删除 */ }
    }
  }

  private removeFileCacheEntry(filePath: string): void {
    for (const chapterId of this.fileCache.keys()) {
      const entry = this.fileCache.get(chapterId);
      if (entry && entry.filePath === filePath) {
        this.fileCache.delete(chapterId);
      }
    }
  }

  private deleteFileSafely(path: string): void {
    try {
      fileIo.unlink(path).catch(() => { /* ignore */ });
    } catch (_e) { /* ignore */ }
  }

  private audioFilePath(bookId: string, pageUrl: string): string | null {
    if (!this.appContext || !bookId || !pageUrl) return null;
    return `${this.appContext.filesDir}/chap_${this.hash(bookId + '|' + pageUrl)}.mp3`;
  }

  private legacyAudioFilePath(bookId: string, chapterId: string): string | null {
    if (!this.appContext || !bookId || !chapterId) return null;
    return `${this.appContext.filesDir}/chap_${this.hash(bookId + '|' + chapterId)}.mp3`;
  }

  private restoreFileCacheEntry(chapterId: string, pageUrl: string, filePath: string | null): string | null {
    if (!filePath || !this.isUsableFile(filePath)) return null;
    let bytes = 0;
    try {
      bytes = fileIo.statSync(filePath).size;
    } catch (_e) {
      bytes = 0;
    }
    this.fileCache.set(chapterId, {
      filePath,
      pageUrl,
      bytes,
      timestamp: Date.now(),
    });
    this.evictFileCache();
    return filePath;
  }

  private isUsableFile(filePath: string): boolean {
    try {
      return fileIo.statSync(filePath).size > 1024;
    } catch (_e) {
      return false;
    }
  }

  /** 解析音频文件的元数据时长（秒），写入 durationCache 并广播事件让 UI 刷新 */
  private async extractDuration(chapter: Chapter, filePath: string): Promise<void> {
    if (this.durationCache.has(chapter.id)) return;
    let extractor: media.AVMetadataExtractor | null = null;
    let f: fileIo.File | null = null;
    try {
      f = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(filePath);
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = { fd: f.fd, offset: 0, length: stat.size };
      const meta = await extractor.fetchMetadata();
      const ms = parseInt(meta.duration ?? '0', 10);
      if (Number.isFinite(ms) && ms > 0) {
        const seconds = Math.round(ms / 1000);
        this.durationCache.set(chapter.id, seconds);
        emitter.emit(EVT_CHAPTER_DURATION_UPDATED, {
          data: { chapterId: chapter.id, durationSec: seconds }
        });
      }
    } catch (err) {
    } finally {
      if (extractor) {
        try { await extractor.release(); } catch (_e) { /* ignore */ }
      }
      if (f) {
        try { await fileIo.close(f); } catch (_e) { /* ignore */ }
      }
    }
  }

  private hash(s: string): string {
    let h = 0;
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) - h + s.charCodeAt(i)) | 0;
    }
    return Math.abs(h).toString(16);
  }
}
