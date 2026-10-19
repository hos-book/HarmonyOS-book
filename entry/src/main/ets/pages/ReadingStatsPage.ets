import { LocalBookCover } from '../components/LocalBookCover';
import { ImmersiveCircleButton } from '../components/ImmersiveCircleButton';
import { PlatformCompat } from '../utils/PlatformCompat';
import { HdsCompat } from '../utils/HdsCompat';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { AppColor, AppMaterial, AppCurve, AppFont, AppRadius, AppSpace, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import {
  BookUsageStats,
  EVT_USAGE_STATS_UPDATED,
  StatsBundle,
  StatsService
} from '../service/StatsService';
import {
  PlayHistoryItem,
  PreferenceService,
  EVT_FAVORITES_CHANGED
} from '../service/PreferenceService';
import { Book } from '../model/Book';
import { DataService } from '../service/DataService';
import { DiagnosticLogService } from '../service/DiagnosticLogService';
import { BookSourceService } from '../service/BookSourceService';
import { SearchCache } from '../utils/SearchCache';
import { OnlineTextContentCache } from '../service/text/OnlineTextContentCache';
import { TextReaderRouteParams, TextReadingPosition } from '../model/TextReading';
import { TextReadingProgressService, EVT_TEXT_READING_PROGRESS_CHANGED } from '../service/text/TextReadingProgressService';
import {
  ListeningHistoryPolicy,
  ListeningRecordCandidate,
  MergedListeningRecord
} from '../service/ListeningHistoryPolicy';

@ObservedV2
class ListenRecordView {
  bookId: string = '';
  aliasBookIds: string[] = [];
  @Trace title: string = '';
  @Trace author: string = '';
  @Trace cover: string = '';
  chapterId: string = '';
  @Trace chapterTitle: string = '';
  progressMs: number = 0;
  durationMs: number = 0;
  @Trace progressPercent: number = 0;
  @Trace listenSeconds: number = 0;
  updatedAt: number = 0;
  @Trace isText: boolean = false;
  @Trace isComic: boolean = false;
  readingPosition: TextReadingPosition | null = null;
}

class ListeningRecordDataSource implements IDataSource {
  private items: ListenRecordView[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.items.length; }
  getData(index: number): ListenRecordView { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
  setRecords(records: ListenRecordView[]): void {
    // 保留同一本书的可观察对象，稳定 key 下进度、标题仍能即时刷新。
    const existing = new Map<string, ListenRecordView>();
    for (const item of this.items) existing.set(item.bookId, item);
    this.items = records.map((record: ListenRecordView): ListenRecordView => {
      const item = existing.get(record.bookId);
      if (!item) return record;
      item.aliasBookIds = record.aliasBookIds;
      item.title = record.title;
      item.author = record.author;
      item.cover = record.cover;
      item.chapterId = record.chapterId;
      item.chapterTitle = record.chapterTitle;
      item.progressMs = record.progressMs;
      item.durationMs = record.durationMs;
      item.progressPercent = record.progressPercent;
      item.listenSeconds = record.listenSeconds;
      item.updatedAt = record.updatedAt;
      item.isText = record.isText;
      item.isComic = record.isComic;
      item.readingPosition = record.readingPosition;
      return item;
    });
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

const AVERAGE_BOOK_SECONDS: number = 8 * 60 * 60;
const MINI_TITLE_BAR_HEIGHT: number = 56;

@ComponentV2
export struct ReadingStatsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param inTab: boolean = false;
  /** 记录 Tab 只展示收藏书籍；时钟入口打开未收藏历史模式。 */
  @Param onlyUnfavorited: boolean = false;
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};

  @Local statsReady: boolean = false;
  @Local statsError: boolean = false;
  @Local streak: number = 0;
  @Local totalSeconds: number = 0;
  @Local monthSeconds: number = 0;
  @Local records: ListenRecordView[] = [];
  @Local contentFilter: number = 0;
  @Local contentFilterVisible: boolean = false;
  private readonly recordTitleBuilder: CustomBuilder = (): void => this.buildRecordTitleBar();
  @Local loading: boolean = true;
  @Local refreshing: boolean = false;
  @Local appeared: boolean = false;
  @Local selectMode: boolean = false;
  @Local selectedIds: Set<string> = new Set();

  private scroller: Scroller = new Scroller();
  private recordDataSource: ListeningRecordDataSource = new ListeningRecordDataSource();
  private recoveryRunning: boolean = false;
  private recoveryActive: boolean = false;
  private recoveryAttempted: Set<string> = new Set();
  private loadingStats: boolean = false;
  private reloadPending: boolean = false;
  private dayTimer: number = -1;
  private statsHandler = (_evt: emitter.EventData): void => {
    // 书籍明细可能还在异步加载；已提交的顶部累计不能等它完成才刷新。
    const cached = StatsService.getCachedStatsBundle(1);
    if (cached !== undefined) this.applyStatsBundle(cached);
    this.loadStats();
  };
  private favoritesHandler = (_evt: emitter.EventData): void => {
    this.loadStats();
  };

  aboutToAppear(): void {
    DiagnosticLogService.info('records.open', `unfavorited=${this.onlyUnfavorited}`);
    this.recoveryActive = true;
    this.recoveryAttempted.clear();
    const cached = StatsService.getCachedStatsBundle(1);
    if (cached !== undefined) this.applyStatsBundle(cached);
    this.onScrollerReady(this.scroller);
    this.loadStats();
    this.scheduleDayRefresh();
    emitter.on(EVT_USAGE_STATS_UPDATED, this.statsHandler);
    emitter.on(EVT_FAVORITES_CHANGED, this.favoritesHandler);
    emitter.on(EVT_TEXT_READING_PROGRESS_CHANGED, this.statsHandler);
    setTimeout(() => { this.appeared = true; }, 24);
  }

  aboutToDisappear(): void {
    this.recoveryActive = false;
    if (this.dayTimer !== -1) clearTimeout(this.dayTimer);
    this.dayTimer = -1;
    try {
      emitter.off(EVT_USAGE_STATS_UPDATED, this.statsHandler);
    } catch (_e) {
      try { emitter.off(EVT_USAGE_STATS_UPDATED); } catch (_ignore) { /* ignore */ }
    }
    try { emitter.off(EVT_FAVORITES_CHANGED, this.favoritesHandler); } catch (_e) { /* ignore */ }
    try { emitter.off(EVT_TEXT_READING_PROGRESS_CHANGED, this.statsHandler); } catch (_e) { /* ignore */ }
  }

  private applyStatsBundle(bundle: StatsBundle): void {
    this.streak = bundle.streak;
    this.totalSeconds = bundle.summary.totalSeconds;
    this.monthSeconds = bundle.summary.monthSeconds;
    this.statsReady = true;
    this.statsError = false;
  }

  private scheduleDayRefresh(): void {
    if (this.dayTimer !== -1) clearTimeout(this.dayTimer);
    const now = new Date();
    const nextDay = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
    this.dayTimer = setTimeout((): void => {
      this.dayTimer = -1;
      if (!this.recoveryActive) return;
      this.loadStats();
      this.scheduleDayRefresh();
    }, Math.max(1000, nextDay.getTime() - now.getTime()));
  }

  private async loadStats(): Promise<void> {
    if (this.loadingStats) {
      this.reloadPending = true;
      return;
    }
    this.loadingStats = true;
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) { this.loadingStats = false; this.refreshing = false; return; }
    try {
      await StatsService.init(ctx);
      const bundle: StatsBundle = await StatsService.getStatsBundle(1);
      // 顶部统计独立于书籍明细；离线或某本书读取失败时仍显示持久化累计值。
      this.applyStatsBundle(StatsService.getCachedStatsBundle(1) ?? bundle);
      await PreferenceService.ensureReady(ctx);
      let history: PlayHistoryItem[] = [];
      let favoriteIds: Set<string> = new Set();
      let reading: TextReadingPosition[] = [];
      await Promise.all([
        Promise.resolve().then(() => PreferenceService.getHistory()).then((items: PlayHistoryItem[]): void => { history = items; }),
        Promise.resolve().then(() => PreferenceService.getFavorites()).then((items: string[]): void => { favoriteIds = new Set(items); }),
        Promise.resolve().then(() => TextReadingProgressService.getAll(ctx, true)).then((items: TextReadingPosition[]): void => { reading = items; })
      ]);
      const allRecords = await this.buildRecordViews(ctx, bundle.records, history, reading);
      this.records = allRecords.filter((item: ListenRecordView): boolean =>
        this.shouldShowRecord(item, favoriteIds));
      this.applyContentFilter();
      this.recoverReadingBooks(ctx, reading).catch((error: Error): void => {
        DiagnosticLogService.info('records.recovery.failed', `${error.message}; ${error.stack ?? ''}`);
      });
      this.selectedIds = new Set(Array.from(this.selectedIds).filter((id) =>
        this.records.some((item) => item.bookId === id)));
      if (this.selectedIds.size === 0) this.selectMode = false;
    } catch (e) {
      if (!this.statsReady) this.statsError = true;
      DiagnosticLogService.info('records.load.failed', `unfavorited=${this.onlyUnfavorited}; ` +
        (e instanceof Error ? `${e.message}; ${e.stack ?? ''}` : String(e)));
      console.error(`[ReadingStatsPage] load stats failed: ${JSON.stringify(e)}`);
    } finally {
      this.loading = false;
      this.refreshing = false;
      this.loadingStats = false;
      if (this.reloadPending) {
        this.reloadPending = false;
        this.loadStats();
      }
    }
  }

  /** 先展示历史，后台修复旧版本未保存的书籍，网络失败不阻塞记录页。 */
  private async recoverReadingBooks(context: common.Context, reading: TextReadingPosition[]): Promise<void> {
    if (this.recoveryRunning || !this.recoveryActive) return;
    this.recoveryRunning = true;
    let changed = false;
    try {
      const missing: string[] = [];
      for (const position of reading) {
        if (!this.recoveryActive) return;
        if (position.bookId.startsWith('import_') || this.recoveryAttempted.has(position.bookId)) continue;
        this.recoveryAttempted.add(position.bookId);
        if (await DataService.getBookById(context, position.bookId)) continue;
        const cached = SearchCache.get(position.bookId);
        if (cached) {
          await DataService.upsertCachedBook(cached);
          changed = true;
        } else {
          missing.push(position.bookId);
        }
      }
      // 兼容旧版 Preferences 索引仍留有完整书籍的情况。
      if (missing.length > 0) {
        try {
          const legacy: Book[] = JSON.parse(await PreferenceService.getCachedBooks());
          if (Array.isArray(legacy)) {
            for (const book of legacy) {
              const index = book ? missing.indexOf(book.id) : -1;
              if (index < 0 || !book.title || !book.sourceUrl || !book.bookUrl) continue;
              await DataService.upsertCachedBook(book);
              missing.splice(index, 1);
              changed = true;
            }
          }
        } catch (_e) { /* 旧索引不可用时尝试正文身份 */ }
      }
      const identities = await OnlineTextContentCache.recoverBookIdentities(context, missing);
      for (const identity of identities) {
        if (!this.recoveryActive) break;
        try {
          const shell: Book = {
            id: identity.bookId, contentType: 'text', title: '', author: '', narrator: '',
            cover: '', category: '', intro: '', totalDuration: 0, chapterCount: 0,
            rating: 0, tags: [], chapters: [], sourceUrl: identity.sourceUrl, bookUrl: identity.bookUrl
          };
          const book = await BookSourceService.loadTextBook(shell, undefined, true);
          if (!book.title.trim()) continue;
          await DataService.upsertCachedBook(book);
          changed = true;
          // 每本成功就刷新，无需等待所有书源响应。
          if (this.recoveryActive) this.loadStats();
        } catch (error) {
          // 缺源、离线或单本失效均保留原记录；记录错误，不将缺源直接判为崩溃原因。
          DiagnosticLogService.info('records.book_recovery.failed',
            error instanceof Error ? error.message : String(error));
        }
      }
    } finally {
      this.recoveryRunning = false;
      if (changed && this.recoveryActive) this.loadStats();
    }
  }

  private shouldShowRecord(item: ListenRecordView, favoriteIds: Set<string>): boolean {
    const isFavorite = favoriteIds.has(item.bookId) ||
      item.aliasBookIds.some((aliasBookId: string): boolean => favoriteIds.has(aliasBookId));
    return this.onlyUnfavorited ? !isFavorite : isFavorite;
  }

  private pageTitle(): Resource {
    return this.onlyUnfavorited ? $r('app.string.record_unfavorited_title') : $r('app.string.record_title');
  }

  private async buildRecordViews(context: common.Context, stats: BookUsageStats[],
    history: PlayHistoryItem[], reading: TextReadingPosition[]): Promise<ListenRecordView[]> {
    const statsMap = new Map<string, BookUsageStats[]>();
    const historyMap = new Map<string, PlayHistoryItem>();
    const bookIds = new Set<string>();
    const readingMap = new Map<string, TextReadingPosition>();
    for (const position of reading) {
      readingMap.set(position.bookId, position);
      bookIds.add(position.bookId);
    }
    for (const item of stats) {
      if (!item || !item.bookId || item.listenSeconds <= 0) continue;
      let bookStats = statsMap.get(item.bookId);
      if (!bookStats) {
        bookStats = [];
        statsMap.set(item.bookId, bookStats);
      }
      bookStats.push(item);
      bookIds.add(item.bookId);
    }
    for (const item of history) {
      if (!item || !item.bookId) continue;
      const current = historyMap.get(item.bookId);
      if (!current || item.updatedAt >= current.updatedAt) historyMap.set(item.bookId, item);
      bookIds.add(item.bookId);
    }

    const candidates: ListeningRecordCandidate[] = [];
    const books = new Map<string, Book>();
    const metadata = new Map<string, Book>();
    for (const book of await DataService.getBooks(context)) metadata.set(book.id, book);
    let missingBooks: number = 0;
    for (const bookId of bookIds) {
      const candidate = new ListeningRecordCandidate(bookId);
      candidate.readingPosition = readingMap.get(bookId) ?? null;
      candidate.isText = candidate.readingPosition !== null || this.isLegacyTextBook(bookId);
      const bookStats = statsMap.get(bookId) ?? [];
      for (const stat of bookStats) {
        candidate.addStats(stat.listenSeconds, stat.updatedAt, stat.title, stat.author, stat.cover,
          stat.sourceUrl, stat.bookUrl);
      }
      const historyItem = historyMap.get(bookId);
      if (historyItem) {
        candidate.setHistory(historyItem.chapterId, historyItem.chapterTitle ?? '', historyItem.progressMs,
          historyItem.durationMs ?? 0, historyItem.updatedAt, historyItem.sourceUrl, historyItem.bookUrl);
      }
      const progress = await PreferenceService.getProgress(bookId);
      if (progress && progress.updatedAt <= Math.max(candidate.historyUpdatedAt, candidate.statsUpdatedAt)) {
        candidate.setProgress(progress.chapterId, progress.chapterTitle, progress.positionMs, progress.durationMs,
          progress.chapterIndex, progress.updatedAt, progress.sourceUrl, progress.bookUrl);
      }
      const book = metadata.get(bookId) ?? SearchCache.get(bookId);
      if (book) {
        books.set(bookId, book);
        candidate.setBook(book.sourceUrl, book.bookUrl, book.title, book.author || book.narrator, book.cover);
        candidate.isText = candidate.isText || book.contentType === 'text' || book.contentType === 'comic';
      } else {
        missingBooks++;
      }
      candidates.push(candidate);
    }

    const merged = ListeningHistoryPolicy.merge(candidates);
    if (missingBooks > 0) {
      DiagnosticLogService.info('records.books_missing',
        `unfavorited=${this.onlyUnfavorited}; missing=${missingBooks}; candidates=${candidates.length}; merged=${merged.length}`);
    }
    const views: ListenRecordView[] = [];
    for (const item of merged) {
      views.push(this.createRecordView(item, books.get(item.bookId) ?? null));
    }
    return views.sort((a, b) => b.updatedAt - a.updatedAt);
  }

  private isLegacyTextBook(bookId: string): boolean {
    return bookId.startsWith('search_text_') || bookId.startsWith('home_text_');
  }

  private createRecordView(item: MergedListeningRecord, book: Book | null): ListenRecordView {
    let chapterId = item.chapterId;
    let chapterIndex = item.chapterIndex;
    if (!item.isText && book && book.chapters && book.chapters.length > 0) {
      const resolvedIndex = DataService.resolveChapterIndex(book, item.chapterId, item.chapterTitle);
      if (resolvedIndex >= 0) {
        chapterIndex = resolvedIndex;
        chapterId = book.chapters[resolvedIndex].id;
      }
    }
    const ratio = item.isText ? Math.max(0, Math.min(1, chapterIndex / Math.max(1, book?.chapterCount ?? 1))) :
      this.calculateBookProgress(book, chapterId, item.chapterTitle, chapterIndex, item.progressMs, item.durationMs);
    const view = new ListenRecordView();
    view.bookId = item.bookId;
    view.aliasBookIds = item.aliasBookIds;
    view.title = book?.title || item.title || '未知书籍';
    view.author = book?.author || book?.narrator || item.author || '未知作者';
    view.cover = book?.cover || item.cover || '';
    view.chapterId = chapterId;
    view.chapterTitle = item.chapterTitle;
    view.progressMs = item.progressMs;
    view.durationMs = item.durationMs;
    view.progressPercent = Math.round(ratio * 100);
    view.listenSeconds = item.listenSeconds;
    view.updatedAt = item.updatedAt || 0;
    view.isText = item.isText;
    view.isComic = book?.contentType === 'comic' || item.bookId.startsWith('search_comic_');
    view.readingPosition = item.readingPosition;
    return view;
  }

  private calculateBookProgress(book: Book | null, chapterId: string, chapterTitle: string,
    savedChapterIndex: number, progressMs: number, durationMs: number): number {
    const chapterRatio = durationMs > 0 ? Math.max(0, Math.min(1, progressMs / durationMs)) : 0;
    if (!book) return chapterRatio;

    const chapterCount = book.chapters && book.chapters.length > 0 ? book.chapters.length : (book.chapterCount || 0);
    if (chapterCount <= 0) return chapterRatio;

    let chapterIndex = -1;
    if (book.chapters && book.chapters.length > 0) {
      chapterIndex = DataService.resolveChapterIndex(
        book,
        chapterId,
        chapterTitle
      );
    }
    if (chapterIndex < 0 && savedChapterIndex >= 0) chapterIndex = savedChapterIndex;
    if (chapterIndex < 0) return chapterRatio;

    const safeIndex = Math.max(0, Math.min(chapterCount - 1, chapterIndex));
    return Math.max(0, Math.min(1, (safeIndex + chapterRatio) / chapterCount));
  }

  private totalListenSeconds(): number {
    return this.totalSeconds;
  }

  private monthListenSeconds(): number {
    return this.monthSeconds;
  }

  private equivalentBookCount(): number {
    return Math.max(0, Math.round(this.totalListenSeconds() / AVERAGE_BOOK_SECONDS));
  }

  private formatDuration(seconds: number): string {
    const total = Math.max(0, Math.floor(seconds));
    if (total < 60) return total > 0 ? '不足1分钟' : '0分钟';
    const minutes = Math.floor(total / 60);
    if (minutes < 60) return `${minutes}分钟`;
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return rest > 0 ? `${hours}小时${rest}分钟` : `${hours}小时`;
  }

  private formatDurationText(item: ListenRecordView): string {
    const total = item.listenSeconds;
    if (total > 0) return this.formatDuration(total);
    if (item.progressMs > 0) return this.formatDuration(Math.floor(item.progressMs / 1000));
    return '刚刚开始';
  }

  private toggleSelect(bookId: string): void {
    const next = new Set(this.selectedIds);
    if (next.has(bookId)) {
      next.delete(bookId);
    } else {
      next.add(bookId);
    }
    this.selectedIds = next;
    this.selectMode = next.size > 0;
  }

  private selectAll(): void {
    this.selectedIds = new Set(this.filteredRecords().map((item: ListenRecordView): string => item.bookId));
    this.selectMode = this.selectedIds.size > 0;
  }

  private clearSelection(): void {
    this.selectedIds = new Set();
    this.selectMode = false;
  }

  private confirmDeleteSelected(): void {
    if (this.selectedIds.size === 0) return;
    const count = this.selectedIds.size;
    this.getUIContext().getPromptAction().showDialog({
      title: '删除记录',
      message: this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.record_delete_confirm').id, count),
      buttons: [
        { text: '取消', color: '#8F8F8F' },
        { text: '删除', color: '#C45D34' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.deleteSelected();
      }
    }).catch(() => { /* ignore */ });
  }

  private async deleteSelected(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const deletedIds = new Set<string>();
    for (const item of this.records) {
      if (!this.selectedIds.has(item.bookId)) continue;
      for (const aliasBookId of item.aliasBookIds) deletedIds.add(aliasBookId);
    }
    for (const selectedId of this.selectedIds) deletedIds.add(selectedId);
    const ids = Array.from(deletedIds);
    await StatsService.removeBookStats(ids);
    for (const id of ids) {
      await PreferenceService.removeHistory(id);
      await PreferenceService.removeProgress(id);
      await TextReadingProgressService.remove(context, id);
    }
    this.clearSelection();
    await this.loadStats();
  }

  private openDetail(item: ListenRecordView): void {
    if (!item.bookId || this.selectMode) return;
    this.navStack.pushPathByName('detail', item.bookId);
  }

  private async resumeRecord(item: ListenRecordView): Promise<void> {
    if (!item.bookId) return;
    if (item.isText) {
      const context = this.getUIContext().getHostContext();
      if (!context) return;
      const reading = item.readingPosition;
      if (reading && reading.bookId !== item.bookId) {
        await TextReadingProgressService.save(context, TextReadingPosition.atChar(item.bookId,
          reading.resourceIndex, reading.domPos, reading.charOffset, reading.pageOffset, reading.chapterTitle));
      }
      this.navStack.pushPathByName(item.isComic ? 'comicReader' : 'reader', TextReaderRouteParams.of(item.bookId));
      return;
    }
    const params: Record<string, Object> = {
      'bookId': item.bookId,
      'chapterId': item.chapterId,
      'progressMs': item.progressMs
    };
    this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
      this.navStack.pushPathByName('player', params, false);
    });
  }

  private applyContentFilter(): void {
    this.recordDataSource.setRecords(this.filteredRecords());
  }

  private contentFilterLabel(index: number): Resource {
    if (index === 1) return $r('app.string.search_type_audio');
    if (index === 2) return $r('app.string.search_type_text');
    if (index === 3) return $r('app.string.comic_type');
    return $r('app.string.search_type_all');
  }

  private contentFilterOptions(): CustomPopupOptions {
    const options: CustomPopupOptions = {
      builder: this.buildContentFilterMenu,
      placement: Placement.BottomRight,
      popupColor: Color.Transparent,
      radius: AppRadius.Xl,
      enableArrow: false,
      focusable: true,
      onStateChange: (event): void => { this.contentFilterVisible = event.isVisible; }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    else options.backgroundBlurStyle = AppMaterial.SheetBlur;
    return options;
  }

  @LocalBuilder
  buildContentFilterMenu() {
    Column({ space: 2 }) {
      ForEach([0, 1, 2, 3], (index: number) => {
        Text(this.contentFilterLabel(index)).fontSize(16)
          .fontColor(index === this.contentFilter ? AppColor.Brand : $r('sys.color.font_primary'))
          .width('100%').height(48).padding({ left: AppSpace.Sm, right: AppSpace.Sm })
          .borderRadius(AppRadius.Xl - AppSpace.Xs)
          .backgroundColor(index === this.contentFilter ? AppColor.BrandSoft : Color.Transparent)
          .onClick((): void => {
            this.contentFilterVisible = false;
            this.contentFilter = index;
            this.clearSelection();
            this.applyContentFilter();
          })
      }, (index: number): string => index.toString())
    }.width(200).padding(AppSpace.Xs)
  }

  @LocalBuilder
  buildRecordTitleBar() {
    Row({ space: AppSpace.Sm }) {
      if (!this.inTab) {
        ImmersiveCircleButton({ icon: $r('sys.symbol.chevron_left'), label: $r('app.string.app_icon_back'),
          onPress: (): void => { this.navStack.pop(); } })
      }
      Text(this.pageTitle()).fontSize(26).fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary')).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      ImmersiveCircleButton({ icon: $r('sys.symbol.funnel'), label: $r('app.string.record_content_filter'),
        iconColor: this.contentFilter > 0 ? AppColor.Brand : $r('sys.color.icon_primary'),
        onPress: (): void => { this.contentFilterVisible = !this.contentFilterVisible; } })
        .bindPopup(this.contentFilterVisible, this.contentFilterOptions())
      ImmersiveCircleButton({ icon: $r('sys.symbol.clock'),
        label: this.onlyUnfavorited ? $r('app.string.record_favorited_back') : $r('app.string.record_unfavorited_title'),
        onPress: (): void => {
          this.contentFilterVisible = false;
          if (this.onlyUnfavorited) this.navStack.pop();
          else this.navStack.pushPathByName('unfavoriteHistory', null, false);
        } })
      ImmersiveCircleButton({ icon: this.selectMode ? $r('sys.symbol.checkmark') : $r('sys.symbol.square_and_pencil'),
        label: this.selectMode ? $r('app.string.record_edit_done') : $r('app.string.record_edit'),
        iconColor: this.selectMode ? AppColor.Brand : $r('sys.color.icon_primary'),
        onPress: (): void => {
          this.contentFilterVisible = false;
          if (this.selectMode) this.clearSelection();
          else this.selectMode = true;
        } }).enabled(!this.loading && this.filteredRecords().length > 0)
    }.width('100%').height(MINI_TITLE_BAR_HEIGHT)
      .padding({ left: AppSpace.Md, right: AppSpace.Md }).clip(false)
  }

  private filteredRecords(): ListenRecordView[] {
    return this.records.filter((item: ListenRecordView): boolean =>
      this.contentFilter === 0 || (this.contentFilter === 1 && !item.isText) ||
      (this.contentFilter === 2 && item.isText && !item.isComic) || (this.contentFilter === 3 && item.isComic));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            [HomeTheme.BgWarmTop, 0.0],
            [HomeTheme.BgWarmMid, 0.42],
            [HomeTheme.BgNeutral, 1.0]
          ]
        })

      HdsNavigation() {
        Refresh({ refreshing: $$this.refreshing, builder: this.refreshIndicator() }) {
          List({ scroller: this.scroller, space: AppSpace.Md }) {
            if (!this.onlyUnfavorited) {
              ListItem() { this.buildSummaryCard() }
            }
            if (this.loading) {
              ListItem() { this.buildLoadingState() }
            } else if (this.records.length === 0) {
              ListItem() { this.buildEmptyState() }
            } else {
              ListItem() { this.buildHistoryHeader() }
              LazyForEach(this.recordDataSource, (item: ListenRecordView) => {
                ListItem() { this.buildRecordItem(item) }
              }, (item: ListenRecordView): string => item.bookId)
            }
          }
          .width('100%')
          .height('100%')
          .cachedCount(5)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .padding({
            left: AppSpace.Md,
            right: AppSpace.Md
          })
          // 首尾避让随列表滚动，避免 padding 将内容裁在悬浮底栏上方。
          .contentStartOffset(WindowUtils.getStatusBarHeightVp() + MINI_TITLE_BAR_HEIGHT + AppSpace.Sm)
          .contentEndOffset(this.inTab ? WindowUtils.getFloatingTabBottomVp() :
            WindowUtils.getBottomSafeVp() + AppSpace.Xl)
        }
        .onRefreshing(() => { this.loadStats(); })
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .align(Alignment.Top)
      }
      .mode(NavigationMode.Stack)
      .titleBar({
        avoidLayoutSafeArea: true,
        content: { stackBuilder: this.recordTitleBuilder },
        style: {
          scrollEffectOpts: {
            scrollEffectType: HdsCompat.scrollEffect
          },
          originalStyle: {
            backgroundStyle: {
              backgroundColor: Color.Transparent
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary')
              },
              backIconStyle: {
                iconColor: $r('sys.color.icon_primary')
              },
              menuStyle: {
                iconColor: $r('sys.color.icon_primary')
              }
            }
          },
          scrollEffectStyle: {
            backgroundStyle: {
              backgroundColor: Color.Transparent
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary')
              },
              backIconStyle: {
                iconColor: $r('sys.color.icon_primary')
              },
              menuStyle: {
                iconColor: $r('sys.color.icon_primary')
              }
            }
          },
          systemMaterialEffect: HdsCompat.material
        }
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .bindToScrollable([this.scroller])
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onVisibleAreaChange([0], (visible: boolean): void => {
      if (visible && this.recoveryActive) {
        this.loadStats();
        this.scheduleDayRefresh();
      }
    })
  }

  @Builder
  refreshIndicator() {
    Row() {
      if (this.refreshing) {
        LoadingProgress().width(24).height(24).color(AppColor.Brand)
      }
    }
    .height(56)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildSummaryCard() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Row() {
          Blank()
          this.buildSummaryArt()
        }
        .width('100%')
        .height('100%')
        .padding({ right: AppSpace.Sm })
        .alignItems(VerticalAlign.Top)

        Column({ space: AppSpace.Xs }) {
          Text('累计收听时长')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
          Row({ space: AppSpace.Xs }) {
            Text(this.statsReady ? `${Math.floor(this.totalListenSeconds() / 3600)}` : $r('app.string.record_stats_pending'))
              .fontSize(32)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
            Text('小时')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .margin({ bottom: 4 })
            Text(this.statsReady ? `${Math.floor((this.totalListenSeconds() % 3600) / 60)}` : $r('app.string.record_stats_pending'))
              .fontSize(AppFont.Title)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
              .margin({ bottom: 2 })
            Text('分钟')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .margin({ bottom: 4 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          .justifyContent(FlexAlign.Start)
          Text(this.statsReady ? $r('app.string.record_stats_equivalent_books', this.equivalentBookCount()) :
            (this.statsError ? $r('app.string.record_stats_read_failed') : $r('app.string.record_stats_loading')))
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('62%')
        .alignItems(HorizontalAlign.Start)
        .margin({ left: AppSpace.Md, top: AppSpace.Md })
      }
      .height(98)
      .width('100%')

      Row() {
        Column({ space: AppSpace.Sm }) {
          Text('连续收听')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
          Row({ space: AppSpace.Xs }) {
            Text(this.statsReady ? `${this.streak}` : $r('app.string.record_stats_pending'))
              .fontSize(AppFont.Title)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
            Text('天')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column()
          .width(0.5)
          .height(34)
          .backgroundColor(AppColor.Divider)

        Column({ space: AppSpace.Sm }) {
          Text('本月收听')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
          Row({ space: AppSpace.Xs }) {
            Text(this.statsReady ? `${Math.floor(this.monthListenSeconds() / 3600)}` : $r('app.string.record_stats_pending'))
              .fontSize(AppFont.Title)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
            Text('小时')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
            Text(this.statsReady ? `${Math.floor((this.monthListenSeconds() % 3600) / 60)}` : $r('app.string.record_stats_pending'))
              .fontSize(AppFont.Title)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Bold)
            Text('分钟')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .layoutWeight(1)
        .padding({ left: AppSpace.Md })
        .alignItems(HorizontalAlign.Start)
      }
      .height(72)
      .width('100%')
      .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Sm, bottom: AppSpace.Sm })
      .backgroundColor($r('app.color.record_stats_detail_surface'))
      .borderRadius({ topLeft: AppRadius.Lg, topRight: AppRadius.Lg, bottomLeft: AppRadius.Xl, bottomRight: AppRadius.Xl })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(170)
    .borderRadius(AppRadius.Xl)
    .backgroundColor($r('app.color.home_card_surface_soft'))
    .shadow({ radius: 18, color: HomeTheme.CardShadow, offsetY: 6 })
    .clip(true)
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : 18 })
    .animation({ duration: 460, curve: AppCurve.Decelerate })
    .onClick(() => { if (this.statsError) this.loadStats(); })
  }

  @Builder
  buildSummaryArt() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column()
        .width(108)
        .height(108)
        .borderRadius(54)
        .backgroundColor('#42FFFFFF')
        .margin({ right: 0, bottom: 0 })

      Column()
        .width(80)
        .height(80)
        .borderRadius(40)
        .backgroundColor('#18D9BDAA')
        .margin({ right: 18, bottom: 14 })

      Column()
        .width(96)
        .height(6)
        .borderRadius(3)
        .backgroundColor('#16A98363')
        .margin({ right: 4, bottom: 5 })

      Column()
        .width(2)
        .height(34)
        .borderRadius(1)
        .backgroundColor('#BFA38D')
        .rotate({ angle: -28 })
        .margin({ right: 83, bottom: 59 })

      Column()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(AppColor.Brand)
        .margin({ right: 87, bottom: 87 })

      Column()
        .width(48)
        .height(18)
        .borderRadius({ topLeft: 16, topRight: 16 })
        .border({ width: 4, color: '#C5A187' })
        .margin({ right: 28, bottom: 54 })

      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width(92)
          .height(56)
          .borderRadius(14)
          .backgroundColor('#D7AE8E')

        Column()
          .width(62)
          .height(6)
          .borderRadius(3)
          .backgroundColor('#40FFFFFF')
          .margin({ left: 15, top: 10 })

        Row({ space: 5 }) {
          Column().width(3).height(18).borderRadius(2).backgroundColor('#9D7A61')
          Column().width(3).height(24).borderRadius(2).backgroundColor('#9D7A61')
          Column().width(3).height(14).borderRadius(2).backgroundColor('#9D7A61')
          Column().width(3).height(22).borderRadius(2).backgroundColor('#9D7A61')
          Column().width(3).height(16).borderRadius(2).backgroundColor('#9D7A61')
        }
        .alignItems(VerticalAlign.Center)
        .margin({ left: 15, top: 23 })

        Column()
          .width(27)
          .height(27)
          .borderRadius(14)
          .backgroundColor('#F3DFCE')
          .margin({ left: 54, top: 22 })

        Column()
          .width(12)
          .height(12)
          .borderRadius(6)
          .backgroundColor('#9D7A61')
          .margin({ left: 62, top: 30 })

        Row({ space: 5 }) {
          Column().width(8).height(8).borderRadius(4).backgroundColor('#F3DFCE')
          Column().width(8).height(8).borderRadius(4).backgroundColor('#F3DFCE')
        }
        .margin({ left: 57, top: 45 })
      }
      .width(92)
      .height(56)
      .margin({ right: 4, bottom: 10 })
    }
    .width(132)
    .height(98)
    .opacity(0.64)
  }

  @Builder
  buildHistoryHeader() {
    Row() {
      Column({ space: 5 }) {
        Text(this.pageTitle())
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
        Column()
          .width(20)
          .height(2)
          .borderRadius(1)
          .backgroundColor(HomeTheme.Accent)
      }
      .alignItems(HorizontalAlign.Start)

      Blank()
      this.buildEditActions()
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  buildEditActions() {
    if (this.selectMode) {
      Row({ space: AppSpace.Md }) {
        Text('全选')
          .fontSize(AppFont.Body)
          .fontColor(AppColor.Brand)
          .onClick(() => this.selectAll())
        Text('删除')
          .fontSize(AppFont.Body)
          .fontColor(AppColor.BrandDark)
          .onClick(() => this.confirmDeleteSelected())
        Text('取消')
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
          .onClick(() => this.clearSelection())
      }
      .alignItems(VerticalAlign.Center)

    }
  }

  @Builder
  buildRecordItem(item: ListenRecordView) {
    Row({ space: AppSpace.Md }) {
      if (this.selectMode) {
        Checkbox()
          .select(this.selectedIds.has(item.bookId))
          .selectedColor(AppColor.Brand)
          .hitTestBehavior(HitTestMode.None)
      }

      this.buildCover(item)

      Column({ space: AppSpace.Xs }) {
        Row() {
          Column({ space: AppSpace.Xs }) {
            Text(item.title)
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(item.author)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          if (!this.selectMode) {
            this.buildRecordActions(item)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row({ space: AppSpace.Sm }) {
          Row({ space: 4 }) {
            SymbolGlyph(item.isText ? $r('sys.symbol.book') : $r('sys.symbol.play_fill'))
              .fontSize(10)
              .fontColor([HomeTheme.Accent])
            Text(item.isText ? $r('app.string.record_read_progress', item.progressPercent) :
              $r('app.string.record_listen_progress', item.progressPercent))
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(VerticalAlign.Center)

          Text(item.isText ? (item.chapterTitle || $r('app.string.record_read_started')) : this.formatDurationText(item))
            .layoutWeight(1)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .margin({ top: 5 })

        Stack({ alignContent: Alignment.Start }) {
          Column()
            .width('100%')
            .height(3)
            .borderRadius(2)
            .backgroundColor(HomeTheme.ProgressTrack)
          Column()
            .width(`${Math.max(3, item.progressPercent)}%`)
            .height(3)
            .borderRadius(2)
            .backgroundColor(HomeTheme.Accent)
        }
        .width('100%')
        .height(3)
      }
      .layoutWeight(1)
      .height(76)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)


    }
    .width('100%')
    .height(88)
    .alignItems(VerticalAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick(() => {
      if (this.selectMode) {
        this.toggleSelect(item.bookId);
      } else {
        this.openDetail(item);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          this.selectMode = true;
          this.toggleSelect(item.bookId);
        })
    )
  }

  @Builder
  buildRecordActions(item: ListenRecordView) {
    Row({ space: 6 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_primary')])
        }
          .width(36)
          .height(36)
          .accessibilityText($r('app.string.session_history'))
          .backgroundColor(HomeTheme.CardSurface)
          .border({ width: 1, color: AppColor.Divider })
          .onClick((): void => {
            const params: Record<string, Object> = { 'bookIds': JSON.stringify([item.bookId, ...item.aliasBookIds]) };
            this.navStack.pushPathByName('sessionHistory', params);
          })
        Stack() {
          SymbolGlyph(item.isText ? $r('sys.symbol.book') : $r('sys.symbol.play_fill'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_primary')])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(HomeTheme.CardSurface)
        .border({ width: 1, color: AppColor.Divider })
        .shadow({ radius: 8, color: HomeTheme.CardShadow, offsetY: 2 })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
        .onClick(() => this.resumeRecord(item))
    }.margin({ left: 8 })
  }

  @Builder
  buildCover(item: ListenRecordView) {
    if (item.cover && item.cover.startsWith('http')) {
      Image(item.cover)
        .width(72)
        .height(72)
        .borderRadius(AppRadius.Sm)
        .objectFit(ImageFit.Cover)
        .sourceSize({ width: 300, height: 400 })
        .alt($r('app.media.app_icon_legacy'))
    } else if (item.cover && (item.cover.startsWith('/') || item.cover.startsWith('file://'))) {
      Image('file://' + item.cover.replace(/^file:\/\//, ''))
        .width(72)
        .height(72)
        .borderRadius(AppRadius.Sm)
        .objectFit(ImageFit.Cover)
        .sourceSize({ width: 300, height: 400 })
        .syncLoad(true)
    } else if (item.cover) {
      Image($rawfile(item.cover))
        .width(72)
        .height(72)
        .borderRadius(AppRadius.Sm)
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.app_icon_legacy'))
    } else if (item.bookId.startsWith('import_')) {
      LocalBookCover({ title: item.title, author: item.author, imgWidth: 72,
        imgHeight: 72, useFixedHeight: true, radius: AppRadius.Sm })
    } else {
      Stack() {
        Text(item.title ? item.title.substring(0, 1) : '?')
          .fontSize(24)
          .fontColor(AppColor.OnBrand)
          .fontWeight(FontWeight.Bold)
      }
      .width(72)
      .height(72)
      .borderRadius(AppRadius.Sm)
      .backgroundColor(HomeTheme.Accent)
    }
  }

  @Builder
  buildLoadingState() {
    Column({ space: AppSpace.Lg }) {
      ForEach([0, 1, 2], (_loadingIndex: number) => {
        Row({ space: AppSpace.Md }) {
          Column()
            .width(72)
            .height(72)
            .borderRadius(AppRadius.Sm)
            .backgroundColor(HomeTheme.ProgressTrack)
          Column({ space: AppSpace.Sm }) {
            Column().width('72%').height(16).borderRadius(8).backgroundColor(HomeTheme.ProgressTrack)
            Column().width('52%').height(12).borderRadius(6).backgroundColor(HomeTheme.ProgressTrack)
            Column().width('90%').height(3).borderRadius(2).backgroundColor(HomeTheme.ProgressTrack)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Center)
        }
        .height(88)
      }, (loadingIndex: number) => loadingIndex.toString())
    }
    .width('100%')
    .opacity(0.7)
  }

  @Builder
  buildEmptyState() {
    Column({ space: AppSpace.Md }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(26)
          .fontColor([HomeTheme.Accent])
      }
      .width(52)
      .height(52)
      .borderRadius(26)
      .backgroundColor(AppColor.BrandSoft)
      Text(this.onlyUnfavorited ? $r('app.string.record_unfavorited_empty') : $r('app.string.record_empty'))
        .fontSize(AppFont.BodyL)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
      Text(this.onlyUnfavorited ? $r('app.string.record_unfavorited_hint') : $r('app.string.record_empty_hint'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .height(190)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(HomeTheme.CardSurface)
    .borderRadius(AppRadius.Lg)
    .border({ width: 0.5, color: AppColor.Divider })
    .opacity(this.appeared ? 1 : 0)
    .animation({ duration: 460, delay: 160, curve: AppCurve.Decelerate })
  }
}
