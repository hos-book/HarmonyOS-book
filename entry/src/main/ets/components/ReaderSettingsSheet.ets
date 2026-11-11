import { ReaderMarginSlider, ReaderEdgeTabs } from './ReaderMarginControls';
import { ReaderRegionStyle } from '../model/ReaderRegionStyle';
import { ReaderRegionStyleEditor } from './ReaderRegionStyleEditor';
import { SliderGestureModifier } from '../utils/SliderGestureModifier';
import { ReaderSettingCard, ReaderSettingsSectionHeader } from './ReaderSettingCard';
import { SettingsHintButton } from './SettingsHintButton';
import { ReaderAutoPageSettings } from './ReaderAutoPageSettings';
import { ReaderTapPolicy } from '../utils/ReaderTapPolicy';
import { ReaderImportedFont } from '../service/text/ReaderFontService';
import { ReaderFontTabs } from './ReaderFontTabs';
import { ReaderThemeEditor } from './ReaderThemeEditor';
import { MembershipState } from '../model/MembershipState';
import { ImmersiveOptionTabs } from './ImmersiveOptionTabs';
/**
 * ReaderSettingsSheet - 阅读设置面板
 *
 * 按鸿蒙分组卡片规范重排：字号 / 行高 / 翻页 / 主题设置卡。
 * 面板由 ReaderSettingsPopup 提供悬浮材质，内容文字跟随系统深浅模式。
 * 阅读纸张配色只影响正文与主题色样，不修改 App 的外观偏好。
 *
 * 本组件只负责呈现与回调，不落盘；持久化由 ReaderPage 统一做。
 */
import { AppColor, AppFont, AppRadius, AppSpace, AppMotion, AppCurve } from '../theme/Theme';
import { TextReadingSettings, PageTurnMode, ReaderCornerLayout, ReaderCornerContent } from '../model/TextReading';
import {
  ReaderPalette,
  ReaderPattern,
  ReaderImageMode,
  ReaderThemeId,
  ReaderThemePreset,
  ReaderCustomTheme,
  READER_THEME_PRESETS,
  resolvePalette
} from '../model/ReaderTheme';
import { ReaderBackground } from './ReaderBackground';

/** 按钮边界状态随参数刷新，避免多参数 Builder 保留首次 enabled 值。 */
@ComponentV2
struct ReaderSpacingStepButton {
  @Param decrease: boolean = false;
  @Param canStep: boolean = false;
  @Param idPrefix: string = 'reader-paragraph-spacing';
  @Event onStep: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      SymbolGlyph(this.decrease ? $r('sys.symbol.minus') : $r('sys.symbol.plus'))
        .fontSize(16).fontColor([$r('sys.color.font_primary')])
    }.width(34).height(34).backgroundColor(Color.Transparent).hoverEffect(HoverEffect.None)
      .enabled(this.canStep).opacity(this.canStep ? 1 : 0.4)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick((): void => this.onStep())
      .id(`${this.idPrefix}-${this.decrease ? 'minus' : 'plus'}`)
  }
}

/** 数值设置统一一行：名称、步进、滑条和当前值。 */
@ComponentV2
struct ReaderTypographySetting {
  @Param label: Resource = $r('app.string.reader_font_size');
  @Param settingValue: number = 0;
  @Param min: number = 0;
  @Param max: number = 100;
  @Param step: number = 1;
  @Param buttonStep: number = 1;
  @Param fractionDigits: number = 0;
  @Param idPrefix: string = 'reader-font-size';
  @Event onChange: (value: number, commit: boolean) => void = () => {};

  build() {
    ReaderSettingCard({ showTitle: false, compact: true }) {
      Row({ space: 4 }) {
        Text(this.label).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
          .maxLines(1).constraintSize({ minWidth: 28 })
        ReaderSpacingStepButton({ decrease: true, canStep: this.settingValue > this.min,
          idPrefix: this.idPrefix, onStep: (): void =>
            this.onChange(Math.max(this.min, this.settingValue - this.buttonStep), true) })
        Slider({ value: this.settingValue, min: this.min, max: this.max, step: this.step, style: SliderStyle.InSet })
          .attributeModifier(new SliderGestureModifier(this.min, this.max))
          .layoutWeight(1).height(40)
          .blockColor(AppColor.OnBrand).trackColor($r('sys.color.comp_divider'))
          .selectedColor(AppColor.Brand).trackThickness(6)
          .accessibilityText(this.label).id(this.idPrefix)
          .onChange((value: number, mode: SliderChangeMode): void =>
            this.onChange(value, mode === SliderChangeMode.End || mode === SliderChangeMode.Click))
        ReaderSpacingStepButton({ canStep: this.settingValue < this.max,
          idPrefix: this.idPrefix, onStep: (): void =>
            this.onChange(Math.min(this.max, this.settingValue + this.buttonStep), true) })
        Text(this.settingValue.toFixed(this.fractionDigits)).fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary')).fontWeight(FontWeight.Medium)
          .width(30).textAlign(TextAlign.End)
      }.width('100%').alignItems(VerticalAlign.Center)
    }
  }
}

@ComponentV2
struct ReaderThemeSwatch {
  @Param preset: ReaderThemePreset = new ReaderThemePreset();
  @Param selected: boolean = false;
  @Event onSelect: () => void = () => {};

