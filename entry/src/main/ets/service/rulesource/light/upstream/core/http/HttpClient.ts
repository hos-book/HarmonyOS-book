import { HttpHeaderValues } from './HttpHeaderValues';
import http from '@ohos.net.http';
import { util, url } from '@kit.ArkTS';
import { CookieStore } from './CookieStore';
import { TlsTrustStore } from './TlsTrustStore';
import { WebBookFetchRuntime } from '../book/WebBookFetchRuntime';
import { BookSourceDebugContext, BookSourceDebugNetworkTrace } from '../book/BookSourceDebugModels';
import { SourceEngineHost } from '../host/SourceEngineHost';
import { HttpProtocolPolicy } from './HttpProtocolPolicy';
import { HttpFinalUrlObserver } from './HttpFinalUrlObserver';

export interface HttpRequest {
  webRequestId?: string;
  webWaitFor?: string;
  webWaitStage?: string;
  webHostStartedAt?: number;
  webHostWaitMs?: number;
  automaticCookieHeader?: boolean;
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
  bodyBytes?: ArrayBuffer;
  charset?: string;
  useCookieJar?: boolean;
  connectTimeout?: number;
  readTimeout?: number;
  /** Absolute deadline shared by throttling, redirects and retries; not a fresh timeout per attempt. */
  deadlineAt?: number;
  contentType?: string;
  maxResponseBytes?: number;
  useWebView?: boolean;
  /** Explicit policy disables implicit transport retries. */
  managedRetry?: boolean;
  retryAttempt?: number;
  retryReason?: string;
  diagnosticAttempts?: string[];
  observedRequestHeaders?: Record<string, string>;
  /** Custom media credentials are scoped to the initial origin, including SDK redirects. */
  protectedHeaderNames?: string[];
  webJs?: string;
  /** See WebBookFetchRequest: re-run `webJs` until the result matches, up to the attempt limit. */
  webJsAcceptPattern?: string;
  webJsMaxAttempts?: number;
  debugContext?: BookSourceDebugContext;
  // Script-bridge requests run inside a serial runtime: a hung request stalls every queued
  // task, so the doubled-timeout idempotent retry is skipped for them (caller re-runs instead).
  noTimeoutRetry?: boolean;
  /** 返回 true 时不再发出请求（发出前、等 WebView 就绪后各检查一次），直接得到「书源请求已取消」。 */
  cancelCheck?: () => boolean;
  /** 宿主诊断端口分配的计时编号；0 或缺省表示不记录分段耗时。 */
  timingId?: number;
  /** 请求所属书源的地址，用来向宿主取该书源的 Cookie 存储；缺省用全局 CookieStore。 */
  cookieSource?: string;
}

export interface HttpResponse {
  bodyIsSnapshot?: boolean;
  snapshotTruncated?: boolean;
  waitStage?: string;
  errorCode?: string;
  errorStage?: string;
  statusCodeAvailable?: boolean;
  hostWaitMs?: number;
  queueMs?: number;
  renderMs?: number;

  url: string;
  headersAvailable?: boolean;
  requestId?: string;
  /** Observed final destination; absent/empty means unavailable on this transport/platform. */
  finalUrl?: string;
  statusCode: number;
  headers: Record<string, string>;
  body: string;
  success: boolean;
  error?: string;
}

export interface HttpBinaryResponse {
  url: string;
  finalUrl?: string;
  statusCode: number;
  headers: Record<string, string>;
  data: Uint8Array;
  success: boolean;
  error?: string;
}

export class HttpClient {
  private static requestSequence: number = 0;
  /** Host-owned persistent preference; automatic per-origin fallback remains temporary. */
  static get forceHttp1(): boolean { return HttpProtocolPolicy.forceHttp1; }
  static set forceHttp1(value: boolean) { HttpProtocolPolicy.forceHttp1 = value; }
  private timeout: number;
  private activeClients: Set<http.HttpRequest> = new Set<http.HttpRequest>();
  static readonly DEFAULT_USER_AGENT: string =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  private defaultHeaders: Record<string, string> = {
    'User-Agent': HttpClient.DEFAULT_USER_AGENT,
    'Accept': '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Connection': 'keep-alive'
  };

  private applyRequestCookies(req: HttpRequest, headers: Record<string, string>): void {
    if (req.useCookieJar === false) return;
    const key = Object.keys(headers).find((name: string): boolean => name.toLowerCase() === 'cookie');
    if (key && !req.automaticCookieHeader) return;
    const jar = CookieStore.forSource(req.cookieSource);
    const cookie = jar.getRequestCookie ? jar.getRequestCookie(req.url) : jar.getCookie(req.url);
    if (!cookie) return;
    const names = cookie.split(';').map((part: string): string => part.trim().split('=')[0]);
    const extra = (key ? headers[key] : '').split(';').map((part: string): string => part.trim())
      .filter((part: string): boolean => !!part && names.indexOf(part.split('=')[0]) < 0);
    if (key) delete headers[key];
    headers['Cookie'] = cookie + (extra.length ? '; ' + extra.join('; ') : '');
  }

