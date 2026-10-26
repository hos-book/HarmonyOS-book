/**
 * 原生书源的定义格式：解析、校验，以及与书源表字段之间的打包/还原。
 *
 * 原生书源不新增数据库列：完整定义以 JSON 存进 jsLib 字段（以 "nativeSource" 键开头作为标记），
 * 其余列只保留名称、分组、请求头等列表与请求层需要的信息。这样备份、云同步、导入导出都沿用现有通道。
 *
 * 本文件不依赖系统 API，可直接在 Node 回归脚本中加载。
 */

import { NativeExpr } from './NativeExpr';
import { NativeJsPrelude } from './NativeJsPrelude';
import type { NativeValue } from './NativeExpr';

export interface NativeVarSpec {
  key: string;
  label?: string;
  options?: string[];
  default?: string;
  /** 是否在发现页显示为筛选项。 */
  filter?: boolean;
  /** js 里的函数名：打开书源设置页时运行它取选项列表（例如测速后列出可用线路），失败时用 options。 */
  optionsScript?: string;
}

/** 听书音色：id 是传给接口的值，name 是显示名。 */
export interface NativeVoiceSpec {
  id: string;
  name: string;
}

export interface NativeRequestSpec {
  url?: string;
  method?: string;
  headers?: Record<string, string>;
  body?: NativeValue;
  /**
   * 用内置浏览器加载并取渲染后的页面，用于必须执行网页自身脚本的站点。
   * 写成对象时可以等指定元素出现再取：{ "waitFor": "选择器", "timeout": 秒 }。
   */
  webView?: boolean | NativeWebViewSpec;
  /** 请求参数与表单的编码，如 gbk；不写为 UTF-8。响应的解码由应用自动识别。 */
  charset?: string;
  /** 请求失败后的重试次数，0 到 3。 */
  retry?: number;
}

export interface NativeWebViewSpec {
  /** CSS 选择器：等这个元素出现后再取页面。 */
  waitFor?: string;
  /** 最长等待秒数，默认 15，上限 60。 */
  timeout?: number;
}

/** 点一下发一个请求、把结果提示给用户的动作。open 有值时改为在应用内打开这个网页。 */
export interface NativeActionSpec extends NativeRequestSpec {
  label: string;
  /** js 里的函数名：点击后运行它，返回的文字作为提示。写了 script 就不发 url 请求。 */
  script?: string;
  when?: string;
  open?: string;
  /** 请求完成后提示给用户的文字。 */
  message?: string;
}

export interface NativeLoginFieldSpec {
  key: string;
  label?: string;
  /** 为 true 时按密码输入，内容不显示也不保存。 */
  secret?: boolean;
}

export interface NativeLoginSubmitSpec extends NativeRequestSpec {
  /** 求值为真表示登录成功。 */
  ok: string;
  /** 登录成功后要保存的凭据，之后通过 login.token 读取。 */
  token?: string;
  /** 可选：账号显示名，通过 login.user 读取。 */
  user?: string;
  /** 失败时提示给用户的文字。 */
  message?: string;
}

/** 先取一次、之后复用的值（如访问令牌）。只能在这里声明，规则不能随处写入状态。 */
export interface NativeCacheSpec extends NativeRequestSpec {
  /** 从响应里取出要保存的值。 */
  value: string;
  /** 有效期（秒），默认 600。到期后下次用到时重新获取。 */
  ttl?: number;
  when?: string;
}

export interface NativeLoginCheckSpec extends NativeRequestSpec {
  /** 求值为真表示已登录。 */
  ok: string;
  /** 可选：账号显示名。 */
  name?: string;
}

export interface NativeLoginSpec {
  /** 登录页地址，在应用内置浏览器中打开。使用表单登录时可以不写。 */
  url?: string;
  /** 表单登录：要用户填写的项。填写的值在 submit 和 sendCode 里通过 form.名称 读取。 */
  form?: NativeLoginFieldSpec[];
  /** 表单登录：提交登录的请求。 */
  submit?: NativeLoginSubmitSpec;
  /** 脚本登录：js 里的函数名，拿到 ctx.form 自己完成登录，成功时调用 login.save(令牌, 用户名)。代替 submit。 */
  script?: string;
  /** 表单登录：发送验证码之类的辅助请求。 */
  sendCode?: NativeActionSpec;
  /** 登录成功后应当存在的 Cookie 名，用于判断登录状态。 */
  cookies?: string[];
  check?: NativeLoginCheckSpec;
}

export interface NativeScriptLimitsSpec {
  requests?: number;
}

