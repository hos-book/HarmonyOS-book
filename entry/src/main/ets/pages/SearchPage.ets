import { BookCoverPolicy } from '../utils/BookCoverPolicy';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { HdsCompat } from '../utils/HdsCompat';
import { CompatibleGridInsets, PlatformCompat } from '../utils/PlatformCompat';
import { ImmersiveTabComponent } from '../components/ImmersiveTabComponent';
import {
  HdsNavDestination, HdsNavDestinationTitleMode, HideMode, BottomBuilderParams, BuilderOptions, TitleBarContentOptions
} from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppColor, AppCurve, AppFont, AppMaterial, AppMotion, AppRadius, AppSpace, HomeTheme } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { BookSource, HomeBlockSection, SearchResult } from '../model/BookSource';
import { LocalRuleSource, LocalRuleSourceStatus } from '../model/LocalRuleSource';
import { BookSourceService } from '../service/BookSourceService';
import { SourceDataService } from '../service/SourceDataService';
import { SearchCache } from '../utils/SearchCache';
import { SearchOptions } from '../utils/SearchOptions';
import { BookCard } from '../components/BookCard';
import { CoverImage } from '../components/CoverImage';
import { BookDataSource } from '../utils/BookDataSource';
import { BookIdentity } from '../utils/BookIdentity';
import { CoverPrefetcher } from '../service/CoverPrefetcher';
import { PlaybackStore } from '../service/PlaybackStore';
import { WindowUtils } from '../utils/WindowUtils';
import { PreferenceService } from '../service/PreferenceService';
import { HomeSourceContent, HomeSourceService } from '../service/rulesource/HomeSourceService';

const DOMAIN = 0x0000;
const TAG = 'SearchPage';
const LOCAL_RULE_COVER_CONCURRENCY: number = 3;
const LOCAL_RULE_COVER_LIMIT: number = 12;
const SEARCH_COVER_ASPECT_RATIO: number = 0.75;
const SEARCH_HEADER_HEIGHT: number = 56;
const SEARCH_TITLE_CONTROL_HEIGHT: number = 44;
const RESULT_TOOLBAR_HEIGHT: number = 48;
const HISTORY_HEADING_HEIGHT: number = 52;
// onShown 在当前导航中先于系统滑入动画触发；450ms 转场期间不读取整份书源或执行推荐规则。
const SEARCH_ENTRY_SETTLE_MS: number = 500;
const SEARCH_RECOMMENDATION_COUNT: number = 5;
const SEARCH_RECOMMENDATION_SOURCE_LIMIT: number = 6;
const SEARCH_RECOMMENDATION_CONCURRENCY: number = 3;
const SEARCH_RECOMMENDATION_KEYWORDS: string[] = [
  '斗破苍穹', '三体', '凡人修仙传', '诡秘之主', '红楼梦', '盗墓笔记', '西游记', '庆余年'
];

@ComponentV2
struct SearchOptionItem {
  @Param label: Resource = $r('app.string.search_exact');
  @Param selected: boolean = false;
  @Event onToggle: () => void = (): void => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: AppSpace.Sm }) {
        Text(this.label)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([AppColor.Brand])
          .visibility(this.selected ? Visibility.Visible : Visibility.Hidden)
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Sm, bottom: AppSpace.Sm })
    .borderRadius(AppRadius.Sm)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.label)
    .accessibilityChecked(this.selected)
    .onClick(() => this.onToggle())
  }
}

@ComponentV2
export struct SearchPage {
  @Local bookColumns: number = 3;
  @Param navStack: NavPathStack = new NavPathStack();
  /** 从详情页分类标签进入时预填并直接检索的关键词；为空表示普通进入。 */
  @Param initialKeyword: string = '';

  @Local keyword: string = '';
  @Local exactSearch: boolean = false;
  @Local searchByAuthor: boolean = false;
  @Local searchTextOnly: boolean = false;
  @Local searchAudioOnly: boolean = false;
  @Local searchOptionsVisible: boolean = false;
  @Local historyWidth: number = 0;
  private historyWrite: Promise<void> = Promise.resolve();
  @Local searching: boolean = false;
  @Local searchedSourceCount: number = 0;
  @Local searchSourceTotal: number = 0;
  @Local hasSearched: boolean = false;
  @Local searchTab: number = 0;
  @Local viewMode: number = 0;
  @Local audioBooks: Book[] = [];
  @Local textBooks: Book[] = [];
  @Local comicBooks: Book[] = [];
  @Local audioCount: number = 0;
  @Local textCount: number = 0;
  @Local visibleResultCount: number = 0;
  @Local searchHistory: string[] = [];
  @Local historyTagsHeight: number = 84;
  @Local historyCollapseOffset: number = 0;
  @Local searchCollapseOffset: number = 0;
  @Local recommendationBooks: Book[] = [];
  @Local recommendationsLoading: boolean = true;

  @Local sourcePickerVisible: boolean = false;
  @Local sourceFilterEnabled: boolean = false;
  @Local selectedSourceUrls: string[] = [];
  @Local availableSearchSources: BookSource[] = [];
  @Local resultGroupVisible: boolean = false;
  @Local resultGroups: Map<string, Book[]> = new Map();
  private groupedBooks: BookDataSource = new BookDataSource();
  private resultsRefreshTimer: number = -1;
  private resultDataSource: BookDataSource = new BookDataSource();
  private searchController: SearchController = new SearchController();
  private resultScroller: Scroller = new Scroller();
  private recommendationScroller: Scroller = new Scroller();
  private searchGen: number = 0;
  private recommendationGen: number = 0;
  private recommendationTimerId: number = -1;
  private pageShown: boolean = false;
  private recommendationsStarted: boolean = false;
  private recommendationsLoaded: boolean = false;
  private leavingPage: boolean = false;
  private readonly searchTitleBarBuilder: CustomBuilder = (): void => this.buildSearchTitleBar();

  @Computed
  get searchTitleBarContent(): TitleBarContentOptions {
    const bottom: BottomBuilderParams = {
      // 历史从空态加载、切换结果工具栏时，必须让 HDS 重建并恢复自定义区可见性。
      builder: (): void => this.buildSearchNavigationBottom(),
      height: this.hasSearched ? RESULT_TOOLBAR_HEIGHT : this.historyPanelHeight
    };
    const content: TitleBarContentOptions = {
      title: { mainTitle: '' },
      stackBuilder: this.searchTitleBarBuilder,
      bottomBuilder: bottom
    };
    if (PlatformCompat.supports(26)) {
      // 仅保留输入框；bottomBuilder 初始高度为 0，不能冻结其透明代理节点。
      const titleBuilder: BuilderOptions = { builder: this.searchTitleBarBuilder, updated: false };
      content.stackBuilderContent = titleBuilder;
    }
    return content;
  }

