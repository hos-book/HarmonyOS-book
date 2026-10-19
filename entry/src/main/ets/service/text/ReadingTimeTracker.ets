import { Book } from '../../model/Book';
import { GeneralSettings } from '../../model/GeneralSettings';
import { StatsService, BookUsageInput } from '../StatsService';

/** 仅结算前台可见阅读区间；暂停、遮挡和退后台均清空计时基准。 */
export class ReadingTimeTracker {
  private since: number = 0;
  private book: Book | null = null;

  checkpoint(book: Book | null, running: boolean): void {
    if (!GeneralSettings.current.historyEnabled) {
      this.since = 0;
      this.book = null;
      return;
    }
    const now = Date.now();
    const previous = this.book;
    if (this.since > 0 && previous !== null) {
      const seconds = Math.floor(Math.max(0, Math.min(30000, now - this.since)) / 1000);
      this.since += seconds * 1000;
      if (seconds > 0) {
        const input: BookUsageInput = { bookId: previous.id, title: previous.title, author: previous.author,
          cover: previous.cover, sourceUrl: previous.sourceUrl, bookUrl: previous.bookUrl };
        StatsService.addListenSeconds(seconds, input, now).catch((): void => {});
      }
    }
    if (!running || book === null) { this.since = 0; this.book = null; return; }
    if (this.since === 0 || previous?.id !== book.id) this.since = now;
    this.book = book;
  }
}
