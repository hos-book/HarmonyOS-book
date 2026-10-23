/**
 * 原生书源接入层：把执行器接到应用的请求层、选择器引擎和数据模型上。
 * 原生书源只经过这里，不进入任何脚本引擎。
 */

import { Book, BookChapter, BookSource, SearchBook } from '../../model/data/Book';
import { HttpClient, HttpResponse } from '../http/HttpClient';
import { BookSourceDebugContext, BookSourceDebugRuleTrace } from '../book/BookSourceDebugModels';
import { digestHashHex } from '../http/DigestHash';
import { AnalyzeUrl } from '../rule/AnalyzeUrl';
import { AnalyzeRule } from '../rule/AnalyzeRule';
import { JsonPathEvaluator } from '../rule/JsonPathEvaluator';
import { RuleExecutionTarget, RuleValue, RuleValueKind } from '../rule/RuleValue';
import { BookTypeSupport } from '../book/BookTypeSupport';
import { BookUrlResolver } from '../book/BookUrlResolver';
import { BookFieldSanitizer } from '../../utils/BookFieldSanitizer';
import { NativeExpr } from './NativeExpr';
import type { NativeScriptLibrary, NativeValue } from './NativeExpr';
import { NativeJsLibrary } from './NativeJsLibrary';
import { NativeSourceRunner } from './NativeSourceRunner';
import { SourceCoverUrl } from './SourceCoverUrl';
import type {
  NativeBookInput, NativeBookRecord, NativeContentResult, NativeMenuEntry, NativeRequest, NativeResponse,
  NativeRunnerHost
} from './NativeSourceRunner';
import { NativeSourceSpec } from './NativeSourceSpec';
import { NativeSourceCrypto } from './NativeSourceCrypto';
import { CookieStore } from '../http/CookieStore';
import { VerificationSupport } from '../http/VerificationSupport';
import { ReaderActionMarker } from '../book/ReaderActionMarker';
import type { NativeLoginSpec, NativeSourceDefinition, NativeVarSpec, NativeVoiceSpec } from './NativeSourceSpec';
import type {
  NativeActionEntry, NativeLoginCredential, NativeLoginResult, NativeLoginState, NativeRuleTrace, NativeVarOptions
} from './NativeSourceRunner';
import type { NativeLoginFieldSpec } from './NativeSourceSpec';
import { NetworkErrorText } from '../http/NetworkErrorText';
import { NativeSourceImport } from './NativeSourceImport';
import { NativeScriptSessions } from './NativeScriptSessions';
import { NativeSourceInteraction } from './NativeSourceInteraction';
import type { NativeBrowserResult } from './NativeSourceInteraction';
import type { NativeScriptEngine } from './NativeScriptHost';
import { BookSourceRuntimeStore } from '../book/BookSourceRuntimeStore';
import { deviceInfo } from '@kit.BasicServicesKit';
import { SourceEngineHost } from '../host/SourceEngineHost';

export interface NativeFilterGroup {
  title: string;
  options: string[];
  selected: string;
}

/** 听书页音色列表里的一项。 */
export interface NativeVoiceOption {
  id: string;
  name: string;
}

/** 书源设置页里的一项变量。 */
export interface NativeVarItem {
  key: string;
  label: string;
  options: string[];
  value: string;
}

class NativeHost implements NativeRunnerHost {
  evaluateExpression?: NativeRunnerHost['evaluateExpression'];
  private nativeScripts: Pick<NativeRunnerHost, 'scriptEngine' | 'evaluateExpression'> | undefined;
  private source: BookSource;
  private http: HttpClient;
  private cancelled: () => boolean;
  private maxResponseBytes: number;
  private debugContext: BookSourceDebugContext | null;
  private cacheScope: string = '';
  private cacheScopeInput: string[] = [];
  /** 只在调试时提供：把规则求值记到调试页的执行明细里。 */
  trace?: (entry: NativeRuleTrace) => void;

  constructor(source: BookSource, http: HttpClient, cancelled: () => boolean, maxResponseBytes: number,
    debugContext: BookSourceDebugContext | null = null) {
    this.source = source;
    this.http = http;
    this.cancelled = cancelled;
    this.maxResponseBytes = maxResponseBytes;
    this.debugContext = debugContext;
    this.nativeScripts = SourceEngineHost.nativeScripts()?.create(source, this);
    this.evaluateExpression = this.nativeScripts?.evaluateExpression;
    if (debugContext) {
      this.trace = (entry: NativeRuleTrace): void => {
        const trace = new BookSourceDebugRuleTrace();
        trace.field = entry.field;
        trace.rule = entry.rule;
        trace.ruleType = entry.type;
        trace.inputCount = 1;
        trace.matchedCount = entry.count;
        trace.outputPreview = entry.preview;
        trace.error = entry.error;
        debugContext.addRule(trace);
      };
    }
  }

