/** 展示真实元数据；未知状态、占位文本和热度/排名均不冒充评分。 */
export class BookMetadataPolicy {
  static text(value: string | undefined): string {
    const text = (value ?? '').trim();
    return /^(?:[-—–]+|暂无(?:数据|分类|评分|信息)?|未知(?:分类|状态)?|无|null|undefined)$/i.test(text) ? '' : text;
  }

  static rating(value: number | string | undefined, label: string = ''): number {
    const raw = String(value ?? '').trim();
    const number = /^\d+(?:\.\d+)?(?:\s*分)?$/.test(raw) ? Number(raw.replace(/\s*分$/, '')) : 0;
    if (Number.isFinite(number) && number > 0 && number <= 10) return number;
    const match = /(?:评分|得分|rating|score)\s*[:：]?\s*(\d+(?:\.\d+)?)(?![\d.])/i.exec(label)
      ?? /(?:^|[\s|,，、;；/])(\d+(?:\.\d+)?)\s*分(?:$|[\s|,，、;；/])/.exec(label);
    const parsed = Number(match?.[1] ?? 0);
    return Number.isFinite(parsed) && parsed > 0 && parsed <= 10 ? parsed : 0;
  }

  static completed(status: string): boolean | undefined {
    const value = BookMetadataPolicy.text(status);
    if (/连载|更新中|未完结|未完本|ongoing|serializing/i.test(value)) return false;
    if (/完结|完本|已完成|completed|finished/i.test(value)) return true;
    return undefined;
  }

  static categories(value: string): string[] {
    const categories: string[] = [];
    for (const raw of value.split(/[|,，、;；/\n]+/)) {
      const label = BookMetadataPolicy.text(raw);
      if (!label || /^(?:audio|text|comic|import)$/i.test(label)
        || /^(?:已完结|完结|完本|连载中?|更新中)\s*\d{4}[-/.年]\d{1,2}/.test(label)
        || /^(?:已完结|完结|完本|已完成|连载|连载中|更新中|completed|finished|ongoing)$/i.test(label)
        || /^(?:(?:评分|得分|rating|score)\s*[:：]?\s*)?\d+(?:\.\d+)?\s*分?$/i.test(label)) continue;
      if (!categories.includes(label)) categories.push(label);
    }
    return categories;
  }
}
