import { Book } from '../model/Book';

/**
 * LazyForEach 通用数据源
 * 长列表性能基础设施，禁用 index 作为 key
 */
export class BookDataSource implements IDataSource {
  private books: Book[] = [];
  private listeners: DataChangeListener[] = [];
  private versionedBooks: Map<string, Book> = new Map();
  private contentVersions: Map<string, number> = new Map();

  totalCount(): number {
    return this.books.length;
  }

  getData(index: number): Book {
    return this.books[index];
  }

  setBooks(books: Book[]): void {
    this.books = books;
    this.listeners.forEach((l) => l.onDataReloaded());
  }

  /** 搜索流式结果只新增或替换时保留已有节点；切换筛选导致删除/重排时整体刷新。 */
  updateBooks(books: Book[]): void {
    // LazyForEach 对未观测对象仅在键变化时重建；隐藏项的版本保留到 clear，支持筛选切回。
    for (const book of books) {
      const previous = this.versionedBooks.get(book.id);
      if (previous !== undefined && previous !== book) {
        this.contentVersions.set(book.id, (this.contentVersions.get(book.id) ?? 0) + 1);
      }
      this.versionedBooks.set(book.id, book);
    }
    const previousIndexes = new Map<string, number>();
    for (let index = 0; index < this.books.length; index++) previousIndexes.set(this.books[index].id, index);
    const added: number[] = [];
    const changed: number[] = [];
    let retained = 0;
    let lastIndex = -1;
    for (let index = 0; index < books.length; index++) {
      const previous = previousIndexes.get(books[index].id);
      if (previous === undefined) {
        added.push(index);
        continue;
      }
      if (previous <= lastIndex) {
        this.setBooks(books);
        return;
      }
      lastIndex = previous;
      retained++;
      if (this.books[previous] !== books[index]) changed.push(index);
    }
    if (retained !== this.books.length) {
      this.setBooks(books);
      return;
    }
    this.books = books;
    for (const index of added) this.listeners.forEach((listener) => listener.onDataAdd(index));
    for (const index of changed) this.listeners.forEach((listener) => listener.onDataChange(index));
  }

  /** 与 updateBooks 配套；业务身份稳定，仅该项内容替换时更新版本，不受列表索引影响。 */
  getVersionedKey(book: Book): string {
    return `${book.id}:${this.contentVersions.get(book.id) ?? 0}`;
  }

  appendBooks(newBooks: Book[]): void {
    const start = this.books.length;
    this.books.push(...newBooks);
    for (let i = start; i < this.books.length; i++) {
      this.listeners.forEach((l) => l.onDataAdd(i));
    }
  }

  clear(): void {
    this.books = [];
    this.versionedBooks.clear();
    this.contentVersions.clear();
    this.listeners.forEach((l) => l.onDataReloaded());
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }
}
