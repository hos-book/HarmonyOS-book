import { Book } from './Book';

export class BookPresentationEdit {
  bookId: string = '';
  title: string = '';
  cover: string = '';
  group: string = '';
}

/** 用户展示信息独立于书源元数据，刷新详情和搜索不能覆盖。 */
export class BookPresentation {
  static edits: BookPresentationEdit[] = [];
  static groups: string[] = [];

  static get(bookId: string): BookPresentationEdit | undefined {
    return BookPresentation.edits.find((item: BookPresentationEdit): boolean => item.bookId === bookId);
  }

  static apply(book: Book): Book {
    const edit = BookPresentation.get(book.id);
    if (edit?.title) book.title = edit.title;
    if (edit?.cover) { book.cover = edit.cover; book.coverFromDetail = true; book.coverFallback = undefined; }
    return book;
  }
}
