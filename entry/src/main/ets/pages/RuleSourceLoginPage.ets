import { webview } from '@kit.ArkWeb';
import { RuleSourceLoginRouteParams } from '../model/RuleSourceLogin';
import { LocalRuleSourceRepository } from '../service/rulesource/LocalRuleSourceRepository';
import { LightSourceCookies as LocalRuleHttpClient } from '../service/rulesource/light/LightSourceCookies';
import { LightPersistedCookieRecord } from '../service/rulesource/light/LightSourceCookies';
import { LocalRuleTlsTrustStore } from '../service/rulesource/LocalRuleTlsTrustStore';
import { LocalRuleBrowserLoginCoordinator } from '../service/rulesource/LocalRuleBrowserLoginCoordinator';
import { LocalRuleExecutionLimits } from '../service/rulesource/LocalRuleRuntimeTypes';
import { LocalRuleWebSession } from '../service/rulesource/LocalRuleWebSession';
import { LocalRulePanelService } from '../service/rulesource/LocalRulePanelService';
import { LightSourceBridge } from '../service/rulesource/light/LightSourceBridge';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

const RULE_LOGIN_DANGER: string = '#D03050';
const RULE_LOGIN_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 ' +
  'Chrome/126.0.0.0 Mobile Safari/537.36';

class RuleSourceWebCookieSnapshot {
  url: string = '';
  cookieHeader: string = '';
}

class RuleSourceLoginHtmlSnapshot {
  html: string = '';
}

@ComponentV2
export struct RuleSourceLoginPage {
  private storedCookieRecords: LightPersistedCookieRecord[] = [];
  @Param navStack: NavPathStack = new NavPathStack();
  @Param route: RuleSourceLoginRouteParams = new RuleSourceLoginRouteParams();
  @Local ready: boolean = false;
  @Local loading: boolean = true;
  @Local saving: boolean = false;
  @Local currentUrl: string = '';
  @Local currentOrigin: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private visitedUrls: string[] = [];
  private leaving: boolean = false;
  private pageAlive: boolean = true;
  private webSessionLease: number = 0;
  private completionTask: Promise<void> | undefined = undefined;
  private cancellationTask: Promise<void> | undefined = undefined;
  private requestCancelled: boolean = false;
  private initialDocumentServed: boolean = false;
  private loginScriptInjected: boolean = false;
  private storedCookies: RuleSourceWebCookieSnapshot[] = [];
  private cookiesRestored: boolean = false;

  aboutToAppear(): void {
    this.pageAlive = true;
    WindowUtils.setStatusBarLight(false);
    if (this.route.requestId.length > 0 && !LocalRuleBrowserLoginCoordinator.attach(this.route.requestId,
      (reason: string): Promise<void> => this.cancelAwaitingLogin(reason))) {
      this.leaving = true;
      this.navStack.pop();
      return;
    }
    this.prepareLogin();
  }

  aboutToDisappear(): void {
    this.pageAlive = false;
    WindowUtils.setStatusBarLight(false);
    if (!this.leaving) {
      if (this.route.requestId.length > 0) {
        this.cancelAwaitingLogin('网页登录已取消');
        return;
      }
      const snapshots = this.snapshotCookies();
      this.persistOnDisappear(snapshots).finally((): void => this.stopAndRelease());
    }
  }

