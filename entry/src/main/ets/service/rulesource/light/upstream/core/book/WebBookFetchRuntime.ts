import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { CookieStore } from '../http/CookieStore';
import { WebJsAwaitScript } from './WebJsAwaitScript';

export interface WebBookFetchRequest {
  cookieSource?: string;
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
  webJs?: string;
  /**
   * When set, `webJs` is re-run until its result matches this pattern or `webJsMaxAttempts` is
   * reached. Players often assign their stream address some time after the DOM has settled.
   */
  webJsAcceptPattern?: string;
  webJsMaxAttempts?: number;
  timeoutMs?: number;
  maxResponseBytes?: number;
}

export interface WebBookFetchResponse {
  url: string;
  statusCode: number;
  headers: Record<string, string>;
  body: string;
  success: boolean;
  error?: string;
}

class WebBookFetchTask {
  request: WebBookFetchRequest = { url: '', method: 'GET', headers: {} };
  resolve: ((value: WebBookFetchResponse) => void) | null = null;
  timeoutId: number = -1;
  inspectId: number = -1;
  stableCount: number = 0;
  lastSignature: string = '';
  pageEnded: boolean = false;
  webJsAttempts: number = 0;
  /** Bumped per webJs run so callbacks of a superseded run (page navigated, retry) are ignored. */
  webJsRun: number = 0;
}

/**
 * Browser-backed transport for rules that explicitly declare `webView: true`.
 * It only opens source-owned URLs, executes normal page JavaScript and returns the
 * resulting DOM (or source-owned webJs output); it contains no site-specific rules.
 */
export class WebBookFetchRuntime {
  private static instance: WebBookFetchRuntime | null = null;
  private controller: webview.WebviewController | null = null;
  private ready: boolean = false;
  private static readonly WEB_JS_RETRY_INTERVAL_MS: number = 500;
  private static readonly WEB_JS_AWAIT_POLL_MS: number = 100;
  private webJsSlotSequence: number = 0;
  private active: WebBookFetchTask | null = null;
  private queue: WebBookFetchTask[] = [];

  static get(): WebBookFetchRuntime {
    if (!WebBookFetchRuntime.instance) WebBookFetchRuntime.instance = new WebBookFetchRuntime();
    return WebBookFetchRuntime.instance;
  }

  attach(controller: webview.WebviewController): void {
    if (this.controller === controller) {
      this.recoverIdleController();
      return;
    }
    // A routed page can attach its host before the previous page has disappeared. Preserve the
    // in-flight request and restart it on the new controller; failing it here creates a race where
    // a detail request submitted by aboutToAppear is cancelled by that very detail page's host.
    const migratingTask = this.active;
    if (migratingTask) {
      if (migratingTask.timeoutId >= 0) clearTimeout(migratingTask.timeoutId);
      if (migratingTask.inspectId >= 0) clearTimeout(migratingTask.inspectId);
      migratingTask.timeoutId = -1;
      migratingTask.inspectId = -1;
      migratingTask.pageEnded = false;
      migratingTask.stableCount = 0;
      migratingTask.lastSignature = '';
      migratingTask.webJsRun++;
      this.active = null;
      this.queue.unshift(migratingTask);
    }
    this.controller = controller;
    // onControllerAttached means loadUrl/postUrl are already usable. Waiting for the initial
    // about:blank onPageEnd introduces a cold-start race and is unnecessary for this transport.
    this.ready = true;
    this.runNext();
  }

  detach(controller: webview.WebviewController): void {
    if (this.controller !== controller) return;
    if (this.active) this.finishActive(this.failure(this.active.request.url, '网页抓取环境已关闭'));
    while (this.queue.length > 0) {
      const task = this.queue.shift();
      if (task?.resolve) task.resolve(this.failure(task.request.url, '网页抓取环境已关闭'));
    }
    this.controller = null;
    this.ready = false;
  }

  setReady(ready: boolean, controller: webview.WebviewController): void {
    if (this.controller !== controller) return;
    this.ready = ready;
    if (ready) this.runNext();
  }

  onPageBegin(controller: webview.WebviewController): void {
    if (this.controller !== controller || !this.active) return;
    this.active.pageEnded = false;
    this.active.stableCount = 0;
    this.active.lastSignature = '';
  }

  onPageEnd(controller: webview.WebviewController): void {
    if (this.controller !== controller) return;
    if (!this.active) {
      this.ready = true;
      this.runNext();
      return;
    }
    this.active.pageEnded = true;
    this.scheduleInspect(this.active, 250);
  }

