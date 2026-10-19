import { GeneralSettings } from '../model/GeneralSettings';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';

const STORE_NAME = 'listenbook_stats';
const KEY_BOOK_USAGE = 'book_usage_records_v2';
const KEY_BOOK_USAGE_REVISION = 'book_usage_revision_v3';
const SNAPSHOT_FILE = 'listening_stats_v3.json';

export const EVT_USAGE_STATS_UPDATED = 'app.usageStats.updated';

export interface BookUsageInput {
  bookId: string;
  title: string;
  author?: string;
  cover?: string;
  sourceUrl?: string;
  bookUrl?: string;
}

export interface BookUsageDay {
  day: string;
  listenSeconds: number;
}

export interface BookUsageStats {
  archived?: boolean;
  bookId: string;
  title: string;
  author: string;
  cover: string;
  listenSeconds: number;
  updatedAt: number;
  days: BookUsageDay[];
  sourceUrl?: string;
  bookUrl?: string;
}

export interface DailyUsageStats {
  day: string;
  listenSeconds: number;
}

export interface UsageStatsBucket {
  label: string;
  listenSeconds: number;
}

export interface UsageStatsSummary {
  todaySeconds: number;
  weekSeconds: number;
  monthSeconds: number;
  totalSeconds: number;
}

export interface HeatPoint {
  day: string;
  seconds: number;
}

/** 从同一份已恢复的缓存计算全部指标，避免并发写入造成展示值不一致 */
export interface StatsBundle {
  records: BookUsageStats[];
  summary: UsageStatsSummary;
  streak: number;
  heatDays: HeatPoint[];
}

class StatsDiskSnapshot {
  version: number = 1;
  revision: number = 0;
  records: BookUsageStats[] = [];
}

export class StatsService {
  private static store: preferences.Preferences | undefined = undefined;
  private static initPromise: Promise<void> | undefined = undefined;
  private static initialized: boolean = false;
  private static records: BookUsageStats[] = [];
  private static revision: number = 0;
  private static snapshotPath: string = '';
  private static dirty: boolean = false;
  private static writeQueue: Promise<void> = Promise.resolve();

  static async init(context: common.Context): Promise<void> {
    if (StatsService.initialized) return;
    if (StatsService.initPromise === undefined) {
      StatsService.initPromise = StatsService.initialize(context).catch((error: Error): void => {
        StatsService.initPromise = undefined;
        throw new Error(error.message);
      });
    }
    await StatsService.initPromise;
  }

  private static async initialize(context: common.Context): Promise<void> {
    StatsService.snapshotPath = `${context.filesDir}/${SNAPSHOT_FILE}`;
    StatsService.store = await preferences.getPreferences(context, { name: STORE_NAME });
    let primary: StatsDiskSnapshot | undefined = undefined;
    let backup: StatsDiskSnapshot | undefined = undefined;
    let readFailed: boolean = false;
    try {
      const raw = await StatsService.store.get(KEY_BOOK_USAGE, '');
      if (typeof raw !== 'string') throw new Error('Invalid statistics value');
      if (raw.length > 0) {
        primary = new StatsDiskSnapshot();
        primary.records = StatsService.parseRecords(raw);
        const revision = await StatsService.store.get(KEY_BOOK_USAGE_REVISION, 0);
        primary.revision = typeof revision === 'number' && Number.isFinite(revision) ? revision : 0;
      }
    } catch (error) {
      readFailed = true;
      primary = undefined;
      console.warn(`[StatsService] preferences read failed: ${String(error)}`);
    }
    try {
      if (await fileIo.access(StatsService.snapshotPath)) {
        const snapshot: StatsDiskSnapshot = JSON.parse(await fileIo.readText(StatsService.snapshotPath));
        if (!snapshot || snapshot.version !== 1 || !Number.isFinite(snapshot.revision) ||
          !Array.isArray(snapshot.records)) throw new Error('Invalid statistics snapshot');
        backup = new StatsDiskSnapshot();
        backup.revision = snapshot.revision;
        backup.records = StatsService.normalizeRecords(snapshot.records);
      }
    } catch (error) {
      readFailed = true;
      backup = undefined;
      console.warn(`[StatsService] snapshot read failed: ${String(error)}`);
    }
    const selected = backup !== undefined && (primary === undefined || backup.revision > primary.revision)
      ? backup : primary;
    if (selected === undefined && readFailed) {
      throw new Error('Statistics could not be loaded; existing data will not be overwritten');
    }
    StatsService.records = selected?.records ?? [];
    StatsService.revision = selected?.revision ?? 0;
    // 首次读取旧版记录即补齐独立快照，不等到下一次播放才保护已有累计值。
    StatsService.dirty = selected !== undefined &&
      (primary === undefined || backup === undefined || primary.revision !== backup.revision);
    if (StatsService.dirty) await StatsService.persistSnapshot();
    StatsService.initialized = true;
  }

