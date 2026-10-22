import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { emitter } from '@kit.BasicServicesKit';
import { TextReadingPosition } from '../../model/TextReading';
import { GeneralSettings } from '../../model/GeneralSettings';
import { PreferenceService } from '../PreferenceService';

const STORE_NAME: string = 'online_text_reading_progress';
const KEY_PREFIX: string = 'position_';
export const EVT_TEXT_READING_PROGRESS_CHANGED: string = 'app.text.reading.progress.changed';

export class TextReadingProgressService {
  private static store: preferences.Preferences | null = null;
  private static initPromise: Promise<void> | null = null;

  static init(context: common.Context): Promise<void> {
    if (TextReadingProgressService.store !== null) return Promise.resolve();
    if (TextReadingProgressService.initPromise !== null) return TextReadingProgressService.initPromise;
    TextReadingProgressService.initPromise = preferences.getPreferences(context, { name: STORE_NAME })
      .then((value: preferences.Preferences): void => {
        TextReadingProgressService.store = value;
      })
      .finally((): void => {
        TextReadingProgressService.initPromise = null;
      });
    return TextReadingProgressService.initPromise;
  }

  static async get(context: common.Context, bookId: string): Promise<TextReadingPosition | null> {
    await TextReadingProgressService.init(context);
    const store = TextReadingProgressService.store;
    if (store === null) return null;
    const raw = store.getSync(TextReadingProgressService.key(bookId), '');
    if (typeof raw !== 'string' || !raw) return null;
    try {
      const parsed = JSON.parse(raw) as TextReadingPosition;
      const value = new TextReadingPosition();
      value.bookId = typeof parsed.bookId === 'string' ? parsed.bookId : bookId;
      value.resourceIndex = typeof parsed.resourceIndex === 'number' ? parsed.resourceIndex : 0;
      value.domPos = typeof parsed.domPos === 'string' ? parsed.domPos : '';
      value.charOffset = typeof parsed.charOffset === 'number' ? parsed.charOffset : 0;
      value.pageOffset = typeof parsed.pageOffset === 'number' ? parsed.pageOffset : 0;
      value.chapterTitle = typeof parsed.chapterTitle === 'string' ? parsed.chapterTitle : '';
      value.updatedAt = typeof parsed.updatedAt === 'number' ? parsed.updatedAt : 0;
      return value;
    } catch (_e) {
      return null;
    }
  }

  static async save(context: common.Context, position: TextReadingPosition): Promise<void> {
    await TextReadingProgressService.init(context);
    const store = TextReadingProgressService.store;
    if (store === null || !position.bookId) return;
    await TextReadingProgressService.prepareHistory(store);
    store.putSync(TextReadingProgressService.key(position.bookId), JSON.stringify(position));
    if (GeneralSettings.current.historyEnabled) {
      store.putSync('history_' + TextReadingProgressService.key(position.bookId), JSON.stringify(position));
    }
    emitter.emit(EVT_TEXT_READING_PROGRESS_CHANGED);
    await store.flush();
    await PreferenceService.promoteFavorite(position.bookId).catch((): void => {
      // 小说、漫画和朗读共用此进度入口；书架排序失败不影响续读。
    });
  }

  /** 记录页与备份共用逐条校验，坏记录不影响其他书籍。 */
  static async getAll(context: common.Context, historyOnly: boolean = false): Promise<TextReadingPosition[]> {
    await TextReadingProgressService.init(context);
    const store = TextReadingProgressService.store;
    const positions: TextReadingPosition[] = [];
    if (store === null) return positions;
    if (historyOnly) await TextReadingProgressService.prepareHistory(store);
    const prefix = historyOnly ? 'history_' + KEY_PREFIX : KEY_PREFIX;
    for (const key of Object.keys(await store.getAll())) {
      if (!key.startsWith(prefix)) continue;
      const raw = store.getSync(key, '');
      if (typeof raw !== 'string' || !raw) continue;
      try {
        const position: TextReadingPosition = JSON.parse(raw);
        if (TextReadingProgressService.isValidPosition(position)) positions.push(position);
      } catch (_e) { /* 只跳过当前记录，不改写本机数据。 */ }
    }
    return positions.sort((left: TextReadingPosition, right: TextReadingPosition): number =>
      right.updatedAt - left.updatedAt);
  }

  private static async prepareHistory(store: preferences.Preferences): Promise<void> {
    if (store.getSync('history_snapshot_migrated', false) === true) return;
    const entries = await store.getAll();
    if (store.getSync('history_snapshot_migrated', false) === true) return;
    for (const key of Object.keys(entries)) {
      if (key.startsWith(KEY_PREFIX)) store.putSync('history_' + key, store.getSync(key, ''));
    }
    store.putSync('history_snapshot_migrated', true);
    await store.flush();
  }

  static isValidPosition(position: TextReadingPosition): boolean {
    return !!position && typeof position.bookId === 'string' && position.bookId.length > 0 &&
      position.bookId.length <= 8192 && typeof position.domPos === 'string' && position.domPos.length <= 8192 &&
      typeof position.chapterTitle === 'string' && position.chapterTitle.length <= 1024 * 1024 &&
      [position.resourceIndex, position.charOffset, position.pageOffset, position.updatedAt]
        .every((value: number): boolean => Number.isSafeInteger(value) && value >= 0);
  }

  /** 替换在线进度，保留当前设备的本地导入书籍。 */
  static async restoreBackupPositions(context: common.Context, positions: TextReadingPosition[]): Promise<void> {
    await TextReadingProgressService.init(context);
    const store = TextReadingProgressService.store;
    if (store === null) throw new Error('Reading progress storage is unavailable');
    for (const key of Object.keys(await store.getAll())) {
      if ((key.startsWith(KEY_PREFIX) && !key.startsWith(KEY_PREFIX + 'import_')) ||
        (key.startsWith('history_' + KEY_PREFIX) && !key.startsWith('history_' + KEY_PREFIX + 'import_'))) store.deleteSync(key);
    }
    for (const position of positions) {
      if (!TextReadingProgressService.isValidPosition(position) || position.bookId.startsWith('import_')) continue;
      store.putSync(TextReadingProgressService.key(position.bookId), JSON.stringify(position));
      store.putSync('history_' + TextReadingProgressService.key(position.bookId), JSON.stringify(position));
    }
    await store.flush();
    emitter.emit(EVT_TEXT_READING_PROGRESS_CHANGED);
  }

  static async remove(context: common.Context, bookId: string): Promise<void> {
    await TextReadingProgressService.init(context);
    const store = TextReadingProgressService.store;
    if (store === null) return;
    store.deleteSync(TextReadingProgressService.key(bookId));
    store.deleteSync('history_' + TextReadingProgressService.key(bookId));
    emitter.emit(EVT_TEXT_READING_PROGRESS_CHANGED);
    await store.flush();
  }

  private static key(bookId: string): string {
    return KEY_PREFIX + bookId.replace(new RegExp('[^A-Za-z0-9_.-]', 'g'), '_');
  }
}