export interface NativeStageSpec extends NativeRequestSpec {
  /**
   * js 里的函数名：由它代替请求取得这个阶段的“页面”，函数里可以同步发请求、读写变量。返回值之后照常
   * 交给 list、fields 等规则；不写 list、fields 时按返回数组的每一项、同名键取值。
   */
  script?: string;
  let?: Record<string, NativeValue>;
  /** 求值结果非空时视为接口报错，文本即错误信息。 */
  fail?: string;
  list?: string;
  fields?: Record<string, NativeValue>;
}

export interface NativeMenuSpec {
  title: string;
  url?: string;
  when?: string;
  /** 当前分类的列表/字段；未写时分别沿用 explore 的配置。 */
  list?: string;
  fields?: Record<string, NativeValue>;
  /** 只在这个分类的请求上附加的请求头，例如个人书架需要的登录凭据。 */
  headers?: Record<string, string>;
  /** 这个分类自己的请求方法与请求体，不写时沿用 explore 的。body 写空串表示不带请求体。 */
  method?: string;
  body?: NativeValue;
}

export interface NativeDynamicMenuSpec extends NativeRequestSpec {
  /**
   * js 里的函数名：由它代替请求返回分类（数组），不发 url 请求。脚本模式下 list 默认取返回的每一项，
   * title 默认 $.title，target 默认 $.url（其中的 {{page}} 换成页码）。
   */
  script?: string;
  list?: string;
  title?: string;
  target?: string;
}

export interface NativeExploreSpec extends NativeStageSpec {
  menus?: NativeMenuSpec[];
  dynamicMenus?: NativeDynamicMenuSpec;
}

export interface NativeDetailSpec extends NativeStageSpec {
  /** 存入书籍变量，后续阶段通过 book.vars.名称 读取。 */
  keep?: Record<string, NativeValue>;
  /** 主请求之后的附加请求，例如作者在一个接口、最新章节在另一个接口。 */
  fetch?: Record<string, NativeFetchSpec>;
}

export interface NativeTocSpec extends NativeStageSpec {
  nextUrl?: string;
  reverse?: boolean;
  /** nextUrl 列出剩余全部目录页时，每批并发请求的页数，1 到 16，默认 4。 */
  batch?: number;
}

export interface NativeFetchSpec extends NativeRequestSpec {
  when?: string;
}

export interface NativeReplaceSpec {
  pattern: string;
  with?: string;
  flags?: string;
}

/** 段评与章末评论入口：书源只给数据和地址，气泡与卡片由应用绘制。 */
export interface NativeCommentPageSpec {
  html: string;
  data?: Record<string, NativeValue>;
  title?: string;
  height?: number;
  /** At most three requests, evaluated only after a click. Results bind directly to their names. */
  fetch?: Record<string, NativeFetchSpec>;
}

export interface NativeCommentsSpec {
  when?: string;
  /** 评论数统计接口，结果绑定为 stats。 */
  stats?: NativeRequestSpec;
  /** 每段评论数：键（或下标）是正文行号，值是条数。 */
  counts?: string;
  /** 段评页地址，可用 para.index / para.text / para.count。 */
  paragraphUrl?: string;
  /** 整章评论页地址，可用 total。 */
  chapterUrl?: string;
  page?: NativeCommentPageSpec;
  chapterPage?: NativeCommentPageSpec;
  max?: number;
}

/** 正文末尾的链接按钮，点击后在应用内打开网页（例如视频播放页）。 */
export interface NativeLinkSpec {
  label: string;
  /** 点击后在应用内打开的网页。与 request 二选一。 */
  url?: string;
  when?: string;
  /** 点击后发出的请求（点赞、收藏等），结果用 message 提示。 */
  request?: NativeRequestSpec;
  message?: string;
}

/** 漫画图片解密：密钥和 IV 在取正文时算好，应用下载图片后用系统加密框架解密。 */
export interface NativeImageDecodeSpec {
  /** js 中的字节处理函数，与标准加密字段互斥。 */
  script?: string;
  params?: Record<string, NativeValue>;
  processPlainImages?: boolean;
  /** 如 AES/CBC/PKCS5Padding。 */
  algorithm?: string;
  key?: string;
  iv?: string;
  /** 显式编码时 key 是字面值、模板或表达式；省略时保留旧规则语义。 */
  keyEncoding?: 'hex' | 'utf8';
  /** 每张图片前 16 字节作为 IV，仅支持 AES-CBC，不能同时配置 iv。 */
  ivPrefixBytes?: number;
}

