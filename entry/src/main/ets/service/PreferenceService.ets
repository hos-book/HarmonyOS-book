import { GeneralSettings } from '../model/GeneralSettings';
import { BookPresentation, BookPresentationEdit } from '../model/BookPresentation';
import lazy { MembershipService } from './MembershipService';
import { MembershipState } from '../model/MembershipState';
import { preferences } from '@kit.ArkData';
import { ReadingSessionService } from './ReadingSessionService';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { Book, Chapter } from '../model/Book';
import { AppAppearance } from '../model/AppAppearance';
import { AppThemeSelection } from '../model/AppThemeBundle';
import { ThemeBundles } from '../theme/ThemeBundles';

/** 书架收藏变化事件：加入、移出或最近阅听顺序变化后触发。 */
export const EVT_FAVORITES_CHANGED = 'app.favorites.changed';
export const EVT_SHELF_SOURCE_VISIBILITY_CHANGED = 'app.shelf.sourceVisibility.changed';
export const EVT_HOME_SOURCE_CHANGED = 'app.home.source.changed';

/**
 * 本地持久化：书架 / 播放历史 / 设置
 */
const STORE_NAME = 'listenbook_prefs';
const KEY_FAVORITES = 'favorite_book_ids';
const KEY_PINNED_FAVORITES = 'pinned_favorite_book_ids';
const KEY_SHELF_STATUS_FILTER = 'shelf_status_filter';
const KEY_HISTORY = 'play_history';
const KEY_LAST_PLAYED = 'last_played';
const KEY_COLOR_MODE = 'color_mode';
const KEY_MATERIAL_STYLE = 'material_style';
const KEY_ACCENT_COLOR = 'accent_color';
const KEY_THEME_SELECTION = 'app_theme_preferences';
const KEY_IMPORTED_BOOKS = 'imported_books';
const KEY_DEFAULT_TAB = 'default_tab';
const KEY_AUTO_PLAY_ON_LAUNCH = 'auto_play_on_launch';
const KEY_COVER_SUPER_RESOLUTION = 'cover_super_resolution';
export const EVT_COVER_SUPER_RESOLUTION_CHANGED = 'app.cover.super_resolution.changed';
const KEY_AUDIO_INTERRUPT_MODE = 'audio_interrupt_mode';
const KEY_AUDIO_AUTO_RESUME = 'audio_auto_resume';
const KEY_DEFAULT_PLAYBACK_SPEED = 'default_playback_speed';
const KEY_PRIVACY_AGREED_VERSION = 'privacy_agreed_version';
const KEY_HOME_GRID_COLUMNS = 'home_grid_columns';
const KEY_HOME_SOURCE_URL = 'home_source_url';
const KEY_HOME_SOURCE_MENU_COLUMNS = 'home_source_menu_columns';
const KEY_CACHED_BOOKS = 'cached_books_v1';
const KEY_PRELOAD_CHAPTERS = 'preload_chapters_count';
/** 搜索历史记录 */
const KEY_SEARCH_HISTORY = 'search_history_v1';
const KEY_SEARCH_CONCURRENCY = 'search_concurrency';
const MAX_SEARCH_HISTORY = 20;
/** 卡片侧持久化的播放快照(由主进程写,FormExtensionAbility 读) */
const KEY_WIDGET_PLAYER_SNAPSHOT = 'widget_player_snapshot_v1';
/** 已添加的卡片 formId 集合(按卡片名分桶) */
const KEY_WIDGET_FORM_IDS = 'widget_form_ids_v1';
/** 每本书独立的最新播放进度,key = `${KEY_PROGRESS_PREFIX}${bookId}` */
const KEY_PROGRESS_PREFIX = 'progress_v1_';
/** 每本书的章节级播放进度,key = `${KEY_CHAPTER_PROGRESS_PREFIX}${bookId}` */
const KEY_CHAPTER_PROGRESS_PREFIX = 'chapter_progress_v1_';
const MAX_CHAPTER_PROGRESS_PER_BOOK = 200;
/** 每本书独立的跳过头尾设置,key = `${KEY_SKIP_PREFIX}${bookId}`。
 *  独立小 KV,不再搭车缓存书索引——避免冷启动走 legacy/persistUnsafe 兜底分支时把 skip 丢掉。 */
const KEY_SKIP_PREFIX = 'skip_v1_';
/** 每本书独立的目录顺序(倒序)开关,key = `${KEY_TOC_ORDER_PREFIX}${bookId}`。
 *  与跳过头尾同思路:独立小 KV 作为权威来源,倒序时写 true,正序删 key 保持 store 干净。 */
const KEY_TOC_ORDER_PREFIX = 'toc_order_v1_';
/** 华为账号登录身份标识(UnionID/OpenID),JSON 持久化 */
const KEY_HW_ACCOUNT = 'hw_account_v1';

export interface PlayHistoryItem {
  bookId: string;
  chapterId: string;
  progressMs: number;
  updatedAt: number;
  chapterTitle?: string;
  durationMs?: number;
  sourceUrl?: string;
  bookUrl?: string;
}

export interface LastPlayedItem {
  bookId: string;
  chapterId: string;
  progressMs: number;
  chapterTitle?: string;
  durationMs?: number;
  speed?: number;
}

/** 每本书独立的跳过头尾设置(秒) */
export interface SkipConfig {
  skipIntro: number;
  skipOutro: number;
}

export class BookSkipBackup {
  bookId: string = '';
  skipIntro: number = 0;
  skipOutro: number = 0;
}

export class PreferenceBackupSnapshot {
  favorites: string[] = [];
  pinnedFavorites: string[] | undefined = undefined;
  history: PlayHistoryItem[] = [];
  lastPlayed: LastPlayedItem | null = null;
  progresses: PlayProgress[] = [];
  skipConfigs: BookSkipBackup[] = [];
  descendingBookIds: string[] | undefined = undefined;
  colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  materialStyle: number = 0;
  accentColor: string = '';
  themeSelection: AppThemeSelection | undefined = undefined;
  defaultTab: number = 0;
  autoPlayOnLaunch: boolean = false;
  audioInterruptMode: number = 0;
  audioAutoResume: boolean = true;
  defaultPlaybackSpeed: number = 1;
  homeGridColumns: number = 3;
  preloadChapters: number = 1;
  searchConcurrency: number = 3;
}

/**
 * 单本书的最新播放进度。
 * 与 PlayHistoryItem 的差异:per-book 一书一槽,永不溢出 50 条上限,
 * 切书前 reset AVPlayer 之前必须先把这条落盘,确保切回时拿到的是最新进度。
 */
export interface PlayProgress {
  bookId: string;
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  positionMs: number;
  durationMs: number;
  updatedAt: number;
  speed?: number;
  sourceUrl?: string;
  bookUrl?: string;
}

/** 单个章节的独立播放进度，用于手动切回章节时续播。 */
export class ChapterPlayProgress {
  bookId: string = '';
  chapterId: string = '';
  positionMs: number = 0;
  durationMs: number = 0;
  updatedAt: number = 0;
}

/** 卡片侧需要的最小快照,主进程写,FormExtensionAbility 读后渲染 */
export interface WidgetPlayerSnapshot {
  playbackKind?: string;
  charOffset?: number;
  bookId: string;
  bookTitle: string;
  author: string;
  cover: string;
  chapterId: string;
  chapterTitle: string;
  progressMs: number;
  durationMs: number;
  isPlaying: boolean;
  updatedAt: number;
}

/** 卡片名 -> formId 列表 */
interface FormIdBucket {
  name: string;
  ids: string[];
}

/** 华为账号登录身份标识(端侧直接返回,无需后端) */
export class HwAccount {
  unionID: string = '';
  openID: string = '';
  nickName: string = '';
  /** 仅保存本地头像缓存文件名，不保存短期有效的头像 URL。 */
  avatarFile: string = '';
  /** 登录时间戳 */
  loginAt: number = 0;

  static isValid(account: HwAccount | null): boolean {
    return account !== null && typeof account.unionID === 'string' &&
      account.unionID.trim().length > 0 && account.unionID.length <= 256 &&
      typeof account.openID === 'string' && account.openID.trim().length > 0 && account.openID.length <= 256 &&
      typeof account.loginAt === 'number' && Number.isFinite(account.loginAt) && account.loginAt > 0;
  }
}

export class PreferenceService {
  static async setBookGroup(bookIds: string[], group: string, groups: string[] = []): Promise<void> {
    await PreferenceService.ensureStore();
    const names = Array.from(new Set(BookPresentation.groups.concat(groups).concat(group ? [group] : [])));
    await PreferenceService.saveBookPresentation(BookPresentation.assignGroup(bookIds, group), names);
  }