  /** 网页渲染并等待指定元素出现：反复检查页面，元素出现后取整页内容。 */
  private async fetchWaitingFor(analyzeUrl: AnalyzeUrl, url: string, request: NativeRequest): Promise<HttpResponse> {
    analyzeUrl.parse(url);
    const webRequest = analyzeUrl.buildRequest();
    webRequest.useWebView = true;
    // 脚本的 browser.render 带了 js：在页面里求值注入的表达式（对象转成 JSON 文本）；没有 waitFor 时只求值一次。
    const result = request.webJs ?
      `var __r=(${request.webJs});return __r===undefined||__r===null?'':(typeof __r==='string'?__r:JSON.stringify(__r));` :
      'return document.documentElement.outerHTML;';
    webRequest.webJs = request.webWaitFor ?
      `(function(){if(!document.querySelector(${JSON.stringify(request.webWaitFor)}))return '';${result}})()` :
      `(function(){${result}})()`;
    if (request.webWaitFor) {
      webRequest.webJsAcceptPattern = '\\S';
      webRequest.webJsMaxAttempts = Math.max(4, request.webTimeout * 2);
    }
    webRequest.readTimeout = request.webTimeout * 1000;
    webRequest.debugContext = this.debugContext || undefined;
    if (this.maxResponseBytes > 0) webRequest.maxResponseBytes = this.maxResponseBytes;
    return await analyzeUrl.fetchPrepared(webRequest);
  }

  async fetch(request: NativeRequest): Promise<NativeResponse> {
    if (this.cancelled()) return { ok: false, status: 0, body: '', url: request.url, error: '已取消' };
    // 沿用书源请求层：限流、Cookie、书源请求头、编码探测和验证处理都在 AnalyzeUrl 里。
    const options: Record<string, Object> = {};
    if (request.method !== 'GET') options['method'] = request.method;
    if (request.body) options['body'] = request.body;
    if (Object.keys(request.headers).length > 0) options['headers'] = request.headers;
    if (request.webView) options['webView'] = true;
    if (request.charset) options['charset'] = request.charset;
    if (request.retry > 0) options['retry'] = request.retry;
    const url = Object.keys(options).length > 0 ? `${request.url},${JSON.stringify(options)}` : request.url;
    // 顶层 headers 已由运行器按作用域求值并放进 request.headers，书源记录里的字面值副本不再重复合并。
    const analyzeUrl = new AnalyzeUrl(this.source, this.http).setCancelCheck(this.cancelled).setStaticSourceHeader(false);
    const response = request.webView && (request.webWaitFor || request.webJs) ?
      await this.fetchWaitingFor(analyzeUrl, url, request) :
      await analyzeUrl.fetch(url, this.maxResponseBytes > 0 ? this.maxResponseBytes : undefined, this.debugContext);
    // 没拿到响应且请求层报的是明确的网络错误（域名解析、超时、连不上等）：与登录无关，直接给出真实原因。
    // 否则配置了登录入口的书源会把断网也报成“需要登录或网页验证”，还会拉起验证流程。
    if (response.statusCode === 0 && !response.success) {
      const networkReason = NetworkErrorText.describe(response.error || '', request.url);
      if (networkReason) {
        console.warn(`[NativeSource] 网络请求失败 source=${this.source.bookSourceName} error=${response.error || ''}`);
        return { ok: false, status: 0, body: '', url: request.url, error: networkReason };
      }
    }
    // 主请求拿到的是人机验证或登录拦截页时，沿用应用现有的「去验证」流程，而不是当成没有结果。
    if (request.primary && VerificationSupport.shouldRequestBrowserVerification(this.source, response.body || '',
      response.statusCode, '')) {
      // 状态码 0（超时、连不上）在配置了登录入口的书源上也会落到这里，记下真实原因便于区分。
      console.warn(`[NativeSource] 主请求判定为需要验证 source=${this.source.bookSourceName} ` +
        `status=${response.statusCode} error=${response.error || ''} bodyLength=${(response.body || '').length}`);
      VerificationSupport.requestVerification(
        VerificationSupport.pickVerificationUrl(this.source, request.url, ''),
        `${this.source.bookSourceName} 验证`, this.source);
      return {
        ok: false, status: response.statusCode, body: '', url: request.url,
        error: NativeSourceService.VERIFICATION_REASON
      };
    }
    return {
      ok: response.success,
      status: response.statusCode,
      body: response.body || '',
      url: BookUrlResolver.effectiveBase(response, request.url, this.source.bookSourceUrl),
      error: response.error || ''
    };
  }

  jsonPath(root: NativeValue, path: string): NativeValue[] {
    return JsonPathEvaluator.evaluate(root as Object, path);
  }

  select(content: string, rule: string, baseUrl: string, list: boolean): string[] {
    const analyzer = new AnalyzeRule(content, baseUrl);
    if (list) return analyzer.getStringList(rule);
    const value = analyzer.getString(rule);
    return value ? [value] : [];
  }