  isAvailable(): boolean { return !!this.controller && this.ready; }

  isAttached(): boolean { return !!this.controller; }

  async waitUntilAttached(timeoutMs: number = 8000): Promise<boolean> {
    if (this.isAttached()) return true;
    const startedAt = Date.now();
    while (Date.now() - startedAt < Math.max(100, timeoutMs)) {
      await new Promise<void>((resolve) => setTimeout(resolve, 50));
      if (this.isAttached()) return true;
    }
    return this.isAttached();
  }

  async waitUntilAvailable(timeoutMs: number = 2500): Promise<boolean> {
    this.recoverIdleController();
    if (this.isAvailable()) return true;
    const startedAt = Date.now();
    while (Date.now() - startedAt < Math.max(100, timeoutMs)) {
      await new Promise<void>((resolve) => setTimeout(resolve, 50));
      this.recoverIdleController();
      if (this.isAvailable()) return true;
    }
    this.recoverIdleController();
    return this.isAvailable();
  }

  fetch(request: WebBookFetchRequest): Promise<WebBookFetchResponse> {
    return new Promise<WebBookFetchResponse>((resolve) => {
      const url = String(request.url || '').trim();
      const method = String(request.method || 'GET').toUpperCase();
      if (!/^https?:\/\//i.test(url)) {
        resolve(this.failure(url, 'WebView 仅支持 http/https 地址'));
        return;
      }
      if (method !== 'GET' && method !== 'POST') {
        resolve(this.failure(url, `WebView 暂不支持 ${method} 请求`));
        return;
      }
      const acceptPattern = String(request.webJsAcceptPattern || '');
      if (acceptPattern) {
        try {
          new RegExp(acceptPattern, 'i');
        } catch (_) {
          resolve(this.failure(url, `网页等待条件不是有效的正则：${acceptPattern}`));
          return;
        }
      }
      if (this.queue.length >= 32) {
        resolve(this.failure(url, '网页抓取任务过多，请稍后重试'));
        return;
      }
      const task = new WebBookFetchTask();
      task.request = request;
      task.resolve = resolve;
      this.queue.push(task);
      this.recoverIdleController();
      this.runNext();
    });
  }

  private recoverIdleController(): void {
    if (!this.controller || this.active || this.ready) return;
    // Returning to about:blank normally restores ready in onPageEnd. Some ArkWeb lifecycle
    // transitions omit that callback; an attached controller with no active task is safe to reuse.
    this.ready = true;
    this.runNext();
  }

  private runNext(): void {
    if (this.active || !this.controller || !this.ready || this.queue.length === 0) return;
    const task = this.queue.shift();
    if (!task) return;
    this.active = task;
    this.ready = false;
    const timeoutMs = Math.max(3000, Math.min(60000, task.request.timeoutMs || 20000));
    task.timeoutId = setTimeout((): void => {
      if (this.active === task) {
        this.finishActive(this.failure(task.request.url, `WebView 请求超时（${timeoutMs}ms）`));
      }
    }, timeoutMs);
    try {
      const userAgent = this.headerValue(task.request.headers, 'user-agent');
      if (userAgent) this.controller.setCustomUserAgent(userAgent);
      const cookie = this.headerValue(task.request.headers, 'cookie');
      if (cookie) CookieStore.forSource(task.request.cookieSource).setCookies(task.request.url, cookie);
      if (String(task.request.method || 'GET').toUpperCase() === 'POST') {
        const bytes = new util.TextEncoder().encodeInto(task.request.body || '');
        this.controller.postUrl(task.request.url, bytes.buffer as ArrayBuffer);
      } else {
        this.controller.loadUrl(task.request.url, this.webHeaders(task.request.headers));
      }
    } catch (error) {
      this.finishActive(this.failure(task.request.url, this.errorMessage(error as Object)));
    }
  }

  private scheduleInspect(task: WebBookFetchTask, delayMs: number): void {
    if (this.active !== task) return;
    if (task.inspectId >= 0) clearTimeout(task.inspectId);
    task.inspectId = setTimeout((): void => this.inspect(task), delayMs);
  }

