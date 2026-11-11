import { ComicReaderAppearance } from '../model/ComicReaderAppearance';
import { ComicAppearanceSettings } from '../components/ComicAppearanceSettings';
import { ReaderChapterJumpHint } from '../components/ReaderChapterJumpHint';
import { ReaderHapticService } from '../service/text/ReaderHapticService';
import { SliderGestureModifier } from '../utils/SliderGestureModifier';
import { ReaderWidgetService } from '../service/ReaderWidgetService';
import { GeneralSettings } from '../model/GeneralSettings';
import { ReaderBrightnessBar } from '../components/ReaderBrightnessBar';
import { ReaderBrightnessService } from '../service/text/ReaderBrightnessService';
import { ReaderHoldingHandService } from '../service/text/ReaderHoldingHandService';
import { ReaderVolumeKeyService } from '../service/text/ReaderVolumeKeyService';
import { ReaderSmartKeyService } from '../service/text/ReaderSmartKeyService';
import { curves } from '@kit.ArkUI';
import { ChapterSheetActions } from '../components/ChapterSheetActions';
import { ChapterSegmentGrid } from '../components/ChapterSegmentGrid';
import { ReaderTapPolicy, ReaderTouchTracker } from '../utils/ReaderTapPolicy';
import { TextReadingSettingsService } from '../service/text/TextReadingSettingsService';
import { ImmersiveOptionTabs } from '../components/ImmersiveOptionTabs';
import { ReaderSettingCard, ReaderSettingsSectionHeader } from '../components/ReaderSettingCard';
import { SettingsHintButton } from '../components/SettingsHintButton';
import { ReaderAutoPageSettings } from '../components/ReaderAutoPageSettings';
import { ReaderAutoPageService } from '../service/text/ReaderAutoPageService';
import { ReaderScreenOnService } from '../service/text/ReaderScreenOnService';
import { emitter } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsTabs, HdsTabsFloatingStyle } from '@kit.UIDesignKit';
import { HdsCompat, CompatibleTabsModifier } from '../utils/HdsCompat';
import { PlatformCompat } from '../utils/PlatformCompat';
import { ReadingSessionService, SessionLocation } from '../service/ReadingSessionService';
import { Book, Chapter } from '../model/Book';
import { TextReaderRouteParams, TextReadingPosition, TextReadingSettings } from '../model/TextReading';
import { AppColor, AppMaterial, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { SearchCache } from '../utils/SearchCache';
import { DataService } from '../service/DataService';
import { BookSourceService } from '../service/BookSourceService';
import { PreferenceService } from '../service/PreferenceService';
import { TextReadingProgressService } from '../service/text/TextReadingProgressService';
import { ComicPage, ComicPageDataSource, ComicReaderService } from '../service/ComicReaderService';
import { ReaderCacheService } from '../service/ReaderCacheService';
import { OnlineTextContentCache } from '../service/text/OnlineTextContentCache';
import { ComicSuperResolutionService } from '../service/ComicSuperResolutionService';
import { MembershipState } from '../model/MembershipState';
import { MembershipService } from '../service/MembershipService';
import { ComicPageImage } from '../components/ComicPageImage';
import { ComicColorizationService } from '../service/ComicColorizationService';
import { ComicOfflineTranslationHost } from '../components/ComicOfflineTranslationHost';
import { ComicOfflineTranslationService } from '../service/ComicOfflineTranslationService';
import { ComicTranslationModelService } from '../service/ComicTranslationModelService';
import { ComicContinuousComponent } from '../components/ComicContinuousComponent';
import { ChapterCacheIndicator } from '../components/ChapterCacheIndicator';
import { ImmersiveCircleButton } from '../components/ImmersiveCircleButton';
import { ReaderSettingsPopup } from '../components/ReaderSettingsPopup';
import { ReaderAutoPageControls } from '../components/ReaderAutoPageControls';
import { BookSourceSwitchSheet } from '../components/BookSourceSwitchSheet';
import { ChapterDataSource } from '../utils/ChapterDataSource';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { WindowUtils } from '../utils/WindowUtils';

class ComicChapterJumpPosition {
  bookId: string = '';
  chapterIndex: number = 0;
  pageIndex: number = 0;
  fraction: number = 0;
}

@ComponentV2
export struct ComicReaderPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param params: TextReaderRouteParams = new TextReaderRouteParams();
  @Local book: Book | undefined = undefined;
  @Local chapterIndex: number = 0;
  @Local chapterPreview: number = -1;
  @Local chapterSliderDragging: boolean = false;
  @Local chapterSliderCommitting: boolean = false;
  @Local chapterSliderUndoPosition: ComicChapterJumpPosition | null = null;
  private chapterSliderGeneration: number = 0;
  @Local pageIndex: number = 0;
  @Local pageCount: number = 0;
  @Local busy: boolean = true;
  @Local failed: boolean = false;
  @Local chrome: boolean = false;
  @Local topSafe: number = WindowUtils.getStatusBarHeightVp();
  @Local bottomSafe: number = WindowUtils.getBottomSafeVp();
  @Local leftSafe: number = WindowUtils.getLeftSafeVp();
  @Local rightSafe: number = WindowUtils.getRightSafeVp();
  @Local mode: number = 0;
  @Local pageLayout: number = 1;
  @Local displayMode: number = 0;
  @Local trimWhiteBorder: boolean = false;
  @Local pageOverlap: number = 10;
  private pageFraction: number = 0;
  @Local scrollInitialFraction: number = 0;
  @Local superResolution: boolean = false;
  @Local zoomActive: boolean = false;
  @Local zoomOwner: string = '';
  @Local viewportTop: number = 0;
  private touchConsumed: boolean = false;
  @Local membership: MembershipState = MembershipState.current;
  @Local savingSuperResolution: boolean = false;
  @Local colorization: boolean = false;
  @Local translation: boolean = false;
  @Local translationDownloading: boolean = false;
  @Local showTranslationMenu: boolean = false;
  @Local showReaderMenu: boolean = false;
  @Local switchingText: boolean = false;
  @Local translationDownloadPercent: number = 0;
  private translationIntent: number = 0;
  @Local translationDirection: string = 'ja-zh';
  @Local translationConfigured: boolean = false;
  @Local pageTurnHaptic: string = 'none';
  @Local volumeKeyPageTurn: boolean = false;
  @Local smartKeyPageTurn: boolean = false;
  @Local keyTurnRequest: number = 0;
  @Local autoPageRunning: boolean = false;
  @Local autoPagePaused: boolean = false;
  @Local autoPageRequest: number = 0;
  @Local autoPageSeconds: number = ReaderAutoPageService.DEFAULT_SECONDS;
  @Local autoScrollSpeed: number = 30;
  @Local autoScrollReady: boolean = false;
  private autoPage: ReaderAutoPageService = new ReaderAutoPageService();
  private screenOn: ReaderScreenOnService = new ReaderScreenOnService();
  @Local appearance: ComicReaderAppearance = new ComicReaderAppearance();
  @Local systemDark: boolean = WindowUtils.isDarkMode();

  @Computed
  get canvasColor(): string { return this.appearance.background(this.systemDark); }

  @Computed
  get canvasInk(): string {
    const option = this.systemDark ? this.appearance.darkBackground : this.appearance.lightBackground;
    return this.systemDark || option === 0 ? '#CCCCCC' : '#444444';
  }
  private colorModeChanged = (): void => {
    this.systemDark = WindowUtils.isDarkMode();
    this.syncBackgroundContrast();
  };

  private syncBackgroundContrast(): void {
    const option = this.systemDark ? this.appearance.darkBackground : this.appearance.lightBackground;
    WindowUtils.setReaderStatusBarLight(this.systemDark || option === 0).catch((): void => {});
  }
  @Local settingsSaving: boolean = false;
  @Local imagePreloadCount: number = 5;
  private imagePreloadGeneration: number = 0;
  private volumeKeys: ReaderVolumeKeyService = new ReaderVolumeKeyService();
  private smartKeys: ReaderSmartKeyService = new ReaderSmartKeyService();
  private touchX: number = 0;
  private touchY: number = 0;
  private touchPageIndex: number = 0;
  private touchGeneration: number = 0;
  private touchStartedAt: number = 0;
  private touchTracker: ReaderTouchTracker = new ReaderTouchTracker();
  @Local showChapterBar: boolean = true;
  @Local showBrightnessBar: boolean = true;
  @Local readingBrightness: number = -1;
  @Local holdingHandLeft: boolean = false;
  @Local generalSettings: GeneralSettings = GeneralSettings.current;
  @Local readerVisible: boolean = true;
  private brightnessControl: ReaderBrightnessService = new ReaderBrightnessService();
  private holdingHand: ReaderHoldingHandService = new ReaderHoldingHandService();

  @Monitor('generalSettings.adaptiveHandedness')
  private syncHoldingHand(): void {
    this.holdingHand.setVisible(this.alive && this.readerVisible && this.generalSettings.adaptiveHandedness);
    if (!this.generalSettings.adaptiveHandedness) this.updateHoldingHand(false);
  }

  private updateHoldingHand(left: boolean): void {
    if (this.holdingHandLeft === left) return;
    if (!this.alive || !this.readerVisible) {
      this.holdingHandLeft = left;
      return;
    }
    this.getUIContext().animateTo({ curve: curves.springMotion(0.4, 1) }, (): void => {
      this.holdingHandLeft = left;
    });
  }
  private readonly tapLeftPercent: number = 100 / 3;
  private readonly tapRightPercent: number = 100 / 3;
  private turning: boolean = false;
  @Local showChapters: boolean = false;
  @Local chapterQuery: string = '';
  @Local chapterSegmented: boolean = false;
  @Local chapterDescending: boolean = false;
  @Local chapterTopRequest: number = 0;
  @Local chapterBottomRequest: number = 0;
  @Local chapterListOffsetFromCurrent: number = 0;
  private chapterListScroller: Scroller = new Scroller();
  private chapterPositionGeneration: number = 0;
  @Local showSettings: boolean = false;
  @Local showSourceSwitch: boolean = false;
  @Local sheetPresented: boolean = false;
  @Local loadingSeconds: number = 0;
  private loadStartedAt: number = Date.now();
  private loadFeedbackTimer: number = -1;
  @Local widthVp: number = 360;
  @Local heightVp: number = 640;
  @Local saveFailed: boolean = false;
  private pages: ComicPageDataSource = new ComicPageDataSource();
  private chapters: ChapterDataSource = new ChapterDataSource();
  @Local scrollResetToken: number = 0;
  @Local scrollInitialPages: ComicPage[] = [];
  private activeChapterPages: ComicPage[] = [];
  private preparedComicChapters: Map<number, ComicPage[]> = new Map();
  private diskCacheOwner: string = ReaderCacheService.owner();

  private protectComicCache(): void {
    if (!this.alive) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    ReaderCacheService.configure(context);
    const paths = this.activeChapterPages.map((page: ComicPage): string => page.url);
    for (const pages of this.preparedComicChapters.values()) {
      for (const page of pages) paths.push(page.url);
    }
    ReaderCacheService.protect(this.diskCacheOwner, paths);
    const book = this.book;
    if (book) {
      const keys: string[] = [];
      const indexes = Array.from(this.preparedComicChapters.keys());
      indexes.push(this.chapterIndex);
      for (const index of indexes) {
        const chapter = book.chapters[index];
        if (chapter) keys.push(OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id,
          chapter.originSourceValue || chapter.source.value));
      }
      OnlineTextContentCache.protect(context, `${this.diskCacheOwner}-lists`, keys);
    }
  }
  private preloadGeneration: number = 0;
  private swiper: SwiperController = new SwiperController();
  private generation: number = 0;
  private alive: boolean = false;
  @Local foreground: boolean = true;
  private backgroundHandler = (): void => {
    this.stopAutoPage();
    this.translationIntent++;
    ComicColorizationService.release();
    this.imagePreloadGeneration++;
    this.savePosition(); this.foreground = false; this.volumeKeys.dispose(); this.smartKeys.dispose(); ReadingSessionService.end('reading');
  };
  private foregroundHandler = (): void => {
    this.foreground = true; this.syncVolumeKeys(); this.savePosition(); this.updateImagePreload();
  };
  private saveTimer: number = -1;
  private restoreTimer: number = -1;
  private saveChain: Promise<void> = Promise.resolve();
  private safeAreaListener = (top: number, bottom: number): void => {
    this.topSafe = top;
    this.bottomSafe = bottom;
    this.leftSafe = WindowUtils.getLeftSafeVp();
    this.rightSafe = WindowUtils.getRightSafeVp();
  };

  private toggleChrome(): void {
    if (this.showChapters || this.showSettings || this.showSourceSwitch || this.chapterSliderCommitting) return;
    this.chrome = !this.chrome;
    if (!this.chrome) this.resetChapterSlider();
    WindowUtils.setReaderStatusBarVisible(this.chrome);
  }

  private onContentTap(event: ClickEvent): void {
    if (this.zoomActive || this.touchConsumed || !this.touchTracker.canTap() || this.busy || this.failed) return;
    const action = ReaderTapPolicy.resolve(ReaderTapPolicy.DEFAULT, event.windowX - this.leftSafe, event.windowY,
      this.widthVp - this.leftSafe - this.rightSafe, this.heightVp, this.tapLeftPercent, this.tapRightPercent);
    if (action === 1 || this.mode === 0) this.toggleChrome();
    // 两侧翻页已在 Touch Up 立即处理，避免原生点击回调重复翻页。
  }

  private onZoomChanged(owner: string, active: boolean): void {
    if (active) this.zoomOwner = owner;
    else if (this.zoomOwner === owner) this.zoomOwner = '';
    this.zoomActive = this.zoomOwner.length > 0;
    // 缩回原大小后的最后一次抬指也属于缩放，不能再触发点击或跨章滑动。
    this.touchConsumed = true;
    this.touchTracker.cancel();
  }

  private reportError(error: Object): void {
    const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
    hilog.error(0x0001, 'ComicReader', 'chapter=%{public}d failed=%{public}s', this.chapterIndex,
      message.replace(/https?:\/\/\S+/g, '[address]'));
    this.chrome = true;
    WindowUtils.setReaderStatusBarVisible(true);
  }

  aboutToAppear(): void {
    this.alive = true;
    this.systemDark = WindowUtils.isDarkMode();
    WindowUtils.addReaderColorListener(this.colorModeChanged);
    this.readerVisible = true;
    this.holdingHand.onChange = (left: boolean): void => { this.updateHoldingHand(left); };
    this.syncHoldingHand();
    const context = this.getUIContext().getHostContext();
    if (context) {
      this.brightnessControl.onFailure = (): void => {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_brightness_failed') });
      };
      this.brightnessControl.init(context).catch((): void => {});
      this.brightnessControl.setVisible(true);
      this.screenOn.init(context).catch((): void => {});
      this.screenOn.setVisible(true);
    }
    this.loadFeedbackTimer = setInterval((): void => {
      if (this.busy) this.loadingSeconds = Math.floor((Date.now() - this.loadStartedAt) / 1000);
    }, 1000);
    WindowUtils.addSafeAreaListener(this.safeAreaListener);
    emitter.on('app.reader.background', this.backgroundHandler);
    emitter.on('app.reader.foreground', this.foregroundHandler);
    WindowUtils.setStatusBarLight(true);
    WindowUtils.setReaderStatusBarLight(true);
    WindowUtils.setReaderStatusBarVisible(false);
    this.initialize();
    this.translationConfigured = ComicOfflineTranslationService.supported();
  }

  aboutToDisappear(): void {
    this.resetChapterSlider();
    this.stopAutoPage();
    this.screenOn.dispose();
    this.translationIntent++;
    ComicColorizationService.release();
    this.volumeKeys.dispose();
    this.smartKeys.dispose();
    ReaderCacheService.release(this.diskCacheOwner);
    ReaderCacheService.release(`${this.diskCacheOwner}-lists`);
    this.readerVisible = false;
    this.holdingHand.setVisible(false);
    this.brightnessControl.dispose();
    if (this.loadFeedbackTimer >= 0) clearInterval(this.loadFeedbackTimer);
    this.savePosition();
    this.alive = false;
    WindowUtils.removeReaderColorListener(this.colorModeChanged);
    ComicReaderService.cancelPendingExcept();
    WindowUtils.removeSafeAreaListener(this.safeAreaListener);
    emitter.off('app.reader.background', this.backgroundHandler);
    emitter.off('app.reader.foreground', this.foregroundHandler);
    ReadingSessionService.end('reading');
    this.generation++;
    if (this.saveTimer >= 0) clearTimeout(this.saveTimer);
    if (this.restoreTimer >= 0) clearTimeout(this.restoreTimer);
    WindowUtils.setStatusBarLight(false);
  }

  private async initialize(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) { this.busy = false; this.failed = true; return; }
    try {
      let book = SearchCache.get(this.params.bookId) ?? await DataService.getBookById(context, this.params.bookId);
      if (!book || book.contentType !== 'comic') throw new Error('Comic unavailable');
      if (book.chapters.length === 0) book.chapters = await DataService.getChaptersForBook(book.id);
      if (book.chapters.length === 0) book = await BookSourceService.loadTextBook(book);
      await PreferenceService.applyTocOrder(book);
      const position = await TextReadingProgressService.get(context, book.id);
      const superResolution = await PreferenceService.getComicSuperResolution();
      const settings = await TextReadingSettingsService.get(context);
      // 首次沿用旧章节条偏好，此后漫画与小说分别保存。
      const showChapterBar = await PreferenceService.getComicChapterBar(settings.showChapterBar);
      const mode = await PreferenceService.getComicReadingMode();
      const autoPageSeconds = await PreferenceService.getAutoPageSeconds(true);
      const autoScrollSpeed = await PreferenceService.getAutoScrollSpeed(true);
      const pageLayout = await PreferenceService.getComicPageLayout();
      const displayMode = await PreferenceService.getComicDisplayMode();
      const trimWhiteBorder = await PreferenceService.getComicTrimWhiteBorder();
      const appearance = await PreferenceService.getComicAppearance();
      const pageOverlap = await PreferenceService.getComicPageOverlap();
      const volumeKeyPageTurn = await PreferenceService.getComicVolumeKeyPageTurn();
      const pageTurnHaptic = await PreferenceService.getComicPageTurnHaptic();
      const showBrightnessBar = await PreferenceService.getComicBrightnessBar();
      const brightness = await PreferenceService.getComicBrightness();
      const imagePreloadCount = await PreferenceService.getComicImagePreloadCount();
      const translationDirection = await PreferenceService.getComicTranslationDirection();
      if (!this.alive) return;
      this.appearance = appearance;
      this.syncBackgroundContrast();
      this.translationDirection = translationDirection;
      this.imagePreloadCount = imagePreloadCount;
      this.showChapterBar = showChapterBar;
      this.volumeKeyPageTurn = volumeKeyPageTurn;
      this.pageTurnHaptic = pageTurnHaptic;
      // 智控键入口暂时隐藏，旧配置也不再启用事件订阅。
      this.smartKeyPageTurn = false;
      this.showBrightnessBar = showBrightnessBar;
      this.readingBrightness = brightness;
      this.brightnessControl.configure(brightness);
      this.superResolution = superResolution && ComicSuperResolutionService.supported();
      this.book = book;
      SearchCache.put(book);
      this.chapters.setChapters(book.chaptersDescending ? book.chapters.slice().reverse() : book.chapters);
      const explicit = this.params.resourceIndex >= 0;
      this.mode = mode;
    this.refreshSplitPages(true);
      this.autoPageSeconds = autoPageSeconds;
      this.autoScrollSpeed = autoScrollSpeed;
      this.pageLayout = pageLayout;
      this.displayMode = displayMode;
      this.trimWhiteBorder = trimWhiteBorder;
      this.pageOverlap = pageOverlap;
      const initialIndex = Math.max(0, Math.min(book.chapters.length - 1,
        explicit ? this.params.resourceIndex : position?.resourceIndex ?? 0));
      const initialPage = !explicit && position && !position.domPos.startsWith('comic:') && book.id.startsWith('import_') ?
        await ComicReaderService.localPageOffset(book, book.chapters[initialIndex], position.charOffset) :
        explicit ? 0 : position?.pageOffset ?? 0;
      const savedFraction = !explicit && position?.domPos.startsWith('comic:') ? Number(position.domPos.split('@')[1] ?? 0) : 0;
      await this.loadChapter(initialIndex, initialPage, false, savedFraction);
    } catch (error) {
      if (this.alive) { this.reportError(error); this.failed = true; this.busy = false; }
    }
  }

  private async loadChapter(index: number, page: number = 0, force: boolean = false, fraction: number = 0,
    keepChapterHint: boolean = false): Promise<boolean> {
    if (!keepChapterHint) this.resetChapterSlider();
    this.loadStartedAt = Date.now();
    this.loadingSeconds = 0;
    const book = this.book;
    if (!book || index < 0 || index >= book.chapters.length) {
      this.failed = true; this.busy = false; return false;
    }
    this.savePosition();
    this.preloadGeneration++;
    ComicReaderService.cancelPendingExcept(book, book.chapters[index]);
    const generation = ++this.generation;
    const retainCurrent = this.pageCount > 0;
    this.busy = true;
    this.failed = false;
    hilog.info(0x0001, 'ComicReader', 'load start chapter=%{public}d force=%{public}s', index, String(force));
    try {
      let pages = !force && this.preparedComicChapters.has(index) ? this.preparedComicChapters.get(index)! :
        await ComicReaderService.load(book, book.chapters[index], this.getUIContext().getHostContext(), force);
      // 切换类型保留原目录；漫画模式跳过版权/前言等纯文字章节。
      if (book.id.startsWith('import_') && pages.length === 0) {
        const start = index;
        let direction = retainCurrent && index < this.chapterIndex ? -1 : 1;
        for (let tried = 1; tried < book.chapters.length && pages.length === 0; tried++) {
          index += direction;
          if (index < 0 || index >= book.chapters.length) {
            if (retainCurrent) break;
            direction = -1;
            index = start - 1;
            if (index < 0) break;
          }
          pages = await ComicReaderService.load(book, book.chapters[index], this.getUIContext().getHostContext());
          if (!this.alive || generation !== this.generation) return false;
        }
        page = 0;
      }
      if (!this.alive || generation !== this.generation) return false;
      if (pages.length === 0) throw new Error('No comic images');
      this.chapterIndex = index;
      this.pages.setPages(pages);
      this.activeChapterPages = pages;
      this.scrollInitialPages = pages;
      this.scrollResetToken++;
      this.preparedComicChapters.clear();
      this.protectComicCache();
      this.pageIndex = Math.max(0, Math.min(page, pages.length - 1));
      this.pageFraction = Number.isFinite(fraction) ? Math.max(0, Math.min(1, fraction)) : 0;
      this.scrollInitialFraction = this.pageFraction;
      this.pageCount = pages.length;
      this.busy = false;
      this.refreshSplitPages(true);
      this.restorePage();
      this.autoPage.restart();
      this.scheduleSave();
      this.preloadChapters(book, index, generation);
      hilog.info(0x0001, 'ComicReader', 'load complete chapter=%{public}d pages=%{public}d', index, pages.length);
      return true;
    } catch (error) {
      if (this.alive && generation === this.generation) {
        this.stopAutoPage();
        hilog.error(0x0001, 'ComicReader', 'load failed target=%{public}d retained=%{public}s', index, String(retainCurrent));
        this.reportError(error); this.failed = !retainCurrent; this.busy = false;
        if (retainCurrent) this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_next_failed') });
      }
    }
    return false;
  }

  private async preloadChapters(book: Book, index: number, generation: number): Promise<void> {
    const ticket = ++this.preloadGeneration;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const count = await PreferenceService.getPreloadChapters();
    for (let distance = 1; distance <= count; distance++) {
      if (!this.alive || !this.foreground || generation !== this.generation || ticket !== this.preloadGeneration) return;
      const target = index + distance;
      if (target < 0 || target >= book.chapters.length) return;
      if (distance > await PreferenceService.getPreloadChapters()) return;
      try {
        const pages = await ComicReaderService.load(book, book.chapters[target], context, false, true);
        if (!this.alive || generation !== this.generation || ticket !== this.preloadGeneration) return;
        if (Math.abs(target - this.chapterIndex) <= 3) this.preparedComicChapters.set(target, pages);
        this.protectComicCache();
        const complete = await ComicReaderService.preloadImages(book, book.chapters[target], pages, context,
          (): boolean => !this.alive || !this.foreground || generation !== this.generation ||
            target === this.chapterIndex || ticket !== this.preloadGeneration);
        this.protectComicCache();
        if (!complete) return;
      }
      catch (_error) { return; }
    }
  }

  @Monitor('pageIndex', 'chapterIndex', 'busy', 'imagePreloadCount')
  private updateImagePreload(): void {
    const ticket = this.imagePreloadGeneration;
    if (!this.alive || !this.foreground || this.busy || this.failed || this.imagePreloadCount === 0) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const generation = this.generation;
    const pages = this.activeChapterPages;
    const count = this.imagePreloadCount;
    ComicReaderService.preloadNearbyImages(pages, this.pages.getData(this.pageIndex)?.index ?? this.pageIndex, count, context,
      (): boolean => !this.alive || !this.foreground || this.busy || generation !== this.generation ||
        ticket !== this.imagePreloadGeneration || pages !== this.activeChapterPages || count !== this.imagePreloadCount,
      // Keep an in-flight image when it becomes the current page, so the visible consumer can join it.
      (index: number): boolean => index >= (this.pages.getData(this.pageIndex)?.index ?? this.pageIndex) &&
         index <= (this.pages.getData(this.pageIndex)?.index ?? this.pageIndex) + this.imagePreloadCount
    ).catch((): void => {});
  }

  private restorePage(): void {
    if (this.usesContinuousPages()) return;
    if (this.restoreTimer >= 0) clearTimeout(this.restoreTimer);
    const target = this.pageIndex;
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      if (!this.alive || this.busy || this.pageCount === 0) return;
      if (!this.usesContinuousPages() && this.mode !== 3) this.swiper.changeIndex(target, false);
    }, 100);
  }

  private scheduleSave(): void {
    if (this.saveTimer >= 0) clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout((): void => { this.saveTimer = -1; this.savePosition(); }, 500);
  }

  private savePosition(): void {
    const startedAt = Date.now();
    const context = this.getUIContext().getHostContext();
    if (!context || !this.book || this.busy || this.failed || this.pageCount === 0) return;
    const mode = this.mode === 0 ? 'comic:scroll' : this.mode === 1 ? 'comic:paged' : this.mode === 2 ? 'comic:rtl' : 'comic:dissolve';
    const position = TextReadingPosition.of(this.book.id, this.chapterIndex, `${mode}@${this.pageFraction}`,
      this.pages.getData(this.pageIndex)?.index ?? this.pageIndex, this.book.chapters[this.chapterIndex].title);
    ReadingSessionService.checkpoint('reading', SessionLocation.text(this.book, position), this.foreground);
    if (Date.now() - startedAt >= 8) console.info(`[ComicPerf] progress-checkpoint ms=${Date.now() - startedAt}`);
    const book = this.book;
    this.saveChain = this.saveChain.then((): Promise<void> => TextReadingProgressService.save(context, position))
      .then((): void => { ReaderWidgetService.update(context, book, position); })
      .then((): void => { if (this.alive) this.saveFailed = false; })
      .catch((): void => { if (this.alive) this.saveFailed = true; });
  }

  private adjacent(direction: number): number {
    return this.chapterIndex + direction;
  }

  private canChange(direction: number): boolean {
    return !this.busy && this.adjacent(direction) >= 0 && this.adjacent(direction) < (this.book?.chapters.length ?? 0);
  }

  private async changeMode(mode: number): Promise<void> {
    if (this.settingsSaving || mode === this.mode) return;
    this.settingsSaving = true;
    try {
      await PreferenceService.setComicReadingMode(mode);
      if (this.alive) this.applyMode(mode);
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    } finally { this.settingsSaving = false; }
  }

  private applyMode(mode: number): void {
    this.turning = false;
    this.mode = mode;
    this.refreshSplitPages(true);
    if (this.usesContinuousPages()) {
      this.scrollInitialPages = this.activeChapterPages;
      this.scrollInitialFraction = this.pageFraction;
      this.scrollResetToken++;
    }
    this.restorePage();
    this.scheduleSave();
  }

  private usesJoinedPages(): boolean { return this.mode === 1 && this.pageLayout === 2; }
  private usesContinuousPages(): boolean { return this.mode === 0 || this.usesJoinedPages(); }

  private async changePageLayout(layout: number): Promise<void> {
    if (this.settingsSaving || layout === this.pageLayout) return;
    this.settingsSaving = true;
    try {
      await PreferenceService.setComicPageLayout(layout);
      if (!this.alive) return;
      this.pageLayout = layout;
      this.applyMode(this.mode);
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    } finally { this.settingsSaving = false; }
  }

  private async changeDisplayMode(mode: number): Promise<void> {
    if (this.settingsSaving || mode === this.displayMode) return;
    this.settingsSaving = true;
    try {
      await PreferenceService.setComicDisplayMode(mode);
      if (!this.alive) return;
      this.displayMode = mode;
      this.autoPage.restart();
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    } finally { this.settingsSaving = false; }
  }

  private displayModeHint(): Resource {
    if (this.displayMode === 1) return $r('app.string.comic_display_width_hint');
    if (this.displayMode === 2) return $r('app.string.comic_display_screen_hint');
    if (this.displayMode === 3) return $r('app.string.comic_display_original_hint');
    return $r('app.string.comic_display_default_hint');
  }

  private async changeAppearance(value: ComicReaderAppearance): Promise<void> {
    if (this.settingsSaving) return;
    this.settingsSaving = true;
    try {
      await PreferenceService.setComicAppearance(value);
      if (!this.alive) return;
      this.appearance = value;
      this.syncBackgroundContrast();
      this.refreshSplitPages(true);
      if (this.usesContinuousPages()) {
        this.scrollInitialPages = this.activeChapterPages;
        this.scrollInitialFraction = this.pageFraction;
      }
      this.autoPage.restart();
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    } finally { this.settingsSaving = false; }
  }

  /** 分割只建立显示视图；缓存、下载与进度继续对应原图。 */
  private refreshSplitPages(force: boolean = false): void {
    if (this.busy || this.activeChapterPages.length === 0) return;
    const current = this.pages.getData(this.pageIndex);
    const views = ComicReaderService.splitViews(this.activeChapterPages,
      this.usesContinuousPages() ? 0 : this.appearance.split);
    if (!force && views.length === this.pages.totalCount()) return;
    this.pages.setPages(views);
    this.pageCount = views.length;
    const exact = current ? views.findIndex((item: ComicPage): boolean => item.key === current.key) : -1;
    const original = current ? views.findIndex((item: ComicPage): boolean => item.index === current.index) : 0;
    this.pageIndex = Math.max(0, exact >= 0 ? exact : original);
    this.restorePage();
  }

  private async setTrimWhiteBorder(enabled: boolean): Promise<void> {
    if (this.settingsSaving || enabled === this.trimWhiteBorder) return;
    this.settingsSaving = true;
    try {
      await PreferenceService.setComicTrimWhiteBorder(enabled);
      if (!this.alive) return;
      this.trimWhiteBorder = enabled;
      this.autoPage.restart();
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    } finally { this.settingsSaving = false; }
  }

  private async changePageOverlap(overlap: number): Promise<void> {
    if (this.settingsSaving || overlap === this.pageOverlap) return;
    this.settingsSaving = true;
    try {
      await PreferenceService.setComicPageOverlap(overlap);
      if (this.alive) this.pageOverlap = overlap;
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    } finally { this.settingsSaving = false; }
  }

  private currentPages(): ComicPage[] {
    return this.pageCount > 0 ? [this.pages.getData(this.pageIndex)] : [];
  }

  private async setSuperResolution(enabled: boolean): Promise<void> {
    if (this.savingSuperResolution || !ComicSuperResolutionService.supported()) return;
    if (enabled && !this.membership.hasAccess) return;
    const previous = this.superResolution;
    this.savingSuperResolution = true;
    this.superResolution = enabled;
    try {
      if (enabled && !await MembershipService.instance.hasCurrentEntitlement()) {
        this.superResolution = previous;
        if (!this.alive) return;
        this.getUIContext().getPromptAction().showToast({ message: MembershipService.instance.message });
        return;
      }
      if (!this.alive) return;
      await PreferenceService.setComicSuperResolution(enabled);
      if (this.alive) this.superResolution = enabled;
    } catch (_error) {
      this.superResolution = previous;
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    } finally {
      this.savingSuperResolution = false;
    }
  }

  private toggleAutoPage(): void {
    if (this.autoPageRunning) { this.pauseAutoPage(); return; }
    if (this.busy || this.failed || this.pageCount === 0 || this.zoomActive) return;
    this.autoPageRunning = true;
    this.autoPagePaused = false;
    this.showSettings = false;
    this.resetChapterSlider();
    this.chrome = false;
    WindowUtils.setReaderStatusBarVisible(false);
    this.screenOn.configure(-1);
    if (this.mode !== 0) this.autoPage.start(this.autoPageSeconds, (): void => {
      if (!this.canAutoPage() || this.restoreTimer >= 0 || this.turning) return;
      if (this.usesContinuousPages()) this.turnPage(1);
      else this.autoPageRequest++;
    });
    this.syncAutoPage();
  }

  private finishAutoPageImage(page: ComicPage): void {
    if (!this.canAutoPage() || page.key !== this.pages.getData(this.pageIndex).key) return;
    if (this.pageIndex === this.pageCount - 1 && !this.canChange(1)) this.stopAutoPage();
    else this.turnPage(1);
  }

  private autoPageImageReady(page: ComicPage, failed: boolean): void {
    if (this.pageCount === 0 || page.key !== this.pages.getData(this.pageIndex).key) return;
    if (failed) this.stopAutoPage();
    else this.autoPage.restart();
  }

  private pauseAutoPage(): void {
    if (!this.autoPageRunning) return;
    this.autoPage.stop();
    this.autoScrollReady = false;
    this.autoPageRunning = false;
    this.autoPagePaused = true;
    this.screenOn.configure(0);
  }

  private stopAutoPage(): void {
    this.autoPage.stop();
    this.autoScrollReady = false;
    if (!this.autoPageRunning && !this.autoPagePaused) return;
    this.autoPageRunning = false;
    this.autoPagePaused = false;
    this.screenOn.configure(0);
  }

  private setAutoPageInterval(seconds: number): void {
    this.autoPageSeconds = ReaderAutoPageService.normalizeSeconds(seconds);
    PreferenceService.setAutoPageSeconds(true, this.autoPageSeconds).catch((): void => {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    });
  }

  private canAutoPage(): boolean {
    return this.autoPageRunning && this.alive && this.foreground && this.readerVisible &&
      !this.busy && !this.failed && this.pageCount > 0 && !this.showSettings &&
      !this.showChapters && !this.showSourceSwitch && !this.sheetPresented && !this.zoomActive &&
      !this.showReaderMenu && !this.showTranslationMenu && !this.chapterSliderDragging && !this.chapterSliderCommitting;
  }

  private setAutoScrollSpeed(speed: number): void {
    this.autoScrollSpeed = speed;
    PreferenceService.setAutoScrollSpeed(true, speed).catch((): void => {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    });
  }

  @Monitor('readerVisible', 'foreground', 'busy', 'failed', 'chrome', 'showSettings', 'showChapters',
    'showSourceSwitch', 'sheetPresented', 'zoomActive', 'showReaderMenu', 'showTranslationMenu',
    'chapterSliderDragging', 'chapterSliderCommitting')
  private syncAutoPage(): void {
    if (!this.readerVisible || !this.foreground || this.failed || this.zoomActive) this.stopAutoPage();
    this.autoScrollReady = this.canAutoPage() && this.mode === 0;
    this.autoPage.setReady(this.canAutoPage() && this.mode !== 0);
  }

  private turnPage(direction: number): void {
    if (this.busy || this.failed || this.showChapters || this.showSettings || this.showSourceSwitch || this.turning || this.zoomActive) return;
    if (this.usesContinuousPages()) {
      this.keyTurnRequest = (Math.abs(this.keyTurnRequest) + 1) * (direction > 0 ? 1 : -1);
      return;
    }
    const target = this.pageIndex + direction;
    if (target < 0 || target >= this.pageCount) {
      this.turnToAdjacentChapter(direction);
      return;
    }
    if (this.mode === 1 || this.mode === 2) {
      this.swiper.changeIndex(target, true);
      return;
    }
    this.turning = true;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut,
      onFinish: () => { this.turning = false; } }, () => {
      this.pageIndex = target;
      this.pageFraction = 0;
    });
    this.scheduleSave();
    this.playPageTurnHaptic();
  }

  private playPageTurnHaptic(): void {
    if (!this.alive || !this.foreground || !this.readerVisible || this.autoPageRunning ||
      this.busy || this.failed || this.zoomActive || this.showChapters || this.showSettings || this.showSourceSwitch) return;
    ReaderHapticService.play(this.pageTurnHaptic);
  }

  private async turnToAdjacentChapter(direction: number): Promise<void> {
    if (!this.canChange(direction)) return;
    const automatic = this.autoPageRunning;
    const loaded = await this.loadChapter(this.adjacent(direction), direction < 0 ? Number.MAX_SAFE_INTEGER : 0);
    if (loaded && !automatic) this.playPageTurnHaptic();
  }

  private onSwiperPageChanged(index: number): void {
    if (this.busy || this.restoreTimer >= 0 || index < 0 || index >= this.pageCount || index === this.pageIndex) return;
    this.pageIndex = index;
    this.pageFraction = 0;
    this.scheduleSave();
    this.playPageTurnHaptic();
  }

  private canUseVolumeKeys(): boolean {
    return this.volumeKeyPageTurn && !this.chrome && this.canTurnWithHardwareKeys();
  }

  private canTurnWithHardwareKeys(): boolean {
    return this.alive && this.foreground && this.readerVisible &&
      !this.busy && !this.failed && this.pageCount > 0 && !this.showChapters && !this.showSettings &&
      !this.showSourceSwitch && !this.zoomActive && !this.sheetPresented && !this.chapterSliderDragging && !this.chapterSliderCommitting;
  }

  @Monitor('volumeKeyPageTurn', 'smartKeyPageTurn', 'readerVisible', 'chrome', 'busy', 'failed', 'pageCount', 'showChapters',
    'showSettings', 'showSourceSwitch', 'zoomActive', 'sheetPresented', 'chapterSliderDragging', 'chapterSliderCommitting')
  private syncVolumeKeys(): void {
    this.volumeKeys.setEnabled(this.canUseVolumeKeys(), (forward: boolean): void => this.handleVolumePageTurn(forward));
    this.smartKeys.setEnabled(this.smartKeyPageTurn && this.canTurnWithHardwareKeys(), (forward: boolean): void => {
      if (this.smartKeyPageTurn) this.handleHardwarePageTurn(forward);
    });
  }

  private handleVolumePageTurn(forward: boolean): void {
    if (this.canUseVolumeKeys()) this.handleHardwarePageTurn(forward);
  }

  private handleHardwarePageTurn(forward: boolean): void {
    if (!this.canTurnWithHardwareKeys() || this.turning || this.restoreTimer >= 0) return;
    this.autoPage.restart();
    if (this.usesContinuousPages()) {
      this.keyTurnRequest = (Math.abs(this.keyTurnRequest) + 1) * (forward ? 1 : -1);
    } else {
      this.turnPage(forward ? 1 : -1);
    }
  }

  private contentTouch(event: TouchEvent): void {
    this.touchTracker.update(event);
    if (event.type === TouchType.Down && event.touches.length === 1) this.touchConsumed = this.zoomActive;
    if (event.touches.length > 1 || this.zoomActive) this.touchConsumed = true;
    if (this.touchConsumed) { this.touchTracker.cancel(); return; }
    const touch = event.changedTouches[0];
    if (!touch || this.busy || this.restoreTimer >= 0) return;
    if (event.type === TouchType.Down) {
      this.touchStartedAt = Date.now();
      this.touchX = touch.windowX;
      this.touchY = touch.windowY;
      this.touchPageIndex = this.pageIndex;
      this.touchGeneration = this.generation;
    } else if (event.type === TouchType.Up) {
      const dx = touch.windowX - this.touchX;
      const dy = touch.windowY - this.touchY;
      if (this.mode !== 0 && this.touchTracker.canTap() && Date.now() - this.touchStartedAt < 300) {
        const action = ReaderTapPolicy.resolve(ReaderTapPolicy.DEFAULT, touch.windowX - this.leftSafe, touch.windowY,
          this.widthVp - this.leftSafe - this.rightSafe, this.heightVp, this.tapLeftPercent, this.tapRightPercent);
        if (action === 0 || action === 2) {
          const forward = this.mode === 2 ? action === 0 : action === 2;
          this.turnPage(forward ? 1 : -1);
        }
        return;
      }
      if (this.mode !== 0 && Math.abs(dx) > 48 && Math.abs(dx) > Math.abs(dy)) {
        const direction = (this.mode === 2 ? dx > 0 : dx < 0) ? 1 : -1;
        if (this.mode === 3 || this.usesJoinedPages()) this.turnPage(direction);
        else if (this.touchGeneration === this.generation &&
          (direction > 0 ? this.touchPageIndex === this.pageCount - 1 : this.touchPageIndex === 0) &&
          this.canChange(direction)) {
          this.turnToAdjacentChapter(direction);
        }
      }
    }
  }

  private async loadScrollPages(index: number, preload: boolean): Promise<ComicPage[]> {
    const book = this.book;
    if (!book || !this.alive || index < 0 || index >= book.chapters.length) return [];
    const prepared = this.preparedComicChapters.get(index);
    if (prepared !== undefined) return prepared;
    const ticket = this.generation;
    const pages = await ComicReaderService.load(book, book.chapters[index], this.getUIContext().getHostContext(), false, preload);
    if (this.alive && ticket === this.generation && Math.abs(index - this.chapterIndex) <= 3) {
      this.preparedComicChapters.set(index, pages);
      this.protectComicCache();
    }
    return pages;
  }

  private onScrollPosition(index: number, page: number, pages: ComicPage[], fraction: number = 0): void {
    if (this.busy || !this.usesContinuousPages() || !this.alive) return;
    if (index === this.chapterIndex && page === this.pageIndex && fraction === this.pageFraction) return;
    const changed = index !== this.chapterIndex;
    if (changed) {
      this.chapterIndex = index;
      this.activeChapterPages = pages;
      this.pages.setPages(pages);
      this.pageCount = pages.length;
      for (const key of this.preparedComicChapters.keys()) {
        if (Math.abs(key - index) > 3) this.preparedComicChapters.delete(key);
      }
      this.protectComicCache();
      if (this.book) this.preloadChapters(this.book, index, this.generation);
    }
    this.pageIndex = page;
    this.pageFraction = fraction;
    this.scheduleSave();
  }

  private imageWidth(): number {
    const available = Math.max(1, this.widthVp - this.leftSafe - this.rightSafe);
    return this.displayMode === 0 ? Math.max(1, available -
      2 * AdaptiveLayout.readerGutter(this.widthVp, this.leftSafe, this.rightSafe)) : available;
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.translation && this.foreground && this.readerVisible) {
        ComicOfflineTranslationHost()
      }
      if ((this.systemDark ? this.appearance.darkBackground : this.appearance.lightBackground) === 2) {
        Column().width('100%').height('100%')
          .backgroundImage($r('app.media.comic_kraft_texture'), ImageRepeat.XY)
          .backgroundImageSize({ width: 128, height: 128 }).hitTestBehavior(HitTestMode.None)
      }
      Column() {
        if (this.busy && this.pageCount === 0) {
          Column({ space: 16 }) {
            LoadingProgress().width(36).height(36).color(AppColor.Brand)
            Text($r('app.string.comic_loading')).fontColor(this.canvasInk)
            Text($r('app.string.comic_loading_elapsed', this.loadingSeconds)).fontColor(this.canvasInk).fontSize(12)
          }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
        } else if (this.failed) {
          Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.book')).fontSize(48).fontColor(['#888888'])
            Text($r('app.string.comic_empty')).fontColor(this.canvasInk).fontSize(17)
            Text($r('app.string.comic_empty_hint')).fontColor(this.canvasInk).fontSize(13).textAlign(TextAlign.Center)
            Button($r('app.string.comic_retry')).backgroundColor(AppColor.Brand)
              .onClick(() => { if (this.book) this.loadChapter(this.chapterIndex, this.pageIndex); else this.initialize(); })
          }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center).padding(32)
        } else if (this.usesContinuousPages()) {
          ComicContinuousComponent({ book: this.book ?? null, resetToken: this.scrollResetToken,
            autoPageRunning: this.autoPageRunning,
            autoScrollReady: this.autoScrollReady, autoScrollSpeed: this.autoScrollSpeed,
            onForwardEnd: (): void => this.stopAutoPage(),
            onAutoPageDelay: (): void => this.autoPage.restart(),
            onTurnFeedback: (): void => this.playPageTurnHaptic(),
            keyTurnRequest: this.keyTurnRequest, paged: this.usesJoinedPages(), overlap: this.pageOverlap,
            initialFraction: this.scrollInitialFraction,
            initialChapterIndex: this.chapterIndex, initialPageIndex: this.pageIndex,
            initialPages: this.scrollInitialPages, pageWidth: this.imageWidth(), displayMode: this.displayMode,
            superResolution: this.superResolution, trimWhiteBorder: this.trimWhiteBorder, appearance: this.appearance,
            placeholderColor: this.canvasInk,
            pageHeight: this.heightVp, viewportTop: this.viewportTop, zoomOwner: this.zoomOwner,
            colorization: this.colorization, translation: this.translation, translationDirection: this.translationDirection,
            colorizationActive: this.foreground && this.readerVisible && !this.showSettings && !this.showChapters,
            onColorError: (message: string): void => this.colorizationFailed(message),
            onZoomChange: (owner: string, active: boolean): void => this.onZoomChanged(owner, active),
            onToggle: (event: ClickEvent): void => this.onContentTap(event),
            loadPages: (index: number, preload: boolean): Promise<ComicPage[]> => this.loadScrollPages(index, preload),
            onPosition: (index: number, page: number, pages: ComicPage[], fraction: number): void => this.onScrollPosition(index, page, pages, fraction)
          }).width('100%').layoutWeight(1)
        } else if (this.mode === 3) {
          Stack() {
            ForEach(this.currentPages(), (page: ComicPage) => {
              Column() {
                ComicPageImage({ onGeometryReady: (): void => this.refreshSplitPages(), page: page, superResolution: this.superResolution,
                  autoPageRequest: this.autoPageRequest, autoPageActive: this.autoPageRunning,
                  onAutoPageEnd: (): void => this.finishAutoPageImage(page),
                  onAutoPageFailure: (): void => this.autoPageImageReady(page, true),
                  onAutoPageDelay: (): void => this.autoPageImageReady(page, false),
                  colorization: this.colorization, translation: this.translation, translationDirection: this.translationDirection,
                  colorizationActive: this.foreground && this.readerVisible && !this.showSettings && !this.showChapters,
                  onColorError: (message: string): void => this.colorizationFailed(message),
                  onZoomChange: (owner: string, active: boolean): void => this.onZoomChanged(owner, active),
                  pageWidth: this.imageWidth(), pageHeight: this.heightVp, paged: true, fitScreen: this.pageLayout !== 0,
                  displayMode: this.displayMode, trimWhiteBorder: this.trimWhiteBorder, appearance: this.appearance,
                  placeholderColor: this.canvasInk,
                  viewportTop: this.viewportTop, zoomOwner: this.zoomOwner,
                  onToggle: (event: ClickEvent): void => { this.onContentTap(event); } })
              }.width('100%').height('100%').transition(TransitionEffect.OPACITY)
            }, (page: ComicPage): string => page.key)
          }.width('100%').layoutWeight(1).clip(true)
        } else {
          Swiper(this.swiper) {
            LazyForEach(this.pages, (page: ComicPage) => {
              Column() {
                ComicPageImage({ onGeometryReady: (): void => this.refreshSplitPages(), page: page, superResolution: this.superResolution, pageWidth: this.imageWidth(), pageHeight: this.heightVp,
                   autoPageRequest: this.autoPageRequest,
                   autoPageActive: this.autoPageRunning && page.key === this.pages.getData(this.pageIndex).key,
                   onAutoPageEnd: (): void => this.finishAutoPageImage(page),
                   onAutoPageFailure: (): void => this.autoPageImageReady(page, true),
                   onAutoPageDelay: (): void => this.autoPageImageReady(page, false),
                   colorization: this.colorization, translation: this.translation, translationDirection: this.translationDirection,
                   colorizationActive: this.foreground && this.readerVisible && !this.showSettings && !this.showChapters,
                   onColorError: (message: string): void => this.colorizationFailed(message),
                   onZoomChange: (owner: string, active: boolean): void => this.onZoomChanged(owner, active),
                     paged: true, fitScreen: this.pageLayout !== 0, displayMode: this.displayMode, trimWhiteBorder: this.trimWhiteBorder, appearance: this.appearance,
                     placeholderColor: this.canvasInk,
                    viewportTop: this.viewportTop, zoomOwner: this.zoomOwner,
                   onToggle: (event: ClickEvent): void => { this.onContentTap(event); } })
              }.width('100%').height('100%').justifyContent(FlexAlign.Center)
            }, (page: ComicPage): string => page.key)
           }.width('100%').layoutWeight(1).index(this.pageIndex).loop(false).indicator(false).cachedCount(2)
           .duration(260).curve(Curve.EaseOut)
            .disableSwipe(this.zoomActive)
           .onAnimationStart((): void => { this.turning = true; })
            .onAnimationEnd((): void => { this.turning = false; this.autoPage.restart(); })
          .direction(this.mode === 2 ? Direction.Rtl : Direction.Ltr)
          .onChange((index: number): void => this.onSwiperPageChanged(index))
        }
      }.width('100%').height('100%')
      .padding({ left: this.leftSafe, right: this.rightSafe })
      // 弹框动画仅采样一个视口大小的正文层；关闭后释放缓存，正常滚动不缓存长列表。
      .clip(true)
      .renderGroup(this.usesContinuousPages() && this.sheetPresented && !this.busy)
      .onClick((event: ClickEvent) => this.onContentTap(event))
      .onTouch((event: TouchEvent) => this.contentTouch(event))
      if (this.showChapters || this.showSettings) {
        Row().width('100%').height('100%').backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Block)
          .onClick((): void => this.onReaderPanelVisibilityChange(false))
      }
      if (this.busy && this.pageCount > 0) {
        Column({ space: 6 }) {
          LoadingProgress().width(36).height(36).color(AppColor.Brand)
          Text($r('app.string.comic_loading_elapsed', this.loadingSeconds)).fontColor(Color.White).fontSize(12)
        }.padding(12).borderRadius(12).backgroundColor('#AA121212')
          .margin({ top: this.topSafe + 60 }).hitTestBehavior(HitTestMode.None)
      }
      if (this.chrome) {
        Row({ space: 8 }) {
          ImmersiveCircleButton({ icon: $r('sys.symbol.chevron_left'), label: $r('app.string.comic_back'),
            onPress: (): void => { this.savePosition(); this.navStack.pop(); } })
          Blank()
          ImmersiveCircleButton({ icon: $r('sys.symbol.arrow_clockwise'), label: $r('app.string.content_reload'),
            onPress: (): void => { this.loadChapter(this.chapterIndex, this.pageIndex, true); } }).enabled(!this.busy)
          Stack({ alignContent: Alignment.Bottom }) {
            ImmersiveCircleButton({ icon: $r('sys.symbol.translate'), label: $r('app.string.comic_ai_translate'),
              iconColor: this.translation && this.membership.hasAccess ? AppColor.Brand : $r('sys.color.font_primary'),
              onPress: (): void => { this.showTranslationMenu = !this.showTranslationMenu; } }).id('comic-translation-toggle')
              .bindMenu(this.showTranslationMenu, this.translationMenu(), this.translationMenuOptions())
            if (this.translationDownloading) {
              Text(`${this.translationDownloadPercent}%`).fontSize(10).fontColor(AppColor.Brand)
                .backgroundColor($r('sys.color.comp_background_primary')).borderRadius(4)
                .hitTestBehavior(HitTestMode.None)
            }
          }
          ImmersiveCircleButton({ icon: $r('sys.symbol.paintpalette'), label: $r('app.string.comic_ai_color'),
            iconColor: this.colorization && this.membership.hasAccess ? AppColor.Brand : $r('sys.color.font_primary'),
            onPress: (): void => { this.setColorization(!this.colorization); } })
            .id('comic-colorization-toggle').enabled(ComicColorizationService.supported())
          ImmersiveCircleButton({ icon: $r('sys.symbol.square_grid_2x2'), label: $r('app.string.reader_more'),
            onPress: (): void => { this.showReaderMenu = !this.showReaderMenu; } })
            .id('comic-reader-functions')
            .bindMenu(this.showReaderMenu, this.readerMenu(), this.readerMenuOptions())
        }.width('100%').padding({ left: 16 + this.leftSafe, right: 16 + this.rightSafe })
        .margin({ top: this.topSafe + 4 }).hitTestBehavior(HitTestMode.Transparent)
      }
      // Each sheet needs its own stable host; repeated bindSheet on one node overrides earlier bindings.
      Column().width(0).height(0).hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.showSourceSwitch, this.sourceSwitchSheet(), { height: '82%', detents: ['82%', '45%', SheetSize.LARGE], dragBar: true, preferType: SheetType.BOTTOM,
          showClose: true, backgroundColor: AppMaterial.SheetBackground,
          blurStyle: AppMaterial.ReaderSheetBlur, systemMaterial: AppMaterial.ReaderSheetThick,
          onWillAppear: (): void => { this.sheetPresented = true; },
          onDisappear: (): void => { this.sheetPresented = false; } })
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (!this.chrome && this.pageCount > 0) {
        Text(this.usesJoinedPages() ? $r('app.string.comic_joined_position', this.chapterAtOrdinal(this.chapterIndex) + 1,
          this.book?.chapters.length ?? 0, this.pageIndex + 1, this.pageCount) :
          $r('app.string.comic_chapter_position', this.chapterAtOrdinal(this.chapterIndex) + 1,
            this.book?.chapters.length ?? 0, this.pageIndex + 1, this.pageCount))
          .fontColor('#DDFFFFFF').fontSize(11).padding(8).backgroundColor('#88121212').borderRadius(12)
          .margin({ right: 16 + this.rightSafe, bottom: Math.max(12, this.bottomSafe) })
        }
        this.bottomBar()
      }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
      if (this.showBrightnessBar && this.chrome) {
        ReaderBrightnessBar({ value: this.readingBrightness, barHeight: this.brightnessBarHeight(),
          onChange: (value: number, commit: boolean): void => { this.changeBrightness(value, commit); } })
          .position({ x: this.holdingHandLeft ? this.leftSafe + 12 : Math.max(this.leftSafe + 12, this.widthVp - this.rightSafe - 60),
            y: Math.max(this.topSafe + 48, this.topSafe + 48 +
              (this.heightVp - this.topSafe - 48 - this.bottomSafe - 140 - this.brightnessBarHeight()) / 2) })
          .id('comic-brightness-bar')
          // 与底栏一致，弹框期间停止被遮挡亮度条的实时材质采样；保留节点及亮度状态。
          .visibility(this.sheetPresented ? Visibility.Hidden : Visibility.Visible)
      }
      if (this.autoPageRunning || this.autoPagePaused) {
        // 控件独立命中，正文不参与暂停、继续和关闭按钮的手势竞争。
        ReaderAutoPageControls({
          paused: this.autoPagePaused, scrolling: this.mode === 0,
          onToggle: (): void => this.toggleAutoPage(),
          onClose: (): void => this.stopAutoPage()
        })
          .position({ x: this.holdingHandLeft ? this.leftSafe + 16 :
            Math.max(this.leftSafe + 16, this.widthVp - this.rightSafe - 16 - 136),
            y: Math.max(this.topSafe, this.heightVp - 40 - Math.max(12, this.bottomSafe) -
              (this.chrome ? 76 + (this.showChapterBar && this.pageCount > 0 ? 56 : 0) + (this.saveFailed ? 20 : 0) :
                (this.holdingHandLeft ? 0 : 40))) })
          .hitTestBehavior(HitTestMode.Default)
          .id('comic-auto-page-controls')
      }
      ReaderSettingsPopup({ visible: this.showChapters || this.showSettings,
        viewportWidth: this.widthVp, viewportHeight: this.heightVp,
        topInset: this.topSafe, leftInset: this.leftSafe, rightInset: this.rightSafe,
        anchorBottom: this.settingsAnchorBottom(),
        preferredHeight: this.showChapters ? 760 : 520, maxHeightRatio: this.showChapters ? 0.84 : 0.64,
        onVisibilityChange: (visible: boolean): void => this.onReaderPanelVisibilityChange(visible) }) {
        if (this.showChapters) {
          this.chapterSheet()
        } else {
          this.settingsSheet()
        }
      }
    }.width('100%').height('100%').backgroundColor(this.canvasColor)
    .onVisibleAreaChange([0, 1], (visible: boolean): void => {
      this.readerVisible = visible;
      if (!visible) this.stopAutoPage();
      this.screenOn.setVisible(visible);
      this.syncVolumeKeys();
      this.brightnessControl.setVisible(visible);
      this.syncHoldingHand();
    })
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .onAreaChange((_old, area) => {
      this.viewportTop = Number(area.globalPosition.y);
      const width = Number(area.width);
      const height = Number(area.height);
      if (width === this.widthVp && height === this.heightVp) return;
      this.widthVp = width; this.heightVp = height;
      if (!this.busy) this.restorePage();
    })

  }

  private readerMenuOptions(): MenuOptions {
    const options: MenuOptions = {
      placement: Placement.BottomLeft,
      backgroundColor: AppMaterial.SheetBackground,
      onDisappear: (): void => { this.showReaderMenu = false; }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    else options.backgroundBlurStyle = AppMaterial.SheetBlur;
    return options;
  }

  @Builder
  private readerMenu(): void {
    Menu() {
      MenuItem({ content: $r('app.string.source_switch_title') })
        .enabled(!this.busy && this.book !== undefined)
        .onClick((): void => { this.showReaderMenu = false; this.showSourceSwitch = true; })
      if (this.book?.id.startsWith('import_') && !this.book?.sourceUrl) {
        MenuItem({ content: $r('app.string.comic_switch_text') })
          .enabled(!this.busy && !this.switchingText)
          .onClick((): void => { this.showReaderMenu = false; this.switchToText(); })
      }
      MenuItem({ content: $r('app.string.reader_details') })
        .enabled(this.book !== undefined && !this.switchingText)
        .onClick((): void => { this.showReaderMenu = false; this.openDetails(); })
    }
  }

  private async switchToText(): Promise<void> {
    const book = this.book;
    if (!book || this.busy || this.switchingText) return;
    this.switchingText = true;
    let typeSaved = false;
    try {
      this.savePosition();
      await this.saveChain;
      if (!this.alive) return;
      const changed = await DataService.switchImportedBookToText(book.id);
      typeSaved = true;
      changed.chapters = book.chapters;
      SearchCache.put(changed);
      if (!this.alive) return;
      this.navStack.replacePath({ name: 'reader', param: TextReaderRouteParams.of(book.id) }, false);
    } catch (error) {
      hilog.error(0x0001, 'ComicReader', 'text switch failed: %{public}s',
        error instanceof Error ? error.message : String(error));
      if (this.alive) this.getUIContext().getPromptAction().showToast({
        message: typeSaved ? $r('app.string.comic_switch_text_open_failed') : $r('app.string.reader_switch_comic_failed')
      });
    } finally { this.switchingText = false; }
  }

  private openDetails(): void {
    if (!this.book) return;
    this.savePosition();
    SearchCache.put(this.book);
    this.navStack.pushPathByName('detail', this.book.id);
  }

  private async switchSource(book: Book, index: number, matched: boolean, oldFavoriteId: string, replace: boolean): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.alive || !this.showSourceSwitch || !book.chapters[index]) return;
    const pages = await ComicReaderService.load(book, book.chapters[index], context);
    if (pages.length === 0) throw new Error(context.resourceManager.getStringSync($r('app.string.source_switch_empty_content').id));
    if (!this.alive || !this.showSourceSwitch) return;
    this.savePosition();
    const mode = this.mode === 0 ? 'comic:scroll' : this.mode === 1 ? 'comic:paged' : this.mode === 2 ? 'comic:rtl' : 'comic:dissolve';
    const position = TextReadingPosition.of(book.id, index, mode,
      matched ? Math.min(this.pageIndex, pages.length - 1) : 0, book.chapters[index].title);
    await DataService.upsertCachedBook(book);
    await TextReadingProgressService.save(context, position);
    if (!this.alive || !this.showSourceSwitch) return;
    SearchCache.put(book);
    if (oldFavoriteId) await PreferenceService.replaceFavoriteSource(oldFavoriteId, book.id, replace);
    this.showSourceSwitch = false;
    this.navStack.replacePath({ name: 'comicReader', param: TextReaderRouteParams.of(book.id) }, false);
  }

  @Builder
  sourceSwitchSheet() {
    BookSourceSwitchSheet({ book: this.book ?? null, chapterTitle: this.book?.chapters[this.chapterIndex]?.title ?? '',
      chapterIndex: this.chapterIndex,
      onSelect: async (book: Book, index: number, matched: boolean, oldFavoriteId: string, replace: boolean): Promise<void> => {
        await this.switchSource(book, index, matched, oldFavoriteId, replace);
      } })
  }

  private bottomControlsWidth(): number {
    return Math.max(1, this.widthVp - 2 * (16 + Math.max(this.leftSafe, this.rightSafe)));
  }

  private settingsAnchorBottom(): number {
    if (this.showChapterBar && this.pageCount > 0) return 76 + this.bottomSafe + 44 + (this.saveFailed ? 20 : 0);
    return PlatformCompat.floatingTabs ? 60 + Math.max(this.bottomSafe, 8) + 4 : 60 + this.bottomSafe;
  }

  private floatingStyle(): HdsTabsFloatingStyle | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    const width = this.bottomControlsWidth();
    return {
      barWidth: { smallWidth: width, mediumWidth: width, largeWidth: width },
      barSideMargin: 0,
      barBottomMargin: Math.max(this.bottomSafe, 8) + 4,
      gradientMask: { maskColor: Color.Transparent, maskHeight: 0 },
      systemMaterialEffect: HdsCompat.adaptiveMaterial,
      lightColor: AppColor.Brand,
      adaptToHandedness: this.generalSettings.adaptiveHandedness
    };
  }

  private tabClick(index: number): void {
    this.resetChapterSlider();
    if (index === 0 && this.canChange(-1)) this.loadChapter(this.adjacent(-1));
    else if (index === 1) this.openChapterSheet();
    else if (index === 2) {
      this.showChapters = false;
      this.chapterPositionGeneration++;
      this.showSettings = true;
    }
    else if (index === 3 && this.canChange(1)) this.loadChapter(this.adjacent(1));
  }

  @Builder
  tabStyle(icon: Resource, label: Resource, index: number, direction: number = 0) {
    Column() {
      SymbolGlyph(icon).fontSize(22).fontColor([
        (index === 1 && this.showChapters) || (index === 2 && this.showSettings) ? AppColor.Brand : $r('sys.color.font_primary')])
    }.width('100%').height(48).justifyContent(FlexAlign.Center)
    .opacity(direction === 0 || this.canChange(direction) ? 1 : 0.35)
    .accessibilityText(label)
    .id(`comic-panel-tab-${index}`)
    .onClick(() => { this.tabClick(index); })
  }

  private chapterOrdinal(): number {
    if (this.chapterPreview >= 0) return this.chapterPreview;
    return this.book?.chaptersDescending ? this.book.chapters.length - 1 - this.chapterIndex : this.chapterIndex;
  }

  private chapterAtOrdinal(ordinal: number): number {
    return this.book?.chaptersDescending ? this.book.chapters.length - 1 - ordinal : ordinal;
  }

  private resetChapterSlider(): void {
    this.chapterSliderGeneration++;
    this.chapterPreview = -1;
    this.chapterSliderDragging = false;
    this.chapterSliderUndoPosition = null;
  }

  private chapterSliderPercent(): string {
    const count = this.book?.chapters.length ?? 0;
    const index = this.chapterAtOrdinal(this.chapterOrdinal());
    return count > 0 ? `${((index + 1) * 100 / count).toFixed(2)}%` : '0.00%';
  }

  private chapterJumpHintVisible(): boolean {
    return (this.chapterSliderDragging || this.chapterSliderUndoPosition !== null) &&
      !this.showChapters && !this.showSettings && !this.showSourceSwitch;
  }

  private async changeChapterSlider(value: number, mode: SliderChangeMode): Promise<void> {
    const book = this.book;
    if (!book || book.chapters.length < 2 || !Number.isFinite(value) || !this.alive || !this.readerVisible ||
      !this.chrome || this.busy || this.chapterSliderCommitting) return;
    this.chapterPreview = Math.max(0, Math.min(Math.round(value), book.chapters.length - 1));
    this.chapterSliderDragging = mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving;
    if (mode !== SliderChangeMode.End && mode !== SliderChangeMode.Click) return;
    const target = this.chapterAtOrdinal(this.chapterPreview);
    if (target === this.chapterIndex) { this.chapterPreview = -1; return; }
    const previousUndo = this.chapterSliderUndoPosition;
    if (previousUndo === null) {
      const position = new ComicChapterJumpPosition();
      position.bookId = book.id;
      position.chapterIndex = this.chapterIndex;
      position.pageIndex = this.pageIndex;
      position.fraction = this.pageFraction;
      this.chapterSliderUndoPosition = position;
    }
    const generation = this.chapterSliderGeneration;
    this.chapterSliderCommitting = true;
    try {
      const loaded = await this.loadChapter(target, 0, false, 0, true);
      if (!loaded && generation === this.chapterSliderGeneration) this.chapterSliderUndoPosition = previousUndo;
    } finally {
      this.chapterPreview = -1;
      this.chapterSliderDragging = false;
      this.chapterSliderCommitting = false;
    }
  }

  private async undoChapterSlider(): Promise<void> {
    const position = this.chapterSliderUndoPosition;
    if (position === null || position.bookId !== this.book?.id || !this.alive || !this.readerVisible ||
      !this.chrome || this.busy || this.chapterSliderDragging || this.chapterSliderCommitting) return;
    const generation = this.chapterSliderGeneration;
    this.chapterSliderCommitting = true;
    try {
      const loaded = await this.loadChapter(position.chapterIndex, position.pageIndex, false, position.fraction, true);
      if (loaded && generation === this.chapterSliderGeneration) this.resetChapterSlider();
    } finally { this.chapterSliderCommitting = false; }
  }

  @Builder
  chapterArrow(direction: number, icon: Resource) {
    Row() {
      SymbolGlyph(icon).fontSize(20).fontColor([$r('sys.color.font_primary')])
    }.width(44).height(44).justifyContent(FlexAlign.Center)
      .enabled(this.canChange(direction) && !this.chapterSliderCommitting)
      .opacity(this.canChange(direction) ? 1 : 0.35)
      .onClick(() => { this.chapterPreview = -1; this.loadChapter(this.adjacent(direction)); })
  }

  private chapterFloatingStyle(): HdsTabsFloatingStyle | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    const width = this.bottomControlsWidth();
    return {
      barWidth: { smallWidth: width, mediumWidth: width, largeWidth: width },
      barSideMargin: 0, barBottomMargin: 0,
      gradientMask: { maskColor: Color.Transparent, maskHeight: 44 },
      systemMaterialEffect: HdsCompat.material,
      adaptToHandedness: false
    };
  }

  @Builder
  chapterMaterialContent() {
    Row().width('100%').height(44)
  }

  @Builder
  chapterBarContent() {
        Row() {
          this.chapterArrow(-1, $r('sys.symbol.chevron_left'))
            Slider({ value: this.chapterOrdinal(), min: 0, max: Math.max(1, (this.book?.chapters.length ?? 0) - 1),
              step: 1, style: SliderStyle.OutSet })
              .attributeModifier(new SliderGestureModifier(0, Math.max(1, (this.book?.chapters.length ?? 0) - 1)))
              .layoutWeight(1).height(44).trackThickness(6).blockSize({ width: 16, height: 16 }).selectedColor(AppColor.Brand).showSteps(false)
              .accessibilityText($r('app.string.comic_chapters'))
               .enabled((this.book?.chapters.length ?? 0) > 1 && !this.busy && !this.chapterSliderCommitting)
              .onChange((value: number, mode: SliderChangeMode) => {
                 this.changeChapterSlider(value, mode);
               })
               .onTouch((event: TouchEvent): void => {
                 if (event.type === TouchType.Cancel && !this.chapterSliderCommitting) {
                   this.chapterPreview = -1;
                   this.chapterSliderDragging = false;
                }
              })
          this.chapterArrow(1, $r('sys.symbol.chevron_right'))
        }.width(this.bottomControlsWidth()).height(44).borderRadius(22)

  }

  @Builder
  bottomBar() {
    Stack({ alignContent: Alignment.Bottom }) {
      HdsTabs() {
        TabContent() {}.tabBar(this.tabStyle($r('sys.symbol.backward_end_fill'), $r('app.string.comic_previous'), 0, -1))
        TabContent() {}.tabBar(this.tabStyle($r('sys.symbol.list_bullet'), $r('app.string.comic_chapters'), 1))
        TabContent() {}.tabBar(this.tabStyle($r('sys.symbol.gearshape'), $r('app.string.reader_settings'), 2))
        TabContent() {}.tabBar(this.tabStyle($r('sys.symbol.forward_end_fill'), $r('app.string.comic_next'), 3, 1))
      }.width(this.bottomControlsWidth()).height(120 + this.bottomSafe)
      .barOverlap(true).barHeight(60).barMode(BarMode.Fixed).barPosition(BarPosition.End).scrollable(false)
      .attributeModifier(new CompatibleTabsModifier(this.floatingStyle(), 60 + this.bottomSafe))
      .onContentWillChange((): boolean => false)
      Column() {
        if (this.saveFailed) { Text($r('app.string.comic_save_failed')).fontColor('#FFD080').fontSize(12) }
        if (this.showChapterBar && this.pageCount > 0) {
        Column({ space: 8 }) {
          if (this.chapterJumpHintVisible()) {
            ReaderChapterJumpHint({ availableWidth: this.bottomControlsWidth(), idPrefix: 'comic',
              chapterTitle: this.book?.chapters[this.chapterAtOrdinal(this.chapterOrdinal())]?.title ?? '',
              percent: this.chapterSliderPercent(),
              undoEnabled: this.chapterSliderUndoPosition !== null && !this.chapterSliderDragging && !this.chapterSliderCommitting,
              onUndo: (): void => { this.undoChapterSlider(); } })
          }
        Stack({ alignContent: Alignment.Center }) {
        if (HdsCompat.materialSupported) {
          HdsTabs() {
            TabContent() {}.tabBar(this.chapterMaterialContent())
          }.width('100%').height(44).barPosition(BarPosition.End).barMode(BarMode.Fixed)
            .barHeight(44).barOverlap(true).scrollable(false)
            .attributeModifier(new CompatibleTabsModifier(this.chapterFloatingStyle(), 44))
            .backgroundColor(Color.Transparent).borderRadius(22, RenderStrategy.OFFSCREEN).clip(true)
            .onContentWillChange((): boolean => false).hitTestBehavior(HitTestMode.None)
        } else {
          Row() {}.width('100%').height(44).borderRadius(22)
            .backgroundColor($r('sys.color.comp_background_tertiary')).backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
        }
        this.chapterBarContent()
        }.width(this.bottomControlsWidth()).height(44)
        }.width(this.bottomControlsWidth())
        }
      }.width('100%').alignItems(HorizontalAlign.Center)
        .margin({ bottom: 76 + this.bottomSafe })
    }.width('100%').height(160 + this.bottomSafe + (this.chapterJumpHintVisible() ? 64 : 0))
    .animation(null).translate({ y: this.chrome ? 0 : 24 }).opacity(this.chrome ? 1 : 0)
    .animation({ duration: 180, curve: Curve.EaseOut })
    // 正文在 Touch Up 处理两侧翻页，工具栏必须阻止触摸透传，否则会先翻下一页并清除撤销记录。
    .hitTestBehavior(this.chrome ? HitTestMode.BLOCK_HIERARCHY : HitTestMode.None)
    .animation(null)
    // Keep both covered live-material bars out of the entire sheet transition, including dismissal.
    .visibility(this.chrome && !this.sheetPresented ? Visibility.Visible : Visibility.Hidden)
    .enabled(this.chrome)
  }

  private openChapterSheet(): void {
    this.resetChapterSlider();
    if (this.showChapters) return;
    if (!this.book || this.book.chapters.length === 0) return;
    this.chapterDescending = this.book.chaptersDescending ?? false;
    this.chapterQuery = '';
    this.chapterListOffsetFromCurrent = 0;
    this.chapters.setChapters(PreferenceService.orderedChapters(this.book));
    this.showSettings = false;
    this.showChapters = true;
    this.scrollChapterListToCurrent();
  }

  private onReaderPanelVisibilityChange(visible: boolean): void {
    if (visible) {
      if (this.showChapters) this.scrollChapterListToCurrent();
      return;
    }
    this.showSettings = false;
    this.closeChapterSheet();
  }

  private closeChapterSheet(): void {
    this.chapterPositionGeneration++;
    this.showChapters = false;
  }

  private isCurrentChapter(chapter: Chapter): boolean {
    return chapter.id === this.book?.chapters[this.chapterIndex]?.id;
  }

  private chapterStableKey(chapter: Chapter): string {
    return chapter.id + ':' + (chapter.originSourceValue || chapter.source.value);
  }

  private selectChapter(chapter: Chapter): void {
    const index = this.book?.chapters.findIndex((item: Chapter): boolean => item.id === chapter.id) ?? -1;
    if (index < 0) return;
    this.closeChapterSheet();
    if (index !== this.chapterIndex || this.failed || this.pageCount === 0) this.loadChapter(index);
  }

  private filterReaderChapters(query: string): void {
    this.chapterPositionGeneration++;
    this.chapterQuery = query;
    const keyword = query.trim().toLowerCase();
    const ordered = this.book ? PreferenceService.orderedChapters(this.book) : [];
    this.chapters.setChapters(ordered.filter((chapter: Chapter): boolean => chapter.title.toLowerCase().includes(keyword)));
    if (!this.chapterSegmented && this.chapters.totalCount() > 0) this.chapterListScroller.scrollToIndex(0, false);
  }

  private toggleChapterOrder(): void {
    const book = this.book;
    if (!book) return;
    book.chaptersDescending = !book.chaptersDescending;
    this.chapterDescending = book.chaptersDescending;
    PreferenceService.saveTocOrder(book.id, book.chaptersDescending).catch((): void => {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.chapter_order_save_failed') });
    });
    this.filterReaderChapters(this.chapterQuery);
    this.chapterTopRequest++;
  }

  private scrollChapterListToCurrent(): void {
    if (!this.book || this.chapterSegmented) return;
    if (this.chapterQuery.length > 0) this.filterReaderChapters('');
    const index = PreferenceService.chapterDisplayIndex(this.book, this.chapterIndex);
    const generation = ++this.chapterPositionGeneration;
    setTimeout((): void => {
      if (!this.alive || !this.showChapters || this.chapterSegmented || generation !== this.chapterPositionGeneration) return;
      try { this.chapterListScroller.scrollToIndex(index, false, ScrollAlign.CENTER); } catch (_error) { }
    }, 60);
  }

  private jumpToCurrentChapter(): void {
    this.chapterListOffsetFromCurrent = 0;
    this.scrollChapterListToCurrent();
  }

  private shouldShowChapterJumpButton(): boolean {
    return !this.chapterSegmented && this.chapterQuery.trim().length === 0 && Math.abs(this.chapterListOffsetFromCurrent) > 200;
  }

  @Builder
  chapterSheet(): void {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: AppSpace.Xs }) {
      Row() {
        Text($r('app.string.comic_chapters'))
          .fontSize(18)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
        Blank()
        Button($r('app.string.chapter_total_switch_text', this.book?.chapters.length ?? 0))
          .fontSize(AppFont.Caption).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.chapterSegmented = !this.chapterSegmented;
            this.chapterListOffsetFromCurrent = 0;
            if (!this.chapterSegmented && this.chapterQuery.length === 0) this.scrollChapterListToCurrent();
          })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([$r('sys.color.font_secondary')])
        }.width(36).height(36).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.common_close')).id('comic-chapters-close')
          .onClick((): void => this.closeChapterSheet())
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: 4 })

      ChapterSheetActions({
        descending: this.chapterDescending,
        onOrder: (): void => this.toggleChapterOrder(),
        onTop: (): void => {
          this.chapterTopRequest++;
          this.chapterPositionGeneration++;
          if (!this.chapterSegmented && this.chapters.totalCount() > 0) this.chapterListScroller.scrollToIndex(0, false, ScrollAlign.START);
        },
        onBottom: (): void => {
          this.chapterBottomRequest++;
          this.chapterPositionGeneration++;
          if (!this.chapterSegmented && this.chapters.totalCount() > 0) this.chapterListScroller.scrollToIndex(this.chapters.totalCount() - 1, false, ScrollAlign.END);
        }
      })

      Search({ value: this.chapterQuery, placeholder: $r('app.string.reader_search_chapters') })
        .onChange((query: string): void => this.filterReaderChapters(query))
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .searchIcon({ size: 18, color: $r('sys.color.font_secondary') })
        .height(40)
        .borderRadius(AppRadius.Lg)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .margin({ left: AppSpace.Lg, right: AppSpace.Lg, top: 0, bottom: 0 })
      if (this.chapterSegmented) {
        ChapterSegmentGrid({
          highlightCurrent: true,
          book: this.book ?? null, topRequest: this.chapterTopRequest, bottomRequest: this.chapterBottomRequest,
          chapters: this.book?.chapters ?? [],
          currentId: this.book?.chapters[this.chapterIndex]?.id ?? '',
          keyword: this.chapterQuery,
          descending: this.chapterDescending,
          onSelect: (chapter: Chapter): void => { this.selectChapter(chapter); }
        }).layoutWeight(1)
      } else {
      if (this.chapters.totalCount() === 0) {
        Text($r('app.string.reader_no_matching_chapters'))
          .fontColor($r('sys.color.font_secondary'))
          .padding(AppSpace.Md)
      }
      List({ space: 0, scroller: this.chapterListScroller }) {
        LazyForEach(this.chapters, (chapter: Chapter) => {
          ListItem() {
            Row({ space: AppSpace.Sm }) {
              Column({ space: AppSpace.Xxs }) {
                Text(chapter.title)
                  .fontSize(AppFont.BodyL)
                  .fontColor(this.isCurrentChapter(chapter) ? AppColor.Brand : $r('sys.color.font_secondary'))
                  .fontWeight(this.isCurrentChapter(chapter) ? FontWeight.Medium : FontWeight.Normal)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.isCurrentChapter(chapter)) {
                SymbolGlyph($r('sys.symbol.scope'))
                  .fontSize(18)
                  .fontColor([AppColor.Brand])
              }
              ChapterCacheIndicator({ book: this.book ?? null, chapter: chapter })
            }
            .width('100%')
            .constraintSize({ minHeight: 64 })
            .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Sm, bottom: AppSpace.Sm })
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.selectChapter(chapter);
            })
          }
        }, (chapter: Chapter) => this.chapterStableKey(chapter))
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ bottom: AppSpace.Sm })
      .scrollBar(BarState.On)
      .cachedCount(8)
      .onScrollIndex((firstIndex: number, lastIndex: number): void => {
        const centerIndex = (firstIndex + lastIndex) / 2;
        this.chapterListOffsetFromCurrent =
          (centerIndex - (this.book ? PreferenceService.chapterDisplayIndex(this.book ?? null, this.chapterIndex) : 0)) * 64;
      })
      }
      }
      .width('100%')
      .height('100%')

      if (this.shouldShowChapterJumpButton()) {
        Row({ space: AppSpace.Xs }) {
          SymbolGlyph($r('sys.symbol.scope'))
            .fontSize(16)
            .fontColor(['#FFFFFF'])
          Text($r('app.string.reader_back_to_current_chapter'))
            .fontSize(AppFont.Caption)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius(22)
        .backgroundColor(AppColor.Brand)
        .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
        .margin({ right: AppSpace.Lg, bottom: AppSpace.Lg })
        .onClick((): void => {
          this.jumpToCurrentChapter();
        })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.8, y: 0.8 }))
          .animation({ curve: curves.springMotion(0.4, 0.9) }))
      }
    }
    .width('100%')
    .height('100%')
  }

  private brightnessBarHeight(): number {
    return Math.min(280, Math.max(160, this.heightVp - this.topSafe - this.bottomSafe - 180));
  }

  private changeBrightness(value: number, commit: boolean): void {
    this.readingBrightness = value;
    this.brightnessControl.configure(value);
    if (commit) {
      PreferenceService.setComicBrightness(value).catch((): void => {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
      });
    }
  }

  private async setBrightnessBar(enabled: boolean): Promise<void> {
    const previous = this.showBrightnessBar;
    this.showBrightnessBar = enabled;
    try { await PreferenceService.setComicBrightnessBar(enabled); }
    catch (_error) {
      this.showBrightnessBar = previous;
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    }
  }

  private async setChapterBar(enabled: boolean): Promise<void> {
    if (this.settingsSaving) return;
    this.settingsSaving = true;
    try {
      await PreferenceService.setComicChapterBar(enabled);
      if (this.alive) this.showChapterBar = enabled;
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    } finally { this.settingsSaving = false; }
  }

  private async setVolumeKeyPageTurn(enabled: boolean): Promise<void> {
    if (this.settingsSaving) return;
    this.settingsSaving = true;
    try {
      await PreferenceService.setComicVolumeKeyPageTurn(enabled);
      if (this.alive) { this.volumeKeyPageTurn = enabled; this.syncVolumeKeys(); }
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    } finally { this.settingsSaving = false; }
  }

  private async setPageTurnHaptic(value: string): Promise<void> {
    if (this.settingsSaving) return;
    this.settingsSaving = true;
    const level = TextReadingSettings.normalizePageTurnHaptic(value);
    try {
      await PreferenceService.setComicPageTurnHaptic(level);
      if (this.alive) {
        this.pageTurnHaptic = level;
        if (this.foreground && this.readerVisible) ReaderHapticService.play(level);
      }
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    } finally { this.settingsSaving = false; }
  }

  private setColorization(enabled: boolean): void {
    if (enabled && !this.membership.hasAccess) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.membership_feature_required') });
      return;
    }
    if (enabled && !ComicColorizationService.supported()) return;
    ComicColorizationService.release();
    this.showTranslationMenu = false;
    this.colorization = enabled;
    const context = this.getUIContext().getHostContext();
    if (enabled && context) {
      ComicColorizationService.prepare(context, (): boolean =>
        this.alive && this.foreground && this.readerVisible && this.colorization && this.membership.hasAccess);
    }
  }

  private colorizationFailed(message: string): void {
    if (!this.alive || (!this.colorization && !this.translation)) return;
    this.colorization = false;
    this.translation = false;
    let text: ResourceStr = $r('app.string.comic_ai_request_failed');
    if (message === 'comic_ai_color_unsupported') text = $r('app.string.comic_ai_color_unsupported');
    else if (message === 'comic_ai_color_failed') text = $r('app.string.comic_ai_color_failed');
    else if (message.startsWith('comic_offline_')) text = $r('app.string.comic_offline_failed');
    else if (message === 'comic_ai_invalid_image') text = $r('app.string.comic_ai_invalid_image');
    else if (message === 'comic_ai_image_too_large') text = $r('app.string.comic_ai_image_too_large');
    else if (message === 'comic_ai_ocr_unsupported') text = $r('app.string.comic_ai_ocr_unsupported');
    else if (message === 'comic_ai_ocr_failed') text = $r('app.string.comic_ai_ocr_failed');
    else if (message === 'comic_ai_translate_invalid_response') text = $r('app.string.comic_ai_translate_invalid_response');
    else if (message === 'comic_ai_translate_too_large') text = $r('app.string.comic_ai_translate_too_large');
    else if (message === 'comic_ai_translate_layout_failed') text = $r('app.string.comic_ai_translate_layout_failed');
    else if (message === 'comic_ai_translate_render_failed') text = $r('app.string.comic_ai_translate_render_failed');
    this.getUIContext().getPromptAction().showToast({ message: text, duration: 4000 });
  }

  private async setImagePreloadCount(count: number): Promise<void> {
    if (this.settingsSaving || count === this.imagePreloadCount) return;
    this.settingsSaving = true;
    try {
      await PreferenceService.setComicImagePreloadCount(count);
      if (this.alive) this.imagePreloadCount = count;
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    } finally { this.settingsSaving = false; }
  }

  private async setTranslationDirection(direction: string): Promise<void> {
    if (this.settingsSaving || direction === this.translationDirection) return;
    this.settingsSaving = true;
    this.translationIntent++;
    this.translation = false;
    try {
      await PreferenceService.setComicTranslationDirection(direction);
      ComicColorizationService.resetFailure();
      if (this.alive) this.translationDirection = direction;
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_save_failed') });
    } finally { this.settingsSaving = false; }
  }

  private async toggleTranslation(): Promise<void> {
    if (!this.membership.hasAccess) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_translation_membership') });
      return;
    }
    if (this.translationDownloading) { this.translationIntent++; return; }
    if (this.translation) { this.translationIntent++; this.translation = false; return; }
    if (this.settingsSaving) return;
    if (!this.translationConfigured) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_offline_failed') });
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const intent = ++this.translationIntent;
    const direction = this.translationDirection;
    const active = (): boolean => this.alive && this.foreground && this.readerVisible && this.membership.hasAccess &&
      intent === this.translationIntent && direction === this.translationDirection;
    this.translationDownloading = true;
    this.translationDownloadPercent = 0;
    try {
      const bytes = await ComicTranslationModelService.missingBytes(context, direction, active);
      if (!active()) return;
      if (bytes > 0) {
        const choice = await this.getUIContext().getPromptAction().showDialog({
          title: $r('app.string.comic_translation_download_title'),
          message: $r('app.string.comic_translation_download_message', Math.ceil(bytes / 1024 / 1024)),
          buttons: [{ text: $r('app.string.common_cancel'), color: $r('sys.color.font_secondary') },
            { text: $r('app.string.comic_translation_download_action'), color: AppColor.Brand }]
        });
        if (choice.index !== 1 || !active()) return;
      }
      await ComicTranslationModelService.ensure(context, direction, active, (percent: number): void => {
        if (active()) this.translationDownloadPercent = percent;
      });
      if (!active()) return;
      ComicColorizationService.resetFailure();
      this.translation = true;
    } catch (_error) {
      if (active()) this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_translation_download_failed') });
    } finally { this.translationDownloading = false; }
  }

  private translationMenuOptions(): MenuOptions {
    const options: MenuOptions = {
      placement: Placement.BottomLeft,
      backgroundColor: AppMaterial.SheetBackground,
      onDisappear: (): void => { this.showTranslationMenu = false; }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    else options.backgroundBlurStyle = AppMaterial.SheetBlur;
    return options;
  }

  private async chooseTranslation(direction: string): Promise<void> {
    this.showTranslationMenu = false;
    if (!this.membership.hasAccess) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_translation_membership') });
      return;
    }
    if (this.translation && this.translationDirection === direction) return;
    const intent = ++this.translationIntent;
    this.translation = false;
    while (this.translationDownloading && this.alive && intent === this.translationIntent) {
      await new Promise<void>(resolve => setTimeout(resolve, 50));
    }
    if (!this.alive || intent !== this.translationIntent) return;
    await this.setTranslationDirection(direction);
    if (this.alive && this.translationDirection === direction) await this.toggleTranslation();
  }

  @Builder
  translationMenuItem(label: Resource, direction: string) {
    MenuItem({ content: label })
      .selected(this.translation && this.membership.hasAccess && this.translationDirection === direction)
      .selectIcon(false)
      .contentFontColor(this.translation && this.membership.hasAccess && this.translationDirection === direction ?
        AppColor.Brand : $r('sys.color.font_primary'))
      .enabled(!this.settingsSaving)
      .onClick((): void => { this.chooseTranslation(direction); })
  }

  @Builder
  translationMenu() {
    Menu() {
      this.translationMenuItem($r('app.string.comic_translation_ja_zh'), 'ja-zh')
      this.translationMenuItem($r('app.string.comic_translation_ko_zh'), 'ko-zh')
      this.translationMenuItem($r('app.string.comic_translation_en_zh'), 'en-zh')
      this.translationMenuItem($r('app.string.comic_translation_zh_en'), 'zh-en')
      MenuItem({ content: this.translationDownloading ? $r('app.string.common_cancel') : $r('app.string.comic_translation_off') })
        .onClick((): void => {
          this.showTranslationMenu = false; this.translationIntent++; this.translation = false;
        })
    }
  }

  @Builder
  settingsSheet() {
    Column() {
      Row() {
        Text($r('app.string.reader_settings')).fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        SettingsHintButton({ title: $r('app.string.comic_settings_gesture_title'), message: $r('app.string.comic_gesture_hint') })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([$r('sys.color.font_secondary')])
        }.width(36).height(36).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.common_close')).id('comic-settings-close')
          .onClick((): void => { this.showSettings = false; })
      }.width('100%').padding({ left: 16, right: 8, top: 4, bottom: 4 })
    Scroll() {
    Column({ space: 6 }) {
      ReaderSettingsSectionHeader({ title: $r('app.string.comic_settings_reading_group') })
      ReaderSettingCard({ compact: true, title: $r('app.string.reader_turn_title'), inline: true }) {
        ImmersiveOptionTabs({ labels: [$r('app.string.comic_scroll'), $r('app.string.comic_paged'),
          $r('app.string.comic_rtl'), $r('app.string.comic_dissolve')], selected: this.mode,
          onSelect: (index: number): void => { this.changeMode(index); } }).enabled(!this.settingsSaving)
      }
      ReaderSettingCard({ compact: true, title: $r('app.string.comic_display_title'), inline: true,
        description: this.displayModeHint() }) {
        ImmersiveOptionTabs({ labels: [$r('app.string.comic_display_default'), $r('app.string.comic_display_width'),
          $r('app.string.comic_display_screen'), $r('app.string.comic_display_original')], selected: this.displayMode,
          onSelect: (index: number): void => { this.changeDisplayMode(index); } })
          .id('comic-display-mode').enabled(!this.settingsSaving)
      }
      if (this.mode !== 0 && this.displayMode === 0) {
        ReaderSettingCard({ compact: true, title: $r('app.string.comic_page_layout'), inline: true,
          description: $r('app.string.comic_page_layout_hint') }) {
          ImmersiveOptionTabs({ labels: this.mode === 1 ? [$r('app.string.comic_layout_width'),
            $r('app.string.comic_layout_screen'), $r('app.string.comic_layout_joined')] :
            [$r('app.string.comic_layout_width'), $r('app.string.comic_layout_screen')],
            selected: this.mode === 1 ? this.pageLayout : Math.min(1, this.pageLayout),
            onSelect: (index: number): void => { this.changePageLayout(index); } }).enabled(!this.settingsSaving)
        }
      } else if (this.mode === 1) {
        ReaderSettingCard({ compact: true, title: $r('app.string.comic_page_layout'), inline: true,
          description: $r('app.string.comic_pagination_hint') }) {
          ImmersiveOptionTabs({ labels: [$r('app.string.comic_layout_single'), $r('app.string.comic_layout_joined')],
            selected: this.pageLayout === 2 ? 1 : 0,
            onSelect: (index: number): void => { this.changePageLayout(index === 1 ? 2 : 1); } })
            .enabled(!this.settingsSaving)
        }
      }
      if (this.usesJoinedPages()) {
        ReaderSettingCard({ compact: true, title: $r('app.string.comic_page_overlap'), inline: true,
          description: $r('app.string.comic_page_overlap_hint') }) {
          ImmersiveOptionTabs({ labels: ['0%', '10%', '20%', '30%'], selected: this.pageOverlap / 10,
            onSelect: (index: number): void => { this.changePageOverlap(index * 10); } }).enabled(!this.settingsSaving)
        }
      }
      ReaderSettingsSectionHeader({ title: $r('app.string.reader_settings_turn_group') })
      ReaderSettingCard({ compact: true, title: $r('app.string.reader_turn_haptic'), inline: true }) {
        ImmersiveOptionTabs({ labels: [$r('app.string.reader_turn_none'), $r('app.string.reader_haptic_strong'),
          $r('app.string.reader_haptic_medium'), $r('app.string.reader_haptic_weak')],
          selected: ['none', 'strong', 'medium', 'weak'].indexOf(this.pageTurnHaptic),
          onSelect: (index: number): void => { this.setPageTurnHaptic(['none', 'strong', 'medium', 'weak'][index]); }
        }).id('comic-page-turn-haptic').enabled(!this.settingsSaving)
      }
      ReaderSettingCard({ compact: true, title: $r('app.string.reader_volume_key_turn'), inline: true,
        description: $r('app.string.reader_volume_key_hint') }) {
        Toggle({ type: ToggleType.Switch, isOn: this.volumeKeyPageTurn }).selectedColor(AppColor.Brand)
          .enabled(!this.settingsSaving)
          .onChange((enabled: boolean): void => { this.setVolumeKeyPageTurn(enabled); })
      }
      ReaderAutoPageSettings({ compact: true, seconds: this.autoPageSeconds, running: this.autoPageRunning, paused: this.autoPagePaused,
        scrolling: this.mode === 0, comic: true, speed: this.autoScrollSpeed,
        onSpeed: (speed: number): void => this.setAutoScrollSpeed(speed),
        available: !this.busy && !this.failed && this.pageCount > 0 && !this.zoomActive,
        onInterval: (seconds: number): void => this.setAutoPageInterval(seconds),
        onToggle: (): void => this.toggleAutoPage() })
      ReaderSettingsSectionHeader({ title: $r('app.string.comic_settings_display_group') })
      ReaderSettingCard({ compact: true, title: $r('app.string.reader_show_chapter_bar'), inline: true }) {
        Toggle({ type: ToggleType.Switch, isOn: this.showChapterBar }).selectedColor(AppColor.Brand)
          .enabled(!this.settingsSaving)
          .onChange((enabled: boolean): void => { this.setChapterBar(enabled); })
      }
      ReaderSettingCard({ compact: true, title: $r('app.string.reader_show_brightness_bar'), inline: true }) {
        Toggle({ type: ToggleType.Switch, isOn: this.showBrightnessBar }).selectedColor(AppColor.Brand)
          .onChange((enabled: boolean): void => { this.setBrightnessBar(enabled); })
      }
      ComicAppearanceSettings({ value: this.appearance,
        onChange: (value: ComicReaderAppearance): void => { this.changeAppearance(value); } }).enabled(!this.settingsSaving)
      ReaderSettingsSectionHeader({ title: $r('app.string.comic_settings_image_group') })
      ReaderSettingCard({ compact: true, title: $r('app.string.comic_trim_white_border'), inline: true,
        description: $r('app.string.comic_trim_white_border_hint') }) {
        Toggle({ type: ToggleType.Switch, isOn: this.trimWhiteBorder }).selectedColor(AppColor.Brand)
          .id('comic-trim-white-border').enabled(!this.settingsSaving)
          .onChange((enabled: boolean): void => { this.setTrimWhiteBorder(enabled); })
      }
      ReaderSettingCard({ compact: true, title: $r('app.string.comic_image_preload_title'), inline: true,
        description: $r('app.string.comic_image_preload_hint') }) {
        ImmersiveOptionTabs({ labels: [$r('app.string.comic_image_preload_off'),
          $r('app.string.comic_image_preload_count', 2), $r('app.string.comic_image_preload_count', 5),
          $r('app.string.comic_image_preload_count', 10), $r('app.string.comic_image_preload_count', 20)],
          selected: [0, 2, 5, 10, 20].indexOf(this.imagePreloadCount),
          onSelect: (index: number): void => { this.setImagePreloadCount([0, 2, 5, 10, 20][index]); }
        }).enabled(!this.settingsSaving)
      }
      ReaderSettingCard({ compact: true, title: $r('app.string.comic_ai_sr'), inline: true, showVip: MembershipState.featureEnabled,
        description: $r('app.string.comic_ai_sr_hint') }) {
        Toggle({ type: ToggleType.Switch, isOn: this.superResolution && this.membership.hasAccess })
          .selectedColor(AppColor.Brand).enabled(this.membership.hasAccess && ComicSuperResolutionService.supported() && !this.savingSuperResolution)
          .onChange((enabled: boolean) => { this.setSuperResolution(enabled); })
      }
      ReaderSettingCard({ compact: true, title: $r('app.string.comic_ai_color'), inline: true, showVip: MembershipState.featureEnabled,
        description: ComicColorizationService.supported() ? $r('app.string.comic_ai_color_hint') : $r('app.string.comic_ai_color_unsupported') }) {
        Toggle({ type: ToggleType.Switch, isOn: this.colorization && this.membership.hasAccess }).selectedColor(AppColor.Brand)
          .enabled(ComicColorizationService.supported())
          .onChange((enabled: boolean): void => { this.setColorization(enabled); })
      }
      ReaderSettingCard({ compact: true, title: $r('app.string.comic_ai_translate'), inline: true, showVip: MembershipState.featureEnabled,
        description: $r('app.string.comic_offline_hint') }) {
        Toggle({ type: ToggleType.Switch, isOn: this.translation && this.membership.hasAccess })
          .selectedColor(AppColor.Brand).enabled(!this.settingsSaving)
          .onChange((_enabled: boolean): void => { this.toggleTranslation(); })
      }
      if (this.translationDownloading) {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20).color(AppColor.Brand)
          Text($r('app.string.comic_translation_downloading', this.translationDownloadPercent)).fontSize(13).layoutWeight(1)
          Button($r('app.string.common_cancel')).onClick((): void => { this.translationIntent++; })
        }.width('100%')
      }
      ReaderSettingCard({ compact: true, title: $r('app.string.comic_translation_engine'), inline: true }) {
        ImmersiveOptionTabs({ labels: [$r('app.string.comic_translation_ja_zh'), $r('app.string.comic_translation_ko_zh'),
          $r('app.string.comic_translation_en_zh'), $r('app.string.comic_translation_zh_en')],
          selected: ['ja-zh', 'ko-zh', 'en-zh', 'zh-en'].indexOf(this.translationDirection),
          onSelect: (index: number): void => {
            const direction = ['ja-zh', 'ko-zh', 'en-zh', 'zh-en'][index];
            if (direction) this.setTranslationDirection(direction);
          } }).id('comic-translation-direction').enabled(!this.settingsSaving && this.membership.hasAccess)
      }
    }.width('100%').padding({ left: 10, right: 10, bottom: 10 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    }.width('100%').height('100%')
  }

}