  private async prepareLogin(): Promise<void> {
    if (!this.route.isValid() || this.route.initialHtml.length > LocalRuleBrowserLoginCoordinator.MAX_HTML_LENGTH) {
      this.showToast($r('app.string.rule_source_login_invalid'));
      LocalRuleBrowserLoginCoordinator.reject(this.route.requestId, '网页登录地址无效');
      this.navStack.pop();
      return;
    }
    try {
      const source = await LocalRuleSourceRepository.get(this.route.sourceUrl);
      if (source === undefined) throw new Error('Rule source not found');
      if (!this.pageAlive || this.requestCancelled || this.leaving) return;
      this.webSessionLease = await LocalRuleWebSession.acquire(60000);
      if (!this.pageAlive || this.requestCancelled || this.leaving) {
        LocalRuleWebSession.release(this.webSessionLease);
        this.webSessionLease = 0;
        return;
      }
      const loginUrls = this.loginUrls();
      this.storedCookieRecords = await LocalRuleHttpClient.getStoredCookieRecords(this.route.sourceUrl);
      for (const loginUrl of loginUrls) {
        const cookieHeader = await LocalRuleHttpClient.getStoredCookieHeader(
          this.route.sourceUrl, loginUrl);
        if (!this.pageAlive || this.requestCancelled || this.leaving || this.webSessionLease === 0) return;
        const snapshot = new RuleSourceWebCookieSnapshot();
        snapshot.url = loginUrl;
        snapshot.cookieHeader = cookieHeader;
        this.storedCookies.push(snapshot);
      }
      this.currentUrl = this.route.loginUrl;
      this.currentOrigin = LocalRuleHttpClient.requestOrigin(this.route.loginUrl);
      this.ready = true;
      this.loading = true;
    } catch (_error) {
      if (!this.pageAlive || this.leaving) return;
      this.showToast($r('app.string.rule_source_login_prepare_failed'));
      LocalRuleBrowserLoginCoordinator.reject(this.route.requestId, '网页登录准备失败');
      this.navStack.pop();
    }
  }

  private restoreWebSession(): void {
    if (!this.pageAlive || this.leaving || this.requestCancelled || this.webSessionLease === 0) return;
    try {
      // 隐私 Cookie 容器须在 Web 挂载后写入，首个站点请求必须等待恢复完成。
      this.releaseWebCookies();
      this.controller.clearSslCache();
      this.controller.setCustomUserAgent(RULE_LOGIN_USER_AGENT);
      for (const record of this.storedCookieRecords) {
        webview.WebCookieManager.configCookieSync(record.url, record.cookie, true, true);
      }
      for (const snapshot of this.storedCookies) {
        if (!this.storedCookieRecords.some(record => LocalRuleHttpClient.requestOrigin(record.url) ===
          LocalRuleHttpClient.requestOrigin(snapshot.url))) this.injectCookies(snapshot.url, snapshot.cookieHeader);
        this.rememberUrl(snapshot.url);
      }
      this.cookiesRestored = true;
      this.storedCookies = [];
      this.storedCookieRecords = [];
      this.controller.loadUrl(this.route.loginUrl);
    } catch (_error) {
      this.cookiesRestored = false;
      this.showToast($r('app.string.rule_source_login_prepare_failed'));
      LocalRuleBrowserLoginCoordinator.reject(this.route.requestId, '网页登录准备失败');
      this.navStack.pop();
    }
  }

  private loginUrls(): string[] {
    return [this.route.loginUrl];
  }

  private injectCookies(url: string, cookieHeader: string): void {
    const pairs = cookieHeader.split(';');
    for (const rawPair of pairs) {
      const pair = rawPair.trim();
      if (pair.length === 0 || pair.indexOf('=') <= 0) continue;
      webview.WebCookieManager.configCookieSync(url, `${pair}; Path=/; Secure`, true, true);
    }
  }

  private rememberUrl(url: string): void {
    const origin = LocalRuleHttpClient.requestOrigin(url);
    if (origin.length === 0) return;
    for (let index = 0; index < this.visitedUrls.length; index++) {
      if (LocalRuleHttpClient.requestOrigin(this.visitedUrls[index]) === origin) {
        this.visitedUrls[index] = url;
        return;
      }
    }
    if (this.visitedUrls.length < 16) this.visitedUrls.push(url);
  }

  private snapshotCookies(): RuleSourceWebCookieSnapshot[] {
    const snapshots: RuleSourceWebCookieSnapshot[] = [];
    if (this.webSessionLease === 0 || !this.cookiesRestored) return snapshots;
    for (const url of this.visitedUrls) {
      const snapshot = new RuleSourceWebCookieSnapshot();
      snapshot.url = url;
      try {
        snapshot.cookieHeader = webview.WebCookieManager.fetchCookieSync(url, true) || '';
      } catch (_error) {
        // 读取失败不是退出登录，不能用空值覆盖已持久化的会话。
        continue;
      }
      snapshots.push(snapshot);
    }
    return snapshots;
  }

  private async persistSnapshots(snapshots: RuleSourceWebCookieSnapshot[]): Promise<void> {
    for (const snapshot of snapshots) {
      try {
        await LocalRuleHttpClient.saveWebCookies(
          this.route.sourceUrl, snapshot.url, snapshot.cookieHeader);
      } catch (_error) {
        // 页面退出时无法再可靠提示，下一次登录仍可重新获取。
      }
    }
  }

