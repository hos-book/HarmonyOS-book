import { Book } from '../model/Book';
import { BookPresentation } from '../model/BookPresentation';

export class BookCoverPolicy {
  static setDetail(book: Book, url: string): void {
    if (BookPresentation.get(book.id)?.cover) { BookPresentation.apply(book); return; }
    if (!url.trim()) return;
    if (!book.coverFromDetail && book.cover && book.cover !== url) book.coverFallback = book.cover;
    book.cover = url;
    book.coverFromDetail = true;
    if (book.coverFallback === url) book.coverFallback = undefined;
  }

  /** 只合并同一本、同一书源的封面，不把搜索快照当成详情更新。 */
  static merge(incoming: Book, existing: Book): void {
    if (incoming.id !== existing.id || incoming.sourceUrl !== existing.sourceUrl ||
      incoming.bookUrl !== existing.bookUrl || !existing.cover.trim()) return;
    // Fresh imported audio discovery carries the selected edition's cover. Older detail
    // caches may contain the novel cover from before the upstream Book context was bridged.
    if (incoming.contentType === 'audio' && incoming.variables?.['__lightBook'] &&
      incoming.cover.trim() && incoming.cover !== existing.cover) return;
    if (!incoming.cover.trim() || (existing.coverFromDetail === true && incoming.coverFromDetail !== true)) {
      const thumbnail = incoming.cover;
      incoming.cover = existing.cover;
      incoming.coverFromDetail = existing.coverFromDetail;
      incoming.coverFallback = thumbnail && thumbnail !== existing.cover ? thumbnail : existing.coverFallback;
    } else if (incoming.coverFromDetail && !incoming.coverFallback && existing.cover !== incoming.cover) {
      incoming.coverFallback = existing.coverFromDetail ? existing.coverFallback : existing.cover;
    }
  }
}