  private themeLabel(): Resource {
    return this.preset.id === ReaderThemeId.Black ? $r('app.string.reader_pure_black') :
      this.preset.id === ReaderThemeId.Night ? $r('app.string.reader_theme_night') :
        $r('app.string.reader_theme_parchment');
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 6 }) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Column({ space: 5 }) {
            Text($r('app.string.reader_theme_sample_glyph'))
              .fontSize(24).fontWeight(FontWeight.Medium).fontColor(this.preset.primary)
            Row().width('70%').height(2).borderRadius(1).backgroundColor(this.preset.primary).opacity(0.2)
            Row().width('48%').height(2).borderRadius(1).backgroundColor(this.preset.primary).opacity(0.12)
          }.width('100%').height('100%').padding(12).alignItems(HorizontalAlign.Start)
          Stack() {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(10).fontColor([AppColor.OnBrand])
          }.width(18).height(18).borderRadius(9).backgroundColor(AppColor.Brand)
            .margin({ top: 6, right: 6 })
            .opacity(this.selected ? 1 : 0)
            .scale({ x: this.selected ? 1 : 0.6, y: this.selected ? 1 : 0.6 })
            .animation({ curve: AppCurve.Spring })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%').height(72).borderRadius(AppRadius.Md)
        .backgroundColor(this.preset.background)
        .border({ width: this.selected ? 2 : 0.5,
          color: this.selected ? AppColor.Brand : AppColor.GlassSheetStroke })
        .translate({ y: this.selected ? -2 : 0 })
        .animation({ curve: AppCurve.Spring })

        Text(this.themeLabel())
          .fontSize(AppFont.Caption)
          .fontColor(this.selected ? AppColor.Brand : $r('sys.color.font_secondary'))
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%').textAlign(TextAlign.Center)
      }
      .width('100%').alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1).padding(0).borderRadius(AppRadius.Md).backgroundColor(Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .accessibilityText(this.themeLabel()).accessibilitySelected(this.selected)
    .id(`reader-theme-preset-${this.preset.id}`)
    .onClick(() => this.onSelect())
  }
}

/** 每个槽位均有独立的应用和编辑入口；编辑不提前切换当前主题。 */
@ComponentV2
struct ReaderCustomThemeSwatch {
  @Param theme: ReaderCustomTheme = new ReaderCustomTheme();
  @Param selected: boolean = false;
  @Event onSelect: () => void = () => {};
  @Event onEdit: () => void = () => {};

  build() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        Column({ space: 4 }) {
          Stack() {
            ReaderBackground({ palette: resolvePalette(ReaderThemeId.Custom, this.theme.background, this.theme.fontColor),
              pattern: this.theme.backgroundImage.length > 0 ? ReaderPattern.Image : ReaderPattern.None,
              bgImagePath: this.theme.backgroundImage, imageMode: this.theme.imageMode, overlayAlpha: this.theme.overlayAlpha })
            Text($r('app.string.reader_theme_sample_glyph')).fontSize(24).fontColor(this.theme.fontColor)
          }.width('100%').height(56).borderRadius(AppRadius.Sm).clip(true)
            .border({ width: 0.5, color: AppColor.GlassSheetStroke })
          Column({ space: 4 }) {
            Text(this.theme.name || $r('app.string.reader_custom_theme_slot', this.theme.slot + 1))
              .fontSize(AppFont.Caption).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').textAlign(TextAlign.Center)
            Text(this.selected ? $r('app.string.reader_theme_in_use') : $r('app.string.reader_theme_tap_to_use'))
              .fontSize(11).fontColor(this.selected ? AppColor.Brand : $r('sys.color.font_secondary'))
              .maxLines(1).width('100%').textAlign(TextAlign.Center)
          }.width('100%').alignItems(HorizontalAlign.Center)
        }.width('100%').alignItems(HorizontalAlign.Center)
      }.width('100%').height(104).padding(0).borderRadius(AppRadius.Sm).backgroundColor(Color.Transparent)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
      .accessibilityText(this.theme.name || this.getUIContext().getHostContext()?.resourceManager.getStringSync(
        $r('app.string.reader_custom_theme_slot').id, this.theme.slot + 1) || '')
      .accessibilitySelected(this.selected).id(`reader-theme-custom-${this.theme.slot}`)
      .onClick((): void => this.onSelect())
      Button({ type: ButtonType.Capsule }) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(12).fontColor([$r('sys.color.font_secondary')])
          Text($r('app.string.reader_theme_edit')).fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
        }
      }.width('100%').height(32).padding({ left: 4, right: 4 })
        .backgroundColor(AppColor.GlassSheetControlTint)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
        .accessibilityText($r('app.string.reader_custom_theme_edit_slot', this.theme.slot + 1))
        .id(`reader-theme-edit-${this.theme.slot}`)
        .onClick((): void => this.onEdit())
    }.width('100%').padding(6).borderRadius(AppRadius.Md).alignItems(HorizontalAlign.Center)
      .backgroundColor(AppColor.GlassSheetControlTint)
      .border({ width: 1, color: this.selected ? AppColor.Brand : AppColor.GlassSheetStroke })
      .animation({ duration: AppMotion.Fast, curve: AppCurve.Standard })
  }
}

/** 独立响应式尺寸控件：拖动立即刷新数值，松手或步进时保存。 */
@ComponentV2
struct ReaderTapSizeSlider {
  @Param label: ResourceStr = '';
  @Param value: number = 33;
  @Param other: number = 33;
  @Local current: number = 33;
  @Event onChange: (value: number, commit: boolean) => void = () => {};

  aboutToAppear(): void { this.syncValue(); }

  @Monitor('value', 'other')
  syncValue(): void { this.current = ReaderTapPolicy.percent(this.value, this.other); }

  private update(value: number, commit: boolean): void {
    this.current = ReaderTapPolicy.percent(value, this.other);
    this.onChange(this.current, commit);
  }

  build() {
    Column({ space: 2 }) {
      Row() {
        Text(this.label).fontSize(13).fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Text(`${this.current}%`).fontSize(13).fontColor($r('sys.color.font_secondary'))
          .width(44).textAlign(TextAlign.End)
      }.width('100%')
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          SymbolGlyph($r('sys.symbol.minus')).fontSize(16).fontColor([$r('sys.color.font_primary')])
        }
        .width(34).height(34).backgroundColor(Color.Transparent).hoverEffect(HoverEffect.None)
        .enabled(this.current > 5).opacity(this.current > 5 ? 1 : 0.4)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
        .onClick((): void => this.update(this.current - 1, true))
        Slider({ value: this.current, min: 5, max: 90 - this.other, step: 1 })
          .attributeModifier(new SliderGestureModifier(5, 90 - this.other))
          .layoutWeight(1).selectedColor(AppColor.Brand)
          .onChange((next: number, mode: SliderChangeMode): void => {
            this.update(next, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
          })
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(16).fontColor([$r('sys.color.font_primary')])
        }
        .width(34).height(34).backgroundColor(Color.Transparent).hoverEffect(HoverEffect.None)
        .enabled(this.current < 90 - this.other).opacity(this.current < 90 - this.other ? 1 : 0.4)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
        .onClick((): void => this.update(this.current + 1, true))
      }.width('100%')
    }.width('100%')
  }
}

