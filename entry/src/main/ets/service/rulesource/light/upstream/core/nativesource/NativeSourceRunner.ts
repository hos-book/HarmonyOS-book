/**
 * 原生书源执行器：按定义依次完成请求、取列表、取字段，全程不经过任何脚本引擎。
 *
 * 网络与选择器通过 NativeRunnerHost 注入，本文件不依赖系统 API，可直接在 Node 回归脚本中加载。
 */

import { CooperativeScheduler } from '../concurrency/CooperativeScheduler';
import { NativeExpr, NativeExprError, NativeScope } from './NativeExpr';
import { SourceCoverUrl } from './SourceCoverUrl';
import { NativeJsPrelude } from './NativeJsPrelude';
import { NativeScriptHost, NativeScriptLimits } from './NativeScriptHost';
import type { NativeScriptEngine } from './NativeScriptHost';
import type { NativeBrowserResult } from './NativeSourceInteraction';
import type { NativeExprHost, NativeScriptLibrary, NativeValue } from './NativeExpr';
import type {
  NativeActionSpec, NativeVarSpec, NativeCommentsSpec, NativeContentSpec, NativeDynamicMenuSpec, NativeFetchSpec, NativeMenuSpec,
  NativeRequestSpec,
  NativeSourceDefinition, NativeStageSpec, NativeTocSpec
} from './NativeSourceSpec';

export interface NativeRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: string;
  webView: boolean;
  /** 网页渲染时要等待出现的元素（CSS 选择器），空串表示不等待。 */
  webWaitFor: string;
  /** 网页渲染的最长等待秒数。 */
  webTimeout: number;
  charset: string;
  retry: number;
  /** 主请求：遇到验证页时应提示用户去验证。附加请求不触发。 */
  primary: boolean;
  /** 网页渲染后在页面里执行的表达式（脚本的 browser.render），结果作为响应正文。 */
  webJs?: string;
}

export interface NativeLoginState {
  ok: boolean;
  name: string;
  message: string;
}

export interface NativeResponse {
  ok: boolean;
  status: number;
  body: string;
  url: string;
  error: string;
}

/** 一条规则的求值记录，供调试页显示。 */
export interface NativeRuleTrace {
  field: string;
  rule: string;
  /** expression | template | selector */
  type: string;
  count: number;
  preview: string;
  error: string;
}

/** 已保存的登录凭据（表单登录得到的）。 */
export interface NativeLoginCredential {
  token: string;
  user: string;
}

export interface NativeLoginResult {
  ok: boolean;
  token: string;
  user: string;
  message: string;
}

/** 一个动作按钮：open 有值时打开网页，否则点击后执行对应序号的请求。 */
export interface NativeActionEntry {
  index: number;
  label: string;
  open: string;
}

export interface NativeRunnerHost extends NativeExprHost {
  fetch(request: NativeRequest): Promise<NativeResponse>;
  /** 调试时记录规则求值；不调试时不提供。 */
  trace?(entry: NativeRuleTrace): void;
  /** 读取声明式缓存；没有或已过期时返回 undefined。 */
  cacheGet?(key: string): NativeValue;
  cachePut?(key: string, value: NativeValue, ttlSeconds: number): void;
  /** 按列表规则取出元素：JSON 元素返回对象，HTML 元素返回外层 HTML 文本。 */
  selectItems(content: string, rule: string, baseUrl: string): NativeValue[];
  /** 书源 js 字段的执行器；不提供时调用 JS 函数会报“不支持”。 */
  scriptLibrary?(code: string): NativeScriptLibrary;
  evaluateExpression?(code: string, library: string, expression: string, scope: Record<string, NativeValue>,
    template: boolean, cancelled: () => boolean): Promise<NativeValue>;
  /** 脚本阶段的后台引擎；不提供时脚本阶段报“不支持”。 */
  scriptEngine?(code: string): NativeScriptEngine;
  /** 脚本里的 cookie.*：name 为空时读整条 Cookie、删除全部。 */
  cookieGet?(url: string, name: string): string;
  cookieSet?(url: string, value: string): void;
  cookieRemove?(url: string, name: string): void;
  /** 脚本写书源变量后保存全部变量（与书源设置页同一份）。 */
  saveVars?(values: Record<string, NativeValue>): Promise<void>;
  /** 脚本保存登录凭据（与表单登录同一份）。 */
  saveCredential?(token: string, user: string): Promise<void>;
  deviceId?(): string;
  userAgent?(): string;
  /** 脚本的 ui.toast。 */
  toast?(message: string): void;
  /** 脚本的 ui.refreshExplore。 */
  refreshExplore?(): Promise<void>;
  /** 脚本的 browser.verify / browser.open：wait 为 true 时等用户完成并返回页面。 */
  openBrowser?(url: string, title: string, wait: boolean): Promise<NativeBrowserResult>;
  /** 非交互场景需要网页验证时，交给应用现有的「去验证」流程。 */
  requestVerification?(url: string, title: string): void;
}

/** 设置页动态选项的结果：失败时 options 为空、error 为原因。 */
export interface NativeVarOptions {
  options: string[];
  error: string;
}

export interface NativeBookRecord {
  name: string;
  author: string;
  kind: string;
  intro: string;
  coverUrl: string;
  wordCount: string;
  lastChapter: string;
  updateTime: string;
  status: string;
  bookUrl: string;
  tocUrl: string;
  /** text | audio | comic | video，空串表示沿用书源类型。 */
  type: string;
  keep: Record<string, string>;
}

export interface NativeBookInput {
  bookUrl: string;
  tocUrl: string;
  name: string;
  author: string;
  kind: string;
  type: string;
  vars: Record<string, NativeValue>;
}

export interface NativeChapterInput {
  url: string;
  title: string;
  index: number;
}

export interface NativeChapterRecord {
  title: string;
  url: string;
  isVip: boolean;
  isPay: boolean;
  isVolume: boolean;
  tag: string;
}

export interface NativeMenuEntry {
  title: string;
  /** 空串表示分组标题。 */
  target: string;
}

export interface NativeParagraphComment {
  /** 正文行号（按换行切分后的下标）。 */
  line: number;
  count: number;
  url: string;
}

export interface NativeContentResult {
  /** text | images | audio | video */
  kind: string;
  text: string;
  baseUrl: string;
  paragraphComments: NativeParagraphComment[];
  /** 整章评论页地址，空串表示没有。 */
  chapterCommentUrl: string;
  /** 正文末尾的链接按钮。 */
  links: NativeContentLink[];
  /** 漫画的图片地址（kind 为 images 时）。 */
  images: string[];
  /** 取图片、音频时附带的请求头。 */
  mediaHeaders: Record<string, string>;
  imageDecode: NativeImageDecode | null;
}

export interface NativeContentLink {
  label: string;
  /** 要打开的网页；为空时表示这是一个请求动作。 */
  url: string;
  /** 请求动作：已经渲染好的请求，以及请求完成后求提示文字的规则。 */
  request: NativeRequest | null;
  message: string;
}

/** 图片解密参数，密钥与 IV 为十六进制。 */
export interface NativeImageDecode {
  script?: string;
  params?: Record<string, NativeValue>;
  processPlainImages?: boolean;
  algorithm: string;
  key: string;
  iv: string;
  ivPrefixBytes?: number;
}

export class NativeSourceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NativeSourceError';
  }
}

interface StagePage {
  scope: NativeScope;
  baseUrl: string;
}

/** 详情页的响应，留给紧接着的目录第一页复用（目录与详情是同一个请求时）。 */
interface KeptPage {
  body: string;
  baseUrl: string;
  keptAt: number;
}

/** 一次脚本函数运行的结果。 */
interface ScriptRun {
  value: NativeValue;
  requests: number;
  ms: number;
}

/** loadStage 对响应的处理：keep 记下供之后复用，take 有记下的同一请求时直接用、不再请求。 */
type StageReuse = '' | 'keep' | 'take';

const MENU_STATIC = 'native:menu:';
/** 脚本阶段不写 fields 时，按同名键取值的字段。 */
const BOOK_FIELD_NAMES = ['name', 'author', 'kind', 'intro', 'coverUrl', 'wordCount', 'lastChapter', 'updateTime',
  'status', 'bookUrl', 'tocUrl', 'type'];
const CHAPTER_FIELD_NAMES = ['title', 'url', 'isVip', 'isPay', 'isVolume', 'tag'];
const STAGE_NAMES: Record<string, string> = {
  '搜索': 'search', '发现': 'explore', '详情': 'detail', '目录': 'toc', '正文': 'content', '发现分类': 'menus'
};
const MENU_ITEM = 'native:item:';
const MAX_TOC_PAGES = 1000;
/** 目录或正文的 nextUrl 一次给出多个地址时，剩余分页每批并发请求的页数；书源可用 batch 改为 1～16。 */
const DEFAULT_PAGE_BATCH = 4;
const MAX_PAGE_BATCH = 16;
/** 记下的详情页只在这段时间内、只复用一次；打开书、换源都是取完详情立即取目录。 */
const KEPT_PAGE_TTL_MS = 60 * 1000;
const MAX_KEPT_PAGES = 4;
/** 正文分页最多跟随的页数，以及多页拼接后的正文长度上限（与兼容书源相同的 8 MB）。 */
const MAX_CONTENT_PAGES = 200;
const MAX_CONTENT_CHARS = 8 * 1024 * 1024;
const MAX_LIST_ITEMS = 20000;
const DEFAULT_COMMENT_BUBBLES = 60;
const MAX_COMMENT_BUBBLES = 300;

/**
 * 逐章取字段时让出主线程，节奏与兼容书源的 RuleExecutionService 相同：连续执行约 6 ms 让出一次，
 * 距上次空出整帧超过 50 ms 时改为空出一帧（只让 1 ms 可能仍落在同一个原生定时器任务里）。
 */
