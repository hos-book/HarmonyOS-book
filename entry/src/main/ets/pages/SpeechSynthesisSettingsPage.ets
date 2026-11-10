import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { sendableContextManager } from '@kit.AbilityKit';
import { SpeechSynthesisSettingsPanel } from '../components/SpeechSynthesisSettingsPanel';
import { SpeechSynthesisSettings } from '../model/SpeechSynthesisSettings';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { AppColor, AppFont, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct SpeechSynthesisSettingsPage {
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Param navStack: NavPathStack = new NavPathStack();
  @Local state: TextToSpeechState = TextToSpeechService.getInstance().state;
  @Local ready: boolean = false;
  @Local failed: boolean = false;

  aboutToAppear(): void { this.initialize(); }

  private async initialize(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.failed = false;
    try {
      await TextToSpeechService.getInstance().initialize(sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(context)));
      this.ready = true;
    } catch (_error) { this.failed = true; }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        if (this.ready) {
          Scroll() {
            Column() {
              SpeechSynthesisSettingsPanel({ settings: this.state.synthesis,
                onSave: (value: SpeechSynthesisSettings): Promise<void> =>
                  TextToSpeechService.getInstance().setSynthesisSettings(value) })
            }.width('100%').constraintSize({ maxWidth: 760 })
              .padding({ left: 16, right: 16, top: this.headerHeight + 16,
                bottom: WindowUtils.getBottomSafeVp() + 16 })
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
        } else if (this.failed) {
          Text($r('app.string.reading_settings_load_error')).fontColor(AppTheme.TextSecondary).padding(20)
          Button($r('app.string.common_retry')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
            .onClick((): void => { this.initialize(); })
        } else { LoadingProgress().width(32).height(32).color(AppColor.Brand) }
      }.width('100%').height('100%')
        .padding({ top: this.ready ? 0 : this.headerHeight })
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: 12 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.tts_synthesis_title')).fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
        }.width('100%').padding({ left: 8, right: 16, top: WindowUtils.getStatusBarHeightVp() + 8, bottom: 8 })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
