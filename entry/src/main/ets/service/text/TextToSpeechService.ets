import { ReaderFloatingService } from './ReaderFloatingService';
import { DesktopLyricText } from '../../model/DesktopLyric';
import { PlatformCompat } from '../../utils/PlatformCompat';
import { TextReadingPosition } from '../../model/TextReading';
import { ReaderTextDocument } from '../../model/ReaderTools';
import { ReaderToolsService } from './ReaderToolsService';
import { TextReadingProgressService } from './TextReadingProgressService';
import { LibrarySyncActivity } from '../sync/LibrarySyncModel';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { CustomTtsConfigParser } from './CustomTtsConfigParser';
import { HttpTtsAudioOutput, HttpTtsPlayer, HttpTtsFailure } from './HttpTtsPlayer';
import { SpeechPcmBuffer } from './SpeechPcmBuffer';
import { DiagnosticLogService } from '../DiagnosticLogService';
import { ReadingSessionService, SessionLocation } from '../ReadingSessionService';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { SpeechSynthesisSettings } from '../../model/SpeechSynthesisSettings';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemDateTime } from '@kit.BasicServicesKit';
import { Book } from '../../model/Book';
import { SpeechPosition, SpeechVoice, TextToSpeechState } from '../../model/TextToSpeechState';
import { StatsService } from '../StatsService';
import { AudioService } from '../AudioService';
import { AudioFocusService } from '../AudioFocusService';
import { AVSessionCallbacks, AVSessionService } from '../AVSessionService';
import { BackgroundTaskService } from '../BackgroundTaskService';
import { PlaybackCoordinator } from '../PlaybackCoordinator';
import { PreferenceService } from '../PreferenceService';
import { TextChapterPreloader } from './TextChapterPreloader';
import { DataService } from '../DataService';
import { BookSourceService } from '../BookSourceService';
import { WidgetUpdater } from '../WidgetUpdater';
import { OnlineTextContentCache } from './OnlineTextContentCache';
import { OnlineTextPaginator } from './OnlineTextPaginator';
import { SpeechSegment, SpeechTextSegmenter } from './SpeechTextSegmenter';

/** 有界预取下一章开头片段；身份、文本均匹配才交给当前播放队列。 */
class NextChapterSpeech {
  key: string = '';
  raw: string = '';
  segments: SpeechSegment[] = [];
  cancelled: boolean = false;
  tasks: Map<number, HttpTtsPlayer> = new Map();
  started: number = 0;
  preparation: Promise<void> = Promise.resolve();

