import { sendableContextManager } from '@kit.AbilityKit';
import { ReaderSpeechSheet } from '../components/ReaderSpeechSheet';
import { ReaderColorPalette } from '../components/ReaderColorPalette';
import { TextReadingSettings } from '../model/TextReading';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { TextReadingSettingsService } from '../service/text/TextReadingSettingsService';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { AppColor, AppFont, AppSpace, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct ReadingSettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local speechState: TextToSpeechState = TextToSpeechService.getInstance().state;
  @Local ready: boolean = false;
  @Local loading: boolean = false;
  @Local saving: boolean = false;
  @Local failed: boolean = false;
  @Local dialogueHighlight: boolean = false;
  @Local dialogueColor: string = '';
  @Local previewColor: string = '#A33245';
  @Local colorRevision: number = 0;

  aboutToAppear(): void { this.load(); }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.loading) return;
    this.loading = true;
    this.failed = false;
    try {
      const settings = await TextReadingSettingsService.get(context);
      this.dialogueHighlight = settings.dialogueHighlight;
      this.dialogueColor = settings.dialogueHighlightColor;
      this.previewColor = this.dialogueColor || '#A33245';
      const abilityContext = sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(context));
      const speech = TextToSpeechService.getInstance();
      await speech.initialize(abilityContext);
      this.ready = true;
      speech.refreshVoices();
    } catch (_error) {
      this.failed = true;
    } finally {
      this.loading = false;
    }
  }

  private async saveDialogue(enabled: boolean, color: string): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.ready || this.saving) return;
    this.saving = true;
    try {
      const settings = await TextReadingSettingsService.get(context);
      settings.dialogueHighlight = enabled;
      settings.dialogueHighlightColor = TextReadingSettings.normalizeDialogueHighlightColor(color);
      await TextReadingSettingsService.save(context, settings);
      this.dialogueHighlight = settings.dialogueHighlight;
      this.dialogueColor = settings.dialogueHighlightColor;
      this.previewColor = this.dialogueColor || '#A33245';
      this.colorRevision++;
    } catch (_error) {
      this.previewColor = this.dialogueColor || '#A33245';
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
      Row({ space: 8 }) {
        Text($r('app.string.reader_dialogue_color')).fontSize(AppFont.Body)
          .fontColor(AppTheme.TextPrimary).layoutWeight(1)
        Button($r('app.string.reader_dialogue_color_auto')).fontColor(AppColor.Brand)
          .backgroundColor(Color.Transparent).enabled(!this.saving)
          .accessibilitySelected(this.dialogueColor === '')
          .onClick((): void => { this.saveDialogue(this.dialogueHighlight, ''); })
          .id('reading-dialogue-color-auto')
      }.width('100%')
      ReaderColorPalette({ color: this.previewColor, resetRevision: this.colorRevision,
        onChange: (color: string, commit: boolean): void => {
          this.previewColor = color;
          if (commit) this.saveDialogue(this.dialogueHighlight, color);
        } }).enabled(!this.saving).id('reading-dialogue-color')
      Text($r('app.string.reader_dialogue_color_preview')).fontSize(AppFont.BodyL)
        .fontColor(this.previewColor).width('100%').padding(12)
        .backgroundColor('#FFF8F0').borderRadius(12)
    }.width('100%').alignItems(HorizontalAlign.Start)
    Divider().color(AppTheme.Divider)
    Text($r('app.string.tts_settings_title')).fontSize(AppFont.BodyL)
      .fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
  }

  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
        }.width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
        Text($r('app.string.reading_settings_title')).fontSize(AppFont.Title)
          .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
      }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Md,
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      if (this.ready) {
        ReaderSpeechSheet({ state: this.speechState, embedded: true,
          extraContent: (): void => { this.dialogueSettings(); } })
          .layoutWeight(1)
      } else if (this.failed) {
        Text($r('app.string.reading_settings_load_error')).fontColor(AppTheme.TextSecondary).padding(20)
        Button($r('app.string.common_retry')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
          .onClick((): void => { this.load(); })
      } else {
        LoadingProgress().width(32).height(32).color(AppColor.Brand).margin({ top: 24 })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.Background)
      .padding({ bottom: WindowUtils.getBottomSafeVp() })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
