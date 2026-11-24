import { common } from '@kit.AbilityKit';
import { LocalRuleSourceType } from '../model/LocalRuleSource';
import { Book, Chapter } from '../model/Book';
import { BookSource, SearchResult } from '../model/BookSource';
import { BookSourceService } from './BookSourceService';
import { BookSourceSwitchResultCache } from './BookSourceSwitchResultCache';
import { SourceDataService } from './SourceDataService';
import { BookIdentity } from '../utils/BookIdentity';
import { ChapterTitleFormatter } from '../utils/ChapterTitleFormatter';
import { LightSourceRequest } from './rulesource/light/LightSourceRequestPolicy';

export class SourceSwitchSearch {
  private stopped: boolean = false;
  private cancelWait: (() => void) | null = null;
  private cancellation: Promise<SearchResult[]>;
  private requests: Set<LightSourceRequest> = new Set();
  private updateTimer: number = -1;

  get cancelled(): boolean { return this.stopped; }
  set cancelled(value: boolean) {
    if (!value || this.stopped) return;
    this.stopped = true;
    for (const request of this.requests) request.cancel();
    if (this.updateTimer !== -1) clearTimeout(this.updateTimer);
    this.updateTimer = -1;
    if (this.cancelWait !== null) this.cancelWait();
  }
  failed: number = 0;
  completed: number = 0;
  total: number = 0;

  private timeoutMs: number;

  constructor(timeoutMs: number = 30000) {
    this.timeoutMs = timeoutMs;
    this.cancellation = new Promise<SearchResult[]>((resolve): void => {
      this.cancelWait = (): void => resolve([]);
    });
  }

  async run(book: Book, update: (books: Book[]) => void, keyword: string = '',
    cacheContext?: common.Context): Promise<void> {
    const query = keyword.trim() || SourceSwitchSearch.searchKeyword(book.title);
    const queryKey = SourceSwitchSearch.titleKey(query);
    const identity = SourceSwitchSearch.cacheIdentity(book);
    const availableTask = SourceDataService.getEnabledSources();
    const cachedTask: Promise<Book[]> = cacheContext === undefined ? Promise.resolve([]) :
      BookSourceSwitchResultCache.load(cacheContext, identity, query);
    const available = await Promise.race([availableTask,
      this.cancellation.then((): BookSource[] => [])]);
    const cachedBooks = await Promise.race([cachedTask, this.cancellation.then((): Book[] => [])]);
    const contentType = book.contentType ?? 'audio';
    const eligibleSources = available.filter((source: BookSource): boolean =>
      source.bookSourceUrl !== book.sourceUrl && (contentType === 'comic' ?
        source.bookSourceType === LocalRuleSourceType.COMIC : contentType === 'text' ?
        source.bookSourceType === LocalRuleSourceType.TEXT || source.bookSourceType === LocalRuleSourceType.WEB_FILE :
        source.bookSourceType === LocalRuleSourceType.AUDIO));
    const eligibleSourceUrls = new Set<string>();
    for (const source of eligibleSources) eligibleSourceUrls.add(source.bookSourceUrl);
    const found: Book[] = [];
    const seen = new Set<string>();
    if (this.cancelled) return;
    const cachedSourceUrls = new Set<string>();
    for (const candidate of cachedBooks) {
      if (!eligibleSourceUrls.has(candidate.sourceUrl) || candidate.contentType !== contentType || !candidate.bookUrl ||
        seen.has(candidate.id)) continue;
      seen.add(candidate.id);
      cachedSourceUrls.add(candidate.sourceUrl);
      found.push(candidate);
    }
    if (found.length > 0) update(found.slice());
    else if (cacheContext === undefined) update([]);
    const sources = eligibleSources.filter((source: BookSource): boolean => !cachedSourceUrls.has(source.bookSourceUrl));
    this.total = sources.length;
    const publish = (): void => {
      if (this.updateTimer !== -1) clearTimeout(this.updateTimer);
      this.updateTimer = -1;
      if (!this.cancelled) update(found.slice());
    };
    let nextIndex = 0;
    const worker = async (): Promise<void> => {
      while (!this.cancelled && nextIndex < sources.length) {
        const source = sources[nextIndex++];
        const request = new LightSourceRequest();
        request.cancelCheck = (): boolean => this.cancelled;
        this.requests.add(request);
        let timer = -1;
        const previousCount = found.length;
        try {
          const timeout = new Promise<SearchResult[]>((_resolve, reject): void => {
            timer = setTimeout((): void => {
              request.cancel();
              reject(new Error('source search timeout'));
            }, this.timeoutMs);
          });
          const results = await Promise.race([BookSourceService.searchBooks(source, query, 1, request), timeout, this.cancellation]);
          if (this.cancelled) return;
          for (const result of results) {
            const kind = result.contentType ?? (source.bookSourceType === LocalRuleSourceType.COMIC ? 'comic' : (source.bookSourceType === LocalRuleSourceType.TEXT ||
              source.bookSourceType === LocalRuleSourceType.WEB_FILE) ? 'text' : 'audio');
            if (kind !== contentType || !result.bookUrl ||
              !SourceSwitchSearch.titleKey(result.name).includes(queryKey)) continue;
            const candidate = SourceSwitchSearch.toBook(result, source, kind);
            if (seen.has(candidate.id)) continue;
            seen.add(candidate.id);
            found.push(candidate);
          }
        } catch (_error) {
          if (!this.cancelled) this.failed++;
        } finally {
          if (timer !== -1) clearTimeout(timer);
          this.requests.delete(request);
          if (!this.cancelled) {
            this.completed++;
            if (this.updateTimer === -1) this.updateTimer = setTimeout(publish, 100);
          }
          if (cacheContext !== undefined && found.length > previousCount) {
            BookSourceSwitchResultCache.save(cacheContext, identity, query, found.slice());
          }
        }
      }
    };
    const tasks: Promise<void>[] = [];
    for (let index = 0; index < Math.min(6, sources.length); index++) tasks.push(worker());
    try { await Promise.all(tasks); }
    finally {
      publish();
      if (cacheContext !== undefined) await BookSourceSwitchResultCache.flush();
    }
  }

