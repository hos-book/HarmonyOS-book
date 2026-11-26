import http from '@ohos.net.http';
import deviceInfo from '@ohos.deviceInfo';

// 请求拦截器是 API 18 起的接口，ArkUI-X 的 http 声明里没有，运行时取用；取不到时走下面的异常兜底。
const httpDynamic: any = http;

/** Observe the SDK's actual destination, never infer it from a canonical tag or the input URL. */
export class HttpFinalUrlObserver {
  url: string = '';
  attached: boolean = false;

  constructor(client: http.HttpRequest, manualRedirects: boolean = false) {
    if (deviceInfo.sdkApiVersion < 22) return;
    try {
      const chain = new httpDynamic.HttpInterceptorChain();
      const interceptor: any = {
        interceptorType: httpDynamic.InterceptorType.FINAL_RESPONSE,
        interceptorHandle: async (request: any, _response: any): Promise<boolean> => {
          if (/^https?:\/\//i.test(request.url || '')) this.url = request.url;
          return true;
        }
      };
      const interceptors: any[] = [];
      if (manualRedirects) {
        interceptors.push({
          // NETWORK_CONNECT does not guard each SDK redirect on real devices.
          // Return the redirect response to HttpClient, which creates a fresh request.
          interceptorType: httpDynamic.InterceptorType.REDIRECTION,
          interceptorHandle: async (_request: any, _response: any): Promise<boolean> => false
        });
      }
      interceptors.push(interceptor);
      this.attached = chain.addChain(interceptors) && chain.apply(client);
    } catch (_) {
      // Older/platform-specific implementations may not support observation. Keep finalUrl unknown.
    }
  }
}
