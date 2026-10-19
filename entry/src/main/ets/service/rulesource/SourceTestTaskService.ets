import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { LocalRuleSource } from '../../model/LocalRuleSource';
import { BackgroundTaskService } from '../BackgroundTaskService';
import { SourceDataService } from '../SourceDataService';
import { LocalRuleSourceBulkTester, LocalRuleSourceBulkTestProgress, LocalRuleSourceBulkTestReport } from './LocalRuleSourceBulkTester';

export class SourceTestTaskState {
  running: boolean = false;
  progress: LocalRuleSourceBulkTestProgress = new LocalRuleSourceBulkTestProgress();
  report: LocalRuleSourceBulkTestReport | null = null;
  failed: boolean = false;
}

/** 测试归服务持有；页面只订阅快照，退出页面不取消用户任务。 */
export class SourceTestTaskService {
  static readonly state: SourceTestTaskState = new SourceTestTaskState();
  private static tester: LocalRuleSourceBulkTester | null = null;
  private static listeners: Set<() => void> = new Set();
  private static notificationChain: Promise<void> = Promise.resolve();
  private static lastNotice: number = 0;
  private static cancelRequested: boolean = false;
  private static context: common.UIAbilityContext | null = null;
  static setContext(context: common.UIAbilityContext): void { SourceTestTaskService.context = context; }
  private static readonly NOTICE_ID: number = 20261019;
  private static readonly onBackgroundInterrupted = (): void => { SourceTestTaskService.cancel(); };

  static subscribe(listener: () => void): void { SourceTestTaskService.listeners.add(listener); }
  static unsubscribe(listener: () => void): void { SourceTestTaskService.listeners.delete(listener); }
  private static emit(): void { for (const listener of SourceTestTaskService.listeners) listener(); }
  static cancel(): void { SourceTestTaskService.cancelRequested = true; SourceTestTaskService.tester?.cancel(); }

  static async start(sources: LocalRuleSource[], keyword: string, mode: string): Promise<void> {
    const context = SourceTestTaskService.context;
    if (context === null) throw new Error('Application context unavailable');
    const state = SourceTestTaskService.state;
    if (state.running) return;
    state.running = true;
    SourceTestTaskService.cancelRequested = false;
    state.report = null;
    state.failed = false;
    state.progress = new LocalRuleSourceBulkTestProgress();
    state.progress.total = sources.length;
    SourceTestTaskService.emit();
    try {
      try {
        if (!await notificationManager.isNotificationEnabled()) await notificationManager.requestEnableNotification(context);
        await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
      } catch (_error) { /* 通知拒绝不阻止测试，仍保留页内进度 */ }
      BackgroundTaskService.subscribeInterruption(SourceTestTaskService.onBackgroundInterrupted);
      BackgroundTaskService.resumeAfterUserAction();
      await BackgroundTaskService.startDataTransfer(context, 'source-test');
      if (SourceTestTaskService.cancelRequested) {
        const report = new LocalRuleSourceBulkTestReport();
        report.total = sources.length;
        report.cancelled = true;
        state.report = report;
        return;
      }
      SourceTestTaskService.notice(context, true);
      const tester = LocalRuleSourceBulkTester.createDefault(mode);
      SourceTestTaskService.tester = tester;
      state.report = await tester.run(sources, keyword, (progress: LocalRuleSourceBulkTestProgress): void => {
        state.progress = progress;
        SourceTestTaskService.emit();
        SourceTestTaskService.notice(context);
      });
    } catch (_error) { state.failed = true; }
    finally {
      state.running = false;
      SourceTestTaskService.tester = null;
      SourceDataService.invalidateLocalSources();
      BackgroundTaskService.unsubscribeInterruption(SourceTestTaskService.onBackgroundInterrupted);
      await BackgroundTaskService.stopDataTransfer(context, 'source-test');
      SourceTestTaskService.notice(context, true);
      SourceTestTaskService.emit();
    }
  }

  private static notice(context: common.Context, force: boolean = false): void {
    const now = Date.now();
    if (!force && now - SourceTestTaskService.lastNotice < 1000) return;
    SourceTestTaskService.lastNotice = now;
    const state = SourceTestTaskService.state;
    const progress = state.progress;
    const title = context.resourceManager.getStringSync($r('app.string.source_test_notification_title').id);
    const status = context.resourceManager.getStringSync((state.running ? $r('app.string.source_test_running') :
      state.failed ? $r('app.string.rule_source_bulk_operation_failed') : state.report?.cancelled ?
        $r('app.string.source_manage_test_cancelled') : $r('app.string.rule_source_bulk_completed')).id);
    const detail = context.resourceManager.getStringSync($r('app.string.source_test_notification_progress').id,
      status, progress.completed, progress.total, progress.passed, progress.failed);
    const request: notificationManager.NotificationRequest = {
      id: SourceTestTaskService.NOTICE_ID, notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isAlertOnce: true, tapDismissed: !state.running,
      content: { notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: title, text: detail } }
    };
    SourceTestTaskService.notificationChain = SourceTestTaskService.notificationChain.then(async (): Promise<void> => {
      if (await notificationManager.isNotificationEnabled()) await notificationManager.publish(request);
    }).catch((): void => {});
  }
}
