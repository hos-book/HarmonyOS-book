import { BookCoverPolicy } from '../utils/BookCoverPolicy';
import { DataService } from './DataService';
/** 用户导入规则源的统一内容门面。 */
import { AudioSource, Book, Chapter } from '../model/Book';
import { BookInfo, BookSource, SearchResult, TocItem } from '../model/BookSource';
import { LocalRuleSource, LocalRuleSourceHealth, LocalRuleSourceStatus } from '../model/LocalRuleSource';
import { TextChapterContent, TextSourceError } from '../model/TextReading';
import { ChapterTitleFormatter } from '../utils/ChapterTitleFormatter';
import { DownloadPolicy } from './DownloadPolicy';
import { LocalRuleContentResult } from './rulesource/LocalRuleRuntimeTypes';
import { LocalRuleDispatcher } from './rulesource/LocalRuleDispatcher';
import { LightSourceRequest } from './rulesource/light/LightSourceRequestPolicy';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';
import { LocalRulePanelService } from './rulesource/LocalRulePanelService';
import { LocalRuleDiagnostics } from './rulesource/LocalRuleDiagnostics';
import { SearchCache } from '../utils/SearchCache';

class BookCatalogLoad {
  book: Book;
  listeners: Array<(book: Book) => void> = [];
  promise: Promise<Book>;
  invalidated: boolean = false;

  constructor(book: Book) {
    this.book = book;
    this.promise = Promise.resolve(book);
  }
}

export interface ExploreFetchResult {
  books: SearchResult[];
  nextUrl: string;
  nextPage?: number;
}

export interface AudioRequestInfo {
  url: string;
  headers: Record<string, string>;
  /** 由导入源明确解析出的地址，允许与无后缀章节直链相同。 */
  resolved?: boolean;
}

const HEALTH_MAX_BOOK_CANDIDATES: number = 3;
const HEALTH_MAX_CHAPTER_CANDIDATES: number = 3;
export class BookSourceService {
  private static audioLoads: Map<string, BookCatalogLoad> = new Map();
  private static textLoads: Map<string, BookCatalogLoad> = new Map();
  private static audioTocRefreshes: Map<string, Promise<TocItem[]>> = new Map();
  private static audioTocRevision: Map<string, number> = new Map();

  static invalidateAudioTocs(sourceUrls: Set<string>): void {
    for (const url of sourceUrls) {
      BookSourceService.audioTocRevision.set(url, (BookSourceService.audioTocRevision.get(url) ?? 0) + 1);
    }
    for (const task of BookSourceService.audioLoads.values()) {
      if (!sourceUrls.has(task.book.sourceUrl)) continue;
      task.invalidated = true;
      BookSourceService.audioLoads.delete(task.book.id);
    }
    for (const task of BookSourceService.textLoads.values()) {
      if (!sourceUrls.has(task.book.sourceUrl)) continue;
      task.invalidated = true;
      BookSourceService.textLoads.delete(task.book.id);
    }
  }

  private static audioTocDefinition(source: LocalRuleSource): string {
    // Invalidate catalogs produced by the removed rule engine even when the source is unchanged.
    return JSON.stringify(['light-source-toc-v1', source.rawSourceJson, source.variable]);
  }

