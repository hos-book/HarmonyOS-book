import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { RoleSpeechPanel } from '../components/RoleSpeechPanel';
import { AppFont, AppSpace, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct RoleSpeechSettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Local panelActive: boolean = true;

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        RoleSpeechPanel({ active: this.panelActive, topInset: this.headerHeight, bottomInset: WindowUtils.getBottomSafeVp(),
          onModelSettings: (): void => {
            this.panelActive = false;
            this.navStack.pushPathByName('roleModelSettings', '', (): void => { this.panelActive = true; });
          } })
      }.width('100%').height('100%')
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.role_speech_title')).fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
        }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