class UiPacer {
  private static readonly SLICE_MS: number = CooperativeScheduler.DEFAULT_UI_SLICE_MS;
  private static readonly FRAME_MS: number = 50;
  private sliceStartedAt: number = Date.now();
  private frameYieldedAt: number = Date.now();

  /** 时间片用完时让出；没用完时不产生 await，避免每章多一次微任务。 */
  due(): boolean {
    return Date.now() - this.sliceStartedAt >= UiPacer.SLICE_MS;
  }

  async yield(): Promise<void> {
    if (Date.now() - this.frameYieldedAt >= UiPacer.FRAME_MS) {
      await CooperativeScheduler.yieldToNextUiFrame();
      this.frameYieldedAt = Date.now();
    } else {
      await CooperativeScheduler.yieldToEventLoop();
    }
    this.sliceStartedAt = Date.now();
  }
}

export class NativeSourceRunner {
  private static keptPages: Map<string, KeptPage> = new Map<string, KeptPage>();
  private definition: NativeSourceDefinition;
  private host: NativeRunnerHost;
  private expr: NativeExpr;
  private varValues: Record<string, string>;
  private cancelled: () => boolean = (): boolean => false;
  private credential: NativeLoginCredential = { token: '', user: '' };
  /** 已保存的全部书源变量，包括没有在 vars 里声明、由脚本写入的键。 */
  private storedVars: Record<string, NativeValue>;
  /** 脚本的 temp：只在这个运行器（一次操作）里有效。 */
  private temp: Map<string, NativeValue> = new Map();
  /** 详情阶段脚本用 keep() 记下的书籍变量。 */
  private scriptKeep: Record<string, string> | null = null;
  private engine: NativeScriptEngine | null = null;

  constructor(definition: NativeSourceDefinition, host: NativeRunnerHost, storedVars: Record<string, NativeValue> = {}) {
    this.definition = definition;
    this.host = host;
    this.expr = new NativeExpr(host).loadLibrary(definition.lib).loadScript(NativeSourceRunner.scriptOf(definition, host));
    this.varValues = NativeSourceRunner.resolveVars(definition, storedVars);
    this.storedVars = Object.assign({}, storedVars || {});
  }

  private static scriptOf(definition: NativeSourceDefinition, host: NativeRunnerHost): NativeScriptLibrary | null {
    const code = definition.js || '';
    if (!code.trim()) return null;
    if (host.scriptLibrary) return host.scriptLibrary(code);
    // 宿主没有脚本引擎时，调用 JS 函数给出明确原因，而不是“没有这个内置函数”。
    return {
      has: (): boolean => true,
      call: (name: string): NativeValue => {
        throw new NativeExprError(`当前环境不支持 JS 函数库，无法调用 “${name}”`);
      }
    };
  }

  /** 表单登录保存下来的凭据，规则里通过 login.token / login.user 读取。 */
  setCredential(credential: NativeLoginCredential): NativeSourceRunner {
    this.credential = { token: credential.token || '', user: credential.user || '' };
    return this;
  }

  /** 表单登录：用用户填写的值发登录请求。 */
  async submitLogin(form: Record<string, string>): Promise<NativeLoginResult> {
    const login = this.definition.login;
    if (login && login.script) return await this.scriptLogin(String(login.script).trim(), form);
    const submit = login ? login.submit : undefined;
    if (!submit) return { ok: false, token: '', user: '', message: '该书源没有配置表单登录' };
    const scope = (await this.baseScope()).set('form', form);
    const response = await this.host.fetch((await this.buildRequest(submit, scope, '')));
    if (!response.ok || !response.body) {
      return { ok: false, token: '', user: '', message: this.describeFailure('登录', response) };
    }
    const page = this.responseScope(scope, response.body, response.url);
    const ok = NativeExpr.isTruthy((await this.value(submit.ok, page, false, 'login.submit.ok')));
    const message = submit.message ?
      NativeExpr.toText((await this.value(submit.message, page, false, 'login.submit.message'))).trim() : '';
    if (!ok) return { ok: false, token: '', user: '', message: message || '登录失败' };
    return {
      ok: true,
      token: submit.token ? NativeExpr.toText((await this.value(submit.token, page, false, 'login.submit.token'))).trim() : '',
      user: submit.user ? NativeExpr.toText((await this.value(submit.user, page, false, 'login.submit.user'))).trim() : '',
      message: message
    };
  }

  /**
   * 脚本登录：函数拿到 ctx.form，自己发请求，成功时调用 login.save(令牌, 用户名)。返回值可以是提示文字，
   * 或 { ok, message }；没有明确给出 ok 时，以是否保存了凭据为准。密码只在这次调用里使用，不会保存。
   */
  private async scriptLogin(fn: string, form: Record<string, string>): Promise<NativeLoginResult> {
    const scope = (await this.baseScope()).set('form', form);
    const before = this.credential.token;
    const ctx = this.scriptContext(scope, 'login');
    ctx['form'] = form;
    let value: NativeValue;
    try {
      value = (await this.runScriptFunction(fn, ctx, 'login.script', scope, true, null)).value;
    } catch (e) {
      return { ok: false, token: '', user: '', message: `登录失败：${(e as Error).message}` };
    }
    const saved = !!this.credential.token && this.credential.token !== before;
    const explicit = value && typeof value === 'object' && !Array.isArray(value) && value['ok'] !== undefined;
    const ok = explicit ? NativeExpr.isTruthy(value['ok']) : saved;
    const message = NativeSourceRunner.scriptMessage(value);
    return {
      ok: ok,
      token: ok ? this.credential.token : '',
      user: ok ? this.credential.user : '',
      message: message || (ok ? '' : '登录失败')
    };
  }

  /** 脚本返回值里给用户看的提示：字符串本身，或对象的 message。 */
  private static scriptMessage(value: NativeValue): string {
    if (typeof value === 'string') return value.trim();
    if (value && typeof value === 'object' && !Array.isArray(value) && value['message'] !== undefined) {
      return NativeExpr.toText(value['message']).trim();
    }
    return '';
  }

  /**
   * 书源设置页的动态选项：vars 里写了 optionsScript 的变量，运行对应函数取选项列表。
   * 函数失败时给出原因，设置页退回到 options 里写死的选项。
   */
  async varOptions(key: string = ''): Promise<Record<string, NativeVarOptions>> {
    const result: Record<string, NativeVarOptions> = {};
    const specs = (this.definition.vars || []).filter((item: NativeVarSpec): boolean =>
      !!item.optionsScript && (!key || item.key === key));
    if (specs.length === 0) return result;
    const scope = await this.baseScope();
    for (const item of specs) {
      const fn = String(item.optionsScript).trim();
      const ctx = this.scriptContext(scope, 'options');
      ctx['key'] = item.key;
      try {
        const value: NativeValue = (await this.runScriptFunction(fn, ctx, `vars.${item.key}`, scope, true, null)).value;
        const options = (Array.isArray(value) ? value : []).map((option: NativeValue): string => NativeExpr.toText(option).trim())
          .filter((option: string): boolean => !!option);
        result[item.key] = options.length > 0 ? { options: options, error: '' } :
          { options: [], error: '没有拿到选项' };
      } catch (e) {
        result[item.key] = { options: [], error: (e as Error).message };
      }
    }
    return result;
  }

  /** 表单登录的辅助请求（发送验证码等），返回提示文字。 */
  async sendLoginCode(form: Record<string, string>): Promise<string> {
    const spec = this.definition.login ? this.definition.login.sendCode : undefined;
    if (!spec) return '该书源没有配置这个操作';
    return await this.performAction(spec, (await this.baseScope()).set('form', form), 'login.sendCode', { form: form });
  }

