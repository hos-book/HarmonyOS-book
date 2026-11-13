import { OnlineTextPage } from './OnlineTextPaginator';
import { PerformanceTrace } from '../../utils/PerformanceTrace';
import { ReaderDialogueRange } from './ReaderDialogueHighlighter';

/** 连续阅读的可见行；字符偏移沿用原始正文，键不依赖列表位置。 */
export class OnlineTextScrollRow {
  page: OnlineTextPage = new OnlineTextPage();
  key: string = '';
  chapterIndex: number = 0;
  startOffset: number = 0;
  endOffset: number = 0;
  text: string = '';
  source: string = '';
  heading: boolean = false;
  lineSourceOffsets: number[] = [];

  offsetAtY(y: number): number {
    let offset = this.startOffset;
    for (let index = 0; index < this.page.lineMetrics.length; index++) {
      const line = this.page.lineMetrics[index];
      const top = line.baseline - line.ascent - this.page.layoutTop + (this.page.lineShifts[index] ?? 0);
      if (top > y) break;
      offset = this.lineSourceOffsets[index] ?? this.startOffset;
    }
    return offset;
  }

  yForOffset(offset: number): number {
    let top = 0;
    for (let index = 0; index < this.page.lineMetrics.length; index++) {
      const line = this.page.lineMetrics[index];
      const start = this.lineSourceOffsets[index] ?? this.startOffset;
      if (start > offset) break;
      top = line.baseline - line.ascent - this.page.layoutTop + (this.page.lineShifts[index] ?? 0);
    }
    return Math.max(0, top);
  }
}

export class OnlineTextScrollChapter {
  layoutSignature: string = '';
  index: number = 0;
  content: string = '';
  rows: OnlineTextScrollRow[] = [];

  static create(index: number, key: string, title: string, content: string,
    lines: OnlineTextPage[]): OnlineTextScrollChapter {
    const chapter = new OnlineTextScrollChapter();
    chapter.index = index;
    chapter.content = content;
    for (const line of lines) {
      const previous = chapter.rows[chapter.rows.length - 1];
      // 连续模式按自然段复用同一个 Paragraph 选区，不能让每一行各自持有拖柄。
      if (previous !== undefined && !previous.heading && !line.isHeading && line.paragraph !== null &&
        previous.page.paragraph === line.paragraph && !previous.page.text.endsWith('\n')) {
        const page = previous.page;
        const shift = page.layoutHeight + page.trailingSpacing - (line.layoutTop - page.layoutTop);
        for (const value of line.lineShifts) page.lineShifts.push(value + shift);
        page.lineMetrics.push(...line.lineMetrics);
        page.commentLineExtra.push(...line.commentLineExtra);
        for (const range of line.dialogueRanges) {
          page.dialogueRanges.push(new ReaderDialogueRange(page.text.length + range.start, page.text.length + range.end));
        }
        page.text += line.text;
        page.layoutHeight += page.trailingSpacing + line.layoutHeight;
        page.trailingSpacing = line.trailingSpacing;
        page.endOffset = line.endOffset;
        previous.endOffset = line.endOffset;
        previous.lineSourceOffsets.push(line.startOffset);
        previous.text = page.text.replace(new RegExp('\\n$'), '');
        previous.source = content.substring(previous.startOffset, previous.endOffset);
        previous.key = `${key}:body:${page.firstLine}:${previous.startOffset}:${line.endOffset}:${page.layoutKey}`;
        continue;
      }
      const row = new OnlineTextScrollRow();
      row.page = line;
      row.heading = line.isHeading;
      row.key = `${key}:${line.isHeading ? 'heading' : 'body'}:${line.firstLine}:${line.startOffset}:${line.endOffset}:${line.layoutKey}`;
      row.chapterIndex = index;
      row.startOffset = line.startOffset;
      row.lineSourceOffsets = [line.startOffset];
      row.endOffset = line.endOffset;
      // 换行由相邻 ListItem 表达，不在每行末尾额外增加一个空行。
      row.text = line.text.replace(new RegExp('\\n$'), '');
      row.source = content.substring(line.startOffset, line.endOffset);
      chapter.rows.push(row);
    }
    return chapter;
  }
}

export class OnlineTextScrollDataSource implements IDataSource {
  private rows: OnlineTextScrollRow[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.rows.length; }
  getData(index: number): OnlineTextScrollRow { return this.rows[index]; }
  reset(rows: OnlineTextScrollRow[]): void {
    this.rows = rows.slice();
    // 同一 LazyForEach 的批量通知不能与旧的 onDataAdd/onDataReloaded 混用。
    const operation: DataOperation = { type: DataOperationType.RELOAD };
    this.notify(operation);
  }
  insert(index: number, rows: OnlineTextScrollRow[]): void {
    if (rows.length === 0) return;
    const position = Math.max(0, Math.min(index, this.rows.length));
    const trace = PerformanceTrace.begin('reader.scroll.insert');
    try {
      this.rows = this.rows.slice(0, position).concat(rows, this.rows.slice(position));
      const operation: DataOperation = { type: DataOperationType.ADD, index: position, count: rows.length };
      this.notify(operation);
    } finally {
      PerformanceTrace.end('reader.scroll.insert', trace);
    }
  }
  remove(index: number, count: number): void {
    const position = Math.max(0, Math.min(index, this.rows.length));
    const removed = Math.max(0, Math.min(count, this.rows.length - position));
    if (removed === 0) return;
    const trace = PerformanceTrace.begin('reader.scroll.remove');
    try {
      this.rows.splice(position, removed);
      const operation: DataOperation = { type: DataOperationType.DELETE, index: position, count: removed };
      this.notify(operation);
    } finally {
      PerformanceTrace.end('reader.scroll.remove', trace);
    }
  }
  private notify(operation: DataOperation): void {
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDatasetChange([operation]));
  }
  findPosition(chapterIndex: number, offset: number): number {
    let last = -1;
    for (let index = 0; index < this.rows.length; index++) {
      const row = this.rows[index];
      if (row.chapterIndex !== chapterIndex) continue;
      if (offset <= 0) return index;
      if (row.heading) continue;
      last = index;
      if (offset < row.endOffset || row.endOffset === 0) return index;
    }
    return last;
  }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
}