@ComponentV2
export struct ReaderSettingsSheet {
  @Param epubOriginalAvailable: boolean = false;
  @Param epubOriginalEnabled: boolean = false;
  @Param epubOriginalSwitching: boolean = false;
  @Param epubOriginalBookTitle: string = '';
  @Event onEpubOriginalSelect: () => void = () => {};
  @Param autoPageSeconds: number = 10;
  @Param autoScrolling: boolean = false;
  @Param autoScrollSpeed: number = 20;
  @Event onAutoScrollSpeed: (speed: number) => void = (): void => {};
  @Param autoPageRunning: boolean = false;
  @Param autoPagePaused: boolean = false;
  @Param autoPageAvailable: boolean = true;
  @Event onAutoPageInterval: (seconds: number) => void = (): void => {};
  @Event onAutoPageToggle: () => void = (): void => {};
  @Local marginEdge: number = 0;
  @Local tapSizeEdge: number = 0;
  @Local tapRegionsExpanded: boolean = false;
  @Param fontPanel: boolean = false;
  private settingsScroller: Scroller = new Scroller();
  @Param supportsSpeech: boolean = false;
  @Event onSpeechSettings: () => void = () => {};
  @Param fontWeight: number = 400;
  @Param textAlignment: string = 'justify';
  @Event onTextAlignmentChange: (value: string) => void = () => {};
  @Param fontFamily: string = '';
  @Param fonts: ReaderImportedFont[] = [];
  @Param fontPath: string = '';
  @Event onDeleteFont: (font: ReaderImportedFont) => void = () => {};
  @Event onSelectFont: (font: ReaderImportedFont) => void = () => {};
  @Param fontName: string = '';
  @Param screenOnMinutes: number = 0;
  @Local editingThemeIndex: number = -1;
  @Local membership: MembershipState = MembershipState.current;
  @Param customThemes: ReaderCustomTheme[] = ReaderCustomTheme.defaults();
  @Param customThemeIndex: number = 0;
  @Param effectiveThemeId: string = ReaderThemeId.Parchment;
  @Event onCustomThemeSave: (theme: ReaderCustomTheme) => Promise<boolean> = async () => false;
  @Event onCustomThemeSelect: (slot: number) => void = () => {};
  @Event onWeightChange: (weight: number, commit: boolean) => void = () => {};
  @Event onPickFont: () => void = () => {};
  @Event onSystemFont: () => void = () => {};
  @Event onScreenOnChange: (minutes: number) => void = () => {};
  @Param followSystemTheme: boolean = true;
  @Param linkedHorizontalMargins: boolean = false;
  @Param bodyColor: string = '';
  @Event onBodyColor: (color: string) => void = () => {};
  @Param headerStyle: ReaderRegionStyle = new ReaderRegionStyle();
  @Param footerStyle: ReaderRegionStyle = new ReaderRegionStyle();
  @Param headingLayout: ReaderRegionStyle = new ReaderRegionStyle();
  @Event onRegionStyle: (region: string, style: ReaderRegionStyle) => void = () => {};
  @Param marginLeft: number = 16;
  @Param marginRight: number = 16;
  @Param marginTop: number = 12;
  @Param marginBottom: number = 12;
  /** 上边距滑杆上限：由阅读页按视口高度一半传入 */
  @Param marginTopMax: number = 64;
  @Event onFollowSystemChange: (enabled: boolean) => void = () => {};
  @Event onMarginChange: (edge: string, value: number, commit: boolean) => void = () => {};
  @Param fontSize: number = TextReadingSettings.FONT_SIZE_DEFAULT;
  @Param lineHeight: number = TextReadingSettings.LINE_HEIGHT_DEFAULT;
  @Param paragraphSpacing: number = TextReadingSettings.PARAGRAPH_SPACING_DEFAULT;
  @Param letterSpacing: number = 0;
  @Event onLetterSpacingChange: (value: number, commit: boolean) => void = () => {};
  @Param paragraphSpacingEnabled: boolean = true;
  @Param chapterHeadingVisible: boolean = true;
  @Param chapterHeadingSize: number = 26;
  @Event onChapterHeadingVisibleChange: (visible: boolean) => void = () => {};
  @Event onChapterHeadingSizeChange: (value: number, commit: boolean) => void = () => {};
  @Event onParagraphSpacingChange: (value: number, commit: boolean) => void = () => {};
  @Param themeId: string = ReaderThemeId.Parchment;
  @Param pattern: string = ReaderPattern.None;
  @Param bgImagePath: string = '';
  @Param imageMode: ReaderImageMode = ReaderImageMode.Cover;
  @Param supportsImageMode: boolean = true;
  @Param overlayAlpha: number = TextReadingSettings.OVERLAY_DEFAULT;
  @Param tapRegions: string = ReaderTapPolicy.DEFAULT;
  @Param tapLeftPercent: number = 33;
  @Param tapRightPercent: number = 33;
  @Param tapTopPercent: number = 33;
  @Param tapBottomPercent: number = 33;
  @Param showChapterBar: boolean = true;
  @Param showBrightnessBar: boolean = true;
  @Param showHeader: boolean = true;
  @Param cornerLayout: string = ReaderCornerLayout.DEFAULT;
  @Event onCornerChange: (corner: number, content: number) => void = () => {};
  @Param showFooter: boolean = true;
  @Param showPageRules: boolean = true;
  @Param showChapterTitle: boolean = true;
  @Param showPageNumber: boolean = true;
  @Param showChapterNumber: boolean = true;
  @Param showBookName: boolean = true;
  @Event onTapSizeChange: (edge: string, value: number, commit: boolean) => void = () => {};
  @Event onResetTapAreas: () => void = () => {};
  @Event onChromeChange: (field: string, value: boolean) => void = () => {};
  @Event onTapRegionsChange: (value: string) => void = () => {};
  @Param volumeKeyPageTurn: boolean = false;
  @Event onVolumeKeyPageTurnChange: (enabled: boolean) => void = () => {};
  @Param pageTurnMode: string = PageTurnMode.Cover;
  @Param pageTurnHaptic: string = 'none';
  @Event onPageTurnHapticChange: (value: string) => void = () => {};
  @Param showReadingStatus: boolean = TextReadingSettings.SHOW_READING_STATUS_DEFAULT;
  @Param alwaysShowStatusBar: boolean = TextReadingSettings.ALWAYS_SHOW_STATUS_BAR_DEFAULT;
  /** 由父页面依 themeId / customBackground 解析好的配色 */
  @Param palette: ReaderPalette = new ReaderPalette();

