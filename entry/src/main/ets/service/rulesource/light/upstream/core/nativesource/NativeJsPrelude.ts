/**
 * 原生书源 JS 函数库与脚本引擎之间的约定：前置脚本、调用代码和结果的编码。
 *
 * 真机用 QuickJS（NativeJsLibrary），Node 回归用 node:vm，两边共用这里生成的代码，行为保持一致。
 * 本文件不依赖系统 API，可直接在 Node 回归脚本中加载。
 */

import type { NativeValue } from './NativeExpr';

export class NativeJsPrelude {
  /** js 字段的长度上限（字符数）。 */
  static readonly MAX_CODE_LENGTH: number = 512 * 1024;

  /**
   * 在书源代码之前执行：用 __host 搭出只读的 native 对象，之后删掉 __host，书源代码只能经 native 调内置函数。
   * 内置函数的参数和返回值都按 JSON 传递。
   *
   * script 为 true 时是脚本阶段的后台环境，另外提供 http、vars、temp、cache、cookie、login、keep、log、sleep、
   * page、device；为 false 时是表达式里调用的环境，这些名字存在但一用就报错，提示改用阶段的 script。
   */
  static source(builtins: string[], script: boolean = false): string {
    return `(function (g) {
  var host = g.__host;
  var define = function (name, value) {
    Object.defineProperty(g, name, { value: value, writable: true, configurable: true, enumerable: false });
  };
  var call = function (name, args) {
    var out = host(name, JSON.stringify(args));
    return out === '' ? null : JSON.parse(out);
  };
  define('uuid', function () {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      var r = Math.random() * 16 | 0;
      return (c === 'x' ? r : (r & 3 | 8)).toString(16);
    });
  });
${script ? NativeJsPrelude.SCRIPT_API : NativeJsPrelude.EXPRESSION_STUBS}
  var names = ${JSON.stringify(builtins)};
  var api = {};
  names.forEach(function (name) {
    api[name] = function () {
      var out = host(name, JSON.stringify(Array.prototype.slice.call(arguments)));
      return out === '' ? null : JSON.parse(out);
    };
  });
  // 写错名字时直接说明，而不是只得到 “not a function”。
  var native = new Proxy(Object.freeze(api), {
    get: function (target, key) {
      if (typeof key !== 'string' || key in target || key === 'toJSON' || key === 'then') return target[key];
      throw new Error('native.' + key + ' 不是可用的内置函数');
    }
  });
  Object.defineProperty(g, 'native', { value: native, enumerable: false });
  Object.defineProperty(g, '__nativeReturn', {
    value: function (value) {
      var text = JSON.stringify(value === undefined ? null : value);
      return text === undefined ? 'null' : text;
    },
    enumerable: false
  });
  delete g.__host;
})(globalThis);`;
  }

