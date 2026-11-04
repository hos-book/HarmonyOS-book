export class ReaderSearchMatch {
  chapterIndex: number;
  offset: number;
  preview: string;

  constructor(chapterIndex: number, offset: number, preview: string) {
    this.chapterIndex = chapterIndex;
    this.offset = offset;
    this.preview = preview;
  }
}

export class ReaderSearchProgress {
  matches: ReaderSearchMatch[] = [];
  completed: number = 0;
  failed: number = 0;
  limited: boolean = false;
}

/** 逐章扫描、分段让出 UI；关闭面板/再次搜索后不再发起后续读取。 */
export class ReaderFullTextSearch {
  static readonly MAX_RESULTS: number = 500;

  static async search(query: string, chapterCount: number,
    read: (index: number) => Promise<string>, cancelled: () => boolean,
    update: (progress: ReaderSearchProgress) => void): Promise<void> {
    const keyword = query.trim();
    const progress = new ReaderSearchProgress();
    if (!keyword) { update(progress); return; }
    for (let index = 0; index < chapterCount && !cancelled(); index++) {
      try {
        const content = await read(index);
        if (cancelled()) return;
        for (let start = 0; start < content.length; start += 16384) {
          const end = Math.min(content.length, start + 16384);
          // 含跨分段边界匹配，但每个命中仅由其起始段收集。
          const segment = content.substring(start, Math.min(content.length, end + keyword.length - 1));
          let found = segment.indexOf(keyword);
          while (found >= 0 && start + found < end) {
            const offset = start + found;
            progress.matches.push(new ReaderSearchMatch(index, offset,
              content.substring(Math.max(0, offset - 28), Math.min(content.length, offset + keyword.length + 60))
                .replace(/\s+/g, ' ')));
            if (progress.matches.length >= ReaderFullTextSearch.MAX_RESULTS) {
              progress.limited = true;
              update(progress);
              return;
            }
            found = segment.indexOf(keyword, found + 1);
          }
          await new Promise<void>((resolve): void => { setTimeout(resolve, 0); });
          if (cancelled()) return;
        }
      } catch (_error) { progress.failed++; }
      if (cancelled()) return;
      progress.completed = index + 1;
      update(progress);
    }
  }
}
