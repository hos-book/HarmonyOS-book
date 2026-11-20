import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/** Host-owned cache. Imported source rules never receive file access. */
export class LightSourceCoverCache {
  private static commitTail: Promise<void> = Promise.resolve();
  private static indexedDir: string = '';
  // In insertion order from oldest to newest; only the serialized commit path writes this index.
  private static entries: Map<string, number> = new Map();
  private static cachedBytes: number = 0;

  static async materialize(identity: string, load: () => Promise<Uint8Array>): Promise<string> {
    const root = AppStorage.get<string>('appCacheDir');
    if (!root) throw new Error('Cover cache unavailable');
    const dir = `${root}/source_covers`;
    if (!await fs.access(dir)) {
      try { await fs.mkdir(dir, true); } catch (error) { if (!await fs.access(dir)) throw error; }
      LightSourceCoverCache.indexedDir = '';
    }
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: new util.TextEncoder().encodeInto('source-cover-v2\n' + identity) });
    const hash = Array.from((await digest.digest()).data).map(value => value.toString(16).padStart(2, '0')).join('');
    const path = `${dir}/${hash}.img`;
    if (await fs.access(path) && (await fs.stat(path)).size > 0) return `file://${path}`;
    const bytes = await load();
    if (bytes.length === 0 || bytes.length > 8 * 1024 * 1024) throw new Error('Invalid cover cache size');
    const commit = LightSourceCoverCache.commitTail.then(() => LightSourceCoverCache.commit(dir, path, bytes));
    LightSourceCoverCache.commitTail = commit.catch(() => {});
    await commit;
    return `file://${path}`;
  }

  private static async commit(dir: string, path: string, bytes: Uint8Array): Promise<void> {
    // Serialize eviction and publication, not network I/O. Four simultaneous covers still fit the disk budget.
    if (await fs.access(path) && (await fs.stat(path)).size > 0) return;
    await LightSourceCoverCache.loadIndex(dir);
    const name = path.substring(dir.length + 1);
    // A failed image or external cache cleanup may have removed this file since it was indexed.
    LightSourceCoverCache.forget(name);
    for (const entry of LightSourceCoverCache.entries) {
      if (LightSourceCoverCache.cachedBytes + bytes.length <= 64 * 1024 * 1024) break;
      const entryPath = `${dir}/${entry[0]}`;
      try {
        await fs.unlink(entryPath);
        LightSourceCoverCache.forget(entry[0]);
      } catch (error) {
        if (!await fs.access(entryPath)) LightSourceCoverCache.forget(entry[0]);
      }
    }
    if (LightSourceCoverCache.cachedBytes + bytes.length > 64 * 1024 * 1024) throw new Error('Cover cache full');
    const temporary = `${path}.tmp`;
    const file = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    let closed = false;
    try {
      const buffer = bytes.slice().buffer;
      let offset = 0;
      while (offset < bytes.length) {
        const written = await fs.write(file.fd, buffer.slice(offset));
        if (written <= 0 || written > bytes.length - offset) throw new Error('Incomplete cover cache write');
        offset += written;
      }
      await fs.close(file);
      closed = true;
      await fs.rename(temporary, path);
      LightSourceCoverCache.forget(`${name}.tmp`);
      LightSourceCoverCache.entries.set(name, bytes.length);
      LightSourceCoverCache.cachedBytes += bytes.length;
    } catch (error) {
      if (!closed) { try { await fs.close(file); } catch (_) { } }
      try { await fs.unlink(temporary); } catch (_) { }
      LightSourceCoverCache.indexedDir = '';
      throw error;
    }
  }

  private static forget(name: string): void {
    LightSourceCoverCache.cachedBytes -= LightSourceCoverCache.entries.get(name) ?? 0;
    LightSourceCoverCache.entries.delete(name);
  }

  private static async loadIndex(dir: string): Promise<void> {
    if (LightSourceCoverCache.indexedDir === dir) return;
    const names = await fs.listFile(dir);
    const entries: { name: string; size: number; time: number }[] = [];
    // Scan once after startup/cleanup, with bounded I/O instead of thousands of simultaneous callbacks.
    for (let start = 0; start < names.length; start += 16) {
      await Promise.all(names.slice(start, start + 16).map(async name => {
        const path = `${dir}/${name}`;
        try {
          const stat = await fs.stat(path);
          entries.push({ name, size: stat.size, time: stat.mtime });
        } catch (error) { if (await fs.access(path)) throw error; }
      }));
    }
    entries.sort((a, b) => a.time - b.time);
    LightSourceCoverCache.entries.clear();
    LightSourceCoverCache.cachedBytes = 0;
    for (const entry of entries) {
      LightSourceCoverCache.entries.set(entry.name, entry.size);
      LightSourceCoverCache.cachedBytes += entry.size;
    }
    LightSourceCoverCache.indexedDir = dir;
  }
}
