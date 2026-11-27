import { transformText } from 'libhsda_core.so';

/** 本地正文使用 Rust 扫描，沿用原有实体处理顺序与段落规则。 */
export class LocalBookHtmlText {
  static decodeEntities(text: string): string {
    return transformText(text, 1);
  }

  static clean(html: string): string {
    return transformText(html, 0);
  }
}
