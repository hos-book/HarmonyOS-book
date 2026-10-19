/**
 * 原生书源的表达式语言。
 *
 * 它不是 JavaScript，也没有任何宿主对象：表达式只能对当前数据求值并调用内置函数。
 * 书源还可以在 lib 里用同一套语法定义函数（fn / let / if / for / while / return），用来写签名、
 * 解密这类纯计算；函数碰不到网络、Cookie 和文件。求值步数、调用深度和数据大小都有上限，
 * 死循环或无限递归会被中止并报错。
 *
 * 本文件不依赖系统 API，可直接在 Node 回归脚本中加载。
 */

// 表达式在 JSON 值上求值，类型只有运行时才知道。
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type NativeValue = any;

export interface NativeExprHost {
  /** 在 root 上执行 JSONPath，返回全部命中。 */
  jsonPath(root: NativeValue, path: string): NativeValue[];
  /** 在 content 上执行选择器规则（JSONPath / CSS / XPath / 正则）。 */
  select(content: string, rule: string, baseUrl: string, list: boolean): string[];
  /** 摘要，algorithm 取 MD5 / SHA1 / SHA256 / SHA512，返回小写十六进制。 */
  digest(algorithm: string, text: string): string;
  /** 加解密等需要系统能力的运算；字节数据以 0-255 的数字列表传递。 */
  crypto?(name: string, args: NativeValue[]): NativeValue;
  /** 读取已保存的 Cookie 值。 */
  cookie?(url: string, name: string): string;
}

export class NativeExprError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NativeExprError';
  }
}

export class NativeScope {
  private values: Record<string, NativeValue> = {};
  private parent: NativeScope | null;

  constructor(parent: NativeScope | null = null) {
    this.parent = parent;
  }

  set(name: string, value: NativeValue): NativeScope {
    this.values[name] = value;
    return this;
  }

  has(name: string): boolean {
    if (Object.prototype.hasOwnProperty.call(this.values, name)) return true;
    return this.parent ? this.parent.has(name) : false;
  }

  get(name: string): NativeValue {
    if (Object.prototype.hasOwnProperty.call(this.values, name)) return this.values[name];
    return this.parent ? this.parent.get(name) : undefined;
  }

  /** 给已声明的变量赋值；变量不存在时返回 false。 */
  assign(name: string, value: NativeValue): boolean {
    if (Object.prototype.hasOwnProperty.call(this.values, name)) {
      this.values[name] = value;
      return true;
    }
    return this.parent ? this.parent.assign(name, value) : false;
  }

  child(): NativeScope {
    return new NativeScope(this);
  }
}

interface Token {
  kind: string; // num | str | id | path | op | end
  text: string;
  value: NativeValue;
  pos: number;
  /** 该记号之前是否换过行：换行后的 ( 和 [ 不再接到上一条语句后面。 */
  nl?: boolean;
}

interface Node {
  t: string;
  v?: NativeValue;
  name?: string;
  op?: string;
  a?: Node;
  b?: Node;
  c?: Node;
  args?: Node[];
  keys?: Node[];
  params?: string[];
}

class FunctionDecl {
  name: string;
  params: string[];
  body: Node;

  constructor(name: string, params: string[], body: Node) {
    this.name = name;
    this.params = params;
    this.body = body;
  }
}

/** 语句执行中的跳转：return / break / continue。 */
class Signal {
  kind: string;
  value: NativeValue;

  constructor(kind: string, value: NativeValue = null) {
    this.kind = kind;
    this.value = value;
  }
}

class Lambda {
  params: string[];
  body: Node;
  scope: NativeScope;

  constructor(params: string[], body: Node, scope: NativeScope) {
    this.params = params;
    this.body = body;
    this.scope = scope;
  }
}

const OPERATORS = ['>>>', '=>', '??', '&&', '||', '==', '!=', '<=', '>=', '<<', '>>', '+', '-', '*', '/', '%', '!',
  '<', '>', '?', ':', ',', '.', '(', ')', '[', ']', '{', '}', '&', '|', '^', '~', '=', ';'];
const KEYWORDS = ['fn', 'let', 'if', 'else', 'for', 'in', 'while', 'return', 'break', 'continue'];
const MAX_STEPS = 3000000;
const MAX_CALL_DEPTH = 64;
const MAX_STRING = 8 * 1024 * 1024;
const MAX_LIST = 100000;
const AST_CACHE_LIMIT = 800;

function isIdStart(ch: string): boolean {
  return /[A-Za-z_\u0080-\uFFFF]/.test(ch);
}

function isIdPart(ch: string): boolean {
  return /[A-Za-z0-9_\u0080-\uFFFF]/.test(ch);
}

function tokenize(source: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  while (i < source.length) {
    const ch = source[i];
    if (ch === ' ' || ch === '\n' || ch === '\t' || ch === '\r') {
      i++;
      continue;
    }
    if (ch === '/' && source[i + 1] === '/') {
      while (i < source.length && source[i] !== '\n') i++;
      continue;
    }
    if (ch === '/' && source[i + 1] === '*') {
      const end = source.indexOf('*/', i + 2);
      if (end < 0) throw new NativeExprError(`注释没有结束：位置 ${i}`);
      i = end + 2;
      continue;
    }
    const start = i;
    if (ch === '0' && (source[i + 1] === 'x' || source[i + 1] === 'X')) {
      i += 2;
      while (i < source.length && /[0-9a-fA-F]/.test(source[i])) i++;
      const text = source.substring(start, i);
      if (text.length <= 2) throw new NativeExprError(`十六进制数字不完整：位置 ${start}`);
      tokens.push({ kind: 'num', text: text, value: parseInt(text.substring(2), 16), pos: start });
      continue;
    }
    if (ch >= '0' && ch <= '9') {
      while (i < source.length && /[0-9.]/.test(source[i])) i++;
      const text = source.substring(start, i);
      tokens.push({ kind: 'num', text: text, value: Number(text), pos: start });
      continue;
    }
    if (ch === '"' || ch === "'") {
      let out = '';
      i++;
      let closed = false;
      while (i < source.length) {
        const c = source[i];
        if (c === '\\' && i + 1 < source.length) {
          const next = source[i + 1];
          // 只转义这几个；其他反斜杠原样保留，写正则时不必再叠一层转义。
          if (next === 'n') out += '\n';
          else if (next === 't') out += '\t';
          else if (next === 'r') out += '\r';
          else if (next === '\\' || next === '"' || next === "'") out += next;
          else out += c + next;
          i += 2;
          continue;
        }
        if (c === ch) {
          closed = true;
          i++;
          break;
        }
        out += c;
        i++;
      }
      if (!closed) throw new NativeExprError(`字符串没有结束：位置 ${start}`);
      tokens.push({ kind: 'str', text: out, value: out, pos: start });
      continue;
    }
    if (ch === '$' && (i + 1 >= source.length || !isIdPart(source[i + 1]))) {
      i++;
      // JSONPath 片段：.name、..name、.*、[...]，方括号内允许任意字符。
      while (i < source.length) {
        const c = source[i];
        if (c === '.') {
          let j = i + 1;
          if (source[j] === '.') j++;
          if (source[j] === '*') {
            i = j + 1;
            continue;
          }
          if (source[j] === '[') {
            i = j;
            continue;
          }
          if (j < source.length && isIdPart(source[j])) {
            while (j < source.length && isIdPart(source[j])) j++;
            i = j;
            continue;
          }
          break;
        }
        if (c === '[') {
          let depth = 0;
          let j = i;
          let quote = '';
          while (j < source.length) {
            const d = source[j];
            if (quote) {
              if (d === quote) quote = '';
            } else if (d === '"' || d === "'") {
              quote = d;
            } else if (d === '[') {
              depth++;
            } else if (d === ']') {
              depth--;
              if (depth === 0) break;
            }
            j++;
          }
          if (j >= source.length) throw new NativeExprError(`JSONPath 方括号没有结束：位置 ${i}`);
          i = j + 1;
          continue;
        }
        break;
      }
      const text = source.substring(start, i);
      tokens.push({ kind: 'path', text: text, value: text, pos: start });
      continue;
    }
    if (isIdStart(ch) || ch === '$') {
      i++;
      while (i < source.length && isIdPart(source[i])) i++;
      const text = source.substring(start, i);
      tokens.push({ kind: 'id', text: text, value: text, pos: start });
      continue;
    }
    let matched = '';
    for (const op of OPERATORS) {
      if (source.startsWith(op, i)) {
        matched = op;
        break;
      }
    }
    if (!matched) throw new NativeExprError(`无法识别的字符 “${ch}”：位置 ${i}`);
    tokens.push({ kind: 'op', text: matched, value: matched, pos: start });
    i += matched.length;
  }
  tokens.push({ kind: 'end', text: '', value: null, pos: source.length });
  let previousEnd = 0;
  for (const token of tokens) {
    token.nl = source.substring(previousEnd, token.pos).indexOf('\n') >= 0;
    previousEnd = token.pos + Math.max(1, token.text.length);
  }
  return tokens;
}

