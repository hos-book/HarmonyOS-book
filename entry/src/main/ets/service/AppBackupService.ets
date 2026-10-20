import { MedalSnapshot } from '../model/Medal';
import { MedalService } from './MedalService';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { Book } from '../model/Book';
import {
  LocalRuleBookInfoRule,
  LocalRuleContentRule,
  LocalRuleSearchRule,
  LocalRuleSource,
  LocalRuleSourceStatus,
  LocalRuleSourceType,
  LocalRuleTocRule
} from '../model/LocalRuleSource';
import {
  LastPlayedItem, PlayHistoryItem, PlayProgress, PreferenceBackupSnapshot, PreferenceService
} from './PreferenceService';
import { BookUsageStats, StatsService } from './StatsService';
import { DataService } from './DataService';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';
import { LocalRuleSourceImportService } from './rulesource/LocalRuleSourceImportService';
import { GuangYuSourceIdentity } from './rulesource/guangyu/GuangYuSourceIdentity';
import { ShuShanSourceIdentity } from './rulesource/shushan/ShuShanSourceIdentity';
import { SourceDataService } from './SourceDataService';
import { DiagnosticLogService } from './DiagnosticLogService';
import { ReadingBackupService, ReadingBackupSnapshot } from './text/ReadingBackupService';

const BACKUP_DIR: string = 'backup';
const BACKUP_FILE: string = 'listenbook_state.json';
const BACKUP_VERSION: number = 2;
const MAX_BACKUP_BYTES: number = 32 * 1024 * 1024;

/** 已发布旧版在 Preferences 中写入的混淆字段；只用于导出时恢复标准字段。 */
class LegacyPlaybackFields {
  h15?: number;
  q11?: number;
  c10?: number;
  h26?: number;
  m56?: number;
  l50?: number;
  n49?: number;
  x47?: number;
  u47?: number;
}

/** 保存可迁移的解析定义；请求头会清洗，运行期 Cookie 和原始书源 JSON 不进入备份。 */
class BackupRuleSource {
  bookSourceUrl: string = '';
  bookSourceName: string = '';
  bookSourceType: number = LocalRuleSourceType.TEXT;
  bookSourceGroup: string = '';
  bookSourceComment: string = '';
  enabled: boolean = true;
  enabledExplore: boolean = false;
  isLocked: boolean | undefined = false;
  isPinned: boolean | undefined = false;
  customOrder: number | undefined = 0;
  enabledCookieJar: boolean = true;
  searchUrl: string = '';
  exploreUrl: string = '';
  header: string = '';
  loginUrl: string = '';
  loginUi: string = '';
  loginCheckJs: string = '';
  jsLib: string = '';
  variable: string = '';
  respondTime: number = 18000;
  concurrentRate: string = '';
  lastUpdateTime: number = 0;
  validationStatus: number = LocalRuleSourceStatus.UNCHECKED;
  validationMessage: string = '';
  ruleSearch: LocalRuleSearchRule | undefined = undefined;
  ruleExplore: LocalRuleSearchRule | undefined = undefined;
  ruleBookInfo: LocalRuleBookInfoRule | undefined = undefined;
  ruleToc: LocalRuleTocRule | undefined = undefined;
  ruleContent: LocalRuleContentRule | undefined = undefined;
}

export class AppBackupSnapshot {
  version: number = BACKUP_VERSION;
  exportedAt: number = 0;
  preferences: PreferenceBackupSnapshot = new PreferenceBackupSnapshot();
  stats: BookUsageStats[] = [];
  medals: MedalSnapshot | undefined = undefined;
  books: Book[] = [];
  ruleSources: BackupRuleSource[] = [];
  reading: ReadingBackupSnapshot | undefined = undefined;
}

export class AppBackupService {
  private static backupDir(context: common.Context): string {
    return `${context.filesDir}/${BACKUP_DIR}`;
  }

  private static backupPath(context: common.Context): string {
    return `${AppBackupService.backupDir(context)}/${BACKUP_FILE}`;
  }

