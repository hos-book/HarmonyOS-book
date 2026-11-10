/** 一行一对单字符符号；空字符串表示未选择任何范围。 */
export class ReaderDialogueRules {
  static readonly DEFAULT: string = '“”\n「」\n『』\n""';
  static readonly PRESETS: string[] = ['“”', '‘’', '「」', '『』', '""', "''", '【】', '《》'];
  static readonly MAX_PAIRS: number = 16;

  static validPair(pair: string): boolean {
    return pair.length === 2 && !/[\s\uD800-\uDFFF]/.test(pair);
  }

  static normalize(value?: string): string {
    if (typeof value !== 'string') return ReaderDialogueRules.DEFAULT;
    const pairs: string[] = [];
    const openings: Set<string> = new Set();
    for (const line of value.slice(0, 256).split('\n')) {
      const pair = line.trim();
      if (!ReaderDialogueRules.validPair(pair) || openings.has(pair.charAt(0))) continue;
      pairs.push(pair);
      openings.add(pair.charAt(0));
      if (pairs.length >= ReaderDialogueRules.MAX_PAIRS) break;
    }
    return pairs.join('\n');
  }
}