class Parser {
  private tokens: Token[];
  private index: number = 0;

  constructor(tokens: Token[]) {
    this.tokens = tokens;
  }

  /** 解析函数库：若干个 fn 定义。 */
  parseLibrary(): FunctionDecl[] {
    const functions: FunctionDecl[] = [];
    while (this.peek().kind !== 'end') {
      if (this.take(';')) continue;
      if (!this.isWord('fn')) {
        throw new NativeExprError(`lib 里只能写 fn 定义，实际是 “${this.peek().text}”：位置 ${this.peek().pos}`);
      }
      this.index++;
      const name = this.identifier('函数名');
      this.expect('(');
      const params: string[] = [];
      while (!this.isOp(')')) {
        params.push(this.identifier('参数名'));
        if (!this.take(',')) break;
      }
      this.expect(')');
      functions.push(new FunctionDecl(name, params, this.block()));
    }
    return functions;
  }

  private isWord(word: string, offset: number = 0): boolean {
    const token = this.peek(offset);
    return token.kind === 'id' && token.text === word;
  }

  private identifier(label: string): string {
    const token = this.peek();
    if (token.kind !== 'id' || KEYWORDS.indexOf(token.text) >= 0) {
      throw new NativeExprError(`此处应为${label}，实际是 “${token.text || '结尾'}”：位置 ${token.pos}`);
    }
    this.index++;
    return token.text;
  }

  private block(): Node {
    this.expect('{');
    const statements: Node[] = [];
    while (!this.isOp('}')) {
      if (this.peek().kind === 'end') throw new NativeExprError('代码块缺少 “}”');
      if (this.take(';')) continue;
      statements.push(this.statement());
    }
    this.expect('}');
    return { t: 'block', args: statements };
  }

  private statement(): Node {
    if (this.isWord('let')) {
      this.index++;
      const name = this.identifier('变量名');
      this.expect('=');
      return { t: 'let', name: name, a: this.ternary() };
    }
    if (this.isWord('if')) {
      this.index++;
      const condition = this.ternary();
      const whenTrue = this.block();
      let whenFalse: Node | undefined = undefined;
      if (this.isWord('else')) {
        this.index++;
        whenFalse = this.isWord('if') ? this.statement() : this.block();
      }
      return { t: 'if', a: condition, b: whenTrue, c: whenFalse };
    }
    if (this.isWord('for')) {
      this.index++;
      const names = [this.identifier('循环变量')];
      if (this.take(',')) names.push(this.identifier('循环变量'));
      if (!this.isWord('in')) throw new NativeExprError(`for 语句缺少 in：位置 ${this.peek().pos}`);
      this.index++;
      const source = this.ternary();
      return { t: 'for', params: names, a: source, b: this.block() };
    }
    if (this.isWord('while')) {
      this.index++;
      const condition = this.ternary();
      return { t: 'while', a: condition, b: this.block() };
    }
    if (this.isWord('return')) {
      this.index++;
      const next = this.peek();
      if (next.nl || next.kind === 'end' || this.isOp('}') || this.isOp(';')) return { t: 'return' };
      return { t: 'return', a: this.ternary() };
    }
    if (this.isWord('break') || this.isWord('continue')) {
      const word = this.peek().text;
      this.index++;
      return { t: word };
    }
    const target = this.ternary();
    if (this.take('=')) {
      if (target.t !== 'var' && target.t !== 'index' && target.t !== 'member') {
        throw new NativeExprError(`“=” 左边只能是变量、下标或字段：位置 ${this.peek().pos}`);
      }
      return { t: 'assign', a: target, b: this.ternary() };
    }
    return { t: 'expr', a: target };
  }

  parse(): Node {
    const node = this.ternary();
    if (this.peek().kind !== 'end') {
      throw new NativeExprError(`多余的内容 “${this.peek().text}”：位置 ${this.peek().pos}`);
    }
    return node;
  }

  private peek(offset: number = 0): Token {
    return this.tokens[Math.min(this.index + offset, this.tokens.length - 1)];
  }

  private isOp(text: string, offset: number = 0): boolean {
    const token = this.peek(offset);
    return token.kind === 'op' && token.text === text;
  }

  private take(text: string): boolean {
    if (!this.isOp(text)) return false;
    this.index++;
    return true;
  }

  private expect(text: string): void {
    if (!this.take(text)) {
      throw new NativeExprError(`此处应为 “${text}”，实际是 “${this.peek().text || '结尾'}”：位置 ${this.peek().pos}`);
    }
  }

  private ternary(): Node {
    const condition = this.binary(0);
    if (!this.take('?')) return condition;
    const whenTrue = this.ternary();
    this.expect(':');
    const whenFalse = this.ternary();
    return { t: 'cond', a: condition, b: whenTrue, c: whenFalse };
  }

