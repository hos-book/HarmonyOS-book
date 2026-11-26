import { AppColor } from '../theme/Theme';

// Loading UI Infinity，MIT，Copyright (c) 2026 Bartosz Zagrodzki。
// 许可随应用保存在 rawfile/third_party/loading_ui/LICENSE.txt。
const INFINITY_LOADING_PATH: string =
  'M24.3 30C11.4 30 5 43.3 5 50s6.4 20 19.3 20c19.3 0 32.1-40 51.4-40' +
  'C88.6 30 95 43.3 95 50s-6.4 20-19.3 20C56.4 70 43.6 30 24.3 30z';
const INFINITY_LOADING_LENGTH: number = 256.58892822265625;

@AnimatableExtend(Path)
function infinityLoadingDashOffset(offset: number) {
  .strokeDashOffset(`${offset}px`)
}

/** 主题色 Infinity 加载动画，路径插值由 ArkUI 动画系统驱动。 */
@ComponentV2
export struct InfinityLoadingIndicator {
  @Param indicatorSize: number = 24;
  @Local dashOffset: number = 0;

  build() {
    Shape() {
      Path()
        .commands(INFINITY_LOADING_PATH)
        .width('100px')
        .height('100px')
        .fill(Color.Transparent)
        .strokeWidth('10px')
        .strokeLineCap(LineCapStyle.Round)
        .strokeDashArray(['205.271142578125px', '51.317785644531256px'])
        .infinityLoadingDashOffset(this.dashOffset)
        .animation({
          duration: 2000,
          curve: Curve.Linear,
          iterations: -1,
          expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
        })
        .stroke(AppColor.Brand)
    }
    // 125px 视口还原原版以中心缩放至 80% 的比例。
    .viewPort({ x: '-12.5px', y: '-12.5px', width: '125px', height: '125px' })
    .width(this.indicatorSize)
    .height(this.indicatorSize)
    .hitTestBehavior(HitTestMode.None)
    .onAppear((): void => { this.dashOffset = INFINITY_LOADING_LENGTH; })
  }
}
