import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export class BookUpdateInfo {
  bookId: string = '';
  title: string = '';
  cover: string = '';
  oldCount: number = 0;
  newCount: number = 0;
  isText: boolean = false;
  latestChapter: string = '';
}

export class ShelfUpdateReport {
  checkedAt: number = 0;
  checkedCount: number = 0;
  updatedCount: number = 0;
  failedCount: number = 0;
  entries: BookUpdateInfo[] = [];
}

/** 本机按自然日检查；手动刷新不受日期限制，所有入口共用同一把锁。 */
export class ShelfUpdateService {
  private static running: boolean = false;
  private static attemptDay: string = '';

  static dayKey(time: number): string {
    const date = new Date(time);
    return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
  }

  /** 同一进程内的 Tab 往返直接命中每日门控，不再读偏好或切换页面加载状态。 */
  static shouldAutoCheck(now: number = Date.now()): boolean {
    return !ShelfUpdateService.running && ShelfUpdateService.attemptDay !== ShelfUpdateService.dayKey(now);
  }

  static async lastReport(context: common.Context): Promise<ShelfUpdateReport> {
    try {
      const store = await preferences.getPreferences(context, { name: 'listenbook_shelf_updates' });
      const raw = await store.get('report_v1', '');
      if (typeof raw !== 'string' || raw.length === 0 || raw.length > 1024 * 1024) return new ShelfUpdateReport();
      const report: ShelfUpdateReport = JSON.parse(raw);
      if (!report || !Number.isFinite(report.checkedAt) || report.checkedAt <= 0 ||
        !Number.isInteger(report.checkedCount) || !Number.isInteger(report.updatedCount) ||
        !Number.isInteger(report.failedCount) || !Array.isArray(report.entries)) return new ShelfUpdateReport();
      report.entries = report.entries.filter((item: BookUpdateInfo): boolean => item !== null &&
        typeof item.bookId === 'string' && typeof item.title === 'string' && typeof item.cover === 'string' &&
        typeof item.latestChapter === 'string' && typeof item.isText === 'boolean' &&
        Number.isInteger(item.oldCount) && item.oldCount >= 0 && Number.isInteger(item.newCount) &&
        item.newCount > item.oldCount);
      return report;
    } catch (_error) { return new ShelfUpdateReport(); }
  }

  static async run(context: common.Context, silent: boolean,
    task: () => Promise<ShelfUpdateReport>, now: number = Date.now()): Promise<ShelfUpdateReport | undefined> {
    if (ShelfUpdateService.running || (silent && !ShelfUpdateService.shouldAutoCheck(now))) return undefined;
    ShelfUpdateService.running = true;
    try {
      let store: preferences.Preferences | undefined = undefined;
      try {
        store = await preferences.getPreferences(context, { name: 'listenbook_shelf_updates' });
        const today = ShelfUpdateService.dayKey(now);
        if (silent && await store.get('attempt_day', '') === today) {
          ShelfUpdateService.attemptDay = today;
          return undefined;
        }
        // 请求前落盘，切后台、重启或失败不会在同一天反复触发静默请求。
        await store.put('attempt_day', today);
        await store.flush();
        ShelfUpdateService.attemptDay = today;
      } catch (error) {
        console.warn(`[ShelfUpdate] schedule unavailable: ${error}`);
        if (silent) return undefined;
      }
      const report = await task();
      if (store !== undefined) {
        try {
          await store.put('report_v1', JSON.stringify(report));
          await store.flush();
        } catch (error) { console.warn(`[ShelfUpdate] report save failed: ${error}`); }
      }
      return report;
    } finally {
      ShelfUpdateService.running = false;
    }
  }
}
