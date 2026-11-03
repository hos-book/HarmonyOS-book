export class ReaderDialogueRange {
  start: number;
  end: number;
  constructor(start: number, end: number) { this.start = start; this.end = end; }
}

/** 只识别成对引号；以整章计算范围，分页和逐行显示不会丢失引号状态。 */
export class ReaderDialogueHighlighter {
  static ranges(text: string): ReaderDialogueRange[] {
    const result: ReaderDialogueRange[] = [];
    let start: number = -1;
    let closing: string = '';
    for (let index = 0; index < text.length; index++) {
      const char: string = text.charAt(index);
      if (start >= 0) {
        if (char === closing) {
          result.push(new ReaderDialogueRange(start, index + 1));
          start = -1;
          closing = '';
        } else if (char === '\n') {
          // 缺失闭引号不染色后续叙述段落。
          start = -1;
          closing = '';
        }
      } else if (char === '“' || char === '「' || char === '『' || char === '"') {
        start = index;
        closing = char === '“' ? '”' : char === '「' ? '」' : char === '『' ? '』' : '"';
      }
    }
    return result;
  }
}
