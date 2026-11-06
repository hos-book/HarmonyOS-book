import { hexToHsv, hsvToHex, normalizeHex, isReaderHexColor } from '../model/ReaderTheme';
import { AppSpace } from '../theme/Theme';

/** 二维饱和度/明度调色盘，色相滑杆覆盖全部 RGB 颜色。 */
@ComponentV2
export struct ReaderColorPalette {
  @Param color: string = '#2D2925';
  @Param resetRevision: number = 0;
  @Event onChange: (color: string, commit: boolean) => void = () => {};
  @Local hue: number = 0;
  @Local saturation: number = 0;
  @Local valueLevel: number = 1;
  @Local hexInput: string = '';
  @Local inputValid: boolean = true;
  @Event onValidityChange: (valid: boolean) => void = () => {};
  private inputDirty: boolean = false;
  // 调色盘完成布局后宽度才可用；必须是响应式状态，否则重新进入页面时
  // 圆点虽然已经根据已保存色值算出饱和度，却不会按实际宽度重绘到正确位置。
  @Local paletteWidth: number = 1;

  private publishColor(color: string, commit: boolean): void {
    this.inputDirty = false;
    this.hexInput = color;
    this.inputValid = true;
    this.onValidityChange(true);
    this.onChange(color, commit);
  }

  private inputColor(value: string, commit: boolean): void {
    // 仅提交实际编辑；单纯聚焦再离开色值框不算手动选色。
    if (commit && !this.inputDirty) return;
    if (!commit) this.inputDirty = true;
    this.hexInput = value;
    this.inputValid = isReaderHexColor(value);
    this.onValidityChange(this.inputValid);
    if (!this.inputValid) return;
    const color = normalizeHex(value);
    if (commit) {
      this.hexInput = color;
      this.inputDirty = false;
    }
    this.onChange(color, commit);
  }

  aboutToAppear(): void { this.restore(); }
  @Monitor('color')
  onColorChanged(): void { this.restore(); }

  @Monitor('resetRevision')
  resetInput(): void {
    this.inputDirty = false;
    this.hexInput = normalizeHex(this.color);
    this.inputValid = true;
    this.onValidityChange(true);
    this.restore();
  }

  private restore(): void {
    if (!isReaderHexColor(this.hexInput) || normalizeHex(this.hexInput) !== normalizeHex(this.color)) {
      this.hexInput = normalizeHex(this.color);
      this.inputValid = true;
      this.onValidityChange(true);
    }
    const hsv = hexToHsv(this.color);
    if (hsv.s > 0 && hsv.v > 0) this.hue = hsv.h;
    this.saturation = hsv.s;
    this.valueLevel = hsv.v;
  }

  build() {
    Column({ space: AppSpace.Sm }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Row().width('100%').height(128)
          .linearGradient({ angle: 90, colors: [['#FFFFFF', 0], [hsvToHex(this.hue, 1, 1), 1]] })
        Row().width('100%').height(128)
          .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#FF000000', 1]] })
        Row().width(14).height(14).borderRadius(7).backgroundColor(Color.Transparent)
          .border({ width: 2, color: '#FFFFFF' })
          .position({ x: this.saturation * this.paletteWidth - 7, y: (1 - this.valueLevel) * 128 - 7 })
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%').height(128).clip(true).borderRadius(10)
      .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
        if (typeof size.width === 'number') this.paletteWidth = Math.max(1, size.width);
      })
      .gesture(PanGesture({ direction: PanDirection.All, distance: 1 }))
      .onTouch((event: TouchEvent): void => {
        const touch = event.touches[0] ?? event.changedTouches[0];
        if (touch === undefined) return;
        this.saturation = Math.max(0, Math.min(1, touch.x / this.paletteWidth));
        this.valueLevel = 1 - Math.max(0, Math.min(1, touch.y / 128));
        this.publishColor(hsvToHex(this.hue, this.saturation, this.valueLevel), event.type === TouchType.Up || event.type === TouchType.Cancel);
        event.stopPropagation();
      })
      Row({ space: 12 }) {
        Slider({ value: this.hue, min: 0, max: 360, step: 1 })
          .layoutWeight(1).selectedColor(hsvToHex(this.hue, 1, 1))
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.hue = value;
            this.publishColor(hsvToHex(value, this.saturation, this.valueLevel),
              mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
          })
        TextInput({ text: this.hexInput, placeholder: '#RRGGBB' })
          .width(116).height(36).fontSize(14).fontColor($r('sys.color.font_primary'))
          .maxLength(7).enterKeyType(EnterKeyType.Done)
          .accessibilityText($r('app.string.reader_color_hex_input'))
          .onChange((value: string): void => this.inputColor(value, false))
          .onSubmit((): void => this.inputColor(this.hexInput, true))
          .onBlur((): void => this.inputColor(this.hexInput, true))
        Row().width(24).height(24).borderRadius(12).backgroundColor(this.color)
      }.width('100%')
      if (!this.inputValid) {
        Text($r('app.string.reader_color_hex_invalid')).fontSize(12)
          .fontColor($r('sys.color.font_secondary')).width('100%')
      }
    }.width('100%')
  }
}