  private static async ensureReady(): Promise<void> {
    if (StatsService.initPromise !== undefined) await StatsService.initPromise;
    if (!StatsService.initialized) throw new Error('StatsService not initialized');
  }

  private static enqueue(action: () => Promise<void>): Promise<void> {
    const pending = StatsService.writeQueue.then(action);
    StatsService.writeQueue = pending.catch((): void => {});
    return pending;
  }

  static async addListenSeconds(seconds: number, book: BookUsageInput, endedAt?: number): Promise<void> {
    if (!GeneralSettings.current.historyEnabled) return;
    if (!Number.isFinite(seconds) || seconds < 1 || !book.bookId) return;
    // 在入队前固定书籍和日期，避免排队跨过零点后把昨日时长写入今天。
    const recordedAt = endedAt !== undefined && Number.isFinite(endedAt) ? endedAt : Date.now();
    const input: BookUsageInput = {
      bookId: book.bookId, title: book.title, author: book.author, cover: book.cover,
      sourceUrl: book.sourceUrl, bookUrl: book.bookUrl
    };
    await StatsService.enqueue(async (): Promise<void> => {
      await StatsService.ensureReady();
      if (!GeneralSettings.current.historyEnabled) return;
      await StatsService.addSeconds(Math.floor(seconds), input, recordedAt, endedAt !== undefined);
    });
  }

  private static async addSeconds(delta: number, book: BookUsageInput, recordedAt: number,
    splitInterval: boolean): Promise<void> {
    const records = StatsService.normalizeRecords(StatsService.records);
    const day = StatsService.formatDay(new Date(recordedAt));
    let rec = records.find((item: BookUsageStats): boolean => item.bookId === book.bookId);
    if (rec === undefined) {
      rec = {
        bookId: book.bookId, title: book.title || '未知书籍', author: book.author || '',
        cover: book.cover || '', listenSeconds: 0, updatedAt: recordedAt, days: [],
        sourceUrl: book.sourceUrl || '', bookUrl: book.bookUrl || ''
      };
      records.push(rec);
    }
    rec.title = book.title || rec.title;
    rec.archived = false;
    rec.author = book.author || rec.author;
    rec.cover = book.cover || rec.cover;
    rec.updatedAt = recordedAt;
    if (book.sourceUrl) rec.sourceUrl = book.sourceUrl;
    if (book.bookUrl) rec.bookUrl = book.bookUrl;
    let remaining = delta;
    let intervalEnd = recordedAt;
    while (remaining > 0) {
      const date = new Date(splitInterval ? intervalEnd - 1 : intervalEnd);
      const dayKey = StatsService.formatDay(date);
      const dayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
      const portion = splitInterval ? Math.min(remaining, Math.ceil((intervalEnd - dayStart) / 1000)) : remaining;
      let dayItem = rec.days.find((item: BookUsageDay): boolean => item.day === dayKey);
      if (dayItem === undefined) {
        dayItem = { day: dayKey, listenSeconds: 0 };
        rec.days.push(dayItem);
      }
      dayItem.listenSeconds += portion;
      remaining -= portion;
      intervalEnd = dayStart;
    }
    rec.listenSeconds += delta;
    rec.days = StatsService.trimDays(rec.days);
    records.sort((left: BookUsageStats, right: BookUsageStats): number => right.updatedAt - left.updatedAt);
    try {
      await StatsService.commitRecords(records);
    } finally {
      // 双存储暂时失败时增量仍在缓存，页面与重试落盘使用同一份数值。
      emitter.emit(EVT_USAGE_STATS_UPDATED, { data: { day, bookId: book.bookId } });
    }
  }

