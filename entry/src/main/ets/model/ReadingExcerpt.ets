/** 摘录独立保留书籍信息，删除书架或源定义不会丢失已保存的原句。 */
export class ReadingExcerptBookInfo {
  bookKey: string = '';
  bookId: string = '';
  bookTitle: string = '';
  author: string = '';
  cover: string = '';
  sourceUrl: string = '';
  bookUrl: string = '';
}

export class ReadingExcerpt extends ReadingExcerptBookInfo {
  id: string = '';
  chapterId: string = '';
  chapterUrl: string = '';
  chapterTitle: string = '';
  resourceIndex: number = 0;
  /** 原文章节中的 UTF-16 坐标，不受后续字体、分页和替换规则变化影响。 */
  startOffset: number = 0;
  endOffset: number = 0;
  text: string = '';
  createdAt: number = 0;
}

export class ReadingExcerptBook extends ReadingExcerptBookInfo {
  count: number = 0;
  latestAt: number = 0;
  latestText: string = '';
}

export class ReadingExcerptSaveResult {
  excerpt: ReadingExcerpt = new ReadingExcerpt();
  created: boolean = false;
}
