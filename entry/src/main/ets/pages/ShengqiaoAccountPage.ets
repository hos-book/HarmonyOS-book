import { webview } from '@kit.ArkWeb';
import { ShengqiaoPageFrame } from '../components/ShengqiaoPageFrame';
import { InfinityLoadingIndicator } from '../components/InfinityLoadingIndicator';
import { ShengqiaoState } from '../model/ShengqiaoPlugin';
import { ShengqiaoPluginService } from '../service/text/ShengqiaoPluginService';
import { ShengqiaoTtsService } from '../service/text/ShengqiaoTtsService';
import { LocalRuleWebSession } from '../service/rulesource/LocalRuleWebSession';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';

@ComponentV2
export struct ShengqiaoAccountPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local state: ShengqiaoState = ShengqiaoPluginService.instance.state;
  @Local showingWeb: boolean = false;
  @Local loading: boolean = false;
  @Local exchanging: boolean = false;
  @Local message: ResourceStr = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private lease: number = 0;
  private alive: boolean = false;
  private address: string = '';

  aboutToAppear(): void { this.alive = true; }
  aboutToDisappear(): void { this.alive = false; this.closeWeb(); }

  private closeWeb(): void {
    if (this.lease > 0) {
      try { this.controller.stop(); webview.WebCookieManager.clearAllCookiesSync(true); }
      catch (_error) { /* Web 容器随页面释放。 */ }
      LocalRuleWebSession.release(this.lease);
      this.lease = 0;
    }
    this.showingWeb = false;
    this.loading = false;
  }

  private async login(): Promise<void> {
    if (this.loading || this.exchanging) return;
    this.loading = true;
    this.message = '';
    try {
      const lease = await LocalRuleWebSession.acquire(60000);
      if (!this.alive) { LocalRuleWebSession.release(lease); return; }
      this.lease = lease;
      this.address = ShengqiaoTtsService.instance.authorizationUrl();
      this.showingWeb = true;
    } catch (_error) {
      this.loading = false;
      this.message = $r('app.string.shengqiao_operation_failed');
    }
  }

  private async complete(address: string): Promise<void> {
    if (this.exchanging) return;
    this.exchanging = true;
    this.loading = true;
    try {
      await ShengqiaoTtsService.instance.completeAuthorization(address);
      if (this.alive) this.message = $r('app.string.shengqiao_login_success');
    } catch (error) {
      if (this.alive) this.message = ShengqiaoTtsService.errorMessage(error);
    } finally { this.closeWeb(); this.exchanging = false; }
  }

  private async logout(): Promise<void> {
    try {
      await ShengqiaoPluginService.instance.logout();
      this.message = $r('app.string.shengqiao_logout_success');
    } catch (_error) { this.message = $r('app.string.shengqiao_operation_failed'); }
  }

  build() {
    ShengqiaoPageFrame({ navStack: this.navStack, pageTitle: $r('app.string.shengqiao_account_title'), scrolling: false }) {
      Column({ space: AppSpace.Md }) {
        Row({ space: AppSpace.Sm }) {
          Column({ space: AppSpace.Xs }) {
            Text(this.state.loggedIn ? $r('app.string.shengqiao_logged_in') : $r('app.string.shengqiao_logged_out'))
              .fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
            Text(this.message || $r('app.string.shengqiao_account_hint')).fontSize(AppFont.Caption)
              .fontColor(AppTheme.TextSecondary)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.loading) { InfinityLoadingIndicator({ indicatorSize: 24 }) }
        }.width('100%')
        if (!this.showingWeb) {
          Button(this.state.loggedIn ? $r('app.string.shengqiao_relogin') : $r('app.string.shengqiao_login'))
            .width('100%').height(44).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
            .enabled(this.state.installed && !this.loading && !this.exchanging).onClick((): void => { this.login(); })
          if (this.state.loggedIn) {
            Button($r('app.string.shengqiao_logout')).width('100%').height(44).fontColor(AppColor.Brand)
              .backgroundColor(AppTheme.Surface).enabled(!this.loading && !this.exchanging)
              .onClick((): void => { this.logout(); })
          }
        }
      }.width(`calc(100% - ${AppSpace.Md * 2}vp)`).constraintSize({ maxWidth: 760 })
        .padding(AppSpace.Md).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg)
      if (this.showingWeb) {
        Web({ src: '', controller: this.controller, incognitoMode: true })
          .width('100%').layoutWeight(1).javaScriptAccess(true).domStorageAccess(true)
          .fileAccess(false).databaseAccess(false).geolocationAccess(false).mixedMode(MixedMode.None)
          .onControllerAttached((): void => {
            webview.WebCookieManager.clearAllCookiesSync(true);
            this.controller.loadUrl(this.address);
          })
          .onPageBegin((): void => { this.loading = true; })
          .onPageEnd((): void => { if (!this.exchanging) this.loading = false; })
          .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
            const address = event.data.getRequestUrl();
            if (address.startsWith(ShengqiaoTtsService.REDIRECT + '?')) { this.complete(address); return true; }
            return !address.startsWith('https://');
          })
      }
    }
  }
}
