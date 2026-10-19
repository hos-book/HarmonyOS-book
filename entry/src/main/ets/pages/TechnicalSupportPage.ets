import { AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

enum SupportNameStyle {
  Technical,
  Gold,
  BlackGold
}

@ComponentV2
export struct TechnicalSupportPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local technicalNames: string[] = [];
  @Local sponsorNames: string[] = [];

  aboutToAppear(): void {
    const resources = this.getUIContext().getHostContext()?.resourceManager;
    if (!resources) return;
    this.technicalNames = resources.getStringSync($r('app.string.technical_support_names').id).split('\n');
    this.sponsorNames = resources.getStringSync($r('app.string.sponsor_thanks_names').id).split('\n');
  }

  @Builder
  buildName(name: ResourceStr, style: SupportNameStyle) {
    Text(name)
      .fontSize(AppFont.BodyL)
      .fontWeight(FontWeight.Medium)
      .fontColor(style === SupportNameStyle.BlackGold ? $r('app.color.sponsor_black_gold')
        : style === SupportNameStyle.Gold ? $r('app.color.sponsor_gold') : $r('sys.color.font_primary'))
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor(style === SupportNameStyle.BlackGold ? $r('app.color.sponsor_black_gold_surface')
        : style === SupportNameStyle.Gold ? $r('app.color.sponsor_gold_surface') : $r('sys.color.comp_background_secondary'))
      .borderRadius(AppRadius.Md)
      .constraintSize({ maxWidth: '100%' })
      .margin({ right: 8, bottom: 8 })
  }

  @Builder
  buildSection(sponsor: boolean) {
    Column({ space: AppSpace.Md }) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Row({ space: 8 }) {
          Column().width(3).height(16)
            .backgroundColor(sponsor ? $r('app.color.sponsor_gold') : AppColor.Brand)
            .borderRadius(2)
          Text(sponsor ? $r('app.string.sponsor_thanks_title') : $r('app.string.technical_support_title'))
            .fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
        }
        .margin({ right: 12, bottom: 4 })
        Text($r('app.string.support_order_note'))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ bottom: 4 })
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        if (sponsor) {
          this.buildName($r('app.string.sponsor_thanks_hendo'), SupportNameStyle.BlackGold)
        } else {
          this.buildName($r('app.string.technical_support_light_page'), SupportNameStyle.BlackGold)
        }
        ForEach(sponsor ? this.sponsorNames : this.technicalNames, (name: string) => {
          this.buildName(name, sponsor ? SupportNameStyle.Gold : SupportNameStyle.Technical)
        }, (name: string) => name)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 20, right: 12, top: 22, bottom: 14 })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Xl)
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([$r('sys.color.font_primary')])
        }
        .width(44).height(44)
        .backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.common_back'))
        .onClick(() => this.navStack.pop())
        Text($r('app.string.about_technical_support'))
          .fontSize(AppFont.Title)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({
        top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Sm, right: AppSpace.Md, bottom: AppSpace.Sm
      })

      Scroll() {
        Column({ space: AppSpace.Md }) {
          Column({ space: 10 }) {
            Text($r('app.string.support_intro_title'))
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
            Text($r('app.string.support_intro_body'))
              .fontSize(AppFont.Body)
              .lineHeight(22)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 4, right: 4, top: 16, bottom: 12 })

          this.buildSection(false)
          this.buildSection(true)
        }
        .width('100%')
        .constraintSize({ maxWidth: 640 })
        .padding({
          left: AppSpace.Md, right: AppSpace.Md,
          bottom: WindowUtils.getBottomSafeVp() + AppSpace.Xl
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
