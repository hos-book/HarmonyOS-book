import { BookCoverPolicy } from '../utils/BookCoverPolicy';
import { BookMetadataPolicy } from '../utils/BookMetadataPolicy';
import { common } from '@kit.AbilityKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppColor, AppRadius, AppSpace, AppFont, AppMaterial } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { GeneralSettings } from '../model/GeneralSettings';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { BookSourceService } from '../service/BookSourceService';
import { BookMetadataText as LocalRuleMetadataText } from '../utils/BookMetadataText';
import { DataService } from '../service/DataService';
import { PreferenceService, PlayHistoryItem } from '../service/PreferenceService';
import { AudioService } from '../service/AudioService';
import { DownloadService, DownloadUpdatePayload, EVT_DOWNLOAD_UPDATED } from '../service/DownloadService';
import { DownloadStore, DownloadBookRecord } from '../service/DownloadStore';
import { DownloadPolicy } from '../service/DownloadPolicy';
import { SourceDataService } from '../service/SourceDataService';
import { PlaybackStore } from '../service/PlaybackStore';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { TextReaderRouteParams, TextReadingPosition, EVT_READER_JUMP_CHAPTER, ReaderJumpChapterEvent } from '../model/TextReading';
import { TextReadingProgressService, EVT_TEXT_READING_PROGRESS_CHANGED } from '../service/text/TextReadingProgressService';
import { OneShotLayoutCallback, OneShotTransitionIds } from '../utils/OneShotTransition';
import { CoverImage } from '../components/CoverImage';
import { CoverAspectRatio } from '../utils/CoverAspectRatio';
import { ImmersiveCircleButton } from '../components/ImmersiveCircleButton';
import { DetailActionItem } from '../components/DetailActionItem';
import { BookGroupSheet } from '../components/BookGroupSheet';
import { BookPresentation } from '../model/BookPresentation';
import { HdsImmersiveTab } from '../components/HdsImmersiveTab';
import { ChapterSheet } from '../components/ChapterSheet';
import { BookSourceSwitchSheet } from '../components/BookSourceSwitchSheet';

const DETAIL_LOG_DOMAIN: number = 0x0000;
const DETAIL_LOG_TAG: string = 'BookDetailPage';

/**
 * 「标签 / 简介」前的图标要与后面首行文字中线对齐。
 * 做法：图标装进一个高度等于正文行高的容器并垂直居中，而不是让 Row 顶端对齐。
 */
const META_ICON_SIZE: number = 16;
const META_TAG_LINE_HEIGHT: number = 24;
const META_INTRO_LINE_HEIGHT: number = 26;

/**
 * HDS 迷你标题栏高度。详情页的顶栏按钮改由标题栏承载（见 DetailTitleBarActions），
 * 正文顶部要留出等高的占位，否则首屏标题会被标题栏压住。
 */
const DETAIL_TITLE_BAR_HEIGHT: number = 56;

/**
 * 详情页返回拦截：目录/换源弹层打开时，返回键先关弹层而不是退整页。
 * 与 PlayerPage 的 PlayerBackInterceptor 同一套做法，由 Index.ets 的
 * detail NavDestination.onBackPressed 调用。
 */
export class DetailBackInterceptor {
  private static handler: (() => boolean) | null = null;

  static set(handler: (() => boolean) | null): void {
    DetailBackInterceptor.handler = handler;
  }

  /** 返回 true 表示已消费（关掉了弹层），false 表示放行（正常退页）。 */
  static consume(): boolean {
    return DetailBackInterceptor.handler ? DetailBackInterceptor.handler() : false;
  }
}

/**
 * 详情页顶栏按钮的共享状态。
 *
 * 为什么顶栏按钮不画在详情页自己身上：
 * 详情页用 HdsNavDestination 的 titleBar + scrollEffect 出顶部沉浸模糊，而 HDS 标题栏
 * 整体 zIndex 高于 NavDestinationContent（实测 dumpLayout 里 TitleBar zIndex=2），
 * 且会阻塞兄弟节点的命中测试。结果是页面自己画的返回/收藏按钮既被模糊盖成灰影、
 * 也完全点不动（实测点爱心不生效、点返回不退页）。所以按钮必须成为标题栏内容的一部分，
 * 由 Index.ets 的 titleBar({ content: { stackBuilder } }) 渲染。
 *
 * 但按钮要读详情页的收藏态、要调详情页的方法，于是用这个单例做桥：动作回调由详情页
 * 在 aboutToAppear 里挂上，状态变化通过 onChanged 通知 Index（Index 必须改自己的 @Local
 * 才会重跑 stackBuilder，光改 @Trace 是刷不动标题栏内容的）。
 * 与 DetailBackInterceptor 同一套做法。
 */
@ObservedV2
export class DetailTitleBarState {
  @Trace isFavorite: boolean = false;
  @Trace horizontalPadding: number = 16;
  onBack: () => void = () => {};
  onToggleFavorite: () => void = () => {};
  /**
   * 状态变化通知。标题栏内容是一次性渲染的独立子树，靠 @Trace 刷不动它，
   * 只能由 Index 收到通知后改自己的 @Local，重跑 titleBar 的 stackBuilder。
   */
  onChanged: () => void = () => {};

  private static current: DetailTitleBarState = new DetailTitleBarState();

  static get(): DetailTitleBarState {
    return DetailTitleBarState.current;
  }
}

/**
 * 详情页顶栏按钮（返回 + 收藏），由 Index.ets 塞进 HDS 标题栏。
 *
 * 收藏态必须由 Index.ets 以 @Param 下发，不能在这里读 DetailTitleBarState 的 @Trace：
 * 实测标题栏内容是被 HDS 一次性渲染进独立子树的，外部 @ObservedV2 的 @Trace 变化
 * 不会触发这里重新 build（日志里 DetailTitleBarActions 只在启动时 build 了 3 次）。
 * 所以 Index 自己持一份 @Local，收藏态一变就重跑 titleBar 的 stackBuilder。
 */
@ComponentV2
export struct DetailTitleBarActions {
  @Param isFavorite: boolean = false;
  @Param horizontalPadding: number = 16;

  build() {
    Row() {
      ImmersiveCircleButton({
        icon: $r('sys.symbol.chevron_left'),
        label: $r('app.string.common_back'),
        diameter: 40,
        iconSize: 22,
        onPress: (): void => { DetailTitleBarState.get().onBack(); }
      })
      Blank()
      // 右上角放爱心：与首页精选行同一套语义（爱心 = 收藏），加入书架的能力留在操作行。
      ImmersiveCircleButton({
        icon: this.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
        label: this.isFavorite
          ? $r('app.string.home_favorite_remove')
          : $r('app.string.home_favorite_add'),
        diameter: 40,
        iconSize: 22,
        iconColor: this.isFavorite ? AppColor.Brand : $r('sys.color.font_primary'),
        onPress: (): void => { DetailTitleBarState.get().onToggleFavorite(); }
      })
    }
    .width('100%')
    .height(DETAIL_TITLE_BAR_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ left: this.horizontalPadding, right: this.horizontalPadding })
    // Transparent：自身与子节点照常响应，但不阻塞兄弟节点。
    // 注意这消不掉「顶部那条带拖不动正文」——真正阻塞的是 HDS 的 TitleBar 容器本身，
    // 这里只是别再多加一层阻塞。
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

@ComponentV2
export struct BookDetailPage {
  @Local generalSettings: GeneralSettings = GeneralSettings.current;
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';
  /**
   * 正文滚动控制器，由详情 NavDestination 传入并共用（bindToScrollable）。
   * 顶栏的沉浸渐变模糊是 HDS 按这个 Scroller 的滚动量绘制的，必须与 Scroll 是同一个实例。
   */
  @Param contentScroller: Scroller = new Scroller();
  @Param transitionCoverHidden: boolean = false;
  @Param deferEntry: boolean = false;
  @Event onCoverReady: (url: string) => void = () => {};
  private entryStarted: boolean = false;
  @Local entryMaterialStage: number = 0;
  @Local ambientOpacity: number = 0;
  @Local book: Book | null = null;
  @Local coverRatio: number = 1;
  @Local loadingDetail: boolean = true;
  @Local loadFailed: boolean = false;
  @Local isFavorite: boolean = false;
  @Local loadingToc: boolean = false;
  @Local tocFailed: boolean = false;
  private tocGeneration: number = 0;
  private detailActive: boolean = false;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
  @Local isStartingPlay: boolean = false;
  @Local lastHistory: PlayHistoryItem | null = null;
  @Local textReadingProgress: TextReadingPosition | null = null;
  @Local introExpanded: boolean = false;
  @Computed
  get displayIntro(): string {
    return LocalRuleMetadataText.intro(this.book?.intro ?? '');
  }
  @Computed
  get displayUpdateTime(): string {
    return LocalRuleMetadataText.intro(this.book?.updateTime ?? '').trim();
  }
  @Local debugInfo: string = '';
  @Local downloadTick: number = 0;
  @Local viewportWidth: number = WindowUtils.getWindowWidthVp();
  @Local viewportHeight: number = WindowUtils.getWindowHeightVp();
  /** 章节目录弹层；详情页只保留入口，目录本体与播放/阅读页共用 ChapterSheet。 */
  @Local showChapterSheet: boolean = false;
  /** 换源弹层。 */
  @Local showSourceSheet: boolean = false;
  @Local showGroupSheet: boolean = false;
  @Local savingGroup: boolean = false;
  /** 书源展示名；标签行缺 tags 时兜底展示，避免来源整页丢失。 */
  @Local sourceName: string = '';
  /** 弹层刚被关闭的时刻，用于返回键兜底（见 handleBack）。 */
  private sheetDismissedAt: number = 0;
  private static readonly SHEET_BACK_GUARD_MS: number = 600;
  private viewportUpdateTimerId: number = -1;
  /** 顶部数据行的横向滚动控制器；沉浸胶囊自己接管拖动时用它驱动滚动。 */
  private statsScroller: Scroller = new Scroller();
  private readingProgressHandler = (): void => {
    const book = this.book;
    if (!this.detailActive || !book || (book.contentType !== 'text' && book.contentType !== 'comic')) return;
    this.loadTextReadingProgress(book.id).catch((error: Error): void => {
      hilog.warn(DETAIL_LOG_DOMAIN, DETAIL_LOG_TAG, 'reading progress refresh failed: %{public}s', error.message);
    });
  };
  private downloadHandler = (evt: emitter.EventData): void => {
    const data = evt.data as DownloadUpdatePayload;
    if (!data || data.bookId !== this.bookId) return;
    this.downloadTick = this.downloadTick + 1;
  };

