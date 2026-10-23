import { AppTheme, HomeTheme } from '../theme/Theme';

/** 一个页面只绘制一张装饰底图，内容与滚动容器保持透明。 */
@ComponentV2
export struct ThemeBackgroundComponent {
  @Param warmMid: number = 0.35;

  build() {
    Stack() {
      if (AppTheme.isPaper) {
        Image(AppTheme.BackgroundImage)
          .width('100%').height('100%').objectFit(ImageFit.Cover)
      } else {
        Column().width('100%').height('100%')
          .linearGradient({ angle: 180, colors: [
            [HomeTheme.BgWarmTop, 0], [HomeTheme.BgWarmMid, this.warmMid], [HomeTheme.BgNeutral, 1]
          ] })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.Background)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
        [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
  }
}
