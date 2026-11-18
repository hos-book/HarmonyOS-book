import { SliderGestureModifier } from '../utils/SliderGestureModifier';

/** 保留原生滑块拖动，并允许长按轨道任意位置后调节播放进度。 */
@ComponentV2
export struct PlayerProgressSlider {
  @Param value: number = 0;
  @Param max: number = 100;
  @Param step: number = 1;
  @Param barHeight: number = 40;
  @Param interactive: boolean = false;
  @Param contentKey: string = '';
  @Param progressLabel: Resource = $r('app.string.player_chapter_progress');
  @Param sliderId: string = 'audio-chapter-progress';
  @Event onChange: (value: number, mode: SliderChangeMode) => void = (): void => {};
  @Event onCancel: () => void = (): void => {};
  @Event onHold: () => void = (): void => {};
  @Local dragging: boolean = false;
  private sliderWidth: number = 0;
  private touchX: number = 0;
  private pointerId: number = -1;
  private trackSeeking: boolean = false;
  private ignoreNative: boolean = false;

  @Monitor('interactive', 'contentKey')
  private resetInteraction(): void {
    this.cancelDrag();
  }

  aboutToDisappear(): void {
    this.cancelDrag();
  }

  private cancelDrag(): void {
    const wasDragging = this.dragging;
    this.trackSeeking = false;
    this.ignoreNative = true;
    this.pointerId = -1;
    this.dragging = false;
    if (wasDragging) this.onCancel();
    this.releaseNativeSuppression();
  }

  private releaseNativeSuppression(): void {
    // 屏蔽本轮触摸的原生 End 回调后，继续允许键盘和无障碍调节。
    setTimeout((): void => {
      if (this.pointerId < 0) this.ignoreNative = false;
    }, 0);
  }

  private trackValue(): number {
    // OutSet 的轨道两端各缩进半个滑块（18vp / 2），与原生滑块位置保持一致。
    const fraction = Math.max(0, Math.min(1, (this.touchX - 9) / Math.max(1, this.sliderWidth - 18)));
    return Math.max(0, Math.min(this.max, Math.round(fraction * this.max / this.step) * this.step));
  }

  private beginTrackDrag(): void {
    if (!this.interactive || this.pointerId < 0 || this.sliderWidth <= 18) return;
    this.trackSeeking = true;
    this.ignoreNative = true;
    this.dragging = true;
    this.onChange(this.trackValue(), SliderChangeMode.Begin);
    this.onHold();
  }

  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) {
      this.cancelDrag();
      return;
    }
    if (event.type === TouchType.Down) {
      // 第二根手指加入时取消本次调节，避免切换触点引起跳变。
      if (this.pointerId >= 0 || event.touches.length !== 1) {
        this.cancelDrag();
        return;
      }
      this.pointerId = event.touches[0].id;
      this.touchX = event.touches[0].x;
      this.ignoreNative = false;
      return;
    }
    const touch = event.changedTouches.find((item: TouchObject): boolean => item.id === this.pointerId);
    if (touch === undefined) return;
    this.touchX = touch.x;
    if (this.trackSeeking && this.interactive) {
      if (event.type === TouchType.Move) this.onChange(this.trackValue(), SliderChangeMode.Moving);
      else if (event.type === TouchType.Up) {
        this.trackSeeking = false;
        this.dragging = false;
        this.onChange(this.trackValue(), SliderChangeMode.End);
      }
    }
    if (event.type === TouchType.Up) {
      this.pointerId = -1;
      this.releaseNativeSuppression();
    }
  }

  private handleNativeChange(value: number, mode: SliderChangeMode): void {
    if (this.ignoreNative || !this.interactive) return;
    this.dragging = mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving;
    this.onChange(value, mode);
  }

  build() {
    Slider({ value: this.value, min: 0, max: this.max, step: this.step, style: SliderStyle.OutSet })
      .attributeModifier(new SliderGestureModifier(0, this.max))
      .selectedColor('#FFFFFF').trackColor('#33FFFFFF').blockColor('#FFFFFF')
      .blockSize({ width: 18, height: 18 }).trackThickness(this.dragging ? 8 : 6)
      .width('100%').height(this.barHeight).enabled(this.interactive)
      .accessibilityText(this.progressLabel).id(this.sliderId)
      .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
        if (typeof size.width !== 'number') return;
        if (this.sliderWidth > 0 && this.sliderWidth !== size.width) this.cancelDrag();
        this.sliderWidth = size.width;
      })
      .onChange((value: number, mode: SliderChangeMode): void => this.handleNativeChange(value, mode))
      .onTouch((event: TouchEvent): void => this.handleTouch(event))
      .priorityGesture(LongPressGesture({ fingers: 1, repeat: false, duration: 300 })
        .onAction((): void => this.beginTrackDrag())
        .onActionCancel((): void => this.cancelDrag()))
  }
}