  @Computed
  get historyPanelHeight(): number {
    if (this.searchHistory.length === 0) return 0;
    return this.historyTagsHeight + HISTORY_HEADING_HEIGHT - this.historyCollapseOffset + AppSpace.Xs;
  }

  private syncHistoryCollapse(): void {
    const offset: number = Math.max(0, Math.min(HISTORY_HEADING_HEIGHT,
      this.recommendationScroller.currentOffset().yOffset));
    if (Math.abs(offset - this.historyCollapseOffset) > 0.5) {
      this.historyCollapseOffset = offset;
    }
  }

  private syncSearchCollapse(): void {
    this.searchCollapseOffset = Math.max(0, Math.min(SEARCH_HEADER_HEIGHT,
      this.resultScroller.currentOffset().yOffset));
  }

  aboutToAppear(): void {
    WindowUtils.setStatusBarLight(false);
    CoverPrefetcher.init();
    BookCard.resetAnimations();
    this.loadSearchHistory();
  }

  aboutToDisappear(): void {
    this.stopPendingSearchUpdates();
  }

  private stopPendingSearchUpdates(): void {
    if (this.leavingPage) return;
    this.leavingPage = true;
    this.pageShown = false;
    this.searchGen++;
    if (this.resultsRefreshTimer >= 0) clearTimeout(this.resultsRefreshTimer);
    this.resultsRefreshTimer = -1;
    this.cancelRecommendations();
  }

  private handlePageShown(): void {
    if (this.leavingPage) return;
    this.pageShown = true;
    if (this.applyInitialKeyword()) return;
    this.scheduleRecommendations();
  }

  /**
   * 详情页分类标签进入：预填关键词并直接检索，替代展示推荐位。
   * 返回 true 表示已接管首屏，不再调度推荐。
   */
  private applyInitialKeyword(): boolean {
    const value = this.initialKeyword.trim();
    if (value.length === 0 || this.hasSearched) return false;
    this.keyword = value;
    this.recommendationsLoaded = true;
    this.recommendationsLoading = false;
    this.recommendationTimerId = setTimeout((): void => {
      this.recommendationTimerId = -1;
      if (this.leavingPage || this.hasSearched) return;
      this.doSearch().catch((): void => {});
    }, SEARCH_ENTRY_SETTLE_MS);
    return true;
  }

  private handlePageHidden(): void {
    this.searchOptionsVisible = false;
    this.pageShown = false;
    this.cancelRecommendations();
    this.searchController.stopEditing();
  }

  private async loadSearchHistory(): Promise<void> {
    try {
      const history = await PreferenceService.getSearchHistory();
      if (!this.leavingPage) {
        this.searchHistory = history;
        this.trimHistory();
        this.exactSearch = await PreferenceService.getSearchExact();
        this.searchByAuthor = await PreferenceService.getSearchByAuthor();
        this.searchTextOnly = await PreferenceService.getSearchTextOnly();
        this.searchAudioOnly = await PreferenceService.getSearchAudioOnly();
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load search history failed: %{public}s', String(e));
    }
  }

  private scheduleRecommendations(): void {
    if (!this.pageShown || this.leavingPage || this.hasSearched || this.recommendationsLoaded ||
      this.recommendationsStarted || this.recommendationTimerId >= 0) return;
    this.recommendationTimerId = setTimeout((): void => {
      this.recommendationTimerId = -1;
      if (!this.pageShown || this.leavingPage || this.hasSearched) return;
      this.loadRecommendations();
    }, SEARCH_ENTRY_SETTLE_MS);
  }

  private cancelRecommendations(): void {
    if (this.recommendationTimerId >= 0) {
      clearTimeout(this.recommendationTimerId);
      this.recommendationTimerId = -1;
    }
    this.recommendationGen++;
    this.recommendationsStarted = false;
  }

  private clearSearch(): void {
    this.searchCollapseOffset = 0;
    this.searchGen++;
    this.searching = false;
    this.searchedSourceCount = 0;
    this.searchSourceTotal = 0;
    this.hasSearched = false;
    this.searchTab = 0;
    this.audioBooks = [];
    this.textBooks = [];
    this.comicBooks = [];
    this.audioCount = 0;
    this.textCount = 0;
    this.visibleResultCount = 0;
    this.resultDataSource.clear();
    this.scheduleRecommendations();
  }

  private submitHistoryKeyword(keyword: string): void {
    this.keyword = keyword;
    this.doSearch();
  }

  private async clearAllHistory(): Promise<void> {
    try {
      this.searchHistory = [];
      this.persistHistory();
      await this.historyWrite;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'clear search history failed: %{public}s', String(e));
    }
  }

  private historyItemWidth(keyword: string): number {
    const size = this.getUIContext().getMeasureUtils().measureTextSize({ textContent: keyword, fontSize: 13 });
    const measured = this.getUIContext().px2vp(Number(size.width));
    return Math.min(Math.max(1, this.historyWidth - AppSpace.Xs), 176, Math.ceil(measured) + 24);
  }

  private trimHistory(): void {
    if (this.historyWidth <= 0) return;
    const widths = this.searchHistory.map((keyword: string): number => this.historyItemWidth(keyword));
    const count = SearchOptions.visibleCount(widths, this.historyWidth - AppSpace.Xs, AppSpace.Xs);
    if (count < this.searchHistory.length) {
      this.searchHistory = this.searchHistory.slice(0, count);
      this.persistHistory();
    }
  }

  private persistHistory(): void {
    const snapshot = this.searchHistory.slice();
    this.historyWrite = this.historyWrite.then((): Promise<void> => PreferenceService.setSearchHistory(snapshot))
      .catch((error: Error): void => { hilog.warn(DOMAIN, TAG, 'save history: %{public}s', error.message); });
  }

