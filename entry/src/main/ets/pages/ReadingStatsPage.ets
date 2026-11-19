import { PhysicalBookCover, PHYSICAL_BOOK_COVER_RADIUS } from '../components/PhysicalBookCover';
import { ImmersiveCircleButton } from '../components/ImmersiveCircleButton';
import { RecordActivityChart } from '../components/RecordActivityChart';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { ImmersiveSummaryTag } from '../components/ImmersiveSummaryTag';
import { RecordDissolveEffect } from '../components/RecordDissolveEffect';
import { DailyQuoteService } from '../service/DailyQuoteService';
import { DailyQuote } from '../model/DailyQuote';
import { PlatformCompat } from '../utils/PlatformCompat';
import { HdsCompat } from '../utils/HdsCompat';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { curves } from '@kit.ArkUI';
import { AppColor, AppMaterial, AppFont, AppRadius, AppSpace, HomeTheme, AppTheme } from '../theme/Theme';
import { ThemeBackgroundComponent } from '../components/ThemeBackgroundComponent';
import { AppBackgroundScene } from '../model/AppBackground';
import { ThemeBackgroundScene } from '../model/AppThemeVisual';
import { ThemeIconRole } from '../theme/ThemeIcons';
import { WindowUtils } from '../utils/WindowUtils';
import { PlayerDragTransition, PlayerDragState } from '../utils/PlayerDragTransition';
import { OneShotCoverState, OneShotTransitionCoordinator } from '../utils/OneShotTransition';
import {
  BookUsageStats,
  ActivityDay,
  UsageContentType,
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
import { BookPresentation } from '../model/BookPresentation';
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
  @Trace chapterIndex: number = -1;
  progressMs: number = 0;
  durationMs: number = 0;
  @Trace progressPercent: number = 0;
  @Trace listenSeconds: number = 0;
  @Trace updatedAt: number = 0;
  @Trace startsDay: boolean = false;
  @Trace endsDay: boolean = false;
  @Trace dateLabel: string = '';
  @Trace dayLabel: ResourceStr = '';
  @Trace timeLabel: string = '';
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
  removeRecords(bookIds: Set<string>): void {
    for (let index = this.items.length - 1; index >= 0; index--) {
      if (!bookIds.has(this.items[index].bookId)) continue;
      this.items.splice(index, 1);
      for (const listener of this.listeners) listener.onDataDelete(index);
    }
  }
  setRecords(records: ListenRecordView[]): void {
    const structureChanged: boolean = records.length !== this.items.length ||
      records.some((record: ListenRecordView, index: number): boolean => record.bookId !== this.items[index]?.bookId);
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
      item.chapterIndex = record.chapterIndex;
      item.progressMs = record.progressMs;
      item.durationMs = record.durationMs;
      item.progressPercent = record.progressPercent;
      item.listenSeconds = record.listenSeconds;
      item.updatedAt = record.updatedAt;
      item.startsDay = record.startsDay;
      item.endsDay = record.endsDay;
      item.dateLabel = record.dateLabel;
      item.dayLabel = record.dayLabel;
      item.timeLabel = record.timeLabel;
      item.isText = record.isText;
      item.isComic = record.isComic;
      item.readingPosition = record.readingPosition;
      return item;
    });
    // 同序记录的展示字段由 @Trace 刷新，避免进度更新触发整张列表重布局。
    if (structureChanged) {
      for (const listener of this.listeners) listener.onDataReloaded();
    }
  }
}

const MINI_TITLE_BAR_HEIGHT: number = 56;
const HISTORY_FILTER_SPRING: ICurve = curves.springMotion(0.34, 0.68);