  static async createSnapshot(context: common.Context, outputPath: string = '', strict: boolean = false): Promise<void> {
    let stage = 'preferences';
    try {
      await PreferenceService.init(context);
      DataService.setContext(context);
      const snapshot = new AppBackupSnapshot();
      snapshot.exportedAt = Date.now();
      snapshot.preferences = AppBackupService.normalizePlaybackSnapshot(await PreferenceService.exportBackupSnapshot());
      stage = 'stats';
      snapshot.stats = (await StatsService.exportBackupStats(context))
        .filter((item: BookUsageStats): boolean => AppBackupService.validStats(item));
      stage = 'medals';
      snapshot.medals = await MedalService.instance.exportSnapshot(context,
        snapshot.stats.reduce((total: number, item: BookUsageStats): number => total + item.listenSeconds, 0));
      stage = 'books';
      snapshot.books = await DataService.exportBackupBookShells();
      stage = 'reading';
      snapshot.reading = await ReadingBackupService.createSnapshot(context);
      stage = 'sources';
      try {
        await LocalRuleSourceRepository.init(context);
        stage = 'sources_read';
        const localSources = await LocalRuleSourceRepository.getAll();
        stage = 'sources_convert';
        for (const source of localSources) {
          snapshot.ruleSources.push(AppBackupService.toBackupRuleSource(source));
        }
      } catch (error) {
        console.error(`[AppBackupService] source export failed: ${DiagnosticLogService.describe(error)}`);
        if (error instanceof Error) console.error(`[AppBackupService] source export stack: ${DiagnosticLogService.sanitize(error.stack ?? '')}`);
        if (strict) throw new Error('Cannot back up source definitions');
        console.warn(`[AppBackupService] skip local rule backup: ${AppBackupService.errorMessage(error)}`);
      }

      const dir = AppBackupService.backupDir(context);
      try { await fileIo.mkdir(dir); } catch (_e) { /* 已存在 */ }
      const path = outputPath || AppBackupService.backupPath(context);
      const tmp = path + '.tmp';
      stage = 'serialize';
      const bytes = new util.TextEncoder().encodeInto(JSON.stringify(snapshot));
      console.info(`[AppBackupService] snapshot bytes=${bytes.byteLength} limit=${MAX_BACKUP_BYTES} books=${snapshot.books.length} sources=${snapshot.ruleSources.length}`);
      if (bytes.byteLength > MAX_BACKUP_BYTES) throw new Error('Backup exceeds size limit');
      stage = 'write';
      const file = await fileIo.open(tmp,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        if (await fileIo.write(file.fd, bytes.buffer) !== bytes.byteLength) {
          throw new Error('Incomplete backup write');
        }
        stage = 'flush';
        try { await fileIo.fsync(file.fd); } catch (_e) {
          if (strict) throw new Error('Cannot flush backup');
        }
      } finally {
        await fileIo.close(file);
      }
      stage = 'commit';
      await fileIo.moveFile(tmp, path);
    } catch (error) {
      console.error(`[AppBackupService] create snapshot failed stage=${stage}: ${DiagnosticLogService.describe(error)}`);
      if (error instanceof Error) throw error;
      throw new Error(DiagnosticLogService.describe(error));
    }
  }