  static async getBookStats(): Promise<BookUsageStats[]> {
    await StatsService.ensureReady();
    await StatsService.writeQueue;
    // 返回副本，页面、备份或删除筛选均不能修改服务持有的最后一份有效数据。
    return StatsService.normalizeRecords(StatsService.records);
  }

  /** 备份独立读取副本；单条旧统计损坏不能阻断整份备份，也不能借此覆盖本机存储。 */
  static async exportBackupStats(context: common.Context): Promise<BookUsageStats[]> {
    await StatsService.writeQueue;
    if (StatsService.initialized) return StatsService.normalizeBackupRecords(StatsService.records);
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    let primary: StatsDiskSnapshot | undefined = undefined;
    let backup: StatsDiskSnapshot | undefined = undefined;
    let readFailed = false;
    try {
      const raw = await store.get(KEY_BOOK_USAGE, '');
      if (typeof raw !== 'string') throw new Error('Invalid statistics value');
      if (raw.length > 0) {
        const records: BookUsageStats[] = JSON.parse(raw);
        if (!Array.isArray(records)) throw new Error('Invalid statistics records');
        primary = new StatsDiskSnapshot();
        primary.records = StatsService.normalizeBackupRecords(records);
        const revision = await store.get(KEY_BOOK_USAGE_REVISION, 0);
        primary.revision = typeof revision === 'number' && Number.isFinite(revision) ? revision : 0;
      }
    } catch (_e) { primary = undefined; readFailed = true; }
    try {
      const path = `${context.filesDir}/${SNAPSHOT_FILE}`;
      if (await fileIo.access(path)) {
        const saved: StatsDiskSnapshot = JSON.parse(await fileIo.readText(path));
        if (!saved || saved.version !== 1 || !Number.isFinite(saved.revision) || !Array.isArray(saved.records)) {
          throw new Error('Invalid statistics snapshot');
        }
        backup = new StatsDiskSnapshot();
        backup.revision = saved.revision;
        backup.records = StatsService.normalizeBackupRecords(saved.records);
      }
    } catch (_e) { backup = undefined; readFailed = true; }
    const selected = backup !== undefined && (primary === undefined || backup.revision > primary.revision) ? backup : primary;
    if (selected === undefined && readFailed) throw new Error('Statistics could not be read for backup');
    return selected?.records ?? [];
  }

  private static normalizeBackupRecords(records: BookUsageStats[]): BookUsageStats[] {
    const result: BookUsageStats[] = [];
    for (const record of records) {
      try {
        const normalized = StatsService.normalizeRecords([record]);
        result.push(normalized[0]);
      } catch (_e) { /* 只跳过当前异常项，保留其他统计。 */ }
    }
    return result;
  }

  private static parseRecords(raw: string): BookUsageStats[] {
    const list: BookUsageStats[] = JSON.parse(raw);
    if (!Array.isArray(list)) throw new Error('Invalid statistics records');
    return StatsService.normalizeRecords(list);
  }

  private static normalizeRecords(records: BookUsageStats[]): BookUsageStats[] {
    return records.map((item: BookUsageStats): BookUsageStats => {
      if (!item || typeof item.bookId !== 'string' || !item.bookId) {
        throw new Error('Invalid statistics record');
      }
      const days = Array.isArray(item.days) ? item.days : [];
      const lifetime = days.reduce((total: number, day: BookUsageDay): number =>
        total + StatsService.safeSeconds(day?.listenSeconds), 0);
      return {
        bookId: item.bookId, title: item.title || '未知书籍', author: item.author || '', cover: item.cover || '',
        listenSeconds: Math.max(StatsService.safeSeconds(item.listenSeconds), lifetime),
        updatedAt: item.updatedAt || 0, days: StatsService.trimDays(days),
        sourceUrl: item.sourceUrl || '', bookUrl: item.bookUrl || '',
        archived: item.archived === true
      };
    }).sort((left: BookUsageStats, right: BookUsageStats): number => right.updatedAt - left.updatedAt);
  }

  private static safeSeconds(seconds: number | undefined): number {
    return seconds !== undefined && Number.isFinite(seconds) ? Math.max(0, Math.floor(seconds)) : 0;
  }

