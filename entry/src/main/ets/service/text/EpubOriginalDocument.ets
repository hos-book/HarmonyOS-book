/** 原书片段与现有 TXT 章节共享字符坐标，不重新生成章节身份。 */
export class EpubOriginalPart {
  spine: number = 0;
  href: string = '';
  start: number = 0;
  end: number = 0;
  offset: number = 0;
  length: number = 0;

  constructor(spine: number = 0, href: string = '', start: number = 0, end: number = 0) {
    this.spine = spine; this.href = href; this.start = start; this.end = end;
  }
}

export class EpubOriginalInjection {
  style: string = '';
  script: string = '';
}

/** 单个字节范围用于本地媒体起播和 seek，不把整段视频重复读入内存。 */
export class EpubOriginalRange {
  start: number = 0;
  end: number = 0;
  size: number = 0;
  partial: boolean = false;
  valid: boolean = true;

  constructor(size: number, header: string = '') {
    this.size = size; this.end = size - 1;
    if (!header) return;
    this.partial = true;
    const match = /^bytes=(\d*)-(\d*)$/i.exec(header.trim());
    if (!match || (!match[1] && !match[2])) { this.valid = false; return; }
    if (!match[1]) {
      const suffix = Number(match[2]);
      if (!Number.isSafeInteger(suffix) || suffix <= 0) { this.valid = false; return; }
      this.start = Math.max(0, size - suffix);
    } else {
      this.start = Number(match[1]);
      if (match[2]) this.end = Math.min(size - 1, Number(match[2]));
    }
    this.valid = Number.isSafeInteger(this.start) && Number.isSafeInteger(this.end) &&
      this.start >= 0 && this.start < size && this.end >= this.start;
  }
}

/** 只调整资源地址与阅读视口；字体、颜色、背景和元素样式来自原书。 */
export class EpubOriginalDocument {
  static readonly ORIGIN: string = 'https://epub.hsda.invalid/';
  private static readonly VOID: string[] = ['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'];

  static decode(value: string): string {
    return value.replace(/&amp;/gi, '&').replace(/&quot;/gi, '"').replace(/&apos;|&#39;/gi, "'")
      .replace(/&#(?:x([0-9a-f]+)|(\d+));/gi, (_all: string, hex: string, dec: string): string => {
        const code = parseInt(hex || dec, hex ? 16 : 10);
        return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : '';
      });
  }

