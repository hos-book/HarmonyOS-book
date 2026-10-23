import { SourceCoverService } from './SourceCoverService';
import { LocalBookCoverService } from './LocalBookCoverService';
import { PlaybackCoordinator } from './PlaybackCoordinator';
import { avSession } from '@kit.AVSessionKit';
import { PlatformCompat } from '../utils/PlatformCompat';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book, Chapter } from '../model/Book';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_AVSession';
const MAX_COVER_CACHE_SIZE: number = 8;
const MAX_COVER_BYTES: number = 4 * 1024 * 1024;
const MEDIA_COVER_PLACEHOLDER: string = 'avsession://cover-placeholder';

export interface AVSessionCallbacks {
  onPlay: () => void;
  onPause: () => void;
  onPlayNext: () => void;
  onPlayPrevious: () => void;
  onFastForward: (ms: number) => void;
  onRewind: (ms: number) => void;
  onSeek: (ms: number) => void;
  onSetSpeed: (speed: number) => void;
  onSetLoopMode: (mode: avSession.LoopMode) => void;
  onCollection: () => void;
  onCastConnected: () => void;
}

const REWIND_INTERVAL_MS: number = 10000;
const FAST_FORWARD_INTERVAL_MS: number = 30000;
const SUPPORTED_PLAY_SPEEDS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];
const SUPPORTED_LOOP_MODES: avSession.LoopMode[] = [
  avSession.LoopMode.LOOP_MODE_SEQUENCE,
  avSession.LoopMode.LOOP_MODE_LIST,
  avSession.LoopMode.LOOP_MODE_SINGLE
];
const MEDIA_CENTER_CONTROLS: avSession.AVMediaCenterControlType[] = [
  'setSpeed',
  'playPrevious',
  'playNext',
  'toggleFavorite'
];

export class AVSessionService {
  private static instance: AVSessionService | null = null;
  private session: avSession.AVSession | null = null;
  private context: common.UIAbilityContext | null = null;
  private coverCache: Map<string, image.PixelMap> = new Map();
  private coverLoads: Map<string, Promise<image.PixelMap | null>> = new Map<string, Promise<image.PixelMap | null>>();
  private coverGeneration: number = 0;
  private initPromise: Promise<void> | null = null;
  private currentBook: Book | null = null;
  private currentChapter: Chapter | null = null;
  private currentMediaImage: string | image.PixelMap | undefined;
  private metadataSerial: number = 0;
  private currentCastUrl: string = '';
  private currentProgressMs: number = 0;
  private currentDurationMs: number = 0;
  private castController: avSession.AVCastController | null = null;
  private onPlay: (() => void) | null = null;
  private onPause: (() => void) | null = null;
  private onPlayNext: (() => void) | null = null;
  private onPlayPrevious: (() => void) | null = null;
  private onFastForward: ((ms: number) => void) | null = null;
  private onRewind: ((ms: number) => void) | null = null;
  private onSeek: ((ms: number) => void) | null = null;
  private onSetSpeed: ((speed: number) => void) | null = null;
  private onSetLoopMode: ((mode: avSession.LoopMode) => void) | null = null;
  private onCollection: (() => void) | null = null;
  private onCastConnected: (() => void) | null = null;
  private outputDeviceChangeHandler = (state: avSession.ConnectionState,
    _device: avSession.OutputDeviceInfo): void => {
    if (state === avSession.ConnectionState.STATE_CONNECTED) {
      this.startCurrentCast().catch((err: Error) => {
        this.logMediaCenterWarning('startCurrentCast', err);
      });
    } else if (state === avSession.ConnectionState.STATE_DISCONNECTED) {
      this.castController = null;
    }
  };

  static getInstance(): AVSessionService {
    if (!AVSessionService.instance) {
      AVSessionService.instance = new AVSessionService();
    }
    return AVSessionService.instance;
  }

  private audioCallbacks: AVSessionCallbacks | null = null;