  /** 脚本阶段的宿主接口：每个调用都经 __host 同步交给宿主，名字以 @ 开头，与内置函数区分。 */
  private static readonly SCRIPT_API: string = `
  var wrap = function (response) {
    if (response && typeof response === 'object') {
      Object.defineProperty(response, 'json', {
        value: function () { return JSON.parse(response.body); }, enumerable: false
      });
    }
    return response;
  };
  var toRequest = function (input, method, body, options) {
    var request = typeof input === 'string' ? { url: input } : Object.assign({}, input || {});
    if (options) Object.assign(request, options);
    if (method && !request.method) request.method = method;
    if (body !== undefined) request.body = body;
    if (request.body !== undefined && request.body !== null && typeof request.body !== 'string') {
      request.headers = Object.assign({}, request.headers || {});
      var typed = Object.keys(request.headers).some(function (name) { return name.toLowerCase() === 'content-type'; });
      if (!typed) request.headers['Content-Type'] = 'application/json';
      request.body = JSON.stringify(request.body);
    }
    return request;
  };
  define('http', Object.freeze({
    get: function (url, options) { return wrap(call('@http', [toRequest(url, 'GET', undefined, options)])); },
    post: function (url, body, options) { return wrap(call('@http', [toRequest(url, 'POST', body, options)])); },
    request: function (request) { return wrap(call('@http', [toRequest(request)])); },
    all: function (list, options) {
      return call('@httpAll', [(list || []).map(function (item) { return toRequest(item); }),
        options === undefined ? null : options]).map(wrap);
    }
  }));
  var store = function (prefix) {
    return Object.freeze({
      get: function (key) { return call('@' + prefix + 'Get', [String(key)]); },
      set: function (key, value, ttl) { call('@' + prefix + 'Set', [String(key), value === undefined ? null : value, ttl]); }
    });
  };
  define('vars', store('vars'));
  define('temp', store('temp'));
  var cacheStore = store('cache');
  define('cache', Object.freeze({ get: cacheStore.get, set: cacheStore.set, put: cacheStore.set }));
  define('cookie', Object.freeze({
    get: function (url, name) { return call('@cookieGet', [String(url), name === undefined ? '' : String(name)]); },
    set: function (url, value) { call('@cookieSet', [String(url), String(value)]); },
    remove: function (url, name) { call('@cookieRemove', [String(url), name === undefined ? '' : String(name)]); }
  }));
  define('login', Object.freeze({
    get token() { return call('@login', []).token; },
    get user() { return call('@login', []).user; },
    save: function (token, user) {
      call('@loginSave', [token === undefined || token === null ? '' : String(token),
        user === undefined || user === null ? '' : String(user)]);
    }
  }));
  define('device', Object.freeze({
    get id() { return call('@device', ['id']); },
    get ua() { return call('@device', ['ua']); }
  }));
  define('keep', function (key, value) {
    call('@keep', [String(key), value === undefined || value === null ? '' : String(value)]);
  });
  define('log', function () {
    call('@log', [Array.prototype.map.call(arguments, function (part) {
      return typeof part === 'string' ? part : JSON.stringify(part);
    }).join(' ')]);
  });
  define('sleep', function (ms) { call('@sleep', [Number(ms) || 0]); });
  define('ui', Object.freeze({
    toast: function (message) { call('@toast', [message === undefined || message === null ? '' : String(message)]); },
    refreshExplore: function () { call('@refreshExplore', []); }
  }));
  define('browser', Object.freeze({
    verify: function (url, hint) {
      return call('@browserVerify', [String(url), hint === undefined || hint === null ? '' : String(hint)]);
    },
    open: function (url, title) {
      call('@browserOpen', [String(url), title === undefined || title === null ? '' : String(title)]);
    },
    render: function (url, options) { return call('@render', [String(url), options || {}]); }
  }));
  define('page', function (body, url) {
    return { __nativePage: true, body: body === undefined || body === null ? '' : String(body),
      url: url === undefined || url === null ? '' : String(url) };
  });`;

  /** 表达式环境里的同名占位：规则在主线程同步求值，不能等网络，也不应改动状态。 */
  private static readonly EXPRESSION_STUBS: string = `
  var refuse = function () { throw new Error('表达式里不能发请求或读写状态，请改用阶段的 script'); };
  ['http', 'vars', 'temp', 'cache', 'cookie', 'login', 'device', 'ui', 'browser'].forEach(function (name) {
    define(name, new Proxy({}, {
      get: function (target, key) {
        if (typeof key !== 'string' || key === 'toJSON' || key === 'then') return undefined;
        return refuse();
      }
    }));
  });
  ['keep', 'log', 'sleep', 'page'].forEach(function (name) { define(name, refuse); });`;

  /** 脚本阶段返回 page(body, url) 时的标记。 */
  static isPage(value: NativeValue): boolean {
    return !!value && typeof value === 'object' && !Array.isArray(value) && value['__nativePage'] === true;
  }

  /** 调用脚本阶段的函数：fn(ctx)，结果是 JSON 文本；async 函数在本次运行里求出结果。 */
  static stageSource(fn: string, ctx: NativeValue): string {
    return `(function () { var r = ${fn}(${JSON.stringify(ctx === undefined ? null : ctx)});\n` +
      `return r && typeof r.then === 'function' ? r.then(__nativeReturn) : __nativeReturn(r); })()`;
  }

