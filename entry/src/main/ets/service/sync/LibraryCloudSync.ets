import { cloudSync } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export enum LibraryCloudIssue { NONE, NETWORK, WIFI, BATTERY, CLOUD_FULL, LOCAL_FULL, HOT, SERVER, NOT_READY, STOPPED, TIMEOUT, SYSTEM }

/** 一个实例监听和触发；调用完成只代表请求已接收，COMPLETED 仍须逐文件确认。 */
@ObservedV2
export class LibraryCloudSync {
  @Trace issue: LibraryCloudIssue = LibraryCloudIssue.NONE;
  @Trace systemCode: number = 0;
  @Trace transferring: boolean = false;
  @Trace lastCompletedAt: number = 0;
  private client: cloudSync.FileSync | null = null;
  private callback: ((progress: cloudSync.SyncProgress) => void) | null = null;
  private generation: number = 0;
  private lastStartAt: number = 0;
  private inFlight: boolean = false;
  private starting: boolean = false;
  private startPending: boolean = false;
  private buffered: cloudSync.SyncProgress | null = null;
  private watchdog: number = -1;
  private waiters: Set<(completed: boolean) => void> = new Set();
  private current: () => boolean;
  private changed: () => void;

  constructor(current: () => boolean, changed: () => void) {
    this.current = current;
    this.changed = changed;
  }

  private finish(completed: boolean): void {
    this.inFlight = false;
    this.transferring = false;
    if (this.watchdog >= 0) clearTimeout(this.watchdog);
    this.watchdog = -1;
    for (const done of Array.from(this.waiters)) done(completed);
  }

  private progress(progress: cloudSync.SyncProgress): void {
    if (!this.current()) return;
    if (this.starting) { this.buffered = progress; return; }
    // 系统完成后可能再发送无错误 STOPPED，表示本轮空闲，不撤销已完成结果。
    if (progress.state === cloudSync.SyncState.STOPPED && progress.error === cloudSync.ErrorType.NO_ERROR &&
      !this.inFlight && this.lastCompletedAt > 0) return;
    const previous = this.issue;
    this.issue = LibraryCloudSync.fromProgress(progress.error);
    this.systemCode = progress.error;
    const terminal = progress.state === cloudSync.SyncState.COMPLETED || progress.state === cloudSync.SyncState.STOPPED ||
      progress.state === cloudSync.SyncState.UPLOAD_FAILED || progress.state === cloudSync.SyncState.DOWNLOAD_FAILED;
    if (progress.state === cloudSync.SyncState.STOPPED && this.issue === LibraryCloudIssue.NONE) this.issue = LibraryCloudIssue.STOPPED;
    if ((progress.state === cloudSync.SyncState.UPLOAD_FAILED || progress.state === cloudSync.SyncState.DOWNLOAD_FAILED) &&
      this.issue === LibraryCloudIssue.NONE) this.issue = LibraryCloudIssue.SERVER;
    if (terminal || this.issue !== LibraryCloudIssue.NONE) {
      const completed = progress.state === cloudSync.SyncState.COMPLETED && this.issue === LibraryCloudIssue.NONE;
      if (completed) this.lastCompletedAt = Date.now();
      this.finish(completed);
      hilog.info(0x0000, 'LibrarySync', 'cloud state=%{public}d error=%{public}d', progress.state, progress.error);
      this.changed();
    } else {
      this.transferring = true;
      if (previous !== this.issue) this.changed();
    }
  }

