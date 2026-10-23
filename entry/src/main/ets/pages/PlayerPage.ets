import { TextReaderRouteParams, TextReadingPosition, ReaderJumpChapterEvent, EVT_READER_JUMP_CHAPTER } from '../model/TextReading';
import { TextReadingProgressService } from '../service/text/TextReadingProgressService';
import { ChapterSheetActions } from '../components/ChapterSheetActions';
import { PlaybackWaveIcon } from '../components/PlaybackWaveIcon';
import { ChapterSegmentGrid } from '../components/ChapterSegmentGrid';
import { PlaybackLoadingIndicator } from '../components/PlaybackLoadingIndicator';
import { LocalTextImage } from '../service/text/LocalTextImage';
import { PlayerCoverImage } from '../components/PlayerCoverImage';
import { CoverImage } from '../components/CoverImage';
import { BookSourceSwitchSheet } from '../components/BookSourceSwitchSheet';
import { common } from '@kit.AbilityKit';
import { AppStorageV2, curves, FrameCallback, LengthMetrics } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { vibrator } from '@kit.SensorServiceKit';
import { AppColor, AppSpace, AppFont, AppMotion, AppRadius, AppMaterial } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { TocItem } from '../model/BookSource';
import { LocalRuleSource } from '../model/LocalRuleSource';
import { PlayerState, PLAYER_STATE_KEY, PlayMode, SleepMode } from '../model/PlayerState';
import { BookSourceService } from '../service/BookSourceService';
import { DataService } from '../service/DataService';
import { AudioPlayFailedPayload, AudioService, EVT_AUDIO_PLAY_FAILED, EVT_SLEEP_CANCELLED } from '../service/AudioService';
import { PreferenceService } from '../service/PreferenceService';
import { SourceDataService } from '../service/SourceDataService';
import { PlaybackStore } from '../service/PlaybackStore';
import { DownloadService, DownloadUpdatePayload, EVT_DOWNLOAD_UPDATED } from '../service/DownloadService';
import { DownloadChapterRecord } from '../service/DownloadStore';
import { DownloadPolicy } from '../service/DownloadPolicy';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';
import { ChapterCacheService, EVT_CHAPTER_DURATION_UPDATED } from '../service/ChapterCacheService';
import { ChapterDataSource } from '../utils/ChapterDataSource';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { PlayerDragState, PlayerDragTransition } from '../utils/PlayerDragTransition';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { TextToSpeechState, SpeechVoice } from '../model/TextToSpeechState';
import { CustomTtsConfig } from '../model/CustomTtsConfig';
import { LightSourceBridge } from '../service/rulesource/light/LightSourceBridge';
import { LocalRuleVoice } from '../service/rulesource/LocalRuleRuntimeTypes';
import { SourceVoiceDataSource } from '../utils/SourceVoiceDataSource';
import { PlatformCompat } from '../utils/PlatformCompat';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_Player';

class PlayerSourceSwitchRoute {
  bookId: string = '';
  chapterId: string = '';
  progressMs: number = 0;
}

class PlayerLayoutReadyFrame extends FrameCallback {
  private callback: () => void;

  constructor(callback: () => void) {
    super();
    this.callback = callback;
  }

  onIdle(_timeLeftInNano: number): void { this.callback(); }
}

/**
 * 播放页向其 NavDestination 暴露的返回拦截器。
 * 抽屉(章节/定时/跳过)打开时,右滑/三键返回应先关抽屉而不是退出整页:
 * PlayerPage 挂载时注册 handler,NavDestination.onBackPressed 委托到这里。
 */
export class PlayerBackInterceptor {
  private static handler: (() => boolean) | null = null;

  static set(h: (() => boolean) | null): void {
    PlayerBackInterceptor.handler = h;
  }

  /** 返回 true 表示已消费(关抽屉),false 表示放行(正常退页) */
  static consume(): boolean {
    return PlayerBackInterceptor.handler ? PlayerBackInterceptor.handler() : false;
  }
}

/**
 * 由 PlayerPage 注册的离场协调器:
 * 返回时通知 PlayerPage 取消延迟加载 timer、提前中断 loadBook 异步链,避免阻塞返回响应。
 */
export class PlayerEntryDecider {
  /** 取消 pending 的延迟加载 timer */
  private static cancelPendingClearHandler: (() => void) | null = null;
  /** 标记 PlayerPage 即将离开,让 loadBook 异步链提前退出 */
  private static markLeavingHandler: (() => void) | null = null;
  private static enteredHandler: (() => void) | null = null;

  static setCancelPendingClear(h: (() => void) | null): void {
    PlayerEntryDecider.cancelPendingClearHandler = h;
  }

  static setMarkLeaving(h: (() => void) | null): void {
    PlayerEntryDecider.markLeavingHandler = h;
  }

  static setEntered(h: (() => void) | null): void {
    PlayerEntryDecider.enteredHandler = h;
  }

  /** 返回前调用,取消 pending 的延迟加载 timer */
  static cancelPendingClear(): void {
    if (PlayerEntryDecider.cancelPendingClearHandler) {
      PlayerEntryDecider.cancelPendingClearHandler();
    }
  }

  /** 返回前调用,通知 PlayerPage 立即停止 loadBook 等异步操作 */
  static markLeaving(): void {
    if (PlayerEntryDecider.markLeavingHandler) {
      PlayerEntryDecider.markLeavingHandler();
    }
  }

  static markEntered(): void {
    if (PlayerEntryDecider.enteredHandler) {
      PlayerEntryDecider.enteredHandler();
    }
  }
}

