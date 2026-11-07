import { EpubOriginalDocument } from './EpubOriginalDocument';

export class EpubXmlNode {
  name: string = '';
  text: string = '';
  attributes: Map<string, string> = new Map();
  children: EpubXmlNode[] = [];

  attr(name: string): string { return this.attributes.get(name) ?? ''; }
  child(name: string): EpubXmlNode | undefined { return this.children.find((node: EpubXmlNode): boolean => node.name === name); }
  all(name: string): EpubXmlNode[] {
    const result: EpubXmlNode[] = [];
    const visit = (node: EpubXmlNode): void => {
      if (node.name === name) result.push(node);
      for (const child of node.children) visit(child);
    };
    visit(this);
    return result;
  }
}

/** EPUB 包元数据/导航的有界 XML 读取；不执行 DTD 或外部实体。 */
export class EpubXml {
  static decode(value: string): string {
    return EpubOriginalDocument.decode(value.replace(/&lt;/gi, '<').replace(/&gt;/gi, '>').replace(/&nbsp;/gi, ' '));
  }

  static parse(source: string): EpubXmlNode {
    if (source.length > 8 * 1024 * 1024) throw new Error('EPUB 元数据或目录过大');
    const root = new EpubXmlNode();
    const stack: EpubXmlNode[] = [root];
    const tokens = /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<!DOCTYPE[\s\S]*?(?:\]>|>)|<\/?[a-zA-Z][\w:.-]*(?:\s+(?:[^<>"']|"[^"]*"|'[^']*')*)?\s*\/?>|[^<]+/gi;
    let count = 0;
    let token = tokens.exec(source);
    while (token !== null) {
      const value = token[0];
      if (value.startsWith('<![CDATA[') || !value.startsWith('<')) {
        const text = value.startsWith('<![CDATA[') ? value.substring(9, value.length - 3) : EpubXml.decode(value);
        for (const node of stack) node.text += text;
      } else if (value.startsWith('</')) {
        const raw = /^<\/([\w:.-]+)/.exec(value)?.[1] ?? '';
        const name = raw.substring(raw.lastIndexOf(':') + 1).toLowerCase();
        const index = stack.map((node: EpubXmlNode): string => node.name).lastIndexOf(name);
        if (index > 0) stack.splice(index);
      } else if (!value.startsWith('<!') && !value.startsWith('<?')) {
        if (++count > 200000 || stack.length > 64) throw new Error('EPUB XML 结构过大');
        const node = new EpubXmlNode();
        const name = /^<([\w:.-]+)/.exec(value)?.[1] ?? '';
        node.name = name.substring(name.lastIndexOf(':') + 1).toLowerCase();
        const attributes = /([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
        let attr = attributes.exec(value);
        while (attr !== null) {
          node.attributes.set(attr[1], EpubXml.decode(attr[2] ?? attr[3] ?? ''));
          attr = attributes.exec(value);
        }
        stack[stack.length - 1].children.push(node);
        if (!/\/\s*>$/.test(value) && !['link', 'img', 'br', 'hr', 'input'].includes(node.name)) stack.push(node);
      }
      token = tokens.exec(source);
    }
    return root;
  }
}
