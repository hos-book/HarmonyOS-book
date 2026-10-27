/**
 * 脚本阶段的宿主端：脚本里的 http、vars、temp、cache、cookie、login、keep、log、sleep、device 和 native.*
 * 调用都在这里分发，并按预算计数。脚本本身在后台线程同步等待，这里的处理都在主线程上（可以是异步的）。
 *
 * 本文件不依赖系统 API，可直接在 Node 回归脚本中加载。
 */

import { HttpRetryPolicy } from '../http/HttpRetryPolicy';
import { HttpHeaderValues } from '../http/HttpHeaderValues';
import { BookSourceDebugRedactor } from '../book/BookSourceDebugModels';
import { NativeExpr } from './NativeExpr';
import type { NativeValue } from './NativeExpr';
import type { NativeRequest, NativeResponse, NativeRunnerHost } from './NativeSourceRunner';

/** 宿主对脚本一次调用的处理；抛出的错误会成为脚本里可以 catch 的错误。 */
export type NativeScriptCallHandler = (name: string, args: NativeValue[]) => Promise<NativeValue> | NativeValue;

export interface NativeScriptRunOptions {
  /** 脚本自身的计算时间上限，不含等待宿主的时间。 */
  cpuMs: number;
  /** 从开始到结束的总时长上限，不含等用户在网页里操作的时间（pausedMs）。 */
  wallMs: number;
  cancelled: () => boolean;
  pausedMs?: () => number;
  timing?: (cpuMs: number, wallMs: number) => void;
}

/** 在后台运行书源 js 里的函数 fn(ctx)：真机是 QuickJS 后台会话，Node 回归是 worker。 */
export interface NativeScriptEngine {
  run(fn: string, ctx: NativeValue, handler: NativeScriptCallHandler, options: NativeScriptRunOptions): Promise<NativeValue>;
}

/** 一次阶段运行的预算。 */
export class NativeScriptLimits {
  static readonly DEFAULT_REQUESTS: number = 30;
  static readonly MAX_REQUESTS: number = 100;
  requests: number = NativeScriptLimits.DEFAULT_REQUESTS;
  bytes: number = 16 * 1024 * 1024;
  cpuMs: number = 2000;
  wallMs: number = 60000;

  static of(requests: number | undefined): NativeScriptLimits {
    const limits = new NativeScriptLimits();
    if (requests !== undefined && requests !== null && Number.isFinite(Number(requests))) {
      limits.requests = Math.max(1, Math.min(Math.floor(Number(requests)), NativeScriptLimits.MAX_REQUESTS));
    }
    return limits;
  }
}

/** 运行器提供给脚本宿主的状态与操作。 */
export interface NativeScriptContext {
  host: NativeRunnerHost;
  sourceUrl: string;
  /** search / explore / detail / toc / content，用于调试记录与报错。 */
  stage: string;
  fn: string;
  limits: NativeScriptLimits;
  cancelled: () => boolean;
  builtin: (name: string, args: NativeValue[]) => NativeValue;
  getVar: (key: string) => NativeValue;
  setVar: (key: string, value: NativeValue) => Promise<void>;
  temp: Map<string, NativeValue>;
  credential: () => NativeValue;
  saveCredential: (token: string, user: string) => Promise<void>;
  /** 详情阶段用来收集 keep()；其他阶段为 null。 */
  keep: Record<string, string> | null;
  /**
   * 用户主动发起的操作（打开书籍的详情、目录、正文，设置页按钮，登录）：可以弹出网页。
   * 搜索、发现是多个书源同时跑的，不弹网页，browser.verify 改走「去验证」。
   */
  interactive: boolean;
  /** 脚本请求实际带的请求头：顶层 headers 按当前作用域求值，再叠上脚本给出的（同名以脚本为准）。 */
  requestHeaders: (own: Record<string, string>) => Promise<Record<string, string>>;
}

const BATCH = 8;
const MAX_SLEEP_MS = 5000;
const NOT_INTERACTIVE = '搜索和发现时不能打开网页';
const DEFAULT_CACHE_TTL = 600;
const MAX_CACHE_TTL = 7 * 24 * 3600;

export class NativeScriptHost {
  private context: NativeScriptContext;
  private requests: number = 0;
  private bytes: number = 0;
  private paused: number = 0;
  private startedAt: number = Date.now();

  constructor(context: NativeScriptContext) {
    this.context = context;
  }

  get requestCount(): number {
    return this.requests;
  }

  /** 等用户在网页里操作的总时长，不计入脚本的总时长预算。 */
  get pausedMs(): number {
    return this.paused;
  }

