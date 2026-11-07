import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { MembershipSubscriptionPage, MEMBERSHIP_BACKGROUND_TOP } from './MembershipSubscriptionPage';
import { MembershipService } from '../service/MembershipService';
import { CapsuleSegmentButtonV2, ColorMetrics, LengthMetrics, SegmentButtonV2Items } from '@kit.ArkUI';
import { HdsTabs } from '@kit.UIDesignKit';
import { AppColor, AppFont, AppSpace, AppTheme, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { PlatformCompat } from '../utils/PlatformCompat';
import { HdsCompat } from '../utils/HdsCompat';
import { AppIconPage } from './AppIconPage';
import { AppIconService } from '../service/AppIconService';
import { ThemeBundleComponent } from '../components/ThemeBundleComponent';
import { BottomTabIconComponent } from '../components/BottomTabIconComponent';

/** 主题选择独立展示，受限图标按需打开会员中心。 */
@ComponentV2
export struct MembershipPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local membership: MembershipService = MembershipService.instance;

  @Local showMembership: boolean = false;
  @Local selectedTab: number = 0;
  @Local tabBarHeight: number = 40;
  @Local tabBarWidth: number = 0;
  @Local titleBarHeight: number = WindowUtils.getStatusBarHeightVp() + 40 + AppSpace.Sm * 2;
  private tabsController: TabsController = new TabsController();
  private tabItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: $r('app.string.app_icon_title') },
    { text: $r('app.string.theme_bundle_title') },
    { text: $r('app.string.bottom_tab_icon_title') }
  ]);

  @Builder
  membershipSheet() {
    MembershipSubscriptionPage({ navStack: this.navStack, inSheet: true,
      onClose: (): void => { this.showMembership = false; } })
  }

  @Builder
  themeTabBackdrop() {
    Row().width('100%').height(this.tabBarHeight)
  }

  @Builder
  themeTabBar() {
    Stack({ alignContent: Alignment.Center }) {
      // NavDestination 内统一由 HDS 承载沉浸材质，原生分段按钮只负责点击与选中反馈。
      if (PlatformCompat.floatingTabs && HdsCompat.materialSupported && this.tabBarWidth > 0) {
        HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
          TabContent() {}.tabBar(this.themeTabBackdrop())
        }.barMode(BarMode.Fixed).barHeight(this.tabBarHeight).barOverlap(true)
          .barFloatingStyle({
            barWidth: { smallWidth: this.tabBarWidth, mediumWidth: this.tabBarWidth, largeWidth: this.tabBarWidth },
            systemMaterialEffect: HdsCompat.material,
            barSideMargin: 0,
            barBottomMargin: 0,
            gradientMask: { maskColor: Color.Transparent, maskHeight: this.tabBarHeight },
            adaptToHandedness: false,
            thermoCtrl: true,
            barOpacity: 1
          })
          .scrollable(false).onContentWillChange((): boolean => false)
          .width(this.tabBarWidth).height(this.tabBarHeight)
          .borderRadius(this.tabBarHeight / 2, RenderStrategy.OFFSCREEN).clip(true)
          .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS)
          .accessibilityLevel('no-hide-descendants')
      }

      CapsuleSegmentButtonV2({
        items: this.tabItems,
        selectedIndex: this.selectedTab,
        $selectedIndex: (index: number): void => this.tabsController.changeIndex(index),
        itemFontSize: LengthMetrics.fp(13),
        itemSelectedFontSize: LengthMetrics.fp(13),
        itemFontWeight: FontWeight.Regular,
        itemSelectedFontWeight: FontWeight.Medium,
        itemFontColor: ColorMetrics.resourceColor(AppTheme.TextSecondary),
        itemSelectedFontColor: ColorMetrics.resourceColor(HomeTheme.Accent),
        itemSelectedBackgroundColor: ColorMetrics.resourceColor($r('app.color.shelf_filter_selected_background')),
        itemBorderRadius: LengthMetrics.vp((this.tabBarHeight - 6) / 2),
        itemMinHeight: LengthMetrics.vp(34),
        itemShadow: { radius: 0, color: Color.Transparent },
        buttonBackgroundColor: ColorMetrics.resourceColor(HdsCompat.materialSupported ? Color.Transparent :
          $r('app.color.shelf_filter_background')),
        buttonBackgroundBlurStyle: HdsCompat.materialSupported ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
        buttonBorderRadius: LengthMetrics.vp(this.tabBarHeight / 2),
        buttonMinHeight: LengthMetrics.vp(40),
        buttonPadding: LengthMetrics.vp(3)
      })
        .width('100%')
        .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions): void => {
          const height: number = Number(newSize.height);
          const width: number = Number(newSize.width);
          if (height > 0 && Math.abs(height - this.tabBarHeight) > 0.1) this.tabBarHeight = height;
          if (width > 0 && Math.abs(width - this.tabBarWidth) > 0.1) this.tabBarWidth = width;
        })

      Row() {
        ForEach(['app-icon', 'theme-bundle', 'bottom-tab-icon'], (key: string, index: number) => {
          Row()
            .layoutWeight(1)
            .height(this.tabBarHeight - 6)
            .borderRadius((this.tabBarHeight - 6) / 2)
            .border({ width: 1, color: $r('app.color.shelf_filter_selected_border') })
            .opacity(this.selectedTab === index ? 1 : 0)
            .animation({ duration: 180, curve: Curve.EaseInOut })
        }, (key: string) => key)
      }.width('100%').height(this.tabBarHeight).padding(3)
        // 整棵描边子树均透传，None 只排除父 Row，其子项仍会挡住原生按钮。
        .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS).accessibilityLevel('no-hide-descendants')

      Row().width('100%').height(this.tabBarHeight).borderRadius(this.tabBarHeight / 2)
        .border({ width: 1, color: $r('app.color.shelf_filter_border') })
        .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS).accessibilityLevel('no-hide-descendants')
    }.width('100%').constraintSize({ maxWidth: 680 })
      .id('theme-immersive-tabs')
  }

  @Builder
  themeTitleBar() {
    FrostedPageHeader({ onHeightChange: (height: number): void => { this.titleBarHeight = height; } }) {
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
        .id('theme-frosted-title-bar')
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Tabs({ controller: this.tabsController, index: $$this.selectedTab }) {
        TabContent() {
          Scroll() {
            Column({ space: AppSpace.Lg }) {
              if (AppIconService.instance.membershipRequired && this.membership.busy) {
                Row({ space: AppSpace.Sm }) {
                  LoadingProgress().width(24).height(24).color(AppColor.Brand)
                  Text($r('app.string.membership_syncing')).fontSize(AppFont.Body)
                    .fontColor(AppTheme.TextSecondary).layoutWeight(1)
                }.width('100%')
              }
              AppIconPage({ onMembershipRequired: (): void => { this.showMembership = true; } })
            }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: AppSpace.Md, right: AppSpace.Md,
              top: this.titleBarHeight + this.tabBarHeight + AppSpace.Sm * 3,
              bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg })
          }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
        }
        TabContent() {
          Scroll() {
            Column() {
              ThemeBundleComponent({ onMembershipRequired: (): void => { this.showMembership = true; } })
            }.width('100%').constraintSize({ maxWidth: 920 })
            .padding({ left: AppSpace.Md, right: AppSpace.Md,
              top: this.titleBarHeight + this.tabBarHeight + AppSpace.Sm * 3,
              bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg })
          }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
        }
        TabContent() {
          Scroll() {
            Column() {
              BottomTabIconComponent()
            }.width('100%').constraintSize({ maxWidth: 680 })
            .padding({ left: AppSpace.Md, right: AppSpace.Md,
              top: this.titleBarHeight + this.tabBarHeight + AppSpace.Sm * 3,
              bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg })
          }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
        }
      }.width('100%').height('100%').barHeight(0)
        .onChange((index: number): void => { this.selectedTab = index; })

      // 标题与标签都叠在内容上方；顶部留白随内容滚动，卡片可进入磨砂层背后。
      Column() {
        this.themeTitleBar()
        Row() {
          this.themeTabBar()
        }.width('100%').justifyContent(FlexAlign.Center)
          .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Sm, bottom: AppSpace.Sm })
          .hitTestBehavior(HitTestMode.Transparent)
      }.width('100%').hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground).clip(true)
    .bindSheet($$this.showMembership, this.membershipSheet(), {
      height: '90%', detents: ['90%', '45%', SheetSize.LARGE], preferType: SheetType.BOTTOM, showClose: false, dragBar: true, backgroundColor: MEMBERSHIP_BACKGROUND_TOP
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