export interface NativeContentSpec extends NativeStageSpec {
  comments?: NativeCommentsSpec;
  links?: NativeLinkSpec[];
  fetch?: Record<string, NativeFetchSpec>;
  text?: string;
  images?: string;
  audio?: string;
  /** 视频类书籍这一集的视频流地址，由应用自带的播放页播放。 */
  video?: string;
  /** audio / video 为空时给用户看的原因，可读取附加请求的结果；不写时从接口返回的 code/message 归纳。 */
  mediaError?: string;
  /** 取图片、音频时附带的请求头，例如 Referer。 */
  mediaHeaders?: Record<string, string>;
  /** 正文分页地址：一个地址是下一页，列表或多行文本是本章剩余全部分页。 */
  nextUrl?: string;
  /** nextUrl 列出剩余全部分页时，每批并发请求的页数，1 到 16，默认 4。 */
  batch?: number;
  imageDecode?: NativeImageDecodeSpec;
  replace?: NativeReplaceSpec[];
}

/** Literal cover parameters, shared by search, explore and detail. IV is hex or a 16-byte file prefix. */
export interface NativeCoverDecodeSpec {
  algorithm: string;
  key: string;
  keyEncoding?: 'hex' | 'utf8';
  iv?: string;
  ivPrefixBytes?: number;
}

export interface NativeSourceDefinition {
  coverDecode?: NativeCoverDecodeSpec;
  /** 封面专用请求头，覆盖顶层 headers，支持模板/表达式。 */
  coverHeaders?: Record<string, string>;
  nativeSource: number;
  name: string;
  url: string;
  group?: string;
  comment?: string;
  /** text | audio | comic | video */
  type?: string;
  enabled?: boolean;
  enabledExplore?: boolean;
  rate?: string;
  headers?: Record<string, string>;
  vars?: NativeVarSpec[];
  /** 函数库：用 fn 定义的纯计算函数，供表达式调用。 */
  lib?: string;
  /** JS 函数库：顶层定义的函数可在表达式里按名调用，函数里通过 native.名称 使用内置函数。只做纯计算。 */
  js?: string;
  /** 脚本阶段的预算：每次阶段运行最多发多少个请求（默认 30，上限 100）。 */
  scriptLimits?: NativeScriptLimitsSpec;
  login?: NativeLoginSpec;
  /** 可选的听书音色。用户在听书页选中的 id 存在书籍变量里，规则通过 book.vars.custom 读取。 */
  voices?: NativeVoiceSpec[];
  cache?: Record<string, NativeCacheSpec>;
  /** 书源设置页里的动作按钮（签到、打开个人中心等）。 */
  actions?: NativeActionSpec[];
  let?: Record<string, NativeValue>;
  search?: NativeStageSpec;
  explore?: NativeExploreSpec;
  detail?: NativeDetailSpec;
  toc?: NativeTocSpec;
  content?: NativeContentSpec;
}

export class NativeSourceSpec {
  static readonly FORMAT: string = 'native';
  static readonly VERSION: number = 1;
  static readonly SEARCH_MARKER: string = 'native:search';
  /** 可以写 script 的阶段。 */
  static readonly SCRIPT_STAGES: string[] = ['search', 'explore', 'detail', 'toc', 'content'];

  /** 定义里所有指向 js 函数的地方：阶段 script、脚本分类、动作按钮、动态选项、脚本登录。 */
  static scriptRefs(definition: NativeSourceDefinition): Array<{ path: string, fn: NativeValue }> {
    const refs: Array<{ path: string, fn: NativeValue }> = [];
    if (definition.content?.imageDecode?.script !== undefined) {
      refs.push({ path: 'content.imageDecode.script', fn: definition.content.imageDecode.script });
    }
    const raw = definition as NativeValue as Record<string, NativeValue>;
    for (const name of NativeSourceSpec.SCRIPT_STAGES) {
      const stage = raw[name] as NativeStageSpec | undefined;
      if (stage && stage.script !== undefined) refs.push({ path: `${name}.script`, fn: stage.script });
    }
    (Array.isArray(definition.actions) ? definition.actions : []).forEach((action: NativeActionSpec, i: number): void => {
      if (action && action.script !== undefined) refs.push({ path: `actions[${i}].script`, fn: action.script });
    });
    for (const item of Array.isArray(definition.vars) ? definition.vars : []) {
      if (item && item.optionsScript !== undefined) refs.push({ path: `vars.${item.key}.optionsScript`, fn: item.optionsScript });
    }
    const dynamicMenus = definition.explore ? definition.explore.dynamicMenus : undefined;
    if (dynamicMenus && typeof dynamicMenus === 'object' && dynamicMenus.script !== undefined) {
      refs.push({ path: 'explore.dynamicMenus.script', fn: dynamicMenus.script });
    }
    const login = definition.login;
    if (login && typeof login === 'object') {
      if (login.script !== undefined) refs.push({ path: 'login.script', fn: login.script });
      if (login.sendCode && login.sendCode.script !== undefined) {
        refs.push({ path: 'login.sendCode.script', fn: login.sendCode.script });
      }
    }
    return refs;
  }

