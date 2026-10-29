import { ReaderColorPalette } from './ReaderColorPalette';
import { ReaderBackground } from './ReaderBackground';
import { ImmersiveOptionTabs } from './ImmersiveOptionTabs';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { TextReadingSettings } from '../model/TextReading';
import { ReaderThemeId, ReaderCustomTheme, ReaderPattern, ReaderImageMode, resolvePalette,
  readerColorContrast, recommendedReaderFontColor } from '../model/ReaderTheme';

/** 草稿只在本组件内存在；返回、关闭弹层与取消都不会更改阅读设置。 */
@ComponentV2
export struct ReaderThemeEditor {
  @Param theme: ReaderCustomTheme = new ReaderCustomTheme();
  @Param supportsImageMode: boolean = true;
  @Param fontSize: number = TextReadingSettings.FONT_SIZE_DEFAULT;
  @Param fontFamily: string = '';
  @Param fontWeight: number = 400;
  @Param lineHeight: number = TextReadingSettings.LINE_HEIGHT_DEFAULT;
  @Event onSave: (theme: ReaderCustomTheme) => Promise<boolean> = async () => false;
  @Event onPickImage: () => Promise<string> = async () => '';
  @Event onDiscardImage: (path: string) => void = () => {};
  @Event onCancel: () => void = () => {};
  @Local draftBackground: string = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
  @Local draftFontColor: string = '#2D2925';
  @Local draftName: string = '';
  @Local draftImage: string = '';
  @Local draftImageMode: ReaderImageMode = ReaderImageMode.Cover;
  @Local draftOverlay: number = TextReadingSettings.OVERLAY_DEFAULT;
  @Local picking: boolean = false;
  @Local saving: boolean = false;
  private active: boolean = false;
  private importedImages: string[] = [];
  @Local editingBackground: boolean = false;
  @Local colorInputValid: boolean = true;
  @Local colorInputRevision: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.draftBackground = this.theme.background;
    this.draftFontColor = this.theme.fontColor;
    this.draftName = this.theme.name;
    this.draftImage = this.theme.backgroundImage;
    this.draftImageMode = this.theme.imageMode;
    this.draftOverlay = this.theme.overlayAlpha;
  }

  aboutToDisappear(): void {
    this.active = false;
    if (!this.saving) this.discardImports();
  }

  private discardImports(): void {
    this.importedImages.forEach((path: string): void => this.onDiscardImage(path));
    this.importedImages = [];
  }

  private async pickImage(): Promise<void> {
    if (this.picking || this.saving) return;
    this.picking = true;
    try {
      const path = await this.onPickImage();
      if (!path) return;
      if (!this.active) { this.onDiscardImage(path); return; }
      this.importedImages.push(path);
      this.draftImage = path;
    } finally { this.picking = false; }
  }

  private async save(): Promise<void> {
    if (this.saving || this.picking || !this.colorInputValid) return;
    const theme = ReaderCustomTheme.of(this.theme.slot, this.draftBackground, this.draftFontColor);
    theme.name = ReaderCustomTheme.normalizeName(this.draftName);
    theme.backgroundImage = this.draftImage;
    theme.imageMode = this.draftImageMode;
    theme.overlayAlpha = this.draftOverlay;
    this.saving = true;
    let saved = false;
    try {
      saved = await this.onSave(theme);
      if (saved) this.importedImages = this.importedImages.filter((path: string): boolean => path !== theme.backgroundImage);
    } finally {
      this.saving = false;
      if (saved || !this.active) this.discardImports();
    }
    if (saved && this.active) this.onCancel();
  }

  @Builder
  buildImageControls() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.reader_theme_background_image')).layoutWeight(1)
          .fontColor($r('sys.color.font_primary'))
        if (this.picking) { LoadingProgress().width(24).height(24).color(AppColor.Brand) }
        Button(this.draftImage.length > 0 ? $r('app.string.reader_change_image') : $r('app.string.reader_theme_import_image'))
          .fontSize(AppFont.Caption).fontColor(AppColor.Brand).backgroundColor(AppColor.GlassSheetControlTint)
          .enabled(!this.picking && !this.saving).onClick((): void => { this.pickImage(); })
        if (this.draftImage.length > 0) {
          Button($r('app.string.reader_theme_remove_image')).fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary')).backgroundColor(Color.Transparent)
            .enabled(!this.picking && !this.saving).onClick((): void => { this.draftImage = ''; })
        }
      }.width('100%')
      if (this.draftImage.length > 0) {
        if (this.supportsImageMode) {
          Text($r('app.string.reader_image_mode')).width('100%').fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
          ImmersiveOptionTabs({ labels: [$r('app.string.reader_image_contain'), $r('app.string.reader_image_tile'),
            $r('app.string.reader_image_stretch'), $r('app.string.reader_image_cover')],
            selected: [ReaderImageMode.Contain, ReaderImageMode.Tile, ReaderImageMode.Stretch, ReaderImageMode.Cover].indexOf(this.draftImageMode),
            onSelect: (index: number): void => {
              this.draftImageMode = [ReaderImageMode.Contain, ReaderImageMode.Tile, ReaderImageMode.Stretch, ReaderImageMode.Cover][index];
            } })
        }
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.reader_image_overlay')).fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
          Slider({ value: this.draftOverlay * 100, min: 0, max: TextReadingSettings.OVERLAY_MAX * 100, step: 1 })
            .layoutWeight(1).selectedColor(AppColor.Brand)
            .onChange((value: number): void => { this.draftOverlay = TextReadingSettings.normalizeOverlay(value / 100); })
          Text(`${Math.round(this.draftOverlay * 100)}%`).fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
        }.width('100%')
        Text($r('app.string.reader_image_overlay_hint')).fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary')).width('100%')
      }
    }.width('100%')
  }

  build() {
    Column({ space: AppSpace.Md }) {
      Text($r('app.string.reader_custom_theme_edit_slot', this.theme.slot + 1))
        .fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary')).width('100%')
      Scroll() {
        Column({ space: AppSpace.Md }) {
          Text($r('app.string.reader_theme_name')).fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary')).width('100%')
          TextInput({ text: this.draftName, placeholder: $r('app.string.reader_custom_theme_slot', this.theme.slot + 1) })
            .maxLength(20).fontColor($r('sys.color.font_primary')).backgroundColor(AppColor.GlassSheetControlTint)
            .accessibilityText($r('app.string.reader_theme_name'))
            .onChange((name: string): void => { this.draftName = name; })
          Stack() {
            ReaderBackground({ palette: resolvePalette(ReaderThemeId.Custom, this.draftBackground, this.draftFontColor),
              pattern: this.draftImage.length > 0 ? ReaderPattern.Image : ReaderPattern.None,
              bgImagePath: this.draftImage, overlayAlpha: this.draftOverlay,
              imageMode: this.supportsImageMode ? this.draftImageMode : ReaderImageMode.Cover })
          Column({ space: AppSpace.Sm }) {
            Text($r('app.string.reader_theme_preview_title'))
              .fontSize(AppFont.Caption).fontColor(this.draftFontColor).width('100%')
            Text($r('app.string.reader_theme_preview_text'))
              .fontSize(this.fontSize).fontColor(this.draftFontColor)
              .fontFamily(this.fontFamily.length > 0 ? this.fontFamily : undefined)
              .fontWeight(this.fontWeight, { enableVariableFontWeight: true })
              .lineHeight(this.fontSize * this.lineHeight).maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }.width('100%').padding(AppSpace.Md)
          }.width('100%').height(164).borderRadius(AppRadius.Lg).clip(true)
            .border({ width: 0.5, color: AppColor.GlassSheetStroke })

          this.buildImageControls()

          Row({ space: AppSpace.Sm }) {
            Button($r('app.string.reader_font_color'))
              .layoutWeight(1).fontColor($r('sys.color.font_primary'))
              .backgroundColor(AppColor.GlassSheetControlTint)
              .border({ width: this.editingBackground ? 0 : 1, color: AppColor.Brand })
              .onClick((): void => { this.editingBackground = false; this.colorInputValid = true; })
            Button($r('app.string.reader_background_color'))
              .layoutWeight(1).fontColor($r('sys.color.font_primary'))
              .backgroundColor(AppColor.GlassSheetControlTint)
              .border({ width: this.editingBackground ? 1 : 0, color: AppColor.Brand })
              .onClick((): void => { this.editingBackground = true; this.colorInputValid = true; })
          }.width('100%')
          Text(this.editingBackground ? $r('app.string.reader_editing_background_color') :
            $r('app.string.reader_editing_font_color'))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary')).width('100%')
          // 分支重建调色盘，避免两种颜色共用上次保留的灰阶色相。
          if (this.editingBackground) {
            ReaderColorPalette({ color: this.draftBackground, resetRevision: this.colorInputRevision,
              onValidityChange: (valid: boolean): void => { this.colorInputValid = valid; },
              onChange: (color: string): void => { this.draftBackground = color; } })
          } else {
            ReaderColorPalette({ color: this.draftFontColor, resetRevision: this.colorInputRevision,
              onValidityChange: (valid: boolean): void => { this.colorInputValid = valid; },
              onChange: (color: string): void => { this.draftFontColor = color; } })
          }
          if (readerColorContrast(this.draftBackground, this.draftFontColor) < 4.5) {
            Text($r('app.string.reader_color_contrast_hint'))
              .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary')).width('100%')
            Button($r('app.string.reader_recommend_font_color'))
              .fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
              .onClick((): void => { this.draftFontColor = recommendedReaderFontColor(this.draftBackground); })
          }
          Button($r('app.string.reader_theme_reset'))
            .fontColor($r('sys.color.font_secondary')).backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.draftBackground = TextReadingSettings.CUSTOM_BACKGROUND_DEFAULT;
              this.draftFontColor = '#2D2925';
              this.draftImage = '';
              this.draftImageMode = ReaderImageMode.Cover;
              this.draftOverlay = TextReadingSettings.OVERLAY_DEFAULT;
              this.colorInputValid = true;
              this.colorInputRevision++;
            })
        }.width('100%').enabled(!this.saving)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      Row({ space: AppSpace.Sm }) {
        Button($r('app.string.reader_theme_cancel')).layoutWeight(1)
          .fontColor($r('sys.color.font_primary')).backgroundColor(AppColor.GlassSheetControlTint)
          .enabled(!this.saving)
          .onClick((): void => this.onCancel())
        Button($r('app.string.reader_theme_save_apply')).layoutWeight(1)
          .fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
          .enabled(this.colorInputValid && !this.picking && !this.saving)
          .opacity(this.colorInputValid && !this.picking && !this.saving ? 1 : 0.4)
          .onClick((): void => { this.save(); })
      }.width('100%')
    }.width('100%').height('100%').padding({ top: AppSpace.Lg, left: AppSpace.Lg, right: AppSpace.Lg, bottom: AppSpace.Lg })
  }
}
