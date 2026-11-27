/** Application scheduling metadata; never part of an imported definition or script variables. */
export class LightSourceRequest {
  priority: number = 1;
  cancelCheck?: () => boolean;
  diagnosticContext: string = '';
  private cancelled: boolean = false;
  constructor(priority: number = 1) { this.priority = priority; }
  isCancelled(): boolean { return this.cancelled || !!this.cancelCheck?.(); }
  promote(): void { this.priority = 2; LightSourceRequestPolicy.notify(); }
  cancel(): void { this.cancelled = true; LightSourceRequestPolicy.notify(); }
}

export class LightSourceRateWaiter {
  request?: LightSourceRequest;
  cancelCheck?: () => boolean;
  wake?: () => void;
  isCancelled(): boolean { return !!this.request?.isCancelled() || !!this.cancelCheck?.(); }
  rank(): number { return this.request?.priority ?? 1; }
  wait(ms: number): Promise<void> {
    return new Promise<void>(resolve => {
      const finish = (): void => {
        clearTimeout(timer);
        this.wake = undefined;
        resolve();
      };
      const timer = setTimeout(finish, ms);
      this.wake = finish;
    });
  }
}

/** Priority only chooses the next waiter; the upstream limiter still owns its frequency window. */
export class LightSourceRequestPolicy {
  private static contexts = new WeakMap<Object, LightSourceRequest>();
  private static waiters = new Map<string, LightSourceRateWaiter[]>();
  static bind(source: Object, request?: LightSourceRequest): void {
    if (request) this.contexts.set(source, request);
  }
  static copy(source: Object, target: Object): void { this.bind(target, this.contexts.get(source)); }
  static isCancelled(source: Object | null): boolean { return !!(source && this.contexts.get(source)?.isCancelled()); }
  static priority(source: Object | null): number { return source ? this.contexts.get(source)?.priority ?? 1 : 1; }
  static enqueue(key: string, source: Object, cancelCheck?: () => boolean): LightSourceRateWaiter {
    const waiter = new LightSourceRateWaiter();
    waiter.request = this.contexts.get(source);
    waiter.cancelCheck = cancelCheck;
    const queue = this.waiters.get(key) || [];
    queue.push(waiter);
    this.waiters.set(key, queue);
    this.notify();
    return waiter;
  }
  static first(key: string, waiter: LightSourceRateWaiter): boolean {
    let first: LightSourceRateWaiter | undefined;
    for (const candidate of this.waiters.get(key) || []) {
      if (candidate.isCancelled()) continue;
      if (!first || candidate.rank() > first.rank()) first = candidate;
    }
    return first === waiter;
  }
  static remove(key: string, waiter: LightSourceRateWaiter): void {
    const queue = (this.waiters.get(key) || []).filter(item => item !== waiter);
    if (queue.length) this.waiters.set(key, queue);
    else this.waiters.delete(key);
    this.notify();
  }
  static notify(): void {
    for (const queue of this.waiters.values()) {
      for (const waiter of queue) waiter.wake?.();
    }
  }
}