  /** Reimported rules must use fresh chapter requests while retaining saved chapter identities. */
  static async prepareAudioChapter(source: BookSource, book: Book, chapter: Chapter): Promise<void> {
    if (!book.bookUrl) return;
    const localSource = await BookSourceService.resolveLocalSource(source);
    if (localSource === undefined) return;
    const definition = BookSourceService.audioTocDefinition(localSource);
    const revision = BookSourceService.audioTocRevision.get(book.sourceUrl) ?? 0;
    if (book.variables?.['__audioTocDefinition'] === definition &&
      chapter.variables?.['__genericTocFallback'] !== 'true') return;
    const key = `${book.id}:${revision}:${definition}`;
    let pending = BookSourceService.audioTocRefreshes.get(key);
    if (pending === undefined) {
      pending = BookSourceService.fetchCurrentAudioToc(localSource, book).finally((): void => {
        BookSourceService.audioTocRefreshes.delete(key);
      });
      BookSourceService.audioTocRefreshes.set(key, pending);
    }
    const items = await pending;
    if (revision !== (BookSourceService.audioTocRevision.get(book.sourceUrl) ?? 0)) {
      throw new Error('书源已更新，请重试');
    }
    const titleKey = (title: string): string =>
      ChapterTitleFormatter.stripBookPrefix(title, book.title).replace(/\s+/g, '');
    const names = new Map<string, TocItem[]>();
    for (const item of items) {
      const name = titleKey(item.name);
      const matches = names.get(name) ?? [];
      matches.push(item);
      names.set(name, matches);
    }
    const find = (saved: Chapter): TocItem | undefined => {
      const name = titleKey(saved.title);
      const indexed = items[saved.index - 1];
      if (indexed !== undefined && titleKey(indexed.name) === name) return indexed;
      const matches = names.get(name);
      return matches?.length === 1 ? matches[0] : undefined;
    };
    if (find(chapter) === undefined) throw new Error('当前书源目录中找不到该章节，请刷新书籍目录');
    const update = (saved: Chapter): void => {
      const item = find(saved);
      if (item === undefined) return;
      saved.originSourceValue = item.url;
      saved.variables = BookSourceService.copyVariables(item.variables);
      if (saved.source.type === 'url') saved.source = { type: 'url', value: item.url };
    };
    if (book.chapters.length === 0) {
      for (let index = 0; index < items.length; index++) {
        const item = items[index];
        const restored: Chapter = {
          id: `${book.id}-c${index}`, index: index + 1, title: item.name, duration: item.duration || 0,
          source: { type: 'url', value: item.url }, originSourceValue: item.url, variables: item.variables
        };
        book.chapters.push(restored);
      }
      book.chapterCount = items.length;
      book.tocComplete = true;
    }
    for (const saved of book.chapters) update(saved);
    update(chapter);
    book.variables = BookSourceService.copyVariables(book.variables);
    book.variables['__audioTocDefinition'] = definition;
    SearchCache.put(book);
    await DataService.upsertCachedBook(book);
    console.info(`[BookSourceService] refreshed chapter requests ${localSource.bookSourceName}: ${items.length}`);
  }

  private static async fetchCurrentAudioToc(source: LocalRuleSource, book: Book): Promise<TocItem[]> {
    const variables = BookSourceService.copyVariables(book.variables);
    variables['__audioTocDefinition'] = '';
    const info = await BookSourceService.getBookInfo(source, book.bookUrl, variables);
    if (info === null) throw new Error('无法刷新当前书源的书籍信息');
    const scoped = BookSourceService.mergeVariables(variables, info.variables);
    // A batch callback makes incomplete or failed catalogs propagate their error.
    return BookSourceService.getBookToc(source, info.tocUrl || book.bookUrl, scoped, book.title,
      (_items: TocItem[]): void => {});
  }

  static pendingAudioBook(bookId: string): Promise<Book> | undefined {
    return BookSourceService.audioLoads.get(bookId)?.promise;
  }

  /** 目录任务独立于页面生命周期；重进详情复用任务，播放时继续补全同一份章节数组。 */
  static async loadAudioBook(book: Book, onUpdate: (book: Book) => void): Promise<Book> {
    const active = BookSourceService.audioLoads.get(book.id);
    if (active !== undefined) {
      active.listeners.push(onUpdate);
      onUpdate(active.book);
      return active.promise;
    }
    const value = BookSourceService.copyBook(book);
    value.variables = BookSourceService.copyVariables(book.variables);
    value.variables['__audioTocDefinition'] = '';
    value.chapters = [];
    value.tocComplete = false;
    const task = new BookCatalogLoad(value);
    task.listeners.push(onUpdate);
    BookSourceService.audioLoads.set(book.id, task);
    SearchCache.put(value);
    task.promise = BookSourceService.fetchAudioBook(task).finally((): void => {
      task.listeners = [];
      if (BookSourceService.audioLoads.get(book.id) === task) BookSourceService.audioLoads.delete(book.id);
    });
    return task.promise;
  }

  private static notifyAudioBook(task: BookCatalogLoad): void {
    if (task.invalidated) return;
    for (const listener of task.listeners) listener(task.book);
  }

