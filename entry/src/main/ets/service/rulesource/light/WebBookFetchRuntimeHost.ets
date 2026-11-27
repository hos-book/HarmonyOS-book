import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WebBookFetchRuntime } from './upstream/core/book/WebBookFetchRuntime';

/** Invisible ArkWeb transport for source rules that explicitly opt into `webView: true`. */
@ComponentV2
export struct WebBookFetchRuntimeHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  private attachRetryId: number = -1;
  private disappearing: boolean = false;

  aboutToAppear(): void {
    this.disappearing = false;
    this.scheduleAttachFallback(0);
  }

  aboutToDisappear(): void {
    this.disappearing = true;
    if (this.attachRetryId >= 0) clearTimeout(this.attachRetryId);
    this.attachRetryId = -1;
    WebBookFetchRuntime.get().detach(this.controller);
  }

  private attachRuntime(): void {
    if (this.disappearing) return;
    if (this.attachRetryId >= 0) clearTimeout(this.attachRetryId);
    this.attachRetryId = -1;
    WebBookFetchRuntime.get().attach(this.controller);
  }

  private scheduleAttachFallback(attempt: number): void {
    if (this.disappearing) return;
    this.attachRetryId = setTimeout((): void => {
      if (this.disappearing) return;
      try {
        // A successful getWebId proves the controller is associated with a Web component. On
        // some routed/hidden Web nodes ArkWeb omits onControllerAttached, so use this as fallback.
        this.controller.getWebId();
        this.attachRuntime();
        return;
      } catch (_) {}
      if (attempt < 100) this.scheduleAttachFallback(attempt + 1);
    }, attempt === 0 ? 0 : 100);
  }

  build() {
    if (canIUse('SystemCapability.Web.Webview.Core')) {
      Web({ src: 'about:blank', controller: this.controller, incognitoMode: true })
        .width(1)
        .height(1)
        .opacity(0.01)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mixedMode(MixedMode.All)
        .onlineImageAccess(true)
        .onConsole((event) => {
          if (event && /blocked by CORS policy|Access-Control-Allow-Origin/.test(event.message.getMessage())) {
            hilog.warn(0x0001, 'SourceWeb', 'Source website request blocked by browser CORS policy');
          }
          return false;
        })
        .onControllerAttached((): void => { this.attachRuntime(); })
        .onPageBegin((): void => { WebBookFetchRuntime.get().onPageBegin(this.controller); })
        .onPageEnd((): void => { WebBookFetchRuntime.get().onPageEnd(this.controller); })
    }
  }
}
