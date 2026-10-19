import { PlatformCompat } from '../utils/PlatformCompat';
import lazy { WearableRuntime } from '../service/wearable/WearableRuntime';
import lazy { MedalService } from '../service/MedalService';
import { AVSessionService } from '../service/AVSessionService';
import lazy { TextToSpeechService } from '../service/text/TextToSpeechService';
import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, AppStorageV2 } from '@kit.ArkUI';
import { rpc } from '@kit.IPCKit';
import { BusinessError, emitter } from '@kit.BasicServicesKit';
import { WindowUtils } from '../utils/WindowUtils';
import { PreferenceService } from '../service/PreferenceService';
import lazy { AuthService } from '../service/AuthService';
import lazy { MembershipService } from '../service/MembershipService';
import lazy { AutoBackupService } from '../service/AutoBackupService';
import { AudioService } from '../service/AudioService';
import lazy { WidgetUpdater } from '../service/WidgetUpdater';
import lazy { WidgetPlaybackService } from '../service/WidgetPlaybackService';
import { DataService } from '../service/DataService';
import { SourceTestTaskService } from '../service/rulesource/SourceTestTaskService';
import { ChapterCacheService } from '../service/ChapterCacheService';
import { DownloadService } from '../service/DownloadService';
import { StatsService } from '../service/StatsService';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { configureArkWebSecurity } from '../service/builtin/ArkWebSecurityConfig';
import lazy { CONTINUATION_PAYLOAD_KEY, ContinuationService } from '../service/ContinuationService';
import { LocalRuleSourceRepository } from '../service/rulesource/LocalRuleSourceRepository';
import { LocalRuleTlsTrustStore } from '../service/rulesource/LocalRuleTlsTrustStore';
import { EVT_READER_TYPOGRAPHY_CHANGED } from '../model/TextReading';
import { FileOpenRouting } from '../utils/FileOpenRouting';
import { DiagnosticLogService } from '../service/DiagnosticLogService';

const DOMAIN = 0x0000;
const TAG = 'ListenBook';

/** 卡片 -> EntryAbility 的路由参数,通过 AppStorage + emitter 透传给 Index 页 */
export const KEY_WIDGET_ROUTE = 'widget_route_pending';
export const EVT_WIDGET_ROUTE = 'app.widget.route';

export interface WidgetRoute {
  target: string;
  bookId?: string;
  fileType?: string;
  ts: number;
}

/** call 事件 RPC 返回的占位 Parcelable(必须返回,否则发送方会异常) */
class AckParcelable implements rpc.Parcelable {
  marshalling(messageSequence: rpc.MessageSequence): boolean {
    messageSequence.writeInt(1);
    return true;
  }
  unmarshalling(messageSequence: rpc.MessageSequence): boolean {
    messageSequence.readInt();
    return true;
  }
}

export default class EntryAbility extends UIAbility {
  /** 防止 timeout 路径与正常完成路径重复调度下载恢复 */
  private downloadRecoveryScheduled: boolean = false;
  private pendingContinuationPayload: string = '';
  private startupServicesReady: boolean = false;
  private startupPlaybackPending: boolean = true;
  private isInForeground: boolean = false;
  private createdAt: number = Date.now();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    DiagnosticLogService.init(this.context);
    DiagnosticLogService.info('app.lastExit',
      `reason=${launchParam.lastExitReason}; message=${launchParam.lastExitMessage ?? ''}`);
    if (PlatformCompat.wearable) {
      WearableRuntime.instance.initialize(this.context);
      return;
    }
    // Must run before the first Web component initializes ArkWeb. Do not eagerly initialize the engine here.
    configureArkWebSecurity();
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    WidgetUpdater.setContext(this.context);
    // 章节音频文件缓存的沙箱根目录
    ChapterCacheService.getInstance().setContext(this.context);
    DownloadService.getInstance().setContext(this.context);
    // 书架资源使用持久目录，启动旧缓存迁移
    DataService.setContext(this.context);
    SourceTestTaskService.setContext(this.context);
    this.captureContinuation(want, launchParam);