  private static async commitRecords(records: BookUsageStats[]): Promise<void> {
    StatsService.records = records;
    StatsService.revision = Math.max(Date.now(), StatsService.revision + 1);
    StatsService.dirty = true;
    await StatsService.persistSnapshot();
  }

  private static async persistSnapshot(): Promise<void> {
    const store = StatsService.store;
    if (store === undefined) throw new Error('StatsService not initialized');
    const snapshot = new StatsDiskSnapshot();
    snapshot.revision = StatsService.revision;
    snapshot.records = StatsService.records;
    let snapshotSaved: boolean = false;
    let preferencesSaved: boolean = false;
    try {
      const temporaryPath = `${StatsService.snapshotPath}.tmp`;
      const file = await fileIo.open(temporaryPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.READ_WRITE);
      try {
        await fileIo.write(file.fd, JSON.stringify(snapshot));
        await fileIo.fsync(file.fd);
      } finally {
        await fileIo.close(file);
      }
      await fileIo.rename(temporaryPath, StatsService.snapshotPath);
      snapshotSaved = true;
    } catch (error) {
      console.warn(`[StatsService] snapshot write failed: ${String(error)}`);
    }
    try {
      await store.put(KEY_BOOK_USAGE, JSON.stringify(snapshot.records));
      await store.put(KEY_BOOK_USAGE_REVISION, snapshot.revision);
      await store.flush();
      preferencesSaved = true;
    } catch (error) {
      console.warn(`[StatsService] preferences write failed: ${String(error)}`);
    }
    StatsService.dirty = !snapshotSaved || !preferencesSaved;
    if (!snapshotSaved && !preferencesSaved) {
      throw new Error('Statistics could not be persisted; retained in memory for retry');
    }
  }

  /** 退后台或退出前等待统计写入，并重试未完成的持久化。 */
  static async flush(): Promise<void> {
    await StatsService.enqueue(async (): Promise<void> => {
      if (StatsService.initPromise !== undefined) await StatsService.initPromise;
      if (StatsService.initialized && StatsService.dirty) await StatsService.persistSnapshot();
    });
  }

  static async removeBookStats(bookIds: string[]): Promise<void> {
    if (bookIds.length === 0) return;
    const deleted = new Set(bookIds);
    await StatsService.enqueue(async (): Promise<void> => {
      await StatsService.ensureReady();
      const records = StatsService.normalizeRecords(StatsService.records);
      for (const item of records) {
        if (deleted.has(item.bookId)) item.archived = true;
      }
      await StatsService.commitRecords(records);
      emitter.emit(EVT_USAGE_STATS_UPDATED);
    });
  }

  static async clearBookStats(): Promise<void> {
    await StatsService.enqueue(async (): Promise<void> => {
      await StatsService.ensureReady();
      const records = StatsService.normalizeRecords(StatsService.records);
      for (const item of records) item.archived = true;
      await StatsService.commitRecords(records);
      emitter.emit(EVT_USAGE_STATS_UPDATED);
    });
  }

  /** 仅设置页“清除累计收听时长”的明确确认可以调用。 */
  static async resetListeningTime(): Promise<void> {
    await StatsService.enqueue(async (): Promise<void> => {
      await StatsService.ensureReady();
      await StatsService.commitRecords([]);
      emitter.emit(EVT_USAGE_STATS_UPDATED);
    });
  }

  static async restoreBackupStats(records: BookUsageStats[]): Promise<void> {
    const safeRecords = StatsService.normalizeRecords(records.filter((item: BookUsageStats): boolean =>
      !!item && !!item.bookId && !item.bookId.startsWith('import_')));
    await StatsService.enqueue(async (): Promise<void> => {
      await StatsService.ensureReady();
      // 恢复旧备份也不能降低本机已经累计的时长；同书同日取较大值，重复恢复不叠加。
      const merged = StatsService.normalizeRecords(StatsService.records);
      for (const incoming of safeRecords) {
        const current = merged.find((item: BookUsageStats): boolean => item.bookId === incoming.bookId);
        if (!current) {
          merged.push(incoming);
          continue;
        }
        for (const day of incoming.days) {
          const saved = current.days.find((item: BookUsageDay): boolean => item.day === day.day);
          if (saved) saved.listenSeconds = Math.max(saved.listenSeconds, day.listenSeconds);
          else current.days.push(day);
        }
        current.listenSeconds = Math.max(current.listenSeconds, incoming.listenSeconds,
          current.days.reduce((total: number, day: BookUsageDay): number => total + day.listenSeconds, 0));
        current.updatedAt = Math.max(current.updatedAt, incoming.updatedAt);
      }
      await StatsService.commitRecords(StatsService.normalizeRecords(merged));
      emitter.emit(EVT_USAGE_STATS_UPDATED, { data: { historical: true } });
    });
  }

