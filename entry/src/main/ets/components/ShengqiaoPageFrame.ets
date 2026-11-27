import { FrostedPageHeader } from './FrostedPageHeader';
import { AppFont, AppSpace, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct ShengqiaoPageFrame {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param pageTitle: ResourceStr = '';
  @Param scrolling: boolean = true;
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @BuilderParam content: () => void = this.empty;
  @Builder empty() {}

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.scrolling) {
        Scroll() {
          Column({ space: AppSpace.Md }) { this.content() }
            .width('100%').constraintSize({ maxWidth: 760 }).alignItems(HorizontalAlign.Start)
            .padding({ left: AppSpace.Md, right: AppSpace.Md, top: this.headerHeight + AppSpace.Md,
              bottom: WindowUtils.getBottomSafeVp() + AppSpace.Xl })
        }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
      } else {
        Column({ space: AppSpace.Sm }) { this.content() }
          .width('100%').height('100%').padding({ top: this.headerHeight,
            bottom: WindowUtils.getBottomSafeVp() })
      }
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text(this.pageTitle).fontSize(AppFont.Title).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
        }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
