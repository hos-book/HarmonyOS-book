import { EpubOriginalDocument } from './EpubOriginalDocument';
import { taskpool } from '@kit.ArkTS';
import { parseEpubMetadata } from './RustTextWorker';

class EpubXmlNativeAttribute {
  name: string = '';
  value: string = '';
}

class EpubXmlNativeNode {
  name: string = '';
  parent: number = 0;
  start: number = 0;
  end: number = 0;
  attributes: EpubXmlNativeAttribute[] = [];
}

class EpubXmlNativeDocument {
  text: string = '';
  nodes: EpubXmlNativeNode[] = [];
}

export class EpubXmlNode {
  name: string = '';
  private sharedText: string = '';
  private textStart: number = 0;
  private textEnd: number = 0;
  attributes: Map<string, string> = new Map();
  children: EpubXmlNode[] = [];

  constructor(sharedText: string = '', textStart: number = 0, textEnd: number = 0) {
    this.sharedText = sharedText;
    this.textStart = textStart;
    this.textEnd = textEnd;
  }

  get text(): string { return this.sharedText.substring(this.textStart, this.textEnd); }

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

/** Rust 扫描 EPUB 元数据与导航，节点共享正文及 UTF-16 区间。 */
export class EpubXml {
  static decode(value: string): string {
    return EpubOriginalDocument.decode(value.replace(/&lt;/gi, '<').replace(/&gt;/gi, '>').replace(/&nbsp;/gi, ' '));
  }

  static async parse(source: string): Promise<EpubXmlNode> {
    const parsed: EpubXmlNativeDocument = JSON.parse(String(await taskpool.execute(parseEpubMetadata, source)));
    const nodes: EpubXmlNode[] = [];
    for (const item of parsed.nodes) {
      const node = new EpubXmlNode(parsed.text, item.start, item.end);
      node.name = item.name;
      for (const attribute of item.attributes) node.attributes.set(attribute.name, attribute.value);
      if (nodes.length > 0) nodes[item.parent].children.push(node);
      nodes.push(node);
    }
    return nodes[0];
  }
}
