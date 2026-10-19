import { HdsNavigation, HdsNavigationTitleMode, HideMode, TitleBarContentOptions, BottomBuilderParams, BuilderOptions } from '@kit.UIDesignKit';
import { RankingBoard, RankingBook, RankingPlatform } from '../model/Ranking';
import { ImmersiveTabComponent } from '../components/ImmersiveTabComponent';
import { FrameCallback, LengthMetrics } from '@kit.ArkUI';
import { CoverImage } from '../components/CoverImage';
import { RankingPosterBackground } from '../components/RankingPosterBackground';
import { AppColor, AppMaterial, HomeTheme, AppSpace, AppRadius } from '../theme/Theme';
import { HdsCompat } from '../utils/HdsCompat';
import { WindowUtils } from '../utils/WindowUtils';
import { PlatformCompat } from '../utils/PlatformCompat';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';
import { SearchCache } from '../utils/SearchCache';
import { RankingService } from '../service/ranking/RankingService';
import { RankingPreferences, RankingCategorySetting } from '../service/ranking/RankingPreferences';
import { BookMatchService, RankingMatch, RankingMatchProgress } from '../service/ranking/BookMatchService';
import { DataService } from '../service/DataService';
import { SourceDataService } from '../service/SourceDataService';
import { BookSource } from '../model/BookSource';
import { BookPosterCarousel, BookPosterItem, BOOK_POSTER_HEIGHT, BOOK_POSTER_DECK_HEIGHT, BOOK_POSTER_COVER_WIDTH } from '../components/BookPosterCarousel';

/** 使用本机时区展示真实获取时间，避免系统区域设置改变年月日顺序或省略秒。 */
function rankingUpdateTime(timestamp: number): Resource {
  const date = new Date(timestamp);
  return $r('app.string.ranking_updated', date.getFullYear().toString(),
    (date.getMonth() + 1).toString().padStart(2, '0'), date.getDate().toString().padStart(2, '0'),
    date.getHours().toString().padStart(2, '0'), date.getMinutes().toString().padStart(2, '0'),
    date.getSeconds().toString().padStart(2, '0'));
}

// 轮播、骨架、导航收起范围和正文占位共用同一高度。
const RANKING_POSTER_HEIGHT: number = BOOK_POSTER_HEIGHT;
const RANKING_DECK_HEIGHT: number = BOOK_POSTER_DECK_HEIGHT;
// 折叠与展开共用封面尺寸，窗口增加的宽度分配给介绍，避免图片随窗口放大。
const RANKING_COVER_WIDTH: number = BOOK_POSTER_COVER_WIDTH;
const RANKING_SEARCH_HEIGHT: number = 56;
// 榜单区块：每列上下两本，列横向排列，最多六本；一屏一列，右侧露出下一列提示可滑动。
const RANKING_SECTION_COLUMN_SIZE: number = 2;
const RANKING_SECTION_ITEMS: number = 6;
const RANKING_SECTION_ROW_HEIGHT: number = 94;
const RANKING_SECTION_ROW_GAP: number = 4;
const RANKING_SECTION_COLUMN_GAP: number = 12;
const RANKING_SECTION_HEIGHT: number = RANKING_SECTION_COLUMN_SIZE * RANKING_SECTION_ROW_HEIGHT +
  RANKING_SECTION_ROW_GAP;
// 左侧内边距 24vp，右侧固定露出 28vp 的下一列，提示还能左滑。
const RANKING_SECTION_EDGE: number = 24;
const RANKING_SECTION_PEEK: number = 28;

@ComponentV2
struct RankingBookRow {
  @Param book: RankingBook = new RankingBook();
  @Event onChoose: (book: RankingBook) => void = () => {};

