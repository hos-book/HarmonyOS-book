import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { CookieStore } from '../http/CookieStore';
import { WebJsAwaitScript } from './WebJsAwaitScript';

export interface WebBookFetchRequest {
  requestId?: string;
  /** Explicit native selector: may be evaluated once the new DOM is interactive. */
  webWaitFor?: string;
  cancelCheck?: () => boolean;
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
  /** Shared deadline includes time queued behind another page. */
  deadlineAt?: number;
  maxResponseBytes?: number;
}

export interface WebBookFetchResponse {
  bodyIsSnapshot?: boolean;
  snapshotTruncated?: boolean;
  waitStage?: string;
  errorCode?: string;
  errorStage?: string;
  statusCodeAvailable?: boolean;
  queueMs?: number;
  renderMs?: number;
  url: string;
  statusCode: number;
  headers: Record<string, string>;
  body: string;
  success: boolean;
  error?: string;
}

class WebBookFetchTask {
  navigation: number = 0;
  navigationUrl: string = '';
  pageStarted: boolean = false;
  earlyProbeSafe: boolean = false;
  documentToken: string = '';
  snapshot: string = '';
  snapshotUrl: string = '';
  snapshotTruncated: boolean = false;
  waitStage: string = 'load';
  queuedAt: number = Date.now();
  startedAt: number = 0;
  cancelId: number = -1;
  request: WebBookFetchRequest = { url: '', method: 'GET', headers: {} };
  resolve: ((value: WebBookFetchResponse) => void) | null = null;
  timeoutId: number = -1;
  deadlineId: number = -1;
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
  private controllers: webview.WebviewController[] = [];
  private ready: boolean = false;
  private static readonly WEB_JS_RETRY_INTERVAL_MS: number = 500;
  private static readonly WEB_JS_AWAIT_POLL_MS: number = 100;
  private webJsSlotSequence: number = 0;
  private documentSequence: number = 0;
  private active: WebBookFetchTask | null = null;
  private queue: WebBookFetchTask[] = [];

  static get(): WebBookFetchRuntime {
    if (!WebBookFetchRuntime.instance) WebBookFetchRuntime.instance = new WebBookFetchRuntime();
    return WebBookFetchRuntime.instance;
  }

  attach(controller: webview.WebviewController): void {
    this.controllers = this.controllers.filter((item: webview.WebviewController): boolean => item !== controller);
    this.controllers.push(controller);
    if (this.controller === controller) {
      this.recoverIdleController();
      return;
    }
    // A routed page can attach its host before the previous page has disappeared. Preserve the
    // in-flight request and restart it on the new controller; failing it here creates a race where
    // a detail request submitted by aboutToAppear is cancelled by that very detail page's host.
    const migratingTask = this.active;
    if (migratingTask) {
      try { this.controller?.stop(); } catch (_) {}
      if (migratingTask.request.method.toUpperCase() !== 'GET' || migratingTask.request.body) {
        this.finishActive(this.failure(migratingTask.request.url, '网页宿主已切换，请重新发起操作', 'WEB_HOST_CHANGED', 'host'));
      } else {
        if (migratingTask.timeoutId >= 0) clearTimeout(migratingTask.timeoutId);
        if (migratingTask.inspectId >= 0) clearTimeout(migratingTask.inspectId);
        migratingTask.timeoutId = -1;
        migratingTask.inspectId = -1;
        migratingTask.pageEnded = false;
        migratingTask.stableCount = 0;
        migratingTask.lastSignature = '';
        this.resetDocument(migratingTask);
        migratingTask.earlyProbeSafe = false;
        migratingTask.webJsRun++;
        this.active = null;
        this.queue.unshift(migratingTask);
      }
    }
    this.controller = controller;
    // onControllerAttached means loadUrl/postUrl are already usable. Waiting for the initial
    // about:blank onPageEnd introduces a cold-start race and is unnecessary for this transport.
    this.ready = true;
    this.runNext();
  }

