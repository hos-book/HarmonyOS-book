import { Book } from './Book';
import { BookPresentation } from './BookPresentation';
import { TextReadingPosition } from './TextReading';
import { PlayHistoryItem } from '../service/PreferenceService';

export class ShelfCollectionRoute {
  group: string;
  constructor(group: string) { this.group = group; }
}

export class ShelfCollectionGroup {
  id: string;
  books: Book[] = [];
  tint: number;
  constructor(id: string, tint: number) { this.id = id; this.tint = tint; }
}

export class ShelfRecentBook {
  book: Book;
  updatedAt: number = 0;
  chapterTitle: string = '';
  chapterIndex: number = -1;
  progress: number = 0;
  constructor(book: Book) { this.book = book; }
}

/** 只派生展示数据，不改写分组、筛选或历史。 */
export class ShelfCollectionData {
  static groups(books: Book[], groups: string[], excluded: Set<string>, keyword: string): ShelfCollectionGroup[] {
    const result: ShelfCollectionGroup[] = groups.map((group: string, index: number): ShelfCollectionGroup =>
      new ShelfCollectionGroup(group, index % 6));
    result.push(new ShelfCollectionGroup(BookPresentation.UNGROUPED, 4));
    const byGroup = new Map<string, ShelfCollectionGroup>();
    for (const group of result) byGroup.set(group.id, group);
    const query = keyword.trim().toLocaleLowerCase();
    for (const book of books) {
      if (excluded.has(book.id)) continue;
      const assigned = BookPresentation.get(book.id)?.group ?? '';
      const group = byGroup.get(assigned) ?? byGroup.get(BookPresentation.UNGROUPED);
      if (!group) continue;
      if (query && !group.id.toLocaleLowerCase().includes(query) &&
        ![book.title, book.author, book.narrator].some((text: string): boolean =>
          (text || '').toLocaleLowerCase().includes(query))) continue;
      group.books.push(book);
    }
    return query ? result.filter((group: ShelfCollectionGroup): boolean =>
      group.books.length > 0 || group.id.toLocaleLowerCase().includes(query)) : result;
  }

  static sameRecent(current: ShelfRecentBook[], next: ShelfRecentBook[]): boolean {
    return current.length === next.length && current.every((item: ShelfRecentBook, index: number): boolean => {
      const other = next[index];
      return item.book.id === other.book.id && item.book.cover === other.book.cover &&
        item.book.title === other.book.title && item.book.author === other.book.author &&
        item.book.contentType === other.book.contentType && item.chapterTitle === other.chapterTitle &&
        item.chapterIndex === other.chapterIndex && Math.floor(item.progress) === Math.floor(other.progress);
    });
  }

  static recent(books: Book[], history: PlayHistoryItem[], positions: TextReadingPosition[]): ShelfRecentBook[] {
    const audio = new Map<string, PlayHistoryItem>();
    for (const item of history) {
      if (item.updatedAt > (audio.get(item.bookId)?.updatedAt ?? 0)) audio.set(item.bookId, item);
    }
    const text = new Map<string, TextReadingPosition>();
    for (const position of positions) text.set(position.bookId, position);
    const seen = new Set<string>();
    const result: ShelfRecentBook[] = [];
    for (const book of books) {
      if (seen.has(book.id)) continue;
      seen.add(book.id);
      const item = new ShelfRecentBook(book);
      const count = book.chapters?.length || book.chapterCount || 0;
      if (book.contentType === 'text' || book.contentType === 'comic') {
        const position = text.get(book.id);
        if (!position || position.updatedAt <= 0) continue;
        item.updatedAt = position.updatedAt;
        item.chapterIndex = position.resourceIndex;
        item.chapterTitle = position.chapterTitle;
        item.progress = count > 0 ? (position.resourceIndex + 1) / count * 100 : 0;
      } else {
        const record = audio.get(book.id);
        if (!record) continue;
        item.updatedAt = record.updatedAt;
        item.chapterTitle = record.chapterTitle ?? '';
        item.chapterIndex = book.chapters?.findIndex((chapter): boolean =>
          chapter.id === record.chapterId || (!!record.chapterTitle && chapter.title === record.chapterTitle)) ?? -1;
        const fraction = (record.durationMs ?? 0) > 0 ? record.progressMs / (record.durationMs ?? 1) : 0;
        item.progress = count > 0 && item.chapterIndex >= 0 ?
          (item.chapterIndex + fraction) / count * 100 : fraction * 100;
      }
      item.progress = Math.min(100, Math.max(0, item.progress));
      result.push(item);
    }
    const latest = result.sort((left: ShelfRecentBook, right: ShelfRecentBook): number =>
      right.updatedAt - left.updatedAt);
    const kinds = new Set<string>();
    return latest.filter((item: ShelfRecentBook): boolean => {
      const kind = item.book.contentType === 'text' || item.book.contentType === 'comic' ? item.book.contentType : 'audio';
      if (kinds.has(kind)) return false;
      kinds.add(kind);
      return true;
    });
  }
}
