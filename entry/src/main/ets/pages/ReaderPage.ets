import { ReaderBrightnessService } from '../service/text/ReaderBrightnessService';
import { ReaderBookmark, ReaderTextDocument } from '../model/ReaderTools';
import { ReaderToolsService } from '../service/text/ReaderToolsService';
import { ReaderBookmarkSheet } from '../components/ReaderBookmarkSheet';
import { ReaderReplaceSheet } from '../components/ReaderReplaceSheet';
import { LocalTextImage } from '../service/text/LocalTextImage';
import { ReaderBrightnessBar } from '../components/ReaderBrightnessBar';
import { GeneralSettings } from '../model/GeneralSettings';
import { ReaderHoldingHandService } from '../service/text/ReaderHoldingHandService';
import { ReaderWidgetService } from '../service/ReaderWidgetService';
import { ChapterSheetActions } from '../components/ChapterSheetActions';
import { ReaderVolumeKeyService } from '../service/text/ReaderVolumeKeyService';
import { ReadingSessionService, SessionLocation } from '../service/ReadingSessionService';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { KeyCode } from '@kit.InputKit';
import { ReaderTapPolicy } from '../utils/ReaderTapPolicy';
import { ImmersiveCircleButton } from '../components/ImmersiveCircleButton';
import { ChapterCacheIndicator } from '../components/ChapterCacheIndicator';
import { BookSourceSwitchSheet } from '../components/BookSourceSwitchSheet';
import { TextReaderRouteParams } from '../model/TextReading';
import { ReaderSpeechFloating } from '../components/ReaderSpeechFloating';
import { CoverImage } from '../components/CoverImage';
import { ReaderFontService, ReaderImportedFont } from '../service/text/ReaderFontService';
import { ReaderScreenOnService } from '../service/text/ReaderScreenOnService';
import { HdsTabs, HdsTabsFloatingStyle } from '@kit.UIDesignKit';
import { HdsCompat, CompatibleTabsModifier } from '../utils/HdsCompat';
import { PreferenceService } from '../service/PreferenceService';
import { ReaderSpeechText } from '../components/ReaderSpeechText';
import { ReaderSpeechSheet } from '../components/ReaderSpeechSheet';
import { ReadingTimeTracker } from '../service/text/ReadingTimeTracker';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { PlatformCompat } from '../utils/PlatformCompat';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { curves, SymbolGlyphModifier } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { bookParser } from '@hms.core.readerservice.bookParser';
import { readerCore } from '@hms.core.readerservice.readerComponent';
import { EpubReaderParams } from '../model/EpubReaderParams';
import { Book, Chapter } from '../model/Book';
import {
  TextReadingPosition,
  PageTurnMode,
  TextReadingSettings,
  ReaderCornerLayout,
  ReaderCornerContent,
  EVT_READER_JUMP_CHAPTER,
  EVT_READER_TYPOGRAPHY_CHANGED,
  ReaderJumpChapterEvent
} from '../model/TextReading';
import { emitter } from '@kit.BasicServicesKit';
import { ReaderPalette, ReaderPattern, ReaderImageMode, ReaderThemeId, ReaderCustomTheme, resolvePalette, resolveEffectiveThemeId } from '../model/ReaderTheme';
import { ReaderBackground } from '../components/ReaderBackground';
import { ReaderContinuousComponent } from '../components/ReaderContinuousComponent';
import { ReaderPageTurnComponent } from '../components/ReaderPageTurnComponent';
import { ReaderSettingsSheet } from '../components/ReaderSettingsSheet';
import { ChapterSegmentGrid } from '../components/ChapterSegmentGrid';
import { ReaderStatusIndicator } from '../components/ReaderStatusIndicator';
import { DataService } from '../service/DataService';
import { BookSourceService } from '../service/BookSourceService';
import {
  OnlineTextNavigationTarget,
  OnlineTextPage,
  OnlineTextPageNavigator,
  OnlineTextPaginator
} from '../service/text/OnlineTextPaginator';
import { TextReadingProgressService } from '../service/text/TextReadingProgressService';
import { OnlineTextContentCache } from '../service/text/OnlineTextContentCache';
import { ReaderCacheService } from '../service/ReaderCacheService';
import { TextReadingSettingsService } from '../service/text/TextReadingSettingsService';
import { AppColor, AppFont, AppSpace, AppRadius, AppMaterial } from '../theme/Theme';
import { ChapterDataSource } from '../utils/ChapterDataSource';
import { SearchCache } from '../utils/SearchCache';
import { WindowUtils } from '../utils/WindowUtils';

const READER_LOG_DOMAIN: number = 0x0000;
const READER_LOG_TAG: string = 'ReaderPage';
const READER_FLOATING_BOTTOM: number = 4;
const READER_MIN_SAFE_BOTTOM: number = 8;
const READER_LANDSCAPE_TOP_GAP: number = 16;
/** 手势/悬浮小白条的最大正文避让：只需让过悬浮条本体，不占完整手势区。 */
const READER_GESTURE_SAFE_MAX: number = 16;
// 与首页 HdsTabs barFloatingStyle 官方沉浸栏同款视觉参数。
const READER_BAR_HEIGHT: number = 56;
const READER_BAR_MASK_HEIGHT: number = 92;
const READER_CHAPTER_ROW_HEIGHT: number = 64;
const READER_CHAPTER_JUMP_DISTANCE: number = 200;
const READER_TEXT_HORIZONTAL_PADDING: number = 24;
const READER_TEXT_HEADER_HEIGHT: number = 22;
const READER_TEXT_FOOTER_HEIGHT: number = 24;
const READER_TEXT_LAYOUT_GUARD: number = 4;

/** 与章节栏一致裁剪 HDS 材质，避免默认外投影落到正文上。 */
class ReaderControlClip implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(node: CommonAttribute): void {
    if (PlatformCompat.floatingTabs) node.borderRadius(READER_BAR_HEIGHT / 2, RenderStrategy.OFFSCREEN);
    else node.borderRadius(READER_BAR_HEIGHT / 2);
    node.clip(true);
  }
}

class ReaderOnlineTextTurnPreview {
  chapterIndex: number = 0;
  pageIndex: number = 0;
  content: string = '';
  pages: OnlineTextPage[] = [];
}