  aboutToAppear(): void {
    this.detailActive = true;
    hilog.info(DETAIL_LOG_DOMAIN, DETAIL_LOG_TAG, '====== BookDetailPage aboutToAppear START, bookId=%{public}s ======', this.bookId);
    // 命中 SearchCache 时同步可拿到 book,首屏立刻有内容;
    // 首帧先展示缓存内容，再推迟数据加载到转场后。
    this.primeBookFromCache();
    this.syncCoverRatio();
    this.downloadTick = this.downloadTick + 1;
    emitter.on(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
    emitter.on(EVT_TEXT_READING_PROGRESS_CHANGED, this.readingProgressHandler);
    DetailBackInterceptor.set((): boolean => this.handleBack());
    // 顶栏按钮画在 HDS 标题栏里（Index.ets 渲染），这里把动作和初始态挂上去。
    const titleBarState = DetailTitleBarState.get();
    titleBarState.onBack = (): void => this.handleTopBarBack();
    titleBarState.onToggleFavorite = (): void => { this.toggleFavorite(); };
    titleBarState.isFavorite = this.isFavorite;
    titleBarState.horizontalPadding = this.horizontalPadding();
    titleBarState.onChanged();
    WindowUtils.setStatusBarLight(false);
    this.finishEntering();
  }

  /** 收藏态变化时同步给标题栏（@Local 的赋值点很多，用 Monitor 一处兜住）。 */
  @Monitor('isFavorite')
  private syncTitleBarFavorite(monitor: IMonitor): void {
    const titleBarState = DetailTitleBarState.get();
    titleBarState.isFavorite = this.isFavorite;
    titleBarState.onChanged();
  }

  /** 顶栏返回：有弹层先关弹层，否则退页——与系统返回键同语义。 */
  private handleTopBarBack(): void {
    this.sheetDismissedAt = 0;
    if (this.handleBack()) return;
    this.navStack.pop();
  }

  /**
   * 弹层打开时优先关弹层；否则放行给 Navigation 退页。
   *
   * 注意 bindSheet 自己也会处理返回键：按下返回时它先把弹层关掉（onDisappear 里
   * showXxxSheet 已经变成 false），同一个返回事件随后才轮到 NavDestination。
   * 此时如果只看 showXxxSheet，会判定成「没有弹层」而把整页也退掉。
   * 所以额外记录「弹层刚刚关闭」的时间窗，在这个窗口内一律消费掉返回事件。
   */
  private handleBack(): boolean {
    if (this.savingGroup) return true;
    if (this.showGroupSheet) { this.showGroupSheet = false; return true; }
    if (Date.now() - this.sheetDismissedAt < 32) { this.sheetDismissedAt = 0; return true; }
    if (this.showChapterSheet) {
      this.showChapterSheet = false;
      return true;
    }
    if (this.showSourceSheet) {
      this.showSourceSheet = false;
      return true;
    }
    return false;
  }

  @Monitor('deferEntry')
  private finishEntering(): void {
    if (!this.detailActive || this.deferEntry || this.entryStarted) return;
    this.entryStarted = true;
    // 先提交封面交接和导航结束，再分帧恢复背景与五个独立材质，避免集中在结束帧。
    this.restoreEntryMaterials();
  }

  private restoreEntryMaterials(): void {
    this.getUIContext().postFrameCallback(new OneShotLayoutCallback((): void => {
      if (!this.detailActive || this.deferEntry) return;
      this.entryMaterialStage++;
      if (this.entryMaterialStage === 1) this.loadBook();
      if (this.entryMaterialStage === 2) {
        this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseInOut }, (): void => {
          this.ambientOpacity = 1;
        });
      }
      if (this.entryMaterialStage < 6) this.restoreEntryMaterials();
    }));
  }

  /** 同步从 SearchCache 取 book,让首帧有内容,后续重活推迟 */
  private primeBookFromCache(): void {
    hilog.info(DETAIL_LOG_DOMAIN, DETAIL_LOG_TAG, 'primeBookFromCache: START');
    const cached = SearchCache.get(this.bookId);
    if (cached) {
      hilog.info(DETAIL_LOG_DOMAIN, DETAIL_LOG_TAG, 'primeBookFromCache: found cached book, title=%{public}s, cover=%{public}s',
        cached.title, cached.cover.substring(0, 60));
      this.book = cached;
      // 先展示已有资料，章节加载仅影响目录区域。
      this.loadingDetail = false;
      // 音频搜索结果只有基础信息时，首帧直接展示目录骨架，避免先闪出”暂无章节信息”。
      this.loadingToc = (cached.contentType === 'text' || cached.contentType === 'comic') ? cached.chapters.length === 0 : this.needsAudioTocLoad(cached);
    } else {
      hilog.warn(DETAIL_LOG_DOMAIN, DETAIL_LOG_TAG, 'primeBookFromCache: NO cached book found in SearchCache');
    }
  }

  private needsAudioTocLoad(book: Book): boolean {
    const tocIncomplete = book.tocComplete === false || book.chapters.length === 0 ||
      (book.chapters.length === 1 && book.chapterCount > 1);
    return book.contentType !== 'text' && book.contentType !== 'comic' && tocIncomplete &&
      book.bookUrl.length > 0 && book.sourceUrl.length > 0;
  }

