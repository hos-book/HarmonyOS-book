import { AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

/** 二级页面共用的磨砂顶栏。放在滚动区域上方，宿主将实测高度用于内容起始留白。 */
@ComponentV2
export struct FrostedPageHeader {
  @BuilderParam content: () => void = this.emptyContent;
  @Event onHeightChange: (height: number) => void = (_height: number): void => {};
  @Local measuredHeight: number = WindowUtils.getStatusBarHeightVp() + 56;

  @Builder
  emptyContent(): void {}

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 直接绑定资源以响应主题和深浅色变化，透明度只影响底色。
      Row().width('100%').height(this.measuredHeight)
        .backgroundColor(AppTheme.SettingsBackground).opacity(0.72)
        .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS).accessibilityLevel('no-hide-descendants')
      Column() {
        this.content()
      }.width('100%').hitTestBehavior(HitTestMode.Transparent)
        .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions): void => {
          const height: number = Number(newSize.height);
          if (height > 0 && Math.abs(height - this.measuredHeight) > 0.1) {
            this.measuredHeight = height;
            this.onHeightChange(height);
          }
        })
    }.width('100%')
      .backgroundEffect({ radius: 24, saturation: 1, brightness: 1, color: Color.Transparent })
      .clip(true)
      .hitTestBehavior(HitTestMode.Transparent)
  }
}
