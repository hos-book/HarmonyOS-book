import { MembershipSubscriptionPage, MEMBERSHIP_BACKGROUND_TOP } from './MembershipSubscriptionPage';
import { MembershipService } from '../service/MembershipService';
import { AppColor, AppFont, AppSpace, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { AppIconPage } from './AppIconPage';
import { AppIconService } from '../service/AppIconService';
import { ThemeBundleComponent } from '../components/ThemeBundleComponent';

/** 主题选择独立展示，受限图标按需打开会员中心。 */
@ComponentV2
export struct MembershipPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local membership: MembershipService = MembershipService.instance;

  @Local showMembership: boolean = false;

  @Builder
  membershipSheet() {
    MembershipSubscriptionPage({ navStack: this.navStack, inSheet: true,
      onClose: (): void => { this.showMembership = false; } })
  }

  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
        }.width(40).height(40).backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.app_icon_back')).onClick(() => this.navStack.pop())
        Text($r('app.string.membership_title')).fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TextPrimary)
        Blank()
      }.width('100%').padding({ top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
        left: AppSpace.Sm, right: AppSpace.Md, bottom: AppSpace.Sm })
      Tabs({ barPosition: BarPosition.Start }) {
        TabContent() {
          Scroll() {
            Column({ space: AppSpace.Lg }) {
              if (AppIconService.instance.membershipRequired && this.membership.busy) {
                Row({ space: AppSpace.Sm }) {
                  LoadingProgress().width(24).height(24).color(AppColor.Brand)
                  Text($r('app.string.membership_syncing')).fontSize(AppFont.Body)
                    .fontColor($r('sys.color.font_secondary')).layoutWeight(1)
                }.width('100%')
              }
              AppIconPage({ onMembershipRequired: (): void => { this.showMembership = true; } })
            }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: AppSpace.Md, right: AppSpace.Md,
              top: AppSpace.Sm, bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg })
          }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
        }.tabBar(SubTabBarStyle.of($r('app.string.app_icon_title'))
          .indicator({ color: AppColor.Brand })
          .labelStyle({ selectedColor: AppColor.Brand, unselectedColor: AppTheme.TextSecondary }))
        TabContent() {
          Scroll() {
            Column() {
              ThemeBundleComponent()
            }.width('100%').constraintSize({ maxWidth: 920 })
            .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Sm,
              bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg })
          }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
        }.tabBar(SubTabBarStyle.of($r('app.string.theme_bundle_title'))
          .indicator({ color: AppColor.Brand })
          .labelStyle({ selectedColor: AppColor.Brand, unselectedColor: AppTheme.TextSecondary }))
      }.width('100%').layoutWeight(1).barMode(BarMode.Fixed).barHeight('auto')
    }.width('100%').height('100%').backgroundColor(AppTheme.Background)
    .bindSheet($$this.showMembership, this.membershipSheet(), {
      height: '90%', detents: ['90%', '45%', SheetSize.LARGE], preferType: SheetType.BOTTOM, showClose: false, dragBar: true, backgroundColor: MEMBERSHIP_BACKGROUND_TOP
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
