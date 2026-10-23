import { ThemeCoverDecoration } from '../model/AppThemeVisual';
import { CoverTheme } from '../theme/CoverTheme';

/** 框内装饰不改变图片尺寸，不接收触摸，不遮挡外层的来源、类型或选中标记。 */
@ComponentV2
export struct CoverDecoration {
  @Param radius: number = 8;
  @Param compact: boolean = false;
  @Param themeBundleId: string = '';

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (CoverTheme.decoration(this.themeBundleId) !== ThemeCoverDecoration.None) {
        if (!this.compact && CoverTheme.decoration(this.themeBundleId) === ThemeCoverDecoration.Spine) {
          Row().width('9%').height('100%')
            .linearGradient({ direction: GradientDirection.Right,
              colors: [['#48000000', 0], ['#0C000000', 0.38],
                ['#44FFFFFF', 0.52], ['#18000000', 0.69], ['#00000000', 1]] })
        }
        Row().width('100%').height('100%')
          .border({ width: this.compact ? 0.8 : 1,
            color: CoverTheme.edgeColor(this.themeBundleId), radius: this.radius })
          .opacity(0.5)
      }
    }.width('100%').height('100%').borderRadius(this.radius).clip(true)
    .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
