/** 空 bookKey 展示全部书籍；指定 bookKey 展示该书的摘录。 */
export class ReadingExcerptRoute {
  bookKey: string;
  bookTitle: string;

  constructor(bookKey: string = '', bookTitle: string = '') {
    this.bookKey = bookKey;
    this.bookTitle = bookTitle;
  }
}