  /** 定义里所有 script 指向的函数名（去重），导入时检查它们在 js 里存在。 */
  static scriptFunctions(definition: NativeSourceDefinition): string[] {
    const names: string[] = [];
    for (const ref of NativeSourceSpec.scriptRefs(definition)) {
      const fn = typeof ref.fn === 'string' ? ref.fn.trim() : '';
      if (fn && names.indexOf(fn) < 0) names.push(fn);
    }
    return names;
  }
  static readonly EXPLORE_MARKER: string = 'native:explore';

  private static unpackCache: Map<string, NativeSourceDefinition> = new Map();

  /** jsLib 字段里存的是不是原生书源定义。 */
  static isPacked(jsLib: string): boolean {
    return /^\s*\{\s*"nativeSource"\s*:/.test(jsLib || '');
  }

  /** 导入的 JSON 对象是不是原生书源。 */
  static isDefinitionObject(value: NativeValue): boolean {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
    return value['sourceFormat'] === NativeSourceSpec.FORMAT || typeof value['nativeSource'] === 'number';
  }

  /** 从导入对象整理出定义；不合法时抛出带原因的错误。 */
  static fromObject(value: NativeValue): NativeSourceDefinition {
    if (!NativeSourceSpec.isDefinitionObject(value)) throw new Error('不是原生书源：缺少 "sourceFormat": "native"');
    const raw = value as Record<string, NativeValue>;
    const version = Number(raw['version'] || raw['nativeSource'] || NativeSourceSpec.VERSION);
    if (version > NativeSourceSpec.VERSION) {
      throw new Error(`该原生书源需要更新版本的应用（格式版本 ${version}）`);
    }
    const definition: Record<string, NativeValue> = { nativeSource: NativeSourceSpec.VERSION };
    for (const key of Object.keys(raw)) {
      if (key === 'sourceFormat' || key === 'version' || key === 'nativeSource') continue;
      definition[key] = raw[key];
    }
    definition['name'] = String(raw['name'] || '').trim();
    definition['url'] = String(raw['url'] || '').trim();
    const errors = NativeSourceSpec.validate(definition as NativeSourceDefinition);
    if (errors.length > 0) throw new Error(errors.slice(0, 5).join('；'));
    return definition as NativeSourceDefinition;
  }

  /** 导出给用户的对象：把内部标记换回 sourceFormat/version。 */
  static toExportObject(definition: NativeSourceDefinition): Record<string, NativeValue> {
    const out: Record<string, NativeValue> = {
      sourceFormat: NativeSourceSpec.FORMAT,
      version: definition.nativeSource || NativeSourceSpec.VERSION
    };
    const raw = definition as NativeValue as Record<string, NativeValue>;
    for (const key of Object.keys(raw)) {
      if (key !== 'nativeSource') out[key] = raw[key];
    }
    return out;
  }

  static pack(definition: NativeSourceDefinition): string {
    const ordered: Record<string, NativeValue> = { nativeSource: definition.nativeSource || NativeSourceSpec.VERSION };
    const raw = definition as NativeValue as Record<string, NativeValue>;
    for (const key of Object.keys(raw)) {
      if (key !== 'nativeSource') ordered[key] = raw[key];
    }
    return JSON.stringify(ordered);
  }

  static unpack(jsLib: string): NativeSourceDefinition | null {
    if (!NativeSourceSpec.isPacked(jsLib)) return null;
    const cached = NativeSourceSpec.unpackCache.get(jsLib);
    if (cached) return cached;
    try {
      const parsed = JSON.parse(jsLib) as NativeSourceDefinition;
      if (NativeSourceSpec.unpackCache.size >= 64) NativeSourceSpec.unpackCache.clear();
      NativeSourceSpec.unpackCache.set(jsLib, parsed);
      return parsed;
    } catch (e) {
      return null;
    }
  }

  static bookSourceType(definition: NativeSourceDefinition): number {
    const type = String(definition.type || 'text').toLowerCase();
    if (type === 'audio') return 1;
    if (type === 'comic' || type === 'image') return 2;
    return 0;
  }

  /** Decoded AES key length in bytes, or -1 when the key or its encoding is malformed. */
  static coverKeyBytes(spec: NativeCoverDecodeSpec): number {
    if (typeof spec.key !== 'string' || !spec.key || spec.key.length > 128) return -1;
    if (spec.keyEncoding === 'utf8') {
      // Same byte count util.TextEncoder produces (lone surrogates become U+FFFD), without a platform import.
      let bytes = 0;
      for (let i = 0; i < spec.key.length; i++) {
        const code = spec.key.charCodeAt(i);
        const next = spec.key.charCodeAt(i + 1);
        if (code < 0x80) bytes += 1;
        else if (code < 0x800) bytes += 2;
        else if (code >= 0xD800 && code <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) { bytes += 4; i++; }
        else bytes += 3;
      }
      return bytes;
    }
    if (spec.keyEncoding !== undefined && spec.keyEncoding !== 'hex') return -1;
    return /^(?:[a-f0-9]{2})+$/i.test(spec.key) ? spec.key.length / 2 : -1;
  }

  static validate(definition: NativeSourceDefinition): string[] {
    const errors: string[] = [];
    const cover = definition.coverDecode;
    if (cover !== undefined) {
      if (!cover || !/^AES\/CBC\/PKCS(?:5|7)Padding$/i.test(cover.algorithm || '') ||
        ![16, 24, 32].includes(NativeSourceSpec.coverKeyBytes(cover)) ||
        (cover.ivPrefixBytes === 16 ? !!cover.iv :
          (cover.ivPrefixBytes !== undefined && cover.ivPrefixBytes !== 0) || !/^[a-f0-9]{32}$/i.test(cover.iv || ''))) {
        errors.push('coverDecode 需要 AES/CBC/PKCS7Padding、16/24/32 字节的 key，以及 iv 或 ivPrefixBytes:16');
      }
    }
    if (!definition.name) errors.push('缺少书源名称 name');
    if (!/^https?:\/\//i.test(definition.url || '')) errors.push('书源地址 url 必须以 http:// 或 https:// 开头');
    if (!definition.search && !definition.explore) errors.push('至少需要 search 或 explore 其中之一');
    const type = String(definition.type || 'text').toLowerCase();
    if (['text', 'audio', 'comic', 'image', 'video'].indexOf(type) < 0) {
      errors.push('type 只能是 text、audio、comic 或 video');
    }

    const keys: Set<string> = new Set();
    for (const item of definition.vars || []) {
      if (!item || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(item.key || '')) {
        errors.push('vars 里的 key 只能用字母、数字和下划线');
        continue;
      }
      if (keys.has(item.key)) errors.push(`vars 里的 key 重复：${item.key}`);
      keys.add(item.key);
      if (item.options !== undefined && !Array.isArray(item.options)) errors.push(`vars.${item.key}.options 必须是数组`);
    }

    if (definition.lib !== undefined && typeof definition.lib !== 'string') {
      errors.push('lib 必须是字符串');
    } else if (definition.lib) {
      const problem = NativeExpr.checkLibrary(definition.lib);
      if (problem) errors.push(`lib：${problem}`);
    }
    if (definition.js !== undefined && typeof definition.js !== 'string') {
      errors.push('js 必须是字符串');
    } else if (definition.js && definition.js.length > NativeJsPrelude.MAX_CODE_LENGTH) {
      errors.push(`js 太长：上限 ${Math.round(NativeJsPrelude.MAX_CODE_LENGTH / 1024)} KB`);
    }
    for (const ref of NativeSourceSpec.scriptRefs(definition)) {
      if (typeof ref.fn !== 'string' || !NativeJsPrelude.isIdentifier(ref.fn.trim())) {
        errors.push(`${ref.path} 必须是 js 里的函数名`);
      } else if (!definition.js || !definition.js.trim()) {
        errors.push(`${ref.path} 需要在 js 里定义函数 ${ref.fn.trim()}`);
      }
    }
    if (definition.scriptLimits !== undefined) {
      const limits = definition.scriptLimits;
      const requests = limits && typeof limits === 'object' ? limits.requests : undefined;
      if (!limits || typeof limits !== 'object' || (requests !== undefined &&
        !(Number.isInteger(requests) && requests >= 1 && requests <= 100))) {
        errors.push('scriptLimits.requests 必须是 1 到 100 的整数');
      }
    }
    if (definition.voices !== undefined) {
      if (!Array.isArray(definition.voices)) {
        errors.push('voices 必须是数组');
      } else if (definition.voices.some((voice: NativeVoiceSpec): boolean =>
        !voice || String(voice.id === undefined ? '' : voice.id) === '' || !voice.name)) {
        errors.push('voices 的每一项都需要 id 和 name');
      }
    }
    NativeSourceSpec.checkValues(definition.let, 'let', errors);
    NativeSourceSpec.checkValues(definition.headers, 'headers', errors);
    if (definition.coverHeaders !== undefined && (!definition.coverHeaders ||
      typeof definition.coverHeaders !== 'object' || Array.isArray(definition.coverHeaders) ||
      Object.values(definition.coverHeaders).some((value: string): boolean => typeof value !== 'string'))) {
      errors.push('coverHeaders 必须是请求头名称到字符串的对象');
    }
    NativeSourceSpec.checkValues(definition.coverHeaders, 'coverHeaders', errors);
    if (definition.cache !== undefined) {
      if (!definition.cache || typeof definition.cache !== 'object' || Array.isArray(definition.cache)) {
        errors.push('cache 必须是对象');
      } else {
        for (const name of Object.keys(definition.cache)) {
          const entry = definition.cache[name];
          if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) errors.push(`cache 的名称只能用字母、数字和下划线：${name}`);
          if (!entry || !entry.url || !entry.value) errors.push(`cache.${name} 需要 url 和 value`);
        }
        NativeSourceSpec.checkValues(definition.cache, 'cache', errors);
      }
    }
    if (definition.actions !== undefined) {
      if (!Array.isArray(definition.actions)) {
        errors.push('actions 必须是数组');
      } else {
        for (const action of definition.actions) {
          if (!action || !action.label || (!action.url && !action.open && !action.script)) {
            errors.push('actions 的每一项都需要 label，以及 url、open 或 script');
          }
        }
        NativeSourceSpec.checkValues(definition.actions, 'actions', errors);
      }
    }
    if (definition.login !== undefined) {
      const login = definition.login;
      if (!login || typeof login !== 'object') {
        errors.push('login 必须是对象');
      } else if (!login.url && !login.submit && !login.script) {
        errors.push('login 需要 url（网页登录）、submit（表单登录）或 script（脚本登录）');
      } else if (login.url && !/^https?:\/\//i.test(String(login.url))) {
        errors.push('login.url 必须是以 http:// 或 https:// 开头的登录页地址');
      } else {
        if (login.submit) {
          if (!login.submit.url || !login.submit.ok) errors.push('login.submit 需要 url 和 ok');
          if (!Array.isArray(login.form) || login.form.length === 0) errors.push('表单登录需要 login.form');
          NativeSourceSpec.checkValues(login.submit, 'login.submit', errors);
        }
        for (const field of Array.isArray(login.form) ? login.form : []) {
          if (!field || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(field.key || '')) {
            errors.push('login.form 里的 key 只能用字母、数字和下划线');
          }
        }
        if (login.sendCode) {
          if (!login.sendCode.url && !login.sendCode.script) errors.push('login.sendCode 需要 url 或 script');
          NativeSourceSpec.checkValues(login.sendCode, 'login.sendCode', errors);
        }
        if (login.cookies !== undefined && !Array.isArray(login.cookies)) errors.push('login.cookies 必须是数组');
        if (login.check) {
          if (!login.check.url || !login.check.ok) errors.push('login.check 需要 url 和 ok');
          NativeSourceSpec.checkValues(login.check, 'login.check', errors);
        }
      }
    }
    const stages: Array<[string, NativeStageSpec | undefined]> = [
      ['search', definition.search], ['explore', definition.explore], ['detail', definition.detail],
      ['toc', definition.toc], ['content', definition.content]
    ];
    for (const entry of stages) {
      if (entry[1] === undefined) continue;
      if (!entry[1] || typeof entry[1] !== 'object' || Array.isArray(entry[1])) {
        errors.push(`${entry[0]} 必须是对象`);
        continue;
      }
      NativeSourceSpec.checkValues(entry[1], entry[0], errors);
    }
    if (definition.search) {
      if (!definition.search.url && !definition.search.script) errors.push('search 缺少 url');
      NativeSourceSpec.requireBookFields(definition.search, 'search', errors);
    }
    if (definition.explore) {
      const explore = definition.explore;
      if ((!explore.menus || explore.menus.length === 0) && !explore.dynamicMenus) {
        errors.push('explore 需要 menus 或 dynamicMenus');
      }
      if (explore.menus !== undefined && !Array.isArray(explore.menus)) errors.push('explore.menus 必须是数组');
      const dynamic = explore.dynamicMenus;
      if (dynamic && (typeof dynamic !== 'object' || Array.isArray(dynamic))) {
        errors.push('explore.dynamicMenus 必须是对象');
      } else if (dynamic && dynamic.script !== undefined) {
        if (dynamic.url) errors.push('explore.dynamicMenus 写了 script 就不要写 url');
      } else if (dynamic && (!dynamic.url || !dynamic.list || !dynamic.title || !dynamic.target)) {
        errors.push('explore.dynamicMenus 需要 url、list、title 和 target，或者写 script');
      }
      if (explore.dynamicMenus || !Array.isArray(explore.menus) || explore.menus.length === 0) {
        NativeSourceSpec.requireBookFields(explore, 'explore', errors);
      }
      for (const [index, menu] of (Array.isArray(explore.menus) ? explore.menus : []).entries()) {
        if (!menu || typeof menu !== 'object' || Array.isArray(menu)) {
          errors.push(`explore.menus[${index}] 必须是对象`);
          continue;
        }
        if (menu.list !== undefined && typeof menu.list !== 'string') errors.push(`explore.menus[${index}].list 必须是字符串`);
        if (menu.fields !== undefined && (!menu.fields || typeof menu.fields !== 'object' || Array.isArray(menu.fields))) {
          errors.push(`explore.menus[${index}].fields 必须是对象`);
        }
        if (menu.url) NativeSourceSpec.requireBookFields(Object.assign({}, explore, {
          list: menu.list === undefined ? explore.list : menu.list,
          fields: menu.fields === undefined ? explore.fields : menu.fields
        }), `explore.menus[${index}]`, errors);
      }
    }
    if (definition.toc) {
      // 脚本阶段可以不写 list 和 fields（按返回数组的每项、同名键取值）；写了 fields 就要写全。
      const scripted = !!definition.toc.script;
      const fields = definition.toc.fields || {};
      if (!definition.toc.list && !scripted) errors.push('toc 缺少 list');
      if (!scripted || definition.toc.fields) {
        if (!fields['title']) errors.push('toc.fields 缺少 title');
        if (!fields['url']) errors.push('toc.fields 缺少 url');
      }
      NativeSourceSpec.checkBatch(definition.toc.batch, 'toc.batch', errors);
    }
    if (definition.content) {
      const content = definition.content;
      if (!content.text && !content.images && !content.audio && !content.video && !content.script) {
        errors.push('content 需要 text、images、audio 或 video 之一');
      }
      if (content.replace !== undefined && !Array.isArray(content.replace)) errors.push('content.replace 必须是数组');
      NativeSourceSpec.checkBatch(content.batch, 'content.batch', errors);
      if (content.links !== undefined) {
        if (!Array.isArray(content.links)) {
          errors.push('content.links 必须是数组');
        } else if (content.links.some((link: NativeLinkSpec): boolean =>
          !link || !link.label || (!link.url && !(link.request && link.request.url)))) {
          errors.push('content.links 的每一项都需要 label，以及 url 或 request');
        }
      }
      if (content.imageDecode !== undefined) {
        const decode = content.imageDecode;
        if (decode && decode.script !== undefined) {
          if ([decode.algorithm, decode.key, decode.iv, decode.keyEncoding, decode.ivPrefixBytes]
            .some((value: NativeValue): boolean => value !== undefined)) {
            errors.push('content.imageDecode.script 不能与 algorithm/key/iv/keyEncoding/ivPrefixBytes 混用');
          }
          if (decode.params !== undefined && (!decode.params || typeof decode.params !== 'object' || Array.isArray(decode.params))) {
            errors.push('content.imageDecode.params 必须是对象');
          }
          if (decode.processPlainImages !== undefined && typeof decode.processPlainImages !== 'boolean') {
            errors.push('content.imageDecode.processPlainImages 必须是布尔值');
          }
        } else {
          if (decode && (decode.params !== undefined || decode.processPlainImages !== undefined)) {
            errors.push('content.imageDecode.params/processPlainImages 需要 script');
          }
          if (!decode || !decode.algorithm || !decode.key) {
            errors.push('content.imageDecode 需要 algorithm 和 key');
          } else if (!/^(aes|desede|3des)\//i.test(String(decode.algorithm))) {
            errors.push('content.imageDecode.algorithm 只支持 AES 和 3DES，例如 AES/CBC/PKCS5Padding');
          }
          if (decode && decode.keyEncoding !== undefined && !['hex', 'utf8'].includes(decode.keyEncoding)) {
            errors.push('content.imageDecode.keyEncoding 只支持 hex 或 utf8');
          }
          if (decode && decode.keyEncoding !== undefined && typeof decode.key === 'string' &&
            !decode.key.trim().startsWith('=') && !decode.key.includes('{{')) {
            const length = NativeSourceSpec.coverKeyBytes({ algorithm: decode.algorithm || '', key: decode.key, keyEncoding: decode.keyEncoding });
            const sizes = /^aes\//i.test(decode.algorithm || '') ? [16, 24, 32] : [24];
            if (!sizes.includes(length)) errors.push(`content.imageDecode.key 需要 ${sizes.join('/')} 字节的有效密钥`);
          }
          if (decode && decode.ivPrefixBytes !== undefined) {
            if (decode.ivPrefixBytes !== 16) errors.push('content.imageDecode.ivPrefixBytes 只允许 16');
            if (decode.iv !== undefined) errors.push('content.imageDecode 的 iv 与 ivPrefixBytes 不能同时配置');
            if (!/^AES\/CBC\/PKCS(?:5|7)Padding$/i.test(decode.algorithm || '')) {
              errors.push('content.imageDecode.ivPrefixBytes 需要 AES/CBC/PKCS5Padding 或 PKCS7Padding');
            }
          }
        }
      }
      if (content.comments) {
        if (!content.comments.paragraphUrl && !content.comments.chapterUrl &&
          !content.comments.page && !content.comments.chapterPage) {
          errors.push('content.comments 需要 paragraphUrl、chapterUrl、page 或 chapterPage');
        }
        if ((content.comments.paragraphUrl || content.comments.page) && !content.comments.counts) {
          errors.push('content.comments 使用 paragraphUrl/page 时需要 counts');
        }
        NativeSourceSpec.checkCommentPage(content.comments.page, 'content.comments.page', errors);
        NativeSourceSpec.checkCommentPage(content.comments.chapterPage, 'content.comments.chapterPage', errors);
      }
      for (const rule of Array.isArray(content.replace) ? content.replace : []) {
        try {
          new RegExp(rule.pattern || '', rule.flags === undefined ? 'g' : rule.flags);
        } catch (e) {
          errors.push(`content.replace 的正则写法不正确：${rule.pattern}`);
        }
      }
    }
    return errors;
  }

  private static checkBatch(batch: number | undefined, path: string, errors: string[]): void {
    if (batch !== undefined && !(typeof batch === 'number' && Number.isInteger(batch) && batch >= 1 && batch <= 16)) {
      errors.push(`${path} 必须是 1 到 16 的整数`);
    }
  }

  private static checkCommentPage(page: NativeCommentPageSpec | undefined, path: string, errors: string[]): void {
    if (page === undefined) return;
    if (!page || typeof page !== 'object' || Array.isArray(page) || typeof page.html !== 'string' || !page.html.trim()) {
      errors.push(`${path}.html 必须是非空字符串规则`);
      return;
    }
    if (page.height !== undefined && !(typeof page.height === 'number' && Number.isFinite(page.height) &&
      page.height >= 0.2 && page.height <= 1)) errors.push(`${path}.height 必须在 0.2 到 1 之间`);
    if (page.title !== undefined && typeof page.title !== 'string') errors.push(`${path}.title 必须是字符串规则`);
    if (page.data !== undefined && (!page.data || typeof page.data !== 'object' || Array.isArray(page.data))) {
      errors.push(`${path}.data 必须是对象`);
    }
    if (page.fetch !== undefined) {
      if (!page.fetch || typeof page.fetch !== 'object' || Array.isArray(page.fetch) || Object.keys(page.fetch).length > 3) {
        errors.push(`${path}.fetch 最多声明 3 个请求`);
      } else {
        for (const name of Object.keys(page.fetch)) {
          const request = page.fetch[name];
          if (!/^[a-zA-Z][a-zA-Z0-9_]*$/.test(name) ||
            ['para', 'total', 'stats', 'book', 'chapter', 'vars', 'login', 'source', 'data', 'body', 'baseUrl'].includes(name)) {
            errors.push(`${path}.fetch 名称无效或占用上下文名称：${name}`);
          }
          if (!request || typeof request.url !== 'string' || !request.url.trim()) errors.push(`${path}.fetch.${name} 需要 url`);
        }
      }
    }
  }

  private static requireBookFields(stage: NativeStageSpec, name: string, errors: string[]): void {
    const fields = stage.fields || {};
    if (!stage.list && !stage.script) errors.push(`${name} 缺少 list`);
    if (stage.script && !stage.fields) return;
    if (!fields['name']) errors.push(`${name}.fields 缺少 name`);
    if (!fields['bookUrl']) errors.push(`${name}.fields 缺少 bookUrl`);
  }

  /** 递归检查每个字符串值：表达式和模板的语法，以及是否混入了脚本。 */
  private static checkValues(value: NativeValue, path: string, errors: string[]): void {
    if (errors.length >= 20 || value === null || value === undefined) return;
    if (typeof value === 'string') {
      const text = value.trim();
      let problem = '';
      if (text.startsWith('=')) {
        problem = NativeExpr.check(text.substring(1));
      } else if (/^@?js\s*:|<js>|@js\s*:/i.test(text)) {
        problem = '原生书源不支持脚本，请改用 = 表达式';
      } else if (text.indexOf('{{') >= 0) {
        problem = NativeExpr.checkTemplate(text);
      }
      if (problem) errors.push(`${path}：${problem}`);
      return;
    }
    if (Array.isArray(value)) {
      for (let i = 0; i < value.length; i++) NativeSourceSpec.checkValues(value[i], `${path}[${i}]`, errors);
      return;
    }
    if (typeof value === 'object') {
      for (const key of Object.keys(value)) {
        // replace 的 pattern/with 是正则与替换文本，不按规则语法检查。
        if (/\.replace\[\d+\]$/.test(path)) continue;
        NativeSourceSpec.checkValues(value[key], `${path}.${key}`, errors);
      }
    }
  }
}