  /** JS 保留字不能用作函数名；内置函数里有 default，拼进检查代码会成为语法错误。 */
  private static readonly RESERVED: string[] = ['break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
    'default', 'delete', 'do', 'else', 'enum', 'export', 'extends', 'false', 'finally', 'for', 'function', 'if',
    'import', 'in', 'instanceof', 'new', 'null', 'return', 'super', 'switch', 'this', 'throw', 'true', 'try',
    'typeof', 'var', 'void', 'while', 'with', 'yield', 'let', 'static', 'implements', 'interface', 'package',
    'private', 'protected', 'public', 'await'];

  /** 能否作为 JS 函数名出现在生成的代码里。 */
  static isIdentifier(name: string): boolean {
    return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name || '') && NativeJsPrelude.RESERVED.indexOf(name) < 0;
  }

  /** 求值结果为 "true" 表示脚本里有这个函数（包括顶层 const/let 定义的）。 */
  static hasSource(name: string): string {
    return `typeof ${name} === 'function'`;
  }

  /** 调用脚本函数，结果是 JSON 文本。 */
  static callSource(name: string, args: NativeValue[]): string {
    return `__nativeReturn(${name}.apply(null, ${JSON.stringify(args.map((arg: NativeValue): NativeValue =>
      arg === undefined ? null : arg))}))`;
  }

  /** 列出 names 里被脚本定义成函数的名字，结果是 JSON 数组。 */
  static definedSource(names: string[]): string {
    const checks = names.filter((name: string): boolean => NativeJsPrelude.isIdentifier(name))
      .map((name: string): string => `typeof ${name} === 'function' ? ${JSON.stringify(name)} : ''`);
    return `JSON.stringify([${checks.join(', ')}].filter(Boolean))`;
  }

  /** definedSource 查出的重名给出导入时的错误信息；没有重名时返回空串。 */
  static clashMessage(clashes: string[], builtins: string[]): string {
    if (clashes.length === 0) return '';
    const name = clashes[0];
    return builtins.indexOf(name) >= 0 ? `js 里的函数 “${name}” 与内置函数重名` :
      `js 里的函数 “${name}” 与 lib 里的函数重名`;
  }

  /** 阶段 script 指向的函数没有在 js 里定义时的错误信息；都在时返回空串。 */
  static missingMessage(required: string[], defined: string[]): string {
    const missing = required.filter((name: string): boolean => defined.indexOf(name) < 0);
    return missing.length > 0 ? `js 里没有阶段 script 用到的函数 “${missing[0]}”` : '';
  }

  static parseResult(text: string): NativeValue {
    if (text === undefined || text === null || text === '') return null;
    return JSON.parse(text);
  }

  /** 脚本里 native.名称(...) 的宿主端：解出参数，调内置函数，把结果编码回去。 */
  static answerBuiltin(builtin: (name: string, args: NativeValue[]) => NativeValue, name: string,
    payload: string): string {
    const args = payload ? JSON.parse(payload) : [];
    const value: NativeValue = builtin(name, Array.isArray(args) ? args : []);
    const text = JSON.stringify(value === undefined ? null : value);
    return text === undefined ? 'null' : text;
  }

  /** 只为明确的未定义标识符错误补充写源提示；不改变脚本环境，也不推断任意业务错误。 */
  static scriptError(message: string, builtins: string[]): string {
    const firstLine = (message || '').split('\n')[0].trim();
    // QuickJS 给标识符加单引号，Node/V8 不加引号。只匹配异常首行，不扫描堆栈或源码。
    const missing = /^ReferenceError: (?:'([A-Za-z_$][A-Za-z0-9_$]*)'|([A-Za-z_$][A-Za-z0-9_$]*)) is not defined$/.exec(firstLine);
    const summary = NativeJsPrelude.shortError(message);
    if (!missing) return summary;
    const name = missing[1] || missing[2];
    if (!NativeJsPrelude.isIdentifier(name) || builtins.indexOf(name) < 0) return summary;
    return `${summary}；若要调用原生书源内置函数，请使用 native.${name}(...)`;
  }

  /** 错误信息只留前几行，避免整段堆栈塞进界面。 */
  static shortError(message: string): string {
    const lines = (message || '').split('\n').map((line: string): string => line.trim()).filter(Boolean);
    return lines.slice(0, 3).join(' ') || '未知错误';
  }
}