  private static readonly LEVELS: string[][] = [
    ['??'], ['||'], ['&&'], ['|'], ['^'], ['&'], ['==', '!='], ['<', '>', '<=', '>='], ['<<', '>>', '>>>'],
    ['+', '-'], ['*', '/', '%']
  ];

  private binary(level: number): Node {
    if (level >= Parser.LEVELS.length) return this.unary();
    let left = this.binary(level + 1);
    while (true) {
      const token = this.peek();
      if (token.kind !== 'op' || Parser.LEVELS[level].indexOf(token.text) < 0) return left;
      this.index++;
      left = { t: 'bin', op: token.text, a: left, b: this.binary(level + 1) };
    }
  }

  private unary(): Node {
    if (this.take('!')) return { t: 'not', a: this.unary() };
    if (this.take('-')) return { t: 'neg', a: this.unary() };
    if (this.take('~')) return { t: 'bitnot', a: this.unary() };
    return this.postfix();
  }

  private postfix(): Node {
    let node = this.primary();
    while (true) {
      if (this.take('.')) {
        const name = this.peek();
        if (name.kind !== 'id' && name.kind !== 'num') {
          throw new NativeExprError(`“.” 后应为字段名：位置 ${name.pos}`);
        }
        this.index++;
        node = { t: 'member', a: node, name: name.text };
      } else if (this.isOp('[') && !this.peek().nl) {
        this.index++;
        const key = this.ternary();
        this.expect(']');
        node = { t: 'index', a: node, b: key };
      } else if (this.isOp('(') && node.t === 'var' && !this.peek().nl) {
        this.index++;
        const args: Node[] = [];
        while (!this.isOp(')')) {
          args.push(this.ternary());
          if (!this.take(',')) break;
        }
        this.expect(')');
        node = { t: 'call', name: node.name, args: args };
      } else {
        return node;
      }
    }
  }

  private lambdaParams(): string[] | null {
    // (a, b) => …
    let offset = 1;
    const names: string[] = [];
    while (true) {
      const token = this.peek(offset);
      if (token.kind === 'op' && token.text === ')') break;
      if (token.kind !== 'id') return null;
      names.push(token.text);
      offset++;
      if (this.isOp(',', offset)) {
        offset++;
        continue;
      }
      if (!this.isOp(')', offset)) return null;
    }
    if (!this.isOp('=>', offset + 1)) return null;
    this.index += offset + 2;
    return names;
  }

  private primary(): Node {
    const token = this.peek();
    if (token.kind === 'num' || token.kind === 'str') {
      this.index++;
      return { t: 'lit', v: token.value };
    }
    if (token.kind === 'path') {
      this.index++;
      return { t: 'path', v: token.text };
    }
    if (token.kind === 'id') {
      if (this.isOp('=>', 1)) {
        this.index += 2;
        return { t: 'lambda', params: [token.text], a: this.ternary() };
      }
      this.index++;
      if (token.text === 'true') return { t: 'lit', v: true };
      if (token.text === 'false') return { t: 'lit', v: false };
      if (token.text === 'null') return { t: 'lit', v: null };
      return { t: 'var', name: token.text };
    }
    if (this.isOp('(')) {
      const params = this.lambdaParams();
      if (params) return { t: 'lambda', params: params, a: this.ternary() };
      this.index++;
      const inner = this.ternary();
      this.expect(')');
      return inner;
    }
    if (this.take('[')) {
      const items: Node[] = [];
      while (!this.isOp(']')) {
        items.push(this.ternary());
        if (!this.take(',')) break;
      }
      this.expect(']');
      return { t: 'list', args: items };
    }
    if (this.take('{')) {
      const keys: Node[] = [];
      const values: Node[] = [];
      while (!this.isOp('}')) {
        const key = this.peek();
        if (key.kind === 'id' || key.kind === 'str' || key.kind === 'num') {
          this.index++;
          keys.push({ t: 'lit', v: key.text });
        } else if (this.take('[')) {
          keys.push(this.ternary());
          this.expect(']');
        } else {
          throw new NativeExprError(`对象的键写法不正确：位置 ${key.pos}`);
        }
        this.expect(':');
        values.push(this.ternary());
        if (!this.take(',')) break;
      }
      this.expect('}');
      return { t: 'map', keys: keys, args: values };
    }
    throw new NativeExprError(`此处缺少表达式，实际是 “${token.text || '结尾'}”：位置 ${token.pos}`);
  }
}

// 内置函数名：函数库里的定义不能与之重名。新增内置函数时同步补到这里。
const BUILTIN_NAMES = ['str', 'num', 'int', 'bool', 'typeOf', 'len', 'trim', 'lower', 'upper', 'default', 'coalesce',
  'replace', 'replaceText', 'match', 'matchAll', 'test', 'split', 'lines', 'join', 'compact', 'unique', 'first', 'last',
  'slice', 'reverse', 'concat', 'contains', 'startsWith', 'endsWith', 'indexOf', 'substring', 'padStart', 'urlencode',
  'urldecode', 'base64', 'unbase64', 'hex', 'unhex', 'md5', 'sha1', 'sha256', 'sha512', 'json', 'tojson', 'keys',
  'values', 'entries', 'get', 'lookup', 'map', 'flatMap', 'filter', 'find', 'range', 'sum', 'min', 'max', 'abs', 'round', 'floor',
  'ceil', 'now', 'formatDate', 'stripHtml', 'htmlDecode', 'absUrl', 'sel', 'selAll', 'u32', 'imul', 'pow', 'toHex',
  'parseHex', 'charCode', 'fromCharCode', 'bytes', 'fromBytes', 'hexBytes', 'bytesHex', 'base64Bytes', 'bytesBase64',
  'list', 'push', 'hash', 'hmac', 'encrypt', 'decrypt', 'rsaEncrypt', 'cookie'];

const astCache: Map<string, Node> = new Map();

function parseExpression(source: string): Node {
  const cached = astCache.get(source);
  if (cached) return cached;
  const node = new Parser(tokenize(source)).parse();
  if (astCache.size >= AST_CACHE_LIMIT) astCache.clear();
  astCache.set(source, node);
  return node;
}

function utf8Bytes(text: string): number[] {
  const bytes: number[] = [];
  const encoded = encodeURIComponent(text);
  for (let i = 0; i < encoded.length; i++) {
    if (encoded[i] === '%') {
      bytes.push(parseInt(encoded.substring(i + 1, i + 3), 16));
      i += 2;
    } else {
      bytes.push(encoded.charCodeAt(i));
    }
  }
  return bytes;
}

function utf8Text(bytes: number[]): string {
  let encoded = '';
  for (const byte of bytes) encoded += '%' + (byte < 16 ? '0' : '') + byte.toString(16);
  try {
    return decodeURIComponent(encoded);
  } catch (e) {
    let fallback = '';
    for (const byte of bytes) fallback += String.fromCharCode(byte);
    return fallback;
  }
}

const BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function base64Encode(bytes: number[]): string {
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out += BASE64[b0 >> 2] + BASE64[((b0 & 3) << 4) | (b1 >> 4)];
    out += bytes.length > i + 1 ? BASE64[((b1 & 15) << 2) | (b2 >> 6)] : '=';
    out += i + 2 < bytes.length ? BASE64[b2 & 63] : '=';
  }
  return out;
}

function base64Decode(text: string): number[] {
  const clean = text.replace(/-/g, '+').replace(/_/g, '/').replace(/[^A-Za-z0-9+/]/g, '');
  const bytes: number[] = [];
  for (let i = 0; i < clean.length; i += 4) {
    const c0 = BASE64.indexOf(clean[i]);
    const c1 = i + 1 < clean.length ? BASE64.indexOf(clean[i + 1]) : 0;
    const c2 = i + 2 < clean.length ? BASE64.indexOf(clean[i + 2]) : -1;
    const c3 = i + 3 < clean.length ? BASE64.indexOf(clean[i + 3]) : -1;
    bytes.push((c0 << 2) | (c1 >> 4));
    if (c2 >= 0) bytes.push(((c1 & 15) << 4) | (c2 >> 2));
    if (c3 >= 0) bytes.push(((c2 & 3) << 6) | c3);
  }
  return bytes;
}

const HTML_ENTITIES: Record<string, string> = {
  nbsp: ' ', lt: '<', gt: '>', amp: '&', quot: '"', apos: "'", ldquo: '“', rdquo: '”', lsquo: '‘', rsquo: '’',
  hellip: '…', mdash: '—', ndash: '–', middot: '·', emsp: ' ', ensp: ' '
};

function htmlDecode(text: string): string {
  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (all: string, body: string): string => {
    if (body[0] === '#') {
      const code = body[1] === 'x' || body[1] === 'X' ? parseInt(body.substring(2), 16) : parseInt(body.substring(1), 10);
      return isNaN(code) || code <= 0 || code > 0x10ffff ? all : String.fromCodePoint(code);
    }
    const mapped = HTML_ENTITIES[body.toLowerCase()];
    return mapped === undefined ? all : mapped;
  });
}

function stripHtml(text: string): string {
  const withBreaks = text
    .replace(/<(script|style)\b[\s\S]*?<\/\1>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|h[1-6]|li|tr|section|article)>/gi, '\n')
    .replace(/<[^>]+>/g, '');
  return htmlDecode(withBreaks).replace(/\r\n?/g, '\n').replace(/\n{3,}/g, '\n\n');
}

function pad2(value: number): string {
  return value < 10 ? '0' + value : String(value);
}

function formatDate(input: NativeValue, pattern: string): string {
  if (input === null || input === undefined || input === '' || input === 0) return '';
  let time = typeof input === 'number' ? input : Number(input);
  if (isNaN(time)) {
    time = Date.parse(String(input));
    if (isNaN(time)) return '';
  } else if (Math.abs(time) < 100000000000) {
    time *= 1000; // 秒级时间戳
  }
  const date = new Date(time);
  if (isNaN(date.getTime())) return '';
  return pattern
    .replace(/yyyy/g, String(date.getFullYear()))
    .replace(/MM/g, pad2(date.getMonth() + 1))
    .replace(/dd/g, pad2(date.getDate()))
    .replace(/HH/g, pad2(date.getHours()))
    .replace(/mm/g, pad2(date.getMinutes()))
    .replace(/ss/g, pad2(date.getSeconds()));
}

export class NativeExpr {
  private host: NativeExprHost;
  private steps: number = 0;
  private depth: number = 0;
  private library: Map<string, FunctionDecl> = new Map();

  constructor(host: NativeExprHost) {
    this.host = host;
  }

  /** 语法检查函数库，返回错误信息；通过时返回空串。 */
  static checkLibrary(source: string): string {
    try {
      NativeExpr.parseLibrary(source);
      return '';
    } catch (e) {
      return (e as Error).message || '函数库语法错误';
    }
  }

  private static parseLibrary(source: string): FunctionDecl[] {
    const functions = new Parser(tokenize(source || '')).parseLibrary();
    const seen: Set<string> = new Set();
    for (const fn of functions) {
      if (BUILTIN_NAMES.indexOf(fn.name) >= 0) throw new NativeExprError(`函数名 “${fn.name}” 与内置函数重名`);
      if (seen.has(fn.name)) throw new NativeExprError(`函数 “${fn.name}” 重复定义`);
      seen.add(fn.name);
    }
    return functions;
  }

  /** 载入书源的函数库，之后的表达式可以直接调用其中的函数。 */
  loadLibrary(source: string | undefined): NativeExpr {
    this.library = new Map();
    if (!source || !source.trim()) return this;
    for (const fn of NativeExpr.parseLibrary(source)) this.library.set(fn.name, fn);
    return this;
  }

  /** 语法检查，返回错误信息；通过时返回空串。 */
  static check(source: string): string {
    try {
      parseExpression(source);
      return '';
    } catch (e) {
      return (e as Error).message || '表达式语法错误';
    }
  }

  /** 检查模板里每个 {{ }} 的语法。 */
  static checkTemplate(template: string): string {
    try {
      for (const part of NativeExpr.splitTemplate(template)) {
        if (part.expr) parseExpression(part.text);
      }
      return '';
    } catch (e) {
      return (e as Error).message || '模板语法错误';
    }
  }

  static isTruthy(value: NativeValue): boolean {
    if (value === null || value === undefined || value === false || value === 0 || value === '') return false;
    if (typeof value === 'number' && isNaN(value)) return false;
    if (Array.isArray(value)) return value.length > 0;
    return true;
  }

  static toText(value: NativeValue): string {
    if (value === null || value === undefined) return '';
    if (typeof value === 'string') return value;
    if (typeof value === 'number') return isNaN(value) ? '' : String(value);
    if (typeof value === 'boolean') return value ? 'true' : 'false';
    if (value instanceof Lambda) return '';
    try {
      return JSON.stringify(value);
    } catch (e) {
      return '';
    }
  }

  static toNumber(value: NativeValue): number {
    if (typeof value === 'number') return value;
    if (typeof value === 'boolean') return value ? 1 : 0;
    if (value === null || value === undefined || value === '') return 0;
    const parsed = Number(String(value).trim());
    return isNaN(parsed) ? 0 : parsed;
  }

  evaluate(source: string, scope: NativeScope): NativeValue {
    this.steps = 0;
    this.depth = 0;
    return this.run(parseExpression(source), scope);
  }

