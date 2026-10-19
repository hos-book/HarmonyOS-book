import { ReaderPattern, ReaderImageMode, ReaderThemeId, ReaderCustomTheme, findThemePreset, normalizeHex, resolvePalette } from './ReaderTheme';

export class TextChapterContent {
  title: string = '';
  content: string = '';
  sourceUrl: string = '';

  static of(title: string, content: string, sourceUrl: string): TextChapterContent {
    const value = new TextChapterContent();
    value.title = title;
    value.content = content;
    value.sourceUrl = sourceUrl;
    return value;
  }
}

export class TextReadingPosition {
  bookId: string = '';
  resourceIndex: number = 0;
  domPos: string = '';
  charOffset: number = 0;
  pageOffset: number = 0;
  chapterTitle: string = '';
  updatedAt: number = 0;

  static of(bookId: string, resourceIndex: number, domPos: string,
    pageOffset: number, chapterTitle: string): TextReadingPosition {
    return TextReadingPosition.atChar(bookId, resourceIndex, domPos, 0, pageOffset, chapterTitle);
  }

  static atChar(bookId: string, resourceIndex: number, domPos: string,
    charOffset: number, pageOffset: number, chapterTitle: string): TextReadingPosition {
    const value = new TextReadingPosition();
    value.bookId = bookId;
    value.resourceIndex = resourceIndex;
    value.domPos = domPos;
    value.charOffset = Math.max(0, charOffset);
    value.pageOffset = pageOffset;
    value.chapterTitle = chapterTitle;
    value.updatedAt = Date.now();
    return value;
  }
}

/** 翻页模式 */
export enum PageTurnMode {
  /** 覆盖翻页（默认） */
  Cover = 'cover',
  None = 'none',
  /** 仿真翻页 */
  Simulation = 'simulation',
  /** 滑动翻页 */
  Slide = 'slide',
  /** 连续滚动正文；保留旧存储值以兼容已保存的设置。 */
  Vertical = 'vertical'
}

export enum ReaderCornerContent {
  ChapterTitle = 0,
  PageNumber = 1,
  ChapterNumber = 2,
  BookName = 3
}

/** 顺序为左上、右上、左下、右下；每种内容只占一个位置。 */
export class ReaderCornerLayout {
  static readonly DEFAULT: string = '0123';

  static normalize(value: string): string {
    return /^[0-3]{4}$/.test(value) && new Set(value.split('')).size === 4 ? value : ReaderCornerLayout.DEFAULT;
  }

  static content(layout: string, corner: number): number {
    return Number(ReaderCornerLayout.normalize(layout).charAt(corner));
  }

  static swap(layout: string, corner: number, content: number): string {
    const normalized = ReaderCornerLayout.normalize(layout);
    if (!Number.isInteger(corner) || corner < 0 || corner > 3 ||
      !Number.isInteger(content) || content < 0 || content > 3) return normalized;
    const slots = normalized.split('');
    const previous = slots.indexOf(content.toString());
    slots[previous] = slots[corner];
    slots[corner] = content.toString();
    return slots.join('');
  }
}

export class TextReadingSettings {
  cornerLayout: string = ReaderCornerLayout.DEFAULT;
  textAlignment: string = 'justify';

  static normalizeTextAlignment(value?: string): string {
    return value === 'start' || value === 'center' || value === 'end' ? value : 'justify';
  }

  tapRegions: string = '012012012';
  tapLeftPercent: number = 33;
  tapRightPercent: number = 33;
  tapTopPercent: number = 33;
  tapBottomPercent: number = 33;
  showChapterBar: boolean = true;
  showHeader: boolean = true;
  showFooter: boolean = true;
  showChapterTitle: boolean = true;
  showPageNumber: boolean = true;
  showChapterNumber: boolean = true;
  showBookName: boolean = true;
  static readonly FONT_SIZE_MIN: number = 14;
  static readonly FONT_SIZE_MAX: number = 50;
  static readonly FONT_SIZE_DEFAULT: number = 18;
  static readonly LINE_HEIGHT_MIN: number = 1;
  static readonly LINE_HEIGHT_MAX: number = 2.4;
  static readonly LINE_HEIGHT_DEFAULT: number = 1.9;
  /** 段后额外留白，以字号倍数计；默认保留原来的紧接排版。 */
  static readonly PARAGRAPH_SPACING_MIN: number = 0;
  static readonly PARAGRAPH_SPACING_MAX: number = 2;
  static readonly PARAGRAPH_SPACING_DEFAULT: number = 0;

