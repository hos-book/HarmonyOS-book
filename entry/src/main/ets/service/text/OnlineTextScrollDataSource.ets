import { OnlineTextPage } from './OnlineTextPaginator';
import { PerformanceTrace } from '../../utils/PerformanceTrace';

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
}

export class OnlineTextScrollChapter {
  index: number = 0;
  content: string = '';
  rows: OnlineTextScrollRow[] = [];

  static create(index: number, key: string, title: string, content: string,
    lines: OnlineTextPage[]): OnlineTextScrollChapter {
    const chapter = new OnlineTextScrollChapter();
    chapter.index = index;
    chapter.content = content;
    const heading = new OnlineTextScrollRow();
    heading.key = `${key}:heading`;
    heading.chapterIndex = index;
    heading.text = title;
    heading.heading = true;
    chapter.rows.push(heading);
    for (const line of lines) {
      const row = new OnlineTextScrollRow();
      row.page = line;
      row.key = `${key}:${line.startOffset}:${line.endOffset}:${line.layoutKey}`;
      row.chapterIndex = index;
      row.startOffset = line.startOffset;
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
      if (row.chapterIndex !== chapterIndex || row.heading) continue;
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