  private static async fetchAudioBook(task: BookCatalogLoad): Promise<Book> {
    const startedAt = Date.now();
    const book = task.book;
    const source = await LocalRuleSourceRepository.getByUrl(book.sourceUrl);
    if (source === undefined) throw new Error('书源已被删除或不可用');
    let info: BookInfo | null = null;
    try { info = await BookSourceService.getBookInfo(source, book.bookUrl, book.variables); }
    catch (_) {
      // Detail and catalog may use independent endpoints. Preserve the selected book's
      // context and let the catalog rule decide whether it can run without fresh metadata.
      console.warn('[BookSourceService] audio detail failed; trying the independent catalog rule');
    }
    let tocUrl = book.variables?.['tocUrl'] || book.bookUrl;
    if (info !== null) {
      tocUrl = info.tocUrl || tocUrl;
      // Audio discovery may use an edition title while detail returns the original novel title.
      // Keep the selected edition's display name; parsed metadata still drives the rule chain.
      if (!book.title.trim() && info.name.trim()) book.title = info.name;
      if (info.author.trim()) book.author = info.author;
      BookCoverPolicy.setDetail(book, info.coverUrl);
      if (info.intro.trim()) book.intro = info.intro;
      else if (['=.=','==', '暂无', '暂无简介', '暂无介绍', '无'].includes(book.intro.replace(/\s+/g, ''))) book.intro = '';
      if (info.kind.trim()) book.category = info.kind;
      if (info.rating !== undefined && info.rating > 0) book.rating = info.rating;
      book.completed = info.completed;
      if (info.wordCount.trim()) book.wordCount = info.wordCount;
      if (info.lastChapter.trim()) book.latestChapterTitle = info.lastChapter;
      if (info.updateTime?.trim()) book.updateTime = info.updateTime;
      book.variables = BookSourceService.mergeVariables(BookSourceService.copyVariables(book.variables), info.variables);
    }
    // 首批章节已使用当前规则生成；起播时不能再为校验规则等待另一轮完整目录。
    book.variables = BookSourceService.copyVariables(book.variables);
    book.variables['__audioTocDefinition'] = BookSourceService.audioTocDefinition(source);
    BookSourceService.notifyAudioBook(task);
    const append = (items: TocItem[]): void => {
      if (task.invalidated) throw new Error('书源已更新，请重试');
      const first = book.chapters.length === 0;
      for (const item of items) {
        const index = book.chapters.length;
        const chapter: Chapter = {
          id: `${book.id}-c${index}`, index: index + 1, title: item.name, duration: item.duration || 0,
          source: { type: 'url', value: item.url }, originSourceValue: item.url, variables: item.variables
        };
        book.chapters.push(chapter);
      }
      book.chapterCount = Math.max(book.chapterCount, book.chapters.length);
      if (first && items.length > 0) {
        console.info(`[BookSourceService] toc first ${source.bookSourceName}: ` +
          `chapters=${book.chapters.length}, elapsedMs=${Date.now() - startedAt}`);
      }
      BookSourceService.notifyAudioBook(task);
    };
    await BookSourceService.getBookToc(source, tocUrl, book.variables, book.title, append);
    if (task.invalidated) throw new Error('书源已更新，请重试');
    if (book.chapters.length === 0) throw new Error('书源未返回有效章节');
    book.tocComplete = true;
    book.variables = BookSourceService.copyVariables(book.variables);
    book.variables['__audioTocDefinition'] = BookSourceService.audioTocDefinition(source);
    SearchCache.put(book);
    BookSourceService.notifyAudioBook(task);
    console.info(`[BookSourceService] toc complete ${source.bookSourceName}: ` +
      `chapters=${book.chapters.length}, elapsedMs=${Date.now() - startedAt}`);
    // 仅完整目录进入现有有界持久缓存，重进详情不再重复解析几千章。
    await DataService.upsertCachedBook(book);
    return book;
  }

  static async prepareAudioSource(_bookSourceUrl: string): Promise<void> {
    return;
  }

  static getAudioResolveTimeoutMs(source: BookSource, fallbackMs: number): number {
    if (source instanceof LocalRuleSource) {
      return Math.max(3000, Math.min(60000, source.respondTime));
    }
    return fallbackMs;
  }

  static async searchBooks(source: BookSource, keyword: string, page: number = 1): Promise<SearchResult[]> {
    if (source instanceof LocalRuleSource && !source.isSearchEnabled()) return [];
    const localSource = await BookSourceService.resolveLocalSource(source);
    return localSource === undefined ? [] : LocalRuleDispatcher.search(localSource, keyword, page);
  }

  static async testLocalSource(source: LocalRuleSource, keyword: string): Promise<LocalRuleSourceHealth> {
    const health = await BookSourceService.testLocalSourceSearchChain(source, keyword);
    return BookSourceService.completeSourceHealth(source, health);
  }

  private static async testLocalSourceSearchChain(source: LocalRuleSource,
    keyword: string): Promise<LocalRuleSourceHealth> {
    const health = new LocalRuleSourceHealth();
    health.sourceUrl = source.bookSourceUrl;
    health.checkedAt = Date.now();
    const startedAt = Date.now();
    if (!source.canExecute()) {
      health.status = LocalRuleSourceStatus.UNSUPPORTED;
      health.message = source.validationMessage || '书源包含当前版本不支持的能力';
      return health;
    }

    const cleanKeyword = keyword.trim();
    if (cleanKeyword.length === 0) {
      health.status = LocalRuleSourceStatus.FAILED;
      health.message = '搜索测试关键词不能为空';
      return health;
    }

    try {
      BookSourceService.requireSearchCapability(source);
      health.message = await BookSourceService.testRuleSource(source, cleanKeyword);
      health.status = LocalRuleSourceStatus.READY;
    } catch (error) {
      health.status = LocalRuleSourceStatus.FAILED;
      health.message = error instanceof Error ? error.message : String(error);
      console.warn(`[BookSourceService] testLocalSource ${source.bookSourceName} failed: ${health.message}`);
    }
    health.responseTimeMs = Date.now() - startedAt;
    return health;
  }

