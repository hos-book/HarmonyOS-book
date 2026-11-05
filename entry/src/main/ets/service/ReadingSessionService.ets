import { GeneralSettings } from '../model/GeneralSettings';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { SessionLocation, ReadingSession } from '../model/ReadingSession';
import { util } from '@kit.ArkTS';
import { emitter } from '@kit.BasicServicesKit';
import { LibrarySyncModel, LibrarySyncValue, LIBRARY_SYNC_CHANGED } from './sync/LibrarySyncModel';
import { DiagnosticLogService } from './DiagnosticLogService';

export { SessionLocation, ReadingSession } from '../model/ReadingSession';

/** 独立于最新进度的有界会话记录。跨章保留分段，跳回不覆盖过去会话。 */
export class ReadingSessionService {
  private static store: preferences.Preferences | null = null;
  private static ready: Promise<void> = Promise.resolve();
  private static chain: Promise<void> = Promise.resolve();
  private static active: Map<string, ReadingSession> = new Map();
  private static savedAt: Map<string, number> = new Map();

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
      entry.id = `${now}_${util.generateRandomUUID(false)}`;
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
      emitter.emit(LIBRARY_SYNC_CHANGED);
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

  private static syncValues(store: preferences.Preferences): LibrarySyncValue[] {
    const result: LibrarySyncValue[] = [];
    const stored: preferences.ValueType[] = Object.values(store.getAllSync());
    for (const raw of stored) {
      if (typeof raw !== 'string') continue;
      try {
        const item: ReadingSession = JSON.parse(raw);
        if (!item?.start || !item.end || !LibrarySyncValue.online(item.end.bookId)) continue;
        // 历史跳转依赖章节身份和位置，不跨设备传输临时音频地址或本机路径。
        item.start.chapterUrl = '';
        item.end.chapterUrl = '';
        const value = new LibrarySyncValue('session', item.end.bookId, JSON.stringify(item));
        value.entryId = item.id;
        if (LibrarySyncModel.validSession(value.bookId, value.entryId, value.value)) result.push(value);
      } catch (_error) { /* 跳过单条损坏数据，不改变本机历史。 */ }
    }
    return result.sort(LibrarySyncModel.order);
  }

  static async exportLibrarySyncValues(): Promise<LibrarySyncValue[]> {
    await ReadingSessionService.ready;
    await ReadingSessionService.chain;
    if (!ReadingSessionService.store) throw new Error('Session store unavailable');
    return ReadingSessionService.syncValues(ReadingSessionService.store);
  }

  static async applyLibrarySyncValues(records: LibrarySyncValue[], expected: LibrarySyncValue[],
    guard: () => void): Promise<LibrarySyncValue[]> {
    const applied: LibrarySyncValue[] = [];
    const task = ReadingSessionService.chain.then(async (): Promise<void> => {
      await ReadingSessionService.ready;
      const store = ReadingSessionService.store;
      if (!store) throw new Error('Session store unavailable');
      guard();
      const current = new Map<string, string>();
      const baseline = new Map<string, string>();
      ReadingSessionService.syncValues(store).forEach((v: LibrarySyncValue): void => {
        current.set(LibrarySyncValue.key(v), v.value);
      });
      expected.forEach((v: LibrarySyncValue): void => { baseline.set(LibrarySyncValue.key(v), v.value); });
      for (const record of records) {
        if (record.kind !== 'session') continue;
        const key = LibrarySyncValue.key(record);
        if ((current.get(key) ?? '') !== (baseline.get(key) ?? '') ||
          Array.from(ReadingSessionService.active.values()).some((v: ReadingSession): boolean => v.id === record.entryId)) continue;
        if (record.value) {
          if (!LibrarySyncModel.validSession(record.bookId, record.entryId, record.value)) continue;
          store.putSync(record.entryId, record.value);
        } else store.deleteSync(record.entryId);
        applied.push(record);
      }
      if (applied.length === 0) return;
      const keys = Object.keys(store.getAllSync()).sort();
      // 优先淘汰在线旧会话，保留本地导入书的历史。
      let excess = keys.length - 2000;
      for (const key of keys) {
        if (excess <= 0) break;
        const raw = store.getSync(key, '');
        if (typeof raw !== 'string') continue;
        try {
          const item: ReadingSession = JSON.parse(raw);
          if (item?.end && LibrarySyncValue.online(item.end.bookId)) { store.deleteSync(key); excess--; }
        } catch (_error) { }
      }
      await store.flush();
    });
    ReadingSessionService.chain = task.catch((error: Error): void => {
      DiagnosticLogService.info('session.sync.failed', error.message);
    });
    await task;
    return applied;
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
