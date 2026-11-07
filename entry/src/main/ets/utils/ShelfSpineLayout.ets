import { Book } from '../model/Book';

export class ShelfSpineItem {
  book: Book;
  width: number;
  height: number;
  color: string;

  constructor(book: Book) {
    this.book = book;
    let seed = 0;
    for (let i = 0; i < book.id.length; i++) seed = (seed * 31 + book.id.charCodeAt(i)) >>> 0;
    this.width = 30 + seed % 11;
    this.height = 154 + Math.floor(seed / 11) % 35;
    const colors: string[] = ['#345B58', '#855348', '#34485E', '#70634C', '#59516A', '#526457', '#815D36'];
    this.color = colors[Math.floor(seed / 385) % colors.length];
  }
}

export class ShelfSpineRow {
  items: ShelfSpineItem[] = [];
  width: number = 0;
  key: string = '';

  add(item: ShelfSpineItem): void {
    this.items.push(item);
    this.width += item.width;
    // 身份与呈现内容决定刷新，阅听进度不会重建书脊封面。
    this.key += JSON.stringify([item.book.id, item.book.title, item.book.author, item.book.cover,
      item.book.contentType, item.book.sourceUrl, item.book.bookUrl, item.book.chapterCount,
      item.book.chapters.length]);
  }
}

export class ShelfSpineHint {
  title: string = '';
  left: number = 0;
  top: number = 0;
  width: number = 0;
  height: number = 44;
}

export class ShelfSpineLayout {
  static hint(row: ShelfSpineRow, bookId: string, width: number): ShelfSpineHint {
    const hint = new ShelfSpineHint();
    const available: number = Math.max(40, width);
    hint.width = Math.min(220, available);
    let left: number = 0;
    for (const item of row.items) {
      if (item.book.id === bookId) {
        hint.title = item.book.title;
        hint.left = Math.max(0, Math.min(available - hint.width, left + item.width / 2 - hint.width / 2));
        hint.top = 216 - item.height - 16 - hint.height - 6;
        return hint;
      }
      left += item.width;
    }
    return hint;
  }

  static rows(books: Book[], width: number): ShelfSpineRow[] {
    const rows: ShelfSpineRow[] = [];
    const available = Math.max(40, width);
    let row = new ShelfSpineRow();
    for (const book of books) {
      const item = new ShelfSpineItem(book);
      if (row.items.length > 0 && (row.width + item.width > available || row.items.length >= 32)) {
        rows.push(row);
        row = new ShelfSpineRow();
      }
      row.add(item);
    }
    if (row.items.length > 0) rows.push(row);
    return rows;
  }

  static bookAt(row: ShelfSpineRow, x: number): string {
    if (!Number.isFinite(x) || x < 0 || x >= row.width) return '';
    let edge = 0;
    for (const item of row.items) {
      edge += item.width;
      if (x < edge) return item.book.id;
    }
    return '';
  }

  static title(title: string, limit: number): string {
    const chars = Array.from(title.trim().replace(/\s+/g, ''));
    const count = Math.max(2, Math.floor(limit));
    return (chars.length > count ? chars.slice(0, count - 1).concat(['…']) : chars).join('\n');
  }
}