  private callFunction(fn: FunctionDecl, args: NativeValue[]): NativeValue {
    if (this.depth >= MAX_CALL_DEPTH) throw new NativeExprError(`函数 “${fn.name}” 调用层数过深`);
    // 函数只看得到自己的参数，读不到书源变量和当前响应，保证它是纯计算。
    const scope = new NativeScope();
    for (let i = 0; i < fn.params.length; i++) scope.set(fn.params[i], i < args.length ? args[i] : null);
    this.depth++;
    try {
      const signal = this.execute(fn.body, scope);
      return signal && signal.kind === 'return' ? signal.value : null;
    } finally {
      this.depth--;
    }
  }

  private execute(node: Node, scope: NativeScope): Signal | null {
    this.tick();
    switch (node.t) {
      case 'block': {
        const inner = scope.child();
        for (const statement of node.args as Node[]) {
          const signal = this.execute(statement, inner);
          if (signal) return signal;
        }
        return null;
      }
      case 'let':
        scope.set(node.name as string, this.run(node.a as Node, scope));
        return null;
      case 'assign':
        this.assign(node.a as Node, this.run(node.b as Node, scope), scope);
        return null;
      case 'if':
        if (NativeExpr.isTruthy(this.run(node.a as Node, scope))) return this.execute(node.b as Node, scope);
        return node.c ? this.execute(node.c, scope) : null;
      case 'for': {
        const source = this.run(node.a as Node, scope);
        const names = node.params as string[];
        const isMap = source !== null && typeof source === 'object' && !Array.isArray(source);
        const items: NativeValue[] = isMap ? Object.keys(source) : this.asList(source);
        for (let i = 0; i < items.length; i++) {
          const inner = scope.child().set(names[0], items[i]);
          if (names.length > 1) inner.set(names[1], isMap ? source[items[i]] : i);
          const signal = this.execute(node.b as Node, inner);
          if (signal && signal.kind === 'break') break;
          if (signal && signal.kind === 'return') return signal;
        }
        return null;
      }
      case 'while':
        while (NativeExpr.isTruthy(this.run(node.a as Node, scope))) {
          const signal = this.execute(node.b as Node, scope);
          if (signal && signal.kind === 'break') break;
          if (signal && signal.kind === 'return') return signal;
        }
        return null;
      case 'return':
        return new Signal('return', node.a ? this.run(node.a, scope) : null);
      case 'break':
        return new Signal('break');
      case 'continue':
        return new Signal('continue');
      default:
        this.run(node.a as Node, scope);
        return null;
    }
  }

  private assign(target: Node, value: NativeValue, scope: NativeScope): void {
    if (target.t === 'var') {
      if (!scope.assign(target.name as string, value)) {
        throw new NativeExprError(`变量 “${target.name}” 还没有用 let 声明`);
      }
      return;
    }
    const container = this.run(target.a as Node, scope);
    const key: NativeValue = target.t === 'member' ? target.name : this.run(target.b as Node, scope);
    if (Array.isArray(container)) {
      const index = Number(key);
      if (!Number.isInteger(index) || index < 0 || index > container.length || index >= MAX_LIST) {
        throw new NativeExprError(`列表下标越界：${NativeExpr.toText(key)}`);
      }
      container[index] = value;
      return;
    }
    if (container && typeof container === 'object' && !(container instanceof Lambda)) {
      const name = NativeExpr.toText(key);
      if (name === '__proto__' || name === 'constructor' || name === 'prototype') {
        throw new NativeExprError(`不能使用键名 “${name}”`);
      }
      (container as Record<string, NativeValue>)[name] = value;
      return;
    }
    throw new NativeExprError('只能给列表元素或对象字段赋值');
  }

  /** 渲染带 {{ 表达式 }} 的模板。 */
  render(template: string, scope: NativeScope): string {
    if (template.indexOf('{{') < 0) return template;
    let out = '';
    for (const part of NativeExpr.splitTemplate(template)) {
      out += part.expr ? NativeExpr.toText(this.evaluate(part.text, scope)) : part.text;
    }
    return out;
  }

  private static splitTemplate(template: string): Array<{ expr: boolean, text: string }> {
    const parts: Array<{ expr: boolean, text: string }> = [];
    let cursor = 0;
    while (cursor < template.length) {
      const open = template.indexOf('{{', cursor);
      if (open < 0) break;
      // 按花括号层数找结束的 }}：表达式里的对象字面量 {{ {a: 1}}} 取到最后一组，
      // 模板外的 JSON {"p":{{page}}} 则在 page 后结束，多出的 } 原样输出。
      let close = -1;
      let quote = '';
      let depth = 0;
      for (let i = open + 2; i < template.length; i++) {
        const ch = template[i];
        if (quote) {
          if (ch === '\\') i++;
          else if (ch === quote) quote = '';
        } else if (ch === '"' || ch === "'") {
          quote = ch;
        } else if (ch === '{') {
          depth++;
        } else if (ch === '}') {
          if (depth > 0) {
            depth--;
          } else if (template[i + 1] === '}') {
            close = i;
            break;
          }
        }
      }
      if (close < 0) throw new NativeExprError('模板里的 {{ 没有对应的 }}');
      if (open > cursor) parts.push({ expr: false, text: template.substring(cursor, open) });
      parts.push({ expr: true, text: template.substring(open + 2, close) });
      cursor = close + 2;
    }
    if (cursor < template.length) parts.push({ expr: false, text: template.substring(cursor) });
    return parts;
  }

  private tick(): void {
    if (++this.steps > MAX_STEPS) throw new NativeExprError('表达式计算量超出上限');
  }

  private run(node: Node, scope: NativeScope): NativeValue {
    this.tick();
    switch (node.t) {
      case 'lit':
        return node.v;
      case 'var': {
        const name = node.name as string;
        if (!scope.has(name)) throw new NativeExprError(`未定义的名称 “${name}”`);
        return scope.get(name);
      }
      case 'path':
        return this.readPath(scope.get('item'), node.v as string);
      case 'member':
        return this.member(this.run(node.a as Node, scope), node.name as string);
      case 'index': {
        const target = this.run(node.a as Node, scope);
        const key = this.run(node.b as Node, scope);
        return this.member(target, typeof key === 'number' ? key : NativeExpr.toText(key));
      }
      case 'not':
        return !NativeExpr.isTruthy(this.run(node.a as Node, scope));
      case 'neg':
        return -NativeExpr.toNumber(this.run(node.a as Node, scope));
      case 'bitnot':
        return ~NativeExpr.toNumber(this.run(node.a as Node, scope));
      case 'cond':
        return NativeExpr.isTruthy(this.run(node.a as Node, scope)) ?
          this.run(node.b as Node, scope) : this.run(node.c as Node, scope);
      case 'bin':
        return this.binary(node, scope);
      case 'list': {
        const items = node.args as Node[];
        return items.map((item: Node): NativeValue => this.run(item, scope));
      }
      case 'map': {
        const result: Record<string, NativeValue> = {};
        const keys = node.keys as Node[];
        const values = node.args as Node[];
        for (let i = 0; i < keys.length; i++) {
          result[NativeExpr.toText(this.run(keys[i], scope))] = this.run(values[i], scope);
        }
        return result;
      }
      case 'lambda':
        return new Lambda(node.params as string[], node.a as Node, scope);
      case 'call':
        return this.call(node.name as string, node.args as Node[], scope);
      default:
        throw new NativeExprError('无法求值的表达式');
    }
  }

