import { HdsTabs } from '@kit.UIDesignKit';
import { AppColor, AppTheme } from '../theme/Theme';
import { HdsCompat } from '../utils/HdsCompat';

/** 迷你栏与转场面板复用应用底部导航的 HDS 材质和主题光色。 */
@ComponentV2
export struct PlayerBarSurface {
  @Param surfaceWidth: number = 0;
  @Param surfaceHeight: number = 0;
  @Param surfaceRadius: number = 999;

  @Builder
  materialBackdrop(): void {
    Column()
      .width('100%')
      .height('100%')
  }

  build() {
    Stack() {
      if (HdsCompat.materialSupported) {
        HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
          TabContent() { Column() }
            .height(this.surfaceHeight)
            .tabBar(this.materialBackdrop())
        }
        .barMode(BarMode.Fixed)
        .barHeight(this.surfaceHeight)
        .barOverlap(true)
        .barFloatingStyle({
          barWidth: { smallWidth: this.surfaceWidth,
            mediumWidth: this.surfaceWidth, largeWidth: this.surfaceWidth },
          systemMaterialEffect: HdsCompat.adaptiveMaterial,
          lightColor: AppColor.Brand,
          barSideMargin: 0,
          barBottomMargin: 0,
          gradientMask: { maskColor: Color.Transparent, maskHeight: this.surfaceHeight },
          adaptToHandedness: false,
          barOpacity: 1
        })
        .scrollable(false)
        .width(this.surfaceWidth)
        .height(this.surfaceHeight)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppTheme.Surface)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      }
    }
    .width(this.surfaceWidth)
    .height(this.surfaceHeight)
    .borderRadius(this.surfaceRadius)
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
  }
}
