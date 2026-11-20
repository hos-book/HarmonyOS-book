/**
 * Cooperative main-thread scheduling primitives.
 *
 * These helpers do not move CPU work to another thread. They keep the ArkUI event loop responsive
 * while a legacy synchronous pipeline is being migrated to Worker/TaskPool execution.
 */
export class CooperativeCancellationToken {
  private cancelledValue: boolean = false;
  private cancelReasonValue: string = '';

  cancel(reason: string = '任务已取消'): void {
    this.cancelledValue = true;
    this.cancelReasonValue = reason || '任务已取消';
  }

  isCancelled(): boolean {
    return this.cancelledValue;
  }

  reason(): string {
    return this.cancelReasonValue || '任务已取消';
  }

  throwIfCancelled(): void {
    if (this.cancelledValue) throw new Error(this.reason());
  }
}

export class CooperativeTimeSlice {
  private readonly budgetMs: number;
  private sliceStartedAt: number = Date.now();
  private operationCount: number = 0;

  constructor(budgetMs: number = 6) {
    this.budgetMs = Math.max(1, Math.min(Math.round(budgetMs), 12));
  }

  elapsedMs(): number {
    return Math.max(0, Date.now() - this.sliceStartedAt);
  }

  async checkpoint(token: CooperativeCancellationToken | null = null,
    force: boolean = false): Promise<boolean> {
    if (token) token.throwIfCancelled();
    this.operationCount++;
    if (!force && this.elapsedMs() < this.budgetMs) return false;
    await CooperativeScheduler.yieldToEventLoop();
    this.sliceStartedAt = Date.now();
    if (token) token.throwIfCancelled();
    return true;
  }

  operations(): number {
    return this.operationCount;
  }
}

interface PendingYield {
  resolve: () => void;
  readyAt: number;
}

export class CooperativeScheduler {
  static readonly DEFAULT_UI_SLICE_MS: number = 6;
  static readonly SLOW_OPERATION_MS: number = 16;
  static readonly DANGEROUS_OPERATION_MS: number = 50;

  static createTimeSlice(budgetMs: number = CooperativeScheduler.DEFAULT_UI_SLICE_MS): CooperativeTimeSlice {
    return new CooperativeTimeSlice(budgetMs);
  }

  /** 让出主线程：排进全局让出队列，至少隔 1 ms 再继续。 */
  static yieldToEventLoop(): Promise<void> {
    return CooperativeScheduler.enqueueYield(1);
  }

  /** 让出至少一帧（16 ms），给渲染和输入留出完整的间隙。 */
  static yieldToNextUiFrame(): Promise<void> {
    return CooperativeScheduler.enqueueYield(16);
  }

  /*
   * 全局让出队列。鸿蒙的定时器任务里，几个同时到期的短定时器会在同一个原生任务里接连执行：
   * 多个任务同时分片（例如连点几次刷新目录，或书架并发检查更新）时，各自 1 ms / 16 ms 的让出
   * 会互相把对方的定时器“跑到期”，主线程一直出不了这个任务，6 秒后被看门狗杀掉。
   * 所以所有让出共用一个定时器，每次到期只放行一个等待者；它跑完一个时间片再让出时才排下一次，
   * 两个时间片之间一定隔着一次事件循环。放行的任务没再让出（转去等网络等）时，用兜底定时器继续。
   */
  private static readonly YIELD_FALLBACK_MS: number = 16;
  private static yieldQueue: PendingYield[] = [];
  private static yieldTimer: number | null = null;
  private static yieldTimerAt: number = 0;

  private static enqueueYield(delayMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      CooperativeScheduler.yieldQueue.push({ resolve: resolve, readyAt: Date.now() + delayMs });
      CooperativeScheduler.armYieldTimer(delayMs);
    });
  }

  private static armYieldTimer(delayMs: number): void {
    const at = Date.now() + delayMs;
    if (CooperativeScheduler.yieldTimer !== null) {
      if (CooperativeScheduler.yieldTimerAt <= at) return;
      clearTimeout(CooperativeScheduler.yieldTimer);
    }
    CooperativeScheduler.yieldTimerAt = at;
    CooperativeScheduler.yieldTimer = setTimeout((): void => CooperativeScheduler.dispatchYield(), delayMs);
  }

  private static dispatchYield(): void {
    CooperativeScheduler.yieldTimer = null;
    const queue = CooperativeScheduler.yieldQueue;
    if (queue.length === 0) return;
    const now = Date.now();
    let index = -1;
    let earliest = Number.MAX_VALUE;
    for (let i = 0; i < queue.length; i++) {
      if (queue[i].readyAt <= now) {
        index = i;
        break;
      }
      earliest = Math.min(earliest, queue[i].readyAt);
    }
    if (index < 0) {
      CooperativeScheduler.armYieldTimer(Math.max(1, earliest - now));
      return;
    }
    const next = queue.splice(index, 1)[0];
    if (queue.length > 0) CooperativeScheduler.armYieldTimer(CooperativeScheduler.YIELD_FALLBACK_MS);
    next.resolve();
  }

  static reportSynchronousOperation(label: string, elapsedMs: number, detail: string = ''): void {
    if (elapsedMs < CooperativeScheduler.SLOW_OPERATION_MS) return;
    const suffix = detail ? ` ${detail}` : '';
    if (elapsedMs >= CooperativeScheduler.DANGEROUS_OPERATION_MS) {
      console.warn(`[MainThreadGuard] dangerous ${label}: ${elapsedMs}ms${suffix}`);
    } else {
      console.info(`[MainThreadGuard] slow ${label}: ${elapsedMs}ms${suffix}`);
    }
  }
}