  aboutToDisappear(): void {
    this.detailActive = false;
    this.tocGeneration++;
    this.cancelViewportUpdateTimer();
    emitter.off(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
    emitter.off(EVT_TEXT_READING_PROGRESS_CHANGED, this.readingProgressHandler);
    DetailBackInterceptor.set(null);
    const titleBarState = DetailTitleBarState.get();
    titleBarState.onBack = (): void => {};
    titleBarState.onToggleFavorite = (): void => {};
    // 复位，避免下一本详情页首帧闪出上一本的收藏态。
    titleBarState.isFavorite = false;
    titleBarState.horizontalPadding = 16;
    titleBarState.onChanged();
    WindowUtils.setStatusBarLight(false);
  }

  private cancelViewportUpdateTimer(): void {
    if (this.viewportUpdateTimerId !== -1) {
      clearTimeout(this.viewportUpdateTimerId);
      this.viewportUpdateTimerId = -1;
    }
  }

  private handleViewportSizeChange(newValue: SizeOptions): void {
    if (typeof newValue.width !== 'number' || typeof newValue.height !== 'number') return;
    const width: number = newValue.width;
    const height: number = newValue.height;
    if (Math.abs(width - this.viewportWidth) < 1 && Math.abs(height - this.viewportHeight) < 1) return;
    this.cancelViewportUpdateTimer();
    this.viewportUpdateTimerId = setTimeout(() => {
      this.viewportUpdateTimerId = -1;
      this.viewportWidth = width;
      this.viewportHeight = height;
      // 标题栏里的按钮也要跟着断点改左右边距。
      const titleBarState = DetailTitleBarState.get();
      titleBarState.horizontalPadding = AdaptiveLayout.horizontalPadding(width, height);
      titleBarState.onChanged();
    }, 0);
  }

  private isCompactLayout(): boolean {
    return AdaptiveLayout.isCompact(this.viewportWidth, this.viewportHeight);
  }

  private horizontalPadding(): number {
    return AdaptiveLayout.horizontalPadding(this.viewportWidth, this.viewportHeight);
  }

  private detailHeroHeight(): number {
    return AdaptiveLayout.detailHeroHeight(this.viewportWidth, this.viewportHeight);
  }

  private detailCoverWidth(): number {
    return CoverAspectRatio.fittedWidth(this.coverRatio,
      AdaptiveLayout.detailCoverWidth(this.viewportWidth, this.viewportHeight),
      AdaptiveLayout.detailCoverHeight(this.viewportWidth, this.viewportHeight));
  }

  private detailCoverHeight(): number {
    return this.detailCoverWidth() / this.coverRatio;
  }

  @Monitor('book')
  private syncCoverRatio(): void {
    this.coverRatio = CoverAspectRatio.get(this.book?.cover ?? '');
  }

  private rememberCoverSize(url: string, width: number, height: number): void {
    if (url !== this.book?.cover) return;
    CoverAspectRatio.remember(url, width, height);
    this.coverRatio = CoverAspectRatio.get(url);
  }

  private displayCategories(): string[] {
    return BookMetadataPolicy.categories(LocalRuleMetadataText.intro(this.book?.category ?? ''));
  }

  private displayStatus(): ResourceStr {
    if (this.book?.completed === undefined) return '';
    return this.book.completed ? $r('app.string.shelf_status_completed') : $r('app.string.shelf_status_ongoing');
  }

  private async loadBook(): Promise<void> {
    this.loadingDetail = this.book === null;
    this.loadFailed = false;
    try {
      await this.loadBookData();
    } catch (e) {
      this.loadFailed = true;
      this.debugInfo = e instanceof Error ? e.message : String(e);
      hilog.error(DETAIL_LOG_DOMAIN, DETAIL_LOG_TAG,
        'detail load failed, id=%{public}s error=%{public}s', this.bookId, this.debugInfo);
    } finally {
      this.loadingDetail = false;
    }
  }

  private async loadBookData(): Promise<void> {
    const b = await this.findBookById(this.bookId);
    if (!this.detailActive) return;
    if (!b) {
      this.loadFailed = true;
      hilog.error(DETAIL_LOG_DOMAIN, DETAIL_LOG_TAG,
        'book lookup missed, id=%{public}s cacheSize=%{public}d', this.bookId, SearchCache.size());
      return;
    }
    if (b) {
      if (b.id.startsWith('import_') && b.chapters.length === 0) {
        b.chapters = await DataService.getChaptersForBook(b.id);
      }
      await PreferenceService.applyTocOrder(b);
      if ((b.contentType === 'text' || b.contentType === 'comic')) {
        this.book = this.copyBookForRender(b);
        this.loadingDetail = false;
        this.loadTextBook(b);
        return;
      }
      // 独立 KV 为权威:贴回跳过头尾,详情页起播也带上正确 skip(否则会用无 skip 对象喂 AudioService)
      await PreferenceService.applySkipConfig(b);
      if (!this.detailActive) return;
      // 先快速渲染基础信息
      // 本地目录恢复会修改缓存对象；V2 需要新引用才能刷新依赖 chapters 的分支。
      this.book = this.copyBookForRender(b);
      AudioService.getInstance().prewarmBookSource(b);
      DownloadService.getInstance().hydrateBookDurations(b.id).catch((_e: Error): void => {});
      this.isFavorite = await PreferenceService.isFavorite(b.id);
      this.resolveSourceName(b.sourceUrl);
      // 加载播放历史，用于"继续播放"入口
      this.loadHistory(b.id);
      // 章节懒加载
      if (this.needsAudioTocLoad(b)) {
        this.loadTocFromSource(b);
      } else {
        this.loadingToc = false;
      }
    }
  }

  private async loadTextBook(book: Book): Promise<void> {
    const startedAt = Date.now();
    const generation = ++this.tocGeneration;
    this.loadingToc = book.tocComplete === false || book.chapters.length === 0;
    this.tocFailed = false;
    try {
      this.isFavorite = await PreferenceService.isFavorite(book.id);
      await this.loadTextReadingProgress(book.id);
      const sourceBook = !this.loadingToc ? book : await BookSourceService.loadTextBook(book,
        (partial: Book): void => {
          if (!this.detailActive || generation !== this.tocGeneration) return;
          const display = this.copyBookForRender(partial);
          if (book.chapters.length > display.chapters.length) display.chapters = book.chapters.slice();
          this.book = display;
        });
      if (!this.detailActive || generation !== this.tocGeneration) return;
      const loaded = this.copyBookForRender(sourceBook);
      this.book = loaded;
      SearchCache.put(loaded);
      this.isFavorite = await PreferenceService.isFavorite(loaded.id);
      if (this.isFavorite) await DataService.upsertCachedBook(loaded);
      await this.loadTextReadingProgress(loaded.id);
      this.resolveSourceName(loaded.sourceUrl);
      hilog.info(DETAIL_LOG_DOMAIN, DETAIL_LOG_TAG,
        'text detail ready, id=%{public}s chapters=%{public}d elapsedMs=%{public}d',
        loaded.id, loaded.chapters.length, Date.now() - startedAt);
    } catch (e) {
      if (!this.detailActive || generation !== this.tocGeneration) return;
      this.tocFailed = true;
      if (book.chapters.length > 0) {
        this.book = this.copyBookForRender(book);
        SearchCache.put(book);
      }
      this.debugInfo = e instanceof Error ? e.message : String(e);
      hilog.error(DETAIL_LOG_DOMAIN, DETAIL_LOG_TAG,
        'text detail failed, id=%{public}s elapsedMs=%{public}d error=%{public}s',
        book.id, Date.now() - startedAt, this.debugInfo);
    } finally {
      if (this.detailActive && generation === this.tocGeneration) this.loadingToc = false;
    }
  }

  private copyBookForRender(book: Book): Book {
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

  private retryLoadBook(): void {
    this.loadBook();
  }

  private async loadTextReadingProgress(bookId: string): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const position = await TextReadingProgressService.get(context, bookId);
    if (this.detailActive && this.book?.id === bookId) this.textReadingProgress = position;
  }

  /** 从 Preferences 加载本书的播放历史。 */
  private async loadHistory(bookId: string): Promise<void> {
    const history = await PreferenceService.getHistory();
    const item = history.find((h) => h.bookId === bookId);
    if (item) this.lastHistory = item;
  }

  /** 解析书源展示名；失败时静默降级为不显示。 */
  private resolveSourceName(sourceUrl: string): void {
    if (sourceUrl.length === 0) return;
    SourceDataService.getSourceByUrl(sourceUrl)
      .then((source): void => {
        if (!this.detailActive || !source) return;
        if (source.bookSourceUrl !== this.book?.sourceUrl) return;
        this.sourceName = source.bookSourceName ?? '';
      })
      .catch((): void => {});
  }

  private async findBookById(id: string): Promise<Book | null> {
    const cached = SearchCache.get(id);
    if (cached && (BookSourceService.pendingAudioBook(id) !== undefined ||
      BookSourceService.pendingTextBook(id) !== undefined)) return cached;
    if (cached && cached.chapters.length > 0 && !this.needsAudioTocLoad(cached)) return cached;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (cached) {
      // 保留详情封面优先级，再恢复目录；本地读失败仍能在线加载。
      const stored = await DataService.getBookById(ctx, id).catch((): undefined => undefined);
      if (stored) BookCoverPolicy.merge(cached, stored);
      if (stored && stored.chapters.length > 0 && (stored.tocComplete !== false || cached.chapters.length === 0)) {
        cached.chapters = stored.chapters;
        cached.tocComplete = stored.tocComplete;
        cached.chapterCount = Math.max(cached.chapterCount, stored.chapterCount, stored.chapters.length);
        const restoredVariables: Record<string, string> = {};
        if (stored.variables !== undefined) {
          for (const key of Object.keys(stored.variables)) restoredVariables[key] = stored.variables[key];
        }
        if (cached.variables !== undefined) {
          for (const key of Object.keys(cached.variables)) restoredVariables[key] = cached.variables[key];
        }
        cached.variables = restoredVariables;
        cached.wordCount = cached.wordCount || stored.wordCount;
        cached.latestChapterTitle = cached.latestChapterTitle || stored.latestChapterTitle;
        cached.updateTime = cached.updateTime || stored.updateTime;
      }
      return cached;
    }
    const imported = await DataService.getBookById(ctx, id);
    if (imported) return imported;
    const record = await DownloadStore.getBook(id);
    if (record) return DownloadService.getInstance().recordToBook(record);
    return null;
  }

  private async loadTocFromSource(book: Book): Promise<void> {
    const generation = ++this.tocGeneration;
    const startedAt = Date.now();
    this.loadingToc = true;
    this.tocFailed = false;
    const fallback = this.copyBookForRender(book);
    let firstShown = false;
    try {
      await BookSourceService.loadAudioBook(book, (loaded: Book): void => {
        if (!this.detailActive || generation !== this.tocGeneration) return;
        const display = this.copyBookForRender(loaded);
        if (fallback.chapters.length > display.chapters.length) display.chapters = fallback.chapters.slice();
        this.book = display;
        this.loadingToc = loaded.tocComplete === false;
        if (!firstShown && loaded.chapters.length > 0) {
          firstShown = true;
          hilog.info(DETAIL_LOG_DOMAIN, DETAIL_LOG_TAG,
            'toc first visible, chapters=%{public}d elapsedMs=%{public}d',
            loaded.chapters.length, Date.now() - startedAt);
        }
      });
    } catch (error) {
      if (!this.detailActive || generation !== this.tocGeneration) return;
      this.tocFailed = true;
      if (fallback.chapters.length > 0) {
        this.book = fallback;
        SearchCache.put(fallback);
      }
      this.debugInfo = error instanceof Error ? error.message : String(error);
      hilog.warn(DETAIL_LOG_DOMAIN, DETAIL_LOG_TAG, 'toc load failed: %{public}s', this.debugInfo);
    } finally {
      if (this.detailActive && generation === this.tocGeneration) this.loadingToc = false;
    }
  }

  /**
   * 当前章节在完整章节列表中的索引。
   * 1) 正在播放本书:取播放章;
   * 2) 否则用最近播放历史定位节目。
   */
  private currentChapterIndex(): number {
    if (!this.book) return -1;
    if ((this.book.contentType === 'text' || this.book.contentType === 'comic')) {
      const position = this.textReadingProgress;
      if (!position || this.book.chapters.length === 0) return -1;
      return Math.max(0, Math.min(position.resourceIndex, this.book.chapters.length - 1));
    }
    if (this.playerState.currentBook && this.playerState.currentChapter
        && this.playerState.currentBook.id === this.bookId) {
      return DataService.resolveChapterIndex(
        this.book,
        this.playerState.currentChapter.id,
        this.playerState.currentChapter.title
      );
    }
    if (this.lastHistory) {
      return DataService.resolveChapterIndex(this.book, this.lastHistory.chapterId, this.lastHistory.chapterTitle);
    }
    return -1;
  }


  private async toggleFavorite(): Promise<void> {
    if (!this.book) return;
    if (this.bookId.startsWith('import_') && this.isFavorite) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '导入的书需在书架长按删除' });
      } catch (_e) { /* ignore */ }
      return;
    }
    // 收藏 id 还在、但本地快照已彻底丢失(书架占位卡场景):这一下应"补回快照、保留收藏",
    // 而不是把仅存的收藏 id 也 toggle 掉 —— 否则用户重搜后点心形,体感是"重新加入书架没用"。
    if (this.isFavorite && !this.bookId.startsWith('import_')) {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const snap = await DataService.getBookById(ctx, this.book.id);
      if (!snap) {
        const needToc = (this.book.tocComplete === false || !this.book.chapters || this.book.chapters.length === 0)
          && !!this.book.bookUrl && !!this.book.sourceUrl;
        if (needToc) {
          await this.loadTocFromSource(this.book);
        }
        await DataService.upsertCachedBook(SearchCache.get(this.book.id) ?? this.book);
        this.isFavorite = true;
        try {
          this.getUIContext().getPromptAction().showToast({ message: '已重新加入书架' });
        } catch (_e) { /* ignore */ }
        return;
      }
    }
    this.isFavorite = await PreferenceService.toggleFavorite(this.book.id);
    if (this.isFavorite) {
      // 在线书:章节还没拉到就先把 toc 拉齐再写缓存,避免书架点击时拿到空 chapters
      const needToc = (this.book.tocComplete === false || !this.book.chapters || this.book.chapters.length === 0)
        && !!this.book.bookUrl && !!this.book.sourceUrl;
      if (needToc) {
        await this.loadTocFromSource(this.book);
      }
      await DataService.upsertCachedBook(SearchCache.get(this.book.id) ?? this.book);

    }
  }

  private downloadRecord(): DownloadBookRecord | null {
    if (this.downloadTick < 0) return null;
    return DownloadService.getInstance().getBookStatus(this.bookId);
  }

  private downloadProgress(): number {
    if (this.downloadTick < 0) return 0;
    return DownloadService.getInstance().getBookProgress(this.bookId).progressPercent;
  }

  private downloadStatusText(): string {
    const record = this.downloadRecord();
    if (!record || record.chapters.length === 0) return '未下载';
    const total = record.chapters.filter((item) => item.status !== 'deleted').length;
    if (record.status === 'completed') return `已下载 ${record.downloadedCount}/${total}`;
    if (record.status === 'downloading' || record.status === 'queued') {
      return `下载中 ${record.downloadedCount}/${total} · ${Math.round(this.downloadProgress())}%`
        + `${record.failedCount > 0 ? ` · 失败 ${record.failedCount}` : ''}`;
    }
    if (record.status === 'paused') return `已暂停 ${record.downloadedCount}/${total}`;
    if (record.failedCount > 0) {
      const failed = record.chapters.find((item) => item.status === 'failed');
      const reason = failed ? DownloadPolicy.failureText(failed.failureCode
        ?? DownloadPolicy.classifyFailure(failed.failureReason)) : '';
      return `已下载 ${record.downloadedCount}/${total} · 失败 ${record.failedCount}${reason ? ` · ${reason}` : ''}`;
    }
    return `已下载 ${record.downloadedCount}/${total}`;
  }

  private currentDownloadStartIndex(): number {
    const idx = this.currentChapterIndex();
    return idx >= 0 ? idx : 0;
  }

  private showToast(message: string | Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (_e) {
      // ignore
    }
  }

  private async downloadWholeBook(): Promise<void> {
    if (!this.book) return;
    try {
      const queued = await DownloadService.getInstance().downloadBook(this.book);
      this.downloadTick = this.downloadTick + 1;
      this.showToast(queued > 0 ? $r('app.string.download_queued_all') : '没有可下载的新章节');
    } catch (_e) {
      this.showToast($r('app.string.download_operation_failed'));
    }
  }

  private async downloadNextTwenty(): Promise<void> {
    if (!this.book) return;
    try {
      const queued = await DownloadService.getInstance()
        .downloadNextChapters(this.book, this.currentDownloadStartIndex(), 20);
      this.downloadTick = this.downloadTick + 1;
      this.showToast(queued > 0 ? $r('app.string.download_queued_next_twenty') : '后续章节已下载或不可下载');
    } catch (_e) {
      this.showToast($r('app.string.download_operation_failed'));
    }
  }

  private async downloadIncremental(): Promise<void> {
    if (!this.book) return;
    try {
      const queued = await DownloadService.getInstance().downloadIncremental(this.book);
      this.downloadTick = this.downloadTick + 1;
      this.showToast(queued > 0 ? $r('app.string.download_queued_incremental') : '没有发现可下载的新章节');
    } catch (_e) {
      this.showToast($r('app.string.download_operation_failed'));
    }
  }

  private async pauseDownload(): Promise<void> {
    try {
      await DownloadService.getInstance().pauseBook(this.bookId);
      this.downloadTick = this.downloadTick + 1;
      this.showToast($r('app.string.download_paused'));
    } catch (_e) {
      this.showToast($r('app.string.download_operation_failed'));
    }
  }

  private async resumeDownload(): Promise<void> {
    try {
      await DownloadService.getInstance().resumeBook(this.bookId);
      this.downloadTick = this.downloadTick + 1;
      this.showToast($r('app.string.download_resumed'));
    } catch (_e) {
      this.showToast($r('app.string.download_operation_failed'));
    }
  }

  private confirmDeleteBookDownload(): void {
    if (!this.book) return;
    const prompt = this.getUIContext().getPromptAction();
    prompt.showDialog({
      title: $r('app.string.download_delete_title'),
      message: $r('app.string.download_delete_message'),
      buttons: [
        { text: $r('app.string.common_cancel'), color: '#8F8F8F' },
        { text: $r('app.string.download_delete_confirm'), color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        DownloadService.getInstance().deleteBookDownload(this.bookId).then(() => {
          this.downloadTick = this.downloadTick + 1;
          this.showToast($r('app.string.download_deleted'));
        }).catch(() => this.showToast($r('app.string.download_operation_failed')));
      }
    }).catch(() => this.showToast($r('app.string.download_operation_failed')));
  }

  private openPrimaryAction(chapter?: Chapter): void {
    if (this.chaptersLoading() || !this.book || this.book.chapters.length === 0 || this.isStartingPlay) return;
    if ((this.book?.contentType === 'text' || this.book?.contentType === 'comic')) {
      this.openTextReader(chapter);
      return;
    }
    this.startPlay(chapter);
  }

  private openTextReader(chapter?: Chapter): void {
    if (!this.book) return;
    if (this.book.contentType === 'comic') {
      SearchCache.put(this.book);
      const index = chapter ? DataService.resolveChapterIndex(this.book, chapter.id, chapter.title) : -1;
      this.navStack.pushPathByName('comicReader', TextReaderRouteParams.of(this.book.id, index));
      return;
    }
    const loadingBook = SearchCache.get(this.bookId);
    if (loadingBook && BookSourceService.pendingTextBook(this.bookId) !== undefined) this.book = loadingBook;
    let resourceIndex = -1;
    if (chapter) {
      resourceIndex = DataService.resolveChapterIndex(this.book, chapter.id, chapter.title);
    }
    SearchCache.put(this.book);
    // 阅读页已在栈内（从阅读页进详情）：返回原阅读页，选中章节时再跳章，避免重开丢失进度。
    const names = this.navStack.getAllPathName();
    for (let index = names.length - 2; index >= 0; index--) {
      if (names[index] !== 'reader') continue;
      // getParamByIndex 返回 unknown：按栈内 reader 路由参数断言后再校验类型与书目
      const param = this.navStack.getParamByIndex(index) as TextReaderRouteParams | undefined;
      if (param instanceof TextReaderRouteParams && param.bookId === this.book.id) {
        this.navStack.popToIndex(index);
        if (resourceIndex >= 0) {
          const event = new ReaderJumpChapterEvent();
          event.bookId = this.book.id;
          event.resourceIndex = resourceIndex;
          emitter.emit(EVT_READER_JUMP_CHAPTER, { data: event });
        }
        return;
      }
    }
    const params = TextReaderRouteParams.of(this.book.id, resourceIndex);
    this.navStack.pushPathByName('reader', params);
  }

  private async startPlay(chapter?: Chapter): Promise<void> {
    if (!this.book || this.isStartingPlay) return;
    this.isStartingPlay = true;
    // 起播使用任务持有的目录，后台追加章节会继续对播放器可见。
    const loadingBook = SearchCache.get(this.bookId);
    if (loadingBook && BookSourceService.pendingAudioBook(this.bookId) !== undefined) this.book = loadingBook;

    // 没有指定章节时，优先从历史恢复，否则用第一章
    let target: Chapter | undefined = chapter;
    let resumeProgressMs = 0;
    if (!target && this.lastHistory) {
      // 标题优先定位:连载更新/TOC 重排后旧 chapterId 会指向错误章节
      const hi = DataService.resolveChapterIndex(this.book, this.lastHistory.chapterId, this.lastHistory.chapterTitle);
      target = hi >= 0 ? this.book.chapters[hi] : undefined;
      resumeProgressMs = this.lastHistory.progressMs;
    }
    if (!target) {
      target = this.book.chapters[0];
    }
    if (!target) {
      this.isStartingPlay = false;
      return;
    }
    // ★ 用户当前正在播这本书且同章节:用 live state.progressMs(更新)替代 lastHistory.progressMs(可能旧 5s),
    //   避免从详情页继续播放反而回退进度
    if (PlaybackStore.getInstance().isCurrentChapter(this.book.id, target.id)) {
      resumeProgressMs = this.playerState.progressMs;
    }

    SearchCache.put(this.book);
    // ★ 当前在播的就是同书「且就是当前这一章」:直接 push player 不带 chapter 参数,
    //   PlayerPage 复用 live state,避免 tryResumePlay 触发 playChapterAndSeek 重置。
    //   若用户点的是别的章(target 非当前章),则走下面带 chapterId 的分支,播放选中的章。
    if (PlaybackStore.getInstance().isCurrentBook(this.book.id)
      && PlaybackStore.getInstance().isCurrentChapter(this.book.id, target.id)) {
      // 详情页入口,清理栈避免重复 player
      this.cleanStackBeforePushPlayer();
      this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
        this.navStack.pushPathByName('player', this.bookId, false);
      });
      this.isStartingPlay = false;
      return;
    }
    const playerParams: Record<string, Object> = {
      'bookId': this.bookId as Object,
      'chapterId': target.id as Object,
      'progressMs': resumeProgressMs as Object
    };
    // 详情页入口,清理栈避免重复 player
    this.cleanStackBeforePushPlayer();
    this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
      this.navStack.pushPathByName('player', playerParams, false);
    });
    this.isStartingPlay = false;
  }

  /** 从详情页进播放页前,清理栈避免重复 player。如果栈里已有 player,先 pop 到 home,再 push player */
  private cleanStackBeforePushPlayer(): void {
    const names = this.navStack.getAllPathName();
    if (!names || names.length === 0) return;
    // 栈结构:home, player?, detail, ...
    // 如果 names[1] === 'player',说明从 player 进的 detail,需要 pop 到 home
    if (names.length >= 2 && names[1] === 'player') {
      this.navStack.popToName('home');
    }
  }

  // ==================== 沉浸光感背景 ====================

  /** 氛围层总高度：铺满视口，首帧尚未拿到尺寸时用兜底值。 */
  private ambientHeight(): number {
    return this.viewportHeight > 0 ? this.viewportHeight : 800;
  }

  /** 封面主色层：低分辨率放大 + 模糊，渲染成本与首页海报背景同级。 */
  @Builder
  buildAmbientCover() {
    if (this.book!.cover && this.book!.cover.startsWith('http')) {
      Image(this.book!.cover)
        .width('100%').height(this.detailHeroHeight() / 2)
        .objectFit(ImageFit.Cover)
        .sourceSize({ width: 100, height: 140 })
        .blur(55 / 4)
    } else if (this.book!.cover && this.book!.cover.startsWith('file://')) {
      Image(this.book!.cover)
        .width('100%').height(this.detailHeroHeight() / 2)
        .objectFit(ImageFit.Cover)
        .sourceSize({ width: 100, height: 140 })
        .blur(55 / 4)
    } else if (this.book!.cover && this.book!.cover.startsWith('/')) {
      Image('file://' + this.book!.cover)
        .width('100%').height(this.detailHeroHeight() / 2)
        .objectFit(ImageFit.Cover)
        .sourceSize({ width: 100, height: 140 })
        .blur(55 / 4)
    } else if (this.book!.cover) {
      Image($rawfile(this.book!.cover))
        .width('100%').height(this.detailHeroHeight() / 2)
        .objectFit(ImageFit.Cover)
        .sourceSize({ width: 100, height: 140 })
        .blur(55 / 4)
    }
  }

  /**
   * 固定氛围背景：封面主色 + 主题遮罩。
   * 遮罩首尾都用同主题不透明色插值，避免 Color.Transparent 被当作透明黑而产生灰黑横带。
   */
  @Builder
  buildAmbientBackdrop() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.buildAmbientCover()
      }
      .width('25%')
      .height(this.detailHeroHeight() / 2)
      .renderGroup(true)
      .scale({ x: 4, y: 4, centerX: 0, centerY: 0 })
      .opacity(0.36)

      Column()
        .width('100%')
        .height(this.ambientHeight())
        .linearGradient({
          angle: 180,
          colors: [
            [$r('app.color.detail_backdrop_scrim_top'), 0.0],
            [$r('app.color.home_card_surface_soft'), 0.38],
            [$r('sys.color.comp_background_primary'), 0.62],
            [$r('sys.color.background_primary'), 0.86],
            [$r('sys.color.background_primary'), 1.0]
          ]
        })
    }
    .width('100%')
    .height(this.ambientHeight())
    .clip(true)
    .opacity(this.ambientOpacity)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }

  // ==================== 封面 + 书名 ====================

  /**
   * 标题区副标题只放作者。
   * 来源名已经由页面底部「标签」行展示（书源入库时 tags[0] 就是来源名），
   * 演播信息同理不必在这里再占一行，避免右侧三行文字把标题挤掉。
   */
  private heroSubtitle(): string {
    const author = (this.book?.author ?? '').trim();
    if (author.length > 0) return author;
    return (this.book?.narrator ?? '').trim();
  }

  @Builder
  buildHero() {
    Row({ space: AppSpace.Lg }) {
      // 封面（共享元素，飞向 PlayerPage / 飞回 BookCard）
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.book!.cover && this.book!.cover.startsWith('http')) {
          CoverImage({
            url: this.book!.cover,
            imgWidth: this.detailCoverWidth(),
            imgHeight: this.detailCoverHeight(),
            useFixedHeight: true,
            radius: AppRadius.Sm,
            imageFit: ImageFit.Contain,
            decodeW: 300,
            decodeH: 400,
            highPriority: true,
            onImageSize: (url: string, width: number, height: number): void =>
              this.rememberCoverSize(url, width, height),
            onImageReady: (url: string): void => this.onCoverReady(url)
          })
        } else if (this.book!.cover && (this.book!.cover.startsWith('/') || this.book!.cover.startsWith('file://'))) {
          // 判断与 BookCard.isLocalFile 对齐:file:// 前缀不能掉进 $rawfile 分支
          Image('file://' + this.book!.cover.replace(/^file:\/\//, ''))
            .width(this.detailCoverWidth())
            .height(this.detailCoverHeight())
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Contain)
            .onComplete((event) => {
              if (event?.loadingStatus === 0) {
                this.rememberCoverSize(this.book?.cover ?? '', event.width, event.height);
                this.onCoverReady(this.book?.cover ?? '');
              }
            })
            .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
        } else if (this.book!.cover) {
          Image($rawfile(this.book!.cover))
            .width(this.detailCoverWidth())
            .height(this.detailCoverHeight())
            .borderRadius(AppRadius.Sm)
            .objectFit(ImageFit.Contain)
            .onComplete((event) => {
              if (event?.loadingStatus === 0) {
                this.rememberCoverSize(this.book?.cover ?? '', event.width, event.height);
                this.onCoverReady(this.book?.cover ?? '');
              }
            })
            .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
        } else {
          CoverImage({ title: this.book!.title, imgWidth: this.detailCoverWidth(),
            imgHeight: this.detailCoverHeight(), useFixedHeight: true, radius: AppRadius.Sm })
            .width(this.detailCoverWidth()).height(this.detailCoverHeight())
            .borderRadius(AppRadius.Sm)
            .shadow({ radius: 8, color: '#33000000', offsetY: 2 })
        }
        // 封面上不再压来源角标：右侧标题区已展示来源名，重复且遮挡封面。
      }
      .width(this.detailCoverWidth())
      .height(this.detailCoverHeight())
      .borderRadius(AppRadius.Sm)
      .clip(true)
      .id(OneShotTransitionIds.detailCover(this.bookId))
      .opacity(this.transitionCoverHidden ? 0 : 1)
      // 图片比例变化只调整图片本身，不把下方整页内容向下推。
      .margin({
        top: (AdaptiveLayout.detailCoverHeight(this.viewportWidth, this.viewportHeight) - this.detailCoverHeight()) / 2,
        bottom: (AdaptiveLayout.detailCoverHeight(this.viewportWidth, this.viewportHeight) - this.detailCoverHeight()) / 2
      })

      Column({ space: AppSpace.Xs }) {
        Text(this.book!.title)
          .fontSize(24)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.heroSubtitle().length > 0) {
          // 作者允许两行：长笔名 / 多作者不再被截成一行省略号。
          Text(this.heroSubtitle())
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width(0)
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.horizontalPadding(),
      right: this.horizontalPadding(),
      top: this.isCompactLayout() ? 0 : AppSpace.Xs,
      bottom: AppSpace.Lg
    })
  }

  // ==================== 数据 + 操作面板（沉浸光感表面） ====================

  private displayRating(): number {
    return BookMetadataPolicy.rating(this.book?.rating, this.book?.category ?? '');
  }

  /** 无评分不显示胶囊，不用「暂无」或 0.0 分占位。 */
  private scoreText(): ResourceStr {
    const rating = this.displayRating();
    if (rating <= 0) return '';
    return $r('app.string.book_detail_score', rating.toFixed(1));
  }

  /** 更新时间只保留日期段，避免被时间戳撑爆。 */
  private displayUpdateShort(): string {
    const value = BookMetadataPolicy.text(this.displayUpdateTime);
    if (value.length === 0) return '';
    const datePart = value.split(' ')[0].split('T')[0];
    return datePart.length > 0 ? datePart : value;
  }

  /** 体量：优先字数/播放量，其次总时长，最后章节数。 */
  private displayScale(): string {
    const wordCount = BookMetadataPolicy.text(this.book?.wordCount);
    if (wordCount.length > 0) return wordCount;
    const total = this.book?.totalDuration ?? 0;
    if (total > 0) return this.formatTotalDuration(total);
    const count = Math.max(this.book?.chapterCount ?? 0, this.book?.chapters.length ?? 0);
    if (count <= 0) return '';
    return `${count}${(this.book?.contentType === 'text' || this.book?.contentType === 'comic') ? '章' : '集'}`;
  }

  private formatTotalDuration(seconds: number): string {
    const hours = Math.floor(seconds / 3600);
    if (hours > 0) return `${hours}小时`;
    const minutes = Math.floor(seconds / 60);
    return `${minutes > 0 ? minutes : 1}分钟`;
  }

  /** 只读信息使用原生 HDS 沉浸胶囊，横向滑动联动外层 Scroll。 */
  @Builder
  buildStatsRow() {
    Scroll(this.statsScroller) {
      Row({ space: AppSpace.Sm }) {
        ForEach(this.displayCategories(), (category: string) => {
          HdsImmersiveTab({ label: category, scroller: this.statsScroller, materialEnabled: this.entryMaterialStage >= 2 })
        }, (category: string): string => category)
        if (this.displayRating() > 0) {
          HdsImmersiveTab({ label: this.scoreText(), scroller: this.statsScroller, materialEnabled: this.entryMaterialStage >= 2 })
        }
        if (this.book?.completed !== undefined) {
          HdsImmersiveTab({ label: this.displayStatus(), scroller: this.statsScroller, materialEnabled: this.entryMaterialStage >= 3 })
        }
        if (this.displayUpdateShort().length > 0) {
          HdsImmersiveTab({ label: this.displayUpdateShort(), scroller: this.statsScroller, materialEnabled: this.entryMaterialStage >= 4 })
        }
        if (this.displayScale().length > 0) {
          HdsImmersiveTab({ label: this.displayScale(), scroller: this.statsScroller, materialEnabled: this.entryMaterialStage >= 5 })
        }
      }
      .height(58)
      .alignItems(VerticalAlign.Center)
      .padding({ left: this.horizontalPadding(), right: this.horizontalPadding() })
    }
    .width('100%')
    .height(58)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  buildActionRow() {
    Row() {
      // 未加入书架用不带对勾的书架图标，加入后才换成带对勾的版本并上主题色。
      DetailActionItem({
        icon: this.isFavorite
          ? $r('sys.symbol.bookshelf_badge_checkmark_fill')
          : $r('sys.symbol.bookshelf'),
        label: this.isFavorite
          ? $r('app.string.book_detail_action_in_shelf')
          : $r('app.string.book_detail_action_add_shelf'),
        active: this.isFavorite,
        onTap: (): void => { this.toggleFavorite(); }
      })
      DetailActionItem({
        icon: $r('sys.symbol.list_bullet'),
        label: $r('app.string.book_detail_action_chapters'),
        active: false,
        onTap: (): void => { this.showChapterSheet = true; }
      })
      DetailActionItem({
        icon: $r('sys.symbol.arrow_left_arrow_right'),
        label: $r('app.string.book_detail_action_switch_source'),
        active: false,
        onTap: (): void => { this.showSourceSheet = true; }
      })
      DetailActionItem({
        icon: $r('sys.symbol.folder'), label: $r('app.string.book_group_action'), active: false,
        onTap: (): void => { this.showGroupSheet = true; }
      })
      if (this.generalSettings.historyEnabled) {
      DetailActionItem({
        icon: $r('sys.symbol.calendar_fill'),
        label: (this.book?.contentType === 'text' || this.book?.contentType === 'comic')
          ? $r('app.string.book_detail_action_read_record')
          : $r('app.string.book_detail_action_listen_record'),
        active: false,
        onTap: (): void => { this.openSessionHistory(); }
      })
      }
    }
    .width('100%')
    .padding({ top: AppSpace.Md, bottom: AppSpace.Md })
  }

  /** 信息胶囊与快捷操作直接布局在封面氛围背景上。 */
  @Builder
  buildGroupSheet() {
    BookGroupSheet({ initialGroup: BookPresentation.get(this.bookId)?.group ?? '',
      onConfirm: async (group: string, groups: string[]): Promise<void> => {
        if (!this.book || this.savingGroup) return;
        this.savingGroup = true;
        try {
          await DataService.upsertCachedBook(this.book);
          await PreferenceService.setBookGroup([this.book.id], group, groups);
          if (!await PreferenceService.isFavorite(this.book.id)) await PreferenceService.toggleFavorite(this.book.id);
          this.isFavorite = true;
          this.showGroupSheet = false;
        } finally { this.savingGroup = false; }
      } })
  }

  @Builder
  buildInfoPanel() {
    Column() {
      if (this.displayCategories().length > 0 || this.displayRating() > 0 || this.book?.completed !== undefined
        || this.displayUpdateShort().length > 0 || this.displayScale().length > 0) {
        this.buildStatsRow()
      }

      Column() {
        Divider()
          .strokeWidth(0.5)
          .color(AppColor.Divider)
          .margin({ left: this.horizontalPadding(), right: this.horizontalPadding() })
        this.buildActionRow()
      }
      .width('100%')
      // 这里原先挂 AppMaterial.SurfaceClean，但 NavDestination 页面里 systemMaterial 不绘制，
      // 面板实际是透明的；直接落在氛围背景上，与参考稿的「分割线 + 图标行」一致。
    }
    .width('100%')
  }

  // ==================== 进度 / 标签 / 简介 ====================

  /** 保留书源已有编号，仅为无编号标题补充目录序号。 */
  private formatChapterLabel(index: number, rawTitle: string): string {
    const title = rawTitle.trim();
    const numbered = /^[【\[（(]?\s*(?:第\s*[0-9０-９零〇一二两三四五六七八九十百千万]+\s*[章集回节節話话期]|[0-9０-９]+\s*[章集回节節話话期]|[0-9０-９]+(?:\s|[、.．:：_\-]|$))/;
    if (numbered.test(title)) return title;
    const unit = (this.book?.contentType === 'text' || this.book?.contentType === 'comic') ? '章' : '集';
    const prefix = `第${index + 1}${unit}`;
    return title.length > 0 ? `${prefix} ${title}` : prefix;
  }

  private chapterLabel(index: number): string {
    if (!this.book || index < 0) return '';
    const chapters = this.book.chapters;
    if (index >= chapters.length) return '';
    return this.formatChapterLabel(index, chapters[index].title);
  }

  /** 历史章节标题，供进度行与换源定位使用。 */
  private historyChapterTitle(): string {
    if (!this.book) return '';
    if ((this.book.contentType === 'text' || this.book.contentType === 'comic')) {
      return this.textReadingProgress?.chapterTitle ?? '';
    }
    if (!this.lastHistory) return '';
    const idx = DataService.resolveChapterIndex(this.book, this.lastHistory.chapterId, this.lastHistory.chapterTitle);
    return idx >= 0 ? this.book.chapters[idx].title : (this.lastHistory.chapterTitle ?? '');
  }

  /** 当前进度所在章：优先正在播放的章，其次阅读进度，最后历史记录。 */
  private progressChapterLabel(): string {
    const index = this.currentChapterIndex();
    if (index < 0 || !this.book) return '';
    const chapters = this.book.chapters;
    if (index >= chapters.length) return '';
    return this.formatChapterLabel(index, chapters[index].title || this.historyChapterTitle());
  }

  private latestChapterLabel(): string {
    const latest = (this.book?.latestChapterTitle ?? '').trim();
    if (latest.length > 0) return latest;
    const chapters = this.book?.chapters ?? [];
    if (chapters.length === 0) return '';
    const last = chapters[chapters.length - 1];
    return this.chapterLabel(chapters.length - 1) || last.title;
  }

  private countLine(): ResourceStr {
    if (!this.book) return '';
    const unit = (this.book.contentType === 'text' || this.book.contentType === 'comic') ? '章' : '集';
    const total = Math.max(this.book.chapterCount, this.book.chapters.length);
    if (total <= 0) return '';
    const record = this.downloadRecord();
    if (record && record.downloadedCount > 0) {
      return (this.book.contentType === 'text' || this.book.contentType === 'comic')
        ? $r('app.string.book_detail_progress_text', total, record.downloadedCount)
        : $r('app.string.book_detail_progress_audio', total, record.downloadedCount);
    }
    return (this.book.contentType === 'text' || this.book.contentType === 'comic')
      ? $r('app.string.book_detail_total_text', total)
      : $r('app.string.book_detail_total_audio', total);
  }

  @Builder
  buildBodyInfo() {
    Column({ space: 6 }) {
      // 当前进度回填时替换同一行，不能额外插入一行推动简介和标签。
      Text() {
        Span(this.progressChapterLabel().length > 0
          ? ((this.book!.contentType === 'text' || this.book!.contentType === 'comic') ? $r('app.string.book_detail_reading_text')
            : $r('app.string.book_detail_reading'))
          : $r('app.string.book_detail_latest'))
          .fontColor($r('sys.color.font_secondary'))
        Span(' · ').fontColor($r('sys.color.font_tertiary'))
        Span(this.progressChapterLabel() || this.latestChapterLabel() || '—')
          .fontColor($r('sys.color.font_primary'))
      }
      .fontSize(this.progressChapterLabel().length > 0 ? AppFont.Title : AppFont.BodyL)
      .lineHeight(26)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')

      Text(this.countLine() || '—')
        .fontSize(15)
        .lineHeight(22)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: this.horizontalPadding(),
      right: this.horizontalPadding(),
      top: AppSpace.Lg
    })
  }

  private displayTags(): string {
    const tags = this.book?.tags ?? [];
    return tags.filter((tag: string): boolean => tag.trim().length > 0).join(', ');
  }

  /**
   * 标签行的实际内容。
   * 书源入库时 tags[0] 就是来源名（SearchPage / HomePage 都是 `tags: [sourceName]`），
   * 所以这一行同时承担了「来源」的展示——顶部标题区因此不再重复放来源。
   * 少数没有 tags 的书（本地导入 / 旧缓存）退回 sourceName，避免来源整页丢失。
   */
  private displayTagLine(): string {
    const tags = this.displayTags();
    return tags.length > 0 ? tags : this.sourceName.trim();
  }

  @Builder
  buildTagsBlock() {
    if (this.displayTagLine().length > 0) {
      Text() {
        SymbolSpan($r('sys.symbol.pin'))
          .fontSize(META_ICON_SIZE)
          .fontColor([$r('sys.color.font_tertiary')])
        Span(' ')
        Span($r('app.string.book_detail_tags_label'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_secondary'))
        Span(this.displayTagLine()).fontColor($r('sys.color.font_secondary'))
      }
      .fontSize(14)
      .lineHeight(META_TAG_LINE_HEIGHT)
      .width('100%')
      .padding({
        left: this.horizontalPadding(),
        right: this.horizontalPadding(),
        top: AppSpace.Md
      })
    }
  }

  @Builder
  buildIntroBlock() {
    Column({ space: AppSpace.Xs }) {
      // 图标参与同一行的字形排版；六行占位由外层承担，短简介也从顶部开始。
      Column() {
        Text() {
          SymbolSpan($r('sys.symbol.doc_text'))
            .fontSize(META_ICON_SIZE)
            .fontColor([$r('sys.color.font_tertiary')])
          Span(' ')
          Span($r('app.string.book_detail_intro_label'))
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_secondary'))
          Span(this.displayIntro.length > 0 ? this.displayIntro : '暂无简介')
            .fontColor(this.displayIntro.length > 0
              ? $r('sys.color.font_secondary')
              : $r('sys.color.font_tertiary'))
        }
        .fontSize(15)
        .lineHeight(META_INTRO_LINE_HEIGHT)
        .maxLines(this.introExpanded ? 100 : 6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .onClick(() => {
          if (this.introExpanded) this.introExpanded = false;
          else if (this.displayIntro.length > 60) this.introExpanded = true;
        })
      }
      .width('100%')
      .constraintSize({ minHeight: META_INTRO_LINE_HEIGHT * 6 })
      .justifyContent(FlexAlign.Start)
      if (this.displayIntro.length > 60) {
        Text(this.introExpanded ? '收起' : '查看更多')
          .fontSize(AppFont.Body)
          .fontColor(AppColor.Brand)
          .onClick(() => { this.introExpanded = !this.introExpanded; })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: this.horizontalPadding(),
      right: this.horizontalPadding(),
      top: AppSpace.Md
    })
  }

  // ==================== 主 CTA ====================

  private primaryCtaLabel(): Resource {
    if (this.chaptersLoading()) return $r('app.string.book_detail_loading_chapters');
    if ((this.book?.contentType === 'text' || this.book?.contentType === 'comic')) {
      return this.textReadingProgress
        ? $r('app.string.book_detail_continue_read')
        : $r('app.string.book_detail_start_read');
    }
    if (!this.lastHistory) return $r('app.string.book_detail_start_listen');
    return $r('app.string.book_detail_continue_listen');
  }

  private chaptersLoading(): boolean {
    return this.deferEntry || ((this.loadingDetail || this.loadingToc) && (this.book?.chapters.length ?? 0) === 0);
  }

  @Builder
  buildPrimaryCta() {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: AppSpace.Sm }) {
        if (this.chaptersLoading() || this.isStartingPlay) {
          LoadingProgress().width(18).height(18).color(AppColor.Brand)
        } else {
          SymbolGlyph((this.book?.contentType === 'text' || this.book?.contentType === 'comic') ? $r('sys.symbol.book') : $r('sys.symbol.play_fill'))
          .fontSize(18).fontColor([$r('sys.color.font_primary')])
        }
        Text(this.primaryCtaLabel())
          .fontSize(AppFont.Title).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).maxLines(1)
      }.hitTestBehavior(HitTestMode.None)
    }
    .height(48)
    .padding({ left: 18, right: 18 })
    .backgroundColor(Color.Transparent)
    .backgroundEffect({ radius: 12, saturation: 1.08, brightness: 1,
      color: $r('app.color.detail_action_glass_tint') })
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 8, color: '#10000000', offsetY: 3 })
    .accessibilityText(this.primaryCtaLabel())
    .margin({
      right: this.horizontalPadding(),
      bottom: WindowUtils.getBottomSafeVp() + 12
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .enabled(!this.chaptersLoading() && (this.book?.chapters.length ?? 0) > 0 && !this.isStartingPlay)
    .opacity(this.chaptersLoading() || (this.book?.chapters.length ?? 0) === 0 || this.isStartingPlay ? 0.6 : 1)
    .onClick((): void => { this.openPrimaryAction(); })
  }

  // ==================== 弹层 ====================

  /** 目录弹层当前章 id。 */
  private currentChapterId(): string {
    const index = this.currentChapterIndex();
    if (index < 0 || !this.book) return '';
    const chapters = this.book.chapters;
    return index < chapters.length ? chapters[index].id : '';
  }

  /** 目录弹层当前章进度文案（仅有声书）。 */
  private currentChapterProgressText(): string {
    if (!this.book || (this.book.contentType === 'text' || this.book.contentType === 'comic')) return '';
    if (this.playerState.currentBook?.id !== this.bookId) return '';
    if (this.playerState.durationMs <= 0) return '';
    const percent = Math.round(this.playerState.progressMs / this.playerState.durationMs * 100);
    return `${percent}%`;
  }

  @Builder
  buildChapterSheetContent() {
    ChapterSheet({
      book: this.book,
      currentId: this.currentChapterId(),
      headerTitle: this.book?.title ?? '',
      loading: this.loadingToc || this.deferEntry,
      failed: this.tocFailed,
      currentProgressText: this.currentChapterProgressText(),
      onSelect: (chapter: Chapter): void => {
        this.showChapterSheet = false;
        this.openPrimaryAction(chapter);
      },
      onRetry: (): void => {
        const book = this.book;
        if (!book) return;
        if ((book.contentType === 'text' || book.contentType === 'comic')) this.loadTextBook(book);
        else this.loadTocFromSource(book);
      },
      onClose: (): void => { this.showChapterSheet = false; }
    })
  }

  @Builder
  buildSourceSheetContent() {
    BookSourceSwitchSheet({
      book: this.book,
      chapterTitle: this.historyChapterTitle(),
      chapterIndex: Math.max(0, this.currentChapterIndex()),
      onSelect: async (book: Book, index: number, _matched: boolean, oldFavoriteId: string, replace: boolean): Promise<void> => {
        await this.switchSource(book, index, oldFavoriteId, replace);
      }
    })
  }

  /**
   * 换源：写入缓存后原地替换详情路由。
   * 只替换路由而不复用旧组件，避免旧 bookId 的加载态/目录残留。
   */
  private async switchSource(book: Book, index: number, oldFavoriteId: string, replace: boolean): Promise<void> {
    if (!this.detailActive || !this.showSourceSheet) return;
    if (index < 0 || index >= book.chapters.length) return;
    SearchCache.put(book);
    await DataService.upsertCachedBook(book);
    if (!this.detailActive) return;
    if (oldFavoriteId) await PreferenceService.replaceFavoriteSource(oldFavoriteId, book.id, replace);
    this.showSourceSheet = false;
    this.navStack.replacePath({ name: 'detail', param: book.id }, false);
  }

  /** 收听/阅读记录：按本书过滤会话历史。 */
  private openSessionHistory(): void {
    if (!this.book) return;
    const param: Record<string, Object> = { 'bookIds': JSON.stringify([this.book.id]) as Object };
    this.navStack.pushPathByName('sessionHistory', param);
  }

  // ==================== 页面骨架 ====================

  build() {
    Column() {
      if (this.loadingDetail) {
        Column({ space: AppSpace.Sm }) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(AppColor.Brand)
          Text($r('app.string.book_detail_loading'))
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.loadFailed) {
        Column({ space: AppSpace.Md }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(42)
            .fontColor([AppColor.Brand])
          Text($r('app.string.book_detail_load_failed'))
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_secondary'))
          Text($r('app.string.common_retry'))
            .fontSize(AppFont.Body)
            .fontColor(AppColor.Brand)
            .height(44)
            .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
            .onClick(() => this.retryLoadBook())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.book) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          // 内容层：氛围背景 + 固定顶栏 + 可滚动正文
          Stack({ alignContent: Alignment.TopStart }) {
            // 转场期间保留最终正文布局，封面模糊氛围层在交接后再绘制。
            if (this.entryMaterialStage >= 1) {
              this.buildAmbientBackdrop()
            }

            // 顶栏不再占用布局：返回/收藏按钮已经交给 HDS 标题栏（Index.ets），
            // 正文从页面顶端开始铺，滚动时才能钻进标题栏底下被画成沉浸渐变模糊。
            // 使用内容内边距避让顶栏；空 Column 占位会在长正文布局中被压缩。
            Scroll(this.contentScroller) {
              Column() {
                this.buildHero()
                this.buildInfoPanel()
                this.buildBodyInfo()
                this.buildTagsBlock()
                this.buildIntroBlock()
                // 给悬浮 CTA 留出呼吸空间，避免最后一段文字被压住
                Column().width('100%').height(80 + WindowUtils.getBottomSafeVp()).flexShrink(0)
              }
              .width('100%')
              .padding({ top: DETAIL_TITLE_BAR_HEIGHT + 48 })
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
          .width('100%')
          .height('100%')
          .bindSheet($$this.showChapterSheet, this.buildChapterSheetContent(), {
            height: '80%',
            detents: ['80%', '45%', SheetSize.LARGE], preferType: SheetType.BOTTOM,
            showClose: false,
            dragBar: true,
            backgroundColor: AppMaterial.SheetBackground,
            blurStyle: AppMaterial.PlayerSheetBlur,
            systemMaterial: AppMaterial.PlayerSheet,
            onDisappear: (): void => {
              this.sheetDismissedAt = Date.now();
              this.showChapterSheet = false;
            }
          })

          this.buildPrimaryCta()
        }
        .width('100%')
        .height('100%')
        // 每个弹层使用独立宿主；同一节点连续 bindSheet 会覆盖前一个绑定。
        .bindSheet($$this.showSourceSheet, this.buildSourceSheetContent(), {
          height: '82%',
          detents: ['82%', '45%', SheetSize.LARGE], dragBar: true, preferType: SheetType.BOTTOM,
          showClose: true,
          backgroundColor: AppMaterial.SheetBackground,
          blurStyle: AppMaterial.PlayerSheetBlur,
          systemMaterial: AppMaterial.PlayerSheet,
          onDisappear: (): void => {
            this.sheetDismissedAt = Date.now();
            this.showSourceSheet = false;
          }
        })
      } else {
        Column() {
          LoadingProgress().width(40).height(40).color(AppColor.Brand)
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .bindSheet($$this.showGroupSheet, this.buildGroupSheet(), {
      height: '65%', detents: ['65%', '45%', SheetSize.LARGE], preferType: SheetType.BOTTOM, dragBar: true, showClose: true, backgroundColor: AppMaterial.SheetBackground,
      blurStyle: AppMaterial.SheetBlur, systemMaterial: AppMaterial.Sheet,
      onWillDismiss: (action: DismissSheetAction): void => { if (!this.savingGroup) action.dismiss(); },
      onDisappear: (): void => { this.sheetDismissedAt = Date.now(); }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
      this.handleViewportSizeChange(newValue);
    })
  }
}
