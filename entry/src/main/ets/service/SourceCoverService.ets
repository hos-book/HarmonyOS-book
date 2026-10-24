import { SourceCoverUrl } from './rulesource/light/upstream/core/nativesource/SourceCoverUrl';
import { LightSourceBridge } from './rulesource/light/LightSourceBridge';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';
import fs from '@ohos.file.fs';

/** Lazy source cover resolution, with bounded parallelism and request coalescing. */
export class SourceCoverService {
  private static inFlight: Map<string, Promise<string>> = new Map<string, Promise<string>>();
  private static active: number = 0;
  private static queue: (() => void)[] = [];
  private static resolved: Map<string, string> = new Map<string, string>();
  private static cacheRevision: number = -1;

  static isEncoded(raw: string): boolean { return SourceCoverUrl.isEncoded(raw); }

  /** 页面/书卡重建直接复用已物化文件，缓存被清理时才重新加载。 */
  static cached(raw: string): string {
    const revision = LocalRuleSourceRepository.getCoverRevision();
    if (SourceCoverService.cacheRevision !== revision) {
      SourceCoverService.resolved.clear();
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
      const source = await LocalRuleSourceRepository.get(SourceCoverUrl.source(raw));
      if (source === undefined) throw new Error('Cover source no longer installed');
      const sessionKey = await LocalRuleSourceRepository.getCoverSessionKey(source.bookSourceUrl);
      const result = await LightSourceBridge.cover(source, raw, sessionKey);
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
}
