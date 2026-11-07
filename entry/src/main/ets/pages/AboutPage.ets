import { AppTheme, AppColor, AppRadius, AppSpace, AppFont } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { sendableContextManager } from '@kit.AbilityKit';
import { UpdateService } from '../service/UpdateService';

@ComponentV2
export struct AboutPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Local appVersion: string = '0.0.0';
  @Local openingMarket: boolean = false;

  aboutToAppear(): void {
    this.appVersion = UpdateService.getCurrentVersion();
  }

  private async openAppGallery(): Promise<void> {
    if (this.openingMarket) return;
    this.openingMarket = true;
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        throw new Error('UIAbilityContext unavailable');
      }
      const abilityContext = sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(context));
      await UpdateService.openAppGallery(abilityContext);
    } catch (_e) {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.about_update_open_failed'), duration: 2000
      });
    } finally {
      this.openingMarket = false;
    }
  }

  @Builder
  updateTrailing(): void {
    if (this.openingMarket) {
      LoadingProgress()
        .width(18)
        .height(18)
        .color(AppColor.Brand)
    } else {
      Row({ space: 4 }) {
        Text($r('app.string.about_update_market'))
          .fontSize(AppFont.Body)
          .fontColor(AppTheme.TextTertiary)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([AppTheme.TextTertiary])
      }
      .alignItems(VerticalAlign.Center)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
      Column({ space: AppSpace.Lg }) {
        Column({ space: AppSpace.Sm }) {
          Image($r('app.media.app_icon_legacy'))
            .width(80)
            .height(80)
            .borderRadius(AppRadius.Xl)
            .clip(true)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 12, color: AppColor.Shadow, offsetY: 4 })

          Text($r('app.string.EntryAbility_label'))
            .fontSize(AppFont.TitleL)
            .fontColor(AppTheme.TextPrimary)
            .fontWeight(FontWeight.Bold)
          Text(`v${this.appVersion}`)
            .fontSize(AppFont.Body)
            .fontColor(AppTheme.TextTertiary)
        }
        .alignItems(HorizontalAlign.Center)
        .padding({ top: AppSpace.Xl })

        Column() {
          Row() {
            Text($r('app.string.about_get_update'))
              .fontSize(AppFont.BodyL)
              .fontColor(AppTheme.TextSecondary)
            Blank()
            this.updateTrailing()
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.openAppGallery())

          Divider().color(AppTheme.Divider).margin({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row() {
            Text($r('app.string.guide_title'))
              .fontSize(AppFont.BodyL)
              .fontColor(AppTheme.TextSecondary)
            Blank()
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([AppTheme.TextTertiary])
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.navStack.pushPathByName('guide', ''))

          Divider().color(AppTheme.Divider).margin({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row() {
            Text($r('app.string.about_open_source'))
              .fontSize(AppFont.BodyL)
              .fontColor(AppTheme.TextSecondary)
            Blank()
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([AppTheme.TextTertiary])
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.navStack.pushPathByName('openSource', ''))

          Divider().color(AppTheme.Divider).margin({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row() {
            Text($r('app.string.about_technical_support'))
              .fontSize(AppFont.BodyL)
              .fontColor(AppTheme.TextSecondary)
            Blank()
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([AppTheme.TextTertiary])
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.navStack.pushPathByName('technicalSupport', ''))

          Divider().color(AppTheme.Divider).margin({ left: AppSpace.Lg, right: AppSpace.Lg })
          Row() {
            Text($r('app.string.about_compliance_title'))
              .fontSize(AppFont.BodyL)
              .fontColor(AppTheme.TextSecondary)
            Blank()
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([AppTheme.TextTertiary])
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.navStack.pushPathByName('compliance', ''))

          Divider().color(AppTheme.Divider).margin({ left: AppSpace.Lg, right: AppSpace.Lg })

          Row() {
            Text('隐私政策')
              .fontSize(AppFont.BodyL)
              .fontColor(AppTheme.TextSecondary)
            Blank()
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([AppTheme.TextTertiary])
          }
          .width('100%')
          .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md, bottom: AppSpace.Md })
          .onClick(() => this.navStack.pushPathByName('privacy', ''))
        }
        .backgroundColor(AppTheme.Surface)
        .borderRadius(AppRadius.Lg)
        .margin({ left: AppSpace.Sm, right: AppSpace.Sm })

        Text($r('app.string.app_description'))
          .fontSize(AppFont.Body)
          .fontColor(AppTheme.TextTertiary)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: -(AppSpace.Lg - AppSpace.Md) })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: this.headerHeight, bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24).fontColor([AppTheme.TextPrimary])
            .onClick(() => this.navStack.pop())
          Text('关于').fontSize(AppFont.Title).fontColor(AppTheme.TextPrimary)
            .fontWeight(FontWeight.Bold).margin({ left: AppSpace.Sm })
        }.width('100%').padding({
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
          left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Md
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.SettingsBackground)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
