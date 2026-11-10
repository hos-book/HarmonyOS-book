import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { Book, Chapter } from '../../model/Book';
import { ReadingExcerpt, ReadingExcerptBook, ReadingExcerptBookInfo, ReadingExcerptSaveResult } from '../../model/ReadingExcerpt';

const EXCERPT_COLUMNS: string = 'id, book_key, book_id, book_title, author, cover, source_url, book_url, ' +
  'chapter_id, chapter_url, chapter_title, resource_index, start_offset, end_offset, text, created_at';

/** 本机加密摘录库。所有写入等待数据库确认；查询按页读取，不截断或淘汰历史。 */
export class ReadingExcerptService {
  static readonly MAX_TEXT_LENGTH: number = 20000;
  private static opening: Promise<relationalStore.RdbStore> | undefined = undefined;
  private static writing: Promise<void> = Promise.resolve();

  private static async prepare(context: common.Context): Promise<relationalStore.RdbStore> {
    const config: relationalStore.StoreConfig = { name: 'reading_excerpts.db',
      securityLevel: relationalStore.SecurityLevel.S2, encrypt: true, allowRebuild: false };
    const store = await relationalStore.getRdbStore(context, config);
    try {
      await store.executeSql('CREATE TABLE IF NOT EXISTS excerpts (' +
        'id TEXT PRIMARY KEY NOT NULL, book_key TEXT NOT NULL, book_id TEXT NOT NULL, book_title TEXT NOT NULL, ' +
        'author TEXT NOT NULL, cover TEXT NOT NULL, source_url TEXT NOT NULL, book_url TEXT NOT NULL, ' +
        'chapter_id TEXT NOT NULL, chapter_url TEXT NOT NULL, chapter_title TEXT NOT NULL, ' +
        'resource_index INTEGER NOT NULL, start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL, ' +
        'text TEXT NOT NULL, created_at INTEGER NOT NULL, ' +
        'UNIQUE(book_key, chapter_id, chapter_url, resource_index, start_offset, end_offset, text))');
      await store.executeSql('CREATE INDEX IF NOT EXISTS excerpts_book_time ON excerpts (book_key, created_at DESC, id DESC)');
      return store;
    } catch (error) {
      await store.close().catch((): void => {});
      throw new Error(error instanceof Error ? error.message : 'reading_excerpt_storage_error');
    }
  }

  private static async store(context: common.Context): Promise<relationalStore.RdbStore> {
    if (ReadingExcerptService.opening === undefined) {
      ReadingExcerptService.opening = ReadingExcerptService.prepare(context);
    }
    try { return await ReadingExcerptService.opening; }
    catch (error) {
      ReadingExcerptService.opening = undefined;
      throw new Error(error instanceof Error ? error.message : 'reading_excerpt_storage_error');
    }
  }

  static bookKey(book: Book): string {
    return JSON.stringify([book.sourceUrl, book.bookUrl, book.id]);
  }

  static toBook(info: ReadingExcerptBookInfo): Book {
    const book: Book = { id: info.bookId, contentType: 'text', title: info.bookTitle, author: info.author,
      narrator: '', cover: info.cover, category: '', intro: '', totalDuration: 0, chapterCount: 0,
      rating: 0, tags: [], chapters: [], tocComplete: false, bookUrl: info.bookUrl, sourceUrl: info.sourceUrl };
    return book;
  }

  private static validText(value: string, maximum: number): boolean {
    return typeof value === 'string' && value.length <= maximum;
  }

  private static validate(value: ReadingExcerpt): void {
    if (typeof value.text !== 'string' || value.text.length > ReadingExcerptService.MAX_TEXT_LENGTH) {
      throw new Error('reading_excerpt_too_long');
    }
    if (!value.text.trim() || !value.bookId || !value.bookTitle ||
      !ReadingExcerptService.validText(value.bookId, 8192) ||
      !ReadingExcerptService.validText(value.bookTitle, 4096) ||
      !ReadingExcerptService.validText(value.author, 4096) ||
      !ReadingExcerptService.validText(value.cover, 16384) ||
      !ReadingExcerptService.validText(value.sourceUrl, 16384) ||
      !ReadingExcerptService.validText(value.bookUrl, 16384) ||
      !ReadingExcerptService.validText(value.chapterId, 8192) ||
      !ReadingExcerptService.validText(value.chapterUrl, 16384) ||
      !ReadingExcerptService.validText(value.chapterTitle, 4096) ||
      ![value.resourceIndex, value.startOffset, value.endOffset].every((n: number): boolean => Number.isSafeInteger(n) && n >= 0) ||
      value.endOffset <= value.startOffset) throw new Error('reading_excerpt_invalid');
  }

  private static readExcerpt(rows: relationalStore.ResultSet): ReadingExcerpt {
    const value = new ReadingExcerpt();
    value.id = rows.getString(0); value.bookKey = rows.getString(1); value.bookId = rows.getString(2);
    value.bookTitle = rows.getString(3); value.author = rows.getString(4); value.cover = rows.getString(5);
    value.sourceUrl = rows.getString(6); value.bookUrl = rows.getString(7); value.chapterId = rows.getString(8);
    value.chapterUrl = rows.getString(9); value.chapterTitle = rows.getString(10); value.resourceIndex = rows.getLong(11);
    value.startOffset = rows.getLong(12); value.endOffset = rows.getLong(13); value.text = rows.getString(14);
    value.createdAt = rows.getLong(15);
    return value;
  }

