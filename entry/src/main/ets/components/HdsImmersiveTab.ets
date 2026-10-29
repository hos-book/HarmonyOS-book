import { HdsTabs } from '@kit.UIDesignKit';
import { PlatformCompat } from '../utils/PlatformCompat';
import { HdsCompat } from '../utils/HdsCompat';
import { AppRadius, AppColor, HomeTheme } from '../theme/Theme';

/** 浮动栏圆角裁剪；API 23 起走离屏策略，与 ImmersiveCircleButton 一致。 */
class HdsTabClip implements AttributeModifier<CommonAttribute> {
  private radius: number;

  constructor(radius: number) { this.radius = radius; }

  applyNormalAttribute(node: CommonAttribute): void {
    if (PlatformCompat.floatingTabs) node.borderRadius(this.radius, RenderStrategy.OFFSCREEN);
    else node.borderRadius(this.radius);
    node.clip(true);
  }
}

/**
 * NavDestination 页面（详情 / 搜索 / 播放）上的沉浸标签。
 *
 * 这些页面里 ArkUI 的 systemMaterial（uiMaterial）不绘制：同一页面用 HdsTabs 浮动栏
 * 承载的圆形按钮却能正常出材质（滚动容器内外都一样）。因此这里改用 HdsTabs 的
 * barFloatingStyle 承载材质，与 ImmersiveCircleButton 走同一条渲染路径。
 *
 * 浮动栏要求明确宽度，所以按字宽估算胶囊宽度，保证整段文字完整显示。
 * 注意 width / height 是 CustomComponent 的保留名，参数只能另起名字。
 *
 * 可通过 onPress 响应点击；事件必须挂在内部根节点，外层 onClick 会被 Block 命中策略挡住。
 * 横向滑动自己接管：
 * 胶囊内部是 HdsTabs（Swiper + 自带可点的 TabBar），实测从胶囊上起手时外层 Scroll
 * 的横向拖动会被内部节点吃掉，只有从胶囊之间的空隙起手才滑得动。
 * 所以这里在胶囊根节点上挂 PanGesture，直接驱动外层 Scroll 的 Scroller，
 * 保证「从任何位置起手都能滑」。材质层与文字层仍设 hitTestBehavior(None)。
 */
@ComponentV2
export struct HdsImmersiveTab {
  @Param label: ResourceStr = '';
  /** 0 表示按文字宽度自适应；Resource 文案无法估算宽度时按 72vp 兜底。 */
  @Param tabWidth: number = 0;
  @Param tabHeight: number = 34;
  @Param selected: boolean = false;
  /** 封面转场先显示同尺寸标签，交接后再建立独立的 HDS 材质树。 */
  @Param materialEnabled: boolean = true;
  /**
   * 外层横向 Scroll 的控制器。
   * 胶囊内部是 HdsTabs（Swiper + 自带可点的 TabBar），从胶囊上起手时
   * 外层 Scroll 的横向拖动会被它吃掉（只有从胶囊之间的空隙起手才滑得动）。
   * 所以胶囊自己接管横向拖动，用这个 Scroller 直接驱动外层滚动。
   */
  @Param scroller: Scroller = new Scroller();
  @Event onPress: () => void = () => {};
  /** 上一帧的累计位移，用来把 PanGesture 的累计 offsetX 换算成增量。 */
  private panBase: number = 0;

  /** 中文字宽约等于字号，ASCII 约半宽；两端各留 14vp 内边距。 */
  private static estimateWidth(label: ResourceStr): number {
    if (typeof label !== 'string') return 72;
    let units: number = 0;
    for (let index: number = 0; index < label.length; index++) {
      units += label.charCodeAt(index) > 0x2E80 ? 14 : 8;
    }
    return Math.round(Math.min(Math.max(units + 28, 56), 240));
  }

  private resolveWidth(): number {
    return this.tabWidth > 0 ? this.tabWidth : HdsImmersiveTab.estimateWidth(this.label);
  }

  @Builder
  barBackdrop() {
    Stack().width('100%').height('100%')
  }

  @Builder
  tabLabel() {
    Text(this.label)
      .fontSize(14)
      .fontColor(this.selected ? HomeTheme.Accent : $r('sys.color.font_secondary'))
      .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Center)
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (!this.materialEnabled) {
        Column()
          .width('100%').height('100%')
          .borderRadius(AppRadius.Pill)
          .backgroundColor(AppColor.GlassControlFallback)
          .hitTestBehavior(HitTestMode.None)
      } else if (PlatformCompat.floatingTabs) {
        // HdsTabs 内部是 Swiper，会抢横向拖动的手势，导致外层横向 Scroll 滑不动。
        // 这里只借它的浮动栏承载材质，命中测试全部让给外层 Stack。
        HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
          TabContent() { Column() }.height(this.tabHeight).tabBar(this.barBackdrop())
        }
          .barMode(BarMode.Fixed)
          .barHeight(this.tabHeight)
          .barOverlap(true)
          .barFloatingStyle({
            barWidth: {
              smallWidth: this.resolveWidth(),
              mediumWidth: this.resolveWidth(),
              largeWidth: this.resolveWidth()
            },
            systemMaterialEffect: HdsCompat.material,
            barSideMargin: 0,
            barBottomMargin: 0,
            gradientMask: { maskColor: '#00000000', maskHeight: this.tabHeight },
            adaptToHandedness: false,
            thermoCtrl: true,
            barOpacity: 1
          })
          .scrollable(false)
          .onContentWillChange((): boolean => false)
          .width(this.resolveWidth())
          .height(this.tabHeight)
          .hitTestBehavior(HitTestMode.None)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .borderRadius(AppRadius.Pill)
          .backgroundColor(AppColor.GlassControlFallback)
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
          .hitTestBehavior(HitTestMode.None)
      }

      this.tabLabel()
    }
    .width(this.resolveWidth())
    .height(this.tabHeight)
    .attributeModifier(new HdsTabClip(this.tabHeight / 2))
    // Block：根节点自己响应触摸测试，把子节点（HdsTabs 内部的 Swiper / 可点 TabBar）
    // 全部挡在命中测试之外，横向拖动才不会被它们抢走。
    .hitTestBehavior(HitTestMode.Block)
    .onClick((): void => this.onPress())
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 4 })
        .onActionStart((): void => {
          this.panBase = 0;
        })
        .onActionUpdate((event: GestureEvent): void => {
          // offsetX 是从手势开始累计的位移，这里取增量后反向驱动 Scroll。
          const delta = event.offsetX - this.panBase;
          this.panBase = event.offsetX;
          this.scroller.scrollBy(-delta, 0);
        })
    )
  }
}
