import { ImmersiveMenu } from '../utils/ImmersiveMenu';
import { ImmersiveMenuHeader } from '../components/ImmersiveMenuHeader';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';
import { BookCoverPolicy } from '../utils/BookCoverPolicy';
import { BookMetadataPolicy } from '../utils/BookMetadataPolicy';
import { BookMetadataText } from '../utils/BookMetadataText';
import { LengthMetrics, PathShape } from '@kit.ArkUI';
import { GeneralSettings } from '../model/GeneralSettings';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { CompatibleGridInsets, PlatformCompat } from '../utils/PlatformCompat';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppColor, AppCurve, AppFont, AppMotion, AppRadius, AppSpace, HomeTheme, AppTheme, AppMaterial } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { BookSource, SearchResult } from '../model/BookSource';
import { LocalRuleSource } from '../model/LocalRuleSource';
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
import { SearchRecommendationService } from '../service/SearchRecommendationService';
import { LightSourceRequest } from '../service/rulesource/light/LightSourceRequestPolicy';

const DOMAIN = 0x0000;
const TAG = 'SearchPage';
const LOCAL_RULE_COVER_CONCURRENCY: number = 3;
const LOCAL_RULE_COVER_LIMIT: number = 12;
const LOCAL_RULE_COVER_PENDING_LIMIT: number = 96;
const SEARCH_COVER_ASPECT_RATIO: number = 0.75;
const SEARCH_HEADER_HEIGHT: number = 56;
const SEARCH_TITLE_CONTROL_HEIGHT: number = 44;
const RESULT_TOOLBAR_HEIGHT: number = 48;
const HISTORY_HEADING_HEIGHT: number = 52;
// onShown 在当前导航中先于系统滑入动画触发；450ms 转场期间不读取整份书源或执行推荐规则。
const SEARCH_ENTRY_SETTLE_MS: number = 500;

/** 自绘顶部使用独立磨砂，不依赖 HDS 标题栏的材质合成范围。 */
class SearchControlSurface implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(node: CommonAttribute): void {
    node.backgroundColor(Color.Transparent)
      .backgroundEffect({ radius: 16, saturation: 1, brightness: 1,
        color: $r('app.color.shelf_toolbar_background') })
      .borderRadius(AppRadius.Pill)
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .clip(true);
  }
}

class SearchCoverTask {
  source: LocalRuleSource;
  book: Book;
  generation: number;

