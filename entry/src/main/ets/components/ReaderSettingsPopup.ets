import { AppMaterial } from '../theme/Theme';
import { PlatformCompat } from '../utils/PlatformCompat';

/** 阅读与播放设置共用悬浮宿主，切换内容时保持面板与底部控件连续可用。 */
@ComponentV2
export struct ReaderSettingsPopup {
  @Param visible: boolean = false;
  @Param viewportWidth: number = 0;
  @Param viewportHeight: number = 0;
  @Param topInset: number = 0;
  @Param leftInset: number = 0;
  @Param rightInset: number = 0;
  @Param anchorBottom: number = 0;
  @Param anchorCenterX: number = -1;
  @Param preferredHeight: number = 520;
  @Param maxHeightRatio: number = 0.64;
  @Event onVisibilityChange: (visible: boolean) => void = () => {};
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent(): void {}

  private panelWidth(): number {
    return Math.max(1, Math.min(560, this.viewportWidth - this.leftInset - this.rightInset - 24));
  }

  private panelHeight(): number {
    // 保留顶部工具栏；横屏和分屏时缩短面板，由内部 Scroll 承载剩余设置。
    const available = this.viewportHeight - this.anchorBottom - this.topInset - 60;
    return Math.max(1, Math.min(this.preferredHeight, this.viewportHeight * this.maxHeightRatio, available));
  }

  private panelLeft(): number {
    const center = this.anchorCenterX >= 0 ? this.anchorCenterX :
      this.leftInset + (this.viewportWidth - this.leftInset - this.rightInset) / 2;
    return Math.max(this.leftInset + 12,
      Math.min(center - this.panelWidth() / 2, this.viewportWidth - this.rightInset - 12 - this.panelWidth()));
  }

  @Builder
  panelContent(): void {
    Column() {
      if (this.visible) { this.content() }
    }.width('100%').height(this.panelHeight()).borderRadius(24).clip(true)
      .id('reader-settings-floating-panel')
  }

  private popupOptions(): CustomPopupOptions {
    const options: CustomPopupOptions = {
      builder: (): void => { this.panelContent(); },
      placement: Placement.Top,
      enableArrow: false,
      targetSpace: 8,
      width: this.panelWidth(),
      radius: 24,
      mask: false,
      autoCancel: false,
      focusable: true,
      showInSubWindow: false,
      avoidTarget: AvoidanceMode.AVOID_AROUND_TARGET,
      popupColor: AppMaterial.SheetBackground,
      keyboardAvoidMode: KeyboardAvoidMode.DEFAULT,
      transition: TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
        .animation({ duration: 160, curve: Curve.EaseOut }),
      onStateChange: (event): void => { this.onVisibilityChange(event.isVisible); },
      onWillDismiss: (action: DismissPopupAction): void => {
        if (action.reason === DismissReason.PRESS_BACK) action.dismiss();
      }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.ReaderSheetThick;
    else options.backgroundBlurStyle = AppMaterial.ReaderSheetBlur;
    return options;
  }

  build() {
    Row().width(this.panelWidth()).height(1)
      .position({
        x: this.panelLeft(),
        y: Math.max(this.topInset, this.viewportHeight - this.anchorBottom)
      })
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
      .bindPopup(this.visible, this.popupOptions())
  }
}
