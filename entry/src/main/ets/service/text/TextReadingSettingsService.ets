import { ReaderTapPolicy } from '../../utils/ReaderTapPolicy';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { TextReadingSettings, ReaderCornerLayout } from '../../model/TextReading';
import { ReaderPattern, ReaderThemeId, ReaderCustomTheme, normalizeHex, resolvePalette } from '../../model/ReaderTheme';

const STORE_NAME: string = 'text_reading_settings';
const KEY_FONT_SIZE: string = 'font_size';
const KEY_LINE_HEIGHT: string = 'line_height';
const KEY_PARAGRAPH_SPACING: string = 'paragraph_spacing';
const KEY_THEME_ID: string = 'theme_id';
const KEY_CUSTOM_BACKGROUND: string = 'custom_background';
const KEY_PATTERN: string = 'background_pattern';
const KEY_BACKGROUND_IMAGE: string = 'background_image';
const KEY_OVERLAY_ALPHA: string = 'overlay_alpha';
const KEY_PAGE_TURN_MODE: string = 'page_turn_mode';
const KEY_SHOW_READING_STATUS: string = 'show_reading_status';
const KEY_ALWAYS_SHOW_STATUS_BAR: string = 'always_show_status_bar';

export class TextReadingSettingsService {
  private static store: preferences.Preferences | null = null;
  private static initPromise: Promise<void> | null = null;

  static init(context: common.Context): Promise<void> {
    if (TextReadingSettingsService.store !== null) return Promise.resolve();
    if (TextReadingSettingsService.initPromise !== null) return TextReadingSettingsService.initPromise;
    TextReadingSettingsService.initPromise = preferences.getPreferences(context, { name: STORE_NAME })
      .then((value: preferences.Preferences): void => {
        TextReadingSettingsService.store = value;
      })
      .finally((): void => {
        TextReadingSettingsService.initPromise = null;
      });
    return TextReadingSettingsService.initPromise;
  }