  cancel(): void {
    this.cancelled = true;
    this.tasks.forEach((task: HttpTtsPlayer): void => task.cancel());
    this.tasks.clear();
  }
}

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
  private httpPrefetchTimer: number = -1;
  private unavailableVoices: Map<string, number> = new Map();
  private httpTasks: Map<number, HttpTtsPlayer> = new Map();
  private nextChapterSpeech: NextChapterSpeech | null = null;
  private httpOutput: HttpTtsAudioOutput = new HttpTtsAudioOutput(
    (event: audio.InterruptEvent): void => AudioFocusService.getInstance().handleInterrupt('speech', event),
    (): void => this.pause(),
    (): Promise<boolean> => AudioFocusService.getInstance().ensureActive('speech'));
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
  private focusPaused: boolean = false;
  private routing: audio.AudioRoutingManager | null = null;
  private focusChain: Promise<void> = Promise.resolve();
  private prefetchedKey: string = '';
  private prefetchedText: string = '';
  private textPreloader: TextChapterPreloader = new TextChapterPreloader();
  private readonly onDeviceChange = (event: audio.DeviceChangeAction): void => {
    if (event.type === audio.DeviceChangeType.DISCONNECT && (this.state.playing || this.state.loading || this.focusPaused)) {
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
    AVSessionService.getInstance().addDesktopLyricListener(this.syncDesktopLyric);
    PlaybackCoordinator.stopSpeech = (): Promise<void> => { this.stop(true); return this.focusChain; };
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
    const gain = this.store.getSync('loudnessGain', 0);
    this.state.loudnessGain = typeof gain === 'number' && Number.isFinite(gain) ?
      Math.max(0, Math.min(24, Math.round(gain))) : 0;
    await this.httpOutput.setLoudnessGain(this.state.loudnessGain);
    const speed = this.store.getSync('speed', 1);
    const person = this.store.getSync('person', 13);
    const language = this.store.getSync('language', 'zh-CN');
    const follow = this.store.getSync('follow', true);
    const synthesis = this.store.getSync('synthesis', '{}');
    this.state.synthesis = SpeechSynthesisSettings.parse(typeof synthesis === 'string' ? synthesis : '{}');
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
    this.syncDesktopLyric();
    if (this.state.active && this.audibleBookId === this.book?.id &&
      this.audibleChapterId === this.book?.chapters[this.state.chapterIndex]?.id) {
      ReaderFloatingService.update(this.state.bookTitle, this.chapterContent, this.audibleOffset, true);
    }
    this.syncPlayerCard();
    if (!this.foreground) return;
    this.listeners.forEach((listener: () => void): void => listener());
  }

  private readonly syncDesktopLyric = (): void => {
    if (!this.state.active || !this.book || !PlaybackCoordinator.speechActive) return;
    const chapter = this.book.chapters[this.state.chapterIndex];
    if (!chapter) return;
    // 排队/合成会先移动逻辑位置，只记录实际出声的位置；暂停或下一段等待时保留末句。
    if (this.audibleRequestId && this.audibleRequestId === this.requestId) {
      this.audibleBookId = this.book.id;
      this.audibleChapterId = chapter.id;
      this.audibleOffset = this.state.playbackOffset;
      this.audibleLyric = DesktopLyricText.speech(this.chapterContent, this.audibleOffset);
    }
    const text = this.audibleBookId === this.book.id && this.audibleChapterId === chapter.id ? this.audibleLyric : '';
    AVSessionService.getInstance().updateDesktopLyric(this.book.id, chapter.id,
      text ? '[00:00.00]' + text : '', true);
  };

  private audibleRequestId: string = '';
  private audibleBookId: string = '';
  private audibleChapterId: string = '';
  private audibleOffset: number = 0;
  private audibleLyric: string = '';

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
    if (resume) await this.resume(false);
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
    this.unavailableVoices.delete(id);
    if (id && !this.state.customTtsConfigs.some((item: CustomTtsConfig): boolean => item.id === id && item.enabled)) return;
    const resume = this.state.playing || this.state.loading;
    this.pause();
    this.releaseEngine();
    this.state.customTtsId = id;
    this.rebuildSpeechSegments();
    this.state.error = '';
    this.saveSettings();
    if (resume) await this.resume(false);
  }

  async setCustomTtsEnabled(id: string, enabled: boolean): Promise<void> {
    await this.updateCustomTtsBatch([id], false, enabled);
  }

  async removeCustomTts(id: string): Promise<void> {
    await this.updateCustomTtsBatch([id], true, false);
  }

  /** 整批只持久化一次，成功后发布状态，当前音色失效时只切换一次。 */
  async updateCustomTtsBatch(ids: string[], remove: boolean, enabled: boolean): Promise<void> {
    const selected = new Set<string>(ids);
    const catalog: CustomTtsConfig[] = [];
    for (const item of this.state.customTtsConfigs) {
      if (!selected.has(item.id)) { catalog.push(item); continue; }
      if (remove) continue;
      const updated: CustomTtsConfig = {
        id: item.id, name: item.name, group: item.group, tier: item.tier, enabled: enabled, url: item.url,
        method: item.method, body: item.body, header: item.header, contentType: item.contentType
      };
      catalog.push(updated);
    }
    await this.saveCustomTtsCatalog(catalog);
    if (selected.has(this.state.customTtsId) && (remove || !enabled)) await this.selectCustomTts('');
  }

  /** 只调整指定音色占用的位置，筛选外的音色保持原位。 */
  async reorderCustomTts(ids: string[]): Promise<void> {
    const byId = new Map<string, CustomTtsConfig>();
    for (const item of this.state.customTtsConfigs) byId.set(item.id, item);
    const ordered: CustomTtsConfig[] = [];
    const selected = new Set<string>();
    for (const id of ids) {
      const item = byId.get(id);
      if (item && !selected.has(id)) { ordered.push(item); selected.add(id); }
    }
    let index = 0;
    const catalog = this.state.customTtsConfigs.map((item: CustomTtsConfig): CustomTtsConfig =>
      selected.has(item.id) ? ordered[index++] : item);
    await this.saveCustomTtsCatalog(catalog);
  }

  private async saveCustomTtsCatalog(catalog: CustomTtsConfig[]): Promise<void> {
    const store = this.store;
    if (store === null) throw new Error('TTS store unavailable');
    const previous = this.state.customTtsConfigs;
    store.putSync('customTtsCatalog', JSON.stringify(catalog));
    try { await store.flush(); }
    catch (_error) { store.putSync('customTtsCatalog', JSON.stringify(previous)); throw new Error('TTS save failed'); }
    this.state.customTtsConfigs = catalog;
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

  async setLoudnessGain(gain: number): Promise<void> {
    if (this.initPromise !== null) await this.initPromise;
    if (this.store === null) { this.state.error = this.message($r('app.string.tts_save_error')); return; }
    if (this.state.loudnessBusy) return;
    this.state.loudnessBusy = true;
    try {
      if (await this.httpOutput.setLoudnessGain(gain)) {
        this.state.loudnessGain = Math.round(gain);
        this.saveSettings();
        await this.flushChain;
      } else this.state.error = this.message($r('app.string.player_volume_boost_failed'));
    } finally { this.state.loudnessBusy = false; }
  }

  setSpeed(speed: number): void {
    if (!Number.isFinite(speed)) return;
    const next = Math.round(Math.max(0.5, Math.min(3, speed)) * 100) / 100;
    if (next === this.state.speed) return;
    const config = this.state.customTtsConfigs.find((item: CustomTtsConfig): boolean => item.id === this.state.customTtsId);
    if (config && !CustomTtsConfigParser.usesSpeed(config)) {
      try { this.httpOutput.setPlaybackSpeed(next); }
      catch (_error) { this.pause(); this.state.error = this.message($r('app.string.tts_custom_play_error')); this.notify(); return; }
      this.state.speed = next;
      this.saveSettings();
      this.syncSession();
      this.notify();
      hilog.info(0x0000, 'SpeechFlow', 'local playback speed=%{public}s', String(next));
      return;
    }
    const resume = this.state.playing || this.state.loading;
    this.pause();
    this.state.speed = next;
    this.saveSettings();
    if (resume) this.resume(false);
  }

  setFollow(follow: boolean): void {
    this.state.follow = follow;
    this.saveSettings();
    this.notify();
  }

  async setSynthesisSettings(value: SpeechSynthesisSettings): Promise<void> {
    if (!SpeechSynthesisSettings.validRules(value.replacements)) throw new Error('Invalid TTS replacement rules');
    const store = this.store;
    if (store === null) throw new Error('TTS settings unavailable');
    const next = SpeechSynthesisSettings.normalize(value);
    if (this.chapterContent.length > 0) SpeechTextSegmenter.batches(this.chapterContent, next, this.state.customTtsId.length > 0);
    const previous = this.state.synthesis;
    store.putSync('synthesis', JSON.stringify(next));
    try { await store.flush(); }
    catch (error) { store.putSync('synthesis', JSON.stringify(previous)); throw new Error(String(error)); }
    const resume = this.state.playing || this.state.loading;
    this.pause();
    this.state.synthesis = next;
    if (this.chapterContent.length > 0) this.rebuildSpeechSegments();
    this.notify();
    if (resume) this.resume(false);
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
    const nextSpeech = !restore && offset === 0 ? this.matchNextChapterSpeech(book, chapterIndex) : null;
    // 手动点击已预取的下一章与自然跨章一样复用；普通暂停仍取消预取。
    if (nextSpeech !== null) this.nextChapterSpeech = null;
    this.pause();
    this.nextChapterSpeech = nextSpeech;
    this.audibleRequestId = '';
    this.audibleBookId = '';
    this.audibleChapterId = '';
    this.audibleLyric = '';
    if (this.book !== null && this.book.id !== book.id) { this.setSleep(0); this.pendingListenMs = 0; }
    this.focusPaused = false;
    AudioFocusService.getInstance().cancelRecovery('speech');
    const ticket = ++this.generation;
    if (restore) {
      await LibrarySyncActivity.prepareResume(book.id);
      if (ticket !== this.generation) return;
    }
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
      if (restore && LibrarySyncActivity.remoteText.has(book.id)) {
        const remote = await TextReadingProgressService.get(context, book.id);
        if (!this.valid(ticket)) return;
        if (remote !== null) {
          const titleIndex = book.chapters.findIndex((chapter): boolean => chapter.title === remote.chapterTitle);
          chapterIndex = titleIndex >= 0 ? titleIndex : remote.resourceIndex;
          offset = remote.charOffset;
        }
      } else if (restore) {
        const saved = this.savedPosition(book);
        if (saved !== null) {
          const index = book.chapters.findIndex((chapter): boolean =>
            (chapter.originSourceValue || chapter.source.value) === saved.chapterUrl);
          // 目录重排时只按原章节 URL 恢复，删除的章节回退用户当前阅读位置。
          if (index >= 0) { chapterIndex = index; offset = saved.charOffset; }
        }
      }
      LibrarySyncActivity.remoteText.delete(book.id);
      this.state.chapterIndex = Math.max(0, Math.min(chapterIndex, book.chapters.length - 1));
      this.state.charOffset = Math.max(0, offset);
      this.state.playbackOffset = this.state.charOffset;
      await this.preparePlayback(ticket);
      if (!this.valid(ticket)) return;
      await this.loadChapter(this.state.chapterIndex, this.state.charOffset, ticket);
    } catch (error) {
      if (this.valid(ticket)) this.fail(error instanceof Error ? error : new Error(String(error)));
    }
  }

  /** 暂停时手动阅读只移动续读位置，不启动合成；系统媒体键也沿用此位置。 */
  followPausedReading(bookId: string, chapterIndex: number, rawOffset: number): void {
    if (!this.state.active || this.state.playing || this.state.loading || this.book === null ||
      this.book.id !== bookId || !Number.isInteger(chapterIndex) || chapterIndex < 0 ||
      chapterIndex >= this.book.chapters.length || !Number.isFinite(rawOffset)) return;
    AudioFocusService.getInstance().cancelRecovery('speech');
    this.focusPaused = false;
    this.generation++;
    this.clearHttpPrefetch();
    if (chapterIndex !== this.state.chapterIndex) {
      this.chapterContent = '';
      this.textDocument = null;
      this.state.contentLength = 0;
    }
    this.state.chapterIndex = chapterIndex;
    this.state.chapterTitle = this.book.chapters[chapterIndex].title;
    this.state.charOffset = this.textDocument?.toDisplay(Math.max(0, rawOffset)) ?? Math.max(0, rawOffset);
    this.state.playbackOffset = this.state.charOffset;
    this.segments = [];
    this.segmentIndex = 0;
    this.state.sentence = '';
    this.state.highlightOffset = -1;
    this.state.highlightEnd = -1;
    this.state.error = '';
    LibrarySyncActivity.remoteText.delete(bookId);
    this.savePosition(true, false);
    this.publishMetadata();
    this.notify();
  }

  async resume(checkCloud: boolean = true): Promise<void> {
    if (this.state.playing || this.state.loading || this.book === null) return;
    const resumeBook = this.book;
    const resumeTicket = ++this.generation;
    if (checkCloud) await LibrarySyncActivity.prepareResume(resumeBook.id);
    if (resumeTicket !== this.generation || this.book !== resumeBook || this.state.playing || this.state.loading) return;
    if (LibrarySyncActivity.remoteText.has(resumeBook.id) && this.context !== null) {
      const remote = await TextReadingProgressService.get(this.context, resumeBook.id);
      if (resumeTicket !== this.generation || this.book !== resumeBook) return;
      if (remote !== null) {
        const titleIndex = resumeBook.chapters.findIndex((chapter): boolean => chapter.title === remote.chapterTitle);
        const index = titleIndex >= 0 ? titleIndex : remote.resourceIndex;
        await this.start(resumeBook, index, remote.charOffset, false);
        return;
      }
      LibrarySyncActivity.remoteText.delete(resumeBook.id);
    }
    this.focusPaused = false;
    AudioFocusService.getInstance().cancelRecovery('speech');
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
        if (this.state.charOffset > (this.segments[this.segmentIndex]?.start ?? 0)) this.rebuildSpeechSegments();
        this.publishMetadata();
        this.speakNext(ticket);
      }
    } catch (error) {
      if (this.valid(ticket)) this.fail(error instanceof Error ? error : new Error(String(error)));
    }
  }

  pause(forFocus: boolean = false): void {
    this.focusPaused = forFocus;
    if (!forFocus) this.releaseFocus();
    this.state.charOffset = Math.max(this.state.charOffset, this.state.playbackOffset);
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
    this.notify();
  }

  stop(preserveDesktopLyric: boolean = false): void {
    this.pause();
    this.setSleep(0);
    this.releaseEngine();
    this.state.active = false;
    AVSessionService.getInstance().endSpeechPlayback(!preserveDesktopLyric);
    PlaybackCoordinator.speechActive = false;
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
    const nextSpeech = offset === 0 ? this.matchNextChapterSpeech(book, index) : null;
    this.clearHttpPrefetch(nextSpeech !== null);
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
      // preparation 只等待正文/分段就绪；音频尚未完成时继续复用同一请求，不重复合成。
      if (nextSpeech !== null) await nextSpeech.preparation;
      if (!this.valid(ticket)) return;
      const raw = nextSpeech !== null && !nextSpeech.cancelled && nextSpeech.raw ? nextSpeech.raw :
        await this.fetchChapter(book, index);
      const document = this.context ? await ReaderToolsService.render(this.context, book.id, raw) : ReaderTextDocument.original(raw);
      if (!this.valid(ticket)) return;
      const content = document.content;
      this.textDocument = document;
      this.state.charOffset = document.toDisplay(offset);
      this.state.playbackOffset = this.state.charOffset;
      this.chapterContent = content;
      this.rebuildSpeechSegments();
      if (this.segments.length === 0 && content.trim().length === 0) throw new Error('Empty chapter');
      this.state.contentLength = content.length;
      this.segmentIndex = SpeechTextSegmenter.indexAt(this.segments, this.state.charOffset);
      if (nextSpeech !== null && !nextSpeech.cancelled &&
        this.matchNextChapterSpeech(book, index) === nextSpeech && this.segmentIndex === 0) {
        nextSpeech.tasks.forEach((task: HttpTtsPlayer, part: number): void => {
          if (this.segments[part]?.text === nextSpeech.segments[part]?.text) {
            this.httpTasks.set(part, task);
            nextSpeech.tasks.delete(part);
          }
        });
        hilog.info(0x0000, 'SpeechFlow', 'next chapter speech reused chapter=%{public}d parts=%{public}d', index, this.httpTasks.size);
      }
      this.clearNextChapterSpeech();
      this.speakNext(ticket);
      this.prefetch(book, index + 1, ticket);
    } catch (error) {
      if (this.valid(ticket)) this.fail(error instanceof Error ? error : new Error(String(error)), true);
    }
  }

  private async fetchChapter(book: Book, index: number): Promise<string> {
    const chapter = book.chapters[index];
    const url = chapter.originSourceValue || chapter.source.value;
    const key = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id, url);
    if (key === this.prefetchedKey && this.prefetchedText) return this.prefetchedText;
    const context = this.context;
    if (context !== null) {
      const saved = await OnlineTextContentCache.read(context, key);
      if (saved !== undefined) {
        hilog.info(0x0000, 'SpeechFlow', 'text cache hit chapter=%{public}d', index);
        return saved;
      }
    }
    hilog.info(0x0000, 'SpeechFlow', 'text cache miss chapter=%{public}d', index);
    const value = await BookSourceService.getTextChapterContent(book, url, chapter.title, chapter.variables);
    const content = value.commentsLoaded ? value.content : OnlineTextPaginator.normalizeContent(value.content);
    if (context !== null) await OnlineTextContentCache.write(context, key, content, value.comments, value.commentsLoaded);
    return content;
  }

  private async prefetch(book: Book, index: number, ticket: number): Promise<void> {
    if (index < 0 || index >= book.chapters.length) return;
    this.textPreloader.start(index - 1, book.chapters.length, async (next: number): Promise<void> => {
      const content = await this.fetchChapter(book, next);
      if (!this.valid(ticket) || next !== index) return;
      const chapter = book.chapters[next];
      this.prefetchedKey = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id,
        chapter.originSourceValue || chapter.source.value);
      this.prefetchedText = content;
    }, (): boolean => this.valid(ticket));
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
      }, this.state.customTtsId ? (this.state.synthesis.timeoutSeconds * 4 + 2) *
        (this.state.synthesis.retries + 1) * 1000 + 30000 : 150000);
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
    // 每个片段都提前合成下一片段，滚动阅读/后台朗读也不等待段间重新请求。
    if (!segment || this.nextSystemId.length > 0 ||
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
    this.prefetchSystemPage();
    const player = new HttpTtsPlayer();
    this.httpPlayer = player;
    this.httpPlaybackChain = this.httpPlaybackChain.catch((): void => {}).then(async (): Promise<void> => {
      if (!this.valid(ticket) || id !== this.requestId) return;
      try {
        await player.speakAudio(context, buffer, Math.max(1, this.state.speed / 2), id, (): void => {
          if (!this.valid(ticket) || id !== this.requestId) return;
          this.audibleRequestId = id;
          if (this.spokenSince < 0) this.spokenSince = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
          this.highlightParagraph();
          this.logCrossPagePlayback(id);
          this.state.loading = false;
          this.state.playing = true;
          this.clearWatchdog();
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

  private clearHttpPrefetch(preserveNextChapter: boolean = false): void {
    if (this.httpPrefetchTimer !== -1) clearTimeout(this.httpPrefetchTimer);
    this.httpPrefetchTimer = -1;
    if (!preserveNextChapter) this.clearNextChapterSpeech();
    this.nextSystemId = '';
    this.nextSystemIndex = -1;
    this.nextSystemAudio = null;
    this.nextSystemPcm.reset();
    this.httpTasks.forEach((task: HttpTtsPlayer): void => task.cancel());
    this.httpTasks.clear();
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
    this.syncDesktopLyric();
    const previousParagraph = this.state.highlightOffset;
    this.highlightParagraph();
    if (this.state.highlightOffset !== previousParagraph && this.state.highlightOffset >= 0) {
      this.state.charOffset = Math.max(this.state.charOffset, this.state.highlightOffset);
      this.savePosition(false);
      this.notify();
    }
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
    if (this.state.charOffset > 0) {
      pageEnds.push(this.state.charOffset);
    }
    this.segments = SpeechTextSegmenter.batches(this.chapterContent, this.state.synthesis, this.state.customTtsId.length > 0, pageEnds);
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

  private prefetchHttp(config: CustomTtsConfig, ticket: number, playing: boolean = false, headStarted: boolean = false): void {
    // 当前请求占一个槽位；进入播放后补齐后续预取，有界并发可按提供方限制调整。
    const first = !playing && !headStarted && !this.httpTasks.has(this.segmentIndex);
    const end = Math.min(this.segments.length, this.segmentIndex + (first ? 1 : this.state.synthesis.concurrency) + (playing ? 1 : 0));
    if (first) {
      if (this.httpPrefetchTimer !== -1) clearTimeout(this.httpPrefetchTimer);
      this.httpPrefetchTimer = setTimeout((): void => {
        this.httpPrefetchTimer = -1;
        if (this.valid(ticket)) this.prefetchHttp(config, ticket, false, true);
      }, 600);
    }
    const speed = this.state.speed;
    for (let index = this.segmentIndex; index < end; index++) {
      if (this.httpTasks.has(index)) continue;
      const task = new HttpTtsPlayer(this.state.synthesis.timeoutSeconds, this.state.synthesis.retries);
      const text = this.segments[index].text;
      this.httpTasks.set(index, task);
      if (!this.valid(ticket)) return;
      task.prepare(config, text, speed).then((): void => {
        if (!this.valid(ticket)) return;
        if (first) {
          if (this.httpPrefetchTimer !== -1) clearTimeout(this.httpPrefetchTimer);
          this.httpPrefetchTimer = -1;
          this.prefetchHttp(config, ticket, false, true);
        }
        this.prefetchNextChapterSpeech(config);
      }).catch((): void => { /* 到该段时由播放路径处理已重试的失败。 */ });
    }
    if (playing && this.segments.length - this.segmentIndex - 1 < this.state.synthesis.concurrency) {
      this.prefetchNextChapterSpeech(config);
    }
  }

  private nextChapterSpeechKey(book: Book, index: number): string {
    const chapter = book.chapters[index];
    const config = this.state.customTtsConfigs.find((item: CustomTtsConfig): boolean => item.id === this.state.customTtsId);
    if (!chapter || !config || !config.enabled) return '';
    return JSON.stringify([book.id, book.sourceUrl, book.bookUrl || book.id,
      chapter.originSourceValue || chapter.source.value, chapter.variables,
      config, CustomTtsConfigParser.usesSpeed(config) ? this.state.speed : 1, this.state.synthesis]);
  }

  private matchNextChapterSpeech(book: Book, index: number): NextChapterSpeech | null {
    const slot = this.nextChapterSpeech;
    return slot !== null && !slot.cancelled && slot.key === this.nextChapterSpeechKey(book, index) ? slot : null;
  }

  private clearNextChapterSpeech(): void {
    this.nextChapterSpeech?.cancel();
    this.nextChapterSpeech = null;
  }

  private prefetchNextChapterSpeech(config: CustomTtsConfig): void {
    const book = this.book;
    const context = this.context;
    if (book === null || context === null || this.state.stopAtChapterEnd ||
      !this.state.playing || this.state.loading) return;
    if (this.segments.length - this.segmentIndex - 1 >= this.state.synthesis.concurrency) return;
    if (this.nextChapterSpeech !== null) { this.fillNextChapterSpeech(this.nextChapterSpeech, config); return; }
    const index = this.state.chapterIndex + 1;
    const key = this.nextChapterSpeechKey(book, index);
    if (!key) return;
    const slot = new NextChapterSpeech();
    slot.key = key;
    this.nextChapterSpeech = slot;
    const settings = SpeechSynthesisSettings.normalize(this.state.synthesis);
    slot.preparation = (async (): Promise<void> => {
      try {
        const raw = await this.fetchChapter(book, index);
        if (slot.cancelled) return;
        const document = await ReaderToolsService.render(context, book.id, raw);
        if (slot.cancelled) return;
        slot.segments = SpeechTextSegmenter.batches(document.content, settings, true);
        slot.raw = raw;
        this.fillNextChapterSpeech(slot, config);
      } catch (_error) { /* 下一章失败不打断当前音频；到章时再按普通路径加载。 */ }
    })();
  }

  private fillNextChapterSpeech(slot: NextChapterSpeech, config: CustomTtsConfig): void {
    if (slot.cancelled || this.nextChapterSpeech !== slot || this.state.loading || !this.state.playing) return;
    const settings = this.state.synthesis;
    let pending = 0;
    this.httpTasks.forEach((task: HttpTtsPlayer): void => { if (!task.ready && task !== this.httpPlayer) pending++; });
    slot.tasks.forEach((task: HttpTtsPlayer): void => { if (!task.ready) pending++; });
    const limit = Math.min(slot.segments.length, settings.concurrency + 1);
    while (pending < settings.concurrency && slot.started < limit) {
      const part = slot.started++;
      const task = new HttpTtsPlayer(settings.timeoutSeconds, settings.retries);
      slot.tasks.set(part, task);
      pending++;
      hilog.info(0x0000, 'SpeechFlow', 'next chapter speech prepare part=%{public}d', part);
      task.prepare(config, slot.segments[part].text, this.state.speed).then((): void => {
        this.fillNextChapterSpeech(slot, config);
      }).catch((): void => {
        if (slot.tasks.get(part) === task) { task.cancel(); slot.tasks.delete(part); }
        this.fillNextChapterSpeech(slot, config);
      });
    }
  }

  private speakHttp(text: string, id: string, ticket: number): void {
    const config = this.state.customTtsConfigs.find((item: CustomTtsConfig): boolean => item.id === this.state.customTtsId);
    const context = this.context;
    if (!config || context === null) { this.fail(new Error('TTS config unavailable')); return; }
    const unavailableUntil = this.unavailableVoices.get(config.id) ?? 0;
    if (unavailableUntil > Date.now()) {
      this.pause();
      this.state.error = this.message($r('app.string.tts_error_voice'));
      this.notify();
      return;
    }
    this.unavailableVoices.delete(config.id);
    this.prefetchHttp(config, ticket);
    const index = this.segmentIndex;
    const player = this.httpTasks.get(index);
    if (!player) { this.fail(new Error('TTS task unavailable')); return; }
    this.state.loading = !player.ready;
    this.state.playing = player.ready;
    hilog.info(0x0000, 'SpeechQueue', 'enqueue chapter=%{public}d part=%{public}d ready=%{public}s',
      this.state.chapterIndex, index, String(player.ready));
    // 等待上一任务释放播放器，避免切换配置时两种声音重叠。
    this.httpPlaybackChain = this.httpPlaybackChain.catch((): void => {}).then(async (): Promise<void> => {
      if (!this.valid(ticket) || id !== this.requestId) return;
      this.httpPlayer = player;
      hilog.info(0x0000, 'SpeechQueue', 'consume chapter=%{public}d part=%{public}d', this.state.chapterIndex, index);
      try {
        await player.speak(context, config, text, this.state.speed, id, (): void => {
          if (!this.valid(ticket) || id !== this.requestId) return;
          this.audibleRequestId = id;
          if (this.spokenSince < 0) this.spokenSince = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
          this.state.loading = false;
          this.state.playing = true;
          this.clearWatchdog();
          this.prefetchHttp(config, ticket, true);
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
      } catch (error) {
        if (this.valid(ticket) && id === this.requestId) {
          this.pause();
          if (error instanceof HttpTtsFailure && error.kind === 'voice') {
            this.unavailableVoices.set(config.id, Date.now() + 5 * 60 * 1000);
          }
          this.state.error = this.httpFailureMessage(error instanceof HttpTtsFailure ? error.kind : 'playback');
          this.notify();
        }
      } finally {
        if (this.httpPlayer === player) this.httpPlayer = null;
      }
    });
  }

  private httpFailureMessage(kind: string): string {
    if (kind === 'auth') return this.message($r('app.string.tts_error_auth'));
    if (kind === 'rate') return this.message($r('app.string.tts_error_rate'));
    if (kind === 'server') return this.message($r('app.string.tts_error_server'));
    if (kind === 'config') return this.message($r('app.string.tts_error_config'));
    if (kind === 'network') return this.message($r('app.string.tts_error_network'));
    if (kind === 'audio') return this.message($r('app.string.tts_error_audio'));
    if (kind === 'voice') return this.message($r('app.string.tts_error_voice'));
    return this.message($r('app.string.tts_custom_play_error'));
  }

  setForeground(foreground: boolean): void {
    this.foreground = foreground;
    if (foreground) this.notify();
  }

  private highlightParagraph(): void {
    const segment = this.segments[this.segmentIndex];
    if (!segment) return;
    const offset = Math.max(segment.start + segment.leadingWhitespace, this.state.playbackOffset);
    const start = this.chapterContent.lastIndexOf('\n', Math.max(0, offset - 1)) + 1;
    const end = this.chapterContent.indexOf('\n', offset);
    if (this.state.highlightOffset !== start) this.state.highlightOffset = start;
    const paragraphEnd = end < 0 ? this.chapterContent.length : end;
    if (this.state.highlightEnd !== paragraphEnd) this.state.highlightEnd = paragraphEnd;
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

  private savePosition(force: boolean, updateSession: boolean = true): void {
    const book = this.book;
    const store = this.store;
    if (book !== null && !this.state.playing && !this.state.loading && LibrarySyncActivity.remoteText.has(book.id)) return;
    if (store === null || book === null || (!force && Date.now() - this.lastSaveAt < 5000)) return;
    const chapter = book.chapters[this.state.chapterIndex];
    if (chapter === undefined) return;
    if (updateSession) {
      ReadingSessionService.end('reading');
      ReadingSessionService.checkpoint('tts', SessionLocation.audio(book, chapter,
        this.currentRawOffset(), this.textDocument?.rawLength ?? this.state.contentLength), this.state.playing);
    }
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
    this.store.putSync('loudnessGain', this.state.loudnessGain);
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
    const sentences = SpeechTextSegmenter.split(this.chapterContent);
    if (sentences.length === 0) return;
    const current = SpeechTextSegmenter.indexAt(sentences, this.state.playbackOffset);
    const target = Math.max(0, Math.min(sentences.length - 1, current + delta));
    this.pause();
    this.state.charOffset = sentences[target].start;
    this.state.playbackOffset = this.state.charOffset;
    this.rebuildSpeechSegments();
    if (this.book) LibrarySyncActivity.remoteText.delete(this.book.id);
    this.resume(false);
  }

  /** 按本章正文百分比定位到对应语音片段，保持原来的播放/暂停状态。 */
  seekProgress(percent: number): void {
    if (!Number.isFinite(percent) || !this.state.active ||
      this.book === null || this.segments.length === 0 || this.state.contentLength <= 0) return;
    const playing = this.state.playing || this.state.loading;
    const offset = Math.floor(Math.max(0, Math.min(100, percent)) * this.state.contentLength / 100);
    const sentences = SpeechTextSegmenter.split(this.chapterContent);
    if (sentences.length === 0) return;
    const index = Math.min(sentences.length - 1, SpeechTextSegmenter.indexAt(sentences, offset));
    const target = sentences[index].start;
    const current = this.segments[this.segmentIndex];
    if (!this.state.loading && this.state.playing && current && target >= current.start && target < current.end &&
      this.httpOutput.seekRatio((target - current.start) / Math.max(1, current.end - current.start))) {
      // 提供方无逐字时间戳，以当前片段的正文比例定位音频，不重新合成。
      this.state.charOffset = target;
      this.state.playbackOffset = target;
      this.highlightParagraph();
      this.savePosition(true);
      this.notify();
      hilog.info(0x0000, 'SpeechFlow', 'seek reused playing audio offset=%{public}d', target);
      return;
    }
    // 暂时摘下尚未播放的任务，停止旧播放器后按范围及文本重新匹配。
    const savedTasks = new Map<number, HttpTtsPlayer>();
    const previousSegments = this.segments;
    this.httpTasks.forEach((task: HttpTtsPlayer, part: number): void => {
      if (task !== this.httpPlayer) { savedTasks.set(part, task); this.httpTasks.delete(part); }
    });
    this.pause();
    if (this.book) LibrarySyncActivity.remoteText.delete(this.book.id);
    this.state.charOffset = target;
    this.state.playbackOffset = this.state.charOffset;
    this.rebuildSpeechSegments();
    savedTasks.forEach((task: HttpTtsPlayer, part: number): void => {
      const old = previousSegments[part];
      const match = this.segments.findIndex((item: SpeechSegment): boolean => old !== undefined &&
        item.start === old.start && item.end === old.end && item.text === old.text);
      if (playing && match >= this.segmentIndex && match < this.segmentIndex + this.state.synthesis.concurrency + 1) {
        this.httpTasks.set(match, task);
      } else task.cancel();
    });
    const segment = this.segments[this.segmentIndex];
    if (!segment) return;
    this.state.sentence = segment.text;
    this.highlightParagraph();
    this.savePosition(true);
    this.notify();
    if (playing) this.resume(false);
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
    this.syncDesktopLyric();
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
      if (this.routing === null) {
        this.routing = audio.getAudioManager().getRoutingManager();
        this.routing.on('deviceChange', audio.DeviceFlag.OUTPUT_DEVICES_FLAG, this.onDeviceChange);
      }
      await AudioFocusService.getInstance().acquire('speech', (): void => {
        if (this.state.playing || this.state.loading) this.pause(true);
      }, async (): Promise<void> => {
        if (!this.focusPaused || !PlaybackCoordinator.speechActive) return;
        this.focusPaused = false;
        await this.resume(false);
      });
    });
    this.focusChain = task;
    return task;
  }

  private releaseFocus(): void {
    const release = AudioFocusService.getInstance().release('speech');
    if (this.routing !== null) {
      this.routing.off('deviceChange', this.onDeviceChange);
      this.routing = null;
    }
    this.focusChain = this.focusChain.catch((): void => {}).then((): Promise<void> => release);
  }
}