  scriptLibrary(code: string): NativeScriptLibrary {
    return NativeJsLibrary.forCode(code);
  }

  scriptEngine(code: string): NativeScriptEngine {
    if (this.nativeScripts?.scriptEngine) return this.nativeScripts.scriptEngine(code);
    return NativeScriptSessions.forCode(code);
  }

  cookieGet(url: string, name: string): string {
    const jar = CookieStore.forSource(this.source.bookSourceUrl);
    return name ? jar.getCookieValue(url, name) : jar.getCookie(url);
  }

  cookieSet(url: string, value: string): void {
    const jar = CookieStore.forSource(this.source.bookSourceUrl);
    jar.setCookies(url, value);
    jar.saveAsync();
  }

  cookieRemove(url: string, name: string): void {
    const jar = CookieStore.forSource(this.source.bookSourceUrl);
    jar.removeCookie(url, name || undefined);
    jar.saveAsync();
  }

  async saveVars(values: Record<string, NativeValue>): Promise<void> {
    await NativeSourceService.saveRuntime(this.source, JSON.stringify(values), null);
  }

  async saveCredential(token: string, user: string): Promise<void> {
    await NativeSourceService.saveRuntime(this.source, null, NativeSourceService.loginInfoWith(this.source, token, user));
  }

  toast(message: string): void {
    const handler = NativeSourceInteraction.handler();
    if (!handler) throw new Error('当前环境不支持提示');
    handler.toast(this.source.bookSourceName || '', message);
  }

  async refreshExplore(): Promise<void> {
    const handler = NativeSourceInteraction.handler();
    if (!handler) throw new Error('当前环境不支持刷新发现页');
    NativeSourceService.clearCache(this.source.bookSourceUrl);
    await handler.refreshExplore(this.source.bookSourceUrl);
  }

  async openBrowser(url: string, title: string, wait: boolean): Promise<NativeBrowserResult> {
    const handler = NativeSourceInteraction.handler();
    if (!handler) return { body: '', error: '当前环境不支持打开网页' };
    return await handler.openBrowser({
      url: url, title: title || this.source.bookSourceName || '网页',
      sourceUrl: this.source.bookSourceUrl, sourceName: this.source.bookSourceName || ''
    }, wait);
  }

  requestVerification(url: string, title: string): void {
    VerificationSupport.requestVerification(url, title, this.source);
  }

  deviceId(): string {
    try {
      return deviceInfo.ODID || '';
    } catch (e) {
      return '';
    }
  }

  userAgent(): string {
    try {
      const headers = JSON.parse(this.source.header || '{}') as Record<string, Object>;
      for (const name of Object.keys(headers)) {
        if (name.toLowerCase() === 'user-agent' && headers[name]) return String(headers[name]);
      }
    } catch (e) {
    }
    return HttpClient.DEFAULT_USER_AGENT;
  }

  selectItems(content: string, rule: string, baseUrl: string): NativeValue[] {
    const values = new AnalyzeRule(content, baseUrl).execute(rule, RuleExecutionTarget.ELEMENTS);
    return values.map((value: RuleValue): NativeValue => {
      if (value.kind === RuleValueKind.JSON) {
        if (value.objectValue !== null && value.objectValue !== undefined) return value.objectValue;
        try {
          return JSON.parse(value.asString());
        } catch (e) {
          return value.asString();
        }
      }
      return value.asString();
    });
  }

  digest(algorithm: string, text: string): string {
    return digestHashHex(algorithm, text);
  }

  cacheGet(key: string): NativeValue {
    return NativeSourceService.cacheGet(this.source.bookSourceUrl, this.cacheKey(key));
  }

  cachePut(key: string, value: NativeValue, ttlSeconds: number): void {
    NativeSourceService.cachePut(this.source.bookSourceUrl, this.cacheKey(key), value, ttlSeconds);
  }

  /**
   * 缓存值按“定义 + 请求头 + 登录状态”分开：宿主可能只用 NativeSourceImport 换了定义而没有清缓存，
   * 换定义或换账号后不能读到旧值。只有这几个字段变了才重新算哈希，没变时只是比较字符串引用。
   * 登录站点的 Cookie 不参与：站点每次响应都可能刷新 Cookie，放进来缓存就永远命中不了；
   * 网页登录与退出登录各自清缓存。
   */
  private cacheKey(key: string): string {
    const input = [this.source.jsLib || '', this.source.header || '', this.source.loginHeader || '',
      this.source.loginInfo || ''];
    const changed = input.some((value: string, index: number): boolean => value !== this.cacheScopeInput[index]);
    if (!this.cacheScope || changed) {
      this.cacheScopeInput = input;
      this.cacheScope = digestHashHex('SHA256', JSON.stringify(input));
    }
    return `${this.cacheScope}\n${key}`;
  }

  crypto(name: string, args: NativeValue[]): NativeValue {
    return NativeSourceCrypto.run(name, args as Object[]);
  }