  /** 交给脚本引擎的处理函数。 */
  handler(): NativeScriptCallHandler {
    return (name: string, args: NativeValue[]): Promise<NativeValue> | NativeValue => this.handle(name, args);
  }

  private handle(name: string, args: NativeValue[]): Promise<NativeValue> | NativeValue {
    if (this.context.cancelled()) throw new Error('已取消');
    if (!name.startsWith('@')) return this.context.builtin(name, args);
    switch (name) {
      case '@http':
        return this.http(args[0]);
      case '@httpAll':
        return this.httpAll(Array.isArray(args[0]) ? args[0] : [], args[1]);
      case '@varsGet':
        return this.context.getVar(this.text(args[0]));
      case '@varsSet':
        return this.context.setVar(this.text(args[0]), args[1] === undefined ? null : args[1]).then((): NativeValue => null);
      case '@tempGet': {
        const value = this.context.temp.get(this.text(args[0]));
        return value === undefined ? null : value;
      }
      case '@tempSet':
        this.context.temp.set(this.text(args[0]), args[1] === undefined ? null : args[1]);
        return null;
      case '@cacheGet': {
        const value = this.cacheHost().cacheGet!(this.cacheKey(args[0]));
        return value === undefined ? null : value;
      }
      case '@cacheSet': {
        const ttl = Math.max(1, Math.min(Number(args[2]) || DEFAULT_CACHE_TTL, MAX_CACHE_TTL));
        this.cacheHost().cachePut!(this.cacheKey(args[0]), args[1] === undefined ? null : args[1], ttl);
        return null;
      }
      case '@cookieGet':
        return this.cookieHost('读取').cookieGet!(this.url(args[0]), this.text(args[1]));
      case '@cookieSet':
        this.cookieHost('写入').cookieSet!(this.url(args[0]), this.text(args[1]));
        return null;
      case '@cookieRemove':
        this.cookieHost('删除').cookieRemove!(this.url(args[0]), this.text(args[1]));
        return null;
      case '@login':
        return this.context.credential();
      case '@loginSave':
        return this.context.saveCredential(this.text(args[0]), this.text(args[1])).then((): NativeValue => null);
      case '@keep':
        if (!this.context.keep) throw new Error('keep 只能在详情阶段使用');
        this.context.keep[this.text(args[0])] = this.text(args[1]);
        return null;
      case '@log':
        this.trace('log', this.text(args[0]), '');
        return null;
      case '@sleep': {
        const ms = Math.max(0, Math.min(Number(args[0]) || 0, MAX_SLEEP_MS));
        return new Promise<NativeValue>((resolve: (value: NativeValue) => void): void => {
          setTimeout((): void => resolve(null), ms);
        });
      }
      case '@toast': {
        const host = this.context.host;
        if (!host.toast) throw new Error('当前环境不支持提示');
        host.toast(this.text(args[0]));
        return null;
      }
      case '@refreshExplore': {
        const host = this.context.host;
        if (!host.refreshExplore) throw new Error('当前环境不支持刷新发现页');
        return host.refreshExplore().then((): NativeValue => null);
      }
      case '@browserVerify':
        return this.browserVerify(this.url(args[0]), this.text(args[1]));
      case '@browserOpen': {
        const host = this.context.host;
        if (!this.context.interactive) throw new Error(NOT_INTERACTIVE);
        if (!host.openBrowser) throw new Error('当前环境不支持打开网页');
        return host.openBrowser(this.url(args[0]), this.text(args[1]), false).then((): NativeValue => null);
      }
      case '@render':
        return this.render(this.url(args[0]), args[1]);
      case '@device': {
        const host = this.context.host;
        if (this.text(args[0]) === 'ua') return this.userAgent();
        return host.deviceId ? host.deviceId() : '';
      }
      default:
        throw new Error(`没有这个宿主接口：${name.substring(1)}`);
    }
  }

  /** 交互场景里打开网页等用户完成，返回页面；非交互场景提示「去验证」。 */
  private async browserVerify(url: string, hint: string): Promise<NativeValue> {
    if (!/^https?:/i.test(url)) throw new Error(`网页地址无效：${url}`);
    const host = this.context.host;
    if (!this.context.interactive) {
      if (host.requestVerification) host.requestVerification(url, hint || '网页验证');
      throw new Error(`需要网页验证${hint ? `（${hint}）` : ''}，请点「去验证」后重试`);
    }
    if (!host.openBrowser) throw new Error('当前环境不支持打开网页');
    const startedAt = Date.now();
    this.trace(`browser.verify ${url}`, '等待用户在网页里完成', '');
    try {
      const result = await host.openBrowser(url, hint, true);
      if (result.error) throw new Error(result.error);
      return result.body;
    } finally {
      this.paused += Date.now() - startedAt;
    }
  }