  private requestHeaders(own: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = { ...this.defaultHeaders };
    for (const name of Object.keys(own || {})) {
      for (const key of Object.keys(headers)) if (key.toLowerCase() === name.toLowerCase()) delete headers[key];
      headers[name.toLowerCase() === 'user-agent' ? 'User-Agent' : name] = own[name];
    }
    return headers;
  }

  constructor(timeout: number = 8000) {
    this.timeout = timeout;
  }

  static readonly CANCELLED_ERROR: string = '书源请求已取消';

  static timeoutResponse(req: HttpRequest): HttpResponse {
    if (req.useWebView && req.webRequestId) {
      const response = WebBookFetchRuntime.get().timeoutRequest(req.webRequestId);
      const hostWaitMs = req.webHostWaitMs ?? (req.webHostStartedAt ? Date.now() - req.webHostStartedAt : 0);
      if (response) return { ...response, hostWaitMs: hostWaitMs, headersAvailable: false,
        finalUrl: response.bodyIsSnapshot ? response.url : '' };
      return { url: req.url, statusCode: 0, headers: {}, body: '', success: false,
        error: '网页请求总等待超时 (2300028)', errorCode: 'REQUEST_DEADLINE', errorStage: 'deadline',
        waitStage: req.webWaitStage || 'session', hostWaitMs: hostWaitMs, statusCodeAvailable: false };
    }
    return { url: req.url, statusCode: 0, headers: {}, body: '', success: false, error: '请求总等待超时 (2300028)', errorCode: 'REQUEST_DEADLINE', errorStage: 'deadline', statusCodeAvailable: false };
  }

  private timeoutFor(req: HttpRequest, configured?: number): number {
    const value = configured || this.timeout;
    return req.deadlineAt ? Math.max(1, Math.min(value, req.deadlineAt - Date.now())) : value;
  }

  /** Also bounds waiting for a shared browser session. Late work checks the same deadline before sending. */
  private async withinDeadline<T>(req: HttpRequest, work: () => Promise<T>, timedOut: () => T): Promise<T> {
    if (!req.deadlineAt) return await work();
    const remaining = req.deadlineAt - Date.now();
    if (remaining <= 0) return timedOut();
    return await new Promise<T>((resolve, reject): void => {
      const timer = setTimeout((): void => resolve(timedOut()), remaining);
      work().then((value: T): void => {
        clearTimeout(timer);
        // The Web runtime already enforces the same deadline and retains its last snapshot.
        resolve(!req.useWebView && req.deadlineAt && Date.now() >= req.deadlineAt ? timedOut() : value);
      },
        (error: Error): void => { clearTimeout(timer); reject(error); });
    });
  }

  private cancelledResponse(req: HttpRequest): HttpResponse {
    return { url: req.url, statusCode: 0, headers: {}, body: '', success: false, error: HttpClient.CANCELLED_ERROR, errorCode: 'CANCELLED', errorStage: 'cancel', statusCodeAvailable: false };
  }

  /** 宿主装了诊断端口（请求带 timingId）时才记录分段耗时；明细由回调生成，没装时不拼字符串。 */
  private endTiming(req: HttpRequest, stage: string, startedAt: number, details?: () => string): void {
    if (!req.timingId) return;
    SourceEngineHost.end(req.timingId, stage, startedAt, details ? details() : '');
  }

  private endTransportTiming(req: HttpRequest, startedAt: number, forceHttp1: boolean,
    resp: http.HttpResponse): void {
    this.endTiming(req, 'http-transport', startedAt, (): string => {
      const timing = resp.performanceTiming;
      const sdk = timing ? ` dnsEndMs=${timing.dnsTiming} tcpEndMs=${timing.tcpTiming}` +
        ` tlsEndMs=${timing.tlsTiming} sendStartMs=${timing.firstSendTiming}` +
        ` firstByteMs=${timing.firstReceiveTiming} finishMs=${timing.totalFinishTiming}` +
        ` redirectEndMs=${timing.redirectTiming} sdkTotalMs=${timing.totalTiming}` : ' sdkTiming=unavailable';
      return `http1=${forceHttp1} status=${resp.responseCode}${sdk}`;
    });
  }

