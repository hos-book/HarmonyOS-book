import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/** Host-owned cache. Imported source rules never receive file access. */
export class LightSourceCoverCache {
  static async materialize(identity: string, load: () => Promise<Uint8Array>): Promise<string> {
    const root = AppStorage.get<string>('appCacheDir');
    if (!root) throw new Error('Cover cache unavailable');
    const dir = `${root}/source_covers`;
    if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: new util.TextEncoder().encodeInto('source-cover-v2\n' + identity) });
    const hash = Array.from((await digest.digest()).data).map(value => value.toString(16).padStart(2, '0')).join('');
    const path = `${dir}/${hash}.img`;
    if (fs.accessSync(path) && fs.statSync(path).size > 0) return `file://${path}`;
    const bytes = await load();
    // Bound disk usage; oldest files are disposable and can be recreated from the original URL.
    const entries = fs.listFileSync(dir).map(name => {
      const stat = fs.statSync(`${dir}/${name}`);
      return { name, size: stat.size, time: stat.mtime };
    }).sort((a, b) => a.time - b.time);
    let size = entries.reduce((total, item) => total + item.size, 0);
    for (const item of entries) {
      if (size + bytes.length <= 64 * 1024 * 1024) break;
      try { fs.unlinkSync(`${dir}/${item.name}`); size -= item.size; } catch (_) { }
    }
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      const buffer = bytes.slice().buffer;
      if (fs.writeSync(file.fd, buffer) !== bytes.length) throw new Error('Incomplete cover cache write');
    } catch (error) {
      try { fs.unlinkSync(path); } catch (_) { }
      throw error;
    } finally { fs.closeSync(file); }
    return `file://${path}`;
  }
}