  /** 在内置浏览器里加载页面并执行注入的表达式，返回结果（对象会转成 JSON 文本）。 */
  private async render(url: string, raw: NativeValue): Promise<NativeValue> {
    const options: Record<string, NativeValue> = raw && typeof raw === 'object' && !Array.isArray(raw) ?
      raw as Record<string, NativeValue> : {};
    const request = await this.request({
      url: url, headers: options['headers'],
      webView: { waitFor: options['waitFor'] || '', timeout: options['timeout'] }
    });
    request.webJs = this.text(options['js']).trim();
    this.count(1);
    const response = await this.fetch(request) as Record<string, NativeValue>;
    if (!response['ok']) throw new Error(`网页渲染失败：${response['error'] || `HTTP ${response['status']}`}`);
    return response['body'];
  }

  private async http(raw: NativeValue): Promise<NativeValue> {
    this.count(1);
    return await this.fetch(await this.request(raw));
  }

  private async httpAll(list: NativeValue[], rawOptions: NativeValue): Promise<NativeValue> {
    if (rawOptions !== undefined && rawOptions !== null &&
      (typeof rawOptions !== 'object' || Array.isArray(rawOptions))) throw new Error('http.all options 必须是对象');
    const options = (rawOptions || {}) as Record<string, NativeValue>;
    const concurrency = options['concurrency'] === undefined ? BATCH :
      this.integerOption(options['concurrency'], 'http.all concurrency', 1, BATCH);
    if (options['failOnPartial'] !== undefined && typeof options['failOnPartial'] !== 'boolean') {
      throw new Error('http.all failOnPartial 必须是布尔值');
    }
    const timeout = this.requestTimeout(options['timeout']);
    this.count(list.length);
    const requests: NativeRequest[] = [];
    for (const raw of list) requests.push(await this.request(raw, timeout));
    const results: NativeValue[] = [];
    let next = 0;
    let stopped = false;
    const worker = async (): Promise<void> => {
      try {
        while (!stopped && next < requests.length) {
          if (this.context.cancelled()) throw new Error('已取消');
          const index = next++;
          results[index] = await this.fetch(requests[index]);
        }
      } catch (error) {
        stopped = true;
        throw error;
      }
    };
    const workers: Promise<void>[] = [];
    for (let index = 0; index < Math.min(concurrency, requests.length); index++) workers.push(worker());
    await Promise.all(workers);
    if (this.context.cancelled()) throw new Error('已取消');
    if (options['failOnPartial'] === true) {
      const failures: string[] = [];
      results.forEach((value: NativeValue, index: number): void => {
        const result = value as Record<string, NativeValue>;
        if (!result['ok']) failures.push(`[${index}] ${result['requestId'] || ''} HTTP ${result['status']} ${BookSourceDebugRedactor.url(String(result['url']))}`);
      });
      if (failures.length) throw new Error(`http.all 部分失败：成功 ${results.length - failures.length}，失败 ${failures.length}；${failures.join('；')}`);
    }
    return results;
  }

