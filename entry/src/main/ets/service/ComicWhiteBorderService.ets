import { taskpool } from '@kit.ArkTS';
import { ComicCropRect } from '../utils/ComicWhiteBorderGeometry';
import { detectComicWhiteBorder } from './ComicWhiteBorderWorker';

/** 小图扫描串行执行；不在 UI 线程解码，不写回或复制原图。 */
export class ComicWhiteBorderService {
  private static cache: Map<string, ComicCropRect> = new Map();
  private static pending: Map<string, Promise<ComicCropRect>> = new Map();
  private static tail: Promise<void> = Promise.resolve();

  static inspect(uri: string): Promise<ComicCropRect> {
    const cached = ComicWhiteBorderService.cache.get(uri);
    if (cached) {
      ComicWhiteBorderService.cache.delete(uri);
      ComicWhiteBorderService.cache.set(uri, cached);
      return Promise.resolve(cached);
    }
    const pending = ComicWhiteBorderService.pending.get(uri);
    if (pending) return pending;
    if (!uri || ComicWhiteBorderService.pending.size >= 16) return Promise.resolve(new ComicCropRect());
    const job: Promise<ComicCropRect> = ComicWhiteBorderService.tail.then(async (): Promise<ComicCropRect> => {
      try {
        const result = await taskpool.execute<[string], number[]>(detectComicWhiteBorder, uri);
        const crop = new ComicCropRect(result[0], result[1], result[2], result[3]);
        ComicWhiteBorderService.cache.set(uri, crop);
        if (ComicWhiteBorderService.cache.size > 96) {
          const keys = Array.from(ComicWhiteBorderService.cache.keys());
          ComicWhiteBorderService.cache.delete(keys[0]);
        }
        return crop;
      } catch (_error) {
        return new ComicCropRect();
      }
    });
    ComicWhiteBorderService.pending.set(uri, job);
    ComicWhiteBorderService.tail = job.then((): void => { ComicWhiteBorderService.pending.delete(uri); });
    return job;
  }
}
