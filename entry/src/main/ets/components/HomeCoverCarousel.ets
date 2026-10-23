import { SearchResult } from '../model/BookSource';
import { BookMetadataPolicy } from '../utils/BookMetadataPolicy';
import { BOOK_COVER_ASPECT_RATIO } from '../utils/CoverAspectRatio';
import { BookPosterCarousel, BookPosterItem, BOOK_POSTER_HEIGHT } from './BookPosterCarousel';

/** 与全网榜单共用轮播尺寸，导航与骨架保持完整高度。 */
export function homeCoverCarouselHeight(): number { return BOOK_POSTER_HEIGHT; }

@ComponentV2
export struct HomeCoverCarousel {
  @Param books: SearchResult[] = [];
  @Param active: boolean = true;
  @Event onBookTap: (book: SearchResult, nodeId: string, radius: number) => void = () => {};
  @Event onCoverChange: (cover: string) => void = () => {};
  @Local inViewport: boolean = false;

  @Computed
  get posterItems(): BookPosterItem[] {
    return this.books.map((book: SearchResult): BookPosterItem => new BookPosterItem(
      book.sourceUrl + '#' + book.bookUrl, book.name, book.author, book.intro, book.coverUrl,
      BOOK_COVER_ASPECT_RATIO, BookMetadataPolicy.rating(book.rating, book.kind)));
  }

  build() {
    BookPosterCarousel({
      items: this.posterItems,
      autoPlay: this.active && this.inViewport,
      openCover: true,
      useOriginalCoverRatio: true,
      onCoverChange: (cover: string): void => this.onCoverChange(cover),
      onChoose: (item: BookPosterItem, nodeId: string, radius: number): void => {
        const book = this.books.find((entry: SearchResult): boolean =>
          entry.sourceUrl + '#' + entry.bookUrl === item.id);
        if (book !== undefined) this.onBookTap(book, nodeId, radius);
      }
    })
      .onVisibleAreaChange([0, 0.5, 1], (visible: boolean, ratio: number): void => {
        this.inViewport = visible && ratio >= 0.5;
      })
  }
}
