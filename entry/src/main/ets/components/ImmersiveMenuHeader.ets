import { AppFont, AppSpace } from '../theme/Theme';

/** 可滚动的复杂菜单保留紧凑标题和明确关闭入口。 */
@ComponentV2
export struct ImmersiveMenuHeader {
  @Param title: ResourceStr = '';
  @Event onClose: () => void = (): void => {};

  build() {
    Row({ space: AppSpace.Xs }) {
      Text(this.title).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([$r('sys.color.font_primary')])
      }.width(36).height(36).backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.common_close'))
        .onClick((): void => this.onClose())
    }.width('100%').constraintSize({ minHeight: 44 }).flexShrink(0)
      .padding({ left: AppSpace.Xs, right: AppSpace.Xxs })
  }
}
