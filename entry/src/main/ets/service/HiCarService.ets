import { common } from '@kit.AbilityKit';
import { AppStorageV2, display, window } from '@kit.ArkUI';
import lazy { smartMobilityCommon } from '@kit.CarKit';
import { Book, Chapter } from '../model/Book';
import { HiCarLibrary, HiCarState } from '../model/HiCar';
import { PLAYER_STATE_KEY, PlayerState } from '../model/PlayerState';
import { PlatformCompat } from '../utils/PlatformCompat';
import { AudioService } from './AudioService';
import { BookSourceService } from './BookSourceService';
import { DataService } from './DataService';
import { DownloadBookRecord } from './DownloadStore';
import { DownloadService } from './DownloadService';
import { PreferenceService } from './PreferenceService';

/** HiCar 只提供显示场景与现有音频库的入口，所有播放仍归 AudioService 管理。 */
export class HiCarService {
  private static readonly singleton: HiCarService = new HiCarService();
  static get instance(): HiCarService { return HiCarService.singleton; }

  readonly state: HiCarState = new HiCarState();
  private context: common.UIAbilityContext | null = null;
  private awareness: smartMobilityCommon.SmartMobilityAwareness | null = null;
  private mainWindow: window.Window | null = null;
  private statusSubscribed: boolean = false;
  private eventSubscribed: boolean = false;
  private windowSubscribed: boolean = false;
  private readonly statusChanged = (info: smartMobilityCommon.SmartMobilityInfo): void => {
    if (!this.context || info.type !== smartMobilityCommon.SmartMobilityType.HICAR) return;
    this.state.connected = info.status === smartMobilityCommon.SmartMobilityStatus.RUNNING;
    this.refreshWindow();
  };
  private readonly eventChanged = (_event: smartMobilityCommon.SmartMobilityEvent): void => {
    if (this.context) this.refresh();
  };
  private readonly displayChanged = (_displayId: number): void => { this.refreshWindow(); };

  initialize(context: common.UIAbilityContext): void {
    if (PlatformCompat.wearable) return;
    this.context = context;
    if (this.awareness) { this.refresh(); return; }
    try {
      if (!canIUse('SystemCapability.CarService.DistributedEngine')) return;
      this.awareness = smartMobilityCommon.getSmartMobilityAwareness();
      this.state.supported = true;
    } catch (error) {
      this.releaseAwareness();
      this.state.supported = false;
      this.state.connected = false;
      this.refreshWindow();
      console.warn('[HiCarService] Car Kit unavailable: ' + String(error));
      return;
    }
    // 状态与可选事件分别注册；一项不可用不能撤销另一项，也不能阻止前台主动查询。
    try {
      this.awareness.on('smartMobilityStatus', [smartMobilityCommon.SmartMobilityType.HICAR], this.statusChanged);
      this.statusSubscribed = true;
    } catch (error) {
      console.warn('[HiCarService] status listener unavailable: ' + String(error));
    }
    try {
      this.awareness.on('smartMobilityEvent', [smartMobilityCommon.SmartMobilityType.HICAR], this.eventChanged);
      this.eventSubscribed = true;
    } catch (error) {
      console.warn('[HiCarService] event listener unavailable: ' + String(error));
    }
    this.refresh();
  }

  refresh(): void {
    if (!this.awareness) return;
    try {
      this.statusChanged(this.awareness.getSmartMobilityStatus(smartMobilityCommon.SmartMobilityType.HICAR));
    } catch (error) {
      this.state.connected = false;
      this.refreshWindow();
      console.warn('[HiCarService] status unavailable: ' + String(error));
    }
  }

  bindWindow(value: window.Window): void {
    this.unbindWindow();
    this.mainWindow = value;
    try {
      value.on('displayIdChange', this.displayChanged);
      this.windowSubscribed = true;
    } catch (error) {
      console.warn('[HiCarService] display listener unavailable: ' + String(error));
    }
    this.refreshWindow();
  }

  /** 连接本身不能切换手机界面；仅在窗口位于独立显示屏时进入车载布局。 */
  static useCarWindow(connected: boolean, windowId: number | undefined, defaultId: number): boolean {
    return connected && windowId !== undefined && Number.isInteger(windowId) && windowId >= 0 &&
      Number.isInteger(defaultId) && defaultId >= 0 && windowId !== defaultId;
  }

  private refreshWindow(): void {
    try {
      this.state.carWindow = HiCarService.useCarWindow(this.state.connected,
        this.mainWindow?.getWindowProperties().displayId, display.getDefaultDisplaySync().id);
    } catch (_error) {
      this.state.carWindow = false;
    }
  }

  unbindWindow(): void {
    if (this.mainWindow && this.windowSubscribed) {
      try { this.mainWindow.off('displayIdChange', this.displayChanged); } catch (_error) {}
    }
    this.windowSubscribed = false;
    this.mainWindow = null;
    this.state.carWindow = false;
  }

  minimize(): void {
    this.context?.moveAbilityToBackground().catch((error: Error): void => {
      console.warn('[HiCarService] background failed: ' + error.message);
    });
  }

