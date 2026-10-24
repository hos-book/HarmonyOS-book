import { Book, Chapter } from '../model/Book';
import { BookSourceService } from './BookSourceService';
import { ReaderImageMarker } from './rulesource/light/upstream/core/book/ReaderImageMarker';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileUri, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { OnlineTextContentCache } from './text/OnlineTextContentCache';
import { LightSourceRequest } from './rulesource/light/LightSourceRequestPolicy';
import { ReaderCacheService } from './ReaderCacheService';
import { ComicImageLoader } from './ComicImageLoader';
import { image } from '@kit.ImageKit';

export class ComicPage {
  key: string = '';
  url: string = '';
  index: number = 0;
  width: number = 0;
  height: number = 0;
  sourceUrl: string = '';
  requestUrl: string = '';
  cacheKey: string = '';
  chapterId: string = '';
}

/** Request/source ownership is rebuilt by registerPages; do not repeat it in every disk row. */
class ComicCachedPage {
  key: string;
  url: string;
  index: number;
  width: number;
  height: number;
  constructor(page: ComicPage) {
    this.key = page.key;
    this.url = page.url;
    this.index = page.index;
    this.width = page.width;
    this.height = page.height;
  }
}

export class ComicPageDataSource implements IDataSource {
  private pages: ComicPage[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.pages.length; }
  getData(index: number): ComicPage { return this.pages[index]; }
  setPages(pages: ComicPage[]): void {
    this.pages = pages;
    for (const listener of this.listeners) listener.onDataReloaded();
  }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
}

/** 图片由轻页公共核心处理请求头、Cookie 和解密，UI 只消费处理后的图片地址。 */
export class ComicReaderService {
  private static pending: Map<string, Promise<ComicPage[]>> = new Map();
  private static requests: Map<string, LightSourceRequest> = new Map();
  private static imagePending: Map<string, Promise<boolean>> = new Map();
  private static chapterPages: Map<string, ComicPage[]> = new Map();
  private static saves: Map<string, Promise<void>> = new Map();
  private static dirtySaves: Set<string> = new Set();

  private static encodePages(pages: ComicPage[]): string {
    return JSON.stringify(pages.map((page: ComicPage): ComicCachedPage => new ComicCachedPage(page)));
  }

  /** Read only the image header before mounting Image, so layout and decode use the same aspect ratio. */
  static async prepareImage(page: ComicPage, path: string): Promise<void> {
    if (page.width > 0 && page.height > 0) return;
    let source: image.ImageSource | undefined;
    try {
      const local = path.startsWith('file://') ? new fileUri.FileUri(path).path : path;
      source = image.createImageSource(local);
      const info = await source.getImageInfo();
      if (info.size.width > 0 && info.size.height > 0) {
        page.width = info.size.width;
        page.height = info.size.height;
      }
    } catch (_error) { /* Image still gets a chance to decode; its error UI handles invalid files. */ }
    finally { if (source) { try { await source.release(); } catch (_error) { } } }
  }

  static async imageReady(page: ComicPage, path: string, context: common.Context): Promise<string> {
    await ComicReaderService.prepareImage(page, path);
    const uri = path.startsWith('/') ? fileUri.getUriFromPath(path) : path;
    if (page.url === uri) return uri;
    page.url = uri;
    // Notify mounted offscreen image nodes before persisting the chapter manifest.
    emitter.emit('app.comic.image.ready');
    const pages = ComicReaderService.chapterPages.get(page.cacheKey);
    if (!pages || !pages.includes(page)) return page.url;
    const key = page.cacheKey;
    ComicReaderService.dirtySaves.add(key);
    if (!ComicReaderService.saves.has(key)) {
      const save = ComicReaderService.saveImages(context, key).catch((): void => {
        hilog.warn(0x0001, 'ComicReader', 'image manifest save failed');
      }).finally((): void => { ComicReaderService.saves.delete(key); });
      ComicReaderService.saves.set(key, save);
    }
    return page.url;
  }

  private static async saveImages(context: common.Context, key: string): Promise<void> {
    // Coalesce completed images without delaying display or the next download.
    while (ComicReaderService.dirtySaves.has(key)) {
      await new Promise<void>((resolve): void => { setTimeout(resolve, 300); });
      ComicReaderService.dirtySaves.delete(key);
      const pages = ComicReaderService.chapterPages.get(key);
      if (!pages || pages.length === 0) return;
      const local = pages.filter((item: ComicPage): boolean => item.url.startsWith('file://'));
      const startedAt = Date.now();
      const saving = OnlineTextContentCache.write(context, key, ComicReaderService.encodePages(pages));
      if (Date.now() - startedAt >= 8) console.info(`[ComicPerf] manifest-encode ms=${Date.now() - startedAt} pages=${pages.length}`);
      await saving;
      await ReaderCacheService.record(local.map((item: ComicPage): string => item.url));
      if (local.length === pages.length && ComicReaderService.chapterPages.get(key) === pages) {
        emitter.emit('app.chapter.cache.updated', { data: { chapterId: pages[0].chapterId } });
      }
    }
  }