  private inspect(task: WebBookFetchTask): void {
    const controller = this.controller;
    if (this.active !== task || !controller || !task.pageEnded) return;
    const script = `(function(){return JSON.stringify({url:String(location.href||''),title:String(document.title||''),` +
      `ready:String(document.readyState||''),html:String(document.documentElement?document.documentElement.outerHTML:'')})})()`;
    controller.runJavaScript(script).then((raw: string): void => {
      if (this.active !== task) return;
      const snapshot = this.parseSnapshot(raw);
      if (!snapshot || !snapshot['html']) {
        this.scheduleInspect(task, 400);
        return;
      }
      const html = snapshot['html'];
      const snapshotUrl = String(snapshot['url'] || '').trim();
      // A newly attached routed-page host first completes its own about:blank navigation. That
      // callback can arrive after the pending request has migrated to it; never mistake the
      // 39-byte empty document for the requested source response.
      if (!/^https?:\/\//i.test(snapshotUrl)) {
        this.scheduleInspect(task, 400);
        return;
      }
      const maxBytes = task.request.maxResponseBytes || 0;
      if (maxBytes > 0 && this.utf8Length(html) > maxBytes) {
        this.finishActive(this.failure(snapshot['url'] || task.request.url, `response too large: >${maxBytes}`));
        return;
      }
      const signature = `${snapshot['url']}|${snapshot['title']}|${snapshot['ready']}|${html.length}|` +
        `${html.substring(0, 160)}|${html.substring(Math.max(0, html.length - 160))}`;
      task.stableCount = signature === task.lastSignature ? task.stableCount + 1 : 0;
      task.lastSignature = signature;
      if (task.stableCount < 2 || snapshot['ready'] !== 'complete') {
        this.scheduleInspect(task, 400);
        return;
      }
      this.resolveBody(task, snapshot['url'] || task.request.url, html);
    }).catch((error: Error): void => {
      if (this.active === task) this.finishActive(this.failure(task.request.url, this.errorMessage(error)));
    });
  }

  private resolveBody(task: WebBookFetchTask, finalUrl: string, html: string): void {
    const controller = this.controller;
    const webJs = String(task.request.webJs || '').trim();
    if (!controller || !webJs) {
      this.finishActive(this.success(finalUrl, html));
      return;
    }
    const run = ++task.webJsRun;
    const slot = `__legadoWebJs${++this.webJsSlotSequence}`;
    controller.runJavaScript(WebJsAwaitScript.start(webJs, slot)).then((raw: string): void => {
      if (this.active !== task || task.webJsRun !== run) return;
      const value = this.unwrapJavaScriptResult(raw);
      if (value === WebJsAwaitScript.BLOCKED) {
        // The page's CSP forbids eval; nothing has run yet, so execute the script as written.
        controller.runJavaScript(webJs).then((plain: string): void => {
          if (this.active !== task || task.webJsRun !== run) return;
          this.acceptWebJsValue(task, finalUrl, html, this.unwrapJavaScriptResult(plain));
        }).catch((error: Error): void => this.failWebJs(task, run, finalUrl, this.errorMessage(error)));
        return;
      }
      if (value === WebJsAwaitScript.PENDING) {
        this.scheduleWebJsPoll(task, run, slot, finalUrl, html);
        return;
      }
      this.acceptWebJsValue(task, finalUrl, html, value);
    }).catch((error: Error): void => this.failWebJs(task, run, finalUrl, this.errorMessage(error)));
  }

  /** Waits for a Promise returned by webJs; the overall request timeout bounds the polling. */
  private scheduleWebJsPoll(task: WebBookFetchTask, run: number, slot: string, finalUrl: string, html: string): void {
    task.inspectId = setTimeout((): void => {
      const controller = this.controller;
      // While the page navigates, inspect() restarts webJs once the new document has settled.
      if (this.active !== task || task.webJsRun !== run || !controller || !task.pageEnded) return;
      controller.runJavaScript(WebJsAwaitScript.poll(slot)).then((raw: string): void => {
        if (this.active !== task || task.webJsRun !== run) return;
        const value = this.unwrapJavaScriptResult(raw);
        if (value === WebJsAwaitScript.PENDING) {
          this.scheduleWebJsPoll(task, run, slot, finalUrl, html);
        } else if (value === WebJsAwaitScript.LOST) {
          // The document that owned the Promise was replaced; start over on the current one.
          task.webJsRun++;
          this.scheduleInspect(task, 400);
        } else if (value.startsWith(WebJsAwaitScript.FAILED_PREFIX)) {
          this.failWebJs(task, run, finalUrl, value.substring(WebJsAwaitScript.FAILED_PREFIX.length));
        } else {
          this.acceptWebJsValue(task, finalUrl, html, value);
        }
      }).catch((error: Error): void => this.failWebJs(task, run, finalUrl, this.errorMessage(error)));
    }, WebBookFetchRuntime.WEB_JS_AWAIT_POLL_MS);
  }