  private releaseAwareness(): void {
    if (this.awareness) {
      if (this.statusSubscribed) {
        try { this.awareness.off('smartMobilityStatus', [smartMobilityCommon.SmartMobilityType.HICAR], this.statusChanged); }
        catch (_error) {}
      }
      if (this.eventSubscribed) {
        try { this.awareness.off('smartMobilityEvent', [smartMobilityCommon.SmartMobilityType.HICAR], this.eventChanged); }
        catch (_error) {}
      }
    }
    this.awareness = null;
    this.statusSubscribed = false;
    this.eventSubscribed = false;
  }

  destroy(): void {
    this.context = null;
    this.unbindWindow();
    this.releaseAwareness();
    this.state.supported = false;
    this.state.connected = false;
  }

  player(): PlayerState {
    return AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, (): PlayerState => new PlayerState())!;
  }

  static isAudio(book: Book): boolean {
    return book.contentType === undefined || book.contentType === 'audio';
  }

  async loadLibrary(): Promise<HiCarLibrary> {
    const result = new HiCarLibrary();
    const context = this.context;
    if (!context) throw new Error('HiCar context unavailable');
    await PreferenceService.init(context);
    await DownloadService.getInstance().init(context);
    const books = await DataService.getBooks(context);
    const byId = new Map<string, Book>();
    for (const book of books) if (HiCarService.isAudio(book)) byId.set(book.id, book);
    const offlineIds = new Set<string>();
    for (const record of DownloadService.getInstance().getAllBookStatuses()) {
      if (record.contentType === 'text' || record.contentType === 'comic' || record.downloadedCount <= 0) continue;
      if (!byId.has(record.bookId)) byId.set(record.bookId, HiCarService.downloadBook(record));
      offlineIds.add(record.bookId);
    }
    for (const item of await PreferenceService.getHistory()) {
      const book = byId.get(item.bookId);
      if (book && !result.recent.some((value: Book): boolean => value.id === book.id)) result.recent.push(book);
    }
    for (const id of await PreferenceService.getShelfFavorites()) {
      const book = byId.get(id);
      if (book) result.shelf.push(book);
    }
    for (const book of byId.values()) {
      if (offlineIds.has(book.id) || (!book.sourceUrl && book.id.startsWith('import_'))) {
        result.downloaded.push(book);
      }
    }
    return result;
  }

  /** 下载记录可独立于缓存书索引保留；恢复时保留真实章节身份，优先走现有下载命中。 */
  private static downloadBook(record: DownloadBookRecord): Book {
    const chapters: Chapter[] = [];
    for (const item of record.chapters) {
      if (item.status !== 'completed' || !item.filePath) continue;
      const chapter: Chapter = {
        id: item.chapterId, index: item.chapterIndex, title: item.title, duration: item.durationSec ?? 0,
        source: { type: 'file', value: item.filePath }, originSourceValue: item.pageUrl, variables: item.variables
      };
      chapters.push(chapter);
    }
    chapters.sort((left: Chapter, right: Chapter): number => left.index - right.index);
    const book: Book = {
      id: record.bookId, contentType: 'audio', title: record.title, author: record.author, narrator: '',
      cover: record.cover, category: '', intro: '', totalDuration: 0, chapterCount: record.chapterCount,
      rating: 0, tags: [], chapters: chapters, sourceUrl: record.sourceUrl, bookUrl: record.bookUrl,
      variables: record.variables, tocComplete: false
    };
    return book;
  }

  async openBook(summary: Book): Promise<Book> {
    const context = this.context;
    if (!context || !HiCarService.isAudio(summary)) throw new Error('Audio book unavailable');
    let book = await DataService.getBookById(context, summary.id) ?? summary;
    if (book.chapters.length === 0) {
      const record = DownloadService.getInstance().getBookStatus(book.id);
      if (record && record.downloadedCount > 0) book = HiCarService.downloadBook(record);
    }
    if (book.chapters.length === 0 && book.sourceUrl) {
      book = await BookSourceService.loadAudioBook(book, (): void => {});
    }
    if (!HiCarService.isAudio(book) || book.chapters.length === 0) throw new Error('Audio chapters unavailable');
    await PreferenceService.applySkipConfig(book);
    return book;
  }

  async chapterPosition(book: Book): Promise<number> {
    const player = this.player();
    if (player.currentBook?.id === book.id && player.currentChapter) {
      const current = DataService.resolveChapterIndex(book, player.currentChapter.id, player.currentChapter.title);
      if (current >= 0) return current;
    }
    const progress = await PreferenceService.getProgress(book.id);
    return progress ? Math.max(0, DataService.resolveChapterIndex(book, progress.chapterId, progress.chapterTitle)) : 0;
  }

  async resume(book: Book, current: () => boolean): Promise<void> {
    const audio = AudioService.getInstance();
    await audio.whenReady(5000);
    if (!current()) return;
    const player = this.player();
    if (player.currentBook?.id === book.id && player.currentChapter) {
      await audio.play();
      return;
    }
    const progress = await PreferenceService.getProgress(book.id);
    if (!current()) return;
    const index = progress ? DataService.resolveChapterIndex(book, progress.chapterId, progress.chapterTitle) : -1;
    const chapter = book.chapters[index >= 0 ? index : 0];
    if (!chapter) throw new Error('Audio chapter unavailable');
    if (progress && index >= 0) {
      await audio.playChapterAndSeek(book, chapter, Math.max(0, progress.positionMs));
    } else {
      await audio.playChapterFromSavedProgress(book, chapter);
    }
  }
}
