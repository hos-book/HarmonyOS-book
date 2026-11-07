import { ReaderFloatingLyrics } from '../components/ReaderFloatingLyrics';
import { ChapterSheet } from '../components/ChapterSheet';
import { BookSourceService } from '../service/BookSourceService';
import lazy { HdsBarLayoutMode } from '@kit.UIDesignKit';
import { AppAppearance } from '../model/AppAppearance';
import { GeneralSettings } from '../model/GeneralSettings';
import { Book, Chapter } from '../model/Book';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { CompatibleTabsModifier, HdsCompat } from '../utils/HdsCompat';
import { PlatformCompat } from '../utils/PlatformCompat';
import { common } from '@kit.AbilityKit';
import { AppStorageV2, SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, HdsBarStyle, HdsTabsBarChangeMode, HdsTabsFloatingStyle } from '@kit.UIDesignKit';
import { emitter } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { HomePage } from './HomePage';
import { HomeBlockSection } from '../model/BookSource';
import { FavoritePage } from './FavoritePage';
import { ReadingStatsPage } from './ReadingStatsPage';
import { ProfilePage } from './ProfilePage';
import { MiniPlayer } from '../components/MiniPlayer';
import { PlayerDragTransition } from '../utils/PlayerDragTransition';
import { AudioService } from '../service/AudioService';
import { DataService } from '../service/DataService';
import { PreferenceService } from '../service/PreferenceService';
import { PlaybackStore } from '../service/PlaybackStore';
import { WindowUtils } from '../utils/WindowUtils';
import { EVT_SWITCH_TAB } from './ImportPage';
import { WebViewAudioExtractorHost } from '../service/builtin/WebViewAudioExtractor';
import { WebEngineGate } from '../service/WebEngineGate';
import { AppColor, HomeTheme, AppTheme, AppMaterial, AppMotion, AppCurve } from '../theme/Theme';
import { ThemeIcons, ThemeIconRole } from '../theme/ThemeIcons';
import { BookSourceAudioWebRuntimeHost } from '../service/rulesource/light/BookSourceAudioWebRuntimeHost';
import { RuleSourceImportWebHost } from '../service/rulesource/light/RuleSourceImportWebHost';
import { MainTabPolicy } from '../utils/MainTabPolicy';
import { BottomTabIconService } from '../service/BottomTabIconService';

/**
 * 全局事件:点击某本书时调,统一收口路由策略。
 */
export const EVT_NAVIGATE_TO_BOOK = 'app.navigate.to.book';

export interface NavigateToBookPayload {
  bookId: string;
  chapterId?: string;
  progressMs?: number;
  forceDetail?: boolean;
}

const FLOATING_BOTTOM: number = 4;
const FLOATING_MIN_SAFE_BOTTOM: number = 8;
const FLOATING_SIDE_MARGIN: number = 16;
const FLOATING_BAR_GAP: number = 8;
const FLOATING_TAB_HEIGHT: number = 60;
const FLOATING_WIDE_BREAKPOINT: number = 600;
const TAB_RESTORE_WIDTH_GROWTH: number = 48;
const TAB_RESTORE_HEIGHT_GROWTH: number = 80;
const TAB_SWITCH_DURATION: number = 350;

class MainTabsAppearance {
  style: HdsTabsFloatingStyle | undefined = undefined;
  background: ResourceColor = Color.Transparent;
  surface: ResourceColor = Color.Transparent;
  materialSupported: boolean = false;
}

