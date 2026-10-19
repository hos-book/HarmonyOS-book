import { GeneralSettings } from '../model/GeneralSettings';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Book, Chapter } from '../model/Book';
import { TextReadingPosition } from '../model/TextReading';
import { DiagnosticLogService } from './DiagnosticLogService';

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

/** 独立于最新进度的有界会话记录。跨章保留分段，跳回不覆盖过去会话。 */
export class ReadingSessionService {
  private static store: preferences.Preferences | null = null;
  private static ready: Promise<void> = Promise.resolve();
  private static chain: Promise<void> = Promise.resolve();
  private static active: Map<string, ReadingSession> = new Map();
  private static savedAt: Map<string, number> = new Map();
  private static sequence: number = 0;

  static init(context: common.BaseContext): void {
    ReadingSessionService.ready = preferences.getPreferences(context, { name: 'reading_sessions_v1' })
      .then((store: preferences.Preferences): void => { ReadingSessionService.store = store; })
      .catch((error: Error): void => { DiagnosticLogService.info('session.init.failed', error.message); });
  }

  static checkpoint(kind: string, location: SessionLocation, running: boolean): void {
    if (!GeneralSettings.current.historyEnabled) { ReadingSessionService.active.delete(kind); return; }
    let entry = ReadingSessionService.active.get(kind);
    if (!entry && !running) return;
    const now = Date.now();
    if (!entry || entry.end.bookId !== location.bookId || entry.end.chapterId !== location.chapterId ||
      entry.end.chapterIndex !== location.chapterIndex) {
      const sessionId = entry?.end.bookId === location.bookId ? entry.sessionId : '';
      if (entry) ReadingSessionService.persist(entry);
      entry = new ReadingSession();
      entry.id = `${now}_${++ReadingSessionService.sequence}`;
      entry.sessionId = sessionId || entry.id;
      entry.kind = kind;
      entry.startedAt = now;
      entry.start = location;
      ReadingSessionService.active.set(kind, entry);
      ReadingSessionService.savedAt.delete(kind);
    }
    entry.endedAt = Math.max(entry.startedAt, now);
    entry.end = location;
    if (!running || now - (ReadingSessionService.savedAt.get(kind) ?? 0) >= 5000) {
      ReadingSessionService.persist(entry);
      ReadingSessionService.savedAt.set(kind, now);
    }
    if (!running) ReadingSessionService.active.delete(kind);
  }

  static end(kind: string): void {
    if (!GeneralSettings.current.historyEnabled) { ReadingSessionService.active.delete(kind); return; }
    const entry = ReadingSessionService.active.get(kind);
    if (!entry) return;
    entry.endedAt = Math.max(entry.startedAt, Date.now());
    ReadingSessionService.persist(entry);
    ReadingSessionService.active.delete(kind);
  }

  private static persist(entry: ReadingSession): void {
    const raw = JSON.stringify(entry);
    const id = entry.id;
    ReadingSessionService.chain = ReadingSessionService.chain.then(async (): Promise<void> => {
      await ReadingSessionService.ready;
      const store = ReadingSessionService.store;
      if (!store) throw new Error('Session store unavailable');
      await store.put(id, raw);
      const keys = Object.keys(await store.getAll()).sort();
      for (let index = 0; index < keys.length - 2000; index++) await store.delete(keys[index]);
      await store.flush();
    }).catch((error: Error): void => { DiagnosticLogService.info('session.save.failed', error.message); });
  }

  private static mergeActive(result: Map<string, ReadingSession>, bookIds: Set<string>): void {
    for (const entry of ReadingSessionService.active.values()) {
      if (!bookIds.has(entry.end.bookId)) continue;
      // 返回独立快照，持续播放时不原地修改已显示的列表项。
      const snapshot: ReadingSession = JSON.parse(JSON.stringify(entry));
      result.set(snapshot.id, snapshot);
    }
  }

  static async list(bookIds: string[], isActive: () => boolean = (): boolean => true): Promise<ReadingSession[]> {
    const wanted = new Set<string>(bookIds);
    if (wanted.size === 0 || !isActive()) return [];
    const result = new Map<string, ReadingSession>();
    // 读取不触发额外写盘；在途会话通过内存快照覆盖已保存的旧进度。
    ReadingSessionService.mergeActive(result, wanted);
    await ReadingSessionService.chain;
    await ReadingSessionService.ready;
    if (!isActive()) return [];
    const store = ReadingSessionService.store;
    if (!store) throw new Error('Session store unavailable');
    ReadingSessionService.mergeActive(result, wanted);
    const values: preferences.ValueType[] = Object.values(await store.getAll());
    for (let index = 0; index < values.length; index++) {
      // 每批让出事件循环，避免 2000 条 JSON 解析连占 UI 线程；离页后立即停止。
      if (index % 32 === 0) {
        await new Promise<void>((resolve): void => { setTimeout(resolve, 0); });
        if (!isActive()) return [];
      }
      const raw = values[index];
      if (typeof raw !== 'string') continue;
      try {
        const item: ReadingSession = JSON.parse(raw);
        if (item && item.start && item.end && typeof item.id === 'string' &&
          ['audio', 'reading', 'tts'].includes(item.kind) && wanted.has(item.end.bookId) &&
          Number.isFinite(item.startedAt) && Number.isFinite(item.endedAt) &&
          Number.isFinite(item.start.position) && Number.isFinite(item.end.position)) {
          const previous = result.get(item.id);
          if (!previous || item.endedAt > previous.endedAt) result.set(item.id, item);
        }
      } catch (_error) { /* 单条损坏不覆盖其他会话。 */ }
    }
    ReadingSessionService.mergeActive(result, wanted);
    return Array.from(result.values()).sort((left: ReadingSession, right: ReadingSession): number =>
      right.startedAt - left.startedAt);
  }
}
