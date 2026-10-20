import { MedalService } from '../service/MedalService';
import { HdsCompat } from '../utils/HdsCompat';
import { AppColor, AppRadius, AppSpace, AppFont, HomeTheme } from '../theme/Theme';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { WindowUtils } from '../utils/WindowUtils';
import { AuthService } from '../service/AuthService';
import { pasteboard } from '@kit.BasicServicesKit';
import { CommunityGroupService } from '../service/CommunityGroupService';
import { AccountAvatar } from '../components/AccountAvatar';
import { MembershipSubscriptionPage } from './MembershipSubscriptionPage';
import { MembershipState } from '../model/MembershipState';
import { MembershipBadge } from '../components/MembershipBadge';

class ProfileItem {
  icon: Resource;
  label: ResourceStr;
  id: string;
  iconBg: ResourceColor;
  /** 副标题,如公众号说明、群号;空时不占位 */
  subtitle: ResourceStr;

  constructor(icon: Resource, label: ResourceStr, id: string, iconBg: ResourceColor, subtitle: ResourceStr = '') {
    this.icon = icon;
    this.label = label;
    this.id = id;
    this.iconBg = iconBg;
    this.subtitle = subtitle;
  }
}

const SOURCE_ITEMS: ProfileItem[] = [
  new ProfileItem($r('sys.symbol.bookshelf'), $r('app.string.rule_source_title'), 'ruleSources',
    AppColor.Brand),
  new ProfileItem($r('sys.symbol.arrow_down_circle'), $r('app.string.profile_local_import'), 'import', '#34C759')
];

const CONTENT_ITEMS: ProfileItem[] = [
  new ProfileItem($r('sys.symbol.star_fill'), $r('app.string.achievement_title'), 'achievements', '#E6A23C'),
  new ProfileItem($r('sys.symbol.star_fill'), $r('app.string.membership_title'), 'membership', AppColor.Brand)
];

const SETTINGS_ITEMS: ProfileItem[] = [
  new ProfileItem($r('sys.symbol.gearshape'), '设置', 'settings', '#8E8E93')
];

const SYSTEM_ITEMS: ProfileItem[] = [
  new ProfileItem($r('sys.symbol.doc_text'), $r('app.string.log_title'), 'logs', '#0A84FF'),
  new ProfileItem($r('sys.symbol.info_circle'), '关于', 'about', '#0A59F7')
];

const SUPPORT_ITEMS: ProfileItem[] = [
  new ProfileItem($r('sys.symbol.qrcode'), $r('app.string.profile_wechat_title'), 'wechat',
    '#07C160', $r('app.string.profile_wechat_desc')),
  new ProfileItem($r('sys.symbol.person_2'), $r('app.string.profile_community_group'), 'community',
    AppColor.Brand, $r('app.string.about_community_group_number'))
];
const ROW_INDENT: number = AppSpace.Md;
const MINI_TITLE_BAR_HEIGHT: number = 56;