  detach(controller: webview.WebviewController): void {
    this.controllers = this.controllers.filter((item: webview.WebviewController): boolean => item !== controller);
    if (this.controller !== controller) return;
    const previous = this.controllers[this.controllers.length - 1];
    if (previous) {
      this.attach(previous);
      return;
    }
    if (this.active) this.finishActive(this.failure(this.active.request.url, '网页抓取环境已关闭', 'WEB_HOST_CLOSED', 'host'));
    while (this.queue.length > 0) {
      const task = this.queue.shift();
      if (task && task.deadlineId >= 0) clearTimeout(task.deadlineId);
      if (task && task.cancelId >= 0) clearInterval(task.cancelId);
      if (task?.resolve) task.resolve(this.failure(task.request.url, '网页抓取环境已关闭', 'WEB_HOST_CLOSED', 'host'));
    }
    this.controller = null;
    this.ready = false;
  }

  setReady(ready: boolean, controller: webview.WebviewController): void {
    if (this.controller !== controller) return;
    this.ready = ready;
    if (ready) this.runNext();
  }

  onPageBegin(controller: webview.WebviewController, url: string = ''): void {
    if (this.controller !== controller || !this.active) return;
    if (url && !/^https?:\/\//i.test(url)) return;
    this.resetDocument(this.active);
    this.active.pageStarted = true;
    this.active.navigationUrl = url || this.active.request.url;
    this.active.pageEnded = false;
    this.active.stableCount = 0;
    this.active.lastSignature = '';
    if (this.active.request.webWaitFor) this.scheduleInspect(this.active, 100);
  }

  onPageEnd(controller: webview.WebviewController, url: string = ''): void {
    if (this.controller !== controller) return;
    if (!this.active) {
      this.ready = true;
      this.runNext();
      return;
    }
    if (url && (!/^https?:\/\//i.test(url) ||
      (this.active.navigationUrl && url !== this.active.navigationUrl))) return;
    this.active.pageStarted = true;
    if (!this.active.navigationUrl) this.active.navigationUrl = url || this.active.request.url;
    this.active.pageEnded = true;
    // Do not interrupt a selector/Promise already running from the early DOM probe.
    if (this.active.waitStage === 'load' || this.active.waitStage === 'stability') this.scheduleInspect(this.active, 250);
  }

  private resetDocument(task: WebBookFetchTask): void {
    task.navigation++;
    task.webJsRun++;
    task.pageStarted = false;
    task.pageEnded = false;
    task.navigationUrl = '';
    task.snapshot = '';
    task.snapshotUrl = '';
    task.snapshotTruncated = false;
    task.waitStage = 'load';
  }

  /** Called by the outer HTTP deadline too, so it cannot replace the runtime's diagnostics. */
  timeoutRequest(requestId: string): WebBookFetchResponse | null {
    if (this.active?.request.requestId === requestId) {
      const response = this.taskResponse(this.active, this.failure(this.active.request.url,
        '网页请求总等待超时 (2300028)', 'REQUEST_DEADLINE', 'deadline'));
      this.finishActive(response);
      return response;
    }
    const index = this.queue.findIndex((task: WebBookFetchTask): boolean => task.request.requestId === requestId);
    if (index < 0) return null;
    const task = this.queue.splice(index, 1)[0];
    if (task.deadlineId >= 0) clearTimeout(task.deadlineId);
    if (task.cancelId >= 0) clearInterval(task.cancelId);
    const response = this.taskResponse(task, this.failure(task.request.url,
      '网页抓取排队超时 (2300028)', 'WEB_QUEUE_TIMEOUT', 'queue'));
    task.resolve?.(response);
    return response;
  }

  isAvailable(): boolean { return !!this.controller && this.ready; }

  isAttached(): boolean { return !!this.controller; }

  async waitUntilAttached(timeoutMs: number = 8000, cancelled?: () => boolean): Promise<boolean> {
    if (this.isAttached()) return true;
    const startedAt = Date.now();
    while (Date.now() - startedAt < Math.max(100, timeoutMs)) {
      if (cancelled && cancelled()) return false;
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
      // Queueing and controller migration share one bounded budget, even for legacy callers.
      task.request = { ...request, deadlineAt: request.deadlineAt || Date.now() + Math.max(3000, Math.min(60000, request.timeoutMs || 20000)) };
      request = task.request;
      task.resolve = resolve;
      if (request.cancelCheck && request.cancelCheck()) {
        resolve(this.failure(url, '书源请求已取消', 'CANCELLED', 'cancel'));
        return;
      }
      if (request.deadlineAt) {
        if (Date.now() >= request.deadlineAt) {
          resolve(this.failure(url, '网页请求总等待超时 (2300028)', 'REQUEST_DEADLINE', 'deadline'));
          return;
        }
        task.deadlineId = setTimeout((): void => {
          const failed = this.failure(url, this.active === task ? '网页请求总等待超时 (2300028)' : '网页抓取排队超时 (2300028)',
            this.active === task ? 'REQUEST_DEADLINE' : 'WEB_QUEUE_TIMEOUT', this.active === task ? 'deadline' : 'queue');
          if (this.active === task) this.finishActive(failed);
          else {
            const index = this.queue.indexOf(task);
            if (index >= 0) {
              this.queue.splice(index, 1);
              if (task.cancelId >= 0) clearInterval(task.cancelId);
              task.resolve?.(this.taskResponse(task, failed));
            }
          }
        }, request.deadlineAt - Date.now());
      }
      if (request.cancelCheck) {
        task.cancelId = setInterval((): void => {
          if (!task.request.cancelCheck?.()) return;
          const failed = this.failure(url, '书源请求已取消', 'CANCELLED', 'cancel');
          if (this.active === task) this.finishActive(failed);
          else {
            const index = this.queue.indexOf(task);
            if (index >= 0) this.queue.splice(index, 1);
            clearInterval(task.cancelId);
            if (task.deadlineId >= 0) clearTimeout(task.deadlineId);
            task.resolve?.(this.taskResponse(task, failed));
          }
        }, 50);
      }
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
    if (task.request.deadlineAt && Date.now() >= task.request.deadlineAt) {
      if (task.deadlineId >= 0) clearTimeout(task.deadlineId);
      if (task.cancelId >= 0) clearInterval(task.cancelId);
      task.resolve?.(this.failure(task.request.url, '网页抓取排队超时 (2300028)', 'WEB_QUEUE_TIMEOUT', 'queue'));
      this.runNext();
      return;
    }
    this.active = task;
    if (!task.startedAt) task.startedAt = Date.now();
    if (task.request.cancelCheck?.()) {
      this.finishActive(this.failure(task.request.url, '书源请求已取消', 'CANCELLED', 'cancel'));
      return;
    }
    this.ready = false;
    const configuredTimeout = Math.max(3000, Math.min(60000, task.request.timeoutMs || 20000));
    const timeoutMs = task.request.deadlineAt ? Math.max(1, Math.min(configuredTimeout, task.request.deadlineAt - Date.now())) :
      configuredTimeout;
    const deadlineLimited = timeoutMs < configuredTimeout;
    task.timeoutId = setTimeout((): void => {
      if (this.active === task) {
        if (deadlineLimited) {
          this.finishActive(this.failure(task.request.url, '网页请求总等待超时 (2300028)', 'REQUEST_DEADLINE', 'deadline'));
          return;
        }
        this.finishActive(this.failure(task.request.url, task.webJsAttempts > 0 ? '网页等待条件未满足' : `网页加载超时（${timeoutMs}ms）`,
          task.webJsAttempts > 0 ? 'WEB_WAIT_UNMET' : 'WEB_LOAD_TIMEOUT', task.webJsAttempts > 0 ? 'selector' : 'load'));
      }
    }, timeoutMs);
    if (task.request.webWaitFor) {
      // Mark the old document before navigating. A same-URL reload must not satisfy the
      // selector using the previous document while the next navigation is still starting.
      task.documentToken = `fetch-${++this.documentSequence}`;
      const controller = this.controller;
      try {
        controller.runJavaScript(`globalThis.__legadoPreviousDocument=${JSON.stringify(task.documentToken)};''`)
        .then((): void => {
          if (this.active !== task || this.controller !== controller) return;
          task.earlyProbeSafe = true;
          this.navigate(task);
        }).catch((): void => {
          if (this.active === task && this.controller === controller) this.navigate(task);
        });
      } catch (_) {
        this.navigate(task);
      }
    } else {
      this.navigate(task);
    }
  }

  private navigate(task: WebBookFetchTask): void {
    if (this.active !== task || !this.controller) return;
    if (task.request.cancelCheck?.()) {
      this.finishActive(this.failure(task.request.url, '书源请求已取消', 'CANCELLED', 'cancel'));
      return;
    }
    if (task.request.deadlineAt && Date.now() >= task.request.deadlineAt) {
      this.finishActive(this.failure(task.request.url, '网页请求总等待超时 (2300028)', 'REQUEST_DEADLINE', 'deadline'));
      return;
    }
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
    if (this.active !== task || !controller || !task.pageStarted) return;
    if (!task.pageEnded && !task.earlyProbeSafe) {
      this.scheduleInspect(task, 400);
      return;
    }
    const navigation = task.navigation;
    const script = `(function(){return JSON.stringify({url:String(location.href||''),title:String(document.title||''),` +
      `stale:String(globalThis.__legadoPreviousDocument===${JSON.stringify(task.documentToken)}),` +
      `ready:String(document.readyState||''),html:String(document.documentElement?document.documentElement.outerHTML:'')})})()`;
    controller.runJavaScript(script).then((raw: string): void => {
      if (this.active !== task || this.controller !== controller || task.navigation !== navigation) return;
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
      if (!/^https?:\/\//i.test(snapshotUrl) || snapshot['stale'] === 'true' ||
        (task.navigationUrl && snapshotUrl !== task.navigationUrl)) {
        this.scheduleInspect(task, 400);
        return;
      }
      const maxBytes = task.request.maxResponseBytes || 0;
      if (maxBytes > 0 && this.utf8Length(html) > maxBytes) {
        this.finishActive(this.failure(snapshot['url'] || task.request.url, `response too large: >${maxBytes}`));
        return;
      }
      // At most 64K UTF-16 units (<=192 KiB UTF-8), and never more than the response limit.
      task.snapshot = html.substring(0, 65536);
      task.snapshotTruncated = task.snapshot.length < html.length;
      task.snapshotUrl = snapshotUrl;
      if (task.request.webWaitFor && task.earlyProbeSafe &&
        (snapshot['ready'] === 'interactive' || snapshot['ready'] === 'complete')) {
        this.resolveBody(task, snapshotUrl, html);
        return;
      }
      const signature = `${snapshot['url']}|${snapshot['title']}|${snapshot['ready']}|${html.length}|` +
        `${html.substring(0, 160)}|${html.substring(Math.max(0, html.length - 160))}`;
      task.stableCount = signature === task.lastSignature ? task.stableCount + 1 : 0;
      task.lastSignature = signature;
      task.waitStage = 'stability';
      if (!task.pageEnded || task.stableCount < 2 || snapshot['ready'] !== 'complete') {
        this.scheduleInspect(task, 400);
        return;
      }
      this.resolveBody(task, snapshot['url'] || task.request.url, html);
    }).catch((error: Error): void => {
      if (this.active === task && this.controller === controller && task.navigation === navigation) {
        this.finishActive(this.failure(task.request.url, this.errorMessage(error)));
      }
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
    task.waitStage = task.request.webWaitFor ? 'selector' : 'script';
    const slot = `__legadoWebJs${++this.webJsSlotSequence}`;
    controller.runJavaScript(WebJsAwaitScript.start(webJs, slot)).then((raw: string): void => {
      if (this.active !== task || task.webJsRun !== run) return;
      const value = this.unwrapJavaScriptResult(raw);
      if (value === WebJsAwaitScript.BLOCKED) {
        // The page's CSP forbids eval; nothing has run yet, so execute the script as written.
        controller.runJavaScript(webJs).then((plain: string): void => {
          if (this.active !== task || task.webJsRun !== run || this.controller !== controller) return;
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
      if (this.active !== task || task.webJsRun !== run || !controller || !task.pageStarted) return;
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
      if (task.request.webWaitFor) this.scheduleInspect(task, WebBookFetchRuntime.WEB_JS_RETRY_INTERVAL_MS);
      else task.inspectId = setTimeout((): void => this.resolveBody(task, finalUrl, html),
          WebBookFetchRuntime.WEB_JS_RETRY_INTERVAL_MS);
      return;
    }
    if (!this.matchesWebJs(task, value)) {
      // The page did load: keep it (and a non-zero status) so callers judge a challenge or login gate
      // by its content instead of treating every unmet wait like a network failure.
      this.finishActive({ url: finalUrl, statusCode: 200, headers: {}, body: '', success: false,
        statusCodeAvailable: false, errorCode: 'WEB_WAIT_UNMET', errorStage: 'selector',
        error: '网页等待条件未满足，未取得可用内容' });
      return;
    }
    this.finishActive(this.success(finalUrl, value && value !== 'undefined' && value !== 'null' ? value : html));
  }

  private failWebJs(task: WebBookFetchTask, run: number, finalUrl: string, message: string): void {
    if (this.active !== task || task.webJsRun !== run) return;
    this.finishActive(this.failure(finalUrl, `webJs 执行失败: ${message}`, 'WEB_JS_FAILED', 'script'));
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
    if (task.deadlineId >= 0) clearTimeout(task.deadlineId);
    if (task.inspectId >= 0) clearTimeout(task.inspectId);
    if (task.cancelId >= 0) clearInterval(task.cancelId);
    if (response.success && task.request.deadlineAt && Date.now() >= task.request.deadlineAt) {
      response = this.failure(task.request.url, '网页请求总等待超时 (2300028)', 'REQUEST_DEADLINE', 'deadline');
    }
    if (task.resolve) task.resolve(this.taskResponse(task, response));
    try { this.controller?.stop(); } catch (_) {}
    try { this.controller?.loadUrl('about:blank'); } catch (_) {}
    this.ready = !!this.controller;
    setTimeout((): void => this.runNext(), 0);
  }

  private taskResponse(task: WebBookFetchTask, response: WebBookFetchResponse): WebBookFetchResponse {
    const retain = !response.success && !response.body && !!task.snapshot &&
      ['deadline', 'load', 'selector', 'script'].includes(response.errorStage || '');
    return { ...response,
      body: retain ? task.snapshot : response.body,
      url: retain ? task.snapshotUrl : response.url,
      bodyIsSnapshot: retain || response.bodyIsSnapshot === true,
      snapshotTruncated: retain ? task.snapshotTruncated : response.snapshotTruncated === true,
      waitStage: task.startedAt ? task.waitStage : 'queue',
      queueMs: Math.max(0, (task.startedAt || Date.now()) - task.queuedAt),
      renderMs: task.startedAt ? Math.max(0, Date.now() - task.startedAt) : 0 };
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
    return { url: url, statusCode: 200, statusCodeAvailable: false, headers: {}, body: body, success: true };
  }

  private failure(url: string, error: string, errorCode: string = 'WEB_FAILED', errorStage: string = 'load'): WebBookFetchResponse {
    return { url: url, statusCode: 0, statusCodeAvailable: false, headers: {}, body: '', success: false,
      error: error, errorCode: errorCode, errorStage: errorStage };
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error || 'unknown error');
  }
}