  cookie(url: string, name: string): string {
    return CookieStore.forSource(this.source.bookSourceUrl).getCookieValue(url, name);
  }
}

interface NativeRuntimeState {
  variable: string | null;
  loginInfo: string | null;
}

interface NativeCacheEntry {
  value: NativeValue;
  expiresAt: number;
}

export class NativeSourceService {
  static readonly VERIFICATION_REASON: string = '需要登录或网页验证';
  static readonly READER_ACTION_SCHEME: string = 'legado-native-action:';
  // 声明式缓存只放在内存里：应用重启后重新获取，不需要考虑落库与同步。
  private static cacheEntries: Map<string, NativeCacheEntry> = new Map();

  static cacheGet(sourceUrl: string, key: string): NativeValue {
    const fullKey = `${sourceUrl}\n${key}`;
    const entry = NativeSourceService.cacheEntries.get(fullKey);
    if (!entry) return undefined;
    if (entry.expiresAt <= Date.now()) {
      NativeSourceService.cacheEntries.delete(fullKey);
      return undefined;
    }
    return entry.value;
  }

  static cachePut(sourceUrl: string, key: string, value: NativeValue, ttlSeconds: number): void {
    if (NativeSourceService.cacheEntries.size >= 200) NativeSourceService.cacheEntries.clear();
    NativeSourceService.cacheEntries.set(`${sourceUrl}\n${key}`,
      { value: value, expiresAt: Date.now() + ttlSeconds * 1000 });
  }

  /** 书源被修改、重新导入或退出登录后，丢掉它的缓存值。 */
  static clearCache(sourceUrl: string): void {
    const prefix = `${sourceUrl}\n`;
    for (const key of Array.from(NativeSourceService.cacheEntries.keys())) {
      if (key.startsWith(prefix)) NativeSourceService.cacheEntries.delete(key);
    }
  }
  /** 该书源是否为原生书源。 */
  static isNative(source: BookSource | null | undefined): boolean {
    return !!source && NativeSourceSpec.isPacked(source.jsLib || '');
  }

  static definitionOf(source: BookSource): NativeSourceDefinition {
    const definition = NativeSourceSpec.unpack(source.jsLib || '');
    if (!definition) throw new Error('原生书源定义已损坏，请重新导入');
    return definition;
  }

  /** 把定义写进书源记录。existing 传入时保留排序、置顶、已选变量等本地状态。 */
  static toBookSource(definition: NativeSourceDefinition, existing: BookSource | null = null): BookSource {
    const source = NativeSourceImport.toBookSource(definition, existing);
    NativeSourceService.clearCache(source.bookSourceUrl);
    return source;
  }

  /** 导入用：把 JSON 对象转成书源记录，不合法时抛出带原因的错误。 */
  static importObject(value: Object, existing: BookSource | null = null): BookSource {
    const definition = NativeSourceSpec.fromObject(value);
    if (definition.js && definition.js.trim()) {
      const problem = NativeJsLibrary.check(definition.js, NativeExpr.libraryFunctionNames(definition.lib),
        NativeSourceSpec.scriptFunctions(definition));
      if (problem) throw new Error(problem);
    }
    return NativeSourceService.toBookSource(definition, existing);
  }

  /** 导出用：还原成带 sourceFormat 的定义对象。 */
  static exportObject(source: BookSource): Object {
    return NativeSourceSpec.toExportObject(NativeSourceService.definitionOf(source)) as Object;
  }

  /**
   * 脚本写入的变量和登录凭据：已经保存到数据库，但别处拿着的书源对象可能还是旧值。在设置页下次保存前，
   * 以这里记下的为准，避免下一次运行读到旧值、把脚本刚写的值覆盖掉。
   */
  private static runtimeState: Map<string, NativeRuntimeState> = new Map();

  /** 保存脚本写入的变量（variable）或登录凭据（loginInfo），传 null 的那一项不变。 */
  static async saveRuntime(source: BookSource, variable: string | null, loginInfo: string | null): Promise<void> {
    const url = source.bookSourceUrl;
    const state = NativeSourceService.runtimeState.get(url) || { variable: null, loginInfo: null };
    if (variable !== null) {
      state.variable = variable;
      source.variable = variable;
    }
    if (loginInfo !== null) {
      state.loginInfo = loginInfo;
      source.loginInfo = loginInfo;
    }
    NativeSourceService.runtimeState.set(url, state);
    const persistence = BookSourceRuntimeStore.forSource(source);
    if (persistence) {
      await persistence.updateBookSourceLoginRuntime(url, NativeSourceService.effectiveVariable(source),
        source.loginHeader || '', NativeSourceService.effectiveLoginInfo(source));
    }
  }

  private static effectiveVariable(source: BookSource): string {
    const state = NativeSourceService.runtimeState.get(source.bookSourceUrl);
    return state && state.variable !== null ? state.variable : (source.variable || '');
  }

