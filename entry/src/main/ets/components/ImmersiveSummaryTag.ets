import { HdsTabs } from '@kit.UIDesignKit';
import { AppColor, AppTheme } from '../theme/Theme';
import { HdsCompat } from '../utils/HdsCompat';
import { PlatformCompat } from '../utils/PlatformCompat';

/** HDS 内部阴影必须在最终合成层按胶囊裁剪；普通圆角或 shadow(0) 不能代替。 */
class ImmersiveSummaryClip implements AttributeModifier<CommonAttribute> {
  private radius: number;

  constructor(radius: number) { this.radius = radius; }

  applyNormalAttribute(node: CommonAttribute): void {
    if (PlatformCompat.floatingTabs) node.borderRadius(this.radius, RenderStrategy.OFFSCREEN);
    else node.borderRadius(this.radius);
    node.clip(true);
  }
}

/** 与顶部圆形按钮共用 HDS 浮动栏材质，仅展示统计，不接管触摸。 */
@ComponentV2
export struct ImmersiveSummaryTag {
  @Param icon: Resource = $r('sys.symbol.clock');
  @Param label: ResourceStr = '';
  @Param value: ResourceStr = '';
  private contentWidth(): number {
    const ui = this.getUIContext();
    const measure = ui.getMeasureUtils();
    const labelWidth = measure.measureText({ textContent: this.label, fontSize: 12 });
    const spaceWidth = measure.measureText({ textContent: ' ', fontSize: 12 });
    const valueWidth = measure.measureText({ textContent: this.value, fontSize: 12, fontWeight: FontWeight.Medium });
    return Math.ceil(ui.px2vp(labelWidth + spaceWidth + valueWidth)) + 36;
  }

  private contentHeight(): number {
    const ui = this.getUIContext();
    const size = ui.getMeasureUtils().measureTextSize({ textContent: this.value, fontSize: 12,
      fontWeight: FontWeight.Medium, maxLines: 1 });
    return Math.ceil(ui.px2vp(Number(size.height))) + 12;
  }

  @Builder
  backdrop() {
    Stack().width('100%').height('100%')
  }

  build() {
    Stack() {
      if (PlatformCompat.floatingTabs) {
        HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
          TabContent() { Column() }.height(this.contentHeight()).tabBar(this.backdrop())
        }
        .barMode(BarMode.Fixed).barHeight(this.contentHeight()).barOverlap(true)
        .barFloatingStyle({
          barWidth: { smallWidth: this.contentWidth(),
            mediumWidth: this.contentWidth(),
            largeWidth: this.contentWidth() },
          systemMaterialEffect: HdsCompat.material,
          barSideMargin: 0, barBottomMargin: 0,
          gradientMask: { maskColor: '#00000000', maskHeight: this.contentHeight() },
          adaptToHandedness: false, thermoCtrl: true, barOpacity: 1
        })
        .scrollable(false).onContentWillChange((): boolean => false)
        .width(this.contentWidth()).height(this.contentHeight())
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
      } else {
        Row().width('100%').height('100%')
          .backgroundColor($r('sys.color.comp_background_primary'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
          .border({ width: 0.5, color: $r('sys.color.comp_divider'), radius: this.contentHeight() / 2 })
          .borderRadius(this.contentHeight() / 2)
          .clip(true)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      }
      Row({ space: 4 }) {
        SymbolGlyph(this.icon).fontSize(12).fontColor([AppColor.Brand])
        Text() {
          Span(this.label).fontColor(AppTheme.TextSecondary)
          Span(' ')
          Span(this.value).fontSize(12).fontColor(AppTheme.TextPrimary).fontWeight(FontWeight.Medium)
        }.fontSize(12).maxLines(1)
      }.width('100%').padding({ left: 10, right: 10 })
    }.width(this.contentWidth()).height(this.contentHeight())
      .attributeModifier(new ImmersiveSummaryClip(this.contentHeight() / 2))
      .hitTestBehavior(HitTestMode.None)
  }
}
