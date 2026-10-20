import { ReaderSettingCard } from './ReaderSettingCard';
import { ReaderTapPolicy } from '../utils/ReaderTapPolicy';
import { ReaderImportedFont } from '../service/text/ReaderFontService';
import { ReaderFontTabs } from './ReaderFontTabs';
import { ReaderThemeEditor } from './ReaderThemeEditor';
import { ImmersiveOptionTabs } from './ImmersiveOptionTabs';
/**
 * ReaderSettingsSheet - 阅读设置面板
 *
 * 按鸿蒙分组卡片规范重排：顶部实时预览 + 字号 / 行高 / 翻页 / 主题设置卡。
 * 面板由父页面的原生 bindSheet 提供材质，内容文字跟随系统深浅模式。
 * 阅读纸张配色只影响正文与预览，不修改 App 的外观偏好。
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
  hexLuminance
} from '../model/ReaderTheme';
import { ReaderBackground } from './ReaderBackground';

/** 行高预设档位 */
class LineHeightPreset {
  label: string = '';
  value: number = 1.9;

  static of(label: string, value: number): LineHeightPreset {
    const preset = new LineHeightPreset();
    preset.label = label;
    preset.value = value;
    return preset;
  }
}

const LINE_HEIGHT_PRESETS: LineHeightPreset[] = [
  LineHeightPreset.of('紧凑', 1.5),
  LineHeightPreset.of('适中', 1.7),
  LineHeightPreset.of('标准', 1.9),
  LineHeightPreset.of('宽松', 2.2)
];

/** 按钮边界状态随参数刷新，避免多参数 Builder 保留首次 enabled 值。 */
@ComponentV2
struct ReaderSpacingStepButton {
  @Param decrease: boolean = false;
  @Param canStep: boolean = false;
  @Event onStep: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(this.decrease ? $r('sys.symbol.minus') : $r('sys.symbol.plus'))
        .fontSize(16).fontColor([$r('sys.color.font_primary')])
    }.width(34).height(34).backgroundColor(AppColor.GlassSheetControlTint)
      .enabled(this.canStep).opacity(this.canStep ? 1 : 0.4)
      .onClick((): void => this.onStep())
      .id(this.decrease ? 'reader-paragraph-spacing-minus' : 'reader-paragraph-spacing-plus')
  }
}

/** 分档按钮使用 @Param 观察选中态，避免 @Builder 按值参数停留在首次渲染。 */
@ComponentV2
struct ReaderSettingChip {
  @Param label: ResourceStr = '';
  @Param selected: boolean = false;
  @Event onSelect: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(AppFont.Caption)
      .fontColor($r('sys.color.font_primary'))
      .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .borderRadius(AppRadius.Pill)
      .backgroundColor(this.selected ? $r('sys.color.comp_background_tertiary') : AppColor.GlassSheetControlTint)
      .border({ width: this.selected ? 1 : 0, color: $r('sys.color.font_primary') })
      .animation({ duration: AppMotion.Fast, curve: AppCurve.Standard })
      .onClick(() => this.onSelect())
  }
}

@ComponentV2
struct ReaderThemeSwatch {
  @Param preset: ReaderThemePreset = new ReaderThemePreset();
  @Param selected: boolean = false;
  @Event onSelect: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.preset.background)
          .border({
            width: this.selected ? 2 : 0.5,
            color: this.selected ? AppColor.Brand : AppColor.GlassSheetStroke
          })
        if (this.selected) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(17)
            .fontColor([this.preset.isDark ? '#FFFFFF' : '#2A2724'])
        }
      }
      .width(44)
      .height(44)

      Text(this.preset.id === ReaderThemeId.Black ? $r('app.string.reader_pure_black') :
        this.preset.id === ReaderThemeId.Night ? $r('app.string.reader_theme_night') : $r('app.string.reader_theme_parchment'))
        .fontSize(10)
        .fontColor(this.selected ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Center)
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
    Column({ space: 6 }) {
      Button() {
        Text(this.selected ? '✓' : 'Aa').fontSize(16).fontColor(this.theme.fontColor)
      }.width(42).height(42).borderRadius(21).backgroundColor(this.theme.background)
      .border({ width: this.selected ? 2 : 0.5, color: this.selected ? AppColor.Brand : AppColor.GlassSheetStroke })
      .accessibilityText($r('app.string.reader_custom_theme_slot', this.theme.slot + 1))
      .onClick((): void => this.onSelect())
      Text($r('app.string.reader_custom_theme_slot', this.theme.slot + 1))
        .fontSize(12).fontColor($r('sys.color.font_primary'))
        .onClick((): void => this.onSelect())
      Button($r('app.string.reader_theme_edit')).height(30).fontSize(12)
        .padding({ left: 10, right: 10 }).fontColor($r('sys.color.font_secondary'))
        .backgroundColor(AppColor.GlassSheetControlTint)
        .accessibilityText($r('app.string.reader_custom_theme_edit_slot', this.theme.slot + 1))
        .onClick((): void => this.onEdit())
    }.layoutWeight(1)
  }
}