@ComponentV2
export struct ReaderPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';
  @Param targetResourceIndex: number = -1;
  @Param targetDomPos: string = '';
  @Local book: Book | null = null;
  @Local showSourceSwitch: boolean = false;
  @Local showReaderMenu: boolean = false;
  @Local showBookmarkSheet: boolean = false;
  @Local showReplaceSheet: boolean = false;
  @Local bookmarks: ReaderBookmark[] = [];
  @Local bookmarkBusy: boolean = false;
  @Local replaceSample: string = '';
  private textDocuments: Map<number, ReaderTextDocument> = new Map();
  private textRulesGeneration: number = 0;
  @Local selectingText: boolean = false;
  @Local reloadingChapter: boolean = false;
  @Local loading: boolean = true;
  @Local readerError: string = '';
  @Local currentResourceIndex: number = 0;
  @Local currentChapterTitle: string = '';
  @Local fontSize: number = TextReadingSettings.FONT_SIZE_DEFAULT;
  @Local lineHeight: number = TextReadingSettings.LINE_HEIGHT_DEFAULT;
  @Local paragraphSpacing: number = TextReadingSettings.PARAGRAPH_SPACING_DEFAULT;
  @Local previewParagraphSpacing: number = -1;
  @Local pickingBackgroundImage: boolean = false;
  @Local followSystemTheme: boolean = false;
  @Local systemNightOverride: boolean = false;
  @Local marginLeft: number = 16;
  @Local marginRight: number = 16;
  @Local marginTop: number = 12;
  @Local marginBottom: number = 12;
  /** 上边距上限：跟随阅读视口高度（最高一半），旋转/分屏时更新 */
  @Local marginTopMax: number = 64;
  @Local chapterQuery: string = '';
  private readonly readerColorListener = (): void => {
    if (this.followSystemTheme && !this.leaving) {
      this.refreshPalette();
      this.applyReadingSettings(false);
    }
  };
  @Local themeId: string = TextReadingSettings.THEME_DEFAULT;
  @Local customBackground: string = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
  @Local customThemes: ReaderCustomTheme[] = ReaderCustomTheme.defaults();
  @Local customThemeIndex: number = 0;
  @Local imageBackground: string = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
  @Local imageFontColor: string = '';
  @Local effectiveThemeId: string = TextReadingSettings.THEME_DEFAULT;
  @Local backgroundPattern: string = ReaderPattern.None;
  @Local bgImagePath: string = '';
  @Local backgroundImageMode: ReaderImageMode = ReaderImageMode.Cover;
  @Local overlayAlpha: number = TextReadingSettings.OVERLAY_DEFAULT;
  @Local tapRegions: string = ReaderTapPolicy.DEFAULT;
  @Local tapLeftPercent: number = 33;
  @Local tapRightPercent: number = 33;
  @Local tapTopPercent: number = 33;
  @Local tapBottomPercent: number = 33;
  @Local showChapterBar: boolean = true;
  @Local showBrightnessBar: boolean = true;
  @Local readingBrightness: number = -1;
  private brightnessControl: ReaderBrightnessService = new ReaderBrightnessService();
  @Local showHeader: boolean = true;
  @Local cornerLayout: string = ReaderCornerLayout.DEFAULT;
  @Local showFooter: boolean = true;
  @Local showChapterTitle: boolean = true;
  @Local showPageNumber: boolean = true;
  @Local showChapterNumber: boolean = true;
  @Local showBookName: boolean = true;
  private volumeKeys: ReaderVolumeKeyService = new ReaderVolumeKeyService();
  @Local readerVisible: boolean = false;
  @Local volumeKeyPageTurn: boolean = false;
  @Local keyTurnRequest: number = 0;
  @Local pageTurnMode: string = TextReadingSettings.PAGE_TURN_MODE_DEFAULT;
  @Local showReadingStatus: boolean = TextReadingSettings.SHOW_READING_STATUS_DEFAULT;
  @Local alwaysShowStatusBar: boolean = TextReadingSettings.ALWAYS_SHOW_STATUS_BAR_DEFAULT;
  /** 由 themeId / customBackground 解析出的当前配色；所有阅读色都从这里取 */
  @Local palette: ReaderPalette = resolvePalette(TextReadingSettings.THEME_DEFAULT,
    TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT);
  @Local readerKitReady: boolean = false;
  @Local jumpingResourceIndex: number = -1;
  @Local readerBarVisible: boolean = false;
  private readerBarChapterTarget: number = -1;
  @Local chapterSliderPreview: number = -1;
  @Local chapterSliderDragging: boolean = false;
  @Local chapterSliderConfirming: boolean = false;
  @Local pageLabelWidthVp: number = 0;
  @Local showChapterSheet: boolean = false;
  @Local chapterSegmented: boolean = false;
  @Local showSettingsSheet: boolean = false;
  @Local fontPanel: boolean = false;
  @Local fontWeight: number = 400;
  @Local textAlignment: string = 'justify';
  @Local previewFontSize: number = 0;
  @Local previewLineHeight: number = 0;
  @Local previewFontWeight: number = 0;
  @Local fontColor: string = '';
  @Local fontFamily: string = '';
  @Local systemTypographyRevision: number = 0;
  @Local fontPath: string = '';
  @Local fontName: string = '';
  @Local importedFonts: ReaderImportedFont[] = [];
  @Local screenOnMinutes: number = 0;
  @Local pickingFont: boolean = false;
  private screenOn: ReaderScreenOnService = new ReaderScreenOnService();
  @Local showSpeechSheet: boolean = false;
  @Local speechState: TextToSpeechState = TextToSpeechService.getInstance().state;
  private openingSpeechPlayer: boolean = false;
  /** 详情页返回栈内阅读页时按所选章节跳转 */
  private readonly jumpChapterHandler: (e: emitter.EventData) => void = (e) => this.onJumpChapterEvent(e);
  @Local chapterListOffsetFromCurrent: number = 0;
  @Local leftSafeVp: number = WindowUtils.getLeftSafeVp();
  @Local rightSafeVp: number = WindowUtils.getRightSafeVp();
  @Local cutoutTopSafeVp: number = WindowUtils.getCutoutTopVp();
  @Local topSafeVp: number = WindowUtils.getStatusBarHeightVp();
  @Local bottomSafeVp: number = WindowUtils.getBottomSafeVp();
  @Local onlineTextPages: OnlineTextPage[] = [];
  @Local onlineTextPageIndex: number = 0;
  @Local continuousRevision: number = 0;
  @Local onlineTextLoading: boolean = false;
  @Local onlineTextTurnPreview: ReaderOnlineTextTurnPreview | null = null;
  private onlineTextTurnSerial: number = 0;
  private onlineTextTurnLoading: boolean = false;
  private onlineTextTurnConfirmed: boolean = false;
  private currentPosition: TextReadingPosition | null = null;
  private context: common.UIAbilityContext | null = null;
  private leaving: boolean = false;
  private chapterDataSource: ChapterDataSource = new ChapterDataSource();
  @Local chapterTopRequest: number = 0;
  @Local chapterBottomRequest: number = 0;
  @Local chapterDescending: boolean = false;
  private chapterListScroller: Scroller = new Scroller();
  // 普通文字阅读不触碰可选 ReaderKit HSP；仅在旧 EPUB 分支通过能力检查后创建。
  private readerKitController: readerCore.ReaderComponentController | null = null;
  @Local epubReaderBuilder: WrappedBuilder<[EpubReaderParams]> | null = null;
  private readerKitHandler: bookParser.BookParserHandler | null = null;
  private readerSetting: readerCore.ReaderSetting | null = null;
  private readerKitDomPos: string = '';
  private readerKitPageOffset: number = 0;
  /** EPUB handler 缓存：记录已解析的文件路径，避免重复调用 getDefaultHandler */
  private static epubHandlerCache: Map<string, bookParser.BookParserHandler> = new Map();
  /** 缓存上限，避免内存占用过大 */
  private static readonly MAX_HANDLER_CACHE_SIZE: number = 3;
  /** 在线文本章节内存缓存：按书源、书籍及章节地址隔离 */
  private static onlineTextContentCache: Map<string, string> = new Map();
  /** 在线文本章节内容缓存上限 */
  private static readonly MAX_TEXT_CONTENT_CACHE_SIZE: number = 50;

  /** 供外部调用的缓存清除方法 */
  static clearEpubCache(): void {
    ReaderPage.epubHandlerCache.clear();
  }

  /** 清除在线文本章节缓存 */
  static clearTextContentCache(): void {
    ReaderPage.onlineTextContentCache.clear();
  }

  private onlineTextContent: string = '';
  private diskCacheOwner: string = ReaderCacheService.owner();
  private onlineTextContentRequests: Map<number, Promise<string>> = new Map();
  private onlineTextLoadSerial: number = 0;
  @Local readerViewportWidthVp: number = 0;
  @Local readerViewportHeightVp: number = 0;
  private readerTextWidthVp: number = 0;
  private readerTextHeightVp: number = 0;
  private readerSettingsRefreshTimerId: number = -1;
  private safeAreaChangeHandler: (topVp: number, bottomVp: number) => void =
    (topVp: number, bottomVp: number): void => {
      const cutoutChanged = Math.abs(this.cutoutTopSafeVp - WindowUtils.getCutoutTopVp()) >= 0.1;
      this.cutoutTopSafeVp = WindowUtils.getCutoutTopVp();
      const topChanged = Math.abs(this.topSafeVp - topVp) >= 0.1;
      const bottomChanged = Math.abs(this.bottomSafeVp - bottomVp) >= 0.1;
      const sideChanged = Math.abs(this.leftSafeVp - WindowUtils.getLeftSafeVp()) >= 0.1 ||
        Math.abs(this.rightSafeVp - WindowUtils.getRightSafeVp()) >= 0.1;
      this.leftSafeVp = WindowUtils.getLeftSafeVp();
      this.rightSafeVp = WindowUtils.getRightSafeVp();
      this.topSafeVp = topVp;
      this.bottomSafeVp = bottomVp;
      if (topChanged || bottomChanged || sideChanged || cutoutChanged) this.scheduleReaderSettingsRefresh();
    };

  private backgroundHandler = (): void => {
    this.readingForeground = false;
    this.completeOnlineTextTurn(this.onlineTextTurnConfirmed);
    this.saveProgress();
    ReadingSessionService.end('reading');
  };

  private systemTypographyKey: string = '';
  private sessionTimer: number = -1;
  private readingForeground: boolean = true;
  private readingTime: ReadingTimeTracker = new ReadingTimeTracker();
  private foregroundHandler = (): void => {
    this.readingForeground = true;
    if (this.readerVisible) { this.syncSpeechPosition(); this.saveProgress(); }
  };

  private currentSystemTypographyKey(): string {
    if (this.context === null) return '';
    const config = this.context.config;
    return `${config.fontId ?? ''}:${config.fontSizeScale ?? 1}:${config.fontWeightScale ?? 1}`;
  }

  private typographyChangeHandler = (): void => {
    if (this.leaving) return;
    const key = this.currentSystemTypographyKey();
    if (key === this.systemTypographyKey) return;
    this.systemTypographyKey = key;
    this.systemTypographyRevision++;
    OnlineTextPaginator.invalidateLayouts();
    this.scheduleReaderSettingsRefresh();
  };

  @Local holdingHandSide: number = 0;
  @Local generalSettings: GeneralSettings = GeneralSettings.current;
  @Local speechMiniVerticalRatio: number = -1;
  private speechMiniDragStartY: number = 0;
  private holdingHand: ReaderHoldingHandService = new ReaderHoldingHandService();

  @Monitor('generalSettings.adaptiveHandedness')
  private syncHoldingHand(): void {
    this.holdingHand.setVisible(this.readerVisible && !this.leaving && this.generalSettings.adaptiveHandedness);
    if (!this.generalSettings.adaptiveHandedness) this.holdingHandSide = 0;
  }

  aboutToAppear(): void {
    this.holdingHand.onChange = (left: boolean): void => { this.holdingHandSide = left ? 1 : 2; };
    this.holdingHand.setVisible(this.generalSettings.adaptiveHandedness);
    emitter.on('app.reader.background', this.backgroundHandler);
    emitter.on('app.reader.foreground', this.foregroundHandler);
    this.sessionTimer = setInterval((): void => {
      if (this.readingForeground && this.readerVisible && !this.leaving) this.saveProgress();
    }, 15000);
    emitter.on(EVT_READER_TYPOGRAPHY_CHANGED, this.typographyChangeHandler);
    this.leaving = false;
    this.readerVisible = true;
    this.readerBarVisible = false;
    this.syncReaderStatusBar();
    WindowUtils.setReaderActive(true);
    this.showChapterSheet = false;
    this.showSettingsSheet = false;
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.systemTypographyKey = this.currentSystemTypographyKey();
    WindowUtils.setStatusBarLight(false);
    WindowUtils.addSafeAreaListener(this.safeAreaChangeHandler);
    WindowUtils.addReaderColorListener(this.readerColorListener);
    WindowUtils.refreshAvoidArea();
    emitter.on(EVT_READER_JUMP_CHAPTER, this.jumpChapterHandler);
    this.brightnessControl.onFailure = (): void => this.showToast($r('app.string.reader_brightness_failed'));
    this.brightnessControl.init(this.context).catch((): void => {});
    this.brightnessControl.setVisible(true);
    this.screenOn.init(this.context).catch((): void => {});
    this.screenOn.setVisible(true);
    this.initializeReader();
  }

  aboutToDisappear(): void {
    ReaderCacheService.release(this.diskCacheOwner);
    this.readerVisible = false;
    this.volumeKeys.dispose();
    this.screenOn.dispose();
    this.brightnessControl.dispose();
    this.holdingHand.setVisible(false);
    emitter.off('app.reader.background', this.backgroundHandler);
    emitter.off('app.reader.foreground', this.foregroundHandler);
    if (this.sessionTimer >= 0) clearInterval(this.sessionTimer);
    this.sessionTimer = -1;
    emitter.off(EVT_READER_TYPOGRAPHY_CHANGED, this.typographyChangeHandler);
    this.completeOnlineTextTurn(this.onlineTextTurnConfirmed);
    this.leaving = true;
    emitter.off(EVT_READER_JUMP_CHAPTER, this.jumpChapterHandler);
    WindowUtils.setReaderActive(false);
    this.onlineTextLoadSerial++;
    this.cancelReaderSettingsRefresh();
    this.saveProgress();
    ReadingSessionService.end('reading');
    this.saveReadingSettings();
    WindowUtils.removeSafeAreaListener(this.safeAreaChangeHandler);
    WindowUtils.removeReaderColorListener(this.readerColorListener);
    WindowUtils.setStatusBarLight(false);
  }

  private cancelReaderSettingsRefresh(): void {
    if (this.readerSettingsRefreshTimerId !== -1) {
      clearTimeout(this.readerSettingsRefreshTimerId);
      this.readerSettingsRefreshTimerId = -1;
    }
  }

  /** 合并旋转和窗口缩放期间的多次尺寸回调。 */
  private scheduleReaderSettingsRefresh(): void {
    this.cancelReaderSettingsRefresh();
    this.readerSettingsRefreshTimerId = setTimeout((): void => {
      this.readerSettingsRefreshTimerId = -1;
      if (this.leaving) return;
      this.applyReadingSettings();
    }, 120);
  }

  private handleViewportSizeChange(_oldValue: SizeOptions, newValue: SizeOptions): void {
    if (typeof newValue.width !== 'number' || typeof newValue.height !== 'number' ||
      newValue.width <= 0 || newValue.height <= 0) return;
    const changed = Math.abs(this.readerViewportWidthVp - newValue.width) >= 0.5 ||
      Math.abs(this.readerViewportHeightVp - newValue.height) >= 0.5;
    this.readerViewportWidthVp = newValue.width;
    this.readerViewportHeightVp = newValue.height;
    this.updateMarginTopMax();
    if (!changed) return;
    this.scheduleReaderSettingsRefresh();
  }

  /** 上边距允许到阅读视口一半；换小屏后把已保存的超大值压回上限内。 */
  private updateMarginTopMax(): void {
    const height = this.readerViewportHeightVp > 0 ? this.readerViewportHeightVp :
      WindowUtils.getWindowHeightVp();
    const nextMax = Math.max(TextReadingSettings.MARGIN_UI_MAX, Math.floor(height / 2));
    if (Math.abs(nextMax - this.marginTopMax) < 1) return;
    this.marginTopMax = nextMax;
    if (this.marginTop > nextMax) {
      this.marginTop = nextMax;
      this.applyReadingSettings();
      this.saveReadingSettings();
    }
  }

  private async initializeReader(): Promise<void> {
    if (!this.context || !this.bookId) {
      this.failReader('电子书参数无效');
      return;
    }
    this.loading = true;
    this.readerError = '';
    this.onlineTextLoadSerial++;
    this.onlineTextLoading = false;
    try {
      await this.restoreReadingSettings();
      if (this.leaving) return;
      let value = SearchCache.get(this.bookId);
      if (!value) value = await DataService.getBookById(this.context, this.bookId) ?? null;
      if (!value) {
        this.failReader('未找到电子书');
        return;
      }
      if (!this.canOpenBook(value)) {
        this.failReader('未找到电子书');
        return;
      }
      if (this.isOnlineTextBookValue(value) && value.chapters.length === 0) {
        value.chapters = await DataService.getChaptersForBook(value.id);
      }
      if (this.isOnlineTextBookValue(value) && value.chapters.length === 0) {
        value = await BookSourceService.loadTextBook(value);

      }
      if (this.isOnlineTextBookValue(value) && value.chapters.length === 0) {
        this.failReader('这本书暂时没有可读章节');
        return;
      }
      if (this.leaving) return;
      // 阅读记录依赖持久书籍身份，已有目录时也必须保存。
      await DataService.upsertCachedBook(value);
      await PreferenceService.applyTocOrder(value);
      this.book = value;
      this.chapterDataSource.setChapters(PreferenceService.orderedChapters(value));
      SearchCache.put(value);
      if (BookSourceService.pendingTextBook(value.id) !== undefined) {
        BookSourceService.loadTextBook(value, (loaded: Book): void => {
          if (this.leaving || this.book?.id !== loaded.id) return;
          // 只更新目录，不重载正文或改变当前字符位置。
          this.book = loaded;
          this.chapterDataSource.setChapters(PreferenceService.orderedChapters(loaded));
        }).catch((error: Error): void => {
          hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'background toc failed: %{public}s', error.message);
        });
      }
      const startPosition = await this.resolveStartPosition(value);
      if (this.leaving) return;
      if (this.isOnlineTextBookValue(value)) {
        await this.prepareOnlineTextReader(value, startPosition);
      } else {
        await this.prepareReaderKitReader(value, startPosition);
      }
      if (!this.leaving) this.saveProgress();
    } catch (e) {
      this.failReader(e instanceof Error ? e.message : String(e));
    }
  }

  private canOpenBook(book: Book): boolean {
    if (this.isOnlineTextBookValue(book)) return true;
    return this.resolveEpubFilePath(book).length > 0;
  }

  private async resolveStartPosition(book: Book): Promise<TextReadingPosition> {
    if (!this.context) return TextReadingPosition.of(book.id, 0, '', 0, this.chapterTitle(0));
    if (this.speechState.active && this.speechState.bookId === book.id) {
      return TextReadingPosition.atChar(book.id, this.speechState.chapterIndex, '', TextToSpeechService.getInstance().currentRawOffset(), 0, this.speechState.chapterTitle);
    }
    if (this.targetResourceIndex >= 0) {
      const target = this.clampResourceIndex(this.targetResourceIndex, book.chapters.length);
      return TextReadingPosition.atChar(book.id, target, this.targetDomPos, 0, 0, this.chapterTitle(target));
    }
    const saved = await TextReadingProgressService.get(this.context, book.id);
    if (saved) {
      const titleIndex = this.chapterIndexByTitle(book, saved.chapterTitle);
      if (titleIndex >= 0) {
        return TextReadingPosition.atChar(
          book.id, titleIndex, saved.domPos, saved.charOffset, saved.pageOffset, saved.chapterTitle);
      }
      const fallbackIndex = this.clampResourceIndex(saved.resourceIndex, book.chapters.length);
      return TextReadingPosition.atChar(
        book.id, fallbackIndex, saved.domPos, saved.charOffset, saved.pageOffset, this.chapterTitle(fallbackIndex));
    }
    const first = 0;
    return TextReadingPosition.atChar(book.id, first, '', 0, 0, this.chapterTitle(first));
  }

  private bookContentType(book: Book): string {
    return book.contentType ?? '';
  }

  private isOnlineTextBook(): boolean {
    const currentBook = this.book;
    return currentBook !== null && this.isOnlineTextBookValue(currentBook);
  }

  private isOnlineTextBookValue(book: Book): boolean {
    return this.bookContentType(book) === 'text' && this.resolveEpubFilePath(book).length === 0;
  }

  private async prepareOnlineTextReader(book: Book, startPosition: TextReadingPosition): Promise<void> {
    this.readerKitReady = false;
    this.readerKitHandler = null;
    this.readerSetting = null;
    const count = Math.max(1, book.chapters.length);
    const resourceIndex = this.clampResourceIndex(startPosition.resourceIndex, count);
    this.currentResourceIndex = resourceIndex;
    this.currentChapterTitle = this.chapterTitle(resourceIndex);
    this.currentPosition = TextReadingPosition.atChar(
      book.id, resourceIndex, '', startPosition.charOffset, startPosition.pageOffset, this.currentChapterTitle);
    const loaded = await this.loadOnlineTextChapter(
      resourceIndex, startPosition.charOffset, startPosition.pageOffset, false, true);
    if (!loaded || this.leaving) return;
    setTimeout((): void => {
      if (!this.leaving) this.hideReaderBar();
    }, 0);
  }

  private async loadOnlineTextChapter(resourceIndex: number, charOffset: number,
    pageOffset: number, openLastPage: boolean, initialLoad: boolean, forceReload: boolean = false): Promise<boolean> {
    const currentBook = this.book;
    if (currentBook === null || resourceIndex < 0 || resourceIndex >= currentBook.chapters.length) return false;
    this.completeOnlineTextTurn(false);
    const serial = ++this.onlineTextLoadSerial;
    this.onlineTextLoading = true;
    this.jumpingResourceIndex = resourceIndex;
    try {
      const content = await this.getOnlineTextChapterContent(currentBook, resourceIndex, forceReload);
      if (this.leaving || serial !== this.onlineTextLoadSerial) return false;
      const hasCharOffset = charOffset > 0;
      charOffset = this.textDocuments.get(resourceIndex)?.toDisplay(charOffset) ?? charOffset;
      const pages = this.paginateOnlineTextContent(content);
      let nextPageIndex = 0;
      if (openLastPage) {
        nextPageIndex = Math.max(0, pages.length - 1);
      } else if (hasCharOffset) {
        nextPageIndex = OnlineTextPaginator.pageIndexForOffset(pages, charOffset);
      } else {
        nextPageIndex = Math.max(0, Math.min(pageOffset, pages.length - 1));
      }
      this.onlineTextContent = content;
      this.onlineTextPages = pages;
      this.onlineTextPageIndex = nextPageIndex;
      this.currentResourceIndex = resourceIndex;
      this.currentChapterTitle = this.chapterTitle(resourceIndex);
      this.loading = false;
      this.readerError = '';
      const offset = !openLastPage && hasCharOffset ? Math.min(charOffset, content.length) :
        pages[nextPageIndex].startOffset;
      this.updateOnlineTextPosition(true, offset);
      if (this.pageTurnMode === PageTurnMode.Vertical) this.continuousRevision++;
      this.prefetchAdjacentOnlineTextChapters(resourceIndex);
      return true;
    } catch (e) {
      if (this.leaving || serial !== this.onlineTextLoadSerial) return false;
      const message = e instanceof Error ? e.message : String(e);
      hilog.error(READER_LOG_DOMAIN, READER_LOG_TAG,
        'online chapter load failed: %{public}s', message);
      if (initialLoad) {
        this.failReader(message || '章节正文加载失败');
      } else {
        this.showToast(message || '章节正文加载失败');
      }
      return false;
    } finally {
      if (serial === this.onlineTextLoadSerial) {
        this.onlineTextLoading = false;
        this.jumpingResourceIndex = -1;
      }
    }
  }

  private async reloadCurrentChapter(): Promise<void> {
    const book = this.book;
    const context = this.context;
    if (!book || !context || this.reloadingChapter || this.onlineTextLoading) return;
    const index = this.currentResourceIndex;
    const chapter = book.chapters[index];
    if (!chapter) return;
    const offset = this.currentRawCharOffset();
    this.reloadingChapter = true;
    try {
      if (this.speechState.bookId === book.id) TextToSpeechService.getInstance().pause();
      this.completeOnlineTextTurn(false);
      // 等待同章预读落盘，再删除，防止旧请求覆盖重载结果。
      const pending = this.onlineTextContentRequests.get(index);
      if (pending) { try { await pending; } catch (_error) { /* retry below */ } }
      if (this.leaving) return;
      const key = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id,
        chapter.originSourceValue ?? chapter.source.value);
      ReaderPage.onlineTextContentCache.delete(key);
      await OnlineTextContentCache.removeChapter(context, key);
      if (!this.leaving) await this.loadOnlineTextChapter(index, offset, 0, false, this.readerError.length > 0, true);
    } catch (_error) {
      if (!this.leaving) this.getUIContext().getPromptAction().showToast({ message: $r('app.string.content_reload_failed') });
    } finally { this.reloadingChapter = false; }
  }

  private async switchSource(book: Book, index: number, matched: boolean, oldFavoriteId: string, replace: boolean): Promise<void> {
    const context = this.context;
    if (this.leaving || !this.showSourceSwitch || !context) return;
    const chapter = book.chapters[index];
    if (!chapter) return;
    const position = TextReadingPosition.atChar(book.id, index, '',
      matched ? this.currentRawCharOffset() : 0, 0, chapter.title);
    const chapterUrl = chapter.originSourceValue ?? chapter.source.value;
    const value = await BookSourceService.getTextChapterContent(book, chapterUrl, chapter.title, chapter.variables);
    const content = OnlineTextPaginator.normalizeContent(value.content);
    if (!content.trim()) throw new Error(context.resourceManager.getStringSync($r('app.string.source_switch_empty_content').id));
    if (this.leaving || !this.showSourceSwitch) return;
    const key = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id, chapterUrl);
    ReaderPage.onlineTextContentCache.set(key, content);
    await OnlineTextContentCache.write(context, key, content);
    position.charOffset = Math.min(position.charOffset, content.length);
    await DataService.upsertCachedBook(book);
    await TextReadingProgressService.save(context, position);
    if (this.leaving || !this.showSourceSwitch) return;
    if (this.speechState.bookId === this.book?.id) TextToSpeechService.getInstance().pause();
    this.saveProgress();
    SearchCache.put(book);
    if (oldFavoriteId) await PreferenceService.replaceFavoriteSource(oldFavoriteId, book.id, replace);
    this.showSourceSwitch = false;
    this.navStack.replacePath({ name: 'reader', param: TextReaderRouteParams.of(book.id) }, false);
  }

  @Builder
  private buildSourceSwitchSheet(): void {
    BookSourceSwitchSheet({ book: this.book, chapterTitle: this.currentChapterTitle, chapterIndex: this.currentResourceIndex,
      onSelect: async (book: Book, index: number, matched: boolean, oldFavoriteId: string, replace: boolean): Promise<void> => {
        await this.switchSource(book, index, matched, oldFavoriteId, replace);
      }
    })
  }

  @Builder
  private buildSourceActions(): void {
    Row({ space: 8 }) {
      ImmersiveCircleButton({ icon: $r('sys.symbol.chevron_left'),
        label: $r('app.string.comic_back'), onPress: (): void => { this.saveProgress(); this.navStack.pop(); } })
      Blank()
      if (this.book?.sourceUrl) {
        ImmersiveCircleButton({
          icon: $r('sys.symbol.arrow_clockwise'), iconSize: 20,
          label: $r('app.string.content_reload'),
          onPress: (): void => { this.reloadCurrentChapter(); }
        })
          .enabled(!this.reloadingChapter && !this.onlineTextLoading)
        ImmersiveCircleButton({
          icon: $r('sys.symbol.arrow_left_arrow_right'), iconSize: 24,
          label: $r('app.string.source_switch_title'),
          onPress: (): void => { this.showSourceSwitch = true; }
        })
          .enabled(!this.reloadingChapter && !this.onlineTextLoading)
          .bindSheet($$this.showSourceSwitch, this.buildSourceSwitchSheet(), {
            height: '82%', detents: ['82%', '45%', SheetSize.LARGE], dragBar: true, preferType: SheetType.BOTTOM, showClose: true,
            backgroundColor: AppMaterial.SheetBackground,
            blurStyle: AppMaterial.ReaderSheetBlur, systemMaterial: AppMaterial.ReaderSheetThick
          })
      }
      ImmersiveCircleButton({
        icon: $r('sys.symbol.info_circle'), iconSize: 24,
        label: $r('app.string.reader_details'),
        onPress: (): void => { this.openBookDetail(); }
      })
      ImmersiveCircleButton({
        icon: $r('sys.symbol.square_grid_2x2'), iconSize: 24,
        label: $r('app.string.reader_more'),
        onPress: (): void => { this.showReaderMenu = !this.showReaderMenu; }
      })
        .bindMenu(this.showReaderMenu, this.buildReaderMenu(), {
          placement: Placement.BottomLeft,
          onDisappear: (): void => { this.showReaderMenu = false; }
        })
    }.width('100%').justifyContent(FlexAlign.End)
      .padding({ left: this.leftSafeVp + 16, right: this.rightSafeVp + 12 })
      .hitTestBehavior(HitTestMode.Transparent)
      .position({ x: 0, y: this.topSafeVp + 4 })
  }

  @Builder
  private buildReaderMenu(): void {
    Menu() {
      MenuItem({ content: $r('app.string.reader_bookmark_add'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.bookmark')) })
        .enabled(!this.loading && !this.onlineTextLoading && !this.bookmarkBusy && !this.readerError)
        .onClick((): void => { this.showReaderMenu = false; this.addBookmark(); })
      MenuItem({ content: $r('app.string.reader_bookmarks'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.bookmark')) })
        .onClick((): void => { this.showReaderMenu = false; this.openBookmarks(); })
      if (this.isOnlineTextBook()) {
        MenuItem({ content: $r('app.string.reader_replace_rules'),
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_left_arrow_right')) })
          .enabled(!this.onlineTextLoading)
          .onClick((): void => { this.showReaderMenu = false; this.openReplaceRules(); })
      }
    }
  }

  private async addBookmark(): Promise<void> {
    const book = this.book;
    const context = this.context;
    const chapter = book?.chapters[this.currentResourceIndex];
    if (!book || !context || !chapter || this.bookmarkBusy || this.onlineTextLoading) return;
    const mark = new ReaderBookmark();
    mark.id = ReaderToolsService.newId(); mark.bookId = book.id;
    mark.chapterId = chapter.id; mark.chapterUrl = chapter.originSourceValue ?? chapter.source.value;
    mark.chapterTitle = chapter.title.substring(0, 1024); mark.resourceIndex = this.currentResourceIndex;
    mark.charOffset = this.currentRawCharOffset(); mark.domPos = this.currentPosition?.domPos ?? '';
    mark.preview = LocalTextImage.speechContent(this.onlineTextContent)
      .substring(this.currentOnlineTextCharOffset(), this.currentOnlineTextCharOffset() + 120).trim();
    mark.createdAt = Date.now();
    this.bookmarkBusy = true;
    try {
      await ReaderToolsService.addBookmark(context, mark);
      if (!this.leaving) this.showToast($r('app.string.reader_bookmark_saved'));
    } catch (_error) { if (!this.leaving) this.showToast($r('app.string.reader_tools_storage_error')); }
    finally { this.bookmarkBusy = false; }
  }

  private async openBookmarks(): Promise<void> {
    if (!this.context || !this.book) return;
    try {
      const marks = await ReaderToolsService.bookmarks(this.context, this.book.id);
      if (this.leaving) return;
      this.bookmarks = marks;
      this.hideReaderBar();
      this.showBookmarkSheet = true;
    } catch (_error) { this.showToast($r('app.string.reader_tools_storage_error')); }
  }

  private async jumpToBookmark(mark: ReaderBookmark): Promise<void> {
    const book = this.book;
    if (!book || mark.bookId !== book.id || this.onlineTextLoading) return;
    let index = book.chapters.findIndex((chapter): boolean =>
      (chapter.originSourceValue ?? chapter.source.value) === mark.chapterUrl);
    if (index < 0 && !mark.chapterUrl) index = book.chapters.findIndex((chapter): boolean => chapter.id === mark.chapterId);
    if (index < 0) { this.showToast($r('app.string.reader_bookmark_missing')); return; }
    if (this.speechState.bookId === book.id) TextToSpeechService.getInstance().pause();
    this.showBookmarkSheet = false;
    if (this.isOnlineTextBook()) await this.loadOnlineTextChapter(index, mark.charOffset, 0, false, false);
    else if (this.readerKitReady && this.readerKitController) {
      try { await this.readerKitController.startPlay(index, mark.domPos); }
      catch (_error) { this.showToast($r('app.string.reader_bookmark_missing')); }
    }
  }

  @Builder
  private buildBookmarkSheet(): void {
    ReaderBookmarkSheet({ bookmarks: this.bookmarks,
      onJump: (mark: ReaderBookmark): void => { this.jumpToBookmark(mark); },
      onDelete: async (mark: ReaderBookmark): Promise<void> => {
        if (!this.context) return;
        await ReaderToolsService.removeBookmark(this.context, mark.id);
        this.bookmarks = this.bookmarks.filter((item): boolean => item.id !== mark.id);
      }
    })
  }

  private async openReplaceRules(): Promise<void> {
    if (!this.book || !this.context || this.onlineTextLoading) return;
    const book = this.book;
    try {
      const raw = await this.getRawOnlineTextChapterContent(book, this.currentResourceIndex);
      if (this.leaving) return;
      this.replaceSample = raw.substring(0, 32000);
    } catch (_error) { this.replaceSample = ''; }
    if (this.leaving) return;
    if (this.speechState.bookId === book.id) TextToSpeechService.getInstance().pause();
    this.hideReaderBar();
    this.showReplaceSheet = true;
  }

  @Builder
  private buildReplaceSheet(): void {
    ReaderReplaceSheet({ bookId: this.bookId, sample: this.replaceSample,
      onChanged: async (): Promise<void> => {
        if (this.leaving) return;
        const offset = this.currentRawCharOffset();
        if (this.speechState.bookId === this.bookId) TextToSpeechService.getInstance().stop();
        this.completeOnlineTextTurn(false);
        this.textRulesGeneration++;
        this.textDocuments.clear();
        await this.loadOnlineTextChapter(this.currentResourceIndex, offset, 0, false, this.readerError.length > 0);
      }
    })
  }

  private async getOnlineTextChapterContent(book: Book, resourceIndex: number, forceReload: boolean = false): Promise<string> {
    const generation = this.textRulesGeneration;
    const raw = await this.getRawOnlineTextChapterContent(book, resourceIndex, forceReload);
    const document = this.context ? await ReaderToolsService.render(this.context, book.id, raw) : ReaderTextDocument.original(raw);
    if (generation !== this.textRulesGeneration) return this.getOnlineTextChapterContent(book, resourceIndex);
    this.textDocuments.set(resourceIndex, document);
    if (this.textDocuments.size > 8) {
      for (const key of this.textDocuments.keys()) {
        if (key !== this.currentResourceIndex && key !== resourceIndex) { this.textDocuments.delete(key); break; }
      }
    }
    if (document.failed && resourceIndex === this.jumpingResourceIndex) this.showToast($r('app.string.reader_replace_failed'));
    return document.content;
  }

  private async getRawOnlineTextChapterContent(book: Book, resourceIndex: number, forceReload: boolean = false): Promise<string> {
    const chapter = book.chapters[resourceIndex];
    if (chapter === undefined) throw new Error('章节索引无效');
    const chapterUrl = chapter.originSourceValue ?? chapter.source.value;
    const cacheKey = OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id, chapterUrl);
    if (this.context && !this.leaving && book.sourceUrl) {
      const keys: string[] = [cacheKey];
      for (const index of [this.currentResourceIndex - 1, this.currentResourceIndex, this.currentResourceIndex + 1]) {
        const nearby = book.chapters[index];
        if (nearby) keys.push(OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id,
          nearby.originSourceValue ?? nearby.source.value));
      }
      OnlineTextContentCache.protect(this.context, this.diskCacheOwner, keys);
    }
    const cached = ReaderPage.onlineTextContentCache.get(cacheKey);
    if (!forceReload && cached !== undefined) {
      ReaderPage.onlineTextContentCache.delete(cacheKey);
      ReaderPage.onlineTextContentCache.set(cacheKey, cached);
      hilog.info(READER_LOG_DOMAIN, READER_LOG_TAG, 'reuse cached text content: %{public}s chapter %{public}d',
        book.title, resourceIndex);
      return cached;
    }
    const pending = this.onlineTextContentRequests.get(resourceIndex);
    if (pending !== undefined) return pending;
    const request = this.readOrFetchOnlineTextContent(book, chapter, chapterUrl, cacheKey, forceReload);
    this.onlineTextContentRequests.set(resourceIndex, request);
    try {
      const content = await request;
      // LRU 淘汰：缓存超限时移除最早的
      if (ReaderPage.onlineTextContentCache.size >= ReaderPage.MAX_TEXT_CONTENT_CACHE_SIZE) {
        for (const firstKey of ReaderPage.onlineTextContentCache.keys()) {
          ReaderPage.onlineTextContentCache.delete(firstKey);
          break;
        }
        hilog.info(READER_LOG_DOMAIN, READER_LOG_TAG, 'evict oldest text content from cache');
      }
      ReaderPage.onlineTextContentCache.set(cacheKey, content);
      hilog.info(READER_LOG_DOMAIN, READER_LOG_TAG, 'cached text content: %{public}s chapter %{public}d',
        book.title, resourceIndex);
      return content;
    } finally {
      this.onlineTextContentRequests.delete(resourceIndex);
    }
  }

  private async readOrFetchOnlineTextContent(book: Book, chapter: Chapter,
    chapterUrl: string, cacheKey: string, forceReload: boolean = false): Promise<string> {
    const context = this.context;
    if (!forceReload && context !== null) {
      const saved = await OnlineTextContentCache.read(context, cacheKey);
      if (saved !== undefined) return saved;
    }
    const value = await BookSourceService.getTextChapterContent(book, chapterUrl, chapter.title, chapter.variables);
    const content = OnlineTextPaginator.normalizeContent(value.content);
    if (context !== null) await OnlineTextContentCache.write(context, cacheKey, content);
    return content;
  }

  private paginateOnlineTextContent(content: string): OnlineTextPage[] {
    const density = this.getUIContext().vp2px(1);
    const fontSizePx = this.getUIContext().fp2px(this.fontSize);
    const viewportWidthVp = this.readerViewportWidthVp > 0 ?
      this.readerViewportWidthVp : WindowUtils.getWindowWidthVp();
    const viewportHeightVp = this.readerViewportHeightVp > 0 ?
      this.readerViewportHeightVp : WindowUtils.getWindowHeightVp();
    const contentWidthVp = this.readerTextWidthVp > 0 ? this.readerTextWidthVp :
      Math.max(80, viewportWidthVp - this.readerLeftPadding() - this.readerRightPadding());
    const reservedHeightVp = this.readerTopInsetVp() + this.readerTextBottomPaddingVp() +
      Math.max(0, this.marginTop - 12) + this.readerHeaderHeight() +
      this.readerFooterHeight() + READER_TEXT_LAYOUT_GUARD;
    const contentHeightVp = this.readerTextHeightVp > 0 ?
      Math.max(1, this.readerTextHeightVp - READER_TEXT_LAYOUT_GUARD) :
      Math.max(80, viewportHeightVp - reservedHeightVp);
    return OnlineTextPaginator.paginate(content, contentWidthVp * density,
      contentHeightVp * density, fontSizePx, this.lineHeight, this.fontFamily, this.fontWeight, this.textAlignment, this.paragraphSpacing);
  }

  private currentOnlineTextCharOffset(): number {
    if (this.currentPosition !== null && this.currentPosition.resourceIndex === this.currentResourceIndex) {
      return this.currentPosition.charOffset;
    }
    const page = this.onlineTextPages[this.onlineTextPageIndex];
    if (page !== undefined) return page.startOffset;
    const position = this.currentPosition;
    return position !== null ? position.charOffset : 0;
  }

  private currentRawCharOffset(): number {
    const offset = this.currentOnlineTextCharOffset();
    return this.textDocuments.get(this.currentResourceIndex)?.toRaw(offset) ?? offset;
  }

  private persistedPosition(): TextReadingPosition | null {
    const position = this.currentPosition;
    if (!position) return null;
    return TextReadingPosition.atChar(position.bookId, position.resourceIndex, position.domPos,
      this.isOnlineTextBook() ? this.currentRawCharOffset() : position.charOffset,
      position.pageOffset, position.chapterTitle);
  }

  private handleReaderTextSizeChange(size: SizeOptions): void {
    if (typeof size.width !== 'number' || typeof size.height !== 'number' ||
      size.width <= 0 || size.height <= 0) return;
    if (Math.abs(this.readerTextWidthVp - size.width) < 0.5 &&
      Math.abs(this.readerTextHeightVp - size.height) < 0.5) return;
    this.readerTextWidthVp = size.width;
    this.readerTextHeightVp = size.height;
    this.scheduleReaderSettingsRefresh();
  }

  private repaginateOnlineText(): void {
    this.completeOnlineTextTurn(this.onlineTextTurnConfirmed);
    if (!this.isOnlineTextBook() || this.onlineTextContent.length === 0) return;
    const charOffset = this.currentOnlineTextCharOffset();
    const pages = this.paginateOnlineTextContent(this.onlineTextContent);
    this.onlineTextPages = pages;
    this.onlineTextPageIndex = OnlineTextPaginator.pageIndexForOffset(pages, charOffset);
    // 窗口/安全区变化只改变分页；保留已确认字符，避免恢复视口后逐次回退。
    this.updateOnlineTextPosition(false, charOffset);
    if (this.pageTurnMode === PageTurnMode.Vertical) this.continuousRevision++;
  }

  private updateContinuousPosition(chapterIndex: number, offset: number, content: string, persist: boolean): void {
    if (this.leaving || this.onlineTextLoading || this.book === null) return;
    if (chapterIndex !== this.currentResourceIndex || this.onlineTextContent !== content) {
      this.currentResourceIndex = chapterIndex;
      this.currentChapterTitle = this.chapterTitle(chapterIndex);
      this.onlineTextContent = content;
      this.onlineTextPages = this.paginateOnlineTextContent(content);
    }
    this.onlineTextPageIndex = OnlineTextPaginator.pageIndexForOffset(this.onlineTextPages, offset);
    this.currentPosition = TextReadingPosition.atChar(this.book.id, chapterIndex, '', offset,
      this.onlineTextPageIndex, this.currentChapterTitle);
    if (persist) this.saveProgress();
  }

  private updateOnlineTextPosition(persist: boolean, charOffset: number = -1): void {
    const currentBook = this.book;
    const page = this.onlineTextPages[this.onlineTextPageIndex];
    if (currentBook === null || page === undefined) return;
    this.currentPosition = TextReadingPosition.atChar(
      currentBook.id, this.currentResourceIndex, '',
      charOffset >= 0 ? Math.min(charOffset, this.onlineTextContent.length) : page.startOffset,
      this.onlineTextPageIndex, this.currentChapterTitle);
    if (persist) this.saveProgress();
  }

  private prefetchAdjacentOnlineTextChapters(resourceIndex: number): void {
    const currentBook = this.book;
    if (currentBook === null || !this.isOnlineTextBook()) return;
    const previousIndex = resourceIndex - 1;
    const nextIndex = resourceIndex + 1;
    if (previousIndex >= 0) {
      this.getOnlineTextChapterContent(currentBook, previousIndex).catch((error: Error): void => {
        hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG,
          'previous chapter preload failed: %{public}s', error.message);
      });
    }
    if (nextIndex < currentBook.chapters.length) {
      this.getOnlineTextChapterContent(currentBook, nextIndex).catch((error: Error): void => {
        hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG,
          'next chapter preload failed: %{public}s', error.message);
      });
    }
  }

  private async prepareReaderKitReader(book: Book, startPosition: TextReadingPosition): Promise<void> {
    this.readerKitReady = false;
    if (!PlatformCompat.readerKit) {
      this.failReader(this.getUIContext().getHostContext()?.resourceManager.getStringSync(
        $r('app.string.reader_kit_unavailable').id) ?? '');
      return;
    }
    // HSP 依赖必须放在动态模块边界之后；import lazy 仍会链接其共享模块。
    const epubModule = await import('../components/EpubReaderComponent');
    if (this.leaving) return;
    this.readerKitController = epubModule.createEpubReaderController();
    this.epubReaderBuilder = epubModule.createEpubReaderBuilder();
    this.readerKitHandler = await this.createReaderKitHandler(book);
    const count = Math.max(1, book.chapters.length);
    const resourceIndex = this.clampResourceIndex(startPosition.resourceIndex, count);
    this.readerSetting = this.createReaderSetting();
    this.currentResourceIndex = resourceIndex;
    this.readerKitDomPos = startPosition.domPos;
    this.readerKitPageOffset = startPosition.pageOffset;
    this.currentChapterTitle = this.chapterTitle(resourceIndex);
    this.currentPosition = TextReadingPosition.atChar(
      book.id, resourceIndex, this.readerKitDomPos, 0, this.readerKitPageOffset, this.currentChapterTitle);
    this.loading = false;
  }

  private async createReaderKitHandler(book: Book): Promise<bookParser.BookParserHandler> {
    const epubPath = this.resolveEpubFilePath(book);
    if (epubPath.length === 0) {
      throw new Error('电子书文件路径为空');
    }
    // 先查缓存
    const cached = ReaderPage.epubHandlerCache.get(epubPath);
    if (cached) {
      hilog.info(READER_LOG_DOMAIN, READER_LOG_TAG, 'reuse cached epub handler: %{public}s',
        epubPath.substring(epubPath.lastIndexOf('/') + 1));
      return cached;
    }
    // 缓存未命中，解析并缓存
    const parserModule = await import('../service/text/EpubParserService');
    const handler = await parserModule.EpubParserService.open(epubPath);
    // LRU 淘汰：缓存超限时移除最早的
    if (ReaderPage.epubHandlerCache.size >= ReaderPage.MAX_HANDLER_CACHE_SIZE) {
      const firstKey = ReaderPage.epubHandlerCache.keys().next().value as string;
      ReaderPage.epubHandlerCache.delete(firstKey);
      hilog.info(READER_LOG_DOMAIN, READER_LOG_TAG, 'evict oldest handler from cache');
    }
    ReaderPage.epubHandlerCache.set(epubPath, handler);
    hilog.info(READER_LOG_DOMAIN, READER_LOG_TAG, 'cached new epub handler: %{public}s',
      epubPath.substring(epubPath.lastIndexOf('/') + 1));
    return handler;
  }

  private resolveEpubFilePath(book: Book): string {
    const variables = book.variables;
    if (variables !== undefined) {
      const filePath = variables['filePath'];
      if (filePath !== undefined && filePath.length > 0) return this.normalizeFilePath(filePath);
      const epubPath = variables['epubPath'];
      if (epubPath !== undefined && epubPath.length > 0) return this.normalizeFilePath(epubPath);
    }
    if (book.bookUrl.startsWith('/') || book.bookUrl.startsWith('file://')) {
      return this.normalizeFilePath(book.bookUrl);
    }
    if (book.sourceUrl.startsWith('/') || book.sourceUrl.startsWith('file://')) {
      return this.normalizeFilePath(book.sourceUrl);
    }
    return '';
  }

  private normalizeFilePath(path: string): string {
    if (path.startsWith('file://')) return path.substring(7);
    return path;
  }

  private retryReader(): void {
    this.initializeReader();
  }

  @Monitor('speechState.charOffset', 'speechState.chapterIndex', 'speechState.playing')
  private syncSpeechPosition(): void {
    const speech = this.speechState;
    if (!this.readerVisible || this.leaving || this.loading || !this.book || !speech.active ||
      speech.bookId !== this.bookId || speech.loading || !this.isOnlineTextBook()) return;
    this.readingTime.checkpoint(this.book, !speech.playing && this.readingForeground);
    if (speech.chapterIndex !== this.currentResourceIndex) {
      if (!this.onlineTextLoading) this.loadOnlineTextChapter(speech.chapterIndex,
        TextToSpeechService.getInstance().currentRawOffset(), 0, false, false);
      return;
    }
    this.onlineTextPageIndex = OnlineTextPaginator.pageIndexForOffset(this.onlineTextPages, speech.charOffset);
    this.updateOnlineTextPosition(false, speech.charOffset);
    if (this.pageTurnMode === PageTurnMode.Vertical) this.continuousRevision++;
  }

  private saveProgress(): void {
    this.readingTime.checkpoint(this.book, this.readerVisible && this.readingForeground && !this.leaving &&
      !this.loading && !this.onlineTextLoading && !this.speechState.playing);
    if (!this.context || !this.currentPosition) return;
    if (this.speechState.active && this.speechState.bookId === this.bookId &&
      (this.speechState.playing || !this.readerVisible)) return;
    const position = this.persistedPosition();
    if (!position) return;
    if (this.book && !this.loading && !TextToSpeechService.getInstance().state.playing) {
      const location = SessionLocation.text(this.book, position);
      location.total = this.textDocuments.get(this.currentResourceIndex)?.rawLength ?? this.onlineTextContent.length;
      ReadingSessionService.checkpoint('reading', location,
        this.readerVisible && this.readingForeground && !this.leaving);
    }
    const context = this.context;
    const book = this.book;
    TextReadingProgressService.save(context, position).then((): void => {
      if (book) ReaderWidgetService.update(context, book, position);
    }).catch((_e: Error): void => {});
  }

  private async restoreReadingSettings(): Promise<void> {
    const currentContext = this.context;
    if (currentContext === null) return;
    try {
      const settings = await TextReadingSettingsService.get(currentContext);
      this.followSystemTheme = settings.followSystemTheme;
      this.marginLeft = settings.marginLeft;
      this.marginRight = settings.marginRight;
      this.marginTop = settings.marginTop;
      this.marginBottom = settings.marginBottom;
      this.textAlignment = settings.textAlignment;
      this.fontWeight = settings.fontWeight;
      this.fontColor = settings.fontColor;
      this.fontPath = settings.fontPath;
      this.fontName = settings.fontName;
      this.importedFonts = await ReaderFontService.list(currentContext, this.fontPath, this.fontName);
      this.screenOnMinutes = settings.screenOnMinutes;
      this.screenOn.configure(this.screenOnMinutes);
      this.fontFamily = '';
      if (this.fontPath.length > 0) {
        try { this.fontFamily = ReaderFontService.register(currentContext, this.fontPath); }
        catch (_e) { this.fontPath = ''; this.fontName = ''; this.fontFamily = ''; }
      }
      this.fontSize = settings.fontSize;
      this.lineHeight = settings.lineHeight;
      this.paragraphSpacing = settings.paragraphSpacing;
      this.themeId = settings.themeId;
      this.customBackground = settings.customBackground;
      this.customThemes = settings.customThemes;
      this.customThemeIndex = settings.customThemeIndex;
      this.imageBackground = settings.imageBackground;
      this.imageFontColor = settings.imageFontColor;
      this.backgroundPattern = settings.pattern;
      this.bgImagePath = settings.backgroundImage;
      this.backgroundImageMode = settings.backgroundImageMode;
      if (this.bgImagePath.length > 0 && !await fileIo.access(this.bgImagePath)) {
        this.bgImagePath = '';
        this.backgroundPattern = ReaderPattern.None;
        if (this.themeId === ReaderThemeId.Image) this.themeId = TextReadingSettings.THEME_DEFAULT;
      }
      this.overlayAlpha = settings.overlayAlpha;
      this.tapLeftPercent = settings.tapLeftPercent;
      this.tapRightPercent = settings.tapRightPercent;
      this.tapTopPercent = settings.tapTopPercent;
      this.tapBottomPercent = settings.tapBottomPercent;
      this.showChapterBar = settings.showChapterBar;
      this.showBrightnessBar = settings.showBrightnessBar;
      this.readingBrightness = settings.brightness;
      this.brightnessControl.configure(this.readingBrightness);
      this.showHeader = settings.showHeader;
      this.cornerLayout = settings.cornerLayout;
      this.showFooter = settings.showFooter;
      this.showChapterTitle = settings.showChapterTitle;
      this.showPageNumber = settings.showPageNumber;
      this.showChapterNumber = settings.showChapterNumber;
      this.showBookName = settings.showBookName;
      this.tapRegions = settings.tapRegions;
      this.volumeKeyPageTurn = settings.volumeKeyPageTurn;
      this.pageTurnMode = settings.pageTurnMode;
      this.showReadingStatus = settings.showReadingStatus;
      this.alwaysShowStatusBar = settings.alwaysShowStatusBar;
      this.syncReaderStatusBar();
      this.updateMarginTopMax();
      this.refreshPalette();
    } catch (e) {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'restore settings failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      this.applyDefaultReadingSettings();
    }
  }

  /** 读盘失败或用户点「恢复默认」时回到出厂配置 */
  private applyDefaultReadingSettings(): void {
    this.followSystemTheme = false;
    this.marginLeft = 16;
    this.marginRight = 16;
    this.marginTop = 12;
    this.marginBottom = 12;
    this.textAlignment = 'justify';
    this.previewFontSize = 0; this.previewLineHeight = 0; this.previewParagraphSpacing = -1; this.previewFontWeight = 0;
    this.fontWeight = 400;
    this.fontColor = '';
    this.fontFamily = '';
    this.fontPath = '';
    this.fontName = '';
    this.screenOnMinutes = 0;
    this.screenOn.configure(0);
    this.fontSize = TextReadingSettings.FONT_SIZE_DEFAULT;
    this.lineHeight = TextReadingSettings.LINE_HEIGHT_DEFAULT;
    this.paragraphSpacing = TextReadingSettings.PARAGRAPH_SPACING_DEFAULT;
    this.themeId = TextReadingSettings.THEME_DEFAULT;
    this.customBackground = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
    this.customThemes = ReaderCustomTheme.defaults();
    this.customThemeIndex = 0;
    this.imageBackground = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
    this.imageFontColor = '';
    this.backgroundPattern = ReaderPattern.None;
    this.bgImagePath = '';
    this.backgroundImageMode = ReaderImageMode.Cover;
    this.overlayAlpha = TextReadingSettings.OVERLAY_DEFAULT;
    this.tapLeftPercent = 33;
    this.tapRightPercent = 33;
    this.tapTopPercent = 33;
    this.tapBottomPercent = 33;
    this.showChapterBar = true;
    this.showBrightnessBar = true;
    this.readingBrightness = -1;
    this.brightnessControl.configure(-1);
    this.showHeader = true;
    this.cornerLayout = ReaderCornerLayout.DEFAULT;
    this.showFooter = true;
    this.showChapterTitle = true;
    this.showPageNumber = true;
    this.showChapterNumber = true;
    this.showBookName = true;
    this.tapRegions = ReaderTapPolicy.DEFAULT;
    this.volumeKeyPageTurn = false;
    this.pageTurnMode = TextReadingSettings.PAGE_TURN_MODE_DEFAULT;
    this.showReadingStatus = TextReadingSettings.SHOW_READING_STATUS_DEFAULT;
    this.alwaysShowStatusBar = TextReadingSettings.ALWAYS_SHOW_STATUS_BAR_DEFAULT;
    this.syncReaderStatusBar();
    this.refreshPalette();
  }

  /** themeId / customBackground 变了就重算配色，并同步状态栏字色 */
  private refreshPalette(): void {
    // WindowUtils 由 EntryAbility.onConfigurationUpdate / 设置页同步，应用「跟随系统」时正确反映系统深浅色。
    const systemDark = WindowUtils.isDarkMode();
    this.systemNightOverride = this.followSystemTheme && systemDark;
    // 系统夜间只覆盖显示，不改写用户保存的图片、蒙层和白天主题。
    this.effectiveThemeId = resolveEffectiveThemeId(this.themeId, this.followSystemTheme, systemDark);
    this.palette = resolvePalette(this.effectiveThemeId, this.customBackground, this.fontColor,
      this.imageBackground, this.imageFontColor);
    // 深色底配白字状态栏，浅色底配黑字
    WindowUtils.setReaderStatusBarLight(this.palette.isDark).catch((_e: Error): void => {});
  }

  private saveReadingSettings(): void {
    const currentContext = this.context;
    if (currentContext === null) return;
    const settings = TextReadingSettings.ofAll(this.fontSize, this.lineHeight, this.themeId,
      this.customBackground, this.backgroundPattern, this.bgImagePath, this.overlayAlpha, this.pageTurnMode, this.showReadingStatus);
    settings.paragraphSpacing = this.paragraphSpacing;
    settings.textAlignment = this.textAlignment;
    settings.fontWeight = this.fontWeight;
    settings.fontColor = this.fontColor;
    settings.customThemes = this.customThemes;
    settings.customThemeIndex = this.customThemeIndex;
    settings.imageBackground = this.imageBackground;
    settings.imageFontColor = this.imageFontColor;
    settings.backgroundImageMode = this.backgroundImageMode;
    settings.fontPath = this.fontPath;
    settings.fontName = this.fontName;
    settings.screenOnMinutes = this.screenOnMinutes;
    settings.followSystemTheme = this.followSystemTheme;
    settings.alwaysShowStatusBar = this.alwaysShowStatusBar;
    settings.volumeKeyPageTurn = this.volumeKeyPageTurn;
    settings.tapRegions = this.tapRegions;
    settings.tapLeftPercent = this.tapLeftPercent;
    settings.tapRightPercent = this.tapRightPercent;
    settings.tapTopPercent = this.tapTopPercent;
    settings.tapBottomPercent = this.tapBottomPercent;
    settings.showChapterBar = this.showChapterBar;
    settings.showBrightnessBar = this.showBrightnessBar;
    settings.brightness = this.readingBrightness;
    settings.showHeader = this.showHeader;
    settings.cornerLayout = this.cornerLayout;
    settings.showFooter = this.showFooter;
    settings.showChapterTitle = this.showChapterTitle;
    settings.showPageNumber = this.showPageNumber;
    settings.showChapterNumber = this.showChapterNumber;
    settings.showBookName = this.showBookName;

    settings.marginLeft = this.marginLeft;
    settings.marginRight = this.marginRight;
    settings.marginTop = this.marginTop;
    settings.marginBottom = this.marginBottom;
    TextReadingSettingsService.save(currentContext, settings).catch((e: Error): void => {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'save settings failed: %{public}s', e.message);
    });
  }

  private createReaderSetting(): readerCore.ReaderSetting {
    const density = this.getUIContext().vp2px(1);
    const scaledDensity = this.getUIContext().fp2px(1);
    const widthVp = this.readerViewportWidthVp > 0 ? this.readerViewportWidthVp : WindowUtils.getWindowWidthVp();
    const heightVp = this.readerViewportHeightVp > 0 ? this.readerViewportHeightVp : WindowUtils.getWindowHeightVp();
    const verticalSafePx = (this.readerTopInsetVp() + this.readerTextBottomPaddingVp() +
      this.readerFooterHeight() + Math.max(0, this.marginTop - 12)) * density;
    const pageConfig: readerCore.ReaderSetting = {
      fontName: this.fontName || this.fontFamily,
      fontSize: TextReadingSettings.normalizeFontSize(this.fontSize),
      fontWeight: this.fontWeight,
      fontColor: this.palette.primary,
      fontPath: this.fontPath,
      lineHeight: TextReadingSettings.normalizeLineHeight(this.lineHeight),
      nightMode: this.palette.isDark,
      themeColor: this.palette.background,
      // ReaderKit 自己渲染排版，背景图使用它要求的沙箱文件路径
      themeBgImg: !this.systemNightOverride && this.backgroundPattern === ReaderPattern.Image ? this.bgImagePath : '',
      flipMode: '0',
      scaledDensity: scaledDensity,
      viewPortWidth: Math.max(1, (widthVp - this.readerLeftPadding() - this.readerRightPadding()) * density),
      viewPortHeight: Math.max(1, heightVp * density - verticalSafePx)
    };
    return pageConfig;
  }

  private applyReadingSettings(reflow: boolean = true): void {
    try {
      if (this.isOnlineTextBook()) {
        if (reflow) this.repaginateOnlineText();
        return;
      }
      const pageConfig = this.createReaderSetting();
      this.readerSetting = pageConfig;
      if (!this.readerKitReady) return;
      this.readerKitController?.setPageConfig(pageConfig);
    } catch (e) {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'apply settings failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  /** 拖动仅更新面板预览；松手一次性提交正文排版，避免每个 Slider 事件阻塞 UI。 */
  private handleFontSizeChange(value: number, commit: boolean): void {
    this.previewFontSize = TextReadingSettings.normalizeFontSize(value);
    if (!commit) return;
    this.fontSize = this.previewFontSize;
    this.previewFontSize = 0;
    this.cancelReaderSettingsRefresh();
    this.applyReadingSettings();
    this.saveReadingSettings();
  }

  private handleParagraphSpacingChange(value: number, commit: boolean): void {
    this.previewParagraphSpacing = TextReadingSettings.normalizeParagraphSpacing(value);
    if (!commit) return;
    this.paragraphSpacing = this.previewParagraphSpacing;
    this.previewParagraphSpacing = -1;
    this.cancelReaderSettingsRefresh();
    this.applyReadingSettings();
    this.saveReadingSettings();
  }

  private handleLineHeightChange(value: number, commit: boolean): void {
    this.previewLineHeight = TextReadingSettings.normalizeLineHeight(value);
    if (!commit) return;
    this.lineHeight = this.previewLineHeight;
    this.previewLineHeight = 0;
    this.cancelReaderSettingsRefresh();
    this.applyReadingSettings();
    this.saveReadingSettings();
  }

  private disableSystemTheme(): void {
    if (!this.followSystemTheme) return;
    this.followSystemTheme = false;
    this.showToast($r('app.string.reader_follow_system_disabled'));
  }

  private handleCustomThemeSelect(slot: number): void {
    this.customThemeIndex = ReaderCustomTheme.normalizeSlot(slot);
    const theme = this.customThemes[this.customThemeIndex];
    this.customBackground = theme.background;
    this.fontColor = theme.fontColor;
    this.handleThemeChange(ReaderThemeId.Custom);
  }

  private handleCustomThemeSave(slot: number, background: string, fontColor: string): void {
    const selectedSlot = ReaderCustomTheme.normalizeSlot(slot);
    this.customThemes = this.customThemes.map((theme: ReaderCustomTheme): ReaderCustomTheme =>
      theme.slot === selectedSlot ? ReaderCustomTheme.of(selectedSlot, background, fontColor) : theme);
    this.handleCustomThemeSelect(selectedSlot);
  }

  private handleImageTextChange(light: boolean): void {
    this.imageFontColor = light ? '#F5F2EA' : '#2D2925';
    this.imageBackground = light ? '#1C1F22' : TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
    this.handleThemeChange(ReaderThemeId.Image);
  }

  private handleThemeChange(themeId: string): void {
    if (themeId === ReaderThemeId.Image && this.bgImagePath.length === 0) {
      this.pickBackgroundImage();
      return;
    }
    this.disableSystemTheme();
    this.themeId = TextReadingSettings.normalizeThemeId(themeId);
    this.backgroundPattern = this.themeId === ReaderThemeId.Image ? ReaderPattern.Image : ReaderPattern.None;
    this.refreshPalette();
    this.applyReadingSettings(false);
    this.saveReadingSettings();
  }

  private handleOverlayChange(value: number, commit: boolean): void {
    this.overlayAlpha = TextReadingSettings.normalizeOverlay(value);
    if (commit) this.saveReadingSettings();
  }

  private handlePageTurnModeChange(mode: string): void {
    this.completeOnlineTextTurn(this.onlineTextTurnConfirmed);
    const offset = this.currentOnlineTextCharOffset();
    this.pageTurnMode = TextReadingSettings.normalizePageTurnMode(mode);
    this.onlineTextPageIndex = OnlineTextPaginator.pageIndexForOffset(this.onlineTextPages, offset);
    this.updateOnlineTextPosition(true, offset);
    this.saveReadingSettings();
  }

  private handleResetDefaults(): void {
    this.applyDefaultReadingSettings();
    this.applyReadingSettings();
    this.saveReadingSettings();
  }

  /**
   * 相册选图 → 复制进沙箱 files/reader_bg。
   * 相册 uri 是临时授权，重启后失效，所以必须落本地副本再引用。
   */
  private selectReaderFont(font: ReaderImportedFont): void {
    if (this.context === null) return;
    try {
      const family = font.path.length > 0 ? ReaderFontService.register(this.context, font.path) : '';
      this.fontPath = font.path; this.fontName = font.name; this.fontFamily = family;
      this.applyReadingSettings(); this.saveReadingSettings();
    } catch (_e) { this.showToast($r('app.string.reader_font_unavailable')); }
  }

  private async deleteReaderFont(font: ReaderImportedFont): Promise<void> {
    if (this.context === null || this.pickingFont) return;
    this.pickingFont = true;
    try {
      this.importedFonts = await ReaderFontService.remove(this.context, font.path);
      if (this.fontPath === font.path) this.selectReaderFont(new ReaderImportedFont());
    } catch (_e) { this.showToast($r('app.string.reader_font_delete_failed')); }
    finally { this.pickingFont = false; }
  }

  private async pickReaderFont(): Promise<void> {
    if (this.context === null || this.pickingFont) return;
    this.pickingFont = true;
    try {
      const result = await ReaderFontService.pick(this.context);
      if (this.leaving) return;
      this.importedFonts = await ReaderFontService.list(this.context);
      if (result.fonts.length > 0) this.selectReaderFont(result.fonts[result.fonts.length - 1]);
      if (result.failures.length > 0) this.showToast($r('app.string.reader_font_partial', result.fonts.length, result.failures.length));
    } catch (_e) {
      this.showToast($r('app.string.reader_import_font_failed'));
    } finally { this.pickingFont = false; }
  }

  private async pickBackgroundImage(): Promise<void> {
    const currentContext = this.context;
    if (currentContext === null || this.pickingBackgroundImage) return;
    this.pickingBackgroundImage = true;
    let destination: string = '';
    let applied: boolean = false;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (result.photoUris.length === 0 || this.leaving) return;
      const dir = `${currentContext.filesDir}/reader_bg`;
      if (!await fileIo.access(dir)) await fileIo.mkdir(dir, true);
      destination = `${dir}/bg_${Date.now()}.jpg`;
      const src = await fileIo.open(result.photoUris[0], fileIo.OpenMode.READ_ONLY);
      try {
        await fileIo.copyFile(src.fd, destination);
      } finally {
        await fileIo.close(src);
      }
      // 验证图片可解码后再替换当前主题；取消或失败保留原图与原设置。
      const imageSource = image.createImageSource(destination);
      try {
        await imageSource.getImageInfo();
      } finally {
        await imageSource.release();
      }
      if (this.leaving) return;
      const previous = this.bgImagePath;
      this.bgImagePath = destination;
      this.disableSystemTheme();
      this.themeId = ReaderThemeId.Image;
      this.backgroundPattern = ReaderPattern.Image;
      this.refreshPalette();
      this.applyReadingSettings(false);
      const settings = TextReadingSettings.ofAll(this.fontSize, this.lineHeight, this.themeId,
        this.customBackground, this.backgroundPattern, this.bgImagePath, this.overlayAlpha, this.pageTurnMode, this.showReadingStatus);
      settings.backgroundImageMode = this.backgroundImageMode;
      settings.paragraphSpacing = this.paragraphSpacing;
      settings.textAlignment = this.textAlignment;
      settings.fontWeight = this.fontWeight;
      settings.fontColor = this.fontColor;
    settings.customThemes = this.customThemes;
    settings.customThemeIndex = this.customThemeIndex;
    settings.imageBackground = this.imageBackground;
    settings.imageFontColor = this.imageFontColor;
      settings.fontPath = this.fontPath;
      settings.fontName = this.fontName;
      settings.screenOnMinutes = this.screenOnMinutes;
      settings.followSystemTheme = this.followSystemTheme;
      settings.alwaysShowStatusBar = this.alwaysShowStatusBar;
      settings.volumeKeyPageTurn = this.volumeKeyPageTurn;
      settings.tapRegions = this.tapRegions;
    settings.tapLeftPercent = this.tapLeftPercent;
    settings.tapRightPercent = this.tapRightPercent;
    settings.tapTopPercent = this.tapTopPercent;
    settings.tapBottomPercent = this.tapBottomPercent;
    settings.showChapterBar = this.showChapterBar;
    settings.showBrightnessBar = this.showBrightnessBar;
    settings.brightness = this.readingBrightness;
    settings.showHeader = this.showHeader;
    settings.cornerLayout = this.cornerLayout;
    settings.showFooter = this.showFooter;
    settings.showChapterTitle = this.showChapterTitle;
    settings.showPageNumber = this.showPageNumber;
    settings.showChapterNumber = this.showChapterNumber;
    settings.showBookName = this.showBookName;

      settings.marginLeft = this.marginLeft;
      settings.marginRight = this.marginRight;
      settings.marginTop = this.marginTop;
      settings.marginBottom = this.marginBottom;
      applied = true;
      await TextReadingSettingsService.save(currentContext, settings);
      // 新路径持久化成功后才删除上一张，避免重启仍引用已删文件。
      if (previous.length > 0 && previous !== destination) {
        fileIo.unlink(previous).catch((_e: Error): void => {});
      }
    } catch (e) {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'pick background failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      this.showToast($r('app.string.reader_image_apply_failed'));
    } finally {
      this.pickingBackgroundImage = false;
      if (!applied && destination.length > 0) {
        fileIo.unlink(destination).catch((_e: Error): void => {});
      }
    }
  }

  private handleReaderKitReady(): void {
    this.readerKitReady = true;
    this.applyReadingSettings();
    this.loading = false;
    this.readerError = '';
    this.hideReaderBar();
  }

  private handleReaderKitError(message: string, code: number): void {
    this.readerKitReady = false;
    const suffix = code > 0 ? ` (${code})` : '';
    this.failReader(`${message}${suffix}`);
  }

  private handleReaderKitPageShow(info: readerCore.PageDataInfo): void {
    const currentBook = this.book;
    if (currentBook === null) return;
    const keepReaderBar = info.resourceIndex === this.readerBarChapterTarget && info.pageOffset === 0;
    if (!keepReaderBar && !this.showChapterSheet && !this.showSettingsSheet &&
      (info.resourceIndex !== this.currentResourceIndex || info.startDomPos !== this.readerKitDomPos ||
        info.pageOffset !== this.readerKitPageOffset)) {
      this.hideReaderBar();
    }
    const count = Math.max(1, currentBook.chapters.length);
    const resourceIndex = this.clampResourceIndex(info.resourceIndex, count);
    const title = this.chapterTitle(resourceIndex);
    this.currentResourceIndex = resourceIndex;
    this.readerKitDomPos = info.startDomPos;
    this.readerKitPageOffset = info.pageOffset;
    if (title.length > 0) {
      this.currentChapterTitle = title;
    }
    this.currentPosition = TextReadingPosition.atChar(
      currentBook.id, resourceIndex, this.readerKitDomPos, 0, this.readerKitPageOffset, this.currentChapterTitle);
    this.saveProgress();
  }

  private failReader(message: string): void {
    this.readerKitReady = false;
    this.onlineTextLoading = false;
    this.jumpingResourceIndex = -1;
    this.readerError = message || '暂时无法打开这本电子书';
    this.loading = false;
  }

  private chapterTitle(index: number): string {
    if (!this.book) return '';
    const chapter = this.book.chapters[index];
    return chapter ? chapter.title : '';
  }

  private chapterIndexByTitle(book: Book, title: string): number {
    if (!title) return -1;
    for (let i = 0; i < book.chapters.length; i++) {
      if (book.chapters[i].title === title) return i;
    }
    return -1;
  }

  private clampResourceIndex(index: number, count: number): number {
    if (count <= 0) return 0;
    return Math.max(0, Math.min(index, count - 1));
  }

  private chapterResourceIndex(chapter: Chapter): number {
    const currentBook = this.book;
    if (currentBook === null) return -1;
    return DataService.resolveChapterIndex(currentBook, chapter.id, chapter.title);
  }

  private chapterStableKey(chapter: Chapter): string {
    if (chapter.id.length > 0) return chapter.id;
    const originSourceValue = chapter.originSourceValue;
    if (originSourceValue !== undefined && originSourceValue.length > 0) return originSourceValue;
    if (chapter.source.value.length > 0) return chapter.source.value;
    return chapter.title;
  }

  private isCurrentChapter(chapter: Chapter): boolean {
    return this.chapterResourceIndex(chapter) === this.currentResourceIndex;
  }

  private async selectChapter(chapter: Chapter): Promise<void> {
    const resourceIndex = this.chapterResourceIndex(chapter);
    if (resourceIndex < 0) return;
    await this.jumpToResourceIndex(resourceIndex);
  }

  /** 跳到指定章节：EPUB 走 ReaderKit，在线文本走分页加载。 */
  private async jumpToResourceIndex(resourceIndex: number, keepReaderBar: boolean = false): Promise<void> {
    if (this.jumpingResourceIndex >= 0) return;
    const currentBook = this.book;
    if (currentBook === null) return;
    if (resourceIndex < 0 || resourceIndex >= currentBook.chapters.length) return;
    this.showChapterSheet = false;
    if (!keepReaderBar) this.hideReaderBar();
    if (this.isOnlineTextBook()) {
      await this.loadOnlineTextChapter(resourceIndex, 0, 0, false, false);
      return;
    }
    if (!this.readerKitReady || this.readerKitController === null) return;
    // ReaderKit 的首屏回调可能晚于 startPlay 返回；底栏切章期间不按普通翻页收栏。
    this.readerBarChapterTarget = keepReaderBar ? resourceIndex : -1;
    this.jumpingResourceIndex = resourceIndex;
    try {
      await this.readerKitController.startPlay(resourceIndex, '');
      this.currentResourceIndex = resourceIndex;
      this.currentChapterTitle = this.chapterTitle(resourceIndex);
      this.readerKitDomPos = '';
      this.readerKitPageOffset = 0;
      this.currentPosition = TextReadingPosition.atChar(
        currentBook.id, resourceIndex, '', 0, 0, this.currentChapterTitle);
      this.saveProgress();
    } catch (e) {
      this.readerBarChapterTarget = -1;
      hilog.error(READER_LOG_DOMAIN, READER_LOG_TAG, 'chapter jump failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    } finally {
      this.jumpingResourceIndex = -1;
    }
  }

  /** 详情页选中章节返回阅读页时触发；未指定章节时保持原进度。 */
  private onJumpChapterEvent(e: emitter.EventData): void {
    const data = e.data as ReaderJumpChapterEvent | undefined;
    if (data === undefined || data === null) return;
    if (this.leaving || data.bookId !== this.bookId) return;
    this.showChapterSheet = false;
    this.showSettingsSheet = false;
    this.showSpeechSheet = false;
    if (data.resourceIndex >= 0) {
      if (data.charOffset >= 0 && this.isOnlineTextBook()) {
        this.loadOnlineTextChapter(data.resourceIndex, data.charOffset, 0, false, false);
      } else {
        this.jumpToResourceIndex(data.resourceIndex);
      }
    }
  }

  private async prepareOnlineTextTurn(forward: boolean): Promise<boolean> {
    if (this.onlineTextLoading || this.leaving) return false;
    const currentBook = this.book;
    if (currentBook === null) return false;
    // 只收起覆盖正文的工具栏，正文视口和系统栏始终保持不变。
    this.hideReaderBar();
    const displayIndex = PreferenceService.chapterDisplayIndex(currentBook, this.currentResourceIndex);
    const target: OnlineTextNavigationTarget = forward ? OnlineTextPageNavigator.next(
      displayIndex, this.onlineTextPageIndex,
      this.onlineTextPages.length, currentBook.chapters.length) :
      OnlineTextPageNavigator.previous(displayIndex, this.onlineTextPageIndex);
    target.chapterIndex = PreferenceService.chapterDisplayIndex(currentBook, target.chapterIndex);
    if (!target.moved) {
      this.showToast(forward ? $r('app.string.reader_last_page') : $r('app.string.reader_first_page'));
      return false;
    }
    const ticket = ++this.onlineTextTurnSerial;
    const preview = new ReaderOnlineTextTurnPreview();
    preview.chapterIndex = target.chapterIndex;
    preview.content = this.onlineTextContent;
    preview.pages = this.onlineTextPages;
    try {
      if (target.chapterIndex !== this.currentResourceIndex) {
        this.onlineTextTurnLoading = true;
        this.onlineTextLoading = true;
        this.jumpingResourceIndex = target.chapterIndex;
        preview.content = await this.getOnlineTextChapterContent(currentBook, target.chapterIndex);
        if (this.leaving || ticket !== this.onlineTextTurnSerial) return false;
        preview.pages = this.paginateOnlineTextContent(preview.content);
      }
      if (this.leaving || ticket !== this.onlineTextTurnSerial) return false;
      preview.pageIndex = target.openLastPage ? Math.max(0, preview.pages.length - 1) : target.pageIndex;
      this.onlineTextTurnPreview = preview;
      return true;
    } catch (e) {
      if (!this.leaving && ticket === this.onlineTextTurnSerial) {
        this.showToast(e instanceof Error ? e.message : String(e));
      }
      return false;
    } finally {
      if (ticket === this.onlineTextTurnSerial) {
        this.onlineTextTurnLoading = false;
        this.onlineTextLoading = false;
        this.jumpingResourceIndex = -1;
      }
    }
  }

  private completeOnlineTextTurn(commit: boolean): void {
    const preview = this.onlineTextTurnPreview;
    this.onlineTextTurnConfirmed = false;
    this.onlineTextTurnSerial++;
    this.onlineTextTurnPreview = null;
    if (this.onlineTextTurnLoading) {
      this.onlineTextTurnLoading = false;
      this.onlineTextLoading = false;
      this.jumpingResourceIndex = -1;
    }
    if (commit && preview !== null && !this.leaving) {
      this.onlineTextContent = preview.content;
      this.onlineTextPages = preview.pages;
      this.onlineTextPageIndex = preview.pageIndex;
      this.currentResourceIndex = preview.chapterIndex;
      this.currentChapterTitle = this.chapterTitle(preview.chapterIndex);
      this.updateOnlineTextPosition(true);
      this.prefetchAdjacentOnlineTextChapters(preview.chapterIndex);
    }
  }

  private currentOnlineTextPageLayout(): OnlineTextPage {
    const preview = this.onlineTextTurnPreview;
    return (preview !== null ? preview.pages[preview.pageIndex] :
      this.onlineTextPages[this.onlineTextPageIndex]) ?? new OnlineTextPage();
  }

  private currentOnlineTextPageContent(): string {
    const preview = this.onlineTextTurnPreview;
    const page = preview !== null ? preview.pages[preview.pageIndex] :
      this.onlineTextPages[this.onlineTextPageIndex];
    return page !== undefined ? page.text : '';
  }

  private currentOnlineTextPageSource(): string {
    const page = this.onlineTextPages[this.onlineTextPageIndex];
    return page !== undefined ? this.onlineTextContent.substring(page.startOffset, page.endOffset) : '';
  }

  private onlineTextPageLabel(): string {
    const preview = this.onlineTextTurnPreview;
    const total = Math.max(1, preview !== null ? preview.pages.length : this.onlineTextPages.length);
    const index = preview !== null ? preview.pageIndex : this.onlineTextPageIndex;
    return `${Math.min(index + 1, total)}/${total}`;
  }

  private onlineTextChapterIndex(): number {
    const preview = this.onlineTextTurnPreview;
    return preview !== null ? preview.chapterIndex : this.currentResourceIndex;
  }

  private onlineTextTurnRevision(): string {
    return `${this.currentResourceIndex}:${this.onlineTextPageIndex}:${this.fontSize}:${this.lineHeight}:${this.paragraphSpacing}:` +
      `${this.cornerLayout}:${this.showChapterTitle}:${this.showPageNumber}:${this.showChapterNumber}:${this.showBookName}:${this.showReadingStatus}:` +
      `${this.textAlignment}:${this.fontFamily}:${this.systemTypographyRevision}:${this.fontWeight}:${this.fontColor}:${this.themeId}:${this.customBackground}:${this.backgroundPattern}:${this.bgImagePath}:${this.backgroundImageMode}:${this.overlayAlpha}:` +
      `${this.readerHeaderHeight()}:${this.readerFooterHeight()}:${this.readerTopInsetVp()}:${this.leftSafeVp}:${this.rightSafeVp}:${this.topSafeVp}:${this.readerBottomInsetVp()}:${this.marginLeft}:${this.marginRight}:${this.marginTop}:${this.marginBottom}:${this.palette.background}:${this.palette.primary}`;
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_e) {
      // 页面退出过程中提示能力可能已经释放。
    }
  }

  private canUseVolumeKeys(): boolean {
    return this.volumeKeyPageTurn && this.canTurnWithKeyboard();
  }

  private canTurnWithKeyboard(): boolean {
    return this.readerVisible && !this.leaving && !this.loading &&
      this.readerError.length === 0 && !this.showChapterSheet && !this.showSettingsSheet &&
      !this.showSpeechSheet && !this.showSourceSwitch && !this.showBookmarkSheet && !this.showReplaceSheet && !this.showReaderMenu && !this.pickingFont && !this.pickingBackgroundImage;
  }

  @Monitor('volumeKeyPageTurn', 'readerVisible', 'loading', 'readerError', 'showChapterSheet',
    'showSettingsSheet', 'showSpeechSheet', 'showSourceSwitch', 'showBookmarkSheet', 'showReplaceSheet', 'showReaderMenu', 'pickingFont', 'pickingBackgroundImage')
  syncVolumeKeys(): void {
    this.volumeKeys.setEnabled(this.canUseVolumeKeys(), (forward: boolean): void => this.handleVolumePageTurn(forward));
  }

  private handleVolumePageTurn(forward: boolean): void {
    if (!this.canUseVolumeKeys()) return;
    this.turnPageFromKey(forward);
  }

  private handleReaderKey(event: KeyEvent): void {
    if (event.type !== KeyType.Down || !this.canTurnWithKeyboard() || this.readerBarVisible) return;
    const forward = event.keyCode === KeyCode.KEYCODE_PAGE_DOWN || event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT;
    const backward = event.keyCode === KeyCode.KEYCODE_PAGE_UP || event.keyCode === KeyCode.KEYCODE_DPAD_LEFT;
    if (!forward && !backward) return;
    this.turnPageFromKey(forward);
    event.stopPropagation();
  }

  private turnPageFromKey(forward: boolean): void {
    this.screenOn.touch();
    if (this.isOnlineTextBook()) {
      this.keyTurnRequest = (Math.abs(this.keyTurnRequest) + 1) * (forward ? 1 : -1);
    } else if (this.readerKitReady) {
      try { this.readerKitController?.flipPage(forward); } catch (_error) {}
    }
  }

  @Builder
  readerTabStyle(icon: Resource, label: Resource) {
    Column() {
      SymbolGlyph(icon).fontSize(24).fontColor([$r('sys.color.font_primary')])
        .accessibilityText(label)
    }.width('100%').height(48).justifyContent(FlexAlign.Center)
  }

  private adjacentChapterIndex(forward: boolean): number {
    return this.currentResourceIndex + (forward ? 1 : -1);
  }

  private canSwitchChapter(forward: boolean): boolean {
    const target = this.adjacentChapterIndex(forward);
    return !this.chapterSliderConfirming && this.book !== null && !this.loading && !this.onlineTextLoading &&
      !this.reloadingChapter && this.jumpingResourceIndex < 0 && !this.leaving &&
      (this.isOnlineTextBook() || this.readerKitReady) && target >= 0 && target < this.book.chapters.length;
  }

  private chapterSliderIndex(): number {
    if (this.chapterSliderPreview >= 0) return this.chapterSliderPreview;
    return this.chapterSliderPosition(this.currentResourceIndex);
  }

  /** 滑条按目录显示顺序定位；上下章按钮独立按正文顺序前进。 */
  private chapterSliderPosition(index: number): number {
    return this.book !== null ? PreferenceService.chapterDisplayIndex(this.book, index) : index;
  }

  private async changeChapterSlider(value: number, mode: SliderChangeMode): Promise<void> {
    if (this.chapterSliderConfirming || this.book === null) return;
    this.chapterSliderPreview = Math.max(0, Math.min(Math.round(value), this.book.chapters.length - 1));
    this.chapterSliderDragging = mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving;
    if (mode !== SliderChangeMode.End && mode !== SliderChangeMode.Click) return;
    const target = this.chapterSliderPosition(this.chapterSliderPreview);
    if (target === this.currentResourceIndex) {
      this.chapterSliderPreview = -1;
      return;
    }
    this.chapterSliderConfirming = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.reader_chapter_jump_title'),
        message: $r('app.string.reader_chapter_jump_message', this.chapterTitle(target)),
        buttons: [
          { text: $r('app.string.common_cancel'), color: this.palette.secondary },
          { text: $r('app.string.reader_chapter_jump_action'), color: AppColor.Brand }
        ]
      });
      if (result.index === 1 && !this.leaving && this.readerBarVisible) {
        await this.jumpToResourceIndex(target, true);
      }
    } catch (error) {
      hilog.warn(READER_LOG_DOMAIN, READER_LOG_TAG, 'chapter slider: %{public}s', String(error));
    } finally {
      this.chapterSliderPreview = -1;
      this.chapterSliderDragging = false;
      this.chapterSliderConfirming = false;
    }
  }

  private chapterBarFloatingStyle(): HdsTabsFloatingStyle | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    const width = this.readerControlWidthVp();
    return {
      barWidth: { smallWidth: width, mediumWidth: width, largeWidth: width },
      barSideMargin: 0,
      barBottomMargin: 0,
      gradientMask: { maskColor: Color.Transparent, maskHeight: 44 },
      systemMaterialEffect: HdsCompat.adaptiveMaterial,
      adaptToHandedness: false
    };
  }

  @Builder
  buildChapterBarContent(): void {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([$r('sys.color.font_primary')])
      }.width(44).height(44).justifyContent(FlexAlign.Center)
        .accessibilityText($r('app.string.reader_previous_chapter'))
        .opacity(this.canSwitchChapter(false) ? 1 : 0.35).enabled(this.canSwitchChapter(false))
        .onClick((): void => { this.jumpToResourceIndex(this.adjacentChapterIndex(false), true); })
      Slider({ value: this.chapterSliderIndex(), min: 0,
        max: Math.max(1, (this.book?.chapters.length ?? 0) - 1), step: 1, style: SliderStyle.OutSet })
        .layoutWeight(1).height(44).trackThickness(6).blockSize({ width: 16, height: 16 })
        .selectedColor(AppColor.Brand).trackColor($r('sys.color.comp_divider')).blockColor($r('sys.color.font_primary'))
        .showSteps(false).enabled(this.canSwitchChapter(false) || this.canSwitchChapter(true))
        .accessibilityText($r('app.string.reader_chapters'))
        .onChange((value: number, mode: SliderChangeMode): void => { this.changeChapterSlider(value, mode); })
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Cancel && !this.chapterSliderConfirming) {
            this.chapterSliderPreview = -1;
            this.chapterSliderDragging = false;
          }
        })
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(20).fontColor([$r('sys.color.font_primary')])
      }.width(44).height(44).justifyContent(FlexAlign.Center)
        .accessibilityText($r('app.string.reader_next_chapter'))
        .opacity(this.canSwitchChapter(true) ? 1 : 0.35).enabled(this.canSwitchChapter(true))
        .onClick((): void => { this.jumpToResourceIndex(this.adjacentChapterIndex(true), true); })
    }.width(Math.max(1, (this.readerViewportWidthVp - this.leftSafeVp - this.rightSafeVp) * 0.84))
      .height(44).padding({ left: 4, right: 4 })
  }

  @Builder
  chapterMaterialContent() {
    Row().width('100%').height(44)
  }

  @Builder
  buildReaderChapterBar(): void {
    Stack({ alignContent: Alignment.Center }) {
      if (PlatformCompat.floatingTabs) {
        HdsTabs() {
          TabContent() {}.tabBar(this.chapterMaterialContent())
        }.width(this.readerControlWidthVp()).height(44).barPosition(BarPosition.End).barMode(BarMode.Fixed)
          .barHeight(44).barOverlap(true).scrollable(false)
          .attributeModifier(new CompatibleTabsModifier(this.chapterBarFloatingStyle(), 44))
          .barBackgroundColor(Color.Transparent)
          .backgroundColor(Color.Transparent).borderRadius(22, RenderStrategy.OFFSCREEN).clip(true)
          .onContentWillChange((): boolean => false).hitTestBehavior(HitTestMode.None)
      } else {
        Row() {}
          .width(this.readerControlWidthVp()).height(44).borderRadius(22).backgroundColor($r('sys.color.comp_background_primary'))
          .padding({ left: this.leftSafeVp + 12, right: this.rightSafeVp + 12 })
      }
      this.buildChapterBarContent()
      if (this.chapterSliderDragging) {
        Column({ space: 2 }) {
          Text(this.chapterTitle(this.chapterSliderPosition(this.chapterSliderIndex())))
            .fontSize(AppFont.Caption).fontColor(Color.White).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.chapterSliderIndex() + 1}/${this.book?.chapters.length ?? 0}`)
            .fontSize(AppFont.Caption).fontColor('#CCFFFFFF')
        }.width('80%').height(44).padding({ left: 14, right: 14 }).borderRadius(22)
          .justifyContent(FlexAlign.Center).backgroundColor(this.palette.isDark ? '#E63A3C40' : '#D94B4D52')
          .translate({ y: -52 }).hitTestBehavior(HitTestMode.None)
      }
    }.width('100%').height(44)
      .margin({ bottom: READER_BAR_HEIGHT + Math.max(this.bottomSafeVp, READER_MIN_SAFE_BOTTOM) + 8 })
  }

  /** 横屏隐藏状态栏时仍保护页眉两端，挖孔避让不包含另一侧的屏幕圆角。 */
  private readerTopInsetVp(): number {
    if (this.alwaysShowStatusBar) return this.topSafeVp;
    const landscape = this.readerViewportWidthVp > this.readerViewportHeightVp &&
      this.readerViewportHeightVp > 0;
    return Math.max(this.cutoutTopSafeVp, landscape ? READER_LANDSCAPE_TOP_GAP : 0);
  }

  private readerHeaderHeight(): number {
    return this.showHeader && (this.cornerVisible(0) || this.cornerVisible(1)) ? READER_TEXT_HEADER_HEIGHT : 0;
  }

  private cornerVisible(corner: number): boolean {
    switch (ReaderCornerLayout.content(this.cornerLayout, corner)) {
      case ReaderCornerContent.ChapterTitle: return this.showChapterTitle;
      case ReaderCornerContent.PageNumber: return this.showPageNumber;
      case ReaderCornerContent.ChapterNumber: return this.showChapterNumber;
      default: return this.showBookName;
    }
  }

  private cornerText(corner: number): string {
    switch (ReaderCornerLayout.content(this.cornerLayout, corner)) {
      case ReaderCornerContent.ChapterTitle: return this.chapterTitle(this.onlineTextChapterIndex());
      case ReaderCornerContent.PageNumber:
        return this.pageTurnMode === PageTurnMode.Vertical ?
          `${Math.round(this.currentOnlineTextCharOffset() / Math.max(1, this.onlineTextContent.length) * 100)}%` :
          this.onlineTextPageLabel();
      case ReaderCornerContent.ChapterNumber:
        return this.book !== null ? `${this.onlineTextChapterIndex() + 1}/${this.book.chapters.length}` : '';
      default: return this.book?.title ?? '';
    }
  }

  private readerGutter(): number {
    const width = this.readerViewportWidthVp > 0 ? this.readerViewportWidthVp : WindowUtils.getWindowWidthVp();
    return AdaptiveLayout.readerGutter(width, this.marginLeft + this.leftSafeVp, this.marginRight + this.rightSafeVp);
  }

  private readerLeftPadding(): number {
    return this.marginLeft + this.leftSafeVp + this.readerGutter();
  }

  private readerRightPadding(): number {
    return this.marginRight + this.rightSafeVp + this.readerGutter();
  }

  private readerFooterHeight(): number {
    return this.showFooter && (this.cornerVisible(2) || this.cornerVisible(3) || this.showReadingStatus) ? READER_TEXT_FOOTER_HEIGHT : 0;
  }

  private readerTextBottomPaddingVp(): number {
    const inset = this.readerBottomInsetVp();
    // 所有阅读模式的下边距同时容纳手势留白，避免在页脚下重复叠加。
    // 实体导航栏仍完整避让，并在栏上方保留用户设置的边距。
    if (WindowUtils.getSystemBottomVp() <= 0) {
      return Math.max(inset, this.marginBottom);
    }
    return inset + this.marginBottom;
  }

  private readerBottomInsetVp(): number {
    if (WindowUtils.getSystemBottomVp() > 0) return this.bottomSafeVp;
    return Math.max(READER_MIN_SAFE_BOTTOM, Math.min(this.bottomSafeVp, READER_GESTURE_SAFE_MAX));
  }

  private readerControlWidthVp(): number {
    return Math.max(1, (this.readerViewportWidthVp - this.leftSafeVp - this.rightSafeVp) * 0.84);
  }

  private readerFloatingStyle(): HdsTabsFloatingStyle | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    const width = Math.max(1, this.readerControlWidthVp() - (this.isOnlineTextBook() ? 48 + 8 : 0));
    return {
      barWidth: { smallWidth: width, mediumWidth: width, largeWidth: width },
      barSideMargin: 0,
      barBottomMargin: 0,
      gradientMask: { maskColor: Color.Transparent, maskHeight: 0 },
      systemMaterialEffect: HdsCompat.adaptiveMaterial,
      lightColor: AppColor.Brand,
      adaptToHandedness: this.generalSettings.adaptiveHandedness
    };
  }

  @Builder
  buildReaderTabs(): void {
    // HdsTabs 保持稳定布局，显隐只作用于外层，避免浮动栏布局与属性动画互相干扰。
    Stack({ alignContent: Alignment.Bottom }) {
      Row({ space: 8 }) {
        Stack() {
          HdsTabs() {
            TabContent() {}.tabBar(this.readerTabStyle($r('sys.symbol.list_bullet'), $r('app.string.reader_chapters')))
            TabContent() {}.tabBar(this.readerTabStyle($r('sys.symbol.gearshape'), $r('app.string.reader_settings')))
            TabContent() {}.tabBar(this.readerTabStyle($r('sys.symbol.textformat'), $r('app.string.reader_font_tab')))
          }
          .width('100%').height(READER_BAR_HEIGHT)
          .barOverlap(true)
          .barMode(BarMode.Fixed)
          .barPosition(BarPosition.End)
          .scrollable(false)
          .attributeModifier(new CompatibleTabsModifier(this.readerFloatingStyle(), READER_BAR_HEIGHT))
          .barBackgroundColor(PlatformCompat.floatingTabs ? Color.Transparent : $r('sys.color.comp_background_primary'))
          .backgroundColor(Color.Transparent)
          .onTabBarClick((index: number): void => this.handleReaderTabClick(index))
          .onContentWillChange((): boolean => false)
        }.layoutWeight(1).height(READER_BAR_HEIGHT).attributeModifier(new ReaderControlClip())
        if (this.isOnlineTextBook()) {
          ReaderSpeechFloating({ playing: this.speechState.playing && this.speechState.bookId === this.bookId,
            onOpen: (): void => { this.openSpeechPlayer(); } })
        }
      }.width(this.readerControlWidthVp()).height(READER_BAR_HEIGHT)
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: Math.max(this.bottomSafeVp, READER_MIN_SAFE_BOTTOM) + READER_FLOATING_BOTTOM })
      if (this.showChapterBar) { this.buildReaderChapterBar() }
    }
    .width('100%')
    .height(READER_BAR_MASK_HEIGHT + this.bottomSafeVp + READER_FLOATING_BOTTOM + 104)
    .animation(null)
    .translate({ y: this.readerBarVisible ? 0 : 24 })
    .opacity(this.readerBarVisible ? 1 : 0)
    .animation({ duration: 180, curve: curves.cubicBezierCurve(0.2, 0, 0, 1) })
    .hitTestBehavior(this.readerBarVisible ? HitTestMode.Transparent : HitTestMode.None)
    .animation(null)
    .visibility(this.readerBarVisible ? Visibility.Visible : Visibility.Hidden)
    .enabled(this.readerBarVisible)
  }

  private toggleReaderBar(): void {
    if (this.showChapterSheet || this.showSettingsSheet || this.showSpeechSheet || this.showSourceSwitch ||
      this.showBookmarkSheet || this.showReplaceSheet || this.showReaderMenu) return;
    if (this.readerBarVisible) {
      this.hideReaderBar();
    } else {
      this.showReaderBar();
    }
  }

  private hideReaderBar(): void {
    this.chapterSliderPreview = -1;
    this.chapterSliderDragging = false;
    this.readerBarChapterTarget = -1;
    this.readerBarVisible = false;
    this.syncReaderStatusBar();
  }

  private showReaderBar(): void {
    if (!this.leaving) {
      this.readerBarVisible = true;
      this.syncReaderStatusBar();
    }
  }

  private syncReaderStatusBar(): void {
    WindowUtils.setReaderStatusBarVisible(this.alwaysShowStatusBar || this.readerBarVisible || this.showChapterSheet);
  }

  private openBookDetail(): void {
    const currentBook = this.book;
    if (currentBook === null) {
      this.showToast($r('app.string.reader_detail_unavailable'));
      return;
    }
    this.showChapterSheet = false;
    this.showSettingsSheet = false;
    this.hideReaderBar();
    SearchCache.put(currentBook);
    // 阅读页保留在栈内：详情页选章节后可返回原阅读页并跳转；防连点重复入栈。
    const names = this.navStack.getAllPathName();
    if (names.length > 0 && names[names.length - 1] === 'detail' &&
      this.navStack.getParamByIndex(names.length - 1) === currentBook.id) {
      return;
    }
    this.navStack.pushPathByName('detail', currentBook.id);
  }

  private openChapterSheet(): void {
    const currentBook = this.book;
    if (currentBook === null || currentBook.chapters.length === 0) {
      this.showToast($r('app.string.reader_no_chapters'));
      return;
    }
    this.showSettingsSheet = false;
    this.chapterListOffsetFromCurrent = 0;
    this.chapterQuery = '';
    this.chapterDescending = currentBook.chaptersDescending ?? false;
    this.chapterDataSource.setChapters(PreferenceService.orderedChapters(currentBook));
    this.showChapterSheet = true;
    this.hideReaderBar();
    this.scrollChapterListToCurrent();
  }

  private closeChapterSheet(): void {
    this.chapterPositionGeneration++;
    this.showChapterSheet = false;
    this.showReaderBar();
  }

  private openSettingsSheet(fontPanel: boolean = false): void {
    this.fontPanel = fontPanel;
    this.showChapterSheet = false;
    this.hideReaderBar();
    this.showSettingsSheet = true;
  }

  private closeSettingsSheet(): void {
    this.saveReadingSettings();
    this.showSettingsSheet = false;
    this.showReaderBar();
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

  private filterReaderChapters(query: string): void {
    this.chapterPositionGeneration++;
    this.chapterQuery = query;
    const keyword = query.trim().toLowerCase();
    const chapters = this.book ? PreferenceService.orderedChapters(this.book) : [];
    this.chapterDataSource.setChapters(chapters.filter((chapter: Chapter): boolean =>
      chapter.title.toLowerCase().includes(keyword)));
    if (!this.chapterSegmented) this.chapterListScroller.scrollToIndex(0, false);
  }

  private chapterPositionGeneration: number = 0;

  private scrollChapterListToCurrent(): void {
    if (this.chapterSegmented) return;
    if (this.chapterQuery.length > 0) this.filterReaderChapters('');
    const generation = ++this.chapterPositionGeneration;
    const currentBook = this.book;
    if (currentBook === null || currentBook.chapters.length === 0) return;
    const index = PreferenceService.chapterDisplayIndex(currentBook,
      this.clampResourceIndex(this.currentResourceIndex, currentBook.chapters.length));
    setTimeout((): void => {
      if (generation !== this.chapterPositionGeneration || this.chapterSegmented || !this.showChapterSheet) return;
      try {
        this.chapterListScroller.scrollToIndex(index, false, ScrollAlign.CENTER);
      } catch (_e) {
        return;
      }
      setTimeout((): void => {
        if (generation !== this.chapterPositionGeneration || this.chapterSegmented || !this.showChapterSheet) return;
        try {
          this.chapterListScroller.scrollToIndex(index, false, ScrollAlign.CENTER);
        } catch (_e) {
          // 弹层关闭或列表释放时无需继续定位。
        }
      }, 150);
    }, 50);
  }

  private jumpToCurrentChapter(): void {
    this.scrollChapterListToCurrent();
    this.chapterListOffsetFromCurrent = 0;
  }

  private shouldShowChapterJumpButton(): boolean {
    return !this.chapterSegmented && Math.abs(this.chapterListOffsetFromCurrent) > READER_CHAPTER_JUMP_DISTANCE;
  }

  private handleReaderTabClick(index: number): void {
    if (index === 0) {
      this.openChapterSheet();
    } else if (index === 1) {
      this.openSettingsSheet();
    } else if (index === 2) {
      this.openSettingsSheet(true);
    }
  }

  private async openSpeechSheet(): Promise<void> {
    if (!this.isOnlineTextBook() || this.context === null || this.book === null) return;
    this.showChapterSheet = false;
    this.showSettingsSheet = false;
    const speech = TextToSpeechService.getInstance();
    try {
      await speech.initialize(this.context);
      if (this.leaving) return;
      this.hideReaderBar();
      this.showSpeechSheet = true;
      speech.refreshVoices();
    } catch (_error) { this.showToast($r('app.string.tts_engine_error')); }
  }

  private async openSpeechPlayer(preservePaused: boolean = false): Promise<void> {
    const book = this.book;
    if (!this.isOnlineTextBook() || this.context === null || book === null ||
      this.onlineTextLoading || this.openingSpeechPlayer) return;
    this.openingSpeechPlayer = true;
    try {
      const speech = TextToSpeechService.getInstance();
      await speech.initialize(this.context);
      if (this.leaving) return;
      this.saveProgress();
      this.hideReaderBar();
      SearchCache.put(book);
      if (speech.state.active && speech.state.bookId === book.id) {
        if (!preservePaused && !speech.state.playing && !speech.state.loading) speech.resume();
      } else {
        speech.start(book, this.currentResourceIndex, this.currentRawCharOffset());
      }
      this.navStack.pushPathByName('player', book.id);
    } catch (_error) {
      this.showToast($r('app.string.tts_engine_error'));
    } finally {
      this.openingSpeechPlayer = false;
    }
  }

  @Builder
  private buildSpeechSheet(): void {
    ReaderSpeechSheet({ state: this.speechState,
      onClose: (): void => { this.showSpeechSheet = false; }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column().width(0).height(0)
        .bindSheet($$this.showBookmarkSheet, this.buildBookmarkSheet(), {
          height: '82%', detents: ['82%', '45%', SheetSize.LARGE], dragBar: true, preferType: SheetType.BOTTOM, showClose: true,
          backgroundColor: AppMaterial.SheetBackground,
          blurStyle: AppMaterial.ReaderSheetBlur, systemMaterial: AppMaterial.ReaderSheetThick,
          onDisappear: (): void => { this.showBookmarkSheet = false; if (!this.leaving) this.showReaderBar(); }
        })
      Column().width(0).height(0)
        .bindSheet($$this.showReplaceSheet, this.buildReplaceSheet(), {
          height: '90%', detents: ['90%', '45%', SheetSize.LARGE], dragBar: true, preferType: SheetType.BOTTOM, showClose: true,
          backgroundColor: AppMaterial.SheetBackground,
          blurStyle: AppMaterial.ReaderSheetBlur, systemMaterial: AppMaterial.ReaderSheetThick,
          onDisappear: (): void => { this.showReplaceSheet = false; if (!this.leaving) this.showReaderBar(); }
        })
      // 背景层最底：预设底色或自定义图片与蒙层
      ReaderBackground({
        palette: this.palette,
        pattern: this.systemNightOverride ? ReaderPattern.None : this.backgroundPattern,
        bgImagePath: this.bgImagePath,
        imageMode: this.isOnlineTextBook() ? this.backgroundImageMode : ReaderImageMode.Cover,
        overlayAlpha: this.overlayAlpha
      })
        // 每个弹层使用独立宿主；同一节点连续 bindSheet 会覆盖前一个绑定。
        .bindSheet($$this.showSpeechSheet, this.buildSpeechSheet(), {
          height: '82%', detents: ['82%', '45%', SheetSize.LARGE], dragBar: true, preferType: SheetType.BOTTOM, showClose: false,
          backgroundColor: AppMaterial.SheetBackground,
          maskColor: Color.Transparent,
          blurStyle: AppMaterial.ReaderSheetBlur,
          systemMaterial: AppMaterial.ReaderSheetThick,
          onDisappear: (): void => {
            this.showSpeechSheet = false;
            if (!this.leaving) this.showReaderBar();
          }
        })

      if (!this.loading && !this.readerError) {
        Stack({ alignContent: Alignment.Bottom }) {
            Stack({ alignContent: Alignment.Bottom }) {
              if (this.isOnlineTextBook()) {
                this.buildOnlineTextReader()
              } else if (this.epubReaderBuilder !== null && this.readerKitController !== null) {
                Stack() {
                  this.epubReaderBuilder.builder({
                    controller: this.readerKitController,
                    handler: this.readerKitHandler,
                    tapRegions: this.tapRegions,
                    tapLeftPercent: this.tapLeftPercent,
                    tapRightPercent: this.tapRightPercent,
                    tapTopPercent: this.tapTopPercent,
                    tapBottomPercent: this.tapBottomPercent,
                    startResourceIndex: this.currentResourceIndex,
                    startDomPos: this.readerKitDomPos,
                    pageConfig: this.readerSetting,
                    onReady: (): void => this.handleReaderKitReady(),
                    onError: (message: string, code: number): void => this.handleReaderKitError(message, code),
                    onReaderPageShow: (info: readerCore.PageDataInfo): void => this.handleReaderKitPageShow(info),
                    onContentTap: (): void => this.toggleReaderBar()
                  })
                }
                  .width('100%')
                  .height('100%')
                  .padding({
                    left: this.readerLeftPadding(), right: this.readerRightPadding(),
                    top: this.readerTopInsetVp() + Math.max(0, this.marginTop - 12),
                    bottom: this.readerTextBottomPaddingVp() + this.readerFooterHeight()
                  })
                if (this.showFooter && this.showReadingStatus) {
                  ReaderStatusIndicator({ color: this.palette.primary })
                    .height(this.readerFooterHeight())
                    .margin({ bottom: this.readerTextBottomPaddingVp() })
                }
              }

            }
            .width('100%')
            .height('100%')
          this.buildReaderTabs()
          if (this.showBrightnessBar) { this.buildBrightnessBar() }
          if (this.speechState.active && this.speechState.bookId === this.bookId && this.isOnlineTextBook()) {
            this.buildSpeechMiniPlayer()
          }
        }
        .width('100%')
        .height('100%')
        .bindSheet($$this.showSettingsSheet, this.buildSettingsSheet(), {
          height: '82%',
          detents: ['82%', '45%', SheetSize.LARGE], dragBar: true, preferType: SheetType.BOTTOM,
          showClose: false,
          backgroundColor: AppMaterial.SheetBackground,
          maskColor: Color.Transparent,
          blurStyle: AppMaterial.ReaderSheetBlur,
          systemMaterial: AppMaterial.ReaderSheetThick,
          onDisappear: (): void => {
            this.showSettingsSheet = false;
            this.previewFontSize = 0; this.previewLineHeight = 0; this.previewParagraphSpacing = -1; this.previewFontWeight = 0;
            if (!this.leaving) {
              this.saveReadingSettings();
              if (!this.showChapterSheet) this.showReaderBar();
            }
          }
        })
      }

      if (this.loading) {
        this.buildLoadingState()
      } else if (this.readerError) {
        this.buildErrorState()
      }
      if (this.book !== null && (this.readerBarVisible || this.readerError.length > 0)) {
        this.buildSourceActions()
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showChapterSheet, this.buildChapterSheet(), {
      height: SheetSize.LARGE,
      detents: [SheetSize.LARGE, '45%', '70%'], dragBar: true, preferType: SheetType.BOTTOM,
      showClose: false,
      backgroundColor: AppMaterial.SheetBackground,
      maskColor: Color.Transparent,
      blurStyle: AppMaterial.ReaderSheetBlur,
      systemMaterial: AppMaterial.ReaderSheetThick,
      onAppear: (): void => this.scrollChapterListToCurrent(),
      onDisappear: (): void => {
        this.showChapterSheet = false;
        if (!this.leaving && !this.showSettingsSheet) this.showReaderBar();
      }
    })
    .onTouch((event: TouchEvent): void => { if (event.type === TouchType.Down) this.screenOn.touch(); })
    .onKeyEvent((event: KeyEvent): void => this.handleReaderKey(event))
    .focusable(true)
    .defaultFocus(true)
    .onVisibleAreaChange([0, 1], (visible: boolean): void => {
      this.readerVisible = visible;
      if (visible) this.syncSpeechPosition();
      this.saveProgress();
      if (!visible) ReadingSessionService.end('reading');
      this.screenOn.setVisible(visible);
      this.brightnessControl.setVisible(visible);
      this.syncHoldingHand();
    })
    // 背景由 ReaderBackground 铺，根节点保持透明
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .onSizeChange((oldValue: SizeOptions, newValue: SizeOptions): void => {
      this.handleViewportSizeChange(oldValue, newValue);
    })
  }

  @Builder
  private speechMiniMaterialContent(): void {
    Stack().width('100%').height('100%')
  }

  private speechMiniTop(): number { return this.readerTopInsetVp() + 48; }

  private speechMiniBottom(): number {
    const height = this.readerViewportHeightVp > 0 ? this.readerViewportHeightVp : WindowUtils.getWindowHeightVp();
    const bottom = Math.max(this.bottomSafeVp, READER_MIN_SAFE_BOTTOM) + (this.readerBarVisible ?
      READER_BAR_HEIGHT + (this.showChapterBar ? 76 : READER_FLOATING_BOTTOM + 12) : 16);
    return Math.max(this.speechMiniTop(), height - bottom - 48);
  }

  private speechMiniY(): number {
    if (this.speechMiniVerticalRatio < 0) return this.speechMiniBottom();
    return this.speechMiniTop() + this.speechMiniVerticalRatio * (this.speechMiniBottom() - this.speechMiniTop());
  }

  private speechMiniX(): number {
    const width = this.readerViewportWidthVp > 0 ? this.readerViewportWidthVp : WindowUtils.getWindowWidthVp();
    return this.holdingHandSide === 2 ? Math.max(this.leftSafeVp + 12, width - this.rightSafeVp - 152) : this.leftSafeVp + 12;
  }

  @Builder
  private buildSpeechMiniPlayer(): void {
    Stack() {
      if (PlatformCompat.floatingTabs) {
        HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
          TabContent() { Column() }.height(48).tabBar(this.speechMiniMaterialContent())
        }.barMode(BarMode.Fixed).barHeight(48).barOverlap(true)
          .barFloatingStyle({
            barWidth: { smallWidth: 140, mediumWidth: 140, largeWidth: 140 },
            systemMaterialEffect: HdsCompat.material,
            barSideMargin: 0, barBottomMargin: 0,
            gradientMask: { maskColor: '#00000000', maskHeight: 48 },
            adaptToHandedness: false, thermoCtrl: true, barOpacity: 1
          })
          .scrollable(false).onContentWillChange((): boolean => false)
          .width(140).height(48).hitTestBehavior(HitTestMode.None)
      } else {
        Stack().width(140).height(48).borderRadius(24)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      }
    Row({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        CoverImage({ url: this.speechState.cover, title: this.book?.title ?? '',
          author: this.book?.author ?? '', localPlaceholder: this.book?.id.startsWith('import_') ?? false,
          imgWidth: 40, imgHeight: 40, useFixedHeight: true, radius: 20,
          decodeW: 120, decodeH: 120 })
      }.width(40).height(40).padding(0).backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.tts_title')).id('reader-speech-cover')
        .onClick((): void => { this.openSpeechPlayer(true); })
      Button({ type: ButtonType.Circle }) {
        if (this.speechState.loading) {
          LoadingProgress().width(28).height(28).color(AppColor.Brand)
        } else {
          Stack() {
            SymbolGlyph(this.speechState.playing ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
              .fontSize(18).fontColor([this.palette.primary])
          }.width(32).height(32).borderRadius(16).border({ width: 1.5, color: this.palette.primary })
        }
      }.width(44).height(40).padding(0).backgroundColor(Color.Transparent)
        .accessibilityText(this.speechState.playing || this.speechState.loading ?
          $r('app.string.tts_pause') : $r('app.string.tts_play')).id('reader-speech-toggle')
        .onClick((): void => {
          const speech = TextToSpeechService.getInstance();
          if (speech.state.playing || speech.state.loading) speech.pause();
          else speech.resume();
        })
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(17).fontColor([this.palette.primary])
      }.width(40).height(40).padding(0).backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.tts_stop')).id('reader-speech-stop')
        .onClick((): void => { TextToSpeechService.getInstance().stop(); })
    }.width(140).height(48).padding(4)
    }.width(140).height(48).attributeModifier(new ReaderControlClip())
      .position({ x: this.speechMiniX(), y: this.speechMiniY() })
      .priorityGesture(GestureGroup(GestureMode.Sequence,
        LongPressGesture({ repeat: false, duration: 350 }).onAction((): void => {
          this.speechMiniDragStartY = this.speechMiniY();
        }),
        PanGesture({ direction: PanDirection.Vertical, distance: 1 })
          .onActionUpdate((event: GestureEvent): void => {
            const span = this.speechMiniBottom() - this.speechMiniTop();
            this.speechMiniVerticalRatio = span > 0 ? Math.max(0, Math.min(1,
              (this.speechMiniDragStartY + event.offsetY - this.speechMiniTop()) / span)) : 0;
          })
      ))
      .onTouch((event: TouchEvent): void => { event.stopPropagation(); })
      .id('reader-speech-mini-player')
  }

  private changeReadingBrightness(value: number, commit: boolean): void {
    this.readingBrightness = TextReadingSettings.normalizeBrightness(value);
    this.brightnessControl.configure(this.readingBrightness);
    if (commit) this.saveReadingSettings();
  }

  private brightnessBarHeight(): number {
    const height = this.readerViewportHeightVp > 0 ? this.readerViewportHeightVp : WindowUtils.getWindowHeightVp();
    return Math.min(280, Math.max(160, height - this.readerTopInsetVp() -
      Math.max(this.bottomSafeVp, READER_MIN_SAFE_BOTTOM) - 180));
  }

  private brightnessBarX(): number {
    const width = this.readerViewportWidthVp > 0 ? this.readerViewportWidthVp : WindowUtils.getWindowWidthVp();
    return this.holdingHandSide === 1 ? this.leftSafeVp + 12 : Math.max(this.leftSafeVp + 12, width - this.rightSafeVp - 60);
  }

  private brightnessBarY(): number {
    const height = this.readerViewportHeightVp > 0 ? this.readerViewportHeightVp : WindowUtils.getWindowHeightVp();
    const top = this.readerTopInsetVp() + 48;
    const bottom = Math.max(this.bottomSafeVp, READER_MIN_SAFE_BOTTOM) + READER_BAR_HEIGHT + 76;
    return Math.max(top, top + (height - top - bottom - this.brightnessBarHeight()) / 2);
  }

  @Builder
  buildBrightnessBar() {
    ReaderBrightnessBar({ value: this.readingBrightness, barHeight: this.brightnessBarHeight(), foreground: this.palette.primary,
      onChange: (value: number, commit: boolean): void => { this.changeReadingBrightness(value, commit); } })
      .position({ x: this.brightnessBarX(), y: this.brightnessBarY() })
      .opacity(this.readerBarVisible ? 1 : 0)
      .visibility(this.readerBarVisible ? Visibility.Visible : Visibility.Hidden)
      .enabled(this.readerBarVisible)
      .hitTestBehavior(this.readerBarVisible ? HitTestMode.Default : HitTestMode.None)
      .onTouch((event: TouchEvent): void => { event.stopPropagation(); })
      .id('reader-brightness-bar')
  }

  @Builder
  buildOnlineTextPage(): void {
    Stack() {
      ReaderBackground({
        palette: this.palette,
        pattern: this.systemNightOverride ? ReaderPattern.None : this.backgroundPattern,
        bgImagePath: this.bgImagePath,
        imageMode: this.isOnlineTextBook() ? this.backgroundImageMode : ReaderImageMode.Cover,
        overlayAlpha: this.overlayAlpha
      })
      Column() {
        Row() {
          Text(this.cornerText(0))
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.primary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .visibility(this.cornerVisible(0) ? Visibility.Visible : Visibility.Hidden)
          Text(this.cornerText(1))
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.primary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.End)
            .constraintSize({ maxWidth: '50%' })
            .visibility(this.cornerVisible(1) ? Visibility.Visible : Visibility.Hidden)
            .onSizeChange((_previous: SizeOptions, current: SizeOptions): void => {
              if (typeof current.width === 'number') this.pageLabelWidthVp = current.width;
            })
        }
        .width('100%')
        .height(this.readerHeaderHeight())
        .visibility(this.readerHeaderHeight() > 0 ? Visibility.Visible : Visibility.None)
        .alignItems(VerticalAlign.Center)

        Column() {
          if (this.pageTurnMode === PageTurnMode.Vertical) {
            ReaderContinuousComponent({
              selectionEnabled: !this.readerBarVisible && !this.showChapterSheet && !this.showSourceSwitch && !this.showSettingsSheet && !this.showSpeechSheet && !this.showBookmarkSheet && !this.showReplaceSheet && !this.showReaderMenu,
              onSelectionChange: (active: boolean): void => { this.selectingText = active; },
              tapRegions: this.tapRegions,
          tapLeftPercent: this.tapLeftPercent,
          tapRightPercent: this.tapRightPercent,
          tapTopPercent: this.tapTopPercent,
          tapBottomPercent: this.tapBottomPercent,

              keyTurnRequest: this.keyTurnRequest,
              speechState: this.speechState,
              followOffset: this.speechState.active && this.speechState.bookId === this.bookId &&
                this.speechState.chapterIndex === this.currentResourceIndex ? this.speechState.charOffset : -1,
              revision: this.continuousRevision, chapterIndex: this.currentResourceIndex,
              content: this.onlineTextContent, charOffset: this.currentOnlineTextCharOffset(),
              chapterCount: this.book?.chapters.length ?? 0,
              fontSize: this.fontSize, lineHeight: this.lineHeight, paragraphSpacing: this.paragraphSpacing, palette: this.palette,
              textAlignment: this.textAlignment,
              fontFamily: this.fontFamily, fontWeight: this.fontWeight,
              bookId: this.bookId,
              topGestureInset: 0,
              getContent: async (index: number): Promise<string> => {
                if (this.book === null) throw new Error('Reader book unavailable');
                return this.getOnlineTextChapterContent(this.book, index);
              },
              getTitle: (index: number): string => this.chapterTitle(index),
              getKey: (index: number): string => `${this.bookId}:${this.book?.chapters[index]?.id ?? index}`,
              onPosition: (index: number, offset: number, content: string, persist: boolean): void =>
                this.updateContinuousPosition(index, offset, content, persist),
              onCenterTap: (): void => this.toggleReaderBar(),
              onScrollStart: (): void => this.hideReaderBar()
            })
          } else {
            ReaderSpeechText({
              selectionEnabled: !this.readerBarVisible && !this.showChapterSheet && !this.showSourceSwitch && !this.showSettingsSheet && !this.showSpeechSheet && !this.showBookmarkSheet && !this.showReplaceSheet && !this.showReaderMenu,
              onSelectionChange: (active: boolean): void => { this.selectingText = active; },
              page: this.currentOnlineTextPageLayout(),
              text: this.currentOnlineTextPageContent(),
              source: this.currentOnlineTextPageSource(),
              sourceStart: this.onlineTextPages[this.onlineTextPageIndex]?.startOffset ?? 0,
              state: this.speechState,
              highlightEnabled: this.speechState.bookId === this.bookId &&
                this.speechState.chapterIndex === this.currentResourceIndex,
              fontSize: this.fontSize, lineHeight: this.lineHeight, palette: this.palette,
              fontFamily: this.fontFamily, fontWeight: this.fontWeight
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .clip(true)
        .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => this.handleReaderTextSizeChange(size))

        Row({ space: AppSpace.Sm }) {
          Text(this.cornerText(2))
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.primary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .visibility(this.cornerVisible(2) ? Visibility.Visible : Visibility.Hidden)
          if (this.showFooter && this.showReadingStatus) {
            ReaderStatusIndicator({ color: this.palette.primary })
          }
          Text(this.cornerText(3))
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.primary)
            .layoutWeight(1)
            .textAlign(TextAlign.End)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .visibility(this.cornerVisible(3) ? Visibility.Visible : Visibility.Hidden)
        }
        .width('100%')
        .height(this.readerFooterHeight())
        .visibility(this.readerFooterHeight() > 0 ? Visibility.Visible : Visibility.None)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({
        left: this.readerLeftPadding(),
        right: this.readerRightPadding(),
        // 只让正文避开系统栏；背景和翻页纸面始终使用完整视口，保持图片连续。
        top: this.readerTopInsetVp() + Math.max(0, this.marginTop - 12),
        bottom: this.readerTextBottomPaddingVp()
      })

    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildOnlineTextReader(): void {
    Stack() {
      if (this.pageTurnMode === PageTurnMode.Vertical) {
        this.buildOnlineTextPage()
      } else {
        ReaderPageTurnComponent({
          selectionActive: this.selectingText,
          tapRegions: this.tapRegions,
          tapLeftPercent: this.tapLeftPercent,
          tapRightPercent: this.tapRightPercent,
          tapTopPercent: this.tapTopPercent,
          tapBottomPercent: this.tapBottomPercent,

          safeLeft: this.leftSafeVp, safeRight: this.rightSafeVp,
          safeTop: this.readerTopInsetVp() + Math.max(0, this.marginTop - 12) + this.readerHeaderHeight(),
          safeBottom: this.readerTextBottomPaddingVp(),
          keyTurnRequest: this.keyTurnRequest,
          mode: this.pageTurnMode,
          revision: this.onlineTextTurnRevision(),
          paperColor: this.palette.background,
          pageContent: (): void => this.buildOnlineTextPage(),
          onPrepare: (forward: boolean): Promise<boolean> => this.prepareOnlineTextTurn(forward),
          onConfirm: (): void => { this.onlineTextTurnConfirmed = true; },
          onComplete: (commit: boolean): void => this.completeOnlineTextTurn(commit),
          onCenterTap: (): void => this.toggleReaderBar()
        })
      }
      if (this.onlineTextLoading) {
        Column({ space: AppSpace.Sm }) {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(AppColor.Brand)
          this.buildLoadingHints(this.chapterTitle(this.jumpingResourceIndex))
        }
        .width('100%')
        .height('100%')
        .padding({ left: AppSpace.Xl, right: AppSpace.Xl })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.palette.scrim)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildChapterSheet(): void {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: AppSpace.Xs }) {
      Row() {
        Text($r('app.string.reader_chapters'))
          .fontSize(AppFont.Title)
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
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([$r('sys.color.font_secondary')])
          .onClick((): void => this.closeChapterSheet())
      }
      .width('100%')
      .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Xs })

      ChapterSheetActions({
        descending: this.chapterDescending,
        onOrder: (): void => this.toggleChapterOrder(),
        onTop: (): void => {
          this.chapterTopRequest++;
          this.chapterPositionGeneration++;
          if (!this.chapterSegmented && this.chapterDataSource.totalCount() > 0) this.chapterListScroller.scrollToIndex(0, false, ScrollAlign.START);
        },
        onBottom: (): void => {
          this.chapterBottomRequest++;
          this.chapterPositionGeneration++;
          if (!this.chapterSegmented && this.chapterDataSource.totalCount() > 0) this.chapterListScroller.scrollToIndex(this.chapterDataSource.totalCount() - 1, false, ScrollAlign.END);
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
          highlightCurrent: false,
          book: this.book, topRequest: this.chapterTopRequest, bottomRequest: this.chapterBottomRequest,
          chapters: this.book?.chapters ?? [],
          currentId: this.book?.chapters[this.currentResourceIndex]?.id ?? '',
          keyword: this.chapterQuery,
          descending: this.chapterDescending,
          onSelect: (chapter: Chapter): void => { this.selectChapter(chapter); }
        }).layoutWeight(1)
      } else {
      if (this.chapterDataSource.totalCount() === 0) {
        Text($r('app.string.reader_no_matching_chapters'))
          .fontColor($r('sys.color.font_secondary'))
          .padding(AppSpace.Md)
      }
      List({ space: 0, scroller: this.chapterListScroller }) {
        LazyForEach(this.chapterDataSource, (chapter: Chapter) => {
          ListItem() {
            Row({ space: AppSpace.Sm }) {
              Column({ space: AppSpace.Xxs }) {
                Text(chapter.title)
                  .fontSize(AppFont.BodyL)
                  .fontColor($r('sys.color.font_secondary'))
                  .fontWeight(FontWeight.Normal)
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
              ChapterCacheIndicator({ book: this.book, chapter: chapter })
            }
            .width('100%')
            .constraintSize({ minHeight: READER_CHAPTER_ROW_HEIGHT })
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
          (centerIndex - (this.book ? PreferenceService.chapterDisplayIndex(this.book, this.currentResourceIndex) : 0)) * READER_CHAPTER_ROW_HEIGHT;
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

  @Builder
  buildSettingsSheet(): void {
    ReaderSettingsSheet({
      supportsSpeech: this.isOnlineTextBook(),
      onSpeechSettings: (): void => { this.openSpeechSheet(); },
      fontPanel: this.fontPanel, fontWeight: this.previewFontWeight || this.fontWeight,
      fonts: this.importedFonts, fontPath: this.fontPath,
      onSelectFont: (font: ReaderImportedFont): void => this.selectReaderFont(font),
      onDeleteFont: (font: ReaderImportedFont): void => { this.deleteReaderFont(font); },
      fontFamily: this.fontFamily, fontName: this.fontName, screenOnMinutes: this.screenOnMinutes,
      onWeightChange: (weight: number, commit: boolean): void => {
        this.previewFontWeight = TextReadingSettings.normalizeFontWeight(weight);
        if (commit) {
          this.fontWeight = this.previewFontWeight;
          this.previewFontWeight = 0;
          this.cancelReaderSettingsRefresh();
          this.applyReadingSettings(); this.saveReadingSettings();
        }
      },
      customThemes: this.customThemes,
      customThemeIndex: this.customThemeIndex,
      imageFontColor: this.imageFontColor,
      effectiveThemeId: this.effectiveThemeId,
      onCustomThemeSave: (slot: number, background: string, fontColor: string): void => {
        this.handleCustomThemeSave(slot, background, fontColor);
      },
      onCustomThemeSelect: (slot: number): void => this.handleCustomThemeSelect(slot),
      onImageTextChange: (light: boolean): void => this.handleImageTextChange(light),
      supportsImageMode: this.isOnlineTextBook(),
      onImageModeChange: (mode: ReaderImageMode): void => {
        this.backgroundImageMode = mode;
        this.saveReadingSettings();
      },
      onPickFont: (): void => { this.pickReaderFont(); },
      onSystemFont: (): void => {
        this.fontFamily = ''; this.fontPath = ''; this.fontName = '';
        this.applyReadingSettings(); this.saveReadingSettings();
      },
      onScreenOnChange: (minutes: number): void => {
        this.screenOnMinutes = minutes; this.screenOn.configure(minutes); this.saveReadingSettings();
      },
      fontSize: this.previewFontSize || this.fontSize,
      lineHeight: this.previewLineHeight || this.lineHeight,
      paragraphSpacing: this.previewParagraphSpacing >= 0 ? this.previewParagraphSpacing : this.paragraphSpacing,
      paragraphSpacingEnabled: this.isOnlineTextBook(),
      onParagraphSpacingChange: (value: number, commit: boolean): void => {
        this.handleParagraphSpacingChange(value, commit);
      },
      themeId: this.themeId,
      pattern: this.systemNightOverride ? ReaderPattern.None : this.backgroundPattern,
      bgImagePath: this.bgImagePath,
      imageMode: this.isOnlineTextBook() ? this.backgroundImageMode : ReaderImageMode.Cover,
      overlayAlpha: this.overlayAlpha,
      tapRegions: this.tapRegions,
          tapLeftPercent: this.tapLeftPercent,
          tapRightPercent: this.tapRightPercent,
          tapTopPercent: this.tapTopPercent,
          tapBottomPercent: this.tapBottomPercent,

      showChapterBar: this.showChapterBar,
      showBrightnessBar: this.showBrightnessBar,
      showHeader: this.showHeader,
      cornerLayout: this.cornerLayout,
      onCornerChange: (corner: number, content: number): void => {
        this.cornerLayout = ReaderCornerLayout.swap(this.cornerLayout, corner, content);
        this.applyReadingSettings();
        this.saveReadingSettings();
      },
      showFooter: this.showFooter,
      showChapterTitle: this.showChapterTitle,
      showPageNumber: this.showPageNumber,
      showChapterNumber: this.showChapterNumber,
      showBookName: this.showBookName,
      onTapSizeChange: (edge: string, value: number, commit: boolean): void => {
        if (edge === 'left') this.tapLeftPercent = ReaderTapPolicy.percent(value, this.tapRightPercent);
        if (edge === 'right') this.tapRightPercent = ReaderTapPolicy.percent(value, this.tapLeftPercent);
        if (edge === 'top') this.tapTopPercent = ReaderTapPolicy.percent(value, this.tapBottomPercent);
        if (edge === 'bottom') this.tapBottomPercent = ReaderTapPolicy.percent(value, this.tapTopPercent);
        if (commit) this.saveReadingSettings();
      },
      onResetTapAreas: (): void => {
        this.tapLeftPercent = 33; this.tapRightPercent = 33;
        this.tapTopPercent = 33; this.tapBottomPercent = 33;
        this.tapRegions = ReaderTapPolicy.DEFAULT; this.saveReadingSettings();
      },
      onChromeChange: (field: string, enabled: boolean): void => {
        if (field === 'showBrightnessBar') this.showBrightnessBar = enabled;
        if (field === 'showChapterBar') this.showChapterBar = enabled;
        if (field === 'showHeader') this.showHeader = enabled;
        if (field === 'showFooter') this.showFooter = enabled;
        if (field === 'showChapterTitle') this.showChapterTitle = enabled;
        if (field === 'showPageNumber') this.showPageNumber = enabled;
        if (field === 'showChapterNumber') this.showChapterNumber = enabled;
        if (field === 'showBookName') this.showBookName = enabled;
        this.applyReadingSettings(); this.saveReadingSettings();
      },
      onTapRegionsChange: (value: string): void => {
        this.tapRegions = ReaderTapPolicy.normalize(value);
        this.saveReadingSettings();
      },
      volumeKeyPageTurn: this.volumeKeyPageTurn,
      onVolumeKeyPageTurnChange: (enabled: boolean): void => {
        this.volumeKeyPageTurn = enabled;
        this.saveReadingSettings();
      },
      pageTurnMode: this.pageTurnMode,
      showReadingStatus: this.showReadingStatus,
      alwaysShowStatusBar: this.alwaysShowStatusBar,
      onStatusBarChange: (enabled: boolean): void => {
        this.alwaysShowStatusBar = enabled;
        this.applyReadingSettings();
        this.syncReaderStatusBar();
        this.saveReadingSettings();
      },
      palette: this.palette,
      followSystemTheme: this.followSystemTheme,
      marginLeft: this.marginLeft, marginRight: this.marginRight,
      marginTop: this.marginTop, marginBottom: this.marginBottom,
      marginTopMax: this.marginTopMax,
      onFollowSystemChange: (enabled: boolean): void => {
        this.followSystemTheme = enabled;
        this.refreshPalette();
        this.applyReadingSettings(false);
        this.saveReadingSettings();
      },
      onMarginChange: (edge: string, value: number, commit: boolean): void => {
        const margin = TextReadingSettings.normalizeMargin(value, 16,
          edge === 'top' ? this.marginTopMax : TextReadingSettings.MARGIN_UI_MAX);
        if (edge === 'left') this.marginLeft = margin;
        if (edge === 'right') this.marginRight = margin;
        if (edge === 'top') this.marginTop = margin;
        if (edge === 'bottom') this.marginBottom = margin;
        this.applyReadingSettings();
        if (commit) this.saveReadingSettings();
      },
      onFontSizeChange: (value: number, commit: boolean): void => {
        this.handleFontSizeChange(value, commit);
      },
      onLineHeightChange: (value: number, commit: boolean): void => {
        this.handleLineHeightChange(value, commit);
      },
      onThemeChange: (themeId: string): void => {
        this.handleThemeChange(themeId);
      },
      onOverlayChange: (value: number, commit: boolean): void => {
        this.handleOverlayChange(value, commit);
      },
      textAlignment: this.textAlignment,
      onTextAlignmentChange: (value: string): void => {
        this.textAlignment = TextReadingSettings.normalizeTextAlignment(value);
        this.applyReadingSettings(); this.saveReadingSettings();
      },
      onPageTurnModeChange: (mode: string): void => {
        this.handlePageTurnModeChange(mode);
      },
      onReadingStatusChange: (enabled: boolean): void => {
        this.showReadingStatus = enabled;
        this.applyReadingSettings();
        this.saveReadingSettings();
      },
      onPickImage: (): void => {
        this.pickBackgroundImage();
      },
      onResetDefaults: (): void => {
        this.handleResetDefaults();
      },
      onClose: (): void => {
        this.closeSettingsSheet();
      }
    })
      .width('100%')
      .height('100%')
  }

  @Builder
  buildLoadingHints(chapterTitle: string) {
    Column({ space: AppSpace.Sm }) {
      Text($r('app.string.reader_loading'))
        .fontSize(AppFont.BodyL)
        .fontColor(Color.White)
      if (chapterTitle) {
        Text(chapterTitle)
          .fontSize(AppFont.BodyL)
          .fontColor(Color.White)
          .maxLines(2)
          .textAlign(TextAlign.Center)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    // 只反色加载圈下方的提示文字，适配实际底色和自定义图片。
    .blendMode(BlendMode.DIFFERENCE, BlendApplyType.OFFSCREEN)
  }

  @Builder
  buildLoadingState() {
    Column({ space: AppSpace.Sm }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(AppColor.Brand)
      this.buildLoadingHints(this.currentChapterTitle)
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpace.Xl, right: AppSpace.Xl })
    .justifyContent(FlexAlign.Center)
    // 背景由 ReaderBackground 铺
  }

  @Builder
  buildErrorState() {
    Column({ space: AppSpace.Md }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(42)
        .fontColor([AppColor.Brand])
      Text(this.readerError)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(3)
      Button($r('app.string.common_retry'))
        .height(44)
        .fontSize(AppFont.Body)
        .fontColor('#FFFFFF')
        .backgroundColor(AppColor.Brand)
        .onClick(() => this.retryReader())
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppSpace.Xl, right: AppSpace.Xl })
    .justifyContent(FlexAlign.Center)
    // 背景由 ReaderBackground 铺
  }
}