  build() {
    Row({ space: 14 }) {
      Text(this.book.rank.toString().padStart(2, '0'))
        .fontSize(26).fontWeight(FontWeight.Medium).fontStyle(FontStyle.Italic)
        .fontColor(this.book.rank <= 3 ? AppColor.Brand : $r('sys.color.font_tertiary')).width(34)
      CoverImage({ url: this.book.coverUrl, imgWidth: 58,
        aspectRatioValue: this.book.contentType === 'text' ? 0.75 : 1,
        useOriginalRatio: true, maxOriginalHeight: 78,
        radius: AppRadius.Sm, imageFit: ImageFit.Contain, decodeW: 174, decodeH: 234 })
      Column({ space: 7 }) {
        Text(this.book.title).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.book.author || this.book.narrator).fontSize(12)
          .fontColor($r('sys.color.font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding({ top: 8, bottom: 8 })
    .constraintSize({ minHeight: RANKING_SECTION_ROW_HEIGHT })
    .onClick(() => this.onChoose(this.book))
    .accessibilityGroup(true).accessibilityText(this.book.title)
  }
}

/** 榜单区块的一列：上下两本；ArkTS 不使用匿名对象，用类承载。 */
class RankingColumn {
  books: RankingBook[];
  key: string;
  constructor(books: RankingBook[], key: string) {
    this.books = books;
    this.key = key;
  }
}

@ComponentV2
struct RankingSection {
  @Require @Param board: RankingBoard;
  @Event onChoose: (book: RankingBook) => void = () => {};
  @Event onMore: (board: RankingBoard) => void = () => {};
  @Local columns: RankingColumn[] = [];
  private audioData: HomeRecommendationDataSource<RankingBook> = new HomeRecommendationDataSource<RankingBook>();

  aboutToAppear(): void { this.syncBooks(); }
  @Monitor('board')
  updateBoard(): void { this.syncBooks(); }

  private syncBooks(): void {
    const books = this.board.books.slice(0, RANKING_SECTION_ITEMS);
    const columns: RankingColumn[] = [];
    for (let index = 0; index < books.length; index += RANKING_SECTION_COLUMN_SIZE) {
      const column = books.slice(index, index + RANKING_SECTION_COLUMN_SIZE);
      columns.push(new RankingColumn(column,
        column.map((book: RankingBook): string => book.id).join('|')));
    }
    this.columns = columns;
    this.audioData.setItems(books);
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 5 }) {
          Text() {
            Span(this.board.title).fontSize(23).fontWeight(FontWeight.Bold)
            Span($r('app.string.ranking_label_separator')).fontSize(16)
            Span(this.board.platformName).fontSize(16).fontWeight(FontWeight.Medium)
          }.fontColor($r('sys.color.font_primary')).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.board.fetchedAt > 0) {
            Text(rankingUpdateTime(this.board.fetchedAt)).fontSize(11).fontColor($r('sys.color.font_secondary'))
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button($r('app.string.ranking_more'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontSize(12).fontColor($r('sys.color.font_secondary')).height(44)
          .onClick(() => this.onMore(this.board))
      }.width('100%').padding({ left: 24, right: 18 })
      if (this.board.books.length === 0) {
        Text(this.board.unavailable ? $r('app.string.ranking_unavailable') : $r('app.string.ranking_loading'))
          .fontSize(13).fontColor($r('sys.color.font_tertiary')).width('100%').height(90)
      } else if (this.board.books[0]?.contentType === 'text') {
        // 一屏一列（上下两本），prevMargin 提供左侧内边距，nextMargin 露出下一列。
        Swiper() {
          ForEach(this.columns, (column: RankingColumn) => {
            Column({ space: RANKING_SECTION_ROW_GAP }) {
              ForEach(column.books, (book: RankingBook) => {
                RankingBookRow({ book: book, onChoose: this.onChoose })
              }, (book: RankingBook): string => book.id)
            }.width('100%').alignItems(HorizontalAlign.Start)
            .padding({ right: RANKING_SECTION_COLUMN_GAP })
          }, (column: RankingColumn): string => column.key)
        }.width('100%').height(RANKING_SECTION_HEIGHT)
        .loop(false).indicator(false).duration(300).curve(Curve.EaseOut)
        .prevMargin(RANKING_SECTION_EDGE).nextMargin(RANKING_SECTION_PEEK)
      } else {
        List({ space: 16 }) {
          LazyForEach(this.audioData, (book: RankingBook) => {
            ListItem() {
              Column({ space: 9 }) {
                Stack({ alignContent: Alignment.BottomStart }) {
                  CoverImage({ url: book.coverUrl, imgWidth: 152, imgHeight: 152, useFixedHeight: true,
                    radius: AppRadius.Sm, imageFit: ImageFit.Contain, decodeW: 456, decodeH: 456 })
                  Text(book.rank.toString().padStart(2, '0')).fontSize(30).fontWeight(FontWeight.Bold)
                    .fontColor(Color.White).textShadow({ radius: 10, color: '#66000000', offsetY: 2 })
                    .margin({ left: 10, bottom: 7 })
                }
                Text(book.title).fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary')).maxLines(2).height(40)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(book.narrator || book.author).fontSize(11).fontColor($r('sys.color.font_secondary'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.width(152).alignItems(HorizontalAlign.Start).onClick(() => this.onChoose(book))
            }
          }, (book: RankingBook): string => book.id)
        }.listDirection(Axis.Horizontal).height(228).width('100%').scrollBar(BarState.Off)
        .contentStartOffset(24).contentEndOffset(24).cachedCount(1)
      }
      if (this.board.stale) {
        Text($r('app.string.ranking_cached')).fontSize(11).fontColor($r('sys.color.font_tertiary'))
          .width('100%').padding({ left: 24, right: 24 })
      }
      Divider().color(AppColor.Divider).margin({ left: 24, right: 24, top: 8 })
    }.width('100%').padding({ top: 26, bottom: 4 }).alignItems(HorizontalAlign.Start)
  }
}

class RankingPosterItem {
  book: RankingBook;
  constructor(book: RankingBook) {
    this.book = book;
  }
}

@Builder
function rankingEmptyHeader() { Row().height(56) }

class RankingMatchRestoreFrame extends FrameCallback {
  private restore: () => void;
  constructor(restore: () => void) { super(); this.restore = restore; }
  onIdle(_timeLeftInNano: number): void { this.restore(); }
}

@ComponentV2
export struct RankingHomePage {
  @Param visible: boolean = true;
  @BuilderParam headerBuilder: () => void = rankingEmptyHeader;
  @Event onBookTap: (id: string, resume: () => void) => void = () => {};
  @Event onSearchTap: () => void = () => {};
  @Event onManageSources: (resume: () => void) => void = () => {};
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};
  @Event onBackHandlerChange: (handler: (() => boolean) | undefined) => void = () => {};
  @Local boards: RankingBoard[] = [];
  @Local platformId: string = '';
  @Local activeBoard: RankingBoard | undefined = undefined;
  @Local boardTransitioning: boolean = false;
  @Local posterCount: number = 0;
  @Local posterVisible: boolean = false;
  @Local posterCover: string = '';
  @Local contentHeight: number = 800;
  @Local headerOffset: number = 0;
  @Local overview: boolean = false;
  @Local loading: boolean = true;
  @Local refreshing: boolean = false;
  @Local refreshPullOffset: number = 0;
  @Local showSheet: boolean = false;
  @Local selectedBook: RankingBook = new RankingBook();
  @Local keyword: string = '';
  @Local searching: boolean = false;
  @Local sourceTotal: number = -1;
  @Local completed: number = 0;
  @Local failed: number = 0;
  @Local matchesCount: number = 0;
  @Local matchType: string = '';
  @Local allMatches: RankingMatch[] = [];
  @Local matchError: boolean = false;
  @Local opening: boolean = false;
  @Local topSafe: number = WindowUtils.getStatusBarHeightVp();
  @Local leftSafe: number = WindowUtils.getLeftSafeVp();
  @Local rightSafe: number = WindowUtils.getRightSafeVp();
  @Local platforms: RankingPlatform[] = RankingService.platforms();
  private readonly rankingSettingsListener = (): void => { this.reloadCategories(); };

  private async reloadCategories(): Promise<void> {
    try {
      const settings = await RankingPreferences.load();
      if (!this.alive) return;
      const enabled = settings.filter((item: RankingCategorySetting): boolean => item.enabled);
      this.platforms = [RankingService.platforms()[0]].concat(enabled.map((item: RankingCategorySetting): RankingPlatform =>
        new RankingPlatform(item.id, item.name)));
      this.platformData.setItems(this.platforms);
      if (!this.platforms.some((item: RankingPlatform): boolean => item.id === this.platformId)) this.platformId = '';
      const previous = this.boards;
      const all = RankingService.boards();
      const next: RankingBoard[] = [];
      for (const platform of enabled) {
        for (const board of all.filter((item: RankingBoard): boolean => item.platformId === platform.id)) {
          next.push(previous.find((item: RankingBoard): boolean => item.id === board.id) ?? board);
        }
      }
      this.boards = next;
      this.syncBoards();
      this.load(false);
    } catch (_error) {
      // 偏好读取失败时保留默认或当前配置，不覆写保存值。
      if (this.alive) this.load(false);
    }
  }
  private boardData: HomeRecommendationDataSource<RankingBoard> = new HomeRecommendationDataSource<RankingBoard>();
  private fullData: HomeRecommendationDataSource<RankingBook> = new HomeRecommendationDataSource<RankingBook>();
  private matchData: HomeRecommendationDataSource<RankingMatch> = new HomeRecommendationDataSource<RankingMatch>();
  private platformData: HomeRecommendationDataSource<RankingPlatform> = new HomeRecommendationDataSource<RankingPlatform>();
  @Local posterItems: RankingPosterItem[] = [];

  @Computed
  get posterDeckItems(): BookPosterItem[] {
    return this.posterItems.map((item: RankingPosterItem): BookPosterItem => new BookPosterItem(
      item.book.id, item.book.title, item.book.author || item.book.narrator, item.book.intro,
      item.book.coverUrl, item.book.contentType === 'text' ? 0.75 : 1));
  }

  private categoryScroller: Scroller = new Scroller();
  private posterIdentity: string = '';
  private posterPlatformId: string = '';
  private scroller: Scroller = new Scroller();
  private boardScroller: Scroller = new Scroller();
  private headerScroller: Scroller = new Scroller();
  private matchScroller: Scroller = new Scroller();
  private matchOffset: number = 0;
  private matchSuspended: boolean = false;
  private matchScrolling: boolean = false;
  private pendingMatchProgress: RankingMatchProgress | undefined = undefined;
  private readonly navigationBottomBuilder: CustomBuilder = (): void => this.navigationBottom();
  private readonly searchHeaderBuilder: CustomBuilder = (): void => this.searchHeader();
  private matcher: BookMatchService = new BookMatchService();
  private generation: number = 0;
  private matchGeneration: number = 0;
  private alive: boolean = false;
  private readonly safeAreaListener = (top: number, _bottom: number): void => {
    this.topSafe = top;
    this.leftSafe = WindowUtils.getLeftSafeVp();
    this.rightSafe = WindowUtils.getRightSafeVp();
  };

  aboutToAppear(): void {
    this.alive = true;
    this.platformData.setItems(this.platforms);
    this.onScrollerReady(this.headerScroller);
    this.onBackHandlerChange((): boolean => {
      if (this.boardTransitioning) return true;
      if (this.showSheet) { this.showSheet = false; return true; }
      if (this.activeBoard !== undefined) { this.closeBoard(); return true; }
      if (this.overview) { this.selectPlatform(''); return true; }
      return false;
    });
    WindowUtils.addSafeAreaListener(this.safeAreaListener);
    RankingPreferences.subscribe(this.rankingSettingsListener);
    this.reloadCategories();
  }

  aboutToDisappear(): void {
    RankingPreferences.unsubscribe(this.rankingSettingsListener);
    this.alive = false;
    this.pendingMatchProgress = undefined;
    this.generation++;
    this.matchGeneration++;
    this.matcher.cancel();
    WindowUtils.removeSafeAreaListener(this.safeAreaListener);
    this.onBackHandlerChange(undefined);
  }

  @Monitor('visible')
  updateHomeVisibility(): void {
    if (this.visible) {
      this.posterPlatformId = this.randomPosterPlatform(this.posterPlatformId);
      this.syncBoards();
    }
  }

  private randomPosterPlatform(previousId: string): string {
    const available = this.platforms.filter((platform: RankingPlatform): boolean =>
      platform.id.length > 0 && this.boards.some((board: RankingBoard): boolean =>
        board.platformId === platform.id && board.books.length > 0));
    // 按平台等概率抽取；存在其他可用平台时，避免连续两次抽中同一个。
    const alternatives = available.filter((platform: RankingPlatform): boolean => platform.id !== previousId);
    const candidates = alternatives.length > 0 ? alternatives : available;
    return candidates.length > 0 ? candidates[Math.floor(Math.random() * candidates.length)].id : '';
  }

  private syncBoards(): void {
    const visible = this.boards.filter((board: RankingBoard): boolean => !this.platformId || board.platformId === this.platformId);
    this.boardData.setItems(visible);
    if (!this.boards.some((board: RankingBoard): boolean =>
      board.platformId === this.posterPlatformId && board.books.length > 0)) {
      this.posterPlatformId = this.randomPosterPlatform(this.posterPlatformId);
    }
    const posterPlatformId = this.posterPlatformId;
    const posterBoards = this.boards.filter((board: RankingBoard): boolean =>
      posterPlatformId.length > 0 && board.platformId === posterPlatformId);
    const posters: RankingPosterItem[] = [];
    const seen = new Set<string>();
    // 从当前平台各榜轮流取书，最多六张；同一本书跨榜不重复。
    for (let index = 0; index < 6 && posters.length < 6; index++) {
      for (const board of posterBoards) {
        const book = board.books[index];
        if (book === undefined || seen.has(book.id) || posters.length >= 6) continue;
        seen.add(book.id);
        posters.push(new RankingPosterItem(book));
      }
    }
    const posterIdentity = posters.map((item: RankingPosterItem): string => item.book.id).join('|');
    if (this.posterIdentity !== posterIdentity) {
      this.posterIdentity = posterIdentity;
      this.posterItems = posters;
      this.posterCount = posters.length;
      this.posterCover = posters[0]?.book.coverUrl ?? '';
    }
    if (this.activeBoard !== undefined) {
      const id = this.activeBoard.id;
      const updated = this.boards.find((board: RankingBoard): boolean => board.id === id);
      if (updated !== this.activeBoard) {
        this.activeBoard = updated;
        this.fullData.setItems(updated?.books ?? []);
      }
    }
  }

  private async load(force: boolean): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) { this.loading = false; this.refreshing = false; return; }
    const generation = ++this.generation;
    this.loading = true;
    try {
      // 当前平台先刷新，精品推荐直接沿用展示顺序（懒人、起点、喜马拉雅）。
      const snapshot = this.boards.filter((board: RankingBoard): boolean =>
        !this.platformId || board.platformId === this.platformId).concat(
        this.boards.filter((board: RankingBoard): boolean =>
          this.platformId.length > 0 && board.platformId !== this.platformId));
      await RankingService.loadProgressively(context, snapshot, force,
        (loaded: RankingBoard): void => {
          this.boards = this.boards.map((entry: RankingBoard): RankingBoard => entry.id === loaded.id ? loaded : entry);
          this.syncBoards();
        }, (): boolean => generation === this.generation);
    } finally {
      if (generation === this.generation) { this.loading = false; this.refreshing = false; }
    }
  }