  /** 搜索校验允许无匹配结果；发现/阅读校验必须取得实际内容。 */
  static async testLocalSourceAvailability(source: LocalRuleSource,
    keyword: string, isCancelled: () => boolean = (): boolean => false): Promise<LocalRuleSourceHealth> {
    const health = new LocalRuleSourceHealth();
    health.sourceUrl = source.bookSourceUrl;
    health.checkedAt = Date.now();
    const startedAt = Date.now();
    if (!source.canExecute()) {
      health.status = LocalRuleSourceStatus.UNSUPPORTED;
      health.message = source.validationMessage || '书源包含当前版本不支持的能力';
      return health;
    }

    const cleanKeyword = keyword.trim();
    if (cleanKeyword.length === 0) {
      health.status = LocalRuleSourceStatus.FAILED;
      health.message = '搜索测试关键词不能为空';
      return health;
    }

    try {
      BookSourceService.checkHealthCancellation(isCancelled);
      BookSourceService.requireSearchCapability(source);
      const results = await LocalRuleDispatcher.searchForHealthCheck(source, cleanKeyword, 1);
      health.status = LocalRuleSourceStatus.READY;
      health.message = results.length > 0 ? `搜索正常，共 ${results.length} 条` :
        '搜索请求正常，当前关键词暂无匹配';
    } catch (error) {
      health.status = LocalRuleSourceStatus.FAILED;
      health.message = error instanceof Error ? error.message : String(error);
      console.warn(`[BookSourceService] availability ${source.bookSourceName} failed: ${health.message}`);
    }
    health.responseTimeMs = Date.now() - startedAt;
    return BookSourceService.completeSourceHealth(source, health, isCancelled);
  }

  private static requireSearchCapability(source: LocalRuleSource): void {
    if (!source.hasSearchCapability()) {
      throw new Error('未配置完整搜索规则');
    }
  }

  /** 搜索链路失败只说明该入口不可用；发现取得实际内容后仍可判定部分可用。 */
  private static async completeSourceHealth(source: LocalRuleSource, health: LocalRuleSourceHealth,
    isCancelled: () => boolean = (): boolean => false): Promise<LocalRuleSourceHealth> {
    BookSourceService.checkHealthCancellation(isCancelled);
    if (health.status !== LocalRuleSourceStatus.FAILED || !source.canExecute() ||
      !source.enabledExplore || !source.exploreUrl.trim()) return health;
    const discovery = await BookSourceService.testLocalSourceExploreReading(source, isCancelled);
    BookSourceService.checkHealthCancellation(isCancelled);
    const searchMessage = health.message;
    health.status = discovery.status;
    health.message = discovery.status === LocalRuleSourceStatus.READY
      ? `部分可用：${discovery.message}；搜索链路未通过：${searchMessage}`
      : `搜索链路未通过：${searchMessage}；发现/阅读未通过：${discovery.message}`;
    health.responseTimeMs = Date.now() - health.checkedAt;
    return health;
  }

  private static async testRuleSource(source: LocalRuleSource, keyword: string): Promise<string> {
    const results = await LocalRuleDispatcher.searchForHealthCheck(source, keyword, 1);
    if (results.length === 0) {
      return '搜索请求正常，当前关键词暂无匹配，已保留书源';
    }

    const contentType: 'audio' | 'text' | 'comic' = results[0].contentType ?? (source.isComic() ? 'comic' : source.isAudio() ? 'audio' : 'text');
    await BookSourceService.validateCandidate(source, results[0], contentType);
    const bookName: string = results[0].name;
    return contentType === 'audio'
      ? `搜索、详情、目录与音频解析正常：${bookName}`
      : `搜索、详情、目录与正文解析正常：${bookName}`;
  }

