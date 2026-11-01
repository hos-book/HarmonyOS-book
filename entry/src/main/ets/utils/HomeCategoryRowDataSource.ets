import { Book } from '../model/Book';

export class HomeCategoryBookRow {
  books: Book[];
  startIndex: number;
  key: string;

  constructor(books: Book[], startIndex: number) {
    this.books = books;
    this.startIndex = startIndex;
    this.key = books.map((book: Book): string => book.id).join('|');
  }
}

/** 按列数分行，让 API 20 的 List 也能懒加载分类网格或单列书单。 */
export class HomeCategoryRowDataSource implements IDataSource {
  private rows: HomeCategoryBookRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): HomeCategoryBookRow {
    return this.rows[index];
  }

  setBooks(books: Book[], columns: number = 3): void {
    const count = Math.max(1, Math.floor(columns));
    const rows: HomeCategoryBookRow[] = [];
    for (let index: number = 0; index < books.length; index += count) {
      rows.push(new HomeCategoryBookRow(books.slice(index, index + count), index));
    }
    this.rows = rows;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}