    // 关键修复:限时初始化,避免后台恢复时阻塞过久导致系统 watchdog 杀进程
    this.initServicesWithTimeout().catch((err: BusinessError) => {
      DiagnosticLogService.failure('app.init', err);
      hilog.error(DOMAIN, TAG, 'Service initialization failed: %{public}s', err?.message ?? JSON.stringify(err));
      // 即使失败也要 markReady,避免 callee 永久等待
      AudioService.getInstance().markReady();
    });

    this.registerCallee();
    this.consumeRouteWant(want);
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    const detail = `level=${level}; uptimeSec=${Math.max(0, Math.floor((Date.now() - this.createdAt) / 1000))}; ` +
      `foreground=${this.isInForeground}`;
    hilog.warn(DOMAIN, TAG, 'Memory pressure: %{public}s', detail);
    DiagnosticLogService.info('app.memory', detail);
  }

  /**
   * 带超时保护的服务初始化。
   * 从状态栏/小组件唤起时,系统期望快速响应。
   * 如果初始化超过 5s,放弃恢复上次播放状态,但仍标记 ready,避免卡死。
   */
  private async initServicesWithTimeout(): Promise<void> {
    const INIT_TIMEOUT_MS = 5000;
    const timeoutPromise = new Promise<void>((_, reject) => {
      setTimeout(() => reject(new Error('Initialization timeout')), INIT_TIMEOUT_MS);
    });

    try {
      await Promise.race([
        this.initServicesCore(),
        timeoutPromise
      ]);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'Init services timeout or failed: %{public}s', e?.message ?? '');
      // 超时可能发生在 bootstrapAudioService 之前，必须 markReady，否则 whenReady 只能靠超时兜底
      AudioService.getInstance().markReady();
      // 超时后仍后台恢复下载，不阻塞冷启动首帧
      this.scheduleDownloadRecovery();
    }
  }

  private async initServicesCore(): Promise<void> {
    const startTime = Date.now();
    hilog.info(DOMAIN, TAG, 'initServicesCore: start');

    AVSessionService.getInstance().init(this.context);
    await PreferenceService.init(this.context);
    await LocalRuleTlsTrustStore.init(this.context).catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'TLS trust store unavailable: %{public}s', error.message);
    });
    hilog.info(DOMAIN, TAG, 'initServicesCore: PreferenceService ready, elapsed=%{public}dms', Date.now() - startTime);

    // 本地规则是旁路能力：后台预热，但不阻塞下载和播放器状态恢复。
    AppStorage.setOrCreate('appCacheDir', this.context.cacheDir);
    AppStorage.setOrCreate('lightSourceSaveLabel', this.context.resourceManager.getStringSync($r('app.string.light_source_save_settings').id));
    AppStorage.setOrCreate('lightSourceLoginLabel', this.context.resourceManager.getStringSync($r('app.string.light_source_web_login').id));
    LocalRuleSourceRepository.init(this.context).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'LocalRuleSourceRepository init failed: %{public}s', JSON.stringify(e));
    });

    try {
      await StatsService.init(this.context);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'StatsService init failed: %{public}s', JSON.stringify(e));
    }
    try {
      await MedalService.instance.init(this.context);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'MedalService init failed: %{public}s', String(error));
    }
    try {
      // 轻量：只读 download_store.json，不做全量文件 stat
      await DownloadService.getInstance().init(this.context);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'DownloadService init failed: %{public}s', JSON.stringify(e));
    }

    this.restoreColorMode();
    const preloadCount = await PreferenceService.getPreloadChapters();
    ChapterCacheService.getInstance().setPreloadCount(preloadCount);
    // 提前把 PlayerState 还原到全局 AppStorage,这样卡片 call 进来时
    // AudioService 已经有 currentBook/Chapter,play() 才能正常工作
    await this.bootstrapAudioService();
    await this.restoreContinuationIfNeeded();
    hilog.info(DOMAIN, TAG, 'initServicesCore: AudioService bootstrapped, elapsed=%{public}dms', Date.now() - startTime);

    // 启动时把 lastPlayed 推一份到卡片,避免冷启动卡片显示空态。
    // 这里(主进程)允许写回 preferences,FormExt 那边的 seed 路径只在内存里用,不写盘
    const snap = await WidgetUpdater.seedAndPersistFromLastPlayed();
    if (snap) {
      await WidgetUpdater.pushSnapshotToCards();
    }

    hilog.info(DOMAIN, TAG, 'initServicesCore: complete, total=%{public}dms', Date.now() - startTime);

    // 下载文件校验 + 中断任务恢复：延后到 ready 之后，避免主线程扫盘卡死
    this.scheduleDownloadRecovery();
    this.startupServicesReady = true;
    if (this.isInForeground) AutoBackupService.instance.setForeground(this.context, true);
    this.tryAutoPlayOnLaunch();
  }

  /** 冷启动且进入前台后仅尝试一次；音频解析不阻塞服务初始化。 */
  private async tryAutoPlayOnLaunch(): Promise<void> {
    if (!this.startupServicesReady || !this.isInForeground || !this.startupPlaybackPending) return;
    try {
      const enabled = await PreferenceService.getAutoPlayOnLaunch();
      // 初始化完成和 onForeground 都可能进入此处，读取偏好后再次判定以去重。
      if (!this.startupPlaybackPending) return;
      this.startupPlaybackPending = false;
      if (!enabled || !this.isInForeground) return;
      const state = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
      if (!state.currentBook || !state.currentChapter || state.isPlaying || state.isLoading) return;
      await AudioService.getInstance().play();
    } catch (error) {
      this.startupPlaybackPending = false;
      hilog.warn(DOMAIN, TAG, 'Auto play on launch failed: %{public}s', String(error));
    }
  }

  /** 延后恢复下载队列，不阻塞冷启动 / 首帧 */
  private scheduleDownloadRecovery(): void {
    if (this.downloadRecoveryScheduled) return;
    this.downloadRecoveryScheduled = true;
    setTimeout((): void => {
      DownloadService.getInstance().restoreDownloads().catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'DownloadService restore failed: %{public}s',
          e?.message ?? JSON.stringify(e));
      });
    }, 300);
  }

  /** 卡片或通知跳转 / 已存活时的拉起,统一在 onNewWant 处理 */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (PlatformCompat.wearable) return;
    this.captureContinuation(want, launchParam);
    this.restoreContinuationIfNeeded().catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'Restore continuation from new want failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
    this.consumeRouteWant(want);
  }

  private captureContinuation(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) return;
    // 跨设备续播由载荷决定播放/暂停状态，不能被启动偏好覆盖。
    this.startupPlaybackPending = false;
    if (!want.parameters) return;
    const payload = want.parameters[CONTINUATION_PAYLOAD_KEY];
    if (typeof payload === 'string') this.pendingContinuationPayload = payload;
  }

  private async restoreContinuationIfNeeded(): Promise<void> {
    if (!this.pendingContinuationPayload) return;
    const payload = this.pendingContinuationPayload;
    this.pendingContinuationPayload = '';
    const state = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
    const bookId = await ContinuationService.restorePayload(this.context, state, payload);
    if (!bookId) return;
    const route: WidgetRoute = { target: 'player', bookId: bookId, ts: Date.now() };
    AppStorage.setOrCreate<WidgetRoute>(KEY_WIDGET_ROUTE, route);
    emitter.emit(EVT_WIDGET_ROUTE, { data: { target: 'player', bookId: bookId, ts: route.ts } });
  }

  async onContinue(wantParam: Record<string, Object>): Promise<AbilityConstant.OnContinueResult> {
    if (PlatformCompat.wearable) return AbilityConstant.OnContinueResult.REJECT;
    try {
      await AudioService.getInstance().flushHistory();
      const state = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
      const payload = ContinuationService.createPayload(state);
      if (payload) wantParam[CONTINUATION_PAYLOAD_KEY] = payload;
      return AbilityConstant.OnContinueResult.AGREE;
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Prepare continuation failed: %{public}s',
        error?.message ?? JSON.stringify(err));
      return AbilityConstant.OnContinueResult.REJECT;
    }
  }

  /**
   * 卡片可能在 PlayerPage 没打开过的情况下就发 call 事件,
   * 此时 AudioService 还没 bind state,play() 就是 no-op。
   * 这里在 EntryAbility 启动时就把 lastPlayed 还原到全局 PlayerState,
   * 并 bind 给 AudioService,让卡片冷启动也能直接续播。
   *
   * 关键:无论成功失败都必须调 markReady(),否则 callee 会永久等待导致卡死。
   */
  private async bootstrapAudioService(): Promise<void> {
    const state = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
    const audioService = AudioService.getInstance();
    audioService.bind(state, this.context);
    audioService.setForeground(this.isInForeground);

    try {
      // 已经有书就不覆盖(用户已在 App 内播放过)
      if (state.currentBook && state.currentChapter) {
        audioService.prewarmBookSource(state.currentBook);
        return;
      }

      // 防御:如果 PreferenceService 初始化超时,getLastPlayed 会抛异常,提前检查避免错误日志泛滥
      // 这种情况下放弃恢复上次播放,但仍让 AudioService 处于可用状态(用户可手动选书)
      try {
        const last = await PreferenceService.getLastPlayed();
        if (!last) {
          return;
        }

        // 防御:getBookById 可能因为文件损坏/过大而失败,加超时保护
        const book = await Promise.race([
          DataService.getBookById(this.context, last.bookId),
          new Promise<undefined>((res) => setTimeout(() => res(undefined), 2000))
        ]);

        if (!book || !book.chapters || book.chapters.length === 0) {
          return;
        }

        const chapterIndex = DataService.resolveChapterIndex(book, last.chapterId, last.chapterTitle);
        const chapter = chapterIndex >= 0 ? book.chapters[chapterIndex] : undefined;
        if (!chapter) {
          return;
        }

        // 独立 KV 为权威:贴回跳过头尾,纠正冷启动缓存书壳可能丢失的 skip
        // (放在赋值前,让 checkSkipOutro / skipIntro 首次起播就用到正确值)
        await PreferenceService.applySkipConfig(book);
        state.currentBook = book;
        state.currentChapter = chapter;
        AVSessionService.getInstance().updateMetadata(book, chapter);
        audioService.prewarmBookSource(book);
        state.progressMs = last.progressMs;
        state.durationMs = last.durationMs ?? 0;
        const progress = await PreferenceService.getProgress(last.bookId);
        state.speed = this.normalizeSpeed(progress?.speed ?? last.speed);
        state.isPlaying = false;
      } catch (prefErr) {
        // PreferenceService 未就绪或读取失败,记录但不影响 AudioService 启动
        const e = prefErr as Error;
        hilog.warn(DOMAIN, TAG, 'bootstrapAudioService: restore lastPlayed failed: %{public}s',
          e?.message ?? JSON.stringify(prefErr));
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'bootstrapAudioService failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    } finally {
      // 不管 lastPlayed 有没有恢复都要 markReady，否则 callee 会一直等
      audioService.markReady();
    }
  }

  private normalizeSpeed(speed: number | undefined): number {
    if (speed === undefined || !Number.isFinite(speed) || speed <= 0) return 1.0;
    return Math.min(4.0, Math.max(0.125, speed));
  }

  /**
   * postCardAction(router) 会把 params 序列化到 want.parameters.params；
   * WantAgent 等普通启动方式则直接把业务字段放在 want.parameters。
   */
  private extractRouteParams(want: Want): Record<string, Object> | undefined {
    const root = want.parameters;
    if (!root) return undefined;
    const nested = root['params'];
    if (typeof nested === 'string') {
      try {
        return JSON.parse(nested) as Record<string, Object>;
      } catch (err) {
        const e = err as Error;
        hilog.warn(DOMAIN, TAG, 'parse widget route params failed: %{public}s',
          e?.message ?? JSON.stringify(err));
      }
    } else if (nested && typeof nested === 'object') {
      return nested as Record<string, Object>;
    }
    return root;
  }

  private consumeRouteWant(want: Want): void {
    const action = want.action ?? '';
    const uri = want.uri ?? '';
    const fileTarget = FileOpenRouting.target(want);
    if (fileTarget.length > 0) {
      // Opening a file must not also resume unrelated audio during cold startup.
      this.startupPlaybackPending = false;
      const route: WidgetRoute = {
        target: fileTarget, bookId: uri, fileType: want.type ?? '', ts: Date.now()
      };
      AppStorage.setOrCreate<WidgetRoute>(KEY_WIDGET_ROUTE, route);
      emitter.emit(EVT_WIDGET_ROUTE, {
        data: { target: route.target, bookId: uri, fileType: route.fileType ?? '', ts: route.ts }
      });
      return;
    }
    if (action === 'readerKitVerify') {
      // ReaderKit 验证功能已禁用（需要 HMS Core ReaderService 依赖）
      hilog.warn(DOMAIN, TAG, 'readerKitVerify action ignored: ReaderKit dependency disabled');
      return;
    }
    const params = this.extractRouteParams(want);
    if (!params) return;
    const from = params['from'] as string | undefined;
    if (from !== 'widget' && from !== 'download_notification') return;
    const target = (params['target'] as string | undefined) ?? 'home';
    const bookId = params['bookId'] as string | undefined;
    const route: WidgetRoute = { target, bookId, ts: Date.now() };
    AppStorage.setOrCreate<WidgetRoute>(KEY_WIDGET_ROUTE, route);
    emitter.emit(EVT_WIDGET_ROUTE, { data: { target, bookId: bookId ?? '', ts: route.ts } });
    hilog.info(DOMAIN, TAG, 'consume route want: from=%{public}s target=%{public}s',
      from, target);
  }

  private registerCallee(): void {
    try {
      this.callee.on('play', (_data: rpc.MessageSequence) => {
        DiagnosticLogService.info('widget.command', 'play');
        this.startupPlaybackPending = false;
        // 乐观更新:立即翻转卡片图标，不等 AVPlayer
        WidgetUpdater.optimisticSetPlaying(true).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'optimistic play push failed: %{public}s', err?.message ?? '');
        });
        WidgetPlaybackService.execute(this.context, 'play').catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'callee play failed: %{public}s', err?.message ?? JSON.stringify(err));
        });
        return new AckParcelable();
      });
      this.callee.on('pause', (_data: rpc.MessageSequence) => {
        DiagnosticLogService.info('widget.command', 'pause');
        this.startupPlaybackPending = false;
        // 乐观更新:立即翻转卡片图标，不等 AVPlayer
        WidgetUpdater.optimisticSetPlaying(false).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'optimistic pause push failed: %{public}s', err?.message ?? '');
        });
        WidgetPlaybackService.execute(this.context, 'pause').catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'callee pause failed: %{public}s', err?.message ?? JSON.stringify(err));
        });
        return new AckParcelable();
      });
      this.callee.on('next', (_data: rpc.MessageSequence) => {
        DiagnosticLogService.info('widget.command', 'next');
        this.startupPlaybackPending = false;
        WidgetPlaybackService.execute(this.context, 'next').catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'callee next failed: %{public}s', err?.message ?? JSON.stringify(err));
        });
        return new AckParcelable();
      });
      this.callee.on('prev', (_data: rpc.MessageSequence) => {
        DiagnosticLogService.info('widget.command', 'previous');
        this.startupPlaybackPending = false;
        WidgetPlaybackService.execute(this.context, 'prev').catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'callee prev failed: %{public}s', err?.message ?? JSON.stringify(err));
        });
        return new AckParcelable();
      });
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'registerCallee failed: code=%{public}d msg=%{public}s',
        e?.code ?? 0, e?.message ?? '');
    }
  }

  private async restoreColorMode(): Promise<void> {
    const mode = await PreferenceService.getColorMode();
    if (mode !== ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
      try {
        this.context.getApplicationContext().setColorMode(mode);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Restore colorMode failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  async onDestroy(): Promise<void> {
    DiagnosticLogService.info('app.destroy', `foreground=${this.isInForeground}`);
    if (PlatformCompat.wearable) {
      await WearableRuntime.instance.destroy();
      return;
    }
    AutoBackupService.instance.setForeground(this.context, false);
    TextToSpeechService.getInstance().stop();
    this.isInForeground = false;
    this.startupPlaybackPending = false;
    try {
      this.callee.off('play');
      this.callee.off('pause');
      this.callee.off('next');
      this.callee.off('prev');
    } catch (_e) { /* ignore */ }
    try {
      await AudioService.getInstance().release();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'AudioService release failed: %{public}s',
        (err as Error)?.message ?? JSON.stringify(err));
    }
    try {
      await StatsService.flush();
      await MedalService.instance.flush();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'StatsService flush failed: %{public}s', String(error));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.loadMainWindow(windowStage).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'Main window load failed: %{public}s', JSON.stringify(err));
    });
  }

  onWindowStageRestore(windowStage: window.WindowStage): void {
    this.loadMainWindow(windowStage).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'Restored window load failed: %{public}s', JSON.stringify(err));
    });
  }

  private async loadMainWindow(windowStage: window.WindowStage): Promise<void> {
    if (PlatformCompat.wearable) {
      await windowStage.loadContent('pages/WearablePage');
      return;
    }
    try {
      await WindowUtils.setupImmersive(windowStage, this.context.config.colorMode);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Immersive setup failed: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      WindowUtils.refreshAvoidArea();
    });
  }

  /** 系统深浅色切换时,同步状态栏字色,避免深色模式下黑字看不见 */
  onConfigurationUpdate(newConfig: Configuration): void {
    if (PlatformCompat.wearable) return;
    if (newConfig.colorMode !== undefined) {
      WindowUtils.updateColorMode(newConfig.colorMode);
    }
    if (newConfig.fontId !== undefined || newConfig.fontSizeScale !== undefined ||
      newConfig.fontWeightScale !== undefined) {
      emitter.emit(EVT_READER_TYPOGRAPHY_CHANGED);
    }
  }

  onWindowStageDestroy(): void {
    if (PlatformCompat.wearable) return;
    WindowUtils.releaseWindow();
  }

  /**
   * 退后台时立即把进度落盘:鸿蒙官方建议在 onBackground 主动 flush,
   * 避免被系统强杀前丢掉最近 5s tick 之间的进度。
   */
  async onBackground(): Promise<void> {
    this.isInForeground = false;
    if (PlatformCompat.wearable) {
      await WearableRuntime.instance.background();
      return;
    }
    AutoBackupService.instance.setForeground(this.context, false);
    emitter.emit('app.reader.background');
    AudioService.getInstance().setForeground(false);
    TextToSpeechService.getInstance().setForeground(false);
    MembershipService.instance.background();
    this.startupPlaybackPending = false;
    try {
      await AudioService.getInstance().flushHistory();
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'onBackground flushHistory failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
    try {
      await StatsService.flush();
      await MedalService.instance.flush();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'onBackground stats flush failed: %{public}s', String(error));
    }
    // 退后台/息屏前再确认一次：若仍有下载队列，维持 dataTransfer 长时任务
    try {
      await DownloadService.getInstance().onAppBackground();
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'onBackground download keep-alive failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  /**
   * 回前台时校准 AVPlayer 健康度。
   * 退后台 + paused 后,系统可能在 1~2s 内回收 audio renderer,把 player 带到 idle
   * 但 fdSrc/url 已失效——再点播放就只能干等。这里主动 reset 到干净 idle,
   * 让用户点 ▶ 时 doPlayChapter 能走完整的 reset → applySource 路径。
   *
   * 关键:从状态栏/小组件唤起时 onForeground 可能比 onCreate 的异步初始化早执行,
   * 此时 AudioService 还没 bind,必须先 whenReady 再调 ensureHealthy,
   * 否则会访问到未初始化的 player 触发崩溃。
   */
  async onForeground(): Promise<void> {
    this.isInForeground = true;
    if (PlatformCompat.wearable) {
      await WearableRuntime.instance.foreground(this.context);
      return;
    }
    // 系统颜色可能在后台改变，阅读器独立跟随系统时也需要重新取值。
    if (this.context.config.colorMode !== undefined) WindowUtils.updateColorMode(this.context.config.colorMode);
    emitter.emit(EVT_READER_TYPOGRAPHY_CHANGED);
    AudioService.getInstance().setForeground(true);
    emitter.emit('app.reader.foreground');
    TextToSpeechService.getInstance().setForeground(true);
    // 不阻塞前台恢复；已保存的账号需重新核对系统登录状态。
    AuthService.instance.restore(this.context);
    MembershipService.instance.foreground(this.context);
    if (this.startupServicesReady) AutoBackupService.instance.setForeground(this.context, true);
    WindowUtils.refreshAvoidArea();
    try {
      // 等待 bootstrapAudioService 完成(带超时保护,避免初始化卡死时永久阻塞前台回调)
      // 超时设为 5 秒,与 onCreate 的总超时时间对齐,避免初始化刚好超时时这里也超时
      await AudioService.getInstance().whenReady(5000);
      await AudioService.getInstance().ensureHealthy();
      this.tryAutoPlayOnLaunch();
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'onForeground ensureHealthy failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }
}
