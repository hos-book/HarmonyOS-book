import { AppRadius, AppSpace, AppMotion, AppCurve, AppMaterial, HomeTheme, AppTheme } from '../theme/Theme';

/** 首页与搜索历史共用的原生沉浸材质标签。 */
@ComponentV2
@ReusableV2
export struct ImmersiveTabComponent {
  @Param label: ResourceStr = '';
  @Param selected: boolean = false;
  @Param itemWidth: number = 76;
  @Param fitContent: boolean = false;
  @Event onTap: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.label)
          .fontSize(13)
          .fontColor(this.selected ? HomeTheme.Accent : AppTheme.TextSecondary)
          .animation(this.fitContent ? null : { duration: AppMotion.Fast, curve: AppCurve.Standard })
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width(this.fitContent ? LayoutPolicy.wrapContent : '100%')
          .constraintSize({ maxWidth: this.fitContent ? undefined : this.itemWidth })
          .padding({
            left: this.fitContent ? AppSpace.Sm : AppSpace.Xxs,
            right: this.fitContent ? AppSpace.Sm : AppSpace.Xxs
          })
      }
      .width(this.fitContent ? LayoutPolicy.wrapContent : '100%')
      .height(30)
      .alignItems(VerticalAlign.Center)

      Row()
        .width(18)
        .height(2)
        .borderRadius(1)
        .backgroundColor(HomeTheme.Accent)
        .opacity(this.selected ? 1 : 0)
        .scale({ x: this.selected ? 1 : 0.35, y: 1 })
        .animation(this.fitContent ? null : { duration: AppMotion.Base, curve: AppCurve.Spring })
    }
    .width(this.fitContent ? LayoutPolicy.wrapContent : this.itemWidth)
    .height(34)
    .flexShrink(0)
    .borderRadius(AppRadius.Pill)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Transparent)
    // 文字使用稳定的主题色，滚动背景变化时不触发材质子树反色。
    .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveThin))
    // 材质尺寸随文字直接布局；动画仅保留在文字和选中指示上。
    .renderGroup(false)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => this.onTap())
  }
}