  constructor(source: LocalRuleSource, book: Book, generation: number) {
    this.source = source;
    this.book = book;
    this.generation = generation;
  }
}

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
          .fontColor([$r('sys.color.font_primary')])
          .visibility(this.selected ? Visibility.Visible : Visibility.Hidden)
      }
      .width('100%')
      .constraintSize({ minHeight: 40 })
      .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: AppSpace.Xs, bottom: AppSpace.Xs })
      .borderRadius(AppRadius.Sm)
      .backgroundColor(ImmersiveMenu.selection(this.selected))
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .padding(AppSpace.Xxs)
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
  @Local searchComicOnly: boolean = false;
  @Local searchOptionsVisible: boolean = false;
  @Local historyWidth: number = 0;
  private historyWrite: Promise<void> = Promise.resolve();
  @Local searching: boolean = false;
  private sourcePages: Map<string, number> = new Map();
  private searchSeen: Set<string> = new Set();
  @Local searchedSourceCount: number = 0;
  @Local searchSourceTotal: number = 0;
  @Local hasSearched: boolean = false;
  @Local searchTab: number = 0;
  @Local viewMode: number = 0;
  private audioBooks: Book[] = [];
  private textBooks: Book[] = [];
  private comicBooks: Book[] = [];
  @Local audioCount: number = 0;
  @Local textCount: number = 0;
  @Local comicCount: number = 0;
  @Local visibleResultCount: number = 0;
  @Local searchHistory: string[] = [];
  @Local historyLoaded: boolean = false;
  @Local entryReady: boolean = false;
  @Local historyTagsHeight: number = 84;
  @Local historyCollapseOffset: number = 0;
  @Local searchCollapseOffset: number = 0;
  @Local recommendationBooks: Book[] = [];
  @Local recommendationsLoading: boolean = true;
  @Local generalSettings: GeneralSettings = GeneralSettings.current;

  @Local sourcePickerVisible: boolean = false;
  @Local searchMenuX: number = 0;
  @Local searchMenuY: number = 0;
  @Local menuViewportWidth: number = 360;
  @Local menuViewportHeight: number = 640;
  @Local resultMenuX: number = 16;
  @Local resultMenuY: number = 80;
  private searchSourceData: HomeRecommendationDataSource<BookSource> = new HomeRecommendationDataSource();
  @Local sourceFilterEnabled: boolean = false;
  @Local selectedSourceUrls: string[] = [];
  @Local availableSearchSources: BookSource[] = [];
  @Local resultGroupVisible: boolean = false;
  private resultGroups: Map<string, Book[]> = new Map();
  @Local resultGroupsRevision: number = 0;
  private searchBookIndexes: Map<string, number> = new Map();
  private representativeIndexes: Map<string, number> = new Map();
  private audioRepresentatives: Book[] = [];
  private textRepresentatives: Book[] = [];
  private comicRepresentatives: Book[] = [];
  private coverHydrationQueue: SearchCoverTask[] = [];
  private coverHydrationActive: number = 0;
  private groupedBooks: BookDataSource = new BookDataSource();
  private resultsRefreshTimer: number = -1;
  private resultDataSource: BookDataSource = new BookDataSource();
  private searchController: SearchController = new SearchController();
  private resultScroller: Scroller = new Scroller();
  private recommendationScroller: Scroller = new Scroller();
  private searchGen: number = 0;
  private recommendationGen: number = 0;
  private recommendationRequest: LightSourceRequest | undefined = undefined;
  private recommendationRevision: string = '';
  private recommendationDataSource: BookDataSource = new BookDataSource();
  private recommendationTimerId: number = -1;
  private entryTimerId: number = -1;
  private historyTextWidths: Map<string, number> = new Map();
  private historyMeasureScale: string = '';
  private pageShown: boolean = false;
  private recommendationsStarted: boolean = false;
  private recommendationsLoaded: boolean = false;
  private leavingPage: boolean = false;
  @Local statusBarContentColor: string = WindowUtils.isDarkMode() ? '#FFFFFFFF' : '#FF000000';
  private readonly statusBarColorListener = (): void => {
    this.statusBarContentColor = WindowUtils.isDarkMode() ? '#FFFFFFFF' : '#FF000000';
  };

  @Computed
  get headerBackdropHeight(): number {
    return WindowUtils.getStatusBarHeightVp() + SEARCH_HEADER_HEIGHT - this.searchCollapseOffset +
      (this.hasSearched ? RESULT_TOOLBAR_HEIGHT : this.historyPanelHeight);
  }

  private headerBackdropClip(): PathShape {
    const ui = this.getUIContext();
    const width: number = ui.vp2px(this.menuViewportWidth);
    const height: number = ui.vp2px(this.headerBackdropHeight);
    const radius: number = ui.vp2px(Math.min(AppRadius.Xl, this.menuViewportWidth / 2));
    // 中间保持原吸顶下缘，两侧向下延伸，用反向四分之一圆连接列表。
    return new PathShape().commands(`M 0 0 H ${width} V ${height + radius} ` +
      `A ${radius} ${radius} 0 0 0 ${width - radius} ${height} H ${radius} ` +
      `A ${radius} ${radius} 0 0 0 0 ${height + radius} Z`);
  }

  @Computed
  get historyPanelHeight(): number {
    if (!this.entryReady) return 84 + HISTORY_HEADING_HEIGHT + AppSpace.Xs;
    if (this.historyLoaded && this.searchHistory.length === 0) return 0;
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
    this.statusBarColorListener();
    WindowUtils.addReaderColorListener(this.statusBarColorListener);
    WindowUtils.setStatusBarLight(false);
    CoverPrefetcher.init();
    BookCard.resetAnimations();
    this.loadSearchHistory();
  }

  aboutToDisappear(): void {
    WindowUtils.removeReaderColorListener(this.statusBarColorListener);
    this.stopPendingSearchUpdates();
  }

  private stopPendingSearchUpdates(): void {
    if (this.leavingPage) return;
    this.leavingPage = true;
    this.pageShown = false;
    this.cancelEntryTimer();
    this.searchGen++;
    this.coverHydrationQueue = [];
    if (this.resultsRefreshTimer >= 0) clearTimeout(this.resultsRefreshTimer);
    this.resultsRefreshTimer = -1;
    this.cancelRecommendations();
  }

  private handlePageShown(): void {
    if (this.leavingPage) return;
    this.pageShown = true;
    if (!this.entryReady && this.entryTimerId < 0) {
      this.entryTimerId = setTimeout((): void => {
        this.entryTimerId = -1;
        if (!this.pageShown || this.leavingPage) return;
        // 先完成输入框与系统滑入，历史材质标签和推荐分别在转场后的任务中构建。
        this.entryReady = true;
        this.trimHistory();
        this.scheduleRecommendations();
      }, SEARCH_ENTRY_SETTLE_MS);
    }
    if (this.applyInitialKeyword()) return;
    this.scheduleRecommendations();
  }

  private cancelEntryTimer(): void {
    if (this.entryTimerId >= 0) clearTimeout(this.entryTimerId);
    this.entryTimerId = -1;
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
    this.sourcePickerVisible = false;
    this.resultGroupVisible = false;
    this.searchOptionsVisible = false;
    this.pageShown = false;
    this.cancelEntryTimer();
    this.cancelRecommendations();
    this.searchController.stopEditing();
  }

  private async loadSearchHistory(): Promise<void> {
    try {
      const history = await PreferenceService.getSearchHistory();
      if (!this.leavingPage) {
        this.searchHistory = history;
        this.historyLoaded = true;
        this.trimHistory();
        this.exactSearch = await PreferenceService.getSearchExact();
        this.searchByAuthor = await PreferenceService.getSearchByAuthor();
        this.searchTextOnly = await PreferenceService.getSearchTextOnly();
        this.searchAudioOnly = await PreferenceService.getSearchAudioOnly();
        this.searchComicOnly = await PreferenceService.getSearchComicOnly();
      }
    } catch (e) {
      this.historyLoaded = true;
      hilog.error(DOMAIN, TAG, 'load search history failed: %{public}s', String(e));
    }
  }

  @Monitor('generalSettings.searchRecommendations')
  private onRecommendationsChanged(): void {
    if (!this.generalSettings.searchRecommendations) {
      this.cancelRecommendations();
      this.recommendationBooks = [];
      this.recommendationDataSource.clear();
      this.recommendationsLoaded = false;
      this.recommendationsLoading = false;
    } else {
      this.scheduleRecommendations();
    }
  }

  private scheduleRecommendations(): void {
    if (!this.generalSettings.searchRecommendations) return;
    if (this.recommendationRevision !== SearchRecommendationService.getRevision()) {
      this.recommendationBooks = [];
      this.recommendationDataSource.clear();
      this.recommendationsLoaded = false;
      this.recommendationRevision = SearchRecommendationService.getRevision();
    }
    if (this.keyword.trim().length > 0) return;
    if (!this.entryReady || !this.pageShown || this.leavingPage || this.hasSearched || this.recommendationsLoaded ||
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
    this.recommendationRequest?.cancel();
    this.recommendationRequest = undefined;
    this.recommendationsStarted = false;
    this.recommendationsLoading = false;
  }

  private clearSearch(): void {
    this.searchCollapseOffset = 0;
    this.searchGen++;
    this.resetPagination();
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
    this.comicCount = 0;
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
    const context = this.getUIContext();
    const scale = `${context.fp2px(13)}:${context.px2vp(1)}`;
    if (scale !== this.historyMeasureScale) {
      this.historyMeasureScale = scale;
      this.historyTextWidths.clear();
    }
    let measured = this.historyTextWidths.get(keyword);
    if (measured === undefined) {
      const size = context.getMeasureUtils().measureTextSize({ textContent: keyword, fontSize: 13 });
      measured = Math.ceil(context.px2vp(Number(size.width))) + 24;
      if (this.historyTextWidths.size >= 64) this.historyTextWidths.clear();
      this.historyTextWidths.set(keyword, measured);
    }
    return Math.min(Math.max(1, this.historyWidth - AppSpace.Xs), 176, measured);
  }

  private trimHistory(): void {
    if (!this.entryReady || this.historyWidth <= 0) return;
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
      this.searchTextOnly, this.searchAudioOnly, this.searchComicOnly).catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'save search options: %{public}s', error.message);
    });
    if (this.hasSearched) this.doSearch();
  }

  private async loadRecommendations(): Promise<void> {
    if (!this.generalSettings.searchRecommendations) return;
    this.recommendationsStarted = true;
    const generation = ++this.recommendationGen;
    const request = new LightSourceRequest(0);
    request.cancelCheck = (): boolean => generation !== this.recommendationGen || this.leavingPage || !this.pageShown;
    this.recommendationRequest = request;
    this.recommendationRevision = SearchRecommendationService.getRevision();
    this.recommendationsLoading = true;
    try {
      await SearchRecommendationService.load(request, (results: SearchResult[]): void => {
        if (request.isCancelled()) return;
        const books = this.recommendationBooks.slice();
        const seen = new Set<string>(books.map((book: Book): string => book.id));
        for (const result of results) {
          if (books.length >= 5) break;
          const book = this.searchResultToBook(result, result.contentType ?? 'text');
          if (seen.has(book.id)) continue;
          seen.add(book.id);
          books.push(book);
        }
        if (books.length === this.recommendationBooks.length) return;
        this.recommendationBooks = books;
        this.recommendationDataSource.updateBooks(books);
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'load recommendations failed: %{public}s', String(error));
    } finally {
      if (generation === this.recommendationGen) {
        this.recommendationRequest = undefined;
        this.recommendationsStarted = false;
        this.recommendationsLoaded = this.recommendationRevision === SearchRecommendationService.getRevision();
        this.recommendationsLoading = false;
      }
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
    this.resetPagination();
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
    this.comicCount = 0;
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
        SearchOptions.matchesSource(source, this.searchTextOnly, this.searchAudioOnly, this.searchComicOnly) &&
        (!this.sourceFilterEnabled || this.selectedSourceUrls.includes(source.bookSourceUrl)));
      this.searchSourceTotal = selectedSources.length;
      const concurrency = await PreferenceService.getSearchConcurrency();
      if (gen !== this.searchGen) return;
      hilog.info(DOMAIN, TAG, 'search schedule concurrency=%{public}d sources=%{public}d generation=%{public}d',
        concurrency, selectedSources.length, gen);
      for (const source of selectedSources) this.sourcePages.set(source.bookSourceUrl, 1);
      await this.searchSources(selectedSources, keyword, gen, this.searchSeen, concurrency);
      if (gen !== this.searchGen) return;
      this.audioCount = this.audioBooks.length;
      this.textCount = this.textBooks.length;
      this.refreshVisibleBooks();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'search failed: %{public}s', String(e));
    } finally {
      if (gen === this.searchGen) {
        this.searching = false;
      }
    }
  }

  private resetPagination(): void {
    this.sourcePages = new Map();
    this.searchSeen = new Set();
    this.resultGroups = new Map();
    this.searchBookIndexes = new Map();
    this.representativeIndexes = new Map();
    this.audioRepresentatives = [];
    this.textRepresentatives = [];
    this.comicRepresentatives = [];
    this.coverHydrationQueue = [];
    this.resultGroupsRevision = 0;
    if (this.resultsRefreshTimer >= 0) clearTimeout(this.resultsRefreshTimer);
    this.resultsRefreshTimer = -1;
  }

  private async searchSources(sources: BookSource[], keyword: string, gen: number,
    seen: Set<string>, concurrency: number): Promise<void> {
    const pending: BookSource[] = sources.slice();
    const nextSource = (): BookSource | undefined => {
      if (gen !== this.searchGen) return undefined;
      return pending.shift();
    };
    const enqueueNextPage = (source: BookSource): void => {
      if (gen === this.searchGen && this.sourcePages.has(source.bookSourceUrl)) pending.push(source);
    };
    const tasks: Promise<void>[] = [];
    for (let index = 0; index < Math.min(concurrency, sources.length); index++) {
      tasks.push(this.searchSourceQueue(nextSource, enqueueNextPage, keyword, gen, seen));
    }
    await Promise.all(tasks);
  }

  private async searchSourceQueue(nextSource: () => BookSource | undefined,
    enqueueNextPage: (source: BookSource) => void, keyword: string,
    gen: number, seen: Set<string>): Promise<void> {
    // 下一页放回队尾，先让尚未搜索的源返回首页；所有页共用并发上限。
    let source = nextSource();
    while (source !== undefined) {
      await this.searchOneSource(source, keyword, gen, seen);
      enqueueNextPage(source);
      source = nextSource();
    }
  }

  private async searchOneSource(source: BookSource, keyword: string, gen: number,
    seen: Set<string>): Promise<void> {
    try {
      const page = this.sourcePages.get(source.bookSourceUrl) ?? 1;
      const request = new LightSourceRequest();
      request.cancelCheck = (): boolean => gen !== this.searchGen || this.leavingPage;
      const results = await BookSourceService.searchBooks(source, keyword, page, request);
      if (gen !== this.searchGen) return;
      // 使用筛选前的身份判断翻页进度；不支持翻页、反复返回首页的源在此终止。
      const freshResults: SearchResult[] = [];
      for (const item of results) {
        const key = `${item.sourceUrl}\u001f${item.bookUrl}`;
        if (seen.has(key)) continue;
        seen.add(key);
        freshResults.push(item);
      }
      if (freshResults.length === 0) this.sourcePages.delete(source.bookSourceUrl);
      else this.sourcePages.set(source.bookSourceUrl, page + 1);
      const books: Book[] = [];
      const fallbackContentType: 'audio' | 'text' | 'comic' = source.bookSourceType === 0 || source.bookSourceType === 3
        ? 'text' : source.bookSourceType === 2 ? 'comic' : 'audio';
      for (const item of freshResults) {
        if (!SearchOptions.matches(item.name, item.author || '', keyword, this.exactSearch, this.searchByAuthor)) continue;
        const contentType: 'audio' | 'text' | 'comic' = item.contentType ?? fallbackContentType;
        if (!SearchOptions.matchesContentType(contentType, this.searchTextOnly, this.searchAudioOnly, this.searchComicOnly)) continue;
        const book = this.searchResultToBook(item, contentType);
        books.push(book);
        this.appendSearchBook(book);
      }
      if (books.length === 0) return;
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
      if (gen === this.searchGen) this.sourcePages.delete(source.bookSourceUrl);
      hilog.warn(DOMAIN, TAG, 'source search failed [%{public}s]: %{public}s',
        source.bookSourceName, String(e));
    } finally {
      if (gen === this.searchGen && this.searching && !this.sourcePages.has(source.bookSourceUrl)) {
        this.searchedSourceCount++;
      }
    }
  }

  private booksForType(contentType: 'audio' | 'text' | 'comic' | undefined): Book[] {
    return contentType === 'comic' ? this.comicBooks : contentType === 'text' ? this.textBooks : this.audioBooks;
  }

  private representativesForType(contentType: 'audio' | 'text' | 'comic' | undefined): Book[] {
    return contentType === 'comic' ? this.comicRepresentatives :
      contentType === 'text' ? this.textRepresentatives : this.audioRepresentatives;
  }

  private appendSearchBook(book: Book): void {
    const books = this.booksForType(book.contentType);
    this.searchBookIndexes.set(book.id, books.length);
    books.push(book);
    const key = this.groupKey(book);
    const group = this.resultGroups.get(key);
    if (group !== undefined) {
      group.push(book);
      return;
    }
    this.resultGroups.set(key, [book]);
    const representatives = this.representativesForType(book.contentType);
    this.representativeIndexes.set(key, representatives.length);
    representatives.push(book);
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
    let queued = 0;
    for (const book of books) {
      if (gen !== this.searchGen || this.leavingPage ||
        this.coverHydrationQueue.length >= LOCAL_RULE_COVER_PENDING_LIMIT) break;
      if (book.cover.trim().length > 0 || book.bookUrl.trim().length === 0) continue;
      this.coverHydrationQueue.push(new SearchCoverTask(source, book, gen));
      if (++queued >= LOCAL_RULE_COVER_LIMIT) break;
    }
    this.pumpCoverHydration();
  }

  private pumpCoverHydration(): void {
    while (!this.leavingPage && this.coverHydrationActive < LOCAL_RULE_COVER_CONCURRENCY &&
      this.coverHydrationQueue.length > 0) {
      const task = this.coverHydrationQueue.shift();
      if (task === undefined || task.generation !== this.searchGen) continue;
      this.coverHydrationActive++;
      this.runCoverHydration(task);
    }
  }

  private async runCoverHydration(task: SearchCoverTask): Promise<void> {
    try {
      const book = await this.hydrateOneLocalRuleCover(task.source, task.book, task.generation);
      if (book !== undefined && task.generation === this.searchGen && !this.leavingPage) {
        this.replaceSearchBook(book);
        this.scheduleResultsRefresh();
        this.prefetchCovers([book]);
      }
    } catch (error) {
      if (task.generation === this.searchGen && !this.leavingPage) {
        hilog.warn(DOMAIN, TAG, 'cover hydration failed [%{public}s]: %{public}s',
          task.source.bookSourceName, String(error));
      }
    } finally {
      // 换代只清队列；旧请求真正结束前仍占据全页并发槽位。
      this.coverHydrationActive--;
      this.pumpCoverHydration();
    }
  }

  private async hydrateOneLocalRuleCover(source: LocalRuleSource, book: Book,
    gen: number): Promise<Book | undefined> {
    const request = new LightSourceRequest(0);
    request.cancelCheck = (): boolean => gen !== this.searchGen || this.leavingPage;
    const info = await BookSourceService.getBookInfo(source, book.bookUrl, book.variables, request);
    if (gen !== this.searchGen || info === null) return undefined;
    const coverUrl = info.coverUrl.trim();
    if (coverUrl.length === 0 || coverUrl === book.cover) return undefined;
    BookCoverPolicy.setDetail(book, coverUrl);
    const hydratedBook = this.cloneBook(book);
    SearchCache.put(hydratedBook);
    return hydratedBook;
  }

  private replaceSearchBook(book: Book): void {
    const index = this.searchBookIndexes.get(book.id);
    if (index === undefined) return;
    this.booksForType(book.contentType)[index] = book;
    const key = this.groupKey(book);
    const group = this.resultGroups.get(key);
    if (group === undefined) return;
    const groupIndex = group.findIndex((item: Book): boolean => item.id === book.id);
    if (groupIndex >= 0) group[groupIndex] = book;
    const representativeIndex = this.representativeIndexes.get(key);
    if (groupIndex === 0 && representativeIndex !== undefined) {
      this.representativesForType(book.contentType)[representativeIndex] = book;
    }
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

  private groupCount(book: Book): number {
    // 私有分组增量更新，统一发布版本让可见角标响应本批次变化。
    if (this.resultGroupsRevision === 0) return 1;
    return this.resultGroups.get(this.groupKey(book))?.length ?? 1;
  }

  private refreshVisibleBooks(): void {
    if (this.resultsRefreshTimer >= 0) clearTimeout(this.resultsRefreshTimer);
    this.resultsRefreshTimer = -1;
    const visible: Book[] = [];
    if (this.searchTab === 0 || this.searchTab === 1) {
      for (const book of this.audioRepresentatives) visible.push(book);
    }
    if (this.searchTab === 0 || this.searchTab === 2) {
      for (const book of this.textRepresentatives) visible.push(book);
    }
    if (this.searchTab === 0 || this.searchTab === 3) {
      for (const book of this.comicRepresentatives) visible.push(book);
    }
    this.audioCount = this.audioBooks.length;
    this.textCount = this.textBooks.length;
    this.comicCount = this.comicBooks.length;
    this.resultGroupsRevision++;
    this.resultDataSource.updateBooks(visible);
    this.visibleResultCount = visible.length;
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
      category: result.kind || '',
      contentType,
      intro: result.intro || '',
      wordCount: result.wordCount,
      latestChapterTitle: result.lastChapter,
      updateTime: result.updateTime,
      totalDuration: 0,
      chapterCount: 0,
      rating: result.rating ?? 0,
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
      this.groupedBooks.setBooks(group.slice());
      this.resultGroupVisible = true;
      return;
    }
    this.openBookDetail(book);
  }

  private openBookDetail(book: Book): void {
    this.resultGroupVisible = false;
    SearchCache.put(book);
    if (PlaybackStore.getInstance().isCurrentBook(book.id)) {
      this.navStack.pushPathByName('player', book.id);
      return;
    }
    this.navStack.pushPathByName('detail', book.id);
  }

  private async openSourcePicker(): Promise<void> {
    const sources = await SourceDataService.getEnabledSources();
    if (this.leavingPage || !this.pageShown || !this.searchOptionsVisible) return;
    this.availableSearchSources = sources;
    this.searchSourceData.setItems(sources);
    this.sourcePickerVisible = true;
  }

  private resultGroupMenuOptions(): MenuOptions {
    const options = ImmersiveMenu.options((): void => { this.resultGroupVisible = false; });
    // 同名来源列表固定强磨砂，封面不能透过弹层干扰正文。
    options.backgroundBlurStyle = PlatformCompat.immersiveMaterial ? BlurStyle.NONE : BlurStyle.COMPONENT_THICK;
    options.systemMaterial = AppMaterial.ReaderSheetThick;
    options.anchorPosition = { x: this.resultMenuX, y: this.resultMenuY };
    return options;
  }

  @LocalBuilder
  buildSourcePicker() {
    Column({ space: AppSpace.Xs }) {
      ImmersiveMenuHeader({ title: $r('app.string.search_selected_sources'),
        onClose: (): void => { this.searchOptionsVisible = false; } })
      Button($r('app.string.search_source_all'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .fontColor($r('sys.color.font_primary')).width('100%').height(40)
        .backgroundColor(ImmersiveMenu.selection(!this.sourceFilterEnabled))
        .onClick((): void => { this.sourceFilterEnabled = false; this.searchOptionsVisible = false; this.updateSearchOptions(); })
      List({ space: AppSpace.Xs }) {
        LazyForEach(this.searchSourceData, (source: BookSource) => {
          ListItem() {
            Row({ space: AppSpace.Sm }) {
              Text(source.bookSourceName).fontSize(AppFont.Body).layoutWeight(1)
                .fontColor($r('sys.color.font_primary')).maxLines(2)
              Checkbox({ name: source.bookSourceUrl }).select(this.selectedSourceUrls.includes(source.bookSourceUrl))
                .selectedColor(AppColor.Brand).onChange((checked: boolean): void => {
                  this.selectedSourceUrls = checked ? this.selectedSourceUrls.concat([source.bookSourceUrl]) :
                    this.selectedSourceUrls.filter((url: string): boolean => url !== source.bookSourceUrl);
                })
            }.width('100%').constraintSize({ minHeight: 48 }).padding(AppSpace.Sm)
              .borderRadius(AppRadius.Sm)
              .backgroundColor(ImmersiveMenu.selection(this.selectedSourceUrls.includes(source.bookSourceUrl)))
          }
        }, (source: BookSource): string => source.bookSourceUrl)
      }.layoutWeight(1).width('100%').padding({ left: AppSpace.Xxs, right: AppSpace.Xxs })
        .scrollBar(BarState.Off)
      Button($r('app.string.search_source_confirm')).backgroundColor(AppColor.Brand).width('100%').height(40)
        .enabled(this.selectedSourceUrls.length > 0)
        .onClick((): void => { this.sourceFilterEnabled = true; this.searchOptionsVisible = false; this.updateSearchOptions(); })
    }.width(ImmersiveMenu.width(this.menuViewportWidth))
      .height(Math.min(ImmersiveMenu.height(this.menuViewportHeight), 164 + this.availableSearchSources.length * 56))
      .constraintSize({ maxWidth: '100%' }).onTouch(ImmersiveMenu.keepOpen)
      .padding(AppSpace.Xs).id('search-source-menu')
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
  buildResultGroupTags(category: string) {
    if (BookMetadataPolicy.categories(BookMetadataText.intro(category)).length > 0) {
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap,
        space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(4) } }) {
        ForEach(BookMetadataPolicy.categories(BookMetadataText.intro(category)), (tag: string) => {
          Text(tag).fontSize(12).fontColor(AppColor.Brand)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(AppColor.BrandSoft).borderRadius(AppRadius.Pill)
            .constraintSize({ maxWidth: '100%' })
        }, (tag: string): string => tag)
      }.width('100%')
    }
  }

  @LocalBuilder
  buildResultGroup() {
    Column({ space: AppSpace.Xs }) {
      ImmersiveMenuHeader({ title: $r('app.string.search_group_title'),
        onClose: (): void => { this.resultGroupVisible = false; } })
      List() {
        LazyForEach(this.groupedBooks, (book: Book) => {
          ListItem() {
            Row({ space: 12 }) {
              CoverImage({ url: book.cover, imgWidth: 60, aspectRatioValue: 0.75, radius: 8 })
              Column({ space: 6 }) {
                Text(book.title).fontColor($r('sys.color.font_primary')).fontSize(16)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                this.buildResultGroupTags(book.category)
                Text(book.narrator || book.author).fontColor($r('sys.color.font_secondary')).fontSize(13)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (book.latestChapterTitle) {
                  Text($r('app.string.source_latest_chapter', book.latestChapterTitle))
                    .fontSize(12).fontColor($r('sys.color.font_secondary'))
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%').padding(12).onClick((): void => { this.openBookDetail(book); })
          }
        }, (book: Book): string => book.id)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }.width(ImmersiveMenu.width(this.menuViewportWidth, 480))
      .height(ImmersiveMenu.height(this.menuViewportHeight)).padding(AppSpace.Xs)
      .constraintSize({ maxWidth: '100%' }).onTouch(ImmersiveMenu.keepOpen)
      .id('search-result-group-menu')
  }

  @Builder
  buildHistoryItem(keyword: string) {
    // 历史记录使用普通圆角标签，避免每个关键词单独创建实时沉浸材质。
    Text(keyword)
      .fontSize(13).fontColor(AppTheme.TextSecondary).maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center)
      .width(this.historyItemWidth(keyword)).height(34)
      .padding({ left: AppSpace.Xs, right: AppSpace.Xs })
      .borderRadius(AppRadius.Md).backgroundColor($r('sys.color.comp_background_tertiary'))
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
      .onClick((): void => this.submitHistoryKeyword(keyword))
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
        Column().width('100%')
          .height(WindowUtils.getStatusBarHeightVp() + SEARCH_HEADER_HEIGHT +
            (!this.entryReady || this.searchHistory.length > 0 ?
              this.historyTagsHeight + HISTORY_HEADING_HEIGHT + AppSpace.Xs : 0))
      }
      if (this.generalSettings.searchRecommendations) {
        ListItem() {
          Text($r('app.string.search_recommendations'))
            .fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary')).width('100%')
            .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Md, bottom: AppSpace.Md })
        }
        if (this.recommendationBooks.length === 0) {
          ListItem() {
            if (this.recommendationsLoading) {
              Row({ space: AppSpace.Xs }) {
                LoadingProgress().width(20).height(20).color(AppColor.Brand)
                Text($r('app.string.search_recommend_loading')).fontSize(AppFont.Caption)
                  .fontColor($r('sys.color.font_tertiary'))
              }.width('100%').height(72).justifyContent(FlexAlign.Center)
            } else {
              Text($r('app.string.search_recommend_empty')).fontSize(AppFont.Caption)
                .fontColor($r('sys.color.font_tertiary')).width('100%').height(56)
                .textAlign(TextAlign.Center)
            }
          }
        }
        LazyForEach(this.recommendationDataSource, (book: Book) => {
          ListItem() {
            Column() { this.buildListItem(book) }.width('100%')
              .padding({ left: AppSpace.Md, right: AppSpace.Md })
          }
        }, (book: Book): string => book.id)
      }
    }
    .layoutWeight(1).width('100%').cachedCount(1)
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
      Text((index === 0 ? this.audioCount + this.textCount + this.comicCount :
        (index === 1 ? this.audioCount : index === 2 ? this.textCount : this.comicCount)).toString())
        .fontSize(11)
        .fontColor(this.searchTab === index ? HomeTheme.Accent : $r('sys.color.font_tertiary'))
    }
    .padding({ left: 9, right: 9, top: 5, bottom: 5 })
    .borderRadius(AppRadius.Pill)
    .backgroundColor(this.searchTab === index ? AppColor.BrandSoft : Color.Transparent)
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
      .attributeModifier(new SearchControlSurface())
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
            showLatestChapter: true,
            coverAspectRatio: SEARCH_COVER_ASPECT_RATIO,
            onTap: () => this.openBook(book)
          })
          this.buildGroupBadge(book)
          }.width('100%')
        }
      }, (book: Book) => this.resultDataSource.getVersionedKey(book))
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
            highPriority: false
          })
        } else if (AppTheme.IllustratedPlaceholders) {
          CoverImage({ url: book.cover, title: book.title, author: book.author,
            localPlaceholder: book.id.startsWith('import_'), imgWidth: 92,
            aspectRatioValue: SEARCH_COVER_ASPECT_RATIO, radius: AppRadius.Md })
        } else {
          Image($r('app.media.app_icon_legacy')).width(92).aspectRatio(SEARCH_COVER_ASPECT_RATIO)
            .borderRadius(AppRadius.Md).objectFit(ImageFit.Cover)
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
      if (book.latestChapterTitle) {
        Text($r('app.string.source_latest_chapter', book.latestChapterTitle))
          .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End).width('32%')
      }
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
      }, (book: Book) => this.resultDataSource.getVersionedKey(book))
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

  @LocalBuilder
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
      .attributeModifier(new SearchControlSurface())
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
      .id('search-back-button')
      .onClick(() => this.navStack.pop())

      Stack() {
        Search({ value: this.keyword, placeholder: $r('app.string.search_placeholder'),
          controller: this.searchController })
          .searchButton($r('app.string.search_action'), { fontColor: HomeTheme.Accent })
          .placeholderColor($r('sys.color.font_tertiary'))
          .placeholderFont({ size: AppFont.Body, weight: FontWeight.Regular })
          .textFont({ size: AppFont.Body, weight: FontWeight.Regular })
          .width('100%')
          .height(SEARCH_TITLE_CONTROL_HEIGHT)
          .margin(0)
          .backgroundColor(Color.Transparent)
          .borderRadius(AppRadius.Pill)
          .id('search-page-input')
          .focusable(true)
          .enableKeyboardOnFocus(true)
          .onSubmit(() => this.doSearch())
          .onChange((value: string) => {
            if (this.leavingPage) return;
            this.keyword = value;
            if (value.trim().length > 0) this.cancelRecommendations();
            else if (this.hasSearched) this.clearSearch();
            else this.scheduleRecommendations();
          })
      }
      .layoutWeight(1)
      .height(SEARCH_TITLE_CONTROL_HEIGHT)
      .borderRadius(AppRadius.Pill)
      .attributeModifier(new SearchControlSurface())

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
        .attributeModifier(new SearchControlSurface())
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

      Row() {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.funnel'))
            .fontSize(22)
            .fontColor([this.sourceFilterEnabled || this.exactSearch || this.searchByAuthor || this.searchTextOnly || this.searchAudioOnly || this.searchComicOnly
              ? AppColor.Brand : $r('sys.color.icon_primary')])
        }
          .width(SEARCH_TITLE_CONTROL_HEIGHT)
          .height(SEARCH_TITLE_CONTROL_HEIGHT)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .attributeModifier(new SearchControlSurface())
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
          .accessibilityText($r('app.string.search_options'))
          .id('search-options-button')
          .onAreaChange((_oldArea: Area, area: Area): void => {
            this.searchMenuX = Number(area.globalPosition.x) + Number(area.width);
            this.searchMenuY = Number(area.globalPosition.y) + Number(area.height);
          })
          .onClick(() => {
            this.searchController.stopEditing();
            this.sourcePickerVisible = false;
            this.searchOptionsVisible = !this.searchOptionsVisible;
          })
      }

    }
    .width('100%')
    .height(SEARCH_HEADER_HEIGHT)
    .padding({ left: AppSpace.Xs, right: AppSpace.Md })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .opacity(Math.max(0, Math.min(1, (SEARCH_HEADER_HEIGHT - this.searchCollapseOffset) / 24)))
    .visibility(this.searchCollapseOffset >= SEARCH_HEADER_HEIGHT - 0.5 ? Visibility.Hidden : Visibility.Visible)
  }

  private searchOptionsMenuOptions(): MenuOptions {
    const options = ImmersiveMenu.options((): void => {
      this.searchOptionsVisible = false;
    });
    options.anchorPosition = { x: this.searchMenuX, y: this.searchMenuY };
    options.onDisappear = (): void => { this.sourcePickerVisible = false; };
    return options;
  }

  @LocalBuilder
  buildSearchMenu() {
    // 原生菜单需要稳定的实体根节点，不能直接把条件分支作为菜单根。
    Column() {
      if (this.sourcePickerVisible) {
        this.buildSourcePicker()
      } else {
        this.buildSearchOptionsMenu()
      }
    }.onTouch(ImmersiveMenu.keepOpen)
  }

  @LocalBuilder
  buildSearchOptionsMenu() {
    Column() {
      SearchOptionItem({ label: $r('app.string.search_selected_sources'), selected: this.sourceFilterEnabled,
        onToggle: (): void => { this.openSourcePicker(); } })
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
      SearchOptionItem({
        label: $r('app.string.search_comic_only'), selected: this.searchComicOnly,
        onToggle: (): void => {
          this.searchComicOnly = !this.searchComicOnly;
          this.updateSearchOptions();
        }
      })
    }
    .width(208)
    .padding(4)
    .onTouch(ImmersiveMenu.keepOpen)
    .id('search-options-menu')
  }

  @LocalBuilder
  buildSearchHeader() {
    Column() {
      this.buildSearchTitleBar()
      this.buildSearchNavigationBottom()
    }
    .width('100%')
    .height(WindowUtils.getStatusBarHeightVp() + SEARCH_HEADER_HEIGHT +
      (this.hasSearched ? RESULT_TOOLBAR_HEIGHT : this.historyPanelHeight))
    .padding({ top: WindowUtils.getStatusBarHeightVp() })
    .translate({ y: -this.searchCollapseOffset })
    .id('search-page-header')
  }

  @LocalBuilder
  buildSearchNavigationBottom() {
    Column() {
    if (this.hasSearched) {
      this.buildResultToolbar()
    } else if (this.entryReady && this.searchHistory.length > 0) {
      Column() {
        this.buildSearchHistory()
      }
      .width('100%')
      .height(LayoutPolicy.wrapContent)
      .padding({ left: AppSpace.Md, right: AppSpace.Md })
    }
    }.width('100%')
      .height(this.hasSearched ? RESULT_TOOLBAR_HEIGHT : this.historyPanelHeight)
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        const width = Math.max(0, Number(size.width) - AppSpace.Md * 2);
        if (Math.abs(width - this.historyWidth) > 0.5) {
          this.historyWidth = width;
          this.trimHistory();
        }
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
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(HomeTheme.BgNeutral)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          // 菜单由页面实体节点持有，避免 HDS 标题栏缓存阻断显隐状态更新。
          .bindMenu(this.searchOptionsVisible, this.buildSearchMenu, this.searchOptionsMenuOptions())

        Column() {
          this.buildSearchBody()
        }
        .width('100%')
        .height('100%')
        .clip(false)
        .backgroundColor(Color.Transparent)

        // 可编辑控件必须位于目的页内容树，避免标题栏/overlay 的独立触摸链路。
        Column()
          .width('100%')
          .height(this.headerBackdropHeight + AppRadius.Xl)
          .backgroundEffect({ radius: 24, saturation: 1, brightness: 1,
            color: $r('app.color.shelf_toolbar_background') })
          .clipShape(this.headerBackdropClip())
          .hitTestBehavior(HitTestMode.None)
        this.buildSearchHeader()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(HomeTheme.BgNeutral)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .systemBarStyle(
      { statusBarContentColor: this.statusBarContentColor },
      { statusBarContentColor: this.statusBarContentColor }
    )
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(HomeTheme.BgNeutral)
    .bindMenu(this.resultGroupVisible, this.buildResultGroup, this.resultGroupMenuOptions())
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
      this.menuViewportWidth = Math.max(1, Number(size.width));
      this.menuViewportHeight = Math.max(1, Number(size.height));
    })
    .onTouch((event: TouchEvent): void => {
      if (event.type !== TouchType.Down || event.touches.length === 0 || this.resultGroupVisible ||
        this.sourcePickerVisible || this.searchOptionsVisible) return;
      this.resultMenuX = event.touches[0].x;
      this.resultMenuY = event.touches[0].y;
    })
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