  static async getAllDailyStats(): Promise<DailyUsageStats[]> {
    return StatsService.aggregateDaily(await StatsService.getBookStats());
  }

  static async getRecentDays(days: number): Promise<UsageStatsBucket[]> {
    const count = Math.max(1, days);
    const stats = await StatsService.getAllDailyStats();
    const map = StatsService.toMap(stats);
    const out: UsageStatsBucket[] = [];
    for (let i = count - 1; i >= 0; i--) {
      const date = StatsService.addDays(new Date(), -i);
      const day = StatsService.formatDay(date);
      const item = map.get(day);
      out.push({
        label: count <= 7 ? StatsService.weekdayLabel(date) : `${date.getMonth() + 1}/${date.getDate()}`,
        listenSeconds: item?.listenSeconds ?? 0
      });
    }
    return out;
  }

  /** 连续 N 天的每日总时长（含 0 值），chronological（旧→新，末位为今天） */
  static async getDailyTotals(days: number): Promise<HeatPoint[]> {
    const count = Math.max(1, days);
    const stats = await StatsService.getAllDailyStats();
    const map = StatsService.toMap(stats);
    const out: HeatPoint[] = [];
    for (let i = count - 1; i >= 0; i--) {
      const date = StatsService.addDays(new Date(), -i);
      const day = StatsService.formatDay(date);
      const item = map.get(day);
      out.push({ day, seconds: item?.listenSeconds ?? 0 });
    }
    return out;
  }