@ComponentV2
export struct PlayerPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';
  @Param deferEntry: boolean = false;
  @Local dragState: PlayerDragState = PlayerDragTransition.getInstance().state;
  @Param resumeChapterId: string = '';
  @Param resumeProgressMs: number = 0;
  @Local book: Book | null = null;
  @Local showSourceSwitch: boolean = false;
  @Local reloadingChapter: boolean = false;
  @Local sourceName: ResourceStr = '';
  @Local sourceVoiceAvailable: boolean = false;
  @Local showSourceVoice: boolean = false;
  @Local sourceVoiceDraft: string = '';
  @Local savingSourceVoice: boolean = false;
  private sourceVoices: SourceVoiceDataSource = new SourceVoiceDataSource();
  private sourceVoiceScroller: Scroller = new Scroller();
  @Local isFavorite: boolean = false;
  @Local showChapterList: boolean = false;
  @Local chapterGridVisible: boolean = false;
  @Local showSleepSheet: boolean = false;
  @Local sleepSheetMode: SleepMode = SleepMode.Duration;
  @Local sleepCustomVisible: boolean = false;
  @Local sleepCustomValue: string = '';
  @Local sleepInputError: ResourceStr = '';
  @Local sleepSmartStopDraft: boolean = false;
  @Local showSkipSheet: boolean = false;
  @Local showSpeedSheet: boolean = false;
  @Local skipIntroValue: number = 0;
  @Local skipOutroValue: number = 0;
  /** 倍速滑块当前值(拖动时实时显示,松手才真正下发到 AudioService) */
  @Local speedValue: number = 1.0;
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;;
  private speechScroller: Scroller = new Scroller();
  @Local speechParagraphs: string[] = [];
  @Local speechParagraphIndex: number = 0;
  private speechParagraphOffsets: number[] = [];
  private speechChapterKey: string = '';
  private speechListReady: boolean = false;
  private speechPositionQueued: boolean = false;
  private speechPositionGeneration: number = 0;
  private speechPositionedChapter: string = '';
  @Local speechState: TextToSpeechState = TextToSpeechService.getInstance().state;
  @Local seeking: boolean = false;
  @Local seekValueMs: number = 0;
  /** 缓存版本号：每次有章节时长被解析出来就 +1，强制 V2 重渲染章节列表 */
  @Local chapterCacheTick: number = 0;
  @Local downloadTick: number = 0;
  /** 章节列表滚动位置 vs 当前播放章节的偏离（vp）；用来决定是否显示"回到当前章节"浮动按钮 */
  @Local listOffsetFromCurrent: number = 0;
  /** 章节搜索关键词；非空时章节列表按标题过滤 */
  @Local chapterSearchKeyword: string = '';
  /** 根容器实时尺寸，用于跟随小窗缩放切换紧凑布局。 */
  @Local viewportWidth: number = 0;
  @Local viewportHeight: number = 0;
  @Local topSafeVp: number = WindowUtils.getStatusBarHeightVp();
  @Local bottomSafeVp: number = WindowUtils.getBottomSafeVp();
  @Local leftSafeVp: number = WindowUtils.getLeftSafeVp();
  @Local rightSafeVp: number = WindowUtils.getRightSafeVp();

  private context: common.UIAbilityContext | null = null;
  private safeAreaChangeHandler = (topVp: number, bottomVp: number): void => {
    if (this.isLeaving) return;
    this.topSafeVp = topVp;
    this.bottomSafeVp = bottomVp;
    this.leftSafeVp = WindowUtils.getLeftSafeVp();
    this.rightSafeVp = WindowUtils.getRightSafeVp();
  };
  @Local chapterTopRequest: number = 0;
  @Local chapterBottomRequest: number = 0;
  @Local chapterDescending: boolean = false;
  private chapterListScroller: Scroller = new Scroller();
  private chapterPositionTimer: number = -1;
  private chapterListInteracted: boolean = false;
  private chapterDataSource: ChapterDataSource = new ChapterDataSource();
  private chapterDurationHandler = (): void => {
    this.chapterCacheTick = this.chapterCacheTick + 1;
    this.chapterDataSource.notifyDataReloaded();
  };
  private downloadHandler = (evt: emitter.EventData): void => {
    const data = evt.data as DownloadUpdatePayload;
    if (!data || data.bookId !== this.bookId) return;
    this.downloadTick = this.downloadTick + 1;
    if (!data.progressOnly) this.chapterDataSource.notifyDataReloaded();
  };
  private sleepCancelledHandler = (): void => {
    this.showToast($r('app.string.player_sleep_switch_cancelled'));
  };
  private audioPlayFailedHandler = (evt: emitter.EventData): void => {
    const data = evt.data as AudioPlayFailedPayload;
    if (!data || data.bookId !== this.bookId) return;
    if (this.playerState.currentChapter && data.chapterId !== this.playerState.currentChapter.id) return;
    this.showToast(data.message || '播放失败，请点击重试');
  };
  /** 延迟加载 timer id,用户立即返回时需要 cancel,避免阻塞返回响应 */
  private deferredLoadTimerId: number = -1;
  /** onSizeChange 需要异步更新状态，保存 timer 以便离场时清理。 */
  private viewportUpdateTimerId: number = -1;
  /** 用户已触发返回,loadBook 异步链应在 await 后检查并提前退出,避免阻塞主线程 */
  private isLeaving: boolean = false;
  private chapterLoadInProgress: boolean = false;
  private entryFinished: boolean = false;
  @Local highQualityCover: boolean = false;

  /** 取消 pending 的延迟加载 timer,返回前调用避免阻塞返回响应 */
  private cancelPendingClearTimers(): void {
    if (this.deferredLoadTimerId !== -1) {
      clearTimeout(this.deferredLoadTimerId);
      this.deferredLoadTimerId = -1;
    }
  }

  private cancelViewportUpdateTimer(): void {
    if (this.viewportUpdateTimerId !== -1) {
      clearTimeout(this.viewportUpdateTimerId);
      this.viewportUpdateTimerId = -1;
    }
  }

  aboutToAppear(): void {
    this.isLeaving = false;
    WindowUtils.addSafeAreaListener(this.safeAreaChangeHandler);
    WindowUtils.refreshAvoidArea();
    this.entryFinished = false;
    this.highQualityCover = false;
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    PlayerEntryDecider.setCancelPendingClear(() => this.cancelPendingClearTimers());
    PlayerEntryDecider.setMarkLeaving(() => { this.isLeaving = true; });
    PlayerEntryDecider.setEntered(() => this.finishEntering());
    PlayerBackInterceptor.set((): boolean => this.handleBack());
    this.primeFromCache();
    // 上拖预览期间只展示当前书籍，手势取消不能触发播放初始化或重载。
    if (!this.deferEntry) {
      this.deferredLoadTimerId = setTimeout(() => {
        this.finishEntering();
      }, AppMotion.Page + 80);
    }
  }

  /** 同步从 SearchCache 取得 book，避免首帧空白 */
  private primeFromCache(): void {
    let b = SearchCache.get(this.bookId);
    const speechBook = TextToSpeechService.getInstance().currentBook();
    const current = speechBook?.id === this.bookId ? speechBook : this.playerState.currentBook;
    if (b && current && this.isSameBook(b, current)
      && b.chapters.length === 0 && current.chapters.length > 0) {
      b = current;
    } else if (!b && current) {
      b = current;
    }
    if (!b) return;
    this.book = b;
    this.syncSpeechParagraphs();
  }

  private finishEntering(): void {
    if (this.entryFinished || this.isLeaving) return;
    this.entryFinished = true;
    this.cancelPendingClearTimers();
    WindowUtils.setStatusBarLight(true);
    emitter.on(EVT_CHAPTER_DURATION_UPDATED, this.chapterDurationHandler);
    emitter.on(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
    emitter.on(EVT_AUDIO_PLAY_FAILED, this.audioPlayFailedHandler);
    emitter.on(EVT_SLEEP_CANCELLED, this.sleepCancelledHandler);
    setTimeout(() => {
      if (this.isLeaving) return;
      this.loadBook();
    }, 32);
    setTimeout(() => {
      if (this.isLeaving) return;
      this.highQualityCover = true;
    }, 96);
  }

  aboutToDisappear(): void {
    this.isLeaving = true;
    this.cancelChapterPosition();
    WindowUtils.removeSafeAreaListener(this.safeAreaChangeHandler);
    PlayerBackInterceptor.set(null);
    PlayerEntryDecider.setCancelPendingClear(null);
    PlayerEntryDecider.setMarkLeaving(null);
    PlayerEntryDecider.setEntered(null);
    this.cancelPendingClearTimers();
    this.cancelViewportUpdateTimer();
    if (this.entryFinished) {
      emitter.off(EVT_CHAPTER_DURATION_UPDATED, this.chapterDurationHandler);
      emitter.off(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
      emitter.off(EVT_AUDIO_PLAY_FAILED, this.audioPlayFailedHandler);
      emitter.off(EVT_SLEEP_CANCELLED, this.sleepCancelledHandler);
    }
    WindowUtils.setStatusBarLight(false);
    if (!this.isSpeechBook()) AudioService.getInstance().flushHistory();
  }

  private handleViewportSizeChange(newValue: SizeOptions): void {
    if (typeof newValue.width !== 'number' || typeof newValue.height !== 'number') return;
    const width: number = newValue.width;
    const height: number = newValue.height;
    if (Math.abs(width - this.viewportWidth) < 1 && Math.abs(height - this.viewportHeight) < 1) return;
    this.cancelViewportUpdateTimer();
    // onSizeChange 在布局阶段同步触发，按官方建议延迟状态更新，避免被并入布局动画。
    this.viewportUpdateTimerId = setTimeout(() => {
      this.viewportUpdateTimerId = -1;
      if (this.isLeaving) return;
      this.viewportWidth = width;
      this.viewportHeight = height;
    }, 0);
  }

  private isCompactPlayer(): boolean {
    return AdaptiveLayout.isCompact(this.viewportWidth, this.viewportHeight);
  }

  private isLandscapePlayer(): boolean {
    return AdaptiveLayout.playerUsesColumns(this.viewportWidth, this.viewportHeight);
  }

  private landscapeBodyHeight(): number {
    return Math.max(1, this.viewportHeight - this.playerTopPadding() - this.playerBottomPadding() - 48 - AppSpace.Sm);
  }

  private landscapeCoverSize(): number {
    // 右栏至少保留 280vp，避免五个播控按钮被封面挤压。
    const availableWidth = this.viewportWidth - this.playerLeftPadding() - this.playerRightPadding() - AppSpace.Xl;
    return Math.max(1, Math.min(320, this.landscapeBodyHeight(), this.viewportWidth * 0.34, availableWidth - 280));
  }

  private playerNeedsScroll(): boolean {
    return AdaptiveLayout.playerNeedsScroll(this.viewportHeight);
  }

  private playerHorizontalPadding(): number {
    return AdaptiveLayout.horizontalPadding(this.viewportWidth, this.viewportHeight);
  }

  private playerLeftPadding(): number {
    return this.leftSafeVp + this.playerHorizontalPadding();
  }

  private playerRightPadding(): number {
    return this.rightSafeVp + this.playerHorizontalPadding();
  }

  private playerTopPadding(): number {
    const spacing = AdaptiveLayout.playerTopSpacing(this.viewportWidth, this.viewportHeight);
    return this.topSafeVp + spacing;
  }

  private playerBottomPadding(): number {
    const spacing = AdaptiveLayout.playerBottomSpacing(this.viewportWidth, this.viewportHeight);
    return this.bottomSafeVp + Math.max(0, spacing - AppSpace.Sm);
  }

  private compactCoverSize(): number {
    return AdaptiveLayout.playerCoverSize(this.viewportWidth, this.viewportHeight);
  }

  /**
   * 返回拦截:任一抽屉打开时先关抽屉并消费返回事件,否则放行让 NavDestination 正常退页。
   * 实际同时只会有一个抽屉打开,逐个判断即可。
   */
  private handleBack(): boolean {
    if (this.showSourceVoice) {
      this.showSourceVoice = false;
      return true;
    }
    if (this.showSourceSwitch) {
      this.showSourceSwitch = false;
      return true;
    }
    if (this.showChapterList) {
      this.showChapterList = false;
      return true;
    }
    if (this.showSleepSheet) {
      this.showSleepSheet = false;
      return true;
    }
    if (this.showSkipSheet) {
      this.showSkipSheet = false;
      return true;
    }
    if (this.showSpeedSheet) {
      this.showSpeedSheet = false;
      return true;
    }
    return false;
  }

  private async closeSpeechToReader(keepSpeaking: boolean = false): Promise<void> {
    const book = this.book ?? TextToSpeechService.getInstance().currentBook();
    if (!book || this.isLeaving) return;
    this.isLeaving = true;
    const matches = this.speechState.bookId === book.id;
    const chapterIndex = matches ? this.speechState.chapterIndex : -1;
    const offset = matches ? this.speechState.charOffset : 0;
    if (matches && !keepSpeaking) TextToSpeechService.getInstance().stop();
    SearchCache.put(book);
    const context = this.getUIContext().getHostContext();
    if (context && chapterIndex >= 0) {
      await TextReadingProgressService.save(context, TextReadingPosition.atChar(book.id, chapterIndex, '',
        offset, 0, book.chapters[chapterIndex]?.title ?? '')).catch((): void => {});
    }
    const names = this.navStack.getAllPathName();
    for (let index = names.length - 2; index >= 0; index--) {
      if (names[index] !== 'reader') continue;
      const param: TextReaderRouteParams | null = JSON.parse(JSON.stringify(this.navStack.getParamByIndex(index)) || 'null');
      if (param !== null && param.bookId === book.id) {
        this.navStack.popToIndex(index);
        if (chapterIndex >= 0 && !keepSpeaking) {
          const event = new ReaderJumpChapterEvent();
          event.bookId = book.id;
          event.resourceIndex = chapterIndex;
          event.charOffset = offset;
          emitter.emit(EVT_READER_JUMP_CHAPTER, { data: event });
        }
        return;
      }
    }
    this.navStack.replacePathByName('reader', TextReaderRouteParams.of(book.id));
  }

  /** 长按恢复默认值时的轻震反馈 */
  private hapticTick(): void {
    try {
      vibrator.startVibration(
        { type: 'time', duration: 30 },
        { id: 0, usage: 'touch' }
      ).catch((_e: object) => { /* 无震动器或权限被关 */ });
    } catch (_e) { /* 同步异常忽略 */ }
  }

  private async loadBook(): Promise<void> {
    // 等待 EntryAbility.bootstrapAudioService 完成，确保冷启动时 playerState/DataService 已就绪
    await AudioService.getInstance().whenReady();
    if (this.isLeaving) return;
    let b = SearchCache.get(this.bookId);
    const speechBook = TextToSpeechService.getInstance().currentBook();
    const current = speechBook?.id === this.bookId ? speechBook : this.playerState.currentBook;
    if (b && current && this.isSameBook(b, current)
      && b.chapters.length === 0 && current.chapters.length > 0) {
      b = current;
    }
    if (!b || b.chapters.length === 0) {
      const stored = await DataService.getBookById(this.context!, this.bookId) || null;
      if (this.isLeaving) return;
      if (!b || (stored && this.isSameBook(b, stored)
        && b.chapters.length === 0 && stored.chapters.length > 0)) {
        b = stored;
      }
    }
    if (!b && current) {
      // 不强制 id 匹配:卡片语义就是"打开正在播放的书",不同会话间 id 可能因
      // hash 算法差异而不一致(home_audio_xxx / search_audio_xxx),只要有 currentBook 就用
      b = current;
    }
    if (!b) {
      console.error('[PlayerPage] loadBook failed, book not found');
      this.getUIContext().animateTo({ duration: 300, curve: Curve.FastOutLinearIn }, () => {
        this.navStack.pop(false);
      });
      return;
    }
    if (b.contentType === 'text') {
      if (this.context === null) return;
      await TextToSpeechService.getInstance().initialize(this.context);
      await PreferenceService.applyTocOrder(b);
      if (this.isLeaving) return;
      this.book = b;
      this.chapterDataSource.setChapters(PreferenceService.orderedChapters(b));
      this.loadSourceName(b);
      this.isFavorite = await PreferenceService.isFavorite(b.id);
      return;
    }
    AudioService.getInstance().setPlayMode(PlayMode.Sequence);
    if (this.needsChapterHydration(b)) {
      b = await this.hydrateBookChapters(b);
      if (this.isLeaving) return;
    }
    // 独立 KV 为权威:贴回 skip,纠正冷启动缓存书壳可能丢失的跳过头尾
    await PreferenceService.applySkipConfig(b);
    await PreferenceService.applyTocOrder(b);
    if (this.isLeaving) return;
    this.book = b;
    this.loadSourceName(b);
    this.chapterDataSource.setChapters(PreferenceService.orderedChapters(b));
    const pendingToc = BookSourceService.pendingAudioBook(b.id);
    if (pendingToc !== undefined) {
      BookSourceService.loadAudioBook(b, (loaded: Book): void => {
        if (this.isLeaving || this.book?.id !== loaded.id) return;
        this.book = this.cloneBookWithChapters(loaded, loaded.chapters, loaded.intro, loaded.variables);
        this.chapterDataSource.setChapters(PreferenceService.orderedChapters(loaded));
      }).catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'background toc failed: %{public}s', error.message);
      });
    }
    if (current && this.isSameBook(current, b)
      && current.chapters.length < b.chapters.length) {
      this.playerState.currentBook = b;
      if (this.playerState.currentChapter) {
        const currentIndex = DataService.resolveChapterIndex(
          b, this.playerState.currentChapter.id, this.playerState.currentChapter.title);
        if (currentIndex >= 0) this.playerState.currentChapter = b.chapters[currentIndex];
      }
    }
    AudioService.getInstance().prewarmBookSource(b);
    this.isFavorite = await PreferenceService.isFavorite(b.id);
    if (this.isLeaving) return;
    // 绑定全局状态/上下文
    AudioService.getInstance().bind(this.playerState, this.context!);

    // 历史记录入口：若指定了恢复章节，且当前 AudioService 没有在播放该章节，则主动起播 + seek
    if (this.resumeChapterId && !this.isLeaving) {
      await this.tryResumePlay(b);
    }
  }

  private isSameBook(left: Book, right: Book): boolean {
    if (left.id === right.id) return true;
    return left.bookUrl.length > 0 && left.bookUrl === right.bookUrl && left.sourceUrl === right.sourceUrl;
  }

  private isSpeechBook(): boolean {
    return this.book?.contentType === 'text';
  }

  private speechMatchesBook(): boolean {
    return this.book !== null && this.speechState.bookId === this.book.id;
  }

  private playbackLoading(): boolean {
    return this.isSpeechBook() ? this.speechMatchesBook() && this.speechState.loading : this.playerState.isLoading;
  }

  private playbackPlaying(): boolean {
    return this.isSpeechBook() ? this.speechMatchesBook() && this.speechState.playing : this.playerState.isPlaying;
  }

  private playbackSpeed(): number {
    return this.isSpeechBook() ? this.speechState.speed : this.playerState.speed;
  }

  private playbackChapter(): Chapter | null {
    if (!this.isSpeechBook()) return this.playerState.currentChapter;
    return this.speechMatchesBook() ? this.book?.chapters[this.speechState.chapterIndex] ?? null : null;
  }

  private setPlaybackSpeed(speed: number): void {
    if (this.isSpeechBook()) TextToSpeechService.getInstance().setSpeed(speed);
    else AudioService.getInstance().setSpeed(speed);
  }

  private skipPlayback(delta: number): void {
    if (this.isSpeechBook()) {
      if (this.speechMatchesBook()) TextToSpeechService.getInstance().skipSentence(delta);
    } else {
      AudioService.getInstance().seekBy(delta * 15000);
    }
  }

  private canSkipPlayback(): boolean {
    if (this.isSpeechBook()) return this.speechMatchesBook() && !this.speechState.loading && this.speechState.contentLength > 0;
    return !this.isLiveBook() && !this.playerState.isLoading && this.playerState.durationMs > 0;
  }

  private speechProgress(): number {
    if (!this.speechMatchesBook() || this.speechState.contentLength <= 0) return 0;
    return Math.max(0, Math.min(100, this.speechState.charOffset * 100 / this.speechState.contentLength));
  }

  private openVoiceOptions(): void {
    if (!this.isSpeechBook()) {
      this.sourceVoiceDraft = this.book?.variables?.['__audioSourceVoice'] ?? this.book?.variables?.['custom'] ?? '';
    } else if (!this.showSourceVoice && this.speechState.voices.length === 0) {
      TextToSpeechService.getInstance().refreshVoices();
    }
    this.showSourceVoice = !this.showSourceVoice;
  }

  private selectedPlaybackVoiceId(): string {
    if (!this.isSpeechBook()) return this.sourceVoiceDraft;
    if (this.speechState.customTtsId) return this.speechState.customTtsId;
    const voice = this.playbackSpeechVoices().find((item: SpeechVoice): boolean => this.speechState.isVoiceSelected(item));
    return voice === undefined ? '' : `system:${voice.id}`;
  }

  private playbackSpeechVoices(): SpeechVoice[] {
    return this.speechState.voices.filter((voice: SpeechVoice): boolean => voice.installed);
  }

  private async saveSpeechVoice(id: string): Promise<void> {
    if (this.savingSourceVoice || id === this.selectedPlaybackVoiceId()) return;
    this.savingSourceVoice = true;
    try {
      const service = TextToSpeechService.getInstance();
      const voice = this.playbackSpeechVoices().find((item: SpeechVoice): boolean => `system:${item.id}` === id);
      if (voice !== undefined) await service.selectVoice(voice);
      else await service.selectCustomTts(id);
    }
    catch (_error) { this.getUIContext().getPromptAction().showToast({ message: $r('app.string.tts_save_error') }); }
    finally { this.savingSourceVoice = false; }
  }

  private async loadSourceName(book: Book): Promise<void> {
    this.sourceVoiceAvailable = false;
    this.sourceVoices.setVoices([]);
    if (!book.sourceUrl) {
      this.sourceName = $r('app.string.player_source_local');
      return;
    }
    this.sourceName = $r('app.string.player_source_unknown');
    const source = await SourceDataService.getSourceByUrl(book.sourceUrl);
    if (this.isLeaving || this.book?.id !== book.id || this.book?.sourceUrl !== book.sourceUrl) return;
    this.sourceName = source?.bookSourceName || $r('app.string.player_source_unknown');
    if (source instanceof LocalRuleSource) {
      try {
        const voices = await LightSourceBridge.voices(source);
        if (this.isLeaving || this.book?.id !== book.id || this.book?.sourceUrl !== book.sourceUrl) return;
        this.sourceVoices.setVoices(voices, book.variables);
        this.sourceVoiceAvailable = this.sourceVoices.totalCount() > 0 ||
          !!(book.variables?.['__audioSourceVoice'] ?? book.variables?.['custom']);
      } catch (_error) {
        // Missing voice declarations must not interrupt loading the book.
      }
    }
  }

  private async saveSourceVoice(voice: string): Promise<void> {
    const book = this.book;
    if (book === null || this.savingSourceVoice || this.reloadingChapter || this.playerState.isLoading) return;
    const variables: Record<string, string> = JSON.parse(JSON.stringify(book.variables ?? {}));
    if (voice === (variables['__audioSourceVoice'] ?? variables['custom'] ?? '')) {
      this.showSourceVoice = false;
      return;
    }
    variables['custom'] = voice;
    variables['__audioSourceVoice'] = voice;
    const updated = this.cloneBookWithChapters(book, book.chapters, book.intro, variables);
    const previousVoice = this.sourceVoiceDraft;
    this.sourceVoiceDraft = voice;
    this.savingSourceVoice = true;
    try {
      await DataService.upsertCachedBook(updated);
      const cache = ChapterCacheService.getInstance();
      cache.clearBook(book.id, book.chapters);
      book.variables = variables;
      SearchCache.put(updated);
      if (this.playerState.currentBook?.id === book.id) this.playerState.currentBook.variables = variables;
      if (!this.isLeaving && this.book?.id === book.id) {
        this.book = updated;
        this.showSourceVoice = false;
        // 切换规则参数时按当前进度重新解析，旧音频缓存不再参与本次播放。
        await this.reloadCurrentChapter();
      }
    } catch (_error) {
      this.sourceVoiceDraft = previousVoice;
      if (!this.isLeaving) this.showToast($r('app.string.settings_save_failed'));
    } finally {
      this.savingSourceVoice = false;
    }
  }

  @Builder
  private buildSourceVoiceOption(id: string, label: ResourceStr): void {
    Button({ type: ButtonType.Normal }) {
      Row({ space: AppSpace.Md }) {
        Text(label).fontSize(16)
          .fontColor(this.selectedPlaybackVoiceId() === id ? AppColor.Brand : $r('sys.color.font_primary'))
          .layoutWeight(1).textAlign(TextAlign.Start).maxLines(1).textOverflow({ overflow: TextOverflow.MARQUEE })
          .marqueeOptions({ start: this.showSourceVoice, step: 0.5, loop: -1 }).clip(true)
        if (this.selectedPlaybackVoiceId() === id) {
          if (this.savingSourceVoice) {
            LoadingProgress().width(22).height(22).color(AppColor.Brand)
          } else {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(20).fontColor([AppColor.Brand])
              .accessibilityText($r('app.string.tts_selected'))
          }
        }
      }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Sm })
    }
    .width('100%').height(48).borderRadius(AppRadius.Xl - AppSpace.Xs)
    .backgroundColor(this.selectedPlaybackVoiceId() === id ? AppColor.BrandSoft : Color.Transparent)
    .enabled(!this.savingSourceVoice && !this.reloadingChapter && (this.isSpeechBook() || !this.playerState.isLoading))
    .onClick((): void => {
      this.showSourceVoice = false;
      if (this.isSpeechBook()) this.saveSpeechVoice(id);
      else this.saveSourceVoice(id);
    }).id(`source-voice-${id || 'default'}`)
  }

  private selectedSourceVoiceIndex(): number {
    if (this.isSpeechBook()) {
      const voices = this.playbackSpeechVoices();
      if (!this.speechState.customTtsId) {
        return Math.max(0, voices.findIndex((voice: SpeechVoice): boolean => this.speechState.isVoiceSelected(voice)));
      }
      const index = this.speechState.customTtsConfigs.findIndex((config: CustomTtsConfig): boolean =>
        config.id === this.speechState.customTtsId);
      return index < 0 ? 0 : voices.length + index;
    }
    for (let index = 0; index < this.sourceVoices.totalCount(); index++) {
      if (this.sourceVoices.getData(index).id === this.sourceVoiceDraft) return index + 1;
    }
    return 0;
  }

  private scrollToSelectedSourceVoice(): void {
    this.getUIContext().postFrameCallback(new PlayerLayoutReadyFrame((): void => {
      if (!this.showSourceVoice || this.isLeaving) return;
      const index = this.selectedSourceVoiceIndex();
      this.sourceVoiceScroller.scrollToIndex(index, false, index === 0 ? ScrollAlign.START : ScrollAlign.CENTER);
    }));
  }

  private sourceVoiceMenuOptions(): CustomPopupOptions {
    const options: CustomPopupOptions = {
      builder: this.buildSourceVoiceMenu,
      placement: Placement.BottomRight,
      popupColor: Color.Transparent,
      radius: AppRadius.Xl,
      enableArrow: false,
      focusable: true,
      onStateChange: (event): void => {
        this.showSourceVoice = event.isVisible;
        if (event.isVisible) this.scrollToSelectedSourceVoice();
      }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    else options.backgroundBlurStyle = AppMaterial.SheetBlur;
    return options;
  }

  @LocalBuilder
  buildSourceVoiceMenu() {
    Column() {
      List({ scroller: this.sourceVoiceScroller, initialIndex: this.selectedSourceVoiceIndex() }) {
        if (this.isSpeechBook()) {
          Repeat<SpeechVoice>(this.playbackSpeechVoices()).each((item: RepeatItem<SpeechVoice>) => {
            ListItem() { this.buildSourceVoiceOption(`system:${item.item.id}`, item.item.label) }
          }).key((voice: SpeechVoice): string => `system:${voice.id}`).virtualScroll()
          Repeat<CustomTtsConfig>(this.speechState.customTtsConfigs).each((item: RepeatItem<CustomTtsConfig>) => {
            ListItem() { this.buildSourceVoiceOption(item.item.id, item.item.name) }
          }).key((config: CustomTtsConfig): string => config.id).virtualScroll()
        } else {
        ListItem() {
          this.buildSourceVoiceOption('', $r('app.string.player_source_voice_default'))
        }
        LazyForEach(this.sourceVoices, (voice: LocalRuleVoice): void => {
          ListItem() { this.buildSourceVoiceOption(voice.id, voice.name) }
        }, (voice: LocalRuleVoice): string => voice.id)
        }
      }.width('100%').height(Math.min(288, Math.max(1, this.isSpeechBook() ?
        this.speechState.customTtsConfigs.length + this.playbackSpeechVoices().length : this.sourceVoices.totalCount() + 1) * 48))
        .scrollBar(BarState.Off)
    }
    .width(Math.min(180, Math.max(120, this.viewportWidth - 32))).padding(AppSpace.Xs)
  }

  private needsChapterHydration(book: Book): boolean {
    if (book.tocComplete === false) {
      return book.chapters.length === 0;
    }
    return book.chapters.length === 0 || (book.chapters.length === 1 && book.chapterCount > 1);
  }

  private cloneBookWithChapters(book: Book, chapters: Chapter[], intro: string,
    variables: Record<string, string> | undefined): Book {
    const hydrated: Book = {
      id: book.id,
      contentType: book.contentType,
      title: book.title,
      author: book.author,
      narrator: book.narrator,
      cover: book.cover,
      coverFromDetail: book.coverFromDetail,
      coverFallback: book.coverFallback,
      category: book.category,
      intro: intro,
      wordCount: book.wordCount,
      latestChapterTitle: book.latestChapterTitle,
      updateTime: book.updateTime,
      totalDuration: book.totalDuration,
      chapterCount: chapters.length,
      rating: book.rating,
      tags: book.tags,
      chapters: chapters,
      tocComplete: book.tocComplete,
      bookUrl: book.bookUrl,
      sourceUrl: book.sourceUrl,
      variables: variables,
      skipIntro: book.skipIntro,
      skipOutro: book.skipOutro,
      chaptersDescending: book.chaptersDescending,
      completed: book.completed
    };
    return hydrated;
  }

  private async hydrateBookChapters(book: Book): Promise<Book> {
    if (!this.needsChapterHydration(book) || this.chapterLoadInProgress) return book;
    this.chapterLoadInProgress = true;
    try {
      if (book.tocComplete === false) {
        return await BookSourceService.loadAudioBook(book, (_loaded: Book): void => {});
      }
      const localChapters = await DataService.getChaptersForBook(book.id);
      if (localChapters.length > 0
        && !(localChapters.length === 1 && book.chapterCount > 1)) {
        const localBook = this.cloneBookWithChapters(book, localChapters, book.intro, book.variables);
        SearchCache.put(localBook);
        return localBook;
      }
      if (!book.bookUrl || !book.sourceUrl) return book;
      const source = await SourceDataService.getSourceByUrl(book.sourceUrl);
      if (!source) return book;
      const bookInfo = await BookSourceService.getBookInfo(source, book.bookUrl, book.variables);
      const tocUrl = bookInfo?.tocUrl || book.bookUrl;
      const variables = bookInfo?.variables || book.variables;
      const tocItems = await BookSourceService.getBookToc(source, tocUrl, variables, book.title);
      if (tocItems.length === 0) return book;
      const chapters = tocItems.map((item: TocItem, index: number): Chapter => ({
        id: `${book.id}-c${index}`,
        index: index + 1,
        title: item.name,
        duration: item.duration || 0,
        source: { type: 'url', value: item.url },
        originSourceValue: item.url,
        variables: item.variables
      }));
      const hydrated = this.cloneBookWithChapters(book, chapters, bookInfo?.intro || book.intro, variables);
      await DataService.upsertCachedBook(hydrated);
      SearchCache.put(hydrated);
      return hydrated;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'hydrate chapters failed: %{public}s', String(e));
      return book;
    } finally {
      this.chapterLoadInProgress = false;
    }
  }

  private async reloadEmptyChapterList(book: Book): Promise<void> {
    const hydrated = await this.hydrateBookChapters(book);
    if (this.isLeaving || hydrated.chapters.length === 0) return;
    this.book = hydrated;
    this.chapterDataSource.setChapters(PreferenceService.orderedChapters(hydrated));
    if (!this.chapterListInteracted) this.scrollToCurrentChapter();
  }

  private async tryResumePlay(book: Book): Promise<void> {
    const target = book.chapters.find((c) => c.id === this.resumeChapterId);
    if (!target) {
      hilog.warn(DOMAIN, TAG, 'resume chapter not found: %{public}s', this.resumeChapterId);
      return;
    }
    // ★ PlaybackStore 同书+同章节命中:直接复用 live state,不调 AudioService 任何方法,
    //   绝对不会触发 reset。即使 progressMs 与 resumeProgressMs 略有差异,以 live 为准
    if (PlaybackStore.getInstance().isCurrentChapter(book.id, target.id)) {
      return;
    }
    // 切到不同章节(可能不同书) → AudioService 内部会 same-book/same-chapter 短路或 reset
    SearchCache.put(book);
    await AudioService.getInstance().playChapterAndSeek(book, target, this.resumeProgressMs);
  }

  private formatMs(ms: number): string {
    const total = Math.floor(ms / 1000);
    const m = Math.floor(total / 60);
    const s = total % 60;
    const mm = m < 10 ? '0' + m : m.toString();
    const ss = s < 10 ? '0' + s : s.toString();
    return mm + ':' + ss;
  }

  /** Slider max 与右侧总时长显示用同一份兜底:prepared 前用 savedDurationMs */
  private sliderMaxMs(): number {
    if (this.playerState.durationMs > 0) return this.playerState.durationMs;
    if (this.playerState.savedDurationMs > 0) return this.playerState.savedDurationMs;
    return 1;
  }

  private displayDurationMs(): number {
    if (this.playerState.durationMs > 0) return this.playerState.durationMs;
    return this.playerState.savedDurationMs;
  }

  /** prepared 前继续显示已保存的进度，避免续播加载时滑块先归零再跳回。 */
  private progressValueMs(): number {
    const max = this.sliderMaxMs();
    if (max <= 1) return 0;
    const value = this.seeking ? this.seekValueMs : this.playerState.progressMs;
    return Math.max(0, Math.min(value, max));
  }

  private async togglePlay(): Promise<void> {
    if (this.isSpeechBook()) {
      const speech = TextToSpeechService.getInstance();
      if (this.speechMatchesBook()) {
        if (this.speechState.playing || this.speechState.loading) speech.pause();
        else await speech.resume();
      } else if (this.book !== null) {
        await speech.start(this.book, 0, 0, true);
      }
      return;
    }
    await AudioService.getInstance().toggle();
  }

  private async playPrev(): Promise<void> {
    if (this.isSpeechBook()) {
      if (this.speechMatchesBook()) await TextToSpeechService.getInstance().moveChapter(-1);
      return;
    }
    if (!this.book || !this.playerState.currentChapter) return;
    const idx = this.currentChapterIndex();
    const target = idx - 1;
    if (idx >= 0 && target >= 0 && target < this.book.chapters.length) {
      const ch = this.book.chapters[target];
      // AudioService 内部会查缓存/解析 URL，这里不用再做
      await AudioService.getInstance().playChapterFromSavedProgress(this.book, ch);
    }
  }

  private async playNext(): Promise<void> {
    if (this.isSpeechBook()) {
      if (this.speechMatchesBook()) await TextToSpeechService.getInstance().moveChapter(1);
      return;
    }
    if (!this.book || !this.playerState.currentChapter) return;
    const idx = this.currentChapterIndex();
    const target = idx + 1;
    if (idx >= 0 && target >= 0 && target < this.book.chapters.length) {
      const ch = this.book.chapters[target];
      await AudioService.getInstance().playChapter(this.book, ch);
    }
  }

  private async toggleFavorite(): Promise<void> {
    if (!this.book) return;
    // 收藏 id 还在但本地快照已丢失:补回快照、保留收藏,而不是把仅存的收藏 id 也 toggle 掉
    if (this.isFavorite && this.context) {
      const snap = await DataService.getBookById(this.context!, this.book.id);
      if (!snap) {
        await DataService.upsertCachedBook(this.book);
        this.isFavorite = true;
        try {
          this.getUIContext().getPromptAction().showToast({ message: '已重新加入书架' });
        } catch (_e) { /* ignore */ }
        return;
      }
    }
    this.isFavorite = await PreferenceService.toggleFavorite(this.book.id);
    if (this.isFavorite) {
      await DataService.upsertCachedBook(this.book);
    }
  }

  /** 倍速显示:整十分位用一位小数(1.0/1.2/2.0),其余保留两位(0.75/1.25) */
  private fmtSpeed(s: number): string {
    const r = Math.round(s * 20) / 20;
    return Math.abs(r * 10 - Math.round(r * 10)) < 1e-6 ? r.toFixed(1) : r.toFixed(2);
  }

  private async resetSpeed(): Promise<void> {
    if (this.playbackSpeed() === 1.0) return;
    this.hapticTick();
    this.speedValue = 1;
    this.setPlaybackSpeed(1);
  }

  private isCurrentChapter(ch: Chapter): boolean {
    if (this.isSpeechBook()) return this.playbackChapter()?.id === ch.id;
    if (!this.playerState.currentChapter) return false;
    if (this.playerState.currentChapter.id === ch.id) return true;
    if (!this.book) return false;
    const idx = this.currentChapterIndex();
    return idx >= 0 && this.book.chapters[idx].id === ch.id;
  }

  private formatDuration(seconds: number): string {
    if (!seconds || seconds <= 0) return '';
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    if (h > 0) {
      return h + '时' + (m > 0 ? m + '分' : '') + (s > 0 ? s + '秒' : '');
    }
    if (m > 0) {
      return m + '分' + (s > 0 ? s + '秒' : '');
    }
    return s + '秒';
  }

  /** 章节列表显示用的时长（秒）：优先用 chapter 自身的 duration，否则用 ChapterCacheService 解析出来的 */
  private chapterDurationSec(ch: Chapter): number {
    // 通过读 chapterCacheTick 把这个 getter 纳入 V2 依赖图,缓存解析完成后能自动重算
    if (this.chapterCacheTick < 0) return 0;
    if (ch.duration && ch.duration > 0) return ch.duration;
    return ChapterCacheService.getInstance().getChapterDuration(ch.id);
  }

  private chapterDownloadRecord(ch: Chapter): DownloadChapterRecord | null {
    if (this.downloadTick < 0 || !this.book) return null;
    return DownloadService.getInstance().getChapterStatus(this.book.id, ch);
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (_e) {
      // ignore
    }
  }

  private handleChapterDownloadLongPress(ch: Chapter): void {
    if (!this.book || this.isSpeechBook()) return;
    if (this.playerState.isLive && this.playerState.currentChapter?.id === ch.id) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.player_live_no_download') });
      return;
    }
    const record = this.chapterDownloadRecord(ch);
    if (record?.status === 'completed') {
      this.confirmDeleteChapterDownload(ch);
      return;
    }
    if (record && (record.status === 'pending' || record.status === 'resolving' || record.status === 'downloading')) {
      this.showToast('这一章正在下载');
      return;
    }
    DownloadService.getInstance().downloadChapter(this.book, ch).then(() => {
      this.downloadTick = this.downloadTick + 1;
      this.showToast('已加入单章下载');
    }).catch(() => this.showToast('下载操作失败，请重试'));
  }

  private isLiveBook(): boolean {
    return this.playerState.isLive && !this.playerState.isLoading &&
      this.playerState.currentBook?.id === this.book?.id;
  }

  private confirmDeleteChapterDownload(ch: Chapter): void {
    if (!this.book) return;
    const prompt = this.getUIContext().getPromptAction();
    prompt.showDialog({
      title: '删除单章下载',
      message: `删除《${ch.title}》的离线音频？`,
      buttons: [
        { text: '取消', color: '#8F8F8F' },
        { text: '删除', color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1 && this.book) {
        DownloadService.getInstance().deleteChapterDownload(
          this.book.id, ch.id, DownloadPolicy.stablePageUrl(ch)).then(() => {
          this.downloadTick = this.downloadTick + 1;
          this.showToast('单章下载已删除');
        }).catch(() => this.showToast('删除下载失败，请重试'));
      }
    }).catch(() => { /* ignore */ });
  }

  private async selectChapter(ch: Chapter): Promise<void> {
    if (!this.book) return;
    // 立即关抽屉（不要等 await playChapter，否则 WebView 嗅探的几秒内 UI 卡在章节列表上）
    this.showChapterList = false;
    if (this.isSpeechBook()) {
      const index = this.book.chapters.findIndex((chapter: Chapter): boolean => chapter.id === ch.id);
      if (index >= 0) await TextToSpeechService.getInstance().start(this.book, index, 0);
      return;
    }
    // AudioService 内部用 playGen 替换式取消旧任务，所以反复点章节不会叠加
    AudioService.getInstance().playChapterFromSavedProgress(this.book, ch).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'selectChapter failed: %{public}s', e.message);
    });
  }

  /** 打开章节列表,加载全部章节 */
  private openChapterList(): void {
    this.cancelChapterPosition();
    this.chapterListInteracted = false;
    this.showChapterList = true;
    this.listOffsetFromCurrent = 0;
    this.chapterSearchKeyword = '';
    this.chapterDescending = this.book?.chaptersDescending ?? false;
    if (!this.book) return;
    this.chapterDataSource.setChapters(PreferenceService.orderedChapters(this.book));
    if (this.book.chapters.length === 0) {
      this.reloadEmptyChapterList(this.book);
    }
  }

  @Monitor('showChapterList')
  private onChapterListVisibilityChanged(): void {
    if (!this.showChapterList) this.cancelChapterPosition();
  }

  private cancelChapterPosition(): void {
    if (this.chapterPositionTimer === -1) return;
    clearTimeout(this.chapterPositionTimer);
    this.chapterPositionTimer = -1;
  }

  private interruptChapterPosition(): void {
    this.chapterListInteracted = true;
    this.cancelChapterPosition();
  }

  /** 按关键词过滤章节列表（关键词为空时还原全部，并滚回当前章节） */
  private toggleChapterOrder(): void {
    const book = this.book;
    if (!book) return;
    book.chaptersDescending = !book.chaptersDescending;
    this.chapterDescending = book.chaptersDescending;
    PreferenceService.saveTocOrder(book.id, book.chaptersDescending).catch((): void => {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.chapter_order_save_failed') });
    });
    this.applyChapterFilter(this.chapterSearchKeyword);
    this.scrollChapterListToIndex(0, ScrollAlign.START);
    this.chapterTopRequest++;
  }

  private applyChapterFilter(keyword: string): void {
    this.interruptChapterPosition();
    this.chapterSearchKeyword = keyword;
    if (!this.book) return;
    const kw = keyword.trim().toLowerCase();
    if (!kw) {
      this.chapterDataSource.setChapters(PreferenceService.orderedChapters(this.book));
      this.scrollToCurrentChapter();
      return;
    }
    const filtered = PreferenceService.orderedChapters(this.book).filter((c) => c.title.toLowerCase().includes(kw));
    this.chapterDataSource.setChapters(filtered);
    // 过滤结果重置滚动到顶部
    this.scrollChapterListToIndex(0, ScrollAlign.START);
  }

  private scrollToCurrentChapter(): void {
    this.cancelChapterPosition();
    if (this.chapterGridVisible || this.chapterSearchKeyword.trim().length > 0) return;
    if (!this.book || !this.playerState.currentChapter) return;
    const idx = this.currentChapterIndex();
    this.scrollChapterListToIndex(this.book ? PreferenceService.chapterDisplayIndex(this.book, idx) : idx);
  }

  /**
   * 可靠定位章节列表到指定 index。
   * 两段式延迟:首次等抽屉/列表挂载并完成首屏布局(规避 setTimeout(0) 的挂载竞态),
   * 把目标项拉进 LazyForEach 渲染窗口;二次等目标项真实行高确定后再精确居中,
   * 修正长列表按平均行高估算导致的 ScrollAlign.CENTER 偏差。
   * 两阶段共用可取消的定时器；用户开始操作后，不再执行剩余定位。
   */
  private scrollChapterListToIndex(idx: number, align: ScrollAlign = ScrollAlign.CENTER): void {
    this.cancelChapterPosition();
    if (idx < 0 || !this.showChapterList || this.chapterGridVisible || this.isLeaving) return;
    this.chapterPositionTimer = setTimeout((): void => {
      this.chapterPositionTimer = -1;
      if (!this.showChapterList || this.chapterGridVisible || this.isLeaving) return;
      try { this.chapterListScroller.scrollToIndex(idx, false, align); } catch (_e) { /* ignore */ }
      if (align !== ScrollAlign.CENTER) return;
      this.chapterPositionTimer = setTimeout((): void => {
        this.chapterPositionTimer = -1;
        if (!this.showChapterList || this.chapterGridVisible || this.isLeaving) return;
        try { this.chapterListScroller.scrollToIndex(idx, false, ScrollAlign.CENTER); } catch (_e) { /* ignore */ }
      }, 150);
    }, 50);
  }

  /** "回到当前章节"按钮:居中滚到当前章节 */
  private jumpToCurrentChapter(): void {
    this.scrollToCurrentChapter();
    this.listOffsetFromCurrent = 0;
  }

  /** 当前播放章节在列表中的索引 */
  private currentChapterIndex(): number {
    if (this.isSpeechBook()) return this.speechMatchesBook() ? this.speechState.chapterIndex : -1;
    if (!this.book || !this.playerState.currentChapter) return -1;
    return DataService.resolveChapterIndex(
      this.book,
      this.playerState.currentChapter.id,
      this.playerState.currentChapter.title
    );
  }

  /** 是否需要显示"回到当前章节"浮动按钮:列表滚动距离当前章节超过 200vp（搜索过滤时不显示） */
  private shouldShowJumpButton(): boolean {
    return this.chapterSearchKeyword.trim().length === 0
      && Math.abs(this.listOffsetFromCurrent) > 200;
  }

  private formatSleepRemaining(): string {
    const ms = this.isSpeechBook() ? this.speechState.remainingSeconds * 1000 : this.playerState.sleepRemainingMs;
    const totalSec = Math.floor(ms / 1000);
    const m = Math.floor(totalSec / 60);
    const s = totalSec % 60;
    return m + ':' + (s < 10 ? '0' : '') + s;
  }

  private sleepActive(): boolean {
    if (this.isSpeechBook()) return this.speechMatchesBook() &&
      (this.speechState.stopAtChapterEnd || this.speechState.remainingSeconds > 0);
    return this.playerState.sleepMode !== SleepMode.Off;
  }

  private sleepLabel(): string {
    if (this.isSpeechBook()) {
      if (this.speechState.stopAtChapterEnd) {
        return this.context?.resourceManager.getStringSync($r('app.string.tts_sleep_chapter').id) ?? '';
      }
      return this.sleepActive() ? this.formatSleepRemaining()
        : this.context?.resourceManager.getStringSync($r('app.string.tts_sleep').id) ?? '';
    }
    if (this.playerState.sleepMode === SleepMode.Chapters) {
      return this.playerState.sleepChaptersRemaining === 1
        ? this.getUIContext().getHostContext()!.resourceManager.getStringSync($r('app.string.player_sleep_this_chapter').id)
        : this.getUIContext().getHostContext()!.resourceManager.getStringSync(
          $r('app.string.player_sleep_remaining_chapters').id, this.playerState.sleepChaptersRemaining);
    }
    if (this.playerState.sleepWaitingForChapter) {
      return this.getUIContext().getHostContext()!.resourceManager.getStringSync($r('app.string.player_sleep_this_chapter').id);
    }
    return this.sleepActive() ? this.formatSleepRemaining()
      : this.getUIContext().getHostContext()!.resourceManager.getStringSync($r('app.string.player_sleep').id);
  }

  private sleepAlarmClipPath(): string {
    const context = this.getUIContext();
    const size = context.vp2px(20);
    const notchX = context.vp2px(10);
    const notchY = context.vp2px(6);
    return this.sleepActive() ? `M0 0 H${notchX} V${notchY} H${size} V${size} H0 Z` :
      `M0 0 H${size} V${size} H0 Z`;
  }

  private sleepBadgeLabel(): ResourceStr {
    if (this.isSpeechBook()) return this.speechState.stopAtChapterEnd
      ? $r('app.string.player_sleep_current_badge') : this.formatSleepRemaining();
    if (this.playerState.sleepMode === SleepMode.Chapters) {
      return $r('app.string.player_sleep_chapters_badge', this.playerState.sleepChaptersRemaining);
    }
    if (this.playerState.sleepWaitingForChapter) return $r('app.string.player_sleep_current_badge');
    return this.formatSleepRemaining();
  }

  private sleepSheetDismissUntil: number = 0;

  private openSleepSheet(): void {
    if (this.showSleepSheet || Date.now() < this.sleepSheetDismissUntil) return;
    if (this.sleepActive()) {
      this.sleepSheetMode = this.playerState.sleepMode;
      this.sleepSmartStopDraft = this.playerState.sleepSmartStop;
    } else {
      this.sleepSheetMode = this.playerState.lastSleepMode;
    }
    this.sleepCustomVisible = false;
    this.sleepInputError = '';
    this.showSleepSheet = true;
  }

  private selectSleepMode(mode: SleepMode): void {
    this.sleepSheetMode = mode;
    this.sleepCustomVisible = false;
    this.sleepInputError = '';
  }

  private setSleep(minutes: number): void {
    if (this.isSpeechBook()) {
      TextToSpeechService.getInstance().setSleep(minutes);
      this.showSleepSheet = false;
      return;
    }
    if (minutes === 0) {
      AudioService.getInstance().cancelSleepTimer();
      this.showToast($r('app.string.player_sleep_cancelled'));
    } else if (AudioService.getInstance().setSleepTimer(minutes, this.sleepSmartStopDraft)) {
      this.showToast($r('app.string.player_sleep_minutes_set', minutes));
    } else {
      this.sleepInputError = $r('app.string.player_sleep_minutes_error');
      return;
    }
    this.showSleepSheet = false;
  }

  private selectSleepOption(value: number): void {
    if (value === 0) {
      this.sleepCustomVisible = true;
      const selected = this.sleepSheetMode === SleepMode.Duration
        ? this.playerState.sleepMinutes : this.playerState.sleepChapterCount;
      this.sleepCustomValue = this.playerState.sleepMode === this.sleepSheetMode && selected > 0
        ? selected.toString() : '';
      this.sleepInputError = '';
      return;
    }
    if (this.sleepSheetMode === SleepMode.Duration) {
      this.setSleep(value);
      return;
    }
    if (!AudioService.getInstance().setSleepChapters(value)) {
      this.sleepInputError = $r('app.string.player_sleep_chapters_error', this.sleepChapterLimit());
      return;
    }
    this.showToast($r('app.string.player_sleep_target', this.playerState.sleepTargetTitle));
    this.showSleepSheet = false;
  }

  private sleepChapterLimit(): number {
    return AudioService.getInstance().getAvailableSleepChapters();
  }

  private submitCustomSleep(): void {
    const value = Number(this.sleepCustomValue);
    const max = this.sleepSheetMode === SleepMode.Duration ? 1440 : this.sleepChapterLimit();
    if (!new RegExp('^[0-9]+$').test(this.sleepCustomValue) || !Number.isInteger(value) || value < 1 || value > max) {
      this.sleepInputError = this.sleepSheetMode === SleepMode.Duration
        ? $r('app.string.player_sleep_minutes_error') : $r('app.string.player_sleep_chapters_error', max);
      return;
    }
    this.selectSleepOption(value);
  }

  private sleepOptionSelected(value: number): boolean {
    if (this.playerState.sleepMode !== this.sleepSheetMode) return false;
    const selected = this.sleepSheetMode === SleepMode.Duration
      ? this.playerState.sleepMinutes : this.playerState.sleepChapterCount;
    if (value > 0) return selected === value;
    const presets: number[] = this.sleepSheetMode === SleepMode.Duration ? [15, 30, 45, 60] : [1, 3, 5, 7];
    return selected > 0 && !presets.includes(selected);
  }

  private sleepOptionLabel(value: number): ResourceStr {
    if (value === 0) {
      if (!this.sleepOptionSelected(0)) return $r('app.string.player_sleep_custom');
      return this.sleepSheetMode === SleepMode.Duration
        ? $r('app.string.player_sleep_custom_minutes', this.playerState.sleepMinutes)
        : $r('app.string.player_sleep_custom_chapters', this.playerState.sleepChapterCount);
    }
    if (this.sleepSheetMode === SleepMode.Duration) return $r('app.string.player_sleep_minutes', value);
    return value === 1 ? $r('app.string.player_sleep_finish_current') : $r('app.string.player_sleep_chapters', value);
  }

  private openBookDetail(): void {
    const id = this.book?.id || this.bookId;
    if (!id) {
      this.showToast('暂无书籍详情');
      return;
    }
    this.navStack.pushPathByName('detail', id);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.buildAmbientBackground()

      // 内容层
      Column() {
        if (this.book) {
          if (this.isLandscapePlayer()) {
            this.buildLandscapePlayerContent()
          } else if (this.isCompactPlayer()) {
            if (this.playerNeedsScroll()) {
              Scroll() {
                Column() {
                  this.buildPlayerContent(true)
                }
                .width('100%')
              }
              .width('100%')
              .layoutWeight(1)
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
            } else {
              this.buildPlayerContent(false)
            }
          } else {
            this.buildPlayerContent(false)
          }
        } else {
          Column()
            .width('100%')
            .height('100%')
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.playerTopPadding(),
        bottom: this.playerBottomPadding(),
        left: this.playerLeftPadding(),
        right: this.playerRightPadding()
      })

    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
      this.handleViewportSizeChange(newValue);
    })
  }

  @Builder
  buildLandscapePlayerContent() {
    if (this.isSpeechBook()) {
      Scroll() {
        Column() {
          this.buildPlayerContent(true)
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    } else {
    this.buildTopBar()
    Row({ space: AppSpace.Xl }) {
      Column() {
        this.buildCover()
      }
      .width(this.landscapeCoverSize())
      .height('100%')
      .justifyContent(FlexAlign.Center)

      Scroll() {
        Column() {
          this.buildMeta()
          if (this.isSpeechBook()) { this.buildSpeechParagraphs() }
          Blank().height(AppSpace.Md)
          this.buildProgress()
          this.buildControls()
          this.buildBottomBar()
        }
        .width('100%')
        .constraintSize({ minHeight: this.landscapeBodyHeight() })
        .justifyContent(FlexAlign.Center)
      }
      .layoutWeight(1)
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .layoutWeight(1)
    .margin({ top: AppSpace.Sm })
    }
  }

  @Builder
  buildPlayerContent(scrollable: boolean) {
    this.buildTopBar()
    if (this.isSpeechBook()) {
      this.buildSpeechBookHeader()
    } else {
      this.buildCover()
    }
    this.buildMeta()
    if (this.isSpeechBook()) { this.buildSpeechParagraphs(!scrollable) }
    // 仅滚动容器使用固定间距；可同屏显示时由 Blank 吸收余高，让播控贴合底部安全区。
    if (this.isSpeechBook()) {
      Blank().height(AppSpace.Sm)
    } else if (scrollable) {
      Blank().height(AppSpace.Md)
    } else {
      Blank()
    }
    this.buildProgress()
    this.buildControls()
    this.buildBottomBar()
  }

  @Builder
  buildAmbientBackground() {
    Stack() {
      if (this.book && this.book.cover) {
        if (this.book.cover.startsWith('http')) {
          CoverImage({ url: this.book.cover, useFixedHeight: true, imgHeight: '100%', radius: 0, decodeW: 120, decodeH: 120 })
            .width('100%')
            .height('100%')
            .blur(40)
        } else if (this.book.cover.startsWith('/') || this.book.cover.startsWith('file://')) {
          Image('file://' + this.book.cover.replace(/^file:\/\//, ''))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .sourceSize({ width: 120, height: 120 })
            .blur(40)
        } else {
          Image($rawfile(this.book.cover))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .blur(40)
        }
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#3B4650')
      }

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#0D0D0D')
        .opacity(0.7)
    }
    .width('100%')
    .height('100%')
  }

  private async reloadCurrentChapter(): Promise<void> {
    if (this.isSpeechBook() && this.book !== null) {
      if (this.speechMatchesBook()) {
        await TextToSpeechService.getInstance().start(this.book, this.speechState.chapterIndex, this.speechState.charOffset);
      }
      return;
    }
    const book = this.book;
    if (!book || this.reloadingChapter || this.playerState.isLoading) return;
    const current = this.playerState.currentBook?.id === book.id ? this.playerState.currentChapter : null;
    const chapter = current ?? book.chapters[0];
    if (!chapter) return;
    this.reloadingChapter = true;
    try {
      await AudioService.getInstance().playChapterAndSeek(book, chapter,
        current ? this.playerState.progressMs : 0, false, true);
    } catch (_error) {
      if (!this.isLeaving) this.showToast($r('app.string.content_reload_failed'));
    } finally { this.reloadingChapter = false; }
  }

  private async switchSource(book: Book, index: number, matched: boolean, oldFavoriteId: string, replace: boolean): Promise<void> {
    if (this.isLeaving || !this.showSourceSwitch) return;
    const chapter = book.chapters[index];
    if (!chapter) return;
    const progress = matched && this.playerState.currentBook?.id === this.book?.id ? this.playerState.progressMs : 0;
    const source = await SourceDataService.getSourceByUrl(book.sourceUrl);
    if (!source) throw new Error(this.context!.resourceManager.getStringSync($r('app.string.source_switch_unavailable').id));
    const chapterUrl = chapter.originSourceValue ?? chapter.source.value;
    const resolved = await BookSourceService.resolveAudioRequest(source, chapterUrl, book.variables, chapter.variables);
    if (!DownloadPolicy.isResolvedAudioUrl(chapterUrl, resolved.url, resolved.resolved)) {
      throw new Error(this.context!.resourceManager.getStringSync($r('app.string.source_switch_unavailable').id));
    }
    if (this.isLeaving || !this.showSourceSwitch) return;
    await DataService.upsertCachedBook(book);
    if (this.isLeaving || !this.showSourceSwitch) return;
    SearchCache.put(book);
    if (oldFavoriteId) await PreferenceService.replaceFavoriteSource(oldFavoriteId, book.id, replace);
    this.showSourceSwitch = false;
    const params = new PlayerSourceSwitchRoute();
    params.bookId = book.id;
    params.chapterId = chapter.id;
    params.progressMs = progress;
    this.navStack.replacePath({ name: 'player', param: params }, false);
  }

  @Builder
  private buildSourceSwitchSheet(): void {
    BookSourceSwitchSheet({ book: this.book,
      chapterTitle: this.playerState.currentBook?.id === this.book?.id ? this.playerState.currentChapter?.title ?? '' : '',
      chapterIndex: this.playerState.currentBook?.id === this.book?.id ? this.currentChapterIndex() : 0,
      onSelect: async (book: Book, index: number, matched: boolean, oldFavoriteId: string, replace: boolean): Promise<void> => {
        await this.switchSource(book, index, matched, oldFavoriteId, replace);
      }
    })
  }

  @Builder
  buildTopBar() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(24)
          .fontColor(['#FFFFFF'])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .attributeModifier(AppMaterial.modifier(AppMaterial.FloatingControl, AppColor.GlassSheetFallback))
      .onClick(() => {
        this.isLeaving = true;
        this.getUIContext().animateTo({ duration: 300, curve: Curve.FastOutLinearIn }, () => {
          this.navStack.pop(false);
        });
      })
      Blank()
      if (this.isSpeechBook()) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.book')).fontSize(24).fontColor(['#FFFFFF'])
        }.width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.tts_enter_reader')).id('tts-enter-reader')
          .margin({ right: 8 })
          .onClick((): void => { this.closeSpeechToReader(true); })
      }
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(24).fontColor(['#FFFFFF'])
      }
        .width(40).height(40).backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.content_reload'))
        .onClick((): void => { this.reloadCurrentChapter(); })
        .margin({ right: 8 })
        .enabled(!this.reloadingChapter && !this.playbackLoading() && this.book !== null)
      if (this.isSpeechBook() || (this.sourceVoiceAvailable && !this.isLiveBook())) {
        Button({ type: ButtonType.Circle }) {
          PlaybackWaveIcon({ playing: this.playbackPlaying() && !this.playbackLoading() })
        }
          .width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.player_source_voice_label'))
          .margin({ right: 8 })
          .enabled(this.isSpeechBook() || (!this.reloadingChapter && !this.playerState.isLoading && !this.savingSourceVoice))
          .onClick((): void => this.openVoiceOptions()).id('player-voice')
          .bindPopup(this.showSourceVoice, this.sourceVoiceMenuOptions())

      }
      if (this.book?.sourceUrl && !this.isSpeechBook()) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_left_arrow_right')).fontSize(24).fontColor(['#FFFFFF'])
        }
          .width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.source_switch_title'))
          .onClick((): void => { this.showSourceSwitch = true; })
          .margin({ right: 8 })
          .enabled(!this.reloadingChapter && !this.playerState.isLoading)
          .bindSheet($$this.showSourceSwitch, this.buildSourceSwitchSheet(), {
            height: '82%', detents: ['82%', '45%', SheetSize.LARGE], dragBar: true, preferType: SheetType.BOTTOM, showClose: true,
            backgroundColor: AppMaterial.SheetBackground,
            blurStyle: AppMaterial.ReaderSheetBlur, systemMaterial: AppMaterial.ReaderSheetThick
          })
      }
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.info_circle')).fontSize(24).fontColor(['#FFFFFF'])
      }
        .width(40).height(40).backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.reader_details'))
        .onClick((): void => { this.openBookDetail(); })
    }
    .width('100%')
    .height(48)
  }

  @Builder
  buildSpeechBookHeader() {
    Row({ space: AppSpace.Lg }) {
      PlayerCoverImage({ title: this.book!.title, url: this.book!.cover,
        author: this.book!.author, localPlaceholder: this.book!.id.startsWith('import_'),
        fallback: this.book!.coverFallback ?? '', highQuality: this.highQualityCover })
        .width(this.isCompactPlayer() ? 88 : 104).aspectRatio(1).borderRadius(12).clip(true)
        .id('player-page-cover').opacity(this.dragState.active ? 0 : 1)
      Column({ space: AppSpace.Sm }) {
        Text(this.sourceName).fontSize(AppFont.Caption).fontColor('#CCFFFFFF')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.book!.title).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.book!.author).fontSize(AppFont.Body).fontColor('#CCFFFFFF')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(VerticalAlign.Center)
      .margin({ top: this.isCompactPlayer() ? AppSpace.Xs : AppSpace.Lg })
  }

  @Builder
  buildCover() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        PlayerCoverImage({
          author: this.book!.author, localPlaceholder: this.book!.id.startsWith('import_'),
          title: this.book!.title, url: this.book!.cover, fallback: this.book!.coverFallback ?? '',
          highQuality: this.highQualityCover
        })
        if (this.sourceName !== '') {
          Text(this.sourceName)
            .fontSize(AppFont.Caption)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '70%' })
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor('#99000000')
            .borderRadius(6)
            .margin(12)
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width(this.isSpeechBook() ? 112 : this.isLandscapePlayer() ? this.landscapeCoverSize()
        : this.isCompactPlayer() ? this.compactCoverSize() : '100%')
      .aspectRatio(1)
      .borderRadius(16)
      .clip(true)
      .geometryTransition('player-cover')
      .id('player-page-cover')
      .opacity(this.dragState.active ? 0 : 1)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: this.isLandscapePlayer() ? 0 : this.isCompactPlayer() ? AppSpace.Xs : AppSpace.Lg })
  }

  @Monitor('speechState.chapterIndex', 'speechState.charOffset', 'speechState.contentLength')
  private syncSpeechParagraphs(): void {
    if (!this.speechMatchesBook()) return;
    const key = `${this.speechState.bookId}:${this.speechState.chapterIndex}:${this.speechState.contentLength}`;
    const chapterChanged = key !== this.speechChapterKey;
    if (chapterChanged) {
      const content = LocalTextImage.speechContent(TextToSpeechService.getInstance().currentChapterContent());
      const paragraphs: string[] = [];
      const offsets: number[] = [];
      let offset = 0;
      for (const line of content.split('\n')) {
        if (line.trim().length > 0) { paragraphs.push(line); offsets.push(offset); }
        offset += line.length + 1;
      }
      this.speechChapterKey = key;
      this.speechParagraphOffsets = offsets;
      this.speechParagraphs = paragraphs;
    }
    let index = 0;
    for (let next = 0; next < this.speechParagraphOffsets.length; next++) {
      if (this.speechParagraphOffsets[next] > this.speechState.charOffset) break;
      index = next;
    }
    if (chapterChanged || this.speechParagraphIndex !== index) {
      this.speechParagraphIndex = index;
      this.positionSpeechParagraph(!chapterChanged);
    }
  }

  private positionSpeechParagraph(animated: boolean): void {
    if (!this.speechListReady || this.speechPositionQueued || this.speechParagraphs.length === 0) return;
    this.speechPositionQueued = true;
    const generation = this.speechPositionGeneration;
    this.getUIContext().postFrameCallback(new PlayerLayoutReadyFrame((): void => {
      if (generation !== this.speechPositionGeneration) return;
      this.speechPositionQueued = false;
      if (this.isLeaving || !this.speechListReady || !this.speechMatchesBook()) return;
      try {
        this.speechScroller.scrollToIndex(this.speechParagraphIndex,
          animated && this.speechPositionedChapter === this.speechChapterKey, ScrollAlign.CENTER);
        this.speechPositionedChapter = this.speechChapterKey;
      } catch (_error) { /* 列表卸载时不继续定位。 */ }
    }));
  }

  @Builder
  buildSpeechParagraphs(fillAvailable: boolean = false) {
    Stack() {
    List({ scroller: this.speechScroller, initialIndex: this.speechParagraphIndex }) {
      Repeat<string>(this.speechParagraphs).each((item: RepeatItem<string>) => {
        ListItem() {
          Text(item.item).fontSize(16).lineHeight(26).width('100%').padding({ top: 8, bottom: 8 })
            .fontColor(item.index === this.speechParagraphIndex ? '#FFFFFF' : '#99FFFFFF')
            .fontWeight(item.index === this.speechParagraphIndex ? FontWeight.Medium : FontWeight.Normal)
        }
      }).key((_paragraph: string, index: number): string => `${this.speechChapterKey}:${this.speechParagraphOffsets[index]}`).virtualScroll()
    }.width('100%').height('100%').scrollBar(BarState.Off).cachedCount(2)
      .onAppear((): void => {
        this.speechListReady = true;
        this.syncSpeechParagraphs();
        this.positionSpeechParagraph(false);
      })
      .onDisAppear((): void => {
        this.speechListReady = false;
        this.speechPositionQueued = false;
        this.speechPositionGeneration++;
        this.speechPositionedChapter = '';
      })
      // 透明蒙版只作用于正文离屏层，露出原来的封面背景，不遮挡触摸。
      Column().width('100%').height('100%')
        .linearGradient({ direction: GradientDirection.Bottom,
          colors: [['#00FFFFFF', 0], ['#FFFFFFFF', 0.08], ['#FFFFFFFF', 0.92], ['#00FFFFFF', 1]] })
        .blendMode(BlendMode.DST_IN)
        .hitTestBehavior(HitTestMode.None)
    }.width('100%').height(220).layoutWeight(fillAvailable ? 1 : 0)
      .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
  }

  @Builder
  buildMeta() {
    Column({ space: 4 }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.playbackChapter()?.title ?? this.book!.title)
            .fontSize(20)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (!this.isSpeechBook()) {
          Text(this.book!.author)
            .fontSize(AppFont.Body)
            .fontColor('#FFFFFF')
            .maxLines(1)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph(this.isFavorite
          ? $r('sys.symbol.bookshelf_badge_checkmark_fill')
          : $r('sys.symbol.bookshelf'))
          .fontSize(24)
          .fontColor([this.isFavorite ? AppColor.Brand : '#FFFFFF'])
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
          .onClick(() => this.toggleFavorite())
      }
      .width('100%')
      if (this.isSpeechBook() && this.speechMatchesBook() && this.speechState.error) {
        Text(this.speechState.error).fontSize(AppFont.Caption).fontColor('#FFFFFF')
          .width('100%').margin({ top: AppSpace.Xs })
      }
    }
    .width('100%')
    .padding({ top: this.isLandscapePlayer() ? 0 : this.isCompactPlayer() ? AppSpace.Md : AppSpace.Xl })
  }

  @Builder
  buildProgress() {
    Column({ space: AppSpace.Xxs }) {
      if (this.isSpeechBook()) {
        Progress({ value: this.speechProgress(), total: 100, type: ProgressType.Linear })
          .color('#FFFFFF').backgroundColor('#33FFFFFF').width('100%')
        Row() {
          Text($r('app.string.tts_chapter_progress')).fontSize(AppFont.Caption).fontColor('#FFFFFF')
          Blank()
          Text(`${Math.floor(this.speechProgress())}%`).fontSize(AppFont.Caption).fontColor('#FFFFFF')
        }.width('100%').margin({ top: AppSpace.Xs })
      } else if (this.isLiveBook()) {
        Text($r('app.string.player_live')).fontSize(AppFont.Body).fontColor('#FFFFFF').height(48)
      } else {
      Slider({
        value: this.progressValueMs(),
        min: 0,
        max: this.sliderMaxMs(),
        step: 1000,
        style: SliderStyle.OutSet
      })
        .selectedColor('#FFFFFF')
        .trackColor('#33FFFFFF')
        .blockColor('#FFFFFF')
        .blockSize({ width: 18, height: 18 })
        .trackThickness(6)
        .enabled(this.playerState.durationMs > 0 && !this.playerState.isLoading)
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            this.seeking = true;
            this.seekValueMs = value;
          } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.seekValueMs = value;
            AudioService.getInstance().seek(value);
            setTimeout(() => { this.seeking = false; }, 200);
          }
        })

      Row() {
        Text(this.formatMs(this.progressValueMs()))
          .fontSize(AppFont.Caption)
          .fontColor('#FFFFFF')
        Blank()
        Text(this.formatMs(this.displayDurationMs()))
          .fontSize(AppFont.Caption)
          .fontColor('#FFFFFF')
      }
      .width('100%')
      .padding({ left: 9, right: 9 })
      .margin({ top: -3 })
      }
    }
    .width('100%')
    .padding({ bottom: this.isCompactPlayer() ? AppSpace.Sm : AppSpace.Md })
  }

  @Builder
  buildControls() {
    Row() {
      Stack({ alignContent: Alignment.Start }) {
        SymbolGlyph(this.isSpeechBook() ? $r('sys.symbol.backward_fill') : $r('sys.symbol.gobackward_15'))
          .fontSize(20)
          .fontColor(['#B3B3B3'])
      }
      .width(44)
      .height(44)
      .enabled(this.canSkipPlayback())
      .opacity(this.isLiveBook() ? 0.4 : 1)
      .accessibilityText(this.isSpeechBook() ? $r('app.string.tts_previous_segment') : $r('app.string.player_rewind_15'))
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
      .onClick((): void => this.skipPlayback(-1))

      Blank()

      SymbolGlyph($r('sys.symbol.backward_end_fill'))
        .fontSize(this.isCompactPlayer() ? 32 : 36)
        .fontColor(['#FFFFFF'])
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
        .onClick(() => this.playPrev())

      Blank()

      Stack({ alignContent: Alignment.Center }) {
        if (this.playbackLoading()) {
          PlaybackLoadingIndicator({ indicatorSize: 36 })
        } else {
          SymbolGlyph(this.playbackPlaying()
            ? $r('sys.symbol.pause_round_triangle_fill') : $r('sys.symbol.play_round_triangle_fill'))
            .fontSize(this.isCompactPlayer() ? 56 : 64)
            .fontWeight(this.playbackPlaying() ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(['#FFFFFF'])
            .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), this.playbackPlaying() ? 1 : 0)
        }
      }
      .width(this.isCompactPlayer() ? 56 : 64)
      .height(this.isCompactPlayer() ? 56 : 64)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .id('player-play-toggle')
      .accessibilityText(this.playbackPlaying() || this.playbackLoading()
        ? $r('app.string.tts_pause') : $r('app.string.tts_play'))
      .onClick(() => {
        if (this.isSpeechBook() || !this.playerState.isLoading) this.togglePlay();
      })

      Blank()

      SymbolGlyph($r('sys.symbol.forward_end_fill'))
        .fontSize(this.isCompactPlayer() ? 32 : 36)
        .fontColor(['#FFFFFF'])
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
        .onClick(() => this.playNext())

      Blank()

      Stack({ alignContent: Alignment.End }) {
        SymbolGlyph(this.isSpeechBook() ? $r('sys.symbol.backward_fill') : $r('sys.symbol.goforward_15'))
          .fontSize(20)
          .fontColor(['#B3B3B3'])
          .rotate({ angle: this.isSpeechBook() ? 180 : 0 })
      }
      .width(44)
      .height(44)
      .enabled(this.canSkipPlayback())
      .opacity(this.isLiveBook() ? 0.4 : 1)
      .accessibilityText(this.isSpeechBook() ? $r('app.string.tts_next_segment') : $r('app.string.player_forward_15'))
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
      .onClick((): void => this.skipPlayback(1))
    }
    .width('calc(100% - 18vp)')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)

  }

  @Builder
  buildBottomBar() {
    Row() {
      Column() {
        Text(this.fmtSpeed(this.isLiveBook() ? 1 : this.playbackSpeed()) + 'x')
          .fontSize(AppFont.Body + 1)
          .height(26)
          .fontColor(this.playbackSpeed() !== 1.0 ? AppColor.Brand : '#B3B3B3')
          .fontWeight(FontWeight.Medium)
      }
      .width(56)
      .alignItems(HorizontalAlign.Start)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.isLiveBook()) return;
        this.speedValue = this.playbackSpeed();
        this.showSpeedSheet = true;
      })
      .bindSheet($$this.showSpeedSheet, this.buildSpeedSheet(), {
        height: '55%',
        detents: ['55%', '45%', SheetSize.LARGE], preferType: SheetType.BOTTOM,
        showClose: false,
        dragBar: true,
        backgroundColor: AppMaterial.SheetBackground,
        blurStyle: AppMaterial.PlayerSheetBlur,
        systemMaterial: AppMaterial.PlayerSheet,
        onDisappear: () => { this.showSpeedSheet = false; }
      })
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction(() => this.resetSpeed())
      )

      Blank()

      Stack({ alignContent: Alignment.TopStart }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.alarm'))
            .fontSize(20)
            .fontColor([this.sleepActive() ? AppColor.Brand : '#B3B3B3'])
        }
        .width(20).height(20)
        // Path 的路径坐标使用 px；须与 20vp 图标按同一屏幕密度换算。
        .clip(new Path().commands(this.sleepAlarmClipPath()))
        .position({ x: 18, y: 12 })
        .hitTestBehavior(HitTestMode.None)
        if (this.sleepActive()) {
          Text(this.sleepBadgeLabel())
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.Brand)
            .maxLines(1)
            .constraintSize({ maxWidth: 48 })
            .height(14)
            .position({ x: 29, y: 6 })
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width(56)
      .height(44)
      .accessibilityText(this.sleepLabel())
      .onClick(() => this.openSleepSheet())
      .bindSheet($$this.showSleepSheet, this.buildPlaybackSleepSheet(), {
        height: SheetSize.FIT_CONTENT,
        detents: [SheetSize.FIT_CONTENT, '45%', SheetSize.LARGE], preferType: SheetType.BOTTOM,
        showClose: false,
        dragBar: true,
        backgroundColor: AppMaterial.SheetBackground,
        blurStyle: AppMaterial.PlayerSheetBlur,
        systemMaterial: AppMaterial.PlayerSheet,
        onWillDisappear: (): void => { this.sleepSheetDismissUntil = Date.now() + 400; },
        onWillDismiss: (action: DismissSheetAction): void => {
          this.sleepSheetDismissUntil = Date.now() + 400;
          this.showSleepSheet = false;
          action.dismiss();
        }
      })
      .gesture(LongPressGesture().onAction(() => {
        if (this.sleepActive()) {
          this.hapticTick();
          this.setSleep(0);
        }
      }))

      Blank()

      if (this.isSpeechBook()) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(22).fontColor(['#B3B3B3'])
        }.width(56).height(44).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.tts_stop')).id('tts-stop')
          .onClick((): void => {
            this.closeSpeechToReader();
          })
      } else {
      Column() {
        Stack({ alignContent: Alignment.End }) {
          SymbolGlyph($r('sys.symbol.chevron_left_2'))
            .fontSize(25)
            .rotate({ angle: 180 })
            .fontColor([this.hasSkipConfig() ? AppColor.Brand : '#B3B3B3'])
        }
        .width(26)
        .height(26)
      }
      .width(56)
      .alignItems(HorizontalAlign.Center)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.skipIntroValue = this.book?.skipIntro ?? 0;
        this.skipOutroValue = this.book?.skipOutro ?? 0;
        this.showSkipSheet = true;
      })
      .bindSheet($$this.showSkipSheet, this.buildSkipSheet(), {
        height: '55%',
        detents: ['55%', '45%', SheetSize.LARGE], preferType: SheetType.BOTTOM,
        showClose: false,
        dragBar: true,
        backgroundColor: AppMaterial.SheetBackground,
        blurStyle: AppMaterial.PlayerSheetBlur,
        systemMaterial: AppMaterial.PlayerSheet,
        onDisappear: () => { this.showSkipSheet = false; }
      })
      .gesture(LongPressGesture().onAction(() => {
        if (this.hasSkipConfig()) {
          this.hapticTick();
          this.persistSkip(0, 0);
          this.skipIntroValue = 0;
          this.skipOutroValue = 0;
        }
      }))
      }

      Blank()

      Stack({ alignContent: Alignment.End }) {
        SymbolGlyph($r('sys.symbol.music_note_list'))
          .fontSize(21)
          .fontColor(['#B3B3B3'])
      }
      .width(44)
      .height(44)
      .accessibilityText($r('app.string.reader_chapters'))
      .onClick(() => this.openChapterList())
      .bindSheet($$this.showChapterList, this.buildChapterSheet(), {
        height: '80%',
        detents: ['80%', '45%', SheetSize.LARGE], preferType: SheetType.BOTTOM,
        showClose: false,
        dragBar: true,
        backgroundColor: AppMaterial.SheetBackground,
        blurStyle: AppMaterial.PlayerSheetBlur,
        systemMaterial: AppMaterial.PlayerSheet,
        onAppear: () => {
          if (!this.chapterListInteracted) this.scrollToCurrentChapter();
        },
        onDisappear: () => {
          this.cancelChapterPosition();
          this.showChapterList = false;
        }
      })

    }
    .width('calc(100% - 18vp)')
    .padding({ top: this.isLandscapePlayer() ? AppSpace.Md : AppSpace.Lg })
  }

  @Builder
  buildChapterSheet() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: AppSpace.Xs }) {
      Row() {
        Text(this.book?.title ?? '')
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Button($r('app.string.chapter_total_switch', this.book?.chapters.length ?? 0))
          .fontSize(AppFont.Caption).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.interruptChapterPosition();
            this.chapterGridVisible = !this.chapterGridVisible;
            if (!this.chapterGridVisible) this.applyChapterFilter(this.chapterSearchKeyword);
          })
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([$r('sys.color.font_secondary')])
          .onClick(() => { this.showChapterList = false; })
      }
      .width('100%')
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Xs })

      ChapterSheetActions({
        descending: this.chapterDescending,
        onOrder: (): void => this.toggleChapterOrder(),
        onTop: (): void => {
          this.chapterTopRequest++;
          this.interruptChapterPosition();
          this.scrollChapterListToIndex(0, ScrollAlign.START);
        },
        onBottom: (): void => {
          this.chapterBottomRequest++;
          this.interruptChapterPosition();
          this.scrollChapterListToIndex(this.chapterDataSource.totalCount() - 1, ScrollAlign.END);
        }
      })

      // 章节搜索框（原生 Search,与首页一致）
      Search({ value: this.chapterSearchKeyword!!, placeholder: '搜索章节' })
        .onChange((value: string) => this.applyChapterFilter(value))
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .searchIcon({ size: 18, color: $r('sys.color.font_secondary') })
        .height(40)
        .borderRadius(AppRadius.Lg)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .margin({ left: AppSpace.Lg, right: AppSpace.Lg, top: 0, bottom: 0 })

      if (this.chapterGridVisible) {
        ChapterSegmentGrid({
          book: this.book, topRequest: this.chapterTopRequest, bottomRequest: this.chapterBottomRequest,
          chapters: this.book?.chapters ?? [], currentId: this.playbackChapter()?.id ?? '',
          keyword: this.chapterSearchKeyword, descending: this.chapterDescending,
          onSelect: (chapter: Chapter): void => { this.selectChapter(chapter); },
          onLongPress: (chapter: Chapter): void => this.handleChapterDownloadLongPress(chapter)
        }).layoutWeight(1)
      } else {
        this.buildChapterItems()
      }
      }
      .width('100%')
      .height('100%')

      // "回到当前章节"浮动按钮:列表滚远时显示
      if (!this.chapterGridVisible && this.shouldShowJumpButton()) {
        Row({ space: AppSpace.Xs }) {
          SymbolGlyph($r('sys.symbol.scope'))
            .fontSize(16)
            .fontColor(['#FFFFFF'])
          Text('回到当前章节')
            .fontSize(AppFont.Caption)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius(22)
        .backgroundColor(AppColor.Brand)
        .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
        .margin({ right: AppSpace.Lg, bottom: AppSpace.Lg })
        .onClick(() => this.jumpToCurrentChapter())
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.8, y: 0.8 }))
          .animation({ curve: curves.springMotion(0.4, 0.9) }))
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildChapterItems() {
    List({ space: 0, scroller: this.chapterListScroller }) {
      LazyForEach(this.chapterDataSource, (ch: Chapter) => {
        ListItem() {
          Row() {
            Column({ space: 2 }) {
              Text(ch.title)
                .fontSize(AppFont.BodyL)
                .fontColor(this.isCurrentChapter(ch) ? AppColor.Brand : $r('sys.color.font_primary'))
                .fontWeight(this.isCurrentChapter(ch) ? FontWeight.Medium : FontWeight.Normal)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.isCurrentChapter(ch)) {
              if (this.playbackLoading()) {
                LoadingProgress()
                  .width(18).height(18).color(AppColor.Brand)
              } else {
                SymbolGlyph($r('sys.symbol.speaker_wave_2_fill'))
                  .fontSize(18)
                  .fontColor([AppColor.Brand])
              }
            }
            if (!this.isSpeechBook()) {
              this.buildChapterDownloadIndicator(ch)
            }
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.selectChapter(ch))
          .gesture(
            LongPressGesture({ repeat: false, duration: 500 })
              .onAction(() => this.handleChapterDownloadLongPress(ch))
          )
        }
      }, (ch: Chapter) => DownloadPolicy.stablePageUrl(ch) || ch.id)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.On)
    .scrollBarWidth(8)
    .scrollBarMargin({ start: LengthMetrics.vp(8), end: LengthMetrics.vp(56) })
    .enableScrollInteraction(true)
    .cachedCount(5)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) this.interruptChapterPosition();
    })
    .onWillScroll((_offset: number, _state: ScrollState, source: ScrollSource): void => {
      if (source === ScrollSource.DRAG || source === ScrollSource.FLING
        || source === ScrollSource.OTHER_USER_INPUT || source === ScrollSource.SCROLL_BAR
        || source === ScrollSource.SCROLL_BAR_FLING) {
        this.interruptChapterPosition();
      }
    })
    .onScrollIndex((firstIndex: number, lastIndex: number) => {
      // 用首尾可见 index 与当前章节 index 计算偏离
      // 行高约 64vp(BodyL+Caption+padding),用 (center - idx) * 64 估算
      const idx = this.currentChapterIndex();
      if (idx < 0) return;
      const center = (firstIndex + lastIndex) / 2;
      this.listOffsetFromCurrent = (center - (this.book ? PreferenceService.chapterDisplayIndex(this.book, idx) : idx)) * 64;
    })
  }

  @Builder
  buildSleepModeTab(mode: SleepMode) {
    Button(mode === SleepMode.Duration ? $r('app.string.player_sleep_by_time') : $r('app.string.player_sleep_by_chapter'))
      .type(ButtonType.Normal)
      .layoutWeight(1)
      .height(40)
      .fontSize(AppFont.Body)
      .fontWeight(this.sleepSheetMode === mode ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.sleepSheetMode === mode ? AppColor.Brand : $r('sys.color.font_secondary'))
      .backgroundColor(this.sleepSheetMode === mode ? AppColor.BrandSoft : Color.Transparent)
      .borderRadius(AppRadius.Sm)
      .onClick(() => this.selectSleepMode(mode))
  }

  @Builder
  private buildSpeechTimerButton(label: ResourceStr, minutes: number, chapterEnd: boolean = false): void {
    Button(label).fontSize(AppFont.Caption).fontColor(AppColor.Brand)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .onClick((): void => {
        TextToSpeechService.getInstance().setSleep(minutes, chapterEnd);
        this.showSleepSheet = false;
      })
  }

  @Builder
  private buildPlaybackSleepSheet(): void {
    if (this.isSpeechBook()) {
      Column({ space: AppSpace.Lg }) {
        Text($r('app.string.tts_sleep')).fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary')).width('100%')
        Row({ space: AppSpace.Xs }) {
          this.buildSpeechTimerButton($r('app.string.tts_sleep_off'), 0)
          this.buildSpeechTimerButton($r('app.string.tts_sleep_15'), 15)
          this.buildSpeechTimerButton($r('app.string.tts_sleep_30'), 30)
          this.buildSpeechTimerButton($r('app.string.tts_sleep_60'), 60)
        }.width('100%').justifyContent(FlexAlign.SpaceBetween)
        this.buildSpeechTimerButton($r('app.string.tts_sleep_chapter'), 0, true)
        if (this.speechState.remainingSeconds > 0) {
          Text($r('app.string.tts_sleep_remaining', Math.ceil(this.speechState.remainingSeconds / 60)))
            .fontColor(AppColor.Brand).fontSize(AppFont.Body)
        } else if (this.speechState.stopAtChapterEnd) {
          Text($r('app.string.tts_sleep_chapter_active')).fontColor(AppColor.Brand).fontSize(AppFont.Body)
        }
      }.width('100%').padding(AppSpace.Lg).alignItems(HorizontalAlign.Start)
    } else {
      this.buildSleepSheet()
    }
  }

  @Builder
  buildSleepOption(value: number) {
    Button(this.sleepOptionLabel(value))
      .type(ButtonType.Normal)
      .layoutWeight(1)
      .height(48)
      .fontSize(AppFont.BodyL)
      .fontColor(this.sleepOptionSelected(value) ? AppColor.Brand : $r('sys.color.font_primary'))
      .backgroundColor(this.sleepOptionSelected(value) ? AppColor.BrandSoft : $r('sys.color.comp_background_tertiary'))
      .border({ width: this.sleepOptionSelected(value) ? 1 : 0, color: AppColor.Brand })
      .borderRadius(AppRadius.Md)
      .enabled(value === 0 || this.sleepSheetMode === SleepMode.Duration || value <= this.sleepChapterLimit())
      .onClick(() => this.selectSleepOption(value))
  }

  @Builder
  buildSleepSheet() {
    Column({ space: AppSpace.Md }) {
      Row() {
        Text($r('app.string.player_sleep_title'))
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
        Blank()
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.player_sleep_close'))
        .onClick(() => { this.showSleepSheet = false; })
      }
      .width('100%')

      Row({ space: AppSpace.Md }) {
        Column({ space: 4 }) {
          Text($r('app.string.player_auto_sleep'))
            .fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
          Text(this.playerState.lastSleepMode === SleepMode.Chapters ?
            $r('app.string.player_auto_sleep_chapters_hint', this.playerState.lastSleepChapters) :
            $r('app.string.player_auto_sleep_hint', this.playerState.lastSleepMinutes))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.playerState.autoSleepEnabled })
          .selectedColor(AppColor.Brand)
          .onChange((enabled: boolean): void => {
            AudioService.getInstance().setAutoSleepEnabled(enabled).catch((): void => {
              this.showToast($r('app.string.player_auto_sleep_save_failed'));
            });
          })
      }.width('100%')

      Row({ space: AppSpace.Xs }) {
        this.buildSleepModeTab(SleepMode.Duration)
        this.buildSleepModeTab(SleepMode.Chapters)
      }
      .padding(AppSpace.Xs)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .borderRadius(AppRadius.Md)
      .width('100%')

      if (this.sleepSheetMode === SleepMode.Duration) {
        Row({ space: AppSpace.Sm }) {
          this.buildSleepOption(15)
          this.buildSleepOption(30)
        }
        .width('100%')
        Row({ space: AppSpace.Sm }) {
          this.buildSleepOption(45)
          this.buildSleepOption(60)
        }
        .width('100%')
        Row() {
          this.buildSleepOption(0)
        }
        .width('100%')
      } else {
        Row({ space: AppSpace.Sm }) {
          this.buildSleepOption(1)
          this.buildSleepOption(3)
        }
        .width('100%')
        Row({ space: AppSpace.Sm }) {
          this.buildSleepOption(5)
          this.buildSleepOption(7)
        }
        .width('100%')
        Row() {
          this.buildSleepOption(0)
        }
        .width('100%')
      }

      if (this.sleepCustomVisible) {
        Row({ space: AppSpace.Sm }) {
          TextInput({ text: this.sleepCustomValue, placeholder: this.sleepSheetMode === SleepMode.Duration
            ? $r('app.string.player_sleep_minutes_placeholder')
            : $r('app.string.player_sleep_chapters_placeholder', this.sleepChapterLimit()) })
            .type(InputType.Number)
            .enterKeyType(EnterKeyType.Done)
            .maxLength(4)
            .height(48)
            .layoutWeight(1)
            .caretColor(AppColor.Brand)
            .onChange((value: string) => {
              this.sleepCustomValue = value;
              this.sleepInputError = '';
            })
            .onSubmit(() => this.submitCustomSleep())
          Text(this.sleepSheetMode === SleepMode.Duration
            ? $r('app.string.player_sleep_minute_unit') : $r('app.string.player_sleep_chapter_unit'))
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        Text($r('app.string.player_sleep_custom_hint'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      }
      if (this.sleepInputError !== '') {
        Text(this.sleepInputError)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.warning'))
          .width('100%')
      }

      if (this.sleepSheetMode === SleepMode.Duration) {
        Row({ space: AppSpace.Sm }) {
          Column({ space: 4 }) {
            Text($r('app.string.player_sleep_smart'))
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
            Text($r('app.string.player_sleep_smart_hint'))
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.sleepSmartStopDraft })
            .selectedColor(AppColor.Brand)
            .onChange((enabled: boolean) => {
              this.sleepSmartStopDraft = enabled;
              AudioService.getInstance().setSleepSmartStop(enabled);
            })
        }
        .width('100%')
      } else {
        Text($r('app.string.player_sleep_chapter_hint'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      }

      if (this.playerState.sleepMode === SleepMode.Chapters && this.sleepSheetMode === SleepMode.Chapters) {
        Text($r('app.string.player_sleep_target', this.playerState.sleepTargetTitle))
          .fontSize(AppFont.Caption)
          .fontColor(AppColor.Brand)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      } else if (this.playerState.sleepWaitingForChapter && this.sleepSheetMode === SleepMode.Duration) {
        Text($r('app.string.player_sleep_waiting'))
          .fontSize(AppFont.Caption)
          .fontColor(AppColor.Brand)
          .width('100%')
      }
      if (this.sleepActive()) {
        Button($r('app.string.player_sleep_cancel'))
          .height(44)
          .width('100%')
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.warning'))
          .backgroundColor(Color.Transparent)
          .onClick(() => this.setSleep(0))
      }
    }
    .width('100%')
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Sm, bottom: AppSpace.Lg })
  }

  @Builder
  buildAdjustmentButton(action: string) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(action.endsWith('Down') ? $r('sys.symbol.minus') : $r('sys.symbol.plus'))
        .fontSize(20)
        .fontColor([AppColor.Brand])
    }
    .width(44)
    .height(44)
    .backgroundColor(AppColor.BrandSoft)
    .enabled(this.adjustmentEnabled(action))
    .opacity(this.adjustmentEnabled(action) ? 1 : 0.4)
    .accessibilityText(this.adjustmentLabel(action))
    .onClick(() => this.adjustValue(action))
  }

  private adjustmentEnabled(action: string): boolean {
    const current = action.startsWith('speed') ? this.speedValue
      : action.startsWith('intro') ? this.skipIntroValue : this.skipOutroValue;
    const min = action.startsWith('speed') ? 0.5 : 0;
    const max = action.startsWith('speed') ? (3) : 120;
    return action.endsWith('Down') ? current > min : current < max;
  }

  private adjustmentLabel(action: string): Resource {
    if (action.startsWith('speed')) {
      return action.endsWith('Down') ? $r('app.string.player_speed_decrease') : $r('app.string.player_speed_increase');
    }
    if (action.startsWith('intro')) {
      return action.endsWith('Down') ? $r('app.string.player_intro_decrease') : $r('app.string.player_intro_increase');
    }
    return action.endsWith('Down') ? $r('app.string.player_outro_decrease') : $r('app.string.player_outro_increase');
  }

  private adjustValue(action: string): void {
    const delta = action.endsWith('Down') ? -1 : 1;
    if (action.startsWith('speed')) {
      this.speedValue = Math.min(3, Math.max(0.5, Math.round(this.speedValue * 20 + delta) / 20));
      this.setPlaybackSpeed(this.speedValue);
      return;
    }
    if (action.startsWith('intro')) {
      this.skipIntroValue = Math.min(120, Math.max(0, this.skipIntroValue + delta));
    } else {
      this.skipOutroValue = Math.min(120, Math.max(0, this.skipOutroValue + delta));
    }
    this.persistSkip(this.skipIntroValue, this.skipOutroValue);
  }

  @Builder
  buildSkipSheet() {
    Scroll() {
      Column({ space: AppSpace.Lg }) {
        Row() {
          Text($r('app.string.player_skip_title'))
            .fontSize(AppFont.Title)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Bold)
          Blank()
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .width(44)
          .height(44)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.showSkipSheet = false; })
        }
        .width('100%')
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg })

        Column({ space: AppSpace.Xs }) {
          Row() {
            Text($r('app.string.player_skip_intro'))
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Text($r('app.string.player_skip_seconds', this.skipIntroValue))
              .fontSize(AppFont.BodyL)
              .fontColor(AppColor.Brand)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row({ space: AppSpace.Sm }) {
            this.buildAdjustmentButton('introDown')
            Slider({ value: this.skipIntroValue, min: 0, max: 120, step: 1 })
              .blockColor(AppColor.Brand)
              .trackColor($r('sys.color.comp_divider'))
              .selectedColor(AppColor.Brand)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.skipIntroValue = Math.round(value);
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.persistSkip(this.skipIntroValue, this.skipOutroValue);
                }
              })
              .layoutWeight(1)
            this.buildAdjustmentButton('introUp')
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
        }
        .width('100%')
        .padding({ top: AppSpace.Sm })

        Column({ space: AppSpace.Xs }) {
          Row() {
            Text($r('app.string.player_skip_outro'))
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Text($r('app.string.player_skip_seconds', this.skipOutroValue))
              .fontSize(AppFont.BodyL)
              .fontColor(AppColor.Brand)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row({ space: AppSpace.Sm }) {
            this.buildAdjustmentButton('outroDown')
            Slider({ value: this.skipOutroValue, min: 0, max: 120, step: 1 })
              .blockColor(AppColor.Brand)
              .trackColor($r('sys.color.comp_divider'))
              .selectedColor(AppColor.Brand)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.skipOutroValue = Math.round(value);
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.persistSkip(this.skipIntroValue, this.skipOutroValue);
                }
              })
              .layoutWeight(1)
            this.buildAdjustmentButton('outroUp')
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
        }
        .width('100%')
        .padding({ top: AppSpace.Sm })
      }
      .width('100%')
      .padding({ top: AppSpace.Xs, bottom: AppSpace.Xl })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
  }

  @Builder
  buildSpeedSheet() {
    Scroll() {
      Column({ space: AppSpace.Lg }) {
        Row() {
          Text($r('app.string.player_speed_title'))
            .fontSize(AppFont.Title)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Bold)
          Blank()
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .width(44)
          .height(44)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.showSpeedSheet = false; })
        }
        .width('100%')
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg })

        Column({ space: AppSpace.Xs }) {
          Row() {
            Text($r('app.string.player_speed'))
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Text(this.fmtSpeed(this.speedValue) + 'x')
              .fontSize(AppFont.TitleL)
              .fontColor(AppColor.Brand)
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row({ space: AppSpace.Sm }) {
            this.buildAdjustmentButton('speedDown')
            Slider({ value: this.speedValue, min: 0.5, max: 3, step: 0.05 })
              .blockColor(AppColor.Brand)
              .trackColor($r('sys.color.comp_divider'))
              .selectedColor(AppColor.Brand)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.speedValue = Math.round(value * 20) / 20;
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.setPlaybackSpeed(this.speedValue);
                }
              })
              .layoutWeight(1)
            this.buildAdjustmentButton('speedUp')
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
          .margin({ top: AppSpace.Md })

          Row() {
            Text('0.5x')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
            Blank()
             Text($r('app.string.player_speed_max'))
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
        }
        .width('100%')
        .padding({ top: AppSpace.Sm })
      }
      .width('100%')
      .padding({ top: AppSpace.Xs, bottom: AppSpace.Xl })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
  }

  private hasSkipConfig(): boolean {
    if (!this.book) return false;
    return (this.book.skipIntro ?? 0) > 0 || (this.book.skipOutro ?? 0) > 0;
  }

  /** 原子写片头+片尾:一次 saveSkipConfig,避免长按清空时两次异步各写各的留半状态 */
  private async persistSkip(intro: number, outro: number): Promise<void> {
    if (!this.book) return;
    const b = this.book;
    const cloned: Book = {
      id: b.id, title: b.title, author: b.author, narrator: b.narrator,
      cover: b.cover,
      coverFromDetail: b.coverFromDetail,
      coverFallback: b.coverFallback, category: b.category, intro: b.intro,
      wordCount: b.wordCount, latestChapterTitle: b.latestChapterTitle, updateTime: b.updateTime,
      totalDuration: b.totalDuration, chapterCount: b.chapterCount,
      rating: b.rating, tags: b.tags, chapters: b.chapters,
      bookUrl: b.bookUrl, sourceUrl: b.sourceUrl,
      contentType: b.contentType, completed: b.completed, chaptersDescending: b.chaptersDescending,
      variables: b.variables, skipIntro: intro, skipOutro: outro
    };
    this.book = cloned;
    AudioService.getInstance().applySkipConfigNow(cloned.id, intro, outro);
    // 独立 KV 落盘(权威来源):冷启动恢复不依赖缓存书索引,避免走 legacy/persistUnsafe 兜底时丢 skip
    await PreferenceService.saveSkipConfig(cloned.id, intro, outro);
    await DataService.upsertCachedBook(cloned);
    SearchCache.put(cloned);

  }

  @Builder
  buildChapterDownloadIndicator(ch: Chapter) {
    if (this.chapterDownloadRecord(ch)?.status === 'completed' ||
      (this.chapterCacheTick >= 0 && this.book !== null &&
        ChapterCacheService.getInstance().isAudioChapterCached(this.book, ch))) {
      SymbolGlyph($r('sys.symbol.checkmark_circle'))
        .fontSize(16)
        .fontColor([AppColor.Brand])
    } else if (this.chapterDownloadRecord(ch)?.status === 'pending'
      || this.chapterDownloadRecord(ch)?.status === 'resolving'
      || this.chapterDownloadRecord(ch)?.status === 'downloading') {
      LoadingProgress()
        .width(16)
        .height(16)
        .color(AppColor.Brand)
    } else if (this.chapterDownloadRecord(ch)?.status === 'failed') {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(16)
        .fontColor(['#D03050'])
    } else {
      SymbolGlyph($r('sys.symbol.cloud'))
        .fontSize(16)
        .fontColor([$r('sys.color.font_tertiary')])
    }
  }
}
