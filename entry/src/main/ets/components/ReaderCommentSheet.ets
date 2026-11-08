import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book } from '../model/Book';
import { ReaderParagraphComment, ReaderCommentMessage, ReaderCommentMessages } from '../model/ReaderComment';
import { BookSourceService } from '../service/BookSourceService';
import { LocalRuleReaderActionResult } from '../service/rulesource/LocalRuleRuntimeTypes';
import { LightSourceRequest } from '../service/rulesource/light/LightSourceRequestPolicy';
import { LightPersistedCookieRecord, LightSourceCookies } from '../service/rulesource/light/LightSourceCookies';
import { LocalRuleWebSession } from '../service/rulesource/LocalRuleWebSession';
import { ReaderCommentWebPolicy } from '../service/text/ReaderCommentWebPolicy';
import { LightReaderCommentDocument } from '../service/rulesource/light/LightReaderCommentDocument';
import { ListDataSource } from '../utils/ListDataSource';
import { AppColor } from '../theme/Theme';

class ReaderCommentCookie {
  url: string = '';
  header: string = '';
}

@ComponentV2
export struct ReaderCommentSheet {
  @Param book: Book | null = null;
  @Param chapterIndex: number = -1;
  @Param comment: ReaderParagraphComment = new ReaderParagraphComment();
  @Param dark: boolean = false;
  @Param offlineComments: ReaderCommentMessages | null = null;
  @Event onClose: () => void = () => {};
  @Local loading: boolean = true;
  @Local failed: boolean = false;
  @Local ready: boolean = false;
  @Local message: string = '';
  @Local itemCount: number = 0;
  private items: ListDataSource<ReaderCommentMessage> = new ListDataSource<ReaderCommentMessage>();
  private controller: webview.WebviewController = new webview.WebviewController();
  private request: LightSourceRequest = new LightSourceRequest(2);
  private result: LocalRuleReaderActionResult = new LocalRuleReaderActionResult();
  private alive: boolean = false;
  private serial: number = 0;
  private lease: number = 0;
  private timer: number = -1;
  private collectTimer: number = -1;
  private documentBase64: string = '';
  private started: boolean = false;
  private served: boolean = false;
  private cookiesReady: boolean = false;
  private storedCookies: LightPersistedCookieRecord[] = [];
  private header: string = '';
  private visited: string[] = [];
  private closing: Promise<void> = Promise.resolve();
  private sourceUrl: string = '';

  aboutToAppear(): void { this.alive = true; this.prepare(); }
  aboutToDisappear(): void {
    this.alive = false;
    this.serial++;
    this.request.cancel();
    this.clearTimer();
    this.releaseWeb();
  }

  private clearTimer(): void {
    if (this.timer >= 0) clearTimeout(this.timer);
    if (this.collectTimer >= 0) clearTimeout(this.collectTimer);
    this.timer = -1;
    this.collectTimer = -1;
  }

  private accept(raw: string): boolean {
    const data: ReaderCommentMessages = JSON.parse(LightReaderCommentDocument.parse(raw));
    if (data.items.length === 0 && !data.empty) return false;
    this.items.setItems(data.items);
    this.itemCount = data.items.length;
    this.loading = false;
    this.releaseWeb();
    return true;
  }

  private collect(): void {
    if (!this.alive || !this.ready || this.failed || this.collectTimer >= 0) return;
    const ticket = this.serial;
    this.collectTimer = setTimeout((): void => {
      this.collectTimer = -1;
      this.controller.runJavaScript(LightReaderCommentDocument.COLLECT).then((raw: string): void => {
        if (!this.alive || ticket !== this.serial || !this.ready || this.failed) return;
        if (!this.accept(raw)) this.collect();
      }).catch((): void => {
        if (this.alive && ticket === this.serial && this.ready && !this.failed) this.collect();
      });
    }, 250);
  }

