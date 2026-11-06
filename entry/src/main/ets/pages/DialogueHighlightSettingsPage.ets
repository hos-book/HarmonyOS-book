import { ReaderColorPalette } from '../components/ReaderColorPalette';
import { TextReadingSettings } from '../model/TextReading';
import { ReaderPalette, resolveEffectiveThemeId, resolvePalette } from '../model/ReaderTheme';
import { TextReadingSettingsService } from '../service/text/TextReadingSettingsService';
import { AppColor, AppFont, AppSpace, AppTheme } from '../theme/Theme';
import { resolveReaderAccent } from '../theme/ReaderAccentColor';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct DialogueHighlightSettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local ready: boolean = false;
  @Local loading: boolean = false;
  @Local saving: boolean = false;
  @Local failed: boolean = false;
  @Local dialogueHighlight: boolean = false;
  @Local dialogueColor: string = '';
  @Local dialogueFollowTheme: boolean = true;
  @Local previewColor: string = new ReaderPalette().accent;
  @Local themeDialogueColor: string = new ReaderPalette().accent;
  @Local previewBackground: string = '#FFF8F0';
  @Local colorRevision: number = 0;
  private readingSettings: TextReadingSettings = new TextReadingSettings();
  private readonly readerColorListener = (): void => this.refreshThemeColor();

  @Computed
  get themeAccent(): ResourceStr { return AppColor.Brand; }

  @Monitor('themeAccent')
  refreshThemeColor(): void {
    this.themeDialogueColor = resolveReaderAccent(this.getUIContext().getHostContext(), this.themeAccent);
    const settings = this.readingSettings;
    const themeId = resolveEffectiveThemeId(settings.themeId, settings.followSystemTheme, WindowUtils.isDarkMode());
    this.previewBackground = resolvePalette(themeId, settings.customBackground, settings.fontColor,
      settings.imageBackground, settings.imageFontColor).background;
    if (this.dialogueFollowTheme) {
      this.previewColor = this.themeDialogueColor;
      this.colorRevision++;
    }
  }

  aboutToAppear(): void {
    WindowUtils.addReaderColorListener(this.readerColorListener);
    this.load();
  }

  aboutToDisappear(): void { WindowUtils.removeReaderColorListener(this.readerColorListener); }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.loading) return;
    this.loading = true;
    this.failed = false;
    try {
      const settings = await TextReadingSettingsService.get(context);
      this.readingSettings = settings;
      this.dialogueHighlight = settings.dialogueHighlight;
      this.dialogueColor = settings.dialogueHighlightColor;
      this.dialogueFollowTheme = this.dialogueColor.length === 0;
      this.refreshThemeColor();
      this.previewColor = this.dialogueColor || this.themeDialogueColor;
      this.ready = true;
    } catch (_error) {
      this.failed = true;
    } finally {
      this.loading = false;
    }
  }

  private async saveDialogue(enabled: boolean, color: string, followTheme: boolean = color.length === 0): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.ready || this.saving) return;
    this.saving = true;
    this.dialogueFollowTheme = followTheme;
    try {
      const settings = await TextReadingSettingsService.get(context);
      settings.dialogueHighlight = enabled;
      const normalizedColor = TextReadingSettings.normalizeDialogueHighlightColor(color);
      settings.dialogueHighlightColor = followTheme ? '' : (normalizedColor || this.themeDialogueColor);
      await TextReadingSettingsService.save(context, settings);
      this.dialogueHighlight = settings.dialogueHighlight;
      this.dialogueColor = settings.dialogueHighlightColor;
      this.dialogueFollowTheme = this.dialogueColor.length === 0;
      this.previewColor = this.dialogueColor || this.themeDialogueColor;
      this.colorRevision++;
    } catch (_error) {
      this.previewColor = this.dialogueColor || this.themeDialogueColor;
      this.dialogueFollowTheme = this.dialogueColor.length === 0;
      this.colorRevision++;
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reading_settings_save_error') });
    } finally {
      this.saving = false;
    }
  }

  @Builder
  dialogueSettings(): void {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text($r('app.string.reader_dialogue_highlight')).fontSize(AppFont.BodyL)
          .fontColor(AppTheme.TextPrimary).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.dialogueHighlight }).selectedColor(AppColor.Brand)
          .enabled(!this.saving).id('reading-dialogue-highlight')
          .onChange((enabled: boolean): void => { this.saveDialogue(enabled, this.dialogueColor); })
      }.width('100%')
      Text($r('app.string.reader_dialogue_highlight_hint')).fontSize(AppFont.Caption)
        .fontColor(AppTheme.TextSecondary).width('100%')
    }.width('100%').padding(18).borderRadius(18).backgroundColor(AppTheme.Surface)
      .border({ width: 0.5, color: AppTheme.Divider }).alignItems(HorizontalAlign.Start)
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text($r('app.string.reader_dialogue_color')).fontSize(AppFont.Body)
          .fontColor(AppTheme.TextPrimary).layoutWeight(1)
        Row({ space: 8 }) {
          Text($r('app.string.reader_dialogue_color_auto')).fontSize(AppFont.Caption)
            .fontColor(AppTheme.TextSecondary)
          Toggle({ type: ToggleType.Switch, isOn: this.dialogueFollowTheme }).selectedColor(AppColor.Brand)
            .enabled(!this.saving)
            .accessibilityText($r('app.string.reader_dialogue_color_auto'))
            .onChange((followTheme: boolean): void => {
              const color = followTheme ? '' : (this.dialogueColor || this.previewColor);
              this.saveDialogue(this.dialogueHighlight, color, followTheme);
            })
            .id('reading-dialogue-color-follow-theme')
        }
      }.width('100%')
      ReaderColorPalette({ color: this.previewColor, resetRevision: this.colorRevision,
        onChange: (color: string, commit: boolean): void => {
          this.previewColor = color;
          if (commit) this.saveDialogue(this.dialogueHighlight, color, false);
        } }).enabled(!this.saving).id('reading-dialogue-color')
      Text($r('app.string.reader_dialogue_color_preview')).fontSize(AppFont.BodyL)
        .fontColor(this.previewColor).width('100%').padding(12)
        .backgroundColor(this.previewBackground).borderRadius(12)
    }.width('100%').padding(18).borderRadius(18).backgroundColor(AppTheme.Surface)
      .border({ width: 0.5, color: AppTheme.Divider }).alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
        }.width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
        Text($r('app.string.reader_dialogue_highlight')).fontSize(AppFont.Title)
          .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
      }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Md,
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      if (this.ready) {
        Scroll() {
          Column({ space: 12 }) {
            this.dialogueSettings()
          }.width('100%').constraintSize({ maxWidth: 760 }).padding(16)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      } else if (this.failed) {
        Text($r('app.string.reading_settings_load_error')).fontColor(AppTheme.TextSecondary).padding(20)
        Button($r('app.string.common_retry')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
          .onClick((): void => { this.load(); })
      } else {
        LoadingProgress().width(32).height(32).color(AppColor.Brand).margin({ top: 24 })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .padding({ bottom: WindowUtils.getBottomSafeVp() })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
