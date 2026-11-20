import { SourceCoverUrl } from './rulesource/light/upstream/core/nativesource/SourceCoverUrl';
import { LightSourceBridge, LightSourceCoverSession } from './rulesource/light/LightSourceBridge';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';
import fs from '@ohos.file.fs';

/** Lazy source cover resolution, with bounded parallelism and request coalescing. */
export class SourceCoverService {
  private static inFlight: Map<string, Promise<string>> = new Map<string, Promise<string>>();
  private static active: number = 0;
  private static queue: (() => void)[] = [];
  private static resolved: Map<string, string> = new Map<string, string>();
  private static cacheRevision: number = -1;
  private static sessions: Map<string, LightSourceCoverSession> = new Map();
  private static sessionLoads: Map<string, Promise<LightSourceCoverSession>> = new Map();
  private static sessionChars: number = 0;

  static isEncoded(raw: string): boolean { return SourceCoverUrl.isEncoded(raw); }

  /** 页面/书卡重建直接复用已物化文件，缓存被清理时才重新加载。 */
  static cached(raw: string): string {
    const revision = LocalRuleSourceRepository.getCoverRevision();
    if (SourceCoverService.cacheRevision !== revision) {
      SourceCoverService.resolved.clear();
      SourceCoverService.sessions.clear();
      SourceCoverService.sessionChars = 0;
      SourceCoverService.cacheRevision = revision;
    }
    const path = SourceCoverService.resolved.get(raw);
    if (path === undefined) return '';
    try {
      if (fs.accessSync(path.replace(/^file:\/\//, ''))) {
        SourceCoverService.resolved.delete(raw);
        SourceCoverService.resolved.set(raw, path);
        return path;
      }
    } catch (_error) {}
    SourceCoverService.resolved.delete(raw);
    return '';
  }

  static invalidate(raw: string): void {
    const path = SourceCoverService.resolved.get(raw);
    SourceCoverService.resolved.delete(raw);
    if (path !== undefined) {
      try { fs.unlinkSync(path.replace(/^file:\/\//, '')); } catch (_error) {}
    }
  }

  static async resolve(raw: string): Promise<string> {
    if (!SourceCoverUrl.isEncoded(raw)) return raw;
    const cached = SourceCoverService.cached(raw);
    if (cached) return cached;
    const revision = LocalRuleSourceRepository.getCoverRevision();
    const key = `${revision}:${raw}`;
    const existing = SourceCoverService.inFlight.get(key);
    if (existing !== undefined) return existing;
    if (SourceCoverService.inFlight.size >= 64) throw new Error('Cover queue full');
    const pending = SourceCoverService.load(raw, revision);
    SourceCoverService.inFlight.set(key, pending);
    try { return await pending; } finally { SourceCoverService.inFlight.delete(key); }
  }

  private static async load(raw: string, revision: number): Promise<string> {
    if (SourceCoverService.active >= 3) {
      await new Promise<void>((resolve: () => void): void => { SourceCoverService.queue.push(resolve); });
    } else {
      SourceCoverService.active++;
    }
    try {
      const session = await SourceCoverService.getSession(SourceCoverUrl.source(raw), revision);
      if (revision !== LocalRuleSourceRepository.getCoverRevision()) throw new Error('Cover session changed');
      const result = await session.load(raw);
      if (revision !== LocalRuleSourceRepository.getCoverRevision()) throw new Error('Cover session changed');
      SourceCoverService.resolved.set(raw, result);
      for (const key of SourceCoverService.resolved.keys()) {
        if (SourceCoverService.resolved.size <= 256) break;
        SourceCoverService.resolved.delete(key);
      }
      return result;
    } finally {
      const next = SourceCoverService.queue.shift();
      if (next !== undefined) next();
      else SourceCoverService.active--;
    }
  }

  private static async getSession(sourceUrl: string, revision: number): Promise<LightSourceCoverSession> {
    if (revision !== LocalRuleSourceRepository.getCoverRevision()) throw new Error('Cover session changed');
    const key = `${revision}:${sourceUrl}`;
    const cached = SourceCoverService.sessions.get(key);
    if (cached !== undefined) {
      SourceCoverService.sessions.delete(key);
      SourceCoverService.sessions.set(key, cached);
      return cached;
    }
    const existing = SourceCoverService.sessionLoads.get(key);
    if (existing !== undefined) return existing;
    const pending = SourceCoverService.loadSession(sourceUrl, revision);
    SourceCoverService.sessionLoads.set(key, pending);
    try {
      const session = await pending;
      if (revision !== LocalRuleSourceRepository.getCoverRevision()) throw new Error('Cover session changed');
      // Bound both entry count and serialized definition size; a large source remains usable without retention.
      if (session.size <= 2 * 1024 * 1024) {
        for (const entry of SourceCoverService.sessions) {
          if (SourceCoverService.sessions.size < 8 &&
            SourceCoverService.sessionChars + session.size <= 2 * 1024 * 1024) break;
          SourceCoverService.sessionChars -= entry[1].size;
          SourceCoverService.sessions.delete(entry[0]);
        }
        SourceCoverService.sessions.set(key, session);
        SourceCoverService.sessionChars += session.size;
      }
      return session;
    } finally {
      SourceCoverService.sessionLoads.delete(key);
    }
  }

  private static async loadSession(sourceUrl: string, revision: number): Promise<LightSourceCoverSession> {
    const source = await LocalRuleSourceRepository.get(sourceUrl);
    if (source === undefined) throw new Error('Cover source no longer installed');
    const sessionKey = await LocalRuleSourceRepository.getCoverSessionKey(sourceUrl);
    if (revision !== LocalRuleSourceRepository.getCoverRevision()) throw new Error('Cover session changed');
    return LightSourceBridge.prepareCoverSession(source, sessionKey);
  }
}