  private static effectiveLoginInfo(source: BookSource): string {
    const state = NativeSourceService.runtimeState.get(source.bookSourceUrl);
    return state && state.loginInfo !== null ? state.loginInfo : (source.loginInfo || '');
  }

  static storedVars(source: BookSource): Record<string, NativeValue> {
    try {
      const parsed = JSON.parse(NativeSourceService.effectiveVariable(source) || '{}') as Object;
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed as Record<string, NativeValue>;
    } catch (e) {
    }
    return {};
  }

  /** 书源设置页用：全部变量及其当前值。 */
  static varItems(source: BookSource): NativeVarItem[] {
    const definition = NativeSourceSpec.unpack(source.jsLib || '');
    if (!definition) return [];
    const current = NativeSourceRunner.resolveVars(definition, NativeSourceService.storedVars(source));
    return (definition.vars || []).map((item: NativeVarSpec): NativeVarItem => ({
      key: item.key,
      label: item.label || item.key,
      options: Array.isArray(item.options) ? item.options.map((option: string): string => String(option)) : [],
      value: current[item.key] || ''
    }));
  }

  /** 把设置页里的值合并进书源变量 JSON。 */
  static variableWithValues(source: BookSource, items: NativeVarItem[]): string {
    const stored = NativeSourceService.storedVars(source);
    for (const item of items) stored[item.key] = item.value;
    // 设置页接着会保存这个结果，之后以书源对象上的值为准。
    const state = NativeSourceService.runtimeState.get(source.bookSourceUrl);
    if (state) state.variable = null;
    return JSON.stringify(stored);
  }

  /** 书源声明的听书音色；不是原生书源或没有声明时返回空列表。 */
  static voices(source: BookSource | null): NativeVoiceOption[] {
    const definition = source ? NativeSourceSpec.unpack(source.jsLib || '') : null;
    if (!definition || !Array.isArray(definition.voices)) return [];
    return definition.voices.map((voice: NativeVoiceSpec): NativeVoiceOption =>
      ({ id: String(voice.id), name: String(voice.name) }));
  }

  static loginSpec(source: BookSource): NativeLoginSpec | null {
    const definition = NativeSourceSpec.unpack(source.jsLib || '');
    return definition && definition.login ? definition.login : null;
  }

  /** 按声明的 Cookie 名判断是否已登录；没有声明时只要该站点有 Cookie 就算。 */
  static hasLoginCookies(source: BookSource): boolean {
    const login = NativeSourceService.loginSpec(source);
    if (!login) return false;
    if (NativeSourceService.credential(source).token) return true;
    if (!login.url) return false;
    const names = Array.isArray(login.cookies) ? login.cookies : [];
    const jar = CookieStore.forSource(source.bookSourceUrl);
    if (names.length === 0) return !!jar.getCookie(login.url);
    return names.every((name: string): boolean => !!jar.getCookieValue(login.url, String(name)));
  }

