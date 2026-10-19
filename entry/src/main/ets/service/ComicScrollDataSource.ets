import { ComicPage } from './ComicReaderService';

export class ComicScrollRow {
  page: ComicPage = new ComicPage();
  chapterIndex: number = 0;
  pageIndex: number = 0;
}

export class ComicScrollChapter {
  index: number = 0;
  pages: ComicPage[] = [];
  rows: ComicScrollRow[] = [];

  static create(index: number, pages: ComicPage[]): ComicScrollChapter {
    const chapter = new ComicScrollChapter();
    chapter.index = index;
    chapter.pages = pages;
    for (let pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      const row = new ComicScrollRow();
      row.page = pages[pageIndex];
      row.chapterIndex = index;
      row.pageIndex = pageIndex;
      chapter.rows.push(row);
    }
    return chapter;
  }
}

/** 跨章滚动仅通知增删，保留原图片身份及列表的视觉锚点。 */
export class ComicScrollDataSource implements IDataSource {
  private rows: ComicScrollRow[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.rows.length; }
  getData(index: number): ComicScrollRow { return this.rows[index]; }
  reset(rows: ComicScrollRow[]): void {
    this.rows = rows.slice();
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
  insert(index: number, rows: ComicScrollRow[]): void {
    for (let offset = 0; offset < rows.length; offset++) {
      const position = index + offset;
      this.rows.splice(position, 0, rows[offset]);
      this.listeners.forEach((listener: DataChangeListener): void => listener.onDataAdd(position));
    }
  }
  remove(index: number, count: number): void {
    for (let offset = 0; offset < count; offset++) {
      this.rows.splice(index, 1);
      this.listeners.forEach((listener: DataChangeListener): void => listener.onDataDelete(index));
    }
  }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
}
