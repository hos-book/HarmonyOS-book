/** AI 回复以纯文本展示；保留引用编号及正文中的 #，兼容已有聊天记录。 */
export class JianjianReplyText {
  static display(value: string): string {
    const result: string[] = [];
    let codeFence = '';
    let proseFence = false;
    // 分隔符不依赖同一行内成对出现，兼容跨行、嵌套、转义和未闭合的加粗标记。
    const plain = value.replace(/(?:\\?\*){2,}/g, '');
    for (const line of plain.split('\n')) {
      const fence = line.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
      if (fence !== null) {
        if (!codeFence) {
          codeFence = fence[1];
          proseFence = ['', 'md', 'markdown', 'text', 'plaintext', 'txt'].includes(fence[2].trim().toLowerCase());
          continue;
        }
        if (fence[1][0] === codeFence[0] && fence[1].length >= codeFence.length && !fence[2].trim()) {
          codeFence = ''; continue;
        }
      }
      if (codeFence && !proseFence) { result.push(line); continue; }
      let text = line.replace(/^ {0,3}#{1,6}[ \t]+/, '');
      if (text !== line) text = text.replace(/[ \t]+#+[ \t]*$/, '');
      text = text.replace(/`([^`\n]+)`/g, '$1').replace(/__([^_\n]+)__/g, '$1');
      result.push(text);
    }
    return result.join('\n');
  }
}
