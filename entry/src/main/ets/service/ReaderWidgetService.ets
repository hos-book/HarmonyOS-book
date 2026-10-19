import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import lazy { formBindingData, formProvider } from '@kit.FormKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book } from '../model/Book';
import { TextReadingPosition } from '../model/TextReading';
import { PreferenceService } from './PreferenceService';
import { TextReadingProgressService } from './text/TextReadingProgressService';
import { WidgetUpdater } from './WidgetUpdater';
import { PlatformCompat } from '../utils/PlatformCompat';

const STATE_STORE = 'reader_widget_state';
const FORMS_STORE = 'reader_widget_forms';

export class ReaderWidgetSnapshot {
  bookId: string = '';
  bookTitle: string = '';
  author: string = '';
  cover: string = '';
  chapterTitle: string = '';
  chapterIndex: number = 0;
  chapterCount: number = 0;
  target: string = 'home';
}

class ReaderWidgetData extends ReaderWidgetSnapshot {
  hasBook: boolean = false;
  hasCover: boolean = false;
  coverUri: string = '';
  cardLabel: string = '';
  progressLabel: string = '';
  actionLabel: string = '';
}

/** 仅保存卡片展示快照；继续阅读仍使用原有章节/字符进度，不复制另一套进度。 */
export class ReaderWidgetService {
  private static generation: number = 0;
  private static lastState: string = '';
  private static writes: Promise<void> = Promise.resolve();

  static update(context: common.Context, book: Book, position: TextReadingPosition): Promise<void> {
    if (PlatformCompat.wearable || book.id !== position.bookId) return Promise.resolve();
    const snapshot = ReaderWidgetService.fromBook(book, position);
    const serialized = JSON.stringify(snapshot);
    if (serialized === ReaderWidgetService.lastState) return ReaderWidgetService.writes;
    const generation = ++ReaderWidgetService.generation;
    ReaderWidgetService.lastState = serialized;
    ReaderWidgetService.writes = ReaderWidgetService.writes.then(async (): Promise<void> => {
      if (generation !== ReaderWidgetService.generation) return;
      const store = await preferences.getPreferences(context, { name: STATE_STORE });
      await store.put('snapshot', serialized);
      await store.flush();
      await ReaderWidgetService.refreshAll(context, snapshot, generation);
    }).catch((error: Error): void => {
      if (generation === ReaderWidgetService.generation) ReaderWidgetService.lastState = '';
      hilog.warn(0xFF00, 'ReaderWidget', 'update failed: %{public}s', error.message);
    });
    return ReaderWidgetService.writes;
  }

  private static fromBook(book: Book, position: TextReadingPosition): ReaderWidgetSnapshot {
    const snapshot = new ReaderWidgetSnapshot();
    snapshot.bookId = book.id;
    snapshot.bookTitle = book.title;
    snapshot.author = book.author;
    snapshot.cover = book.cover;
    snapshot.chapterCount = Math.max(0, book.chapters.length || book.chapterCount);
    snapshot.chapterIndex = Math.max(0, Math.min(position.resourceIndex, Math.max(0, snapshot.chapterCount - 1)));
    snapshot.chapterTitle = position.chapterTitle || book.chapters[snapshot.chapterIndex]?.title || '';
    snapshot.target = book.contentType === 'comic' ? 'comicReader' : 'reader';
    return snapshot;
  }

  static emptyData(context: common.Context): ReaderWidgetData {
    const data = new ReaderWidgetData();
    data.cardLabel = context.resourceManager.getStringSync($r('app.string.reader_card_label').id);
    data.bookTitle = context.resourceManager.getStringSync($r('app.string.reader_card_empty').id);
    data.chapterTitle = context.resourceManager.getStringSync($r('app.string.reader_card_empty_hint').id);
    data.actionLabel = context.resourceManager.getStringSync($r('app.string.reader_card_open').id);
    data.progressLabel = data.actionLabel;
    return data;
  }

