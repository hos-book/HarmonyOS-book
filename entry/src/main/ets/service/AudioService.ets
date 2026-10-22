import { PlaybackCoordinator } from './PlaybackCoordinator';
import { ChapterRuleContext } from './rulesource/ChapterRuleContext';
import { LightSourceRequest } from './rulesource/light/LightSourceRequestPolicy';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter, BusinessError, systemDateTime } from '@kit.BasicServicesKit';
import { avSession } from '@kit.AVSessionKit';
import { Book, Chapter, AudioSource } from '../model/Book';
import { BookSource } from '../model/BookSource';
import { PlayerState, PlayMode, SleepMode } from '../model/PlayerState';
import { PreferenceService, PlayProgress, ChapterPlayProgress } from './PreferenceService';
import { SourceDataService } from './SourceDataService';
import { AudioRequestInfo, BookSourceService } from './BookSourceService';
import { DataService } from './DataService';
import { AVSessionService, AVSessionCallbacks } from './AVSessionService';
import { BackgroundTaskService } from './BackgroundTaskService';
import { ReadingSessionService, SessionLocation } from './ReadingSessionService';
import { ChapterCacheService } from './ChapterCacheService';
import { DownloadPolicy } from './DownloadPolicy';
import { LiveAudioService } from './LiveAudioService';
import { DownloadService } from './DownloadService';
import { WidgetUpdater } from './WidgetUpdater';
import { PlaybackStore } from './PlaybackStore';
import { BookUsageInput, StatsService } from './StatsService';
import { getWebViewAudioExtractor } from './builtin/WebViewAudioExtractor';
import { ExternalMediaWatcher } from './ExternalMediaWatcher';
import { ChapterProgressPolicy } from './ChapterProgressPolicy';
import { DiagnosticLogService } from './DiagnosticLogService';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_Audio';
const AUDIO_RESOLVE_TIMEOUT_MS = 15000;
const PRELOAD_STABLE_PLAYBACK_MS = 8000;

/** 播放历史落盘后广播的事件名,书架等页面订阅以实时刷新进度文案 */
export const EVT_HISTORY_UPDATED = 'app.history.updated';
export const EVT_AUDIO_PLAY_FAILED = 'app.audio.play.failed';
export const EVT_SLEEP_CANCELLED = 'app.audio.sleep.cancelled';

export interface AudioPlayFailedPayload {
  bookId: string;
  chapterId: string;
  message: string;
}

interface AudioResolveResult {
  headers: Record<string, string>;
  success: boolean;
}

/**
 * AVPlayer 单例封装
 * 内部按 AudioSource.type 分发：rawfile / url / file
 */
export class AudioService {
  private static instance: AudioService | null = null;
  private player: media.AVPlayer | null = null;
  private liveSource: boolean = false;
  private liveBufferTimer: number = -1;
  private liveReconnectAttempts: number = 0;
  private liveReconnectChapter: string = '';
  private liveLastReconnectAt: number = 0;

  private cancelLiveRecovery(): void {
    if (this.liveBufferTimer >= 0) clearTimeout(this.liveBufferTimer);
    this.liveBufferTimer = -1;
  }

  private scheduleLiveRecovery(player: media.AVPlayer): void {
    if (this.liveBufferTimer >= 0) return;
    const generation = this.playGen;
    this.liveBufferTimer = setTimeout((): void => {
      this.liveBufferTimer = -1;
      this.recoverLiveBuffer(player, generation);
    }, 15000);
  }