  private async persistSnapshotsStrict(snapshots: RuleSourceWebCookieSnapshot[]): Promise<void> {
    for (const snapshot of snapshots) {
      await LocalRuleHttpClient.saveWebCookies(this.route.sourceUrl, snapshot.url, snapshot.cookieHeader);
    }
  }

  private async persistOnDisappear(snapshots: RuleSourceWebCookieSnapshot[]): Promise<void> {
    await this.persistSnapshots(snapshots);
  }

  private releaseWebCookies(): void {
    if (this.webSessionLease === 0) return;
    try {
      webview.WebCookieManager.clearAllCookiesSync(true);
    } catch (_error) {
      // ArkWeb 尚未完成初始化时无需清理。
    }
  }

  private async finishLogin(): Promise<void> {
    if (this.saving || !this.ready || this.leaving || this.requestCancelled) return;
    const completion = this.completeLogin();
    this.completionTask = completion;
    try { await completion; }
    finally { if (this.completionTask === completion) this.completionTask = undefined; }
  }

  private async completeLogin(): Promise<void> {
    this.saving = true;
    const snapshots = this.snapshotCookies();
    try {
      const awaitingScript = this.route.requestId.length > 0;
      await this.persistSnapshotsStrict(snapshots);
      let awaitedHtml = '';
      if (awaitingScript) {
        if (this.requestCancelled || !LocalRuleBrowserLoginCoordinator.isPending(this.route.requestId)) return;
        awaitedHtml = await this.readBoundedPageHtml();
        if (this.requestCancelled || !LocalRuleBrowserLoginCoordinator.isPending(this.route.requestId)) return;
      }
      if (!awaitingScript) {
        const source = await LocalRuleSourceRepository.get(this.route.sourceUrl);
        if (source !== undefined) {
          const content = await this.readBoundedPageHtml();
          await LocalRulePanelService.checkLogin(source, content, {}, this.currentUrl);
        } else {
          await LocalRuleSourceRepository.setLoginStatus(this.route.sourceUrl, 'saved');
        }
      }
      this.leaving = true;
      this.stopAndRelease();
      this.showToast($r('app.string.rule_source_login_saved'));
      this.navStack.pop();
      if (awaitingScript) LocalRuleBrowserLoginCoordinator.resolve(this.route.requestId, awaitedHtml);
    } catch (error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
      if (this.route.requestId.length > 0 && !this.requestCancelled) {
        this.leaving = true;
        this.stopAndRelease();
        if (this.pageAlive) this.navStack.pop();
        LocalRuleBrowserLoginCoordinator.reject(this.route.requestId,
          error instanceof Error ? error.message : '网页登录保存失败');
      }
    } finally {
      this.saving = false;
    }
  }