  setCallbacks(cbs: AVSessionCallbacks): void {
    this.audioCallbacks = cbs;
    if (!PlaybackCoordinator.speechActive) this.applyCallbacks(cbs);
  }

  setSpeechCallbacks(cbs: AVSessionCallbacks): void {
    this.currentCastUrl = '';
    this.metadataSerial++;
    this.applyCallbacks(cbs);
  }

  endSpeechPlayback(): void {
    if (!this.session || !PlaybackCoordinator.speechActive) return;
    const state: avSession.AVPlaybackState = { state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE };
    this.session.setAVPlaybackState(state).catch((error: Error): void => {
      this.logMediaCenterWarning('endSpeechPlayback', error);
    });
  }

  restoreAudioCallbacks(): void {
    this.metadataSerial++;
    if (this.audioCallbacks) this.applyCallbacks(this.audioCallbacks);
  }

  private applyCallbacks(cbs: AVSessionCallbacks): void {
    this.onPlay = cbs.onPlay;
    this.onPause = cbs.onPause;
    this.onPlayNext = cbs.onPlayNext;
    this.onPlayPrevious = cbs.onPlayPrevious;
    this.onFastForward = cbs.onFastForward;
    this.onRewind = cbs.onRewind;
    this.onSeek = cbs.onSeek;
    this.onSetSpeed = cbs.onSetSpeed;
    this.onSetLoopMode = cbs.onSetLoopMode;
    this.onCollection = cbs.onCollection;
    this.onCastConnected = cbs.onCastConnected;
  }

  init(context: common.UIAbilityContext): Promise<void> {
    if (this.initPromise) return this.initPromise;
    if (this.session) return Promise.resolve();
    this.context = context;
    this.initPromise = this.doInit(context);
    return this.initPromise;
  }