  static async latest(context: common.Context): Promise<ReaderWidgetSnapshot> {
    await preferences.removePreferencesFromCache(context, { name: STATE_STORE });
    const store = await preferences.getPreferences(context, { name: STATE_STORE });
    const raw = await store.get('snapshot', '');
    if (typeof raw === 'string' && raw) {
      try {
        const snapshot: ReaderWidgetSnapshot = JSON.parse(raw);
        if (typeof snapshot.bookId === 'string' && snapshot.bookId && typeof snapshot.bookTitle === 'string' &&
          typeof snapshot.author === 'string' && typeof snapshot.cover === 'string' &&
          typeof snapshot.chapterTitle === 'string' && Number.isFinite(snapshot.chapterIndex) &&
          Number.isFinite(snapshot.chapterCount) && ['reader', 'comicReader'].includes(snapshot.target)) return snapshot;
      } catch (_) { /* 坏快照从已有阅读记录恢复。 */ }
    }
    await PreferenceService.invalidateCache(context);
    await PreferenceService.init(context);
    const imported: Book[] = JSON.parse(await PreferenceService.getImportedBooks());
    const cached: Book[] = JSON.parse(await PreferenceService.getCachedBooks());
    const books = imported.concat(cached);
    const positions = await TextReadingProgressService.getAll(context);
    for (const position of positions) {
      const book = books.find((candidate: Book): boolean => candidate.id === position.bookId);
      if (book && (book.contentType === 'text' || book.contentType === 'comic')) {
        return ReaderWidgetService.fromBook(book, position);
      }
    }
    return new ReaderWidgetSnapshot();
  }

  static async register(context: common.Context, formId: string, remove: boolean = false): Promise<void> {
    if (!formId) return;
    const store = await ReaderWidgetService.formsStore(context);
    if (remove) await store.delete(formId);
    else await store.put(formId, true);
    await store.flush();
  }

  private static async formsStore(context: common.Context): Promise<preferences.Preferences> {
    await preferences.removePreferencesFromCache(context, { name: FORMS_STORE });
    return preferences.getPreferences(context, { name: FORMS_STORE });
  }

  private static async refreshAll(context: common.Context, snapshot: ReaderWidgetSnapshot,
    generation: number): Promise<void> {
    const store = await ReaderWidgetService.formsStore(context);
    const ids = Object.keys(await store.getAll());
    if (ids.length === 0 || generation !== ReaderWidgetService.generation) return;
    await ReaderWidgetService.push(context, ids, snapshot, true, generation);
  }

  static async refresh(context: common.Context, formId: string): Promise<void> {
    const snapshot = await ReaderWidgetService.latest(context);
    await ReaderWidgetService.push(context, [formId], snapshot, false);
  }

  private static async push(context: common.Context, ids: string[], snapshot: ReaderWidgetSnapshot,
    allowNetwork: boolean, generation: number = -1): Promise<void> {
    const data = ReaderWidgetService.emptyData(context);
    if (snapshot.bookId) {
      data.hasBook = true;
      data.bookId = snapshot.bookId;
      data.bookTitle = snapshot.bookTitle;
      data.author = snapshot.author;
      data.chapterTitle = snapshot.chapterTitle;
      data.target = snapshot.target;
      data.actionLabel = context.resourceManager.getStringSync($r('app.string.reader_card_continue').id);
      const percent = snapshot.chapterCount > 0 ?
        Math.min(99, Math.max(0, Math.floor(snapshot.chapterIndex * 100 / snapshot.chapterCount))) : 0;
      data.progressLabel = context.resourceManager.getStringSync($r('app.string.reader_card_progress').id, percent);
    }
    let file: fileIo.File | null = null;
    try {
      const cover: string | null = await WidgetUpdater.resolveFormCover(context, snapshot.bookId, snapshot.cover,
        snapshot.bookTitle, snapshot.author, allowNetwork);
      if (generation >= 0 && generation !== ReaderWidgetService.generation) return;
      let payload: string = '';
      if (cover) {
        try { file = await fileIo.open(cover, fileIo.OpenMode.READ_ONLY); } catch (_) {}
      }
      if (file) {
        const name = `reader_${Date.now()}_${generation}`;
        data.coverUri = `memory://${name}`;
        data.hasCover = true;
        // FormKit 的图片键是动态文件名，以 JSON 构造，保持 ArkTS 数据类字段静态。
        payload = JSON.stringify(data).slice(0, -1) + ',"formImages":{' + JSON.stringify(name) + ':' + file.fd + '}}';
      } else {
        data.coverUri = snapshot.cover.startsWith('https://') ? snapshot.cover : '';
        data.hasCover = data.coverUri.length > 0;
        payload = JSON.stringify(data);
      }
      const binding = formBindingData.createFormBindingData(payload);
      for (const id of ids) {
        if (generation >= 0 && generation !== ReaderWidgetService.generation) return;
        try { await formProvider.updateForm(id, binding); } catch (error) {
          hilog.warn(0xFF00, 'ReaderWidget', 'push failed: %{public}s', String(error));
        }
      }
    } finally {
      if (file) { try { await fileIo.close(file); } catch (_) {} }
    }
  }
}