  async execute(req: HttpRequest): Promise<HttpResponse> {
    req = { ...req, diagnosticAttempts: [] };
    const requestId = `http-${++HttpClient.requestSequence}`;
    if (req.useWebView) {
      req.webRequestId = requestId;
      req.webWaitStage = 'session';
    }
    const startedAt = Date.now();
    let response: HttpResponse;
    try {
      response = await this.withinDeadline(req, (): Promise<HttpResponse> => this.executeInternal(req),
        (): HttpResponse => HttpClient.timeoutResponse(req));
    } catch (error) {
      response = { url: req.url || '', statusCode: 0, headers: {}, body: '', success: false,
        error: error instanceof Error ? error.message : String(error || 'network error') };
    }
    response.statusCodeAvailable = response.statusCodeAvailable === undefined ? response.statusCode > 0 && !req.useWebView : response.statusCodeAvailable;
    response.headersAvailable = response.headersAvailable === undefined ? response.statusCode > 0 && !req.useWebView : response.headersAvailable;
    response.requestId = requestId;
    this.endTiming(req, 'http-total', startedAt,
      (): string => `status=${response.statusCode} success=${response.success} web=${!!req.useWebView}`);
    if (req.debugContext) {
      const trace = new BookSourceDebugNetworkTrace();
      trace.method = req.method || 'GET';
      trace.url = req.url || '';
      trace.finalUrl = response.finalUrl || '';
      trace.statusCode = response.statusCode || 0;
      trace.statusCodeAvailable = response.statusCodeAvailable === true;
      trace.errorCode = response.errorCode || '';
      trace.errorStage = response.errorStage || '';
      trace.waitStage = response.waitStage || '';
      trace.bodyIsSnapshot = response.bodyIsSnapshot === true;
      trace.snapshotTruncated = response.snapshotTruncated === true;
      trace.hostWaitMs = response.hostWaitMs || 0;
      trace.queueMs = response.queueMs || 0;
      trace.renderMs = response.renderMs || 0;
      trace.requestId = requestId;
      trace.transport = req.useWebView ? 'WebView' : 'HTTP';
      trace.retryAttempt = req.retryAttempt || 0;
      trace.retryReason = req.retryReason || '';
      trace.attempts = (req.diagnosticAttempts || []).join(' → ');
      trace.requestHeaders = req.observedRequestHeaders || {};
      trace.responseHeaders = response.headersAvailable ? HttpHeaderValues.normalize(response.headers || {}) : {};
      trace.headersAvailable = response.headersAvailable === true;
      trace.responseChars = response.body ? response.body.length : 0;
      trace.responseBytes = -1; // Wire size is not measured by this decoded-text path.
      trace.bodyPreview = response.body || '';
      trace.elapsedMs = Math.max(0, Date.now() - startedAt);
      trace.error = response.success ? '' : (response.error || 'request failed');
      req.debugContext.addNetwork(trace);
    }
    return response;
  }

  private async executeInternal(req: HttpRequest): Promise<HttpResponse> {
    if (req.cancelCheck && req.cancelCheck()) return this.cancelledResponse(req);
    if (req.deadlineAt && Date.now() >= req.deadlineAt) return HttpClient.timeoutResponse(req);
    if (!req.url || req.url.trim() === '') {
      return { url: '', statusCode: 0, headers: {}, body: '', success: false, error: 'empty url' };
    }
    if (req.useWebView) {
      return await SourceEngineHost.withWeb(req.cookieSource || '', async () => {
        if (req.deadlineAt && Date.now() >= req.deadlineAt) return HttpClient.timeoutResponse(req);
        const runtime = WebBookFetchRuntime.get();
        // Only wait for the hidden ArkWeb host to attach. A busy host is healthy: fetch() queues
        // subsequent requests and runs them in order instead of misreporting it as "not ready".
        const hostStarted = Date.now();
        req.webHostStartedAt = hostStarted;
        req.webWaitStage = 'host';
        const attached = await runtime.waitUntilAttached(this.timeoutFor(req, 8000), req.cancelCheck);
        const hostWaitMs = Date.now() - hostStarted;
        req.webHostWaitMs = hostWaitMs;
        if (req.cancelCheck?.()) return this.cancelledResponse(req);
        if (req.deadlineAt && Date.now() >= req.deadlineAt) return HttpClient.timeoutResponse(req);
        if (!attached) {
          return { url: req.url, statusCode: 0, headers: {}, body: '', success: false,
            error: '网页抓取宿主不可用，请返回页面后重试', errorCode: 'WEB_HOST_UNAVAILABLE', errorStage: 'host', statusCodeAvailable: false, hostWaitMs: hostWaitMs };
        }
        if (req.cancelCheck && req.cancelCheck()) return this.cancelledResponse(req);
        req.observedRequestHeaders = this.requestHeaders(req.headers);
        req.diagnosticAttempts?.push('WebView');
        req.webWaitStage = 'queue';
        const response = await runtime.fetch({
          requestId: req.webRequestId,
          webWaitFor: req.webWaitFor,
          url: req.url,
          cookieSource: req.cookieSource,
          cancelCheck: req.cancelCheck,
          method: req.method,
          headers: this.requestHeaders(req.headers),
          body: req.body,
          webJs: req.webJs,
          webJsAcceptPattern: req.webJsAcceptPattern,
          webJsMaxAttempts: req.webJsMaxAttempts,
          timeoutMs: this.timeoutFor(req, Math.max(req.connectTimeout || 0, req.readTimeout || 0, this.timeout)),
          deadlineAt: req.deadlineAt,
          maxResponseBytes: req.maxResponseBytes
        });
        return { ...response, hostWaitMs: hostWaitMs, statusCodeAvailable: false, headersAvailable: false,
          finalUrl: response.success || response.bodyIsSnapshot ? response.url : '' };
      });
    }
    const forceHttp1 = HttpProtocolPolicy.prefersHttp1(req.url);
    const response = await this.executeWithProtocol(req, forceHttp1);
    if (!response.success && forceHttp1) HttpProtocolPolicy.forget(req.url);
    if (!req.managedRetry && !response.success && !forceHttp1 && HttpProtocolPolicy.mayRetry(req.url, req.method, response.error || '')) {
      console.info('[HttpClient] transport failed; trying HTTP/1.1 once:', this.hostForLog(req.url));
      const retry = await this.executeWithProtocol(req, true);
      if (retry.success) HttpProtocolPolicy.rememberSuccess(req.url);
      return retry;
    }
    if (!response.success && !req.noTimeoutRetry && !req.deadlineAt && this.shouldRetryTimeout(req, response.error || '')) {
      const retryTimeout = Math.min(30000, Math.max(this.timeout * 2, 15000));
      console.info('[HttpClient] idempotent request timed out; retrying once:', this.hostForLog(req.url));
      return await this.executeWithProtocol({
        ...req,
        connectTimeout: Math.max(req.connectTimeout || 0, retryTimeout),
        readTimeout: Math.max(req.readTimeout || 0, retryTimeout)
      }, true);
    }
    return response;
  }

