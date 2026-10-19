import { AppColor, AppFont, AppMaterial, AppRadius, AppSpace } from '../theme/Theme';

/**
 * 设置分组卡片。
 * 内容走 @BuilderParam + 尾随闭包；UI 描述不能当普通 lambda 参数传，
 * 所以这里必须是独立组件而不是父组件里的 @Builder 方法。
 */
@ComponentV2
export struct ReaderSettingCard {
  @Param title: ResourceStr = '';
  @Param inline: boolean = false;
  @Param compact: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent(): void {
  }

  build() {
    Column({ space: this.compact ? 4 : AppSpace.Sm }) {
      if (this.inline) {
        Row({ space: AppSpace.Sm }) {
          Text(this.title)
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          this.content()
        }.width('100%').alignItems(VerticalAlign.Center)
      } else {
      Text(this.title)
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_secondary'))
        .fontWeight(FontWeight.Medium)
        .width('100%')
      this.content()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpace.Md, right: AppSpace.Md,
      top: this.compact ? 8 : AppSpace.Md, bottom: this.compact ? 8 : AppSpace.Md })
    .borderRadius(AppRadius.Lg)
    .backgroundColor(AppColor.GlassSheetControlTint)
    .border({ width: 0.5, color: AppColor.GlassSheetStroke })
  }
}