  static logout(source: BookSource): void {
    const login = NativeSourceService.loginSpec(source);
    if (!login) return;
    NativeSourceService.clearCache(source.bookSourceUrl);
    if (!login.url) return;
    const origin = /^https?:\/\/[^/?#]+/i.exec(login.url);
    const jar = CookieStore.forSource(source.bookSourceUrl);
    jar.removeCookie(login.url);
    if (origin) {
      jar.removeCookie(origin[0]);
      jar.removeCookie(`${origin[0]}/`);
    }
    jar.saveAsync();
    NativeSourceService.clearCache(source.bookSourceUrl);
  }

  static async checkLogin(source: BookSource, http: HttpClient): Promise<NativeLoginState> {
    return await NativeSourceService.runner(source, http, (): boolean => false).checkLogin();
  }

  /**
   * 发现页的筛选项：定义里标了 filter 且带选项的变量。筛选栏不运行 optionsScript，只列静态 options；
   * 设置页选了脚本给出的值时把它补在末尾，让筛选栏仍能高亮当前值。
   */
  static filters(source: BookSource): NativeFilterGroup[] {
    const definition = NativeSourceSpec.unpack(source.jsLib || '');
    if (!definition) return [];
    const current = NativeSourceRunner.resolveVars(definition, NativeSourceService.storedVars(source));
    return (definition.vars || [])
      .filter((item: NativeVarSpec): boolean => item.filter === true && Array.isArray(item.options) &&
        item.options.length > 0)
      .map((item: NativeVarSpec): NativeFilterGroup => {
        const options = (item.options as string[]).map((option: string): string => String(option));
        const selected = current[item.key] || '';
        if (item.optionsScript && selected && options.indexOf(selected) < 0) options.push(selected);
        return { title: item.label || item.key, options: options, selected: selected };
      });
  }

  /** 修改一个变量，返回新的书源变量 JSON；没有变化或选项不合法时返回空串。 */
  static variableAfterSelect(source: BookSource, title: string, selection: string): string {
    const definition = NativeSourceSpec.unpack(source.jsLib || '');
    if (!definition) return '';
    const target = (definition.vars || []).find((item: NativeVarSpec): boolean => (item.label || item.key) === title);
    if (!target) return '';
    if (Array.isArray(target.options) && target.options.length > 0 &&
      target.options.map((option: string): string => String(option)).indexOf(selection) < 0) {
      return '';
    }
    const stored = NativeSourceService.storedVars(source);
    if (String(stored[target.key] === undefined ? '' : stored[target.key]) === selection) return '';
    stored[target.key] = selection;
    // 调用方接着会保存这个结果：之后以它为准，不能再让脚本先前写入的值盖过发现页的选择。
    const state = NativeSourceService.runtimeState.get(source.bookSourceUrl);
    if (state) state.variable = null;
    const variable = JSON.stringify(stored);
    source.variable = variable;
    return variable;
  }

  private static runner(source: BookSource, http: HttpClient, cancelled: () => boolean,
    maxResponseBytes: number = 0, debugContext: BookSourceDebugContext | null = null): NativeSourceRunner {
    const host = new NativeHost(source, http, cancelled, maxResponseBytes, debugContext);
    return new NativeSourceRunner(NativeSourceService.definitionOf(source), host,
      NativeSourceService.storedVars(source)).setCancelCheck(cancelled)
      .setCredential(NativeSourceService.credential(source));
  }

  // ---------- 表单登录的凭据：存在 loginInfo 里，备份和云同步都不包含它 ----------

  static credential(source: BookSource): NativeLoginCredential {
    try {
      const parsed = JSON.parse(NativeSourceService.effectiveLoginInfo(source) || '{}') as Record<string, Object>;
      return { token: String(parsed['nativeToken'] || ''), user: String(parsed['nativeUser'] || '') };
    } catch (e) {
      return { token: '', user: '' };
    }
  }

  /** 写入或清除凭据后的 loginInfo 文本。只保存登录换来的凭据，不保存用户填写的密码。 */
  static loginInfoWith(source: BookSource, token: string, user: string): string {
    let record: Record<string, Object> = {};
    const loginInfo = NativeSourceService.effectiveLoginInfo(source);
    // 调用方接着会保存这个结果，之后以书源对象上的值为准。
    const state = NativeSourceService.runtimeState.get(source.bookSourceUrl);
    if (state) state.loginInfo = null;
    try {
      const parsed = JSON.parse(loginInfo || '{}') as Object;
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) record = parsed as Record<string, Object>;
    } catch (e) {
    }
    if (token) {
      record['nativeToken'] = token;
      record['nativeUser'] = user;
    } else {
      delete record['nativeToken'];
      delete record['nativeUser'];
    }
    return JSON.stringify(record);
  }

  static loginForm(source: BookSource): NativeLoginFieldSpec[] {
    const login = NativeSourceService.loginSpec(source);
    return login && (login.submit || login.script) && Array.isArray(login.form) ? login.form : [];
  }

  /** 书源设置页的动态选项（vars 里写了 optionsScript 的变量）。 */
  static async varOptions(source: BookSource, http: HttpClient, key: string = ''): Promise<Record<string, NativeVarOptions>> {
    return await NativeSourceService.runner(source, http, (): boolean => false).varOptions(key);
  }

  static async submitLogin(source: BookSource, http: HttpClient,
    form: Record<string, string>): Promise<NativeLoginResult> {
    const result = await NativeSourceService.runner(source, http, (): boolean => false).submitLogin(form);
    if (result.ok) NativeSourceService.clearCache(source.bookSourceUrl);
    return result;
  }

  static async sendLoginCode(source: BookSource, http: HttpClient, form: Record<string, string>): Promise<string> {
    return await NativeSourceService.runner(source, http, (): boolean => false).sendLoginCode(form);
  }

  // ---------- 动作按钮 ----------

  static async actions(source: BookSource, http: HttpClient): Promise<NativeActionEntry[]> {
    return await NativeSourceService.runner(source, http, (): boolean => false).actions();
  }

  static async runAction(source: BookSource, http: HttpClient, index: number): Promise<string> {
    return await NativeSourceService.runner(source, http, (): boolean => false).runAction(index);
  }

  /** 正文里的请求按钮：阅读器点击后把标记里的地址交回这里执行。 */
  static isReaderAction(url: string): boolean {
    return (url || '').startsWith(NativeSourceService.READER_ACTION_SCHEME);
  }

