import { ReaderDialogueRules } from '../../model/ReaderDialogueRules';

export class ReaderDialogueRange {
  start: number;
  end: number;
  constructor(start: number, end: number) { this.start = start; this.end = end; }
}

/** 只识别成对引号；以整章计算范围，分页和逐行显示不会丢失引号状态。 */
export class ReaderDialogueHighlighter {
  static ranges(text: string, quotePairs: string = ReaderDialogueRules.DEFAULT): ReaderDialogueRange[] {
    const result: ReaderDialogueRange[] = [];
    const pairs = ReaderDialogueRules.normalize(quotePairs).split('\n').filter((pair: string): boolean => pair.length === 2);
    if (pairs.length === 0) return result;
    const closings: Map<string, string> = new Map();
    for (const pair of pairs) closings.set(pair.charAt(0), pair.charAt(1));
    let start: number = -1;
    let closing: string = '';
    for (let index = 0; index < text.length; index++) {
      const char: string = text.charAt(index);
      if (start >= 0) {
        if (char === closing) {
          result.push(new ReaderDialogueRange(start, index + 1));
          start = -1;
          closing = '';
        }
      } else if (closings.has(char)) {
        start = index;
        closing = closings.get(char) ?? '';
      }
    }
    return result;
  }
}