  private recoverLiveBuffer(player: media.AVPlayer, generation: number): void {
    if (this.player !== player || generation !== this.playGen || !this.state?.isLive ||
      !this.state.isPlaying || this.pauseRequested || this.sleepPausePending || this.pausedByFocus ||
      this.pausedByExternalMedia || PlaybackCoordinator.speechActive) return;
    const book = this.state.currentBook;
    const chapter = this.state.currentChapter;
    if (!book || !chapter) return;
    if (Date.now() - this.liveLastReconnectAt > 120000) this.liveReconnectAttempts = 0;
    if (this.liveReconnectAttempts >= 3) {
      this.pause('live-buffer-timeout');
      this.emitPlayFailed(book.id, chapter.id, '电台连接中断，请稍后重试');
      return;
    }
    this.liveReconnectAttempts++;
    this.liveLastReconnectAt = Date.now();
    this.tracePlayback(`live-reconnect:${this.liveReconnectAttempts}`);
    // HLS 下载器可能一直停留在 playing+buffering，未必会抛 error；重新取直播点。
    this.detachPlayer(player);
    this.doPlayChapter(book, chapter, 0).catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'live reconnect failed: %{public}s', error.message);
    });
  }

  private detachPlayer(player: media.AVPlayer): void {
    if (this.player === player) this.player = null;
    this.stopTick();
    // 移除事件后异步释放，旧 HLS reset/release 不得阻塞新章节或回写新状态。
    try { player.off('stateChange'); } catch (_e) {}
    try { player.off('timeUpdate'); } catch (_e) {}
    try { player.off('error'); } catch (_e) {}
    try { player.off('audioInterrupt'); } catch (_e) {}
    try { player.off('bufferingUpdate'); } catch (_e) {}
    try { player.off('audioOutputDeviceChangeWithInfo'); } catch (_e) {}
    player.release().catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'release old player: %{public}s', error.message);
    });
  }

  private async resetPlayerForSwitch(player: media.AVPlayer): Promise<void> {
    let timer: number = -1;
    let resetDone = false;
    const reset = player.reset().then((): void => { resetDone = true; })
      .catch((_error: Error): void => {});
    const timeout = new Promise<void>((resolve: () => void): void => {
      timer = setTimeout(resolve, 2000);
    });
    await Promise.race([reset, timeout]);
    if (timer >= 0) clearTimeout(timer);
    if (!resetDone && this.player === player) {
      hilog.warn(DOMAIN, TAG, 'player reset stalled; replace player');
      this.detachPlayer(player);
    }
  }
  private state: PlayerState | null = null;
  updateBookPresentation(book: Book): void {
    if (this.state?.currentBook?.id !== book.id) return;
    const current: Book = JSON.parse(JSON.stringify(this.state.currentBook));
    current.title = book.title;
    current.cover = book.cover;
    current.coverFallback = book.coverFallback;
    current.coverFromDetail = book.coverFromDetail;
    this.state.currentBook = current;
    if (this.state.currentChapter) AVSessionService.getInstance().updateMetadata(current, this.state.currentChapter);
  }
  private context: common.UIAbilityContext | null = null;
  private timer: number = -1;
  private pendingSeek: number = 0;
  private sleepPreferencesReady: Promise<void> | null = null;
  private autoSleepRequested: boolean = false;
  private sleepTimer: number = -1;
  private sleepEndTime: number = 0;
  private chapterEndHandled: boolean = false;
  private sleepPausePending: boolean = false;
  /** 手动、系统播控或耳机摘下要求暂停；加载完成和迟到的焦点事件不得覆盖。 */
  private pauseRequested: boolean = false;
  private pauseSource: string = 'none';
  private foreground: boolean = true;
  private playerStartPromise: Promise<void> | null = null;
  private playerStartTarget: media.AVPlayer | null = null;
  private playerStartGeneration: number = -1;

  /** 只记录状态和位置，不记录书名、音频地址或请求凭据。 */
  private tracePlayback(event: string): void {
    DiagnosticLogService.info('audio.event',
      `event=${event}; state=${this.player?.state ?? 'none'}; foreground=${this.foreground}; ` +
      `position=${this.state?.progressMs ?? 0}; generation=${this.playGen}; pause=${this.pauseRequested}; ` +
      `source=${this.pauseSource}; focus=${this.pausedByFocus}; external=${this.pausedByExternalMedia}; ` +
      `sleep=${this.sleepPausePending}; loading=${this.state?.isLoading ?? false}; bg=${BackgroundTaskService.isRunning()}`);
    hilog.info(DOMAIN, TAG,
      'playback event=%{public}s state=%{public}s foreground=%{public}s pos=%{public}d gen=%{public}d pause=%{public}s source=%{public}s focus=%{public}s external=%{public}s sleep=%{public}s loading=%{public}s bg=%{public}s',
      event, this.player?.state ?? 'none', String(this.foreground), this.state?.progressMs ?? 0,
      this.playGen, String(this.pauseRequested), this.pauseSource, String(this.pausedByFocus),
      String(this.pausedByExternalMedia), String(this.sleepPausePending), String(this.state?.isLoading ?? false),
      String(BackgroundTaskService.isRunning()));
  }

  /** 分段计时只记录阶段、耗时与任务代次，不包含来源或音频凭据。 */
  private tracePlaybackDuration(stage: string, startedAt: number, generation: number, cache: string = 'none'): void {
    const elapsedMs = Math.max(0, Date.now() - startedAt);
    DiagnosticLogService.info('audio.timing', `stage=${stage}; elapsedMs=${elapsedMs}; generation=${generation}; cache=${cache}`);
    hilog.info(DOMAIN, TAG, 'playback timing=%{public}s elapsedMs=%{public}d gen=%{public}d cache=%{public}s',
      stage, elapsedMs, generation, cache);
  }

  setForeground(foreground: boolean): void {
    this.foreground = foreground;
    this.tracePlayback(foreground ? 'foreground' : 'background');
  }
  private resumeAfterSleepChapter: boolean = false;
  private isApplying: boolean = false;
  private currentFile: fileIo.File | null = null;
  /** 用户偏好的焦点模式：0=共享(SHARE_MODE)、1=独立(INDEPENDENT_MODE) */
  private interruptMode: number = 0;
  /** 失去焦点被强制暂停后，收到 RESUME 是否自动续播 */
  private autoResume: boolean = true;
  /** 标识当前暂停是否由系统焦点变化引起（用于决定 RESUME 时是否自动续播） */
  private pausedByFocus: boolean = false;
  /** 标识当前是否被外部 MEDIA(视频/游戏/视频通话) 抢焦点强制 STOP。
   *  与 pausedByFocus 互斥:STOP 不会再下发 RESUME,要靠 ExternalMediaWatcher 旁路监测视频结束 */
  private pausedByExternalMedia: boolean = false;
  /** 视频结束监测器:被 STOP 后 arm,视频流消失即续播 */
  private externalWatcher: ExternalMediaWatcher = new ExternalMediaWatcher();
  /** 节流写入 progressMs 的最近一次时间戳。AVPlayer timeUpdate ~100ms 一次,
   *  但 progressMs 是 @Trace,会触发全局 V2 级联重渲染,降到 500ms 一次足够 UI 用 */
  private lastProgressWriteAt: number = 0;
  private static readonly PROGRESS_WRITE_INTERVAL_MS: number = 500;
  /** 节流持久化的最近一次时间戳。正常播放依靠 timeUpdate 稀疏持久化(5s 一次),
   *  避免依赖 tick 频繁落盘,配合低功耗渲染器长休眠周期 */
  private lastPersistAt: number = 0;
  private static readonly PERSIST_INTERVAL_MS: number = 5000;
  private static readonly USAGE_TICK_MS: number = 15000;
  private usageSince: number = -1;
  private usageBook: BookUsageInput | undefined = undefined;
  private pendingUsageMs: number = 0;
  /** 续播 seek 目标(ms)。>0 表示正在等待 seek 生效:
   *  此期间 AVPlayer 可能先回调一个接近 0 的旧 timeUpdate,会把 progressMs 打回起点。
   *  守卫:位置尚未追上目标前忽略这些偏小的旧值,到达目标附近才解除。 */
  private resumeTargetMs: number = 0;
  private static readonly RESUME_GUARD_TOLERANCE_MS: number = 1500;
  /** 播放任务代次：每次 playChapter / playChapterAndSeek 都会自增。
   *  正在解析音频 URL（耗时长，比如 WebView 嗅探）的旧任务跑完后会用这个比对，
   *  如果不是最新代次就直接丢弃，不再装载到 AVPlayer，避免"切了新章节但旧的还在响"。 */
  private playGen: number = 0;
  /** 与已实际装载的音源绑定，不能在旧播放器回调中读取新任务代次冒充归属。 */
  private playerSourceGeneration: number = -1;
  private playbackLoadStartedAt: number = 0;
  private preloadBuffering: boolean = false;
  private preloadStartTimer: number = -1;
  /** One automatic retry per user playback request; network timeouts must not restart indefinitely. */
  private autoRetryChapterId: string = '';
  /** 最近一次在线地址解析失败原因，用于把书源业务错误反馈给播放页。 */
  private lastResolveFailure: string = '';

  private canAutoRetryLoad(chapterId: string): boolean {
    return this.autoRetryChapterId !== chapterId;
  }
  /** 持久化代次：clearOnlineFavoritesAndHistory 期间冻结写入，防止清理后被 tick/persistHistory 写回。 */
  private persistGen: number = 0;
  private frozenPersistGen: number = -1;

  static getInstance(): AudioService {
    if (!AudioService.instance) {
      AudioService.instance = new AudioService();
    }
    return AudioService.instance;
  }

  /**
   * 用一个 Promise 暴露"是否准备好接受播控指令"。
   * 卡片 callee（play/pause/next/prev）会等这个 Promise resolve 再调用 AudioService，
   * 否则冷启动后第一下点卡片可能 state.currentChapter 还没 restore，play() 会变 no-op。
   */
  private readyResolve: (() => void) | null = null;
  private readyPromise: Promise<void> = new Promise<void>((res) => { this.readyResolve = res; });

  /** EntryAbility.bootstrapAudioService 完成后调一次 */
  markReady(): void {
    if (this.readyResolve) {
      this.readyResolve();
      this.readyResolve = null;
    }
  }

  /** 卡片 callee 用：等 ready，但带个超时兜底（避免 ready 永远不来卡死播控） */
  async whenReady(timeoutMs: number = 3000): Promise<void> {
    let timer: number = -1;
    const timeout = new Promise<void>((res) => {
      timer = setTimeout(res, timeoutMs);
    });
    await Promise.race([this.readyPromise, timeout]);
    if (timer >= 0) clearTimeout(timer);
  }

  prewarmBookSource(book: Book): void {
    if (!book.sourceUrl) return;
    this.prepareBookSource(book.sourceUrl).catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, 'prewarmBookSource failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
  }

  async openCastPicker(): Promise<boolean> {
    if (!this.context || !this.state || !this.state.currentBook || !this.state.currentChapter) return false;
    const book = this.state.currentBook;
    const chapter = this.state.currentChapter;
    let castUrl = AVSessionService.getInstance().currentCastMediaSource(book.id, chapter.id);
    if (!castUrl) castUrl = await this.resolveCastUrl(book, chapter);
    if (!castUrl) return false;
    AVSessionService.getInstance().updateCastMediaSource(book, chapter, castUrl);
    return AVSessionService.getInstance().openCastPicker();
  }

  private async prepareBookSource(sourceUrl: string): Promise<void> {
    await BookSourceService.prepareAudioSource(sourceUrl);
  }

  bind(state: PlayerState, context: common.UIAbilityContext): void {
    this.state = state;
    this.context = context;
    this.loadFocusPrefs();
    this.loadSleepPreferences();
    this.initAVSession();
  }

  private async loadFocusPrefs(): Promise<void> {
    try {
      this.interruptMode = await PreferenceService.getAudioInterruptMode();
      this.autoResume = await PreferenceService.getAudioAutoResume();
      if (this.player) {
        this.applyInterruptMode(this.player);
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'loadFocusPrefs failed: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
    }
  }

  /** 设置音频焦点模式：0=SHARE_MODE, 1=INDEPENDENT_MODE */
  async setInterruptMode(mode: number): Promise<void> {
    await PreferenceService.setAudioInterruptMode(mode);
    this.interruptMode = mode;
    if (this.player) {
      this.applyInterruptMode(this.player);
    }
  }

  /** 设置失焦自动恢复开关 */
  async setAutoResume(enabled: boolean): Promise<void> {
    this.autoResume = enabled;
    await PreferenceService.setAudioAutoResume(enabled);
  }

  private applyInterruptMode(p: media.AVPlayer): void {
    // audioInterruptMode 是属性 setter,鸿蒙限定必须在 prepared/playing/paused/completed
    // 状态下调用,idle/initialized/error/stopped/released 都会抛 Operate Not Permit。
    // 这里只在合法状态下设;非法状态由 stateChange 'prepared' 回调里再调一次兜底。
    const s = p.state;
    if (s !== 'prepared' && s !== 'playing' && s !== 'paused' && s !== 'completed') {
      return;
    }
    try {
      p.audioInterruptMode = this.interruptMode === 1
        ? audio.InterruptMode.INDEPENDENT_MODE
        : audio.InterruptMode.SHARE_MODE;
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'applyInterruptMode failed: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
    }
  }

  private initAVSession(): void {
    if (!this.context) return;
    const cbs: AVSessionCallbacks = {
      onPlay: () => {
        this.play().catch((err: Error): void => {
          hilog.warn(DOMAIN, TAG, 'Session play failed: %{public}s', err.message);
        });
      },
      onPause: () => { this.pause('avsession'); },
      onPlayNext: () => {
        this.playNext().catch((error: BusinessError): void => { DiagnosticLogService.failure('audio.next', error); });
      },
      onPlayPrevious: () => {
        this.playPrevious().catch((error: BusinessError): void => { DiagnosticLogService.failure('audio.previous', error); });
      },
      onFastForward: (ms: number) => { this.seekBy(ms); },
      onRewind: (ms: number) => { this.seekBy(-ms); },
      onSeek: (ms: number) => { this.seek(ms); },
      onSetSpeed: (speed: number) => { this.setSpeed(speed); },
      onSetLoopMode: (mode: avSession.LoopMode) => { this.setPlayMode(this.fromAVSessionLoopMode(mode)); },
      onCollection: () => { this.toggleFavoriteFromSession(); },
      onCastConnected: () => { this.pause('cast'); }
    };
    AVSessionService.getInstance().setCallbacks(cbs);
    AVSessionService.getInstance().init(this.context).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'init AVSession failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
  }

  private syncPlaybackState(): void {
    this.syncPlaybackStateNow(false);
  }

  private async syncPlaybackStateNow(forceWidget: boolean): Promise<void> {
    if (!this.state) return;
    // 卡片不等待媒体中心 IPC 或收藏查询；调用时即截取当前书籍状态。
    const widgetUpdate = this.syncPlayerCard(forceWidget);
    try {
      const isFav = this.state.currentBook
        ? await PreferenceService.isFavorite(this.state.currentBook.id)
        : false;
      await AVSessionService.getInstance().updatePlaybackState(
        this.state.isPlaying,
        this.state.progressMs,
        this.state.speed,
        this.state.durationMs,
        isFav
      );
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'updatePlaybackState failed: %{public}s',
        (err as Error)?.message ?? JSON.stringify(err));
    }
    await widgetUpdate;
  }

  private async syncPlayerCard(force: boolean): Promise<void> {
    try {
      await WidgetUpdater.updatePlayerCard(this.state, force);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'updatePlayerCard failed: %{public}s',
        (err as Error)?.message ?? JSON.stringify(err));
    }
  }

  private async ensurePlayer(): Promise<media.AVPlayer> {
    await this.loadSleepPreferences();
    if (this.player) {
      return this.player;
    }
    const p = await media.createAVPlayer();
    p.on('stateChange', (newState: media.AVPlayerState, reason: media.StateChangeReason) => {
      if (this.player !== p) return;
      if (this.playerSourceGeneration !== this.playGen || p.state !== newState) return;
      this.tracePlayback(`state:${newState}:reason=${reason}`);
      if (this.playbackLoadStartedAt > 0 && ['initialized', 'prepared', 'playing'].includes(newState)) {
        this.tracePlaybackDuration(`state:${newState}`, this.playbackLoadStartedAt, this.playGen);
      }
      if (newState !== 'playing') {
        this.cancelPreloadStart();
        this.stopTick();
      }
      if (!this.state) return;
      if (newState === 'initialized') {
        // 听书内容声明为 AUDIOBOOK 流,系统据此挂载低功耗音频渲染器:
        // 亮屏缓存最大 1s、熄屏缓存最大 10s,主处理器可长时间休眠,
        // 后台/熄屏播放功耗显著下降。setter 仅在 initialized 状态合法。
        try {
          p.audioRendererInfo = {
            usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
            rendererFlags: 0
          };
        } catch (err) {
          const e = err as Error;
          hilog.warn(DOMAIN, TAG, 'set audioRendererInfo failed: %{public}s',
            e?.message ?? JSON.stringify(err));
        }
        const generation = this.playerSourceGeneration;
        const prepareStartedAt = Date.now();
        p.prepare().catch((error: BusinessError): void => {
          this.handlePlayerOperationFailure(p, generation, 'prepare', error);
        }).finally((): void => {
          this.tracePlaybackDuration('prepare-call', prepareStartedAt, generation);
        });
      } else if (newState === 'prepared') {
        // 此时 player 已进入合法状态,补一次焦点模式 setter(ensurePlayer 阶段不能设)
        this.applyInterruptMode(p);
        this.state.isLive = this.liveSource || (this.state.currentChapter?.source.type === 'url' && p.duration < 0);
        this.state.durationMs = this.state.isLive ? 0 : Math.max(0, p.duration);
        hilog.info(DOMAIN, TAG, 'prepared live=%{public}s duration=%{public}d', String(this.state.isLive), p.duration);
        if (this.state.isLive) {
          this.pendingSeek = 0;
          this.resumeTargetMs = 0;
          this.state.progressMs = 0;
          this.state.savedDurationMs = 0;
        }
        // TOC 不带时长,这里把 AVPlayer 解出的真实时长回写到章节,
        // 让冷启动滑块/详情页百分比/书架文案能拿到 duration(否则恒为 0)
        if (!this.state.isLive && this.state.currentChapter && p.duration > 0) {
          this.state.currentChapter.duration = Math.round(p.duration / 1000);
          // 立即持久化时长到数据库，确保冷启动后仍可用
          if (this.state.currentBook) {
            DataService.upsertCachedBook(this.state.currentBook).catch((err: Error) => {
              hilog.error(DOMAIN, TAG, 'Failed to persist chapter duration: %{public}s', err.message);
            });
          }
        }
        // prepared 即上报一次 playbackState,让控制中心能立刻拿到 duration 渲染进度条
        AVSessionService.getInstance().updateMetadataDuration(this.state.durationMs);
        this.syncPlaybackState();
        if (this.pendingSeek > 0) {
          p.seek(this.pendingSeek, media.SeekMode.SEEK_PREV_SYNC);
          this.pendingSeek = 0;
        }
        // 续用上次的倍速:切章节/换书 reset 后 AVPlayer 会回到 1.0x,这里在 prepared 合法态补回
        if (!this.state.isLive && this.state.speed !== 1.0) {
          try { p.setPlaybackRate(this.state.speed); } catch (_e) { /* 状态异常忽略 */ }
        }
        // 立即设置播放状态，让UI立即响应
        this.state.isPlaying = !this.sleepPausePending && !this.pauseRequested && !this.pausedByFocus &&
          !this.pausedByExternalMedia && !PlaybackCoordinator.speechActive;
        if (this.state.isPlaying) {
          const generation = this.playerSourceGeneration;
          this.playPlayer(p).catch((error: BusinessError): void => {
            this.handlePlayerOperationFailure(p, generation, 'play', error);
          });
        }
        else {
          this.state.isLoading = false;
          this.stopBackgroundIfIdle();
        }
      } else if (newState === 'playing') {
        if (this.sleepPausePending || this.pauseRequested || this.pausedByFocus ||
          this.pausedByExternalMedia || PlaybackCoordinator.speechActive) {
          p.pause().catch((err: Error): void => {
            hilog.warn(DOMAIN, TAG, 'Pending pause failed: %{public}s', err.message);
          });
          return;
        }
        this.chapterEndHandled = false;
        this.state.isPlaying = true;
        this.startAutoSleepIfNeeded();
        // 真正开始出声,清掉 loading 标记
        this.state.isLoading = false;
        this.startTick();
        this.recordSession();
        if (this.state.currentBook && this.state.currentChapter) {
          this.triggerPreload(this.state.currentBook, this.state.currentChapter);
        }
        this.syncPlaybackState();
        PlaybackStore.getInstance().setPlaying(true);
        if (this.context) {
          BackgroundTaskService.start(this.context);
        }
      } else if (newState === 'paused') {
        this.state.isPlaying = false;
        if (this.state.currentBook && this.state.currentChapter) {
          this.triggerPreload(this.state.currentBook, this.state.currentChapter, true);
        }
        this.stopTick();
        // 立即落盘:暂停后 tick 停了,不存就会丢掉「上次 tick 到暂停」之间的进度,
        // 手动暂停 / 锁屏 / 电话打断后续播都会偏早。progressMs 此刻已是暂停位置,
        // seek 守卫保证它不会是被打回的 0。
        this.persistHistory();
        this.syncPlaybackState();
        PlaybackStore.getInstance().setPlaying(false);
        // 未在播时不要继续挂 audioPlayback 长时任务:
        // 系统会以「音频未运行」取消整条 continuous task，连同 dataTransfer 一起失效，
        // 息屏后纯下载也会被冻结。下载侧会单独维持 dataTransfer。
        if (this.context) {
          BackgroundTaskService.stop(this.context).catch((_e: Error): void => {});
        }
      } else if (newState === 'completed') {
        this.state.isPlaying = false;
        this.recordSession();
        this.recordPause();
        this.stopTick();
        this.syncPlaybackState();
        PlaybackStore.getInstance().setPlaying(false);
        // 自动切章的解析、联网与缓冲仍属于同一播放任务，不能在缓存边界先释放后台资格。
        this.handleChapterEnd();
      }
    });
    p.on('timeUpdate', (ms: number) => {
      if (!this.state || this.player !== p || this.playerSourceGeneration !== this.playGen || this.state.isLive) return;
      // 切换章节/书的过程中（reset 之后、新音源 prepared 之前），AVPlayer 偶尔会回调
      // 一些残留的旧位置 timeUpdate；isLoading=true 期间一律不写 progressMs，
      // 避免把进度条来回打回。
      if (this.state.isLoading) return;
      // seek 守卫:续播 seek 尚未生效时,AVPlayer 会先回调接近 0 的旧位置,
      // 若放行会把 progressMs 打回起点(还可能被 5s tick 落盘成错进度)。
      // 位置追上目标附近前忽略这些偏小旧值;到达或超过目标即解除守卫。
      if (this.resumeTargetMs > 0) {
        if (ms + AudioService.RESUME_GUARD_TOLERANCE_MS < this.resumeTargetMs) {
          return;
        }
        this.resumeTargetMs = 0;
      }
      // 单集循环可能只 seek 而不再发 playing；回到正文后才允许下一次章尾结算。
      const outroMs = Math.max(0, this.state.currentBook?.skipOutro ?? 0) * 1000;
      if (this.chapterEndHandled && !this.sleepPausePending && ms < p.duration - outroMs - 1000) {
        this.chapterEndHandled = false;
      }
      // 节流:跳进度 / 暂停 / 切章节时立即写,正常播放每 500ms 写一次,
      // 避免 100ms 级 @Trace 抖动导致 V2 全局级联重绘
      const now = Date.now();
      const force = !this.state.isPlaying || Math.abs(ms - this.state.progressMs) > 1500;
      if (force || now - this.lastProgressWriteAt >= AudioService.PROGRESS_WRITE_INTERVAL_MS) {
        this.state.progressMs = ms;
        this.lastProgressWriteAt = now;
      }
      // 先更新进度，再处理片尾停止，确保落盘的是本次章尾位置。
      this.checkSkipOutro(ms);
      // 稀疏持久化:正常播放期间每 5s 落盘一次,避免杀进程丢失大段进度。
      // 与 tick 的 15s 持久化错开:这里管播放中兜底,tick 管 Widget 同步兜底。
      if (this.state.isPlaying && now - this.lastPersistAt >= AudioService.PERSIST_INTERVAL_MS) {
        this.persistHistory().catch(() => { /* ignore */ });
        this.lastPersistAt = now;
      }
    });
    p.on('error', (err: BusinessError) => {
      if (this.player !== p || this.playerSourceGeneration !== this.playGen) return;
      const e = err;
      this.tracePlayback(`error:code=${err.code}`);
      hilog.error(DOMAIN, TAG, 'AVPlayer error: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
      if (!this.state) return;
      const ch = this.state.currentChapter;
      const book = this.state.currentBook;
      // 是否在用"已解析/缓存过的 URL"（值 != 原始章节页 URL）加载
      const usingResolvedUrl = !!ch && ch.source.type === 'url'
        && !!ch.originSourceValue && ch.source.value !== ch.originSourceValue;
      this.state.isLoading = false;
      this.state.isPlaying = false;
      this.recordSession();
      // 解析后的临时音频 URL 可能已过期（如 aikeu 的签名链接），把这个章节的缓存清掉，
      // 之后用 originSourceValue 重新解析一份新的音频 URL。
      if (ch && ch.originSourceValue) {
        try { ChapterCacheService.getInstance().clearChapter(ch.id); } catch (_e) { /* ignore */ }
        ch.source = { type: 'url', value: ch.originSourceValue };
      }
      // 加载/解析过的 URL 失效（缓存或上次解析的临时链接）:清缓存后自动重新解析一次再播，
      // loading 不会提前消失（playChapter 内会重新置 true）；重试仍失败则由限流阻止再次自动重试。
      if (book && ch && usingResolvedUrl && !this.pauseRequested && !this.sleepPausePending
        && !this.pausedByFocus && !this.pausedByExternalMedia && !PlaybackCoordinator.speechActive
        && this.canAutoRetryLoad(ch.id)) {
        this.autoRetryChapterId = ch.id;
        hilog.warn(DOMAIN, TAG, 'AVPlayer error with resolved URL, auto re-resolve chapter: %{public}s', ch.title);
        const resumeMs = this.state.progressMs;
        this.tracePlayback('retry:resolved-url');
        this.playChapterAndSeek(book, ch, resumeMs, true).catch((err2: Error): void => {
          hilog.warn(DOMAIN, TAG, 'auto retry playChapter failed: %{public}s',
            err2 && err2.message ? err2.message : JSON.stringify(err2));
        });
        return;
      }
      this.stopTick();
      PlaybackStore.getInstance().setPlaying(false);
      this.syncPlaybackState();
      if (this.context) BackgroundTaskService.stop(this.context);
    });
    p.on('audioInterrupt', (event: audio.InterruptEvent) => {
      if (this.player !== p) return;
      this.handleInterrupt(event);
    });
    p.on('bufferingUpdate', (type: media.BufferingInfoType, value: number): void => {
      if (this.player !== p || this.playerSourceGeneration !== this.playGen) return;
      if (type === media.BufferingInfoType.BUFFERING_START) {
        this.cancelPreloadStart();
        this.stopTick();
      } else if (type === media.BufferingInfoType.BUFFERING_END && p.state === 'playing' &&
        this.state?.isPlaying && !this.pauseRequested && !PlaybackCoordinator.speechActive) {
        this.startTick();
      }
      if (!this.state?.isLive) {
        if (type === media.BufferingInfoType.BUFFERING_START &&
          !this.pauseRequested && !this.sleepPausePending && this.state?.isPlaying) {
          this.preloadBuffering = true;
          ChapterCacheService.getInstance().suspendPreload();
        } else if (type === media.BufferingInfoType.BUFFERING_END) {
          this.preloadBuffering = false;
          if (this.state?.currentBook && this.state.currentChapter) {
            this.triggerPreload(this.state.currentBook, this.state.currentChapter);
          }
        }
      }
      if (type === media.BufferingInfoType.BUFFERING_START || type === media.BufferingInfoType.BUFFERING_END) {
        this.tracePlayback(`buffering:type=${type}:value=${value}`);
      }
      if (type === media.BufferingInfoType.BUFFERING_START && this.state?.isLive && p.state === 'playing') {
        this.scheduleLiveRecovery(p);
      } else if (type === media.BufferingInfoType.BUFFERING_END) {
        this.cancelLiveRecovery();
      }
    });
    // API 11：包括支持佩戴检测的耳机双耳摘下，以及蓝牙断开/有线耳机拔出。
    // 新设备可用仅表示路由变化；戴上续播交给耳机/系统通过 AVSession 下发 play。
    p.on('audioOutputDeviceChangeWithInfo', (info: audio.AudioStreamDeviceChangeInfo): void => {
      this.tracePlayback(`output-device:reason=${info.changeReason}`);
      if (this.player !== p
        || info.changeReason !== audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE) return;
      hilog.info(DOMAIN, TAG, 'Audio output unavailable, pause playback');
      this.pause('output-device-unavailable');
    });
    // 焦点模式不在这里设——AVPlayer 刚 createAVPlayer 完是 idle 状态,
    // setter 会被鸿蒙拒绝(Operate Not Permit)。改在 stateChange 'prepared' 里设。
    this.player = p;
    return p;
  }

  /** 卡片、锁屏和自动切章共用：先具备后台资格再出声，等待期间仍以最新暂停/切章为准。 */
  private playPlayer(player: media.AVPlayer): Promise<void> {
    const generation = this.playGen;
    if (this.playerStartPromise && this.playerStartTarget === player && this.playerStartGeneration === generation) {
      return this.playerStartPromise;
    }
    const task: Promise<void> = this.startPlayerWithBackground(player, generation).finally((): void => {
      if (this.playerStartPromise === task) {
        this.playerStartPromise = null;
        this.playerStartTarget = null;
      }
    });
    this.playerStartTarget = player;
    this.playerStartGeneration = generation;
    this.playerStartPromise = task;
    return task;
  }

  private async startPlayerWithBackground(player: media.AVPlayer, generation: number): Promise<void> {
    const context = this.context;
    if (!context || !this.canStartPlayer(player, generation)) return;
    const sessionStartedAt = Date.now();
    try { await AVSessionService.getInstance().init(context); }
    finally { this.tracePlaybackDuration('avsession-ready', sessionStartedAt, generation); }
    if (!this.canStartPlayer(player, generation)) {
      this.finishCancelledPlayerStart(player, generation);
      return;
    }
    const backgroundStartedAt = Date.now();
    try { await BackgroundTaskService.start(context); }
    finally { this.tracePlaybackDuration('background-ready', backgroundStartedAt, generation); }
    if (!this.canStartPlayer(player, generation)) {
      this.finishCancelledPlayerStart(player, generation);
      return;
    }
    // 被系统静音/冻结后播放器可能仍为 playing，用户再次播放也必须补申请后台任务。
    if (player.state === 'playing') return;
    const playStartedAt = Date.now();
    try {
      await player.play();
    } catch (error) {
      this.handlePlayerOperationFailure(player, generation, 'play', error);
    } finally {
      this.tracePlaybackDuration('player-play', playStartedAt, generation);
    }
  }

  private finishCancelledPlayerStart(player: media.AVPlayer, generation: number): void {
    if (this.player !== player || this.playGen !== generation ||
      this.playerSourceGeneration !== generation || !this.state) return;
    this.state.isPlaying = false;
    this.state.isLoading = false;
    this.syncPlaybackState();
    this.stopBackgroundIfIdle();
  }

  private canStartPlayer(player: media.AVPlayer, generation: number): boolean {
    return this.player === player && this.playGen === generation && this.state !== null &&
      this.playerSourceGeneration === generation &&
      (player.state === 'prepared' || player.state === 'paused' || player.state === 'completed' || player.state === 'playing') &&
      !this.pauseRequested && !this.sleepPausePending && !this.pausedByFocus &&
      !this.pausedByExternalMedia && !PlaybackCoordinator.speechActive;
  }

  private handlePlayerOperationFailure(player: media.AVPlayer, generation: number,
    operation: string, error: BusinessError): void {
    if (this.player !== player || this.playGen !== generation ||
      this.playerSourceGeneration !== generation || !this.state) return;
    DiagnosticLogService.failure(`audio.${operation}`, error);
    this.tracePlayback(`operation-failed:${operation}:code=${error.code ?? -1}`);
    this.state.isPlaying = false;
    this.state.isLoading = false;
    this.stopTick();
    PlaybackStore.getInstance().setPlaying(false);
    this.syncPlaybackState();
    this.stopBackgroundIfIdle();
  }

  private handleInterrupt(event: audio.InterruptEvent): void {
    this.cancelLiveRecovery();
    this.tracePlayback(`interrupt:type=${event.eventType}:force=${event.forceType}:hint=${event.hintType}:autoResume=${this.autoResume}`);
    if (PlaybackCoordinator.speechActive || this.pauseRequested || this.sleepPausePending) return;
    // SHARE 的 PAUSE/STOP 由应用执行；FORCE 已由系统执行，但同样必须封住异步起播。
    if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
      event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
        // 临时暂停（语音、电话、闹铃等）：标记为焦点暂停，等待系统后续下发 RESUME
        // 旧的视频流 watcher 若残留,先 disarm 以免误触发(当前打断已被新事件接管)
        this.cancelExternalMediaWatch();
        this.pausedByFocus = true;
        if (this.state) {
          this.state.isPlaying = false;
          this.state.isLoading = false;
        }
        this.stopTick();
        this.persistHistory();
        this.syncPlaybackState();
        PlaybackStore.getInstance().setPlaying(false);
      } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        // 永久失去焦点:系统不会再下发 RESUME(典型场景:抖音/B 站等视频抢焦点)。
        // 不再 reset player —— 留住 paused 状态,arm ExternalMediaWatcher,
        // 监测到外部视频流消失时主动续播。30s 超时后 watcher 自动 disarm。
        // 先把旧 watcher 清掉,避免被新一轮 STOP 重复 arm 留下双监听
        this.cancelExternalMediaWatch();
        this.pausedByFocus = false;
        this.pausedByExternalMedia = true;
        if (this.state) {
          this.state.isPlaying = false;
          this.state.isLoading = false;
        }
        this.stopTick();
        // 立即把当前进度落盘:与 'paused' stateChange 分支同样的理由,
        // 防止 STOP 后 tick 停了丢掉最近一段进度
        this.persistHistory();
        this.syncPlaybackState();
        PlaybackStore.getInstance().setPlaying(false);
        if (this.autoResume) {
          this.externalWatcher.arm(() => this.resumeAfterExternalMedia());
        }
      }
      const player = this.player;
      if (event.forceType === audio.InterruptForceType.INTERRUPT_SHARE && player?.state === 'playing') {
        player.pause().catch((error: BusinessError): void => {
          DiagnosticLogService.failure('audio.interrupt-pause', error);
        });
      }
      this.stopBackgroundIfIdle();
      // DUCK / UNDUCK：系统仅做音量变化，播放未中断，无需处理状态
    } else if (event.forceType === audio.InterruptForceType.INTERRUPT_SHARE) {
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
        // 此前因 PAUSE 临时失焦，现在系统下发可续播提示
        if (this.autoResume && this.pausedByFocus) {
          this.pausedByFocus = false;
          this.resumeFromInterrupt();
        } else {
          this.pausedByFocus = false;
        }
      }
    }
  }

  private async resumeFromInterrupt(): Promise<void> {
    this.tracePlayback('resume:focus');
    if (PlaybackCoordinator.speechActive || this.pauseRequested || this.sleepPausePending) return;
    try {
      const p = await this.ensurePlayer();
      if (PlaybackCoordinator.speechActive || this.pauseRequested || this.sleepPausePending ||
        this.pausedByFocus || this.pausedByExternalMedia) return;
      if (p.state === 'paused') {
        // 立即设置播放状态
        if (this.state) {
          this.state.isPlaying = true;
        }
        await this.playPlayer(p);
      } else if (p.state === 'idle' || p.state === 'stopped') {
        await this.resumeFromState();
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'resumeFromInterrupt failed: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
    }
  }

  /**
   * 视频流消失后,ExternalMediaWatcher 回调走这里。
   * 若用户在等待期间已经手动操作过(toggle/pause/play/playChapter),pausedByExternalMedia 已被清零,直接返回。
   */
  private async resumeAfterExternalMedia(): Promise<void> {
    this.tracePlayback('resume:external-media');
    if (!this.pausedByExternalMedia || !this.autoResume || this.pauseRequested || this.sleepPausePending) return;
    this.pausedByExternalMedia = false;
    try {
      const p = await this.ensurePlayer();
      if (PlaybackCoordinator.speechActive || this.pauseRequested || this.sleepPausePending ||
        this.pausedByFocus || this.pausedByExternalMedia) return;
      if (p.state === 'paused') {
        if (this.state) {
          this.state.isPlaying = true;
        }
        await this.playPlayer(p);
      } else if (p.state === 'idle' || p.state === 'stopped') {
        // 等待期间系统已经把 renderer 回收,走完整续播路径
        await this.resumeFromState();
      }
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'resumeAfterExternalMedia failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  /** 用户主动操作 / 重新被打断时调用,确保旧 watcher 不残留触发 */
  private cancelExternalMediaWatch(): void {
    this.pausedByExternalMedia = false;
    if (this.externalWatcher.isArmed()) {
      this.externalWatcher.disarm();
    }
  }

  private recordPause(): void {
    // AVSession 永远保持 activated,不再做 idle deactivate。保留空方法以兼容历史调用点。
  }

  private startTick(): void {
    this.stopTick();
    const book = this.state?.currentBook;
    if (!book || !this.state?.currentChapter) return;
    if (this.usageBook?.bookId !== book.id) this.pendingUsageMs = 0;
    this.usageBook = {
      bookId: book.id, title: book.title, author: book.author || book.narrator || '',
      cover: book.cover || '', sourceUrl: book.sourceUrl || '', bookUrl: book.bookUrl || ''
    };
    this.usageSince = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
    this.timer = setInterval(() => {
      this.persistHistory();
      this.recordListenUsage();
      // 同步给 widget:稳态播放期间 stateChange 不再翻转,卡片那边的 FormExt 进程
      // 缓存又跟主进程隔离,系统触发 onUpdateForm 时容易读到陈旧的 isPlaying。
      // 主进程定期强推一次最新状态,卡片至多滞后该间隔即可纠正。
      // 间隔 15s:低功耗渲染器熄屏缓存最大 10s,过短的 tick 会每周期唤醒主处理器,
      // 抵消 AUDIOBOOK 流的省电收益。toggle/pause/release/seek 都有即时同步,
      // 这里只是兜底。
      this.syncPlaybackState();
    }, AudioService.USAGE_TICK_MS);
  }

  private stopTick(): void {
    this.recordListenUsage();
    this.usageSince = -1;
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private recordListenUsage(): void {
    if (this.usageSince < 0 || this.usageBook === undefined) return;
    // STARTUP 含熄屏休眠，不受系统校时、倍速或拖动播放进度影响。
    const now = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
    this.pendingUsageMs += Math.max(0, now - this.usageSince);
    this.usageSince = now;
    const seconds = Math.floor(this.pendingUsageMs / 1000);
    if (seconds < 1) return;
    this.pendingUsageMs -= seconds * 1000;
    StatsService.addListenSeconds(seconds, this.usageBook, Date.now()).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'recordListenUsage failed: %{public}s', err?.message ?? JSON.stringify(err));
    });
  }

  private recordSession(): void {
    if (!this.state || this.state.isLive || !this.state.currentBook || !this.state.currentChapter) return;
    ReadingSessionService.checkpoint('audio', SessionLocation.audio(this.state.currentBook,
      this.state.currentChapter, this.state.progressMs, this.state.durationMs), this.state.isPlaying);
  }

  private async persistHistory(): Promise<void> {
    if (this.frozenPersistGen >= 0) return;
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    this.recordSession();
    const book = this.state.currentBook;
    const chapter = this.state.currentChapter;
    const chapterId = chapter.id;
    const chapterTitle = chapter.title;
    const progressMs = this.state.isLive ? 0 : this.state.progressMs;
    const durationMs = this.state.durationMs;
    const chapterIndex = this.findChapterIndex(book, chapter);
    await PreferenceService.upsertHistory({
      bookId: book.id,
      chapterId,
      progressMs,
      updatedAt: Date.now(),
      chapterTitle,
      durationMs,
      sourceUrl: book.sourceUrl || '',
      bookUrl: book.bookUrl || ''
    });
    await PreferenceService.setLastPlayed(book.id, chapterId, progressMs, chapterTitle, durationMs, this.state.speed);
    // 每本书独立的最新进度,切书前 reset AVPlayer 之前必须把这条落盘,
    // 切回旧书时 caller 没传 positionMs 也能从这里 fallback 到上次位置
    const progress: PlayProgress = {
      bookId: book.id,
      chapterId,
      chapterTitle,
      chapterIndex: chapterIndex >= 0 ? chapterIndex : 0,
      positionMs: progressMs,
      durationMs,
      updatedAt: Date.now(),
      speed: this.state.speed,
      sourceUrl: book.sourceUrl || '',
      bookUrl: book.bookUrl || ''
    };
    await PreferenceService.saveProgress(progress);
    const chapterProgress = new ChapterPlayProgress();
    chapterProgress.bookId = book.id;
    chapterProgress.chapterId = chapterId;
    chapterProgress.positionMs = progressMs;
    chapterProgress.durationMs = durationMs;
    chapterProgress.updatedAt = Date.now();
    await PreferenceService.saveChapterProgress(chapterProgress);
    await DataService.upsertCachedBook(book);
    // PlaybackStore: 让其他页面拿到的是"现在响着的"那本书,
    // sourceUrl 走 chapter.source.value(已是解析后的真实 URL,作 same-source 判断)
    PlaybackStore.getInstance().update(
      book.id, chapterId, progress.chapterIndex,
      chapter.source?.value ?? '', this.state.isPlaying
    );
    emitter.emit(EVT_HISTORY_UPDATED, { data: { bookId: book.id } });
  }

  /** 主动把当前进度立刻落盘,供 PlayerPage 退出 / 暂停等场景调用 */
  async flushHistory(): Promise<void> {
    await this.persistHistory();
  }

  /**
   * 回前台时调用:校准 AVPlayer 健康度。
   *
   * 退后台 + paused 状态下,鸿蒙在 1~2s 内会回收 audio renderer,player.state 自己掉到 idle,
   * 但内部 fdSrc/url 已失效——此时直接走 toggle → resumeFromState → applySource 设 url
   * 不一定能驱动到 prepared,UI 表现就是"按播放没反应"。
   *
   * 这里只在异常状态下做最小干预:
   * - released:player 已不可用,丢弃引用,下次 ensurePlayer 会重建
   * - error / stopped:reset 一次回到干净 idle
   * - idle:已经是干净状态,留给后续 toggle 走 resumeFromState 路径
   * - 其他(playing/paused/prepared/initialized):说明 player 还活着,不动
   *
   * 不在这里主动起播——避免应用刚回前台就抢焦点打断别的 App。
   */
  async ensureHealthy(): Promise<void> {
    const p = this.player;
    if (!p) return;
    const s = p.state;
    if (s === 'released') {
      this.player = null;
      return;
    }
    if (s === 'error' || s === 'stopped') {
      try {
        await p.reset();
      } catch (err) {
        const e = err as Error;
        hilog.warn(DOMAIN, TAG, 'ensureHealthy: reset failed: %{public}s',
          e?.message ?? JSON.stringify(err));
      }
    }
  }

  /**
   * 切到某章节从头播。三态决策:
   * - 同书+同章节+player 已 prepared/playing/paused: seek(0) + play(),不 reset
   * - 同书+不同章节: await 当前进度落盘 → reset → 装载新章节
   * - 不同书: await 当前进度落盘 → reset → 拿新书 PlayProgress 兜底 savedDurationMs → 装载
   */
  async playChapter(book: Book, chapter: Chapter, automatic: boolean = false): Promise<void> {
    if (automatic && PlaybackCoordinator.speechActive) return;
    if (!await PlaybackCoordinator.useAudio()) return;
    AVSessionService.getInstance().restoreAudioCallbacks();
    if (!this.state || !this.context) {
      throw new Error('AudioService not bound');
    }
    this.prepareSleepForPlayback(book, chapter, automatic);
    if (!automatic) this.autoRetryChapterId = '';
    this.cancelExternalMediaWatch();

    // ★ 同书+同章节短路:不 reset,直接 seek(0) + play,避免重新嗅探 URL
    if (this.canReuseSameChapter(book, chapter)) {
      AVSessionService.getInstance().updateMetadata(book, chapter);
      await this.replaySameChapterFromStart();
      return;
    }
    // 先翻转加载状态，覆盖进度落盘、播放器 reset 和 URL 解析的等待时间。
    this.beginChapterLoading();
    // 切书或切章节前先把上一进度落盘,避免 reset 后丢数据
    try {
      await this.flushBeforeSwitch(book, chapter);
      const skipIntroMs = (book.skipIntro ?? 0) * 1000;
      return await this.doPlayChapter(book, chapter, skipIntroMs);
    } catch (err) {
      if (this.state) this.state.isLoading = false;
      throw err as Error;
    }
  }

  /** 手动选集时恢复该章节的独立进度；没有记录时按正常片头设置起播。 */
  async playChapterFromSavedProgress(book: Book, chapter: Chapter): Promise<void> {
    const saved = await PreferenceService.getChapterProgress(book.id, chapter.id);
    if (!saved) {
      await this.playChapter(book, chapter);
      return;
    }
    const durationMs = saved.durationMs > 0 ? saved.durationMs : Math.max(0, chapter.duration * 1000);
    const seekMs = ChapterProgressPolicy.resolveResumePosition(
      saved.positionMs,
      durationMs,
      Math.max(0, book.skipIntro ?? 0) * 1000,
      Math.max(0, book.skipOutro ?? 0) * 1000
    );
    await this.playChapterAndSeek(book, chapter, seekMs);
  }

  /** 同书+同章节复用:不 reset。视 player 状态决定 seek/play */
  private async replaySameChapterFromStart(): Promise<void> {
    if (!this.state) return;
    const p = this.player;
    if (!p) return;
    if (this.state.isLive) {
      await this.seekAndPlaySameChapter(0);
      return;
    }
    // toggle() 可能在调用前设了 isLoading=true，复用章节不需要 loading 圈
    this.state.isLoading = false;
    const skipIntroMs = (this.state.currentBook?.skipIntro ?? 0) * 1000;
    this.state.progressMs = skipIntroMs;
    if (p.state === 'completed' || p.state === 'paused' || p.state === 'prepared') {
      try {
        p.seek(skipIntroMs, media.SeekMode.SEEK_PREV_SYNC);
        this.state.isPlaying = true;
        await this.playPlayer(p);
      } catch (err) {
        const e = err as Error;
        hilog.error(DOMAIN, TAG, 'replaySameChapterFromStart failed: %{public}s',
          e?.message ?? JSON.stringify(err));
        this.state.isPlaying = false;
      }
    } else if (p.state === 'playing') {
      try {
        p.seek(skipIntroMs, media.SeekMode.SEEK_PREV_SYNC);
      } catch (_e) { /* ignore */ }
    }
  }

  /** 判断 (book,chapter) 是否就是当前播放的同章节,且 player 处于可复用状态 */
  private canReuseSameChapter(book: Book, chapter: Chapter): boolean {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return false;
    if (this.state.currentBook.id !== book.id) return false;
    if (this.state.currentChapter.id !== chapter.id) return false;
    const p = this.player;
    if (!p) return false;
    const s = p.state;
    return s === 'playing' || s === 'paused' || s === 'prepared' || s === 'completed';
  }

  /**
   * 切书/切章节前把上一进度落盘 + 给 UI 立即填上 savedDurationMs 兜底。
   * - 切到不同书: 把当前书 flush;再去 PreferenceService.getProgress(目标 bookId) 拿 durationMs 兜底
   * - 切到同书不同章: 把当前章 flush;saveDurationMs 用目标章节自身 chapter.duration
   */
  private async flushBeforeSwitch(targetBook: Book, targetChapter: Chapter): Promise<void> {
    if (!this.state) return;
    const curBookId = this.state.currentBook?.id ?? '';
    const curChapterId = this.state.currentChapter?.id ?? '';
    const bookChanged = curBookId !== targetBook.id;
    const chapterChanged = bookChanged || curChapterId !== targetChapter.id;
    if (curBookId && curChapterId && chapterChanged) {
      // 切书或切集:先把当前章节的进度落盘
      try { await this.persistHistory(); } catch (_e) { /* ignore */ }
      if (bookChanged) ReadingSessionService.end('audio');
    }
    // 切书(含冷启动首播)优先恢复单本倍速，没有有效记录才用全局默认值；同书切章保持当前倍速。
    // 必须 await getProgress 走持久化 store:冷启动后 progressMemo 为空,
    // getProgressSync 只读内存缓存会恒为 null,导致重启后倍速永远回落 1.0x。
    // 顺带把该书进度读进 memo,后面 savedDurationMs 兜底也能命中。
    // 真正下发到 AVPlayer 由 prepared 回调里的 state.speed 补回逻辑负责。
    if (bookChanged) {
      const saved = await PreferenceService.getProgress(targetBook.id);
      const savedSpeed = saved?.speed;
      this.state.speed = typeof savedSpeed === 'number' && Number.isFinite(savedSpeed) && savedSpeed > 0
        ? this.normalizeSpeed(savedSpeed) : await PreferenceService.getDefaultPlaybackSpeed();
    }
    // savedDurationMs 兜底:让 Slider max 在 prepared 之前就有非 0 值,
    // 视觉上不再"从头加载"——立刻显示"当前位置/总时长"比例。
    // 优先级: ChapterCacheService 实测 > chapter.duration > 同书旧 PlayProgress
    let saved = 0;
    const cachedDurationSec = ChapterCacheService.getInstance().getChapterDuration(targetChapter.id);
    if (cachedDurationSec > 0) {
      saved = cachedDurationSec * 1000;
    } else if (targetChapter.duration && targetChapter.duration > 0) {
      saved = targetChapter.duration * 1000;
    } else {
      const memo = PreferenceService.getProgressSync(targetBook.id);
      if (memo && memo.chapterId === targetChapter.id && memo.durationMs > 0) {
        saved = memo.durationMs;
      }
    }
    this.state.savedDurationMs = saved;
  }

  /**
   * 同步判断目标章节是否走"快路径":
   * - source.type === 'file' / 'rawfile': 已经是本地文件,无需嗅探
   * - source.type === 'url' 且长期下载 / ChapterCacheService 已有文件 / 已解析 URL: 命中
   *
   * 命中时切书过程整体 ~300-600ms 就能 prepared,UI 不必显示 loading 圈,
   * 给用户"瞬间切换"的观感。
   */
  private isFastSwitchPath(book: Book, chapter: Chapter): boolean {
    if (chapter.source.type === 'rawfile') return true;
    if (DownloadService.getInstance().getDownloadedFilePath(book.id, chapter)) return true;
    const cache = ChapterCacheService.getInstance();
    // 关闭预加载后，临时章节缓存不参与切章命中，确保每次切章都重新请求书源接口。
    if (!cache.isPreloadEnabled()) return false;
    if (chapter.source.type === 'file') return true;
    const pageUrl = chapter.originSourceValue || chapter.source.value;
    if (cache.getAudioFilePath(book.id, chapter.id, pageUrl)) return true;
    if (cache.getAudioUrl(chapter.id)) return true;
    return false;
  }

  private async doPlayChapter(book: Book, chapter: Chapter, seekMs: number, forceReload: boolean = false): Promise<void> {
    if (!this.state || !this.context || PlaybackCoordinator.speechActive) return;
    this.stopTick();
    const myGen = ++this.playGen;
    this.playerSourceGeneration = -1;
    this.cancelPreloadStart();
    this.playbackLoadStartedAt = Date.now();
    this.preloadBuffering = false;
    this.cancelLiveRecovery();
    const oldWasLive = this.liveSource || this.state.isLive;
    this.liveSource = false;
    this.state.isLive = false;
    if (this.liveReconnectChapter !== chapter.id) {
      this.liveReconnectChapter = chapter.id;
      this.liveReconnectAttempts = 0;
    }
    ChapterCacheService.getInstance().suspendPreload(forceReload ? '' : chapter.id);
    this.currentAudioHeaders = {};
    this.tracePlayback('chapter-load');
    // 目标已有缓存或正在解析时保留嗅探，切章接手同一请求。
    const fastPath = !forceReload && (this.isFastSwitchPath(book, chapter) ||
      ChapterCacheService.getInstance().getPendingAudioResolve(book, chapter) !== undefined);
    // 快路径不需要 WebView 嗅探，不调 cancelPending——避免把预加载正在跑的嗅探取消掉，
    // 导致后续慢路径章节的 URL 解析也被波及（WebView extractor 串行，cancel 会丢队列中的任务）。
    if (!fastPath) {
      try { getWebViewAudioExtractor().cancelPending(); } catch (_e) { /* ignore */ }
    }
    this.isApplying = true;
    try {
      // 0) 先停旧 player(避免新 URL 嗅探的几秒内旧音频还在响 + 旧 timeUpdate 污染 progressMs)
      // 注意:idle 也要 reset。退后台被系统回收 audio renderer 后,player.state 会停在 idle
      // 但 fdSrc/url 已失效,此时直接 applySource 设 url 不一定能驱动到 prepared,
      // 必须 reset 一次让状态机回到干净 idle。released 状态没法 reset,跳过即可。
      const resetStartedAt = Date.now();
      try {
        const cur = this.player;
        if (cur && cur.state !== 'released') {
          if (oldWasLive) this.detachPlayer(cur);
          else await this.resetPlayerForSwitch(cur);
        }
      } catch (_e) { /* ignore */ }
      finally { this.tracePlaybackDuration('reset', resetStartedAt, myGen); }
      if (myGen !== this.playGen) {
        // 被新 playChapter 抢占，不清 isLoading——新的 doPlayChapter 会自己设
        return;
      }

      // 1) 翻 UI 状态
      this.state.currentBook = book;
      this.state.currentChapter = chapter;
      this.state.progressMs = seekMs;
      this.state.durationMs = 0;
      this.state.isLive = false;
      this.state.isPlaying = false;
      // 切章/切书一律翻 loading:即使 URL 已缓存(快路径),音频仍要缓冲/落盘,
      // 页面若无提示用户会以为卡死。真正出声(prepared→playing)后清掉,
      // 本地文件秒切时只是闪一下,不影响"瞬间切换"观感。
      this.state.isLoading = true;
      // 在解析地址、网络缓冲之前切换卡片，不能等 playing 回调或 15 秒兜底。
      this.syncPlayerCard(true);
      AVSessionService.getInstance().updateMetadata(book, chapter);
      // 早写 PlaybackStore:让正在等待的页面立刻看到"当前书已切换"
      PlaybackStore.getInstance().update(
        book.id, chapter.id,
        this.findChapterIndex(book, chapter),
        chapter.source?.value ?? '', false
      );

      // 2) 解析音频 URL（失败时自动重试一次）
      const maxAttempts: number = 2;
      let audioHeaders: Record<string, string> = {};
      let resolveResult: AudioResolveResult = { headers: {}, success: false };
      let resolved: boolean = false;
      this.lastResolveFailure = '';
      for (let attempt = 0; attempt < maxAttempts; attempt++) {
        resolveResult = await this.resolveAudioUrl(book, chapter, forceReload);
        if (myGen !== this.playGen) {
          return;
        }
        if (resolveResult.success) {
          audioHeaders = resolveResult.headers;
          resolved = true;
          break;
        }
        if (attempt < maxAttempts - 1) {
          hilog.warn(DOMAIN, TAG, 'resolveAudioUrl failed (attempt %d/%d), retrying after 800ms',
            attempt + 1, maxAttempts);
          await new Promise<void>((res) => setTimeout(res, 800));
        }
      }
      if (!resolved) {
        hilog.warn(DOMAIN, TAG, 'resolveAudioUrl failed after %d attempts, aborting playback', maxAttempts);
        this.state.isLoading = false;
        this.state.isPlaying = false;
        const message = this.lastResolveFailure.length > 0
          ? this.lastResolveFailure : '无法获取音频地址，请检查网络或稍后重试';
        this.emitPlayFailed(book.id, chapter.id, message);
        return;
      }
      this.syncCastMediaSource(book, chapter);

      const isLive = chapter.source.type === 'url'
        ? await LiveAudioService.isLive(chapter.source.value, audioHeaders) : false;
      if (myGen !== this.playGen) return;
      this.liveSource = isLive;
      this.state.isLive = isLive;

      // 3) 装载
      const p = await this.ensurePlayer();
      if (myGen !== this.playGen) {
        return;
      }
      const startMs = isLive ? 0 : Math.max(seekMs, Math.max(0, book.skipIntro ?? 0) * 1000);
      this.pendingSeek = startMs;
      this.resumeTargetMs = startMs;
      this.currentAudioHeaders = audioHeaders;
      const loaded = await this.applySource(p, chapter.source, audioHeaders, myGen);
      if (!loaded) {
        // 装载失败(缓存文件被系统清理/URL 失效等),立即清 loading 并提示,
        // 避免 UI 一直转圈。下个 applySource 的调用会走 resolveAudioUrl 重新解析。
        hilog.error(DOMAIN, TAG, 'applySource returned false, aborting playback');
        if (myGen === this.playGen && this.state) {
          this.state.isLoading = false;
          this.state.isPlaying = false;
          this.emitPlayFailed(book.id, chapter.id, '音频源不可用，请点击重试');
        }
        return;
      }
    } catch (err) {
      if (myGen === this.playGen && this.state) {
        this.state.isLoading = false;
        this.state.isPlaying = false;
        const e = err as Error;
        const message = e?.message?.includes('超时') ? '音频地址获取超时，请点击重试' : '播放失败，请点击重试';
        this.emitPlayFailed(book.id, chapter.id, message);
      }
      throw err as Error;
    } finally {
      if (myGen === this.playGen) {
        this.isApplying = false;
        this.stopBackgroundIfIdle();
      }
    }
  }

  /**
   * 把章节的 source.value（可能是页面 URL）解析成真实音频 URL。
   * - rawfile / file 类型：跳过
   * - 已经是直接音频 URL（缓存过 / 上次解析过）：跳过
   * - URL 类型 + 在线书源：调用 BookSourceService.getAudioUrl 解析
   *
   * 重要：如果上一次播放后 source.value 已经是临时签名 URL（如 api.aikeu.com 带 sign），
   * 重启后这条 URL 已过期，必须用 originSourceValue 里保存的章节页 URL 重新解析。
   */
  private isFileUsable(path: string): boolean {
    try {
      return fileIo.statSync(path).size > 0;
    } catch (_e) {
      return false;
    }
  }

  private async resolveAudioUrl(book: Book, chapter: Chapter, forceReload: boolean = false): Promise<AudioResolveResult> {
    const generation = this.playGen;
    const resolveStartedAt = Date.now();
    const cache = ChapterCacheService.getInstance();
    if (chapter.source.type !== 'url') {
      if (chapter.source.type === 'rawfile') {
        this.tracePlaybackDuration('resolve-path', resolveStartedAt, generation, 'rawfile');
        const r: AudioResolveResult = { headers: {}, success: true };
        return r;
      }
      // file 类型:先验证文件真实存在。cacheDir 里的临时缓存可能被系统清理/LRU 淘汰,
      // 持久化的旧 file 路径直接喂给 AVPlayer 会 open 失败且 UI 卡在 loading。
      const downloadedPath = DownloadService.getInstance().getDownloadedFilePath(book.id, chapter);
      if (this.isFileUsable(chapter.source.value)
        && (downloadedPath || cache.isPreloadEnabled())) {
        this.tracePlaybackDuration('resolve-path', resolveStartedAt, generation, downloadedPath ? 'downloaded-file' : 'local-file');
        const r: AudioResolveResult = { headers: {}, success: true };
        return r;
      }
      // 文件已丢失(或关闭预加载):回退到章节页 URL 重新解析
      if (chapter.originSourceValue) {
        try { cache.clearChapter(chapter.id); } catch (_e) { /* ignore */ }
        chapter.source = { type: 'url', value: chapter.originSourceValue };
      } else {
        hilog.error(DOMAIN, TAG, 'file source missing and no originSourceValue: %{public}s',
          chapter.source.value);
        this.lastResolveFailure = '本地音频文件已丢失，且没有可重新获取的地址';
        const r: AudioResolveResult = { headers: {}, success: false };
        return r;
      }
    }
    if (!book.sourceUrl) {
      this.lastResolveFailure = '该书籍缺少可用的内容来源';
      const r: AudioResolveResult = { headers: {}, success: false };
      return r;
    }
    if (!chapter.originSourceValue) {
      chapter.originSourceValue = chapter.source.value;
    }
    const downloadedPath = DownloadService.getInstance().getDownloadedFilePath(book.id, chapter);
    if (!forceReload && downloadedPath && this.isFileUsable(downloadedPath)) {
      this.tracePlaybackDuration('resolve-path', resolveStartedAt, generation, 'downloaded-file');
      chapter.source = { type: 'file', value: downloadedPath };
      const r: AudioResolveResult = { headers: {}, success: true };
      return r;
    }
    if (!forceReload && cache.isPreloadEnabled()) {
      const filePath = await cache.waitForAudioFile(book, chapter);
      if (filePath && this.isFileUsable(filePath)) {
        this.tracePlaybackDuration('resolve-path', resolveStartedAt, generation, 'preload-file');
        hilog.info(DOMAIN, TAG, 'preload file hit chapter=%{public}s', chapter.id);
        chapter.source = { type: 'file', value: filePath };
        const r: AudioResolveResult = { headers: {}, success: true };
        return r;
      }
      const pendingResolve = cache.getPendingAudioResolve(book, chapter);
      if (pendingResolve !== undefined) {
        const pendingStartedAt = Date.now();
        try { await pendingResolve; }
        finally { this.tracePlaybackDuration('pending-preload-resolve', pendingStartedAt, generation, 'pending'); }
        if (generation !== this.playGen) {
          const cancelled: AudioResolveResult = { headers: {}, success: false };
          return cancelled;
        }
        hilog.info(DOMAIN, TAG, 'preload resolve reused chapter=%{public}s', chapter.id);
      }
      const cachedUrl = cache.isPreloadEnabled() ? cache.getAudioUrl(chapter.id) : null;
      if (cachedUrl) {
        this.tracePlaybackDuration('resolve-path', resolveStartedAt, generation, 'preload-url');
        chapter.source = { type: 'url', value: cachedUrl };
        const cachedHeaders = cache.getAudioHeaders(chapter.id);
        const r: AudioResolveResult = { headers: cachedHeaders, success: true };
        return r;
      }
    }
    this.tracePlaybackDuration('resolve-path', resolveStartedAt, generation, 'network');
    try {
      const source = await SourceDataService.getSourceByUrl(book.sourceUrl);
      if (!source) {
        this.lastResolveFailure = '该内容来源已不可用，请重新导入后重试';
        const r: AudioResolveResult = { headers: {}, success: false };
        return r;
      }
      const chapterStartedAt = Date.now();
      try { await BookSourceService.prepareAudioChapter(source, book, chapter); }
      finally { this.tracePlaybackDuration('prepareAudioChapter', chapterStartedAt, generation); }
      const pageUrl = chapter.originSourceValue || chapter.source.value;
      const requestStartedAt = Date.now();
      let requestInfo: AudioRequestInfo;
      try {
        requestInfo = await this.resolveAudioRequestWithTimeout(source, pageUrl, book.variables,
          ChapterRuleContext.create(chapter.title, chapter.index - 1, chapter.variables));
      } finally { this.tracePlaybackDuration('resolveAudioRequest', requestStartedAt, generation); }
      const audioUrl = requestInfo.url;
      // 解析失败时书源层会原样回传章节页 URL（如 tingyou://play/...），
      // 必须校验后才算成功，否则假地址会被装进 AVPlayer 并报“音频源不可用”，
      // 还会跳过 doPlayChapter 的解析重试。
      if (DownloadPolicy.isResolvedAudioUrl(pageUrl, audioUrl, requestInfo.resolved)) {
        // 前台首次解析也进入共享缓存，快速回听无需再次请求书源。
        if (!this.state?.isLive) cache.rememberAudioRequest(chapter.id, audioUrl, requestInfo.headers);
        chapter.source = { type: 'url', value: audioUrl };
        const r: AudioResolveResult = { headers: requestInfo.headers, success: true };
        return r;
      }
      this.lastResolveFailure = '书源未返回可播放的音频地址';
      const r: AudioResolveResult = { headers: {}, success: false };
      return r;
    } catch (err) {
      const e = err as Error;
      this.lastResolveFailure = e && e.message ? e.message : '音频地址解析失败';
      hilog.error(DOMAIN, TAG, 'resolveAudioUrl failed: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
      const r: AudioResolveResult = { headers: {}, success: false };
      return r;
    }
  }

  private async resolveAudioRequestWithTimeout(source: BookSource, pageUrl: string,
    variables?: Record<string, string>, chapterVariables?: Record<string, string>): Promise<AudioRequestInfo> {
    let timerId: number = -1;
    const generation = this.playGen;
    const request = new LightSourceRequest(2);
    request.cancelCheck = (): boolean => generation !== this.playGen;
    const timeoutMs = BookSourceService.getAudioResolveTimeoutMs(source, AUDIO_RESOLVE_TIMEOUT_MS);
    const timeout = new Promise<AudioRequestInfo>((_resolve, reject) => {
      timerId = setTimeout((): void => {
        request.cancel();
        reject(new Error('音频地址获取超时'));
      }, timeoutMs);
    });
    try {
      return await Promise.race([
        BookSourceService.resolveAudioRequest(source, pageUrl, variables, chapterVariables, request), timeout
      ]);
    } finally {
      request.cancel();
      if (timerId >= 0) clearTimeout(timerId);
    }
  }

  private isHttpUrl(value: string): boolean {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  private syncCastMediaSource(book: Book, chapter: Chapter): void {
    let url = '';
    if (chapter.source.type === 'url' && this.isHttpUrl(chapter.source.value)
      && chapter.source.value !== chapter.originSourceValue) {
      url = chapter.source.value;
    }
    if (!url) url = ChapterCacheService.getInstance().getAudioUrl(chapter.id) ?? '';
    if (this.isHttpUrl(url)) {
      AVSessionService.getInstance().updateCastMediaSource(book, chapter, url);
    }
  }

  private async resolveCastUrl(book: Book, chapter: Chapter): Promise<string> {
    const cachedUrl = ChapterCacheService.getInstance().getAudioUrl(chapter.id) ?? '';
    if (this.isHttpUrl(cachedUrl)) return cachedUrl;
    if (!book.sourceUrl) return '';
    const pageUrl = chapter.originSourceValue || chapter.source.value;
    if (pageUrl.length === 0) return '';
    try {
      const source = await SourceDataService.getSourceByUrl(book.sourceUrl);
      if (!source) return '';
      const requestInfo = await this.resolveAudioRequestWithTimeout(
        source, pageUrl, book.variables, ChapterRuleContext.create(chapter.title, chapter.index - 1, chapter.variables));
      return this.isHttpUrl(requestInfo.url) ? requestInfo.url : '';
    } catch (err) {
      const error = err as Error;
      hilog.warn(DOMAIN, TAG, 'resolveCastUrl failed: %{public}s',
        error?.message ?? JSON.stringify(err));
      return '';
    }
  }

  private emitPlayFailed(bookId: string, chapterId: string, message: string): void {
    emitter.emit(EVT_AUDIO_PLAY_FAILED, {
      data: { bookId, chapterId, message } as AudioPlayFailedPayload
    });
  }

  /**
   * 把 src 装载进 AVPlayer。成功返回 true；失败返回 false（不主动向外抛，
   * 由调用方 decide 是否重试/报错）。特别是：
   * - file 类型：缓存文件可能已被系统回收/过期删除，打开失败返回 false，
   *   调用方可借此清掉失效缓存并回退用 URL 重新解析下载，而不是卡在 loading。
   */
  private async applySource(p: media.AVPlayer, src: AudioSource,
    headers: Record<string, string> = {}, generation: number = this.playGen): Promise<boolean> {
    if (!this.context || this.player !== p || generation !== this.playGen) return false;

    this.closeCurrentFile();

    try {
      if (src.type === 'rawfile') {
        const fd = await this.context.resourceManager.getRawFd(src.value);
        if (this.player !== p || generation !== this.playGen) return false;
        this.playerSourceGeneration = generation;
        p.fdSrc = { fd: fd.fd, offset: fd.offset, length: fd.length };
      } else if (src.type === 'url') {
        if (!src.value || src.value.trim().length === 0) {
          hilog.error(DOMAIN, TAG, 'Empty URL provided');
          return false;
        }
        if (!src.value.startsWith('http://') && !src.value.startsWith('https://')) {
          hilog.error(DOMAIN, TAG, 'Invalid URL scheme: %{public}s', src.value.substring(0, 50));
          return false;
        }
        const mediaSource = media.createMediaSourceWithUrl(src.value, headers);
        // 使用默认流式读取：系统离线缓存会将首个小读取扩为 4 MiB 分块，
        // 等整块下载后才交付数据，拖慢首播。离线能力由 ChapterCacheService 和下载服务提供。
        const mediaStartedAt = Date.now();
        const mediaGeneration = generation;
        this.playerSourceGeneration = generation;
        try { await p.setMediaSource(mediaSource); }
        finally { this.tracePlaybackDuration('setMediaSource', mediaStartedAt, mediaGeneration); }
      } else if (src.type === 'file') {
        // 沙箱文件用 fdSrc 播放（AVPlayer 对沙箱绝对路径不接受 file:// 形式）。
        // 缓存文件可能已被系统回收/过期删除，打开失败返回 false，不抛异常。
        ChapterCacheService.getInstance().setPlayingFile(src.value);
        const f = await fileIo.open(src.value, fileIo.OpenMode.READ_ONLY);
        if (this.player !== p || generation !== this.playGen) {
          await fileIo.close(f);
          return false;
        }
        this.currentFile = f;
        const stat = await fileIo.stat(f.fd);
        if (this.player !== p || generation !== this.playGen) return false;
        this.playerSourceGeneration = generation;
        p.fdSrc = { fd: f.fd, offset: 0, length: stat.size };
      } else {
        return false;
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'applySource failed: %{public}s',
        e && e.message ? e.message : JSON.stringify(err));
      if (this.player === p && generation === this.playGen) this.closeCurrentFile();
      return false;
    }
    return true;
  }

  private closeCurrentFile(): void {
    ChapterCacheService.getInstance().setPlayingFile();
    if (this.currentFile) {
      try {
        fileIo.closeSync(this.currentFile);
      } catch (_e) { /* ignore */ }
      this.currentFile = null;
    }
  }

  private async toggleFavoriteFromSession(): Promise<void> {
    const book = this.state?.currentBook;
    if (!book) return;
    const isFav = await PreferenceService.toggleFavorite(book.id);
    if (isFav) {
      await DataService.upsertCachedBook(book);
    }
    this.syncPlaybackState();
  }

  async toggle(): Promise<void> {
    if (!this.pauseRequested && (this.player?.state === 'playing' || this.state?.isLoading)) {
      await this.pause();
    } else {
      await this.play();
    }
  }

  /** 按 state 中的 currentBook/currentChapter/progressMs 起播续播。url 类型 + 书源会先重解析地址。 */
  async resumeFromState(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const book = this.state.currentBook;
    const chapter = this.state.currentChapter;
    const seekMs = this.state.progressMs;
    // playChapterAndSeek 内部会做 URL 解析，这里不用重复
    await this.playChapterAndSeek(book, chapter, seekMs);
  }

  async seek(ms: number): Promise<void> {
    if (this.state?.isLive) return;
    if (PlaybackCoordinator.speechActive) return;
    this.sleepPausePending = false;
    this.resumeAfterSleepChapter = false;
    this.chapterEndHandled = false;
    this.cancelExternalMediaWatch();
    const p = await this.ensurePlayer();
    // 同步先把 state.progressMs 推到目标位置,避免 UI 滑块回弹
    if (this.state) {
      this.state.progressMs = ms;
    }
    if (p.state === 'completed') {
      // completed 状态下需要先 seek + play 才能继续
      p.seek(ms, media.SeekMode.SEEK_PREV_SYNC);
      await this.playPlayer(p);
    } else {
      p.seek(ms, media.SeekMode.SEEK_PREV_SYNC);
    }
    this.syncPlaybackState();
  }

  async seekBy(deltaMs: number): Promise<void> {
    if (!this.state || !Number.isFinite(deltaMs)) return;
    const currentMs = Math.max(0, this.state.progressMs);
    const maxMs = this.state.durationMs > 0 ? this.state.durationMs : Number.MAX_SAFE_INTEGER;
    const targetMs = Math.min(maxMs, Math.max(0, currentMs + deltaMs));
    await this.seek(targetMs);
  }

  async replayCurrent(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    await this.playChapterAndSeek(this.state.currentBook, this.state.currentChapter, 0);
  }

  setPlayMode(mode: PlayMode): void {
    if (!this.state) return;
    this.state.playMode = mode;
    AVSessionService.getInstance().updateLoopMode(this.toAVSessionLoopMode(mode))
      .catch((_e: Error): void => {});
  }

  private fromAVSessionLoopMode(mode: avSession.LoopMode): PlayMode {
    if (mode === avSession.LoopMode.LOOP_MODE_SINGLE) return PlayMode.SingleLoop;
    if (mode === avSession.LoopMode.LOOP_MODE_LIST) return PlayMode.ListLoop;
    return PlayMode.Sequence;
  }

  private toAVSessionLoopMode(mode: PlayMode): avSession.LoopMode {
    if (mode === PlayMode.SingleLoop) return avSession.LoopMode.LOOP_MODE_SINGLE;
    if (mode === PlayMode.ListLoop) return avSession.LoopMode.LOOP_MODE_LIST;
    return avSession.LoopMode.LOOP_MODE_SEQUENCE;
  }

  /** 归一化倍速:缺省/NaN/Infinity/非正数一律回 1.0,其余 clamp 到 AVPlayer 合法区间 [0.125, 4.0]。
   *  恢复持久化值和 setSpeed 走同一逻辑,防止反序列化出的脏数据被直接喂给 setPlaybackRate。 */
  private normalizeSpeed(speed: number | undefined): number {
    if (speed === undefined || !Number.isFinite(speed) || speed <= 0) return 1.0;
    return Math.min(4.0, Math.max(0.125, speed));
  }

  async setSpeed(speed: number): Promise<void> {
    if (this.state?.isLive) return;
    const p = await this.ensurePlayer();
    // 连续(无级)倍速:用 setPlaybackRate,有效范围 [0.125, 4.0]。
    // 旧实现用 media.PlaybackSpeed 离散枚举,只能 0.75/1/1.25/1.75/2,无法无级调节。
    const rate = this.normalizeSpeed(speed);
    try {
      p.setPlaybackRate(rate);
    } catch (e) {
      // setPlaybackRate 仅在 prepared/playing/paused/completed 合法,其它状态会抛异常;
      // 忽略即可,prepared 时会在 stateChange 里重新应用 state.speed。
      hilog.warn(DOMAIN, TAG, 'setPlaybackRate failed: %{public}s', JSON.stringify(e));
    }
    if (this.state) this.state.speed = rate;
    this.syncPlaybackState();
    // 立即落盘该书倍速:slider 松手才调用,频率低;避免「改完没暂停就杀进程」丢记忆
    try { await this.persistHistory(); } catch (_e) { /* ignore */ }
  }

  private loadSleepPreferences(): Promise<void> {
    if (this.sleepPreferencesReady !== null) return this.sleepPreferencesReady;
    this.sleepPreferencesReady = this.restoreSleepPreferences();
    return this.sleepPreferencesReady;
  }

  private async restoreSleepPreferences(): Promise<void> {
    try {
      const enabled = await PreferenceService.getAutoSleepEnabled();
      const minutes = await PreferenceService.getLastSleepMinutes();
      const mode = await PreferenceService.getLastSleepMode();
      const chapters = await PreferenceService.getLastSleepChapters();
      if (this.state) {
        this.state.autoSleepEnabled = enabled;
        this.state.lastSleepMinutes = minutes;
        this.state.lastSleepMode = mode === SleepMode.Chapters ? SleepMode.Chapters : SleepMode.Duration;
        this.state.lastSleepChapters = chapters;
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'restore sleep settings failed: %{public}s', String(error));
    }
  }

  async setAutoSleepEnabled(enabled: boolean): Promise<void> {
    await this.loadSleepPreferences();
    await PreferenceService.setAutoSleepEnabled(enabled);
    if (!this.state) return;
    this.state.autoSleepEnabled = enabled;
    if (enabled && this.state.isPlaying) {
      this.autoSleepRequested = true;
      this.startAutoSleepIfNeeded();
    }
  }

  private startAutoSleepIfNeeded(): void {
    if (!this.autoSleepRequested) return;
    this.autoSleepRequested = false;
    if (!this.state?.autoSleepEnabled || this.state.sleepMode !== SleepMode.Off) return;
    if (this.state.lastSleepMode === SleepMode.Chapters) {
      const count = Math.min(this.state.lastSleepChapters, this.getAvailableSleepChapters());
      // 当前书剩余不足时只播放剩余章节，不覆盖用户记住的原始章数。
      if (count > 0) this.setSleepChapters(count, false);
    } else {
      this.setSleepTimer(this.state.lastSleepMinutes);
    }
  }

  setSleepTimer(minutes: number, smartStop: boolean = false, fadeOut: boolean = false): boolean {
    if (!this.state) return false;
    if (minutes === 0) {
      this.cancelSleepTimer();
      return true;
    }
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 1440) return false;
    this.cancelSleepTimer();
    this.state.sleepMode = SleepMode.Duration;
    this.state.sleepMinutes = minutes;
    this.state.lastSleepMode = SleepMode.Duration;
    this.state.lastSleepMinutes = minutes;
    PreferenceService.setLastSleepMinutes(minutes).catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'save sleep duration failed: %{public}s', error.message);
    });
    this.state.sleepSmartStop = smartStop;
    this.state.sleepFadeOut = fadeOut;
    this.sleepEndTime = Date.now() + minutes * 60 * 1000;
    this.state.sleepRemainingMs = minutes * 60 * 1000;
    this.sleepTimer = setInterval(() => this.updateSleepTimer(), 1000);
    return true;
  }

  getAvailableSleepChapters(): number {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return 0;
    const book = this.state.currentBook;
    const index = this.findChapterIndex(book, this.state.currentChapter);
    return index < 0 ? 0 : Math.min(999, book.chapters.length - index);
  }

  setSleepChapters(count: number, remember: boolean = true): boolean {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return false;
    const available = this.getAvailableSleepChapters();
    if (!Number.isInteger(count) || count < 1 || count > available) return false;
    const book = this.state.currentBook;
    const index = this.findChapterIndex(book, this.state.currentChapter);
    this.cancelSleepTimer();
    this.state.sleepMode = SleepMode.Chapters;
    if (remember) {
      this.state.lastSleepMode = SleepMode.Chapters;
      this.state.lastSleepChapters = count;
      PreferenceService.setLastSleepChapters(count).catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'save sleep chapters failed: %{public}s', error.message);
      });
    }
    this.state.sleepChapterCount = count;
    this.state.sleepChaptersRemaining = count;
    this.state.sleepTargetTitle = book.chapters[index + count - 1].title;
    return true;
  }

  /** 修改智能停止选项不重置已走过的倒计时。 */
  setSleepSmartStop(enabled: boolean): void {
    if (!this.state || this.state.sleepMode !== SleepMode.Duration) return;
    this.state.sleepSmartStop = enabled;
    if (!enabled && this.state.sleepWaitingForChapter) this.finishSleep(false);
  }

  private updateSleepTimer(atChapterEnd: boolean = false): void {
    if (!this.state || this.state.sleepMode !== SleepMode.Duration || this.state.sleepWaitingForChapter) return;
    const remaining = Math.max(0, this.sleepEndTime - Date.now());
    this.state.sleepRemainingMs = remaining;
    if (remaining > 0) return;
    if (atChapterEnd) {
      this.finishSleep(true);
      return;
    }
    const chapterRemaining = this.state.durationMs - this.state.progressMs;
    if (this.state.sleepSmartStop && this.player?.state === 'playing'
      && !this.state.isLoading && chapterRemaining > 0 && chapterRemaining <= 10 * 60 * 1000) {
      this.state.sleepWaitingForChapter = true;
      return;
    }
    this.finishSleep(false);
  }

  cancelSleepTimer(): void {
    this.autoSleepRequested = false;
    if (this.sleepTimer >= 0) {
      clearInterval(this.sleepTimer);
      this.sleepTimer = -1;
    }
    this.sleepEndTime = 0;
    if (!this.state) return;
    this.state.sleepMode = SleepMode.Off;
    this.state.sleepMinutes = 0;
    this.state.sleepRemainingMs = 0;
    this.state.sleepChapterCount = 0;
    this.state.sleepChaptersRemaining = 0;
    this.state.sleepTargetTitle = '';
    this.state.sleepWaitingForChapter = false;
    this.state.sleepSmartStop = false;
    this.state.sleepFadeOut = false;
  }

  private prepareSleepForPlayback(book: Book, chapter: Chapter, automatic: boolean): void {
    if (!this.state) return;
    if (!automatic) {
      this.pauseRequested = false;
      this.pauseSource = 'none';
      BackgroundTaskService.resumeAfterUserAction();
    }
    this.pausedByFocus = false;
    const changed = this.state.currentBook?.id !== book.id || this.state.currentChapter?.id !== chapter.id;
    if (!automatic && changed && (this.state.sleepMode === SleepMode.Chapters || this.state.sleepWaitingForChapter)) {
      this.cancelSleepTimer();
      emitter.emit(EVT_SLEEP_CANCELLED, {});
    }
    this.sleepPausePending = false;
    this.resumeAfterSleepChapter = false;
    if (!automatic) this.autoSleepRequested = true;
  }

  /** 自然结束与跳过片尾共用入口，一章只能结算一次，先停止再决定是否续播。 */
  private handleChapterEnd(): void {
    this.tracePlayback('chapter-end');
    if (!this.state || this.state.isLoading || this.isApplying || this.chapterEndHandled || this.pauseRequested) return;
    this.chapterEndHandled = true;
    this.updateSleepTimer(true);
    if (this.sleepPausePending) return;
    if (this.state.sleepWaitingForChapter) {
      this.finishSleep(true);
      return;
    }
    if (this.state.sleepMode === SleepMode.Chapters) {
      this.state.sleepChaptersRemaining = Math.max(0, this.state.sleepChaptersRemaining - 1);
      if (this.state.sleepChaptersRemaining === 0) {
        this.finishSleep(true);
        return;
      }
    }
    this.autoPlayNext().catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'Automatic chapter continuation failed: %{public}s', error.message);
    }).finally((): void => { this.stopBackgroundIfIdle(); });
  }

  private stopBackgroundIfIdle(): void {
    if (this.context && !this.state?.isPlaying && !this.state?.isLoading && !this.isApplying) {
      BackgroundTaskService.stop(this.context).catch((_error: Error): void => {});
    }
  }

  private finishSleep(atChapterEnd: boolean): void {
    this.tracePlayback(`sleep-stop:chapterEnd=${atChapterEnd}`);
    this.cancelSleepTimer();
    this.sleepPausePending = true;
    this.resumeAfterSleepChapter = atChapterEnd;
    this.pausedByFocus = false;
    this.cancelExternalMediaWatch();
    this.pauseForSleep().catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, 'Sleep stop failed: %{public}s', err.message);
    });
  }

  private async pauseForSleep(): Promise<void> {
    const p = this.player;
    if (this.state) this.state.isPlaying = false;
    if (this.state?.currentBook && this.state.currentChapter) {
      this.triggerPreload(this.state.currentBook, this.state.currentChapter, true);
    }
    if (p?.state === 'playing') await p.pause();
    await this.persistHistory();
    PlaybackStore.getInstance().setPlaying(this.state?.isPlaying ?? false);
    this.syncPlaybackState();
    this.stopBackgroundIfIdle();
  }

  /** 定时停在章尾后，用户再次播放从下一章继续；末章沿用原重播行为。 */
  private async resumeAfterSleep(): Promise<boolean> {
    this.sleepPausePending = false;
    if (!this.resumeAfterSleepChapter || !this.state || !this.state.currentBook || !this.state.currentChapter) return false;
    this.resumeAfterSleepChapter = false;
    const book = this.state.currentBook;
    const index = this.findChapterIndex(book, this.state.currentChapter);
    if (index < 0) return false;
    const nextIndex = index < book.chapters.length - 1 ? index + 1 : index;
    await this.playChapter(book, book.chapters[nextIndex]);
    return true;
  }

  async release(): Promise<void> {
    this.playGen++;
    this.cancelPreloadStart();
    this.playerSourceGeneration = -1;
    ChapterCacheService.getInstance().suspendPreload();
    this.cancelLiveRecovery();
    this.pauseRequested = true;
    this.cancelExternalMediaWatch();
    this.cancelSleepTimer();
    this.stopTick();
    if (this.state) {
      this.state.isPlaying = false;
      this.state.isLoading = false;
      this.state.sleepMinutes = 0;
      this.state.sleepRemainingMs = 0;
      // 退出时先走最小卡片更新包,避免完整快照处理封面/取色拖慢"播放中 -> 暂停"状态翻转。
      try { await WidgetUpdater.optimisticSetPlaying(false); } catch (_e) { /* ignore */ }
      try { await this.persistHistory(); } catch (_e) { /* ignore */ }
      PlaybackStore.getInstance().setPlaying(false);
      await this.syncPlaybackStateNow(true);
    }
    if (this.player) {
      // 先移除事件监听器，避免 release 过程中回调触发对已释放资源的访问
      try { this.player.off('stateChange'); } catch (_e) { /* ignore */ }
      try { this.player.off('timeUpdate'); } catch (_e) { /* ignore */ }
      try { this.player.off('error'); } catch (_e) { /* ignore */ }
      try { this.player.off('audioInterrupt'); } catch (_e) { /* ignore */ }
      try { this.player.off('bufferingUpdate'); } catch (_e) { /* ignore */ }
      try { this.player.off('audioOutputDeviceChangeWithInfo'); } catch (_e) { /* ignore */ }
      await this.player.release();
      this.player = null;
    }
    this.closeCurrentFile();
    if (this.context) {
      await BackgroundTaskService.stop(this.context);
    }
    await AVSessionService.getInstance().destroy();
    // 重置单例：让下次 getInstance() 创建全新实例，避免 readyPromise/playGen 等状态残留
    this.state = null;
    this.context = null;
    this.playGen = 0;
    this.isApplying = false;
    this.pendingSeek = 0;
    this.resumeTargetMs = 0;
    this.pausedByFocus = false;
    this.pausedByExternalMedia = false;
    this.lastProgressWriteAt = 0;
    this.lastPersistAt = 0;
    AudioService.instance = null;
  }

  freezePersist(): void {
    this.frozenPersistGen = ++this.persistGen;
    this.stopTick();
    this.cancelSleepTimer();
    this.cancelExternalMediaWatch();
  }

  unfreezePersist(): void {
    this.frozenPersistGen = -1;
  }

  async stopForClear(): Promise<void> {
    this.playGen++;
    this.cancelPreloadStart();
    this.playerSourceGeneration = -1;
    this.freezePersist();
    if (this.player && this.player.state !== 'idle' && this.player.state !== 'released') {
      try { await this.player.reset(); } catch (_e) { /* ignore */ }
    }
    this.closeCurrentFile();
    if (this.state) {
      this.state.isPlaying = false;
      this.state.isLoading = false;
      this.state.currentBook = null;
      this.state.currentChapter = null;
      this.state.progressMs = 0;
      this.state.durationMs = 0;
      this.state.savedDurationMs = 0;
    }
    PlaybackStore.getInstance().clear();
    await AVSessionService.getInstance().updatePlaybackState(false, 0, 1.0, 0, false).catch(() => {});
    try { await WidgetUpdater.updatePlayerCard(null, true); } catch (_e) { /* ignore */ }
  }

  /** 片尾跳过：检测当前播放位置是否到达片尾区域，到达则自动跳下一章 */
  private checkSkipOutro(ms: number): void {
    if (!this.state || !this.state.currentBook) return;
    const skipOutro = this.state.currentBook.skipOutro ?? 0;
    if (skipOutro <= 0) return;
    const p = this.player;
    if (!p || p.state !== 'playing') return;
    const duration = p.duration;
    if (duration <= 0) return;
    const outroStartMs = duration - skipOutro * 1000;
    if (outroStartMs <= 0) return;
    if (ms >= outroStartMs) {
      this.handleChapterEnd();
    }
  }

  /** 设置完成即调整当前章节；已越过片头时不回退，加载期间更新待跳转位置。 */
  applySkipConfigNow(bookId: string, intro: number, outro: number): void {
    if (!this.state || this.state.currentBook?.id !== bookId) return;
    if (this.state.isLive) return;
    this.state.currentBook.skipIntro = Math.max(0, intro);
    this.state.currentBook.skipOutro = Math.max(0, outro);
    const p = this.player;
    const progress = p && (p.state === 'playing' || p.state === 'paused' || p.state === 'prepared') ?
      Math.max(this.state.progressMs, p.currentTime) : this.state.progressMs;
    const introMs = Math.max(0, intro) * 1000;
    const duration = p && p.duration > 0 ? p.duration : this.state.durationMs;
    if (progress < introMs && (duration <= 0 || introMs < duration)) {
      this.state.progressMs = introMs;
      this.resumeTargetMs = introMs;
      if (p && (p.state === 'playing' || p.state === 'paused' || p.state === 'prepared')) {
        p.seek(introMs, media.SeekMode.SEEK_PREV_SYNC);
        this.syncPlaybackState();
      } else {
        this.pendingSeek = Math.max(this.pendingSeek, introMs);
      }
    }
    this.checkSkipOutro(Math.max(progress, this.state.progressMs));
  }

  private async autoPlayNext(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const mode = this.state.sleepMode === SleepMode.Chapters ? PlayMode.Sequence : this.state.playMode;
    const chapters = this.state.currentBook.chapters;
    const idx = this.findChapterIndex(this.state.currentBook, this.state.currentChapter);
    if (idx < 0) return;

    if (mode === PlayMode.SingleLoop) {
      // 单集循环:重播当前章节
      await this.playChapterAndSeek(this.state.currentBook, chapters[idx], 0, true);
      return;
    }
    const next = idx + 1;
    if (next >= 0 && next < chapters.length) {
      await this.playChapter(this.state.currentBook, chapters[next], true);
      return;
    }
    if (mode === PlayMode.ListLoop && chapters.length > 0) {
      // 列表循环:回到第一集
      await this.playChapter(this.state.currentBook, chapters[0], true);
      return;
    }
    // 片尾跳过也算章末，末章仍在 playing 时必须主动暂停。
    if (this.player?.state === 'playing') {
      this.pause('chapter-end').catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'Final chapter stop failed: %{public}s', error.message);
      });
    }
  }

  /**
   * 起播某章节并 seek 到指定位置。三态决策同 playChapter:
   * - 同书+同章节+player 已 prepared/playing/paused: 仅 seek(seekMs),不 reset
   * - 同书+不同章 / 不同书: await 落盘 → reset → 装载 → prepared 后 seek
   */
  async playChapterAndSeek(book: Book, chapter: Chapter, seekMs: number, automatic: boolean = false,
    forceReload: boolean = false): Promise<void> {
    if (automatic && PlaybackCoordinator.speechActive) return;
    if (!await PlaybackCoordinator.useAudio()) return;
    AVSessionService.getInstance().restoreAudioCallbacks();
    if (!this.state || !this.context) {
      throw new Error('AudioService not bound');
    }
    this.prepareSleepForPlayback(book, chapter, automatic);
    if (!automatic) this.autoRetryChapterId = '';
    this.cancelExternalMediaWatch();
    // 重载必须重新解析；普通续播仍复用当前播放器。
    if (!forceReload && this.canReuseSameChapter(book, chapter)) {
      AVSessionService.getInstance().updateMetadata(book, chapter);
      await this.seekAndPlaySameChapter(seekMs);
      return;
    }
    this.beginChapterLoading();
    try {
      await this.flushBeforeSwitch(book, chapter);
      if (forceReload && book.sourceUrl && chapter.originSourceValue) {
        ChapterCacheService.getInstance().clearChapter(chapter.id, book.id, chapter.originSourceValue);
        chapter.source = { type: 'url', value: chapter.originSourceValue };
      }
      return await this.doPlayChapter(book, chapter, seekMs, forceReload);
    } catch (err) {
      if (this.state) this.state.isLoading = false;
      throw err as Error;
    }
  }

  private beginChapterLoading(): void {
    if (!this.state) return;
    this.cancelLiveRecovery();
    this.state.isLive = false;
    this.state.isLoading = true;
    this.state.isPlaying = false;
  }

  /** 同书+同章节复用:仅 seek + 让它播 */
  private async seekAndPlaySameChapter(seekMs: number): Promise<void> {
    if (!this.state) return;
    const p = this.player;
    if (!p) return;
    if (this.state.isLive) {
      if (p.state === 'paused' || p.state === 'prepared') await this.playPlayer(p);
      return;
    }
    this.state.progressMs = seekMs;
    if (seekMs > 0) {
      this.resumeTargetMs = seekMs;
    }
    try {
      if (p.state === 'playing') {
        p.seek(seekMs, media.SeekMode.SEEK_PREV_SYNC);
      } else if (p.state === 'paused' || p.state === 'prepared' || p.state === 'completed') {
        p.seek(seekMs, media.SeekMode.SEEK_PREV_SYNC);
        this.state.isPlaying = true;
        await this.playPlayer(p);
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'seekAndPlaySameChapter failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  refreshPreload(): void {
    if (this.state?.currentBook && this.state.currentChapter) {
      this.triggerPreload(this.state.currentBook, this.state.currentChapter, !this.state.isPlaying);
    }
  }

  private triggerPreload(book: Book, chapter: Chapter, afterPause: boolean = false): void {
    this.cancelPreloadStart();
    const generation = this.playGen;
    const preload = (): void => {
      if (generation !== this.playGen || !this.state || this.state.isLoading ||
        this.state.currentBook?.id !== book.id || this.state.currentChapter?.id !== chapter.id) return;
      if (!afterPause && (!this.state.isPlaying || this.preloadBuffering)) return;
      if (afterPause && (!this.player || (this.player.state !== 'playing' &&
        this.player.state !== 'paused' && this.player.state !== 'prepared' && this.player.state !== 'completed'))) return;
      if (this.state.isLive) return;
      const cache = ChapterCacheService.getInstance();
      cache.resumePreload();
      const idx = this.findChapterIndex(book, chapter);
      if (idx >= 0) {
        cache.preloadAudioChapters(book, idx,
          chapter.source.type === 'url' ? chapter.source.value : '', this.currentAudioHeaders);
      }
    };
    // 暂停时保留原有限缓存队列；正常播放先留出连续选章窗口，再消耗书源请求额度。
    if (afterPause) {
      try { preload(); } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        hilog.warn(DOMAIN, TAG, 'continue paused preload failed: %{public}s', message);
      }
    }
    else if (!this.state?.isLive) {
      this.preloadStartTimer = setTimeout((): void => {
        this.preloadStartTimer = -1;
        preload();
      }, PRELOAD_STABLE_PLAYBACK_MS);
    }
  }

  private cancelPreloadStart(): void {
    if (this.preloadStartTimer >= 0) clearTimeout(this.preloadStartTimer);
    this.preloadStartTimer = -1;
  }

  private currentAudioHeaders: Record<string, string> = {};

  private findChapterIndex(book: Book, chapter: Chapter | null): number {
    if (!book || !chapter) return -1;
    return DataService.resolveChapterIndex(book, chapter.id, chapter.title);
  }

  /** 公开:供 AVSession / 卡片 callee 调用 */
  async playNext(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const chapters = this.state.currentBook.chapters;
    const idx = this.findChapterIndex(this.state.currentBook, this.state.currentChapter);
    const next = idx + 1;
    if (idx >= 0 && next >= 0 && next < chapters.length) {
      await this.playChapter(this.state.currentBook, chapters[next]);
    } else if (this.state.playMode === PlayMode.ListLoop && chapters.length > 0) {
      await this.playChapter(this.state.currentBook, chapters[0]);
    }
  }

  /** 公开:供 AVSession / 卡片 callee 调用 */
  async playPrevious(): Promise<void> {
    if (!this.state || !this.state.currentBook || !this.state.currentChapter) return;
    const chapters = this.state.currentBook.chapters;
    const idx = this.findChapterIndex(this.state.currentBook, this.state.currentChapter);
    const previous = idx - 1;
    if (idx >= 0 && previous >= 0 && previous < chapters.length) {
      await this.playChapterFromSavedProgress(this.state.currentBook, chapters[previous]);
    }
  }

  /** 朗读抢占时取消仍在解析的旧音源，防止稍后复活。 */
  async suspendForSpeech(): Promise<void> {
    const retainedSource = this.playerSourceGeneration === this.playGen;
    this.playGen++;
    if (retainedSource) this.playerSourceGeneration = this.playGen;
    this.isApplying = false;
    await this.pause('speech');
    if (this.state) this.state.isLoading = false;
  }

  /** 系统播控、耳机和卡片共用的暂停入口，重复指令保持暂停。 */
  async pause(source: string = 'user'): Promise<void> {
    if (this.state?.currentBook && this.state.currentChapter) {
      this.triggerPreload(this.state.currentBook, this.state.currentChapter, true);
    }
    this.cancelLiveRecovery();
    this.pauseSource = source;
    this.tracePlayback('pause-request');
    this.pauseRequested = true;
    this.pausedByFocus = false;
    this.cancelExternalMediaWatch();
    this.stopTick();
    if (this.state) this.state.isPlaying = false;
    PlaybackStore.getInstance().setPlaying(false);
    this.syncPlaybackState();
    try {
      if (this.player?.state === 'playing') await this.player.pause();
      // 装载中的进度由 prepared/后续暂停处理，避免将旧音源位置写入新章节。
      if (!this.state?.isLoading) await this.persistHistory();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'pause failed: %{public}s', JSON.stringify(err));
    } finally {
      // 已由系统暂停的播放器不会再发送 paused，用户暂停仍须释放后台占用。
      this.stopBackgroundIfIdle();
    }
  }

  /** 系统播控、耳机和卡片共用的播放入口；重复 play 不切换为暂停或重载音源。 */
  async play(): Promise<void> {
    this.tracePlayback('play-request');
    BackgroundTaskService.resumeAfterUserAction();
    if (this.player?.state !== 'playing') this.autoSleepRequested = true;
    this.pauseSource = 'none';
    this.pauseRequested = false;
    this.pausedByFocus = false;
    this.cancelExternalMediaWatch();
    await this.loadSleepPreferences();
    if (this.pauseRequested) return;
    if (!await PlaybackCoordinator.useAudio()) return;
    if (this.pauseRequested) return;
    AVSessionService.getInstance().restoreAudioCallbacks();
    if (this.state?.currentBook && this.state.currentChapter) {
      AVSessionService.getInstance().updateMetadata(this.state.currentBook, this.state.currentChapter);
    }
    if (await this.resumeAfterSleep()) return;
    if (PlaybackCoordinator.speechActive || this.pauseRequested || this.isApplying || this.state?.isLoading) return;
    if (this.player?.state === 'released') this.player = null;
    if (!this.player || this.player.state === 'idle' || this.player.state === 'stopped'
      || this.player.state === 'error') {
      if (this.state && this.state.currentBook && this.state.currentChapter) {
        await this.resumeFromState();
      }
      return;
    }
    if (this.player.state === 'paused' || this.player.state === 'prepared') {
      if (this.state) {
        this.state.isPlaying = true;
      }
      try {
        await this.playPlayer(this.player);
      } catch (err) {
        if (this.state) this.state.isPlaying = false;
        this.syncPlaybackState();
        hilog.error(DOMAIN, TAG, 'play failed: %{public}s', JSON.stringify(err));
      }
    } else if (this.player.state === 'completed') {
      this.player.seek(0, media.SeekMode.SEEK_PREV_SYNC);
      if (this.state) {
        this.state.progressMs = 0;
        this.state.isPlaying = true;
      }
      await this.playPlayer(this.player);
    } else if (this.player.state === 'playing') {
      await this.playPlayer(this.player);
    }
  }
}
