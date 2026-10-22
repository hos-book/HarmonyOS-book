import { BusinessError } from '@kit.BasicServicesKit';
import { DiagnosticLogService } from './DiagnosticLogService';

/** 最多四个在途 I/O；任一个完成即补位，全部收尾后才允许调用方删除目录。 */
export class LocalImportTaskQueue {
  private pending: Promise<void>[] = [];
  private failure: string = '';
  private active: number = 0;
  private busySince: number = 0;
  waitMs: number = 0;
  busyMs: number = 0;

  async add(task: () => Promise<void>): Promise<void> {
    if (this.failure.length > 0) throw new Error(this.failure);
    if (this.active++ === 0) this.busySince = Date.now();
    const job = this.run(task);
    this.pending.push(job);
    job.then((): void => {
      const index = this.pending.indexOf(job);
      if (index >= 0) this.pending.splice(index, 1);
    });
    if (this.pending.length >= 4) {
      const started = Date.now();
      await Promise.race(this.pending);
      this.waitMs += Date.now() - started;
      if (this.failure.length > 0) throw new Error(this.failure);
    }
  }

  private async run(task: () => Promise<void>): Promise<void> {
    try { await task(); }
    catch (error) {
      const detail: BusinessError = error;
      if (this.failure.length === 0) this.failure = DiagnosticLogService.describe(detail) || 'Import I/O failed';
    } finally {
      if (--this.active === 0) this.busyMs += Date.now() - this.busySince;
    }
  }

  /** 不重新抛错，保证失败清理不会与仍在执行的文件操作竞争。 */
  async settle(): Promise<void> {
    const started = Date.now();
    await Promise.all(this.pending);
    this.pending = [];
    this.waitMs += Date.now() - started;
  }

  async finish(): Promise<void> {
    await this.settle();
    if (this.failure.length > 0) throw new Error(this.failure);
  }
}
