import { BookSource } from '../../model/data/Book';
import { SourceEngineHost } from '../host/SourceEngineHost';

class BookSourceRateState {
  timestamps: number[] = [];
}

/** Why a request may not be sent yet. */
export enum RateLimitAcquireResult {
  Acquired = 0,
  Cancelled = 1,
  // waited as long as allowed and the source's window is still full
  RateLimited = 2
}

/**
 * A native source stage that declares its own `rate`: its requests queue in a window of their own (keyed by
 * source + stage) instead of the source-level one. `0` or an empty value means that stage is not limited even
 * when the source is.
 */
export interface BookSourceStageRate {
  stage: string;
  rate: string;
}

export class BookSourceRateLimiter {
  // A Map, not an object: the key is source-supplied text and must never reach a prototype member.
  private static states: Map<string, BookSourceRateState> = new Map<string, BookSourceRateState>();
  // Sleep in slices so a cancelled caller is released promptly instead of after the whole window.
  private static readonly WAIT_SLICE_MS: number = 500;

  /**
   * Waits for a slot in the source's `concurrentRate` window.
   * @param isCancelled checked before every wait slice; a cancelled wait consumes no slot
   * @param maxWaitMs total waiting allowed; 0 (the default) waits as long as the window requires, which is what
   *   reading and caching want. Searching passes a cap: a source may declare windows of up to an hour.
   * @param stageRate a native stage's own `rate`, replacing the source-level one with a window of its own
   */
  static async acquire(source: BookSource | null, isCancelled?: () => boolean,
    maxWaitMs: number = 0, stageRate: BookSourceStageRate | null = null): Promise<RateLimitAcquireResult> {
    if (SourceEngineHost.isCancelled(source) || (isCancelled && isCancelled())) {
      return RateLimitAcquireResult.Cancelled;
    }
    if (!source) return RateLimitAcquireResult.Acquired;
    const rate = stageRate ? stageRate.rate : source.concurrentRate;
    if (!rate) return RateLimitAcquireResult.Acquired;
    const config = this.parse(rate);
    if (!config) return RateLimitAcquireResult.Acquired;
    const sourceKey = source.bookSourceUrl || source.bookSourceName;
    if (!sourceKey) return RateLimitAcquireResult.Acquired;
    const key = stageRate ? `${sourceKey}#rate:${stageRate.stage}` : sourceKey;
    const deadline = maxWaitMs > 0 ? Date.now() + maxWaitMs : 0;
    let state = this.states.get(key);
    if (!state) {
      state = new BookSourceRateState();
      this.states.set(key, state);
    }
    // Without a host scheduler the waiter only sleeps and `first` is always true, so the loop below behaves
    // exactly like the plain window wait. A host scheduler can make a waiter yield a free slot to a
    // higher-priority one; the window itself is still enforced here.
    const waiter = SourceEngineHost.enqueue(key, source, isCancelled);
    try {
      while (true) {
        if (waiter.isCancelled()) return RateLimitAcquireResult.Cancelled;
        const now = Date.now();
        state.timestamps = state.timestamps.filter(timestamp => now - timestamp < config.windowMs);
        if (state.timestamps.length < config.limit) {
          if (!SourceEngineHost.first(key, waiter)) {
            if (deadline > 0 && now >= deadline) return RateLimitAcquireResult.RateLimited;
            const slice = BookSourceRateLimiter.WAIT_SLICE_MS;
            await waiter.wait(deadline > 0 ? Math.min(slice, Math.max(1, deadline - now)) : slice);
            continue;
          }
          state.timestamps.push(now);
          return RateLimitAcquireResult.Acquired;
        }
        let waitMs = Math.max(1, state.timestamps[0] + config.windowMs - now);
        if (deadline > 0) {
          if (now >= deadline) return RateLimitAcquireResult.RateLimited;
          waitMs = Math.min(waitMs, deadline - now);
        }
        await waiter.wait(Math.min(waitMs, BookSourceRateLimiter.WAIT_SLICE_MS));
      }
    } finally {
      SourceEngineHost.remove(key, waiter);
    }
  }

  /**
   * `count/windowMs` allows `count` requests per window. A bare number is Legado's interval form:
   * `1000` leaves at least 1000 ms between two requests, i.e. one request per window. `0` and
   * anything unrecognised mean no source-level limit.
   */
  static parse(value: string): { limit: number, windowMs: number } | null {
    const text = (value || '').trim();
    const interval = text.match(/^(\d+)$/);
    if (interval) {
      const intervalMs = parseInt(interval[1]);
      return intervalMs > 0 ? { limit: 1, windowMs: Math.min(60 * 60 * 1000, intervalMs) } : null;
    }
    const match = text.match(/^(\d+)\s*\/\s*(\d+)$/);
    if (!match) return null;
    const limit = Math.min(1000, Math.max(1, parseInt(match[1])));
    const windowMs = Math.min(60 * 60 * 1000, Math.max(100, parseInt(match[2])));
    return { limit: limit, windowMs: windowMs };
  }
}
