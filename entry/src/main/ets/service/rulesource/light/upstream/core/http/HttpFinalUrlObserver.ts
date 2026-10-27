import http from '@ohos.net.http';
import deviceInfo from '@ohos.deviceInfo';

/** Observe the SDK's actual destination, never infer it from a canonical tag or the input URL. */
export class HttpFinalUrlObserver {
  url: string = '';
  attached: boolean = false;

  constructor(client: http.HttpRequest, manualRedirects: boolean = false) {
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
      const interceptors: http.HttpInterceptor[] = [];
      if (manualRedirects) {
        interceptors.push({
          // NETWORK_CONNECT does not guard each SDK redirect on real devices.
          // Return the redirect response to HttpClient, which creates a fresh request.
          interceptorType: http.InterceptorType.REDIRECTION,
          interceptorHandle: async (_request: http.HttpRequestContext, _response: http.HttpResponse): Promise<boolean> => false
        });
      }
      interceptors.push(interceptor);
      this.attached = chain.addChain(interceptors) && chain.apply(client);
    } catch (_) {
      // Older/platform-specific implementations may not support observation. Keep finalUrl unknown.
    }
  }
}
