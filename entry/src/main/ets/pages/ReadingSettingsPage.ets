import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { sendableContextManager } from '@kit.AbilityKit';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { AppColor, AppFont, AppSpace, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct ReadingSettingsPage {
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Param navStack: NavPathStack = new NavPathStack();
  @Local ready: boolean = false;
  @Local loading: boolean = false;
  @Local failed: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.loading) return;
    this.loading = true;
    this.failed = false;
    try {
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

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        if (this.ready) {
          Scroll() {
            Column({ space: 8 }) {
              Text($r('app.string.tts_settings_title')).fontSize(AppFont.Caption)
                .fontColor(AppTheme.TextSecondary).width('100%').padding({ left: 4 })
              Row({ space: 12 }) {
                Column({ space: 2 }) {
                  Text($r('app.string.tts_voice_management')).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
                  Text($r('app.string.tts_voice_management_hint')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([AppTheme.TextSecondary])
              }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 }).constraintSize({ minHeight: 64 }).borderRadius(14)
                .backgroundColor(AppTheme.Surface).border({ width: 0.5, color: AppTheme.Divider })
                .id('reading-voice-management')
                .onClick((): void => { this.navStack.pushPathByName('voiceManagement', ''); })
              Row({ space: 12 }) {
                Text($r('app.string.tts_synthesis_title')).fontSize(AppFont.BodyL)
                  .fontColor(AppTheme.TextPrimary).layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([AppTheme.TextSecondary])
              }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 }).constraintSize({ minHeight: 52 }).borderRadius(14)
                .backgroundColor(AppTheme.Surface).border({ width: 0.5, color: AppTheme.Divider })
                .onClick((): void => { this.navStack.pushPathByName('speechSynthesisSettings', ''); })
                .id('reading-synthesis-settings')
              Text($r('app.string.reading_display_settings')).fontSize(AppFont.Caption)
                .fontColor(AppTheme.TextSecondary).width('100%').padding({ left: 4, top: 8 })
              Row({ space: 12 }) {
                Text($r('app.string.reader_font_management')).fontSize(AppFont.BodyL)
                  .fontColor(AppTheme.TextPrimary).layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([AppTheme.TextSecondary])
              }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .constraintSize({ minHeight: 52 }).borderRadius(14)
                .backgroundColor(AppTheme.Surface).border({ width: 0.5, color: AppTheme.Divider })
                .id('reading-font-management')
                .onClick((): void => { this.navStack.pushPathByName('fontManagement', ''); })
              Row({ space: 12 }) {
                Text($r('app.string.reader_speech_display')).fontSize(AppFont.BodyL)
                  .fontColor(AppTheme.TextPrimary).layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([AppTheme.TextSecondary])
              }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 }).constraintSize({ minHeight: 52 }).borderRadius(14)
                .backgroundColor(AppTheme.Surface).border({ width: 0.5, color: AppTheme.Divider })
                .onClick((): void => { this.navStack.pushPathByName('speechDisplaySettings', ''); })
                .id('reading-speech-display')
              Row({ space: 12 }) {
                Text($r('app.string.reader_dialogue_highlight')).fontSize(AppFont.BodyL)
                  .fontColor(AppTheme.TextPrimary).layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([AppTheme.TextSecondary])
              }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 }).constraintSize({ minHeight: 52 }).borderRadius(14)
                .backgroundColor(AppTheme.Surface).border({ width: 0.5, color: AppTheme.Divider })
                .onClick((): void => { this.navStack.pushPathByName('dialogueHighlightSettings', ''); })
                .id('reading-dialogue-settings')
            }.width('100%').constraintSize({ maxWidth: 760 })
              .padding({ left: 16, right: 16, top: this.headerHeight + 8, bottom: 12 })
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
        } else if (this.failed) {
          Text($r('app.string.reading_settings_load_error')).fontColor(AppTheme.TextSecondary).padding(20)
          Button($r('app.string.common_retry')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
            .onClick((): void => { this.load(); })
        } else {
          LoadingProgress().width(32).height(32).color(AppColor.Brand).margin({ top: 24 })
        }
      }.width('100%').height('100%')
        .padding({ top: this.ready ? 0 : this.headerHeight, bottom: WindowUtils.getBottomSafeVp() })
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.reading_settings_title')).fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
        }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