  private selectPlatform(id: string): void {
    if (id.length === 0) {
      this.posterPlatformId = this.randomPosterPlatform(this.posterPlatformId);
    } else {
      this.posterPlatformId = id;
    }
    this.platformId = id;
    this.overview = false;
    this.syncBoards();
    // 不操作纵向滚动控制器；平台切换保持当前海报与分类栏位置。
  }

  private openBoard(board: RankingBoard): void {
    if (this.boardTransitioning || this.activeBoard !== undefined) return;
    this.boardScroller = new Scroller();
    this.onScrollerReady(this.boardScroller);
    this.fullData.setItems(board.books);
    this.transitionBoard(board);
  }

  private closeBoard(): void {
    if (this.boardTransitioning || this.activeBoard === undefined) return;
    this.onScrollerReady(this.headerScroller);
    this.transitionBoard(undefined);
  }

  private transitionBoard(board: RankingBoard | undefined): void {
    this.boardTransitioning = true;
    this.getUIContext().animateTo({
      duration: WindowUtils.getPageTransitionDuration(), curve: Curve.EaseInOut,
      onFinish: (): void => { if (this.alive) this.boardTransitioning = false; }
    }, (): void => { this.activeBoard = board; });
  }

  private openMatch(book: RankingBook): void {
    this.selectedBook = book;
    this.keyword = BookMatchService.keyword(book);
    this.matchType = '';
    this.matchSuspended = false;
    this.matchOffset = 0;
    this.showSheet = true;
    this.searchMatches();
  }