  /** 当前章只预取阅读位置后的有限窗口，不跨章；单页失败不阻断后续图片。 */
  static async preloadNearbyImages(pages: ComicPage[], pageIndex: number, count: number,
    context: common.Context, cancelled: () => boolean,
    keepPage: (index: number) => boolean = (): boolean => true): Promise<void> {
    if (!Number.isInteger(pageIndex) || !Number.isInteger(count) || count <= 0) return;
    const start = Math.max(0, pageIndex + 1);
    const end = Math.min(pages.length, start + Math.min(count, 20));
    const tasks: Promise<void>[] = [];
    for (let index = start; index < end; index++) {
      const page = pages[index];
      const stopped = (): boolean => cancelled() || !keepPage(index);
      if (stopped()) continue;
      // The shared loader bounds background downloads to two and prioritizes visible pages.
      tasks.push(ComicImageLoader.load(page.sourceUrl, page.url, stopped).then(async (path: string): Promise<void> => {
        if (!stopped()) await ComicReaderService.imageReady(page, path, context);
      }).catch((): void => {}));
    }
    await Promise.all(tasks);
  }

  /** 图片预取独立于清单加载，进入该章无需等待整章图片下载完。 */
  static async preloadImages(book: Book, chapter: Chapter, pages: ComicPage[], context: common.Context,
    cancelCheck: () => boolean): Promise<boolean> {
    const key = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id,
      chapter.originSourceValue || chapter.source.value);
    const imageKey = `${key}:images`;
    const pending = ComicReaderService.imagePending.get(imageKey);
    if (pending && !ComicReaderService.requests.get(imageKey)?.isCancelled()) return pending;
    const request = new LightSourceRequest(0);
    request.cancelCheck = cancelCheck;
    ComicReaderService.requests.set(imageKey, request);
    if (!ComicReaderService.chapterPages.has(key)) ComicReaderService.registerPages(book, chapter, key, pages);
    const task = ComicReaderService.fillImages(book, chapter, pages, context, request);
    ComicReaderService.imagePending.set(imageKey, task);
    try { return await task; } finally {
      if (ComicReaderService.imagePending.get(imageKey) === task) {
        ComicReaderService.imagePending.delete(imageKey);
        ComicReaderService.requests.delete(imageKey);
      }
    }
  }

  private static async fillImages(book: Book, chapter: Chapter, pages: ComicPage[], context: common.Context,
    request: LightSourceRequest): Promise<boolean> {
    for (const page of pages) {
      if (request.isCancelled()) return false;
      try {
        const path = await ComicImageLoader.load(book.sourceUrl, page.url,
          (): boolean => request.isCancelled());
        if (request.isCancelled()) return false;
        await ComicReaderService.imageReady(page, path, context);
      } catch (_error) { return false; }
    }
    if (request.isCancelled()) return false;
    // Offline completeness is checked only after the final coalesced manifest is durable.
    if (pages.length > 0) await ComicReaderService.saves.get(pages[0].cacheKey);
    const complete = (await ComicReaderService.cached(context, book, chapter)).length === pages.length;
    if (complete) emitter.emit('app.chapter.cache.updated', { data: { chapterId: chapter.id } });
    hilog.info(0x0001, 'ComicReader', 'image prefetch complete=%{public}s pages=%{public}d', String(complete), pages.length);
    return complete;
  }

  static cancelPendingExcept(book?: Book, chapter?: Chapter): void {
    const keep = book && chapter ? OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id,
      chapter.originSourceValue || chapter.source.value) : '';
    for (const key of ComicReaderService.requests.keys()) {
      if (key !== keep && key !== `${keep}:images`) ComicReaderService.requests.get(key)?.cancel();
    }
  }

  static async cached(context: common.Context, book: Book, chapter: Chapter): Promise<ComicPage[]> {
    ReaderCacheService.configure(context);
    const key = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id,
      chapter.originSourceValue || chapter.source.value);
    const saved = await OnlineTextContentCache.read(context, key);
    if (!saved) return [];
    try {
      const pages: ComicPage[] = JSON.parse(saved);
      if (!Array.isArray(pages) || pages.length === 0) return [];
      for (const page of pages) {
        if (typeof page.url !== 'string' || !page.url.startsWith('file://')) return [];
        const path = new fileUri.FileUri(page.url).path;
        if (!path.startsWith(`${context.cacheDir}/comic_images/`) || (await fileIo.stat(path)).size <= 0) return [];
      }
      await ReaderCacheService.record(pages.map((page: ComicPage): string => page.url));
      return pages;
    } catch (_error) { return []; }
  }

  static async load(book: Book, chapter: Chapter, context?: common.Context,
    force: boolean = false, preload: boolean = false): Promise<ComicPage[]> {
    if (context) ReaderCacheService.configure(context);
    const key = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id,
      chapter.originSourceValue || chapter.source.value);
    if (force) ComicReaderService.requests.get(`${key}:images`)?.cancel();
    else if (!preload) ComicReaderService.requests.get(`${key}:images`)?.promote();
    const pending = ComicReaderService.pending.get(key);
    if (pending) {
      const request = ComicReaderService.requests.get(key);
      if (!force && !request?.isCancelled()) {
        if (!preload) request?.promote();
        return pending;
      }
      try { await pending; } catch (_error) { /* 强制刷新仍继续 */ }
    }
    const request = new LightSourceRequest(preload ? 0 : 2);
    ComicReaderService.requests.set(key, request);
    const task = ComicReaderService.readOrLoad(book, chapter, key, request, context, force);
    ComicReaderService.pending.set(key, task);
    try { return await task; } finally {
      if (ComicReaderService.pending.get(key) === task) {
        ComicReaderService.pending.delete(key);
        ComicReaderService.requests.delete(key);
      }
    }
  }

  private static async readOrLoad(book: Book, chapter: Chapter, key: string, request: LightSourceRequest,
    context?: common.Context, force: boolean = false): Promise<ComicPage[]> {
    if (context) {
      const cached = await ComicReaderService.cached(context, book, chapter);
      if (!force && cached.length > 0) {
        ComicReaderService.registerPages(book, chapter, key, cached);
        return cached;
      }
      if (force) {
        ComicReaderService.chapterPages.delete(key);
        ComicReaderService.dirtySaves.delete(key);
        await ComicReaderService.saves.get(key);
        for (const page of cached) {
          try { await fileIo.unlink(new fileUri.FileUri(page.url).path); } catch (_error) { /* 已清理 */ }
        }
        await OnlineTextContentCache.removeChapter(context, key);
      }
    }
    const prepared = ComicReaderService.chapterPages.get(key);
    if (!force && prepared && prepared.length > 0) {
      let reusable = true;
      if (context) {
        for (const page of prepared) {
          if (!page.url.startsWith('file://')) continue;
          try {
            if ((await fileIo.stat(new fileUri.FileUri(page.url).path)).size > 0) continue;
          } catch (_error) { /* 已被缓存清理，重新下载这一页。 */ }
          if (page.requestUrl && !page.requestUrl.startsWith('file://')) page.url = page.requestUrl;
          else reusable = false;
        }
      }
      if (request.isCancelled()) throw new Error('Comic request cancelled');
      if (reusable) return prepared;
    }
    if (request.isCancelled()) throw new Error('Comic request cancelled');
    const pages = await ComicReaderService.fetch(book, chapter, request);
    if (request.isCancelled()) throw new Error('Comic request cancelled');
    ComicReaderService.registerPages(book, chapter, key, pages);
    if (context && pages.length > 0) {
      await OnlineTextContentCache.write(context, key, ComicReaderService.encodePages(pages));
      emitter.emit('app.chapter.cache.updated', { data: { chapterId: chapter.id } });
    }
    return pages;
  }

  private static registerPages(book: Book, chapter: Chapter, key: string, pages: ComicPage[]): void {
    for (const page of pages) {
      page.sourceUrl = book.sourceUrl;
      page.requestUrl = page.requestUrl || page.url;
      page.cacheKey = key;
      page.chapterId = chapter.id;
    }
    ComicReaderService.chapterPages.set(key, pages);
    if (ComicReaderService.chapterPages.size > 8) ComicReaderService.chapterPages.delete(Array.from(ComicReaderService.chapterPages.keys())[0]);
  }

  private static async fetch(book: Book, chapter: Chapter, request: LightSourceRequest): Promise<ComicPage[]> {
    const result = await BookSourceService.getSourceChapterContent(book,
      chapter.originSourceValue || chapter.source.value, chapter.variables, request, true);
    hilog.info(0x0001, 'ComicReader',
      'resolved type=%{public}s images=%{public}d local=%{public}d deferred=%{public}s rich=%{public}d text=%{public}d',
      result.mediaType, result.imageUrls?.length ?? -1,
      result.imageUrls.filter((url: string): boolean => url.startsWith('/') || url.startsWith('file://')).length,
      'true', result.richContent?.length ?? -1, result.content?.length ?? -1);
    const markers = result.richContent.match(/\[\[LEGADO_EPUB_IMAGE:[\s\S]*?\]\]/g) ?? [];
    const pages: ComicPage[] = [];
    const occurrences = new Map<string, number>();
    for (let index = 0; index < result.imageUrls.length; index++) {
      const url = result.imageUrls[index];
      if (!url) continue;
      const page = new ComicPage();
      // The shared engine returns sandbox paths for downloaded/decrypted images.
      // ArkUI Image needs a file URI; a bare path is interpreted as a resource asset.
      page.url = url.startsWith('/') ? fileUri.getUriFromPath(url) : url;
      page.index = pages.length;
      const occurrence = occurrences.get(url) ?? 0;
      occurrences.set(url, occurrence + 1);
      page.key = `${chapter.id}:${url}:${occurrence}`;
      if (index < markers.length) {
        const info = ReaderImageMarker.parse(markers[index]);
        page.width = info.width;
        page.height = info.height;
      }
      pages.push(page);
    }
    return pages;
  }
}