@ComponentV2
struct ReaderMarginSlider {
  @Param label: ResourceStr = '';
  @Param value: number = 16;
  @Param max: number = 64;
  @Event onChange: (value: number, commit: boolean) => void = () => {};

  @Builder
  stepper(icon: Resource, enabled: boolean, delta: number) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([$r('sys.color.font_primary')])
    }
    .width(34)
    .height(34)
    .backgroundColor(AppColor.GlassSheetControlTint)
    .enabled(enabled)
    .opacity(enabled ? 1 : 0.4)
    .onClick((): void => {
      this.onChange(Math.max(0, Math.min(this.max, this.value + delta)), true);
    })
  }

  build() {
    Row({ space: AppSpace.Sm }) {
      Text(this.label).fontSize(AppFont.Caption).width(36).fontColor($r('sys.color.font_primary'))
      this.stepper($r('sys.symbol.minus'), this.value > 0, -1)
      Slider({ value: this.value, min: 0, max: this.max, step: 1 })
        .layoutWeight(1).selectedColor(AppColor.Brand)
        .onChange((next: number, mode: SliderChangeMode): void => {
          this.onChange(next, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
        })
      this.stepper($r('sys.symbol.plus'), this.value < this.max, 1)
      Text(`${this.value}`).width(36).fontColor($r('sys.color.font_primary')).fontSize(AppFont.Caption)
    }.width('100%')
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
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.minus')).fontSize(16).fontColor([$r('sys.color.font_primary')])
        }
        .width(34).height(34).backgroundColor(AppColor.GlassSheetControlTint)
        .enabled(this.current > 5).opacity(this.current > 5 ? 1 : 0.4)
        .onClick((): void => this.update(this.current - 1, true))
        Slider({ value: this.current, min: 5, max: 90 - this.other, step: 1 })
          .layoutWeight(1).selectedColor(AppColor.Brand)
          .onChange((next: number, mode: SliderChangeMode): void => {
            this.update(next, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
          })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(16).fontColor([$r('sys.color.font_primary')])
        }
        .width(34).height(34).backgroundColor(AppColor.GlassSheetControlTint)
        .enabled(this.current < 90 - this.other).opacity(this.current < 90 - this.other ? 1 : 0.4)
        .onClick((): void => this.update(this.current + 1, true))
      }.width('100%')
    }.width('100%')
  }
}

@ComponentV2
export struct ReaderSettingsSheet {
  @Param fontPanel: boolean = false;
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
  @Param customThemes: ReaderCustomTheme[] = ReaderCustomTheme.defaults();
  @Param customThemeIndex: number = 0;
  @Param imageFontColor: string = '';
  @Param effectiveThemeId: string = ReaderThemeId.Parchment;
  @Event onCustomThemeSave: (slot: number, background: string, fontColor: string) => void = () => {};
  @Event onCustomThemeSelect: (slot: number) => void = () => {};
  @Event onImageTextChange: (light: boolean) => void = () => {};
  @Event onWeightChange: (weight: number, commit: boolean) => void = () => {};
  @Event onPickFont: () => void = () => {};
  @Event onSystemFont: () => void = () => {};
  @Event onScreenOnChange: (minutes: number) => void = () => {};
  @Param followSystemTheme: boolean = false;
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
  @Param paragraphSpacingEnabled: boolean = true;
  @Event onParagraphSpacingChange: (value: number, commit: boolean) => void = () => {};
  @Param themeId: string = ReaderThemeId.Parchment;
  @Param pattern: string = ReaderPattern.None;
  @Param bgImagePath: string = '';
  @Param imageMode: ReaderImageMode = ReaderImageMode.Cover;
  @Param supportsImageMode: boolean = true;
  @Event onImageModeChange: (mode: ReaderImageMode) => void = () => {};
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
  @Param showReadingStatus: boolean = TextReadingSettings.SHOW_READING_STATUS_DEFAULT;
  @Param alwaysShowStatusBar: boolean = TextReadingSettings.ALWAYS_SHOW_STATUS_BAR_DEFAULT;
  /** 由父页面依 themeId / customBackground 解析好的配色 */
  @Param palette: ReaderPalette = new ReaderPalette();

