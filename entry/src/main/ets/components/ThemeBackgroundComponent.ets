import { AppTheme } from '../theme/Theme';
import { ThemeBackgroundKind } from '../model/AppThemeVisual';

/** 同一背景解析用于页面与候选预览；显式 id 不会修改全局外观。 */
@ComponentV2
export struct ThemeBackgroundComponent {
  @Param warmMid: number = 0.35;
  @Param themeBundleId: string = '';
  @Param preview: boolean = false;

  build() {
    Stack() {
      if (AppTheme.resolve(this.themeBundleId).visual.background.kind === ThemeBackgroundKind.Image) {
        Image(AppTheme.resolve(this.themeBundleId).visual.background.image ?? '')
          .width('100%').height('100%').objectFit(ImageFit.Cover)
          .opacity(AppTheme.resolve(this.themeBundleId).visual.background.imageOpacity)
      } else if (!this.preview &&
        AppTheme.resolve(this.themeBundleId).visual.background.kind === ThemeBackgroundKind.Gradient) {
        Column().width('100%').height('100%')
          .linearGradient({ angle: 180, colors: [
            [AppTheme.resolve(this.themeBundleId).visual.colors.homeTop, 0],
            [AppTheme.resolve(this.themeBundleId).visual.colors.homeMid, this.warmMid],
            [AppTheme.resolve(this.themeBundleId).visual.colors.homeBottom, 1]
          ] })
      }
    }.width('100%').height('100%')
      .backgroundColor(AppTheme.resolve(this.themeBundleId).visual.colors.background)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      .expandSafeArea(this.preview ? [] : [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
        this.preview ? [] : [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
  }
}