  private readBoundedPageHtml(): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('网页登录内容读取超时')), 3000);
      // Only this fixed snapshot expression runs in ArkWeb; source scripts stay in QuickJS.
      this.controller.runJavaScript('JSON.stringify({html:document.documentElement ? ' +
        'document.documentElement.outerHTML.slice(0,524288) : ""})').then((raw: string): void => {
        clearTimeout(timer);
        try {
          if (raw.length > LocalRuleBrowserLoginCoordinator.MAX_HTML_LENGTH * 8 + 1024) {
            reject(new Error('网页登录内容超过返回大小限制'));
            return;
          }
          let payload = raw;
          if (payload.startsWith('"')) {
            const decoded: string = JSON.parse(payload);
            if (typeof decoded !== 'string') throw new Error('Invalid browser snapshot');
            payload = decoded;
          }
          const snapshot: RuleSourceLoginHtmlSnapshot = JSON.parse(payload);
          if (snapshot === null || typeof snapshot !== 'object' || typeof snapshot.html !== 'string' ||
            snapshot.html.length > LocalRuleBrowserLoginCoordinator.MAX_HTML_LENGTH) {
            reject(new Error('网页登录内容格式无效'));
          } else { resolve(snapshot.html); }
        } catch (_error) { reject(new Error('网页登录内容格式无效')); }
      }).catch((error: Error): void => { clearTimeout(timer); reject(error); });
    });
  }

  private cancelAwaitingLogin(reason: string): Promise<void> {
    this.requestCancelled = true;
    if (this.cancellationTask === undefined) this.cancellationTask = this.cleanupAwaitingLogin(reason);
    return this.cancellationTask;
  }

  private async cleanupAwaitingLogin(reason: string): Promise<void> {
    const completion = this.completionTask;
    if (completion !== undefined) await completion;
    if (!this.leaving) {
      this.saving = true;
      const snapshots = this.snapshotCookies();
      try { await this.persistSnapshotsStrict(snapshots); }
      catch (_error) { /* A failed login is rejected even when cookie persistence is unavailable. */ }
      this.leaving = true;
      this.stopAndRelease();
      if (this.pageAlive) this.navStack.pop();
      this.saving = false;
    }
    LocalRuleBrowserLoginCoordinator.reject(this.route.requestId, reason);
  }

  private async leaveLogin(): Promise<void> {
    if (this.route.requestId.length > 0) {
      await this.cancelAwaitingLogin('网页登录已取消');
      return;
    }
    if (this.saving) return;
    this.saving = true;
    const snapshots = this.snapshotCookies();
    try {
      await this.persistSnapshots(snapshots);
    } catch (_error) {
      // 返回操作不能被会话保存失败阻塞。
    }
    this.leaving = true;
    this.stopAndRelease();
    this.navStack.pop();
    this.saving = false;
  }

  private stopAndRelease(): void {
    try {
      this.controller.stop();
    } catch (_error) {
      // 页面已经停止时直接清理隔离 Cookie。
    }
    this.releaseWebCookies();
    LocalRuleWebSession.release(this.webSessionLease);
    this.webSessionLease = 0;
  }

  private confirmClearLogin(): void {
    if (this.saving) return;
    this.getUIContext().showAlertDialog({
      title: $r('app.string.rule_source_login_clear_title'),
      message: $r('app.string.rule_source_login_clear_message'),
      primaryButton: {
        value: $r('app.string.rule_source_login_clear_action'),
        fontColor: RULE_LOGIN_DANGER,
        action: () => {
          this.clearLogin();
        }
      },
      secondaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      }
    });
  }

  private async clearLogin(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      const loginUrls = this.loginUrls();
      const source = await LocalRuleSourceRepository.get(this.route.sourceUrl);
      if (source !== undefined) await LightSourceBridge.clearLogin(source);
      await LocalRuleSourceRepository.setLoginStatus(this.route.sourceUrl, 'signedOut');
      for (const loginUrl of loginUrls) {
        await LocalRuleHttpClient.clearCookies(this.route.sourceUrl, loginUrl);
      }
      this.releaseWebCookies();
      this.visitedUrls = [];
      for (const loginUrl of loginUrls) this.rememberUrl(loginUrl);
      this.currentUrl = this.route.loginUrl;
      this.currentOrigin = LocalRuleHttpClient.requestOrigin(this.route.loginUrl);
      this.controller.loadUrl(this.route.loginUrl);
      this.showToast($r('app.string.rule_source_login_cleared'));
    } catch (_error) {
      this.showToast($r('app.string.rule_source_operation_failed'));
    } finally {
      this.saving = false;
    }
  }

  private refreshPage(): void {
    if (!this.ready || this.saving) return;
    try {
      this.controller.refresh(true);
    } catch (_error) {
      this.showToast($r('app.string.rule_source_login_refresh_failed'));
    }
  }

  private allowNavigation(url: string): boolean {
    if (url === 'about:blank') return true;
    if (!RuleSourceLoginRouteParams.of(this.route.sourceUrl, this.route.displayName, url).isValid()) {
      this.showToast($r('app.string.rule_source_login_https_only'));
      return false;
    }
    return true;
  }

  private interceptInitialDocument(request: WebResourceRequest): WebResourceResponse | null {
    if (this.initialDocumentServed || this.route.initialHtml.length === 0 || !request.isMainFrame()) return null;
    // An imported snapshot belongs only to this first document, never to a redirect or another origin.
    this.initialDocumentServed = true;
    if (request.getRequestUrl() !== this.route.documentUrl()) return null;
    const response = new WebResourceResponse();
    const headers: Header[] = [
      { headerKey: 'Content-Type', headerValue: 'text/html; charset=UTF-8' },
      { headerKey: 'Cache-Control', headerValue: 'no-store' },
      { headerKey: 'Content-Security-Policy', headerValue: LocalRuleExecutionLimits.INLINE_HTML_CSP }
    ];
    response.setResponseCode(200);
    response.setReasonMessage('OK');
    response.setResponseMimeType('text/html');
    response.setResponseEncoding('UTF-8');
    response.setResponseHeader(headers);
    response.setResponseData(this.route.initialHtml);
    return response;
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_error) {
      // 页面退出过程中 UIContext 可能已经失效。
    }
  }

  build() {
    Column() {
      this.buildHeader()

      if (!this.ready) {
        Column() {
          LoadingProgress()
            .width(30)
            .height(30)
            .color(AppColor.Brand)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Web({ src: '', controller: this.controller, incognitoMode: true })
            .width('100%')
            .height('100%')
            .onControllerAttached((): void => {
              this.restoreWebSession();
            })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .databaseAccess(false)
            .fileAccess(false)
            .geolocationAccess(false)
            .imageAccess(true)
            .onlineImageAccess(true)
            .mixedMode(MixedMode.None)
            .onSslErrorEvent((event: SslErrorEvent): void => {
              if (!event.isFatalError && LocalRuleTlsTrustStore.isTrustedUrlSync(event.url)) {
                event.handler.handleConfirm();
              } else {
                event.handler.handleCancel();
                this.loading = false;
                this.getUIContext().getPromptAction().showToast({
                  message: LocalRuleTlsTrustStore.describeFailure('证书校验失败', event.url)
                });
              }
            })
            .multiWindowAccess(false)
            .onInterceptRequest((event): WebResourceResponse | null => {
              return event === undefined ? null : this.interceptInitialDocument(event.request);
            })
            .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
              return !this.allowNavigation(request.getRequestUrl());
            })
            .onPageBegin((event): void => {
              this.loading = true;
              if (event?.url) {
                this.currentUrl = event.url;
                this.currentOrigin = LocalRuleHttpClient.requestOrigin(event.url);
                this.rememberUrl(event.url);
              }
            })
            .onPageEnd((event): void => {
              this.loading = false;
              if (!this.loginScriptInjected && this.route.injectJs.length > 0 &&
                event?.url === this.route.loginUrl) {
                this.loginScriptInjected = true;
                this.controller.runJavaScript(this.route.injectJs).catch((): void => {});
              }
              if (event?.url) {
                this.currentUrl = event.url;
                this.currentOrigin = LocalRuleHttpClient.requestOrigin(event.url);
                this.rememberUrl(event.url);
              }
            })
            .onErrorReceive((): void => {
              this.loading = false;
            })

          if (this.loading) {
            LoadingProgress()
              .width(30)
              .height(30)
              .color(AppColor.Brand)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildHeader() {
    Row({ space: AppSpace.Xs }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([$r('sys.color.font_primary')])
      }
      .width(44)
      .height(44)
      .borderRadius(AppRadius.Pill)
      .onClick(() => this.leaveLogin())

      Column({ space: 1 }) {
        Text(this.route.displayName)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.currentOrigin)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button() {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(19)
          .fontColor([AppColor.Brand])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .borderRadius(AppRadius.Pill)
      .enabled(this.ready && !this.saving)
      .accessibilityText($r('app.string.rule_source_login_refresh'))
      .onClick(() => this.refreshPage())

      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([RULE_LOGIN_DANGER])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .borderRadius(AppRadius.Pill)
      .enabled(this.ready && !this.saving)
      .accessibilityText($r('app.string.rule_source_login_clear_action'))
      .onClick(() => this.confirmClearLogin())

      Text($r('app.string.common_done'))
        .fontSize(AppFont.Body)
        .fontColor(AppColor.Brand)
        .fontWeight(FontWeight.Medium)
        .height(44)
        .padding({ left: AppSpace.Xs, right: AppSpace.Xs })
        .enabled(this.ready && !this.saving && !this.loading && !this.requestCancelled)
        .onClick(() => this.finishLogin())
    }
    .width('100%')
    .height(WindowUtils.getStatusBarHeightVp() + 56)
    .padding({
      left: AppSpace.Xs,
      right: AppSpace.Xs,
      top: WindowUtils.getStatusBarHeightVp()
    })
    .backgroundColor($r('sys.color.background_primary'))
  }
}
