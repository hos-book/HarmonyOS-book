import { common } from '@kit.AbilityKit';
import { cloudSync, fileIo, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { LIBRARY_SYNC_MAX_BYTES } from './LibrarySyncModel';

export class LibraryCloudFile {
  name: string = '';
  deviceId: string = '';
  generation: number = 0;
}

export class LibraryUploadState {
  location: number = 0;
  state: cloudSync.FileState = cloudSync.FileState.TO_BE_UPLOADED;
  confirmed: boolean = false;
}

/** 文件只由其创建设备写入，其他设备只读；系统自动上传，不循环调用 FileSync.start。 */
export class LibrarySyncFiles {
  private cancelDownload: (() => void) | null = null;

  cancel(): void { this.cancelDownload?.(); }

  async list(context: common.Context, ownerKey: string): Promise<LibraryCloudFile[]> {
    const prefix = `library_v1_${ownerKey}_`;
    const result: LibraryCloudFile[] = [];
    for (const name of await fileIo.listFile(context.cloudFileDir)) {
      if (!name.startsWith(prefix)) continue;
      const suffix = name.substring(prefix.length);
      const match = /^([0-9a-f-]{36})_([0-9]+)_([0-9a-f-]{36})\.json$/.exec(suffix);
      if (!match) continue;
      const value = new LibraryCloudFile();
      value.name = name;
      value.deviceId = match[1];
      value.generation = Number(match[2]);
      if (Number.isSafeInteger(value.generation)) result.push(value);
      if (result.length > 4096) throw new Error('Too many sync files');
    }
    return result.sort((a: LibraryCloudFile, b: LibraryCloudFile): number =>
      b.generation - a.generation || (a.name < b.name ? -1 : 1));
  }

  async confirmed(path: string): Promise<boolean> {
    return (await this.uploadState(path)).confirmed;
  }

  async uploadState(path: string): Promise<LibraryUploadState> {
    const stat = await fileIo.stat(path);
    const state = cloudSync.getCoreFileSyncState(fileUri.getUriFromPath(path));
    const result = new LibraryUploadState();
    result.location = stat.location;
    result.state = state;
    result.confirmed = (stat.location & 2) !== 0 && (state === cloudSync.FileState.UPLOAD_SUCCESS ||
      state === cloudSync.FileState.INITIAL_AFTER_DOWNLOAD);
    return result;
  }

  async readCloud(path: string, guard: () => void): Promise<string> {
    guard();
    const stat = await fileIo.stat(path);
    if (!stat.isFile() || stat.size <= 0 || stat.size > LIBRARY_SYNC_MAX_BYTES) {
      throw new Error('Invalid sync file size');
    }
    guard();
    if (stat.location === 2) await this.download(fileUri.getUriFromPath(path), guard);
    guard();
    return LibrarySyncFiles.read(path);
  }

  private async download(uri: string, guard: () => void): Promise<void> {
    const task = new cloudSync.CloudFileCache();
    let complete = false;
    try {
      await new Promise<void>((resolve, reject) => {
        let done = false;
        let timer = -1;
        let accountTimer = -1;
        const finish = (error: Error | null): void => {
          if (done) return;
          done = true;
          clearTimeout(timer);
          clearInterval(accountTimer);
          try { task.off('progress', progress); } catch (_error) { }
          this.cancelDownload = null;
          if (error) reject(error); else resolve();
        };
        const progress = (value: cloudSync.DownloadProgress): void => {
          if (value.uri !== uri) return;
          if (value.state === cloudSync.State.COMPLETED) finish(null);
          else if (value.state === cloudSync.State.FAILED || value.state === cloudSync.State.STOPPED) {
            finish(new Error('Cloud download unavailable'));
          }
        };
        this.cancelDownload = (): void => finish(new Error('Sync cancelled'));
        timer = setTimeout((): void => finish(new Error('Cloud download timed out')), 30000);
        accountTimer = setInterval((): void => {
          try { guard(); } catch (_error) { finish(new Error('Sync account changed')); }
        }, 1000);
        try {
          task.on('progress', progress);
          task.start(uri).catch((_error: BusinessError): void => finish(new Error('Cloud download failed')));
        } catch (_error) { finish(new Error('Cloud download unavailable')); }
      });
      complete = true;
    } finally {
      if (!complete) { try { await task.stop(uri); } catch (_error) { } }
    }
  }

  static async read(path: string): Promise<string> {
    const input = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(input.fd);
      if (!stat.isFile() || stat.size <= 0 || stat.size > LIBRARY_SYNC_MAX_BYTES) throw new Error('Invalid sync size');
      const bytes = new ArrayBuffer(stat.size);
      let total = 0;
      // FileIO offset 是文件偏移；分段缓冲避免将短读覆写到已读前缀。
      const result = new Uint8Array(bytes);
      while (total < stat.size) {
        const part = new ArrayBuffer(Math.min(256 * 1024, stat.size - total));
        const count = await fileIo.read(input.fd, part, { offset: total, length: part.byteLength });
        if (count <= 0 || count > part.byteLength) throw new Error('Incomplete sync read');
        result.set(new Uint8Array(part, 0, count), total);
        total += count;
      }
      return new util.TextDecoder().decodeToString(result);
    } finally { await fileIo.close(input); }
  }

  static async write(path: string, raw: string, cloud: boolean = false, guard: () => void = (): void => {}): Promise<void> {
    const bytes = new util.TextEncoder().encodeInto(raw);
    if (bytes.byteLength > LIBRARY_SYNC_MAX_BYTES) throw new Error('Sync size limit exceeded');
    // 云文件使用唯一最终名称，close 提交给 FUSE；避免临时文件重命名后仍被系统标记为无需上传。
    // 本机队列继续原子替换，不能将此规则推广到本机持久化。
    const pending = cloud ? path : path + '.pending';
    guard();
    const file = await fileIo.open(pending, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    let complete = false;
    try {
      let total = 0;
      while (total < bytes.byteLength) {
        guard();
        const part = bytes.slice(total, Math.min(bytes.byteLength, total + 256 * 1024));
        const count = await fileIo.write(file.fd, part.buffer, { offset: total, length: part.byteLength });
        if (count <= 0 || count > part.byteLength) throw new Error('Incomplete sync write');
        total += count;
      }
      // 云目录由 FUSE 管理，close 提交；本机队列必须 fsync。
      if (!cloud) await fileIo.fsync(file.fd);
      complete = true;
    } finally {
      await fileIo.close(file);
      if (cloud && !complete) {
        try { await fileIo.unlink(path); } catch (_error) { }
      }
    }
    guard();
    if (!cloud) await fileIo.moveFile(pending, path);
  }
}
