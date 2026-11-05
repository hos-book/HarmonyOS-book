import { Book, Chapter } from './Book';
import { TextReadingPosition } from './TextReading';

export class SessionLocation {
  bookId: string = '';
  chapterId: string = '';
  chapterTitle: string = '';
  chapterUrl: string = '';
  chapterIndex: number = 0;
  position: number = 0;
  total: number = 0;
  domPos: string = '';
  pageOffset: number = 0;

  static audio(book: Book, chapter: Chapter, position: number, total: number): SessionLocation {
    const value = new SessionLocation();
    value.bookId = book.id;
    value.chapterId = chapter.id;
    value.chapterTitle = chapter.title;
    value.chapterUrl = chapter.originSourceValue || chapter.source.value;
    value.chapterIndex = Math.max(0, book.chapters.findIndex((item: Chapter): boolean => item.id === chapter.id));
    value.position = Math.max(0, position);
    value.total = Math.max(0, total);
    return value;
  }

  static text(book: Book, position: TextReadingPosition): SessionLocation {
    const chapter = book.chapters[position.resourceIndex];
    const value = chapter ? SessionLocation.audio(book, chapter, position.charOffset, 0) : new SessionLocation();
    value.bookId = book.id;
    value.chapterIndex = position.resourceIndex;
    value.chapterTitle = position.chapterTitle;
    value.position = position.charOffset;
    value.domPos = position.domPos;
    value.pageOffset = position.pageOffset;
    return value;
  }
}

export class ReadingSession {
  id: string = '';
  sessionId: string = '';
  kind: string = '';
  startedAt: number = 0;
  endedAt: number = 0;
  start: SessionLocation = new SessionLocation();
  end: SessionLocation = new SessionLocation();
}

