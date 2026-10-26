
import { ReaderCacheService } from '../../../../../ReaderCacheService';
/** Cache lifetime belongs to the app, including active-reader holds and durable text chapters. */
export class ReaderCacheBudget {
  static touchComicFile(path: string): void { ReaderCacheService.record([path]).catch(() => {}); }
  static noteComicWrite(path?: string): void {
    if (path) ReaderCacheService.record([path]).catch(() => {});
    else ReaderCacheService.reconcile();
  }
}