  private acceptWebJsValue(task: WebBookFetchTask, finalUrl: string, html: string, value: string): void {
    task.webJsAttempts++;
    if (this.shouldRetryWebJs(task, value)) {
      // The overall request timeout still bounds the polling.
      task.inspectId = setTimeout((): void => this.resolveBody(task, finalUrl, html),
        WebBookFetchRuntime.WEB_JS_RETRY_INTERVAL_MS);
      return;
    }
    if (!this.matchesWebJs(task, value)) {
      // The page did load: keep it (and a non-zero status) so callers judge a challenge or login gate
      // by its content instead of treating every unmet wait like a network failure.
      this.finishActive({ url: finalUrl, statusCode: 200, headers: {}, body: html, success: false,
        error: '网页等待条件未满足，未取得可用内容' });
      return;
    }
    this.finishActive(this.success(finalUrl, value && value !== 'undefined' && value !== 'null' ? value : html));
  }

  private failWebJs(task: WebBookFetchTask, run: number, finalUrl: string, message: string): void {
    if (this.active !== task || task.webJsRun !== run) return;
    this.finishActive(this.failure(finalUrl, `webJs 执行失败: ${message}`));
  }

  private shouldRetryWebJs(task: WebBookFetchTask, value: string): boolean {
    // Honor the declared wait duration; the request timer remains the hard limit.
    const maxAttempts = Math.max(1, Math.min(120, Math.floor(task.request.webJsMaxAttempts || 1)));
    return task.webJsAttempts < maxAttempts && !this.matchesWebJs(task, value);
  }

  private matchesWebJs(task: WebBookFetchTask, value: string): boolean {
    const pattern = String(task.request.webJsAcceptPattern || '');
    if (!pattern) return true;
    try {
      return new RegExp(pattern, 'i').test(value);
    } catch (_) {
      return false;
    }
  }

  private finishActive(response: WebBookFetchResponse): void {
    const task = this.active;
    if (!task) return;
    this.active = null;
    if (task.timeoutId >= 0) clearTimeout(task.timeoutId);
    if (task.inspectId >= 0) clearTimeout(task.inspectId);
    if (task.resolve) task.resolve(response);
    try { this.controller?.stop(); } catch (_) {}
    try { this.controller?.loadUrl('about:blank'); } catch (_) {}
    setTimeout((): void => this.runNext(), 0);
  }

  private webHeaders(source: Record<string, string>): webview.WebHeader[] {
    const result: webview.WebHeader[] = [];
    for (const key of Object.keys(source || {})) {
      const normalized = key.toLowerCase();
      if (normalized === 'user-agent' || normalized === 'cookie' || normalized === 'connection' ||
        normalized === 'host' || normalized === 'content-length') continue;
      result.push({ headerKey: key, headerValue: String(source[key] || '') });
    }
    return result;
  }

  private headerValue(headers: Record<string, string>, name: string): string {
    for (const key of Object.keys(headers || {})) {
      if (key.toLowerCase() === name) return String(headers[key] || '');
    }
    return '';
  }

  private parseSnapshot(raw: string): Record<string, string> | null {
    try { return JSON.parse(this.unwrapJavaScriptResult(raw)) as Record<string, string>; } catch (_) { return null; }
  }

  private unwrapJavaScriptResult(raw: string): string {
    const value = String(raw || '');
    if (value.startsWith('"') && value.endsWith('"')) {
      try { return String(JSON.parse(value)); } catch (_) {}
    }
    return value;
  }

  private utf8Length(value: string): number {
    let length = 0;
    for (let i = 0; i < value.length; i++) {
      const code = value.charCodeAt(i);
      if (code < 0x80) length += 1;
      else if (code < 0x800) length += 2;
      else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < value.length) { length += 4; i++; }
      else length += 3;
    }
    return length;
  }

  private success(url: string, body: string): WebBookFetchResponse {
    return { url: url, statusCode: 200, headers: {}, body: body, success: true };
  }

  private failure(url: string, error: string): WebBookFetchResponse {
    return { url: url, statusCode: 0, headers: {}, body: '', success: false, error: error };
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error || 'unknown error');
  }
}
