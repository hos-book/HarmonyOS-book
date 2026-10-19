import { Book, Chapter } from '../model/Book';
import { BookSourceService } from './BookSourceService';
import { ReaderImageMarker } from './rulesource/light/upstream/core/book/ReaderImageMarker';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileUri, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { OnlineTextContentCache } from './text/OnlineTextContentCache';
import { LightSourceRequest } from './rulesource/light/LightSourceRequestPolicy';

export class ComicPage {
  key: string = '';
  url: string = '';
  index: number = 0;
  width: number = 0;
  height: number = 0;
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
    const task = ComicReaderService.fillImages(book, chapter, pages, context, key, request);
    ComicReaderService.imagePending.set(imageKey, task);
    try { return await task; } finally {
      if (ComicReaderService.imagePending.get(imageKey) === task) {
        ComicReaderService.imagePending.delete(imageKey);
        ComicReaderService.requests.delete(imageKey);
      }
    }
  }

  private static async fillImages(book: Book, chapter: Chapter, pages: ComicPage[], context: common.Context,
    key: string, request: LightSourceRequest): Promise<boolean> {
    const paths = await BookSourceService.cacheComicImages(book, pages.map((page: ComicPage): string => page.url), request);
    if (request.isCancelled() || paths.length !== pages.length) return false;
    const saved: ComicPage[] = [];
    for (let index = 0; index < pages.length; index++) {
      const page = new ComicPage();
      page.key = pages[index].key;
      page.index = pages[index].index;
      page.width = pages[index].width;
      page.height = pages[index].height;
      page.url = paths[index].startsWith('/') ? fileUri.getUriFromPath(paths[index]) : paths[index];
      saved.push(page);
    }
    await OnlineTextContentCache.write(context, key, JSON.stringify(saved));
    if (request.isCancelled()) return false;
    for (let index = 0; index < saved.length; index++) pages[index].url = saved[index].url;
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
      return pages;
    } catch (_error) { return []; }
  }

  static async load(book: Book, chapter: Chapter, context?: common.Context,
    force: boolean = false, preload: boolean = false): Promise<ComicPage[]> {
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
      if (!force && cached.length > 0) return cached;
      if (force) {
        for (const page of cached) {
          try { await fileIo.unlink(new fileUri.FileUri(page.url).path); } catch (_error) { /* 已清理 */ }
        }
        await OnlineTextContentCache.removeChapter(context, key);
      }
    }
    if (request.isCancelled()) throw new Error('Comic request cancelled');
    const pages = await ComicReaderService.fetch(book, chapter, request);
    if (request.isCancelled()) throw new Error('Comic request cancelled');
    if (context && pages.length > 0) {
      await OnlineTextContentCache.write(context, key, JSON.stringify(pages));
      emitter.emit('app.chapter.cache.updated', { data: { chapterId: chapter.id } });
    }
    return pages;
  }

  private static async fetch(book: Book, chapter: Chapter, request: LightSourceRequest): Promise<ComicPage[]> {
    const result = await BookSourceService.getSourceChapterContent(book,
      chapter.originSourceValue || chapter.source.value, chapter.variables, request);
    hilog.info(0x0001, 'ComicReader', 'resolved type=%{public}s images=%{public}d rich=%{public}d text=%{public}d',
      result.mediaType, result.imageUrls?.length ?? -1, result.richContent?.length ?? -1, result.content?.length ?? -1);
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