  static create(context: common.Context, book: Book, chapter: Chapter, resourceIndex: number,
    startOffset: number, endOffset: number, text: string): Promise<ReadingExcerptSaveResult> {
    const value = new ReadingExcerpt();
    value.id = util.generateRandomUUID(); value.bookKey = ReadingExcerptService.bookKey(book); value.bookId = book.id;
    value.bookTitle = book.title; value.author = book.author; value.cover = book.cover;
    value.sourceUrl = book.sourceUrl; value.bookUrl = book.bookUrl; value.chapterId = chapter.id;
    value.chapterUrl = chapter.originSourceValue || chapter.source.value; value.chapterTitle = chapter.title;
    value.resourceIndex = resourceIndex; value.startOffset = startOffset; value.endOffset = endOffset;
    value.text = text; value.createdAt = Date.now();
    const request = ReadingExcerptService.writing.then(async (): Promise<ReadingExcerptSaveResult> => {
      ReadingExcerptService.validate(value);
      const store = await ReadingExcerptService.store(context);
      await store.executeSql('INSERT OR IGNORE INTO excerpts (' + EXCERPT_COLUMNS + ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [value.id, value.bookKey, value.bookId, value.bookTitle, value.author, value.cover, value.sourceUrl, value.bookUrl,
          value.chapterId, value.chapterUrl, value.chapterTitle, value.resourceIndex, value.startOffset, value.endOffset,
          value.text, value.createdAt]);
      const rows = await store.querySql('SELECT ' + EXCERPT_COLUMNS + ' FROM excerpts WHERE book_key = ? AND ' +
        'chapter_id = ? AND chapter_url = ? AND resource_index = ? AND start_offset = ? AND end_offset = ? AND text = ? LIMIT 1',
        [value.bookKey, value.chapterId, value.chapterUrl, value.resourceIndex, value.startOffset, value.endOffset, value.text]);
      try {
        if (!rows.goToFirstRow()) throw new Error('reading_excerpt_storage_error');
        const result = new ReadingExcerptSaveResult();
        result.excerpt = ReadingExcerptService.readExcerpt(rows);
        result.created = result.excerpt.id === value.id;
        return result;
      } finally { rows.close(); }
    });
    ReadingExcerptService.writing = request.then((): void => {}, (): void => {});
    return request;
  }

  private static checkPage(offset: number, limit: number): void {
    if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 1 || limit > 100) {
      throw new Error('reading_excerpt_invalid');
    }
  }

  static async list(context: common.Context, bookKey: string, offset: number = 0, limit: number = 50): Promise<ReadingExcerpt[]> {
    ReadingExcerptService.checkPage(offset, limit);
    await ReadingExcerptService.writing;
    const store = await ReadingExcerptService.store(context);
    const rows = await store.querySql('SELECT ' + EXCERPT_COLUMNS +
      ' FROM excerpts WHERE book_key = ? ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?', [bookKey, limit, offset]);
    const items: ReadingExcerpt[] = [];
    try {
      while (rows.goToNextRow()) items.push(ReadingExcerptService.readExcerpt(rows));
      return items;
    } finally { rows.close(); }
  }

  static async books(context: common.Context, offset: number = 0, limit: number = 50): Promise<ReadingExcerptBook[]> {
    ReadingExcerptService.checkPage(offset, limit);
    await ReadingExcerptService.writing;
    const store = await ReadingExcerptService.store(context);
    const rows = await store.querySql('SELECT e.book_key, e.book_id, e.book_title, e.author, e.cover, e.source_url, e.book_url, ' +
      'g.item_count, e.created_at, substr(e.text, 1, 240) FROM excerpts e JOIN ' +
      '(SELECT book_key, COUNT(*) AS item_count FROM excerpts GROUP BY book_key) g ON g.book_key = e.book_key ' +
      'WHERE e.id = (SELECT last.id FROM excerpts last WHERE last.book_key = e.book_key ORDER BY last.created_at DESC, last.id DESC LIMIT 1) ' +
      'ORDER BY e.created_at DESC, e.id DESC LIMIT ? OFFSET ?', [limit, offset]);
    const items: ReadingExcerptBook[] = [];
    try {
      while (rows.goToNextRow()) {
        const value = new ReadingExcerptBook();
        value.bookKey = rows.getString(0); value.bookId = rows.getString(1); value.bookTitle = rows.getString(2);
        value.author = rows.getString(3); value.cover = rows.getString(4); value.sourceUrl = rows.getString(5);
        value.bookUrl = rows.getString(6); value.count = rows.getLong(7); value.latestAt = rows.getLong(8);
        value.latestText = rows.getString(9); items.push(value);
      }
      return items;
    } finally { rows.close(); }
  }

  static remove(context: common.Context, id: string): Promise<void> {
    const request = ReadingExcerptService.writing.then(async (): Promise<void> => {
      if (!id || id.length > 128) throw new Error('reading_excerpt_invalid');
      const store = await ReadingExcerptService.store(context);
      await store.executeSql('DELETE FROM excerpts WHERE id = ?', [id]);
    });
    ReadingExcerptService.writing = request.catch((): void => {});
    return request;
  }
}