  private static normalizePlaybackSnapshot(original: PreferenceBackupSnapshot): PreferenceBackupSnapshot {
    // 只处理导出副本：兼容已知旧字段，逐条跳过仍不合法的记录，不改写本机缓存。
    const snapshot: PreferenceBackupSnapshot = JSON.parse(JSON.stringify(original));
    snapshot.history = snapshot.history.filter((item: PlayHistoryItem): boolean => {
      if (!item || typeof item !== 'object' || Array.isArray(item)) return false;
      const legacy: LegacyPlaybackFields = JSON.parse(JSON.stringify(item));
      const updatedAt = AppBackupService.recoverPlaybackNumber(item.updatedAt,
        [legacy.h15, legacy.q11, legacy.c10]);
      if (updatedAt === undefined) return false;
      item.updatedAt = updatedAt;
      return AppBackupService.validHistoryItem(item);
    });
    snapshot.progresses = snapshot.progresses.filter((item: PlayProgress): boolean => {
      if (!item || typeof item !== 'object' || Array.isArray(item)) return false;
      const legacy: LegacyPlaybackFields = JSON.parse(JSON.stringify(item));
      const updatedAt = AppBackupService.recoverPlaybackNumber(item.updatedAt,
        [legacy.h15, legacy.q11, legacy.c10]);
      const chapterIndex = AppBackupService.recoverPlaybackNumber(item.chapterIndex, [legacy.h26]);
      const positionMs = AppBackupService.recoverPlaybackNumber(item.positionMs,
        [legacy.m56, legacy.l50, legacy.n49, legacy.x47, legacy.u47]);
      if (updatedAt === undefined || chapterIndex === undefined || positionMs === undefined) return false;
      item.updatedAt = updatedAt;
      item.chapterIndex = chapterIndex;
      item.positionMs = positionMs;
      return AppBackupService.validProgress(item);
    });
    if (snapshot.lastPlayed && !AppBackupService.validLastPlayed(snapshot.lastPlayed)) snapshot.lastPlayed = null;
    const skippedHistory = original.history.length - snapshot.history.length;
    const skippedProgresses = original.progresses.length - snapshot.progresses.length;
    if (skippedHistory > 0 || skippedProgresses > 0) {
      console.warn(`[AppBackupService] skipped invalid playback records: history=${skippedHistory}, progresses=${skippedProgresses}`);
    }
    return snapshot;
  }

  private static recoverPlaybackNumber(current: number, legacy: Array<number | undefined>): number | undefined {
    if (AppBackupService.validNumber(current)) return current;
    for (const value of legacy) {
      if (value !== undefined && AppBackupService.validNumber(value)) return value;
    }
    // 不推测未知格式，也不以 0 覆盖无法恢复的位置；由调用方跳过这一条。
    return undefined;
  }

