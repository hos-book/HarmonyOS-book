import { common } from '@kit.AbilityKit';
import { DailyQuote } from '../model/DailyQuote';

/** 纯本地随机洗牌；一轮内不重复，轮次交界避免连续重复。 */
export class DailyQuoteService {
  private static poems: DailyQuote[] = [];
  private static cursor: number = 0;
  private static order: number[] = [];
  private static lastText: string = '';

  private static shuffle(): void {
    const order: number[] = [];
    for (let i = 0; i < DailyQuoteService.poems.length; i++) order.push(i);
    for (let i = order.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const saved = order[i];
      order[i] = order[j];
      order[j] = saved;
    }
    if (order.length > 1 && DailyQuoteService.poems[order[0]].text === DailyQuoteService.lastText) {
      const j = 1 + Math.floor(Math.random() * (order.length - 1));
      const saved = order[0];
      order[0] = order[j];
      order[j] = saved;
    }
    DailyQuoteService.order = order;
    DailyQuoteService.cursor = 0;
  }

  static next(context: common.Context): DailyQuote {
    if (DailyQuoteService.poems.length === 0) {
      const lines: string[] = [];
      const resourceIds: number[] = [
        $r('app.strarray.daily_quote_poems').id,
        $r('app.strarray.daily_quote_poems_2').id,
        $r('app.strarray.daily_quote_poems_3').id,
        $r('app.strarray.daily_quote_poems_4').id,
        $r('app.strarray.daily_quote_poems_5').id
      ];
      for (const resourceId of resourceIds) {
        lines.push(...context.resourceManager.getStringArrayValueSync(resourceId));
      }
      for (const line of lines) {
        const fields = line.split('|');
        if (fields.length !== 3 || fields.some((field: string): boolean => field.trim().length === 0)) continue;
        const quote = new DailyQuote();
        quote.text = fields[0];
        quote.author = fields[1];
        quote.source = fields[2];
        DailyQuoteService.poems.push(quote);
      }
    }
    if (DailyQuoteService.poems.length === 0) throw new Error('Missing bundled poems');
    if (DailyQuoteService.cursor >= DailyQuoteService.order.length) {
      DailyQuoteService.shuffle();
    }
    const selected = DailyQuoteService.poems[DailyQuoteService.order[DailyQuoteService.cursor++]];
    DailyQuoteService.lastText = selected.text;
    const result = new DailyQuote();
    result.text = selected.text;
    result.author = selected.author;
    result.source = selected.source;
    return result;
  }
}
