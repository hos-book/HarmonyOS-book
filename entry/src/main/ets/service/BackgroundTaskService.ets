import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DiagnosticLogService } from './DiagnosticLogService';
import { PlatformCompat } from '../utils/PlatformCompat';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_BgTask';
const AUDIO_MODE = 'audioPlayback';
const DATA_TRANSFER_MODE = 'dataTransfer';

export class BackgroundTaskService {
  private static running: boolean = false;
  private static appliedModes: string = '';
  private static requestedModes: Set<string> = new Set();
  private static syncPromise: Promise<void> = Promise.resolve();
  private static context: common.UIAbilityContext | null = null;
  private static listenersBound: boolean = false;
  private static systemBlocked: boolean = false;
  private static taskRegistered: boolean = false;
  private static starting: boolean = false;
  private static suspended: boolean = false;
  private static taskId: number = -1;
  private static endedTaskId: number = -1;
  private static taskGeneration: number = 0;
  private static interruptionListeners: Set<() => void> = new Set();

  static subscribeInterruption(listener: () => void): void { BackgroundTaskService.interruptionListeners.add(listener); }
  static unsubscribeInterruption(listener: () => void): void { BackgroundTaskService.interruptionListeners.delete(listener); }

  private static readonly onCancel = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (!BackgroundTaskService.matchesTask(info.id)) return;
    const reason = info?.reason ?? -1;
    const detail = PlatformCompat.supports(26) ? (info.detailedReason ?? -1) : -1;
    hilog.warn(DOMAIN, TAG, 'continuousTaskCancel id=%{public}d reason=%{public}d modes=%{public}s',
      info?.id ?? -1, reason, BackgroundTaskService.modeSnapshot());
    // 系统已取消长时任务，本地必须立刻认为未在跑，否则后续只会走 update 失败路径
    BackgroundTaskService.clearTask();
    BackgroundTaskService.endedTaskId = info.id;
    DiagnosticLogService.info('background.cancel', `id=${info.id}; reason=${reason}; detail=${detail}; modes=${BackgroundTaskService.modeSnapshot()}; owners=${Array.from(BackgroundTaskService.audioOwners).join(',')}`);
    BackgroundTaskService.systemBlocked = true;
    for (const listener of BackgroundTaskService.interruptionListeners) listener();
  };

  private static readonly onSuspend = (info: backgroundTaskManager.ContinuousTaskSuspendInfo): void => {
    if (!BackgroundTaskService.matchesTask(info.continuousTaskId)) return;
    const reason = info?.suspendReason ?? -1;
    hilog.warn(DOMAIN, TAG, 'continuousTaskSuspend id=%{public}d reason=%{public}d modes=%{public}s',
      info?.continuousTaskId ?? -1, reason, BackgroundTaskService.modeSnapshot());
    // 尊重系统挂起，等待 active 回调或用户重新发起任务。
    BackgroundTaskService.running = false;
    BackgroundTaskService.taskRegistered = true;
    BackgroundTaskService.suspended = true;
    BackgroundTaskService.taskId = info.continuousTaskId;
    BackgroundTaskService.taskGeneration++;
    DiagnosticLogService.info('background.suspend', `id=${info.continuousTaskId}; reason=${reason}; modes=${BackgroundTaskService.modeSnapshot()}`);
    BackgroundTaskService.systemBlocked = true;
    for (const listener of BackgroundTaskService.interruptionListeners) listener();
  };

  private static readonly onActive = (info: backgroundTaskManager.ContinuousTaskActiveInfo): void => {
    if (!BackgroundTaskService.taskRegistered || !BackgroundTaskService.suspended ||
      !BackgroundTaskService.matchesTask(info.id)) return;
    hilog.info(DOMAIN, TAG, 'continuousTaskActive id=%{public}d modes=%{public}s',
      info?.id ?? -1, BackgroundTaskService.modeSnapshot());
    if (BackgroundTaskService.requestedModes.size > 0) {
      BackgroundTaskService.running = true;
      BackgroundTaskService.suspended = false;
      BackgroundTaskService.systemBlocked = false;
      DiagnosticLogService.info('background.active', `id=${info.id}; modes=${BackgroundTaskService.modeSnapshot()}`);
    }
  };

  private static audioOwners: Set<string> = new Set();
  private static transferOwners: Set<string> = new Set();

  static startSpeech(context: common.UIAbilityContext): Promise<void> {
    BackgroundTaskService.audioOwners.add('speech');
    return BackgroundTaskService.setMode(context, AUDIO_MODE, true);
  }

  static stopSpeech(context: common.UIAbilityContext): Promise<void> {
    BackgroundTaskService.audioOwners.delete('speech');
    return BackgroundTaskService.setMode(context, AUDIO_MODE, BackgroundTaskService.audioOwners.size > 0);
  }

  static start(context: common.UIAbilityContext): Promise<void> {
    BackgroundTaskService.audioOwners.add('audio');
    return BackgroundTaskService.setMode(context, AUDIO_MODE, true);
  }

  static stop(context: common.UIAbilityContext): Promise<void> {
    BackgroundTaskService.audioOwners.delete('audio');
    return BackgroundTaskService.setMode(context, AUDIO_MODE, BackgroundTaskService.audioOwners.size > 0);
  }

  static startDataTransfer(context: common.UIAbilityContext, owner: string = 'download'): Promise<void> {
    BackgroundTaskService.transferOwners.add(owner);
    return BackgroundTaskService.setMode(context, DATA_TRANSFER_MODE, true);
  }

  static stopDataTransfer(context: common.UIAbilityContext, owner: string = 'download'): Promise<void> {
    BackgroundTaskService.transferOwners.delete(owner);
    return BackgroundTaskService.setMode(context, DATA_TRANSFER_MODE, BackgroundTaskService.transferOwners.size > 0);
  }

  /**
   * 下载仍有进度/队列时调用：若长时任务已被系统取消，重新申请。
   * 失败只记日志，不抛到业务层。
   */
  static ensure(context?: common.UIAbilityContext | null): Promise<void> {
    if (context) BackgroundTaskService.context = context;
    const ctx = BackgroundTaskService.context;
    if (!ctx || BackgroundTaskService.systemBlocked || BackgroundTaskService.requestedModes.size === 0) return Promise.resolve();
    if (BackgroundTaskService.running) return Promise.resolve();
    return BackgroundTaskService.queueSync(ctx);
  }

  static isRunning(): boolean {
    return BackgroundTaskService.running;
  }

  /** 只由用户明确的播放操作解除系统取消后的本地阻挡；自动预取不得自行解锁。 */
  static resumeAfterUserAction(): void {
    BackgroundTaskService.systemBlocked = false;
  }

  static hasMode(mode: string): boolean {
    return BackgroundTaskService.requestedModes.has(mode);
  }

  private static setMode(context: common.UIAbilityContext, mode: string, enabled: boolean): Promise<void> {
    hilog.info(DOMAIN, TAG, 'mode request mode=%{public}s enabled=%{public}s running=%{public}s owners=%{public}s',
      mode, String(enabled), String(BackgroundTaskService.running), Array.from(BackgroundTaskService.audioOwners).join(','));
    BackgroundTaskService.context = context;
    BackgroundTaskService.bindListeners();
    if (enabled) {
      if (!BackgroundTaskService.requestedModes.has(mode)) BackgroundTaskService.systemBlocked = false;
      BackgroundTaskService.requestedModes.add(mode);
    } else {
      BackgroundTaskService.requestedModes.delete(mode);
    }
    return BackgroundTaskService.queueSync(context);
  }

  private static queueSync(context: common.UIAbilityContext): Promise<void> {
    BackgroundTaskService.syncPromise = BackgroundTaskService.syncPromise.then(async (): Promise<void> => {
      await BackgroundTaskService.sync(context);
    }).catch((err: Error): void => {
      hilog.error(DOMAIN, TAG, 'sync background modes failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
    return BackgroundTaskService.syncPromise;
  }

  private static bindListeners(): void {
    if (BackgroundTaskService.listenersBound) return;
    BackgroundTaskService.listenersBound = true;
    try {
      backgroundTaskManager.on('continuousTaskCancel', BackgroundTaskService.onCancel);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'bind continuousTaskCancel failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
    try {
      backgroundTaskManager.on('continuousTaskSuspend', BackgroundTaskService.onSuspend);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'bind continuousTaskSuspend failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
    try {
      backgroundTaskManager.on('continuousTaskActive', BackgroundTaskService.onActive);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'bind continuousTaskActive failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  private static modeSnapshot(): string {
    return Array.from(BackgroundTaskService.requestedModes).join(',');
  }

  /** 回调是异步送达的，旧任务的取消/激活不得覆盖用户刚恢复的新任务。 */
  private static matchesTask(id: number): boolean {
    if (!BackgroundTaskService.taskRegistered && !BackgroundTaskService.starting) return false;
    if (BackgroundTaskService.taskId >= 0) return id === BackgroundTaskService.taskId;
    if (id >= 0 && id === BackgroundTaskService.endedTaskId) return false;
    return true;
  }

  private static clearTask(): void {
    BackgroundTaskService.endedTaskId = BackgroundTaskService.taskId;
    BackgroundTaskService.taskId = -1;
    BackgroundTaskService.taskRegistered = false;
    BackgroundTaskService.suspended = false;
    BackgroundTaskService.running = false;
    BackgroundTaskService.appliedModes = '';
    BackgroundTaskService.taskGeneration++;
  }

  private static async stopRunning(context: common.UIAbilityContext): Promise<void> {
    // 先使旧回调失效；挂起仍是已申请的任务，也必须显式释放。
    BackgroundTaskService.clearTask();
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      hilog.info(DOMAIN, TAG, 'stopBackgroundRunning ok');
    } catch (error) {
      DiagnosticLogService.failure('background.stop', error);
      hilog.warn(DOMAIN, TAG, 'stopBackgroundRunning: %{public}s', String(error));
    }
  }

  private static async sync(context: common.UIAbilityContext): Promise<void> {
    const modes: string[] = Array.from(BackgroundTaskService.requestedModes);
    if (modes.length > 0 && BackgroundTaskService.systemBlocked) return;
    try {
      if (modes.length === 0) {
        if (BackgroundTaskService.taskRegistered) await BackgroundTaskService.stopRunning(context);
        return;
      }

      if (BackgroundTaskService.suspended) await BackgroundTaskService.stopRunning(context);

      if (BackgroundTaskService.running) {
        if (BackgroundTaskService.appliedModes === modes.join(',')) return;
        try {
          const generation = BackgroundTaskService.taskGeneration;
          await backgroundTaskManager.updateBackgroundRunning(context, modes);
          if (generation !== BackgroundTaskService.taskGeneration) return;
          BackgroundTaskService.appliedModes = modes.join(',');
          hilog.info(DOMAIN, TAG, 'updateBackgroundRunning ok modes=%{public}s', modes.join(','));
          return;
        } catch (err) {
          // update 失败多半是任务已被系统取消，回退到重新 start
          const e = err as Error;
          hilog.warn(DOMAIN, TAG, 'updateBackgroundRunning failed, fallback start: %{public}s',
            e?.message ?? JSON.stringify(err));
          BackgroundTaskService.clearTask();
        }
      }

      if (BackgroundTaskService.systemBlocked) return;
      await BackgroundTaskService.startRunning(context, modes);
    } catch (err) {
      BackgroundTaskService.running = false;
      DiagnosticLogService.failure('background.sync', err, `modes=${modes.join(',')}`);
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'sync background modes failed: %{public}s modes=%{public}s',
        e?.message ?? JSON.stringify(err), modes.join(','));
    }
  }

  private static async startRunning(context: common.UIAbilityContext, modes: string[]): Promise<void> {
    const generation = BackgroundTaskService.taskGeneration;
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name,
        parameters: {
          from: 'continuous_task'
        }
      }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    BackgroundTaskService.starting = true;
    try {
      const agent = await wantAgent.getWantAgent(wantAgentInfo);
      if (generation !== BackgroundTaskService.taskGeneration || BackgroundTaskService.systemBlocked) return;
      const task = await backgroundTaskManager.startBackgroundRunning(context, modes, agent);
      // start 返回之前系统也可能取消/挂起任务，不能用迟到结果覆盖该状态。
      if (generation !== BackgroundTaskService.taskGeneration) return;
      BackgroundTaskService.taskId = task.continuousTaskId ?? -1;
      BackgroundTaskService.taskRegistered = true;
      BackgroundTaskService.running = true;
      BackgroundTaskService.appliedModes = modes.join(',');
      DiagnosticLogService.info('background.start', `id=${BackgroundTaskService.taskId}; modes=${modes.join(',')}`);
      hilog.info(DOMAIN, TAG, 'startBackgroundRunning ok modes=%{public}s', modes.join(','));
    } finally {
      BackgroundTaskService.starting = false;
    }
  }
}
