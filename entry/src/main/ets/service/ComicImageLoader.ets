import { Book } from '../model/Book';
import { BookSourceService } from './BookSourceService';
import { LightSourceRequest } from './rulesource/light/LightSourceRequestPolicy';

class ComicImageJob {
  key: string = '';
  sourceUrl: string = '';
  url: string = '';
  request: LightSourceRequest = new LightSourceRequest(0);
  consumers: Array<() => boolean> = [];
  promise: Promise<string> = Promise.resolve('');
  resolve: (url: string) => void = () => {};
  reject: (error: Error) => void = () => {};
  cancelled(): boolean { return this.consumers.every((check: () => boolean): boolean => check()); }
}

/** Bounded source-aware image work. Background tasks use at most two slots; visible pages take priority. */
export class ComicImageLoader {
  private static readonly MAX_ACTIVE: number = 6;
  private static readonly MAX_BACKGROUND: number = 2;
  private static jobs: Map<string, ComicImageJob> = new Map();
  private static queue: ComicImageJob[] = [];
  private static active: number = 0;
  private static background: number = 0;

  static promote(sourceUrl: string, url: string): void {
    ComicImageLoader.jobs.get(`${sourceUrl}\n${url}`)?.request.promote();
    ComicImageLoader.pump();
  }

  static async load(sourceUrl: string, url: string, cancelled: () => boolean,
    foreground: boolean = false): Promise<string> {
    if (cancelled()) throw new Error('Comic image cancelled');
    if (url.startsWith('file://') || url.startsWith('/')) return url;
    if (!sourceUrl) throw new Error('Comic image source missing');
    const key = `${sourceUrl}\n${url}`;
    let job = ComicImageLoader.jobs.get(key);
    if (job?.cancelled()) job = undefined;
    if (!job) {
      if (ComicImageLoader.queue.length >= 64) throw new Error('Comic image queue full');
      const created = new ComicImageJob();
      created.key = key;
      created.sourceUrl = sourceUrl;
      created.url = url;
      created.request.cancelCheck = (): boolean => created.cancelled();
      created.promise = new Promise<string>((resolve, reject) => { created.resolve = resolve; created.reject = reject; });
      job = created;
      ComicImageLoader.jobs.set(key, job);
      ComicImageLoader.queue.push(job);
    }
    job.consumers.push(cancelled);
    if (foreground) job.request.promote();
    ComicImageLoader.pump();
    const result = await job.promise;
    if (cancelled()) throw new Error('Comic image cancelled');
    return result;
  }

  private static pump(): void {
    for (let index = ComicImageLoader.queue.length - 1; index >= 0; index--) {
      const job = ComicImageLoader.queue[index];
      if (job.cancelled()) {
        ComicImageLoader.queue.splice(index, 1);
        if (ComicImageLoader.jobs.get(job.key) === job) ComicImageLoader.jobs.delete(job.key);
        job.reject(new Error('Comic image cancelled'));
      }
    }
    while (ComicImageLoader.active < ComicImageLoader.MAX_ACTIVE) {
      let index = ComicImageLoader.queue.findIndex((job: ComicImageJob): boolean => job.request.priority === 2);
      if (index < 0 && ComicImageLoader.background < ComicImageLoader.MAX_BACKGROUND &&
        ComicImageLoader.active < ComicImageLoader.MAX_ACTIVE - 1) index = 0;
      if (index < 0 || index >= ComicImageLoader.queue.length) return;
      const job = ComicImageLoader.queue.splice(index, 1)[0];
      const background = job.request.priority !== 2;
      ComicImageLoader.active++;
      if (background) ComicImageLoader.background++;
      ComicImageLoader.run(job, background);
    }
  }

  private static async run(job: ComicImageJob, background: boolean): Promise<void> {
    try {
      const book: Book = { id: '', title: '', author: '', narrator: '', cover: '', category: '', intro: '',
        totalDuration: 0, chapterCount: 0, rating: 0, tags: [], chapters: [], bookUrl: '', sourceUrl: job.sourceUrl };
      const paths = await BookSourceService.cacheComicImages(book, [job.url], job.request);
      if (job.cancelled()) throw new Error('Comic image cancelled');
      const path = paths[0] || '';
      if (!path.startsWith('/') && !path.startsWith('file://')) throw new Error('Comic image download or decode failed');
      job.resolve(path);
    } catch (error) {
      job.reject(job.cancelled() ? new Error('Comic image cancelled') :
        error instanceof Error ? error : new Error('Comic image download or decode failed'));
    } finally {
      if (ComicImageLoader.jobs.get(job.key) === job) ComicImageLoader.jobs.delete(job.key);
      ComicImageLoader.active--;
      if (background) ComicImageLoader.background--;
      ComicImageLoader.pump();
    }
  }
}
