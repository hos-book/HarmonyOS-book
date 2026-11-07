import { AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { VipFeatureBadge } from './VipFeatureBadge';
import { SettingsHintButton } from './SettingsHintButton';

/**
 * 设置分组卡片。
 * 内容走 @BuilderParam + 尾随闭包；UI 描述不能当普通 lambda 参数传，
 * 所以这里必须是独立组件而不是父组件里的 @Builder 方法。
 */
@ComponentV2
export struct ReaderSettingCard {
  @Param title: ResourceStr = '';
  @Param showTitle: boolean = true;
  @Param description: ResourceStr = '';
  @Param inline: boolean = false;
  @Param showVip: boolean = false;
  @Param compact: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent(): void {
  }

  build() {
    Column({ space: this.compact ? 4 : AppSpace.Sm }) {
      if (this.inline) {
        Row({ space: AppSpace.Sm }) {
          Row({ space: 2 }) {
            Text(this.title)
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_primary'))
              .flexShrink(1)
            if (this.showVip) { VipFeatureBadge() }
            if (this.description) { SettingsHintButton({ title: this.title, message: this.description }) }
          }.layoutWeight(1).alignItems(VerticalAlign.Center)
          this.content()
        }.width('100%').alignItems(VerticalAlign.Center)
      } else {
      if (this.showTitle) {
        Row({ space: 2 }) {
          Text(this.title)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
            .flexShrink(1)
          if (this.description) { SettingsHintButton({ title: this.title, message: this.description }) }
        }.width('100%')
      }
      this.content()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppSpace.Md, right: AppSpace.Md,
      top: this.compact ? 8 : AppSpace.Md, bottom: this.compact ? 8 : AppSpace.Md })
    .borderRadius(AppRadius.Lg)
    .backgroundColor($r('app.color.reader_setting_card_background'))
    .border({ width: 1, color: $r('app.color.reader_setting_card_border') })
  }
}

@ComponentV2
export struct ReaderSettingsSectionHeader {
  @Param title: ResourceStr = '';

  build() {
    Text(this.title).fontSize(AppFont.Caption).fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary')).width('100%')
      .padding({ left: 6, right: 6, top: 8, bottom: 2 })
  }
}