  private updateSearchOptions(): void {
    PreferenceService.setSearchOptions(this.exactSearch, this.searchByAuthor,
      this.searchTextOnly, this.searchAudioOnly).catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'save search options: %{public}s', error.message);
    });
    if (this.hasSearched) this.doSearch();
  }

  private async loadRecommendations(): Promise<void> {
    this.recommendationsStarted = true;
    this.recommendationGen++;
    const generation = this.recommendationGen;
    this.recommendationsLoading = true;
    try {
      const sources = await SourceDataService.getEnabledSources();
      if (generation !== this.recommendationGen) return;
      const orderedSources = this.shuffleSources(sources);
      const books: Book[] = [];
      const seen = new Set<string>();
      // 返回页面后继续补齐，已展示的推荐不清空、不重新洗牌。
      for (const book of this.recommendationBooks) this.appendRecommendationBook(book, books, seen);

      for (const source of orderedSources) {
        if (!(source instanceof LocalRuleSource) || !HomeSourceService.isEligible(source)) continue;
        try {
          const content = await HomeSourceService.loadHome(source, false,
            (partial: HomeSourceContent): void => {
              if (generation !== this.recommendationGen) return;
              this.appendHomeRecommendationBooks(source, partial.blocks, books, seen);
              this.publishRecommendationBooks(books, generation);
            });
          if (generation !== this.recommendationGen) return;
          this.appendHomeRecommendationBooks(source, content.blocks, books, seen);
          this.publishRecommendationBooks(books, generation);
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'load source home recommendations failed: %{public}s', String(error));
        }
        break;
      }

      if (books.length < SEARCH_RECOMMENDATION_COUNT) {
        await this.appendSearchRecommendationBooks(orderedSources, books, seen, generation);
      }
      if (generation !== this.recommendationGen) return;
      this.publishRecommendationBooks(books, generation);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'load recommendations failed: %{public}s', String(error));
    } finally {
      if (generation === this.recommendationGen) {
        this.recommendationsStarted = false;
        this.recommendationsLoaded = true;
        this.recommendationsLoading = false;
      }
    }
  }

  private shuffleSources(sources: BookSource[]): BookSource[] {
    const shuffled = sources.slice();
    for (let index = shuffled.length - 1; index > 0; index--) {
      const randomIndex = Math.floor(Math.random() * (index + 1));
      const current = shuffled[index];
      shuffled[index] = shuffled[randomIndex];
      shuffled[randomIndex] = current;
    }
    return shuffled;
  }

  private appendHomeRecommendationBooks(source: BookSource, blocks: HomeBlockSection[],
    books: Book[], seen: Set<string>): void {
    const fallbackType: 'audio' | 'text' | 'comic' = source.bookSourceType === 0 || source.bookSourceType === 3
      ? 'text' : source.bookSourceType === 2 ? 'comic' : 'audio';
    for (const block of blocks) {
      for (const result of block.books) {
        const book = this.searchResultToBook(result, result.contentType ?? fallbackType);
        this.appendRecommendationBook(book, books, seen);
      }
    }
  }

  private async appendSearchRecommendationBooks(sources: BookSource[], books: Book[], seen: Set<string>,
    generation: number): Promise<void> {
    const readySources: BookSource[] = [];
    for (const source of sources) {
      if (source instanceof LocalRuleSource && source.validationStatus === LocalRuleSourceStatus.READY) {
        readySources.push(source);
      }
    }
    const sourcePool = readySources.length > 0 ? readySources : sources;
    const candidates: BookSource[] = [];
    for (const source of sourcePool) {
      candidates.push(source);
      if (candidates.length >= SEARCH_RECOMMENDATION_SOURCE_LIMIT) break;
    }
    let nextIndex: number = 0;
    const worker = async (): Promise<void> => {
      while (generation === this.recommendationGen && books.length < SEARCH_RECOMMENDATION_COUNT &&
        nextIndex < candidates.length) {
        const source = candidates[nextIndex++];
        const keywordIndex = Math.floor(Math.random() * SEARCH_RECOMMENDATION_KEYWORDS.length);
        const batch = await this.loadSourceRecommendationBooks(source,
          SEARCH_RECOMMENDATION_KEYWORDS[keywordIndex]);
        if (generation !== this.recommendationGen) return;
        for (const book of batch) this.appendRecommendationBook(book, books, seen);
        this.publishRecommendationBooks(books, generation);
      }
    };
    const tasks: Promise<void>[] = [];
    for (let index = 0; index < Math.min(SEARCH_RECOMMENDATION_CONCURRENCY, candidates.length); index++) {
      tasks.push(worker());
    }
    await Promise.all(tasks);
  }

  private async loadSourceRecommendationBooks(source: BookSource, keyword: string): Promise<Book[]> {
    try {
      const results = await BookSourceService.searchBooks(source, keyword);
      const fallbackType: 'audio' | 'text' | 'comic' = source.bookSourceType === 0 || source.bookSourceType === 3
        ? 'text' : source.bookSourceType === 2 ? 'comic' : 'audio';
      const books: Book[] = [];
      for (const result of results) {
        books.push(this.searchResultToBook(result, result.contentType ?? fallbackType));
      }
      return books;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'recommendation source failed [%{public}s]: %{public}s',
        source.bookSourceName, String(error));
      return [];
    }
  }

  private appendRecommendationBook(book: Book, books: Book[], seen: Set<string>): void {
    if (books.length >= SEARCH_RECOMMENDATION_COUNT) return;
    const key = `${book.sourceUrl}\u001f${book.bookUrl}`;
    if (book.title.trim().length === 0 || book.bookUrl.trim().length === 0 || seen.has(key)) return;
    seen.add(key);
    books.push(book);
  }

  private publishRecommendationBooks(books: Book[], generation: number): void {
    if (generation !== this.recommendationGen || books.length <= this.recommendationBooks.length) return;
    const appended = books.slice(this.recommendationBooks.length);
    this.recommendationBooks = books.slice();
    this.prefetchCovers(appended);
    if (books.length >= SEARCH_RECOMMENDATION_COUNT) {
      this.recommendationsLoaded = true;
      this.recommendationsLoading = false;
    }
  }

  private async doSearch(): Promise<void> {
    if (this.leavingPage) return;
    const keyword = this.keyword.trim();
    if (!keyword) {
      this.clearSearch();
      return;
    }
    this.keyword = keyword;
    this.cancelRecommendations();
    this.searchHistory = [keyword].concat(this.searchHistory.filter((item: string): boolean => item !== keyword));
    this.trimHistory();
    this.persistHistory();
    this.searchGen++;
    const gen = this.searchGen;
    this.searching = true;
    this.searchedSourceCount = 0;
    this.searchSourceTotal = 0;
    this.searchCollapseOffset = 0;
    this.hasSearched = true;
    this.searchTab = 0;
    this.audioBooks = [];
    this.textBooks = [];
    this.comicBooks = [];
    this.audioCount = 0;
    this.textCount = 0;
    this.visibleResultCount = 0;
    this.resultDataSource.clear();
    try {
      this.resultScroller.scrollEdge(Edge.Top);
    } catch (_e) {
      // 数据源切换期间滚动容器可能尚未完成布局。
    }
    BookCard.resetAnimations();
    try {
      const sources = await SourceDataService.getEnabledSources();
      if (gen !== this.searchGen) return;
      const selectedSources = sources.filter((source: BookSource): boolean =>
        SearchOptions.matchesSourceType(source.bookSourceType, this.searchTextOnly, this.searchAudioOnly) &&
        (!this.sourceFilterEnabled || this.selectedSourceUrls.includes(source.bookSourceUrl)));
      this.searchSourceTotal = selectedSources.length;
      const concurrency = await PreferenceService.getSearchConcurrency();
      if (gen !== this.searchGen) return;
      hilog.info(DOMAIN, TAG, 'search schedule concurrency=%{public}d sources=%{public}d generation=%{public}d',
        concurrency, selectedSources.length, gen);
      const seen = new Set<string>();
      await this.searchSources(selectedSources, keyword, gen, seen, concurrency);
      if (gen !== this.searchGen) return;
      this.audioCount = this.audioBooks.length;
      this.textCount = this.textBooks.length;
      this.refreshVisibleBooks();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'search failed: %{public}s', String(e));
    } finally {
      if (gen === this.searchGen) this.searching = false;
    }
  }

  private async searchSources(sources: BookSource[], keyword: string, gen: number,
    seen: Set<string>, concurrency: number): Promise<void> {
    let nextIndex: number = 0;
    const nextSource = (): BookSource | undefined => {
      if (gen !== this.searchGen || nextIndex >= sources.length) return undefined;
      return sources[nextIndex++];
    };
    const tasks: Promise<void>[] = [];
    for (let index = 0; index < Math.min(concurrency, sources.length); index++) {
      tasks.push(this.searchSourceQueue(nextSource, keyword, gen, seen));
    }
    await Promise.all(tasks);
  }

  private async searchSourceQueue(nextSource: () => BookSource | undefined, keyword: string,
    gen: number, seen: Set<string>): Promise<void> {
    // 空闲位置立即接续下一个书源，不等待同批其他慢源。
    let source = nextSource();
    while (source !== undefined) {
      await this.searchOneSource(source, keyword, gen, seen);
      source = nextSource();
    }
  }

  private async searchOneSource(source: BookSource, keyword: string, gen: number,
    seen: Set<string>): Promise<void> {
    try {
      const results = await BookSourceService.searchBooks(source, keyword);
      if (gen !== this.searchGen) return;
      const books: Book[] = [];
      const audioBooks: Book[] = [];
      const textBooks: Book[] = [];
      const comicBooks: Book[] = [];
      const fallbackContentType: 'audio' | 'text' | 'comic' = source.bookSourceType === 0 || source.bookSourceType === 3
        ? 'text' : source.bookSourceType === 2 ? 'comic' : 'audio';
      for (const item of results) {
        if (!SearchOptions.matches(item.name, item.author || '', keyword, this.exactSearch, this.searchByAuthor)) continue;
        const contentType: 'audio' | 'text' | 'comic' = item.contentType ?? fallbackContentType;
        if (!SearchOptions.matchesContentType(contentType, this.searchTextOnly, this.searchAudioOnly)) continue;
        const dedupeKey = `${item.sourceUrl}\u001f${item.bookUrl}`;
        if (seen.has(dedupeKey)) continue;
        seen.add(dedupeKey);
        const book = this.searchResultToBook(item, contentType);
        books.push(book);
        if (contentType === 'comic') {
          comicBooks.push(book);
        } else if (contentType === 'text') {
          textBooks.push(book);
        } else {
          audioBooks.push(book);
        }
      }
      if (books.length === 0) return;
      if (comicBooks.length > 0) this.comicBooks = this.comicBooks.concat(comicBooks);
      if (textBooks.length > 0) {
        this.textBooks = this.textBooks.concat(textBooks);
        this.textCount = this.textBooks.length;
      }
      if (audioBooks.length > 0) {
        this.audioBooks = this.audioBooks.concat(audioBooks);
        this.audioCount = this.audioBooks.length;
      }
      this.scheduleResultsRefresh();
      this.prefetchCovers(books);
      if (source instanceof LocalRuleSource && source.ruleSearch.coverUrl.trim().length === 0 &&
        source.ruleBookInfo.coverUrl.trim().length > 0) {
        this.hydrateMissingLocalRuleCovers(source, books, gen).catch((error: Error): void => {
          hilog.warn(DOMAIN, TAG, 'cover hydration failed [%{public}s]: %{public}s',
            source.bookSourceName, error.message);
        });
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'source search failed [%{public}s]: %{public}s',
        source.bookSourceName, String(e));
    } finally {
      if (gen === this.searchGen) this.searchedSourceCount++;
    }
  }

  private prefetchCovers(books: Book[]): void {
    const covers: string[] = [];
    for (const book of books) {
      if (book.cover && book.cover.startsWith('http')) covers.push(book.cover);
    }
    CoverPrefetcher.prefetchMany(covers, 12);
  }

  private async hydrateMissingLocalRuleCovers(source: LocalRuleSource, books: Book[],
    gen: number): Promise<void> {
    const candidates: Book[] = [];
    for (const book of books) {
      if (book.cover.trim().length > 0 || book.bookUrl.trim().length === 0) continue;
      candidates.push(book);
      if (candidates.length >= LOCAL_RULE_COVER_LIMIT) break;
    }
    for (let start = 0; start < candidates.length; start += LOCAL_RULE_COVER_CONCURRENCY) {
      if (gen !== this.searchGen) return;
      const tasks: Promise<Book | undefined>[] = [];
      const end = Math.min(candidates.length, start + LOCAL_RULE_COVER_CONCURRENCY);
      for (let index = start; index < end; index++) {
        tasks.push(this.hydrateOneLocalRuleCover(source, candidates[index], gen));
      }
      const hydratedBooks = await Promise.all(tasks);
      if (gen !== this.searchGen) return;
      for (const hydratedBook of hydratedBooks) {
        if (hydratedBook !== undefined) this.replaceSearchBook(hydratedBook);
      }
      this.refreshVisibleBooks();
    }
    this.prefetchCovers(candidates);
  }

  private async hydrateOneLocalRuleCover(source: LocalRuleSource, book: Book,
    gen: number): Promise<Book | undefined> {
    const info = await BookSourceService.getBookInfo(source, book.bookUrl, book.variables);
    if (gen !== this.searchGen || info === null) return undefined;
    const coverUrl = info.coverUrl.trim();
    if (coverUrl.length === 0) return undefined;
    BookCoverPolicy.setDetail(book, coverUrl);
    const hydratedBook = this.cloneBook(book);
    SearchCache.put(hydratedBook);
    return hydratedBook;
  }

  private replaceSearchBook(book: Book): void {
    const audioBooks = this.audioBooks.slice();
    let audioChanged = false;
    for (let index = 0; index < audioBooks.length; index++) {
      if (audioBooks[index].id !== book.id) continue;
      audioBooks[index] = book;
      audioChanged = true;
      break;
    }
    if (audioChanged) this.audioBooks = audioBooks;

    const textBooks = this.textBooks.slice();
    let textChanged = false;
    for (let index = 0; index < textBooks.length; index++) {
      if (textBooks[index].id !== book.id) continue;
      textBooks[index] = book;
      textChanged = true;
      break;
    }
    if (textChanged) this.textBooks = textBooks;
    this.comicBooks = this.comicBooks.map((item: Book): Book => item.id === book.id ? book : item);
  }

  private cloneBook(book: Book): Book {
    const cloned: Book = {
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
      tags: book.tags,
      chapters: book.chapters,
      bookUrl: book.bookUrl,
      sourceUrl: book.sourceUrl,
      variables: book.variables,
      skipIntro: book.skipIntro,
      skipOutro: book.skipOutro,
      completed: book.completed
    };
    return cloned;
  }

  private scheduleResultsRefresh(): void {
    if (this.resultsRefreshTimer >= 0) return;
    this.resultsRefreshTimer = setTimeout((): void => {
      this.resultsRefreshTimer = -1;
      if (!this.leavingPage) this.refreshVisibleBooks();
    }, 120);
  }

  private groupKey(book: Book): string {
    return `${book.contentType ?? 'audio'}:${book.title.replace(/\s+/g, '').toLowerCase()}`;
  }

  private groupCount(book: Book): number { return this.resultGroups.get(this.groupKey(book))?.length ?? 1; }

  private refreshVisibleBooks(): void {
    const visible: Book[] = [];
    if (this.searchTab === 0 || this.searchTab === 1) {
      for (const book of this.audioBooks) visible.push(book);
    }
    if (this.searchTab === 0 || this.searchTab === 2) {
      for (const book of this.textBooks) visible.push(book);
    }
    if (this.searchTab === 0 || this.searchTab === 3) {
      for (const book of this.comicBooks) visible.push(book);
    }
    const groups = new Map<string, Book[]>();
    const representatives: Book[] = [];
    for (const book of visible) {
      const key = this.groupKey(book);
      const group = groups.get(key);
      if (group) group.push(book);
      else { groups.set(key, [book]); representatives.push(book); }
    }
    this.resultGroups = groups;
    this.resultDataSource.setBooks(representatives);
    this.visibleResultCount = representatives.length;
  }

  private selectSearchTab(index: number): void {
    if (index < 0 || index > 3 || this.searchTab === index) return;
    this.searchTab = index;
    this.refreshVisibleBooks();
  }

  private searchResultToBook(result: SearchResult, contentType: 'audio' | 'text' | 'comic'): Book {
    const emptyChapters: Chapter[] = [];
    const id = contentType === 'comic' ? BookIdentity.onlineComicBookId(result.sourceUrl, result.bookUrl) : contentType === 'text'
      ? BookIdentity.onlineTextBookId(result.sourceUrl || '', result.bookUrl || result.name)
      : BookIdentity.onlineAudioBookId(result.sourceUrl || '', result.bookUrl || result.name);
    const book: Book = {
      id,
      title: result.name,
      author: result.author || '未知',
      narrator: result.sourceName,
      cover: result.coverUrl || '',
      category: result.kind || (contentType === 'comic' ? '漫画' : contentType === 'text' ? '电子书' : '有声书'),
      contentType,
      intro: result.intro || '',
      wordCount: result.wordCount,
      latestChapterTitle: result.lastChapter,
      updateTime: result.updateTime,
      totalDuration: 0,
      chapterCount: 0,
      rating: 0,
      tags: [result.sourceName],
      chapters: emptyChapters,
      bookUrl: result.bookUrl,
      sourceUrl: result.sourceUrl,
      variables: result.variables,
      completed: result.completed
    };
    SearchCache.put(book);
    return book;
  }

  private openBook(book: Book): void {
    const group = this.resultGroups.get(this.groupKey(book));
    if (group && group.length > 1) {
      this.groupedBooks.setBooks(group);
      this.resultGroupVisible = true;
      return;
    }
    this.openBookDetail(book);
  }

  private openBookDetail(book: Book): void {
    this.resultGroupVisible = false;
    SearchCache.put(book);
    if (PlaybackStore.getInstance().isCurrentBook(book.id)) {
      this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
        this.navStack.pushPathByName('player', book.id, false);
      });
      return;
    }
    this.navStack.pushPathByName('detail', book.id);
  }

  private async openSourcePicker(): Promise<void> {
    const sources = await SourceDataService.getEnabledSources();
    if (this.leavingPage) return;
    this.availableSearchSources = sources;
    this.sourcePickerVisible = true;
  }

  @Builder
  buildSourcePicker() {
    Column({ space: 12 }) {
      Button($r('app.string.search_source_all')).backgroundColor(AppColor.Brand)
        .onClick((): void => { this.sourceFilterEnabled = false; this.sourcePickerVisible = false; this.updateSearchOptions(); })
      List() {
        Repeat<BookSource>(this.availableSearchSources).each((item: RepeatItem<BookSource>) => {
          ListItem() {
            Row({ space: 12 }) {
              Text(item.item.bookSourceName).layoutWeight(1).fontColor($r('sys.color.font_primary')).maxLines(2)
              Checkbox({ name: item.item.bookSourceUrl }).select(this.selectedSourceUrls.includes(item.item.bookSourceUrl))
                .selectedColor(AppColor.Brand).onChange((checked: boolean): void => {
                  this.selectedSourceUrls = checked ? this.selectedSourceUrls.concat([item.item.bookSourceUrl]) :
                    this.selectedSourceUrls.filter((url: string): boolean => url !== item.item.bookSourceUrl);
                })
            }.width('100%').padding(12)
          }
        }).key((source: BookSource): string => source.bookSourceUrl).virtualScroll()
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      Button($r('app.string.tts_custom_confirm')).backgroundColor(AppColor.Brand).enabled(this.selectedSourceUrls.length > 0)
        .onClick((): void => { this.sourceFilterEnabled = true; this.sourcePickerVisible = false; this.updateSearchOptions(); })
    }.width('100%').height('100%').padding(16)
  }

  @Builder
  buildGroupBadge(book: Book) {
    if (this.groupCount(book) > 1) {
      Text(`${this.groupCount(book)}`).fontSize(12).fontColor(Color.White).backgroundColor(AppColor.Brand)
        .constraintSize({ minWidth: 26 }).height(26).textAlign(TextAlign.Center).borderRadius(13).margin(6)
        .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  buildResultGroup() {
    List() {
      LazyForEach(this.groupedBooks, (book: Book) => {
        ListItem() {
          Row({ space: 12 }) {
            CoverImage({ url: book.cover, imgWidth: 60, aspectRatioValue: 0.75, radius: 8 })
            Column({ space: 6 }) {
              Text(book.title).fontColor($r('sys.color.font_primary')).fontSize(16)
              Text(book.narrator || book.author).fontColor($r('sys.color.font_secondary')).fontSize(13)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%').padding(12).onClick((): void => { this.openBookDetail(book); })
        }
      }, (book: Book): string => book.id)
    }.width('100%').height('100%').scrollBar(BarState.Auto).padding({ bottom: 24 })
  }

  @Builder
  buildHistoryItem(keyword: string) {
    ImmersiveTabComponent({
      label: keyword,
      itemWidth: this.historyItemWidth(keyword),
      onTap: (): void => this.submitHistoryKeyword(keyword)
    })
    .margin({ right: AppSpace.Xs, bottom: AppSpace.Xs })
  }

  @Builder
  buildSearchHistory() {
    if (this.searchHistory.length > 0) {
      Column() {
        Row() {
          Text($r('app.string.search_history'))
            .fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)

          Text($r('app.string.search_clear_history'))
            .fontSize(AppFont.Caption)
            .fontColor(HomeTheme.Accent)
            .padding({ left: AppSpace.Xs, right: AppSpace.Xs, top: 4, bottom: 4 })
            .borderRadius(AppRadius.Xs)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
            .onClick(() => this.clearAllHistory())
        }
        .width('100%')
        .height(HISTORY_HEADING_HEIGHT - this.historyCollapseOffset)
        .opacity(1 - this.historyCollapseOffset / HISTORY_HEADING_HEIGHT)
        .clip(true)

        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.searchHistory, (keyword: string) => {
            this.buildHistoryItem(keyword)
          }, (keyword: string) => keyword)
        }
        .width('100%')
        .height(LayoutPolicy.wrapContent)
        .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions): void => {
          this.historyWidth = Number(newSize.width);
          this.trimHistory();
          const nextHeight: number = Number(newSize.height);
          if (nextHeight > 0 && Math.abs(nextHeight - this.historyTagsHeight) > 0.5) {
            this.historyTagsHeight = Math.min(84, nextHeight);
          }
        })
      }
      .width('100%')
      .padding({ bottom: AppSpace.Xs })
    }
  }

  @Builder
  buildRecommendations() {
    List({ scroller: this.recommendationScroller }) {
      // 完整展开高度作为可滚动首项；吸顶时只收起浮层标题，不改变列表占位。
      ListItem() {
        Column()
          .width('100%')
          .height(WindowUtils.getStatusBarHeightVp() + SEARCH_HEADER_HEIGHT +
            (this.searchHistory.length > 0 ? this.historyTagsHeight + HISTORY_HEADING_HEIGHT + AppSpace.Xs : 0))
      }
      ListItem() {
        Column({ space: AppSpace.Md }) {
          Text($r('app.string.search_recommendations'))
            .fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')

          if (this.recommendationsLoading && this.recommendationBooks.length === 0) {
            Row({ space: AppSpace.Xs }) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color(AppColor.Brand)
              Text($r('app.string.search_recommend_loading'))
                .fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .width('100%')
            .height(72)
            .justifyContent(FlexAlign.Center)
          } else if (this.recommendationBooks.length === 0) {
            Text($r('app.string.search_recommend_empty'))
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
              .height(56)
              .textAlign(TextAlign.Center)
          } else {
            Column() {
              ForEach(this.recommendationBooks, (book: Book) => {
                this.buildListItem(book)
              }, (book: Book) => book.id)
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Md })
      }
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .align(Alignment.Top)
    .onDidScroll(() => this.syncHistoryCollapse())
    .contentEndOffset(WindowUtils.getFloatingTabBottomVp() + AppSpace.Lg)
  }

  @Builder
  buildSearchTypeTab(label: Resource, index: number) {
    Row({ space: AppSpace.Xxs }) {
      Text(label)
        .fontSize(12)
        .fontColor(this.searchTab === index ? HomeTheme.Accent : $r('sys.color.font_secondary'))
        .fontWeight(this.searchTab === index ? FontWeight.Medium : FontWeight.Regular)
      Text((index === 0 ? this.audioCount + this.textCount + this.comicBooks.length :
        (index === 1 ? this.audioCount : index === 2 ? this.textCount : this.comicBooks.length)).toString())
        .fontSize(11)
        .fontColor(this.searchTab === index ? HomeTheme.Accent : $r('sys.color.font_tertiary'))
    }
    .padding({ left: 9, right: 9, top: 5, bottom: 5 })
    .borderRadius(AppRadius.Pill)
    .backgroundColor(Color.Transparent)
    .onClick(() => this.selectSearchTab(index))
  }

  @Builder
  buildResultToolbar() {
    Row() {
      Stack() {
        Row() {
          Scroll() {
            Row({ space: AppSpace.Xxs }) {
              this.buildSearchTypeTab($r('app.string.search_type_all'), 0)
              this.buildSearchTypeTab($r('app.string.search_type_audio'), 1)
              this.buildSearchTypeTab($r('app.string.search_type_text'), 2)
              this.buildSearchTypeTab($r('app.string.comic_type'), 3)
            }
            .padding({ left: 4, right: 4, top: 3, bottom: 3 })
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)

          if (this.searching) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(AppColor.Brand)
              .margin({ left: AppSpace.Xs })
            Text(`${this.searchedSourceCount}/${this.searchSourceTotal}`)
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .margin({ left: AppSpace.Xxs })
          }

        }
        .width('100%')
        .height('100%')
        .padding({ left: AppSpace.Xxs, right: AppSpace.Xxs })
      }
      .width('100%')
      .height(40)
      .borderRadius(AppRadius.Pill)
      .backgroundColor(Color.Transparent)
      .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveClean))
    }
    .width('100%')
    .height(48)
    .padding({ left: AppSpace.Md, right: AppSpace.Md })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildLoadingState() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Xs }) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(AppColor.Brand)
        Text(`${this.searchedSourceCount}/${this.searchSourceTotal}`)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
      }
      Text($r('app.string.search_loading'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildEmptyState() {
    Column({ space: AppSpace.Xs }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('sys.color.font_tertiary')])
      Text($r('app.string.search_no_result'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: AppSpace.Xs })
      Text($r('app.string.search_try_another'))
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildGridResults() {
    Grid(this.resultScroller) {
      LazyForEach(this.resultDataSource, (book: Book, index: number) => {
        GridItem() {
          Stack({ alignContent: Alignment.TopEnd }) {
          BookCard({
            book: book,
            indexHint: index,
            coverAspectRatio: SEARCH_COVER_ASPECT_RATIO,
            onTap: () => this.openBook(book)
          })
          this.buildGroupBadge(book)
          }.width('100%')
        }
      }, (book: Book) => book.id)
    }
    .columnsTemplate(`repeat(${this.bookColumns}, 1fr)`)
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
      if (typeof size.width === 'number' && size.width > 0) {
        this.bookColumns = AdaptiveLayout.bookColumns(size.width);
      }
    })
    .onDidScroll(() => this.syncSearchCollapse())
    .columnsGap(AppSpace.Sm)
    .rowsGap(AppSpace.Md)
    .cachedCount(6)
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .padding({
      left: AppSpace.Md,
      right: AppSpace.Md
    })
    .attributeModifier(new CompatibleGridInsets(WindowUtils.getStatusBarHeightVp() + SEARCH_HEADER_HEIGHT +
      RESULT_TOOLBAR_HEIGHT + AppSpace.Sm, WindowUtils.getFloatingTabBottomVp() + AppSpace.Lg, AppSpace.Md))
  }

  @Builder
  buildListItem(book: Book) {
    Row({ space: AppSpace.Md }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (book.cover && book.cover.startsWith('http')) {
          CoverImage({
            url: book.cover,
            imgWidth: 92,
            aspectRatioValue: SEARCH_COVER_ASPECT_RATIO,
            radius: AppRadius.Md,
            decodeW: 276,
            decodeH: 368,
            highPriority: false
          })
        } else {
          Image($r('app.media.app_icon_legacy'))
            .width(92)
            .aspectRatio(SEARCH_COVER_ASPECT_RATIO)
            .borderRadius(AppRadius.Md)
            .objectFit(ImageFit.Cover)
        }
        this.buildGroupBadge(book)
        if (book.narrator) {
          Text(book.narrator)
            .fontSize(10)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor($r('sys.color.ohos_id_color_mask_thin'))
            .borderRadius({ topRight: AppRadius.Sm, bottomLeft: AppRadius.Md })
            .align(Alignment.BottomStart)
        }
      }

      Column({ space: AppSpace.Xxs }) {
        Text(book.title)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(book.author)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (book.intro) {
          Text(book.intro)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ top: AppSpace.Sm, bottom: AppSpace.Sm })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.99 })
    .onClick(() => this.openBook(book))
  }

  @Builder
  buildListResults() {
    List({ scroller: this.resultScroller, space: AppSpace.Xs }) {
      LazyForEach(this.resultDataSource, (book: Book) => {
        ListItem() {
          this.buildListItem(book)
        }
      }, (book: Book) => book.id)
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .cachedCount(6)
    .contentStartOffset(WindowUtils.getStatusBarHeightVp() + SEARCH_HEADER_HEIGHT +
      RESULT_TOOLBAR_HEIGHT + AppSpace.Sm)
    .contentEndOffset(WindowUtils.getFloatingTabBottomVp() + AppSpace.Lg)
    .onDidScroll(() => this.syncSearchCollapse())
    .padding({
      left: AppSpace.Md,
      right: AppSpace.Md
    })
  }

  @Builder
  buildSearchTitleBar() {
    Row({ space: AppSpace.Xs }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .width(SEARCH_TITLE_CONTROL_HEIGHT)
      .height(SEARCH_TITLE_CONTROL_HEIGHT)
      .borderRadius(AppRadius.Pill)
      .backgroundColor(Color.Transparent)
      .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveClean))
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
      .onClick(() => this.navStack.pop())

      Search({ value: this.keyword, placeholder: $r('app.string.search_placeholder'),
        controller: this.searchController })
        .searchButton($r('app.string.search_action'), { fontColor: HomeTheme.Accent })
        .placeholderColor($r('sys.color.font_tertiary'))
        .placeholderFont({ size: AppFont.Body, weight: FontWeight.Regular })
        .textFont({ size: AppFont.Body, weight: FontWeight.Regular })
        .layoutWeight(1)
        .height(SEARCH_TITLE_CONTROL_HEIGHT)
        .backgroundColor(Color.Transparent)
        .borderRadius(AppRadius.Pill)
        .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveClean))
        .id('search-page-input')
        .focusable(true)
        .onSubmit(() => this.doSearch())
        .onChange((value: string) => {
          if (this.leavingPage) return;
          this.keyword = value;
          if (value.length === 0 && this.hasSearched) this.clearSearch();
        })

      if (this.hasSearched && !this.searching) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.viewMode === 0 ?
            $r('sys.symbol.list_bullet') : $r('sys.symbol.square_grid_2x2'))
            .fontSize(22)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .width(SEARCH_TITLE_CONTROL_HEIGHT)
        .height(SEARCH_TITLE_CONTROL_HEIGHT)
        .padding(0)
        .borderRadius(AppRadius.Pill)
        .backgroundColor(Color.Transparent)
        .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveClean))
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
        .accessibilityText($r('app.string.search_switch_layout'))
        .id('search-layout-button')
        .onClick(() => {
          this.searchController.stopEditing();
          this.getUIContext().animateTo({ duration: AppMotion.Base, curve: AppCurve.Standard }, () => {
            this.viewMode = this.viewMode === 0 ? 1 : 0;
            try {
              this.resultScroller.scrollEdge(Edge.Top);
            } catch (_e) {
              // 切换布局的同一帧可能暂时没有可滚动节点。
            }
          });
        })
      }

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.funnel'))
          .fontSize(22)
          .fontColor([this.exactSearch || this.searchByAuthor || this.searchTextOnly || this.searchAudioOnly
            ? AppColor.Brand : $r('sys.color.icon_primary')])
      }
        .width(SEARCH_TITLE_CONTROL_HEIGHT)
        .height(SEARCH_TITLE_CONTROL_HEIGHT)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveClean))
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
        .accessibilityText($r('app.string.search_options'))
        .id('search-options-button')
        .onClick(() => {
          this.searchController.stopEditing();
          this.searchOptionsVisible = !this.searchOptionsVisible;
        })
        .bindPopup(this.searchOptionsVisible, this.searchOptionsPopupOptions())

    }
    .width('100%')
    .height(SEARCH_HEADER_HEIGHT)
    .padding({ left: AppSpace.Xs, right: AppSpace.Md })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .translate({ y: -this.searchCollapseOffset })
    .opacity(Math.max(0, Math.min(1, (SEARCH_HEADER_HEIGHT - this.searchCollapseOffset) / 24)))
    .visibility(this.searchCollapseOffset >= SEARCH_HEADER_HEIGHT - 0.5 ? Visibility.Hidden : Visibility.Visible)
  }

  private searchOptionsPopupOptions(): CustomPopupOptions {
    const options: CustomPopupOptions = {
      builder: this.buildSearchOptionsMenu,
      placement: Placement.BottomRight,
      popupColor: AppMaterial.SheetBackground,
      enableArrow: false,
      focusable: true,
      onStateChange: (event): void => { this.searchOptionsVisible = event.isVisible; }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    else options.backgroundBlurStyle = AppMaterial.SheetBlur;
    return options;
  }

  @LocalBuilder
  buildSearchOptionsMenu() {
    Column() {
      SearchOptionItem({ label: $r('app.string.search_selected_sources'), selected: this.sourceFilterEnabled,
        onToggle: (): void => { this.searchOptionsVisible = false; this.openSourcePicker(); } })
      SearchOptionItem({
        label: $r('app.string.search_exact'), selected: this.exactSearch,
        onToggle: (): void => {
          this.exactSearch = !this.exactSearch;
          this.updateSearchOptions();
        }
      })
      SearchOptionItem({
        label: $r('app.string.search_by_author'), selected: this.searchByAuthor,
        onToggle: (): void => {
          this.searchByAuthor = !this.searchByAuthor;
          this.updateSearchOptions();
        }
      })
      SearchOptionItem({
        label: $r('app.string.search_text_only'), selected: this.searchTextOnly,
        onToggle: (): void => {
          this.searchTextOnly = !this.searchTextOnly;
          this.updateSearchOptions();
        }
      })
      SearchOptionItem({
        label: $r('app.string.search_audio_only'), selected: this.searchAudioOnly,
        onToggle: (): void => {
          this.searchAudioOnly = !this.searchAudioOnly;
          this.updateSearchOptions();
        }
      })
    }
    .width(208)
    .padding(4)
  }

  @Builder
  buildSearchNavigationBottom() {
    Column() {
    if (this.hasSearched) {
      this.buildResultToolbar()
    } else if (this.searchHistory.length > 0) {
      // 通用沉浸材质置于导航自定义区域，与首页分类标签使用同一渲染范围。
      Column() {
        this.buildSearchHistory()
      }
      .width('100%')
      .height(LayoutPolicy.wrapContent)
      .padding({ left: AppSpace.Md, right: AppSpace.Md })
    }
    }.width('100%')
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        this.historyWidth = Math.max(0, Number(size.width) - AppSpace.Md * 2);
        this.trimHistory();
      })
  }

  @Builder
  buildSearchBody() {
    if (!this.hasSearched) {
      this.buildRecommendations()
    } else if (this.visibleResultCount === 0 && this.searching) {
      this.buildLoadingState()
    } else if (this.visibleResultCount === 0) {
      this.buildEmptyState()
    } else {
      if (this.viewMode === 0) {
        this.buildGridResults()
      } else {
        this.buildListResults()
      }
    }
  }

  build() {
    HdsNavDestination() {
      Column().width(0).height(0).bindSheet($$this.resultGroupVisible, this.buildResultGroup(), {
        height: '82%', showClose: true, backgroundColor: AppMaterial.SheetBackground,
        blurStyle: AppMaterial.SheetBlur, systemMaterial: AppMaterial.Sheet,
        title: { title: $r('app.string.search_group_title') } })

      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(HomeTheme.BgNeutral)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Column() {
          this.buildSearchBody()
        }
        .width('100%')
        .height('100%')
        .clip(false)
        .backgroundColor(Color.Transparent)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(HomeTheme.BgNeutral)
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: this.searchTitleBarContent,
      // 与首页一致：透明初态，内容上滑后由系统绘制沉浸渐变模糊。
      style: {
        scrollEffectOpts: {
          scrollEffectType: HdsCompat.scrollEffect
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent }
        },
        scrollEffectStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent }
        },
        thermoCtrl: true
      }
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideBackButton(true)
    .bindToScrollable(this.hasSearched ? [this.resultScroller] : [this.recommendationScroller])
    .dynamicHideTitleBar({
      hideTitleArea: this.hasSearched && this.visibleResultCount > 0,
      hideBottomBuilder: false,
      hideStatusBar: false,
      mode: HideMode.SCROLL_UP_TO,
      hideRatio: 1.0
    })
    .systemBarStyle(
      { statusBarContentColor: '#FFFFFFFF' },
      { statusBarContentColor: '#FF000000' }
    )
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(HomeTheme.BgNeutral)
    .bindSheet($$this.sourcePickerVisible, this.buildSourcePicker(), { height: '82%', showClose: true,
      backgroundColor: AppMaterial.SheetBackground, blurStyle: AppMaterial.SheetBlur,
      systemMaterial: AppMaterial.Sheet, title: { title: $r('app.string.search_selected_sources') } })
    .onShown(() => this.handlePageShown())
    .onWillHide(() => this.handlePageHidden())
    .onHidden(() => this.handlePageHidden())
    .onWillDisappear(() => {
      // 在退场开始前停止回写，避免推荐、搜索及键盘与返回动画争抢布局。
      this.stopPendingSearchUpdates();
      this.searchController.stopEditing();
    })
    // 保持沉浸材质实时采样，双向转场均交给 HDS；customTransition 会覆盖 systemTransition。
    .renderGroup(false)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
  }
}