  private async doInit(context: common.UIAbilityContext): Promise<void> {
    try {
      this.session = await avSession.createAVSession(context, 'ListenBook', 'audio');
      this.registerCommands();
      await this.session.activate();
      this.configureMediaCenter();
      this.configureUrlCasting();
      await this.setupLaunchAbility(context);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'AVSession init failed: %{public}s',
        e?.message ?? JSON.stringify(err));
      this.initPromise = null;
    }
  }

  private async ensureReady(): Promise<boolean> {
    if (this.initPromise) {
      await this.initPromise;
    }
    return this.session !== null;
  }

  private async setupLaunchAbility(context: common.UIAbilityContext): Promise<void> {
    if (!this.session) return;
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(wantAgentInfo);
      await this.session.setLaunchAbility(agent);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'setLaunchAbility failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  private registerCommands(): void {
    if (!this.session) return;
    this.session.on('play', () => {
      this.onPlay?.();
    });
    this.session.on('pause', () => {
      this.onPause?.();
    });
    this.session.on('playNext', () => {
      this.onPlayNext?.();
    });
    this.session.on('playPrevious', () => {
      this.onPlayPrevious?.();
    });
    this.session.on('fastForward', (time?: number) => {
      this.onFastForward?.(this.normalizeSkipTime(time, FAST_FORWARD_INTERVAL_MS));
    });
    this.session.on('rewind', (time?: number) => {
      this.onRewind?.(this.normalizeSkipTime(time, REWIND_INTERVAL_MS));
    });
    this.session.on('seek', (timeMs: number) => {
      this.onSeek?.(timeMs);
    });
    this.session.on('setSpeed', (speed: number) => {
      this.onSetSpeed?.(speed);
    });
    this.session.on('setLoopMode', (mode: avSession.LoopMode) => {
      this.onSetLoopMode?.(mode);
    });
    this.session.on('toggleFavorite', () => {
      this.onCollection?.();
    });
    this.session.on('outputDeviceChange', this.outputDeviceChangeHandler);
  }

  private async configureUrlCasting(): Promise<void> {
    if (!this.session) return;
    try {
      const extras: Record<string, Object> = { 'url-cast': true };
      await this.session.setExtras(extras);
    } catch (err) {
      this.logMediaCenterWarning('setExtras.url-cast', err);
    }
  }

  private async configureMediaCenter(): Promise<void> {
    if (!this.session || !PlatformCompat.supports(26)) return;
    try {
      await this.session.setSupportedPlaySpeeds(SUPPORTED_PLAY_SPEEDS);
    } catch (err) {
      this.logMediaCenterWarning('setSupportedPlaySpeeds', err);
    }
    try {
      await this.session.setSupportedLoopModes(SUPPORTED_LOOP_MODES);
    } catch (err) {
      this.logMediaCenterWarning('setSupportedLoopModes', err);
    }
    try {
      await this.session.setMediaCenterControlType(MEDIA_CENTER_CONTROLS);
    } catch (err) {
      this.logMediaCenterWarning('setMediaCenterControlType', err);
    }
  }

  async updateLoopMode(mode: avSession.LoopMode): Promise<void> {
    if (PlaybackCoordinator.speechActive) return;
    if (!await this.ensureReady() || !this.session) return;
    const playbackState: avSession.AVPlaybackState = { loopMode: mode };
    try {
      await this.session.setAVPlaybackState(playbackState);
    } catch (err) {
      this.logMediaCenterWarning('setAVPlaybackState.loopMode', err);
    }
  }

  private logMediaCenterWarning(operation: string, err: Object): void {
    const error = err as Error;
    hilog.warn(DOMAIN, TAG, '%{public}s failed: %{public}s', operation,
      error?.message ?? JSON.stringify(err));
  }

  private normalizeSkipTime(time: number | undefined, fallbackMs: number): number {
    if (time === undefined || !Number.isFinite(time) || time <= 0) return fallbackMs;
    return time;
  }

  async updateMetadata(book: Book, chapter: Chapter, speech: boolean = false): Promise<void> {
    if (speech !== PlaybackCoordinator.speechActive) return;
    const serial = ++this.metadataSerial;
    if (!await this.ensureReady() || !this.session) return;
    if (serial !== this.metadataSerial || speech !== PlaybackCoordinator.speechActive) return;
    // 新书必须显式覆盖系统封面缓存；省略 mediaImage 不能保证旧图被清除。
    // 占位图只读本地资源，不能等待书源网络请求后才发布新书。
    const mediaImage: string | image.PixelMap = this.coverCache.get(book.cover)
      ?? await this.loadCover(MEDIA_COVER_PLACEHOLDER) ?? '';
    if (serial !== this.metadataSerial || speech !== PlaybackCoordinator.speechActive || !this.session) return;
    const previousAssetId = this.currentBook && this.currentChapter
      ? `${this.currentBook.id}_${this.currentChapter.id}` : '';
    const nextAssetId = `${book.id}_${chapter.id}`;
    if (previousAssetId !== nextAssetId) {
      this.currentCastUrl = '';
      this.currentDurationMs = 0;
    }
    this.currentBook = book;
    this.currentChapter = chapter;
    this.currentMediaImage = mediaImage;
    const metadata: avSession.AVMetadata = {
      assetId: `${book.id}_${chapter.id}`,
      title: chapter.title,
      artist: book.title,
      author: book.author,
      mediaImage: mediaImage,
    };
    if (chapter.duration > 0) metadata.duration = chapter.duration * 1000;
    try {
      await this.session.setAVMetadata(metadata);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'setAVMetadata failed: %{public}s',
        e?.message ?? JSON.stringify(err));
      if (serial !== this.metadataSerial || speech !== PlaybackCoordinator.speechActive) return;
      try {
        const fallback: avSession.AVMetadata = {
          assetId: `${book.id}_${chapter.id}`,
          title: chapter.title,
          artist: book.title,
          mediaImage: mediaImage,
        };
        await this.session.setAVMetadata(fallback);
      } catch (err2) {
        const e2 = err2 as Error;
        hilog.error(DOMAIN, TAG, 'setAVMetadata fallback also failed: %{public}s',
          e2?.message ?? JSON.stringify(err2));
      }
    }
    if (serial !== this.metadataSerial) return;
    const cover = this.context ? await LocalBookCoverService.resolve(this.context, book.id,
      book.cover, book.title, book.author) : book.cover;
    if (!cover || serial !== this.metadataSerial || speech !== PlaybackCoordinator.speechActive) return;
    const pixelMap = await this.loadCover(cover);
    if (pixelMap === null || serial !== this.metadataSerial || speech !== PlaybackCoordinator.speechActive || !this.session) return;
    this.currentMediaImage = pixelMap;
    metadata.mediaImage = pixelMap;
    if (this.currentDurationMs > 0) metadata.duration = this.currentDurationMs;
    try {
      await this.session.setAVMetadata(metadata);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'cover metadata update failed: %{public}s', String(error));
    }

  }

  /** AVPlayer prepared 后用真实 duration 刷新元数据,供胶囊/控制中心显示总时长 */
  async updateMetadataDuration(durationMs: number): Promise<void> {
    if (PlaybackCoordinator.speechActive) return;
    if (!await this.ensureReady() || !this.session) return;
    if (!this.currentBook || !this.currentChapter) return;
    if (durationMs <= 0) return;
    this.currentDurationMs = durationMs;
    const book = this.currentBook;
    const chapter = this.currentChapter;
    const metadata: avSession.AVMetadata = {
      assetId: `${book.id}_${chapter.id}`,
      title: chapter.title,
      artist: book.title,
      author: book.author,
      duration: durationMs,
      mediaImage: this.currentMediaImage,
    };
    try {
      await this.session.setAVMetadata(metadata);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'updateMetadataDuration failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  async updatePlaybackState(isPlaying: boolean, progressMs: number, speed: number,
    durationMs: number, isFavorite: boolean = false, speech: boolean = false): Promise<void> {
    if (speech !== PlaybackCoordinator.speechActive) return;
    if (!await this.ensureReady() || !this.session) return;
    if (speech !== PlaybackCoordinator.speechActive) return;
    this.currentProgressMs = progressMs;
    this.currentDurationMs = durationMs;
    let state: avSession.PlaybackState = avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    if (isPlaying) {
      state = avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    }
    const playbackState: avSession.AVPlaybackState = {
      state: state,
      speed: speed,
      position: {
        elapsedTime: progressMs,
        updateTime: Date.now()
      },
      isFavorite: isFavorite
    };
    if (durationMs > 0) playbackState.duration = durationMs;
    try {
      await this.session.setAVPlaybackState(playbackState);
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'setAVPlaybackState failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  updateCastMediaSource(book: Book, chapter: Chapter, url: string): void {
    if (PlaybackCoordinator.speechActive) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return;
    if (this.currentBook && this.currentChapter
      && this.currentBook.id === book.id && this.currentChapter.id === chapter.id) {
      this.currentCastUrl = url;
    }
  }

  currentCastMediaSource(bookId: string, chapterId: string): string {
    if (!this.currentBook || !this.currentChapter) return '';
    if (this.currentBook.id !== bookId || this.currentChapter.id !== chapterId) return '';
    return this.currentCastUrl;
  }

  async openCastPicker(): Promise<boolean> {
    if (!await this.ensureReady() || !this.context || !this.currentCastUrl) return false;
    try {
      const helper = new avSession.AVCastPickerHelper(this.context);
      const options: avSession.AVCastPickerOptions = { sessionType: 'audio' };
      await helper.select(options);
      return true;
    } catch (err) {
      this.logMediaCenterWarning('AVCastPickerHelper.select', err);
      return false;
    }
  }

  private async startCurrentCast(): Promise<void> {
    if (!this.session || !this.currentBook || !this.currentChapter || !this.currentCastUrl) return;
    const book = this.currentBook;
    const chapter = this.currentChapter;
    const description: avSession.AVMediaDescription = {
      assetId: `${book.id}_${chapter.id}`,
      title: chapter.title,
      subtitle: book.title,
      artist: book.author,
      albumTitle: book.title,
      mediaImage: book.cover.startsWith('http://') || book.cover.startsWith('https://')
        ? book.cover : undefined,
      mediaUri: this.currentCastUrl,
      startPosition: Math.max(0, this.currentProgressMs),
      duration: this.currentDurationMs > 0 ? this.currentDurationMs : undefined
    };
    const item: avSession.AVQueueItem = {
      itemId: Math.max(0, chapter.index),
      description: description
    };
    this.castController = await this.session.getAVCastController();
    await this.castController.start(item);
    this.onCastConnected?.();
  }

  private async loadCover(cover: string): Promise<image.PixelMap | null> {
    if (SourceCoverService.isEncoded(cover)) {
      try { return await this.loadCover(await SourceCoverService.resolve(cover)); }
      catch (_) { return null; }
    }
    const cached = this.coverCache.get(cover);
    if (cached !== undefined) {
      this.coverCache.delete(cover);
      this.coverCache.set(cover, cached);
      return cached;
    }
    const pending = this.coverLoads.get(cover);
    if (pending !== undefined) return pending;
    const task = this.loadAndCacheCover(cover, this.coverGeneration).finally((): void => {
      if (this.coverLoads.get(cover) === task) this.coverLoads.delete(cover);
    });
    this.coverLoads.set(cover, task);
    return task;
  }

  private async loadAndCacheCover(cover: string, generation: number): Promise<image.PixelMap | null> {
    try {
      let pixelMap: image.PixelMap | null = null;
      if (cover === MEDIA_COVER_PLACEHOLDER && this.context) {
        const bytes = await this.context.resourceManager.getMediaContent($r('app.media.book_cover_placeholder').id);
        pixelMap = await this.decodeCover(image.createImageSource(bytes.buffer));
      } else if (cover.startsWith('http://') || cover.startsWith('https://')) {
        pixelMap = await this.loadNetworkCover(cover);
      } else if (this.context) {
        pixelMap = await this.loadLocalCover(cover);
      }
      if (pixelMap) {
        // destroy 之后才完成的下载/解码，不能把原生位图写回已经销毁的单例。
        if (generation !== this.coverGeneration) {
          await this.releaseCover(pixelMap);
          return null;
        }
        this.coverCache.set(cover, pixelMap);
        this.trimCoverCache();
      }
      return pixelMap;
    } catch (err) {
      this.logMediaCenterWarning('loadCover', err);
      return null;
    }
  }

  private trimCoverCache(): void {
    for (const key of this.coverCache.keys()) {
      if (this.coverCache.size <= MAX_COVER_CACHE_SIZE) break;
      const pixelMap = this.coverCache.get(key);
      // 当前元数据仍引用的位图不得被旧请求完成时淘汰。
      if (pixelMap === undefined || pixelMap === this.currentMediaImage || key === this.currentBook?.cover) continue;
      this.coverCache.delete(key);
      this.releaseCover(pixelMap);
    }
  }

  private async releaseCover(pixelMap: image.PixelMap): Promise<void> {
    try { await pixelMap.release(); }
    catch (error) { this.logMediaCenterWarning('releaseCover', error); }
  }

  private async decodeCover(source: image.ImageSource): Promise<image.PixelMap> {
    try {
      const options: image.DecodingOptions = { desiredSize: { width: 512, height: 512 } };
      return await source.createPixelMap(options);
    } finally {
      // 损坏图片也必须释放解码器，不能只在 createPixelMap 成功后释放。
      try { await source.release(); }
      catch (error) { this.logMediaCenterWarning('releaseImageSource', error); }
    }
  }

  private async loadNetworkCover(url: string): Promise<image.PixelMap | null> {
    const httpClient = http.createHttp();
    try {
      const resp = await httpClient.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 15000,
        maxLimit: MAX_COVER_BYTES
      });
      if (resp.responseCode === 200 && resp.result instanceof ArrayBuffer &&
        resp.result.byteLength > 0 && resp.result.byteLength <= MAX_COVER_BYTES) {
        return await this.decodeCover(image.createImageSource(resp.result));
      }
    } finally {
      httpClient.destroy();
    }
    return null;
  }

  private async loadLocalCover(path: string): Promise<image.PixelMap | null> {
    if (!this.context) return null;
    // 书源缓存和自定义封面返回 file:// URI，与桌面小组件使用相同的本地路径。
    const filePath = path.startsWith('file://') ? path.substring('file://'.length) : path;
    // 沙箱文件保持 fd 到解码结束，避免额外分配整张原图的 ArrayBuffer。
    if (filePath.startsWith('/')) {
      try {
        const f = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
        try {
          const stat = await fileIo.stat(f.fd);
          if (stat.size <= 0 || stat.size > MAX_COVER_BYTES) {
            return null;
          }
          return await this.decodeCover(image.createImageSource(f.fd));
        } finally {
          await fileIo.close(f);
        }
      } catch (err) {
        const e = err as Error;
        hilog.error(DOMAIN, TAG, 'loadLocalCover sandbox path failed: %{public}s',
          e?.message ?? JSON.stringify(err));
        return null;
      }
    }
    // rawfile 路径
    try {
      const rawData = await this.context.resourceManager.getRawFileContent(path);
      if (rawData.byteLength === 0 || rawData.byteLength > MAX_COVER_BYTES) return null;
      return await this.decodeCover(image.createImageSource(rawData.buffer));
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'loadLocalCover rawfile failed: %{public}s',
        e?.message ?? JSON.stringify(err));
      return null;
    }
  }

  /** 暂时停用 session（不销毁），控制中心不再显示播控卡片 */
  async deactivate(): Promise<void> {
    if (!this.session) return;
    try {
      await this.session.deactivate();
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'deactivate failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  /** 重新激活已 deactivate 的 session */
  async reactivate(): Promise<void> {
    if (!this.session) return;
    try {
      await this.session.activate();
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'reactivate failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  async destroy(): Promise<void> {
    this.metadataSerial++;
    this.coverGeneration++;
    this.coverLoads.clear();
    const session = this.session;
    this.session = null;
    if (session) {
      try { session.off('outputDeviceChange', this.outputDeviceChangeHandler); } catch (_e) {}
      try { await session.deactivate(); } catch (_e) {}
      try { await session.destroy(); }
      catch (error) { this.logMediaCenterWarning('destroy', error); }
    }
    this.currentMediaImage = undefined;
    const releases: Promise<void>[] = [];
    this.coverCache.forEach((pm: image.PixelMap): void => {
      releases.push(this.releaseCover(pm));
    });
    this.coverCache.clear();
    await Promise.all(releases);
    // 重置单例状态，让下次 getInstance() 创建全新实例
    this.context = null;
    this.initPromise = null;
    this.currentBook = null;
    this.currentChapter = null;
    this.currentMediaImage = undefined;
    this.currentCastUrl = '';
    this.currentProgressMs = 0;
    this.currentDurationMs = 0;
    this.castController = null;
    this.onPlay = null;
    this.onPause = null;
    this.onPlayNext = null;
    this.onPlayPrevious = null;
    this.onFastForward = null;
    this.onRewind = null;
    this.onSeek = null;
    this.onSetSpeed = null;
    this.onSetLoopMode = null;
    this.onCollection = null;
    this.onCastConnected = null;
    AVSessionService.instance = null;
  }
}