  async request(waitMs: number = 0): Promise<boolean> {
    if (!this.current()) return false;
    if (!this.inFlight && !this.startPending && Date.now() - this.lastStartAt >= 60000) {
      const token = this.generation;
      this.lastStartAt = Date.now();
      this.inFlight = true;
      this.starting = true;
      this.buffered = null;
      this.issue = LibraryCloudIssue.NONE;
      this.systemCode = 0;
      // start 自身挂起也有上界；超时不 stop 系统传输，仅释放本机等待。
      this.watchdog = setTimeout((): void => {
        if (token !== this.generation) return;
        this.starting = false;
        this.buffered = null;
        this.issue = LibraryCloudIssue.TIMEOUT;
        this.finish(false);
        this.changed();
      }, 120000);
      try {
        if (this.client === null) {
          const client = new cloudSync.FileSync();
          const callback = (value: cloudSync.SyncProgress): void => {
            if (token === this.generation && this.current()) this.progress(value);
          };
          client.on('progress', callback);
          this.client = client;
          this.callback = callback;
        }
        this.startPending = true;
        const task = this.client.start();
        task.then((): void => {
          this.startPending = false;
          if (token !== this.generation || !this.current()) return;
          this.starting = false;
          const pending = this.buffered;
          this.buffered = null;
          if (pending !== null) this.progress(pending);
        }).catch((error: BusinessError): void => {
          this.startPending = false;
          if (token !== this.generation || !this.current()) return;
          this.starting = false;
          this.issue = LibraryCloudSync.fromSystem(error.code);
          this.systemCode = error.code;
          this.finish(false);
          hilog.warn(0x0000, 'LibrarySync', 'cloud start failed code=%{public}d', error.code);
          this.changed();
        });
      } catch (error) {
        this.startPending = false;
        this.starting = false;
        this.issue = LibraryCloudSync.fromSystem(error.code);
        this.systemCode = error.code;
        this.finish(false);
        this.changed();
      }
    }
    if (!this.inFlight || waitMs <= 0) return !this.inFlight && this.issue === LibraryCloudIssue.NONE && this.lastCompletedAt > 0;
    return new Promise<boolean>((resolve): void => {
      const finish = (completed: boolean): void => {
        clearTimeout(timer);
        this.waiters.delete(finish);
        resolve(completed);
      };
      const timer = setTimeout((): void => finish(false), waitMs);
      this.waiters.add(finish);
    });
  }

  close(): void {
    this.generation++;
    if (this.client && this.callback) {
      try { this.client.off('progress', this.callback); } catch (_error) { }
    }
    this.client = null;
    this.callback = null;
    this.buffered = null;
    this.starting = false;
    this.finish(false);
    this.issue = LibraryCloudIssue.NONE;
    this.systemCode = 0;
    this.lastCompletedAt = 0;
    // 保留限频时间，短时间反复开关或手动备份不能绕过系统调用限制。
  }

  private static fromSystem(code: number): LibraryCloudIssue {
    if (code === 22400001) return LibraryCloudIssue.NOT_READY;
    if (code === 22400002) return LibraryCloudIssue.NETWORK;
    if (code === 22400003) return LibraryCloudIssue.BATTERY;
    return LibraryCloudIssue.SYSTEM;
  }

  private static fromProgress(error: cloudSync.ErrorType): LibraryCloudIssue {
    switch (error) {
      case cloudSync.ErrorType.NO_ERROR: return LibraryCloudIssue.NONE;
      case cloudSync.ErrorType.NETWORK_UNAVAILABLE: return LibraryCloudIssue.NETWORK;
      case cloudSync.ErrorType.WIFI_UNAVAILABLE: return LibraryCloudIssue.WIFI;
      case cloudSync.ErrorType.BATTERY_LEVEL_LOW:
      case cloudSync.ErrorType.BATTERY_LEVEL_WARNING: return LibraryCloudIssue.BATTERY;
      case cloudSync.ErrorType.CLOUD_STORAGE_FULL: return LibraryCloudIssue.CLOUD_FULL;
      case cloudSync.ErrorType.LOCAL_STORAGE_FULL: return LibraryCloudIssue.LOCAL_FULL;
      case cloudSync.ErrorType.DEVICE_TEMPERATURE_TOO_HIGH: return LibraryCloudIssue.HOT;
      case cloudSync.ErrorType.REMOTE_SERVER_ABNORMAL: return LibraryCloudIssue.SERVER;
      default: return LibraryCloudIssue.SYSTEM;
    }
  }
}