  @Event onFontSizeChange: (value: number, commit: boolean) => void = () => {};
  @Event onLineHeightChange: (value: number, commit: boolean) => void = () => {};
  @Event onThemeChange: (themeId: string) => void = () => {};
  @Event onOverlayChange: (value: number, commit: boolean) => void = () => {};
  @Event onPageTurnModeChange: (mode: string) => void = () => {};
  @Event onReadingStatusChange: (enabled: boolean) => void = () => {};
  @Event onStatusBarChange: (enabled: boolean) => void = () => {};
  /** 请求打开相册选图；由页面侧执行 picker + 落沙箱 */
  @Event onPickImage: () => void = () => {};
  @Event onResetDefaults: () => void = () => {};
  @Event onClose: () => void = () => {};

  /** 实时预览：真实字号、行高、底色与图片，所见即所得 */
  @Builder
  buildPreview() {
    Stack() {
      ReaderBackground({
        palette: this.palette,
        pattern: this.pattern,
        bgImagePath: this.bgImagePath,
        imageMode: this.imageMode,
        overlayAlpha: this.overlayAlpha
      })

      Column({ space: 6 }) {
        Row() {
          Text('第十二章 归客')
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.primary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('3/24')
            .fontSize(AppFont.Caption)
            .fontColor(this.palette.primary)
        }
        .width('100%')

        Column({ space: this.getUIContext().px2vp(this.getUIContext().fp2px(this.fontSize)) * this.paragraphSpacing }) {
          ForEach([
            $r('app.string.reader_paragraph_preview_first'),
            $r('app.string.reader_paragraph_preview_second')
          ], (paragraph: Resource) => {
            Text(paragraph)
              .width('100%')
              .fontSize(this.fontSize)
              .fontFamily(this.fontFamily.length > 0 ? this.fontFamily : undefined)
              .fontWeight(this.fontWeight, { enableVariableFontWeight: true })
              .fontColor(this.palette.primary)
              .lineHeight(this.getUIContext().px2vp(this.getUIContext().fp2px(this.fontSize)) * this.lineHeight)
              .textAlign(this.textAlignment === 'start' ? TextAlign.Start :
                this.textAlignment === 'center' ? TextAlign.Center :
                this.textAlignment === 'end' ? TextAlign.End : TextAlign.JUSTIFY)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }, (paragraph: Resource): string => `${paragraph.id}`)
        }
        .width('100%')
        .layoutWeight(1)
        .clip(true)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 18, right: 18, top: AppSpace.Sm, bottom: AppSpace.Sm })
    }
    .width('100%')
    .height(180)
    .borderRadius(AppRadius.Lg)
    .clip(true)
    .border({ width: 0.5, color: ReaderPalette.withAlpha(this.palette.primary, 0x1f) })
  }

  /** 字号：左右步进 + 滑杆，步进按钮到边界自动置灰 */
  @Builder
  buildFontSizeSection() {
    ReaderSettingCard({ title: '字号', compact: true }) {
      Row({ space: AppSpace.Sm }) {
        this.stepper($r('sys.symbol.minus'), this.fontSize > TextReadingSettings.FONT_SIZE_MIN, () => {
          this.onFontSizeChange(this.fontSize - 1, true);
        })

        Slider({
          value: this.fontSize,
          min: TextReadingSettings.FONT_SIZE_MIN,
          max: TextReadingSettings.FONT_SIZE_MAX,
          step: 1,
          style: SliderStyle.InSet
        })
          .layoutWeight(1)
          .height(40)
          .blockColor(AppColor.OnBrand)
          .trackColor($r('sys.color.comp_divider'))
          .selectedColor(AppColor.Brand)
          .trackThickness(6)
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.onFontSizeChange(value, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
          })

        this.stepper($r('sys.symbol.plus'), this.fontSize < TextReadingSettings.FONT_SIZE_MAX, () => {
          this.onFontSizeChange(this.fontSize + 1, true);
        })

        Text(`${this.fontSize}`)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .width(28)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  /** 圆形步进按钮 */
  @Builder
  stepper(icon: Resource, enabled: boolean, onTap: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([enabled ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary')])
    }
    .width(34)
    .height(34)
    .borderRadius(17)
    .backgroundColor(AppColor.GlassSheetControlTint)
    .opacity(enabled ? 1 : 0.4)
    .onClick(() => {
      if (enabled) onTap();
    })
  }

  /** 当前行高是否命中某个预设档（容差 0.05，避免浮点误差导致选中态丢失） */
  private isLineHeightPreset(value: number): boolean {
    return Math.abs(this.lineHeight - value) < 0.05;
  }

  /** 行高：四档快选 + 滑杆微调，两者双向同步 */
  @Builder
  buildLineHeightSection() {
    ReaderSettingCard({ title: '行高', compact: true }) {
      Column({ space: 6 }) {
        Row({ space: AppSpace.Xs }) {
          ForEach(
            LINE_HEIGHT_PRESETS,
            (preset: LineHeightPreset) => {
              ReaderSettingChip({
                label: preset.label,
                selected: this.isLineHeightPreset(preset.value),
                onSelect: () => this.onLineHeightChange(preset.value, true)
              })
            },
            (preset: LineHeightPreset) => `lh-${preset.label}`
          )
        }
        .width('100%')

        Row({ space: AppSpace.Sm }) {
          this.stepper($r('sys.symbol.minus'), this.lineHeight > TextReadingSettings.LINE_HEIGHT_MIN, () => {
            this.onLineHeightChange(TextReadingSettings.normalizeLineHeight(this.lineHeight - 0.1), true);
          })

          Slider({
            value: this.lineHeight,
            min: TextReadingSettings.LINE_HEIGHT_MIN,
            max: TextReadingSettings.LINE_HEIGHT_MAX,
            step: 0.1,
            style: SliderStyle.InSet
          })
            .layoutWeight(1)
            .height(40)
            .blockColor(AppColor.OnBrand)
            .trackColor($r('sys.color.comp_divider'))
            .selectedColor(AppColor.Brand)
            .trackThickness(6)
            .onChange((value: number, mode: SliderChangeMode): void => {
              this.onLineHeightChange(value, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
            })

          this.stepper($r('sys.symbol.plus'), this.lineHeight < TextReadingSettings.LINE_HEIGHT_MAX, () => {
            this.onLineHeightChange(TextReadingSettings.normalizeLineHeight(this.lineHeight + 0.1), true);
          })

          Text(`${this.lineHeight.toFixed(1)}`)
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
            .width(28)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
    }
  }

  @Builder
  buildParagraphSpacingSection() {
    ReaderSettingCard({ title: $r('app.string.reader_paragraph_spacing'), compact: true }) {
      Row({ space: AppSpace.Sm }) {
        ReaderSpacingStepButton({ decrease: true,
          canStep: this.paragraphSpacing > TextReadingSettings.PARAGRAPH_SPACING_MIN, onStep: (): void => {
          this.onParagraphSpacingChange(TextReadingSettings.normalizeParagraphSpacing(this.paragraphSpacing - 0.1), true);
        } })
        Slider({
          value: this.paragraphSpacing,
          min: TextReadingSettings.PARAGRAPH_SPACING_MIN,
          max: TextReadingSettings.PARAGRAPH_SPACING_MAX,
          step: 0.1,
          style: SliderStyle.InSet
        })
          .layoutWeight(1)
          .height(40)
          .blockColor(AppColor.OnBrand)
          .trackColor($r('sys.color.comp_divider'))
          .selectedColor(AppColor.Brand)
          .trackThickness(6)
          .accessibilityText($r('app.string.reader_paragraph_spacing'))
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.onParagraphSpacingChange(value, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
          })
        ReaderSpacingStepButton({ canStep: this.paragraphSpacing < TextReadingSettings.PARAGRAPH_SPACING_MAX,
          onStep: (): void => {
          this.onParagraphSpacingChange(TextReadingSettings.normalizeParagraphSpacing(this.paragraphSpacing + 0.1), true);
        } })
        Text(`${this.paragraphSpacing.toFixed(1)}`)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .width(28)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  /** 预设主题与自定义图片互斥，图片主题内保留换图和蒙层。 */
  @Builder
  buildThemeSection() {
    ReaderSettingCard({ title: $r('app.string.reader_theme_title') }) {
      Column({ space: AppSpace.Sm }) {
        Text($r('app.string.reader_preset_themes')).fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary')).width('100%')
        Row({ space: AppSpace.Sm }) {
          ForEach(
            READER_THEME_PRESETS.filter((preset: ReaderThemePreset): boolean => preset.id !== ReaderThemeId.EyeCare),
            (preset: ReaderThemePreset) => {
              ReaderThemeSwatch({
                preset: preset,
                selected: this.effectiveThemeId === preset.id,
                onSelect: () => this.onThemeChange(preset.id)
              })
            },
            (preset: ReaderThemePreset) => `theme-${preset.id}`
          )
          this.buildImageThemeSwatch()
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .justifyContent(FlexAlign.SpaceBetween)

        if (this.effectiveThemeId === ReaderThemeId.Image) {
          this.buildImageControls()
        }
        Text($r('app.string.reader_custom_theme')).fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary')).width('100%').margin({ top: AppSpace.Sm })
        Row({ space: AppSpace.Sm }) {
          ForEach(this.customThemes, (theme: ReaderCustomTheme) => {
            ReaderCustomThemeSwatch({ theme: theme,
              selected: this.effectiveThemeId === ReaderThemeId.Custom && this.customThemeIndex === theme.slot,
              onSelect: (): void => this.onCustomThemeSelect(theme.slot),
              onEdit: (): void => { this.editingThemeIndex = theme.slot; } })
          }, (theme: ReaderCustomTheme): string => theme.id)
        }.width('100%')
        Row() {
          Text($r('app.string.reader_follow_system')).layoutWeight(1)
            .fontColor($r('sys.color.font_primary'))
          Toggle({ type: ToggleType.Switch, isOn: this.followSystemTheme })
            .selectedColor(AppColor.Brand)
            .onChange((enabled: boolean): void => this.onFollowSystemChange(enabled))
        }.width('100%')
        if (this.followSystemTheme) {
          Text($r('app.string.reader_follow_system_theme_hint')).fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary')).width('100%')
        }
      }
      .width('100%')
    }
  }

  @Builder
  buildImageThemeSwatch() {
    Column({ space: 6 }) {
      Column({ space: 6 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(20)
            .fontColor([this.effectiveThemeId === ReaderThemeId.Image ? $r('sys.color.font_primary') : $r('sys.color.font_secondary')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(AppColor.GlassSheetControlTint)
        .border({
          width: this.effectiveThemeId === ReaderThemeId.Image ? 2 : 0.5,
          color: this.effectiveThemeId === ReaderThemeId.Image ? AppColor.Brand : AppColor.GlassSheetStroke
        })
        .margin({ top: 2, bottom: 2 })

        Text($r('app.string.reader_custom_image'))
          .fontSize(10)
          .fontColor(this.effectiveThemeId === ReaderThemeId.Image ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => this.onThemeChange(ReaderThemeId.Image))

      if (this.bgImagePath.length > 0) {
        Button($r('app.string.reader_change_image'))
          .fontSize(AppFont.Caption).fontColor($r('sys.color.font_primary'))
          .height(32).padding({ left: 10, right: 10 })
          .backgroundColor(AppColor.GlassSheetControlTint)
          .onClick((): void => this.onPickImage())
      }
    }
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildImageControls() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.reader_image_text')).fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary')).layoutWeight(1)
        ImmersiveOptionTabs({ labels: [$r('app.string.reader_text_dark'), $r('app.string.reader_text_light')],
          selected: hexLuminance(this.imageFontColor.length > 0 ? this.imageFontColor : this.palette.primary) > 0.55 ? 1 : 0,
          onSelect: (index: number): void => this.onImageTextChange(index === 1) })
      }.width('100%')
      if (this.supportsImageMode) {
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.reader_image_mode')).fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          ImmersiveOptionTabs({
            labels: [$r('app.string.reader_image_contain'), $r('app.string.reader_image_tile'),
              $r('app.string.reader_image_stretch'), $r('app.string.reader_image_cover')],
            selected: [ReaderImageMode.Contain, ReaderImageMode.Tile, ReaderImageMode.Stretch,
              ReaderImageMode.Cover].indexOf(this.imageMode),
            onSelect: (index: number): void => this.onImageModeChange(
              [ReaderImageMode.Contain, ReaderImageMode.Tile, ReaderImageMode.Stretch,
                ReaderImageMode.Cover][index] ?? ReaderImageMode.Cover)
          })
        }.width('100%')
        Text(this.imageModeHint())
          .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary')).width('100%')
      }
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.reader_image_overlay'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .width(30)
        Slider({
          value: this.overlayAlpha * 100,
          min: TextReadingSettings.OVERLAY_MIN * 100,
          max: TextReadingSettings.OVERLAY_MAX * 100,
          step: 1,
          style: SliderStyle.InSet
        })
          .layoutWeight(1)
          .height(32)
          .blockColor(AppColor.OnBrand)
          .trackColor($r('sys.color.comp_divider'))
          .selectedColor(AppColor.Brand)
          .trackThickness(4)
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.onOverlayChange(value / 100,
              mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
          })
        Text(`${Math.round(this.overlayAlpha * 100)}%`)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_primary'))
          .width(34)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text($r('app.string.reader_image_overlay_hint'))
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
    }
    .width('100%')
  }

  private imageModeHint(): ResourceStr {
    if (this.imageMode === ReaderImageMode.Contain) return $r('app.string.reader_image_contain_hint');
    if (this.imageMode === ReaderImageMode.Tile) return $r('app.string.reader_image_tile_hint');
    if (this.imageMode === ReaderImageMode.Stretch) return $r('app.string.reader_image_stretch_hint');
    return $r('app.string.reader_image_cover_hint');
  }

  @Builder
  buildTextAlignmentSection() {
    ReaderSettingCard({ title: $r('app.string.reader_alignment_title'), inline: true }) {
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
    ReaderSettingCard({ title: $r('app.string.reader_turn_title'), inline: true }) {
      ImmersiveOptionTabs({
        labels: [$r('app.string.reader_turn_none'), $r('app.string.reader_turn_cover'),
          $r('app.string.reader_turn_simulation'), $r('app.string.reader_vertical_turn')],
        selected: ['none', 'cover', 'simulation', 'vertical'].indexOf(this.pageTurnMode),
        onSelect: (index: number): void => this.onPageTurnModeChange(
          [PageTurnMode.None, PageTurnMode.Cover, PageTurnMode.Simulation, PageTurnMode.Vertical][index])
      })
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
    ReaderSettingCard({ title: $r('app.string.reader_tap_title') }) {
      Column({ space: 8 }) {
        Text($r('app.string.reader_tap_hint'))
          .fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
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
        ReaderTapSizeSlider({
          label: $r('app.string.reader_tap_left_width'), value: this.tapLeftPercent, other: this.tapRightPercent,
          onChange: (value: number, commit: boolean): void => this.onTapSizeChange('left', value, commit)
        })
        ReaderTapSizeSlider({
          label: $r('app.string.reader_tap_right_width'), value: this.tapRightPercent, other: this.tapLeftPercent,
          onChange: (value: number, commit: boolean): void => this.onTapSizeChange('right', value, commit)
        })
        ReaderTapSizeSlider({
          label: $r('app.string.reader_tap_top_height'), value: this.tapTopPercent, other: this.tapBottomPercent,
          onChange: (value: number, commit: boolean): void => this.onTapSizeChange('top', value, commit)
        })
        ReaderTapSizeSlider({
          label: $r('app.string.reader_tap_bottom_height'), value: this.tapBottomPercent, other: this.tapTopPercent,
          onChange: (value: number, commit: boolean): void => this.onTapSizeChange('bottom', value, commit)
        })
        Button($r('app.string.reader_tap_reset'))
          .fontSize(12).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
.onClick((): void => this.onResetTapAreas())
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
    ReaderSettingCard({ title: $r('app.string.reader_show_brightness_bar'), inline: true }) {
      Toggle({ type: ToggleType.Switch, isOn: this.showBrightnessBar }).selectedColor(AppColor.Brand)
        .onChange((enabled: boolean): void => this.onChromeChange('showBrightnessBar', enabled))
    }
    ReaderSettingCard({ title: $r('app.string.reader_show_chapter_bar'), inline: true }) {
      Toggle({ type: ToggleType.Switch, isOn: this.showChapterBar }).selectedColor(AppColor.Brand)
        .onChange((enabled: boolean): void => this.onChromeChange('showChapterBar', enabled))
    }
    ReaderSettingCard({ title: $r('app.string.reader_header_title') }) {
      Column({ space: 8 }) {
        this.chromeToggle($r('app.string.reader_show_header'), 'showHeader', this.showHeader)
        if (this.showHeader) {
          this.cornerSelector(0)
          this.cornerSelector(1)
        }
      }.width('100%')
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
    ReaderSettingCard({ title: $r('app.string.reader_margins') }) {
      Column() {
        ReaderMarginSlider({
          label: $r('app.string.reader_margin_left'), value: this.marginLeft,
          onChange: (value: number, commit: boolean): void => this.onMarginChange('left', value, commit)
        })
        ReaderMarginSlider({
          label: $r('app.string.reader_margin_right'), value: this.marginRight,
          onChange: (value: number, commit: boolean): void => this.onMarginChange('right', value, commit)
        })
        ReaderMarginSlider({
          label: $r('app.string.reader_margin_top'), value: this.marginTop, max: this.marginTopMax,
          onChange: (value: number, commit: boolean): void => this.onMarginChange('top', value, commit)
        })
        ReaderMarginSlider({
          label: $r('app.string.reader_margin_bottom'), value: this.marginBottom,
          onChange: (value: number, commit: boolean): void => this.onMarginChange('bottom', value, commit)
        })
      }.width('100%')
    }
  }

  @Builder
  buildStatusBarSection() {
    ReaderSettingCard({ title: $r('app.string.reader_status_bar_title') }) {
      Row({ space: AppSpace.Sm }) {
        Column({ space: AppSpace.Xxs }) {
          Text($r('app.string.reader_status_bar_always'))
            .fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
          Text($r('app.string.reader_status_bar_hint'))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.alwaysShowStatusBar })
          .selectedColor(AppColor.Brand)
          .onChange((enabled: boolean): void => this.onStatusBarChange(enabled))
      }.width('100%').alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  buildReadingStatusSection() {
    ReaderSettingCard({ title: $r('app.string.reader_footer_title') }) {
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
    ReaderSettingCard({ title: $r('app.string.reader_font_weight'), compact: true }) {
      Row({ space: AppSpace.Sm }) {
        this.stepper($r('sys.symbol.minus'), this.fontWeight > 100, () => {
          this.onWeightChange(TextReadingSettings.normalizeFontWeight(this.fontWeight - 100), true);
        })
        Slider({ value: this.fontWeight, min: 100, max: 900, step: 1, style: SliderStyle.InSet })
          .layoutWeight(1).height(40)
          .blockColor(AppColor.OnBrand).trackColor($r('sys.color.comp_divider'))
          .selectedColor(AppColor.Brand).trackThickness(6)
          .onChange((value: number, mode: SliderChangeMode): void => this.onWeightChange(value,
            mode === SliderChangeMode.End || mode === SliderChangeMode.Click))
        this.stepper($r('sys.symbol.plus'), this.fontWeight < 900, () => {
          this.onWeightChange(TextReadingSettings.normalizeFontWeight(this.fontWeight + 100), true);
        })
        Text(`${this.fontWeight}`)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .width(28)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    }
  }

  @Builder
  buildFontAppearance() {
    ReaderSettingCard({ title: $r('app.string.reader_custom_font_title'), inline: true }) {
      ReaderFontTabs({ fonts: this.fonts, selectedPath: this.fontPath,
        onSelect: (font: ReaderImportedFont): void => this.onSelectFont(font),
        onDelete: (font: ReaderImportedFont): void => this.onDeleteFont(font) })
        .width('68%')
    }
      Row({ space: AppSpace.Sm }) {
        Button($r('app.string.reader_import_font')).fontColor($r('sys.color.font_primary'))
          .backgroundColor(AppColor.GlassSheetControlTint).onClick((): void => this.onPickFont())
      }
      Text($r('app.string.reader_import_font_hint')).fontSize(12).fontColor($r('sys.color.font_secondary'))
  }

  @Builder
  buildScreenOnSection() {
    ReaderSettingCard({ title: $r('app.string.reader_screen_on'), inline: true }) {
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
  }

  build() {
    Column() {
      if (this.editingThemeIndex >= 0) {
        ReaderThemeEditor({ themeSlot: this.editingThemeIndex,
          themeBackground: this.customThemes[this.editingThemeIndex].background,
          fontColor: this.customThemes[this.editingThemeIndex].fontColor,
          fontSize: this.fontSize, fontFamily: this.fontFamily, fontWeight: this.fontWeight, lineHeight: this.lineHeight,
          onSave: (background: string, fontColor: string): void => {
            this.onCustomThemeSave(this.editingThemeIndex, background, fontColor);
            this.editingThemeIndex = -1;
          },
          onCancel: (): void => { this.editingThemeIndex = -1; } })
      } else {

      Row() {
        Text(this.fontPanel ? $r('app.string.reader_font_theme_title') : $r('app.string.reader_settings'))
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('恢复默认')
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: 6, bottom: 6 })
          .borderRadius(AppRadius.Pill)
          .backgroundColor(AppColor.GlassSheetControlTint)
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
        .onClick(() => this.onClose())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: AppSpace.Lg, right: AppSpace.Md, bottom: AppSpace.Sm })

      if (this.fontPanel) {
        Column() {
          this.buildPreview()
        }.width('100%').padding({ left: AppSpace.Lg, right: AppSpace.Lg, bottom: 8 })
      }

      Scroll() {
        Column({ space: this.fontPanel ? 8 : AppSpace.Md }) {
          if (this.fontPanel) {
            this.buildThemeSection()
            this.buildFontSizeSection()
            this.buildLineHeightSection()
            if (this.paragraphSpacingEnabled) {
              this.buildParagraphSpacingSection()
            }
            this.buildFontWeightSection()
            this.buildTextAlignmentSection()
            this.buildFontAppearance()
          } else {
            this.buildPageTurnModeSection()
            if (this.supportsSpeech) {
              ReaderSettingCard({ title: $r('app.string.tts_custom_import'), inline: true }) {
                Button($r('app.string.reader_tts_manage')).fontColor(AppColor.Brand)
                  .backgroundColor(AppColor.GlassSheetControlTint)
                  .onClick((): void => this.onSpeechSettings()).id('reader-tts-settings')
              }
            }
            ReaderSettingCard({ title: $r('app.string.reader_volume_key_turn'), inline: true }) {
              Toggle({ type: ToggleType.Switch, isOn: this.volumeKeyPageTurn })
                .selectedColor(AppColor.Brand)
                .onChange((enabled: boolean): void => this.onVolumeKeyPageTurnChange(enabled))
            }
            Text($r('app.string.reader_volume_key_hint'))
              .fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
            this.buildMarginSection()
            this.buildScreenOnSection()
            this.buildStatusBarSection()
            this.buildHeaderSection()
            this.buildReadingStatusSection()
            this.buildTapRegionsSection()
          }
        }
        .width('100%')
        .padding({
          left: AppSpace.Lg,
          right: AppSpace.Lg,
          bottom: AppSpace.Lg
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