  private async executeWithProtocol(req: HttpRequest, forceHttp1: boolean): Promise<HttpResponse> {
    if (req.cancelCheck && req.cancelCheck()) return this.cancelledResponse(req);
    if (req.deadlineAt && Date.now() >= req.deadlineAt) return HttpClient.timeoutResponse(req);
    const client = http.createHttp();
    this.activeClients.add(client);
    const destination = new HttpFinalUrlObserver(client);
    let responseTooLarge = false;
    let expired = false;
    const deadlineTimer = req.deadlineAt ? setTimeout((): void => {
      expired = true;
      try { client.destroy(); } catch (_) { }
    }, Math.max(1, req.deadlineAt - Date.now())) : -1;
    try {
      const method = this.resolveMethod(req.method);
      const headers: Record<string, string> = this.requestHeaders(req.headers);
      const requestData = this.requestData(req);
      this.applyRequestCookies(req, headers);
      req.observedRequestHeaders = headers;
      req.diagnosticAttempts?.push(forceHttp1 ? 'HTTP/1.1' : 'HTTP 默认协议');
      const maxResponseBytes = req.maxResponseBytes || 0;
      // Interceptors do not run on requestInStream. On API 22+ use the SDK's bounded buffer
      // so script requests can observe automatic redirects without losing their byte limit.
      if (maxResponseBytes > 0 && !destination.attached) {
        const chunks: ArrayBuffer[] = [];
        let receivedBytes = 0;
        let streamSentAt = 0;
        let headersTimed = false;
        let dataTimed = false;
        let streamedHeaders: Record<string, string> = {};
        const onHeadersReceive = (value: Object): void => {
          if (!headersTimed && streamSentAt > 0) {
            headersTimed = true;
            this.endTiming(req, 'http-stream-first-headers', streamSentAt);
          }
          streamedHeaders = (value || {}) as Record<string, string>;
          const contentLength = Number(this.findHeader(streamedHeaders, 'content-length') || '0');
          if (contentLength > maxResponseBytes) {
            responseTooLarge = true;
            client.destroy();
          }
        };
        const onDataReceive = (chunk: ArrayBuffer): void => {
          if (responseTooLarge) return;
          if (!dataTimed && streamSentAt > 0) {
            dataTimed = true;
            this.endTiming(req, 'http-stream-first-data', streamSentAt);
          }
          receivedBytes += chunk.byteLength;
          if (receivedBytes > maxResponseBytes) {
            responseTooLarge = true;
            chunks.length = 0;
            client.destroy();
            return;
          }
          chunks.push(chunk);
        };
        client.on('headersReceive', onHeadersReceive);
        client.on('dataReceive', onDataReceive);
        let responseCode = 0;
        let streamError = '';
        try {
          const options: http.HttpRequestOptions = {
            method: method,
            header: headers,
            extraData: requestData,
            connectTimeout: this.timeoutFor(req, req.connectTimeout),
            readTimeout: this.timeoutFor(req, req.readTimeout)
          };
          this.applyTlsTrust(options, req.url);
          if (forceHttp1) options.usingProtocol = http.HttpProtocol.HTTP1_1;
          streamSentAt = Date.now();
          try {
            responseCode = await client.requestInStream(req.url, options);
          } finally {
            this.endTiming(req, 'http-stream-transport', streamSentAt, (): string => `http1=${forceHttp1}`);
          }
        } catch (error) {
          streamError = this.decorateTlsError(req.url, this.describeError(error as Object));
        } finally {
          client.off('headersReceive', onHeadersReceive);
          client.off('dataReceive', onDataReceive);
        }
        if (expired || (req.deadlineAt && Date.now() >= req.deadlineAt)) return HttpClient.timeoutResponse(req);
        if (responseTooLarge) {
          return {
            url: req.url,
            statusCode: responseCode,
            headers: streamedHeaders,
            body: '',
            success: false,
            error: `response too large: >${maxResponseBytes}`
          };
        }
        const result = this.mergeArrayBuffers(chunks, receivedBytes);
        const streamedResponse = this.buildResponse(req, responseCode, streamedHeaders, result);
        if (streamError) {
          // Some servers finish a chunked response and then close the connection in a way
          // Network Kit reports as 2300056. Preserve the received body so callers can
          // validate and use a complete payload instead of losing it with the socket error.
          streamedResponse.success = false;
          streamedResponse.error = streamError;
        }
        return streamedResponse;
      }

      const options: http.HttpRequestOptions = {
        method: method,
        header: headers,
        extraData: requestData,
        connectTimeout: this.timeoutFor(req, req.connectTimeout),
        readTimeout: this.timeoutFor(req, req.readTimeout),
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      if (maxResponseBytes > 0) options.maxLimit = Math.min(maxResponseBytes, 100 * 1024 * 1024);
      this.applyTlsTrust(options, req.url);
      if (forceHttp1) options.usingProtocol = http.HttpProtocol.HTTP1_1;
      const transportStartedAt = Date.now();
      const resp = await client.request(req.url, options);
      if (expired || (req.deadlineAt && Date.now() >= req.deadlineAt)) return HttpClient.timeoutResponse(req);
      this.endTransportTiming(req, transportStartedAt, forceHttp1, resp);
      const responseHeaders = (resp.header || {}) as Record<string, string>;
      if (maxResponseBytes > 0 && resp.result instanceof ArrayBuffer && resp.result.byteLength > maxResponseBytes) {
        responseTooLarge = true;
        throw new Error('response too large');
      }
      const response = this.buildResponse({ ...req, url: destination.url || req.url },
        resp.responseCode, responseHeaders, resp.result);
      response.finalUrl = destination.url;
      return response;
    } catch (e) {
      if (expired || (req.deadlineAt && Date.now() >= req.deadlineAt)) return HttpClient.timeoutResponse(req);
      return {
        url: req.url,
        statusCode: 0,
        headers: {},
        body: '',
        success: false,
        error: responseTooLarge || (!!req.maxResponseBytes && /2300063/.test(this.describeError(e as Object))) ?
          `response too large: >${req.maxResponseBytes}` :
          this.decorateTlsError(req.url, this.describeError(e as Object))
      };
    } finally {
      if (deadlineTimer >= 0) clearTimeout(deadlineTimer);
      this.activeClients.delete(client);
      try { client.destroy(); } catch (_) { }
    }
  }

  async executeBinary(req: HttpRequest, maxResponseBytes: number = 20 * 1024 * 1024):
    Promise<HttpBinaryResponse> {
    if (req.protectedHeaderNames?.length && !req.deadlineAt) {
      req = { ...req, deadlineAt: Date.now() + Math.max(this.timeout, req.connectTimeout || 0, req.readTimeout || 0) };
    }
    return await this.withinDeadline(req, (): Promise<HttpBinaryResponse> => this.executeBinaryInternal(req, maxResponseBytes),
      (): HttpBinaryResponse => ({ url: req.url, statusCode: 0, headers: {}, data: new Uint8Array(),
        success: false, error: '请求超时 (2300028)' }));
  }

  private async executeBinaryInternal(req: HttpRequest, maxResponseBytes: number): Promise<HttpBinaryResponse> {
    if (!req.url || req.url.trim() === '') {
      return { url: '', statusCode: 0, headers: {}, data: new Uint8Array(), success: false, error: 'empty url' };
    }
    // A limit carried by the request itself is honoured too; it used to be ignored on this path.
    const limit = req.maxResponseBytes && req.maxResponseBytes > 0 ?
      Math.min(req.maxResponseBytes, maxResponseBytes) : maxResponseBytes;
    if (req.protectedHeaderNames?.length) return await this.executeProtectedBinary(req, limit);
    return await this.executeBinaryAttempt(req, limit);
  }

  private async executeProtectedBinary(req: HttpRequest, limit: number): Promise<HttpBinaryResponse> {
    let current: HttpRequest = { ...req, headers: { ...req.headers } };
    const scoped = (req.protectedHeaderNames || []).map((name: string): string => name.toLowerCase())
      .concat(['cookie', 'authorization', 'proxy-authorization', 'origin']);
    const visited: string[] = [req.url];
    for (let hop = 0; hop <= 8; hop++) {
      const response = await this.executeBinaryAttempt(current, limit);
      if (![301, 302, 303, 307, 308].includes(response.statusCode)) return response;
      const location = this.findHeader(response.headers, 'location');
      if (!location) return response;
      let target: url.URL;
      let previous: url.URL;
      try {
        target = new url.URL(location, current.url);
        previous = new url.URL(current.url);
      } catch (_) {
        return { ...response, success: false, error: '媒体重定向地址无效' };
      }
      if (!['http:', 'https:'].includes(target.protocol) || target.username || target.password) {
        return { ...response, success: false, error: '媒体重定向只支持不含用户凭据的 HTTP(S) 地址' };
      }
      if (hop === 8 || visited.includes(target.href)) {
        return { ...response, success: false, error: '媒体重定向循环或超过 8 次' };
      }
      if (!['GET', 'HEAD'].includes(current.method.toUpperCase())) {
        return { ...response, success: false, error: '带自定义头的媒体重定向仅支持 GET/HEAD' };
      }
      const headers: Record<string, string> = {};
      const crossed = target.origin !== previous.origin;
      for (const name of Object.keys(current.headers)) {
        if (!crossed || !scoped.includes(name.toLowerCase())) headers[name] = current.headers[name];
      }
      current = { ...current, url: target.href, headers: headers,
        useCookieJar: crossed ? false : current.useCookieJar };
      visited.push(target.href);
    }
    return { url: current.url, statusCode: 0, headers: {}, data: new Uint8Array(), success: false,
      error: '媒体重定向超过 8 次' };
  }

  private async executeBinaryAttempt(req: HttpRequest, limit: number): Promise<HttpBinaryResponse> {
    const forceHttp1 = HttpProtocolPolicy.prefersHttp1(req.url);
    const response = await this.executeBinaryWithProtocol(req, limit, forceHttp1);
    if (!response.success && forceHttp1) HttpProtocolPolicy.forget(req.url);
    if (!response.success && !forceHttp1 && HttpProtocolPolicy.mayRetry(req.url, req.method, response.error || '')) {
      console.info('[HttpClient] binary transport failed; trying HTTP/1.1 once:', this.hostForLog(req.url));
      const retry = await this.executeBinaryWithProtocol(req, limit, true);
      if (retry.success) HttpProtocolPolicy.rememberSuccess(req.url);
      return retry;
    }
    return response;
  }

  private async executeBinaryWithProtocol(req: HttpRequest, maxResponseBytes: number,
    forceHttp1: boolean): Promise<HttpBinaryResponse> {
    if (req.deadlineAt && Date.now() >= req.deadlineAt) {
      return { url: req.url, statusCode: 0, headers: {}, data: new Uint8Array(), success: false, error: '请求超时 (2300028)' };
    }
    if (req.cancelCheck && req.cancelCheck()) {
      return { url: req.url, statusCode: 0, headers: {}, data: new Uint8Array(), success: false,
        error: HttpClient.CANCELLED_ERROR };
    }
    const client = http.createHttp();
    this.activeClients.add(client);
    const manualRedirects = !!req.protectedHeaderNames?.length;
    const destination = new HttpFinalUrlObserver(client, manualRedirects);
    if (req.protectedHeaderNames?.length && !destination.attached) {
      this.activeClients.delete(client);
      try { client.destroy(); } catch (_) { }
      return { url: req.url, statusCode: 0, headers: {}, data: new Uint8Array(), success: false,
        error: '自定义媒体请求头需要支持请求拦截的系统（API 22+）' };
    }
    let expired = false;
    const deadlineTimer = req.deadlineAt ? setTimeout((): void => {
      expired = true;
      try { client.destroy(); } catch (_) { }
    }, Math.max(1, req.deadlineAt - Date.now())) : -1;
    let cancelTimer: number = -1;
    let cancelled = false;
    if (req.cancelCheck) {
      cancelTimer = setInterval((): void => {
        if (!cancelled && req.cancelCheck && req.cancelCheck()) {
          cancelled = true;
          try { client.destroy(); } catch (_) { }
        }
      }, 50);
    }
    try {
      const headers: Record<string, string> = this.requestHeaders(req.headers);
      const requestData = this.requestData(req);
      this.applyRequestCookies(req, headers);
      const options: http.HttpRequestOptions = {
        method: this.resolveMethod(req.method),
        header: headers,
        extraData: requestData,
        connectTimeout: this.timeoutFor(req, req.connectTimeout),
        readTimeout: this.timeoutFor(req, req.readTimeout),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        maxLimit: maxResponseBytes
      };
      this.applyTlsTrust(options, req.url);
      if (forceHttp1) options.usingProtocol = http.HttpProtocol.HTTP1_1;
      const transportStartedAt = Date.now();
      const resp = await client.request(req.url, options);
      if (expired || (req.deadlineAt && Date.now() >= req.deadlineAt)) throw new Error('请求超时 (2300028)');
      if (cancelled || (req.cancelCheck && req.cancelCheck())) {
        return { url: req.url, statusCode: 0, headers: {}, data: new Uint8Array(), success: false,
          error: HttpClient.CANCELLED_ERROR };
      }
      this.endTransportTiming(req, transportStartedAt, forceHttp1, resp);
      const responseHeaders = (resp.header || {}) as Record<string, string>;
      const setCookie = this.findHeader(responseHeaders, 'set-cookie');
      if (setCookie && req.useCookieJar !== false) {
        CookieStore.forSource(req.cookieSource).setCookies(manualRedirects ? req.url : destination.url || req.url, setCookie);
        CookieStore.forSource(req.cookieSource).saveAsync();
      }
      // A stopped redirect can have no result at all. Its headers, not its body,
      // drive the next hop; do not feed an empty value into the platform encoder.
      if (manualRedirects && [301, 302, 303, 307, 308].includes(resp.responseCode)) {
        return { url: req.url, finalUrl: req.url, statusCode: resp.responseCode,
          headers: responseHeaders, data: new Uint8Array(), success: false };
      }
      const data = resp.result instanceof ArrayBuffer ?
        new Uint8Array(resp.result as ArrayBuffer) :
        (resp.result ? new util.TextEncoder().encodeInto(String(resp.result)) : new Uint8Array());
      if (data.byteLength > maxResponseBytes) {
        return {
          url: req.url,
          statusCode: resp.responseCode,
          headers: responseHeaders,
          data: new Uint8Array(),
          success: false,
          error: `response too large: >${maxResponseBytes}`
        };
      }
      return {
        url: manualRedirects ? req.url : destination.url || req.url,
        finalUrl: manualRedirects ? req.url : destination.url,
        statusCode: resp.responseCode,
        headers: responseHeaders,
        data: data,
        success: resp.responseCode >= 200 && resp.responseCode < 300
      };
    } catch (e) {
      return {
        url: req.url,
        statusCode: 0,
        headers: {},
        data: new Uint8Array(),
        success: false,
        error: expired ? '请求超时 (2300028)' :
          (cancelled ? HttpClient.CANCELLED_ERROR : this.decorateTlsError(req.url, this.describeError(e as Object)))
      };
    } finally {
      if (deadlineTimer >= 0) clearTimeout(deadlineTimer);
      if (cancelTimer >= 0) clearInterval(cancelTimer);
      this.activeClients.delete(client);
      try { client.destroy(); } catch (_) { }
    }
  }

  cancelAll(): void {
    this.activeClients.forEach((client: http.HttpRequest) => {
      try {
        client.destroy();
      } catch (e) {
      }
    });
    this.activeClients.clear();
  }

  private resolveMethod(method: string): http.RequestMethod {
    switch (method.toUpperCase()) {
      case 'POST': return http.RequestMethod.POST;
      case 'PUT': return http.RequestMethod.PUT;
      case 'DELETE': return http.RequestMethod.DELETE;
      case 'HEAD': return http.RequestMethod.HEAD;
      default: return http.RequestMethod.GET;
    }
  }

  private requestData(req: HttpRequest): string | ArrayBuffer {
    const method = (req.method || 'GET').toUpperCase();
    if (method === 'GET' || method === 'HEAD') return '';
    return req.bodyBytes || req.body || '';
  }

  private findHeader(headers: Record<string, string>, name: string): string {
    const lower = name.toLowerCase();
    for (const key in headers) {
      if (key.toLowerCase() === lower) return String(headers[key] || '');
    }
    return '';
  }

  private buildResponse(req: HttpRequest, responseCode: number, responseHeaders: Record<string, string>,
    result: string | Object): HttpResponse {
    const decodeStartedAt = Date.now();
    const setCookie = this.findHeader(responseHeaders, 'set-cookie');
    if (setCookie && req.useCookieJar !== false) {
      CookieStore.forSource(req.cookieSource).setCookies(req.url, setCookie);
      CookieStore.forSource(req.cookieSource).saveAsync();
    }
    const charset = req.charset || this.responseCharset(responseHeaders);
    const body = this.decodeBody(result, charset);
    const finalBody = req.charset ? body : this.decodeBodyWithMetaCharset(result, body, charset);
    this.endTiming(req, 'http-cookie-decode', decodeStartedAt);
    return {
      url: req.url,
      statusCode: responseCode,
      headers: responseHeaders,
      body: finalBody,
      success: responseCode >= 200 && responseCode < 300
    };
  }

  private mergeArrayBuffers(chunks: ArrayBuffer[], totalBytes: number): ArrayBuffer {
    if (chunks.length === 1) return chunks[0];
    const merged = new Uint8Array(totalBytes);
    let offset = 0;
    for (const chunk of chunks) {
      const bytes = new Uint8Array(chunk);
      merged.set(bytes, offset);
      offset += bytes.byteLength;
    }
    return merged.buffer as ArrayBuffer;
  }

  private responseCharset(headers: Record<string, string>): string {
    const contentType = this.findHeader(headers, 'content-type');
    const match = contentType.match(/charset\s*=\s*["']?([^;\s"']+)/i);
    return match ? match[1].trim().toLowerCase() : 'utf-8';
  }

  private decodeBody(result: string | Object, charset?: string): string {
    if (typeof result === 'string') return result as string;
    if (result instanceof ArrayBuffer) {
      try {
        return util.TextDecoder.create(this.normalizeCharset(charset || 'utf-8'))
          .decodeWithStream(new Uint8Array(result as ArrayBuffer), { stream: false });
      } catch (_) {
        return String(result || '');
      }
    }
    return String(result || '');
  }

  private decodeBodyWithMetaCharset(result: string | Object, decoded: string, charset: string): string {
    if (!(result instanceof ArrayBuffer)) return decoded;
    const metaCharset = this.findMetaCharset(decoded);
    if (!metaCharset || this.normalizeCharset(metaCharset) === this.normalizeCharset(charset || 'utf-8')) {
      return decoded;
    }
    return this.decodeBody(result, metaCharset);
  }

  private findMetaCharset(html: string): string {
    const head = (html || '').substring(0, 4096);
    const direct = head.match(/<meta[^>]+charset\s*=\s*["']?\s*([A-Za-z0-9_-]+)/i);
    if (direct) return direct[1].trim().toLowerCase();
    const contentType = head.match(/<meta[^>]+http-equiv\s*=\s*["']?content-type["']?[^>]+content\s*=\s*["'][^"']*charset\s*=\s*([^;"'\s>]+)/i);
    return contentType ? contentType[1].trim().toLowerCase() : '';
  }

  private normalizeCharset(charset: string): string {
    const value = charset.toLowerCase().replace(/["']/g, '').trim();
    if (value === 'gb2312' || value === 'gbk') return 'gb18030';
    return value || 'utf-8';
  }

  private describeError(error: Object): string {
    if (error instanceof Error && this.isReadableErrorText(error.message)) return error.message;
    if (typeof error === 'string' && this.isReadableErrorText(error as string)) return error as string;
    if (error && typeof error === 'object') {
      const record = error as Record<string, Object>;
      const rawMessage = record['message'] || record['msg'] || record['reason'];
      let message = typeof rawMessage === 'string' ? (rawMessage as string).trim() : '';
      if (!this.isReadableErrorText(message) && rawMessage && typeof rawMessage === 'object') {
        const nested = rawMessage as Record<string, Object>;
        message = String(nested['message'] || nested['msg'] || nested['reason'] || '').trim();
      }
      const code = String(record['code'] || record['errorCode'] || '').trim();
      if (this.isReadableErrorText(message)) return code ? `${message} (${code})` : message;
      try {
        const json = JSON.stringify(error);
        if (json && json !== '{}') return json;
      } catch (_) {
      }
    }
    const fallback = String(error || '').trim();
    return this.isReadableErrorText(fallback) ? fallback : '未知网络错误';
  }

  private isReadableErrorText(value: string): boolean {
    const text = (value || '').trim().toLowerCase();
    return !!text && !text.includes('[object object]') && text !== 'object object' && text !== '{}';
  }

  private shouldRetryTimeout(req: HttpRequest, error: string): boolean {
    const method = (req.method || 'GET').toUpperCase();
    if (method !== 'GET' && method !== 'HEAD') return false;
    return /2300028|operation\s+timeout|timed?\s*out|timeout/i.test(error || '');
  }

  private applyTlsTrust(options: http.HttpRequestOptions, url: string): void {
    if (TlsTrustStore.isTrustedUrl(url)) {
      options.remoteValidation = 'skip';
    }
  }

  private decorateTlsError(url: string, error: string): string {
    if (!TlsTrustStore.isCertificateError(error) || /证书主机\s*[：:]/.test(error || '')) return error;
    const host = TlsTrustStore.hostFromUrl(url);
    return host ? `证书校验失败（证书主机：${host}）：${error}` : error;
  }

  private hostForLog(url: string): string {
    const match = (url || '').match(/^https?:\/\/([^/:?#]+)/i);
    return match && match[1] ? match[1] : '(unknown host)';
  }
}
