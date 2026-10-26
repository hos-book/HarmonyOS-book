import http from '@ohos.net.http';
import deviceInfo from '@ohos.deviceInfo';

/** Observe the SDK's actual destination, never infer it from a canonical tag or the input URL. */
export class HttpFinalUrlObserver {
  url: string = '';
  attached: boolean = false;

  constructor(client: http.HttpRequest) {
    if (deviceInfo.sdkApiVersion < 22) return;
    try {
      const chain = new http.HttpInterceptorChain();
      const interceptor: http.HttpInterceptor = {
        interceptorType: http.InterceptorType.FINAL_RESPONSE,
        interceptorHandle: async (request: http.HttpRequestContext, _response: http.HttpResponse): Promise<boolean> => {
          if (/^https?:\/\//i.test(request.url || '')) this.url = request.url;
          return true;
        }
      };
      this.attached = chain.addChain([interceptor]) && chain.apply(client);
    } catch (_) {
      // Older/platform-specific implementations may not support observation. Keep finalUrl unknown.
    }
  }
}