  static async saveBookPresentation(edits: BookPresentationEdit[], groups: string[]): Promise<void> {
    const store = await PreferenceService.ensureStore();
    await store.put('book_presentation_v1', JSON.stringify(edits));
    await store.put('shelf_groups_v1', JSON.stringify(groups));
    await store.flush();
    BookPresentation.edits = edits;
    BookPresentation.groups = groups;
    emitter.emit(EVT_FAVORITES_CHANGED);
  }

  static async setAdaptiveHandedness(enabled: boolean): Promise<void> {
    const store = await PreferenceService.ensureStore();
    const previous = store.getSync('adaptive_handedness', true);
    try {
      await store.put('adaptive_handedness', enabled);
      await store.flush();
      GeneralSettings.current.adaptiveHandedness = enabled;
    } catch (error) {
      await store.put('adaptive_handedness', previous);
      throw new Error(`Failed to save handedness preference: ${String(error)}`);
    }
  }

  static async getComicVolumeKeyPageTurn(): Promise<boolean> {
    const store = await PreferenceService.ensureStore();
    return store.getSync('comic_volume_key_page_turn', false) === true;
  }

  static async setComicVolumeKeyPageTurn(enabled: boolean): Promise<void> {
    await PreferenceService.saveComicPreference('comic_volume_key_page_turn', enabled, false);
  }

  static async getComicReadingMode(): Promise<number> {
    const store = await PreferenceService.ensureStore();
    const value = store.getSync('comic_reading_mode', 0);
    return value === 1 || value === 3 ? value : 0;
  }

  static async setComicReadingMode(mode: number): Promise<void> {
    await PreferenceService.saveComicPreference('comic_reading_mode', mode === 1 || mode === 3 ? mode : 0, 0);
  }

  static async getComicChapterBar(fallback: boolean = true): Promise<boolean> {
    const store = await PreferenceService.ensureStore();
    const value = store.getSync('comic_chapter_bar', '');
    if (typeof value === 'boolean') return value;
    await PreferenceService.saveComicPreference('comic_chapter_bar', fallback, fallback);
    return fallback;
  }

  static async setComicChapterBar(enabled: boolean): Promise<void> {
    await PreferenceService.saveComicPreference('comic_chapter_bar', enabled, true);
  }

  private static async saveComicPreference(key: string, value: boolean | number,
    fallback: boolean | number): Promise<void> {
    const store = await PreferenceService.ensureStore();
    const previous = store.getSync(key, fallback);
    try {
      await store.put(key, value);
      await store.flush();
    } catch (error) {
      await store.put(key, previous);
      throw new Error(`Failed to save comic preference: ${String(error)}`);
    }
  }

  static async getComicBrightnessBar(): Promise<boolean> {
    const store = await PreferenceService.ensureStore();
    return store.getSync('comic_brightness_bar', true) !== false;
  }

  static async setComicBrightnessBar(enabled: boolean): Promise<void> {
    const store = await PreferenceService.ensureStore();
    await store.put('comic_brightness_bar', enabled);
    await store.flush();
  }

  static async getComicBrightness(): Promise<number> {
    const store = await PreferenceService.ensureStore();
    const value = store.getSync('comic_brightness', -1);
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? Math.min(1, value) : -1;
  }

  static async setComicBrightness(value: number): Promise<void> {
    const store = await PreferenceService.ensureStore();
    await store.put('comic_brightness', Number.isFinite(value) && value >= 0 ? Math.min(1, value) : -1);
    await store.flush();
  }

  static async setHistoryEnabled(enabled: boolean): Promise<void> {
    const store = await PreferenceService.ensureStore();
    await store.put('history_enabled', enabled);
    await store.flush();
    GeneralSettings.current.historyEnabled = enabled;
    if (!enabled) { ReadingSessionService.end('reading'); ReadingSessionService.end('audio'); ReadingSessionService.end('tts'); }
  }

  static async setShowShelfSource(enabled: boolean): Promise<void> {
    const store = await PreferenceService.ensureStore();
    await store.put('show_shelf_source', enabled);
    await store.flush();
    GeneralSettings.current.showShelfSource = enabled;
    emitter.emit(EVT_SHELF_SOURCE_VISIBILITY_CHANGED);
  }

  private static store: preferences.Preferences | null = null;
  private static initPromise: Promise<void> | null = null;
  private static appearanceSave: Promise<void> = Promise.resolve();
  private static favoriteListener: (() => void) | null = null;
  private static historyListener: (() => void) | null = null;

  /** 由 EntryAbility 启动时注入,用于触发卡片刷新(避免与 WidgetUpdater 形成循环 import) */
  static onFavoriteChanged(cb: () => void): void {
    PreferenceService.favoriteListener = cb;
  }

  static onHistoryChanged(cb: () => void): void {
    PreferenceService.historyListener = cb;
  }

  private static notifyFavoriteChanged(): void {
    PreferenceService.favoriteListener?.();
  }

  private static notifyHistoryChanged(): void {
    PreferenceService.historyListener?.();
  }

  static async init(context: common.BaseContext): Promise<void> {
    if (PreferenceService.store) {
      return;
    }
    if (!PreferenceService.initPromise) {
      ReadingSessionService.init(context);
      const options: preferences.Options = { name: STORE_NAME };
      PreferenceService.initPromise = preferences.getPreferences(context, options).then(async (s) => {
        PreferenceService.store = s;
        try {
          const edits = s.getSync('book_presentation_v1', '[]');
          const groups = s.getSync('shelf_groups_v1', '[]');
          if (typeof edits === 'string') BookPresentation.edits = JSON.parse(edits);
          if (typeof groups === 'string') BookPresentation.groups = JSON.parse(groups);
        } catch (_error) { /* 损坏的展示偏好不影响书籍和目录 */ }
        GeneralSettings.current.historyEnabled = s.getSync('history_enabled', true) !== false;
        GeneralSettings.current.showShelfSource = s.getSync('show_shelf_source', true) !== false;
        GeneralSettings.current.adaptiveHandedness = s.getSync('adaptive_handedness', true) !== false;
        const material = await s.get(KEY_MATERIAL_STYLE, 0);
        const accent = await s.get(KEY_ACCENT_COLOR, '');
        const rawTheme = await s.get(KEY_THEME_SELECTION, '');
        const selection: AppThemeSelection = PreferenceService.decodeThemeSelection(
          typeof rawTheme === 'string' ? rawTheme : '',
          typeof accent === 'string' ? accent : '', typeof material === 'number' ? material : 0);
        PreferenceService.publishThemeSelection(selection);
      });
    }
    await PreferenceService.initPromise;
  }

  static async ensureReady(context: common.BaseContext): Promise<void> {
    if (PreferenceService.store) return;
    await PreferenceService.init(context);
  }

  /**
   * 抛弃当前进程内的 preferences 缓存,强制下次 init 重新从文件读。
   * preferences 不支持多进程并发,FormExtensionAbility 进程的内存缓存
   * 不会感知主进程后续 put 的值;每次进入 onUpdateForm 前调一次,
   * 才能拿到主进程最新写入的卡片快照(避免卡片显示暂停但实际还在播)。
   */
  static async invalidateCache(context: common.BaseContext): Promise<void> {
    try {
      await preferences.removePreferencesFromCache(context, { name: STORE_NAME });
    } catch (_e) { /* ignore */ }
    PreferenceService.store = null;
    PreferenceService.initPromise = null;
  }

  private static async ensureStore(): Promise<preferences.Preferences> {
    if (!PreferenceService.store) {
      if (PreferenceService.initPromise) {
        await PreferenceService.initPromise;
      }
      if (!PreferenceService.store) {
        throw new Error('PreferenceService not initialized');
      }
    }
    return PreferenceService.store;
  }

