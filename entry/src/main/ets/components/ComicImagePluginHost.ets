import { webview } from '@kit.ArkWeb';
import { fileIo } from '@kit.CoreFileKit';
import { ComicImagePluginService } from '../service/ComicImagePluginService';

/** 仅提供宿主资源、当前正文图片及已启用算法。 */
@ComponentV2
export struct ComicImagePluginHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  private service: ComicImagePluginService = ComicImagePluginService.instance;

  aboutToDisappear(): void { this.service.detach(this.controller); }

  private response(url: string): WebResourceResponse {
    const response = new WebResourceResponse();
    const path = url.startsWith(ComicImagePluginService.ORIGIN) ? url.substring(ComicImagePluginService.ORIGIN.length) : '';
    const bundled = ['index.html', 'host.js', 'worker.js'].includes(path);
    const local = bundled ? '' : this.service.resource(path);
    response.setResponseEncoding('utf-8');
    response.setResponseHeader([{ headerKey: 'Cache-Control', headerValue: 'no-store' }]);
    if (!bundled && !local) {
      response.setResponseCode(403); response.setReasonMessage('Forbidden'); response.setResponseData('');
      return response;
    }
    response.setResponseCode(200); response.setReasonMessage('OK');
    response.setResponseMimeType(path.endsWith('.js') ? 'text/javascript' : path.endsWith('.html') ? 'text/html' :
      path.endsWith('.json') ? 'application/json' : path.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream');
    if (bundled) response.setResponseData($rawfile('comic_plugins/' + path));
    else {
      try {
        const file = fileIo.openSync(local, fileIo.OpenMode.READ_ONLY);
        try { response.setResponseData(file.fd); }
        catch (_error) { fileIo.closeSync(file); throw new Error('comic_plugin_resource'); }
      } catch (_error) {
        response.setResponseCode(404); response.setReasonMessage('Missing'); response.setResponseData('');
      }
    }
    return response;
  }

  build() {
    Web({ src: ComicImagePluginService.ORIGIN + 'index.html', controller: this.controller, incognitoMode: true })
      .width(1).height(1).opacity(0.01).hitTestBehavior(HitTestMode.None)
      .javaScriptAccess(true).domStorageAccess(false).fileAccess(false).onlineImageAccess(false)
      .mixedMode(MixedMode.None).databaseAccess(false)
      .onInterceptRequest((event): WebResourceResponse => this.response(event?.request.getRequestUrl() ?? ''))
      .onLoadIntercept((event): boolean => event?.data.getRequestUrl() !== ComicImagePluginService.ORIGIN + 'index.html')
      .onPageEnd((): void => { this.service.attach(this.controller); })
  }
}