  static async testLocalSourceExploreReading(source: LocalRuleSource,
    isCancelled: () => boolean = (): boolean => false): Promise<LocalRuleSourceHealth> {
    const health = new LocalRuleSourceHealth();
    health.sourceUrl = source.bookSourceUrl;
    health.checkedAt = Date.now();
    const variables = LocalRuleDiagnostics.open((): void => {});
    try {
      if (!source.enabledExplore || !source.exploreUrl.trim()) throw new Error('缺少发现地址或发现未启用');
      if (!source.canExecute()) throw new Error(source.validationMessage || '书源不可执行');
      BookSourceService.checkHealthCancellation(isCancelled);
      const panel = await LocalRulePanelService.load(source, false, variables);
      const entries = panel.entries.filter((entry): boolean => entry.url.trim().length > 0).slice(0, 8);
      if (entries.length === 0) throw new Error('没有解析出发现分类');
      const seen = new Set<string>();
      let lastError = '';
      for (const entry of entries) {
        BookSourceService.checkHealthCancellation(isCancelled);
        try {
          const result = await LocalRuleDispatcher.explore(source, entry.url, 1, variables);
          for (const book of result.books) {
            if (seen.has(book.bookUrl)) continue;
            seen.add(book.bookUrl);
            BookSourceService.checkHealthCancellation(isCancelled);
            try {
              // 验证通过即结束，避免先收集候选而等待其他分类请求。
              await BookSourceService.validateCandidate(source, book,
                source.isAudio() ? 'audio' : 'text', isCancelled, true);
              BookSourceService.checkHealthCancellation(isCancelled);
              health.status = LocalRuleSourceStatus.READY;
              health.message = `发现、详情、目录与${(book.contentType ?? (source.isComic() ? 'comic' : source.isAudio() ? 'audio' : 'text')) === 'audio' ? '音频' : '正文'}解析正常：${book.name}`;
              return health;
            } catch (error) {
              BookSourceService.checkHealthCancellation(isCancelled);
              lastError = error instanceof Error ? error.message : String(error);
            }
            if (seen.size >= 4) break;
          }
        } catch (error) {
          BookSourceService.checkHealthCancellation(isCancelled);
          lastError = error instanceof Error ? error.message : String(error);
        }
        if (seen.size >= 4) break;
      }
      if (seen.size === 0) throw new Error(lastError || '发现分类未返回可验证的书籍');
      throw new Error(lastError || '发现/阅读链路未取得有效内容');
    } catch (error) {
      health.status = LocalRuleSourceStatus.FAILED;
      health.message = error instanceof Error ? error.message : String(error);
      return health;
    } finally {
      health.responseTimeMs = Date.now() - health.checkedAt;
      LocalRuleDiagnostics.close(variables);
    }
  }

  private static checkHealthCancellation(isCancelled: () => boolean): void {
    if (isCancelled()) throw new Error('书源校验已取消');
  }

  private static async validateCandidate(source: LocalRuleSource, result: SearchResult,
    contentType: 'audio' | 'text' | 'comic', isCancelled: () => boolean = (): boolean => false,
    publicOnly: boolean = false): Promise<void> {
    BookSourceService.checkHealthCancellation(isCancelled);
    const searchVariables = BookSourceService.copyVariables(result.variables);
    const info = await BookSourceService.getBookInfo(source, result.bookUrl, searchVariables);
    BookSourceService.checkHealthCancellation(isCancelled);
    if (info === null) throw new Error(`详情解析失败：${result.name}`);

    const variables = BookSourceService.mergeVariables(searchVariables, info.variables);
    const resolvedType = result.contentType ?? contentType;
    variables['__bookContentType'] = resolvedType;
    const tocUrl = info.tocUrl.trim().length > 0 ? info.tocUrl : result.bookUrl;
    const toc = await BookSourceService.getBookToc(source, tocUrl, variables, result.name);
    BookSourceService.checkHealthCancellation(isCancelled);
    if (toc.length === 0) throw new Error(`目录解析失败：${result.name}`);
    const chapters = publicOnly ? toc.filter((chapter: TocItem): boolean =>
      !chapter.isVolume && !chapter.isVip && !chapter.isPay) : toc;
    if (chapters.length === 0) throw new Error('目录正常，但没有可校验的免费章节');
    await BookSourceService.validateChapterCandidates(source, chapters, variables, resolvedType, isCancelled);
  }