  static async getFavorites(): Promise<string[]> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_FAVORITES, '[]') as string;
    return JSON.parse(raw) as string[];
  }

  static async getPinnedFavorites(): Promise<string[]> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_PINNED_FAVORITES, '[]');
    if (typeof raw !== 'string') return [];
    const pinned: string[] = JSON.parse(raw);
    const favorites = new Set(await PreferenceService.getFavorites());
    return pinned.filter((id: string): boolean => favorites.has(id));
  }

  /** 置顶书保持独立顺序，其余按最近加入或阅听的持久化顺序显示。 */
  static async getShelfFavorites(): Promise<string[]> {
    const favorites = await PreferenceService.getFavorites();
    const pinned = await PreferenceService.getPinnedFavorites();
    const pinnedSet = new Set(pinned);
    return pinned.concat(favorites.filter((id: string): boolean => !pinnedSet.has(id)));
  }

  /** 只前移已收藏的书；同步读改写避免进度回调把已移出的书重新加入。 */
  static async promoteFavorite(bookId: string): Promise<void> {
    if (!bookId) return;
    const store = await PreferenceService.ensureStore();
    const raw = store.getSync(KEY_FAVORITES, '[]');
    if (typeof raw !== 'string') return;
    const favorites: string[] = JSON.parse(raw);
    const index = favorites.indexOf(bookId);
    if (index <= 0) return;
    favorites.splice(index, 1);
    favorites.unshift(bookId);
    store.putSync(KEY_FAVORITES, JSON.stringify(favorites));
    await store.flush();
    PreferenceService.notifyFavoriteChanged();
    emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId } });
  }

  static async setFavoritesPinned(bookIds: string[], pinned: boolean): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const favorites = new Set(await PreferenceService.getFavorites());
    const selected = new Set(bookIds.filter((id: string): boolean => favorites.has(id)));
    if (selected.size === 0) return;
    const previous = await s.get(KEY_PINNED_FAVORITES, '[]');
    const remaining = (await PreferenceService.getPinnedFavorites())
      .filter((id: string): boolean => !selected.has(id));
    const next = pinned ? Array.from(selected).concat(remaining) : remaining;
    try {
      await s.put(KEY_PINNED_FAVORITES, JSON.stringify(next));
      await s.flush();
    } catch (error) {
      await s.put(KEY_PINNED_FAVORITES, previous);
      const failure: Error = error;
      throw failure;
    }
    PreferenceService.notifyFavoriteChanged();
    emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId: '' } });
  }

  private static async prunePinnedFavorites(favorites: string[]): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_PINNED_FAVORITES, '[]');
    if (typeof raw !== 'string') return;
    const pinned: string[] = JSON.parse(raw);
    const keep = new Set(favorites);
    const remaining = pinned.filter((id: string): boolean => keep.has(id));
    if (remaining.length !== pinned.length) await s.put(KEY_PINNED_FAVORITES, JSON.stringify(remaining));
  }

  static async toggleFavorite(bookId: string): Promise<boolean> {
    const s = await PreferenceService.ensureStore();
    const list = await PreferenceService.getFavorites();
    const idx = list.indexOf(bookId);
    let added: boolean;
    if (idx >= 0) {
      list.splice(idx, 1);
      added = false;
    } else {
      list.unshift(bookId);
      added = true;
    }
    await s.put(KEY_FAVORITES, JSON.stringify(list));
    await PreferenceService.prunePinnedFavorites(list);
    await s.flush();
    PreferenceService.notifyFavoriteChanged();
    emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId } });
    return added;
  }

  static async removeFavorite(bookId: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const list = await PreferenceService.getFavorites();
    const idx = list.indexOf(bookId);
    if (idx >= 0) {
      list.splice(idx, 1);
      await s.put(KEY_FAVORITES, JSON.stringify(list));
      await PreferenceService.prunePinnedFavorites(list);
      await s.flush();
      PreferenceService.notifyFavoriteChanged();
      emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId } });
    }
  }

  /** 确认换源后保留书架顺序和置顶，原书缓存与阅读记录继续保留。 */
  static async replaceFavoriteSource(oldId: string, newId: string, replace: boolean = true): Promise<void> {
    if (!oldId || !newId || oldId === newId) return;
    const s = await PreferenceService.ensureStore();
    const list = await PreferenceService.getFavorites();
    const replaceExisting = replace && list.includes(oldId);
    const replaced = replaceExisting ? list.filter((id: string): boolean => id !== newId)
      .map((id: string): string => id === oldId ? newId : id) :
      (list.includes(newId) ? list : [newId, ...list]);
    const pinned = await PreferenceService.getPinnedFavorites();
    const nextPinned = Array.from(new Set(pinned.map((id: string): string => replaceExisting && id === oldId ? newId : id)));
    await s.put(KEY_FAVORITES, JSON.stringify(replaced));
    await s.put(KEY_PINNED_FAVORITES, JSON.stringify(nextPinned));
    await s.flush();
    PreferenceService.notifyFavoriteChanged();
    emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId: newId } });
  }

  static async isFavorite(bookId: string): Promise<boolean> {
    const list = await PreferenceService.getFavorites();
    return list.includes(bookId);
  }

  /** 批量移出书架只落盘、通知一次，保留阅读记录、进度及本地文件。 */
  static async removeFavorites(bookIds: string[]): Promise<void> {
    if (bookIds.length === 0) return;
    const selected = new Set<string>(bookIds);
    const s = await PreferenceService.ensureStore();
    const list = await PreferenceService.getFavorites();
    const remaining = list.filter((id: string): boolean => !selected.has(id));
    if (remaining.length === list.length) return;
    await s.put(KEY_FAVORITES, JSON.stringify(remaining));
    await PreferenceService.prunePinnedFavorites(remaining);
    await s.flush();
    PreferenceService.notifyFavoriteChanged();
    emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId: '' } });
  }

  // ===== 华为账号登录身份标识 =====

  static async getHwAccount(): Promise<HwAccount | null> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_HW_ACCOUNT, '');
    if (typeof raw !== 'string' || raw.length === 0 || raw.length > 2048) {
      return null;
    }
    try {
      const parsed: HwAccount | null = JSON.parse(raw);
      if (!parsed || !HwAccount.isValid(parsed)) return null;
      const account = new HwAccount();
      account.unionID = parsed.unionID;
      account.openID = parsed.openID;
      account.loginAt = parsed.loginAt;
      account.nickName = typeof parsed.nickName === 'string' ? parsed.nickName.trim().substring(0, 256) : '';
      account.avatarFile = typeof parsed.avatarFile === 'string' && /^[a-f0-9-]{36}\.img$/.test(parsed.avatarFile)
        ? parsed.avatarFile : '';
      return account;
    } catch (_e) {
      return null;
    }
  }

  static async setHwAccount(account: HwAccount): Promise<void> {
    if (!HwAccount.isValid(account)) throw new Error('Invalid Huawei account');
    await PreferenceService.writeHwAccount(JSON.stringify(account));
  }

  static async clearHwAccount(): Promise<void> {
    await PreferenceService.writeHwAccount('');
  }

  private static async writeHwAccount(raw: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const previous = await s.get(KEY_HW_ACCOUNT, '');
    try {
      if (raw) await s.put(KEY_HW_ACCOUNT, raw);
      else await s.delete(KEY_HW_ACCOUNT);
      await s.flush();
    } catch (_error) {
      // put/delete 先改变 Preferences 内存缓存；落盘失败后回滚，避免下次恢复误报成功。
      try {
        if (typeof previous === 'string' && previous) await s.put(KEY_HW_ACCOUNT, previous);
        else await s.delete(KEY_HW_ACCOUNT);
      } catch (_rollbackError) { /* 仍向调用方报告保存失败。 */ }
      throw new Error('Huawei account persistence failed');
    }
  }

  static async getHistory(): Promise<PlayHistoryItem[]> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_HISTORY, '[]') as string;
    return JSON.parse(raw) as PlayHistoryItem[];
  }

  static async upsertHistory(item: PlayHistoryItem): Promise<void> {
    if (!GeneralSettings.current.historyEnabled) return;
    const s = await PreferenceService.ensureStore();
    const list = await PreferenceService.getHistory();
    const idx = list.findIndex((it) => it.bookId === item.bookId);
    if (idx >= 0) {
      list.splice(idx, 1);
    }
    list.unshift(item);
    if (list.length > 50) {
      list.length = 50;
    }
    await s.put(KEY_HISTORY, JSON.stringify(list));
    await s.flush();
    PreferenceService.notifyHistoryChanged();
  }

  static async removeHistory(bookId: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const list = await PreferenceService.getHistory();
    const filtered = list.filter((it) => it.bookId !== bookId);
    await s.put(KEY_HISTORY, JSON.stringify(filtered));
    await s.flush();
    PreferenceService.notifyHistoryChanged();
  }

  static async setLastPlayed(bookId: string, chapterId: string, progressMs: number = 0,
    chapterTitle?: string, durationMs?: number, speed?: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const item: LastPlayedItem = { bookId, chapterId, progressMs, chapterTitle, durationMs, speed };
    await s.put(KEY_LAST_PLAYED, JSON.stringify(item));
    await s.flush();
  }

  static async getLastPlayed(): Promise<LastPlayedItem | null> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_LAST_PLAYED, '') as string;
    if (!raw) return null;
    try {
      return JSON.parse(raw) as LastPlayedItem;
    } catch (e) {
      return null;
    }
  }

  /**
   * 单本书最新进度。
   * 内存缓存命中时同步返回(快路径,supports 切书前后的快速读写);否则去 store 读。
   */
  private static progressMemo: Map<string, PlayProgress> = new Map();

  static async getProgress(bookId: string): Promise<PlayProgress | null> {
    if (!bookId) return null;
    const memo = PreferenceService.progressMemo.get(bookId);
    if (memo) return memo;
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_PROGRESS_PREFIX + bookId, '') as string;
    if (!raw) return null;
    try {
      const p = JSON.parse(raw) as PlayProgress;
      PreferenceService.progressMemo.set(bookId, p);
      return p;
    } catch (_e) {
      return null;
    }
  }

  static getProgressSync(bookId: string): PlayProgress | null {
    if (!bookId) return null;
    return PreferenceService.progressMemo.get(bookId) ?? null;
  }

  static async saveProgress(p: PlayProgress): Promise<void> {
    if (!p || !p.bookId) return;
    PreferenceService.progressMemo.set(p.bookId, p);
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_PROGRESS_PREFIX + p.bookId, JSON.stringify(p));
    await s.flush();
    await PreferenceService.promoteFavorite(p.bookId).catch((): void => {
      // 书架排序失败不影响已保存的播放进度。
    });
  }

  static async removeProgress(bookId: string): Promise<void> {
    if (!bookId) return;
    PreferenceService.progressMemo.delete(bookId);
    PreferenceService.chapterProgressMemo.delete(bookId);
    const s = await PreferenceService.ensureStore();
    await s.delete(KEY_PROGRESS_PREFIX + bookId);
    await s.delete(KEY_CHAPTER_PROGRESS_PREFIX + bookId);
    const lastPlayed = await PreferenceService.getLastPlayed();
    if (lastPlayed?.bookId === bookId) await s.delete(KEY_LAST_PLAYED);
    await s.flush();
  }

  private static chapterProgressMemo: Map<string, ChapterPlayProgress[]> = new Map();

  private static async loadChapterProgresses(bookId: string): Promise<ChapterPlayProgress[]> {
    const memo = PreferenceService.chapterProgressMemo.get(bookId);
    if (memo !== undefined) return memo;
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_CHAPTER_PROGRESS_PREFIX + bookId, '') as string;
    if (!raw) {
      const empty: ChapterPlayProgress[] = [];
      PreferenceService.chapterProgressMemo.set(bookId, empty);
      return empty;
    }
    try {
      const items = JSON.parse(raw) as ChapterPlayProgress[];
      PreferenceService.chapterProgressMemo.set(bookId, items);
      return items;
    } catch (_e) {
      const empty: ChapterPlayProgress[] = [];
      PreferenceService.chapterProgressMemo.set(bookId, empty);
      return empty;
    }
  }

  static async getChapterProgress(bookId: string, chapterId: string): Promise<ChapterPlayProgress | null> {
    if (!bookId || !chapterId) return null;
    const items = await PreferenceService.loadChapterProgresses(bookId);
    for (const item of items) {
      if (item.chapterId === chapterId) return item;
    }
    return null;
  }

  static async saveChapterProgress(progress: ChapterPlayProgress): Promise<void> {
    if (!progress.bookId || !progress.chapterId) return;
    const saved = await PreferenceService.loadChapterProgresses(progress.bookId);
    const next = saved.filter((item: ChapterPlayProgress): boolean => item.chapterId !== progress.chapterId);
    next.unshift(progress);
    const limited = next.length > MAX_CHAPTER_PROGRESS_PER_BOOK
      ? next.slice(0, MAX_CHAPTER_PROGRESS_PER_BOOK) : next;
    PreferenceService.chapterProgressMemo.set(progress.bookId, limited);
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_CHAPTER_PROGRESS_PREFIX + progress.bookId, JSON.stringify(limited));
    await s.flush();
  }

  /**
   * 跳过头尾(每本书独立)。独立 KV 存储,不依赖缓存书索引。
   * 内存缓存命中同步返回,supports 冷启动恢复时贴回 currentBook。
   */
  private static skipMemo: Map<string, SkipConfig> = new Map();

  static async getSkipConfig(bookId: string): Promise<SkipConfig | null> {
    if (!bookId) return null;
    const memo = PreferenceService.skipMemo.get(bookId);
    if (memo) return memo;
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_SKIP_PREFIX + bookId, '') as string;
    if (!raw) return null;
    try {
      const cfg = JSON.parse(raw) as SkipConfig;
      PreferenceService.skipMemo.set(bookId, cfg);
      return cfg;
    } catch (_e) {
      return null;
    }
  }

  static async saveSkipConfig(bookId: string, skipIntro: number, skipOutro: number): Promise<void> {
    if (!bookId) return;
    const cfg: SkipConfig = { skipIntro: skipIntro || 0, skipOutro: skipOutro || 0 };
    PreferenceService.skipMemo.set(bookId, cfg);
    const s = await PreferenceService.ensureStore();
    // 全 0 视为清除:删掉 key 保持 store 干净,读回落 null → 不覆盖
    if (cfg.skipIntro <= 0 && cfg.skipOutro <= 0) {
      await s.delete(KEY_SKIP_PREFIX + bookId);
    } else {
      await s.put(KEY_SKIP_PREFIX + bookId, JSON.stringify(cfg));
    }
    await s.flush();
  }

  /**
   * 把独立存储里的跳过头尾贴回 book 对象(store 有记录则以 store 为准)。
   * 冷启动恢复 currentBook / PlayerPage 载入书时调用,消除缓存书索引丢 skip 的影响。
   */
  static async applySkipConfig(book: Book | null | undefined): Promise<void> {
    if (!book || !book.id) return;
    await PreferenceService.applyTocOrder(book);
    const cfg = await PreferenceService.getSkipConfig(book.id);
    if (cfg) {
      book.skipIntro = cfg.skipIntro;
      book.skipOutro = cfg.skipOutro;
      return;
    }
    // store 无记录:若 book 自带非零 skip(旧方案存在缓存书壳里),一次性迁移进独立 store,
    // 让老用户无需重新设置,下次冷启动即从权威 store 读回。
    const bi = book.skipIntro ?? 0;
    const bo = book.skipOutro ?? 0;
    if (bi > 0 || bo > 0) {
      await PreferenceService.saveSkipConfig(book.id, bi, bo);
    }
  }

  private static tocOrderMemo: Map<string, boolean> = new Map();

  /** 排序偏好仅控制目录展示；阅读和播放始终按原始章节顺序前进。 */
  private static isTocDescending(book: Book): boolean {
    return PreferenceService.tocOrderMemo.get(book.id) ?? book.chaptersDescending ?? false;
  }

  static orderedChapters(book: Book): Chapter[] {
    const chapters = book.chapters.slice();
    return PreferenceService.isTocDescending(book) ? chapters.reverse() : chapters;
  }

  static chapterDisplayIndex(book: Book, index: number): number {
    if (index < 0) return -1;
    return PreferenceService.isTocDescending(book) ? book.chapters.length - 1 - index : index;
  }

  /** 读取本书的目录顺序;默认正序。 */
  static async getTocOrder(bookId: string): Promise<boolean> {
    if (!bookId) return false;
    const memo = PreferenceService.tocOrderMemo.get(bookId);
    if (memo !== undefined) return memo;
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_TOC_ORDER_PREFIX + bookId, false) as boolean;
    PreferenceService.tocOrderMemo.set(bookId, raw === true);
    return raw === true;
  }

  /** 保存本书的目录顺序;正序视为清除。 */
  static async saveTocOrder(bookId: string, descending: boolean): Promise<void> {
    if (!bookId) return;
    PreferenceService.tocOrderMemo.set(bookId, descending);
    const s = await PreferenceService.ensureStore();
    if (descending) {
      await s.put(KEY_TOC_ORDER_PREFIX + bookId, true);
    } else {
      await s.delete(KEY_TOC_ORDER_PREFIX + bookId);
    }
    await s.flush();
  }

  /** 把独立存储里的目录顺序贴回 book 对象;详情页/播放页/阅读页载入书时调用。 */
  static async applyTocOrder(book: Book | null | undefined): Promise<void> {
    if (!book || !book.id) return;
    book.chaptersDescending = await PreferenceService.getTocOrder(book.id);
  }

  static async getRankingCategories(): Promise<string> {
    const s = await PreferenceService.ensureStore();
    const value = await s.get('ranking_categories_v1', '');
    return typeof value === 'string' ? value : '';
  }

  static async setRankingCategories(value: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put('ranking_categories_v1', value);
    await s.flush();
  }

  static async getColorMode(): Promise<number> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_COLOR_MODE, ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) as number;
  }

  static async setColorMode(mode: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_COLOR_MODE, mode);
    await s.flush();
  }

  static async setMaterialStyle(value: number): Promise<void> {
    return PreferenceService.enqueueAppearanceSave((): AppThemeSelection =>
      new AppThemeSelection(AppAppearance.current.themeBundleId, AppAppearance.current.accent,
        AppAppearance.normalizeMaterial(value)));
  }

  static async setAccentColor(value: string): Promise<void> {
    return PreferenceService.enqueueAppearanceSave((): AppThemeSelection =>
      new AppThemeSelection(AppAppearance.current.themeBundleId, AppAppearance.normalizeAccent(value),
        AppAppearance.current.material));
  }

  static async applyThemeBundle(id: string): Promise<void> {
    if (ThemeBundles.normalizeId(id) !== id) throw new Error('Unknown theme bundle');
    return PreferenceService.enqueueAppearanceSave((): AppThemeSelection => {
      const bundle = ThemeBundles.resolve(id);
      return new AppThemeSelection(bundle.id, bundle.accent, bundle.material);
    });
  }

  static async resetThemeBundleOverrides(): Promise<void> {
    return PreferenceService.enqueueAppearanceSave((): AppThemeSelection => {
      const bundle = ThemeBundles.resolve(AppAppearance.current.themeBundleId);
      return new AppThemeSelection(bundle.id, bundle.accent, bundle.material);
    });
  }

  private static decodeThemeSelection(raw: string, legacyAccent: string, legacyMaterial: number): AppThemeSelection {
    const fallback = new AppThemeSelection(ThemeBundles.DefaultId,
      AppAppearance.normalizeAccent(legacyAccent), AppAppearance.normalizeMaterial(legacyMaterial));
    if (raw.length === 0 || raw.length > 2048) return fallback;
    try {
      const decoded: AppThemeSelection | null = JSON.parse(raw);
      if (decoded === null || typeof decoded !== 'object' || decoded.schemaVersion !== 1 ||
        typeof decoded.themeBundleId !== 'string' || typeof decoded.accentColor !== 'string' ||
        typeof decoded.materialStyle !== 'number') return fallback;
      return new AppThemeSelection(ThemeBundles.normalizeId(decoded.themeBundleId),
        AppAppearance.normalizeAccent(decoded.accentColor), AppAppearance.normalizeMaterial(decoded.materialStyle));
    } catch (_error) {
      return fallback;
    }
  }

  private static publishThemeSelection(selection: AppThemeSelection): void {
    AppAppearance.current.themeBundleId = selection.themeBundleId;
    AppAppearance.current.accent = selection.accentColor;
    AppAppearance.current.material = selection.materialStyle;
  }

  /** 在队列内读取当前外观，避免连续调色/切套装覆盖刚保存的其他字段。 */
  private static enqueueAppearanceSave(create: () => AppThemeSelection): Promise<void> {
    const task: Promise<void> = PreferenceService.appearanceSave.then(async (): Promise<void> => {
      const store = await PreferenceService.ensureStore();
      const selection: AppThemeSelection = create();
      const previous = await store.get(KEY_THEME_SELECTION, '');
      try {
        await store.put(KEY_THEME_SELECTION, JSON.stringify(selection));
        await store.flush();
      } catch (error) {
        // 同时回滚 Preferences 内存值，后续其他设置 flush 也不会提交失败的主题。
        await store.put(KEY_THEME_SELECTION, previous);
        throw new Error(error instanceof Error ? error.message : 'Theme preferences save failed');
      }
      PreferenceService.publishThemeSelection(selection);
    });
    PreferenceService.appearanceSave = task.catch((): void => {});
    return task;
  }

  static async getImportedBooks(): Promise<string> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_IMPORTED_BOOKS, '[]') as string;
  }

  static async saveImportedBooks(json: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_IMPORTED_BOOKS, json);
    await s.flush();
  }

  static async getDefaultTab(): Promise<number> {
    const s = await PreferenceService.ensureStore();
    const idx = await s.get(KEY_DEFAULT_TAB, 0);
    if (typeof idx !== 'number' || !Number.isInteger(idx) || idx < 0 || idx > 3) return 0;
    return idx;
  }

  static async getShelfGroup(): Promise<string> {
    const store = await PreferenceService.ensureStore();
    const value = await store.get('shelf_selected_group', '');
    return typeof value === 'string' ? value : '';
  }

  static async getShelfViewMode(): Promise<number> {
    const store = await PreferenceService.ensureStore();
    const value = await store.get('shelf_view_mode', 0);
    return value === 1 ? 1 : 0;
  }

  static async setShelfViewMode(mode: number): Promise<void> {
    const store = await PreferenceService.ensureStore();
    await store.put('shelf_view_mode', mode === 1 ? 1 : 0);
    await store.flush();
  }

  static async setShelfGroup(group: string): Promise<void> {
    const store = await PreferenceService.ensureStore();
    await store.put('shelf_selected_group', group);
    await store.flush();
  }

  static async getShelfStatusFilter(): Promise<number> {
    const store = await PreferenceService.ensureStore();
    const value = await store.get(KEY_SHELF_STATUS_FILTER, 0);
    return value === 1 || value === 2 ? value : 0;
  }

  static async setShelfStatusFilter(value: number): Promise<void> {
    const store = await PreferenceService.ensureStore();
    await store.put(KEY_SHELF_STATUS_FILTER, value === 1 || value === 2 ? value : 0);
    await store.flush();
  }

  static async setDefaultTab(idx: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_DEFAULT_TAB, idx);
    await s.flush();
  }

  static async getPrivacyAgreedVersion(): Promise<string> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_PRIVACY_AGREED_VERSION, '') as string;
  }

  static async setPrivacyAgreedVersion(version: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_PRIVACY_AGREED_VERSION, version);
    await s.flush();
  }

  static normalizeDefaultPlaybackSpeed(speed: number | undefined): number {
    if (typeof speed !== 'number' || !Number.isFinite(speed) || speed <= 0) return 1;
    return Math.round(Math.max(0.5, Math.min(3, speed)) * 20) / 20;
  }

  /** 仅供没有单本倍速记录的有声书起播时使用，不修改正在播放的书。 */
  static async getDefaultPlaybackSpeed(): Promise<number> {
    const store = await PreferenceService.ensureStore();
    const value = await store.get(KEY_DEFAULT_PLAYBACK_SPEED, 1);
    return PreferenceService.normalizeDefaultPlaybackSpeed(typeof value === 'number' ? value : undefined);
  }

  static async setDefaultPlaybackSpeed(speed: number): Promise<void> {
    const store = await PreferenceService.ensureStore();
    const previous = await store.get(KEY_DEFAULT_PLAYBACK_SPEED, 1);
    try {
      await store.put(KEY_DEFAULT_PLAYBACK_SPEED, PreferenceService.normalizeDefaultPlaybackSpeed(speed));
      await store.flush();
    } catch (error) {
      await store.put(KEY_DEFAULT_PLAYBACK_SPEED, previous);
      const failure: Error = error;
      throw failure;
    }
  }

  /** 0=共享焦点（默认，听书与其他音乐互斥）, 1=独立焦点（不与本应用其他音频互斥） */
  static async getAudioInterruptMode(): Promise<number> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_AUDIO_INTERRUPT_MODE, 0) as number;
  }

  static async setAudioInterruptMode(mode: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_AUDIO_INTERRUPT_MODE, mode);
    await s.flush();
  }

  /** 打开应用时续播上次内容；新安装和旧版本升级默认关闭。 */
  static async getAutoSleepEnabled(): Promise<boolean> {
    const store = await PreferenceService.ensureStore();
    return (await store.get('auto_sleep_enabled', false)) === true;
  }

  static async setAutoSleepEnabled(enabled: boolean): Promise<void> {
    const store = await PreferenceService.ensureStore();
    await store.put('auto_sleep_enabled', enabled);
    await store.flush();
  }

  static async getLastSleepMode(): Promise<number> {
    const store = await PreferenceService.ensureStore();
    return (await store.get('last_sleep_mode', 1)) === 2 ? 2 : 1;
  }

  static async getLastSleepChapters(): Promise<number> {
    const store = await PreferenceService.ensureStore();
    const value = await store.get('last_sleep_chapters', 1);
    return typeof value === 'number' && Number.isInteger(value) && value >= 1 && value <= 999 ? value : 1;
  }

  static async setLastSleepChapters(count: number): Promise<void> {
    if (!Number.isInteger(count) || count < 1 || count > 999) return;
    const store = await PreferenceService.ensureStore();
    await store.put('last_sleep_chapters', count);
    await store.put('last_sleep_mode', 2);
    await store.flush();
  }

  static async getLastSleepMinutes(): Promise<number> {
    const store = await PreferenceService.ensureStore();
    const value = await store.get('last_sleep_minutes', 30);
    return typeof value === 'number' && Number.isInteger(value) && value >= 1 && value <= 1440 ? value : 30;
  }

  static async setLastSleepMinutes(minutes: number): Promise<void> {
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 1440) return;
    const store = await PreferenceService.ensureStore();
    await store.put('last_sleep_minutes', minutes);
    await store.put('last_sleep_mode', 1);
    await store.flush();
  }

  static async getAutoPlayOnLaunch(): Promise<boolean> {
    const store = await PreferenceService.ensureStore();
    return (await store.get(KEY_AUTO_PLAY_ON_LAUNCH, false)) === true;
  }

  static async getCoverSuperResolution(): Promise<boolean> {
    const store = await PreferenceService.ensureStore();
    return (await store.get(KEY_COVER_SUPER_RESOLUTION, false)) === true;
  }

  static async getComicSuperResolution(): Promise<boolean> {
    const store = await PreferenceService.ensureStore();
    return (await store.get('comicSuperResolution', false)) === true;
  }

  static async setComicSuperResolution(enabled: boolean): Promise<void> {
    const store = await PreferenceService.ensureStore();
    const previous = await store.get('comicSuperResolution', false);
    try {
      await store.put('comicSuperResolution', enabled);
      await store.flush();
    } catch (error) {
      await store.put('comicSuperResolution', previous);
      throw new Error(`Failed to save comic super resolution preference: ${String(error)}`);
    }
  }

  static async setCoverSuperResolution(enabled: boolean): Promise<void> {
    const store = await PreferenceService.ensureStore();
    const previous = await store.get(KEY_COVER_SUPER_RESOLUTION, false);
    try {
      await store.put(KEY_COVER_SUPER_RESOLUTION, enabled);
      await store.flush();
    } catch (error) {
      await store.put(KEY_COVER_SUPER_RESOLUTION, previous);
      throw new Error(`Failed to save cover super resolution preference: ${String(error)}`);
    }
    emitter.emit(EVT_COVER_SUPER_RESOLUTION_CHANGED);
  }

  static async setAutoPlayOnLaunch(enabled: boolean): Promise<void> {
    const store = await PreferenceService.ensureStore();
    await store.put(KEY_AUTO_PLAY_ON_LAUNCH, enabled);
    await store.flush();
  }

  /** 失去焦点暂停后，是否在系统通知 RESUME 时自动恢复播放 */
  static async getAudioAutoResume(): Promise<boolean> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_AUDIO_AUTO_RESUME, true) as boolean;
  }

  static async setAudioAutoResume(enabled: boolean): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_AUDIO_AUTO_RESUME, enabled);
    await s.flush();
  }

  /** 首页默认听书源，以导入源 URL 持久化。 */
  static async getHomeSourceUrl(): Promise<string> {
    const store = await PreferenceService.ensureStore();
    const value = await store.get(KEY_HOME_SOURCE_URL, '');
    return typeof value === 'string' ? value : '';
  }

  static async setHomeSourceUrl(sourceUrl: string): Promise<void> {
    const store = await PreferenceService.ensureStore();
    await store.put(KEY_HOME_SOURCE_URL, sourceUrl);
    await store.flush();
    emitter.emit(EVT_HOME_SOURCE_CHANGED);
  }

  /** 首页切源弹框列数，与首页书籍栅格设置独立。 */
  static async getHomeSourceMenuColumns(): Promise<number> {
    const store = await PreferenceService.ensureStore();
    const value = await store.get(KEY_HOME_SOURCE_MENU_COLUMNS, 1);
    return value === 2 ? 2 : 1;
  }

  static async setHomeSourceMenuColumns(columns: number): Promise<void> {
    const store = await PreferenceService.ensureStore();
    await store.put(KEY_HOME_SOURCE_MENU_COLUMNS, columns === 2 ? 2 : 1);
    await store.flush();
  }

  /** 首页书籍栅格列数：1 / 2 / 3，默认 3 */
  static async getHomeGridColumns(): Promise<number> {
    const s = await PreferenceService.ensureStore();
    const v = await s.get(KEY_HOME_GRID_COLUMNS, 3) as number;
    if (v < 1) return 1;
    if (v > 3) return 3;
    return v;
  }

  static async setHomeGridColumns(cols: number): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const clamped = cols < 1 ? 1 : (cols > 3 ? 3 : cols);
    await s.put(KEY_HOME_GRID_COLUMNS, clamped);
    await s.flush();
  }

  /** 缓存书池：来自搜索 / 在线源的书籍快照,用于让收藏 + 历史能在书架/历史页找到对应 Book */
  static async getCachedBooks(): Promise<string> {
    const s = await PreferenceService.ensureStore();
    return await s.get(KEY_CACHED_BOOKS, '[]') as string;
  }

  static async putCachedBookJson(json: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_CACHED_BOOKS, json);
    await s.flush();
  }

  /**
   * 清空"书架 + 播放记录":收藏 / 历史 / 每本进度 / 上次播放 / 卡片快照 / 旧缓存池。
   * 保留:应用设置、登录信息、卡片 formId 等其余偏好。
   */
  static async clearBookshelfAndHistory(): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.delete(KEY_FAVORITES);
    await s.delete(KEY_PINNED_FAVORITES);
    await s.delete(KEY_HISTORY);
    await s.delete(KEY_LAST_PLAYED);
    await s.delete(KEY_WIDGET_PLAYER_SNAPSHOT);
    await s.delete(KEY_CACHED_BOOKS);
    // 逐本进度 progress_v1_* + 逐本跳过头尾 skip_v1_*:枚举全部 key,前缀匹配删除
    try {
      const all = await s.getAll() as Record<string, Object>;
      for (const key of Object.keys(all)) {
        if (key.startsWith(KEY_PROGRESS_PREFIX) || key.startsWith(KEY_CHAPTER_PROGRESS_PREFIX)
          || key.startsWith(KEY_SKIP_PREFIX)) {
          await s.delete(key);
        }
      }
    } catch (_e) { /* ignore */ }
    PreferenceService.progressMemo.clear();
    PreferenceService.chapterProgressMemo.clear();
    PreferenceService.skipMemo.clear();
    await s.flush();
    PreferenceService.notifyFavoriteChanged();
    PreferenceService.notifyHistoryChanged();
    emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId: '' } });
  }

  /** 清空在线收藏与播放记录，保留本地导入书的收藏和每本书的跳过头尾设置。 */
  static async clearOnlineFavoritesAndHistory(): Promise<void> {
    const s = await PreferenceService.ensureStore();
    // 保留 import_* 收藏 ID
    const ids = await PreferenceService.getFavorites();
    const importIds = ids.filter((id: string) => id.startsWith('import_'));
    await s.put(KEY_FAVORITES, JSON.stringify(importIds));
    await PreferenceService.prunePinnedFavorites(importIds);
    await s.delete(KEY_HISTORY);
    await s.delete(KEY_LAST_PLAYED);
    await s.delete(KEY_WIDGET_PLAYER_SNAPSHOT);
    await s.delete(KEY_CACHED_BOOKS);
    // 仅删 progress_v1_*，保留 skip_v1_*
    try {
      const all = await s.getAll() as Record<string, Object>;
      for (const key of Object.keys(all)) {
        if (key.startsWith(KEY_PROGRESS_PREFIX) || key.startsWith(KEY_CHAPTER_PROGRESS_PREFIX)) {
          await s.delete(key);
        }
      }
    } catch (_e) { /* ignore */ }
    PreferenceService.progressMemo.clear();
    PreferenceService.chapterProgressMemo.clear();
    // skipMemo 不清——跳过头尾设置是用户主动配置
    await s.flush();
    PreferenceService.notifyFavoriteChanged();
    PreferenceService.notifyHistoryChanged();
    emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId: '' } });
  }

  /** 卡片快照:主进程写,FormExtensionAbility 在 onAddForm/onUpdateForm 里读 */
  static async getWidgetPlayerSnapshot(): Promise<WidgetPlayerSnapshot | null> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_WIDGET_PLAYER_SNAPSHOT, '') as string;
    if (!raw) return null;
    try {
      return JSON.parse(raw) as WidgetPlayerSnapshot;
    } catch (_e) {
      return null;
    }
  }

  static async setWidgetPlayerSnapshot(snap: WidgetPlayerSnapshot): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_WIDGET_PLAYER_SNAPSHOT, JSON.stringify(snap));
    await s.flush();
  }

  /** 已添加到桌面的卡片 formId 列表(按卡片名 name 分桶) */
  static async getWidgetFormIds(name: string): Promise<string[]> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_WIDGET_FORM_IDS, '[]') as string;
    const arr = JSON.parse(raw) as FormIdBucket[];
    const bucket = arr.find((b) => b.name === name);
    return bucket ? bucket.ids.slice() : [];
  }

  static async addWidgetFormId(name: string, formId: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_WIDGET_FORM_IDS, '[]') as string;
    const arr = JSON.parse(raw) as FormIdBucket[];
    let bucket = arr.find((b) => b.name === name);
    if (!bucket) {
      bucket = { name, ids: [] };
      arr.push(bucket);
    }
    if (!bucket.ids.includes(formId)) {
      bucket.ids.push(formId);
    }
    await s.put(KEY_WIDGET_FORM_IDS, JSON.stringify(arr));
    await s.flush();
  }

  static async removeWidgetFormId(name: string, formId: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_WIDGET_FORM_IDS, '[]') as string;
    const arr = JSON.parse(raw) as FormIdBucket[];
    const bucket = arr.find((b) => b.name === name);
    if (!bucket) return;
    bucket.ids = bucket.ids.filter((id) => id !== formId);
    await s.put(KEY_WIDGET_FORM_IDS, JSON.stringify(arr));
    await s.flush();
  }

  static async getPreloadChapters(): Promise<number> {
    const s = await PreferenceService.ensureStore();
    const count = await s.get(KEY_PRELOAD_CHAPTERS, 1) as number;
    if (Number.isInteger(count) && count >= 0 && count <= 50) {
      return count;
    }
    return 1;
  }

  static async setPreloadChapters(count: number): Promise<void> {
    if (!Number.isInteger(count) || count < 0 || count > 50) throw new Error('Invalid preload count');
    const s = await PreferenceService.ensureStore();
    const previous = await PreferenceService.getPreloadChapters();
    await s.put(KEY_PRELOAD_CHAPTERS, count);
    try {
      await s.flush();
    } catch (error) {
      await s.put(KEY_PRELOAD_CHAPTERS, previous);
      throw new Error(String(error));
    }
  }

  static async getSearchConcurrency(): Promise<number> {
    const s = await PreferenceService.ensureStore();
    if (!await MembershipService.instance.hasCurrentEntitlement()) {
      const previous = await s.get(KEY_SEARCH_CONCURRENCY, 3);
      if (previous !== 3) {
        await s.put(KEY_SEARCH_CONCURRENCY, 3);
        try { await s.flush(); } catch (_error) { /* 本次搜索仍只使用默认并发。 */ }
      }
      return 3;
    }
    const count = await s.get(KEY_SEARCH_CONCURRENCY, 3);
    return typeof count === 'number' && Number.isInteger(count) && count >= 1 && count <= 12 ? count : 3;
  }

  static async setSearchConcurrency(count: number): Promise<void> {
    if (!Number.isInteger(count) || count < 1 || count > 12) {
      throw new Error('Search concurrency must be an integer from 1 to 12');
    }
    const s = await PreferenceService.ensureStore();
    if (count !== 3 && !await MembershipService.instance.hasCurrentEntitlement()) {
      throw new Error('MEMBERSHIP_REQUIRED');
    }
    const previous = await s.get(KEY_SEARCH_CONCURRENCY, 3);
    await s.put(KEY_SEARCH_CONCURRENCY, count);
    try {
      await s.flush();
    } catch (error) {
      await s.put(KEY_SEARCH_CONCURRENCY, previous);
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  /** 获取搜索历史 */
  static async setSearchHistory(history: string[]): Promise<void> {
    if (!GeneralSettings.current.historyEnabled) return;
    const s = await PreferenceService.ensureStore();
    await s.put(KEY_SEARCH_HISTORY, JSON.stringify(history.slice(0, MAX_SEARCH_HISTORY)));
    await s.flush();
  }

  static async getSearchExact(): Promise<boolean> {
    const s = await PreferenceService.ensureStore();
    return s.get('search_exact', false).then((value): boolean => value === true);
  }

  static async getSearchByAuthor(): Promise<boolean> {
    const s = await PreferenceService.ensureStore();
    return s.get('search_by_author', false).then((value): boolean => value === true);
  }

  static async getSearchTextOnly(): Promise<boolean> {
    const s = await PreferenceService.ensureStore();
    return s.get('search_text_only', false).then((value): boolean => value === true);
  }

  static async getSearchAudioOnly(): Promise<boolean> {
    const s = await PreferenceService.ensureStore();
    return s.get('search_audio_only', false).then((value): boolean => value === true);
  }

  static async getSearchComicOnly(): Promise<boolean> {
    const s = await PreferenceService.ensureStore();
    return s.get('search_comic_only', false).then((value): boolean => value === true);
  }

  static async setSearchOptions(exact: boolean, byAuthor: boolean,
    textOnly: boolean = false, audioOnly: boolean = false, comicOnly: boolean = false): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.put('search_exact', exact);
    await s.put('search_by_author', byAuthor);
    await s.put('search_text_only', textOnly);
    await s.put('search_audio_only', audioOnly);
    await s.put('search_comic_only', comicOnly);
    await s.flush();
  }

  static async getSearchHistory(): Promise<string[]> {
    if (!GeneralSettings.current.historyEnabled) return [];
    const s = await PreferenceService.ensureStore();
    const raw = await s.get(KEY_SEARCH_HISTORY, '[]') as string;
    try {
      return JSON.parse(raw) as string[];
    } catch (_e) {
      return [];
    }
  }

  /** 添加搜索历史 */
  static async addSearchHistory(keyword: string): Promise<void> {
    if (!GeneralSettings.current.historyEnabled) return;
    if (!keyword || keyword.trim().length === 0) return;
    const s = await PreferenceService.ensureStore();
    const list = await PreferenceService.getSearchHistory();
    const trimmed = keyword.trim();
    const idx = list.indexOf(trimmed);
    if (idx >= 0) {
      list.splice(idx, 1);
    }
    list.unshift(trimmed);
    if (list.length > MAX_SEARCH_HISTORY) {
      list.length = MAX_SEARCH_HISTORY;
    }
    await s.put(KEY_SEARCH_HISTORY, JSON.stringify(list));
    await s.flush();
  }

  /** 删除单条搜索历史 */
  static async removeSearchHistory(keyword: string): Promise<void> {
    const s = await PreferenceService.ensureStore();
    const list = await PreferenceService.getSearchHistory();
    const filtered = list.filter((item: string) => item !== keyword);
    await s.put(KEY_SEARCH_HISTORY, JSON.stringify(filtered));
    await s.flush();
  }

  /** 清空全部搜索历史 */
  static async clearSearchHistory(): Promise<void> {
    const s = await PreferenceService.ensureStore();
    await s.delete(KEY_SEARCH_HISTORY);
    await s.flush();
  }

  /** 导出允许跨设备迁移的白名单偏好，不包含账号、卡片和本地导入数据。 */
  static async exportBackupSnapshot(): Promise<PreferenceBackupSnapshot> {
    await PreferenceService.appearanceSave;
    const snapshot = new PreferenceBackupSnapshot();
    snapshot.descendingBookIds = [];
    snapshot.favorites = (await PreferenceService.getFavorites())
      .filter((id: string) => !id.startsWith('import_'));
    snapshot.pinnedFavorites = (await PreferenceService.getPinnedFavorites())
      .filter((id: string): boolean => !id.startsWith('import_'));
    snapshot.history = (await PreferenceService.getHistory())
      .filter((item: PlayHistoryItem): boolean => !!item && typeof item.bookId === 'string' &&
        !item.bookId.startsWith('import_'));
    const lastPlayed = await PreferenceService.getLastPlayed();
    snapshot.lastPlayed = lastPlayed && typeof lastPlayed.bookId === 'string' &&
      !lastPlayed.bookId.startsWith('import_') ? lastPlayed : null;
    snapshot.colorMode = await PreferenceService.getColorMode();
    snapshot.materialStyle = AppAppearance.current.material;
    snapshot.accentColor = AppAppearance.current.accent;
    snapshot.themeSelection = new AppThemeSelection(AppAppearance.current.themeBundleId,
      AppAppearance.current.accent, AppAppearance.current.material);
    snapshot.defaultTab = await PreferenceService.getDefaultTab();
    snapshot.autoPlayOnLaunch = await PreferenceService.getAutoPlayOnLaunch();
    snapshot.audioInterruptMode = await PreferenceService.getAudioInterruptMode();
    snapshot.audioAutoResume = await PreferenceService.getAudioAutoResume();
    snapshot.defaultPlaybackSpeed = await PreferenceService.getDefaultPlaybackSpeed();
    snapshot.homeGridColumns = await PreferenceService.getHomeGridColumns();
    snapshot.preloadChapters = await PreferenceService.getPreloadChapters();
    snapshot.searchConcurrency = await PreferenceService.getSearchConcurrency();
    const s = await PreferenceService.ensureStore();
    const all = await s.getAll() as Record<string, Object>;
    for (const key of Object.keys(all)) {
      if (key.startsWith(KEY_PROGRESS_PREFIX)) {
        const bookId = key.substring(KEY_PROGRESS_PREFIX.length);
        if (bookId.startsWith('import_')) continue;
        const progress = await PreferenceService.getProgress(bookId);
        if (progress) snapshot.progresses.push(progress);
      } else if (key.startsWith(KEY_TOC_ORDER_PREFIX)) {
        const bookId = key.substring(KEY_TOC_ORDER_PREFIX.length);
        if (bookId && !bookId.startsWith('import_') && await PreferenceService.getTocOrder(bookId)) {
          snapshot.descendingBookIds.push(bookId);
        }
      } else if (key.startsWith(KEY_SKIP_PREFIX)) {
        const bookId = key.substring(KEY_SKIP_PREFIX.length);
        if (bookId.startsWith('import_')) continue;
        const config = await PreferenceService.getSkipConfig(bookId);
        if (config) {
          const backup = new BookSkipBackup();
          backup.bookId = bookId;
          backup.skipIntro = config.skipIntro;
          backup.skipOutro = config.skipOutro;
          snapshot.skipConfigs.push(backup);
        }
      }
    }
    return snapshot;
  }

  /** 恢复跨设备偏好，保留目标设备已有的本地导入书数据。 */
  static async restoreBackupSnapshot(snapshot: PreferenceBackupSnapshot): Promise<void> {
    await PreferenceService.appearanceSave;
    const s = await PreferenceService.ensureStore();
    const localFavorites = (await PreferenceService.getFavorites())
      .filter((id: string) => id.startsWith('import_'));
    const existingPins = await PreferenceService.getPinnedFavorites();
    const localHistory = (await PreferenceService.getHistory())
      .filter((item: PlayHistoryItem) => item.bookId.startsWith('import_'));
    const restoredFavorites = snapshot.favorites
      .filter((id: string) => !!id && !id.startsWith('import_'));
    const restoredHistory = snapshot.history
      .filter((item: PlayHistoryItem) => !!item && !!item.bookId && !item.bookId.startsWith('import_'));
    await s.put(KEY_FAVORITES, JSON.stringify(localFavorites.concat(restoredFavorites)));
    const restoredPins = snapshot.pinnedFavorites ?? existingPins;
    const nextPins = existingPins.filter((id: string): boolean => localFavorites.includes(id))
      .concat(restoredPins.filter((id: string): boolean => restoredFavorites.includes(id)));
    await s.put(KEY_PINNED_FAVORITES, JSON.stringify(Array.from(new Set(nextPins))));
    await s.put(KEY_HISTORY, JSON.stringify(localHistory.concat(restoredHistory).slice(0, 50)));
    if (snapshot.lastPlayed && !snapshot.lastPlayed.bookId.startsWith('import_')) {
      await s.put(KEY_LAST_PLAYED, JSON.stringify(snapshot.lastPlayed));
    } else {
      await s.delete(KEY_LAST_PLAYED);
    }

    const all = await s.getAll() as Record<string, Object>;
    for (const key of Object.keys(all)) {
      if (key.startsWith(KEY_PROGRESS_PREFIX)) {
        const bookId = key.substring(KEY_PROGRESS_PREFIX.length);
        if (!bookId.startsWith('import_')) await s.delete(key);
      } else if (snapshot.descendingBookIds !== undefined && key.startsWith(KEY_TOC_ORDER_PREFIX)) {
        const bookId = key.substring(KEY_TOC_ORDER_PREFIX.length);
        if (!bookId.startsWith('import_')) await s.delete(key);
      } else if (key.startsWith(KEY_CHAPTER_PROGRESS_PREFIX)) {
        const bookId = key.substring(KEY_CHAPTER_PROGRESS_PREFIX.length);
        if (!bookId.startsWith('import_')) await s.delete(key);
      } else if (key.startsWith(KEY_SKIP_PREFIX)) {
        const bookId = key.substring(KEY_SKIP_PREFIX.length);
        if (!bookId.startsWith('import_')) await s.delete(key);
      }
    }
    PreferenceService.progressMemo.clear();
    PreferenceService.chapterProgressMemo.clear();
    PreferenceService.skipMemo.clear();
    if (snapshot.descendingBookIds !== undefined) {
      PreferenceService.tocOrderMemo.clear();
      for (const bookId of snapshot.descendingBookIds) {
        if (!bookId || bookId.startsWith('import_')) continue;
        PreferenceService.tocOrderMemo.set(bookId, true);
        await s.put(KEY_TOC_ORDER_PREFIX + bookId, true);
      }
    }
    for (const progress of snapshot.progresses) {
      if (!progress || !progress.bookId || progress.bookId.startsWith('import_')) continue;
      PreferenceService.progressMemo.set(progress.bookId, progress);
      await s.put(KEY_PROGRESS_PREFIX + progress.bookId, JSON.stringify(progress));
    }
    for (const skip of snapshot.skipConfigs) {
      if (!skip || !skip.bookId || skip.bookId.startsWith('import_')) continue;
      const config: SkipConfig = { skipIntro: skip.skipIntro, skipOutro: skip.skipOutro };
      PreferenceService.skipMemo.set(skip.bookId, config);
      await s.put(KEY_SKIP_PREFIX + skip.bookId, JSON.stringify(config));
    }

    const material: number = AppAppearance.normalizeMaterial(snapshot.materialStyle ?? 0);
    const accent: string = AppAppearance.normalizeAccent(snapshot.accentColor ?? '');
    const selection: AppThemeSelection = PreferenceService.decodeThemeSelection(
      snapshot.themeSelection === undefined ? '' : JSON.stringify(snapshot.themeSelection), accent, material);
    const previousTheme = await s.get(KEY_THEME_SELECTION, '');
    await s.put(KEY_COLOR_MODE, snapshot.colorMode);
    await s.put(KEY_DEFAULT_TAB, snapshot.defaultTab);
    await s.put(KEY_AUTO_PLAY_ON_LAUNCH, snapshot.autoPlayOnLaunch === true);
    await s.put(KEY_AUDIO_INTERRUPT_MODE, snapshot.audioInterruptMode);
    await s.put(KEY_AUDIO_AUTO_RESUME, snapshot.audioAutoResume);
    await s.put(KEY_DEFAULT_PLAYBACK_SPEED,
      PreferenceService.normalizeDefaultPlaybackSpeed(snapshot.defaultPlaybackSpeed));
    await s.put(KEY_HOME_GRID_COLUMNS, snapshot.homeGridColumns);
    await s.put(KEY_PRELOAD_CHAPTERS, Number.isFinite(snapshot.preloadChapters) ?
      Math.max(0, Math.min(50, Math.round(snapshot.preloadChapters))) : 1);
    await s.put(KEY_SEARCH_CONCURRENCY, MembershipState.current.hasAccess && typeof snapshot.searchConcurrency === 'number' &&
      Number.isInteger(snapshot.searchConcurrency) && snapshot.searchConcurrency >= 1 &&
      snapshot.searchConcurrency <= 12 ? snapshot.searchConcurrency : 3);
    try {
      await s.put(KEY_THEME_SELECTION, JSON.stringify(selection));
      await s.flush();
    } catch (error) {
      await s.put(KEY_THEME_SELECTION, previousTheme);
      throw new Error(error instanceof Error ? error.message : 'Theme preferences restore failed');
    }
    PreferenceService.publishThemeSelection(selection);
    PreferenceService.notifyFavoriteChanged();
    PreferenceService.notifyHistoryChanged();
    emitter.emit(EVT_FAVORITES_CHANGED, { data: { bookId: '' } });
  }

}
