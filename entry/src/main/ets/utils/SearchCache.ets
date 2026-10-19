import { Book, Chapter } from '../model/Book';
import { BookCoverPolicy } from './BookCoverPolicy';
import { BookPresentation } from '../model/BookPresentation';

/** 最大缓存条目数，防止内存无限增长 */
const MAX_CACHE_SIZE = 80;

const searchCache: Map<string, Book> = new Map();

export class SearchCache {
  static put(book: Book): void {
    const id = book.id;
    const existing = searchCache.get(id);
    if (existing && existing.chapters.length > 0 && book.chapters.length === 0 && book.tocComplete !== false) {
      book.chapters = existing.chapters;
      book.tocComplete = existing.tocComplete;
      if (book.chapterCount < existing.chapters.length) {
        book.chapterCount = existing.chapters.length;
      }
    }
    if (existing) BookCoverPolicy.merge(book, existing);
    BookPresentation.apply(book);
    // 若已存在先删除，确保重新插入后在 Map 末尾（LRU 顺序）
    if (searchCache.has(id)) {
      searchCache.delete(id);
    }
    searchCache.set(id, book);
    // 超出上限时淘汰最早的条目
    while (searchCache.size > MAX_CACHE_SIZE) {
      const firstKey = searchCache.keys().next();
      if (firstKey.done) break;
      searchCache.delete(firstKey.value as string);
    }
  }

  static get(id: string): Book | null {
    const book = searchCache.get(id);
    if (!book) return null;
    // LRU：命中后移到末尾，延长生命周期
    searchCache.delete(id);
    searchCache.set(id, book);
    return book;
  }

  static remove(id: string): void {
    if (!id) return;
    searchCache.delete(id);
  }

  static clear(): void {
    searchCache.clear();
  }

  static invalidateSources(sourceUrls: Set<string>,
    beforeInvalidate?: (bookId: string, chapters: Chapter[]) => void,
    protectedIds?: Set<string>): string[] {
    const ids: string[] = [];
    for (const book of searchCache.values()) {
      if (!sourceUrls.has(book.sourceUrl)) continue;
      if (beforeInvalidate !== undefined) beforeInvalidate(book.id, book.chapters);
      if (protectedIds === undefined || !protectedIds.has(book.id)) {
        book.chapters = [];
        book.totalDuration = 0;
      }
      book.tocComplete = false;
      book.variables = {};
      ids.push(book.id);
    }
    return ids;
  }

  static size(): number {
    return searchCache.size;
  }
}