  @Event onFontSizeChange: (value: number, commit: boolean) => void = () => {};
  @Event onLineHeightChange: (value: number, commit: boolean) => void = () => {};
  @Event onThemeChange: (themeId: string) => void = () => {};
  @Event onPageTurnModeChange: (mode: string) => void = () => {};
  @Event onReadingStatusChange: (enabled: boolean) => void = () => {};
  @Event onStatusBarChange: (enabled: boolean) => void = () => {};
  /** 请求打开相册选图；由页面侧执行 picker + 落沙箱 */
  @Event onPickImage: () => Promise<string> = async () => '';
  @Event onDiscardImage: (path: string) => void = () => {};
  @Event onResetDefaults: () => void = () => {};
  @Event onClose: () => void = () => {};

  @Builder
  buildFontSizeSection() {
    ReaderTypographySetting({ label: $r('app.string.reader_font_size'), settingValue: this.fontSize,
      min: TextReadingSettings.FONT_SIZE_MIN, max: TextReadingSettings.FONT_SIZE_MAX,
      onChange: (value: number, commit: boolean): void => this.onFontSizeChange(value, commit) })
  }

  @Builder
  buildLineHeightSection() {
    ReaderTypographySetting({ label: $r('app.string.reader_line_height'), settingValue: this.lineHeight,
      min: TextReadingSettings.LINE_HEIGHT_MIN, max: TextReadingSettings.LINE_HEIGHT_MAX,
      step: 0.1, buttonStep: 0.1, fractionDigits: 1, idPrefix: 'reader-line-height',
      onChange: (value: number, commit: boolean): void =>
        this.onLineHeightChange(TextReadingSettings.normalizeLineHeight(value), commit) })
  }

  @Builder
  buildParagraphSpacingSection() {
    ReaderTypographySetting({ label: $r('app.string.reader_paragraph_spacing'), settingValue: this.paragraphSpacing,
      min: TextReadingSettings.PARAGRAPH_SPACING_MIN, max: TextReadingSettings.PARAGRAPH_SPACING_MAX,
      step: 0.1, buttonStep: 0.1, fractionDigits: 1, idPrefix: 'reader-paragraph-spacing',
      onChange: (value: number, commit: boolean): void =>
        this.onParagraphSpacingChange(TextReadingSettings.normalizeParagraphSpacing(value), commit) })
  }

  @Builder
  buildLetterSpacingSection() {
    ReaderTypographySetting({ label: $r('app.string.reader_letter_spacing'), settingValue: this.letterSpacing,
      min: 0, max: 10, step: 0.5, buttonStep: 0.5, fractionDigits: 1, idPrefix: 'reader-letter-spacing',
      onChange: (value: number, commit: boolean): void =>
        this.onLetterSpacingChange(TextReadingSettings.normalizeLetterSpacing(value), commit) })
  }