  static async runReaderAction(source: BookSource, http: HttpClient, url: string): Promise<string> {
    let request: NativeRequest | null = null;
    let message = '';
    try {
      const payload = JSON.parse(decodeURIComponent(url.substring(NativeSourceService.READER_ACTION_SCHEME.length))) as
        Record<string, Object>;
      request = payload['r'] as NativeRequest;
      message = String(payload['m'] || '');
    } catch (e) {
      request = null;
    }
    if (!request || !/^https?:\/\//i.test(String(request.url || ''))) return '操作无效';
    return await NativeSourceService.runner(source, http, (): boolean => false).runLinkAction(request, message);
  }

  private static typeBits(type: string, source: BookSource): number {
    return BookTypeSupport.typeFromTab(type) || BookTypeSupport.typeFromSource(source) || BookTypeSupport.TEXT;
  }

  /** 视频没有专门的类型位，记在书籍变量的 tab 里；其余类型由类型位推出。 */
  private static typeName(bits: number, source: BookSource, variable: string = ''): string {
    if (variable && BookUrlResolver.getVariableJson(variable, 'tab') === 'video') return 'video';
    const value = Number(bits) || BookTypeSupport.typeFromSource(source);
    if ((value & BookTypeSupport.AUDIO) !== 0) return 'audio';
    if ((value & BookTypeSupport.IMAGE) !== 0) return 'comic';
    return 'text';
  }

  private static toSearchBook(source: BookSource, record: NativeBookRecord): SearchBook {
    const book = new SearchBook();
    book.name = BookFieldSanitizer.clean(record.name);
    book.author = BookFieldSanitizer.clean(record.author);
    book.kind = BookFieldSanitizer.clean(record.kind);
    book.status = BookFieldSanitizer.clean(record.status);
    book.intro = BookFieldSanitizer.clean(record.intro);
    book.coverUrl = record.coverUrl;
    book.wordCount = BookFieldSanitizer.clean(record.wordCount);
    book.latestChapterTitle = BookFieldSanitizer.clean(record.lastChapter);
    book.updateTime = BookFieldSanitizer.clean(record.updateTime);
    book.bookUrl = record.bookUrl;
    book.tocUrl = record.tocUrl;
    book.origin = source.bookSourceUrl;
    book.originName = source.bookSourceName;
    book.type = NativeSourceService.typeBits(record.type, source);
    // 媒体类型同时写进书籍变量，加入书架后各处的类型判定都读得到。
    book.variable = BookUrlResolver.setVariableJson('', 'tab',
      record.type === 'video' ? 'video' : NativeSourceService.typeName(book.type, source));
    book.bookSourceComment = source.bookSourceComment;
    book.customOrder = source.customOrder;
    book.weight = source.weight;
    return book;
  }

  private static bookInput(source: BookSource, book: Book): NativeBookInput {
    let vars: Record<string, NativeValue> = {};
    try {
      const parsed = JSON.parse(book.variable || '{}') as Object;
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) vars = parsed as Record<string, NativeValue>;
    } catch (e) {
    }
    return {
      bookUrl: book.bookUrl,
      tocUrl: book.tocUrl,
      name: book.name,
      author: book.author,
      kind: book.kind,
      type: NativeSourceService.typeName(book.type, source, book.variable),
      vars: vars
    };
  }

  static async search(source: BookSource, http: HttpClient, keyword: string, cancelled: () => boolean,
    maxResponseBytes: number = 0, debugContext: BookSourceDebugContext | null = null,
    page: number = 1): Promise<SearchBook[]> {
    const records = await NativeSourceService.runner(source, http, cancelled, maxResponseBytes, debugContext)
      .search(keyword, page);
    return records.map((record: NativeBookRecord): SearchBook => NativeSourceService.toSearchBook(source, record));
  }

  static async exploreMenus(source: BookSource, http: HttpClient,
    debugContext: BookSourceDebugContext | null = null): Promise<NativeMenuEntry[]> {
    return await NativeSourceService.runner(source, http, (): boolean => false, 0, debugContext).exploreMenus();
  }

  static async explore(source: BookSource, http: HttpClient, target: string, page: number,
    debugContext: BookSourceDebugContext | null = null): Promise<SearchBook[]> {
    const records = await NativeSourceService.runner(source, http, (): boolean => false, 0, debugContext)
      .explore(target, page);
    return records.map((record: NativeBookRecord): SearchBook => NativeSourceService.toSearchBook(source, record));
  }

  static async getBookInfo(source: BookSource, http: HttpClient, book: Book,
    debugContext: BookSourceDebugContext | null = null): Promise<Book> {
    book.origin = source.bookSourceUrl;
    book.originName = source.bookSourceName;
    const record = await NativeSourceService.runner(source, http, (): boolean => false, 0, debugContext)
      .detail(NativeSourceService.bookInput(source, book));
    book.name = BookFieldSanitizer.prefer(record.name, book.name);
    book.author = BookFieldSanitizer.prefer(record.author, book.author);
    book.kind = BookFieldSanitizer.prefer(record.kind, book.kind);
    book.status = BookFieldSanitizer.prefer(record.status, book.status);
    book.intro = BookFieldSanitizer.prefer(record.intro, book.intro);
    book.wordCount = BookFieldSanitizer.prefer(record.wordCount, book.wordCount);
    book.latestChapterTitle = BookFieldSanitizer.prefer(record.lastChapter, book.latestChapterTitle);
    book.updateTime = BookFieldSanitizer.prefer(record.updateTime, book.updateTime);
    book.coverUrl = SourceCoverUrl.isEncoded(record.coverUrl) ? record.coverUrl : book.coverUrl || record.coverUrl;
    book.tocUrl = record.tocUrl || book.tocUrl || book.bookUrl;
    if (record.type) book.type = NativeSourceService.typeBits(record.type, source);
    else if (!Number(book.type)) book.type = NativeSourceService.typeBits('', source);
    // 详情给出了类型就以它为准；没给时保留搜索或发现阶段已经定下的类型。
    let variable = BookUrlResolver.setVariableJson(book.variable, 'tab', record.type === 'video' ? 'video' :
      NativeSourceService.typeName(book.type, source, record.type ? '' : book.variable));
    for (const key of Object.keys(record.keep)) {
      variable = BookUrlResolver.setVariableJson(variable, key, record.keep[key]);
    }
    book.variable = variable;
    return book;
  }

