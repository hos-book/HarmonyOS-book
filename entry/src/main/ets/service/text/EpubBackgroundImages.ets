import { EpubPageStyle } from './EpubPageStyle';

class EpubCssValue {
  value: string = '';
  base: string = '';
  specificity: number = -1;
  important: boolean = false;
}

class EpubCssDeclaration {
  property: string;
  value: string;
  important: boolean;
  constructor(property: string, value: string, important: boolean) {
    this.property = property; this.value = value; this.important = important;
  }
}

class EpubCssSelector {
  tag: string = '';
  ids: string[] = [];
  classes: string[] = [];
  specificity: number = 0;
}

class EpubCssElement {
  tag: string = '';
  id: string = '';
  classes: string[] = [];
}

class EpubCssRule {
  selectors: EpubCssSelector[] = [];
  declarations: EpubCssDeclaration[] = [];
}

/** 静态提取 body/html 与标题的背景和前景属性。 */
export class EpubBackgroundImages {
  private styles: Map<string, EpubCssRule[]> = new Map();
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

  private static element(tag: string): EpubCssElement {
    const result = new EpubCssElement();
    result.tag = /^<([a-z][a-z0-9]*)(?:\s|>)/i.exec(tag)?.[1].toLowerCase() ?? '';
    result.id = EpubBackgroundImages.attr(tag, 'id');
    result.classes = EpubBackgroundImages.attr(tag, 'class').split(/\s+/);
    return result;
  }

