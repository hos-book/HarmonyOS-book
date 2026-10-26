/** 展示真实元数据；未知状态、占位文本和热度/排名均不冒充评分。 */
export class BookMetadataPolicy {
  static text(value: string | undefined): string {
    const text = (value ?? '').trim();
    return /^(?:[-—–]+|暂无(?:数据|分类|评分|信息)?|未知(?:分类|状态)?|无|null|undefined)$/i.test(text) ? '' : text;
  }

  static rating(value: number | string | undefined, label: string = ''): number {
    const raw = String(value ?? '').trim();
    const number = BookMetadataPolicy.normalizeRating(raw);
    if (number > 0) return number;
    const text = BookMetadataPolicy.tagText(label);
    const match = /(?:评分|得分|rating|score)\s*[:：]?\s*(\d+(?:\.\d+)?(?:\s*(?:分|[%％]|\/\s*\d+))?)(?![\d.])/i.exec(text)
      ?? /(?:^|[\s|,，、;；/·•・●▪:：])(\d+(?:\.\d+)?\s*(?:分|[%％]|\/\s*(?:100|10)))(?:$|[\s|,，、;；/·•・●▪:：])/.exec(text);
    return BookMetadataPolicy.normalizeRating(match?.[1] ?? '');
  }

  /** 未标量程时沿用十分制，大于 10 且不超过 100 按百分制；显式 /100、% 始终换算。 */
  private static normalizeRating(raw: string): number {
    const match = /^(\d+(?:\.\d+)?)(?:\s*(分|[%％])|\s*\/\s*(100|10))?$/.exec(raw.trim());
    if (!match) return 0;
    const value = Number(match[1]);
    const maximum = match[3] ? Number(match[3]) : /[%％]/.test(match[2] ?? '') || value > 10 ? 100 : 10;
    if (!Number.isFinite(value) || value <= 0 || value > maximum) return 0;
    return maximum === 100 ? value / 10 : value;
  }

  static completed(status: string): boolean | undefined {
    const value = BookMetadataPolicy.text(status);
    if (/连载|更新中|未完结|未完本|ongoing|serializing/i.test(value)) return false;
    if (/完结|完本|已完成|completed|finished/i.test(value)) return true;
    return undefined;
  }

  static categories(value: string): string[] {
    const categories: string[] = [];
    // 参照轻页按空白、冒号和标点拆标签；日期须先处理，避免拆出时间碎片。
    const text = BookMetadataPolicy.tagText(value).replace(
      /(?:最后更新|更新时间|更新于|更新)?\s*[:：]?\s*\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}(?:日)?(?:[ T]\d{1,2}[:：]\d{1,2}(?:[:：]\d{1,2})?)?/g, ' ');
    for (const raw of text.split(/[\s|,，、;；/·•・●▪:：]+/)) {
      const label = BookMetadataPolicy.text(raw);
      if (!label || /^(?:audio|text|comic|import)$/i.test(label)
        || /^(?:已完结|完结|完本|已完成|连载|连载中|更新中|completed|finished|ongoing)$/i.test(label)
        || /^(?:评分|得分|rating|score|分)$/i.test(label)
        || /^\d+(?:\.\d+)?(?:亿|万|千)?(?:字|章|章节)$/.test(label)
        || /^(?:(?:评分|得分|rating|score)\s*[:：]?\s*)?\d+(?:\.\d+)?\s*(?:分|[%％])?$/i.test(label)) continue;
      if (!categories.includes(label)) categories.push(label);
    }
    return categories;
  }

  private static tagText(value: string): string {
    return value.replace(/<[^>]+>/g, ' ')
      .replace(/&(?:nbsp|ensp|emsp|thinsp);|&#(?:160|x0*a0);/gi, ' ')
      .replace(/&middot;/gi, '·');
  }
}