  static cacheIdentity(book: Book): string {
    return `${book.contentType ?? 'audio'}\u001f${SourceSwitchSearch.titleKey(book.title)}\u001f${SourceSwitchSearch.titleKey(book.author)}`;
  }

  /** Strip edition labels from the search query; keep the full title in results for confirmation. */
  static searchKeyword(title: string): string {
    const cleaned = title.replace(/[《》]/g, '').replace(/[（(【\[][^）)】\]]*(全集|完结|演播|有声|广播剧|多人|精品|完整版|VIP)[^）)】\]]*[）)】\]]/gi, '')
      .split(/[|｜]/)[0].replace(/\s*[-—·]?\s*(有声小说|有声书|多人演播|多人有声剧|完整版|全集|完结版|完结)\s*$/g, '').trim();
    return cleaned || title.trim();
  }

  static titleKey(title: string): string {
    return title.replace(/[\s《》【】「」“”()（）:：·,，.。!！?？_—-]/g, '').toLowerCase();
  }

  static matchChapter(oldBook: Book, title: string, newBook: Book): number {
    if (!title.trim()) return -1;
    const key = SourceSwitchSearch.titleKey(ChapterTitleFormatter.stripBookPrefix(title, oldBook.title));
    const matches: number[] = [];
    newBook.chapters.forEach((chapter: Chapter, index: number): void => {
      if (SourceSwitchSearch.titleKey(ChapterTitleFormatter.stripBookPrefix(chapter.title, newBook.title)) === key) {
        matches.push(index);
      }
    });
    return matches.length === 1 ? matches[0] : -1;
  }

  static locateChapter(oldBook: Book, title: string, oldIndex: number, newBook: Book): number {
    if (newBook.chapters.length === 0) return -1;
    const matched = SourceSwitchSearch.matchChapter(oldBook, title, newBook);
    if (matched >= 0) return matched;
    return Math.min(Math.max(0, oldIndex), newBook.chapters.length - 1);
  }

  private static toBook(result: SearchResult, source: BookSource, kind: 'audio' | 'text' | 'comic'): Book {
    const sourceUrl = source.bookSourceUrl;
    const book: Book = {
      id: kind === 'comic' ? BookIdentity.onlineComicBookId(sourceUrl, result.bookUrl) : kind === 'text' ? BookIdentity.onlineTextBookId(sourceUrl, result.bookUrl) :
        BookIdentity.onlineAudioBookId(sourceUrl, result.bookUrl),
      contentType: kind, title: result.name, author: result.author, narrator: source.bookSourceName,
      cover: result.coverUrl, category: result.kind, intro: result.intro, totalDuration: 0,
      latestChapterTitle: result.lastChapter,
      chapterCount: 0, rating: result.rating ?? 0, tags: [source.bookSourceName], chapters: [],
      bookUrl: result.bookUrl, sourceUrl, variables: result.variables
    };
    return book;
  }
}

export class SourceSwitchBookDataSource implements IDataSource {
  private books: Book[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.books.length; }
  getData(index: number): Book { return this.books[index]; }
  setBooks(books: Book[]): void {
    const previousCount = this.books.length;
    const appended = books.length >= previousCount && this.books.every((book: Book, index: number): boolean => book.id === books[index].id);
    this.books = books;
    if (appended) {
      for (let index = previousCount; index < books.length; index++) {
        this.listeners.forEach((listener: DataChangeListener): void => listener.onDataAdd(index));
      }
    } else this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
}
