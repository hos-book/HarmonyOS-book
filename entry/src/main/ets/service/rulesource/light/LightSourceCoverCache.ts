import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/** Host-owned cache. Imported source rules never receive file access. */
export class LightSourceCoverCache {
  private static commitTail: Promise<void> = Promise.resolve();

  static async materialize(identity: string, load: () => Promise<Uint8Array>): Promise<string> {
    const root = AppStorage.get<string>('appCacheDir');
    if (!root) throw new Error('Cover cache unavailable');
    const dir = `${root}/source_covers`;
    if (!await fs.access(dir)) {
      try { await fs.mkdir(dir, true); } catch (error) { if (!await fs.access(dir)) throw error; }
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
    // Bound disk usage; oldest files are disposable and can be recreated from the original URL.
    const entries = (await Promise.all((await fs.listFile(dir)).map(async name => {
      const stat = await fs.stat(`${dir}/${name}`);
      return { name, size: stat.size, time: stat.mtime };
    }))).sort((a, b) => a.time - b.time);
    let size = entries.reduce((total, item) => total + item.size, 0);
    for (const item of entries) {
      if (size + bytes.length <= 64 * 1024 * 1024) break;
      try { await fs.unlink(`${dir}/${item.name}`); size -= item.size; } catch (_) { }
    }
    if (size + bytes.length > 64 * 1024 * 1024) throw new Error('Cover cache full');
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
    } catch (error) {
      if (!closed) { try { await fs.close(file); } catch (_) { } }
      try { await fs.unlink(temporary); } catch (_) { }
      throw error;
    }
  }
}
