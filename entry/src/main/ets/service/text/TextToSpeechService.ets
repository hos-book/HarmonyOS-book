import { TextReadingPosition } from '../../model/TextReading';
import { ReaderTextDocument } from '../../model/ReaderTools';
import { ReaderToolsService } from './ReaderToolsService';
import { TextReadingProgressService } from './TextReadingProgressService';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { CustomTtsConfigParser } from './CustomTtsConfigParser';
import { HttpTtsAudioOutput, HttpTtsPlayer } from './HttpTtsPlayer';
import { SpeechPcmBuffer } from './SpeechPcmBuffer';
import { DiagnosticLogService } from '../DiagnosticLogService';
import { ReadingSessionService, SessionLocation } from '../ReadingSessionService';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemDateTime } from '@kit.BasicServicesKit';
import { Book } from '../../model/Book';
import { SpeechPosition, SpeechVoice, TextToSpeechState } from '../../model/TextToSpeechState';
import { StatsService } from '../StatsService';
import { AudioService } from '../AudioService';
import { AVSessionCallbacks, AVSessionService } from '../AVSessionService';
import { BackgroundTaskService } from '../BackgroundTaskService';
import { PlaybackCoordinator } from '../PlaybackCoordinator';
import { PreferenceService } from '../PreferenceService';
import { DataService } from '../DataService';
import { BookSourceService } from '../BookSourceService';
import { WidgetUpdater } from '../WidgetUpdater';
import { OnlineTextContentCache } from './OnlineTextContentCache';
import { OnlineTextPaginator } from './OnlineTextPaginator';
import { SpeechSegment, SpeechTextSegmenter } from './SpeechTextSegmenter';

/** 独立于页面生命周期的系统/HTTP 朗读。停止/换书后旧请求由代次和 requestId 隔离。 */
export class TextToSpeechService {
  updateBookPresentation(book: Book): void {
    if (this.book?.id !== book.id) return;
    this.book.title = book.title;
    this.book.cover = book.cover;
    this.state.bookTitle = book.title;
    this.state.cover = book.cover;
    const chapter = this.book.chapters[this.state.chapterIndex];
    if (chapter) AVSessionService.getInstance().updateMetadata(this.book, chapter, true);
    this.syncPlayerCard();
  }
  private static instance: TextToSpeechService | null = null;
  readonly state: TextToSpeechState = new TextToSpeechState();
  private context: common.UIAbilityContext | null = null;
  private store: preferences.Preferences | null = null;
  private initPromise: Promise<void> | null = null;
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private httpPlayer: HttpTtsPlayer | null = null;
  private httpPlaybackChain: Promise<void> = Promise.resolve();
  private httpSynthesisChain: Promise<void> = Promise.resolve();
  private httpTasks: Map<number, HttpTtsPlayer> = new Map();
  private httpOutput: HttpTtsAudioOutput = new HttpTtsAudioOutput();
  private pcm: SpeechPcmBuffer = new SpeechPcmBuffer();
  private pcmPlaybackId: string = '';
  private lastAudioLogAt: number = 0;
  private downloadedVoices: Set<string> = new Set();
  private enginePerson: number = -1;
  private engineLanguage: string = '';
  private engineChain: Promise<void> = Promise.resolve();
  private book: Book | null = null;
  private segments: SpeechSegment[] = [];
  private chapterContent: string = '';
  private textDocument: ReaderTextDocument | null = null;
  private segmentIndex: number = 0;
  private readingPageBookId: string = '';
  private readingPageChapter: number = -1;
  private readingPageEnds: number[] = [];
  private nextSystemId: string = '';
  private nextSystemIndex: number = -1;
  private nextSystemPcm: SpeechPcmBuffer = new SpeechPcmBuffer();
  private nextSystemAudio: ArrayBuffer | null = null;
  private generation: number = 0;
  private requestSequence: number = 0;
  private requestId: string = '';
  private watchdog: number = -1;
  private foreground: boolean = true;
  private sleepTimer: number = -1;
  private sleepDeadline: number = 0;
  private flushChain: Promise<void> = Promise.resolve();
  private lastSaveAt: number = 0;
  private lastWidgetState: string = '';
  private lastWidgetAt: number = 0;
  private spokenSince: number = -1;
  private pendingListenMs: number = 0;
  private listeners: Set<() => void> = new Set();
  private audioSession: audio.AudioSessionManager | null = null;
  private routing: audio.AudioRoutingManager | null = null;
  private focusChain: Promise<void> = Promise.resolve();
  private prefetchedKey: string = '';
  private prefetchedText: string = '';
  private readonly onDeactivated = (event: audio.AudioSessionDeactivatedEvent): void => {
    hilog.info(0x0000, 'TextToSpeech', 'audio session deactivated reason=%{public}d', event.reason);
    // 系统 TTS 在独立进程出声；本进程空闲会话 60 秒超时不是来电/焦点抢占。
    if (event.reason === audio.AudioSessionDeactivatedReason.DEACTIVATED_TIMEOUT) return;
    if (this.state.playing || this.state.loading) this.pause();
  };
  private readonly onDeviceChange = (event: audio.DeviceChangeAction): void => {
    if (event.type === audio.DeviceChangeType.DISCONNECT && (this.state.playing || this.state.loading)) {
      this.pause();
    }
  };

  static getInstance(): TextToSpeechService {
    if (TextToSpeechService.instance === null) TextToSpeechService.instance = new TextToSpeechService();
    return TextToSpeechService.instance;
  }

  currentBook(): Book | null {
    return this.book;
  }

  initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    PlaybackCoordinator.stopSpeech = (): Promise<void> => { this.stop(); return this.focusChain; };
    if (this.store !== null) return Promise.resolve();
    if (this.initPromise !== null) return this.initPromise;
    this.initPromise = this.loadSettings(context).finally((): void => { this.initPromise = null; });
    return this.initPromise;
  }

  static async reloadSettings(context: common.Context): Promise<void> {
    const service = TextToSpeechService.instance;
    if (service !== null && service.store !== null) await service.loadSettings(context);
  }

  private async loadSettings(context: common.Context): Promise<void> {
    this.store = await preferences.getPreferences(context, { name: 'text_to_speech' });
    const speed = this.store.getSync('speed', 1);
    const person = this.store.getSync('person', 13);
    const language = this.store.getSync('language', 'zh-CN');
    const follow = this.store.getSync('follow', true);
    this.state.speed = typeof speed === 'number' && Number.isFinite(speed) ? Math.max(0.5, Math.min(3, speed)) : 1;
    this.state.person = typeof person === 'number' && Number.isFinite(person) ? person : 13;
    this.state.language = typeof language === 'string' ? language : 'zh-CN';
    this.state.follow = typeof follow === 'boolean' ? follow : true;
    const catalog = this.store.getSync('customTtsCatalog', '[]');
    try {
      this.state.customTtsConfigs = typeof catalog === 'string' && catalog !== '[]' ? CustomTtsConfigParser.parse(catalog) : [];
    } catch (_error) { this.state.customTtsConfigs = []; }
    const selected = this.store.getSync('customTtsId', '');
    this.state.customTtsId = typeof selected === 'string' &&
      this.state.customTtsConfigs.some((item: CustomTtsConfig): boolean => item.id === selected && item.enabled) ? selected : '';
    if (!this.isChineseVoice(this.state.language)) {
      this.state.language = 'zh-CN';
      this.state.person = 13;
      this.saveSettings();
    }
  }

  addListener(listener: () => void): void {
    this.listeners.add(listener);
  }
  removeListener(listener: () => void): void {
    this.listeners.delete(listener);
  }

  private notify(): void {
    this.syncPlayerCard();
    if (!this.foreground) return;
    this.listeners.forEach((listener: () => void): void => listener());
  }

  private syncPlayerCard(): void {
    const book = this.book;
    if (book === null || !PlaybackCoordinator.speechActive) return;
    const chapter = book.chapters[this.state.chapterIndex];
    const visibleState = JSON.stringify([book.id, book.title, book.author, book.cover, chapter?.id ?? '',
      chapter?.title ?? '', this.state.playing && !this.state.loading]);
    const now = Date.now();
    if (visibleState === this.lastWidgetState && now - this.lastWidgetAt < 5000) return;
    this.lastWidgetState = visibleState;
    this.lastWidgetAt = now;
    WidgetUpdater.updateSpeechCard(book, this.state).catch((error: Error): void => this.report(error));
  }

  private message(resource: Resource): string {
    return this.context?.resourceManager.getStringSync(resource.id) ?? '';
  }

  private report(error: Error): void {
    hilog.warn(0x0000, 'TextToSpeech', '%{public}s', error.message);
  }

  private isChineseVoice(language: string): boolean {
    return language.replace('_', '-').toLowerCase() === 'zh-cn';
  }

  async refreshVoices(): Promise<void> {
    try {
      const query: textToSpeech.VoiceQuery = { requestId: this.nextId(), online: 1 };
      const result = await textToSpeech.listVoices(query);
      const voices: SpeechVoice[] = [];
      for (const item of result) {
        if (item.status === 'EOM' || !this.isChineseVoice(item.language)) continue;
        const voiceId = `${item.language}:${item.person}:${item.style}`;
        const voice = this.state.voices.find((existing: SpeechVoice): boolean => existing.id === voiceId) ?? new SpeechVoice();
        voice.person = item.person;
        voice.language = item.language;
        voice.style = item.style;
        voice.id = `${item.language}:${item.person}:${item.style}`;
        voice.label = item.description || `${item.language} · ${item.person}`;
        voice.installed = this.downloadedVoices.has(voice.id) || item.status === 'INSTALLED' ||
          (item.person === 0 || item.person === 13);
        if (!voices.some((existing: SpeechVoice): boolean => existing.id === voice.id)) voices.push(voice);
      }
      this.state.voices = voices;
      if (voices.length === 0 && !this.state.customTtsId) this.state.error = this.message($r('app.string.tts_no_voices'));
    } catch (error) {
      if (!this.state.customTtsId) this.state.error = this.message($r('app.string.tts_engine_error'));
      this.report(error instanceof Error ? error : new Error(String(error)));
    }
  }

  async selectVoice(voice: SpeechVoice): Promise<void> {
    if (this.state.downloadingVoice || !this.isChineseVoice(voice.language)) return;
    this.state.error = '';
    if (!voice.installed) {
      this.state.downloadingVoice = voice.id;
      try {
        await this.downloadVoice(voice);
        this.downloadedVoices.add(voice.id);
        voice.installed = true;
        const current = this.state.voices.find((item: SpeechVoice): boolean => item.id === voice.id);
        if (current) current.installed = true;
      } catch (error) {
        this.state.error = this.message($r('app.string.tts_download_error'));
        this.report(error instanceof Error ? error : new Error(String(error)));
        return;
      } finally {
        this.state.downloadingVoice = '';
      }
    }
    const resume = this.state.playing || this.state.loading;
    this.pause();
    this.state.customTtsId = '';
    this.rebuildSpeechSegments();
    this.state.person = voice.person;
    this.state.language = voice.language;
    this.saveSettings();
    this.releaseEngine();
    if (resume) await this.resume();
  }

  async importCustomTts(configs: CustomTtsConfig[]): Promise<void> {
    const store = this.store;
    if (store === null || configs.length === 0) return;
    const catalog = this.state.customTtsConfigs.slice();
    for (const config of configs) {
      const index = catalog.findIndex((item: CustomTtsConfig): boolean => item.id === config.id);
      if (index >= 0) {
        config.enabled = catalog[index].enabled;
        catalog[index] = config;
      }
      else catalog.push(config);
    }
    if (catalog.length > CustomTtsConfigParser.MAX_CONFIGS) throw new Error('TTS catalog full');
    const previous = JSON.stringify(this.state.customTtsConfigs);
    store.putSync('customTtsCatalog', JSON.stringify(catalog));
    try { await store.flush(); }
    catch (_error) { store.putSync('customTtsCatalog', previous); throw new Error('TTS save failed'); }
    this.state.customTtsConfigs = catalog;
    await this.selectCustomTts(configs[configs.length - 1].id);
  }

  async selectCustomTts(id: string): Promise<void> {
    if (id && !this.state.customTtsConfigs.some((item: CustomTtsConfig): boolean => item.id === id && item.enabled)) return;
    const resume = this.state.playing || this.state.loading;
    this.pause();
    this.releaseEngine();
    this.state.customTtsId = id;
    this.rebuildSpeechSegments();
    this.state.error = '';
    this.saveSettings();
    if (resume) await this.resume();
  }

  async setCustomTtsEnabled(id: string, enabled: boolean): Promise<void> {
    const store = this.store;
    if (store === null) return;
    const previous = this.state.customTtsConfigs;
    const index = previous.findIndex((item: CustomTtsConfig): boolean => item.id === id);
    if (index < 0 || previous[index].enabled === enabled) return;
    const item = previous[index];
    const updated: CustomTtsConfig = {
      id: item.id, name: item.name, enabled: enabled, url: item.url,
      method: item.method, body: item.body, header: item.header, contentType: item.contentType
    };
    const catalog = previous.slice();
    catalog[index] = updated;
    store.putSync('customTtsCatalog', JSON.stringify(catalog));
    try { await store.flush(); }
    catch (_error) { store.putSync('customTtsCatalog', JSON.stringify(previous)); throw new Error('TTS save failed'); }
    this.state.customTtsConfigs = catalog;
    if (!enabled && this.state.customTtsId === id) await this.selectCustomTts('');
  }

  async removeCustomTts(id: string): Promise<void> {
    const store = this.store;
    if (store === null) return;
    const previous = this.state.customTtsConfigs;
    const catalog = previous.filter((item: CustomTtsConfig): boolean => item.id !== id);
    store.putSync('customTtsCatalog', JSON.stringify(catalog));
    try { await store.flush(); }
    catch (_error) { store.putSync('customTtsCatalog', JSON.stringify(previous)); throw new Error('TTS save failed'); }
    this.state.customTtsConfigs = catalog;
    if (this.state.customTtsId === id) await this.selectCustomTts('');
  }

  private downloadVoice(voice: SpeechVoice): Promise<void> {
    return new Promise<void>((resolve, reject): void => {
      let finished = false;
      const timer = setTimeout((): void => {
        if (finished) return;
        finished = true;
        reject(new Error('Voice download timed out'));
      }, 180000);
      const params: textToSpeech.VoiceDownload = {
        requestId: this.nextId(), person: voice.person, language: voice.language, style: voice.style
      };
      try {
        textToSpeech.downloadVoice(params, (error, response): void => {
          if (finished) return;
          if (error) {
            finished = true;
            clearTimeout(timer);
            if (error.code === 1002300010) resolve();
            else reject(new Error(error.message));
            return;
          }
          response.on('complete', (): void => {
            if (finished) return;
            finished = true;
            clearTimeout(timer);
            resolve();
          });
          response.on('error', (downloadError): void => {
            if (finished) return;
            finished = true;
            clearTimeout(timer);
            reject(new Error(String(downloadError)));
          });
        });
      } catch (error) {
        finished = true;
        clearTimeout(timer);
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  }

  setSpeed(speed: number): void {
    if (!Number.isFinite(speed)) return;
    const resume = this.state.playing || this.state.loading;
    this.pause();
    this.state.speed = Math.round(Math.max(0.5, Math.min(3, speed)) * 100) / 100;
    this.saveSettings();
    if (resume) this.resume();
  }

  setFollow(follow: boolean): void {
    this.state.follow = follow;
    this.saveSettings();
    this.notify();
  }

  setSleep(minutes: number, chapterEnd: boolean = false): void {
    if (this.sleepTimer !== -1) clearInterval(this.sleepTimer);
    this.sleepTimer = -1;
    this.sleepDeadline = minutes > 0 ? Date.now() + minutes * 60000 : 0;
    this.state.stopAtChapterEnd = chapterEnd;
    this.state.remainingSeconds = Math.max(0, minutes * 60);
    if (minutes > 0) {
      this.sleepTimer = setInterval((): void => {
        this.state.remainingSeconds = Math.max(0, Math.ceil((this.sleepDeadline - Date.now()) / 1000));
        if (this.state.remainingSeconds === 0) {
          this.pause();
          this.setSleep(0);
        }
      }, 1000);
    }
  }

  async start(book: Book, chapterIndex: number, offset: number, restore: boolean = false): Promise<void> {
    const context = this.context;
    if (context === null || book.contentType !== 'text' || book.chapters.length === 0) return;
    this.pause();
    if (this.book !== null && this.book.id !== book.id) { this.setSleep(0); this.pendingListenMs = 0; }
    const ticket = ++this.generation;
    PlaybackCoordinator.speechActive = true;
    this.state.active = true;
    this.state.loading = true;
    this.state.error = '';
    try {
      await this.initialize(context);
      await PreferenceService.applyTocOrder(book);
      if (!this.valid(ticket)) return;
      this.book = book;
      this.state.bookId = book.id;
      this.state.bookTitle = book.title;
      this.state.cover = book.cover;
      this.state.chapterCount = book.chapters.length;
      this.segments = [];
      this.chapterContent = '';
      this.textDocument = null;
      this.prefetchedKey = '';
      this.prefetchedText = '';
      if (restore) {
        const saved = this.savedPosition(book);
        if (saved !== null) {
          const index = book.chapters.findIndex((chapter): boolean =>
            (chapter.originSourceValue || chapter.source.value) === saved.chapterUrl);
          // 目录重排时只按原章节 URL 恢复，删除的章节回退用户当前阅读位置。
          if (index >= 0) { chapterIndex = index; offset = saved.charOffset; }
        }
      }
      this.state.chapterIndex = Math.max(0, Math.min(chapterIndex, book.chapters.length - 1));
      this.state.charOffset = Math.max(0, offset);
      await this.preparePlayback(ticket);
      if (!this.valid(ticket)) return;
      await this.loadChapter(this.state.chapterIndex, this.state.charOffset, ticket);
    } catch (error) {
      if (this.valid(ticket)) this.fail(error instanceof Error ? error : new Error(String(error)));
    }
  }

  async resume(): Promise<void> {
    if (this.state.playing || this.state.loading || this.book === null) return;
    const ticket = ++this.generation;
    PlaybackCoordinator.speechActive = true;
    this.state.active = true;
    this.state.loading = true;
    this.state.error = '';
    try {
      await this.preparePlayback(ticket);
      if (!this.valid(ticket)) return;
      if (this.segments.length === 0) {
        await this.loadChapter(this.state.chapterIndex, this.currentRawOffset(), ticket);
      } else {
        if (this.state.charOffset > (this.segments[this.segmentIndex]?.start ?? 0) &&
          this.readingPageBookId === this.state.bookId && this.readingPageChapter === this.state.chapterIndex &&
          this.readingPageEnds.length > 0) this.rebuildSpeechSegments();
        this.publishMetadata();
        this.speakNext(ticket);
      }
    } catch (error) {
      if (this.valid(ticket)) this.fail(error instanceof Error ? error : new Error(String(error)));
    }
  }

  pause(): void {
    DiagnosticLogService.info('tts.pause', `foreground=${this.foreground}; offset=${this.state.charOffset}; bg=${BackgroundTaskService.isRunning()}`);
    this.recordSpokenTime();
    this.generation++;
    this.requestId = '';
    this.pcm.reset();
    this.pcmPlaybackId = '';
    this.clearWatchdog();
    this.state.playing = false;
    this.state.loading = false;
    try { this.engine?.stop(); } catch (_error) { /* 引擎可能已被系统回收 */ }
    this.httpPlayer?.cancel();
    this.httpPlayer = null;
    this.clearHttpPrefetch();
    this.httpPlaybackChain = this.httpPlaybackChain.catch((): void => {}).then((): Promise<void> => this.httpOutput.release());
    this.savePosition(true);
    this.syncSession();
    ReadingSessionService.end('tts');
    if (this.context !== null) BackgroundTaskService.stopSpeech(this.context);
    this.releaseFocus();
    this.notify();
  }

  stop(): void {
    this.pause();
    this.setSleep(0);
    this.releaseEngine();
    AVSessionService.getInstance().endSpeechPlayback();
    PlaybackCoordinator.speechActive = false;
    this.state.active = false;
    this.state.highlightOffset = -1;
    this.state.highlightEnd = -1;
    AVSessionService.getInstance().restoreAudioCallbacks();
  }

  async removeSavedPositions(context: common.Context, bookIds: string[]): Promise<void> {
    if (bookIds.includes(this.state.bookId)) {
      this.stop();
      this.book = null;
      this.state.bookId = '';
      this.notify();
    }
    await this.flushChain;
    const store = this.store ?? await preferences.getPreferences(context, { name: 'text_to_speech' });
    for (const id of bookIds) store.deleteSync(`position_${id}`);
    await store.flush();
  }

  async moveChapter(delta: number): Promise<void> {
    if (this.book === null) return;
    const target = this.state.chapterIndex + delta;
    if (target < 0 || target >= this.book.chapters.length) return;
    await this.start(this.book, target, 0);
  }

  private valid(ticket: number): boolean {
    return ticket === this.generation && PlaybackCoordinator.speechActive;
  }

  private async preparePlayback(ticket: number): Promise<void> {
    await AudioService.getInstance().suspendForSpeech();
    await this.httpPlaybackChain.catch((): void => {});
    if (!this.valid(ticket) || this.context === null) return;
    this.installSessionCallbacks();
    await AVSessionService.getInstance().init(this.context);
    if (!this.valid(ticket)) return;
    if (!this.state.customTtsId) await this.ensureEngine(ticket);
    if (!this.valid(ticket)) return;
    await this.acquireFocus(ticket);
  }

  private ensureEngine(ticket: number): Promise<void> {
    const task = this.engineChain.catch((): void => {}).then(async (): Promise<void> => {
      if (!this.valid(ticket)) return;
      if (this.engine !== null && this.enginePerson === this.state.person &&
        this.engineLanguage === this.state.language) return;
      this.releaseEngine();
      const person = this.state.person;
      const language = this.state.language;
      const params: textToSpeech.CreateEngineParams = {
        language: language, person: person, online: 1,
        extraParams: { 'isBackStage': true, 'name': 'ListenBookSpeech' }
      };
      const engine = await this.createEngineWithTimeout(params);
      if (!this.valid(ticket)) { engine.shutdown(); return; }
      this.engine = engine;
      this.enginePerson = person;
      this.engineLanguage = language;
      const listener: textToSpeech.SpeakListener = {
        onStart: (id: string, response: textToSpeech.StartResponse): void => {
          if (id === this.nextSystemId) {
            try { this.nextSystemPcm.configure(response); }
            catch (_error) { this.discardSystemPrefetch(id); }
            return;
          }
          if (id !== this.requestId) return;
          try { this.pcm.configure(response); }
          catch (error) { this.fail(new Error(String(error))); }
        },
        onComplete: (id: string, response: textToSpeech.CompleteResponse): void => {
          if (id === this.nextSystemId) {
            if (response.type !== 0 || this.nextSystemAudio !== null) return;
            try { this.nextSystemAudio = this.nextSystemPcm.toWave(); }
            catch (_error) { this.discardSystemPrefetch(id); return; }
            this.nextSystemPcm.reset();
            if (id === this.requestId) this.playPreparedSystemSpeech(id, this.generation);
            return;
          }
          if (id !== this.requestId || response.type !== 0 || this.pcmPlaybackId === id) return;
          this.pcmPlaybackId = id;
          this.playSystemSpeech(id, this.generation);
        },
        onStop: (id: string, _response: textToSpeech.StopResponse): void => {
          if (id === this.nextSystemId) { this.discardSystemPrefetch(id); return; }
          if (id === this.requestId) this.pause();
        },
        onError: (id: string, code: number, _message: string): void => {
          if (id === this.nextSystemId) { this.discardSystemPrefetch(id); return; }
          if (id === this.requestId) this.fail(new Error(`TTS error ${code}`));
        },
        onData: (id: string, data: ArrayBuffer, response: textToSpeech.SynthesisResponse): void => {
          if (id === this.nextSystemId) {
            try { this.nextSystemPcm.append(data, response); }
            catch (_error) { this.discardSystemPrefetch(id); }
            return;
          }
          if (id !== this.requestId) return;
          try { this.pcm.append(data, response); }
          catch (error) { this.fail(new Error(String(error))); }
        }
      };
      engine.setListener(listener);
    });
    this.engineChain = task;
    return task;
  }

  private createEngineWithTimeout(params: textToSpeech.CreateEngineParams): Promise<textToSpeech.TextToSpeechEngine> {
    return new Promise<textToSpeech.TextToSpeechEngine>((resolve, reject): void => {
      let finished = false;
      const timer = setTimeout((): void => {
        finished = true;
        reject(new Error('Speech engine initialization timed out'));
      }, 20000);
      textToSpeech.createEngine(params).then((engine: textToSpeech.TextToSpeechEngine): void => {
        if (finished) { engine.shutdown(); return; }
        finished = true;
        clearTimeout(timer);
        resolve(engine);
      }).catch((error: Error): void => {
        if (finished) return;
        finished = true;
        clearTimeout(timer);
        reject(error);
      });
    });
  }

  private releaseEngine(): void {
    const engine = this.engine;
    this.engine = null;
    this.enginePerson = -1;
    if (engine !== null) {
      try { engine.shutdown(); } catch (_error) { /* 已回收 */ }
    }
  }

  private async loadChapter(index: number, offset: number, ticket: number): Promise<void> {
    const book = this.book;
    if (book === null || !this.valid(ticket)) return;
    this.clearHttpPrefetch();
    this.state.loading = true;
    this.state.chapterIndex = index;
    this.state.chapterTitle = book.chapters[index].title;
    this.state.charOffset = offset;
    this.state.playbackOffset = offset;
    this.state.contentLength = 0;
    this.state.sentence = '';
    this.state.highlightOffset = -1;
    this.state.highlightEnd = -1;
    this.segments = [];
    this.chapterContent = '';
    this.textDocument = null;
    this.publishMetadata();
    try {
      const raw = await this.fetchChapter(book, index);
      const document = this.context ? await ReaderToolsService.render(this.context, book.id, raw) : ReaderTextDocument.original(raw);
      if (!this.valid(ticket)) return;
      const content = document.content;
      this.textDocument = document;
      this.state.charOffset = document.toDisplay(offset);
      this.chapterContent = content;
      this.rebuildSpeechSegments();
      if (this.segments.length === 0 && content.trim().length === 0) throw new Error('Empty chapter');
      this.state.contentLength = content.length;
      this.segmentIndex = SpeechTextSegmenter.indexAt(this.segments, this.state.charOffset);
      this.speakNext(ticket);
      this.prefetch(book, index + 1, ticket);
    } catch (error) {
      if (this.valid(ticket)) this.fail(error instanceof Error ? error : new Error(String(error)), true);
    }
  }

  private async fetchChapter(book: Book, index: number): Promise<string> {
    const chapter = book.chapters[index];
    const url = chapter.originSourceValue || chapter.source.value;
    const key = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl, url);
    if (key === this.prefetchedKey && this.prefetchedText) return this.prefetchedText;
    const context = this.context;
    if (context !== null) {
      const saved = await OnlineTextContentCache.read(context, key);
      if (saved !== undefined) return saved;
    }
    const value = await BookSourceService.getTextChapterContent(book, url, chapter.title, chapter.variables);
    const content = OnlineTextPaginator.normalizeContent(value.content);
    if (context !== null) await OnlineTextContentCache.write(context, key, content);
    return content;
  }

  private async prefetch(book: Book, index: number, ticket: number): Promise<void> {
    if (index < 0 || index >= book.chapters.length) return;
    try {
      const content = await this.fetchChapter(book, index);
      if (!this.valid(ticket)) return;
      const chapter = book.chapters[index];
      this.prefetchedKey = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl,
        chapter.originSourceValue || chapter.source.value);
      this.prefetchedText = content;
    } catch (_error) { /* 预取失败不影响当前章；到下一章时重试并展示错误。 */ }
  }

  private speakNext(ticket: number): void {
    if (!this.valid(ticket) || (!this.state.customTtsId && this.engine === null) || this.book === null) return;
    if (this.sleepDeadline > 0 && Date.now() >= this.sleepDeadline) {
      this.pause(); this.setSleep(0); return;
    }
    if (this.segmentIndex >= this.segments.length) {
      this.state.charOffset = this.state.contentLength;
      this.savePosition(true);
      const next = this.state.chapterIndex + 1;
      if (this.state.stopAtChapterEnd || next < 0 || next >= this.book.chapters.length) {
        this.pause(); this.setSleep(0); return;
      }
      this.loadChapter(next, 0, ticket);
      return;
    }
    const segment = this.segments[this.segmentIndex];
    this.state.charOffset = segment.start;
    this.state.playbackOffset = segment.start;
    this.state.sentence = segment.text;
    this.requestId = this.nextId();
    this.pcm.reset();
    this.pcmPlaybackId = '';
    this.state.playing = true;
    this.savePosition(false);
    this.notify();
    const params: textToSpeech.SpeakParams = {
      requestId: this.requestId,
      extraParams: { 'queueMode': 0, 'speed': Math.min(2, this.state.speed), 'volume': 1, 'pitch': 1,
        'languageContext': this.state.language, 'audioType': 'pcm', 'soundChannel': 1, 'playType': 0, 'isBackStage': true }
    };
    try {
      this.clearWatchdog();
      this.watchdog = setTimeout((): void => {
        if (this.valid(ticket)) this.fail(new Error('Speech callback timed out'));
      }, 150000);
      if (this.state.customTtsId) this.speakHttp(segment.text, this.requestId, ticket);
      else if (this.nextSystemIndex === this.segmentIndex && this.nextSystemId.length > 0) {
        this.requestId = this.nextSystemId;
        this.playPreparedSystemSpeech(this.requestId, ticket);
      } else this.engine?.speak(segment.text, params);
    } catch (error) {
      this.fail(error instanceof Error ? error : new Error(String(error)));
    }
  }

  private discardSystemPrefetch(id: string): void {
    if (id !== this.nextSystemId) return;
    const waiting = id.length > 0 && id === this.requestId;
    this.nextSystemId = '';
    this.nextSystemIndex = -1;
    this.nextSystemAudio = null;
    this.nextSystemPcm.reset();
    // 预取失败不打断当前音频；已到下一段时按普通合成重试。
    if (waiting) this.speakNext(this.generation);
  }

  private prefetchSystemPage(): void {
    const segment = this.segments[this.segmentIndex];
    if (!segment || this.nextSystemId.length > 0 ||
      this.readingPageBookId !== this.state.bookId || this.readingPageChapter !== this.state.chapterIndex ||
      !this.readingPageEnds.some((end: number): boolean => end > segment.start && end <= segment.end) ||
      this.segmentIndex + 1 >= this.segments.length) return;
    this.nextSystemId = this.nextId();
    this.nextSystemIndex = this.segmentIndex + 1;
    const params: textToSpeech.SpeakParams = {
      requestId: this.nextSystemId,
      extraParams: { 'queueMode': 0, 'speed': Math.min(2, this.state.speed), 'volume': 1, 'pitch': 1,
        'languageContext': this.state.language, 'audioType': 'pcm', 'soundChannel': 1, 'playType': 0, 'isBackStage': true }
    };
    try { this.engine?.speak(this.segments[this.nextSystemIndex].text, params); }
    catch (_error) { this.discardSystemPrefetch(this.nextSystemId); }
  }

  private playPreparedSystemSpeech(id: string, ticket: number): void {
    const buffer = this.nextSystemAudio;
    if (buffer === null) return;
    this.nextSystemId = '';
    this.nextSystemIndex = -1;
    this.nextSystemAudio = null;
    this.pcmPlaybackId = id;
    this.playSystemSpeech(id, ticket, buffer);
  }

  private playSystemSpeech(id: string, ticket: number, prepared: ArrayBuffer | null = null): void {
    const context = this.context;
    if (context === null) return;
    let buffer: ArrayBuffer;
    try { buffer = prepared ?? this.pcm.toWave(); }
    catch (error) { this.fail(new Error(String(error))); return; }
    this.pcm.reset();
    const player = new HttpTtsPlayer();
    this.httpPlayer = player;
    this.httpPlaybackChain = this.httpPlaybackChain.catch((): void => {}).then(async (): Promise<void> => {
      if (!this.valid(ticket) || id !== this.requestId) return;
      try {
        await player.speakAudio(context, buffer, Math.max(1, this.state.speed / 2), id, (): void => {
          if (!this.valid(ticket) || id !== this.requestId) return;
          if (this.spokenSince < 0) this.spokenSince = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
          this.highlightParagraph();
          this.logCrossPagePlayback(id);
          this.state.loading = false;
          this.state.playing = true;
          this.prefetchSystemPage();
          BackgroundTaskService.startSpeech(context);
          if (Date.now() - this.lastAudioLogAt >= 60000) {
            this.lastAudioLogAt = Date.now();
            DiagnosticLogService.info('tts.audio.start', `foreground=${this.foreground}; bytes=${buffer.byteLength}; offset=${this.state.charOffset}; bg=${BackgroundTaskService.isRunning()}`);
          }
          this.syncSession();
          this.notify();
        }, this.httpOutput, (position: number, duration: number): void => {
          if (!this.valid(ticket) || id !== this.requestId || !this.state.playing || this.state.loading) return;
          this.followSpeechProgress(position, duration);
        });
        if (!this.valid(ticket) || id !== this.requestId) return;
        this.recordSpokenTime();
        this.requestId = '';
        this.clearWatchdog();
        this.segmentIndex++;
        this.speakNext(ticket);
      } catch (error) {
        if (this.valid(ticket) && id === this.requestId) this.fail(new Error(String(error)));
      } finally {
        if (this.httpPlayer === player) this.httpPlayer = null;
      }
    });
  }

  private clearHttpPrefetch(): void {
    this.nextSystemId = '';
    this.nextSystemIndex = -1;
    this.nextSystemAudio = null;
    this.nextSystemPcm.reset();
    this.httpTasks.forEach((task: HttpTtsPlayer): void => task.cancel());
    this.httpTasks.clear();
    this.httpSynthesisChain = Promise.resolve();
  }

  private followSpeechProgress(position: number, duration: number): void {
    if (!Number.isFinite(position) || !Number.isFinite(duration) || duration <= 0 || position < 0) return;
    const segment = this.segments[this.segmentIndex];
    if (!segment) return;
    // 合成接口没有逐字时间戳。仅用真实播放进度估算页界，不切音频、不逐字刷新 UI。
    const readStart = segment.start + segment.leadingWhitespace;
    const offset = Math.min(segment.end - 1,
      readStart + Math.floor((segment.end - readStart) * Math.min(1, position / duration)));
    if (offset > this.state.playbackOffset) this.state.playbackOffset = offset;
    if (this.readingPageBookId !== this.state.bookId || this.readingPageChapter !== this.state.chapterIndex) return;
    let pageOffset = this.state.charOffset;
    for (const end of this.readingPageEnds) {
      if (end > pageOffset && end > segment.start && end < segment.end && end <= offset) pageOffset = end;
    }
    if (pageOffset === this.state.charOffset) return;
    hilog.info(0x0000, 'SpeechFlow', 'page request=%{public}s range=%{public}d-%{public}d offset=%{public}d time=%{public}d/%{public}d',
      this.requestId, segment.start, segment.end, pageOffset, position, duration);
    this.state.charOffset = pageOffset;
    this.savePosition(false);
    this.notify();
  }

  private logCrossPagePlayback(id: string): void {
    const segment = this.segments[this.segmentIndex];
    if (!segment || this.readingPageBookId !== this.state.bookId ||
      this.readingPageChapter !== this.state.chapterIndex ||
      !this.readingPageEnds.some((end: number): boolean => end > segment.start && end < segment.end)) return;
    hilog.info(0x0000, 'SpeechFlow', 'play request=%{public}s range=%{public}d-%{public}d custom=%{public}s',
      id, segment.start, segment.end, this.state.customTtsId.length > 0 ? 'true' : 'false');
  }

  private rebuildSpeechSegments(): void {
    const pageEnds: number[] = [];
    // 手动从新页起读仍按指定页首切入；自然播放的后续页界不拆词。
    if (this.state.charOffset > 0 && this.readingPageBookId === this.state.bookId &&
      this.readingPageChapter === this.state.chapterIndex && this.readingPageEnds.length > 0) {
      pageEnds.push(this.state.charOffset);
    }
    this.segments = SpeechTextSegmenter.split(this.chapterContent, this.state.customTtsId.length > 0, pageEnds);
    this.segmentIndex = SpeechTextSegmenter.indexAt(this.segments, this.state.charOffset);
  }

  setReadingPageEnds(bookId: string, chapterIndex: number, offsets: number[]): void {
    if (this.readingPageBookId === bookId && this.readingPageChapter === chapterIndex &&
      offsets.length === this.readingPageEnds.length && offsets.every((offset: number, index: number): boolean =>
        offset === this.readingPageEnds[index])) return;
    this.readingPageBookId = bookId;
    this.readingPageChapter = chapterIndex;
    this.readingPageEnds = offsets.slice();
    // 只更新页界映射，重新排版不废弃仍可复用的完整语句音频。
  }

  private prefetchHttp(config: CustomTtsConfig, ticket: number): void {
    // 当前句 + 后续两句；同一时刻只合成一句，避免触发提供方并发限制。
    const end = Math.min(this.segments.length, this.segmentIndex + 3);
    const speed = this.state.speed;
    for (let index = this.segmentIndex; index < end; index++) {
      if (this.httpTasks.has(index)) continue;
      const task = new HttpTtsPlayer();
      const text = this.segments[index].text;
      this.httpTasks.set(index, task);
      this.httpSynthesisChain = this.httpSynthesisChain.then(async (): Promise<void> => {
        if (!this.valid(ticket) || this.httpTasks.get(index) !== task) return;
        try { await task.prepare(config, text, speed); }
        catch (_error) { /* 预取失败不打断当前句，到该句时按原有错误路径提示。 */ }
      });
    }
  }

  private speakHttp(text: string, id: string, ticket: number): void {
    const config = this.state.customTtsConfigs.find((item: CustomTtsConfig): boolean => item.id === this.state.customTtsId);
    const context = this.context;
    if (!config || context === null) { this.fail(new Error('TTS config unavailable')); return; }
    this.prefetchHttp(config, ticket);
    const index = this.segmentIndex;
    const player = this.httpTasks.get(index);
    if (!player) { this.fail(new Error('TTS task unavailable')); return; }
    this.state.loading = !player.ready;
    this.state.playing = player.ready;
    // 等待上一任务释放播放器，避免切换配置时两种声音重叠。
    this.httpPlaybackChain = this.httpPlaybackChain.catch((): void => {}).then(async (): Promise<void> => {
      if (!this.valid(ticket) || id !== this.requestId) return;
      this.httpPlayer = player;
      try {
        await player.speak(context, config, text, this.state.speed, id, (): void => {
          if (!this.valid(ticket) || id !== this.requestId) return;
          if (this.spokenSince < 0) this.spokenSince = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
          this.state.loading = false;
          this.state.playing = true;
          this.highlightParagraph();
          this.logCrossPagePlayback(id);
          BackgroundTaskService.startSpeech(context);
          this.syncSession();
          this.notify();
        }, this.httpOutput, (position: number, duration: number): void => {
          if (!this.valid(ticket) || id !== this.requestId || !this.state.playing || this.state.loading) return;
          this.followSpeechProgress(position, duration);
        });
        if (!this.valid(ticket) || id !== this.requestId) return;
        this.recordSpokenTime();
        this.requestId = '';
        this.clearWatchdog();
        this.httpTasks.delete(index);
        this.segmentIndex++;
        this.speakNext(ticket);
      } catch (_error) {
        if (this.valid(ticket) && id === this.requestId) {
          this.pause();
          this.state.error = this.message($r('app.string.tts_custom_play_error'));
        }
      } finally {
        if (this.httpPlayer === player) this.httpPlayer = null;
      }
    });
  }

  setForeground(foreground: boolean): void {
    this.foreground = foreground;
    if (foreground) this.notify();
  }

  private highlightParagraph(): void {
    const segment = this.segments[this.segmentIndex];
    if (!segment) return;
    if (this.state.highlightOffset !== segment.paragraphStart) this.state.highlightOffset = segment.paragraphStart;
    if (this.state.highlightEnd !== segment.paragraphEnd) this.state.highlightEnd = segment.paragraphEnd;
  }

  private recordSpokenTime(): void {
    if (this.spokenSince < 0 || this.book === null) return;
    this.pendingListenMs += Math.max(0, systemDateTime.getUptime(systemDateTime.TimeType.STARTUP) - this.spokenSince);
    this.spokenSince = -1;
    const seconds = Math.floor(this.pendingListenMs / 1000);
    if (seconds < 1) return;
    this.pendingListenMs -= seconds * 1000;
    const book = this.book;
    StatsService.addListenSeconds(seconds, { bookId: book.id, title: book.title, author: book.author,
      cover: book.cover, sourceUrl: book.sourceUrl, bookUrl: book.bookUrl }, Date.now())
      .catch((error: Error): void => this.report(error));
  }

  private clearWatchdog(): void {
    if (this.watchdog !== -1) clearTimeout(this.watchdog);
    this.watchdog = -1;
  }

  private nextId(): string { return `tts${Date.now()}n${++this.requestSequence}`; }

  private fail(error: Error, content: boolean = false): void {
    DiagnosticLogService.info('tts.failed', `${error.message}; foreground=${this.foreground}; offset=${this.state.charOffset}`);
    this.pause();
    this.releaseEngine();
    this.state.error = this.message(content ? $r('app.string.tts_content_error') : $r('app.string.tts_engine_error'));
    this.report(error);
  }

  private savedPosition(book: Book): SpeechPosition | null {
    const raw = this.store?.getSync(`position_${book.id}`, '');
    if (typeof raw !== 'string' || raw.length === 0) return null;
    try {
      const value: SpeechPosition = JSON.parse(raw);
      if (value === null || value.sourceUrl !== book.sourceUrl || value.bookUrl !== book.bookUrl ||
        typeof value.chapterUrl !== 'string' || !Number.isFinite(value.charOffset) || value.charOffset < 0) return null;
      return value;
    } catch (_error) { return null; }
  }

  currentChapterContent(): string { return this.chapterContent; }
  currentRawOffset(): number { return this.textDocument?.toRaw(this.state.charOffset) ?? this.state.charOffset; }

  hasSavedPosition(book: Book): boolean { return this.savedPosition(book) !== null; }

  private savePosition(force: boolean): void {
    const book = this.book;
    const store = this.store;
    if (store === null || book === null || (!force && Date.now() - this.lastSaveAt < 5000)) return;
    const chapter = book.chapters[this.state.chapterIndex];
    if (chapter === undefined) return;
    ReadingSessionService.end('reading');
    ReadingSessionService.checkpoint('tts', SessionLocation.audio(book, chapter,
      this.currentRawOffset(), this.textDocument?.rawLength ?? this.state.contentLength), this.state.playing);
    const value = new SpeechPosition();
    value.sourceUrl = book.sourceUrl;
    value.bookUrl = book.bookUrl;
    value.chapterUrl = chapter.originSourceValue || chapter.source.value;
    value.chapterIndex = this.state.chapterIndex;
    value.charOffset = this.currentRawOffset();
    try {
      store.putSync(`position_${book.id}`, JSON.stringify(value));
      if (this.context !== null) {
        const position = TextReadingPosition.atChar(book.id, this.state.chapterIndex, '',
          this.currentRawOffset(), 0, chapter.title);
        TextReadingProgressService.save(this.context, position).catch((): void => {});
      }
      this.lastSaveAt = Date.now();
      this.flush();
    } catch (_error) { this.state.error = this.message($r('app.string.tts_save_error')); }
  }

  private saveSettings(): void {
    if (this.store === null) return;
    try {
    this.store.putSync('speed', this.state.speed);
    this.store.putSync('person', this.state.person);
    this.store.putSync('language', this.state.language);
    this.store.putSync('follow', this.state.follow);
    this.store.putSync('customTtsId', this.state.customTtsId);
    this.flush();
    } catch (_error) { this.state.error = this.message($r('app.string.tts_save_error')); }
  }

  private flush(): void {
    const store = this.store;
    if (store === null) return;
    this.flushChain = this.flushChain.then((): Promise<void> => store.flush()).catch((error: Error): void => {
      this.state.error = this.message($r('app.string.tts_save_error'));
      this.report(error);
    });
  }

  private installSessionCallbacks(): void {
    const callbacks: AVSessionCallbacks = {
      onPlay: (): void => { this.resume(); }, onPause: (): void => this.pause(),
      onPlayNext: (): void => { this.moveChapter(1); },
      onPlayPrevious: (): void => { this.moveChapter(-1); },
      onFastForward: (_ms: number): void => this.skipSentence(1),
      onRewind: (_ms: number): void => this.skipSentence(-1),
      // TTS 没有精确时长，不把字符数伪装成毫秒或支持虚假的时间拖动。
      onSeek: (_ms: number): void => {}, onSetSpeed: (speed: number): void => this.setSpeed(speed),
      onSetLoopMode: (): void => {}, onCollection: (): void => { this.toggleFavorite(); },
      onCastConnected: (): void => this.pause()
    };
    AVSessionService.getInstance().setSpeechCallbacks(callbacks);
  }

  skipSentence(delta: number): void {
    if (this.segments.length === 0) return;
    this.pause();
    this.segmentIndex = Math.max(0, Math.min(this.segments.length - 1, this.segmentIndex + delta));
    this.state.charOffset = this.segments[this.segmentIndex].start;
    this.state.playbackOffset = this.state.charOffset;
    this.resume();
  }

  /** 按本章正文百分比定位到对应语音片段，保持原来的播放/暂停状态。 */
  seekProgress(percent: number): void {
    if (!Number.isFinite(percent) || !this.state.active || this.state.loading ||
      this.book === null || this.segments.length === 0 || this.state.contentLength <= 0) return;
    const playing = this.state.playing;
    const offset = Math.floor(Math.max(0, Math.min(100, percent)) * this.state.contentLength / 100);
    const index = Math.min(this.segments.length - 1, SpeechTextSegmenter.indexAt(this.segments, offset));
    this.pause();
    this.segmentIndex = index;
    const segment = this.segments[index];
    this.state.charOffset = segment.start;
    this.state.playbackOffset = segment.start;
    this.state.sentence = segment.text;
    this.highlightParagraph();
    this.savePosition(true);
    this.notify();
    if (playing) this.resume();
  }

  private async toggleFavorite(): Promise<void> {
    const book = this.book;
    if (book === null) return;
    try {
      const favorite = await PreferenceService.toggleFavorite(book.id);
      if (favorite) await DataService.upsertCachedBook(book);
      this.syncSession();
    } catch (error) { this.report(error instanceof Error ? error : new Error(String(error))); }
  }

  private publishMetadata(): void {
    if (this.book === null) return;
    AVSessionService.getInstance().updateMetadata(this.book, this.book.chapters[this.state.chapterIndex], true);
  }

  private async syncSession(): Promise<void> {
    if (!PlaybackCoordinator.speechActive || this.book === null) return;
    const ticket = this.generation;
    const favorite = await PreferenceService.isFavorite(this.book.id).catch((): boolean => false);
    if (!this.valid(ticket)) return;
    await AVSessionService.getInstance().updatePlaybackState(this.state.playing, 0, this.state.speed, 0, favorite, true);
  }

  private acquireFocus(ticket: number): Promise<void> {
    const task = this.focusChain.catch((): void => {}).then(async (): Promise<void> => {
      if (!this.valid(ticket)) return;
      if (this.audioSession === null) {
        this.audioSession = audio.getAudioManager().getSessionManager();
        this.audioSession.on('audioSessionDeactivated', this.onDeactivated);
      }
      if (this.routing === null) {
        this.routing = audio.getAudioManager().getRoutingManager();
        this.routing.on('deviceChange', audio.DeviceFlag.OUTPUT_DEVICES_FLAG, this.onDeviceChange);
      }
      await this.audioSession.activateAudioSession({ concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT });
    });
    this.focusChain = task;
    return task;
  }

  private releaseFocus(): void {
    this.focusChain = this.focusChain.catch((): void => {}).then(async (): Promise<void> => {
      if (this.audioSession !== null) {
        this.audioSession.off('audioSessionDeactivated', this.onDeactivated);
        await this.audioSession.deactivateAudioSession().catch((): void => {});
        this.audioSession = null;
      }
      if (this.routing !== null) {
        this.routing.off('deviceChange', this.onDeviceChange);
        this.routing = null;
      }
    }).catch((error: Error): void => this.report(error));
  }
}