@ComponentV2
export struct ProfilePage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Event onScrollerReady: (scroller: Scroller) => void = () => {};
  @Local medalService: MedalService = MedalService.instance;
  @Local auth: AuthService = AuthService.instance;
  @Local membership: MembershipState = MembershipState.current;
  @Local showMembership: boolean = false;

  private scrollScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.onScrollerReady(this.scrollScroller);
    const context = this.getUIContext().getHostContext();
    if (context) {
      this.auth.restore(context);
      this.medalService.init(context).catch((error: Error): void => {
        console.warn(`[ProfilePage] medals unavailable: ${error.message}`);
      });
    }
  }

  private onItemTap(id: string): void {
    if (id === 'import') {
      this.navStack.pushPathByName('import', '');
    } else if (id === 'logs') {
      this.navStack.pushPathByName('logs', '');
    } else if (id === 'achievements') {
      this.navStack.pushPathByName('achievements', '');
    } else if (id === 'account') {
      this.navStack.pushPathByName('account', '');
    } else if (id === 'settings') {
      this.navStack.pushPathByName('settings', '');

    } else if (id === 'membership') {
      this.navStack.pushPathByName('membership', '');
    } else if (id === 'ruleSources') {
      this.navStack.pushPathByName('ruleSources', '');
    } else if (id === 'about') {
      this.navStack.pushPathByName('about', '');
    } else if (id === 'wechat') {
      this.copyWechatName();
    } else if (id === 'community') {
      this.openCommunityGroup();
    }
  }

  private copyWechatName(): void {
    try {
      const name = this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.profile_wechat_name').id);
      if (!name) return;
      pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, name)).then(() => {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.profile_wechat_copied') });
      }).catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.profile_wechat_copy_failed') });
      });
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.profile_wechat_copy_failed') });
    }
  }

  private async openCommunityGroup(): Promise<void> {
    const opened = await CommunityGroupService.open(this.getUIContext().getHostContext());
    if (!opened) {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.community_group_open_failed'),
        duration: 2000
      });
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            [HomeTheme.BgWarmTop, 0.0],
            [HomeTheme.BgWarmMid, 0.35],
            [HomeTheme.BgNeutral, 1.0]
          ]
        })

      HdsNavigation() {
        Scroll(this.scrollScroller) {
          Column({ space: AppSpace.Lg }) {
            this.buildAccountCard()
            this.buildGroup(SOURCE_ITEMS)
            this.buildGroup(SETTINGS_ITEMS)
            this.buildGroup(CONTENT_ITEMS)
            this.buildGroup(SYSTEM_ITEMS)
            this.buildGroup(SUPPORT_ITEMS, '支持与联系')
          }
          .width('100%')
          .padding({
            left: AppSpace.Md,
            right: AppSpace.Md,
            top: WindowUtils.getStatusBarHeightVp() + MINI_TITLE_BAR_HEIGHT + AppSpace.Sm,
            bottom: WindowUtils.getFloatingTabBottomVp()
          })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor(Color.Transparent)
        .align(Alignment.Top)
      }
      .mode(NavigationMode.Stack)
      .titleBar({
        avoidLayoutSafeArea: true,
        content: {
          title: {
            mainTitle: '我的'
          }
        },
        style: {
          scrollEffectOpts: {
            scrollEffectType: HdsCompat.scrollEffect
          },
          originalStyle: {
            backgroundStyle: {
              backgroundColor: Color.Transparent
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary')
              }
            }
          },
          scrollEffectStyle: {
            backgroundStyle: {
              backgroundColor: Color.Transparent
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary')
              }
            }
          },
          systemMaterialEffect: HdsCompat.material
        }
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .bindToScrollable([this.scrollScroller])
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildAccountCard() {
    Column() {
      Row({ space: 14 }) {
        AccountAvatar({ uri: this.auth.avatarUri, avatarSize: 56 })
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text(this.auth.isLoggedIn ? (this.auth.nickName || $r('app.string.hw_auth_account_title')) :
              $r('app.string.hw_auth_login_title'))
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.auth.isLoggedIn ? this.membership.nameColor : $r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1)
          }.width('100%').alignItems(VerticalAlign.Center)
          if (this.membership.displayActive) {
            MembershipBadge({ productId: this.membership.displayProductId, badgeHeight: 20, compact: true })
          }
          if (!this.auth.isLoggedIn) {
            Text($r('app.string.hw_auth_login_desc'))
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .constraintSize({ minHeight: 56 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)

        if (this.auth.logging || this.auth.restoring) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color(AppColor.Brand)
            .accessibilityText($r('app.string.hw_auth_processing'))
        } else {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(24)
            .width(24)
            .height(24)
            .fontColor([$r('sys.color.font_tertiary')])
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: AppSpace.Sm, right: ROW_INDENT, top: 20, bottom: 20 })
      .enabled(!this.auth.logging && !this.auth.restoring)
      .onClick(() => {
        this.navStack.pushPathByName('account', '');
      })
      if (MembershipState.featureEnabled) {
        Divider().strokeWidth(0.5).color($r('sys.color.comp_divider')).margin({ left: 20, right: 20 })
        Row({ space: 12 }) {
        Text($r('app.string.membership_entry_desc')).fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary')).layoutWeight(1).maxLines(2)
        Button($r('app.string.membership_subscription_title'))
          .height(32).fontSize(13).padding({ left: 14, right: 14 }).flexShrink(0).backgroundColor('#D5B887').fontColor('#55432C')
          .fontWeight(FontWeight.Medium).onClick((): void => { this.showMembership = true; })
        }.width('100%').padding({ left: 20, right: 20, top: 14, bottom: 14 })
      }
    }.width('100%').backgroundColor($r('sys.color.comp_background_primary')).borderRadius(AppRadius.Lg)
    .bindSheet($$this.showMembership, this.membershipSheet(), {
      height: '90%', preferType: SheetType.BOTTOM, showClose: false, dragBar: false,
      backgroundColor: '#EFEDE7'
    })
  }

  @Builder
  membershipSheet() {
    MembershipSubscriptionPage({ navStack: this.navStack, inSheet: true,
      onClose: (): void => { this.showMembership = false; } })
  }

  @Builder
  buildGroup(items: ProfileItem[], title: string = '') {
    Column() {
      if (title.length > 0) {
        Text(title)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_tertiary'))
          .padding({ left: AppSpace.Sm, bottom: AppSpace.Xs })
      }

      Column() {
        ForEach(items, (item: ProfileItem, index: number) => {
          this.buildRow(item)
          if (index < items.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: ROW_INDENT + 28 + AppSpace.Sm })
          }
        }, (item: ProfileItem) => item.id)
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildRow(item: ProfileItem) {
    Row({ space: AppSpace.Sm }) {
      Stack() {
        SymbolGlyph(item.icon)
          .fontSize(18)
          .fontColor([Color.White])
      }
      .width(28)
      .height(28)
      .backgroundColor(item.iconBg)
      .borderRadius(7)

      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(item.label)
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          if (item.id === 'achievements' && this.auth.isLoggedIn && this.medalService.ready &&
            this.medalService.selectedMedalId !== '') {
            Image(this.medalService.selected()?.badge)
              .width(20).height(20).objectFit(ImageFit.Contain).flexShrink(0)
              .accessibilityText(this.medalService.selected()?.name ?? $r('app.string.account_medal_list'))
          }
        }.width('100%').alignItems(VerticalAlign.Center)
        if (typeof item.subtitle !== 'string' || item.subtitle.length > 0) {
          Text(item.subtitle)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(24)
        .width(24)
        .height(24)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%')
    .padding({
      left: ROW_INDENT,
      right: ROW_INDENT,
      top: AppSpace.Sm,
      bottom: AppSpace.Sm
    })
    .constraintSize({ minHeight: 56 })
    .onClick(() => this.onItemTap(item.id))
  }
}