  private async searchMatches(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.keyword.trim()) return;
    const generation = ++this.matchGeneration;
    this.matchScrolling = false;
    this.pendingMatchProgress = undefined;
    this.searching = true;
    this.matchError = false;
    this.sourceTotal = -1;
    this.completed = 0;
    this.failed = 0;
    this.matchesCount = 0;
    this.allMatches = [];
    this.matchOffset = 0;
    this.matchData.setItems([]);
    try {
      await this.matcher.search(context, this.selectedBook, this.keyword.trim(), (progress: RankingMatchProgress): void => {
        if (generation !== this.matchGeneration || !this.alive) return;
        // 拖动和惯性滚动期间保留当前顺序，停止后一次性应用最新结果。
        if (this.matchScrolling) this.pendingMatchProgress = progress;
        else this.applyMatchProgress(progress);
      });
    } catch (_error) {
      if (generation === this.matchGeneration) this.matchError = true;
    } finally {
      if (generation === this.matchGeneration) this.searching = false;
    }
  }

  private applyMatchProgress(progress: RankingMatchProgress): void {
    this.sourceTotal = progress.total;
    this.completed = progress.completed;
    this.failed = progress.failed;
    // 单源失败或返回空结果只更新进度，不触发 LazyForEach 全量刷新。
    if (progress.matches.length === this.allMatches.length &&
      progress.matches.every((match: RankingMatch, index: number): boolean => match === this.allMatches[index])) return;
    this.allMatches = progress.matches.slice();
    this.filterMatches();
  }

  private finishMatchScroll(): void {
    this.matchScrolling = false;
    const progress = this.pendingMatchProgress;
    this.pendingMatchProgress = undefined;
    if (this.alive && progress) this.applyMatchProgress(progress);
  }

  private filterMatches(): void {
    const visible = this.allMatches.filter((match: RankingMatch): boolean =>
      this.matchType.length === 0 || match.book.contentType === this.matchType);
    this.matchesCount = visible.length;
    this.matchData.setItems(visible);
  }

  private selectMatchType(type: string): void {
    if (type === this.matchType) return;
    this.matchType = type;
    this.matchOffset = 0;
    this.filterMatches();
    this.matchScroller.scrollEdge(Edge.Top);
  }

  private async chooseMatch(match: RankingMatch): Promise<void> {
    if (this.opening) return;
    this.opening = true;
    const selected = this.selectedBook;
    const generation = this.matchGeneration;
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) return;
      const sources = await SourceDataService.getEnabledSources();
      if (!sources.some((source: BookSource): boolean => source.bookSourceUrl === match.book.sourceUrl)) {
        throw new Error('Selected source is no longer enabled');
      }
      await DataService.upsertCachedBook(match.book);
      await BookMatchService.remember(context, selected, match);
      if (!this.alive || generation !== this.matchGeneration || !this.showSheet) return;
      SearchCache.put(match.book);
      this.matchSuspended = true;
      this.matchOffset = this.matchScroller.currentOffset().yOffset;
      this.showSheet = false;
      this.onBookTap(match.book.id, (): void => {
        if (!this.alive || this.selectedBook.id !== selected.id) return;
        this.matchSuspended = false;
        this.showSheet = true;
      });
    } catch (_error) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ranking_open_failed') });
      } catch (_ignored) { /* 页面离开时不显示提示。 */ }
    } finally { this.opening = false; }
  }

  private manageSources(): void {
    this.showSheet = false;
    this.onManageSources((): void => {
      if (!this.alive) return;
      this.showSheet = true;
      this.searchMatches();
    });
  }

  @Builder
  private heroContent() {
    if (this.posterCount > 0) {
      BookPosterCarousel({ items: this.posterDeckItems,
        autoPlay: this.visible && this.posterVisible && this.activeBoard === undefined && !this.boardTransitioning && !this.showSheet,
        onChoose: (item: BookPosterItem): void => {
          const poster = this.posterItems.find((entry: RankingPosterItem): boolean => entry.book.id === item.id);
          if (poster !== undefined) this.openMatch(poster.book);
        },
        onCoverChange: (cover: string): void => { this.posterCover = cover; },
        onVerticalScroll: (offset: number): void => this.scrollFromPoster(offset),
        onVerticalFling: (velocity: number): void => this.flingFromPoster(velocity) })
      .onVisibleAreaChange([0, 0.5, 1], (visible: boolean, ratio: number): void => { this.posterVisible = visible && ratio >= 0.5; })
    } else if (this.loading) {
      Row({ space: 16 }) {
        Column({ space: 14 }) {
          Row().height(22).width('80%').backgroundColor(AppColor.Divider).borderRadius(6)
          Row().height(16).width('55%').backgroundColor(AppColor.Divider).borderRadius(5)
          LoadingProgress().width(24).height(24).color(AppColor.Brand)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Stack() {
          Row().width(RANKING_COVER_WIDTH).height(RANKING_COVER_WIDTH / 0.75)
            .borderRadius(AppRadius.Sm).backgroundColor(AppColor.Divider)
        }.width(RANKING_COVER_WIDTH).height(RANKING_DECK_HEIGHT)
      }.height(RANKING_POSTER_HEIGHT).width('100%')
        .padding({ left: 24, right: 42, top: 8, bottom: 16 })
    }
  }

  @Builder
  private platformTabs() {
    Row({ space: AppSpace.Xs }) {
      ImmersiveTabComponent({ label: $r('app.string.home_categories'), fitContent: true,
        selected: this.overview, onTap: (): void => { this.overview = true; } })
      List({ space: AppSpace.Xs, scroller: this.categoryScroller }) {
        LazyForEach(this.platformData, (platform: RankingPlatform) => {
          ListItem() {
            ImmersiveTabComponent({ label: platform.name, fitContent: true,
              selected: !this.overview && this.platformId === platform.id,
              onTap: (): void => this.selectPlatform(platform.id) })
          }
        }, (platform: RankingPlatform): string => platform.id || 'recommendations')
      }.layoutWeight(1).height(34).listDirection(Axis.Horizontal).scrollBar(BarState.Off)
      // 与书源首页一致，保留两侧渐隐，材质随背景实时绘制。
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(24) })
      .renderGroup(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).cachedCount(1)
      if (this.isSearchCollapsed) {
        Stack() {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(21).fontColor([$r('sys.color.icon_primary')])
          }.width(42).height(42).borderRadius(AppRadius.Pill)
            .backgroundColor(Color.Transparent)
            .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveThin))
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
            .onClick(() => this.onSearchTap())
        }.width(42).height(42)
      }
    }.height(48).width('100%').padding({ left: AppSpace.Md, right: AppSpace.Md, top: 3, bottom: 3 })
  }

  @Builder
  private categoryOverview() {
    Column({ space: 12 }) {
      ForEach(this.platforms.filter((platform: RankingPlatform): boolean => platform.id.length > 0),
        (platform: RankingPlatform) => {
          Column({ space: 12 }) {
            Text(platform.name).fontSize(19).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
            Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(10) } }) {
              ForEach(this.boards.filter((board: RankingBoard): boolean => board.platformId === platform.id),
                (board: RankingBoard) => {
                  Button(board.title, { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor($r('sys.color.font_primary'))
                    .height(44).backgroundColor(AppColor.Divider).onClick(() => this.openBoard(board))
                }, (board: RankingBoard): string => board.id)
            }.width('100%')
          }.alignItems(HorizontalAlign.Start).padding(18).width('100%').borderRadius(16)
          .backgroundColor(AppColor.GlassSheetControlTint)
        }, (platform: RankingPlatform): string => platform.id)
    }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 24 })
  }

  @Builder
  private refreshIndicator() {
    Row() {
      if (this.refreshing) {
        LoadingProgress().width(24).height(24).color(AppColor.Brand)
      } else {
        Progress({ value: Math.min(100, this.refreshPullOffset / 96 * 100), total: 100, type: ProgressType.Ring })
          .width(24).height(24).color(AppColor.Brand).backgroundColor(Color.Transparent)
          .style({ strokeWidth: 2, enableSmoothEffect: false })
      }
    }.width('100%').height(this.refreshPullOffset).justifyContent(FlexAlign.Center)
      .opacity(Math.min(1, this.refreshPullOffset / 24)).clip(true)
  }

  @Builder
  private emptyRefreshIndicator() {
    Column().width(0).height(0)
  }

  @Builder
  private sheetContent() {
    Column({ space: 16 }) {
        Row({ space: 14 }) {
          CoverImage({ url: this.selectedBook.coverUrl, imgWidth: 54,
            aspectRatioValue: this.selectedBook.contentType === 'text' ? 0.75 : 1,
            useOriginalRatio: true, maxOriginalHeight: 72,
            radius: AppRadius.Sm, imageFit: ImageFit.Contain })
          Column({ space: 7 }) {
            Text(this.selectedBook.title).fontSize(18).fontWeight(FontWeight.Bold).maxLines(2)
              .width('100%').fontColor($r('sys.color.font_primary'))
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.selectedBook.author || this.selectedBook.narrator).fontSize(12).maxLines(1)
              .width('100%').fontColor($r('sys.color.font_secondary'))
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').padding({ right: 40 })
        Search({ value: this.keyword, placeholder: $r('app.string.ranking_search_keyword') })
          .height(44).searchButton($r('app.string.ranking_search'), { fontColor: $r('sys.color.font_primary') })
          .onChange((text: string): void => { this.keyword = text; })
          .onSubmit(() => this.searchMatches())
        Row({ space: 8 }) {
          ImmersiveTabComponent({ label: $r('app.string.shelf_filter_all_count', this.allMatches.length),
            fitContent: true, selected: this.matchType === '', onTap: (): void => this.selectMatchType('') })
          ImmersiveTabComponent({ label: $r('app.string.shelf_filter_audio_count',
            this.allMatches.filter((match: RankingMatch): boolean => match.book.contentType === 'audio').length),
            fitContent: true, selected: this.matchType === 'audio', onTap: (): void => this.selectMatchType('audio') })
          ImmersiveTabComponent({ label: $r('app.string.shelf_filter_text_count',
            this.allMatches.filter((match: RankingMatch): boolean => match.book.contentType === 'text').length),
            fitContent: true, selected: this.matchType === 'text', onTap: (): void => this.selectMatchType('text') })
          ImmersiveTabComponent({ label: $r('app.string.shelf_filter_comic_count',
            this.allMatches.filter((match: RankingMatch): boolean => match.book.contentType === 'comic').length),
            fitContent: true, selected: this.matchType === 'comic', onTap: (): void => this.selectMatchType('comic') })
        }.width('100%').height(40)
        if (this.searching) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color(AppColor.Brand)
            Text($r('app.string.ranking_matching', this.completed, Math.max(0, this.sourceTotal)))
              .fontSize(12).fontColor($r('sys.color.font_secondary'))
          }.width('100%')
        } else if (this.sourceTotal === 0) {
          Text($r('app.string.ranking_no_sources')).fontSize(14).fontColor($r('sys.color.font_secondary'))
            .width('100%').padding({ top: 14, bottom: 14 })
        } else if (this.matchesCount === 0) {
          Text(this.matchError || this.failed > 0 ? $r('app.string.ranking_match_failed') : $r('app.string.ranking_no_match'))
            .fontSize(14).fontColor($r('sys.color.font_secondary')).width('100%')
        } else {
          Text($r('app.string.ranking_choose_version')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
        }
        List({ space: 8, scroller: this.matchScroller }) {
          LazyForEach(this.matchData, (match: RankingMatch) => {
            ListItem() {
              Column({ space: 7 }) {
                Row() {
                  Text(match.sourceName).fontSize(12).fontColor($r('sys.color.font_secondary')).layoutWeight(1).maxLines(1)
                  Text(match.book.contentType === 'comic' ? $r('app.string.comic_type') : match.book.contentType === 'text' ? $r('app.string.search_type_text') : $r('app.string.search_type_audio'))
                    .fontSize(10).fontColor($r('sys.color.font_secondary')).margin({ right: 8 })
                  if (match.remembered) {
                    Text($r('app.string.ranking_last_choice')).fontSize(10).fontColor($r('sys.color.font_secondary'))
                  }
                }.width('100%')
                Text(match.book.title).fontSize(16).fontWeight(FontWeight.Medium).maxLines(2)
                  .fontColor($r('sys.color.font_primary')).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(match.book.author || match.book.intro).fontSize(12).maxLines(2)
                  .fontColor($r('sys.color.font_secondary')).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.width('100%').padding(14).alignItems(HorizontalAlign.Start).borderRadius(14)
              .backgroundColor($r('app.color.ranking_match_surface'))
              .border({ width: 1, color: $r('app.color.ranking_match_border') })
              .enabled(!this.opening)
              .onClick(() => this.chooseMatch(match))
            }
          }, (match: RankingMatch): string => `${match.book.sourceUrl}\u001f${match.book.bookUrl}`)
        }.width('100%').layoutWeight(1).cachedCount(4)
        .onScrollStart((): void => { this.matchScrolling = true; })
        .onScrollStop((): void => this.finishMatchScroll())
        if (!this.searching && this.matchesCount === 0) {
          Button($r('app.string.ranking_manage_sources'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .fontColor($r('sys.color.font_primary')).height(44).onClick(() => this.manageSources())
        }
    }.width('100%').height('100%').padding({ left: 24, right: 24, top: 14, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  @Computed
  get headerRange(): number { return RANKING_SEARCH_HEIGHT + RANKING_POSTER_HEIGHT; }

  @Computed
  get posterBackgroundHeight(): number { return this.topSafe + this.headerRange + 48; }

  @Computed
  get searchViewportHeight(): number {
    return Math.max(0, RANKING_SEARCH_HEIGHT - this.headerOffset);
  }

  @Computed
  get isSearchCollapsed(): boolean { return this.headerOffset >= this.headerRange - 0.5; }

  @Computed
  get searchTitleContent(): TitleBarContentOptions {
    const content: TitleBarContentOptions = {
      title: { mainTitle: '' }, stackBuilder: this.searchHeaderBuilder
    };
    if (PlatformCompat.supports(26)) {
      const builder: BuilderOptions = { builder: this.searchHeaderBuilder, updated: false };
      content.stackBuilderContent = builder;
    }
    return content;
  }

  @Computed
  get navigationTitleContent(): TitleBarContentOptions {
    const bottom: BottomBuilderParams = {
      builder: this.navigationBottomBuilder,
      height: RANKING_POSTER_HEIGHT + 48
    };
    if (PlatformCompat.supports(26)) {
      const builderContent: BuilderOptions = { builder: this.navigationBottomBuilder, updated: false };
      bottom.builderContent = builderContent;
    }
    const content: TitleBarContentOptions = {
      title: { mainTitle: '' }, bottomBuilder: bottom
    };
    return content;
  }

  private scrollFromPoster(offset: number): void {
    if (this.activeBoard !== undefined || this.boardTransitioning) return;
    // 标题层不属于 Scroll 子树，显式将纵向拖动交给既有的两级滚动容器。
    if (offset > 0) {
      const headerDelta = Math.min(offset, Math.max(0, this.headerRange - this.headerScroller.currentOffset().yOffset));
      this.headerScroller.scrollBy(0, headerDelta);
      if (offset > headerDelta) this.scroller.scrollBy(0, offset - headerDelta);
    } else {
      const listDelta = Math.max(offset, -Math.max(0, this.scroller.currentOffset().yOffset));
      this.scroller.scrollBy(0, listDelta);
      if (offset < listDelta) this.headerScroller.scrollBy(0, offset - listDelta);
    }
  }

  private flingFromPoster(velocity: number): void {
    if (this.activeBoard !== undefined || this.boardTransitioning) return;
    try {
      const headerOffset = this.headerScroller.currentOffset().yOffset;
      if ((velocity < 0 && headerOffset < this.headerRange - 0.5) ||
        (velocity > 0 && this.scroller.currentOffset().yOffset < 0.5)) {
        this.headerScroller.fling(velocity);
      } else {
        this.scroller.fling(velocity);
      }
    } catch (_error) { /* 页面离开时滚动控制器可能已解绑。 */ }
  }

  private syncHeaderScroll(): void {
    const previousOffset = this.headerOffset;
    this.headerOffset = Math.max(0, Math.min(this.headerRange, this.headerScroller.currentOffset().yOffset));
    // 首页双击回顶时联动正文；独立榜单不改变这两个滚动控制器。
    if (this.activeBoard === undefined && previousOffset >= 0.5 &&
      this.headerOffset < 0.5 && this.scroller.currentOffset().yOffset > 0.5) {
      this.scroller.scrollEdge(Edge.Top);
    }
  }

  @LocalBuilder
  private searchHeader() {
    Row() { this.headerBuilder() }
      .width('100%').height(RANKING_SEARCH_HEIGHT)
      .translate({ y: -Math.min(RANKING_SEARCH_HEIGHT, this.headerOffset) })
      .opacity(Math.min(1, this.searchViewportHeight / 24))
      .visibility(this.searchViewportHeight <= 0.5 ? Visibility.Hidden : Visibility.Visible)
  }

  @LocalBuilder
  private navigationBottom() {
    Column() {
      Column() { this.heroContent() }.width('100%').height(RANKING_POSTER_HEIGHT)
        .flexShrink(0).clip(true)
        .opacity(Math.max(0, Math.min(1, (this.headerRange - this.headerOffset) / 64)))
        .enabled(!this.isSearchCollapsed)
      this.platformTabs()
    }.width('100%').height(RANKING_POSTER_HEIGHT + 48)
  }

  @Builder
  private rankingNavigation() {
    // 与书源首页相同：整段导航随外层 Scroll 移动，内部标题和占位始终保持完整高度。
    HdsNavigation() {
      Column() {
        Column().width('100%').height(this.topSafe + this.headerRange + 48)
        this.rankingContent()
      }.width('100%').clip(false).backgroundColor(Color.Transparent)
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: this.navigationTitleContent,
      style: {
        scrollEffectOpts: { scrollEffectType: HdsCompat.scrollEffect },
        originalStyle: { backgroundStyle: { backgroundColor: Color.Transparent } },
        scrollEffectStyle: { backgroundStyle: { backgroundColor: Color.Transparent } },
        thermoCtrl: true, systemMaterialEffect: HdsCompat.material
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(true).mode(NavigationMode.Stack)
    .bindToScrollable([this.scroller])
    .systemBarStyle({ statusBarContentColor: '#FFFFFFFF' },
      { statusBarContentColor: '#FF000000' })
    .width('100%').height(this.contentHeight + this.headerRange).flexShrink(0)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private rankingContent() {
    // 首页始终保留在树中，榜单使用独立列表，返回无需重建或回填滚动位置。
    List({ scroller: this.scroller }) {
      ListItemGroup() {
        if (this.overview) {
          ListItem() { this.categoryOverview() }
        } else if (!this.loading && this.boards.length === 0) {
          ListItem() {
            Text($r('app.string.ranking_categories_empty')).fontSize(14)
              .fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
              .width('100%').padding(32)
          }
        } else {
          LazyForEach(this.boardData, (board: RankingBoard) => {
            ListItem() {
              RankingSection({ board: board, onChoose: (book: RankingBook): void => this.openMatch(book),
                onMore: (item: RankingBoard): void => this.openBoard(item) })
            }
          }, (board: RankingBoard): string => `${board.id}:${board.fetchedAt}:${board.stale}:${board.unavailable}`)
        }
      }
      ListItem() {
        Text($r('app.string.ranking_footer')).fontSize(11).fontColor($r('sys.color.font_tertiary'))
          .textAlign(TextAlign.Center).width('100%').padding({ top: 30, bottom: 120, left: 24, right: 24 })
      }
    }.width('100%').height(Math.max(1, this.contentHeight - this.topSafe - 48))
    .scrollBar(BarState.Off).cachedCount(1)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
    // 外层抵消整页下拉以固定海报和分类；仅正文下移，为分类下方的刷新指示器留出空间。
    .translate({ y: this.refreshPullOffset })
    // 与书源首页一致：让滚出视口的书籍继续绘制在分类胶囊背后，供沉浸材质采样。
    .clip(false).backgroundColor(Color.Transparent)
  }

  @Builder
  private boardPage(board: RankingBoard) {
    HdsNavigation() {
      Refresh({ refreshing: $$this.refreshing, builder: this.emptyRefreshIndicator() }) {
        List({ scroller: this.boardScroller }) {
          ListItem() {
            Column({ space: 10 }) {
              Text() {
                Span(board.title).fontSize(34).fontWeight(FontWeight.Bold)
                Span($r('app.string.ranking_label_separator')).fontSize(22)
                Span(board.platformName).fontSize(22).fontWeight(FontWeight.Medium)
              }.fontColor($r('sys.color.font_primary')).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(board.fetchedAt > 0
                ? rankingUpdateTime(board.fetchedAt)
                : $r('app.string.ranking_unavailable')).fontSize(11).fontColor($r('sys.color.font_secondary'))
              if (board.stale) {
                Text($r('app.string.ranking_cached')).fontSize(11).fontColor($r('sys.color.font_tertiary'))
              }
              Text($r('app.string.ranking_top_count', board.books.length))
                .fontSize(11).fontColor($r('sys.color.font_tertiary'))
            }.padding(24).width('100%').alignItems(HorizontalAlign.Start)
          }
          LazyForEach(this.fullData, (book: RankingBook) => {
            ListItem() {
              Column() {
                RankingBookRow({ book: book, onChoose: (item: RankingBook): void => this.openMatch(item) })
              }.padding({ left: 24, right: 24 })
            }
          }, (book: RankingBook): string => book.id)
          ListItem() {
            Text($r('app.string.ranking_footer')).fontSize(11).fontColor($r('sys.color.font_tertiary'))
              .textAlign(TextAlign.Center).width('100%').padding({ top: 30, bottom: 120, left: 24, right: 24 })
          }
        }.width('100%').height('100%').contentStartOffset(this.topSafe + 56)
        .scrollBar(BarState.Off).cachedCount(1)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }.width('100%').height('100%').onRefreshing(() => this.load(true))
      .onOffsetChange((offset: number): void => { this.refreshPullOffset = Math.max(0, offset); })
      .refreshOffset(96).pullDownRatio(0.5)
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: { title: { mainTitle: '' }, backIcon: {
        icon: $r('sys.symbol.chevron_left'), action: (): void => this.closeBoard()
      } },
      style: { scrollEffectOpts: { scrollEffectType: HdsCompat.scrollEffect },
        originalStyle: {
          contentStyle: { backIconStyle: { iconColor: $r('sys.color.icon_primary') } }
        },
        scrollEffectStyle: {
          contentStyle: { backIconStyle: { iconColor: $r('sys.color.icon_primary') } }
        },
        thermoCtrl: true, systemMaterialEffect: HdsCompat.material }
    })
    .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(false).mode(NavigationMode.Stack)
    .bindToScrollable([this.boardScroller])
    .systemBarStyle({ statusBarContentColor: '#FFFFFFFF' },
      { statusBarContentColor: '#FF000000' })
    .width('100%').height('100%').backgroundColor(HomeTheme.BgNeutral)
    .padding({ left: this.leftSafe, right: this.rightSafe })
    .transition(TransitionEffect.move(TransitionEdge.END))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
        Stack({ alignContent: Alignment.Top }) {
          RankingPosterBackground({ cover: this.posterCover, imageHeight: this.posterBackgroundHeight })
          Column().width('100%').height(this.posterBackgroundHeight)
            .linearGradient({ angle: 180, colors: [[Color.Transparent, 0.25], [HomeTheme.BgNeutral, 1]] })
        }.width('100%').height(this.posterBackgroundHeight)
          .translate({ y: -this.headerOffset }).clip(true).hitTestBehavior(HitTestMode.None)
          .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
            [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.END])
          .accessibilityLevel('no')
      HdsNavigation() {
        Refresh({ refreshing: $$this.refreshing, builder: this.emptyRefreshIndicator() }) {
          Scroll(this.headerScroller) {
            Column() { this.rankingNavigation() }
              .width('100%').height(this.contentHeight + this.headerRange).clip(false)
              .translate({ y: -this.refreshPullOffset })
          }.width('100%').height('100%').scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).clip(false)
            .onDidScroll((): void => this.syncHeaderScroll())
        }.onRefreshing(() => this.load(true)).width('100%').height('100%')
        .onOffsetChange((offset: number): void => { this.refreshPullOffset = Math.max(0, offset); })
        .refreshOffset(96).pullDownRatio(0.5)
        .pullToRefresh(this.headerOffset < 0.5)
      }
      .titleBar({
        avoidLayoutSafeArea: true,
        content: this.searchTitleContent,
        style: {
          // 外层仅承载搜索，不创建会覆盖内层分类前景的模糊/材质层。
          scrollEffectOpts: { enableScrollEffect: false },
          originalStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent,
              maskExtraHeight: 0 },
            contentStyle: { backIconStyle: { iconColor: $r('sys.color.icon_primary') } }
          },
          scrollEffectStyle: {
            backgroundStyle: { backgroundColor: Color.Transparent,
              maskExtraHeight: 0 },
            contentStyle: { backIconStyle: { iconColor: $r('sys.color.icon_primary') } }
          },
          thermoCtrl: true
        }
      })
      .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(true).mode(NavigationMode.Stack)
      .bindToScrollable([this.headerScroller]).backgroundColor(Color.Transparent)
      .dynamicHideTitleBar({
        hideTitleArea: true,
        hideBottomBuilder: true,
        hideStatusBar: false,
        mode: HideMode.SCROLL_UP_TO,
        hideRatio: 1.0
      })
      .padding({ left: this.leftSafe, right: this.rightSafe })
      .enabled(this.activeBoard === undefined)
      .accessibilityLevel(this.activeBoard === undefined ? 'auto' : 'no-hide-descendants')
      .systemBarStyle({ statusBarContentColor: '#FFFFFFFF' },
        { statusBarContentColor: '#FF000000' })
      if (this.activeBoard !== undefined) {
        this.boardPage(this.activeBoard)
      }
      if (this.refreshPullOffset > 0) {
        Column() { this.refreshIndicator() }.width('100%')
          .position({ x: 0, y: this.topSafe + (this.activeBoard === undefined
            ? Math.max(0, this.headerRange - this.headerOffset) + 48 : RANKING_SEARCH_HEIGHT) })
          .hitTestBehavior(HitTestMode.None)
      }
    }.width('100%').height('100%').backgroundColor(HomeTheme.BgNeutral)
    .enabled(!this.boardTransitioning)
    .clip(true)
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      const height: number = Number(size.height);
      if (Number.isFinite(height) && height > 0) this.contentHeight = height;
    })
    .bindSheet($$this.showSheet, this.sheetContent(), {
      height: '92%', preferType: SheetType.BOTTOM, showClose: true, dragBar: true,
      backgroundColor: AppMaterial.SheetBackground, blurStyle: AppMaterial.SheetBlur, systemMaterial: AppMaterial.Sheet,
      onAppear: (): void => {
        const restoreOffset: number = this.matchOffset;
        this.getUIContext().postFrameCallback(new RankingMatchRestoreFrame((): void => {
          if (this.alive && this.showSheet && restoreOffset > 0) {
            this.matchScroller.scrollTo({ xOffset: 0, yOffset: restoreOffset, animation: false });
          }
        }));
      },
      onDisappear: (): void => {
        this.finishMatchScroll();
        if (!this.showSheet && !this.matchSuspended) {
          this.matcher.cancel(); this.matchGeneration++; this.searching = false;
        }
      }
    })
  }
}