  static normalizeParagraphSpacing(value: number): number {
    return Number.isFinite(value) ? Math.round(Math.max(0, Math.min(2, value)) * 10) / 10 : 0;
  }
  /** 背景图蒙层浓度：0 = 图片原样，0.85 = 几乎被底色盖住 */
  static readonly OVERLAY_MIN: number = 0;
  static readonly OVERLAY_MAX: number = 0.85;
  static readonly OVERLAY_DEFAULT: number = 0.35;
  static readonly THEME_DEFAULT: string = ReaderThemeId.Parchment;
  static readonly CUSTOM_BACKGROUND_DEFAULT: string = '#F5F2EA';
  static readonly PAGE_TURN_MODE_DEFAULT: string = PageTurnMode.Cover;
  static readonly SHOW_READING_STATUS_DEFAULT: boolean = true;
  static readonly ALWAYS_SHOW_STATUS_BAR_DEFAULT: boolean = true;
  /** 边距持久化宽松上限：上边距允许随屏幕高度放大到视口一半，其余边保持 UI 上限。 */
  static readonly MARGIN_MAX_LIMIT: number = 512;
  /** 常规边距 UI 上限（左右/下） */
  static readonly MARGIN_UI_MAX: number = 64;

  followSystemTheme: boolean = true;
  marginLeft: number = 16;
  marginRight: number = 16;
  marginTop: number = 12;
  marginBottom: number = 12;

  static normalizeMargin(value: number, fallback: number, max: number = TextReadingSettings.MARGIN_UI_MAX): number {
    return Number.isFinite(value) ? Math.round(Math.max(0, Math.min(max, value))) : fallback;
  }

  fontWeight: number = 400;
  /** 自定义主题字色；空值使用按背景推荐的默认色。 */
  fontColor: string = '';
  /** 图片主题配置与自定义主题配色分开保存。 */
  imageBackground: string = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
  imageFontColor: string = '';
  customThemeIndex: number = 0;
  customThemes: ReaderCustomTheme[] = ReaderCustomTheme.defaults();
  fontPath: string = '';
  fontName: string = '';
  screenOnMinutes: number = 0;

  static normalizeFontWeight(value: number): number {
    return Number.isFinite(value) ? Math.round(Math.max(100, Math.min(900, value))) : 400;
  }

  static normalizeScreenOnMinutes(value: number): number {
    return [-1, 0, 1, 5, 10].includes(value) ? value : 0;
  }

  fontSize: number = TextReadingSettings.FONT_SIZE_DEFAULT;
  lineHeight: number = TextReadingSettings.LINE_HEIGHT_DEFAULT;
  paragraphSpacing: number = TextReadingSettings.PARAGRAPH_SPACING_DEFAULT;
  /** 预设主题 id，或 ReaderThemeId.Image 表示自定义图片 */
  themeId: string = TextReadingSettings.THEME_DEFAULT;
  /** 自定义主题底色 */
  customBackground: string = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
  /** 兼容旧偏好字段，只保留 none / image */
  pattern: string = ReaderPattern.None;
  /** pattern=image 时的沙箱内图片路径 */
  backgroundImage: string = '';
  backgroundImageMode: ReaderImageMode = ReaderImageMode.Cover;

  static normalizeBackgroundImageMode(value: string): ReaderImageMode {
    if (value === ReaderImageMode.Contain) return ReaderImageMode.Contain;
    if (value === ReaderImageMode.Tile) return ReaderImageMode.Tile;
    if (value === ReaderImageMode.Stretch) return ReaderImageMode.Stretch;
    return ReaderImageMode.Cover;
  }
  /** 背景图上的底色蒙层浓度 */
  overlayAlpha: number = TextReadingSettings.OVERLAY_DEFAULT;
  /** 音量加上一页、音量减下一页；默认保留系统音量行为。 */
  volumeKeyPageTurn: boolean = false;
  /** 翻页模式 */
  pageTurnMode: string = TextReadingSettings.PAGE_TURN_MODE_DEFAULT;
  /** 底部居中显示电量和时间，不影响正文视口。 */
  showReadingStatus: boolean = TextReadingSettings.SHOW_READING_STATUS_DEFAULT;
  /** 关闭时跟随阅读工具栏显隐；安全区始终保留。 */
  alwaysShowStatusBar: boolean = TextReadingSettings.ALWAYS_SHOW_STATUS_BAR_DEFAULT;

  static of(fontSize: number, lineHeight: number): TextReadingSettings {
    const value = new TextReadingSettings();
    value.fontSize = TextReadingSettings.normalizeFontSize(fontSize);
    value.lineHeight = TextReadingSettings.normalizeLineHeight(lineHeight);
    return value;
  }

