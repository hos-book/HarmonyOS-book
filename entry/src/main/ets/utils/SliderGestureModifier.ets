/** 轨道控件统一防误触：禁止点击跳变，拖动超过取值范围的 4% 才开始调节。 */
export class SliderGestureModifier implements AttributeModifier<SliderAttribute> {
  private readonly responsiveDistance: number;

  constructor(min: number, max: number) {
    const range: number = max - min;
    this.responsiveDistance = Number.isFinite(range) && range > 0 ? range * 0.04 : 0;
  }

  applyNormalAttribute(slider: SliderAttribute): void {
    slider.sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
      .minResponsiveDistance(this.responsiveDistance);
  }
}
