import { GeneralSettings } from '../model/GeneralSettings';
import { Book } from '../model/Book';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { HdsCompat, CompatibleTabsModifier } from '../utils/HdsCompat';
import { PlatformCompat } from '../utils/PlatformCompat';
import { common } from '@kit.AbilityKit';
import { AppStorageV2, SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, HdsBarStyle, HdsTabsBarChangeMode, HdsTabsFloatingStyle } from '@kit.UIDesignKit';
import { emitter } from '@kit.BasicServicesKit';
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
import { AppColor, HomeTheme } from '../theme/Theme';
import { BookSourceAudioWebRuntimeHost } from '../service/rulesource/light/BookSourceAudioWebRuntimeHost';
import { RuleSourceImportWebHost } from '../service/rulesource/light/RuleSourceImportWebHost';

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
const TAB_RESTORE_WIDTH_GROWTH: number = 48;
const TAB_RESTORE_HEIGHT_GROWTH: number = 80;

@ComponentV2
export struct MainPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Event onBackHandlerChange: (handler: (() => boolean) | undefined) => void = () => {};
  @Event onHomeShownHandlerChange: (handler: (() => void) | undefined) => void = () => {};
  private pendingHomeResume: (() => void) | undefined = undefined;
  private homeBackHandler: (() => boolean) | undefined = undefined;
  private shelfBackHandler: (() => boolean) | undefined = undefined;
  @Local currentTab: number = 0;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
  /** 当前迷你栏样式,折叠态下让 MiniPlayer 只渲染封面 */
  @Local miniBarCollapsed: boolean = false;
  @Local speechState: TextToSpeechState = TextToSpeechService.getInstance().state;
  @Local viewportWidth: number = 0;
  @Local viewportHeight: number = 0;
  @Local bottomSafeVp: number = WindowUtils.getBottomSafeVp();

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
  private restoreTabBarOnWindowGrow: boolean = false;
  private tabCollapseViewportWidth: number = 0;
  private tabCollapseViewportHeight: number = 0;
  private safeAreaChangeHandler: (topVp: number, bottomVp: number) => void =
    (_topVp: number, bottomVp: number): void => {
      if (Math.abs(this.bottomSafeVp - bottomVp) < 0.1) return;
      this.bottomSafeVp = bottomVp;
    };

  aboutToAppear(): void {
    this.onHomeShownHandlerChange((): void => {
      const resume = this.pendingHomeResume;
      this.pendingHomeResume = undefined;
      resume?.();
    });
    this.onBackHandlerChange((): boolean => {
      if (this.currentTab === 1) return this.shelfBackHandler?.() ?? false;
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
    this.onHomeShownHandlerChange(undefined);
    this.pendingHomeResume = undefined;
    this.onBackHandlerChange(undefined);
    this.cancelLayoutTimers();
    WindowUtils.removeSafeAreaListener(this.safeAreaChangeHandler);
    emitter.off(EVT_SWITCH_TAB, this.switchTabHandler);
    emitter.off(EVT_NAVIGATE_TO_BOOK, this.navigateBookHandler);
  }

  private cancelLayoutTimers(): void {
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
    }, 0);
  }

  private handleBarStyleChange(miniStyle: HdsBarStyle, tabStyle: HdsBarStyle,
    _miniBarWidth: number, _tabBarWidth: number, mode: HdsTabsBarChangeMode): void {
    this.miniBarCollapsed = miniStyle === HdsBarStyle.COLLAPSE;
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
      this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
        this.navStack.pushPathByName('player', bookId, false);
      });
      return;
    }
    if (chapterId) {
      const params: Record<string, Object> = {
        'bookId': bookId,
        'chapterId': chapterId,
        'progressMs': progressMs
      };
      this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
        this.navStack.pushPathByName('player', params, false);
      });
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
    if (idx < 0 || idx > 3) return;
    setTimeout(() => {
      this.changeTab(idx);
    }, 60);
  }

  private async restoreDefaultTab(): Promise<void> {
    const idx = await PreferenceService.getDefaultTab();
    if (idx <= 0 || idx > 3) return;
    setTimeout(() => {
      this.changeTab(idx);
    }, 50);
  }

  /**
   * 统一切 Tab 入口,让外部事件、默认页恢复、页面内跳转都走 HdsTabs 原生切换。
   */
  private changeTab(index: number): void {
    if (index < 0 || index > 3 || index === this.currentTab) return;
    if (!this.generalSettings.historyEnabled && index === 2) index = 0;
    this.tabController.changeIndex(!this.generalSettings.historyEnabled && index === 3 ? 2 : index);
  }

  @Monitor('generalSettings.historyEnabled')
  private onHistoryVisibilityChanged(): void {
    const logical = !this.generalSettings.historyEnabled && this.currentTab === 2 ? 0 : this.currentTab;
    this.currentTab = logical;
    this.tabController.changeIndex(!this.generalSettings.historyEnabled && logical === 3 ? 2 : logical);
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

  private buildTabBar(icon: Resource, label: string): BottomTabBarStyle {
    return new BottomTabBarStyle(
      {
        normal: new SymbolGlyphModifier(icon).fontColor([$r('sys.color.font_primary')]).fontSize(24),
        selected: new SymbolGlyphModifier(icon).fontColor([AppColor.Brand]).fontSize(26)
      },
      label
    ).labelStyle({
      unselectedColor: $r('sys.color.font_primary'),
      selectedColor: AppColor.Brand
    });
  }

  /**
   * 迷你栏内容 Builder
   * 由 HdsTabs 官方管理折叠/展开状态:
   * - 折叠态(COLLAPSE): 显示一个圆形播放控制按钮
   * - 展开态(EXPAND): 显示完整的 MiniPlayer
   */
  @Builder
  miniBarBuilder(): void {
    if (this.currentPlaybackBook() !== null) {
      MiniPlayer({
        book: this.currentPlaybackBook(),
        chapterTitle: this.speechState.active ? this.speechState.error || this.speechState.chapterTitle
          : this.playerState.currentChapter?.title ?? '',
        playing: this.speechState.active ? this.speechState.playing : this.playerState.isPlaying,
        loading: this.speechState.active ? this.speechState.loading : this.playerState.isLoading,
        progressPercent: this.playbackProgressPercent(),
        collapsed: this.miniBarCollapsed,
        onPlayerPanStart: (offsetY: number): void => this.beginPlayerDrag(offsetY),
        onPlayerPanUpdate: (offsetY: number): void => PlayerDragTransition.getInstance().update(offsetY),
        onPlayerPanEnd: (offsetY: number, velocityY: number): void =>
          PlayerDragTransition.getInstance().end(offsetY, velocityY),
        onPlayerPanCancel: (): void => { PlayerDragTransition.getInstance().cancel(); },
        onTapBody: () => {
          // 折叠态:点击封面 → 展开迷你栏(不进播放器);展开态:进播放器
          if (PlatformCompat.floatingTabs && this.miniBarCollapsed) {
            this.tabController.applyMiniBarStyle(HdsBarStyle.EXPAND);
          } else {
            this.navigateToPlayer();
          }
        },
        onToggle: (): void => this.togglePlayback(),
        onNext: () => this.playNext(),
        onExpand: () => {
          if (PlatformCompat.floatingTabs && this.miniBarCollapsed) {
            this.tabController.applyMiniBarStyle(HdsBarStyle.EXPAND);
          } else {
            this.navigateToPlayer();
          }
        }
      })
    }
  }

  private floatingBarStyle(): HdsTabsFloatingStyle | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    return {
      // 宽窗口保留底部导航习惯，避免四个入口和迷你播放条横跨整块屏幕。
      barSideMargin: Math.max(16, (this.viewportWidth - 720) / 2),
      barBottomMargin: Math.max(this.bottomSafeVp, FLOATING_MIN_SAFE_BOTTOM) + FLOATING_BOTTOM,
      gradientMask: { maskColor: $r('app.color.floating_bar_mask'), maskHeight: 92 },
      systemMaterialEffect: HdsCompat.adaptiveMaterial,
      // 保留随主题色变化的沉浸光感。
      lightColor: AppColor.Brand,
      // 智感握持:左右手自动跟手
      adaptToHandedness: true,
      // 迷你栏配置:HdsTabs 会自动管理折叠/展开
      miniBar: (this.speechState.active || this.playerState.currentBook) ? {
        miniBarBuilder: () => this.miniBarBuilder(),
        enableMiniBarBackground: true,
        enableMiniBarClip: true,
        // 系统切换样式时同步给 MiniPlayer,让它切换内部布局(折叠态只显示封面)
        onBarStyleChange: (miniStyle: HdsBarStyle, tabStyle: HdsBarStyle,
          miniBarWidth: number, tabBarWidth: number, mode: HdsTabsBarChangeMode) => {
          this.handleBarStyleChange(miniStyle, tabStyle, miniBarWidth, tabBarWidth, mode);
        }
      } : undefined
    };
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      HdsTabs({ controller: this.tabController }) {
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
            onBlockMore: (block: HomeBlockSection) => this.openBlockMore(block),
            onCategoryTap: (sourceUrl: string, sourceName: string, title: string, url: string) =>
              this.openCategory(sourceUrl, sourceName, title, url),
            onScrollerReady: (scroller: Scroller) => { this.scrollers.set(0, scroller); }
          })
        }
        .tabBar(this.buildTabBar($r('sys.symbol.house_fill'), '首页'))

        TabContent() {
          FavoritePage({
            onBackHandlerChange: (handler: (() => boolean) | undefined): void => {
              this.shelfBackHandler = handler;
            },
            visible: this.currentTab === 1,
            navStack: this.navStack,
            onBookTap: (id: string) => this.navigateToBook(id, '', 0, false),
            onScrollerReady: (scroller: Scroller) => { this.scrollers.set(1, scroller); }
          })
        }
        .tabBar(this.buildTabBar($r('sys.symbol.bookshelf'), '书架'))

        if (this.generalSettings.historyEnabled) {
        TabContent() {
          ReadingStatsPage({
            navStack: this.navStack,
            inTab: true,
            onScrollerReady: (scroller: Scroller) => { this.scrollers.set(2, scroller); }
          })
        }
        .tabBar(this.buildTabBar($r('sys.symbol.calendar_fill'), '记录'))
        }

        TabContent() {
          ProfilePage({
            navStack: this.navStack,
            onScrollerReady: (scroller: Scroller) => { this.scrollers.set(3, scroller); }
          })
        }
        .tabBar(this.buildTabBar($r('sys.symbol.person_fill'), '我的'))
      }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .attributeModifier(new CompatibleTabsModifier(this.floatingBarStyle(), 56 + this.bottomSafeVp))
      .onTabBarClick((index: number) => {
        const now = Date.now();
        const DOUBLE_TAP_DELAY = 300;
        if (index === this.lastTabClickIndex && (now - this.lastTabClickTime) < DOUBLE_TAP_DELAY) {
          // 双击当前 Tab → 滚动回顶部
          const scroller = this.scrollers.get(!this.generalSettings.historyEnabled && index === 2 ? 3 : index);
          if (scroller) {
            try { scroller.scrollEdge(Edge.Top); } catch (_e) { /* ignore */ }
          }
        }
        this.lastTabClickTime = now;
        this.lastTabClickIndex = index;
      })
      .onChange((index: number) => {
        this.currentTab = !this.generalSettings.historyEnabled && index === 2 ? 3 : index;
      })
      .animationDuration(300)
      .width('100%')
      .height('100%')
      .backgroundColor(HomeTheme.BgNeutral)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (!PlatformCompat.floatingTabs && (this.speechState.active || this.playerState.currentBook)) {
        Column() {
          this.miniBarBuilder()
        }
        .height(64)
        .width('92%')
        .constraintSize({ maxWidth: 720 })
        .backgroundColor($r('sys.color.comp_background_primary'))
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
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
      this.handleViewportSizeChange(newValue);
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
    if (book === null || paths[paths.length - 1] !== 'home') return;
    const transition = PlayerDragTransition.getInstance();
    if (transition.state.active) return;
    const origin = transition.capture(this.getUIContext());
    if (origin === undefined || !transition.begin(this.viewportHeight, offsetY, origin)) return;
    // 必须保留 Navigation 动画，才能建立可取消的原生交互式路由。
    this.navStack.pushPathByName('player', book.id);
  }

  private navigateToPlayer(): void {
    const book = this.currentPlaybackBook();
    if (book === null || PlayerDragTransition.getInstance().state.active) return;
    const bookId = book.id;
    this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
      this.navStack.pushPathByName('player', bookId, false);
    });
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