  private static async validateChapterCandidates(source: LocalRuleSource, toc: TocItem[],
    variables: Record<string, string>, contentType: 'audio' | 'text' | 'comic',
    isCancelled: () => boolean = (): boolean => false): Promise<void> {
    const candidates = BookSourceService.preferredChapterCandidates(toc);
    let attempted = 0;
    let lastError = '';
    for (const chapter of candidates) {
      BookSourceService.checkHealthCancellation(isCancelled);
      if (attempted >= HEALTH_MAX_CHAPTER_CANDIDATES) break;
      attempted++;
      try {
        if (contentType === 'audio') {
          const request = await BookSourceService.resolveAudioRequest(
            source, chapter.url, variables, chapter.variables);
          if (!DownloadPolicy.isResolvedAudioUrl(chapter.url, request.url, request.resolved)) {
            throw new Error('未解析出可播放的 HTTP 音频地址');
          }
        } else {
          const scopedVariables = BookSourceService.mergeVariables(variables, chapter.variables);
          const content = await LocalRuleDispatcher.resolveContent(source, chapter.url, scopedVariables);
          if (contentType === 'comic') {
            if (content.imageUrls.length === 0) throw new Error('章节漫画图片为空');
          } else if (content.content.trim().length === 0) throw new Error('章节正文为空');
        }
        return;
      } catch (error) {
        lastError = error instanceof Error ? error.message : String(error);
      }
    }
    if (attempted === 0) throw new Error('目录中没有可验证的章节');
    throw new Error(lastError || '章节内容解析失败');
  }

  private static preferredChapterCandidates(toc: TocItem[]): TocItem[] {
    const output: TocItem[] = [];
    const seen = new Set<string>();
    for (const item of toc) {
      if (item.isVolume || item.isPay || item.isVip) continue;
      BookSourceService.appendChapter(output, seen, item);
    }
    for (const item of toc) {
      if (item.isVolume) continue;
      BookSourceService.appendChapter(output, seen, item);
    }
    for (const item of toc) BookSourceService.appendChapter(output, seen, item);
    return output;
  }

  private static appendChapter(output: TocItem[], seen: Set<string>, item: TocItem): void {
    if (item.url.trim().length === 0 || seen.has(item.url)) return;
    seen.add(item.url);
    output.push(item);
  }

  private static hasContentType(results: SearchResult[], contentType: 'audio' | 'text' | 'comic'): boolean {
    for (const result of results) {
      if (result.contentType === contentType) return true;
    }
    return false;
  }

  private static appendUnique(values: string[], value: string): void {
    const clean = value.trim();
    if (clean.length > 0 && !values.includes(clean)) values.push(clean);
  }

  static async getBookInfo(source: BookSource, bookUrl: string,
    _variables?: Record<string, string>): Promise<BookInfo | null> {
    const localSource = await BookSourceService.resolveLocalSource(source);
    return localSource === undefined ? null : LocalRuleDispatcher.getBookInfo(
      localSource, bookUrl, BookSourceService.copyVariables(_variables));
  }

  static async getBookToc(source: BookSource, tocUrl: string,
    _variables?: Record<string, string>, bookName?: string,
    onBatch?: (items: TocItem[]) => void): Promise<TocItem[]> {
    const seen = new Set<string>();
    const unique: TocItem[] = [];
    const append = (batch: TocItem[]): void => {
      const added: TocItem[] = [];
      for (const item of batch) {
        if (!item.url || seen.has(item.url)) continue;
        seen.add(item.url);
        if (bookName) item.name = ChapterTitleFormatter.stripBookPrefix(item.name, bookName);
        unique.push(item);
        added.push(item);
      }
      if (added.length > 0 && onBatch !== undefined) onBatch(added);
    };
    const localSource = await BookSourceService.resolveLocalSource(source);
    const items: TocItem[] = localSource === undefined ? [] : await LocalRuleDispatcher.getBookToc(
      localSource, tocUrl, BookSourceService.copyVariables(_variables), onBatch === undefined ? undefined : append);
    append(items);
    return unique;
  }

  static async getAudioUrl(source: BookSource, chapterUrl: string,
    _variables?: Record<string, string>): Promise<string> {
    const localSource = await BookSourceService.resolveLocalSource(source);
    return localSource === undefined
      ? chapterUrl : LocalRuleDispatcher.getAudioUrl(
        localSource, chapterUrl, BookSourceService.copyVariables(_variables));
  }

  static async resolveAudioRequest(source: BookSource, chapterUrl: string,
    variables?: Record<string, string>, chapterVariables?: Record<string, string>,
    request?: LightSourceRequest): Promise<AudioRequestInfo> {
    const localSource = await BookSourceService.resolveLocalSource(source);
    if (localSource !== undefined) {
      const scopedVariables = BookSourceService.mergeVariables(
        BookSourceService.copyVariables(variables), chapterVariables);
      if (variables !== undefined && variables['__audioSourceVoice'] !== undefined) {
        scopedVariables['custom'] = variables['__audioSourceVoice'];
      }
      const result: LocalRuleContentResult = await LocalRuleDispatcher.resolveContent(
        localSource, chapterUrl, scopedVariables, request);
      const localUrl = result.audioUrl;
      if (!DownloadPolicy.isHttpUrl(localUrl)) throw new Error('书源未返回可播放的音频地址');
      const localHeaders = Object.keys(result.requestHeaders).length > 0
        ? result.requestHeaders : LocalRuleDispatcher.getAudioHeaders(localSource, localUrl);
      return { url: localUrl, headers: localHeaders, resolved: true };
    }
    throw new Error('该内容来源已不可用，请重新导入后重试');
  }