  static async getChapterList(source: BookSource, http: HttpClient, book: Book,
    limit: number = 0, debugContext: BookSourceDebugContext | null = null): Promise<BookChapter[]> {
    const records = await NativeSourceService.runner(source, http, (): boolean => false, 0, debugContext)
      .toc(NativeSourceService.bookInput(source, book), limit);
    const chapters: BookChapter[] = [];
    let pendingVolume = '';
    for (const record of records) {
      // 分卷标题不占章节位置，记到它后面第一章上，由目录在该章上方显示。
      if (record.isVolume) {
        pendingVolume = record.title;
        continue;
      }
      if (!record.url) continue;
      const chapter = new BookChapter();
      chapter.title = record.title;
      chapter.url = record.url;
      chapter.bookUrl = book.bookUrl;
      chapter.index = chapters.length;
      chapter.isVip = record.isVip;
      chapter.isPay = record.isPay;
      chapter.variable = BookUrlResolver.setVariableJson(chapter.variable, 'baseUrl', record.url);
      if (record.tag) chapter.variable = BookUrlResolver.setVariableJson(chapter.variable, 'updateTime', record.tag);
      if (pendingVolume) {
        chapter.variable = BookUrlResolver.setVariableJson(chapter.variable, 'volume', pendingVolume);
        pendingVolume = '';
      }
      chapters.push(chapter);
    }
    return chapters;
  }

  static async getContent(source: BookSource, http: HttpClient, book: Book, chapter: BookChapter,
    cancelled: () => boolean, debugContext: BookSourceDebugContext | null = null): Promise<NativeContentResult> {
    const result = await NativeSourceService.runner(source, http, cancelled, 0, debugContext).content(
      NativeSourceService.bookInput(source, book), { url: chapter.url, title: chapter.title, index: chapter.index });
    if (result.kind === 'text') result.text = NativeSourceService.withCommentMarkers(result);
    // 图片和音频要带请求头、图片要解密时，沿用应用已有的写法：地址后面跟一个选项对象。
    const hasHeaders = Object.keys(result.mediaHeaders).length > 0;
    if (result.kind === 'audio' && result.text && hasHeaders) {
      result.text += `,${JSON.stringify({ headers: result.mediaHeaders })}`;
    }
    if (result.kind === 'images' && (hasHeaders || result.imageDecode)) {
      const options: Record<string, Object> = {};
      if (hasHeaders) options['headers'] = result.mediaHeaders;
      if (result.imageDecode) options['decode'] = result.imageDecode;
      result.images = result.images.map((url: string, index: number): string =>
        `${url},${JSON.stringify({ ...options, imageIndex: index })}`);
    }
    return result;
  }

  /**
   * 把段评和章末评论入口写成阅读器的交互标记。标签沿用阅读器已有的约定：
   * 以数字结尾的显示为带条数的气泡，含「本章说」的显示为章末入口。
   */
  private static withCommentMarkers(result: NativeContentResult): string {
    if (result.paragraphComments.length === 0 && !result.chapterCommentUrl && result.links.length === 0) {
      return result.text;
    }
    const lines = result.text.split('\n');
    for (const comment of result.paragraphComments) {
      if (comment.line < 0 || comment.line >= lines.length) continue;
      lines[comment.line] += ReaderActionMarker.create(`段评 ${comment.count > 99 ? '99+' : comment.count}`,
        comment.url, '段评');
    }
    for (const link of result.links) {
      // 请求按钮把渲染好的请求编进标记地址，点击时由 runReaderAction 取出执行。
      const target = link.request ? NativeSourceService.READER_ACTION_SCHEME +
        encodeURIComponent(JSON.stringify({ r: link.request, m: link.message })) : link.url;
      const button = ReaderActionMarker.create(link.label, target, link.label);
      if (button) lines.push('', button);
    }
    if (result.chapterCommentUrl) {
      const tail = ReaderActionMarker.create('本章说', result.chapterCommentUrl, '本章说');
      if (tail) lines.push('', tail);
    }
    return lines.join('\n');
  }
}