  @Builder
  buildChapterHeadingSection() {
    ReaderSettingCard({ showTitle: false, compact: true }) {
      Column({ space: 8 }) {
        Row() {
          Text($r('app.string.reader_region_heading'))
            .fontSize(AppFont.Body).fontColor($r('sys.color.font_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.chapterHeadingVisible })
            .selectedColor(AppColor.Brand)
            .onChange((visible: boolean): void => this.onChapterHeadingVisibleChange(visible))
            .id('reader-heading-visible')
        }.width('100%')
        if (this.chapterHeadingVisible) {
          Row({ space: AppSpace.Sm }) {
            Text($r('app.string.reader_chapter_heading_size')).fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_primary')).width(56)
            ReaderSpacingStepButton({ decrease: true, canStep: this.chapterHeadingSize > TextReadingSettings.CHAPTER_HEADING_MIN,
              idPrefix: 'reader-heading-size',
              onStep: (): void => this.onChapterHeadingSizeChange(this.chapterHeadingSize - 1, true) })
            Slider({ value: this.chapterHeadingSize, min: TextReadingSettings.CHAPTER_HEADING_MIN,
              max: TextReadingSettings.CHAPTER_HEADING_MAX, step: 1, style: SliderStyle.InSet })
              .attributeModifier(new SliderGestureModifier(TextReadingSettings.CHAPTER_HEADING_MIN, TextReadingSettings.CHAPTER_HEADING_MAX))
              .layoutWeight(1).height(40)
              .blockColor(AppColor.OnBrand).trackColor($r('sys.color.comp_divider'))
              .selectedColor(AppColor.Brand).trackThickness(6)
              .accessibilityText($r('app.string.reader_chapter_heading_size'))
              .onChange((value: number, mode: SliderChangeMode): void =>
                this.onChapterHeadingSizeChange(value, mode === SliderChangeMode.End || mode === SliderChangeMode.Click))
              .id('reader-heading-size')
            ReaderSpacingStepButton({ canStep: this.chapterHeadingSize < TextReadingSettings.CHAPTER_HEADING_MAX,
              idPrefix: 'reader-heading-size',
              onStep: (): void => this.onChapterHeadingSizeChange(this.chapterHeadingSize + 1, true) })
            Text(`${this.chapterHeadingSize}`).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium).width(28).textAlign(TextAlign.End).id('reader-heading-size-value')
          }.width('100%')
          ReaderRegionStyleEditor({ title: $r('app.string.reader_region_heading'),
            groupId: 'reader-heading-edge', framed: false, showTitle: false, value: this.headingLayout,
            onChange: (style: ReaderRegionStyle): void => this.onRegionStyle('heading', style) })
        }
      }.width('100%')
    }
  }

  /** 图片属于自定义主题；可用数量随已核验的权益变化。 */
  @Builder
  buildThemeSection() {
    ReaderSettingCard({ compact: true, title: $r('app.string.reader_theme_title') }) {
      Column({ space: AppSpace.Sm }) {
        Text($r('app.string.reader_preset_themes')).fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary')).width('100%')
        Row({ space: AppSpace.Sm }) {
          ForEach(
            READER_THEME_PRESETS.filter((preset: ReaderThemePreset): boolean => preset.id !== ReaderThemeId.EyeCare),
            (preset: ReaderThemePreset) => {
              ReaderThemeSwatch({
                preset: preset,
                selected: !this.epubOriginalEnabled && this.effectiveThemeId === preset.id,
                onSelect: () => this.onThemeChange(preset.id)
              })
            },
            (preset: ReaderThemePreset) => `theme-${preset.id}`
          )
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        if (this.epubOriginalAvailable) {
          Row({ space: AppSpace.Sm }) {
            SymbolGlyph($r('sys.symbol.book')).fontSize(26).fontColor([AppColor.Brand])
            Column({ space: 3 }) {
              Text($r('app.string.reader_epub_original_theme')).fontSize(AppFont.Body)
                .fontColor($r('sys.color.font_primary'))
              Text(this.epubOriginalBookTitle).fontSize(AppFont.Caption).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('sys.color.font_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            if (this.epubOriginalSwitching) {
              LoadingProgress().width(22).height(22).color(AppColor.Brand)
            } else if (this.epubOriginalEnabled) {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(22).fontColor([AppColor.Brand])
            }
          }.width('100%').padding(12).borderRadius(AppRadius.Md)
            .backgroundColor(AppColor.GlassSheetControlTint)
            .border({ width: this.epubOriginalEnabled ? 1.5 : 0, color: AppColor.Brand })
            .enabled(!this.epubOriginalSwitching)
            .onClick((): void => this.onEpubOriginalSelect())
            .accessibilityText($r('app.string.reader_epub_original_theme'))
            .accessibilitySelected(this.epubOriginalEnabled).id('reader-theme-epub-original')
          Text($r('app.string.reader_epub_original_hint')).fontSize(12)
            .fontColor($r('sys.color.font_secondary')).width('100%')
        }

        Column({ space: 4 }) {
          Row({ space: AppSpace.Xs }) {
            Text($r('app.string.reader_custom_theme')).fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary')).layoutWeight(1)
            Text($r('app.string.reader_custom_theme_available', ReaderCustomTheme.limit(this.membership.hasAccess)))
              .fontSize(10).fontColor($r('sys.color.font_secondary'))
          }.width('100%')
          Text($r('app.string.reader_custom_theme_limit')).fontSize(11)
            .fontColor($r('sys.color.font_secondary')).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start).margin({ top: 4 })
        List({ space: 8 }) {
          ForEach(this.customThemes.filter((theme: ReaderCustomTheme): boolean =>
            ReaderCustomTheme.canUse(theme.slot, this.membership.hasAccess)), (theme: ReaderCustomTheme) => {
            ListItem() {
              ReaderCustomThemeSwatch({ theme: this.customThemes[theme.slot],
                selected: !this.epubOriginalEnabled && this.effectiveThemeId === ReaderThemeId.Custom && this.customThemeIndex === theme.slot,
                onSelect: (): void => this.onCustomThemeSelect(theme.slot),
                onEdit: (): void => {
                  if (ReaderCustomTheme.canUse(theme.slot, this.membership.hasAccess)) this.editingThemeIndex = theme.slot;
                } })
            }.width('calc((100% - 16vp) / 3)')
          }, (theme: ReaderCustomTheme): string => theme.id)
        }.width('100%').height(152).listDirection(Axis.Horizontal).scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring).id('reader-custom-theme-list')
        Divider().strokeWidth(0.5).color(AppColor.GlassSheetStroke)
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.reader_follow_system')).fontSize(AppFont.Body).layoutWeight(1)
            .fontColor($r('sys.color.font_primary'))
          Toggle({ type: ToggleType.Switch, isOn: this.followSystemTheme })
            .selectedColor(AppColor.Brand)
            .accessibilityText($r('app.string.reader_follow_system')).id('reader-theme-follow-system')
            .onChange((enabled: boolean): void => this.onFollowSystemChange(enabled))
        }.width('100%').constraintSize({ minHeight: 40 }).alignItems(VerticalAlign.Center)
        if (this.followSystemTheme) {
          Text($r('app.string.reader_follow_system_theme_hint')).fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary')).width('100%')
        }
      }
      .width('100%')
    }
  }

  @Builder
  buildTextAlignmentSection() {
    ReaderSettingCard({ compact: true, title: $r('app.string.reader_alignment_title'), inline: true }) {
      ImmersiveOptionTabs({
        labels: [$r('app.string.reader_alignment_justify'), $r('app.string.reader_alignment_start'),
          $r('app.string.reader_alignment_center'), $r('app.string.reader_alignment_end')],
        selected: ['justify', 'start', 'center', 'end'].indexOf(this.textAlignment),
        onSelect: (index: number): void => this.onTextAlignmentChange(['justify', 'start', 'center', 'end'][index])
      })
    }
  }

  /** 翻页模式：覆盖、仿真 */
  @Builder
  buildPageTurnModeSection() {
    ReaderSettingCard({ compact: true, title: $r('app.string.reader_turn_title'), inline: true }) {
      ImmersiveOptionTabs({
        labels: [$r('app.string.reader_turn_none'), $r('app.string.reader_turn_cover'),
          $r('app.string.reader_turn_simulation'), $r('app.string.reader_vertical_turn')],
        selected: ['none', 'cover', 'simulation', 'vertical'].indexOf(this.pageTurnMode),
        onSelect: (index: number): void => this.onPageTurnModeChange(
          [PageTurnMode.None, PageTurnMode.Cover, PageTurnMode.Simulation, PageTurnMode.Vertical][index])
      })
    }
  }

  @Builder
  buildPageTurnHapticSection() {
    ReaderSettingCard({ compact: true, title: $r('app.string.reader_turn_haptic'), inline: true }) {
      ImmersiveOptionTabs({
        labels: [$r('app.string.reader_turn_none'), $r('app.string.reader_haptic_strong'),
          $r('app.string.reader_haptic_medium'), $r('app.string.reader_haptic_weak')],
        selected: ['none', 'strong', 'medium', 'weak'].indexOf(this.pageTurnHaptic),
        onSelect: (index: number): void => this.onPageTurnHapticChange(['none', 'strong', 'medium', 'weak'][index])
      }).id('reader-page-turn-haptic')
    }
  }

  private tapRegionLabel(index: number): Resource {
    const action = Number(ReaderTapPolicy.normalize(this.tapRegions).charAt(index));
    if (action === 0) return $r('app.string.reader_tap_previous');
    if (action === 1) return $r('app.string.reader_tap_toolbar');
    if (action === 2) return $r('app.string.reader_tap_next');
    return $r('app.string.reader_tap_none');
  }

  @Builder
  buildTapRegionsSection() {
    ReaderSettingCard({ compact: true, showTitle: false }) {
      Column({ space: 8 }) {
        Row({ space: 2 }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: AppSpace.Sm }) {
            Text($r('app.string.reader_tap_title'))
              .fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
              .fontWeight(FontWeight.Medium).layoutWeight(1).textAlign(TextAlign.Start)
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14).fontColor([$r('sys.color.font_secondary')])
              .rotate({ angle: this.tapRegionsExpanded ? 180 : 0 })
              .animation({ duration: AppMotion.Fast, curve: AppCurve.Standard })
          }.width('100%')
        }.layoutWeight(1).height(32).padding(0).borderRadius(8)
          .backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.reader_tap_title'))
          .accessibilityDescription(this.tapRegionsExpanded ? $r('app.string.reader_tap_collapse') :
            $r('app.string.reader_tap_expand'))
          .onClick((): void => { this.tapRegionsExpanded = !this.tapRegionsExpanded; })
          .id('reader-tap-regions-toggle')
        SettingsHintButton({ title: $r('app.string.reader_tap_title'), message: $r('app.string.reader_tap_hint') })
        }.width('100%')
        if (this.tapRegionsExpanded) {
          Column({ space: 4 }) {
            ForEach([0, 1, 2], (row: number) => {
              Row({ space: 4 }) {
                ForEach([0, 1, 2], (column: number) => {
                  Button(this.tapRegionLabel(row * 3 + column), { type: ButtonType.Normal })
                    .layoutWeight(column === 0 ? this.tapLeftPercent : column === 2 ? this.tapRightPercent :
                      100 - this.tapLeftPercent - this.tapRightPercent).height('100%').borderRadius(8).fontSize(11)
                    .fontColor($r('sys.color.font_primary'))
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .onClick((): void => this.onTapRegionsChange(ReaderTapPolicy.cycle(this.tapRegions, row * 3 + column)))
                }, (column: number): string => `column-${column}`)
              }.width('100%').layoutWeight(row === 0 ? this.tapTopPercent : row === 2 ? this.tapBottomPercent :
                100 - this.tapTopPercent - this.tapBottomPercent)
            }, (row: number): string => `row-${row}`)
          }.width('100%').height(210)
          ReaderEdgeTabs({ selected: this.tapSizeEdge, groupId: 'reader-tap-edge',
            onSelect: (index: number): void => { this.tapSizeEdge = index; } })
          if (this.tapSizeEdge === 2) {
            ReaderTapSizeSlider({
              label: $r('app.string.reader_tap_left_width'), value: this.tapLeftPercent, other: this.tapRightPercent,
              onChange: (value: number, commit: boolean): void => this.onTapSizeChange('left', value, commit)
            })
          } else if (this.tapSizeEdge === 3) {
            ReaderTapSizeSlider({
              label: $r('app.string.reader_tap_right_width'), value: this.tapRightPercent, other: this.tapLeftPercent,
              onChange: (value: number, commit: boolean): void => this.onTapSizeChange('right', value, commit)
            })
          } else if (this.tapSizeEdge === 0) {
            ReaderTapSizeSlider({
              label: $r('app.string.reader_tap_top_height'), value: this.tapTopPercent, other: this.tapBottomPercent,
              onChange: (value: number, commit: boolean): void => this.onTapSizeChange('top', value, commit)
            })
          } else {
            ReaderTapSizeSlider({
              label: $r('app.string.reader_tap_bottom_height'), value: this.tapBottomPercent, other: this.tapTopPercent,
              onChange: (value: number, commit: boolean): void => this.onTapSizeChange('bottom', value, commit)
            })
          }
          Button($r('app.string.reader_tap_reset'))
            .fontSize(12).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
            .onClick((): void => this.onResetTapAreas())
        }
      }.width('100%')
    }
  }

  @Builder
  chromeToggle(label: Resource, field: string, value: boolean) {
    Row() {
      Text(label).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary')).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor(AppColor.Brand)
        .onChange((enabled: boolean): void => this.onChromeChange(field, enabled))
    }.width('100%')
  }

  @Builder
  buildHeaderSection() {
    ReaderSettingCard({ compact: true, title: $r('app.string.reader_show_brightness_bar'), inline: true }) {
      Toggle({ type: ToggleType.Switch, isOn: this.showBrightnessBar }).selectedColor(AppColor.Brand)
        .onChange((enabled: boolean): void => this.onChromeChange('showBrightnessBar', enabled))
    }
    ReaderSettingCard({ compact: true, title: $r('app.string.reader_show_chapter_bar'), inline: true }) {
      Toggle({ type: ToggleType.Switch, isOn: this.showChapterBar }).selectedColor(AppColor.Brand)
        .onChange((enabled: boolean): void => this.onChromeChange('showChapterBar', enabled))
    }
    ReaderSettingCard({ compact: true, showTitle: false }) {
      Column({ space: 8 }) {
        this.chromeToggle($r('app.string.reader_show_header'), 'showHeader', this.showHeader)
        if (this.showHeader) {
          this.cornerSelector(0)
          this.cornerSelector(1)
        }
      }.width('100%')
    }
    ReaderSettingCard({ compact: true, title: $r('app.string.reader_show_page_rules'), inline: true }) {
      Toggle({ type: ToggleType.Switch, isOn: this.showPageRules }).selectedColor(AppColor.Brand)
        .id('reader-show-page-rules')
        .accessibilityText($r('app.string.reader_show_page_rules'))
        .onChange((enabled: boolean): void => this.onChromeChange('showPageRules', enabled))
    }
  }

  private cornerLabel(corner: number): Resource {
    if (corner === 0) return $r('app.string.reader_corner_top_left');
    if (corner === 1) return $r('app.string.reader_corner_top_right');
    if (corner === 2) return $r('app.string.reader_corner_bottom_left');
    return $r('app.string.reader_corner_bottom_right');
  }

  private cornerValue(corner: number): Resource {
    switch (ReaderCornerLayout.content(this.cornerLayout, corner)) {
      case ReaderCornerContent.ChapterTitle: return $r('app.string.reader_show_chapter_title');
      case ReaderCornerContent.PageNumber: return $r('app.string.reader_show_page_number');
      case ReaderCornerContent.ChapterNumber: return $r('app.string.reader_show_chapter_number');
      default: return $r('app.string.reader_show_book_name');
    }
  }

  private cornerEnabled(corner: number): boolean {
    switch (ReaderCornerLayout.content(this.cornerLayout, corner)) {
      case ReaderCornerContent.ChapterTitle: return this.showChapterTitle;
      case ReaderCornerContent.PageNumber: return this.showPageNumber;
      case ReaderCornerContent.ChapterNumber: return this.showChapterNumber;
      default: return this.showBookName;
    }
  }

  private setCornerEnabled(corner: number, enabled: boolean): void {
    switch (ReaderCornerLayout.content(this.cornerLayout, corner)) {
      case ReaderCornerContent.ChapterTitle: this.onChromeChange('showChapterTitle', enabled); break;
      case ReaderCornerContent.PageNumber: this.onChromeChange('showPageNumber', enabled); break;
      case ReaderCornerContent.ChapterNumber: this.onChromeChange('showChapterNumber', enabled); break;
      case ReaderCornerContent.BookName: this.onChromeChange('showBookName', enabled); break;
    }
  }

  @Builder
  cornerSelector(corner: number) {
    Row({ space: AppSpace.Sm }) {
      Text(this.cornerLabel(corner))
        .fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
      Select([
        { value: $r('app.string.reader_show_chapter_title') },
        { value: $r('app.string.reader_show_page_number') },
        { value: $r('app.string.reader_show_chapter_number') },
        { value: $r('app.string.reader_show_book_name') }
      ])
        .selected(ReaderCornerLayout.content(this.cornerLayout, corner))
        .value(this.cornerValue(corner))
        .font({ size: AppFont.Caption })
        .layoutWeight(1)
        .accessibilityText(this.cornerLabel(corner))
        .onSelect((content: number): void => this.onCornerChange(corner, content))
      Toggle({ type: ToggleType.Switch, isOn: this.cornerEnabled(corner) })
        .selectedColor(AppColor.Brand)
        .accessibilityText(this.cornerLabel(corner))
        .onChange((enabled: boolean): void => this.setCornerEnabled(corner, enabled))
    }.width('100%')
  }

  @Builder
  buildMarginSection() {
    ReaderSettingCard({ compact: true, showTitle: false }) {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text($r('app.string.reader_margins')).fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
        ReaderEdgeTabs({ selected: this.marginEdge, groupId: 'reader-margin-edge',
          onSelect: (index: number): void => { this.marginEdge = index; } })
          .layoutWeight(1)
        }.width('100%')
        if (this.linkedHorizontalMargins) {
          Text($r('app.string.reader_margin_columns_linked'))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary')).width('100%')
        }
        if (this.marginEdge === 2) {
        ReaderMarginSlider({
          label: $r('app.string.reader_margin_left'), value: this.marginLeft,
          onChange: (value: number, commit: boolean): void => this.onMarginChange('left', value, commit)
        })
        } else if (this.marginEdge === 3) {
        ReaderMarginSlider({
          label: $r('app.string.reader_margin_right'), value: this.marginRight,
          onChange: (value: number, commit: boolean): void => this.onMarginChange('right', value, commit)
        })
        } else if (this.marginEdge === 0) {
        ReaderMarginSlider({
          label: $r('app.string.reader_margin_top'), value: this.marginTop, max: this.marginTopMax,
          onChange: (value: number, commit: boolean): void => this.onMarginChange('top', value, commit)
        })
        } else {
        ReaderMarginSlider({
          label: $r('app.string.reader_margin_bottom'), value: this.marginBottom,
          onChange: (value: number, commit: boolean): void => this.onMarginChange('bottom', value, commit)
        })
        }
      }.width('100%')
    }
  }

  @Builder
  buildStatusBarSection() {
    ReaderSettingCard({ compact: true, inline: true, title: $r('app.string.reader_status_bar_always'),
      description: $r('app.string.reader_status_bar_hint') }) {
      Toggle({ type: ToggleType.Switch, isOn: this.alwaysShowStatusBar })
        .selectedColor(AppColor.Brand)
        .onChange((enabled: boolean): void => this.onStatusBarChange(enabled))
    }
  }

  @Builder
  buildReadingStatusSection() {
    ReaderSettingCard({ compact: true, showTitle: false }) {
      Column({ space: 8 }) {
      this.chromeToggle($r('app.string.reader_show_footer'), 'showFooter', this.showFooter)
      if (this.showFooter) {
      this.cornerSelector(2)
      this.cornerSelector(3)
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.reader_show_battery_time'))
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.showReadingStatus })
          .selectedColor(AppColor.Brand)
          .onChange((enabled: boolean): void => this.onReadingStatusChange(enabled))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      }
      }.width('100%')
    }
  }

  @Builder
  buildFontWeightSection() {
    if (this.fontPath.length === 0) {
      ReaderTypographySetting({ label: $r('app.string.reader_font_weight'), settingValue: this.fontWeight,
        min: 100, max: 900, buttonStep: 100, idPrefix: 'reader-font-weight',
        onChange: (value: number, commit: boolean): void =>
          this.onWeightChange(TextReadingSettings.normalizeFontWeight(value), commit) })
    }
  }

  @Builder
  buildFontAppearance() {
    ReaderSettingCard({ compact: true, title: $r('app.string.reader_custom_font_title'), inline: true }) {
      ReaderFontTabs({ fonts: this.fonts, selectedPath: this.fontPath,
        onSelect: (font: ReaderImportedFont): void => this.onSelectFont(font),
        onDelete: (font: ReaderImportedFont): void => this.onDeleteFont(font) })
        .width('76%')
    }
  }

  @Builder
  buildScreenOnSection() {
    ReaderSettingCard({ compact: true, title: $r('app.string.reader_screen_on'), inline: true }) {
      ImmersiveOptionTabs({
        labels: [$r('app.string.reader_screen_system'), $r('app.string.reader_screen_minutes', 1),
          $r('app.string.reader_screen_minutes', 5), $r('app.string.reader_screen_minutes', 10),
          $r('app.string.reader_screen_always')],
        selected: [0, 1, 5, 10, -1].indexOf(this.screenOnMinutes),
        onSelect: (index: number): void => this.onScreenOnChange([0, 1, 5, 10, -1][index])
      })
    }
  }

  aboutToDisappear(): void {
    this.editingThemeIndex = -1;
    this.tapRegionsExpanded = false;
  }

  @Monitor('fontPanel')
  private onPanelTabChanged(): void {
    this.editingThemeIndex = -1;
    try { this.settingsScroller.scrollTo({ xOffset: 0, yOffset: 0 }); } catch (_error) { }
  }

  build() {
    Column() {
      if (this.editingThemeIndex >= 0) {
        ReaderThemeEditor({ theme: this.customThemes[this.editingThemeIndex],
          supportsImageMode: this.supportsImageMode,
          onPickImage: (): Promise<string> => this.onPickImage(),
          onDiscardImage: (path: string): void => this.onDiscardImage(path),
          fontSize: this.fontSize, fontFamily: this.fontFamily, fontWeight: this.fontWeight, lineHeight: this.lineHeight,
          onSave: (theme: ReaderCustomTheme): Promise<boolean> => this.onCustomThemeSave(theme),
          onCancel: (): void => { this.editingThemeIndex = -1; } })
      } else {

      Row() {
        Text(this.fontPanel ? $r('app.string.reader_font_theme_title') : $r('app.string.reader_settings'))
          .fontSize(18)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('恢复默认')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: 6, bottom: 6 })
          .borderRadius(AppRadius.Pill)
          .backgroundColor(AppColor.GlassSheetControlTint)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
          .onClick(() => this.onResetDefaults())
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .margin({ left: AppSpace.Xs })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
        .accessibilityText($r('app.string.common_close')).id('reader-settings-close')
        .onClick(() => this.onClose())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 8, top: 4, bottom: 4 })

      Scroll(this.settingsScroller) {
        Column({ space: 6 }) {
          if (this.fontPanel) {
            ReaderSettingsSectionHeader({ title: $r('app.string.reader_settings_theme_group') })
            this.buildThemeSection()
            if (this.epubOriginalEnabled) {
              Text($r('app.string.reader_epub_original_custom_hint'))
                .fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
            }
            ReaderSettingsSectionHeader({ title: $r('app.string.reader_settings_font_group') })
            this.buildFontAppearance()
            this.buildFontSizeSection()
            this.buildFontWeightSection()
            ReaderSettingsSectionHeader({ title: $r('app.string.reader_settings_paragraph_group') })
            this.buildTextAlignmentSection()
            this.buildLineHeightSection()
            if (this.paragraphSpacingEnabled) {
              this.buildParagraphSpacingSection()
              this.buildLetterSpacingSection()
            }
            ReaderSettingsSectionHeader({ title: $r('app.string.reader_settings_display_group') })
            this.buildMarginSection()
            ReaderSettingCard({ compact: true, title: $r('app.string.reader_region_body_color') }) {
              TextInput({ text: this.bodyColor, placeholder: $r('app.string.reader_region_color_hint') }).maxLength(7)
                .onChange((color: string): void => {
                  if (color === '' || /^#[0-9a-fA-F]{6}$/.test(color)) this.onBodyColor(color);
                })
            }
            this.buildChapterHeadingSection()
            ReaderRegionStyleEditor({ title: $r('app.string.reader_region_header'), groupId: 'reader-header-edge', value: this.headerStyle,
              onChange: (style: ReaderRegionStyle): void => this.onRegionStyle('header', style) })
            ReaderRegionStyleEditor({ title: $r('app.string.reader_region_footer'), groupId: 'reader-footer-edge', value: this.footerStyle,
              onChange: (style: ReaderRegionStyle): void => this.onRegionStyle('footer', style) })
          } else {
            ReaderSettingsSectionHeader({ title: $r('app.string.reader_settings_turn_group') })
            this.buildPageTurnModeSection()
            this.buildPageTurnHapticSection()
            ReaderSettingCard({ compact: true, title: $r('app.string.reader_volume_key_turn'), inline: true,
              description: $r('app.string.reader_volume_key_hint') }) {
              Toggle({ type: ToggleType.Switch, isOn: this.volumeKeyPageTurn })
                .selectedColor(AppColor.Brand)
                .onChange((enabled: boolean): void => this.onVolumeKeyPageTurnChange(enabled))
            }
            this.buildTapRegionsSection()
            ReaderAutoPageSettings({ compact: true, seconds: this.autoPageSeconds, running: this.autoPageRunning, paused: this.autoPagePaused,
              scrolling: this.autoScrolling, speed: this.autoScrollSpeed, onSpeed: this.onAutoScrollSpeed,
              available: this.autoPageAvailable, onInterval: this.onAutoPageInterval, onToggle: this.onAutoPageToggle })
            ReaderSettingsSectionHeader({ title: $r('app.string.reader_settings_display_group') })
            this.buildStatusBarSection()
            this.buildHeaderSection()
            this.buildReadingStatusSection()
            ReaderSettingsSectionHeader({ title: $r('app.string.reader_settings_assistance_group') })
            this.buildScreenOnSection()
            if (this.supportsSpeech) {
              ReaderSettingCard({ compact: true, title: $r('app.string.tts_title'), inline: true }) {
                Button($r('app.string.reader_speech_display')).fontColor(AppColor.Brand)
                  .backgroundColor(AppColor.GlassSheetControlTint)
                  .onClick((): void => this.onSpeechSettings()).id('reader-speech-display-settings')
              }
            }
          }
        }
        .width('100%')
        .padding({
          left: 10,
          right: 10,
          bottom: 10
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
  }
}