  static async get(context: common.Context): Promise<TextReadingSettings> {
    await TextReadingSettingsService.init(context);
    const store = TextReadingSettingsService.store;
    if (store === null) return new TextReadingSettings();
    const savedFontSize = store.getSync(KEY_FONT_SIZE, TextReadingSettings.FONT_SIZE_DEFAULT);
    const savedLineHeight = store.getSync(KEY_LINE_HEIGHT, TextReadingSettings.LINE_HEIGHT_DEFAULT);
    const savedThemeId = store.getSync(KEY_THEME_ID, TextReadingSettings.THEME_DEFAULT);
    const savedBackground = store.getSync(KEY_CUSTOM_BACKGROUND, TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT);
    const savedPattern = store.getSync(KEY_PATTERN, ReaderPattern.None);
    const savedImage = store.getSync(KEY_BACKGROUND_IMAGE, '');
    const savedOverlay = store.getSync(KEY_OVERLAY_ALPHA, TextReadingSettings.OVERLAY_DEFAULT);
    const savedPageTurnMode = store.getSync(KEY_PAGE_TURN_MODE, TextReadingSettings.PAGE_TURN_MODE_DEFAULT);
    const savedReadingStatus = store.getSync(KEY_SHOW_READING_STATUS, TextReadingSettings.SHOW_READING_STATUS_DEFAULT);
    const fontSize = typeof savedFontSize === 'number' ? savedFontSize : TextReadingSettings.FONT_SIZE_DEFAULT;
    const lineHeight = typeof savedLineHeight === 'number' ? savedLineHeight : TextReadingSettings.LINE_HEIGHT_DEFAULT;
    const themeId = typeof savedThemeId === 'string' ? savedThemeId : TextReadingSettings.THEME_DEFAULT;
    const background = typeof savedBackground === 'string'
      ? savedBackground : TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
    const pattern = typeof savedPattern === 'string' ? savedPattern : ReaderPattern.None;
    const image = typeof savedImage === 'string' ? savedImage : '';
    const overlay = typeof savedOverlay === 'number' ? savedOverlay : TextReadingSettings.OVERLAY_DEFAULT;
    const pageTurnMode = typeof savedPageTurnMode === 'string' ? savedPageTurnMode : TextReadingSettings.PAGE_TURN_MODE_DEFAULT;
    const showReadingStatus = typeof savedReadingStatus === 'boolean' ? savedReadingStatus :
      TextReadingSettings.SHOW_READING_STATUS_DEFAULT;
    const result = TextReadingSettings.ofAll(fontSize, lineHeight, themeId, background, pattern, image, overlay,
      pageTurnMode, showReadingStatus);
    const paragraphSpacing = store.getSync(KEY_PARAGRAPH_SPACING, TextReadingSettings.PARAGRAPH_SPACING_DEFAULT);
    result.paragraphSpacing = TextReadingSettings.normalizeParagraphSpacing(
      typeof paragraphSpacing === 'number' ? paragraphSpacing : TextReadingSettings.PARAGRAPH_SPACING_DEFAULT);
    const imageMode = store.getSync('background_image_mode', 'cover');
    result.backgroundImageMode = TextReadingSettings.normalizeBackgroundImageMode(
      typeof imageMode === 'string' ? imageMode : 'cover');
    const alignment = store.getSync('text_alignment', 'justify');
    result.textAlignment = TextReadingSettings.normalizeTextAlignment(typeof alignment === 'string' ? alignment : 'justify');
    const tapLeftPercent = store.getSync('tapLeftPercent', 33);
    result.tapLeftPercent = ReaderTapPolicy.percent(typeof tapLeftPercent === 'number' ? tapLeftPercent : 33);
    const tapRightPercent = store.getSync('tapRightPercent', 33);
    result.tapRightPercent = ReaderTapPolicy.percent(typeof tapRightPercent === 'number' ? tapRightPercent : 33, result.tapLeftPercent);
    const tapTopPercent = store.getSync('tapTopPercent', 33);
    result.tapTopPercent = ReaderTapPolicy.percent(typeof tapTopPercent === 'number' ? tapTopPercent : 33);
    const tapBottomPercent = store.getSync('tapBottomPercent', 33);
    result.tapBottomPercent = ReaderTapPolicy.percent(typeof tapBottomPercent === 'number' ? tapBottomPercent : 33, result.tapTopPercent);
    result.showChapterBar = store.getSync('showChapterBar', true) !== false;
    result.showBrightnessBar = store.getSync('showBrightnessBar', true) !== false;
    const brightness = store.getSync('reader_brightness', -1);
    result.brightness = TextReadingSettings.normalizeBrightness(typeof brightness === 'number' ? brightness : -1);
    result.showHeader = store.getSync('showHeader', true) !== false;
    const cornerLayout = store.getSync('corner_layout', ReaderCornerLayout.DEFAULT);
    result.cornerLayout = ReaderCornerLayout.normalize(typeof cornerLayout === 'string' ? cornerLayout : '');
    result.showFooter = store.getSync('showFooter', true) !== false;
    result.showChapterTitle = store.getSync('showChapterTitle', true) !== false;
    result.showPageNumber = store.getSync('showPageNumber', true) !== false;
    result.showChapterNumber = store.getSync('showChapterNumber', true) !== false;
    result.showBookName = store.getSync('showBookName', true) !== false;
    const tapRegions = store.getSync('tap_regions', ReaderTapPolicy.DEFAULT);
    result.tapRegions = ReaderTapPolicy.normalize(typeof tapRegions === 'string' ? tapRegions : ReaderTapPolicy.DEFAULT);
    const statusBar = store.getSync(KEY_ALWAYS_SHOW_STATUS_BAR, TextReadingSettings.ALWAYS_SHOW_STATUS_BAR_DEFAULT);
    result.alwaysShowStatusBar = typeof statusBar === 'boolean' ? statusBar :
      TextReadingSettings.ALWAYS_SHOW_STATUS_BAR_DEFAULT;
    result.volumeKeyPageTurn = store.getSync('volume_key_page_turn', false) === true;
    result.followSystemTheme = store.getSync('follow_system_theme', true) !== false;
    const marginLeft = store.getSync('marginLeft', 16);
    result.marginLeft = TextReadingSettings.normalizeMargin(typeof marginLeft === 'number' ? marginLeft : 16, 16);
    const marginRight = store.getSync('marginRight', 16);
    result.marginRight = TextReadingSettings.normalizeMargin(typeof marginRight === 'number' ? marginRight : 16, 16);
    const marginTop = store.getSync('marginTop', 12);
    result.marginTop = TextReadingSettings.normalizeMargin(typeof marginTop === 'number' ? marginTop : 12, 12,
      TextReadingSettings.MARGIN_MAX_LIMIT);
    const marginBottom = store.getSync('marginBottom', 12);
    result.marginBottom = TextReadingSettings.normalizeMargin(typeof marginBottom === 'number' ? marginBottom : 12, 12);
    const weight = store.getSync('font_weight', 400);
    result.fontWeight = TextReadingSettings.normalizeFontWeight(typeof weight === 'number' ? weight : 400);
    const color = store.getSync('font_color', '');
    result.fontColor = typeof color === 'string' && color.length > 0 ? normalizeHex(color) : '';
    const imageBackground = store.getSync('image_background', result.customBackground);
    result.imageBackground = typeof imageBackground === 'string' ? normalizeHex(imageBackground) :
      TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
    const imageFontColor = store.getSync('image_font_color', result.fontColor);
    result.imageFontColor = typeof imageFontColor === 'string' && imageFontColor.length > 0 ?
      normalizeHex(imageFontColor) : '';
    // 旧全局字色转换为一套自定义主题，保留升级前的可见效果；预设今后保持原配色。
    if (store.getSync('theme_config_version', 0) !== 1 && result.themeId !== ReaderThemeId.Image &&
      result.themeId !== ReaderThemeId.Custom && result.fontColor.length > 0) {
      result.customBackground = resolvePalette(result.themeId, result.customBackground).background;
      result.themeId = ReaderThemeId.Custom;
      result.pattern = ReaderPattern.None;
    }
    const selectedCustomTheme = store.getSync('custom_theme_index', 0);
    result.customThemeIndex = ReaderCustomTheme.normalizeSlot(typeof selectedCustomTheme === 'number' ? selectedCustomTheme : 0);
    const customThemes = ReaderCustomTheme.defaults();
    for (let slot = 0; slot < customThemes.length; slot++) {
      const fallback = slot === result.customThemeIndex ?
        ReaderCustomTheme.of(slot, result.customBackground, result.fontColor) : customThemes[slot];
      const savedBackground = store.getSync(`custom_theme_${slot}_background`, fallback.background);
      const savedFontColor = store.getSync(`custom_theme_${slot}_font_color`, fallback.fontColor);
      customThemes[slot] = ReaderCustomTheme.of(slot,
        typeof savedBackground === 'string' ? savedBackground : fallback.background,
        typeof savedFontColor === 'string' ? savedFontColor : fallback.fontColor);
    }
    result.customThemes = customThemes;
    // 旧版单套配色进入第一个槽位。兼容字段始终镜像当前槽位。
    if (store.getSync('custom_themes_version', 0) === 1) {
      result.customBackground = customThemes[result.customThemeIndex].background;
      result.fontColor = customThemes[result.customThemeIndex].fontColor;
    }
    const fontPath = store.getSync('font_path', '');
    result.fontPath = typeof fontPath === 'string' ? fontPath : '';
    const fontName = store.getSync('font_name', '');
    result.fontName = typeof fontName === 'string' ? fontName : '';
    const minutes = store.getSync('screen_on_minutes', 0);
    result.screenOnMinutes = TextReadingSettings.normalizeScreenOnMinutes(typeof minutes === 'number' ? minutes : 0);
    return result;
  }

