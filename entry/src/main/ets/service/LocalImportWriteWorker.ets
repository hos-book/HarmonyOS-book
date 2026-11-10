import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

/** 在后台连续写入一批小文件，避免每章三次异步 I/O 往返主线程。 */
@Concurrent
export function writeLocalImportBatch(paths: string[], contents: string[]): void {
  if (paths.length !== contents.length) throw new Error('Invalid import write batch');
  const encoder = util.TextEncoder.create('utf-8');
  for (let index = 0; index < paths.length; index++) {
    const bytes = encoder.encodeInto(contents[index]).buffer;
    const file = fileIo.openSync(paths[index], fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      let offset = 0;
      while (offset < bytes.byteLength) {
        const count = fileIo.writeSync(file.fd, offset === 0 ? bytes : bytes.slice(offset));
        if (count <= 0) throw new Error('Incomplete imported chapter');
        offset += count;
      }
    } finally { fileIo.closeSync(file); }
  }
}
