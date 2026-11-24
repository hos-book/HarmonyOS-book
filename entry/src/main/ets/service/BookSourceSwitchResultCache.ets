import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Book } from '../model/Book';

export class BookSourceSwitchCacheSnapshot {
  keyword: string = '';
  books: Book[] = [];
}

export class BookSourceSwitchResultCache {
  private static readonly STORE_NAME: string = 'book_source_switch_results_v1';
  private static writeQueue: Promise<void> = Promise.resolve();

  static searchKey(identity: string, keyword: string): string {
    return `${identity}\u001f${BookSourceSwitchResultCache.normalizeKeyword(keyword)}`;
  }

  static async load(context: common.Context, identity: string, keyword: string): Promise<Book[]> {
    try {
      await BookSourceSwitchResultCache.writeQueue;
      const store = await preferences.getPreferences(context, { name: BookSourceSwitchResultCache.STORE_NAME });
      const raw = await store.get(BookSourceSwitchResultCache.storageKey(identity), '');
      if (typeof raw !== 'string' || raw.length === 0) return [];
      const snapshot: BookSourceSwitchCacheSnapshot = JSON.parse(raw);
      if (snapshot.keyword !== BookSourceSwitchResultCache.normalizeKeyword(keyword) ||
        !Array.isArray(snapshot.books)) return [];
      return snapshot.books;
    } catch (error) {
      console.warn('[BookSourceSwitchResultCache] load failed:', error);
      return [];
    }
  }

  static save(context: common.Context, identity: string, keyword: string, books: Book[]): Promise<void> {
    const snapshot = new BookSourceSwitchCacheSnapshot();
    snapshot.keyword = BookSourceSwitchResultCache.normalizeKeyword(keyword);
    snapshot.books = books;
    const raw = JSON.stringify(snapshot);
    const write = BookSourceSwitchResultCache.writeQueue.then(async (): Promise<void> => {
      try {
        const store = await preferences.getPreferences(context, { name: BookSourceSwitchResultCache.STORE_NAME });
        await store.put(BookSourceSwitchResultCache.storageKey(identity), raw);
        await store.flush();
      } catch (error) {
        console.warn('[BookSourceSwitchResultCache] save failed:', error);
      }
    });
    BookSourceSwitchResultCache.writeQueue = write;
    return BookSourceSwitchResultCache.writeQueue;
  }

  static flush(): Promise<void> {
    return BookSourceSwitchResultCache.writeQueue;
  }

  private static storageKey(identity: string): string {
    return `results_${JSON.stringify(identity)}`;
  }

  private static normalizeKeyword(keyword: string): string {
    return keyword.trim().replace(/\s+/g, ' ').toLowerCase();
  }
}