  static resolve(from: string, value: string): string {
    let raw = EpubOriginalDocument.decode(value.trim()).split(/[?#]/)[0];
    if (!raw || /^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(raw)) return '';
    try { raw = decodeURIComponent(raw); } catch (_error) { return ''; }
    if (/[\u0000-\u001f\\]/.test(raw)) return '';
    const parts: string[] = raw.startsWith('/') ? [] : from.split('/').slice(0, -1);
    for (const part of raw.split('/')) {
      if (part === '..') { if (parts.length === 0) return ''; parts.pop(); }
      else if (part && part !== '.') parts.push(part);
    }
    return parts.join('/');
  }

  static url(path: string): string {
    return EpubOriginalDocument.ORIGIN + 'assets/' + EpubOriginalDocument.assetPath(path);
  }

  /** EPUB ZIP 条目允许冒号、星号等字符；编码落盘同时兼容设备和桌面导入验证。 */
  static assetPath(path: string): string {
    return path.split('/').map((part: string): string => encodeURIComponent(part)
      .replace(/[!'()*]/g, (value: string): string => '%' + value.charCodeAt(0).toString(16).toUpperCase())).join('/');
  }

  static path(url: string): string {
    const prefix = EpubOriginalDocument.ORIGIN + 'assets/';
    if (!url.startsWith(prefix)) return '';
    const raw = url.substring(prefix.length).split(/[?#]/)[0];
    try {
      const decoded = decodeURIComponent(raw);
      if (decoded.split('/').some((part: string): boolean => part === '..' || part === '.') ||
        /[\u0000-\u001f\\]/.test(decoded) || decoded.startsWith('/')) return '';
      return decoded;
    } catch (_error) { return ''; }
  }

  static mime(path: string): string {
    const ext = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
    switch (ext) {
      case 'css': return 'text/css';
      case 'svg': return 'image/svg+xml';
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'avif': return 'image/avif';
      case 'bmp': return 'image/bmp';
      case 'ttf': return 'font/ttf';
      case 'otf': return 'font/otf';
      case 'woff': return 'font/woff';
      case 'woff2': return 'font/woff2';
      case 'mp3': return 'audio/mpeg';
      case 'm4a': return 'audio/mp4';
      case 'aac': return 'audio/aac';
      case 'wav': return 'audio/wav';
      case 'ogg': case 'oga': return 'audio/ogg';
      case 'flac': return 'audio/flac';
      case 'mp4': case 'm4v': return 'video/mp4';
      case 'webm': return 'video/webm';
      case 'ogv': return 'video/ogg';
      case 'vtt': return 'text/vtt';
      default: return '';
    }
  }

  static dependencies(source: string, href: string, css: boolean): string[] {
    const result: Set<string> = new Set();
    const add = (value: string): void => {
      const path = EpubOriginalDocument.resolve(href, value);
      if (path && EpubOriginalDocument.mime(path)) result.add(path);
    };
    if (!css) {
      const attributes = /\s(?:src|href|xlink:href|poster)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi;
      let match = attributes.exec(source);
      while (match !== null) { add(match[1] ?? match[2] ?? match[3] ?? ''); match = attributes.exec(source); }
    }
    const urls = /url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)|@import\s+["']([^"']+)["']/gi;
    let url = urls.exec(source);
    while (url !== null) { add(url[1] ?? url[2] ?? url[3] ?? url[4] ?? ''); url = urls.exec(source); }
    return Array.from(result);
  }

  private static address(value: string, href: string): string {
    const raw = EpubOriginalDocument.decode(value);
    if (raw.startsWith('#') || /^data:(?:image|font|application\/(?:font|x-font))/i.test(raw)) return raw;
    const path = EpubOriginalDocument.resolve(href, raw);
    return path ? EpubOriginalDocument.url(path) + (raw.includes('#') ? raw.substring(raw.indexOf('#')) : '') : '';
  }

  static css(css: string, href: string): string {
    return css.replace(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)/gi,
      (_all: string, a: string, b: string, c: string): string =>
        `url("${EpubOriginalDocument.address((a ?? b ?? c ?? '').trim(), href).replace(/"/g, '%22')}")`)
      .replace(/(@import\s+)["']([^"']+)["']/gi, (_all: string, prefix: string, value: string): string =>
        `${prefix}"${EpubOriginalDocument.address(value, href).replace(/"/g, '%22')}"`);
  }

  static escape(value: string): string {
    return value.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  private static safe(html: string, href: string): string {
    let result = html.replace(/<(script|iframe|object|embed|form)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '')
      .replace(/<\/?(?:script|iframe|object|embed|form|base|meta)\b[^>]*>/gi, '')
      .replace(/\s(?:on[a-z]+|srcdoc|nonce|integrity)\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, '')
      .replace(/(\s(?:src|href|xlink:href|poster)\s*=\s*)(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi,
        (_all: string, prefix: string, a: string, b: string, c: string): string =>
          `${prefix}"${EpubOriginalDocument.escape(EpubOriginalDocument.address(a ?? b ?? c ?? '', href))}"`)
      .replace(/(\sstyle\s*=\s*)(?:"([^"]*)"|'([^']*)')/gi,
        (_all: string, prefix: string, a: string, b: string): string =>
          `${prefix}"${EpubOriginalDocument.escape(EpubOriginalDocument.css(EpubOriginalDocument.decode(a ?? b ?? ''), href))}"`)
      .replace(/<style\b[^>]*>([\s\S]*?)<\/style\s*>/gi,
        (_all: string, css: string): string => `<style>${EpubOriginalDocument.css(css, href)}</style>`);
    // XHTML 的空锚点不能吞掉后续内容；SVG 自闭合元素保持原样。
    result = result.replace(/<(a|div|span|p|section)\b([^<>]*?)\/>/gi,
      (_all: string, tag: string, attrs: string): string => `<${tag}${attrs}></${tag}>`);
    return result;
  }

  /** 按原目录的 HTML 偏移裁切，保留跨锚点的祖先标签和 class/style。 */
  static slice(html: string, start: number, end: number): string {
    const stack: string[] = [];
    const names: string[] = [];
    const tags = /<!--[\s\S]*?-->|<\/?([a-z][\w:-]*)\b[^>]*>/gi;
    const prefix = html.substring(0, start);
    let match = tags.exec(prefix);
    while (match !== null) {
      const name = (match[1] ?? '').toLowerCase();
      if (name && !EpubOriginalDocument.VOID.includes(name)) {
        if (match[0].startsWith('</')) {
          const index = names.lastIndexOf(name);
          if (index >= 0) { names.splice(index); stack.splice(index); }
        } else if (!match[0].endsWith('/>')) { names.push(name); stack.push(match[0]); }
      }
      match = tags.exec(prefix);
    }
    return stack.join('') + html.substring(start, end);
  }

  static build(source: string, part: EpubOriginalPart, script: string, nonce: string, layout: string = ''): string {
    const body = /<body\b([^>]*)>/i.exec(source);
    const html = /<html\b([^>]*)>/i.exec(source);
    const bodyStart = body ? body.index + body[0].length : 0;
    const close = source.search(/<\/body\s*>/i);
    const bodyEnd = close >= 0 ? close : source.length;
    const start = Math.max(bodyStart, part.start);
    const end = Math.min(bodyEnd, part.end);
    const content = EpubOriginalDocument.slice(source.substring(bodyStart, bodyEnd),
      Math.max(0, start - bodyStart), Math.max(0, end - bodyStart));
    const head = /<head\b[^>]*>([\s\S]*?)<\/head\s*>/i.exec(source)?.[1] ?? '';
    const styles = (head.match(/<style\b[^>]*>[\s\S]*?<\/style\s*>|<link\b[^>]*>/gi) ?? [])
      .filter((tag: string): boolean => /^<style/i.test(tag) || /\bstylesheet\b/i.test(tag)).join('');
    const csp = `default-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self' data:; ` +
      `media-src 'self'; script-src 'nonce-${nonce}'; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'`;
    return '<!DOCTYPE html><html' + EpubOriginalDocument.safe(html?.[1] ?? '', part.href) + '><head>' +
      '<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">' +
      `<meta http-equiv="Content-Security-Policy" content="${EpubOriginalDocument.escape(csp)}">` +
      EpubOriginalDocument.safe(styles, part.href) + `<style id="legado-layout">${layout}</style></head><body` +
      EpubOriginalDocument.safe(body?.[1] ?? '', part.href) + '>' + EpubOriginalDocument.safe(content, part.href) +
      `<script nonce="${nonce}">${script.replace(/<\/script/gi, '<\\/script')}</script></body></html>`;
  }

  /** 只允许同源章节框架，原书脚本与网络权限仍由每个章节的 CSP 隔离。 */
  static continuous(script: string, nonce: string): string {
    const csp = `default-src 'none'; frame-src 'self'; img-src 'self' data:; style-src 'unsafe-inline'; ` +
      `script-src 'nonce-${nonce}'; connect-src 'none'; base-uri 'none'; form-action 'none'`;
    return '<!DOCTYPE html><html><head><meta charset="utf-8">' +
      '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">' +
      `<meta http-equiv="Content-Security-Policy" content="${EpubOriginalDocument.escape(csp)}">` +
      '<style>html,body{margin:0;padding:0;overflow-anchor:none}section{position:relative}' +
      'iframe{display:block;position:sticky;top:0;width:100%;border:0}</style></head><body>' +
      `<script nonce="${nonce}">${script.replace(/<\/script/gi, '<\\/script')}</script></body></html>`;
  }
}