@ComponentV2
export struct MainPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param allowPlayerDrag: boolean = true;
  @Event onBackHandlerChange: (handler: (() => boolean) | undefined) => void = () => {};
  @Event onHomeShownHandlerChange: (handler: (() => void) | undefined) => void = () => {};
  private pendingHomeResume: (() => void) | undefined = undefined;
  private homeBackHandler: (() => boolean) | undefined = undefined;
  private shelfBackHandler: (() => boolean) | undefined = undefined;
  private recordsBackHandler: (() => boolean) | undefined = undefined;
  @Local appearance: AppAppearance = AppAppearance.current;
  @Local bottomTabIcons: BottomTabIconService = BottomTabIconService.instance;
  private useFloatingTabs(): boolean { return PlatformCompat.floatingTabs; }
  private useVerticalTabs(): boolean { return PlatformCompat.supports(24) && this.appearance.verticalBottomTabs; }
  private useWideFloatingBars(): boolean { return this.useVerticalTabs() && this.viewportWidth >= FLOATING_WIDE_BREAKPOINT; }

  private bottomTabInset(): number {
    return this.useFloatingTabs()
      ? Math.max(this.bottomSafeVp, FLOATING_MIN_SAFE_BOTTOM) + FLOATING_BOTTOM + FLOATING_TAB_HEIGHT
      : this.bottomSafeVp + 56;
  }
  @Monitor('appearance.verticalBottomTabs')
  private onTabStyleChanged(): void {
    if (this.miniBarExpandTimer !== -1) clearTimeout(this.miniBarExpandTimer);
    this.miniBarExpandTimer = -1;
    // 开关切换时重建对应的原生底栏，不能沿用另一种布局的控制器和折叠状态。
    this.tabController = new HdsTabsController();
    this.appliedVerticalBarStyle = undefined;
    this.requestedMiniBarStyle = undefined;
    this.miniBarAnimationRunning = false;
    this.miniBarCompactControls = false;
    this.scrollers.clear();
    this.verticalBarCollapsed = false;
    this.scrollDistance = 0;
    this.miniBarCollapsed = this.useFloatingTabs();
    this.restoreTabBarOnWindowGrow = false;
    this.lastTabClickIndex = -1;
  }

  private resetTabStyle(): void {
    // 旧版仅镜像系统回调；返回主页或换页签不改变圆封面/展开播放器状态。
    if (!this.useVerticalTabs() || !this.verticalBarCollapsed) return;
    this.verticalBarCollapsed = false;
    this.scrollDistance = 0;
    this.syncVerticalBars();
  }
  @Local currentTab: number = 0;
  // 镜像原生 Tabs 已选中的物理索引，动画开始时同步，供后续属性刷新使用。
  // 不参与状态观测，避免 onChange 再刷新 HdsTabs 整组属性并重建 MiniPlayer。
  private nativeTabIndex: number = 0;
  @Local tabsReady: boolean = false;
  private defaultTabRequest: number = 0;
  private pendingInitialTab: number = -1;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
  /** 当前迷你栏样式,折叠态下让 MiniPlayer 只渲染封面 */
  @Local miniBarCollapsed: boolean = PlatformCompat.floatingTabs;
  // 新版普通态为上下双行；紧凑态为当前页签圆按钮 + 完整横向播放器。
  @Local verticalBarCollapsed: boolean = false;
  // 请求状态与呈现状态分离：播控只在原生动画真正开始时换尺寸。
  @Local miniBarCompactControls: boolean = false;
  private miniBarAnimationRunning: boolean = false;
  private requestedMiniBarStyle: HdsBarStyle | undefined = undefined;
  private scrollDistance: number = 0;
  @Local showMiniChapters: boolean = false;
  @Local miniChapterBook: Book | null = null;
  @Local miniChaptersLoading: boolean = false;
  @Local miniChaptersFailed: boolean = false;
  private miniChapterRequest: number = 0;
  @Local speechState: TextToSpeechState = TextToSpeechService.getInstance().state;
  @Local miniPlayerIdleHidden: boolean = false;
  private miniPlayerIdleTimer: number = -1;
  private miniPlayerIdleSince: number = 0;
  private miniPlayerIdleBook: string = '';
  private miniPlayerWasBusy: boolean = false;
  private miniPlayerIdleAlive: boolean = false;
  @Local viewportWidth: number = 0;
  @Local viewportHeight: number = 0;
  @Local bottomSafeVp: number = WindowUtils.getBottomSafeVp();
  @Local sideSafeVp: number = Math.max(WindowUtils.getLeftSafeVp(), WindowUtils.getRightSafeVp());

  /** 隐藏 Web 宿主的按需挂载门控:引擎首次被调用时置位,据此条件渲染对应 Host */
  private gate: WebEngineGate = WebEngineGate.instance;
  private tabController: HdsTabsController = new HdsTabsController();
  private context: common.UIAbilityContext | null = null;
  private switchTabHandler: (e: emitter.EventData) => void = (e) => this.onSwitchTabEvent(e);
  /** 各 Tab 页的滚动控制器,用于双击 Tab 回顶部 */
  private scrollers: Map<number, Scroller> = new Map();
  /** 上一次 Tab 点击时间,用于双击检测 */
  @Local generalSettings: GeneralSettings = GeneralSettings.current;
  private lastTabClickTime: number = 0;
  private lastTabClickIndex: number = -1;
  private viewportUpdateTimerId: number = -1;
  private miniBarExpandTimer: number = -1;
  // 普通字段避免原生回调反向刷新 barFloatingStyle，已生效/已提交的状态不重复播动画。
  private appliedVerticalBarStyle: HdsBarStyle | undefined = undefined;
  // 主题权益核验会触发属性求值，但实际颜色/布局可能完全没变。
  // 保持配置与 Builder 身份，避免 HdsTabs 拆掉再创建迷你播控。
  private cachedFloatingStyle: HdsTabsFloatingStyle | undefined = undefined;
  private cachedFloatingStyleKey: string = '';
  private stableMiniBarBuilder: () => void = (): void => this.miniBarBuilder();
  private cachedTabsAppearance: MainTabsAppearance = new MainTabsAppearance();
  private cachedTabsAppearanceKey: string = '';

  // 原生属性每次重设都会重建 MiniBar，即使传入同一个对象也一样。
  // Computed 在最终外观不变时不通知 HdsTabs，隔离前台权益核验等中间状态。
  @Computed
  private get tabsAppearance(): MainTabsAppearance {
    const value: MainTabsAppearance = new MainTabsAppearance();
    value.style = this.floatingBarStyle();
    value.background = HomeTheme.BgNeutral;
    value.materialSupported = HdsCompat.materialSupported;
    value.surface = value.materialSupported ? Color.Transparent : AppTheme.Surface;
    const key: string = JSON.stringify(value);
    if (key !== this.cachedTabsAppearanceKey) {
      this.cachedTabsAppearance = value;
      this.cachedTabsAppearanceKey = key;
    }
    return this.cachedTabsAppearance;
  }
  private restoreTabBarOnWindowGrow: boolean = false;
  private tabCollapseViewportWidth: number = 0;
  private tabCollapseViewportHeight: number = 0;
  private safeAreaChangeHandler: (topVp: number, bottomVp: number) => void =
    (_topVp: number, bottomVp: number): void => {
      this.sideSafeVp = Math.max(WindowUtils.getLeftSafeVp(), WindowUtils.getRightSafeVp());
      if (Math.abs(this.bottomSafeVp - bottomVp) < 0.1) return;
      this.bottomSafeVp = bottomVp;
    };

  aboutToAppear(): void {
    this.miniPlayerIdleAlive = true;
    this.refreshMiniPlayerIdle(true);
    this.onHomeShownHandlerChange((): void => {
      this.resetTabStyle();
      const resume = this.pendingHomeResume;
      this.pendingHomeResume = undefined;
      resume?.();
    });
    this.onBackHandlerChange((): boolean => {
      if (this.showMiniChapters) { this.closeMiniChapters(); return true; }
      if (this.currentTab === 1) return this.shelfBackHandler?.() ?? false;
      if (this.currentTab === 2 && this.generalSettings.historyEnabled) return this.recordsBackHandler?.() ?? false;
      return this.currentTab === 0 && (this.homeBackHandler?.() ?? false);
    });
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AudioService.getInstance().bind(this.playerState, this.context);
    this.restoreLastPlayed();
    WindowUtils.setStatusBarLight(false);
    WindowUtils.addSafeAreaListener(this.safeAreaChangeHandler);
    WindowUtils.refreshAvoidArea();
    this.restoreDefaultTab();
    emitter.on(EVT_SWITCH_TAB, this.switchTabHandler);
    emitter.on(EVT_NAVIGATE_TO_BOOK, this.navigateBookHandler);
  }

  aboutToDisappear(): void {
    this.miniPlayerIdleAlive = false;
    this.clearMiniPlayerIdleTimer();
    this.miniChapterRequest++;
    this.defaultTabRequest++;
    this.onHomeShownHandlerChange(undefined);
    this.pendingHomeResume = undefined;
    this.onBackHandlerChange(undefined);
    this.cancelLayoutTimers();
    for (const scroller of this.scrollers.values()) {
      try { this.tabController.unbindScroller(scroller); } catch (_error) { /* 未绑定或已销毁。 */ }
    }
    WindowUtils.removeSafeAreaListener(this.safeAreaChangeHandler);
    emitter.off(EVT_SWITCH_TAB, this.switchTabHandler);
    emitter.off(EVT_NAVIGATE_TO_BOOK, this.navigateBookHandler);
  }

  private clearMiniPlayerIdleTimer(): void {
    if (this.miniPlayerIdleTimer !== -1) clearTimeout(this.miniPlayerIdleTimer);
    this.miniPlayerIdleTimer = -1;
  }

  @Monitor('generalSettings.miniPlayerHideMinutes')
  private onMiniPlayerHidePreferenceChanged(): void {
    this.refreshMiniPlayerIdle(true);
  }

  @Monitor('playerState.currentBook', 'playerState.currentChapter', 'playerState.isPlaying', 'playerState.isLoading',
    'speechState.active', 'speechState.bookId', 'speechState.playing', 'speechState.loading')
  private onMiniPlayerPlaybackChanged(): void {
    this.refreshMiniPlayerIdle();
  }

  private miniPlayerVisible(): boolean {
    return !this.miniPlayerIdleHidden && (this.speechState.active || this.playerState.currentBook !== null);
  }

  private refreshMiniPlayerIdle(reset: boolean = false): void {
    this.clearMiniPlayerIdleTimer();
    if (!this.miniPlayerIdleAlive) return;
    const bookKey: string = this.speechState.active ? `speech:${this.speechState.bookId}`
      : this.playerState.currentBook?.id ?? '';
    if (bookKey.length === 0) this.appliedVerticalBarStyle = undefined;
    const busy: boolean = this.speechState.active ? this.speechState.playing || this.speechState.loading
      : this.playerState.isPlaying || this.playerState.isLoading;
    const minutes: number = this.generalSettings.miniPlayerHideMinutes;
    const wasHidden: boolean = this.miniPlayerIdleHidden;
    if (reset || busy || busy !== this.miniPlayerWasBusy || bookKey !== this.miniPlayerIdleBook ||
      bookKey.length === 0 || minutes === 0) {
      this.miniPlayerIdleSince = Date.now();
      this.miniPlayerIdleHidden = false;
    }
    this.miniPlayerIdleBook = bookKey;
    this.miniPlayerWasBusy = busy;
    if (wasHidden && !this.miniPlayerIdleHidden) this.syncVerticalBars();
    if (busy || minutes === 0 || bookKey.length === 0) return;
    const remaining: number = minutes * 60000 - (Date.now() - this.miniPlayerIdleSince);
    if (remaining <= 0) {
      // 仅隐藏主页迷你控件，不清理播放状态、进度、会话或系统桌面歌词。
      this.miniPlayerIdleHidden = true;
      this.appliedVerticalBarStyle = undefined;
      return;
    }
    this.miniPlayerIdleTimer = setTimeout((): void => {
      this.miniPlayerIdleTimer = -1;
      this.refreshMiniPlayerIdle();
    }, remaining);
  }

  private cancelLayoutTimers(): void {
    if (this.miniBarExpandTimer !== -1) clearTimeout(this.miniBarExpandTimer);
    this.miniBarExpandTimer = -1;
    if (this.viewportUpdateTimerId !== -1) {
      clearTimeout(this.viewportUpdateTimerId);
      this.viewportUpdateTimerId = -1;
    }
  }

  private registerTabScroller(logical: number, scroller: Scroller): void {
    const previous = this.scrollers.get(logical);
    if (previous !== undefined && previous !== scroller) {
      try { this.tabController.unbindScroller(previous); } catch (_error) { /* 尚未绑定。 */ }
    }
    this.scrollers.set(logical, scroller);
  }

  private onContentScroll(tab: number, offset: number, state: ScrollState): void {
    if (!this.useVerticalTabs() || this.useWideFloatingBars() || tab !== this.currentTab || state !== ScrollState.Scroll ||
      this.showMiniChapters || this.navStack.getAllPathName().length > 0 || Math.abs(offset) < 0.1) return;
    if (this.scrollDistance * offset < 0) this.scrollDistance = 0;
    this.scrollDistance += offset;
    if (Math.abs(this.scrollDistance) < 24) return;
    const collapsed = this.scrollDistance > 0;
    this.scrollDistance = 0;
    if (collapsed === this.verticalBarCollapsed) return;
    this.verticalBarCollapsed = collapsed;
    this.syncVerticalBars(false);
  }

  private handleViewportSizeChange(newValue: SizeOptions): void {
    if (typeof newValue.width !== 'number' || typeof newValue.height !== 'number') return;
    const width: number = newValue.width;
    const height: number = newValue.height;
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return;
    if (Math.abs(width - this.viewportWidth) < 1 && Math.abs(height - this.viewportHeight) < 1) return;
    const shouldRestoreTabBar: boolean = this.restoreTabBarOnWindowGrow &&
      (width >= this.tabCollapseViewportWidth + TAB_RESTORE_WIDTH_GROWTH ||
        height >= this.tabCollapseViewportHeight + TAB_RESTORE_HEIGHT_GROWTH);
    if (this.viewportUpdateTimerId !== -1) clearTimeout(this.viewportUpdateTimerId);
    this.viewportUpdateTimerId = setTimeout(() => {
      this.viewportUpdateTimerId = -1;
      this.viewportWidth = width;
      this.viewportHeight = height;
      WindowUtils.refreshAvoidArea();
      if (shouldRestoreTabBar) this.restoreExpandedTabBars();
      this.syncVerticalBars();
    }, 0);
  }

  private handleBarStyleChange(miniStyle: HdsBarStyle, tabStyle: HdsBarStyle,
    _miniBarWidth: number, _tabBarWidth: number, mode: HdsTabsBarChangeMode): void {
    // 反向请求已提交时，旧控制器通知不能覆盖新的目标；原生点击始终以用户选择为准。
    if (this.useVerticalTabs() && mode !== HdsTabsBarChangeMode.NORMAL &&
      mode !== HdsTabsBarChangeMode.USER_CLICK && this.requestedMiniBarStyle !== undefined &&
      miniStyle !== this.requestedMiniBarStyle) return;
    this.miniBarCollapsed = miniStyle === HdsBarStyle.COLLAPSE;
    if (this.useVerticalTabs()) {
      this.appliedVerticalBarStyle = miniStyle;
      if (mode !== HdsTabsBarChangeMode.NORMAL) {
        this.requestedMiniBarStyle = miniStyle;
      }
      // 初始化/窗口变化可能没有收展动画；点击和控制器路径由动画回调驱动内容。
      if (mode === HdsTabsBarChangeMode.NORMAL && !this.miniBarAnimationRunning) {
        this.miniBarCompactControls = this.useWideFloatingBars() || miniStyle === HdsBarStyle.EXPAND;
        this.requestedMiniBarStyle = undefined;
      }
      if (!this.useWideFloatingBars() && mode === HdsTabsBarChangeMode.USER_CLICK) {
        this.requestedMiniBarStyle = miniStyle;
        this.verticalBarCollapsed = tabStyle === HdsBarStyle.COLLAPSE;
        this.scrollDistance = 0;
      }
      hilog.info(0x0000, 'MainTabs', 'native mini=%{public}d tab=%{public}d width=%{public}d/%{public}d mode=%{public}d',
        miniStyle, tabStyle, _miniBarWidth, _tabBarWidth, mode);
      return;
    }
    if (tabStyle === HdsBarStyle.EXPAND) {
      this.restoreTabBarOnWindowGrow = false;
      return;
    }
    if (mode === HdsTabsBarChangeMode.USER_CLICK) {
      this.restoreTabBarOnWindowGrow = true;
      this.tabCollapseViewportWidth = this.viewportWidth;
      this.tabCollapseViewportHeight = this.viewportHeight;
    }
  }

  private handleMiniBarAnimationStart(style: HdsBarStyle, targetWidth: number): void {
    if (!this.useVerticalTabs()) return;
    // start.style 是起始态，width 才是终点宽度。只观察宽度，不回写外观配置重建 MiniBar。
    const targetStyle: HdsBarStyle = this.requestedMiniBarStyle ??
      (style === HdsBarStyle.COLLAPSE ? HdsBarStyle.EXPAND : HdsBarStyle.COLLAPSE);
    this.miniBarAnimationRunning = true;
    this.requestedMiniBarStyle = targetStyle;
    this.getUIContext().animateTo({ duration: AppMotion.Slow, curve: AppCurve.Standard }, (): void => {
      this.miniBarCompactControls = this.useWideFloatingBars() || targetStyle === HdsBarStyle.EXPAND;
    });
    hilog.info(0x0000, 'MainTabs', 'animation start style=%{public}d target=%{public}d width=%{public}d',
      style, targetStyle, targetWidth);
  }

  private handleMiniBarAnimationEnd(style: HdsBarStyle): void {
    if (!this.useVerticalTabs()) return;
    // 原生反向动画可能先结束旧一段；仅校准最新目标，不能把播控尺寸跳回旧态。
    const latestStyle: HdsBarStyle | undefined = this.requestedMiniBarStyle ?? this.appliedVerticalBarStyle;
    if (latestStyle !== undefined && style !== latestStyle) return;
    this.miniBarAnimationRunning = false;
    this.requestedMiniBarStyle = undefined;
    this.appliedVerticalBarStyle = style;
    this.miniBarCollapsed = style === HdsBarStyle.COLLAPSE;
    this.miniBarCompactControls = this.useWideFloatingBars() || style === HdsBarStyle.EXPAND;
    hilog.info(0x0000, 'MainTabs', 'animation end style=%{public}d', style);
  }

  private restoreExpandedTabBars(): void {
    this.restoreTabBarOnWindowGrow = false;
    this.tabCollapseViewportWidth = 0;
    this.tabCollapseViewportHeight = 0;
    this.miniBarCollapsed = false;
  }

  private navigateBookHandler: (e: emitter.EventData) => void = (e) => this.onNavigateBookEvent(e);

  private onNavigateBookEvent(e: emitter.EventData): void {
    const data = e.data as Record<string, Object> | undefined;
    if (!data) return;
    const bookId = data['bookId'] as string;
    if (!bookId) return;
    const chapterId = (data['chapterId'] as string) ?? '';
    const progressMs = (data['progressMs'] as number) ?? 0;
    const forceDetail = (data['forceDetail'] as boolean) === true;
    this.navigateToBook(bookId, chapterId, progressMs, forceDetail);
  }

  private navigateToBook(bookId: string, chapterId: string, progressMs: number, forceDetail: boolean): void {
    if (forceDetail) {
      this.navStack.pushPathByName('detail', bookId);
      return;
    }
    if (PlaybackStore.getInstance().isCurrentBook(bookId)) {
      this.navStack.pushPathByName('player', bookId);
      return;
    }
    if (chapterId) {
      const params: Record<string, Object> = {
        'bookId': bookId,
        'chapterId': chapterId,
        'progressMs': progressMs
      };
      this.navStack.pushPathByName('player', params);
      return;
    }
    this.navStack.pushPathByName('detail', bookId);
  }

  private onSwitchTabEvent(e: emitter.EventData): void {
    const data = e.data as Record<string, Object> | undefined;
    if (!data) return;
    const v = data['index'];
    if (typeof v !== 'number') return;
    const idx = v as number;
    if (idx < 0 || idx > 4) return;
    if (!this.tabsReady) {
      this.changeTab(idx);
      return;
    }
    setTimeout(() => {
      this.changeTab(idx);
    }, 60);
  }

  private async restoreDefaultTab(): Promise<void> {
    if (this.tabsReady) return;
    const request = ++this.defaultTabRequest;
    let index: number = 0;
    try {
      index = await PreferenceService.getDefaultTab();
    } catch (_error) {
      // 偏好读取失败时仍可进入首页。
    }
    if (request !== this.defaultTabRequest) return;
    if (this.pendingInitialTab !== -1) index = this.pendingInitialTab;
    if (!this.generalSettings.historyEnabled && index === 2) index = 0;
    this.currentTab = index;
    this.nativeTabIndex = MainTabPolicy.physical(index, this.generalSettings.historyEnabled);
    this.pendingInitialTab = -1;
    this.tabsReady = true;
  }

  /**
   * 首屏挂载前保存目标页，挂载后的跳转使用 HdsTabs 原生切换。
   */
  private changeTab(index: number): void {
    if (!Number.isInteger(index) || index < 0 || index > 4) return;
    if (!this.tabsReady) {
      this.pendingInitialTab = index;
      return;
    }
    if (!this.generalSettings.historyEnabled && index === 2) index = 0;
    if (index === this.currentTab) return;
    this.tabController.changeIndex(MainTabPolicy.physical(index, this.generalSettings.historyEnabled));
  }

  private requestTabChange(index: number): void {
    const count: number = MainTabPolicy.order(this.generalSettings.historyEnabled).length;
    if (!this.tabsReady || !Number.isInteger(index) ||
      index < 0 || index >= count || index === this.nativeTabIndex) return;
    this.tabController.changeIndex(index);
  }

  private judgeTabSwipe(info: GestureInfo): GestureJudgeResult {
    return info.tag === 'main-tab-swipe' && !this.generalSettings.swipeSwitchTabs ?
      GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE;
  }

  private handleTabSwipe(event: GestureEvent): void {
    if (!this.generalSettings.swipeSwitchTabs) return;
    if (Math.abs(event.offsetX) < 48 || Math.abs(event.offsetX) <= Math.abs(event.offsetY) * 1.2) return;
    this.requestTabChange(this.nativeTabIndex + (event.offsetX < 0 ? 1 : -1));
  }

  @Monitor('generalSettings.historyEnabled')
  private onHistoryVisibilityChanged(): void {
    if (!this.tabsReady) return;
    const logical = !this.generalSettings.historyEnabled && this.currentTab === 2 ? 0 : this.currentTab;
    this.nativeTabIndex = MainTabPolicy.physical(logical, this.generalSettings.historyEnabled);
    this.currentTab = logical;
    this.tabController.changeIndex(this.nativeTabIndex);
    this.lastTabClickIndex = -1;
  }

  private async restoreLastPlayed(): Promise<void> {
    if (this.playerState.currentBook) return;
    const last = await PreferenceService.getLastPlayed();
    if (!last) return;
    const book = await DataService.getBookById(this.context!, last.bookId);
    if (!book) return;
    const idx = DataService.resolveChapterIndex(book, last.chapterId, last.chapterTitle);
    if (idx < 0) return;
    const chapter = book.chapters[idx];
    // 独立 KV 为权威:贴回跳过头尾,纠正缓存书壳可能丢失的 skip
    await PreferenceService.applySkipConfig(book);
    const progress = await PreferenceService.getProgress(book.id);
    const savedSpeed = progress?.speed ?? last.speed;
    const speed = typeof savedSpeed === 'number' && Number.isFinite(savedSpeed) && savedSpeed > 0
      ? Math.min(4.0, Math.max(0.125, savedSpeed)) : await PreferenceService.getDefaultPlaybackSpeed();
    // 与 EntryAbility 恢复并行；异步读取期间已有播放状态时，不能用旧快照覆盖。
    if (this.playerState.currentBook) return;
    // 先还原倍速再公布当前书籍，避免同书续播跳过倍速读取并把默认 1 倍重新落盘。
    this.playerState.speed = speed;
    this.playerState.currentBook = book;
    this.playerState.currentChapter = chapter;
    this.playerState.progressMs = last.progressMs;
    const savedDuration = (last.durationMs && last.durationMs > 0)
      ? last.durationMs
      : (chapter.duration > 0 ? chapter.duration * 1000 : 0);
    this.playerState.durationMs = savedDuration;
    this.playerState.isPlaying = false;
    PlaybackStore.getInstance().update(
      book.id, chapter.id, idx,
      chapter.source?.value ?? '', false
    );
  }

  private buildTabBar(icon: Resource, label: string, role: ThemeIconRole): BottomTabBarStyle {
    // 标签及图标的收展交给原生 HdsTabs，避免样式回调中销毁/重建 Text 引起闪现。
    const themeIcon: ResourceStr | undefined = this.bottomTabIcons.resolve(role) ?? ThemeIcons.resolve(role);
    const symbol: TabBarSymbol = {
      normal: new SymbolGlyphModifier(icon).fontSize(24).fontColor([$r('sys.color.font_primary')]),
      selected: new SymbolGlyphModifier(icon).fontSize(26).fontColor([AppColor.Brand])
    };
    const tabBar: BottomTabBarStyle = new BottomTabBarStyle(themeIcon ?? symbol, label);
    return tabBar
      .labelStyle({
        font: { size: 12, weight: FontWeight.Medium },
        selectedColor: AppColor.Brand,
        unselectedColor: AppTheme.TextSecondary,
        maxLines: 1
      })
      .iconStyle({ selectedColor: AppColor.Brand, unselectedColor: AppTheme.TextSecondary })
      .layoutMode(LayoutMode.VERTICAL)
      .verticalAlign(VerticalAlign.Center);
  }

  /**
   * 迷你栏内容 Builder
   * 新版两种布局均显示完整播控；旧版原生折叠态只显示圆形封面。
   */
  @Builder
  miniBarBuilder(): void {
    if (this.miniPlayerVisible() && this.currentPlaybackBook() !== null) {
      MiniPlayer({
        book: this.currentPlaybackBook(),
        chapterTitle: this.speechState.active ? this.speechState.error || this.speechState.chapterTitle
          : this.playerState.currentChapter?.title ?? '',
        playing: this.speechState.active ? this.speechState.playing : this.playerState.isPlaying,
        loading: this.speechState.active ? this.speechState.loading : this.playerState.isLoading,
        progressPercent: this.playbackProgressPercent(),
        collapsed: !this.useVerticalTabs() && this.miniBarCollapsed,
        verticalStyle: this.useVerticalTabs(),
        compactControls: this.useVerticalTabs() && (this.useWideFloatingBars() || this.miniBarCompactControls),
        onChapters: (): void => { this.openMiniChapters(); },
        onInteract: (): void => this.refreshMiniPlayerIdle(true),
        onPlayerPanStart: (offsetY: number): void => this.beginPlayerDrag(offsetY),
        onPlayerPanUpdate: (offsetY: number): void => PlayerDragTransition.getInstance().update(offsetY),
        onPlayerPanEnd: (offsetY: number, velocityY: number): void =>
          PlayerDragTransition.getInstance().end(offsetY, velocityY),
        onPlayerPanCancel: (): void => { PlayerDragTransition.getInstance().cancel(); },
        onTapBody: () => {
          // 折叠态:点击封面 → 展开迷你栏(不进播放器);展开态:进播放器
          if (this.useFloatingTabs() && !this.useVerticalTabs() && this.miniBarCollapsed) {
            this.tabController.applyMiniBarStyle(HdsBarStyle.EXPAND);
          } else {
            this.navigateToPlayer();
          }
        },
        onToggle: (): void => this.togglePlayback(),
        onNext: () => this.playNext(),
        onExpand: () => {
          if (this.useFloatingTabs() && !this.useVerticalTabs() && this.miniBarCollapsed) {
            this.tabController.applyMiniBarStyle(HdsBarStyle.EXPAND);
          } else {
            this.navigateToPlayer();
          }
        }
      }).onAppear((): void => {
        hilog.info(0x0000, 'MainTabs', 'mini mount');
        this.syncVerticalBars();
      })
        .onDisAppear((): void => {
          // 隐藏/重建时原生可能取消结束回调，不能让下一次挂载一直停在动画中。
          this.miniBarAnimationRunning = false;
          this.requestedMiniBarStyle = undefined;
          this.appliedVerticalBarStyle = undefined;
          hilog.info(0x0000, 'MainTabs', 'mini unmount');
        })
    }
  }

  private syncVerticalBars(defer: boolean = true): void {
    if (this.miniBarExpandTimer !== -1) clearTimeout(this.miniBarExpandTimer);
    this.miniBarExpandTimer = -1;
    if (!this.useVerticalTabs()) return;
    if (!defer) {
      this.applyVerticalBarStyle();
      return;
    }
    // 首次挂载/窗口布局更新只等待本次构建提交，不给每次滚动额外增加 80ms 延迟。
    this.miniBarExpandTimer = setTimeout((): void => {
      this.miniBarExpandTimer = -1;
      this.applyVerticalBarStyle();
    }, 0);
  }

  private applyVerticalBarStyle(): void {
    if (!this.useVerticalTabs() || !this.miniPlayerVisible() ||
      this.currentPlaybackBook() === null) return;
    const style: HdsBarStyle = this.useWideFloatingBars() || this.verticalBarCollapsed ?
      HdsBarStyle.EXPAND : HdsBarStyle.COLLAPSE;
    if (this.appliedVerticalBarStyle === style) return;
    try {
      // 反向滚动立即交给原生接续动画，不等待上一段结束；同目标仍去重。
      // 600vp 起原生两栏同时展开；窄容器才使用双行/圆页签的收展动画。
      this.appliedVerticalBarStyle = style;
      this.requestedMiniBarStyle = style;
      this.tabController.applyMiniBarStyle(style);
      hilog.info(0x0000, 'MainTabs', 'scroll collapsed=%{public}s', String(this.verticalBarCollapsed));
    } catch (_error) {
      this.appliedVerticalBarStyle = undefined;
      this.requestedMiniBarStyle = undefined;
    }
  }

  private floatingBarStyle(): HdsTabsFloatingStyle | undefined {
    if (!this.useFloatingTabs()) return undefined;
    const style: HdsTabsFloatingStyle = {
      // 旧版沿用系统宽度与侧边距，新版在下方按实际容器宽度配置两层。
      barSideMargin: Math.max(FLOATING_SIDE_MARGIN, (this.viewportWidth - 720) / 2),
      barBottomMargin: Math.max(this.bottomSafeVp, FLOATING_MIN_SAFE_BOTTOM) + FLOATING_BOTTOM,
      gradientMask: { maskColor: HomeTheme.FloatingBarMask, maskHeight: 92 },
      systemMaterialEffect: HdsCompat.adaptiveMaterial,
      // 保留随主题色变化的沉浸光感。
      lightColor: AppColor.Brand,
      // 智感握持:左右手自动跟手
      adaptToHandedness: this.generalSettings.adaptiveHandedness,
      // 迷你栏配置:HdsTabs 会自动管理折叠/展开
      miniBar: this.miniPlayerVisible() ? {
        miniBarBuilder: this.stableMiniBarBuilder,
        miniBarStyle: this.useVerticalTabs() ?
          (this.useWideFloatingBars() ? HdsBarStyle.EXPAND : HdsBarStyle.COLLAPSE) : undefined,
        enableMiniBarBackground: true,
        enableMiniBarClip: true,
        // 系统切换样式时同步页签状态；新版两种状态都保留全部播控。
        onBarStyleChange: (miniStyle: HdsBarStyle, tabStyle: HdsBarStyle,
          miniBarWidth: number, tabBarWidth: number, mode: HdsTabsBarChangeMode) => {
          this.handleBarStyleChange(miniStyle, tabStyle, miniBarWidth, tabBarWidth, mode);
        },
        onMiniBarAnimationStart: (miniStyle: HdsBarStyle, width: number): void => {
          this.handleMiniBarAnimationStart(miniStyle, width);
        },
        onMiniBarAnimationEnd: (miniStyle: HdsBarStyle): void => {
          this.handleMiniBarAnimationEnd(miniStyle);
        }
      } : undefined
    };
    if (this.useVerticalTabs()) {
      style.barSideMargin = FLOATING_SIDE_MARGIN + this.sideSafeVp;
      // 导航栏按窗口拉伸，不能沿用四页签默认 328vp 的宽度。
      // VERTICAL 仅指定 barWidth；miniBarWidth 留给原生收展布局，为圆页签预留空间。
      if (this.useWideFloatingBars()) {
        // 宽容器中原生页签/迷你栏同时展开，必须分配同一份可用宽度。
        const availableWidth: number = Math.max(1,
          this.viewportWidth - 2 * (FLOATING_SIDE_MARGIN + this.sideSafeVp));
        const barWidth: number = style.miniBar !== undefined ?
          Math.max(1, (availableWidth - FLOATING_BAR_GAP) / 2) : availableWidth;
        style.barWidth = { smallWidth: barWidth, mediumWidth: barWidth, largeWidth: barWidth };
        if (style.miniBar !== undefined) {
          style.miniBar.miniBarWidth = {
            smallWidth: barWidth, mediumWidth: barWidth, largeWidth: barWidth
          };
        }
      } else if (this.viewportWidth > 0) {
        const barWidth: number = Math.max(1,
          this.viewportWidth - 2 * (FLOATING_SIDE_MARGIN + this.sideSafeVp));
        style.barWidth = { smallWidth: barWidth, mediumWidth: barWidth, largeWidth: barWidth };
      }
      if (style.miniBar !== undefined) {
        style.miniBar.barLayoutMode = this.useWideFloatingBars() ? HdsBarLayoutMode.HORIZONTAL : HdsBarLayoutMode.VERTICAL;
      }
    }
    // 这里只比较声明式外观参数；回调绑定当前实例，Builder 自身继续响应播放状态。
    const key: string = JSON.stringify(style);
    if (this.cachedFloatingStyle !== undefined && this.cachedFloatingStyleKey === key) {
      return this.cachedFloatingStyle;
    }
    this.cachedFloatingStyleKey = key;
    this.cachedFloatingStyle = style;
    return style;
  }

  private handleTabBarClick(index: number): void {
    const now = Date.now();
    if (index === this.lastTabClickIndex && now - this.lastTabClickTime < 300) {
      const scroller = this.scrollers.get(MainTabPolicy.logical(index, this.generalSettings.historyEnabled));
      if (scroller !== undefined) {
        try { scroller.scrollEdge(Edge.Top); } catch (_error) { /* 页面正在切换。 */ }
      }
    }
    this.lastTabClickTime = now;
    this.lastTabClickIndex = index;
  }

  private handleTabChange(index: number): void {
    const previous: number = this.nativeTabIndex;
    this.nativeTabIndex = index;
    this.currentTab = MainTabPolicy.logical(index, this.generalSettings.historyEnabled);
    if (previous !== index) {
      this.resetTabStyle();
    }
  }

  @Builder
  private mainTabContents(): void {
        TabContent() {
          HomePage({
            visible: this.currentTab === 0,
            onSourceSettings: (sourceUrl: string): void => {
              this.navStack.pushPathByName('ruleSourceExplore', sourceUrl);
            },
            onManageSources: (resume: () => void): void => {
              this.pendingHomeResume = resume;
              this.navStack.pushPath({ name: 'ruleSources' });
            },
            onRankingBookTap: (id: string, resume: () => void): void => {
              // 普通返回和侧滑返回不带 result，不能依赖 onPop 恢复匹配弹层。
              this.pendingHomeResume = resume;
              this.navStack.pushPath({ name: 'detail', param: id });
            },
            onBackHandlerChange: (handler: (() => boolean) | undefined): void => {
              this.homeBackHandler = handler;
            },
            onBookTap: (id: string) => this.navigateToBook(id, '', 0, false),
            onSearchTap: () => this.navStack.pushPathByName('search', null),
            onPodcastTap: (): void => { this.navStack.pushPathByName('podcast', null); },
            onBlockMore: (block: HomeBlockSection) => this.openBlockMore(block),
            onCategoryTap: (sourceUrl: string, sourceName: string, title: string, url: string) =>
              this.openCategory(sourceUrl, sourceName, title, url),
            onScrollerReady: (scroller: Scroller) => { this.registerTabScroller(0, scroller); },
            onContentScroll: (offset: number, state: ScrollState): void => this.onContentScroll(0, offset, state)
          })
          .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 24 }).tag('main-tab-swipe')
            .onActionEnd((event: GestureEvent): void => this.handleTabSwipe(event)))
          .onGestureJudgeBegin((info: GestureInfo): GestureJudgeResult => this.judgeTabSwipe(info))
        }
        .tabBar(this.buildTabBar($r('sys.symbol.house_fill'), '首页', ThemeIconRole.Home))

        TabContent() {
          FavoritePage({
            onBackHandlerChange: (handler: (() => boolean) | undefined): void => {
              this.shelfBackHandler = handler;
            },
            visible: this.currentTab === 1,
            bottomTabInset: this.bottomTabInset(),
            miniPlayerVisible: this.miniPlayerVisible(),
            navStack: this.navStack,
            onBookTap: (id: string) => this.navigateToBook(id, '', 0, false),
            onScrollerReady: (scroller: Scroller) => { this.registerTabScroller(1, scroller); },
            onContentScroll: (offset: number, state: ScrollState): void => this.onContentScroll(1, offset, state)
          })
          .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 24 }).tag('main-tab-swipe')
            .onActionEnd((event: GestureEvent): void => this.handleTabSwipe(event)))
          .onGestureJudgeBegin((info: GestureInfo): GestureJudgeResult => this.judgeTabSwipe(info))
        }
        .tabBar(this.buildTabBar($r('sys.symbol.bookshelf'), '书架', ThemeIconRole.Shelf))

        if (this.generalSettings.historyEnabled) {
        TabContent() {
          ReadingStatsPage({
            visible: this.currentTab === 2,
            onBackHandlerChange: (handler: (() => boolean) | undefined): void => {
              this.recordsBackHandler = handler;
            },
            navStack: this.navStack,
            inTab: true,
            onScrollerReady: (scroller: Scroller) => { this.registerTabScroller(2, scroller); },
            onContentScroll: (offset: number, state: ScrollState): void => this.onContentScroll(2, offset, state)
          })
          .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 24 }).tag('main-tab-swipe')
            .onActionEnd((event: GestureEvent): void => this.handleTabSwipe(event)))
          .onGestureJudgeBegin((info: GestureInfo): GestureJudgeResult => this.judgeTabSwipe(info))
        }
        .tabBar(this.buildTabBar($r('sys.symbol.calendar_fill'), '记录', ThemeIconRole.Record))
        }

        TabContent() {
          ProfilePage({
            navStack: this.navStack,
            onScrollerReady: (scroller: Scroller) => { this.registerTabScroller(3, scroller); },
            onContentScroll: (offset: number, state: ScrollState): void => this.onContentScroll(3, offset, state)
          })
          .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 24 }).tag('main-tab-swipe')
            .onActionEnd((event: GestureEvent): void => this.handleTabSwipe(event)))
          .onGestureJudgeBegin((info: GestureInfo): GestureJudgeResult => this.judgeTabSwipe(info))
        }
        .tabBar(this.buildTabBar($r('sys.symbol.person_fill'), '我的', ThemeIconRole.Profile))
  }

  @Builder
  private floatingTabs(): void {
    HdsTabs({ controller: this.tabController, index: this.nativeTabIndex }) {
      this.mainTabContents()
    }

      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      // 关闭原生跟手横滑，由偏好决定自定义手势切底部 Tab 或页面内类型。
      .scrollable(false)
      .barFloatingStyle(this.tabsAppearance.style)
      .barBackgroundColor(this.tabsAppearance.surface)
      .barBackgroundBlurStyle(this.tabsAppearance.materialSupported ? BlurStyle.NONE : BlurStyle.COMPONENT_REGULAR)
      .onTabBarClick((index: number): void => this.handleTabBarClick(index))
      .onAnimationStart((_index: number, targetIndex: number): void => this.handleTabChange(targetIndex))
      .onChange((index: number): void => this.handleTabChange(index))
      // 使用 HdsTabs 原生整页横向滑动，底栏与迷你播放器保持原位。
      .animationDuration(TAB_SWITCH_DURATION)
      .width('100%')
      .height('100%')
      .backgroundColor(this.tabsAppearance.background)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private legacyTabs(): void {
    HdsTabs({ controller: this.tabController, index: this.nativeTabIndex }) {
      this.mainTabContents()
    }

      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      // 关闭原生跟手横滑，由偏好决定自定义手势切底部 Tab 或页面内类型。
      .scrollable(false)
      .attributeModifier(new CompatibleTabsModifier(this.floatingBarStyle(), 56 + this.bottomSafeVp))
      .onTabBarClick((index: number): void => this.handleTabBarClick(index))
      .onAnimationStart((_index: number, targetIndex: number): void => this.handleTabChange(targetIndex))
      .onChange((index: number): void => this.handleTabChange(index))
      // 使用 HdsTabs 原生整页横向滑动，底栏与迷你播放器保持原位。
      .animationDuration(TAB_SWITCH_DURATION)
      .width('100%')
      .height('100%')
      .backgroundColor(HomeTheme.BgNeutral)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      ReaderFloatingLyrics().zIndex(100).align(Alignment.Center)
      if (this.tabsReady) {
      // 属性刷新仍读取最新选中页；子页 visible 单独响应 currentTab，不反向重配底栏。
      if (this.useVerticalTabs()) {
        this.floatingTabs()
      } else {
        this.legacyTabs()
      }
      }

      if (this.tabsReady && !this.useFloatingTabs() && this.miniPlayerVisible()) {
        Column() {
          this.miniBarBuilder()
        }
        .height(64)
        .width('92%')
        .constraintSize({ maxWidth: 720 })
        .backgroundColor(AppTheme.Surface)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .borderRadius(24)
        .clip(true)
        .margin({ bottom: 64 + this.bottomSafeVp })
      }

      // 欢部分音频地址需要 ArkWeb 兜底提取，按需创建隐藏宿主。
      if (this.gate.needAudioExtractor) {
        WebViewAudioExtractorHost()
      }

      if (this.gate.needRuleBrowser) {
        BookSourceAudioWebRuntimeHost()
        RuleSourceImportWebHost()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HomeTheme.BgNeutral)
    .bindSheet($$this.showMiniChapters, this.buildMiniChapterSheet(), {
      height: '90%', detents: ['90%', '60%', SheetSize.LARGE], preferType: SheetType.BOTTOM,
      showClose: false, dragBar: true,
      backgroundColor: AppMaterial.SheetBackground,
      blurStyle: AppMaterial.PlayerSheetBlur, systemMaterial: AppMaterial.PlayerSheet,
      onDisappear: (): void => this.closeMiniChapters()
    })
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
      this.handleViewportSizeChange(newValue);
    })
  }

  private closeMiniChapters(): void {
    this.showMiniChapters = false;
    this.miniChapterRequest++;
    this.miniChaptersLoading = false;
  }

  private async openMiniChapters(): Promise<void> {
    const book = this.currentPlaybackBook();
    if (book === null) return;
    const request = ++this.miniChapterRequest;
    this.miniChapterBook = book;
    this.miniChaptersFailed = false;
    this.showMiniChapters = true;
    const needsLoad = book.sourceUrl.length > 0 && (book.tocComplete === false ||
      book.chapters.length === 0 || book.chapterCount > book.chapters.length);
    this.miniChaptersLoading = needsLoad;
    try {
      let loaded = book;
      if (needsLoad) {
        const update = (value: Book): void => {
          if (request === this.miniChapterRequest) this.miniChapterBook = this.copyMiniChapterBook(value);
        };
        loaded = book.contentType === 'text'
          ? await BookSourceService.loadTextBook(book, update)
          : await BookSourceService.loadAudioBook(book, update);
      }
      await PreferenceService.applyTocOrder(loaded);
      if (request !== this.miniChapterRequest) return;
      this.miniChapterBook = this.copyMiniChapterBook(loaded);
      this.miniChaptersFailed = loaded.chapters.length === 0;
    } catch (_error) {
      if (request === this.miniChapterRequest) this.miniChaptersFailed = true;
    } finally {
      if (request === this.miniChapterRequest) this.miniChaptersLoading = false;
    }
  }

  private copyMiniChapterBook(book: Book): Book {
    const value: Book = {
      id: book.id, contentType: book.contentType, title: book.title, author: book.author,
      narrator: book.narrator, cover: book.cover, coverFromDetail: book.coverFromDetail,
      coverFallback: book.coverFallback, category: book.category, intro: book.intro,
      wordCount: book.wordCount, latestChapterTitle: book.latestChapterTitle, updateTime: book.updateTime,
      totalDuration: book.totalDuration, chapterCount: book.chapterCount, rating: book.rating,
      tags: book.tags.slice(), chapters: book.chapters.slice(), tocComplete: book.tocComplete,
      bookUrl: book.bookUrl, sourceUrl: book.sourceUrl, variables: book.variables,
      skipIntro: book.skipIntro, skipOutro: book.skipOutro,
      chaptersDescending: book.chaptersDescending, completed: book.completed
    };
    return value;
  }

  private miniChapterId(): string {
    const book = this.miniChapterBook;
    if (book === null) return '';
    if (book.contentType === 'text') {
      return this.speechState.bookId === book.id ? book.chapters[this.speechState.chapterIndex]?.id ?? '' : '';
    }
    return this.playerState.currentBook?.id === book.id ? this.playerState.currentChapter?.id ?? '' : '';
  }

  private async selectMiniChapter(chapter: Chapter): Promise<void> {
    const book = this.miniChapterBook;
    if (book === null) return;
    const index = book.chapters.findIndex((item: Chapter): boolean => item.id === chapter.id);
    if (index < 0) return;
    this.closeMiniChapters();
    if (book.contentType === 'text') {
      await TextToSpeechService.getInstance().start(book, index, 0);
    } else {
      await AudioService.getInstance().playChapterFromSavedProgress(book, chapter);
    }
  }

  @Builder
  private buildMiniChapterSheet(): void {
    ChapterSheet({
      book: this.miniChapterBook, currentId: this.miniChapterId(),
      headerTitle: this.miniChapterBook?.title ?? '',
      loading: this.miniChaptersLoading, failed: this.miniChaptersFailed,
      onClose: (): void => this.closeMiniChapters(),
      onRetry: (): void => { this.openMiniChapters(); },
      onSelect: (chapter: Chapter): void => { this.selectMiniChapter(chapter); }
    })
  }

  private openBlockMore(block: HomeBlockSection): void {
    if (!block || !block.moreUrl) return;
    const params: Record<string, Object> = {
      'sourceUrl': block.sourceUrl,
      'sourceName': block.sourceName,
      'title': block.title,
      'moreUrl': block.moreUrl
    };
    this.navStack.pushPathByName('blockMore', params);
  }

  /** 分类入口:复用 blockMore 路由展示分类书单 */
  private openCategory(sourceUrl: string, sourceName: string, title: string, url: string): void {
    if (!sourceUrl || !url) return;
    const params: Record<string, Object> = {
      'sourceUrl': sourceUrl,
      'sourceName': sourceName,
      'title': title,
      'moreUrl': url
    };
    this.navStack.pushPathByName('blockMore', params);
  }

  private beginPlayerDrag(offsetY: number): void {
    const book = this.currentPlaybackBook();
    const paths = this.navStack.getAllPathName();
    if (!this.allowPlayerDrag || book === null || paths.length > 0) return;
    const transition = PlayerDragTransition.getInstance();
    if (transition.state.active) return;
    // 松手确认后才压栈；短拖取消不进入原生 Navigation，避免 NavBar 残留禁用状态。
    // 双层播放栏不要求拖过整屏的 18%；普通上拖约 58vp 即可展开，大窗口也保持可达。
    const gestureHeight: number = this.useVerticalTabs() ? Math.min(this.viewportHeight, 320) : this.viewportHeight;
    if (this.useVerticalTabs()) {
      const origin = transition.capture(this.getUIContext());
      if (origin !== undefined) {
        transition.beginPreviewGesture(gestureHeight, offsetY, origin, book.id,
          (): void => { this.navStack.pushPathByName('player', book.id); },
          (finish: () => void): void => {
            this.getUIContext().animateTo({ curve: AppCurve.GestureSettle, onFinish: finish },
              (): void => transition.collapsePreview());
          });
        return;
      }
    }
    transition.beginGesture(gestureHeight, offsetY, (): void => this.navigateToPlayer());
  }

  private navigateToPlayer(): void {
    const book = this.currentPlaybackBook();
    if (book === null || PlayerDragTransition.getInstance().state.active) return;
    if (this.allowPlayerDrag && this.navStack.size() === 0) {
      const transition = PlayerDragTransition.getInstance();
      const origin = transition.capture(this.getUIContext());
      if (origin !== undefined && transition.beginTap(origin)) {
        // 点击与上拖共用底部播控的真实矩形，保留 Navigation 自定义转场。
        this.navStack.pushPathByName('player', book.id);
        return;
      }
    }
    const bookId = book.id;
    this.navStack.pushPathByName('player', bookId);
  }

  private playNext(): void {
    if (this.speechState.active) {
      TextToSpeechService.getInstance().moveChapter(1);
      return;
    }
    if (!this.playerState.currentBook || !this.playerState.currentChapter) return;
    AudioService.getInstance().playNext();
  }

  private currentPlaybackBook(): Book | null {
    if (this.speechState.active) {
      const book = TextToSpeechService.getInstance().currentBook();
      return book?.id === this.speechState.bookId ? book : null;
    }
    return this.playerState.currentBook;
  }

  private playbackProgressPercent(): number {
    const total = this.speechState.active ? this.speechState.contentLength :
      (this.playerState.durationMs > 0 ? this.playerState.durationMs : this.playerState.savedDurationMs);
    const position = this.speechState.active ? this.speechState.charOffset : this.playerState.progressMs;
    return total > 0 ? Math.max(0, Math.min(100, position * 100 / total)) : 0;
  }

  private togglePlayback(): void {
    if (this.speechState.active) {
      const speech = TextToSpeechService.getInstance();
      if (this.speechState.playing || this.speechState.loading) speech.pause();
      else speech.resume();
    } else {
      AudioService.getInstance().toggle();
    }
  }
}