  /** 书源设置页里可用的动作按钮。 */
  async actions(): Promise<NativeActionEntry[]> {
    const specs = this.definition.actions || [];
    if (specs.length === 0) return [];
    const scope = await this.baseScope();
    const entries: NativeActionEntry[] = [];
    for (let i = 0; i < specs.length; i++) {
      const spec = specs[i];
      if (spec.when && !NativeExpr.isTruthy((await this.value(spec.when, scope, false, `actions[${i}].when`)))) continue;
      const label = NativeExpr.toText((await this.template(spec.label, scope))).trim();
      if (!label) continue;
      const open = spec.open ? NativeExpr.resolveUrl(NativeExpr.toText((await this.template(spec.open, scope))).trim(),
        this.definition.url) : '';
      entries.push({ index: i, label: label, open: /^https?:\/\//i.test(open) ? open : '' });
    }
    return entries;
  }

  /** 执行一个动作按钮，返回提示文字。 */
  async runAction(index: number): Promise<string> {
    const spec = (this.definition.actions || [])[index];
    if (!spec) return '没有这个操作';
    return await this.performAction(spec, await this.baseScope(), `actions[${index}]`);
  }

  /** 执行正文里的请求按钮：请求在取正文时已经渲染好，这里只发出并求提示文字。 */
  async runLinkAction(request: NativeRequest, messageSpec: string): Promise<string> {
    const scope = await this.baseScope();
    const response = await this.host.fetch(request);
    if (!response.ok) return this.describeFailure('操作', response);
    if (!messageSpec) return '已完成';
    const page = this.responseScope(scope, response.body || '', response.url || request.url);
    return NativeExpr.toText((await this.value(messageSpec, page, false, 'content.links.message'))).trim() || '已完成';
  }

  private async performAction(spec: NativeActionSpec, scope: NativeScope, field: string,
    extra: Record<string, NativeValue> = {}): Promise<string> {
    if (spec.script) {
      const fn = String(spec.script).trim();
      const ctx = this.scriptContext(scope, 'action');
      ctx['action'] = NativeExpr.toText((await this.template(spec.label || '', scope))).trim();
      for (const key of Object.keys(extra)) ctx[key] = extra[key];
      try {
        const run = await this.runScriptFunction(fn, ctx, field, scope, true, null);
        return NativeSourceRunner.scriptMessage(run.value) || '已完成';
      } catch (e) {
        return `操作失败：${(e as Error).message}`;
      }
    }
    const request = (await this.buildRequest(spec, scope, ''));
    if (!request.url) return '操作没有可用的地址';
    const response = await this.host.fetch(request);
    if (!response.ok) return this.describeFailure('操作', response);
    if (!spec.message) return '已完成';
    const page = this.responseScope(scope, response.body || '', response.url || request.url);
    return NativeExpr.toText((await this.value(spec.message, page, false, `${field}.message`))).trim() || '已完成';
  }

  setCancelCheck(check: () => boolean): NativeSourceRunner {
    this.cancelled = check;
    return this;
  }

  /** 合并默认值与已保存的值；已保存的值不在选项内时回退到默认值。 */
  static resolveVars(definition: NativeSourceDefinition, stored: Record<string, NativeValue>): Record<string, string> {
    const values: Record<string, string> = {};
    for (const item of definition.vars || []) {
      const options = Array.isArray(item.options) ? item.options.map((option: string): string => String(option)) : [];
      const fallback = item.default !== undefined ? String(item.default) : (options.length > 0 ? options[0] : '');
      const saved = stored && stored[item.key] !== undefined && stored[item.key] !== null ? String(stored[item.key]) : '';
      values[item.key] = saved && (item.optionsScript || options.length === 0 || options.indexOf(saved) >= 0) ? saved : fallback;
    }
    return values;
  }

  async search(key: string, page: number = 1): Promise<NativeBookRecord[]> {
    const stage = this.scripted(this.requireStage(this.definition.search, '搜索'), BOOK_FIELD_NAMES);
    const scope = (await this.baseScope()).set('key', key).set('page', page);
    const loaded = await this.loadStage(stage, scope, '', '搜索');
    return (await this.readBooks(stage, loaded, 'search'));
  }

  /** 用书源声明的检查接口确认登录状态。 */
  async checkLogin(): Promise<NativeLoginState> {
    const check = this.definition.login ? this.definition.login.check : undefined;
    if (!check) return { ok: false, name: '', message: '该书源没有配置登录检查' };
    const scope = (await this.baseScope());
    const request = (await this.buildRequest(check, scope, ''));
    const response = await this.host.fetch(request);
    if (!response.ok || !response.body) {
      return { ok: false, name: '', message: this.describeFailure('登录检查', response) };
    }
    const pageScope = this.responseScope(scope, response.body, response.url || request.url);
    const ok = NativeExpr.isTruthy((await this.value(check.ok, pageScope)));
    return {
      ok: ok,
      name: ok && check.name ? NativeExpr.toText((await this.value(check.name, pageScope))).trim() : '',
      message: ok ? '' : '未登录或登录已失效'
    };
  }

  async exploreMenus(): Promise<NativeMenuEntry[]> {
    const explore = this.requireStage(this.definition.explore, '发现');
    const scope = (await this.baseScope());
    const entries: NativeMenuEntry[] = [];
    const menus = explore.menus || [];
    for (let i = 0; i < menus.length; i++) {
      const menu = menus[i];
      if (menu.when && !NativeExpr.isTruthy((await this.value(menu.when, scope)))) continue;
      const title = NativeExpr.toText((await this.template(menu.title || '', scope)));
      if (!title) continue;
      entries.push({ title: title, target: menu.url ? `${MENU_STATIC}${i}` : '' });
    }
    const dynamic = explore.dynamicMenus ? NativeSourceRunner.scriptedMenus(explore.dynamicMenus) : undefined;
    if (dynamic && dynamic.script) {
      // 脚本分类：函数的返回值当作页面，之后的 list、title、target 照常求值。
      let page: StagePage | null = null;
      try {
        page = await this.loadScriptStage(dynamic, scope, '发现分类');
      } catch (e) {
        if (entries.length === 0) throw e;
      }
      if (page) {
        // 返回的是“名称::地址”文本（与兼容书源的 exploreUrl 相同）时，拆成分类数组。
        if (!(explore.dynamicMenus && explore.dynamicMenus.list) && page.scope.get('data') === null) {
          page.scope.set('__items', NativeSourceRunner.menuTextItems(NativeExpr.toText(page.scope.get('body'))));
        }
        await this.readMenuItems(dynamic, page.scope, page.baseUrl, entries);
      }
    } else if (dynamic) {
      const request = await this.buildRequest(dynamic, scope, '');
      if (request.url) {
        const response = await this.host.fetch(request);
        if (!response.ok || !response.body) {
          if (entries.length === 0) throw new NativeSourceError(this.describeFailure('发现分类', response));
        } else {
          const baseUrl = response.url || request.url;
          await this.readMenuItems(dynamic, this.responseScope(scope, response.body, baseUrl), baseUrl, entries);
        }
      }
    }
    return entries;
  }

  private async readMenuItems(dynamic: NativeDynamicMenuSpec, pageScope: NativeScope, baseUrl: string,
    entries: NativeMenuEntry[]): Promise<void> {
    const items = await this.listItems(dynamic.list || '', pageScope, baseUrl);
    for (const item of items) {
      const itemScope = pageScope.child().set('item', item);
      const title = NativeExpr.toText(await this.value(dynamic.title || '', itemScope)).trim();
      if (!title) continue;
      // 目标地址里通常带页码，到真正打开分类时再渲染，这里只记下条目本身。
      const hasTarget = NativeExpr.isTruthy(await this.value(dynamic.target || '', itemScope.child().set('page', 1)));
      entries.push({ title: title, target: hasTarget ? MENU_ITEM + JSON.stringify(item) : '' });
    }
  }

  /** “名称::地址”文本按行或 && 分成分类；没有 :: 的是分组标题。 */
  private static menuTextItems(text: string): NativeValue[] {
    const items: NativeValue[] = [];
    for (const part of text.split(/&&|\r?\n/)) {
      const line = part.trim();
      if (!line) continue;
      const at = line.indexOf('::');
      const title = (at < 0 ? line : line.substring(0, at)).trim();
      const url = at < 0 ? '' : line.substring(at + 2).trim();
      if (!title) continue;
      items.push(url ? { title: title, url: url } : { title: title });
    }
    return items;
  }

  /** 脚本分类没写 list、title、target 时：返回数组的每项一条，按 title、url 取，url 里的 {{page}} 换成页码。 */
  private static scriptedMenus(dynamic: NativeDynamicMenuSpec): NativeDynamicMenuSpec {
    if (!dynamic.script) return dynamic;
    return Object.assign({}, dynamic, {
      list: dynamic.list || '= __items',
      title: dynamic.title || '$.title',
      target: dynamic.target || "= replaceText(str($.url ?? ''), '{{page}}', str(page))"
    });
  }

  async explore(target: string, page: number = 1): Promise<NativeBookRecord[]> {
    const explore = this.scripted(this.requireStage(this.definition.explore, '发现'), BOOK_FIELD_NAMES);
    const scope = (await this.baseScope()).set('page', page);
    let url = '';
    let title = '';
    let menuItem: NativeValue = null;
    let menu: NativeMenuSpec | undefined = undefined;
    if (target.startsWith(MENU_STATIC)) {
      menu = (explore.menus || [])[Number(target.substring(MENU_STATIC.length))];
      url = menu && menu.url ? NativeExpr.toText((await this.template(menu.url, scope))) : '';
      title = menu ? NativeExpr.toText((await this.template(menu.title || '', scope))) : '';
    } else if (target.startsWith(MENU_ITEM) && explore.dynamicMenus) {
      let item: NativeValue = null;
      try {
        item = JSON.parse(target.substring(MENU_ITEM.length));
      } catch (e) {
        item = null;
      }
      const dynamic = NativeSourceRunner.scriptedMenus(explore.dynamicMenus);
      url = NativeExpr.toText(await this.value(dynamic.target || '', scope.child().set('item', item)));
      menuItem = item;
    }
    if (!url) throw new NativeSourceError('发现分类没有可用的地址');
    const stage: NativeStageSpec = Object.assign({}, explore, {
      url: '= __url', headers: Object.assign({}, explore.headers || {}, menu && menu.headers ? menu.headers : {})
    });
    // 静态分类可以各用各的请求方法和请求体，一个书源对接请求方式不同的几个接口。
    if (menu && menu.method !== undefined) stage.method = menu.method;
    if (menu && menu.body !== undefined) stage.body = menu.body;
    if (menu && menu.list !== undefined) stage.list = menu.list;
    if (menu && menu.fields !== undefined) stage.fields = menu.fields;
    const loaded = await this.loadStage(stage,
      scope.child().set('__url', url).set('__title', title).set('__menuItem', menuItem), '', '发现');
    return (await this.readBooks(stage, loaded, 'explore'));
  }

  async detail(book: NativeBookInput): Promise<NativeBookRecord> {
    const stage = this.scripted(this.definition.detail || {}, BOOK_FIELD_NAMES);
    const scope = (await this.baseScope()).set('book', book);
    this.scriptKeep = stage.script ? {} : null;
    let loaded: StagePage;
    let scriptKeep: Record<string, string> = {};
    try {
      loaded = await this.loadStage(stage, scope, book.bookUrl, '详情', 'keep');
      scriptKeep = this.scriptKeep || {};
    } finally {
      this.scriptKeep = null;
    }
    await this.runExtraFetches(this.definition.detail ? this.definition.detail.fetch : undefined, loaded);
    const record = (await this.readBook(stage.fields || {}, loaded.scope, loaded.baseUrl, 'detail'));
    if (!record.bookUrl) record.bookUrl = book.bookUrl;
    for (const key of Object.keys(scriptKeep)) record.keep[key] = scriptKeep[key];
    const keep = this.definition.detail ? this.definition.detail.keep : undefined;
    if (keep) {
      for (const key of Object.keys(keep)) {
        record.keep[key] = NativeExpr.toText((await this.value(keep[key], loaded.scope, false, `detail.keep.${key}`)));
      }
    }
    return record;
  }

  async toc(book: NativeBookInput, limit: number = 0): Promise<NativeChapterRecord[]> {
    const stage = this.scripted(this.requireStage(this.definition.toc, '目录'), CHAPTER_FIELD_NAMES);
    const chapters: NativeChapterRecord[] = [];
    const visited: Set<string> = new Set();
    const defaultUrl = book.tocUrl || book.bookUrl;
    const nextStage: NativeStageSpec = Object.assign({}, stage, { url: '= __url' });
    const pageScope = async (page: number, url: string): Promise<NativeScope> =>
      (await this.baseScope()).set('book', book).set('page', page).child().set('__url', url);
    const pacer = new UiPacer();
    let nextUrl = '';
    for (let page = 1; page <= MAX_TOC_PAGES; page++) {
      if (this.cancelled()) return [];
      const loaded = await this.loadStage(page === 1 ? stage : nextStage, await pageScope(page, nextUrl),
        defaultUrl, '目录', page === 1 ? 'take' : '');
      visited.add(loaded.baseUrl);
      const full = await this.appendTocPage(stage, loaded, chapters, limit, pacer);
      if (this.cancelled()) return [];
      if (full) break;
      // 脚本阶段自己处理翻页。
      if (!stage.nextUrl || stage.script) break;
      const pending = (await this.nextUrls(stage.nextUrl, loaded, 'toc.nextUrl')).filter((url: string): boolean => !visited.has(url));
      if (pending.length === 0) break;
      if (pending.length === 1) {
        nextUrl = pending[0];
        visited.add(nextUrl);
        continue;
      }
      // 一次给出多个地址表示“剩余全部目录页”：按列出顺序分批并发请求，不再跟随这些页自己的 nextUrl。
      const listed = pending.slice(0, MAX_TOC_PAGES - page);
      const batchSize = this.batchSize(stage.batch);
      for (let offset = 0; offset < listed.length; offset += batchSize) {
        if (this.cancelled()) return [];
        const batch = listed.slice(offset, offset + batchSize);
        const pages = await Promise.all((await Promise.all(batch.map(async (url: string, index: number): Promise<StagePage> =>
          (await this.loadStage(nextStage, await pageScope(page + offset + index + 1, url), defaultUrl, '目录'))))));
        for (const listedPage of pages) {
          const listedFull = await this.appendTocPage(stage, listedPage, chapters, limit, pacer);
          if (this.cancelled()) return [];
          if (listedFull) return stage.reverse === true ? chapters.reverse() : chapters;
        }
      }
      break;
    }
    return stage.reverse === true ? chapters.reverse() : chapters;
  }

  /** 把一页目录的章节追加到 chapters；到达条数上限或已取消时返回 true。 */
  private async appendTocPage(stage: NativeTocSpec, loaded: StagePage, chapters: NativeChapterRecord[],
    limit: number, pacer: UiPacer): Promise<boolean> {
    const fields = stage.fields || {};
    for (const item of (await this.listItems(stage.list || '', loaded.scope, loaded.baseUrl, 'toc.list'))) {
      if (pacer.due()) {
        await pacer.yield();
        if (this.cancelled()) return true;
      }
      const itemScope = loaded.scope.child().set('item', item).set('index', chapters.length);
      const title = NativeExpr.toText((await this.value(fields['title'], itemScope, false, 'toc.fields.title'))).trim();
      if (!title) continue;
      const isVolume = NativeExpr.isTruthy((await this.value(fields['isVolume'], itemScope, false, 'toc.fields.isVolume')));
      const url = NativeExpr.resolveUrl(
        this.firstLine(this.first((await this.value(fields['url'], itemScope, false, 'toc.fields.url')))), loaded.baseUrl);
      if (!url && !isVolume) continue;
      chapters.push({
        title: title,
        url: url,
        isVip: NativeExpr.isTruthy((await this.value(fields['isVip'], itemScope, false, 'toc.fields.isVip'))),
        isPay: NativeExpr.isTruthy((await this.value(fields['isPay'], itemScope, false, 'toc.fields.isPay'))),
        isVolume: isVolume,
        tag: NativeExpr.toText((await this.value(fields['tag'] || fields['updateTime'], itemScope, false,
          'toc.fields.tag'))).trim()
      });
      if (chapters.length >= MAX_LIST_ITEMS || (limit > 0 && chapters.length >= limit)) return true;
    }
    return false;
  }

  /** nextUrl 的结果：一个地址是下一页；列表或多行文本是剩余全部分页。已补全、去重。 */
  private async nextUrls(spec: NativeValue, loaded: StagePage, field: string): Promise<string[]> {
    const raw = (await this.value(spec, loaded.scope, false, field));
    const values: NativeValue[] = Array.isArray(raw) ? raw : NativeExpr.toText(raw).split(/\r?\n/);
    const urls: string[] = [];
    for (const value of values) {
      const text = NativeExpr.toText(value).trim();
      const url = text ? NativeExpr.resolveUrl(text, loaded.baseUrl) : '';
      if (url && urls.indexOf(url) < 0) urls.push(url);
    }
    return urls;
  }

  /** 分页列表每批并发请求的页数：书源的 batch，没写或不合法时用默认值。 */
  private batchSize(batch: number | undefined): number {
    return Math.max(1, Math.min(Math.floor(Number(batch)) || DEFAULT_PAGE_BATCH, MAX_PAGE_BATCH));
  }

  /** 把一页正文（文本或图片）追加到结果里，返回追加的字符数。 */
  private async appendContentPage(stage: NativeContentSpec, kind: string, loaded: StagePage, parts: string[],
    imageUrls: string[]): Promise<number> {
    if (kind === 'images') {
      let added = 0;
      const images = (await this.value(stage.images, loaded.scope, true, 'content.images'));
      for (const image of Array.isArray(images) ? images : [images]) {
        const url = NativeExpr.resolveUrl(NativeExpr.toText(image).trim(), loaded.baseUrl);
        if (url) {
          imageUrls.push(url);
          const tag = `<img src="${url.replace(/"/g, '%22')}">`;
          parts.push(tag);
          added += tag.length;
        }
      }
      return added;
    }
    const text = (await this.value(stage.text, loaded.scope, false, 'content.text'));
    const added = Array.isArray(text) ?
      text.map((line: NativeValue): string => NativeExpr.toText(line)).join('\n') : NativeExpr.toText(text);
    parts.push(added);
    return added.length;
  }

  async content(book: NativeBookInput, chapter: NativeChapterInput): Promise<NativeContentResult> {
    const stage = this.scriptedContent(this.requireStage(this.definition.content, '正文'));
    const bookType = String(book.type || this.definition.type || 'text').toLowerCase();
    const kind = bookType === 'video' && stage.video ? 'video' : (bookType === 'audio' && stage.audio ? 'audio' :
      ((bookType === 'comic' || bookType === 'image') && stage.images ? 'images' :
        (stage.text ? 'text' : (stage.images ? 'images' : (stage.audio ? 'audio' : 'video')))));
    const empty = (baseUrl: string): NativeContentResult => ({
      kind: kind, text: '', baseUrl: baseUrl, paragraphComments: [], chapterCommentUrl: '', links: [],
      images: [], mediaHeaders: {}, imageDecode: null
    });
    if (this.cancelled()) return empty('');
    const pageScope = async (page: number, url: string): Promise<NativeScope> =>
      (await this.baseScope()).set('book', book).set('chapter', chapter).set('page', page).child().set('__url', url);
    const firstPage = await this.loadStage(stage, await pageScope(1, ''), chapter.url, '正文');
    const firstBase = firstPage.baseUrl;
    await this.runExtraFetches(stage.fetch, firstPage);
    if (kind === 'audio' || kind === 'video') {
      const audio = this.firstLine(this.first((await this.value(kind === 'audio' ? stage.audio : stage.video,
        firstPage.scope, false, `content.${kind}`))));
      if (!audio) throw new NativeSourceError((await this.mediaFailure(stage, firstPage, kind)));
      return {
        kind: kind, text: NativeExpr.resolveUrl(audio, firstPage.baseUrl), baseUrl: firstPage.baseUrl,
        paragraphComments: [], chapterCommentUrl: '', links: [], images: [],
        mediaHeaders: (await this.renderHeaders(stage.mediaHeaders, firstPage.scope)), imageDecode: null
      };
    }
    const parts: string[] = [];
    const imageUrls: string[] = [];
    let size = (await this.appendContentPage(stage, kind, firstPage, parts, imageUrls));
    const visited: Set<string> = new Set([firstBase, NativeExpr.resolveUrl(chapter.url, this.definition.url)]);
    const nextStage: NativeStageSpec = Object.assign({}, stage, { url: '= __url' });
    let loaded = firstPage;
    let page = 1;
    let skipped = 0;
    while (stage.nextUrl && !stage.script) {
      if (this.cancelled()) return empty(firstBase);
      const pending = (await this.nextUrls(stage.nextUrl, loaded, 'content.nextUrl'))
        .filter((url: string): boolean => !visited.has(url));
      if (pending.length === 0) break;
      if (page >= MAX_CONTENT_PAGES || size >= MAX_CONTENT_CHARS) {
        skipped = pending.length;
        break;
      }
      if (pending.length === 1) {
        visited.add(pending[0]);
        page++;
        loaded = await this.loadStage(nextStage, await pageScope(page, pending[0]), chapter.url, '正文');
        visited.add(loaded.baseUrl);
        await this.runExtraFetches(stage.fetch, loaded);
        size += (await this.appendContentPage(stage, kind, loaded, parts, imageUrls));
        continue;
      }
      // 一次给出多个地址表示“本章剩余全部分页”：按列出顺序分批并发请求，不再跟随这些页自己的 nextUrl。
      const listed = pending.slice(0, MAX_CONTENT_PAGES - page);
      skipped = pending.length - listed.length;
      const batchSize = this.batchSize(stage.batch);
      for (let offset = 0; offset < listed.length; offset += batchSize) {
        if (this.cancelled()) return empty(firstBase);
        if (size >= MAX_CONTENT_CHARS) {
          skipped += listed.length - offset;
          break;
        }
        const batch = listed.slice(offset, offset + batchSize);
        const pages = await Promise.all((await Promise.all(batch.map(async (url: string, index: number): Promise<StagePage> =>
          (await this.loadStage(nextStage, await pageScope(page + offset + index + 1, url), chapter.url, '正文'))))));
        for (const listedPage of pages) {
          await this.runExtraFetches(stage.fetch, listedPage);
          size += (await this.appendContentPage(stage, kind, listedPage, parts, imageUrls));
        }
      }
      break;
    }
    if (skipped > 0 && this.host.trace) {
      this.host.trace({
        field: 'content.nextUrl', rule: NativeExpr.toText(stage.nextUrl), type: 'limit', count: skipped, preview: '',
        error: `本章分页超过 ${MAX_CONTENT_PAGES} 页或正文超过 8 MB，后面 ${skipped} 页没有获取`
      });
    }
    let text = parts.join('\n');
    if (kind === 'text') {
      for (const rule of stage.replace || []) {
        if (!rule || !rule.pattern) continue;
        text = text.replace(new RegExp(rule.pattern, rule.flags === undefined ? 'g' : rule.flags), rule.with || '');
      }
    }
    const result: NativeContentResult = {
      kind: kind, text: text, baseUrl: firstBase, paragraphComments: [], chapterCommentUrl: '', links: [],
      images: imageUrls, mediaHeaders: (await this.renderHeaders(stage.mediaHeaders, firstPage.scope)),
      imageDecode: null
    };
    if (kind === 'images' && stage.imageDecode && firstPage) {
      const decode = stage.imageDecode;
      if (decode.script !== undefined) {
        const params = (await this.renderDeep(decode.params || {}, firstPage.scope)) as Record<string, NativeValue>;
        if (JSON.stringify(params).length > 16384) {
          throw this.fieldError('content.imageDecode.params', '', new Error('参数不能超过 16384 字符'));
        }
        result.imageDecode = { algorithm: '', key: '', iv: '', script: decode.script.trim(),
          params: params, processPlainImages: decode.processPlainImages === true };
      } else {
        const toHex = (value: NativeValue): string => {
          const bytes: number[] = Array.isArray(value) ? value : this.expr.evaluate('bytes(__text)',
            new NativeScope().set('__text', NativeExpr.toText(value)));
          return bytes.map((byte: number): string => ((byte & 255) < 16 ? '0' : '') + (byte & 255).toString(16)).join('');
        };
        let key = '';
        if (decode.keyEncoding !== undefined) {
          const value = NativeExpr.toText((await this.template(decode.key || '', firstPage.scope)));
          if (decode.keyEncoding === 'hex') {
            if (!/^(?:[a-f0-9]{2})+$/i.test(value)) {
              throw this.fieldError('content.imageDecode.key', '', new Error('keyEncoding:hex 需要完整的十六进制字节'));
            }
            key = value.toLowerCase();
          } else {
            key = toHex(value);
          }
        } else {
          key = toHex((await this.value(decode.key || '', firstPage.scope, false, 'content.imageDecode.key')));
        }
        if (!key) throw this.fieldError('content.imageDecode.key', '',
          new Error('密钥求值为空；固定密钥请声明 keyEncoding，或用 = 开头的字符串表达式'));
        if (decode.keyEncoding !== undefined || decode.ivPrefixBytes !== undefined) {
          const sizes = /^aes\//i.test(decode.algorithm || '') ? [16, 24, 32] : [24];
          if (!sizes.includes(key.length / 2)) throw this.fieldError('content.imageDecode.key', '',
            new Error(`密钥长度应为 ${sizes.join('/')} 字节，当前为 ${key.length / 2} 字节`));
        }
        result.imageDecode = {
          algorithm: NativeExpr.toText((await this.template(decode.algorithm || '', firstPage.scope))).trim(),
          key: key,
          iv: decode.iv ? toHex((await this.value(decode.iv, firstPage.scope, false, 'content.imageDecode.iv'))) : ''
        };
        if (decode.ivPrefixBytes !== undefined) result.imageDecode.ivPrefixBytes = decode.ivPrefixBytes;
      }
    }
    if (kind === 'text' && firstPage) {
      const links = stage.links || [];
      for (let i = 0; i < links.length; i++) {
        const link = links[i];
        if (link.when && !NativeExpr.isTruthy((await this.value(link.when, firstPage.scope, false,
          `content.links[${i}].when`)))) {
          continue;
        }
        const label = NativeExpr.toText((await this.template(link.label, firstPage.scope))).trim();
        if (!label) continue;
        if (link.request && link.request.url) {
          const request = (await this.buildRequest(link.request, firstPage.scope, ''));
          if (/^https?:\/\//i.test(request.url)) {
            result.links.push({ label: label, url: '', request: request, message: link.message || '' });
          }
          continue;
        }
        const url = NativeExpr.resolveUrl(NativeExpr.toText((await this.template(link.url || '', firstPage.scope))).trim(),
          firstPage.baseUrl);
        if (/^https?:\/\//i.test(url)) result.links.push({ label: label, url: url, request: null, message: '' });
      }
    }
    if (kind === 'text' && stage.comments && firstPage && text.trim()) {
      // 评论只是附加信息，任何一步失败都不影响正文。
      try {
        await this.collectComments(stage.comments, firstPage, text, result);
      } catch (e) {
        result.paragraphComments = [];
        result.chapterCommentUrl = '';
      }
    }
    return result;
  }

  private async collectComments(spec: NativeCommentsSpec, page: StagePage, text: string,
    result: NativeContentResult): Promise<void> {
    if (spec.when && !NativeExpr.isTruthy((await this.value(spec.when, page.scope)))) return;
    const scope = page.scope.child();
    scope.set('stats', spec.stats ? await this.fetchValue(spec.stats, scope) : null);
    let total = 0;
    if (spec.paragraphUrl && spec.counts) {
      const counts = (await this.value(spec.counts, scope));
      const lines = text.split('\n');
      const limit = Math.max(1, Math.min(Number(spec.max) || DEFAULT_COMMENT_BUBBLES, MAX_COMMENT_BUBBLES));
      const keys = counts && typeof counts === 'object' ? Object.keys(counts) : [];
      keys.sort((a: string, b: string): number => Number(a) - Number(b));
      for (const key of keys) {
        const line = Number(key);
        const count = Math.floor(NativeExpr.toNumber(counts[key]));
        if (!Number.isInteger(line) || count <= 0) continue;
        total += count;
        if (line < 0 || line >= lines.length || result.paragraphComments.length >= limit) continue;
        const plain = lines[line].replace(/<[^>]+>/g, '').trim();
        if (!plain) continue;
        const para = { index: line, count: count, text: plain.length > 90 ? plain.substring(0, 90) : plain };
        const url = NativeExpr.resolveUrl(
          NativeExpr.toText((await this.template(spec.paragraphUrl, scope.child().set('para', para)))).trim(), page.baseUrl);
        if (/^https?:\/\//i.test(url)) result.paragraphComments.push({ line: line, count: count, url: url });
      }
    }
    if (spec.chapterUrl) {
      const url = NativeExpr.resolveUrl(
        NativeExpr.toText((await this.template(spec.chapterUrl, scope.child().set('total', total)))).trim(), page.baseUrl);
      if (/^https?:\/\//i.test(url)) result.chapterCommentUrl = url;
    }
  }

  /** 发一个附加请求：响应是 JSON 时返回解析后的对象，否则返回文本；失败返回 null。 */
  private async fetchValue(spec: NativeRequestSpec, scope: NativeScope): Promise<NativeValue> {
    const request = (await this.buildRequest(spec, scope, ''));
    if (!request.url) return null;
    try {
      const response = await this.host.fetch(request);
      if (!response.ok || !response.body) return null;
      try {
        return JSON.parse(response.body);
      } catch (e) {
        return response.body;
      }
    } catch (e) {
      return null;
    }
  }

  private requireStage<T>(stage: T | undefined, label: string): T {
    if (!stage) throw new NativeSourceError(`该书源没有配置${label}`);
    return stage;
  }

  private async renderHeaders(headers: Record<string, string> | undefined, scope: NativeScope): Promise<Record<string, string>> {
    const rendered: Record<string, string> = {};
    for (const name of Object.keys(headers || {})) {
      const value = NativeExpr.toText((await this.template((headers as Record<string, string>)[name], scope)));
      if (value) rendered[name] = value;
    }
    return rendered;
  }

  /** 声明式缓存：有效期内直接复用，否则发请求取值并保存。结果按名称绑定到求值环境。 */
  private async applyCaches(scope: NativeScope): Promise<void> {
    const caches = this.definition.cache;
    if (!caches) return;
    for (const name of Object.keys(caches)) {
      const spec = caches[name];
      let value: NativeValue = null;
      if (!spec.when || NativeExpr.isTruthy((await this.value(spec.when, scope)))) {
        // 变量变了（换服务器、换账号）缓存就不该再用，所以把变量值算进键里。
        const key = `${name}\n${JSON.stringify(this.varValues)}`;
        const cached = this.host.cacheGet ? this.host.cacheGet(key) : undefined;
        if (cached !== undefined && cached !== null) {
          value = cached;
        } else {
          const request = (await this.buildRequest(spec, scope, ''));
          if (request.url) {
            try {
              const response = await this.host.fetch(request);
              if (response.ok && response.body) {
                value = (await this.value(spec.value, this.responseScope(scope, response.body, response.url || request.url)));
              }
            } catch (e) {
              value = null;
            }
            if (value !== null && value !== undefined && value !== '' && this.host.cachePut) {
              const ttl = Math.max(1, Math.min(Number(spec.ttl) || 600, 7 * 24 * 3600));
              this.host.cachePut(key, value, ttl);
            }
          }
        }
      }
      scope.set(name, value === undefined ? null : value);
    }
  }

  private async baseScope(): Promise<NativeScope> {
    const scope = new NativeScope()
      .set('vars', this.varValues)
      .set('source', { url: this.definition.url, name: this.definition.name })
      .set('key', '')
      .set('page', 1)
      .set('book', null)
      .set('chapter', null)
      .set('item', null)
      .set('index', 0)
      .set('body', '')
      .set('data', null)
      .set('baseUrl', this.definition.url)
      .set('login', this.credential)
      .set('form', {});
    await this.applyCaches(scope);
    (await this.applyLets(this.definition.let, scope));
    return scope.child();
  }

  private async applyLets(lets: Record<string, NativeValue> | undefined, scope: NativeScope): Promise<void> {
    if (!lets) return;
    for (const name of Object.keys(lets)) scope.set(name, (await this.value(lets[name], scope, false, `let.${name}`)));
  }

  /** 请求一个阶段的页面并准备好求值环境；地址渲染为空时不发请求。reuse 见 StageReuse。 */
  private async loadStage(stage: NativeStageSpec, scope: NativeScope, defaultUrl: string, label: string,
    reuse: StageReuse = ''): Promise<StagePage> {
    if (stage.script) return (await this.finishStage(stage, await this.loadScriptStage(stage, scope, label), label));
    const request = (await this.buildRequest(stage, scope, defaultUrl, true, `${STAGE_NAMES[label] || label}.url`));
    this.traceRule(`${STAGE_NAMES[label] || label}.url`, stage.url === undefined ? '(默认地址)' : stage.url,
      request.url, false);
    let body = '';
    let baseUrl = request.url || NativeExpr.toText(scope.get('baseUrl'));
    if (request.url) {
      const key = reuse ? this.keptPageKey(request) : '';
      const kept = reuse === 'take' ? NativeSourceRunner.takeKeptPage(key) : null;
      if (kept) {
        body = kept.body;
        baseUrl = kept.baseUrl;
        if (this.host.trace) {
          this.host.trace({
            field: `${label}请求`, rule: request.url, type: 'reuse', count: 1,
            preview: '与详情是同一个请求，复用详情页响应，未重新请求', error: ''
          });
        }
      } else {
        const response = await this.host.fetch(request);
        if (!response.ok || !response.body) throw new NativeSourceError(this.describeFailure(label, response));
        body = response.body;
        baseUrl = response.url || request.url;
        if (reuse === 'keep') NativeSourceRunner.keepPage(key, body, baseUrl);
      }
    }
    return (await this.finishStage(stage, { scope: this.responseScope(scope, body, baseUrl), baseUrl: baseUrl }, label));
  }

  /** 页面到手之后：阶段的 let 与 fail。 */
  private async finishStage(stage: NativeStageSpec, page: StagePage, label: string): Promise<StagePage> {
    (await this.applyLets(stage.let, page.scope));
    if (stage.fail) {
      const failure = NativeExpr.toText((await this.value(stage.fail, page.scope, false, 'fail'))).trim();
      if (failure && failure !== 'false') throw new NativeSourceError(`${label}接口返回失败：${failure}`);
    }
    return page;
  }

  /**
   * 脚本阶段：在后台运行 js 里的函数，它的返回值就是这个阶段的“页面”。字符串当作原文，数组或对象当作
   * 已解析的 JSON，page(body, url) 带上页面地址。之后的 list、fields 等规则照常在上面求值。
   */
  /**
   * 在后台运行 js 里的函数 fn(ctx)。interactive 表示用户主动发起的操作，可以弹出网页；搜索、发现不行。
   * 出错时抛出原始原因，由调用方加上是哪个阶段、哪个按钮。
   */
  private async runScriptFunction(fn: string, ctx: Record<string, NativeValue>, stageName: string, scope: NativeScope,
    interactive: boolean, keep: Record<string, string> | null): Promise<ScriptRun> {
    const limits = NativeScriptLimits.of(this.definition.scriptLimits ? this.definition.scriptLimits.requests : undefined);
    const scriptHost = new NativeScriptHost({
      host: this.host,
      sourceUrl: this.definition.url,
      stage: stageName,
      fn: fn,
      limits: limits,
      cancelled: this.cancelled,
      builtin: (name: string, args: NativeValue[]): NativeValue => this.expr.callBuiltin(name, args, scope),
      getVar: (key: string): NativeValue => this.getVar(key),
      setVar: async (key: string, value: NativeValue): Promise<void> => (await this.setVar(key, value)),
      temp: this.temp,
      credential: (): NativeValue => ({ token: this.credential.token, user: this.credential.user }),
      saveCredential: async (token: string, user: string): Promise<void> => (await this.saveCredential(token, user)),
      keep: keep,
      interactive: interactive
    });
    const startedAt = Date.now();
    try {
      const value: NativeValue = await this.scriptEngine().run(fn, ctx, scriptHost.handler(), {
        cpuMs: limits.cpuMs, wallMs: limits.wallMs, cancelled: this.cancelled,
        pausedMs: (): number => scriptHost.pausedMs
      });
      return { value: value, requests: scriptHost.requestCount, ms: Date.now() - startedAt };
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      this.traceScript(stageName, fn, 'return', '', message);
      throw new Error(message);
    }
  }

  private async loadScriptStage(stage: NativeStageSpec, scope: NativeScope, label: string): Promise<StagePage> {
    const fn = String(stage.script || '').trim();
    const stageName = STAGE_NAMES[label] || label;
    const interactive = stageName === 'detail' || stageName === 'toc' || stageName === 'content';
    let run: ScriptRun;
    try {
      run = await this.runScriptFunction(fn, this.scriptContext(scope, stageName), stageName, scope, interactive,
        stageName === 'detail' ? this.scriptKeep : null);
    } catch (e) {
      throw new NativeSourceError(`${label}脚本 ${fn}：${(e as Error).message}`);
    }
    const value: NativeValue = run.value;
    let baseUrl = NativeExpr.toText(scope.get('baseUrl')) || this.definition.url;
    let pageScope: NativeScope;
    if (NativeJsPrelude.isPage(value) || typeof value === 'string') {
      const body = typeof value === 'string' ? value : NativeExpr.toText(value['body']);
      const pageUrl = typeof value === 'string' ? '' : NativeExpr.toText(value['url']).trim();
      if (pageUrl) baseUrl = NativeExpr.resolveUrl(pageUrl, this.definition.url);
      pageScope = this.responseScope(scope, body, baseUrl);
    } else {
      pageScope = scope.child().set('body', value === null || value === undefined ? '' : JSON.stringify(value))
        .set('data', value === undefined ? null : value).set('item', value === undefined ? null : value)
        .set('baseUrl', baseUrl);
    }
    const data = pageScope.get('data');
    pageScope.set('__items', Array.isArray(data) ? data : (data === null || data === undefined ? [] : [data]));
    this.traceScript(stageName, fn, 'return', `${Array.isArray(data) ? `${data.length} 项` :
      (data !== null ? '对象' : `${NativeExpr.toText(pageScope.get('body')).length} 字`)}，请求 ${run.requests} 次，` +
      `${run.ms} ms`, '');
    return { scope: pageScope, baseUrl: baseUrl };
  }

  /** 传给脚本函数的 ctx：与规则里可用的名字一致。 */
  private scriptContext(scope: NativeScope, stageName: string): Record<string, NativeValue> {
    const ctx: Record<string, NativeValue> = { stage: stageName };
    for (const name of ['key', 'page', 'book', 'chapter', 'source', 'login', 'baseUrl']) ctx[name] = scope.get(name);
    for (const name of Object.keys(this.definition.cache || {}).concat(Object.keys(this.definition.let || {}))) {
      ctx[name] = scope.get(name);
    }
    ctx['vars'] = Object.assign({}, this.storedVars, this.varValues);
    ctx['url'] = scope.has('__url') ? NativeExpr.toText(scope.get('__url')) : '';
    ctx['title'] = scope.has('__title') ? NativeExpr.toText(scope.get('__title')) : '';
    ctx['menu'] = scope.has('__menuItem') ? scope.get('__menuItem') : null;
    return ctx;
  }

  private scriptEngine(): NativeScriptEngine {
    if (this.engine) return this.engine;
    const code = this.definition.js || '';
    if (!code.trim()) throw new NativeSourceError('阶段写了 script，但书源没有 js');
    if (!this.host.scriptEngine) throw new NativeSourceError('当前环境不支持脚本阶段');
    this.engine = this.host.scriptEngine(code);
    return this.engine;
  }

  private getVar(key: string): NativeValue {
    if (Object.prototype.hasOwnProperty.call(this.varValues, key)) return this.varValues[key];
    const value = this.storedVars[key];
    return value === undefined ? null : value;
  }

  private async setVar(key: string, value: NativeValue): Promise<void> {
    if (!key) throw new Error('变量名不能为空');
    this.storedVars[key] = value;
    if (Object.prototype.hasOwnProperty.call(this.varValues, key)) {
      this.varValues[key] = value === null || value === undefined ? '' : NativeExpr.toText(value);
    }
    if (!this.host.saveVars) throw new Error('当前环境不支持保存书源变量');
    await this.host.saveVars(Object.assign({}, this.storedVars, this.varValues));
  }

  private async saveCredential(token: string, user: string): Promise<void> {
    if (!this.host.saveCredential) throw new Error('当前环境不支持保存登录凭据');
    await this.host.saveCredential(token, user);
    this.credential = { token: token, user: user };
  }

  /** 脚本阶段没写 list、fields 时：返回的数组每项一条，字段按同名键取值。 */
  private scripted<T extends NativeStageSpec>(stage: T, fieldNames: string[]): T {
    if (!stage.script) return stage;
    const copy = Object.assign({}, stage) as T;
    if (!copy.list) copy.list = '= __items';
    if (!copy.fields) {
      const fields: Record<string, NativeValue> = {};
      for (const name of fieldNames) fields[name] = `$.${name}`;
      copy.fields = fields;
    }
    return copy;
  }

  /** 脚本正文没写 text、images、audio、video 时：返回字符串即正文，返回对象时按同名键取。 */
  private scriptedContent(stage: NativeContentSpec): NativeContentSpec {
    if (!stage.script || stage.text || stage.images || stage.audio || stage.video) return stage;
    return Object.assign({}, stage, {
      text: '= data != null ? $.text : body',
      images: '= data != null ? $.images : []',
      audio: '= data != null ? $.audio : body',
      video: '= data != null ? $.video : body'
    });
  }

  private traceScript(stageName: string, fn: string, rule: string, preview: string, error: string): void {
    if (!this.host.trace) return;
    this.host.trace({ field: `${stageName}.script ${fn}`, rule: rule, type: 'script', count: 1, preview: preview, error: error });
  }

  /** 请求的完整特征：书源加上地址、方法、请求头、请求体与取页方式，全部相同才算同一个请求。 */
  private keptPageKey(request: NativeRequest): string {
    return JSON.stringify([this.definition.url, this.definition.name, request.url, request.method, request.headers,
      request.body, request.webView, request.webWaitFor, request.charset]);
  }

  private static keepPage(key: string, body: string, baseUrl: string): void {
    const pages = NativeSourceRunner.keptPages;
    pages.delete(key);
    while (pages.size >= MAX_KEPT_PAGES) pages.delete(pages.keys().next().value as string);
    pages.set(key, { body: body, baseUrl: baseUrl, keptAt: Date.now() });
  }

  private static takeKeptPage(key: string): KeptPage | null {
    const kept = NativeSourceRunner.keptPages.get(key);
    if (!kept) return null;
    NativeSourceRunner.keptPages.delete(key);
    return Date.now() - kept.keptAt <= KEPT_PAGE_TTL_MS ? kept : null;
  }

  private responseScope(scope: NativeScope, body: string, baseUrl: string): NativeScope {
    let data: NativeValue = null;
    const trimmed = body.trim();
    if (trimmed && (trimmed[0] === '{' || trimmed[0] === '[')) {
      try {
        data = JSON.parse(trimmed);
      } catch (e) {
        data = null;
      }
    }
    return scope.child().set('body', body).set('data', data).set('item', data === null ? body : data)
      .set('baseUrl', baseUrl);
  }

  private describeFailure(label: string, response: NativeResponse): string {
    if (!response.ok) {
      // 状态码正常却被判为失败（例如拿到的是验证页）时，以给出的原因为准。
      const succeededStatus = response.status >= 200 && response.status < 300;
      return response.status > 0 && !(succeededStatus && response.error) ?
        `${label}请求失败（HTTP ${response.status}）` : `${label}请求失败：${response.error || '网络异常'}`;
    }
    return `${label}接口返回空响应`;
  }

  private async buildRequest(spec: NativeRequestSpec, scope: NativeScope, defaultUrl: string,
    primary: boolean = false, urlField: string = ''): Promise<NativeRequest> {
    let rawUrl: string;
    try {
      rawUrl = spec.url === undefined ? defaultUrl : NativeExpr.toText((await this.template(spec.url, scope)));
    } catch (error) {
      throw this.fieldError(urlField, spec.url, error);
    }
    const url = NativeExpr.resolveUrl(rawUrl.trim(), this.definition.url);
    const headers: Record<string, string> = {};
    for (const name of Object.keys(spec.headers || {})) {
      const value = NativeExpr.toText((await this.template((spec.headers as Record<string, string>)[name], scope)));
      if (value) headers[name] = value;
    }
    let body = '';
    if (spec.body !== undefined && spec.body !== null) {
      body = typeof spec.body === 'string' ? NativeExpr.toText((await this.template(spec.body, scope))) :
        JSON.stringify((await this.renderDeep(spec.body, scope)));
    }
    // 请求方法也按模板求值，可以随分类、变量切换 GET/POST。
    const rendered = spec.method ? NativeExpr.toText((await this.template(spec.method, scope))).trim() : '';
    const method = (rendered || (body ? 'POST' : 'GET')).toUpperCase();
    if (!/^[A-Z]+$/.test(method)) throw new NativeSourceError(`请求方法无效：${rendered}`);
    const web = spec.webView && typeof spec.webView === 'object' ? spec.webView : null;
    return {
      url: url, method: method, headers: headers, body: body, webView: spec.webView === true || !!web,
      webWaitFor: web && web.waitFor ? String(web.waitFor).trim() : '',
      webTimeout: Math.max(3, Math.min(Number(web && web.timeout) || 15, 60)),
      charset: String(spec.charset || '').trim(),
      retry: Math.max(0, Math.min(Math.floor(Number(spec.retry) || 0), 3)),
      primary: primary
    };
  }

  private async renderDeep(value: NativeValue, scope: NativeScope): Promise<NativeValue> {
    if (typeof value === 'string') return (await this.template(value, scope));
    if (Array.isArray(value)) return (await Promise.all(value.map(async (item: NativeValue): Promise<NativeValue> => (await this.renderDeep(item, scope)))));
    if (value && typeof value === 'object') {
      const out: Record<string, NativeValue> = {};
      for (const key of Object.keys(value)) out[key] = (await this.renderDeep(value[key], scope));
      return out;
    }
    return value;
  }

  private async runExtraFetches(fetches: Record<string, NativeFetchSpec> | undefined,
    loaded: StagePage): Promise<void> {
    if (!fetches) return;
    for (const name of Object.keys(fetches)) {
      const spec: NativeFetchSpec = fetches[name];
      let result: NativeValue = null;
      // 附加请求只是补充数据，失败时变量为 null，由规则自行决定如何降级。
      if (!spec.when || NativeExpr.isTruthy((await this.value(spec.when, loaded.scope)))) {
        result = await this.fetchValue(spec, loaded.scope);
      }
      loaded.scope.set(name, result);
    }
  }

  /** 音频/视频地址为空时的原因：书源写的 mediaError 优先，否则取附加请求、主请求里第一个报错的 code/message。 */
  private async mediaFailure(stage: NativeContentSpec, loaded: StagePage, kind: string): Promise<string> {
    const label = kind === 'audio' ? '音频' : '视频';
    if (stage.mediaError) {
      const custom = NativeExpr.toText((await this.value(stage.mediaError, loaded.scope, false, 'content.mediaError'))).trim();
      if (custom) return custom;
    }
    const responses: NativeValue[] = Object.keys(stage.fetch || {})
      .map((name: string): NativeValue => loaded.scope.get(name));
    responses.push(loaded.scope.get('data'));
    for (const response of responses) {
      const reason = NativeSourceRunner.apiFailure(response);
      if (reason) return `${label}接口返回失败：${reason}`;
    }
    return `正文规则没有返回${label}地址`;
  }

  private static apiFailure(value: NativeValue): string {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return '';
    const record = value as Record<string, NativeValue>;
    let code: NativeValue = null;
    for (const key of ['code', 'status_code', 'err_no']) {
      if (record[key] !== undefined && record[key] !== null) {
        code = record[key];
        break;
      }
    }
    if (code === null || code === 0 || code === '0' || code === 200) return '';
    let message = '';
    for (const key of ['message', 'msg', 'error', 'err_tips']) {
      message = NativeExpr.toText(record[key] === undefined ? null : record[key]).trim();
      if (message) break;
    }
    const codeText = NativeExpr.toText(code);
    return message ? `${message}（code=${codeText}）` : `code=${codeText}`;
  }

  private async readBooks(stage: NativeStageSpec, loaded: StagePage, prefix: string): Promise<NativeBookRecord[]> {
    const books: NativeBookRecord[] = [];
    const items = (await this.listItems(stage.list || '', loaded.scope, loaded.baseUrl, `${prefix}.list`));
    let scriptValues: Record<string, NativeValue>[] = [];
    for (let i = 0; i < items.length; i++) {
      if (i % 16 === 0) scriptValues = await this.readScriptFields(stage.fields || {}, loaded.scope,
        items.slice(i, i + 16), i, prefix);
      const itemScope = loaded.scope.child().set('item', items[i]).set('index', i);
      const book = (await this.readBook(stage.fields || {}, itemScope, loaded.baseUrl, prefix,
        scriptValues[i % 16] || {}));
      if (book.name && book.bookUrl) books.push(book);
    }
    return books;
  }

  /** Batch pure JS field expressions so a page does not serialize the full response once per field. */
  private async readScriptFields(fields: Record<string, NativeValue>, scope: NativeScope,
    items: NativeValue[] | null, offset: number, prefix: string): Promise<Record<string, NativeValue>[]> {
    if (!this.definition.js || !this.host.evaluateExpression) return [];
    const pairs: string[] = [];
    for (const name of BOOK_FIELD_NAMES) {
      const rule = fields[name];
      if (typeof rule !== 'string' || !rule.trim().startsWith('=')) continue;
      const expression = rule.trim().substring(1);
      if (this.expr.requiresScript(expression)) pairs.push(`${JSON.stringify(name)}:(${expression})`);
    }
    if (!pairs.length) return [];
    const record = `{${pairs.join(',')}}`;
    try {
      if (!items) return [(await this.expression(record, scope)) as Record<string, NativeValue>];
      let rows = '__nativeRows';
      while (scope.has(rows) || record.indexOf(rows) >= 0) rows += '_';
      let row = '__nativeRow';
      while (scope.has(row) || record.indexOf(row) >= 0 || row === rows) row += '_';
      const batch = items.map((item: NativeValue, index: number): NativeValue => ({ item, index: offset + index }));
      // Nested scopes preserve the ordinary item/index semantics, including JSONPath and native callbacks.
      const expression = `map(${rows}, ${row} => map([${row}.item], item => map([${row}.index], index => ${record})[0])[0])`;
      return (await this.expression(expression, scope.child().set(rows, batch))) as Record<string, NativeValue>[];
    } catch (error) {
      throw this.fieldError(`${prefix}.fields`, record, error);
    }
  }

  private async readBook(fields: Record<string, NativeValue>, scope: NativeScope, baseUrl: string,
    prefix: string, scriptValues?: Record<string, NativeValue>): Promise<NativeBookRecord> {
    const scripted = scriptValues || (await this.readScriptFields(fields, scope, null, 0, prefix))[0] || {};
    const read = async (name: string): Promise<NativeValue> => {
      if (!Object.prototype.hasOwnProperty.call(scripted, name)) {
        return await this.value(fields[name], scope, false, `${prefix}.fields.${name}`);
      }
      const value = scripted[name];
      this.traceRule(`${prefix}.fields.${name}`, fields[name], value, false, scope);
      return value;
    };
    const text = async (name: string): Promise<string> => {
      const value = await read(name);
      return (Array.isArray(value) ? value.map((part: NativeValue): string => NativeExpr.toText(part).trim())
        .filter((part: string): boolean => !!part).join(',') : NativeExpr.toText(value)).trim();
    };
    const url = async (name: string): Promise<string> => NativeExpr.resolveUrl(this.firstLine(this.first(
      (await read(name)))), baseUrl);
    const typeSpec = fields['type'];
    const literalType = typeof typeSpec === 'string' && /^(text|audio|comic|image|video)$/i.test(typeSpec.trim());
    const coverHeaders = Object.assign({},
      SourceCoverUrl.cleanHeaders((await this.renderHeaders(this.definition.headers, scope))),
      SourceCoverUrl.cleanHeaders((await this.renderHeaders(this.definition.coverHeaders, scope))));
    const cover = await url('coverUrl');
    return {
      name: (await text('name')),
      author: (await text('author')),
      kind: (await text('kind')),
      intro: (await text('intro')),
      coverUrl: this.definition.coverDecode || Object.keys(coverHeaders).length > 0 ?
        SourceCoverUrl.wrap(cover, this.definition.url, coverHeaders) : cover,
      wordCount: (await text('wordCount')),
      lastChapter: (await text('lastChapter')),
      updateTime: (await text('updateTime')),
      status: (await text('status')),
      bookUrl: (await url('bookUrl')),
      tocUrl: (await url('tocUrl')),
      type: (literalType ? String(typeSpec).trim() : (await text('type'))).toLowerCase(),
      keep: {}
    };
  }

  /**
   * 地址类字段只取第一项：选择器命中多个元素时，非列表求值会把结果按行拼起来（简介等文本需要这样），
   * 而地址里不会有换行，取第一行与兼容书源“地址取第一个”的行为一致。
   */
  private firstLine(value: NativeValue): string {
    for (const line of NativeExpr.toText(value).split(/\r?\n/)) {
      const text = line.trim();
      if (text) return text;
    }
    return '';
  }

  private first(value: NativeValue): NativeValue {
    return Array.isArray(value) ? (value.length > 0 ? value[0] : '') : value;
  }

  private async expression(text: string, scope: NativeScope, template: boolean = false): Promise<NativeValue> {
    if (this.definition.js && this.host.evaluateExpression && this.expr.requiresScript(text, template)) {
      return this.host.evaluateExpression(this.definition.js, this.definition.lib || '', text, scope.snapshot(),
        template, this.cancelled);
    }
    return template ? this.expr.render(text, scope) : this.expr.evaluate(text, scope);
  }

  private async listItems(rule: string, scope: NativeScope, baseUrl: string, field: string = ''): Promise<NativeValue[]> {
    const spec = (rule || '').trim();
    if (!spec) return [];
    let items: NativeValue[];
    try {
      if (spec.startsWith('=')) {
        const value = (await this.expression(spec.substring(1), scope));
        items = Array.isArray(value) ? value : (value === null || value === undefined || value === '' ? [] : [value]);
      } else {
        const current = scope.get('item');
        const jsonItems = this.jsonRule(spec, current, true);
        items = jsonItems !== null ? (jsonItems as NativeValue[]) :
          this.host.selectItems(typeof current === 'string' ? current : NativeExpr.toText(current), spec, baseUrl);
      }
    } catch (e) {
      throw this.fieldError(field, spec, e);
    }
    this.traceRule(field, spec, items, true);
    return items.length > MAX_LIST_ITEMS ? items.slice(0, MAX_LIST_ITEMS) : items;
  }

  /** 给求值错误补上是哪条规则出的错，并记入调试信息。 */
  private fieldError(field: string, spec: NativeValue, error: NativeValue): Error {
    const message = error instanceof Error ? error.message : String(error);
    if (!field) return error instanceof Error ? error : new NativeSourceError(message);
    if (this.host.trace) {
      this.host.trace({
        field: field, rule: typeof spec === 'string' ? spec : NativeExpr.toText(spec),
        type: this.ruleType(spec), count: 0, preview: '', error: message
      });
    }
    return new NativeSourceError(`规则 ${field} 出错：${message}`);
  }

  private ruleType(spec: NativeValue): string {
    if (typeof spec !== 'string') return 'literal';
    const text = spec.trim();
    return text.startsWith('=') ? 'expression' : (text.indexOf('{{') >= 0 ? 'template' : 'selector');
  }

  /** 调试时记录一条规则的结果。列表里只记第一个元素的字段，避免上千条重复记录。 */
  private traceRule(field: string, spec: NativeValue, result: NativeValue, isList: boolean, scope?: NativeScope): void {
    if (!field || !this.host.trace || spec === undefined || spec === null || spec === '') return;
    if (scope && Number(scope.get('index')) > 0) return;
    const text = NativeExpr.toText(Array.isArray(result) && isList ? result[0] : result);
    this.host.trace({
      field: field, rule: typeof spec === 'string' ? spec : NativeExpr.toText(spec), type: this.ruleType(spec),
      count: Array.isArray(result) ? result.length : (text ? 1 : 0),
      preview: text.length > 300 ? `${text.substring(0, 300)}…` : text, error: ''
    });
  }

  /** 模板位置（地址、请求头、标题）：= 开头按表达式，其余按 {{ }} 模板。 */
  private async template(spec: NativeValue, scope: NativeScope): Promise<NativeValue> {
    if (typeof spec !== 'string') return spec;
    const text = spec.trim();
    if (text.startsWith('=')) return (await this.expression(text.substring(1), scope));
    return (await this.expression(spec, scope, true));
  }

  /** 字段位置的求值。field 给出规则在定义里的位置，出错时用来定位，调试时用来记录。 */
  private async value(spec: NativeValue, scope: NativeScope, list: boolean = false, field: string = ''): Promise<NativeValue> {
    let result: NativeValue;
    try {
      result = (await this.rawValue(spec, scope, list));
    } catch (e) {
      throw this.fieldError(field, spec, e);
    }
    this.traceRule(field, spec, result, list, scope);
    return result;
  }

  /** 字段位置：= 开头按表达式，含 {{ }} 按模板，其余按选择器规则在当前元素上取值。 */
  private async rawValue(spec: NativeValue, scope: NativeScope, list: boolean = false): Promise<NativeValue> {
    if (spec === undefined || spec === null || spec === '') return list ? [] : '';
    if (typeof spec !== 'string') return spec;
    const text = spec.trim();
    if (text.startsWith('=')) return (await this.expression(text.substring(1), scope));
    if (text.indexOf('{{') >= 0) return (await this.expression(spec, scope, true));
    const current = scope.get('item');
    const jsonValue = this.jsonRule(text, current, list);
    if (jsonValue !== null) return jsonValue;
    const content = typeof current === 'string' ? current : NativeExpr.toText(current);
    const found = this.host.select(content, text, NativeExpr.toText(scope.get('baseUrl')), list);
    return list ? found : (found.length > 0 ? found[0] : '');
  }

  /**
   * 纯 JSONPath 规则（可用 || 写备选）直接在对象上取值，免去把每个元素反复序列化再解析。
   * 不是这种写法时返回 null，交给完整的选择器引擎。
   */
  private jsonRule(rule: string, current: NativeValue, list: boolean): NativeValue {
    if (current === null || typeof current !== 'object') return null;
    if (!/^\$[.\[]/.test(rule) || /##|&&|%%|@|<|\{/.test(rule)) return null;
    for (const path of rule.split('||')) {
      const matches = this.host.jsonPath(current, path.trim());
      if (matches.length === 0) continue;
      if (list) return matches;
      const texts = matches.map((item: NativeValue): string => NativeExpr.toText(item));
      if (texts.some((item: string): boolean => !!item)) return matches.length === 1 ? matches[0] : texts.join('\n');
    }
    return list ? [] : '';
  }
}
