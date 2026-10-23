import { common, sendableContextManager } from '@kit.AbilityKit';
import { MembershipState } from '../model/MembershipState';
import { MembershipPlan, MembershipService } from '../service/MembershipService';
import { AppIconService } from '../service/AppIconService';
import { AppColor, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { AuthService } from '../service/AuthService';
import { AccountAvatar } from '../components/AccountAvatar';
import { MembershipBadge } from '../components/MembershipBadge';
import { iap } from '@kit.IAPKit';

export const MEMBERSHIP_BACKGROUND_TOP: string = '#E3D1A9';

@ComponentV2
export struct MembershipSubscriptionPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local membership: MembershipService = MembershipService.instance;
  @Local state: MembershipState = MembershipState.current;
  @Param inSheet: boolean = false;
  @Event onClose: () => void = () => {};
  @Local auth: AuthService = AuthService.instance;
  @Local selectedPlan: string = 'lastVip';
  @Local showDetails: boolean = false;
  @Local agreed: boolean = false;
  @Local contentViewportHeight: number = 0;

  aboutToAppear(): void {
    const context = this.abilityContext();
    if (context) this.membership.load(context);
  }

  private abilityContext(): common.UIAbilityContext | undefined {
    const host = this.getUIContext().getHostContext();
    if (!host) return undefined;
    try {
      return sendableContextManager.convertToUIAbilityContext(sendableContextManager.convertFromContext(host));
    } catch (_error) { return undefined; }
  }

  private purchase(plan: MembershipPlan): void {
    if (!this.agreed || !this.membership.supported) return;
    const context = this.abilityContext();
    if (context) this.membership.purchase(context, plan.id);
  }

  private restore(): void {
    const context = this.abilityContext();
    if (context) this.membership.load(context, true);
  }

  private retryMembership(): void {
    const context = this.abilityContext();
    if (context) this.membership.load(context);
  }

  private manage(): void {
    const context = this.abilityContext();
    if (context) this.membership.manage(context);
  }

  private findPlan(productId: string): MembershipPlan | undefined {
    return this.membership.plans.find((plan: MembershipPlan): boolean => plan.id === productId);
  }

  private subscriptionSummary(): Resource {
    const date = new Date(this.state.displayExpiresAt);
    return this.state.displayAutoRenew ?
      $r('app.string.membership_expiry_renew_on', date.getFullYear(), date.getMonth() + 1, date.getDate()) :
      $r('app.string.membership_expiry_renew_off', date.getFullYear(), date.getMonth() + 1, date.getDate());
  }

  private planPrice(productId: string): ResourceStr {
    return this.findPlan(productId)?.price || (this.membership.productsLoading ?
      $r('app.string.membership_products_loading') : $r('app.string.membership_plan_unavailable'));
  }

  private offerPeriod(plan: MembershipPlan): Resource {
    switch (plan.offerPeriodUnit) {
      case iap.PeriodUnit.DAY: return $r('app.string.membership_offer_days', plan.offerPeriodCount);
      case iap.PeriodUnit.WEEK: return $r('app.string.membership_offer_weeks', plan.offerPeriodCount);
      case iap.PeriodUnit.MONTH: return $r('app.string.membership_offer_months', plan.offerPeriodCount);
      case iap.PeriodUnit.YEAR: return $r('app.string.membership_offer_years', plan.offerPeriodCount);
      default: return $r('app.string.membership_offer_period_cashier');
    }
  }

  private isAnnualUpgrade(productId: string): boolean {
    return this.state.active && this.state.productId === 'iconMonth' && productId === 'iconYear' &&
      this.state.pendingProductId !== 'iconYear';
  }

  private shouldManagePlan(productId: string): boolean {
    return this.state.active && productId !== 'lastVip' && !this.isAnnualUpgrade(productId);
  }

  private planAction(productId: string): Resource {
    if (this.state.active && this.state.lifetime) return $r('app.string.membership_lifetime_owned');
    if (this.isAnnualUpgrade(productId)) return $r('app.string.membership_upgrade_year');
    if (this.shouldManagePlan(productId)) return $r('app.string.membership_manage');
    return productId === 'lastVip' ? $r('app.string.membership_buy_lifetime') : $r('app.string.membership_subscribe');
  }

  private canSelectPlan(productId: string): boolean {
    if (this.membership.busy || !this.membership.supported || (this.state.active && this.state.lifetime)) return false;
    if (!this.state.hasAccess && !this.state.confirmedInactive) return false;
    if (this.isAnnualUpgrade(productId)) return this.agreed && this.membership.canUpgradeToYear();
    if (this.shouldManagePlan(productId)) return true;
    return this.agreed && this.findPlan(productId) !== undefined;
  }

  @Builder
  planCard(productId: string) {
    Column({ space: 8 }) {
      MembershipBadge({ productId: productId, badgeHeight: 36 })
      Text(productId === 'lastVip' ? $r('app.string.membership_lifetime') :
        productId === 'iconMonth' ? $r('app.string.membership_month') : $r('app.string.membership_year'))
        .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#30291F')
      Text(this.planPrice(productId)).fontSize(this.findPlan(productId) ? 20 : 14).fontWeight(FontWeight.Bold).fontColor('#30291F')
      if (this.findPlan(productId)?.offerId || this.findPlan(productId)?.introductory) {
        Text(this.findPlan(productId)?.introductory ? $r('app.string.membership_intro_label') :
          $r('app.string.membership_offer_label')).fontSize(11).fontColor('#806039')
        Text(this.findPlan(productId)?.regularPrice ?? '').fontSize(12).fontColor('#7A6A55')
          .decoration({ type: TextDecorationType.LineThrough })
      }
      Text(productId === 'lastVip' ? $r('app.string.membership_lifetime_period') :
        productId === 'iconMonth' ? $r('app.string.membership_month_period') : $r('app.string.membership_year_period'))
        .fontSize(11).fontColor('#7A6A55').textAlign(TextAlign.Center).maxLines(1)
    }.width(130).constraintSize({ minHeight: 132 }).padding(12).borderRadius(12)
    .backgroundColor(this.selectedPlan === productId ? '#FFFAF1' : '#FFFFFF')
    .border({ width: this.selectedPlan === productId ? 2 : 1,
      color: this.selectedPlan === productId ? '#AD8450' : '#FFFFFF' })
    .onClick((): void => { this.selectedPlan = productId; })
    .accessibilitySelected(this.selectedPlan === productId)
  }

  @Builder
  offerTerms(plan: MembershipPlan) {
    if (plan.offerPeriodCount > 0) {
      Text(this.offerPeriod(plan)).fontSize(12).fontColor('#746B5E').width('100%')
    }
    if (plan.offerPaymentMode === iap.OfferPaymentMode.FREE_TRIAL) {
      Text($r('app.string.membership_offer_trial')).fontSize(12).fontColor('#746B5E').width('100%')
    } else if (plan.offerPaymentMode === iap.OfferPaymentMode.PAY_AS_YOU_GO) {
      Text($r('app.string.membership_offer_recurring', plan.price)).fontSize(12).fontColor('#746B5E').width('100%')
    } else if (plan.offerPaymentMode === iap.OfferPaymentMode.PAY_UP_FRONT) {
      Text($r('app.string.membership_offer_upfront', plan.price)).fontSize(12).fontColor('#746B5E').width('100%')
    }
  }

  @Builder
  accountHeader() {
    Row({ space: 10 }) {
      AccountAvatar({ uri: this.auth.avatarUri, avatarSize: 36 })
      Row({ space: 6 }) {
        Text(this.auth.isLoggedIn ? (this.auth.nickName || $r('app.string.hw_auth_account_title')) :
          $r('app.string.hw_auth_login_title'))
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#30291F').flexShrink(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.state.displayActive) {
          MembershipBadge({ productId: this.state.displayProductId, badgeHeight: 28 }).flexShrink(0)
        }
      }.layoutWeight(1).alignItems(VerticalAlign.Center)
    }.width('100%').padding({ top: 4, bottom: 4 })
  }

  @Builder
  benefitCard() {
    Column({ space: 8 }) {
      Text($r('app.string.membership_card_title')).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#624023')
      if (!this.state.active || this.membership.message.id !== $r('app.string.membership_active').id) {
        Text(this.membership.message).fontSize(12).fontColor('#725338').width('100%')
      }
      if (!this.membership.busy && this.membership.supported && !this.state.hasAccess && !this.state.confirmedInactive) {
        Button($r('app.string.common_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontColor('#725338').onClick(() => this.retryMembership())
      }
      if (this.state.displayActive) {
        Text(this.state.displayLifetime ? $r('app.string.membership_lifetime_valid') :
          this.subscriptionSummary())
          .fontSize(12).fontColor('#725338').width('100%')
          .maxLines(1).minFontSize(10).maxFontSize(12).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
      }
      if (this.state.active && this.state.pendingProductId === 'iconYear') {
        Text($r('app.string.membership_upgrade_year_pending')).fontSize(12).fontColor('#725338').width('100%')
      }
      Text($r('app.string.membership_benefit_short')).fontSize(12).fontColor('#624023')
        .width('100%').margin({ top: 10 })
    }.width('100%').padding(16).borderRadius(14).alignItems(HorizontalAlign.Start)
    .linearGradient({ angle: 120, colors: [['#EBD5B4', 0], ['#C59962', 1]] })
  }

  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.membership_subscription_title')).fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor('#30291F').layoutWeight(1)
        if (this.membership.busy) {
          LoadingProgress().width(20).height(20).color(AppColor.Brand)
        }
        Button($r('app.string.membership_restore_short')).fontSize(11).height(28).flexShrink(0)
          .padding({ left: 8, right: 8 }).backgroundColor('#D9BE8C').fontColor('#55432C')
          .accessibilityText($r('app.string.membership_restore'))
          .enabled(!this.membership.busy).onClick(() => this.restore())
        Button($r('app.string.membership_manage')).fontSize(11).height(28).flexShrink(0)
          .padding({ left: 8, right: 8 }).backgroundColor('#D9BE8C').fontColor('#55432C')
          .enabled(!this.membership.busy && this.membership.supported).onClick(() => this.manage())
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor(['#30291F'])
        }.width(32).height(32).backgroundColor('#1A8B744C')
        .accessibilityText($r('app.string.membership_close'))
        .onClick((): void => { if (this.inSheet) this.onClose(); else this.navStack.pop(); })
      }.width('100%').padding({ top: this.inSheet ? 14 : WindowUtils.getStatusBarHeightVp() + 14,
        left: 16, right: 16, bottom: 8 })
      Scroll() {
        Column({ space: 12 }) {
          this.accountHeader()
          this.benefitCard()
          Text($r('app.string.membership_period_title')).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor('#665C4D').width('100%').margin({ top: 4 })
          Scroll() {
            Row({ space: 10 }) {
              this.planCard('lastVip')
              this.planCard('iconYear')
              this.planCard('iconMonth')
            }.padding({ top: 2, bottom: 2 })
          }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          if (!AppIconService.instance.supported) {
            Text($r('app.string.app_icon_unsupported')).fontSize(12).fontColor('#746B5E').width('100%')
          }
          if (this.membership.confirmationPending) {
            Text($r('app.string.membership_confirmation_pending')).fontSize(12)
              .fontColor('#746B5E').width('100%')
          }
          if (this.selectedPlan === 'lastVip') {
            Text($r('app.string.membership_lifetime_renewal_notice')).fontSize(12)
              .fontColor('#746B5E').width('100%')
          }
          if (this.isAnnualUpgrade(this.selectedPlan)) {
            Text($r('app.string.membership_upgrade_year_notice')).fontSize(12)
              .fontColor('#746B5E').width('100%')
            if (!this.membership.productsLoading && !this.membership.canUpgradeToYear()) {
              Text($r('app.string.membership_upgrade_unavailable')).fontSize(12)
                .fontColor('#746B5E').width('100%')
            }
          }
          if (this.membership.supported) {
            Text(this.membership.productsMessage).fontSize(12)
              .fontColor('#746B5E').width('100%')
          }
          if (this.findPlan(this.selectedPlan)?.offerId || this.findPlan(this.selectedPlan)?.introductory) {
            ForEach(this.membership.plans.filter((plan: MembershipPlan): boolean => plan.id === this.selectedPlan),
              (plan: MembershipPlan) => { this.offerTerms(plan) }, (plan: MembershipPlan): string => plan.id)
            Text($r('app.string.membership_offer_notice')).fontSize(12).fontColor('#746B5E').width('100%')
            if (this.selectedPlan !== 'lastVip') {
              Text($r('app.string.membership_offer_renewal', this.findPlan(this.selectedPlan)?.regularPrice ?? ''))
                .fontSize(12).fontColor('#746B5E').width('100%')
            }
          }
          Button($r('app.string.membership_details')).height(30).fontSize(12).fontColor('#806039')
            .backgroundColor(Color.Transparent).onClick((): void => { this.showDetails = !this.showDetails; })
          if (this.showDetails) {
            Text($r('app.string.membership_benefit')).fontSize(12).fontColor('#746B5E').width('100%')
            Text($r('app.string.membership_terms')).fontSize(12).fontColor('#746B5E').width('100%')
          }
          if (!this.state.active || !this.state.lifetime) {
            Row({ space: AppSpace.Sm }) {
              Checkbox({ name: 'subscriptionConsent' }).width(18).height(18).select(this.agreed).selectedColor(AppColor.Brand)
                .onChange((value: boolean): void => { this.agreed = value; })
                .accessibilityText($r('app.string.membership_consent'))
              Text($r('app.string.membership_consent')).fontSize(12)
                .fontColor('#30291F').layoutWeight(1)
            }.width('100%')
          }
          Button(this.planAction(this.selectedPlan)).width('100%').height(40)
            .fontSize(15).fontWeight(FontWeight.Medium).backgroundColor('#B9905C').fontColor(Color.White)
            .enabled(this.canSelectPlan(this.selectedPlan))
            .onClick((): void => {
              if (this.shouldManagePlan(this.selectedPlan)) this.manage();
              else {
                const plan = this.findPlan(this.selectedPlan);
                if (plan) this.purchase(plan);
              }
            })
        }.width('100%').constraintSize({ maxWidth: 680, minHeight: this.contentViewportHeight })
        .justifyContent(FlexAlign.SpaceBetween).padding({ left: AppSpace.Md, right: AppSpace.Md,
          top: AppSpace.Sm, bottom: WindowUtils.getBottomSafeVp() + AppSpace.Sm })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        const height = Number(newArea.height);
        if (Number.isFinite(height) && height > 0 && this.contentViewportHeight !== height) {
          this.contentViewportHeight = height;
        }
      })
    }.width('100%').height('100%')
    .linearGradient({ angle: 180, colors: [[MEMBERSHIP_BACKGROUND_TOP, 0], ['#EEE7D8', 0.55], ['#F3F4F5', 1]] })
  }
}
