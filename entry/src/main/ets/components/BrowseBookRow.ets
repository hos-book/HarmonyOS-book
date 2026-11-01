import { Book } from '../model/Book';
import { SearchResult } from '../model/BookSource';
import { HomeBookRow } from './HomeBookRow';
import { OneShotTransitionCoordinator } from '../utils/OneShotTransition';

/** 分类与发现书单共用行，沿用首页封面转场及简介样式。 */
@ComponentV2
export struct BrowseBookRow {
  @Param @Require book: Book;
  @Event onTap: (id: string) => void = () => {};
  private opening: boolean = false;
  private disposed: boolean = false;

  aboutToAppear(): void { this.disposed = false; }
  aboutToDisappear(): void { this.disposed = true; }

  private result(): SearchResult {
    return {
      name: this.book.title, author: this.book.author, coverUrl: this.book.cover,
      bookUrl: this.book.bookUrl, intro: this.book.intro, kind: this.book.category,
      lastChapter: this.book.latestChapterTitle ?? '', sourceName: this.book.narrator,
      sourceUrl: this.book.sourceUrl, rating: this.book.rating
    };
  }

  private async open(nodeId: string, radius: number): Promise<void> {
    if (this.opening) return;
    this.opening = true;
    const id = this.book.id;
    const coordinator = OneShotTransitionCoordinator.getInstance();
    try {
      await coordinator.captureAsync(this.getUIContext(), id, nodeId, radius);
      if (this.disposed || this.book.id !== id) {
        coordinator.discardPending();
        return;
      }
      this.onTap(id);
    } finally {
      this.opening = false;
    }
  }

  build() {
    HomeBookRow({
      result: this.result(),
      onOpen: (_result: SearchResult, nodeId: string, radius: number): void => {
        this.open(nodeId, radius);
      }
    })
  }
}
