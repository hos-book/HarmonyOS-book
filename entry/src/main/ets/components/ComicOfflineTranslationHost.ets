import { webview } from '@kit.ArkWeb';
import { fileIo } from '@kit.CoreFileKit';
import { ComicTranslationModelService } from '../service/ComicTranslationModelService';
import { ComicOfflineTranslationService } from '../service/ComicOfflineTranslationService';

/** 固定本地资源白名单；所有其他请求均返回 403，不存在通用平台 JS 桥。 */
@ComponentV2
export struct ComicOfflineTranslationHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  private readonly files: string[] = ['index.html', 'host.js', 'engine.js', 'transformers.min.js',
    'ort-wasm.wasm', 'ort-wasm-simd.wasm'];
  private readonly modelFiles: string[] = ['config.json', 'generation_config.json', 'tokenizer.json',
    'tokenizer_config.json', 'special_tokens_map.json', 'onnx/encoder_model_quantized.onnx', 'onnx/decoder_model_merged_quantized.onnx'];

  aboutToDisappear(): void {
    ComicOfflineTranslationService.detach(this.controller);
  }

  private response(url: string): WebResourceResponse {
    const response = new WebResourceResponse();
    const path = url.startsWith(ComicOfflineTranslationService.ORIGIN) ?
      url.substring(ComicOfflineTranslationService.ORIGIN.length) : '';
    const allowedModel = ['ja-en', 'ko-en', 'en-zh', 'zh-en'].some((model: string): boolean =>
      path.startsWith(`models/${model}/`) && this.modelFiles.includes(path.substring(`models/${model}/`.length)));
    if (!this.files.includes(path) && !allowedModel) {
      response.setResponseCode(403); response.setReasonMessage('Forbidden');
      response.setResponseMimeType('text/plain'); response.setResponseData('');
      return response;
    }
    response.setResponseCode(200); response.setReasonMessage('OK');
    response.setResponseMimeType(path.endsWith('.js') ? 'text/javascript' : path.endsWith('.wasm') ? 'application/wasm' :
      path.endsWith('.json') ? 'application/json' : path.endsWith('.html') ? 'text/html' : 'application/octet-stream');
    response.setResponseEncoding('utf-8');
    response.setResponseHeader([{ headerKey: 'Cache-Control', headerValue: 'no-store' }]);
    if (allowedModel) {
      try {
        const context = this.getUIContext().getHostContext();
        const local = context ? ComicTranslationModelService.localPath(context, path) : '';
        if (!local) throw new Error('comic_offline_model_missing');
        const file = fileIo.openSync(local, fileIo.OpenMode.READ_ONLY);
        try {
          // setResponseData(number) 将句柄交由 Web 关闭。页面不能保存后再关闭：
          // Web 释放后的 fd 可能已被复用，重复关闭会破坏 Web 的 IPC 管道并触发 SIGABRT。
          response.setResponseData(file.fd);
        } catch (_error) {
          // 只有移交失败时，句柄仍由应用负责释放。
          fileIo.closeSync(file);
          throw new Error('comic_offline_model_response_failed');
        }
      } catch (_error) {
        response.setResponseCode(404); response.setReasonMessage('Not Found'); response.setResponseData('');
      }
    } else response.setResponseData($rawfile('comic_offline/' + path));
    return response;
  }

  build() {
    Web({ src: ComicOfflineTranslationService.ORIGIN + 'index.html', controller: this.controller, incognitoMode: true })
      .width(1).height(1).opacity(0.01).hitTestBehavior(HitTestMode.None)
      .javaScriptAccess(true).domStorageAccess(false).fileAccess(false).onlineImageAccess(false)
      .mixedMode(MixedMode.None).databaseAccess(false)
      .onInterceptRequest((event): WebResourceResponse => this.response(event?.request.getRequestUrl() ?? ''))
      .onLoadIntercept((event): boolean => event?.data.getRequestUrl() !== ComicOfflineTranslationService.ORIGIN + 'index.html')
      .onPageEnd((): void => { ComicOfflineTranslationService.attach(this.controller); })
  }
}
