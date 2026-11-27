import { taskpool } from '@kit.ArkTS';
import { scanReaderText } from './RustTextWorker';

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

/** 逐章读取，后台扫描；结果以 UTF-16 位置交给现有阅读器。 */
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
        const offsets: number[] = JSON.parse(String(await taskpool.execute(scanReaderText, content, keyword,
          ReaderFullTextSearch.MAX_RESULTS - progress.matches.length)));
        if (cancelled()) return;
        for (const offset of offsets) {
          progress.matches.push(new ReaderSearchMatch(index, offset,
            content.substring(Math.max(0, offset - 28), Math.min(content.length, offset + keyword.length + 60))
              .replace(/\s+/g, ' ')));
        }
        if (progress.matches.length >= ReaderFullTextSearch.MAX_RESULTS) {
          progress.limited = true;
          update(progress);
          return;
        }
      } catch (_error) { progress.failed++; }
      if (cancelled()) return;
      progress.completed = index + 1;
      update(progress);
    }
  }
}
