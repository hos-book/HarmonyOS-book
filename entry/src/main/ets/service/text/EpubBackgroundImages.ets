import { EpubPageStyle } from './EpubPageStyle';

class EpubCssValue {
  value: string = '';
  base: string = '';
  specificity: number = -1;
  important: boolean = false;
}

/** 提取 body/html 与标题背景；不执行书内 CSS、脚本或网络请求。 */
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
    const match = new RegExp('\\s' + name + '\\s*=\\s*["\']([^"\']*)["\']', 'i').exec(tag);
    return match === null ? '' : match[1];
  }

  private static specificity(selector: string, tag: string): number {
    const simple = selector.trim();
    if (!/^(?:[a-z][a-z0-9]*|\*)?(?:[.#][\w-]+)*$/i.test(simple) || !simple) return -1;
    const type = /^[a-z][a-z0-9]*/i.exec(simple);
    if (type && !new RegExp('^<' + type[0] + '(?:\\s|>)', 'i').test(tag)) return -1;
    const classes = EpubBackgroundImages.attr(tag, 'class').split(/\s+/);
    const id = EpubBackgroundImages.attr(tag, 'id');
    const pattern = /([.#])([\w-]+)/g;
    let match = pattern.exec(simple);
    let score = type ? 1 : 0;
    while (match !== null) {
      if (match[1] === '.' ? !classes.includes(match[2]) : id !== match[2]) return -1;
      score += match[1] === '.' ? 10 : 100;
      match = pattern.exec(simple);
    }
    return score;
  }

  private static put(result: Map<string, EpubCssValue>, property: string, value: string, base: string,
    specificity: number, important: boolean): void {
    const previous = result.get(property);
    if (previous && (previous.important && !important || previous.important === important && specificity < previous.specificity)) return;
    const next = new EpubCssValue();
    next.value = value; next.base = base; next.specificity = specificity; next.important = important;
    result.set(property, next);
  }

  private static apply(declarations: string, base: string, specificity: number, result: Map<string, EpubCssValue>): void {
    for (const declaration of declarations.split(';')) {
      const property = /^\s*(background(?:-image|-color|-size|-repeat|-position)?|color)\s*:\s*([\s\S]*)$/i.exec(declaration);
      if (!property) continue;
      const name = property[1].toLowerCase();
      const important = /!important\s*$/i.test(property[2]);
      const value = property[2].replace(/!important\s*$/i, '').trim();
      if (name !== 'background') {
        EpubBackgroundImages.put(result, name, value, base, specificity, important);
        continue;
      }
      // shorthand 重置背景属性，但不能覆盖更高优先级的 longhand。
      const image = /url\(\s*["']?[^"')]+["']?\s*\)/i.exec(value);
      const rest = value.replace(/url\([^)]*\)/gi, '').toLowerCase();
      const size = /\/\s*(cover|contain|auto)\b/.exec(rest);
      const repeat = /\b(no-repeat|repeat-x|repeat-y|repeat)\b/.exec(rest);
      const color = /#[0-9a-f]{3,8}\b|rgb\([^)]*\)|\b(?:white|black|transparent)\b/i.exec(rest);
      const position = rest.split('/')[0].match(/\b(?:left|right|top|bottom|center)\b|(?:0|50|100)%/g);
      EpubBackgroundImages.put(result, 'background-image', image ? image[0] : 'none', base, specificity, important);
      EpubBackgroundImages.put(result, 'background-size', size ? size[1] : 'auto', base, specificity, important);
      EpubBackgroundImages.put(result, 'background-repeat', repeat ? repeat[1] : 'repeat', base, specificity, important);
      EpubBackgroundImages.put(result, 'background-color', color ? color[0] : 'transparent', base, specificity, important);
      EpubBackgroundImages.put(result, 'background-position', position ? position.join(' ') : 'top left', base, specificity, important);
    }
  }

  private static rules(css: string, base: string, tag: string, result: Map<string, EpubCssValue>): void {
    const text = css.replace(/\/\*[\s\S]*?\*\//g, '');
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
      // 不猜测 @media 等条件，只应用可明确匹配的简单选择器。
      if (!selector.startsWith('@')) for (const part of selector.split(',')) {
        const score = EpubBackgroundImages.specificity(part, tag);
        if (score >= 0) EpubBackgroundImages.apply(text.substring(open + 1, end - 1), base, score, result);
      }
      start = end;
    }
  }

  async inspect(html: string, spine: string, read: (relative: string) => Promise<string>): Promise<EpubPageStyle> {
    const body = /<body\b[^>]*>/i.exec(html);
    if (!body) return new EpubPageStyle();
    const root = /<html\b[^>]*>/i.exec(html);
    const heading = /<h[1-6]\b[^>]*>/i.exec(html.substring(body.index));
    const bodyRules: Map<string, EpubCssValue> = new Map();
    const rootRules: Map<string, EpubCssValue> = new Map();
    const headingRules: Map<string, EpubCssValue> = new Map();
    const styles = /<link\b[^>]*>|<style\b[^>]*>([\s\S]*?)<\/style\s*>/gi;
    const head = html.substring(0, body.index);
    let match = styles.exec(head);
    while (match) {
      let css = match[1] ?? '';
      let base = spine;
      if (match[1] === undefined && EpubBackgroundImages.attr(match[0], 'rel').toLowerCase().split(/\s+/).includes('stylesheet')) {
        base = EpubBackgroundImages.resolve(spine, EpubBackgroundImages.attr(match[0], 'href'));
        if (base) {
          let cached = this.styles.get(base);
          if (cached === undefined && this.styles.size < 128 && this.styleChars < 8 * 1024 * 1024) {
            try { cached = await read(EpubBackgroundImages.relative(spine, base)); } catch (_error) { cached = ''; }
            if (cached.length > 512 * 1024) cached = '';
            this.styleChars += cached.length;
            this.styles.set(base, cached);
          }
          css = cached ?? '';
        }
      }
      if (css) {
        EpubBackgroundImages.rules(css, base, body[0], bodyRules);
        if (root) EpubBackgroundImages.rules(css, base, root[0], rootRules);
        if (heading) EpubBackgroundImages.rules(css, base, heading[0], headingRules);
      }
      match = styles.exec(head);
    }
    EpubBackgroundImages.apply(EpubBackgroundImages.attr(body[0], 'style'), spine, 1000, bodyRules);
    if (root) EpubBackgroundImages.apply(EpubBackgroundImages.attr(root[0], 'style'), spine, 1000, rootRules);
    if (heading) EpubBackgroundImages.apply(EpubBackgroundImages.attr(heading[0], 'style'), spine, 1000, headingRules);
    const result = EpubBackgroundImages.style(bodyRules);
    const rootStyle = EpubBackgroundImages.style(rootRules);
    if (!result.image && !result.color && (rootStyle.image || rootStyle.color)) {
      result.image = rootStyle.image; result.color = rootStyle.color; result.size = rootStyle.size;
      result.repeat = rootStyle.repeat; result.position = rootStyle.position;
    }
    result.foreground = result.foreground || rootStyle.foreground;
    result.headingColor = EpubPageStyle.color(headingRules.get('background-color')?.value ?? '');
    result.headingForeground = EpubPageStyle.color(headingRules.get('color')?.value ?? '');
    if (!result.visible()) { result.foreground = ''; result.headingForeground = ''; }
    return result;
  }

  private static style(rules: Map<string, EpubCssValue>): EpubPageStyle {
    const result = new EpubPageStyle();
    const image = rules.get('background-image');
    const url = /url\(\s*["']?([^"')]+)["']?\s*\)/i.exec(image?.value ?? '');
    if (image && url) result.image = EpubBackgroundImages.resolve(image.base, url[1]);
    result.color = EpubPageStyle.color(rules.get('background-color')?.value ?? '');
    result.foreground = EpubPageStyle.color(rules.get('color')?.value ?? '');
    const size = rules.get('background-size')?.value.toLowerCase() ?? '';
    if (size === 'cover' || size === 'contain') result.size = size;
    const repeat = rules.get('background-repeat')?.value.toLowerCase() ?? '';
    if (['no-repeat', 'repeat-x', 'repeat-y'].includes(repeat)) result.repeat = repeat;
    const position = rules.get('background-position');
    if (position) result.position = EpubPageStyle.position(position.value);
    return result;
  }

  /** 显式漫画模式将卷首背景作为一张漫画页；文字模式使用独立背景层。 */
  async expand(html: string, spine: string, read: (relative: string) => Promise<string>): Promise<string> {
    const style = await this.inspect(html, spine, read);
    const body = /<body\b[^>]*>/i.exec(html);
    if (!style.image || !body) return html;
    const relative = EpubBackgroundImages.relative(spine, style.image).replace(/&/g, '&amp;').replace(/"/g, '&quot;');
    const offset = body.index + body[0].length;
    return html.substring(0, offset) + '<img src="' + relative + '"/>' + html.substring(offset);
  }
}