  private async prepare(): Promise<void> {
    // EPUB notes are already extracted from the bounded local reader: no second Web lease or source request.
    if (this.offlineComments !== null) {
      this.items.setItems(this.offlineComments.items);
      this.itemCount = this.offlineComments.items.length;
      this.loading = false;
      return;
    }
    const ticket = ++this.serial;
    this.request.cancel();
    await this.releaseWeb();
    if (!this.alive || ticket !== this.serial) return;
    this.request = new LightSourceRequest(2);
    this.loading = true;
    this.failed = false;
    this.message = '';
    this.itemCount = 0;
    this.items.setItems([]);
    this.started = false;
    this.served = false;
    this.visited = [];
    this.controller = new webview.WebviewController();
    try {
      const book = this.book;
      if (!book) throw new Error('Missing book');
      this.sourceUrl = book.sourceUrl;
      const result = await BookSourceService.getParagraphComment(book, this.chapterIndex, this.comment.url, this.request);
      if (!this.alive || ticket !== this.serial) return;
      this.result = result;
      if (this.accept(result.commentData || result.value || '')) return;
      if (!result.html && !result.url) {
        this.loading = false;
        this.message = result.message || result.value || '';
        return;
      }
      if ((result.html?.length ?? 0) > 2 * 1024 * 1024) throw new Error('Comment page too large');
      if (!result.offline && !ReaderCommentWebPolicy.remote(result.url)) {
        if (!result.html) throw new Error('Invalid comment address');
        result.url = 'https://reader-comments.invalid/';
      }
      this.documentBase64 = result.offline ? new util.Base64Helper().encodeToStringSync(
        new util.TextEncoder().encodeInto(result.html)) : '';
      const lease = await LocalRuleWebSession.acquire(20000);
      if (!this.alive || ticket !== this.serial) { LocalRuleWebSession.release(lease); return; }
      this.lease = lease;
      this.storedCookies = result.offline ? [] : await LightSourceCookies.getStoredCookieRecords(this.sourceUrl);
      this.header = result.offline ? '' : await LightSourceCookies.getStoredCookieHeader(this.sourceUrl, result.url);
      if (!this.alive || ticket !== this.serial) { await this.releaseWeb(); return; }
      this.ready = true;
      this.timer = setTimeout((): void => { if (ticket === this.serial && this.alive) this.fail(); }, 20000);
    } catch (error) {
      hilog.warn(0x0000, 'ReaderComment', 'prepare failed: %{public}s',
        String(error).replace(/https?:\/\/\S+/g, '[url]').substring(0, 240));
      if (this.alive && ticket === this.serial) this.fail();
    }
  }

  private fail(): void {
    this.clearTimer();
    this.request.cancel();
    this.loading = false;
    this.failed = true;
    this.releaseWeb();
  }

  private attach(): void {
    if (!this.alive || this.lease === 0) return;
    try {
      webview.WebCookieManager.clearAllCookiesSync(true);
      this.controller.clearSslCache();
      for (const record of this.storedCookies) {
        webview.WebCookieManager.configCookieSync(record.url, record.cookie, true, true);
      }
      const origin = LightSourceCookies.requestOrigin(this.result.url);
      if (!this.result.offline && !this.storedCookies.some((record: LightPersistedCookieRecord): boolean =>
        LightSourceCookies.requestOrigin(record.url) === origin)) {
        for (const raw of this.header.split(';')) {
          const pair = raw.trim();
          if (pair.indexOf('=') > 0) webview.WebCookieManager.configCookieSync(this.result.url, pair + '; Path=/', true, true);
        }
      }
      this.cookiesReady = true;
      this.storedCookies = [];
      this.header = '';
    } catch (_error) { this.fail(); }
  }

  private pageEnd(url: string): void {
    if (!this.alive || !this.ready || this.failed) return;
    if (!this.started) {
      if (url !== 'about:blank' || !this.cookiesReady) return;
      this.started = true;
      try {
        if (this.result.offline) this.controller.loadData(this.documentBase64, 'text/html', 'base64');
        else this.controller.loadUrl(this.result.url);
        this.collect();
      } catch (_error) { this.fail(); }
      return;
    }
    if (url === 'about:blank') return;
    this.remember(url);
    this.collect();
    try { this.controller.clearHistory(); } catch (_error) { /* 网页已退出 */ }
  }

