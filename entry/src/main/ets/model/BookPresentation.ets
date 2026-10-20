import { Book } from './Book';

export class BookPresentationEdit {
  bookId: string = '';
  title: string = '';
  cover: string = '';
  group: string = '';
}

/** 用户展示信息独立于书源元数据，刷新详情和搜索不能覆盖。 */
export class BookPresentation {
  static readonly UNGROUPED: string = '__ungrouped__';
  static edits: BookPresentationEdit[] = [];
  static groups: string[] = [];

  static matchesGroup(bookId: string, filter: string): boolean {
    if (!filter) return true;
    const group = BookPresentation.get(bookId)?.group ?? '';
    return filter === BookPresentation.UNGROUPED ? !group : group === filter;
  }

  static assignGroup(bookIds: string[], group: string): BookPresentationEdit[] {
    const ids = new Set(bookIds);
    const edits = BookPresentation.edits.filter((item: BookPresentationEdit): boolean => !ids.has(item.bookId));
    ids.forEach((id: string): void => {
      const previous = BookPresentation.get(id);
      const edit = new BookPresentationEdit();
      edit.bookId = id;
      edit.title = previous?.title ?? '';
      edit.cover = previous?.cover ?? '';
      edit.group = group;
      edits.push(edit);
    });
    return edits;
  }

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