  static async loadTextBook(book: Book, onMetadata?: (book: Book) => void,
    metadataOnly: boolean = false): Promise<Book> {
    if (metadataOnly) return BookSourceService.fetchTextBook(new BookCatalogLoad(BookSourceService.copyBook(book)), true);
    const active = BookSourceService.textLoads.get(book.id);
    if (active !== undefined) {
      if (onMetadata !== undefined) {
        active.listeners.push(onMetadata);
        onMetadata(BookSourceService.copyBook(active.book));
      }
      return active.promise;
    }
    const value = BookSourceService.copyBook(book);
    value.chapters = [];
    value.tocComplete = false;
    const task = new BookCatalogLoad(value);
    if (onMetadata !== undefined) task.listeners.push(onMetadata);
    BookSourceService.textLoads.set(book.id, task);
    SearchCache.put(value);
    task.promise = BookSourceService.fetchTextBook(task).finally((): void => {
      task.listeners = [];
      if (BookSourceService.textLoads.get(book.id) === task) BookSourceService.textLoads.delete(book.id);
    });
    return task.promise;
  }

  static pendingTextBook(bookId: string): Promise<Book> | undefined {
    return BookSourceService.textLoads.get(bookId)?.promise;
  }

  private static notifyTextBook(task: BookCatalogLoad): void {
    if (task.invalidated) return;
    for (const listener of task.listeners) listener(BookSourceService.copyBook(task.book));
  }

  private static async fetchTextBook(task: BookCatalogLoad, metadataOnly: boolean = false): Promise<Book> {
    const book = task.book;
    const localSource = await LocalRuleSourceRepository.getByUrl(book.sourceUrl);
    if (localSource === undefined || (!localSource.isText() && book.contentType !== 'text') ||
      !localSource.canExecute()) {
      throw new TextSourceError('SOURCE_NOT_FOUND', '本地书源不可用或已被删除');
    }

    const variables = BookSourceService.copyVariables(book.variables);
    variables['__bookContentType'] = book.contentType ?? 'text';
    const info = await LocalRuleDispatcher.getBookInfo(localSource, book.bookUrl, variables);
    let tocUrl = book.bookUrl;
    let resolvedVariables = variables;
    if (info !== null) {
      if (info.tocUrl.length > 0) tocUrl = info.tocUrl;
      resolvedVariables = BookSourceService.mergeVariables(variables, info.variables);
    }
    const value = book;
    if (info !== null) {
      if (info.name.length > 0) value.title = info.name;
      if (info.author.length > 0) value.author = info.author;
      BookCoverPolicy.setDetail(value, info.coverUrl);
      if (info.intro.length > 0) value.intro = info.intro;
      if (info.kind.length > 0) value.category = info.kind;
      if (info.rating !== undefined && info.rating > 0) value.rating = info.rating;
      value.completed = info.completed;
      if (info.wordCount.trim()) value.wordCount = info.wordCount;
      if (info.lastChapter.trim()) value.latestChapterTitle = info.lastChapter;
      if (info.updateTime?.trim()) value.updateTime = info.updateTime;
      value.variables = resolvedVariables;
    }
    if (metadataOnly) return value;
    value.variables = resolvedVariables;
    BookSourceService.notifyTextBook(task);
    await BookSourceService.getBookToc(localSource, tocUrl, resolvedVariables, value.title,
      (items: TocItem[]): void => {
        if (task.invalidated) throw new Error('书源已更新，请重试');
        for (const item of items) {
          const index = value.chapters.length;
          const audioSource: AudioSource = { type: 'url', value: item.url };
          const chapter: Chapter = {
            id: `${value.id}-c${index}`, index: index + 1, title: item.name,
            duration: item.duration ?? 0, source: audioSource,
            originSourceValue: item.url, variables: item.variables
          };
          value.chapters.push(chapter);
        }
        value.chapterCount = Math.max(value.chapterCount, value.chapters.length);
        BookSourceService.notifyTextBook(task);
      });
    if (task.invalidated) throw new Error('书源已更新，请重试');
    value.chapterCount = value.chapters.length;
    value.tocComplete = true;
    SearchCache.put(value);
    BookSourceService.notifyTextBook(task);
    await DataService.upsertCachedBook(value);
    return value;
  }

