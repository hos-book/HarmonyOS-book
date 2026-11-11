import { BookSource } from '../../model/data/Book';
import { SourceRuntimeStage } from './BookSourceRuntimeRouter';
import { BookSourceStageWebRuntime, StageWebRuntimeRequest } from './BookSourceStageWebRuntime';

interface BookSourceHeaderRuntimeEntry {
  headers: Record<string, string>;
  expiresAt: number;
}

export interface BookSourceHeaderResult {
  headers: Record<string, string>;
  /** How long the result may be reused; 0 means the script runs again for the next request. */
  ttlMs: number;
}

/**
 * Resolves a source's `@js:` header rule in the bounded stage runtime so dynamic header values
 * (for example `"Referer": sourceUrl + '/'` or a Cookie assembled from source variables) reach
 * native AnalyzeUrl requests. The static literal-only extraction in AnalyzeUrl remains the
 * fallback whenever the runtime is unavailable.
 *
 * The script only reads source state (getVariable/getLoginHeader/...), so results are cached per
 * source URL + source variable and refreshed on a short TTL. A script whose values must change per
 * request (timestamps, nonces, signatures) opts out by returning the reserved `"@cache"` entry:
 * `false`/`0` disables caching, a positive number is a lifetime in seconds (at most the default
 * TTL). The entry is never sent as a header. Callers must still scope the result
 * to trusted hosts (AnalyzeUrl.isTrustedRequestHost) — a source's dynamic Cookie must never leak
 * to third-party content or image hosts.
 */
export class BookSourceHeaderRuntime {
  private static readonly TTL_MS: number = 5 * 60 * 1000;
  private static readonly MAX_ENTRIES: number = 32;
  private static readonly CACHE_KEY: string = '@cache';
  private static cache: Record<string, BookSourceHeaderRuntimeEntry> = {};

  /**
   * The JavaScript of a header rule written as `@js:…` or `<js>…</js>` (both are Legado forms), or an
   * empty string when the header is a literal block.
   */
  static script(header: string): string {
    const raw = (header || '').trim();
    if (/^@?js\s*:/i.test(raw)) return raw.replace(/^@?js\s*:/i, '');
    const block = /^<js>([\s\S]*)<\/js>$/i.exec(raw);
    return block ? block[1] : '';
  }

  static async resolve(source: BookSource): Promise<Record<string, string>> {
    const raw = BookSourceHeaderRuntime.script(source.header || '');
    if (!raw.trim()) return {};
    // Header scripts commonly read login fields (a token typed into the login form), so a login
    // change must not keep serving the previous headers for the rest of the TTL.
    const cacheKey = `${source.bookSourceUrl || ''}\n${source.variable || ''}\n${source.loginHeader || ''}\n` +
      `${BookSourceHeaderRuntime.hash(source.loginInfo || '')}`;
    const cached = BookSourceHeaderRuntime.cache[cacheKey];
    if (cached && cached.expiresAt > Date.now()) return cached.headers;
    const result = await BookSourceHeaderRuntime.evaluate(source, raw);
    if (result.ttlMs > 0) BookSourceHeaderRuntime.store(cacheKey, result.headers, result.ttlMs);
    else delete BookSourceHeaderRuntime.cache[cacheKey];
    return result.headers;
  }

  /** Test hook: drops every cached header resolution. */
  static clearCache(): void {
    BookSourceHeaderRuntime.cache = {};
  }

  private static async evaluate(source: BookSource, raw: string): Promise<BookSourceHeaderResult> {
    const failed: BookSourceHeaderResult = { headers: {}, ttlMs: BookSourceHeaderRuntime.TTL_MS };
    const runtime = BookSourceStageWebRuntime.get();
    if (!runtime.isAvailable() && !await runtime.waitUntilAvailable(1500)) return failed;
    const request = new StageWebRuntimeRequest();
    request.applyStageBudget(SourceRuntimeStage.URL);
    request.source = source;
    request.baseUrl = source.bookSourceUrl || '';
    request.code = raw;
    try {
      const result = await runtime.execute(request);
      return BookSourceHeaderRuntime.parseHeaderJson(result.value || '');
    } catch (_) {
      return failed;
    }
  }

  private static hash(value: string): string {
    let hash = 0;
    for (let index = 0; index < value.length; index++) hash = (hash * 31 + value.charCodeAt(index)) | 0;
    return `${value.length}:${hash}`;
  }

  /** Accepts either a JSON object or a JSON-encoded object string (the common script shape). */
  static parseHeaderJson(value: string): BookSourceHeaderResult {
    const result: BookSourceHeaderResult = { headers: {}, ttlMs: BookSourceHeaderRuntime.TTL_MS };
    let current: Object = value;
    for (let depth = 0; depth < 2; depth++) {
      const text = String(current ?? '').trim();
      if (!text.startsWith('{')) {
        if (depth === 0 && text.startsWith('"')) {
          try {
            current = JSON.parse(text);
            continue;
          } catch (_) {
          }
        }
        return result;
      }
      try {
        const parsed = JSON.parse(text) as Record<string, Object>;
        for (const key of Object.keys(parsed)) {
          const item = parsed[key];
          if (!key || item === undefined || item === null || typeof item === 'object') continue;
          if (key.toLowerCase() === BookSourceHeaderRuntime.CACHE_KEY) {
            result.ttlMs = BookSourceHeaderRuntime.cacheLifetimeMs(item);
            continue;
          }
          result.headers[key] = String(item);
        }
        return result;
      } catch (_) {
        return result;
      }
    }
    return result;
  }

  private static cacheLifetimeMs(value: Object): number {
    const text = String(value).trim().toLowerCase();
    if (text === 'false') return 0;
    const seconds = Number(text);
    if (text === '' || !Number.isFinite(seconds) || seconds < 0) return BookSourceHeaderRuntime.TTL_MS;
    return Math.min(BookSourceHeaderRuntime.TTL_MS, Math.round(seconds * 1000));
  }

  private static store(cacheKey: string, headers: Record<string, string>, ttlMs: number): void {
    BookSourceHeaderRuntime.cache[cacheKey] = { headers: headers, expiresAt: Date.now() + ttlMs };
    const keys = Object.keys(BookSourceHeaderRuntime.cache);
    if (keys.length <= BookSourceHeaderRuntime.MAX_ENTRIES) return;
    keys.sort((left: string, right: string): number =>
      (BookSourceHeaderRuntime.cache[left]?.expiresAt || 0) - (BookSourceHeaderRuntime.cache[right]?.expiresAt || 0));
    while (keys.length > BookSourceHeaderRuntime.MAX_ENTRIES) {
      const oldest = keys.shift();
      if (oldest === undefined) break;
      delete BookSourceHeaderRuntime.cache[oldest];
    }
  }
}
