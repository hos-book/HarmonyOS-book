import { Book } from '../model/Book';
import { BookPresentation } from '../model/BookPresentation';
import { SourceCoverUrl } from '../service/rulesource/light/upstream/core/nativesource/SourceCoverUrl';

export class BookCoverPolicy {
  /** 同图的裸地址不能丢掉书源解密和请求头信息，也不能打断已解密缓存的复用。 */
  private static preserveSourceContext(existing: string, incoming: string): string {
    if (SourceCoverUrl.isEncoded(existing) && !SourceCoverUrl.isEncoded(incoming) &&
      existing.split('#')[0] === incoming.split('#')[0]) return existing;
    return incoming;
  }

  static setDetail(book: Book, url: string): void {
    if (BookPresentation.get(book.id)?.cover) { BookPresentation.apply(book); return; }
    // 详情和书架检查只补缺失封面，不因元数据刷新替换已选封面。
    if (book.cover.trim() || !url.trim()) return;
    book.cover = url;
    book.coverFromDetail = true;
    if (book.coverFallback === url) book.coverFallback = undefined;
  }

  /** 只合并同一本、同一书源的封面，不把搜索快照当成详情更新。 */
  static merge(incoming: Book, existing: Book): void {
    if (incoming.id !== existing.id || incoming.sourceUrl !== existing.sourceUrl ||
      incoming.bookUrl !== existing.bookUrl || !existing.cover.trim()) return;
    incoming.cover = BookCoverPolicy.preserveSourceContext(existing.cover, incoming.cover);
    if (!incoming.cover.trim()) {
      incoming.cover = existing.cover;
      incoming.coverFromDetail = existing.coverFromDetail;
      incoming.coverFallback = existing.coverFallback;
    }
  }
}