  /** 完整构造；服务层读盘后用它一次装配。 */
  static ofAll(fontSize: number, lineHeight: number, themeId: string,
    customBackground: string, pattern: string, backgroundImage: string,
    overlayAlpha: number, pageTurnMode?: string, showReadingStatus?: boolean): TextReadingSettings {
    const value = TextReadingSettings.of(fontSize, lineHeight);
    value.themeId = TextReadingSettings.normalizeThemeId(themeId);
    value.customBackground = normalizeHex(customBackground);
    value.pattern = TextReadingSettings.normalizePattern(pattern);
    value.backgroundImage = typeof backgroundImage === 'string' ? backgroundImage : '';
    value.overlayAlpha = TextReadingSettings.normalizeOverlay(overlayAlpha);
    value.pageTurnMode = TextReadingSettings.normalizePageTurnMode(pageTurnMode);
    value.showReadingStatus = typeof showReadingStatus === 'boolean' ? showReadingStatus :
      TextReadingSettings.SHOW_READING_STATUS_DEFAULT;
    // 旧版「主题 + 相册图案」合并为图片主题，保留原蒙层配色与浓度。
    if (value.pattern === ReaderPattern.Image && value.backgroundImage.length > 0
      && value.themeId !== ReaderThemeId.Image) {
      value.customBackground = resolvePalette(value.themeId, value.customBackground).background;
      value.themeId = ReaderThemeId.Image;
    }
    if (value.themeId === ReaderThemeId.Image && value.backgroundImage.length === 0) {
      value.themeId = TextReadingSettings.THEME_DEFAULT;
    }
    value.pattern = value.themeId === ReaderThemeId.Image ? ReaderPattern.Image : ReaderPattern.None;
    return value;
  }

  static normalizeThemeId(value: string): string {
    if (typeof value !== 'string' || value.length === 0) return TextReadingSettings.THEME_DEFAULT;
    if (value === ReaderThemeId.Paper) return ReaderThemeId.Parchment;
    if (value === ReaderThemeId.Custom || value === ReaderThemeId.Image) return value;
    return findThemePreset(value) !== null ? value : TextReadingSettings.THEME_DEFAULT;
  }

  static normalizePattern(value: string): string {
    if (value === ReaderPattern.Image || value === ReaderPattern.None) {
      return value;
    }
    return ReaderPattern.None;
  }

  static normalizeOverlay(value: number): number {
    if (typeof value !== 'number' || Number.isNaN(value)) return TextReadingSettings.OVERLAY_DEFAULT;
    const clamped = Math.max(TextReadingSettings.OVERLAY_MIN,
      Math.min(TextReadingSettings.OVERLAY_MAX, value));
    return Math.round(clamped * 100) / 100;
  }

  static normalizeFontSize(value: number): number {
    return Math.round(Math.max(TextReadingSettings.FONT_SIZE_MIN,
      Math.min(TextReadingSettings.FONT_SIZE_MAX, value)));
  }

  static normalizeLineHeight(value: number): number {
    const clamped = Math.max(TextReadingSettings.LINE_HEIGHT_MIN,
      Math.min(TextReadingSettings.LINE_HEIGHT_MAX, value));
    return Math.round(clamped * 10) / 10;
  }

  static normalizePageTurnMode(value?: string): string {
    if (value === PageTurnMode.None || value === PageTurnMode.Cover || value === PageTurnMode.Simulation || value === PageTurnMode.Slide || value === PageTurnMode.Vertical) {
      return value;
    }
    return TextReadingSettings.PAGE_TURN_MODE_DEFAULT;
  }
}

export class TextReaderRouteParams {
  bookId: string = '';
  resourceIndex: number = -1;
  domPos: string = '';

  static of(bookId: string, resourceIndex: number = -1, domPos: string = ''): TextReaderRouteParams {
    const value = new TextReaderRouteParams();
    value.bookId = bookId;
    value.resourceIndex = resourceIndex;
    value.domPos = domPos;
    return value;
  }
}

/** 详情页复用栈内阅读页时请求跳章的事件 */
export const EVT_READER_JUMP_CHAPTER: string = 'app.reader.jumpChapter';
export const EVT_READER_TYPOGRAPHY_CHANGED: string = 'app.reader.typography.changed';

/** EVT_READER_JUMP_CHAPTER 的事件负载 */
export class ReaderJumpChapterEvent {
  bookId: string = '';
  resourceIndex: number = -1;
}

export class TextSourceError extends Error {
  code: string = '';
  retryAfterSeconds: number = 0;

  constructor(code: string, message: string, retryAfterSeconds: number = 0) {
    super(message);
    this.name = 'TextSourceError';
    this.code = code;
    this.retryAfterSeconds = retryAfterSeconds;
  }
}
