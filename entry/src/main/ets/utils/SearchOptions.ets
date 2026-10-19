export class SearchOptions {
  static matchesSourceType(type: number | undefined, textOnly: boolean, audioOnly: boolean, comicOnly: boolean = false): boolean {
    if (!textOnly && !audioOnly && !comicOnly) return true;
    return (textOnly && (type === 0 || type === 3)) || (audioOnly && type === 1) || (comicOnly && type === 2);
  }

  static matchesContentType(type: 'audio' | 'text' | 'comic', textOnly: boolean, audioOnly: boolean, comicOnly: boolean = false): boolean {
    if (!textOnly && !audioOnly && !comicOnly) return true;
    return (textOnly && type === 'text') || (audioOnly && type === 'audio') || (comicOnly && type === 'comic');
  }

  static matches(name: string, author: string, keyword: string, exact: boolean, byAuthor: boolean): boolean {
    if (!exact && !byAuthor) return true;
    const value = (byAuthor ? author : name).trim().toLocaleLowerCase();
    const query = keyword.trim().toLocaleLowerCase();
    return exact ? value === query : value.includes(query);
  }

  // 输入按最新优先排列，只保留能连续排入两行的前缀。
  static visibleCount(widths: number[], available: number, gap: number): number {
    if (available <= 0) return widths.length;
    let row = 1;
    let used = 0;
    for (let i = 0; i < widths.length; i++) {
      const width = Math.min(widths[i], available);
      if (used > 0 && used + gap + width > available) {
        row++;
        used = 0;
      }
      if (row > 2) return i;
      used += (used > 0 ? gap : 0) + width;
    }
    return widths.length;
  }
}
