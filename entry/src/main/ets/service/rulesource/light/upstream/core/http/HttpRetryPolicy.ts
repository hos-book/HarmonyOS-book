/** Explicit native-source retry policy. Numeric retry keeps its legacy semantics. */
export interface HttpRetrySpec {
  times: number;
  onStatus?: number[];
  backoff?: 'fixed' | 'exp';
  base?: number;
  maxDelay?: number;
  respectRetryAfter?: boolean;
}

export class HttpRetryPolicy {
  static parse(value: Object | undefined | null): number | HttpRetrySpec {
    if (value === undefined || value === null) return 0;
    // Preserve the previous numeric/coercion behavior for existing sources.
    if (typeof value !== 'object') return Math.max(0, Math.min(Math.floor(Number(value) || 0), 3));
    if (Array.isArray(value)) throw new Error('retry 必须是次数或策略对象');
    const spec = value as HttpRetrySpec;
    const keys = ['times', 'onStatus', 'backoff', 'base', 'maxDelay', 'respectRetryAfter'];
    if (Object.keys(value).some((key: string): boolean => !keys.includes(key))) throw new Error('retry 包含未知字段');
    this.integer(spec.times, 'times', 0, 3);
    const statuses = spec.onStatus === undefined ? [429, 503] : spec.onStatus;
    if (!Array.isArray(statuses) || statuses.some((status: number): boolean =>
      typeof status !== 'number' || !Number.isInteger(status) || status < 400 || status > 599)) {
      throw new Error('retry.onStatus 必须是 400–599 的状态码数组');
    }
    const base = spec.base === undefined ? 800 : spec.base;
    const maxDelay = spec.maxDelay === undefined ? 10000 : spec.maxDelay;
    this.integer(base, 'base', 1, 60000);
    this.integer(maxDelay, 'maxDelay', base, 60000);
    if (spec.backoff !== undefined && spec.backoff !== 'fixed' && spec.backoff !== 'exp') {
      throw new Error('retry.backoff 必须是 fixed 或 exp');
    }
    if (spec.respectRetryAfter !== undefined && typeof spec.respectRetryAfter !== 'boolean') {
      throw new Error('retry.respectRetryAfter 必须是布尔值');
    }
    return { times: spec.times, onStatus: statuses.slice(), backoff: spec.backoff || 'exp', base: base,
      maxDelay: maxDelay, respectRetryAfter: spec.respectRetryAfter !== false };
  }

  static delay(spec: HttpRetrySpec, retryIndex: number, headers: Record<string, string>, now: number): number {
    let delay = Math.min(spec.maxDelay!, spec.base! * (spec.backoff === 'exp' ? Math.pow(2, retryIndex) : 1));
    if (spec.respectRetryAfter) {
      const key = Object.keys(headers || {}).find((name: string): boolean => name.toLowerCase() === 'retry-after');
      const text = key ? String(headers[key]).trim() : '';
      const serverDelay = /^\d+$/.test(text) ? Number(text) * 1000 : Date.parse(text) - now;
      // A server delay above the configured cap means "do not retry", not "retry earlier".
      if (Number.isFinite(serverDelay)) delay = Math.max(delay, serverDelay);
    }
    return delay > spec.maxDelay! ? -1 : delay;
  }

  static async wait(ms: number, cancelled: () => boolean, deadlineAt: number): Promise<boolean> {
    const until = Date.now() + ms;
    if (deadlineAt && until >= deadlineAt) return false;
    while (Date.now() < until) {
      if (cancelled() || (deadlineAt > 0 && Date.now() >= deadlineAt)) return false;
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, Math.min(50, Math.max(1, until - Date.now()))); });
    }
    return !cancelled() && (!deadlineAt || Date.now() < deadlineAt);
  }

  private static integer(value: number, field: string, min: number, max: number): void {
    if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) {
      throw new Error(`retry.${field} 必须是 ${min}–${max} 的整数`);
    }
  }
}
