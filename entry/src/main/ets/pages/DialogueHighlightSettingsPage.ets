import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { ReaderColorPalette } from '../components/ReaderColorPalette';
import { TextReadingSettings } from '../model/TextReading';
import { ReaderDialogueRules } from '../model/ReaderDialogueRules';
import { ReaderPalette, resolveEffectiveThemeId, resolvePalette } from '../model/ReaderTheme';
import { TextReadingSettingsService } from '../service/text/TextReadingSettingsService';
import { AppColor, AppFont, AppSpace, AppTheme } from '../theme/Theme';
import { resolveReaderAccent } from '../theme/ReaderAccentColor';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct DialogueHighlightSettingsPage {
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Param navStack: NavPathStack = new NavPathStack();
  @Local ready: boolean = false;
  @Local loading: boolean = false;
  @Local saving: boolean = false;
  @Local failed: boolean = false;
  @Local dialogueHighlight: boolean = false;
  @Local dialogueColor: string = '';
  @Local quotePairs: string = ReaderDialogueRules.DEFAULT;
  @Local customOpening: string = '';
  @Local customClosing: string = '';
  @Local previewForeground: string = new ReaderPalette().primary;
  @Local dialogueFollowTheme: boolean = true;
  @Local previewColor: string = new ReaderPalette().accent;
  @Local themeDialogueColor: string = new ReaderPalette().accent;
  @Local previewBackground: string = '#FFF8F0';
  @Local colorRevision: number = 0;
  private previewSample: string = '';
  private readingSettings: TextReadingSettings = new TextReadingSettings();
  private readonly readerColorListener = (): void => this.refreshThemeColor();

  @Computed
  get themeAccent(): ResourceStr { return AppColor.Brand; }

  @Monitor('themeAccent')
  refreshThemeColor(): void {
    this.themeDialogueColor = resolveReaderAccent(this.getUIContext().getHostContext(), this.themeAccent);
    const settings = this.readingSettings;
    const themeId = resolveEffectiveThemeId(settings.themeId, settings.followSystemTheme, WindowUtils.isDarkMode());
    const palette = resolvePalette(themeId, settings.customBackground, settings.fontColor,
      settings.imageBackground, settings.imageFontColor);
    this.previewBackground = palette.background;
    this.previewForeground = palette.primary;
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
      this.previewSample = context.resourceManager.getStringSync($r('app.string.reader_dialogue_preview_sample').id);
      this.dialogueHighlight = settings.dialogueHighlight;
      this.quotePairs = settings.dialogueQuotePairs;
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

  private async saveDialogue(enabled: boolean, color: string, followTheme: boolean = color.length === 0,
    quotePairs: string = this.quotePairs): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.ready || this.saving) return;
    this.saving = true;
    this.dialogueFollowTheme = followTheme;
    try {
      const settings = await TextReadingSettingsService.get(context);
      settings.dialogueHighlight = enabled;
      settings.dialogueQuotePairs = ReaderDialogueRules.normalize(quotePairs);
      const normalizedColor = TextReadingSettings.normalizeDialogueHighlightColor(color);
      settings.dialogueHighlightColor = followTheme ? '' : (normalizedColor || this.themeDialogueColor);
      await TextReadingSettingsService.save(context, settings);
      this.readingSettings = settings;
      this.quotePairs = settings.dialogueQuotePairs;
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

  private availablePairs(): string[] {
    return ReaderDialogueRules.PRESETS.concat(this.quotePairs.split('\n').filter((pair: string): boolean =>
      pair.length === 2 && !ReaderDialogueRules.PRESETS.includes(pair)));
  }

  private setPair(pair: string, selected: boolean): void {
    const pairs = this.quotePairs.split('\n').filter((value: string): boolean => value.length === 2 && value !== pair);
    if (selected) pairs.push(pair);
    this.saveDialogue(this.dialogueHighlight, this.dialogueColor, this.dialogueFollowTheme, pairs.join('\n'));
  }

  private async addCustomPair(): Promise<void> {
    const pair = this.customOpening + this.customClosing;
    const pairs = this.quotePairs.split('\n').filter((value: string): boolean => value.length === 2);
    if (!ReaderDialogueRules.validPair(pair) || pairs.length >= ReaderDialogueRules.MAX_PAIRS ||
      pairs.some((value: string): boolean => value.charAt(0) === pair.charAt(0))) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_dialogue_pair_invalid') });
      return;
    }
    await this.saveDialogue(this.dialogueHighlight, this.dialogueColor, this.dialogueFollowTheme,
      pairs.concat([pair]).join('\n'));
    if (this.quotePairs.split('\n').includes(pair)) {
      this.customOpening = '';
      this.customClosing = '';
    }
  }

  @Builder
  quoteSettings(): void {
    Column({ space: 12 }) {
      Text($r('app.string.reader_dialogue_ranges')).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
      Text($r('app.string.reader_dialogue_ranges_hint')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.availablePairs(), (pair: string) => {
          Row({ space: 8 }) {
            Checkbox({ name: pair }).select(this.quotePairs.split('\n').includes(pair))
              .selectedColor(AppColor.Brand).enabled(!this.saving)
              .accessibilityText(`${pair.charAt(0)}…${pair.charAt(1)}`)
              .onChange((selected: boolean): void => { this.setPair(pair, selected); })
              .id(`reading-dialogue-pair-${pair}`)
            Text(`${pair.charAt(0)}…${pair.charAt(1)}`).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
          }.width('50%').height(44)
        }, (pair: string): string => pair)
      }.width('100%')
      Text($r('app.string.reader_dialogue_custom_pair')).fontSize(AppFont.Body).fontColor(AppTheme.TextPrimary)
      Row({ space: 8 }) {
        TextInput({ text: this.customOpening, placeholder: $r('app.string.reader_dialogue_opening') })
          .layoutWeight(1).maxLength(1).onChange((value: string): void => { this.customOpening = value; })
        TextInput({ text: this.customClosing, placeholder: $r('app.string.reader_dialogue_closing') })
          .layoutWeight(1).maxLength(1).onChange((value: string): void => { this.customClosing = value; })
        Button($r('app.string.reader_dialogue_add_pair')).fontColor(AppColor.Brand).backgroundColor(AppTheme.SettingsBackground)
          .enabled(!this.saving && this.customOpening.length === 1 && this.customClosing.length === 1)
          .onClick((): void => { this.addCustomPair(); })
      }.width('100%').enabled(!this.saving)
    }.width('100%').padding(18).borderRadius(18).backgroundColor(AppTheme.Surface)
      .border({ width: 0.5, color: AppTheme.Divider }).alignItems(HorizontalAlign.Start)
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
    this.quoteSettings()
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
      Text($r('app.string.reader_speech_style_preview')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      Text() {
        ForEach(this.availablePairs(), (pair: string) => {
          Span(`${pair.charAt(0)}${this.previewSample}${pair.charAt(1)}\n`)
            .fontColor(this.dialogueHighlight && this.quotePairs.split('\n').includes(pair) ? this.previewColor : this.previewForeground)
        }, (pair: string): string => pair)
      }.fontSize(AppFont.BodyL).width('100%').padding(12)
        .backgroundColor(this.previewBackground).borderRadius(12)
    }.width('100%').padding(18).borderRadius(18).backgroundColor(AppTheme.Surface)
      .border({ width: 0.5, color: AppTheme.Divider }).alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        if (this.ready) {
          Scroll() {
            Column({ space: 12 }) {
              this.dialogueSettings()
            }.width('100%').constraintSize({ maxWidth: 760 })
              // 安全区留白随内容滚动，避免缩短视口后在手势条上方截断卡片。
              .padding({ left: 16, right: 16, top: this.headerHeight + 16,
                bottom: WindowUtils.getBottomSafeVp() + 16 })
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
        } else if (this.failed) {
          Text($r('app.string.reading_settings_load_error')).fontColor(AppTheme.TextSecondary).padding(20)
          Button($r('app.string.common_retry')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
            .onClick((): void => { this.load(); })
        } else {
          LoadingProgress().width(32).height(32).color(AppColor.Brand).margin({ top: 24 })
        }
      }.width('100%').height('100%')
        .padding({ top: this.ready ? 0 : this.headerHeight })
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.reader_dialogue_highlight')).fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
        }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
