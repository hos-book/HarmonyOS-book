/** 本地电子书的 HTML 转文字：复用正则，合并标签扫描，不初始化排版引擎。 */
export class LocalBookHtmlText {
  static decodeEntities(text: string): string {
    if (!text.includes('&')) return text;
    return text.replace(/&nbsp;/gi, ' ').replace(/&amp;/gi, '&').replace(/&quot;/gi, '"')
      .replace(/&#39;|&apos;/gi, "'").replace(/&lt;/gi, '<').replace(/&gt;/gi, '>');
  }

  static clean(html: string): string {
    const body = /<body\b[^>]*>([\s\S]*?)<\/body\s*>/i.exec(html);
    let text = body ? body[1] : html;
    if (text.includes('<')) {
      text = text
        .replace(/<!--[\s\S]*?-->|<(head|script|style)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '')
        .replace(/<br\s*\/?>|<\/?(?:p|div|section|article|li|h[1-6])\b[^>]*>/gi, '\n')
        .replace(/<[^>]+>/g, '');
    }
    // 保留已有实体解码顺序；普通中文章节不需要反复扫描六种实体。
    text = LocalBookHtmlText.decodeEntities(text);
    return text.replace(/\r\n?/g, '\n').replace(/[\t ]+/g, ' ')
      .replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n').trim();
  }
}
