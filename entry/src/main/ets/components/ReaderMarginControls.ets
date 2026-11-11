/** 正文、页眉、页脚与标题共用的边距控件；统一防误触与步进操作。 */
import { AppColor, AppFont, AppSpace, AppCurve } from '../theme/Theme';
import { SliderGestureModifier } from '../utils/SliderGestureModifier';

/** 独立组件接收响应式参数，避免多参数 Builder 缓存首次 enabled 状态。 */
@ComponentV2
struct ReaderMarginStepButton {
  @Param decrease: boolean = false;
  @Param canStep: boolean = false;
  @Param idPrefix: string = 'reader-margin';
  @Event onStep: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      SymbolGlyph(this.decrease ? $r('sys.symbol.minus') : $r('sys.symbol.plus'))
        .fontSize(16).fontColor([$r('sys.color.font_primary')])
    }.width(34).height(34).backgroundColor(Color.Transparent).hoverEffect(HoverEffect.None)
      .enabled(this.canStep).opacity(this.canStep ? 1 : 0.4)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .id(`${this.idPrefix}-${this.decrease ? 'minus' : 'plus'}`)
      .onClick((): void => this.onStep())
  }
}

@ComponentV2
export struct ReaderMarginSlider {
  @Param label: Resource = $r('app.string.reader_margin_top');
  @Param value: number = 16;
  @Param max: number = 64;
  @Param unit: string = '';
  @Param idPrefix: string = 'reader-margin';
  @Event onChange: (value: number, commit: boolean) => void = () => {};
  @Local current: number = 16;

  aboutToAppear(): void { this.syncValue(); }

  @Monitor('value', 'max')
  syncValue(): void { this.current = this.clamp(this.value); }

  private clamp(value: number): number {
    return Number.isFinite(value) ? Math.round(Math.max(0, Math.min(this.max, value))) : 0;
  }

  private update(value: number, commit: boolean): void {
    this.current = this.clamp(value);
    this.onChange(this.current, commit);
  }

  build() {
    Row({ space: AppSpace.Sm }) {
      Text(this.label).fontSize(AppFont.Caption).width(36).fontColor($r('sys.color.font_primary'))
      ReaderMarginStepButton({ decrease: true, canStep: this.current > 0, idPrefix: this.idPrefix,
        onStep: (): void => this.update(this.current - 1, true) })
      Slider({ value: this.current, min: 0, max: this.max, step: 1 })
        .attributeModifier(new SliderGestureModifier(0, this.max))
        .layoutWeight(1).selectedColor(AppColor.Brand)
        .accessibilityText(this.label).id(this.idPrefix)
        .onChange((next: number, mode: SliderChangeMode): void => {
          this.update(next, mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
        })
      ReaderMarginStepButton({ canStep: this.current < this.max, idPrefix: this.idPrefix,
        onStep: (): void => this.update(this.current + 1, true) })
      Text(`${this.current}${this.unit}`).width(40).fontColor($r('sys.color.font_primary')).fontSize(AppFont.Caption)
        .textAlign(TextAlign.End).id(`${this.idPrefix}-value`)
    }.width('100%')
  }
}

@ComponentV2
export struct ReaderEdgeTabs {
  @Param selected: number = 0;
  @Param groupId: string = '';
  @Event onSelect: (index: number) => void = () => {};

  build() {
    Row({ space: 4 }) {
      ForEach([$r('app.string.reader_margin_top'), $r('app.string.reader_margin_bottom'),
        $r('app.string.reader_margin_left'), $r('app.string.reader_margin_right')], (label: Resource, index: number) => {
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Stack() {
            if (this.selected === index) {
              Row().width('100%').height('100%').borderRadius(18)
                .backgroundColor($r('sys.color.comp_background_primary'))
                .geometryTransition(`${this.groupId}-selection`)
                .hitTestBehavior(HitTestMode.None)
            }
            Text(label).fontSize(AppFont.Body)
              .fontColor(this.selected === index ? AppColor.Brand : $r('sys.color.font_primary'))
          }.width('100%').height(36)
        }
          .id(`${this.groupId}-${index}`)
          .layoutWeight(1).height(36).padding(0).backgroundColor(Color.Transparent).clip(false)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
          .accessibilityText(label)
          .accessibilitySelected(this.selected === index)
          .onClick((): void => {
            if (this.selected === index) return;
            // 各组设置使用独立的共享元素 ID，选中底板随弹簧滑动。
            this.getUIContext().animateTo({ curve: AppCurve.Spring }, (): void => this.onSelect(index));
          })
      }, (label: Resource): string => `${label.id}`)
    }.width('100%').padding(4).borderRadius(22)
      .backgroundColor($r('sys.color.comp_background_tertiary')).clip(true)
  }
}