  static async save(context: common.Context, settings: TextReadingSettings): Promise<void> {
    await TextReadingSettingsService.init(context);
    const store = TextReadingSettingsService.store;
    if (store === null) return;
    store.putSync('tapLeftPercent', settings.tapLeftPercent);
    store.putSync('tapRightPercent', settings.tapRightPercent);
    store.putSync('tapTopPercent', settings.tapTopPercent);
    store.putSync('tapBottomPercent', settings.tapBottomPercent);
    store.putSync('showChapterBar', settings.showChapterBar);
    store.putSync('showBrightnessBar', settings.showBrightnessBar);
    store.putSync('reader_brightness', TextReadingSettings.normalizeBrightness(settings.brightness));
    store.putSync('showHeader', settings.showHeader);
    store.putSync('corner_layout', ReaderCornerLayout.normalize(settings.cornerLayout));
    store.putSync('showFooter', settings.showFooter);
    store.putSync('showChapterTitle', settings.showChapterTitle);
    store.putSync('showPageNumber', settings.showPageNumber);
    store.putSync('showChapterNumber', settings.showChapterNumber);
    store.putSync('showBookName', settings.showBookName);
    store.putSync('tap_regions', ReaderTapPolicy.normalize(settings.tapRegions));
    store.putSync('text_alignment', TextReadingSettings.normalizeTextAlignment(settings.textAlignment));
    store.putSync(KEY_FONT_SIZE, TextReadingSettings.normalizeFontSize(settings.fontSize));
    store.putSync(KEY_LINE_HEIGHT, TextReadingSettings.normalizeLineHeight(settings.lineHeight));
    store.putSync(KEY_PARAGRAPH_SPACING, TextReadingSettings.normalizeParagraphSpacing(settings.paragraphSpacing));
    store.putSync(KEY_THEME_ID, TextReadingSettings.normalizeThemeId(settings.themeId));
    store.putSync(KEY_CUSTOM_BACKGROUND, normalizeHex(settings.customBackground));
    store.putSync(KEY_PATTERN, TextReadingSettings.normalizePattern(settings.pattern));
    store.putSync(KEY_BACKGROUND_IMAGE, settings.backgroundImage);
    store.putSync('background_image_mode', TextReadingSettings.normalizeBackgroundImageMode(settings.backgroundImageMode));
    store.putSync(KEY_OVERLAY_ALPHA, TextReadingSettings.normalizeOverlay(settings.overlayAlpha));
    store.putSync(KEY_PAGE_TURN_MODE, TextReadingSettings.normalizePageTurnMode(settings.pageTurnMode));
    store.putSync(KEY_SHOW_READING_STATUS, settings.showReadingStatus);
    store.putSync(KEY_ALWAYS_SHOW_STATUS_BAR, settings.alwaysShowStatusBar);
    store.putSync('volume_key_page_turn', settings.volumeKeyPageTurn);
    store.putSync('follow_system_theme', settings.followSystemTheme);
    store.putSync('marginLeft', TextReadingSettings.normalizeMargin(settings.marginLeft, 16));
    store.putSync('marginRight', TextReadingSettings.normalizeMargin(settings.marginRight, 16));
    store.putSync('marginTop', TextReadingSettings.normalizeMargin(settings.marginTop, 12,
      TextReadingSettings.MARGIN_MAX_LIMIT));
    store.putSync('marginBottom', TextReadingSettings.normalizeMargin(settings.marginBottom, 12));
    store.putSync('font_weight', TextReadingSettings.normalizeFontWeight(settings.fontWeight));
    store.putSync('font_color', settings.fontColor.length > 0 ? normalizeHex(settings.fontColor) : '');
    store.putSync('image_background', normalizeHex(settings.imageBackground));
    store.putSync('image_font_color', settings.imageFontColor.length > 0 ? normalizeHex(settings.imageFontColor) : '');
    store.putSync('theme_config_version', 1);
    const selectedCustomTheme = ReaderCustomTheme.normalizeSlot(settings.customThemeIndex);
    const fallbackThemes = ReaderCustomTheme.defaults();
    for (let slot = 0; slot < 5; slot++) {
      const theme = slot === selectedCustomTheme ? ReaderCustomTheme.of(slot, settings.customBackground, settings.fontColor) :
        (settings.customThemes[slot] ?? fallbackThemes[slot]);
      store.putSync(`custom_theme_${slot}_background`, normalizeHex(theme.background));
      store.putSync(`custom_theme_${slot}_font_color`, normalizeHex(theme.fontColor));
    }
    store.putSync('custom_theme_index', selectedCustomTheme);
    store.putSync('custom_themes_version', 1);
    store.putSync('font_path', settings.fontPath);
    store.putSync('font_name', settings.fontName);
    store.putSync('screen_on_minutes', TextReadingSettings.normalizeScreenOnMinutes(settings.screenOnMinutes));
    await store.flush();
  }
}
