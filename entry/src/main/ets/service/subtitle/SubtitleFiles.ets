import { fileIo, statfs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export class SubtitleFiles {
  static remove(path: string): void {
    try { fileIo.unlinkSync(path); } catch (_error) {}
  }

  static async digest(path: string, active: () => boolean): Promise<string> {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const size = fileIo.statSync(file.fd).size;
      const md = cryptoFramework.createMd('SHA256');
      let offset = 0;
      while (offset < size) {
        if (!active()) throw new Error('subtitle_cancelled');
        const buffer = new ArrayBuffer(Math.min(1024 * 1024, size - offset));
        const count = await fileIo.read(file.fd, buffer, { offset: offset });
        if (count !== buffer.byteLength) throw new Error('subtitle_file_read');
        await md.update({ data: new Uint8Array(buffer) });
        offset += count;
      }
      return SubtitleFiles.hex((await md.digest()).data);
    } finally { fileIo.closeSync(file); }
  }

  static async key(value: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: new util.TextEncoder().encodeInto(value) });
    return SubtitleFiles.hex((await md.digest()).data);
  }

  private static hex(bytes: Uint8Array): string {
    let result = '';
    for (const byte of bytes) result += byte.toString(16).padStart(2, '0');
    return result;
  }

  /** Bounded streaming write: no entire audio/model in JS memory, no unbounded write queue. */
  static async download(url: string, headers: Record<string, string>, path: string, maxBytes: number,
    active: () => boolean, progress: (bytes: number) => void): Promise<void> {
    const parent = path.substring(0, path.lastIndexOf('/'));
    if (statfs.getFreeSizeSync(parent) < maxBytes + 32 * 1024 * 1024) throw new Error('subtitle_space');
    const client = http.createHttp();
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    let received = 0;
    let failure = '';
    let success = false;
    const deadline = Date.now() + 900000;
    const timer = setInterval((): void => {
      if (!active() || Date.now() > deadline) {
        failure = active() ? 'subtitle_download_timeout' : 'subtitle_cancelled';
        client.destroy();
      }
    }, 250);
    try {
      client.on('dataReceive', (chunk: ArrayBuffer): void => {
        if (failure) return;
        if (!active() || received + chunk.byteLength > maxBytes) {
          failure = active() ? 'subtitle_too_large' : 'subtitle_cancelled';
          client.destroy(); return;
        }
        try {
          if (fileIo.writeSync(file.fd, chunk) !== chunk.byteLength) throw new Error('subtitle_file_write');
          received += chunk.byteLength;
          progress(received);
        } catch (_error) { failure = 'subtitle_file_write'; client.destroy(); }
      });
      const status = await client.requestInStream(url, { method: http.RequestMethod.GET, header: headers,
        connectTimeout: 15000, readTimeout: 900000, usingCache: false });
      if (failure || !active()) throw new Error(failure || 'subtitle_cancelled');
      if (status !== 200 || received < 64) throw new Error('subtitle_download_failed');
      success = true;
    } finally {
      clearInterval(timer); client.destroy(); fileIo.closeSync(file);
      if (!success) SubtitleFiles.remove(path);
    }
  }
}