  @Builder
  commentRow(item: ReaderCommentMessage) {
    Row({ space: 10 }) {
      Stack() {
        Circle().fill(AppColor.BrandSoft).width(34).height(34)
        Text(item.author.substring(0, 1) || $r('app.string.reader_comment_avatar'))
          .fontSize(15).fontColor(AppColor.Brand).fontWeight(FontWeight.Medium)
        if (item.avatar) {
          Image(item.avatar).width(34).height(34).borderRadius(17).objectFit(ImageFit.Cover)
        }
      }.width(34).height(34)
      Column({ space: 6 }) {
        Text(item.author || $r('app.string.reader_comment_guest')).fontSize(12)
          .fontColor($r('sys.color.font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Column({ space: 6 }) {
          if (item.replyTo) {
            Text($r('app.string.reader_comment_reply_to', item.replyTo)).fontSize(12).fontColor(AppColor.Brand)
          }
          Text(item.text).fontSize(15).lineHeight(23).fontColor($r('sys.color.font_primary'))
            .copyOption(CopyOptions.LocalDevice).width('100%')
        }.alignItems(HorizontalAlign.Start).padding({ left: 14, right: 14, top: 11, bottom: 11 })
          .backgroundColor($r('app.color.reader_comment_bubble_background'))
          .border({ width: 1, color: $r('app.color.reader_comment_bubble_border') })
          .borderRadius({ topLeft: 4, topRight: 16, bottomLeft: 16, bottomRight: 16 }).width('100%')
        if (item.time || item.likes) {
          Row({ space: 10 }) {
            if (item.time) { Text(item.time).fontSize(10).fontColor($r('sys.color.font_tertiary')) }
            if (item.likes && item.likes !== '0') {
              Text($r('app.string.reader_comment_likes', item.likes)).fontSize(10).fontColor($r('sys.color.font_tertiary'))
            }
          }
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(VerticalAlign.Top).padding({ left: item.replyTo ? 28 : 18, right: 22 })
  }

  private remember(url: string): void {
    if (ReaderCommentWebPolicy.remote(url) && !this.visited.includes(url) && this.visited.length < 16) this.visited.push(url);
  }

  private intercept(request: WebResourceRequest): WebResourceResponse | null {
    const url = request.getRequestUrl();
    if (this.result.offline && !ReaderCommentWebPolicy.navigation(url, true, request.isMainFrame(), this.documentBase64) &&
      !/^data:image\//i.test(url)) return this.response('', 403);
    if (!this.result.offline && this.result.html && !this.served && request.isMainFrame() && url === this.result.url) {
      this.served = true;
      return this.response(this.result.html, 200);
    }
    return null;
  }

  private response(html: string, status: number): WebResourceResponse {
    const response = new WebResourceResponse();
    response.setResponseData(html);
    response.setResponseCode(status);
    response.setReasonMessage(status === 200 ? 'OK' : 'Blocked');
    response.setResponseMimeType('text/html');
    response.setResponseEncoding('UTF-8');
    return response;
  }

  private releaseWeb(): Promise<void> {
    this.clearTimer();
    this.ready = false;
    const lease = this.lease;
    if (lease === 0) return this.closing;
    this.lease = 0;
    const snapshots: ReaderCommentCookie[] = [];
    try { this.controller.stop(); } catch (_error) { /* 已停止 */ }
    if (this.cookiesReady && !this.result.offline) {
      for (const url of this.visited) {
        try {
          const snapshot = new ReaderCommentCookie();
          snapshot.url = url;
          snapshot.header = webview.WebCookieManager.fetchCookieSync(url, true);
          snapshots.push(snapshot);
        } catch (_error) { /* 读取失败不能清空已存会话 */ }
      }
    }
    this.cookiesReady = false;
    const sourceUrl = this.sourceUrl;
    this.closing = (async (): Promise<void> => {
      try {
        for (const snapshot of snapshots) {
          try { await LightSourceCookies.saveWebCookies(sourceUrl, snapshot.url, snapshot.header); }
          catch (_error) { /* 退出仍须释放租约 */ }
        }
        // 等 Web 条件节点卸载后再允许其他书源使用无痕容器。
        await new Promise<void>((resolve): void => { setTimeout(resolve, 0); });
      } finally {
        try { webview.WebCookieManager.clearAllCookiesSync(true); } catch (_error) { /* 容器已销毁 */ }
        LocalRuleWebSession.release(lease);
      }
    })();
    return this.closing;
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.reader_comment_title')).fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        if (this.itemCount > 0) { Text(this.itemCount.toString()).fontSize(12).fontColor(AppColor.Brand).margin({ left: 8 }) }
        Blank()
        Button($r('app.string.common_close')).fontSize(14).fontColor(AppColor.Brand)
          .backgroundColor(Color.Transparent).onClick((): void => this.onClose())
      }.width('100%').padding({ left: 20, right: 12, top: 4, bottom: 12 })
      Stack() {
        if (this.ready) {
          Web({ src: 'about:blank', controller: this.controller, incognitoMode: true })
            .width('100%').height('100%')
            .opacity(0).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
            .javaScriptAccess(true).domStorageAccess(!this.result.offline).databaseAccess(false)
            .fileAccess(false).geolocationAccess(false).mixedMode(MixedMode.None)
            .blockNetwork(this.result.offline === true).onlineImageAccess(!this.result.offline)
            .multiWindowAccess(false).allowWindowOpenMethod(false)
            .darkMode(this.dark ? WebDarkMode.On : WebDarkMode.Off).forceDarkAccess(false)
            .onControllerAttached((): void => this.attach())
            .onOverrideUrlLoading((request: WebResourceRequest): boolean =>
              !ReaderCommentWebPolicy.navigation(request.getRequestUrl(), this.result.offline === true, request.isMainFrame(), this.documentBase64))
            .onLoadIntercept((event?: OnLoadInterceptEvent): boolean => !!event?.data &&
              !ReaderCommentWebPolicy.navigation(event.data.getRequestUrl(), this.result.offline === true, event.data.isMainFrame(), this.documentBase64))
            .onInterceptRequest((event?: OnInterceptRequestEvent): WebResourceResponse | null => event ? this.intercept(event.request) : null)
            .onPermissionRequest((event: OnPermissionRequestEvent): void => event.request.deny())
            .onShowFileSelector((event: OnShowFileSelectorEvent): boolean => { event.result.handleFileList([]); return true; })
            .onAlert((event: OnAlertEvent): boolean => { event.result.handleCancel(); return true; })
            .onConfirm((event: OnConfirmEvent): boolean => { event.result.handleCancel(); return true; })
            .onPrompt((event: OnPromptEvent): boolean => { event.result.handleCancel(); return true; })
            .onPageBegin((event: OnPageBeginEvent): void => this.remember(event.url))
            .onPageEnd((event: OnPageEndEvent): void => this.pageEnd(event.url))
            .onErrorReceive((event: OnErrorReceiveEvent): void => {
              if (event.request.isMainFrame()) {
                hilog.warn(0x0000, 'ReaderComment', 'web failed: %{public}d', event.error.getErrorCode());
                this.fail();
              }
            })
            .onHttpErrorReceive((event: OnHttpErrorReceiveEvent): void => {
              if (event.request.isMainFrame()) {
                hilog.warn(0x0000, 'ReaderComment', 'http failed: %{public}d', event.response.getResponseCode());
                this.fail();
              }
            })
        }
        if (this.itemCount > 0) {
          List({ space: 18 }) {
            LazyForEach(this.items, (item: ReaderCommentMessage) => {
              ListItem() { this.commentRow(item) }
            }, (item: ReaderCommentMessage): string => item.id)
          }.width('100%').height('100%').padding({ top: 10, bottom: 28 }).scrollBar(BarState.Off)
            .id('reader-comment-messages')
        } else {
          Column({ space: 14 }) {
            if (this.loading) { LoadingProgress().width(30).height(30).color(AppColor.Brand) }
            Text(this.failed ? $r('app.string.reader_comment_failed') : this.loading ?
              $r('app.string.reader_comment_loading') : this.message || $r('app.string.reader_comment_empty'))
              .fontSize(14).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
            if (this.failed) {
              Button($r('app.string.common_retry')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
                .onClick((): void => { this.prepare(); })
            }
          }.width('100%').height('100%').padding(24).justifyContent(FlexAlign.Center)
        }
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}