  /** 云端或用户选择的文件进入本地恢复流程前，先验证整个快照。 */
  static async readSnapshot(path: string): Promise<AppBackupSnapshot> {
    const stat = await fileIo.stat(path);
    if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_BACKUP_BYTES) {
      throw new Error('Invalid backup size');
    }
    const raw = await fileIo.readText(path);
    const snapshot: AppBackupSnapshot = JSON.parse(raw);
    if (!AppBackupService.validSnapshot(snapshot)) throw new Error('Invalid backup format');
    return snapshot;
  }

  static async restoreSnapshot(context: common.Context, inputPath: string = '', strict: boolean = false): Promise<boolean> {
    const path = inputPath || AppBackupService.backupPath(context);
    let exists = false;
    try { exists = await fileIo.access(path); } catch (_e) { exists = false; }
    if (!exists) return false;
    const snapshot = await AppBackupService.readSnapshot(path);

    await PreferenceService.init(context);
    await StatsService.init(context);
    DataService.setContext(context);
    if (snapshot.version >= 2 && Array.isArray(snapshot.ruleSources)) {
      const localSources: LocalRuleSource[] = [];
      for (const backupSource of snapshot.ruleSources) {
        const source = AppBackupService.fromBackupRuleSource(backupSource);
        if (source !== undefined) localSources.push(source);
      }
      if (localSources.length > 0) {
        try {
          await LocalRuleSourceRepository.init(context);
          const restoredCount = await LocalRuleSourceImportService.importSources(localSources);
          if (restoredCount < localSources.length) {
            console.info(`[AppBackupService] skipped ${localSources.length - restoredCount} locked sources`);
          }
          SourceDataService.invalidateLocalSources();
        } catch (error) {
          if (strict) throw new Error('Cannot restore source definitions');
          console.warn(`[AppBackupService] skip local rule restore: ${AppBackupService.errorMessage(error)}`);
        }
      }
    }
    await PreferenceService.restoreBackupSnapshot(snapshot.preferences);
    await StatsService.restoreBackupStats(Array.isArray(snapshot.stats) ? snapshot.stats : []);
    await MedalService.instance.restoreSnapshot(context, snapshot.medals);
    await DataService.restoreBackupBookShells(snapshot.books, strict);
    if (snapshot.reading !== undefined) await ReadingBackupService.restoreSnapshot(context, snapshot.reading);
    return true;
  }

  private static validSnapshot(snapshot: AppBackupSnapshot): boolean {
    if (!snapshot || (snapshot.version !== 1 && snapshot.version !== BACKUP_VERSION) ||
      !AppBackupService.validNumber(snapshot.exportedAt) || snapshot.exportedAt <= 0 ||
      !snapshot.preferences || !Array.isArray(snapshot.books) || snapshot.books.length > 10000 ||
      !Array.isArray(snapshot.stats) || snapshot.stats.length > 10000) return AppBackupService.invalidSnapshot('snapshot');
    if (snapshot.medals !== undefined && !MedalService.isValidSnapshot(snapshot.medals)) {
      return AppBackupService.invalidSnapshot('medals');
    }
    const prefs = snapshot.preferences;
    if (prefs.descendingBookIds !== undefined && (!Array.isArray(prefs.descendingBookIds) ||
      prefs.descendingBookIds.length > 10000 ||
      !prefs.descendingBookIds.every((id: string): boolean => AppBackupService.validId(id)))) {
      return AppBackupService.invalidSnapshot('preferences.descendingBookIds');
    }
    if (snapshot.reading !== undefined && !ReadingBackupService.isValidSnapshot(snapshot.reading)) {
      return AppBackupService.invalidSnapshot('reading');
    }
    if (!Array.isArray(prefs.favorites) || prefs.favorites.length > 10000 ||
      !prefs.favorites.every((id: string): boolean => AppBackupService.validId(id)) ||
      !Array.isArray(prefs.history) || prefs.history.length > 10000 ||
      !Array.isArray(prefs.progresses) || prefs.progresses.length > 10000 ||
      !Array.isArray(prefs.skipConfigs) || prefs.skipConfigs.length > 10000) return AppBackupService.invalidSnapshot('preferences.collections');
    if (prefs.pinnedFavorites !== undefined && (!Array.isArray(prefs.pinnedFavorites) ||
      prefs.pinnedFavorites.length > 10000 ||
      !prefs.pinnedFavorites.every((id: string): boolean => AppBackupService.validId(id) &&
        prefs.favorites.includes(id)))) return AppBackupService.invalidSnapshot('preferences.pinnedFavorites');
    if (![prefs.colorMode, prefs.defaultTab, prefs.audioInterruptMode, prefs.homeGridColumns]
      .every((value: number): boolean => typeof value === 'number' && Number.isFinite(value)) ||
      typeof prefs.audioAutoResume !== 'boolean' ||
      !AppBackupService.optionalText(prefs.accentColor) ||
      !AppBackupService.optionalNumber(prefs.materialStyle) ||
      !AppBackupService.optionalNumber(prefs.preloadChapters) ||
      (prefs.searchConcurrency !== undefined && (typeof prefs.searchConcurrency !== 'number' ||
        !Number.isInteger(prefs.searchConcurrency) || prefs.searchConcurrency < 1 || prefs.searchConcurrency > 12)) ||
      (prefs.autoPlayOnLaunch !== undefined && typeof prefs.autoPlayOnLaunch !== 'boolean')) return AppBackupService.invalidSnapshot('preferences.settings');
    if (prefs.lastPlayed && !AppBackupService.validLastPlayed(prefs.lastPlayed)) {
      return AppBackupService.invalidSnapshot('preferences.lastPlayed');
    }
    for (const item of prefs.history) {
      if (!AppBackupService.validHistoryItem(item)) return AppBackupService.invalidSnapshot('preferences.history');
    }
    for (const progress of prefs.progresses) {
      if (!AppBackupService.validProgress(progress)) return AppBackupService.invalidSnapshot('preferences.progresses');
    }
    for (const skip of prefs.skipConfigs) {
      if (!skip || !AppBackupService.validId(skip.bookId) ||
        !AppBackupService.validNumber(skip.skipIntro) || !AppBackupService.validNumber(skip.skipOutro)) return AppBackupService.invalidSnapshot('preferences.skipConfigs');
    }
    for (const book of snapshot.books) {
      if (!book || !AppBackupService.validId(book.id) ||
        ![book.title, book.author, book.narrator, book.cover, book.category, book.intro, book.bookUrl, book.sourceUrl]
          .every((value: string): boolean => AppBackupService.validText(value)) ||
        !Array.isArray(book.tags) || !book.tags.every((value: string): boolean => AppBackupService.validText(value)) ||
        !Array.isArray(book.chapters) || book.chapters.length > 0 ||
        !AppBackupService.optionalNumber(book.skipIntro) || !AppBackupService.optionalNumber(book.skipOutro) ||
        (book.contentType !== undefined && book.contentType !== 'audio' && book.contentType !== 'text' && book.contentType !== 'comic') ||
        ![book.totalDuration, book.chapterCount, book.rating]
          .every((value: number): boolean => AppBackupService.validNumber(value))) return AppBackupService.invalidSnapshot('books');
    }
    for (const stat of snapshot.stats) {
      if (!AppBackupService.validStats(stat)) return AppBackupService.invalidSnapshot('stats');
    }
    if (snapshot.version >= 2) {
      if (!Array.isArray(snapshot.ruleSources) || snapshot.ruleSources.length > 10000) return AppBackupService.invalidSnapshot('ruleSources');
      for (const source of snapshot.ruleSources) {
        if (!AppBackupService.validRuleSource(source)) return AppBackupService.invalidSnapshot('ruleSources.item');
      }
    }
    return true;
  }

  private static validLastPlayed(item: LastPlayedItem): boolean {
    return !!item && AppBackupService.validId(item.bookId) && AppBackupService.validText(item.chapterId) &&
      AppBackupService.validNumber(item.progressMs) && AppBackupService.optionalText(item.chapterTitle) &&
      AppBackupService.validDuration(item.durationMs) && AppBackupService.optionalNumber(item.speed);
  }

  private static validHistoryItem(item: PlayHistoryItem): boolean {
    return !!item && AppBackupService.validId(item.bookId) && AppBackupService.validText(item.chapterId) &&
      AppBackupService.validNumber(item.progressMs) && AppBackupService.validNumber(item.updatedAt) &&
      AppBackupService.optionalText(item.chapterTitle) && AppBackupService.validDuration(item.durationMs) &&
      AppBackupService.optionalText(item.sourceUrl) && AppBackupService.optionalText(item.bookUrl);
  }

  private static validProgress(item: PlayProgress): boolean {
    return !!item && AppBackupService.validId(item.bookId) && AppBackupService.validText(item.chapterId) &&
      AppBackupService.validText(item.chapterTitle) && AppBackupService.optionalNumber(item.speed) &&
      AppBackupService.optionalText(item.sourceUrl) && AppBackupService.optionalText(item.bookUrl) &&
      item.durationMs !== undefined && AppBackupService.validDuration(item.durationMs) &&
      [item.chapterIndex, item.positionMs, item.updatedAt]
        .every((value: number): boolean => AppBackupService.validNumber(value));
  }

  private static validStats(stat: BookUsageStats): boolean {
    if (!stat || !AppBackupService.validId(stat.bookId) ||
      ![stat.title, stat.author, stat.cover].every((value: string): boolean => AppBackupService.validText(value)) ||
      !AppBackupService.validNumber(stat.listenSeconds) || !AppBackupService.validNumber(stat.updatedAt) ||
      !AppBackupService.optionalText(stat.sourceUrl) || !AppBackupService.optionalText(stat.bookUrl) ||
      !Array.isArray(stat.days) || stat.days.length > 10000) return false;
    for (const day of stat.days) {
      if (!day || typeof day.day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(day.day) ||
        !AppBackupService.validNumber(day.listenSeconds)) return false;
    }
    return true;
  }

  private static invalidSnapshot(section: string): boolean {
    // 仅记录格式错误的位置，不输出书籍、书源或账号数据。
    console.error(`[AppBackupService] invalid snapshot section=${section}`);
    return false;
  }

  private static validId(value: string): boolean {
    return typeof value === 'string' && value.length > 0 && value.length <= 8192 && !value.startsWith('import_');
  }

  private static validText(value: string): boolean {
    return typeof value === 'string' && value.length <= 1024 * 1024;
  }

  private static validNumber(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0;
  }

  private static optionalText(value: string | undefined): boolean {
    return value === undefined || AppBackupService.validText(value);
  }

  private static optionalNumber(value: number | undefined): boolean {
    return value === undefined || AppBackupService.validNumber(value);
  }

  private static validDuration(value: number | undefined): boolean {
    // AVPlayer 在尚未取得媒体时长时返回 -1，现有播放记录会保留该值。
    return value === -1 || AppBackupService.optionalNumber(value);
  }

  private static validRuleSource(source: BackupRuleSource): boolean {
    if (!source || !AppBackupService.validId(source.bookSourceUrl) ||
      !AppBackupService.validText(source.bookSourceName) || source.bookSourceName.length === 0 ||
      ![source.bookSourceGroup, source.bookSourceComment, source.searchUrl, source.exploreUrl, source.header,
        source.loginUrl, source.loginUi, source.loginCheckJs, source.jsLib, source.variable, source.concurrentRate,
        source.validationMessage].every((value: string): boolean => AppBackupService.validText(value)) ||
      typeof source.enabled !== 'boolean' || typeof source.enabledExplore !== 'boolean' ||
      typeof source.enabledCookieJar !== 'boolean' ||
      (source.isLocked !== undefined && typeof source.isLocked !== 'boolean') ||
      (source.isPinned !== undefined && typeof source.isPinned !== 'boolean') ||
      // 置顶使用 MIN(custom_order) - 1，负数是合法的排序值。
      (source.customOrder !== undefined &&
        (typeof source.customOrder !== 'number' || !Number.isFinite(source.customOrder))) ||
      ![source.bookSourceType, source.respondTime, source.lastUpdateTime, source.validationStatus]
        .every((value: number): boolean => AppBackupService.validNumber(value))) return false;
    if (!AppBackupService.validSearchRule(source.ruleSearch) ||
      !AppBackupService.validSearchRule(source.ruleExplore)) return false;
    const info = source.ruleBookInfo;
    if (info !== undefined && (!info || ![info.init, info.name, info.author, info.coverUrl, info.intro, info.kind,
      info.status, info.lastChapter, info.wordCount, info.updateTime, info.tocUrl]
      .every((value: string): boolean => AppBackupService.validText(value)))) return false;
    const toc = source.ruleToc;
    if (toc !== undefined && (!toc || ![toc.chapterList, toc.chapterName, toc.chapterUrl, toc.nextTocUrl,
      toc.isVip, toc.isPay, toc.isVolume, toc.updateTime, toc.duration]
      .every((value: string): boolean => AppBackupService.validText(value)))) return false;
    const content = source.ruleContent;
    return content === undefined || (!!content && [content.content, content.title, content.audioUrl,
      content.nextContentUrl, content.replaceRegex, content.sourceRegex]
      .every((value: string): boolean => AppBackupService.validText(value)));
  }

  private static validSearchRule(rule: LocalRuleSearchRule | undefined): boolean {
    return rule === undefined || (!!rule && [rule.bookList, rule.name, rule.author, rule.coverUrl,
      rule.bookUrl, rule.intro, rule.kind, rule.status, rule.lastChapter, rule.wordCount, rule.updateTime]
      .every((value: string): boolean => AppBackupService.validText(value)) &&
      AppBackupService.optionalText(rule.nextPageUrl));
  }

  private static toBackupRuleSource(source: LocalRuleSource): BackupRuleSource {
    const backup = new BackupRuleSource();
    backup.bookSourceUrl = source.bookSourceUrl;
    backup.bookSourceName = source.bookSourceName;
    backup.bookSourceType = source.bookSourceType;
    backup.bookSourceGroup = source.bookSourceGroup;
    backup.bookSourceComment = source.bookSourceComment;
    backup.enabled = source.enabled;
    backup.enabledExplore = source.enabledExplore;
    backup.isLocked = source.isLocked;
    backup.isPinned = source.isPinned;
    backup.customOrder = source.customOrder;
    backup.enabledCookieJar = source.enabledCookieJar;
    backup.searchUrl = source.searchUrl;
    backup.exploreUrl = source.exploreUrl;
    backup.header = AppBackupService.sanitizeHeader(source.header);
    backup.loginUrl = source.loginUrl;
    backup.loginUi = source.loginUi;
    backup.loginCheckJs = source.loginCheckJs;
    backup.jsLib = source.jsLib;
    backup.variable = source.variable;
    backup.respondTime = source.respondTime;
    backup.concurrentRate = source.concurrentRate;
    backup.lastUpdateTime = source.lastUpdateTime;
    backup.validationStatus = source.validationStatus;
    backup.validationMessage = source.validationMessage;
    backup.ruleSearch = AppBackupService.copySearchRule(source.ruleSearch);
    backup.ruleExplore = AppBackupService.copySearchRule(source.ruleExplore);
    backup.ruleBookInfo = AppBackupService.copyBookInfoRule(source.ruleBookInfo);
    backup.ruleToc = AppBackupService.copyTocRule(source.ruleToc);
    backup.ruleContent = AppBackupService.copyContentRule(source.ruleContent);
    return backup;
  }

  private static fromBackupRuleSource(backup: BackupRuleSource): LocalRuleSource | undefined {
    const sourceUrl = (backup.bookSourceUrl || '').trim();
    const sourceName = (backup.bookSourceName || '').trim();
    if (sourceUrl.length === 0 || sourceName.length === 0) return undefined;

    const source = new LocalRuleSource();
    source.bookSourceUrl = sourceUrl;
    source.bookSourceName = sourceName;
    source.bookSourceType = AppBackupService.validSourceType(backup.bookSourceType);
    source.bookSourceGroup = backup.bookSourceGroup || '';
    source.bookSourceComment = backup.bookSourceComment || '';
    source.enabled = backup.enabled === true;
    source.enabledExplore = backup.enabledExplore === true;
    source.isLocked = backup.isLocked === true;
    source.isPinned = backup.isPinned === true;
    source.customOrder = backup.customOrder ?? 0;
    source.enabledCookieJar = backup.enabledCookieJar !== false;
    source.searchUrl = backup.searchUrl || '';
    source.exploreUrl = backup.exploreUrl || '';
    source.header = AppBackupService.sanitizeHeader(backup.header || '');
    source.loginUrl = backup.loginUrl || '';
    source.loginUi = backup.loginUi || '';
    source.loginCheckJs = backup.loginCheckJs || '';
    source.jsLib = backup.jsLib || '';
    source.variable = backup.variable || '';
    source.respondTime = Number.isFinite(backup.respondTime) && backup.respondTime > 0
      ? backup.respondTime : 18000;
    source.concurrentRate = backup.concurrentRate || '';
    source.lastUpdateTime = Number.isFinite(backup.lastUpdateTime) ? backup.lastUpdateTime : 0;
    const savedStatus = AppBackupService.validStatus(backup.validationStatus);
    const usesNativeAdapter = GuangYuSourceIdentity.isSourceUrl(sourceUrl) ||
      ShuShanSourceIdentity.isSourceUrl(sourceUrl);
    if (savedStatus === LocalRuleSourceStatus.UNSUPPORTED && !usesNativeAdapter) {
      source.validationStatus = LocalRuleSourceStatus.UNSUPPORTED;
      source.validationMessage = backup.validationMessage || '书源包含当前版本不支持的能力';
      source.enabled = false;
    } else {
      source.validationStatus = LocalRuleSourceStatus.UNCHECKED;
      source.validationMessage = '恢复后等待重新测试';
    }

    if (backup.ruleSearch !== undefined) {
      source.ruleSearch = AppBackupService.copySearchRule(backup.ruleSearch);
    }
    if (backup.ruleExplore !== undefined) {
      source.ruleExplore = AppBackupService.copySearchRule(backup.ruleExplore);
    }
    if (backup.ruleBookInfo !== undefined) {
      source.ruleBookInfo = AppBackupService.copyBookInfoRule(backup.ruleBookInfo);
    }
    if (backup.ruleToc !== undefined) {
      source.ruleToc = AppBackupService.copyTocRule(backup.ruleToc);
    }
    if (backup.ruleContent !== undefined) {
      source.ruleContent = AppBackupService.copyContentRule(backup.ruleContent);
    }
    source.rawSourceJson = '';
    return source;
  }

  private static copySearchRule(source: LocalRuleSearchRule): LocalRuleSearchRule {
    const rule = new LocalRuleSearchRule();
    rule.bookList = source.bookList || '';
    rule.name = source.name || '';
    rule.author = source.author || '';
    rule.coverUrl = source.coverUrl || '';
    rule.bookUrl = source.bookUrl || '';
    rule.intro = source.intro || '';
    rule.kind = source.kind || '';
    rule.status = source.status || '';
    rule.lastChapter = source.lastChapter || '';
    rule.wordCount = source.wordCount || '';
    rule.updateTime = source.updateTime || '';
    rule.nextPageUrl = source.nextPageUrl || '';
    return rule;
  }

  private static copyBookInfoRule(source: LocalRuleBookInfoRule): LocalRuleBookInfoRule {
    const rule = new LocalRuleBookInfoRule();
    rule.init = source.init || '';
    rule.name = source.name || '';
    rule.author = source.author || '';
    rule.coverUrl = source.coverUrl || '';
    rule.intro = source.intro || '';
    rule.kind = source.kind || '';
    rule.status = source.status || '';
    rule.lastChapter = source.lastChapter || '';
    rule.wordCount = source.wordCount || '';
    rule.updateTime = source.updateTime || '';
    rule.tocUrl = source.tocUrl || '';
    return rule;
  }

  private static copyTocRule(source: LocalRuleTocRule): LocalRuleTocRule {
    const rule = new LocalRuleTocRule();
    rule.chapterList = source.chapterList || '';
    rule.chapterName = source.chapterName || '';
    rule.chapterUrl = source.chapterUrl || '';
    rule.nextTocUrl = source.nextTocUrl || '';
    rule.isVip = source.isVip || '';
    rule.isPay = source.isPay || '';
    rule.isVolume = source.isVolume || '';
    rule.updateTime = source.updateTime || '';
    rule.duration = source.duration || '';
    return rule;
  }

  private static copyContentRule(source: LocalRuleContentRule): LocalRuleContentRule {
    const rule = new LocalRuleContentRule();
    rule.content = source.content || '';
    rule.title = source.title || '';
    rule.audioUrl = source.audioUrl || '';
    rule.nextContentUrl = source.nextContentUrl || '';
    rule.replaceRegex = source.replaceRegex || '';
    rule.sourceRegex = source.sourceRegex || '';
    return rule;
  }

  private static sanitizeHeader(header: string): string {
    try {
      // 导入的 JSON 可能保留对象形式的 header；静态字段类型不代表运行期一定是字符串。
      const text = typeof header === 'string' ? header.trim() : JSON.stringify(header);
      if (typeof text !== 'string' || text.length === 0) return '';
      const parsed = JSON.parse(text) as Object;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return '';
      const record = parsed as Record<string, Object>;
      const safeHeaders: Record<string, string> = {};
      for (const key of Object.keys(record)) {
        if (!AppBackupService.isSafeHeaderName(key)) continue;
        const value = record[key];
        if (typeof value === 'string' && value.trim().length > 0) {
          safeHeaders[key] = value;
        }
      }
      return Object.keys(safeHeaders).length > 0 ? JSON.stringify(safeHeaders) : '';
    } catch (_error) {
      return '';
    }
  }

  private static isSafeHeaderName(name: string): boolean {
    const normalized = name.trim().toLowerCase();
    return normalized === 'accept' || normalized === 'accept-language' ||
      normalized === 'cache-control' || normalized === 'content-type' ||
      normalized === 'origin' || normalized === 'referer' || normalized === 'user-agent';
  }

  private static validStatus(status: number): number {
    if (status === LocalRuleSourceStatus.READY || status === LocalRuleSourceStatus.FAILED ||
      status === LocalRuleSourceStatus.UNSUPPORTED) return status;
    return LocalRuleSourceStatus.UNCHECKED;
  }

  private static validSourceType(sourceType: number): number {
    if (sourceType === LocalRuleSourceType.AUDIO || sourceType === LocalRuleSourceType.COMIC ||
      sourceType === LocalRuleSourceType.WEB_FILE) return sourceType;
    return LocalRuleSourceType.TEXT;
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message;
    return String(error);
  }
}