  static async getTextChapterContent(book: Book, chapterUrl: string,
    title: string, chapterVariables?: Record<string, string>): Promise<TextChapterContent> {
    if (book.id.startsWith('import_') && book.contentType === 'text' && book.sourceUrl.length === 0) {
      const content = await DataService.readImportedText(book, chapterUrl);
      return TextChapterContent.of(title, content, chapterUrl);
    }
    const localSource = await LocalRuleSourceRepository.getByUrl(book.sourceUrl);
    if (localSource === undefined || (!localSource.isText() && book.contentType !== 'text') ||
      !localSource.canExecute()) {
      throw new TextSourceError('SOURCE_NOT_FOUND', '本地书源不可用或已被删除');
    }
    const scopedVariables = BookSourceService.mergeVariables(
      BookSourceService.copyVariables(book.variables), chapterVariables);
    scopedVariables['__bookContentType'] = 'text';
    const result = await LocalRuleDispatcher.resolveContent(localSource, chapterUrl, scopedVariables);
    if (result.content.trim().length === 0) {
      throw new TextSourceError('EMPTY_CONTENT', '章节正文为空');
    }
    return TextChapterContent.of(result.title || title, result.content, chapterUrl);
  }

  /** Lossless rule output for media and paragraph actions; existing reader/player contracts remain intact. */
  static async cacheComicImages(book: Book, urls: string[], request?: LightSourceRequest): Promise<string[]> {
    const source = await LocalRuleSourceRepository.getByUrl(book.sourceUrl);
    if (source === undefined || !source.canExecute()) throw new Error('本地书源不可用或已被删除');
    return LocalRuleDispatcher.cacheComicImages(source, urls, request);
  }

  static async getSourceChapterContent(book: Book, chapterUrl: string,
    chapterVariables?: Record<string, string>, request?: LightSourceRequest,
    deferReaderImages: boolean = false): Promise<LocalRuleContentResult> {
    const source = await LocalRuleSourceRepository.getByUrl(book.sourceUrl);
    if (source === undefined || !source.canExecute()) throw new Error('本地书源不可用或已被删除');
    return LocalRuleDispatcher.resolveContent(source,chapterUrl,
      BookSourceService.mergeVariables(BookSourceService.copyVariables(book.variables),chapterVariables), request,
      deferReaderImages);
  }

  static async getExploreBooksByUrl(source: BookSource, categoryUrl: string,
    _page: number = 1, resultLimit: number = 50): Promise<ExploreFetchResult> {
    const localSource = await BookSourceService.resolveLocalSource(source);
    if (localSource !== undefined) {
      const result = await LocalRuleDispatcher.explore(localSource, categoryUrl, _page, {}, resultLimit);
      return { books: result.books, nextUrl: result.nextUrl, nextPage: _page + 1 };
    }
    return { books: [], nextUrl: '' };
  }

  private static async resolveLocalSource(source: BookSource): Promise<LocalRuleSource | undefined> {
    if (source instanceof LocalRuleSource) return source;
    try {
      return await LocalRuleSourceRepository.getByUrl(source.bookSourceUrl);
    } catch (_error) {
      return undefined;
    }
  }

  private static copyVariables(input: Record<string, string> | undefined): Record<string, string> {
    const output: Record<string, string> = {};
    if (input === undefined) return output;
    const keys = Object.keys(input);
    for (const key of keys) output[key] = input[key] ?? '';
    return output;
  }

  private static mergeVariables(left: Record<string, string>,
    right: Record<string, string> | undefined): Record<string, string> {
    const output = BookSourceService.copyVariables(left);
    if (right === undefined) return output;
    const keys = Object.keys(right);
    for (const key of keys) output[key] = right[key] ?? '';
    return output;
  }

  private static copyBook(book: Book): Book {
    const value: Book = {
      id: book.id,
      contentType: book.contentType,
      title: book.title,
      author: book.author,
      narrator: book.narrator,
      cover: book.cover,
      coverFromDetail: book.coverFromDetail,
      coverFallback: book.coverFallback,
      category: book.category,
      intro: book.intro,
      wordCount: book.wordCount,
      latestChapterTitle: book.latestChapterTitle,
      updateTime: book.updateTime,
      totalDuration: book.totalDuration,
      chapterCount: book.chapterCount,
      rating: book.rating,
      tags: book.tags.slice(),
      chapters: book.chapters.slice(),
      tocComplete: book.tocComplete,
      bookUrl: book.bookUrl,
      sourceUrl: book.sourceUrl,
      variables: book.variables,
      skipIntro: book.skipIntro,
      skipOutro: book.skipOutro,
      chaptersDescending: book.chaptersDescending,
      completed: book.completed
    };
    return value;
  }
}