@ComponentV2
export struct ReadingStatsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param inTab: boolean = false;
  @Param visible: boolean = true;
  /** 记录 Tab 只展示收藏书籍；时钟入口打开未收藏历史模式。 */
  @Param onlyUnfavorited: boolean = false;
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};
  @Event onContentScroll: (offset: number, state: ScrollState) => void = () => {};
  @Event onBackHandlerChange: (handler: (() => boolean) | undefined) => void = () => {};

  @Local statsReady: boolean = false;
  @Local playerTransition: PlayerDragState = PlayerDragTransition.getInstance().state;
  @Local detailCoverState: OneShotCoverState = OneShotTransitionCoordinator.getInstance().coverState;
  @Local dailyQuoteText: ResourceStr = $r('app.string.daily_quote_initial');
  @Local dailyQuoteSource: string = '';
  @Local dailyQuoteCardWidth: number = 0;
  @Local statsError: boolean = false;
  @Local streak: number = 0;
  @Local totalSeconds: number = 0;
  @Local activityDays: ActivityDay[] = [];
  @Local containerWidth: number = 0;
  @Local records: ListenRecordView[] = [];
  @Local contentFilter: number = 0;
  @Local contentFilterVisible: boolean = false;
  private readonly recordTitleBuilder: CustomBuilder = (): void => this.buildRecordTitleBar();
  @Local loading: boolean = true;
  @Local refreshing: boolean = false;
  @Local selectMode: boolean = false;
  @Local recordEditLocked: boolean = false;
  @Local recordEditLockReady: boolean = false;
  @Local savingRecordEditLock: boolean = false;
  @Local selectedIds: Set<string> = new Set();
  @Local deletingRecords: boolean = false;
  @Local dissolvingBookId: string = '';
  @Local collapsingBookId: string = '';

  private scroller: ListScroller = new ListScroller();
  private recordLoadGeneration: number = 0;
  private recordEditLockGeneration: number = 0;
  private deleteAnimationFinished: (() => void) | undefined = undefined;
  private recordDataSource: ListeningRecordDataSource = new ListeningRecordDataSource();
  private recoveryRunning: boolean = false;
  private openingDetail: boolean = false;
  private recoveryActive: boolean = false;
  private recoveryAttempted: Set<string> = new Set();
  private loadingStats: boolean = false;
  private reloadPending: boolean = false;
  private listScrolling: boolean = false;
  private dayTimer: number = -1;
  private visibleRefreshTimer: number = -1;
  private statsRefreshTimer: number = -1;
  private pageVisible: boolean = false;
  private recordVisibilityReady: boolean = false;
  private usageContentTypes: Map<string, UsageContentType> = new Map<string, UsageContentType>();
  private usageRecords: BookUsageStats[] | undefined = undefined;
  private loadedRecords: ListenRecordView[] = [];
  private loadedFavoriteIds: Set<string> = new Set<string>();
  private statsHandler = (_evt: emitter.EventData): void => {
    if (!this.pageVisible || !this.recoveryActive) return;
    if (this.listScrolling) {
      this.reloadPending = true;
      return;
    }
    // 阅读进度、统计和收藏排序会相邻发出事件，合并为一次取数。
    if (this.statsRefreshTimer !== -1) return;
    this.statsRefreshTimer = setTimeout((): void => {
      this.statsRefreshTimer = -1;
      this.loadStats();
    }, 120);
  };
  private favoritesHandler = (_evt: emitter.EventData): void => {
    this.recordVisibilityReady = true;
    this.recordLoadGeneration++;
    this.applyRecordVisibility();
    this.statsHandler(_evt);
  };

  aboutToAppear(): void {
    this.onBackHandlerChange((): boolean => this.handleBack());
    DiagnosticLogService.info('records.open', `unfavorited=${this.onlyUnfavorited}`);
    this.recoveryActive = true;
    this.loadRecordEditLock();
    this.recoveryAttempted.clear();
    const cached = this.recordVisibilityReady ? StatsService.getCachedStatsBundle(7, this.hiddenRecordBookIds(), this.usageContentTypes) : undefined;
    if (cached !== undefined) this.applyStatsBundle(cached);
    this.onScrollerReady(this.scroller);
    emitter.on(EVT_USAGE_STATS_UPDATED, this.statsHandler);
    emitter.on(EVT_FAVORITES_CHANGED, this.favoritesHandler);
    emitter.on(EVT_TEXT_READING_PROGRESS_CHANGED, this.statsHandler);
  }

  aboutToDisappear(): void {
    this.onBackHandlerChange(undefined);
    this.recoveryActive = false;
    this.recordEditLockGeneration++;
    this.finishDeleteAnimation();
    this.pageVisible = false;
    this.cancelVisibleRefresh();
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
    // 按日期保留可观察对象，让稳定 key 下的柱高随实时计时刷新。
    const existing = new Map<string, ActivityDay>();
    for (const day of this.activityDays) existing.set(day.day, day);
    const structureChanged: boolean = this.activityDays.length !== bundle.activityDays.length ||
      bundle.activityDays.some((day: ActivityDay, index: number): boolean => day.day !== this.activityDays[index]?.day);
    const days: ActivityDay[] = bundle.activityDays.map((day: ActivityDay): ActivityDay => {
      const item = existing.get(day.day);
      if (item === undefined) return day;
      item.comicSeconds = day.comicSeconds;
      item.readingSeconds = day.readingSeconds;
      item.audioSeconds = day.audioSeconds;
      item.unclassifiedSeconds = day.unclassifiedSeconds;
      return item;
    });
    if (structureChanged) this.activityDays = days;
    this.statsReady = true;
    this.statsError = false;
  }

  private cancelVisibleRefresh(): void {
    if (this.visibleRefreshTimer !== -1) clearTimeout(this.visibleRefreshTimer);
    this.visibleRefreshTimer = -1;
    if (this.statsRefreshTimer !== -1) clearTimeout(this.statsRefreshTimer);
    this.statsRefreshTimer = -1;
  }

  @Monitor('visible')
  onRecordTabVisibilityChanged(): void {
    if (this.inTab) this.handleRecordVisibility(this.visible, this.visible ? 1 : 0);
  }

  private handleRecordVisibility(visible: boolean, ratio: number): void {
    this.cancelVisibleRefresh();
    this.pageVisible = false;
    this.listScrolling = false;
    if (this.dayTimer !== -1) clearTimeout(this.dayTimer);
    this.dayTimer = -1;
    if (!visible || ratio < 0.99 || !this.recoveryActive || (this.inTab && !this.visible)) return;
    // 横滑露出一角不取数；完整显示稳定后再刷新，避免取数与滑动争抢 UI 线程。
    this.visibleRefreshTimer = setTimeout((): void => {
      this.visibleRefreshTimer = -1;
      if (!this.recoveryActive) return;
      this.pageVisible = true;
      this.loadRecordEditLock();
      this.loadStats();
      this.loadDailyQuote();
      this.scheduleDayRefresh();
    }, 220);
  }

  private scheduleDayRefresh(): void {
    if (this.dayTimer !== -1) clearTimeout(this.dayTimer);
    const now = new Date();
    const nextDay = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
    this.dayTimer = setTimeout((): void => {
      this.dayTimer = -1;
      if (!this.recoveryActive) return;
      this.loadStats();
      this.loadDailyQuote();
      this.scheduleDayRefresh();
    }, Math.max(1000, nextDay.getTime() - now.getTime()));
  }

  private loadDailyQuote(): void {
    if (this.onlyUnfavorited || !this.pageVisible) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    try {
      this.applyDailyQuote(DailyQuoteService.next(context));
    } catch (_error) { /* 资源异常时保留当前诗句，不影响记录和统计。 */ }
  }

  private applyDailyQuote(quote: DailyQuote): void {
    this.dailyQuoteText = quote.text;
    this.dailyQuoteSource = [quote.author, quote.source].filter((value: string): boolean => value.length > 0).join(' · ');
  }

  @Computed
  private get dailyQuoteInline(): boolean {
    if (this.dailyQuoteSource.length === 0) return true;
    const ui = this.getUIContext();
    const measure = ui.getMeasureUtils();
    const quoteWidth = measure.measureText({ textContent: this.dailyQuoteText, fontSize: 15 });
    const indentWidth = measure.measureText({ textContent: '　　', fontSize: 15 });
    const authorWidth = measure.measureText({
      textContent: $r('app.string.daily_quote_attribution', this.dailyQuoteSource), fontSize: AppFont.Caption
    });
    return ui.px2vp(quoteWidth + indentWidth + authorWidth) + 12 <= this.dailyQuoteCardWidth;
  }

  private async loadStats(): Promise<void> {
    // 缓存 Tab 的事件只在重新显示时统一读取，避免后台记录页争抢切换帧。
    if (!this.recoveryActive || !this.pageVisible) return;
    if (this.statsRefreshTimer !== -1) clearTimeout(this.statsRefreshTimer);
    this.statsRefreshTimer = -1;
    if (this.loadingStats || this.listScrolling || this.deletingRecords) {
      this.reloadPending = true;
      return;
    }
    this.reloadPending = false;
    this.loadingStats = true;
    const generation = this.recordLoadGeneration;
    let summaryLoaded: boolean = false;
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) { this.loadingStats = false; this.refreshing = false; return; }
    try {
      await PreferenceService.ensureReady(ctx);
      this.recordVisibilityReady = true;
      await StatsService.init(ctx);
      const usageRecords: BookUsageStats[] = await StatsService.getBookStats();
      if (!this.recoveryActive || !this.pageVisible) return;
      if (this.listScrolling) { this.reloadPending = true; return; }
      // 顶部统计独立于书籍明细；离线或某本书读取失败时仍显示持久化累计值。
      this.usageRecords = usageRecords;
      this.applyStatsBundle(StatsService.summarizeBookStats(usageRecords, 7,
        this.hiddenRecordBookIds(), this.usageContentTypes));
      summaryLoaded = true;
      let history: PlayHistoryItem[] = [];
      let favoriteIds: Set<string> = new Set();
      let reading: TextReadingPosition[] = [];
      await Promise.all([
        Promise.resolve().then(() => PreferenceService.getHistory()).then((items: PlayHistoryItem[]): void => { history = items; }),
        Promise.resolve().then(() => PreferenceService.getFavorites()).then((items: string[]): void => { favoriteIds = new Set(items); }),
        Promise.resolve().then(() => TextReadingProgressService.getAll(ctx, true)).then((items: TextReadingPosition[]): void => { reading = items; })
      ]);
      if (this.listScrolling) { this.reloadPending = true; return; }
      const allRecords = await this.buildRecordViews(ctx,
        usageRecords.filter((record: BookUsageStats): boolean => !record.archived), history, reading);
      if (!this.recoveryActive || !this.pageVisible) return;
      if (generation !== this.recordLoadGeneration || this.deletingRecords) { this.reloadPending = true; return; }
      if (this.listScrolling) { this.reloadPending = true; return; }
      this.loadedRecords = allRecords;
      this.loadedFavoriteIds = favoriteIds;
      this.applyRecordVisibility();
      this.recoverReadingBooks(ctx, reading).catch((error: Error): void => {
        DiagnosticLogService.info('records.recovery.failed', `${error.message}; ${error.stack ?? ''}`);
      });
    } catch (e) {
      if (!summaryLoaded) this.statsError = true;
      DiagnosticLogService.info('records.load.failed', `unfavorited=${this.onlyUnfavorited}; ` +
        (e instanceof Error ? `${e.message}; ${e.stack ?? ''}` : String(e)));
      console.error(`[ReadingStatsPage] load stats failed: ${JSON.stringify(e)}`);
    } finally {
      if (this.recoveryActive && this.pageVisible && !this.listScrolling) this.loading = false;
      this.refreshing = false;
      this.loadingStats = false;
      if (this.reloadPending && !this.listScrolling && !this.deletingRecords) {
        this.reloadPending = false;
        this.loadStats();
      }
    }
  }

  private finishRecordScroll(): void {
    this.listScrolling = false;
    // 播放进度、统计和收藏变更在滚动停止后合并刷新，避免惯性滚动中重排列表。
    if (this.reloadPending) this.loadStats();
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
    if (this.isRecordHidden(item)) return false;
    const isFavorite = favoriteIds.has(item.bookId) ||
      item.aliasBookIds.some((aliasBookId: string): boolean => favoriteIds.has(aliasBookId));
    return this.onlyUnfavorited ? !isFavorite : isFavorite;
  }

  private isRecordHidden(item: ListenRecordView): boolean {
    return BookPresentation.isHidden(item.bookId) ||
      item.aliasBookIds.some((bookId: string): boolean => BookPresentation.isHidden(bookId));
  }

  private hiddenRecordBookIds(): Set<string> {
    const ids = new Set<string>();
    for (const edit of BookPresentation.edits) {
      if (edit.hidden) ids.add(edit.bookId);
    }
    for (const item of this.loadedRecords) {
      if (!this.isRecordHidden(item)) continue;
      ids.add(item.bookId);
      for (const id of item.aliasBookIds) ids.add(id);
    }
    return ids;
  }

  private applyRecordVisibility(): void {
    this.records = this.loadedRecords.filter((item: ListenRecordView): boolean =>
      this.shouldShowRecord(item, this.loadedFavoriteIds));
    this.selectedIds = new Set<string>(Array.from(this.selectedIds).filter((id: string): boolean =>
      this.records.some((item: ListenRecordView): boolean => item.bookId === id)));
    if (this.selectedIds.size === 0) this.selectMode = false;
    this.applyContentFilter();
    const cached = this.usageRecords !== undefined ? StatsService.summarizeBookStats(this.usageRecords, 7,
      this.hiddenRecordBookIds(), this.usageContentTypes) :
      StatsService.getCachedStatsBundle(7, this.hiddenRecordBookIds(), this.usageContentTypes);
    if (cached !== undefined) this.applyStatsBundle(cached);
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
    this.usageContentTypes.clear();
    for (const book of await DataService.getBooks(context)) {
      metadata.set(book.id, book);
      this.usageContentTypes.set(book.id, book.contentType ?? 'audio');
    }
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
      const type: UsageContentType | undefined = book?.contentType ??
        (bookId.startsWith('search_comic_') || bookId.startsWith('home_comic_') ? 'comic' :
          candidate.isText ? 'text' : historyItem !== undefined || book !== undefined ? 'audio' : undefined);
      if (type !== undefined) this.usageContentTypes.set(bookId, type);
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
    view.chapterTitle = item.chapterTitle || (chapterIndex >= 0 ? book?.chapters[chapterIndex]?.title : '') || '';
    view.chapterIndex = chapterIndex;
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

  private canEditRecords(): boolean {
    return this.recordEditLockReady && !this.recordEditLocked && !this.savingRecordEditLock && !this.deletingRecords;
  }

  private async loadRecordEditLock(): Promise<void> {
    if (this.savingRecordEditLock) return;
    const generation = ++this.recordEditLockGeneration;
    this.recordEditLockReady = false;
    try {
      const locked = await PreferenceService.getRecordEditLocked();
      if (!this.recoveryActive || generation !== this.recordEditLockGeneration) return;
      this.recordEditLocked = locked;
      if (locked) {
        this.clearSelection();
        this.closeRecordSwipe();
      }
      this.recordEditLockReady = true;
    } catch (error) {
      DiagnosticLogService.info('records.editLock.load.failed', String(error));
    }
  }

  private async setRecordEditLocked(locked: boolean): Promise<void> {
    if (!this.recordEditLockReady || this.savingRecordEditLock || this.deletingRecords ||
      this.recordEditLocked === locked) return;
    this.recordEditLockGeneration++;
    const previous = this.recordEditLocked;
    this.savingRecordEditLock = true;
    this.recordEditLocked = locked;
    this.contentFilterVisible = false;
    this.clearSelection();
    this.closeRecordSwipe();
    try {
      await PreferenceService.setRecordEditLocked(locked);
    } catch (error) {
      this.recordEditLocked = previous;
      DiagnosticLogService.info('records.editLock.save.failed', String(error));
      if (this.recoveryActive) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
      }
    } finally {
      this.savingRecordEditLock = false;
    }
  }

  private handleRecordEditPress(): void {
    if (!this.recordEditLockReady || this.savingRecordEditLock || this.deletingRecords) return;
    if (this.recordEditLocked) {
      this.setRecordEditLocked(false);
      return;
    }
    if (this.loading || this.filteredRecords().length === 0) return;
    this.contentFilterVisible = false;
    this.closeRecordSwipe();
    if (this.selectMode) this.clearSelection();
    else this.selectMode = true;
  }

  private toggleSelect(bookId: string): void {
    if (!this.canEditRecords()) return;
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
    if (!this.canEditRecords()) return;
    this.selectedIds = new Set(this.filteredRecords().map((item: ListenRecordView): string => item.bookId));
    this.selectMode = this.selectedIds.size > 0;
  }

  private clearSelection(): void {
    this.selectedIds = new Set();
    this.selectMode = false;
  }

  private handleBack(): boolean {
    if (this.deletingRecords) return true;
    if (!this.selectMode) return false;
    this.clearSelection();
    return true;
  }

  private async confirmDeleteSelected(): Promise<void> {
    if (!this.canEditRecords() || this.selectedIds.size === 0) return;
    await this.confirmDeleteRecords(new Set<string>(this.selectedIds));
  }

  private async confirmDeleteRecord(item: ListenRecordView): Promise<void> {
    if (!this.canEditRecords() || this.selectMode) return;
    await this.confirmDeleteRecords(new Set<string>([item.bookId]), item);
  }

  private async confirmDeleteRecords(recordIds: Set<string>, single?: ListenRecordView): Promise<void> {
    if (!this.canEditRecords()) return;
    const deletedIds = new Set<string>(recordIds);
    for (const item of this.records) {
      if (!recordIds.has(item.bookId)) continue;
      for (const aliasBookId of item.aliasBookIds) deletedIds.add(aliasBookId);
    }
    const ids = Array.from(deletedIds);
    this.deletingRecords = true;
    this.recordLoadGeneration++;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.record_delete_title'),
        message: single ? $r('app.string.record_delete_single_confirm', single.title) :
          $r('app.string.record_delete_confirm', recordIds.size),
        buttons: [
          { text: $r('app.string.common_cancel'), color: AppTheme.TextPrimary },
          { text: $r('app.string.common_delete'), color: AppColor.BrandDark }
        ]
      });
      if (result.index !== 1 || !this.recoveryActive || this.recordEditLocked) return;
      await this.closeRecordSwipe();
      await this.deleteSelected(ids);
      if (single && this.recoveryActive && this.pageVisible) await this.animateRecordDelete(single.bookId);
      this.recordDataSource.removeRecords(recordIds);
      this.records = this.records.filter((item: ListenRecordView): boolean => !recordIds.has(item.bookId));
      this.loadedRecords = this.loadedRecords.filter((item: ListenRecordView): boolean => !recordIds.has(item.bookId));
      this.applyContentFilter();
      this.clearSelection();
    } catch (error) {
      DiagnosticLogService.info('records.delete.failed', String(error));
      if (this.recoveryActive) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.record_delete_failed') });
      }
    } finally {
      this.dissolvingBookId = '';
      this.collapsingBookId = '';
      this.deletingRecords = false;
      this.loadStats();
    }
  }

  private closeRecordSwipe(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      const timer = setTimeout(resolve, 350);
      try {
        this.scroller.closeAllSwipeActions({ onFinish: (): void => { clearTimeout(timer); resolve(); } });
      } catch (_error) { clearTimeout(timer); resolve(); }
    });
  }

  private finishDeleteAnimation(): void {
    const finish = this.deleteAnimationFinished;
    this.deleteAnimationFinished = undefined;
    finish?.();
  }

  private async animateRecordDelete(bookId: string): Promise<void> {
    await new Promise<void>((resolve: () => void): void => {
      const timer = setTimeout((): void => this.finishDeleteAnimation(), 4050);
      this.deleteAnimationFinished = (): void => { clearTimeout(timer); resolve(); };
      this.dissolvingBookId = bookId;
    });
    if (!this.recoveryActive || !this.pageVisible) return;
    await new Promise<void>((resolve: () => void): void => {
      const timer = setTimeout(resolve, 280);
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut,
        onFinish: (): void => { clearTimeout(timer); resolve(); } }, (): void => {
        this.collapsingBookId = bookId;
      });
    });
  }

  private async deleteSelected(ids: string[]): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) throw new Error('Record context unavailable');
    await StatsService.removeBookStats(ids);
    for (const id of ids) {
      await PreferenceService.removeHistory(id);
      await PreferenceService.removeProgress(id);
      await TextReadingProgressService.remove(context, id);
    }
  }

  private async openDetail(item: ListenRecordView): Promise<void> {
    if (!item.bookId || this.isRecordHidden(item) || this.selectMode || this.deletingRecords || this.openingDetail || this.playerTransition.active) return;
    this.openingDetail = true;
    const bookId = item.bookId;
    const stackSize = this.navStack.size();
    const transition = OneShotTransitionCoordinator.getInstance();
    try {
      await transition.captureAsync(this.getUIContext(), bookId, this.recordCoverId(item), PHYSICAL_BOOK_COVER_RADIUS);
      if (!this.recoveryActive || !this.visible || this.isRecordHidden(item) || this.selectMode || this.navStack.size() !== stackSize) {
        transition.discardPending();
        return;
      }
      this.navStack.pushPathByName('detail', bookId);
    } finally {
      this.openingDetail = false;
    }
  }

  private async resumeRecord(item: ListenRecordView): Promise<void> {
    if (!item.bookId || this.isRecordHidden(item) || this.selectMode || this.deletingRecords || this.openingDetail || this.playerTransition.active) return;
    if (item.isText) {
      const context = this.getUIContext().getHostContext();
      if (!context) return;
      const reading = item.readingPosition;
      if (reading && reading.bookId !== item.bookId) {
        await TextReadingProgressService.save(context, TextReadingPosition.atChar(item.bookId,
          reading.resourceIndex, reading.domPos, reading.charOffset, reading.pageOffset, reading.chapterTitle));
      }
      if (!this.isRecordHidden(item)) this.navStack.pushPathByName(item.isComic ? 'comicReader' : 'reader', TextReaderRouteParams.of(item.bookId));
      return;
    }
    const params: Record<string, Object> = {
      'bookId': item.bookId,
      'chapterId': item.chapterId,
      'progressMs': item.progressMs
    };
    // 以当前行封面为起点，沿用书架与迷你栏的播放器转场；测量失败仍正常续播。
    const transition = PlayerDragTransition.getInstance();
    const origin = transition.captureCover(this.getUIContext(), this.recordCoverId(item), PHYSICAL_BOOK_COVER_RADIUS);
    if (origin !== undefined) transition.beginTap(origin);
    this.navStack.pushPathByName('player', params);
  }

  private recordCoverId(item: ListenRecordView): string {
    return `record-cover-${this.inTab ? 'tab' : 'page'}-${this.onlyUnfavorited ? 'history' : 'saved'}-${item.bookId}`;
  }

  private openSessionHistory(item: ListenRecordView): void {
    if (this.deletingRecords || this.isRecordHidden(item)) return;
    const params: Record<string, Object> = { 'bookIds': JSON.stringify([item.bookId, ...item.aliasBookIds]) };
    this.navStack.pushPathByName('sessionHistory', params);
  }

  private applyContentFilter(): void {
    const records = this.filteredRecords();
    let previousDay: string = 'first';
    const today = new Date();
    const yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1);
    for (let index: number = 0; index < records.length; index++) {
      const item = records[index];
      const date = new Date(item.updatedAt);
      const day = item.updatedAt > 0 ? this.dateKey(date) : '';
      item.startsDay = day !== previousDay;
      const next = records[index + 1];
      const nextDay = next && next.updatedAt > 0 ? this.dateKey(new Date(next.updatedAt)) : '';
      item.endsDay = index === records.length - 1 || day !== nextDay;
      item.dateLabel = day === this.dateKey(today) || day === this.dateKey(yesterday) ?
        `${date.getMonth() + 1}.${date.getDate()}` : '';
      item.dayLabel = day.length === 0 ? $r('app.string.record_date_unknown') :
        day === this.dateKey(today) ? $r('app.string.record_date_today') :
        day === this.dateKey(yesterday) ? $r('app.string.record_date_yesterday') :
        $r('app.string.record_date_full', date.getFullYear(), date.getMonth() + 1, date.getDate());
      item.timeLabel = day.length > 0 ?
        `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}` : '';
      previousDay = day;
    }
    this.recordDataSource.setRecords(records);
  }

  private dateKey(date: Date): string {
    return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
  }

  private wideLayout(): boolean {
    return this.containerWidth >= AdaptiveLayout.LARGE_WIDTH;
  }

  private recordRowHeight(): number { return this.wideLayout() ? 92 : 88; }

  private recordItemHeight(item: ListenRecordView): number {
    return this.recordRowHeight() + (item.startsDay ? 36 : 0);
  }

  private recordKind(item: ListenRecordView): Resource {
    return item.isComic ? $r('app.string.comic_type') :
      item.isText ? $r('app.string.search_type_text') : $r('app.string.search_type_audio');
  }

  private recordChapter(item: ListenRecordView): ResourceStr {
    return item.chapterTitle || (item.chapterIndex >= 0 ?
      $r('app.string.reader_bookmark_position', item.chapterIndex + 1) : $r('app.string.record_read_started'));
  }

  private chooseContentFilter(index: number): void {
    if (this.deletingRecords || index === this.contentFilter) return;
    this.contentFilter = index;
    this.clearSelection();
    this.applyContentFilter();
  }

  private contentFilterLabel(index: number): Resource {
    if (index === 1) return $r('app.string.search_type_audio');
    if (index === 2) return $r('app.string.search_type_text');
    if (index === 3) return $r('app.string.comic_type');
    return $r('app.string.search_type_all');
  }

  private historyFilterWidth(): number {
    return this.containerWidth < 360 ? 200 : 216;
  }

  private historyFilterItemWidth(): number {
    return (this.historyFilterWidth() - 6) / 4;
  }

  private contentFilterOptions(): MenuOptions {
    const options: MenuOptions = {
      placement: Placement.BottomRight,
      backgroundColor: AppMaterial.SheetBackground,
      onDisappear: (): void => { this.contentFilterVisible = false; }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    else options.backgroundBlurStyle = AppMaterial.SheetBlur;
    return options;
  }

  @LocalBuilder
  buildContentFilterMenu() {
    Menu() {
      ForEach([0, 1, 2, 3], (index: number) => {
        MenuItem({ content: this.contentFilterLabel(index) }).contentFont({ size: AppFont.Body })
          .contentFontColor($r('sys.color.font_primary')).selected(index === this.contentFilter)
          .backgroundColor(index === this.contentFilter ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
          .onClick((): void => {
            this.contentFilterVisible = false;
            this.chooseContentFilter(index);
          })
      }, (index: number): string => index.toString())
    }.width(180)
  }

  @LocalBuilder
  buildRecordTitleBar() {
    Row({ space: 4 }) {
      if (!this.inTab) {
        ImmersiveCircleButton({ icon: $r('sys.symbol.chevron_left'), label: $r('app.string.app_icon_back'),
          diameter: 36, iconSize: 22, useMaterial: false,
          onPress: (): void => { if (!this.handleBack()) this.navStack.pop(); } })
      }
      Text(this.pageTitle()).fontSize(26).fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TextPrimary).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      // 与书架共用薄磨砂规格和标题的视觉对齐偏移。
      Row({ space: 4 }) {
        ImmersiveCircleButton({ icon: $r('sys.symbol.funnel'), themeIconRole: ThemeIconRole.Filter,
          diameter: 36, iconSize: 22, useMaterial: false,
          label: $r('app.string.record_content_filter'),
          iconColor: this.contentFilter > 0 ? AppColor.Brand : AppTheme.IconPrimary,
          onPress: (): void => { this.contentFilterVisible = !this.contentFilterVisible; } })
          .bindMenu(this.contentFilterVisible, this.buildContentFilterMenu, this.contentFilterOptions())
        ImmersiveCircleButton({ icon: $r('sys.symbol.bookmark'), label: $r('app.string.reader_excerpt_title'),
          diameter: 36, iconSize: 22, useMaterial: false,
          onPress: (): void => {
            this.contentFilterVisible = false;
            this.navStack.pushPathByName('readingExcerpts', '');
          } })
          .flexShrink(0)
        ImmersiveCircleButton({ icon: $r('sys.symbol.clock'),
          diameter: 36, iconSize: 22, useMaterial: false,
          label: this.onlyUnfavorited ? $r('app.string.record_favorited_back') : $r('app.string.record_unfavorited_title'),
          onPress: (): void => {
            this.contentFilterVisible = false;
            if (this.onlyUnfavorited) this.navStack.pop();
            else this.navStack.pushPathByName('unfavoriteHistory', null, false);
          } })
        ImmersiveCircleButton({ icon: this.recordEditLocked ? $r('sys.symbol.lock') :
          (this.selectMode ? $r('sys.symbol.checkmark') : $r('sys.symbol.square_and_pencil')),
          diameter: 36, iconSize: 22, useMaterial: false,
          label: this.recordEditLocked ? $r('app.string.record_edit_locked') :
            (this.selectMode ? $r('app.string.record_edit_done') : $r('app.string.record_edit')),
          iconColor: this.recordEditLocked || this.selectMode ? AppColor.Brand : AppTheme.IconPrimary,
          longPressEnabled: !this.selectMode && !this.recordEditLocked,
          onPress: (): void => this.handleRecordEditPress(),
          onLongPress: (): void => { this.setRecordEditLocked(true); } })
          .enabled(this.recordEditLockReady && !this.savingRecordEditLock)
      }.alignItems(VerticalAlign.Center).translate({ y: -2 }).flexShrink(0)
    }.width('100%').height(MINI_TITLE_BAR_HEIGHT).enabled(!this.deletingRecords)
      .alignItems(VerticalAlign.Center)
      .padding({ left: AppSpace.Md, right: AppSpace.Md }).clip(false)
  }

  private filteredRecords(): ListenRecordView[] {
    return this.records.filter((item: ListenRecordView): boolean =>
      !this.isRecordHidden(item) && (this.contentFilter === 0 || (this.contentFilter === 1 && !item.isText) ||
      (this.contentFilter === 2 && item.isText && !item.isComic) || (this.contentFilter === 3 && item.isComic)));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ThemeBackgroundComponent({ warmMid: 0.42, scene: ThemeBackgroundScene.Record, appScene: AppBackgroundScene.Record })

      HdsNavigation() {
        Refresh({ refreshing: $$this.refreshing, builder: this.refreshIndicator() }) {
          // 间距由各条目 margin 保持；显式为 0，避免链式动效额外加入默认 20vp。
          List({ scroller: this.scroller, space: 0 }) {
            if (!this.onlyUnfavorited) {
              ListItem() { this.buildDailyQuoteCard() }.margin({ bottom: AppSpace.Sm })
              ListItem() { this.buildSummaryCard() }
              ListItem() { this.buildRecordOverview() }.margin({ bottom: 20 })
            }
            ListItem() { this.buildHistoryHeader() }.margin({ bottom: 2 })
            if (this.loading) {
              ListItem() { this.buildLoadingState() }
            } else if (this.filteredRecords().length === 0) {
              ListItem() { this.buildEmptyState() }
            } else {
              if (this.selectMode) {
                ListItem() {
                  Row() {
                    Blank()
                    this.buildEditActions()
                  }.width('100%')
                }
              }
              LazyForEach(this.recordDataSource, (item: ListenRecordView) => {
                ListItem() {
                  Column() {
                    if (item.startsDay) this.buildRecordDate(item)
                    RecordDissolveEffect({ snapshotId: `${this.recordCoverId(item)}-dissolve`,
                      active: this.dissolvingBookId === item.bookId,
                      content: (): void => this.buildRecordItem(item),
                      onFinished: (): void => this.finishDeleteAnimation() })
                  }.width('100%').alignItems(HorizontalAlign.Start)
                }
                .height(this.collapsingBookId === item.bookId ? 0 : this.recordItemHeight(item))
                .margin({ bottom: 0 })
                .clip(false)
                .swipeAction({ end: this.selectMode || !this.canEditRecords() ? undefined :
                  (): void => this.buildRecordDeleteAction(item),
                  edgeEffect: SwipeEdgeEffect.None })
              }, (item: ListenRecordView): string => item.bookId)
            }
          }
          .width('100%')
          .height('100%')
          .cachedCount(5)
          .enableScrollInteraction(!this.deletingRecords)
          .onScrollStart((): void => {
            this.listScrolling = true;
          })
          .onScrollStop((): void => this.finishRecordScroll())
          .onDidScroll((offset: number, state: ScrollState): void => {
            this.onContentScroll(offset, state);
          })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .padding({
            left: AppSpace.Md,
            right: AppSpace.Md
          })
          // 首尾避让随列表滚动，避免 padding 将内容裁在悬浮底栏上方。
          .contentStartOffset(WindowUtils.getStatusBarHeightVp() + MINI_TITLE_BAR_HEIGHT +
            (this.onlyUnfavorited ? AppSpace.Sm : 0))
          .contentEndOffset(this.inTab ? WindowUtils.getFloatingTabBottomVp() :
            WindowUtils.getBottomSafeVp() + AppSpace.Xl)
        }
        .onRefreshing(() => { this.loadStats(); this.loadDailyQuote(); })
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
                mainTitleColor: AppTheme.TextPrimary
              },
              backIconStyle: {
                iconColor: AppTheme.IconPrimary
              },
              menuStyle: {
                iconColor: AppTheme.IconPrimary
              }
            }
          },
          scrollEffectStyle: {
            backgroundStyle: {
              backgroundColor: Color.Transparent
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: AppTheme.TextPrimary
              },
              backIconStyle: {
                iconColor: AppTheme.IconPrimary
              },
              menuStyle: {
                iconColor: AppTheme.IconPrimary
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
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => { this.containerWidth = Number(size.width); })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onVisibleAreaChange([0, 0.99], (visible: boolean, ratio: number): void => {
      this.handleRecordVisibility(visible, ratio);
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
  buildRecordOverview() {
    RecordActivityChart({ days: this.activityDays, ready: this.statsReady, failed: this.statsError,
      onRetry: (): void => { this.loadStats(); } })
  }

  @Builder
  buildHistoryHeader() {
    Row({ space: 10 }) {
      Text($r('app.string.record_history_heading')).fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TextPrimary).layoutWeight(1).maxLines(1)
      this.buildHistoryFilter()
    }.width('100%').constraintSize({ minHeight: 38 })
  }

  @Builder
  buildHistoryFilter() {
    // 固定局部尺寸驱动弹簧滑块，不随列表滚动追踪全局坐标或回写状态。
    Stack({ alignContent: Alignment.Start }) {
      Row().width(this.historyFilterItemWidth()).height(34).borderRadius(17)
        .backgroundColor($r('app.color.shelf_filter_selected_background'))
        .border({ width: 1, color: $r('app.color.shelf_filter_selected_border'), radius: 17 })
        .translate({ x: this.contentFilter * this.historyFilterItemWidth() })
        .animation({ curve: HISTORY_FILTER_SPRING })
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      Row({ space: 0 }) {
        ForEach([0, 1, 2, 3], (index: number) => {
          Button(this.contentFilterLabel(index), { type: ButtonType.Capsule })
            .layoutWeight(1).height(34).padding({ left: 4, right: 4 })
            .fontSize(this.containerWidth < 360 ? 12 : 13)
            .fontWeight(index === this.contentFilter ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(index === this.contentFilter ? HomeTheme.Accent : $r('sys.color.font_secondary'))
            .backgroundColor(Color.Transparent)
            .scale({ x: index === this.contentFilter ? 1.04 : 1, y: index === this.contentFilter ? 1.04 : 1 })
            .animation({ curve: HISTORY_FILTER_SPRING })
            .stateEffect(false).hoverEffect(HoverEffect.None)
            .accessibilitySelected(index === this.contentFilter)
            .onClick((): void => this.chooseContentFilter(index))
        }, (index: number): string => `record-filter-${index}`)
      }.width('100%').height(34)
    }.width(this.historyFilterWidth()).height(40).padding(3).flexShrink(0)
      .attributeModifier(AppMaterial.modifier(AppMaterial.SurfaceClean, Color.Transparent))
      .border({ width: 1, color: $r('app.color.shelf_filter_border'), radius: 20 })
      .borderRadius(20).clip(true).enabled(!this.deletingRecords)
      .id('record-type-filter')
  }

  @Builder
  buildRecordDate(item: ListenRecordView) {
    Row({ space: 8 }) {
      Text(item.dayLabel).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
      if (item.dateLabel.length > 0) {
        Text(item.dateLabel).fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
      Divider().strokeWidth(0.5).color($r('sys.color.comp_divider')).layoutWeight(1).margin({ left: 2 })
    }.width('100%').height(36).padding({ top: 7 })
  }


  @Builder
  buildSummaryCard() {
    Column({ space: 12 }) {
      Scroll() {
        Row({ space: 8 }) {
          ImmersiveSummaryTag({ neutralText: true, icon: $r('sys.symbol.clock'), label: $r('app.string.record_total_inline'),
            value: this.statsReady ? $r('app.string.record_summary_duration', Math.floor(this.totalListenSeconds() / 3600),
              Math.floor((this.totalListenSeconds() % 3600) / 60)) : $r('app.string.record_stats_pending') })
          ImmersiveSummaryTag({ neutralText: true, icon: $r('sys.symbol.calendar'), label: $r('app.string.record_streak'),
            value: this.statsReady ? $r('app.string.record_streak_days_compact', this.streak) :
              $r('app.string.record_stats_pending') })
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
      if (!this.statsReady || this.statsError) {
        Text(this.statsError ? $r('app.string.record_stats_read_failed') : $r('app.string.record_stats_loading'))
          .fontSize(AppFont.Caption).fontColor($r('sys.color.font_tertiary')).width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 2, bottom: 16 })
    .onClick(() => { if (this.statsError) this.loadStats(); })
  }

  @Builder
  buildDailyQuoteCard() {
    Column({ space: 6 }) {
      Text($r('app.string.daily_quote_title'))
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor(AppColor.Brand)
      if (this.dailyQuoteInline) {
        Row({ space: 12 }) {
          Text(this.dailyQuoteText).fontSize(15).lineHeight(23).textIndent('30fp')
            .fontColor(AppTheme.TextPrimary).layoutWeight(1)
          if (this.dailyQuoteSource.length > 0) {
            Text($r('app.string.daily_quote_attribution', this.dailyQuoteSource))
              .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
              .textAlign(TextAlign.End).flexShrink(0)
          }
        }.width('100%').alignItems(VerticalAlign.Center)
      } else {
        Column({ space: 2 }) {
          Text(this.dailyQuoteText).fontSize(15).lineHeight(23).textIndent('30fp')
            .fontColor(AppTheme.TextPrimary).width('100%')
          Text($r('app.string.daily_quote_attribution', this.dailyQuoteSource))
            .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
            .width('100%').textAlign(TextAlign.End)
        }.width('100%')
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding({ top: 0, bottom: 4 })
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
      this.dailyQuoteCardWidth = Number(size.width);
    })
  }

  @Builder
  buildEditActions() {
    if (this.selectMode) {
      Row({ space: AppSpace.Md }) {
        Text($r('app.string.shelf_select_all'))
          .fontSize(AppFont.Body)
          .fontColor(AppColor.Brand)
          .onClick(() => this.selectAll())
        Text($r('app.string.common_delete'))
          .fontSize(AppFont.Body)
          .fontColor(AppColor.BrandDark)
          .enabled(this.selectedIds.size > 0 && !this.deletingRecords)
          .onClick(() => this.confirmDeleteSelected())
        Text($r('app.string.common_cancel'))
          .fontSize(AppFont.Body)
          .fontColor(AppTheme.TextTertiary)
          .onClick(() => this.clearSelection())
      }
      .alignItems(VerticalAlign.Center)
      .enabled(!this.deletingRecords)

    }
  }

  @Builder
  buildRecordDeleteAction(item: ListenRecordView) {
    Row() {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(22).fontColor([$r('sys.color.ohos_id_color_warning')])
      }
      .width(44).height(44).padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.record_delete_title'))
      .enabled(!this.deletingRecords)
      .onClick((): void => { this.confirmDeleteRecord(item); })
    }.width(52).height(88).justifyContent(FlexAlign.End).alignItems(VerticalAlign.Center)
  }

  @Builder
  buildRecordItem(item: ListenRecordView) {
    Row({ space: this.wideLayout() ? 16 : 12 }) {
      if (this.selectMode) {
        Checkbox().select(this.selectedIds.has(item.bookId)).selectedColor(AppColor.Brand)
          .hitTestBehavior(HitTestMode.None).width(20).height(20).margin(0)
      }
      if (this.wideLayout()) {
        Text(item.timeLabel).fontSize(12).fontColor($r('sys.color.font_secondary')).width(48)
      }
      Stack() {
        this.buildRecordBookCover(item)
      }
      .width(48).height(68)
      .opacity(this.detailCoverState.hiddenSourceId === this.recordCoverId(item) ||
        (this.playerTransition.active && this.playerTransition.sourceNodeId === this.recordCoverId(item)) ? 0 : 1)

      Column({ space: 5 }) {
        Text(item.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.recordChapter(item)).fontSize(12).fontColor($r('sys.color.font_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Row({ space: 5 }) {
          SymbolGlyph(item.isText ? $r('sys.symbol.book') : $r('sys.symbol.headphones'))
            .fontSize(11).fontColor([AppColor.Brand])
          Text(this.recordKind(item)).fontSize(11).fontColor($r('sys.color.font_secondary'))
          if (!this.wideLayout()) {
            if (this.containerWidth >= 360 && item.timeLabel.length > 0) {
              Text(item.timeLabel).fontSize(11).fontColor($r('sys.color.font_tertiary'))
            }
            Text($r('app.string.record_progress_percent', item.progressPercent))
              .fontSize(11).fontColor($r('sys.color.font_secondary'))
          }
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.wideLayout()) {
        Column({ space: 7 }) {
          Text(item.isText ? $r('app.string.record_read_progress', item.progressPercent) :
            $r('app.string.record_listen_progress', item.progressPercent))
            .fontSize(12).fontColor($r('sys.color.font_secondary'))
          Stack({ alignContent: Alignment.Start }) {
            Column().width('100%').height(3).borderRadius(2).backgroundColor($r('sys.color.comp_divider'))
            Column().width(`${Math.max(0, Math.min(100, item.progressPercent))}%`)
              .height(3).borderRadius(2).backgroundColor($r('sys.color.font_primary'))
          }.width(88).height(3)
        }.alignItems(HorizontalAlign.End).width(100)
      }
      if (!this.selectMode) this.buildRecordActions(item)
    }
    .width('100%').height(this.recordRowHeight())
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: item.endsDay ? 0 : 0.5 }, color: $r('sys.color.comp_divider') })
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onClick((): void => {
      if (this.deletingRecords) return;
      if (this.selectMode) this.toggleSelect(item.bookId);
      else this.openDetail(item);
    })
    .gesture(LongPressGesture({ repeat: false, duration: 500 }).onAction((): void => {
      if (!this.canEditRecords()) return;
      this.closeRecordSwipe();
      this.selectMode = true;
      this.toggleSelect(item.bookId);
    }))
  }

  @Builder
  buildRecordActions(item: ListenRecordView) {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.clock')).fontSize(16).fontColor([AppColor.Brand])
      }
      .width(32).height(36).padding(0).backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.session_history'))
      .onClick((): void => this.openSessionHistory(item))
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(item.isText ? $r('sys.symbol.book') : $r('sys.symbol.play_fill'))
          .fontSize(16).fontColor([AppColor.Brand])
      }
      .width(36).height(36).padding(0).backgroundColor($r('sys.color.comp_background_tertiary'))
      .accessibilityText(item.isText ? $r('app.string.book_detail_continue_read') :
        $r('app.string.book_detail_continue_listen'))
      .onClick((): void => { this.resumeRecord(item); })
    }
  }

  @Builder
  buildRecordBookCover(item: ListenRecordView) {
    PhysicalBookCover({ url: item.cover, title: item.title, author: item.author,
      localPlaceholder: item.bookId.startsWith('import_'), imgWidth: 46 })
      .id(this.recordCoverId(item)).accessibilityLevel('no')
  }

  @Builder
  buildLoadingState() {
    Column({ space: AppSpace.Lg }) {
      ForEach([0, 1, 2], (_loadingIndex: number) => {
        Row({ space: AppSpace.Md }) {
          Column()
            .width(48)
            .height(68)
            .borderRadius(PHYSICAL_BOOK_COVER_RADIUS)
            .backgroundColor($r('sys.color.comp_divider'))
          Column({ space: AppSpace.Sm }) {
            Column().width('72%').height(16).borderRadius(8).backgroundColor($r('sys.color.comp_divider'))
            Column().width('52%').height(12).borderRadius(6).backgroundColor($r('sys.color.comp_divider'))
            Column().width('90%').height(3).borderRadius(2).backgroundColor($r('sys.color.comp_divider'))
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
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      Text(this.contentFilter > 0 ? $r('app.string.record_filter_empty') :
        this.onlyUnfavorited ? $r('app.string.record_unfavorited_empty') : $r('app.string.record_empty'))
        .fontSize(AppFont.BodyL)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
      Text(this.contentFilter > 0 ? $r('app.string.record_filter_hint') :
        this.onlyUnfavorited ? $r('app.string.record_unfavorited_hint') : $r('app.string.record_empty_hint'))
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .height(190)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }
}