  private static selector(value: string): EpubCssSelector | null {
    const simple = value.trim();
    if (!/^(?:[a-z][a-z0-9]*|\*)?(?:[.#][\w-]+)*$/i.test(simple) || !simple) return null;
    const result = new EpubCssSelector();
    result.tag = /^[a-z][a-z0-9]*/i.exec(simple)?.[0].toLowerCase() ?? '';
    result.specificity = result.tag ? 1 : 0;
    const pattern = /([.#])([\w-]+)/g;
    let match = pattern.exec(simple);
    while (match !== null) {
      if (match[1] === '.') result.classes.push(match[2]);
      else result.ids.push(match[2]);
      result.specificity += match[1] === '.' ? 10 : 100;
      match = pattern.exec(simple);
    }
    return result;
  }

  private static matches(selector: EpubCssSelector, element: EpubCssElement): boolean {
    if (selector.tag && selector.tag !== element.tag) return false;
    for (const id of selector.ids) if (id !== element.id) return false;
    for (const name of selector.classes) if (!element.classes.includes(name)) return false;
    return true;
  }

  private static put(result: Map<string, EpubCssValue>, property: string, value: string, base: string,
    specificity: number, important: boolean): void {
    const previous = result.get(property);
    if (previous && (previous.important && !important || previous.important === important && specificity < previous.specificity)) return;
    const next = new EpubCssValue();
    next.value = value; next.base = base; next.specificity = specificity; next.important = important;
    result.set(property, next);
  }

  private static declarations(text: string): EpubCssDeclaration[] {
    const result: EpubCssDeclaration[] = [];
    for (const declaration of text.split(';')) {
      const property = /^\s*(background(?:-image|-color|-size|-repeat|-position)?|color)\s*:\s*([\s\S]*)$/i.exec(declaration);
      if (!property) continue;
      const name = property[1].toLowerCase();
      const important = /!important\s*$/i.test(property[2]);
      const value = property[2].replace(/!important\s*$/i, '').trim();
      if (name !== 'background') {
        result.push(new EpubCssDeclaration(name, value, important));
        continue;
      }
      const image = /url\(\s*["']?[^"')]+["']?\s*\)/i.exec(value);
      const rest = value.replace(/url\([^)]*\)/gi, '').toLowerCase();
      const size = /\/\s*(cover|contain|auto)\b/.exec(rest);
      const repeat = /\b(no-repeat|repeat-x|repeat-y|repeat)\b/.exec(rest);
      const color = /#[0-9a-f]{3,8}\b|rgb\([^)]*\)|\b(?:white|black|transparent)\b/i.exec(rest);
      const position = rest.split('/')[0].match(/\b(?:left|right|top|bottom|center)\b|(?:0|50|100)%/g);
      result.push(new EpubCssDeclaration('background-image', image ? image[0] : 'none', important));
      result.push(new EpubCssDeclaration('background-size', size ? size[1] : 'auto', important));
      result.push(new EpubCssDeclaration('background-repeat', repeat ? repeat[1] : 'repeat', important));
      result.push(new EpubCssDeclaration('background-color', color ? color[0] : 'transparent', important));
      result.push(new EpubCssDeclaration('background-position', position ? position.join(' ') : 'top left', important));
    }
    return result;
  }

  private static apply(declarations: EpubCssDeclaration[], base: string, specificity: number,
    result: Map<string, EpubCssValue>): void {
    for (const declaration of declarations) {
      EpubBackgroundImages.put(result, declaration.property, declaration.value, base, specificity, declaration.important);
    }
  }

  private static parse(css: string): EpubCssRule[] {
    const rules: EpubCssRule[] = [];
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
      if (!selector.startsWith('@')) {
        const rule = new EpubCssRule();
        for (const part of selector.split(',')) {
          const parsed = EpubBackgroundImages.selector(part);
          if (parsed) rule.selectors.push(parsed);
        }
        if (rule.selectors.length > 0) {
          rule.declarations = EpubBackgroundImages.declarations(text.substring(open + 1, end - 1));
          rules.push(rule);
        }
      }
      start = end;
    }
    return rules;
  }

  private static rules(rules: EpubCssRule[], base: string, element: EpubCssElement,
    result: Map<string, EpubCssValue>): void {
    for (const rule of rules) for (const selector of rule.selectors) {
      if (EpubBackgroundImages.matches(selector, element)) {
        EpubBackgroundImages.apply(rule.declarations, base, selector.specificity, result);
      }
    }
  }

  private cacheStyles(path: string, css: string): void {
    if (this.styles.has(path) || this.styles.size >= 128 || this.styleChars >= 8 * 1024 * 1024) return;
    const text = css.length <= 512 * 1024 ? css : '';
    this.styleChars += text.length;
    this.styles.set(path, EpubBackgroundImages.parse(text));
  }

  async inspect(html: string, spine: string, read: (relative: string) => Promise<string>): Promise<EpubPageStyle> {
    const body = /<body\b[^>]*>/i.exec(html);
    if (!body) return new EpubPageStyle();
    const root = /<html\b[^>]*>/i.exec(html);
    const heading = /<h[1-6]\b[^>]*>/i.exec(html.substring(body.index));
    const bodyElement = EpubBackgroundImages.element(body[0]);
    const rootElement = root ? EpubBackgroundImages.element(root[0]) : null;
    const headingElement = heading ? EpubBackgroundImages.element(heading[0]) : null;
    const bodyRules: Map<string, EpubCssValue> = new Map();
    const rootRules: Map<string, EpubCssValue> = new Map();
    const headingRules: Map<string, EpubCssValue> = new Map();
    const styles = /<link\b[^>]*>|<style\b[^>]*>([\s\S]*?)<\/style\s*>/gi;
    const head = html.substring(0, body.index);
    let match = styles.exec(head);
    while (match) {
      let rules: EpubCssRule[] = [];
      let base = spine;
      if (match[1] !== undefined) rules = EpubBackgroundImages.parse(match[1]);
      else if (EpubBackgroundImages.attr(match[0], 'rel').toLowerCase().split(/\s+/).includes('stylesheet')) {
        base = EpubBackgroundImages.resolve(spine, EpubBackgroundImages.attr(match[0], 'href'));
        if (base) {
          if (!this.styles.has(base) && this.styles.size < 128 && this.styleChars < 8 * 1024 * 1024) {
            let css = '';
            try { css = await read(EpubBackgroundImages.relative(spine, base)); } catch (_error) {}
            this.cacheStyles(base, css);
          }
          rules = this.styles.get(base) ?? [];
        }
      }
      EpubBackgroundImages.rules(rules, base, bodyElement, bodyRules);
      if (rootElement) EpubBackgroundImages.rules(rules, base, rootElement, rootRules);
      if (headingElement) EpubBackgroundImages.rules(rules, base, headingElement, headingRules);
      match = styles.exec(head);
    }
    EpubBackgroundImages.apply(EpubBackgroundImages.declarations(EpubBackgroundImages.attr(body[0], 'style')), spine, 1000, bodyRules);
    if (root) EpubBackgroundImages.apply(EpubBackgroundImages.declarations(EpubBackgroundImages.attr(root[0], 'style')), spine, 1000, rootRules);
    if (heading) EpubBackgroundImages.apply(EpubBackgroundImages.declarations(EpubBackgroundImages.attr(heading[0], 'style')), spine, 1000, headingRules);
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