  private integerOption(value: NativeValue, name: string, min: number, max: number): number {
    if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) {
      throw new Error(`${name} 必须是 ${min} 到 ${max} 的整数`);
    }
    return value;
  }

  private requestTimeout(value: NativeValue): number | undefined {
    return value === undefined ? undefined : this.integerOption(value, 'http timeout（毫秒）', 100, 60000);
  }

  private count(added: number): void {
    this.requests += added;
    if (this.requests > this.context.limits.requests) {
      throw new Error(`脚本请求次数超过上限（${this.context.limits.requests} 次）`);
    }
  }

  private async fetch(request: NativeRequest): Promise<NativeValue> {
    const startedAt = Date.now();
    const remaining = this.context.limits.wallMs - (startedAt - this.startedAt - this.paused);
    if (remaining <= 0) throw new Error('脚本运行总时长超过上限');
    request.timeoutMs = Math.min(request.timeoutMs || remaining, remaining);
    let response: NativeResponse;
    try {
      response = await this.context.host.fetch(request);
    } catch (e) {
      response = { ok: false, status: 0, body: '', url: request.url, error: (e as Error).message || '网络异常' };
    }
    if (this.context.cancelled()) throw new Error('已取消');
    const body = response.body || '';
    this.bytes += body.length;
    this.trace(`${request.method} ${BookSourceDebugRedactor.url(request.url)}`,
      `${response.requestId || ''} · ${response.status || '-'} · ${body.length} 字符 · ${Date.now() - startedAt} ms`,
      response.ok ? '' : (response.error || `HTTP ${response.status}`));
    if (this.bytes > this.context.limits.bytes) {
      throw new Error(`脚本收到的数据超过上限（${Math.round(this.context.limits.bytes / 1024 / 1024)} MB）`);
    }
    return {
      ok: response.ok, status: response.status, body: body, url: response.url || request.url,
      finalUrl: response.finalUrl || '', error: response.error || '',
      headers: HttpHeaderValues.normalize(response.headers || {}), headersAvailable: response.headersAvailable === true,
      requestId: response.requestId || ''
    };
  }

  /** 脚本给出的请求（地址字符串或对象）整理成与声明式请求相同的 NativeRequest。 */
  private async request(raw: NativeValue, defaultTimeout?: number): Promise<NativeRequest> {
    const spec: Record<string, NativeValue> = raw && typeof raw === 'object' && !Array.isArray(raw) ?
      raw as Record<string, NativeValue> : { url: raw };
    const url = this.url(spec['url']);
    if (!/^(https?:|data:)/i.test(url)) throw new Error(`请求地址无效：${this.text(spec['url'])}`);
    const headers: Record<string, string> = {};
    const rawHeaders = spec['headers'];
    if (rawHeaders && typeof rawHeaders === 'object') {
      for (const name of Object.keys(rawHeaders)) {
        const value = (rawHeaders as Record<string, NativeValue>)[name];
        if (value !== undefined && value !== null && value !== '') headers[name] = String(value);
      }
    }
    const body = spec['body'] === undefined || spec['body'] === null ? '' : String(spec['body']);
    const method = (this.text(spec['method']).trim() || (body ? 'POST' : 'GET')).toUpperCase();
    if (!/^[A-Z]+$/.test(method)) throw new Error(`请求方法无效：${spec['method']}`);
    const web = spec['webView'];
    const webSpec: Record<string, NativeValue> | null = web && typeof web === 'object' ? web as Record<string, NativeValue> : null;
    return {
      url: url, method: method, headers: await this.context.requestHeaders(headers), body: body,
      webView: web === true || !!webSpec,
      webWaitFor: webSpec && webSpec['waitFor'] ? String(webSpec['waitFor']).trim() : '',
      webTimeout: Math.max(3, Math.min(Number(webSpec ? webSpec['timeout'] : 0) || 15, 60)),
      charset: this.text(spec['charset']).trim(),
      retry: HttpRetryPolicy.parse(spec['retry']),
      timeoutMs: spec['timeout'] === undefined ? defaultTimeout : this.requestTimeout(spec['timeout']),
      primary: false
    };
  }

  /** 书源请求用的 User-Agent：顶层 headers 里写了（可以是模板）就用求值后的值，否则用宿主默认的。 */
  private async userAgent(): Promise<string> {
    const headers = await this.context.requestHeaders({});
    for (const name of Object.keys(headers)) {
      if (name.toLowerCase() === 'user-agent') return headers[name];
    }
    const host = this.context.host;
    return host.userAgent ? host.userAgent() : '';
  }

  private cookieHost(action: string): NativeRunnerHost {
    const host = this.context.host;
    if (!host.cookieGet || !host.cookieSet || !host.cookieRemove) throw new Error(`当前环境不支持${action} Cookie`);
    return host;
  }

  /** 没有缓存时明确报错：静默丢掉写入会让脚本读到空值，难以排查。 */
  private cacheHost(): NativeRunnerHost {
    const host = this.context.host;
    if (!host.cacheGet || !host.cachePut) throw new Error('当前环境不支持缓存');
    return host;
  }

  private cacheKey(key: NativeValue): string {
    return `script\n${this.text(key)}`;
  }

  private url(value: NativeValue): string {
    return NativeExpr.resolveUrl(this.text(value).trim(), this.context.sourceUrl);
  }

  private text(value: NativeValue): string {
    return value === undefined || value === null ? '' : String(value);
  }

  private trace(rule: string, preview: string, error: string): void {
    if (!this.context.host.trace) return;
    this.context.host.trace({
      field: `${this.context.stage}.script ${this.context.fn}`, rule: rule, type: 'script', count: 1,
      preview: preview, error: error
    });
  }
}
