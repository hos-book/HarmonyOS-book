/** EPUB 卷首常用 body 的 CSS 背景承载插图；转文字时将它保留为正文前的图片。
 * 仅解释 body 的简单标签/class/id 选择器，不执行 CSS、脚本或网络请求。
 */
class EpubBackgroundRule {
  path: string = '';
  specificity: number = -1;
  important: boolean = false;
}

export class EpubBackgroundImages {
  private styles: Map<string, string> = new Map();
  private styleChars: number = 0;

  static resolve(parentFile: string, relative: string): string {
    let value = relative.trim().replace(/&amp;/gi, '&');
    try { value = decodeURIComponent(value); } catch (_error) { return ''; }
    if (!value || /^(?:[a-z][a-z0-9+.-]*:|[\/\\])/i.test(value) || /[\u0000-\u001f\\]/.test(value)) return '';
    value = value.split('#')[0].split('?')[0];
    const parts = parentFile.split('/'); parts.pop();
    for (const part of value.split('/')) {
      if (part === '..') { if (parts.length === 0) return ''; parts.pop(); }
      else if (part && part !== '.') parts.push(part);
    }
    return parts.join('/');
  }

  static relative(parentFile: string, target: string): string {
    const from = parentFile.split('/'); from.pop();
    const to = target.split('/');
    while (from.length > 0 && to.length > 0 && from[0] === to[0]) { from.shift(); to.shift(); }
    return '../'.repeat(from.length) + to.join('/');
  }

  private static attr(tag: string, name: string): string {
    const match = new RegExp(`\\s${name}\\s*=\\s*["']([^"']*)["']`, 'i').exec(tag);
    return match === null ? '' : match[1];
  }

  private static specificity(selector: string, body: string): number {
    const simple = selector.trim();
    if (!/^(?:body)?(?:[.#][\w-]+)*$/i.test(simple) || !simple) return -1;
    const classes = EpubBackgroundImages.attr(body, 'class').split(/\s+/);
    const id = EpubBackgroundImages.attr(body, 'id');
    const pattern = /([.#])([\w-]+)/g;
    let match = pattern.exec(simple);
    let score = /^body/i.test(simple) ? 1 : 0;
    while (match !== null) {
      if (match[1] === '.' ? !classes.includes(match[2]) : id !== match[2]) return -1;
      score += match[1] === '.' ? 10 : 100;
      match = pattern.exec(simple);
    }
    return score;
  }

  private static apply(declarations: string, base: string, specificity: number, result: EpubBackgroundRule): void {
    for (const declaration of declarations.split(';')) {
      const property = /^\s*background(?:-image)?\s*:\s*([\s\S]*)$/i.exec(declaration);
      if (property === null) continue;
      const important = /!important\s*$/i.test(property[1]);
      if (result.important && !important) continue;
      if (important === result.important && specificity < result.specificity) continue;
      const url = /url\(\s*["']?([^"')]+)["']?\s*\)/i.exec(property[1]);
      result.path = url === null ? '' : EpubBackgroundImages.resolve(base, url[1]);
      result.specificity = specificity;
      result.important = important;
    }
  }

  private static rules(css: string, base: string, body: string, result: EpubBackgroundRule): void {
    const text = css.replace(/\/\*[\s\S]*?\*\//g, '');
    // 顶层规则；跳过 @media/@font-face 等嵌套块，避免误应用条件样式。
    let start = 0;
    while (start < text.length) {
      const open = text.indexOf('{', start);
      if (open < 0) break;
      let depth = 1; let end = open + 1;
      while (end < text.length && depth > 0) {
        if (text[end] === '{') depth++;
        if (text[end] === '}') depth--;
        end++;
      }
      const selector = text.substring(start, open).replace(/^\s*@charset[^;]*;\s*/i, '').trim();
      if (!selector.startsWith('@')) for (const part of selector.split(',')) {
        const score = EpubBackgroundImages.specificity(part, body);
        if (score >= 0) EpubBackgroundImages.apply(text.substring(open + 1, end - 1), base, score, result);
      }
      start = end;
    }
  }

  async expand(html: string, spine: string, read: (relative: string) => Promise<string>): Promise<string> {
    const body = /<body\b[^>]*>/i.exec(html);
    if (body === null) return html;
    const result = new EpubBackgroundRule();
    const styles = /<link\b[^>]*>|<style\b[^>]*>([\s\S]*?)<\/style\s*>/gi;
    let match = styles.exec(html.substring(0, body.index));
    while (match !== null) {
      if (match[1] !== undefined) EpubBackgroundImages.rules(match[1], spine, body[0], result);
      else if (EpubBackgroundImages.attr(match[0], 'rel').toLowerCase().split(/\s+/).includes('stylesheet')) {
        const path = EpubBackgroundImages.resolve(spine, EpubBackgroundImages.attr(match[0], 'href'));
        if (path) {
          let css = this.styles.get(path);
          if (css === undefined && this.styles.size < 128 && this.styleChars < 8 * 1024 * 1024) {
            try { css = await read(EpubBackgroundImages.relative(spine, path)); } catch (_error) { css = ''; }
            if (css.length > 512 * 1024) css = '';
            this.styleChars += css.length;
            this.styles.set(path, css);
          }
          if (css) EpubBackgroundImages.rules(css, path, body[0], result);
        }
      }
      match = styles.exec(html.substring(0, body.index));
    }
    EpubBackgroundImages.apply(EpubBackgroundImages.attr(body[0], 'style'), spine, 1000, result);
    if (!result.path) return html;
    const relative = EpubBackgroundImages.relative(spine, result.path).replace(/&/g, '&amp;').replace(/"/g, '&quot;');
    const offset = body.index + body[0].length;
    return html.substring(0, offset) + `<img src="${relative}"/>` + html.substring(offset);
  }
}