  /** 截至今天的连续打卡天数（当天时长>0 才计入今天） */
  static async getStreakDays(): Promise<number> {
    const stats = await StatsService.getAllDailyStats();
    const map = StatsService.toMap(stats);
    let streak = 0;
    for (let i = 0; i < 730; i++) {
      const day = StatsService.formatDay(StatsService.addDays(new Date(), -i));
      const item = map.get(day);
      const seconds = item?.listenSeconds ?? 0;
      if (seconds > 0) {
        streak++;
      } else if (i === 0) {
        // 今天还没收听，从昨天继续算
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  static async getYearMonths(year: number): Promise<UsageStatsBucket[]> {
    const stats = await StatsService.getAllDailyStats();
    const out: UsageStatsBucket[] = [];
    for (let month = 0; month < 12; month++) {
      out.push({ label: `${month + 1}月`, listenSeconds: 0 });
    }
    for (const item of stats) {
      const date = StatsService.parseDay(item.day);
      if (!date || date.getFullYear() !== year) continue;
      const idx = date.getMonth();
      out[idx].listenSeconds += item.listenSeconds;
    }
    return out;
  }

  static async getSummary(): Promise<UsageStatsSummary> {
    const records = await StatsService.getBookStats();
    return StatsService.computeSummary(StatsService.toMap(StatsService.aggregateDaily(records)),
      records.reduce((total: number, record: BookUsageStats): number => total + record.listenSeconds, 0));
  }

  /**
   * 等待在途写入完成，从同一份 records 缓存快照算出所有指标。
   * 页面用这个替代分散的 getBookStats/getSummary/getStreakDays/getDailyTotals 多次读盘,
   * 保证 6 个展示值内部一致(不会出现"今日有值但累计/本数/连续为 0"的撕裂)。
   */
  static async getStatsBundle(heatmapDays: number): Promise<StatsBundle> {
    return StatsService.buildStatsBundle(await StatsService.getBookStats(), heatmapDays);
  }

  static getCachedStatsBundle(heatmapDays: number): StatsBundle | undefined {
    if (!StatsService.initialized) return undefined;
    return StatsService.buildStatsBundle(StatsService.normalizeRecords(StatsService.records), heatmapDays);
  }

  private static buildStatsBundle(records: BookUsageStats[], heatmapDays: number): StatsBundle {
    const daily = StatsService.aggregateDaily(records);
    const map = StatsService.toMap(daily);
    return {
      records: records.filter((item: BookUsageStats): boolean => !item.archived),
      summary: StatsService.computeSummary(map,
        records.reduce((total: number, record: BookUsageStats): number => total + record.listenSeconds, 0)),
      streak: StatsService.computeStreak(map),
      heatDays: StatsService.computeHeatDays(map, heatmapDays)
    };
  }

  private static computeSummary(map: Map<string, DailyUsageStats>, totalSeconds: number): UsageStatsSummary {
    const now = new Date();
    const today = StatsService.formatDay(now);
    const weekStart = StatsService.formatDay(StatsService.addDays(now, -6));
    const monthStart = StatsService.formatDay(new Date(now.getFullYear(), now.getMonth(), 1));
    let todaySeconds = 0;
    let weekSeconds = 0;
    let monthSeconds = 0;
    for (const item of map.values()) {
      if (item.day > today) continue;
      const secs = item.listenSeconds;
      if (item.day === today) todaySeconds += secs;
      if (item.day >= weekStart) weekSeconds += secs;
      if (item.day >= monthStart) monthSeconds += secs;
    }
    return { todaySeconds, weekSeconds, monthSeconds, totalSeconds };
  }

  private static computeStreak(map: Map<string, DailyUsageStats>): number {
    let streak = 0;
    for (let i = 0; i < 730; i++) {
      const day = StatsService.formatDay(StatsService.addDays(new Date(), -i));
      const item = map.get(day);
      const seconds = item?.listenSeconds ?? 0;
      if (seconds > 0) {
        streak++;
      } else if (i === 0) {
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  private static computeHeatDays(map: Map<string, DailyUsageStats>, days: number): HeatPoint[] {
    const count = Math.max(1, days);
    const out: HeatPoint[] = [];
    for (let i = count - 1; i >= 0; i--) {
      const date = StatsService.addDays(new Date(), -i);
      const day = StatsService.formatDay(date);
      const item = map.get(day);
      out.push({ day, seconds: item?.listenSeconds ?? 0 });
    }
    return out;
  }

  private static aggregateDaily(records: BookUsageStats[]): DailyUsageStats[] {
    const map = new Map<string, DailyUsageStats>();
    for (const record of records) {
      for (const day of record.days) {
        let item = map.get(day.day);
        if (!item) {
          item = { day: day.day, listenSeconds: 0 };
          map.set(day.day, item);
        }
        item.listenSeconds += Math.max(0, Math.floor(day.listenSeconds || 0));
      }
    }
    return Array.from(map.values()).sort((a, b) => a.day.localeCompare(b.day));
  }

  private static trimDays(days: BookUsageDay[]): BookUsageDay[] {
    const start = StatsService.formatDay(StatsService.addDays(new Date(), -730));
    return days
      .filter((item) => item && typeof item.day === 'string' && item.day >= start)
      .map((item): BookUsageDay => ({
        day: item.day,
        listenSeconds: StatsService.safeSeconds(item.listenSeconds)
      }))
      .sort((a, b) => a.day.localeCompare(b.day));
  }

  private static toMap(stats: DailyUsageStats[]): Map<string, DailyUsageStats> {
    const map = new Map<string, DailyUsageStats>();
    for (const item of stats) {
      map.set(item.day, item);
    }
    return map;
  }

  private static sum(stats: DailyUsageStats[]): number {
    return stats.reduce((acc, item) => acc + item.listenSeconds, 0);
  }

  private static addDays(date: Date, days: number): Date {
    const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    d.setDate(d.getDate() + days);
    return d;
  }

  private static parseDay(day: string): Date | null {
    const parts = day.split('-');
    if (parts.length !== 3) return null;
    const y = Number(parts[0]);
    const m = Number(parts[1]);
    const d = Number(parts[2]);
    if (!y || !m || !d) return null;
    return new Date(y, m - 1, d);
  }

  private static formatDay(date: Date): string {
    const y = date.getFullYear();
    const m = (date.getMonth() + 1).toString().padStart(2, '0');
    const d = date.getDate().toString().padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  private static weekdayLabel(date: Date): string {
    const labels = ['日', '一', '二', '三', '四', '五', '六'];
    return labels[date.getDay()];
  }
}