  private readPath(item: NativeValue, path: string): NativeValue {
    let root: NativeValue = item;
    if (typeof root === 'string') {
      const text = root.trim();
      if (!text || (text[0] !== '{' && text[0] !== '[')) return null;
      try {
        root = JSON.parse(text);
      } catch (e) {
        return null;
      }
    }
    if (root === null || root === undefined) return null;
    if (path === '$') return root;
    const matches = this.host.jsonPath(root, path);
    const multiple = /\*|\.\.|\?|:|,/.test(path);
    if (multiple) return matches;
    return matches.length > 0 ? matches[0] : null;
  }

  private member(target: NativeValue, key: string | number): NativeValue {
    if (target === null || target === undefined) return null;
    if (typeof target === 'string') {
      if (key === 'length') return target.length;
      const index = Number(key);
      return isNaN(index) ? null : (target[index < 0 ? target.length + index : index] ?? null);
    }
    if (Array.isArray(target)) {
      if (key === 'length') return target.length;
      const index = Number(key);
      if (isNaN(index)) return null;
      const value = target[index < 0 ? target.length + index : index];
      return value === undefined ? null : value;
    }
    if (typeof target === 'object' && !(target instanceof Lambda)) {
      const name = String(key);
      if (!Object.prototype.hasOwnProperty.call(target, name)) return null;
      const value = (target as Record<string, NativeValue>)[name];
      return value === undefined ? null : value;
    }
    return null;
  }

  private binary(node: Node, scope: NativeScope): NativeValue {
    const op = node.op as string;
    const left = this.run(node.a as Node, scope);
    if (op === '&&') return NativeExpr.isTruthy(left) ? this.run(node.b as Node, scope) : left;
    if (op === '||') return NativeExpr.isTruthy(left) ? left : this.run(node.b as Node, scope);
    if (op === '??') return left === null || left === undefined ? this.run(node.b as Node, scope) : left;
    const right = this.run(node.b as Node, scope);
    switch (op) {
      case '+':
        if (typeof left === 'number' && typeof right === 'number') return left + right;
        if (Array.isArray(left) && Array.isArray(right)) return this.limitList(left.concat(right));
        return this.limitText(NativeExpr.toText(left) + NativeExpr.toText(right));
      case '-':
        return NativeExpr.toNumber(left) - NativeExpr.toNumber(right);
      case '*':
        return NativeExpr.toNumber(left) * NativeExpr.toNumber(right);
      case '/': {
        const divisor = NativeExpr.toNumber(right);
        return divisor === 0 ? 0 : NativeExpr.toNumber(left) / divisor;
      }
      case '%': {
        const divisor = NativeExpr.toNumber(right);
        return divisor === 0 ? 0 : NativeExpr.toNumber(left) % divisor;
      }
      case '==':
        return this.equals(left, right);
      case '!=':
        return !this.equals(left, right);
      case '&':
        return NativeExpr.toNumber(left) & NativeExpr.toNumber(right);
      case '|':
        return NativeExpr.toNumber(left) | NativeExpr.toNumber(right);
      case '^':
        return NativeExpr.toNumber(left) ^ NativeExpr.toNumber(right);
      case '<<':
        return NativeExpr.toNumber(left) << NativeExpr.toNumber(right);
      case '>>':
        return NativeExpr.toNumber(left) >> NativeExpr.toNumber(right);
      case '>>>':
        return NativeExpr.toNumber(left) >>> NativeExpr.toNumber(right);
      default: {
        const bothText = typeof left === 'string' && typeof right === 'string' &&
          (isNaN(Number(left)) || isNaN(Number(right)));
        const a: NativeValue = bothText ? left : NativeExpr.toNumber(left);
        const b: NativeValue = bothText ? right : NativeExpr.toNumber(right);
        if (op === '<') return a < b;
        if (op === '>') return a > b;
        if (op === '<=') return a <= b;
        return a >= b;
      }
    }
  }

  private equals(left: NativeValue, right: NativeValue): boolean {
    const a = left === undefined ? null : left;
    const b = right === undefined ? null : right;
    if (a === b) return true;
    if (a === null || b === null) return false;
    if (typeof a === 'object' || typeof b === 'object') return NativeExpr.toText(a) === NativeExpr.toText(b);
    // 数字与数字字符串视为相等，接口里 "3" 和 3 混用很常见。
    return NativeExpr.toText(a) === NativeExpr.toText(b);
  }

  private limitText(text: string): string {
    if (text.length > MAX_STRING) throw new NativeExprError('表达式生成的文本过大');
    return text;
  }

  private limitList(list: NativeValue[]): NativeValue[] {
    if (list.length > MAX_LIST) throw new NativeExprError('表达式生成的列表过大');
    return list;
  }

  private apply(fn: NativeValue, args: NativeValue[], name: string): NativeValue {
    if (!(fn instanceof Lambda)) throw new NativeExprError(`${name} 需要一个 x => … 形式的参数`);
    const scope = fn.scope.child();
    for (let i = 0; i < fn.params.length; i++) scope.set(fn.params[i], i < args.length ? args[i] : null);
    return this.run(fn.body, scope);
  }

  private regex(pattern: NativeValue, flags: string): RegExp {
    const text = NativeExpr.toText(pattern);
    try {
      return new RegExp(text, flags);
    } catch (e) {
      throw new NativeExprError(`正则写法不正确：${text}`);
    }
  }

  private asList(value: NativeValue): NativeValue[] {
    if (Array.isArray(value)) return value;
    if (value === null || value === undefined || value === '') return [];
    return [value];
  }

  private byteList(value: NativeValue): number[] {
    if (Array.isArray(value)) return value.map((item: NativeValue): number => NativeExpr.toNumber(item) & 255);
    return utf8Bytes(NativeExpr.toText(value));
  }

  private crypto(name: string, args: NativeValue[]): NativeValue {
    if (!this.host.crypto) throw new NativeExprError(`当前环境不支持 ${name}`);
    return this.host.crypto(name, args);
  }

