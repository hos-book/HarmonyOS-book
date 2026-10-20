import { AppColor, AppMaterial } from '../theme/Theme';

@ComponentV2
export struct ReaderBrightnessBar {
  @Param value: number = -1;
  @Param barHeight: number = 280;
  @Param foreground: ResourceColor = $r('sys.color.font_primary');
  @Event onChange: (value: number, commit: boolean) => void = (): void => {};

  build() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.sun_max')).fontSize(20).fontColor([this.foreground])
      Text(this.value < 0 ? $r('app.string.reader_brightness_auto') : `${Math.round(this.value * 100)}%`)
        .fontSize(10).height(16).fontColor(this.foreground).maxLines(1)
      Slider({ value: this.value < 0 ? 50 : this.value * 100,
        min: 0, max: 100, step: 1, direction: Axis.Vertical, reverse: true })
        .layoutWeight(1).width(32).blockSize({ width: 18, height: 18 }).trackThickness(4)
        .blockColor(AppColor.Brand).selectedColor(AppColor.Brand)
        .accessibilityText($r('app.string.reader_brightness'))
        .onChange((value: number, mode: SliderChangeMode): void => {
          this.onChange(value / 100, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
        })
      Button($r('app.string.reader_brightness_auto')).fontSize(11).height(32).width(44).padding(0)
        .fontColor(this.value < 0 ? AppColor.Brand : this.foreground)
        .backgroundColor(Color.Transparent).onClick((): void => this.onChange(-1, true))
    }.width(48).height(this.barHeight).padding({ top: 12, bottom: 4 }).borderRadius(24)
      .attributeModifier(AppMaterial.modifier(AppMaterial.FloatingControl, AppColor.GlassSheetFallback))
      .onTouch((event: TouchEvent): void => { event.stopPropagation(); })
  }
}
