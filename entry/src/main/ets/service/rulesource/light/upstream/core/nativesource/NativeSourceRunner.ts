/**
 * 原生书源执行器：按定义依次完成请求、取列表、取字段，全程不经过任何脚本引擎。
 *
 * 网络与选择器通过 NativeRunnerHost 注入，本文件不依赖系统 API，可直接在 Node 回归脚本中加载。
 */

import { CooperativeScheduler } from '../concurrency/CooperativeScheduler';
import { NativeExpr, NativeScope } from './NativeExpr';
import { SourceCoverUrl } from './SourceCoverUrl';
import type { NativeExprHost, NativeValue } from './NativeExpr';
import type {
  NativeActionSpec, NativeCommentsSpec, NativeContentSpec, NativeFetchSpec, NativeMenuSpec, NativeRequestSpec,
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
  algorithm: string;
  key: string;
  iv: string;
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

/** loadStage 对响应的处理：keep 记下供之后复用，take 有记下的同一请求时直接用、不再请求。 */
type StageReuse = '' | 'keep' | 'take';

const MENU_STATIC = 'native:menu:';
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

  constructor(definition: NativeSourceDefinition, host: NativeRunnerHost, storedVars: Record<string, NativeValue> = {}) {
    this.definition = definition;
    this.host = host;
    this.expr = new NativeExpr(host).loadLibrary(definition.lib);
    this.varValues = NativeSourceRunner.resolveVars(definition, storedVars);
  }

  /** 表单登录保存下来的凭据，规则里通过 login.token / login.user 读取。 */
  setCredential(credential: NativeLoginCredential): NativeSourceRunner {
    this.credential = { token: credential.token || '', user: credential.user || '' };
    return this;
  }

  /** 表单登录：用用户填写的值发登录请求。 */
  async submitLogin(form: Record<string, string>): Promise<NativeLoginResult> {
    const submit = this.definition.login ? this.definition.login.submit : undefined;
    if (!submit) return { ok: false, token: '', user: '', message: '该书源没有配置表单登录' };
    const scope = (await this.baseScope()).set('form', form);
    const response = await this.host.fetch(this.buildRequest(submit, scope, ''));
    if (!response.ok || !response.body) {
      return { ok: false, token: '', user: '', message: this.describeFailure('登录', response) };
    }
    const page = this.responseScope(scope, response.body, response.url);
    const ok = NativeExpr.isTruthy(this.value(submit.ok, page, false, 'login.submit.ok'));
    const message = submit.message ?
      NativeExpr.toText(this.value(submit.message, page, false, 'login.submit.message')).trim() : '';
    if (!ok) return { ok: false, token: '', user: '', message: message || '登录失败' };
    return {
      ok: true,
      token: submit.token ? NativeExpr.toText(this.value(submit.token, page, false, 'login.submit.token')).trim() : '',
      user: submit.user ? NativeExpr.toText(this.value(submit.user, page, false, 'login.submit.user')).trim() : '',
      message: message
    };
  }

  /** 表单登录的辅助请求（发送验证码等），返回提示文字。 */
  async sendLoginCode(form: Record<string, string>): Promise<string> {
    const spec = this.definition.login ? this.definition.login.sendCode : undefined;
    if (!spec) return '该书源没有配置这个操作';
    return await this.performAction(spec, (await this.baseScope()).set('form', form), 'login.sendCode');
  }

  /** 书源设置页里可用的动作按钮。 */
  async actions(): Promise<NativeActionEntry[]> {
    const specs = this.definition.actions || [];
    if (specs.length === 0) return [];
    const scope = await this.baseScope();
    const entries: NativeActionEntry[] = [];
    for (let i = 0; i < specs.length; i++) {
      const spec = specs[i];
      if (spec.when && !NativeExpr.isTruthy(this.value(spec.when, scope, false, `actions[${i}].when`))) continue;
      const label = NativeExpr.toText(this.template(spec.label, scope)).trim();
      if (!label) continue;
      const open = spec.open ? NativeExpr.resolveUrl(NativeExpr.toText(this.template(spec.open, scope)).trim(),
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
    return NativeExpr.toText(this.value(messageSpec, page, false, 'content.links.message')).trim() || '已完成';
  }

  private async performAction(spec: NativeActionSpec, scope: NativeScope, field: string): Promise<string> {
    const request = this.buildRequest(spec, scope, '');
    if (!request.url) return '操作没有可用的地址';
    const response = await this.host.fetch(request);
    if (!response.ok) return this.describeFailure('操作', response);
    if (!spec.message) return '已完成';
    const page = this.responseScope(scope, response.body || '', response.url || request.url);
    return NativeExpr.toText(this.value(spec.message, page, false, `${field}.message`)).trim() || '已完成';
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
      values[item.key] = saved && (options.length === 0 || options.indexOf(saved) >= 0) ? saved : fallback;
    }
    return values;
  }

  async search(key: string, page: number = 1): Promise<NativeBookRecord[]> {
    const stage = this.requireStage(this.definition.search, '搜索');
    const scope = (await this.baseScope()).set('key', key).set('page', page);
    const loaded = await this.loadStage(stage, scope, '', '搜索');
    return this.readBooks(stage, loaded, 'search');
  }

  /** 用书源声明的检查接口确认登录状态。 */
  async checkLogin(): Promise<NativeLoginState> {
    const check = this.definition.login ? this.definition.login.check : undefined;
    if (!check) return { ok: false, name: '', message: '该书源没有配置登录检查' };
    const scope = (await this.baseScope());
    const request = this.buildRequest(check, scope, '');
    const response = await this.host.fetch(request);
    if (!response.ok || !response.body) {
      return { ok: false, name: '', message: this.describeFailure('登录检查', response) };
    }
    const pageScope = this.responseScope(scope, response.body, response.url || request.url);
    const ok = NativeExpr.isTruthy(this.value(check.ok, pageScope));
    return {
      ok: ok,
      name: ok && check.name ? NativeExpr.toText(this.value(check.name, pageScope)).trim() : '',
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
      if (menu.when && !NativeExpr.isTruthy(this.value(menu.when, scope))) continue;
      const title = NativeExpr.toText(this.template(menu.title || '', scope));
      if (!title) continue;
      entries.push({ title: title, target: menu.url ? `${MENU_STATIC}${i}` : '' });
    }
    const dynamic = explore.dynamicMenus;
    if (dynamic) {
      const request = this.buildRequest(dynamic, scope, '');
      if (request.url) {
        const response = await this.host.fetch(request);
        if (!response.ok || !response.body) {
          if (entries.length === 0) throw new NativeSourceError(this.describeFailure('发现分类', response));
        } else {
          const baseUrl = response.url || request.url;
          const pageScope = this.responseScope(scope, response.body, baseUrl);
          const items = this.listItems(dynamic.list, pageScope, baseUrl);
          for (const item of items) {
            const itemScope = pageScope.child().set('item', item);
            const title = NativeExpr.toText(this.value(dynamic.title, itemScope)).trim();
            if (!title) continue;
            // 目标地址里通常带页码，到真正打开分类时再渲染，这里只记下条目本身。
            const hasTarget = NativeExpr.isTruthy(this.value(dynamic.target, itemScope.child().set('page', 1)));
            entries.push({ title: title, target: hasTarget ? MENU_ITEM + JSON.stringify(item) : '' });
          }
        }
      }
    }
    return entries;
  }

  async explore(target: string, page: number = 1): Promise<NativeBookRecord[]> {
    const explore = this.requireStage(this.definition.explore, '发现');
    const scope = (await this.baseScope()).set('page', page);
    let url = '';
    let menu: NativeMenuSpec | undefined = undefined;
    if (target.startsWith(MENU_STATIC)) {
      menu = (explore.menus || [])[Number(target.substring(MENU_STATIC.length))];
      url = menu && menu.url ? NativeExpr.toText(this.template(menu.url, scope)) : '';
    } else if (target.startsWith(MENU_ITEM) && explore.dynamicMenus) {
      let item: NativeValue = null;
      try {
        item = JSON.parse(target.substring(MENU_ITEM.length));
      } catch (e) {
        item = null;
      }
      url = NativeExpr.toText(this.value(explore.dynamicMenus.target, scope.child().set('item', item)));
    }
    if (!url) throw new NativeSourceError('发现分类没有可用的地址');
    const stage: NativeStageSpec = Object.assign({}, explore, {
      url: '= __url', headers: Object.assign({}, explore.headers || {}, menu && menu.headers ? menu.headers : {})
    });
    // 静态分类可以各用各的请求方法和请求体，一个书源对接请求方式不同的几个接口。
    if (menu && menu.method !== undefined) stage.method = menu.method;
    if (menu && menu.body !== undefined) stage.body = menu.body;
    const loaded = await this.loadStage(stage, scope.child().set('__url', url), '', '发现');
    return this.readBooks(explore, loaded, 'explore');
  }

  async detail(book: NativeBookInput): Promise<NativeBookRecord> {
    const stage = this.definition.detail || {};
    const scope = (await this.baseScope()).set('book', book);
    const loaded = await this.loadStage(stage, scope, book.bookUrl, '详情', 'keep');
    await this.runExtraFetches(this.definition.detail ? this.definition.detail.fetch : undefined, loaded);
    const record = this.readBook(stage.fields || {}, loaded.scope, loaded.baseUrl, 'detail');
    if (!record.bookUrl) record.bookUrl = book.bookUrl;
    const keep = this.definition.detail ? this.definition.detail.keep : undefined;
    if (keep) {
      for (const key of Object.keys(keep)) {
        record.keep[key] = NativeExpr.toText(this.value(keep[key], loaded.scope, false, `detail.keep.${key}`));
      }
    }
    return record;
  }

  async toc(book: NativeBookInput, limit: number = 0): Promise<NativeChapterRecord[]> {
    const stage = this.requireStage(this.definition.toc, '目录');
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
      if (!stage.nextUrl) break;
      const pending = this.nextUrls(stage.nextUrl, loaded, 'toc.nextUrl').filter((url: string): boolean => !visited.has(url));
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
        const pages = await Promise.all(batch.map(async (url: string, index: number): Promise<StagePage> =>
          this.loadStage(nextStage, await pageScope(page + offset + index + 1, url), defaultUrl, '目录')));
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
    for (const item of this.listItems(stage.list || '', loaded.scope, loaded.baseUrl, 'toc.list')) {
      if (pacer.due()) {
        await pacer.yield();
        if (this.cancelled()) return true;
      }
      const itemScope = loaded.scope.child().set('item', item).set('index', chapters.length);
      const title = NativeExpr.toText(this.value(fields['title'], itemScope, false, 'toc.fields.title')).trim();
      if (!title) continue;
      const isVolume = NativeExpr.isTruthy(this.value(fields['isVolume'], itemScope, false, 'toc.fields.isVolume'));
      const url = NativeExpr.resolveUrl(
        NativeExpr.toText(this.value(fields['url'], itemScope, false, 'toc.fields.url')), loaded.baseUrl);
      if (!url && !isVolume) continue;
      chapters.push({
        title: title,
        url: url,
        isVip: NativeExpr.isTruthy(this.value(fields['isVip'], itemScope, false, 'toc.fields.isVip')),
        isPay: NativeExpr.isTruthy(this.value(fields['isPay'], itemScope, false, 'toc.fields.isPay')),
        isVolume: isVolume,
        tag: NativeExpr.toText(this.value(fields['tag'] || fields['updateTime'], itemScope, false,
          'toc.fields.tag')).trim()
      });
      if (chapters.length >= MAX_LIST_ITEMS || (limit > 0 && chapters.length >= limit)) return true;
    }
    return false;
  }

  /** nextUrl 的结果：一个地址是下一页；列表或多行文本是剩余全部分页。已补全、去重。 */
  private nextUrls(spec: NativeValue, loaded: StagePage, field: string): string[] {
    const raw = this.value(spec, loaded.scope, false, field);
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
  private appendContentPage(stage: NativeContentSpec, kind: string, loaded: StagePage, parts: string[],
    imageUrls: string[]): number {
    if (kind === 'images') {
      let added = 0;
      const images = this.value(stage.images, loaded.scope, true, 'content.images');
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
    const text = this.value(stage.text, loaded.scope, false, 'content.text');
    const added = Array.isArray(text) ?
      text.map((line: NativeValue): string => NativeExpr.toText(line)).join('\n') : NativeExpr.toText(text);
    parts.push(added);
    return added.length;
  }

  async content(book: NativeBookInput, chapter: NativeChapterInput): Promise<NativeContentResult> {
    const stage = this.requireStage(this.definition.content, '正文');
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
      const audio = NativeExpr.toText(this.first(this.value(kind === 'audio' ? stage.audio : stage.video,
        firstPage.scope, false, `content.${kind}`))).trim();
      if (!audio) throw new NativeSourceError(this.mediaFailure(stage, firstPage, kind));
      return {
        kind: kind, text: NativeExpr.resolveUrl(audio, firstPage.baseUrl), baseUrl: firstPage.baseUrl,
        paragraphComments: [], chapterCommentUrl: '', links: [], images: [],
        mediaHeaders: this.renderHeaders(stage.mediaHeaders, firstPage.scope), imageDecode: null
      };
    }
    const parts: string[] = [];
    const imageUrls: string[] = [];
    let size = this.appendContentPage(stage, kind, firstPage, parts, imageUrls);
    const visited: Set<string> = new Set([firstBase, NativeExpr.resolveUrl(chapter.url, this.definition.url)]);
    const nextStage: NativeStageSpec = Object.assign({}, stage, { url: '= __url' });
    let loaded = firstPage;
    let page = 1;
    let skipped = 0;
    while (stage.nextUrl) {
      if (this.cancelled()) return empty(firstBase);
      const pending = this.nextUrls(stage.nextUrl, loaded, 'content.nextUrl')
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
        size += this.appendContentPage(stage, kind, loaded, parts, imageUrls);
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
        const pages = await Promise.all(batch.map(async (url: string, index: number): Promise<StagePage> =>
          this.loadStage(nextStage, await pageScope(page + offset + index + 1, url), chapter.url, '正文')));
        for (const listedPage of pages) {
          await this.runExtraFetches(stage.fetch, listedPage);
          size += this.appendContentPage(stage, kind, listedPage, parts, imageUrls);
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
      images: imageUrls, mediaHeaders: this.renderHeaders(stage.mediaHeaders, firstPage.scope),
      imageDecode: null
    };
    if (kind === 'images' && stage.imageDecode && firstPage) {
      const decode = stage.imageDecode;
      const toHex = (value: NativeValue): string => {
        const bytes: number[] = Array.isArray(value) ? value : this.expr.evaluate('bytes(__text)',
          new NativeScope().set('__text', NativeExpr.toText(value)));
        return bytes.map((byte: number): string => ((byte & 255) < 16 ? '0' : '') + (byte & 255).toString(16)).join('');
      };
      result.imageDecode = {
        algorithm: NativeExpr.toText(this.template(decode.algorithm, firstPage.scope)).trim(),
        key: toHex(this.value(decode.key, firstPage.scope, false, 'content.imageDecode.key')),
        iv: decode.iv ? toHex(this.value(decode.iv, firstPage.scope, false, 'content.imageDecode.iv')) : ''
      };
    }
    if (kind === 'text' && firstPage) {
      const links = stage.links || [];
      for (let i = 0; i < links.length; i++) {
        const link = links[i];
        if (link.when && !NativeExpr.isTruthy(this.value(link.when, firstPage.scope, false,
          `content.links[${i}].when`))) {
          continue;
        }
        const label = NativeExpr.toText(this.template(link.label, firstPage.scope)).trim();
        if (!label) continue;
        if (link.request && link.request.url) {
          const request = this.buildRequest(link.request, firstPage.scope, '');
          if (/^https?:\/\//i.test(request.url)) {
            result.links.push({ label: label, url: '', request: request, message: link.message || '' });
          }
          continue;
        }
        const url = NativeExpr.resolveUrl(NativeExpr.toText(this.template(link.url || '', firstPage.scope)).trim(),
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
    if (spec.when && !NativeExpr.isTruthy(this.value(spec.when, page.scope))) return;
    const scope = page.scope.child();
    scope.set('stats', spec.stats ? await this.fetchValue(spec.stats, scope) : null);
    let total = 0;
    if (spec.paragraphUrl && spec.counts) {
      const counts = this.value(spec.counts, scope);
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
          NativeExpr.toText(this.template(spec.paragraphUrl, scope.child().set('para', para))).trim(), page.baseUrl);
        if (/^https?:\/\//i.test(url)) result.paragraphComments.push({ line: line, count: count, url: url });
      }
    }
    if (spec.chapterUrl) {
      const url = NativeExpr.resolveUrl(
        NativeExpr.toText(this.template(spec.chapterUrl, scope.child().set('total', total))).trim(), page.baseUrl);
      if (/^https?:\/\//i.test(url)) result.chapterCommentUrl = url;
    }
  }

  /** 发一个附加请求：响应是 JSON 时返回解析后的对象，否则返回文本；失败返回 null。 */
  private async fetchValue(spec: NativeRequestSpec, scope: NativeScope): Promise<NativeValue> {
    const request = this.buildRequest(spec, scope, '');
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

  private renderHeaders(headers: Record<string, string> | undefined, scope: NativeScope): Record<string, string> {
    const rendered: Record<string, string> = {};
    for (const name of Object.keys(headers || {})) {
      const value = NativeExpr.toText(this.template((headers as Record<string, string>)[name], scope));
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
      if (!spec.when || NativeExpr.isTruthy(this.value(spec.when, scope))) {
        // 变量变了（换服务器、换账号）缓存就不该再用，所以把变量值算进键里。
        const key = `${name}\n${JSON.stringify(this.varValues)}`;
        const cached = this.host.cacheGet ? this.host.cacheGet(key) : undefined;
        if (cached !== undefined && cached !== null) {
          value = cached;
        } else {
          const request = this.buildRequest(spec, scope, '');
          if (request.url) {
            try {
              const response = await this.host.fetch(request);
              if (response.ok && response.body) {
                value = this.value(spec.value, this.responseScope(scope, response.body, response.url || request.url));
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
    this.applyLets(this.definition.let, scope);
    return scope.child();
  }

  private applyLets(lets: Record<string, NativeValue> | undefined, scope: NativeScope): void {
    if (!lets) return;
    for (const name of Object.keys(lets)) scope.set(name, this.value(lets[name], scope, false, `let.${name}`));
  }

  /** 请求一个阶段的页面并准备好求值环境；地址渲染为空时不发请求。reuse 见 StageReuse。 */
  private async loadStage(stage: NativeStageSpec, scope: NativeScope, defaultUrl: string, label: string,
    reuse: StageReuse = ''): Promise<StagePage> {
    const request = this.buildRequest(stage, scope, defaultUrl, true);
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
    const pageScope = this.responseScope(scope, body, baseUrl);
    this.applyLets(stage.let, pageScope);
    if (stage.fail) {
      const failure = NativeExpr.toText(this.value(stage.fail, pageScope, false, 'fail')).trim();
      if (failure && failure !== 'false') throw new NativeSourceError(`${label}接口返回失败：${failure}`);
    }
    return { scope: pageScope, baseUrl: baseUrl };
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

  private buildRequest(spec: NativeRequestSpec, scope: NativeScope, defaultUrl: string,
    primary: boolean = false): NativeRequest {
    const rawUrl = spec.url === undefined ? defaultUrl : NativeExpr.toText(this.template(spec.url, scope));
    const url = NativeExpr.resolveUrl(rawUrl.trim(), this.definition.url);
    const headers: Record<string, string> = {};
    for (const name of Object.keys(spec.headers || {})) {
      const value = NativeExpr.toText(this.template((spec.headers as Record<string, string>)[name], scope));
      if (value) headers[name] = value;
    }
    let body = '';
    if (spec.body !== undefined && spec.body !== null) {
      body = typeof spec.body === 'string' ? NativeExpr.toText(this.template(spec.body, scope)) :
        JSON.stringify(this.renderDeep(spec.body, scope));
    }
    // 请求方法也按模板求值，可以随分类、变量切换 GET/POST。
    const rendered = spec.method ? NativeExpr.toText(this.template(spec.method, scope)).trim() : '';
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

  private renderDeep(value: NativeValue, scope: NativeScope): NativeValue {
    if (typeof value === 'string') return this.template(value, scope);
    if (Array.isArray(value)) return value.map((item: NativeValue): NativeValue => this.renderDeep(item, scope));
    if (value && typeof value === 'object') {
      const out: Record<string, NativeValue> = {};
      for (const key of Object.keys(value)) out[key] = this.renderDeep(value[key], scope);
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
      if (!spec.when || NativeExpr.isTruthy(this.value(spec.when, loaded.scope))) {
        result = await this.fetchValue(spec, loaded.scope);
      }
      loaded.scope.set(name, result);
    }
  }

  /** 音频/视频地址为空时的原因：书源写的 mediaError 优先，否则取附加请求、主请求里第一个报错的 code/message。 */
  private mediaFailure(stage: NativeContentSpec, loaded: StagePage, kind: string): string {
    const label = kind === 'audio' ? '音频' : '视频';
    if (stage.mediaError) {
      const custom = NativeExpr.toText(this.value(stage.mediaError, loaded.scope, false, 'content.mediaError')).trim();
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

  private readBooks(stage: NativeStageSpec, loaded: StagePage, prefix: string): NativeBookRecord[] {
    const books: NativeBookRecord[] = [];
    const items = this.listItems(stage.list || '', loaded.scope, loaded.baseUrl, `${prefix}.list`);
    for (let i = 0; i < items.length; i++) {
      const itemScope = loaded.scope.child().set('item', items[i]).set('index', i);
      const book = this.readBook(stage.fields || {}, itemScope, loaded.baseUrl, prefix);
      if (book.name && book.bookUrl) books.push(book);
    }
    return books;
  }

  private readBook(fields: Record<string, NativeValue>, scope: NativeScope, baseUrl: string,
    prefix: string): NativeBookRecord {
    const text = (name: string): string => {
      const value = this.value(fields[name], scope, false, `${prefix}.fields.${name}`);
      return (Array.isArray(value) ? value.map((part: NativeValue): string => NativeExpr.toText(part).trim())
        .filter((part: string): boolean => !!part).join(',') : NativeExpr.toText(value)).trim();
    };
    const url = (name: string): string => NativeExpr.resolveUrl(NativeExpr.toText(this.first(
      this.value(fields[name], scope, false, `${prefix}.fields.${name}`))).trim(), baseUrl);
    const typeSpec = fields['type'];
    const literalType = typeof typeSpec === 'string' && /^(text|audio|comic|image|video)$/i.test(typeSpec.trim());
    return {
      name: text('name'),
      author: text('author'),
      kind: text('kind'),
      intro: text('intro'),
      coverUrl: this.definition.coverDecode ? SourceCoverUrl.wrap(url('coverUrl'), this.definition.url) : url('coverUrl'),
      wordCount: text('wordCount'),
      lastChapter: text('lastChapter'),
      updateTime: text('updateTime'),
      status: text('status'),
      bookUrl: url('bookUrl'),
      tocUrl: url('tocUrl'),
      type: (literalType ? String(typeSpec).trim() : text('type')).toLowerCase(),
      keep: {}
    };
  }

  private first(value: NativeValue): NativeValue {
    return Array.isArray(value) ? (value.length > 0 ? value[0] : '') : value;
  }

  private listItems(rule: string, scope: NativeScope, baseUrl: string, field: string = ''): NativeValue[] {
    const spec = (rule || '').trim();
    if (!spec) return [];
    let items: NativeValue[];
    try {
      if (spec.startsWith('=')) {
        const value = this.expr.evaluate(spec.substring(1), scope);
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
  private template(spec: NativeValue, scope: NativeScope): NativeValue {
    if (typeof spec !== 'string') return spec;
    const text = spec.trim();
    if (text.startsWith('=')) return this.expr.evaluate(text.substring(1), scope);
    return this.expr.render(spec, scope);
  }

  /** 字段位置的求值。field 给出规则在定义里的位置，出错时用来定位，调试时用来记录。 */
  private value(spec: NativeValue, scope: NativeScope, list: boolean = false, field: string = ''): NativeValue {
    let result: NativeValue;
    try {
      result = this.rawValue(spec, scope, list);
    } catch (e) {
      throw this.fieldError(field, spec, e);
    }
    this.traceRule(field, spec, result, list, scope);
    return result;
  }

  /** 字段位置：= 开头按表达式，含 {{ }} 按模板，其余按选择器规则在当前元素上取值。 */
  private rawValue(spec: NativeValue, scope: NativeScope, list: boolean = false): NativeValue {
    if (spec === undefined || spec === null || spec === '') return list ? [] : '';
    if (typeof spec !== 'string') return spec;
    const text = spec.trim();
    if (text.startsWith('=')) return this.expr.evaluate(text.substring(1), scope);
    if (text.indexOf('{{') >= 0) return this.expr.render(spec, scope);
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