  private call(name: string, argNodes: Node[], scope: NativeScope): NativeValue {
    const args = argNodes.map((arg: Node): NativeValue => this.run(arg, scope));
    const userFunction = this.library.get(name);
    if (userFunction) return this.callFunction(userFunction, args);
    const text = (index: number): string => NativeExpr.toText(args[index]);
    const num = (index: number, fallback: number = 0): number =>
      index < args.length && args[index] !== null && args[index] !== undefined ? NativeExpr.toNumber(args[index]) : fallback;
    switch (name) {
      case 'str':
        return text(0);
      case 'num':
        return num(0);
      case 'int': {
        const parsed = parseInt(text(0), 10);
        return isNaN(parsed) ? num(1) : parsed;
      }
      case 'bool':
        return NativeExpr.isTruthy(args[0]);
      case 'typeOf': {
        const value = args[0];
        if (value === null || value === undefined) return 'null';
        if (Array.isArray(value)) return 'list';
        return typeof value === 'object' ? 'map' : typeof value;
      }
      case 'len': {
        const value = args[0];
        if (value === null || value === undefined) return 0;
        if (typeof value === 'string' || Array.isArray(value)) return value.length;
        return typeof value === 'object' ? Object.keys(value).length : NativeExpr.toText(value).length;
      }
      case 'trim':
        return text(0).trim();
      case 'lower':
        return text(0).toLowerCase();
      case 'upper':
        return text(0).toUpperCase();
      case 'default':
      case 'coalesce':
        for (const arg of args) {
          if (NativeExpr.isTruthy(arg)) return arg;
        }
        return args.length > 0 ? args[args.length - 1] : null;
      case 'replace': {
        const flags = args.length > 3 ? text(3) : 'g';
        const re = this.regex(args[1], flags);
        const replacement = args[2];
        if (replacement instanceof Lambda) {
          return this.limitText(text(0).replace(re, (...found: NativeValue[]): string => {
            const groups: string[] = [];
            for (const part of found) {
              if (typeof part === 'number') break;
              groups.push(typeof part === 'string' ? part : '');
            }
            return NativeExpr.toText(this.apply(replacement, [groups], 'replace'));
          }));
        }
        return this.limitText(text(0).replace(re, NativeExpr.toText(replacement)));
      }
      case 'replaceText':
        return this.limitText(text(0).split(text(1)).join(text(2)));
      case 'match': {
        const found = this.regex(args[1], args.length > 3 ? text(3) : '').exec(text(0));
        if (!found) return '';
        const group = found[num(2)];
        return group === undefined ? '' : group;
      }
      case 'matchAll': {
        const re = this.regex(args[1], 'g');
        const groupIndex = num(2);
        const results: string[] = [];
        const input = text(0);
        let found = re.exec(input);
        while (found && results.length < MAX_LIST) {
          this.tick();
          results.push(found[groupIndex] === undefined ? '' : found[groupIndex]);
          if (found[0] === '') re.lastIndex++;
          found = re.exec(input);
        }
        return results;
      }
      case 'test':
        return this.regex(args[1], args.length > 2 ? text(2) : '').test(text(0));
      case 'split':
        return this.limitList(text(0).split(text(1)));
      case 'lines':
        return text(0).split(/\r?\n/);
      case 'join':
        return this.limitText(this.asList(args[0]).map((item: NativeValue): string => NativeExpr.toText(item))
          .join(args.length > 1 ? text(1) : ''));
      case 'compact':
        return this.asList(args[0]).filter((item: NativeValue): boolean =>
          NativeExpr.isTruthy(typeof item === 'string' ? item.trim() : item));
      case 'unique': {
        const seen: Set<string> = new Set();
        return this.asList(args[0]).filter((item: NativeValue): boolean => {
          const key = NativeExpr.toText(item);
          if (seen.has(key)) return false;
          seen.add(key);
          return true;
        });
      }
      case 'first': {
        const list = this.asList(args[0]);
        return list.length > 0 ? list[0] : null;
      }
      case 'last': {
        const list = this.asList(args[0]);
        return list.length > 0 ? list[list.length - 1] : null;
      }
      case 'slice': {
        const end = args.length > 2 && args[2] !== null ? num(2) : undefined;
        if (typeof args[0] === 'string') return args[0].slice(num(1), end);
        return this.asList(args[0]).slice(num(1), end);
      }
      case 'reverse':
        return this.asList(args[0]).slice().reverse();
      case 'concat': {
        let merged: NativeValue[] = [];
        for (const arg of args) merged = merged.concat(this.asList(arg));
        return this.limitList(merged);
      }
      case 'contains':
        if (Array.isArray(args[0])) {
          return args[0].some((item: NativeValue): boolean => this.equals(item, args[1]));
        }
        return text(0).indexOf(text(1)) >= 0;
      case 'startsWith':
        return text(0).startsWith(text(1));
      case 'endsWith':
        return text(0).endsWith(text(1));
      case 'indexOf':
        if (Array.isArray(args[0])) {
          return args[0].findIndex((item: NativeValue): boolean => this.equals(item, args[1]));
        }
        return text(0).indexOf(text(1));
      case 'substring':
        return text(0).substring(num(1), args.length > 2 ? num(2) : undefined);
      case 'padStart':
        return text(0).padStart(Math.min(num(1), 1024), args.length > 2 ? text(2) : ' ');
      case 'urlencode':
        return encodeURIComponent(text(0));
      case 'urldecode':
        try {
          return decodeURIComponent(text(0).replace(/\+/g, ' '));
        } catch (e) {
          return text(0);
        }
      case 'base64':
        return base64Encode(utf8Bytes(text(0)));
      case 'unbase64':
        return utf8Text(base64Decode(text(0)));
      case 'hex':
        return utf8Bytes(text(0)).map((byte: number): string => (byte < 16 ? '0' : '') + byte.toString(16)).join('');
      case 'unhex': {
        const clean = text(0).replace(/[^0-9a-f]/gi, '');
        const bytes: number[] = [];
        for (let i = 0; i + 1 < clean.length; i += 2) bytes.push(parseInt(clean.substring(i, i + 2), 16));
        return utf8Text(bytes);
      }
      case 'md5':
        return this.host.digest('MD5', text(0));
      case 'sha1':
        return this.host.digest('SHA1', text(0));
      case 'sha256':
        return this.host.digest('SHA256', text(0));
      case 'sha512':
        return this.host.digest('SHA512', text(0));
      case 'json':
        if (typeof args[0] !== 'string') return args[0] === undefined ? null : args[0];
        try {
          return JSON.parse(args[0]);
        } catch (e) {
          return null;
        }
      case 'tojson':
        return NativeExpr.toText(typeof args[0] === 'string' ? JSON.stringify(args[0]) : args[0]);
      case 'keys':
        return args[0] && typeof args[0] === 'object' && !Array.isArray(args[0]) ? Object.keys(args[0]) : [];
      case 'values':
        return args[0] && typeof args[0] === 'object' && !Array.isArray(args[0]) ?
          Object.keys(args[0]).map((key: string): NativeValue => args[0][key]) : [];
      case 'entries':
        return args[0] && typeof args[0] === 'object' && !Array.isArray(args[0]) ?
          Object.keys(args[0]).map((key: string): NativeValue => ({ key: key, value: args[0][key] })) : [];
      case 'get':
      case 'lookup': {
        const value = this.member(args[0], typeof args[1] === 'number' ? args[1] : text(1));
        return value === null && args.length > 2 ? args[2] : value;
      }
      case 'map':
        return this.asList(args[0]).map((item: NativeValue, index: number): NativeValue =>
          this.apply(args[1], [item, index], 'map'));
      case 'flatMap': {
        let flattened: NativeValue[] = [];
        const source = this.asList(args[0]);
        for (let i = 0; i < source.length; i++) {
          flattened = flattened.concat(this.asList(this.apply(args[1], [source[i], i], 'flatMap')));
          this.limitList(flattened);
        }
        return flattened;
      }
      case 'filter':
        return this.asList(args[0]).filter((item: NativeValue, index: number): boolean =>
          NativeExpr.isTruthy(this.apply(args[1], [item, index], 'filter')));
      case 'find': {
        const list = this.asList(args[0]);
        for (let i = 0; i < list.length; i++) {
          if (NativeExpr.isTruthy(this.apply(args[1], [list[i], i], 'find'))) return list[i];
        }
        return null;
      }
      case 'u32':
        return num(0) >>> 0;
      case 'imul':
        return Math.imul(num(0), num(1));
      case 'pow':
        return Math.pow(num(0), num(1));
      case 'toHex': {
        const value = Math.floor(num(0));
        return (value >= 0 ? value : value >>> 0).toString(16).padStart(Math.min(num(1), 64), '0');
      }
      case 'parseHex': {
        const parsed = parseInt(text(0), 16);
        return isNaN(parsed) ? 0 : parsed;
      }
      case 'charCode': {
        const code = text(0).charCodeAt(num(1));
        return isNaN(code) ? 0 : code;
      }
      case 'fromCharCode':
        return String.fromCharCode(...(Array.isArray(args[0]) ? args[0] : args).map((item: NativeValue): number =>
          NativeExpr.toNumber(item)));
      case 'bytes':
        return this.limitList(utf8Bytes(text(0)));
      case 'fromBytes':
        return utf8Text(this.byteList(args[0]));
      case 'hexBytes': {
        const clean = text(0).replace(/[^0-9a-f]/gi, '');
        const bytes: number[] = [];
        for (let i = 0; i + 1 < clean.length; i += 2) bytes.push(parseInt(clean.substring(i, i + 2), 16));
        return this.limitList(bytes);
      }
      case 'bytesHex':
        return this.byteList(args[0]).map((byte: number): string => (byte < 16 ? '0' : '') + byte.toString(16)).join('');
      case 'base64Bytes':
        return this.limitList(base64Decode(text(0)));
      case 'bytesBase64':
        return base64Encode(this.byteList(args[0]));
      case 'list': {
        const size = Math.max(0, Math.min(Math.floor(num(0)), MAX_LIST));
        const filled: NativeValue[] = [];
        for (let i = 0; i < size; i++) filled.push(args.length > 1 ? args[1] : 0);
        return filled;
      }
      case 'push': {
        if (!Array.isArray(args[0])) throw new NativeExprError('push 的第一个参数必须是列表');
        for (let i = 1; i < args.length; i++) args[0].push(args[i]);
        this.limitList(args[0]);
        return args[0];
      }
      case 'hash':
        return this.crypto('hash', [text(0), this.byteList(args[1])]);
      case 'hmac':
        return this.crypto('hmac', [text(0), this.byteList(args[1]), this.byteList(args[2])]);
      case 'encrypt':
      case 'decrypt':
        return this.crypto(name, [text(0), this.byteList(args[1]), this.byteList(args[2]),
          args.length > 3 && args[3] !== null ? this.byteList(args[3]) : []]);
      case 'rsaEncrypt':
        return this.crypto('rsaEncrypt', [this.byteList(args[0]), text(1), args.length > 2 ? text(2) : 'PKCS1']);
      case 'cookie':
        return this.host.cookie ? this.host.cookie(text(0), text(1)) : '';
      case 'range': {
        const count = Math.max(0, Math.min(Math.floor(num(0)), MAX_LIST));
        const result: number[] = [];
        for (let i = 0; i < count; i++) result.push(i);
        return result;
      }
      case 'sum':
        return this.asList(args[0]).reduce((total: number, item: NativeValue): number =>
          total + NativeExpr.toNumber(item), 0);
      case 'min':
        return Math.min(...(Array.isArray(args[0]) ? args[0] : args).map((item: NativeValue): number =>
          NativeExpr.toNumber(item)));
      case 'max':
        return Math.max(...(Array.isArray(args[0]) ? args[0] : args).map((item: NativeValue): number =>
          NativeExpr.toNumber(item)));
      case 'abs':
        return Math.abs(num(0));
      case 'round': {
        const scale = Math.pow(10, Math.max(0, Math.min(num(1), 10)));
        return Math.round(num(0) * scale) / scale;
      }
      case 'floor':
        return Math.floor(num(0));
      case 'ceil':
        return Math.ceil(num(0));
      case 'now':
        return Date.now();
      case 'formatDate':
        return formatDate(args[0], args.length > 1 ? text(1) : 'yyyy-MM-dd HH:mm');
      case 'stripHtml':
        return stripHtml(text(0));
      case 'htmlDecode':
        return htmlDecode(text(0));
      case 'absUrl':
        return NativeExpr.resolveUrl(text(0), args.length > 1 ? text(1) : NativeExpr.toText(scope.get('baseUrl')));
      case 'sel':
      case 'selAll': {
        const target = args.length > 1 ? args[1] : scope.get('item');
        const content = typeof target === 'string' ? target : NativeExpr.toText(target);
        const found = this.host.select(content, text(0), NativeExpr.toText(scope.get('baseUrl')), name === 'selAll');
        return name === 'selAll' ? found : (found.length > 0 ? found[0] : '');
      }
      default:
        throw new NativeExprError(`没有名为 “${name}” 的内置函数`);
    }
  }

  static resolveUrl(url: string, base: string): string {
    const value = url.trim();
    if (!value || /^[a-z][a-z0-9+.-]*:/i.test(value)) return value;
    const origin = /^([a-z][a-z0-9+.-]*:)\/\/([^/?#]+)/i.exec(base || '');
    if (!origin) return value;
    if (value.startsWith('//')) return origin[1] + value;
    if (value.startsWith('/')) return origin[0] + value;
    const path = (base || '').substring(origin[0].length).replace(/[?#][\s\S]*$/, '');
    if (value.startsWith('?') || value.startsWith('#')) return origin[0] + (path || '/') + value;
    const tailAt = value.search(/[?#]/);
    const tail = tailAt < 0 ? '' : value.substring(tailAt);
    const segments = path.substring(0, path.lastIndexOf('/') + 1).split('/').filter((part: string): boolean => !!part);
    for (const part of (tailAt < 0 ? value : value.substring(0, tailAt)).split('/')) {
      if (part === '.') continue;
      if (part === '..') segments.pop();
      else segments.push(part);
    }
    return origin[0] + '/' + segments.join('/') + tail;
  }
}
