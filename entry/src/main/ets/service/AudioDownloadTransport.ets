import { fileIo, statfs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { DownloadPolicy } from './DownloadPolicy';
import { AudioCacheNetworkPolicy } from './AudioCacheNetworkPolicy';

const MIN_AUDIO_FILE_BYTES = 1024;
const MIN_FREE_BYTES = 16 * 1024 * 1024;
const FREE_SPACE_RESERVE_BYTES = 8 * 1024 * 1024;
const UNKNOWN_LENGTH_SPACE_CHECK_BYTES = 4 * 1024 * 1024;
const RESPONSE_PREFIX_BYTES = 64;

export interface AudioDownloadRequest {
  url: string;
  headers: Record<string, string>;
  finalPath: string;
  onProgress?: (receivedBytes: number, totalBytes: number) => void;
}

export class AudioDownloadTransport {
  private request: http.HttpRequest | null = null;
  private cancelled: boolean = false;
  private networkInterrupted: boolean = false;

  cancel(): void {
    this.cancelled = true;
    if (this.request) {
      this.request.destroy();
    }
  }

  async download(options: AudioDownloadRequest): Promise<number> {
    const partPath = `${options.finalPath}.part`;
    let file: fileIo.File | null = null;
    let writeChain: Promise<void> = Promise.resolve();
    let writeErrorMessage = '';
    let writtenBytes = 0;
    let responseHeaders: Record<string, string> = {};
    let responsePrefix: ArrayBuffer = new ArrayBuffer(0);
    let nextUnknownLengthSpaceCheck = UNKNOWN_LENGTH_SPACE_CHECK_BYTES;
    let completed = false;

    this.cancelled = false;
    this.networkInterrupted = false;
    const network = AudioCacheNetworkPolicy.getInstance();
    const unsubscribe = network.subscribe((): void => {
      if (!network.isAllowed()) {
        this.networkInterrupted = true;
        this.cancel();
      }
    });
    await AudioDownloadTransport.deleteFile(partPath);
    await AudioDownloadTransport.deleteFile(`${options.finalPath}.swap`);
    try {
      if (!network.canTransfer()) throw new Error(AudioCacheNetworkPolicy.WAITING_WIFI);
      if (DownloadPolicy.isHls(options.url, '')) {
        throw new Error('暂不支持 HLS 音频离线下载');
      }
      AudioDownloadTransport.ensureFreeSpace(options.finalPath, MIN_FREE_BYTES);
      file = await fileIo.open(partPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      if (this.cancelled) throw new Error(this.networkInterrupted ? AudioCacheNetworkPolicy.WAITING_WIFI : '下载已取消');
      this.request = http.createHttp();
      this.request.on('headersReceive', (headers: Object) => {
        responseHeaders = AudioDownloadTransport.toHeaderRecord(headers);
        const contentLength = Number(AudioDownloadTransport.getHeader(responseHeaders, 'content-length'));
        if (contentLength > 0) {
          try {
            AudioDownloadTransport.ensureFreeSpace(options.finalPath, contentLength + FREE_SPACE_RESERVE_BYTES);
          } catch (err) {
            writeErrorMessage = err instanceof Error ? err.message : String(err);
            if (this.request) this.request.destroy();
          }
        }
      });
      this.request.on('dataReceive', (chunk: ArrayBuffer) => {
        if (this.cancelled || writeErrorMessage.length > 0 || chunk.byteLength === 0) return;
        responsePrefix = DownloadPolicy.appendPrefix(responsePrefix, chunk, RESPONSE_PREFIX_BYTES);
        writeChain = writeChain.then(async (): Promise<void> => {
          if (this.cancelled || writeErrorMessage.length > 0 || !file) return;
          // WriteOptions.offset 是文件内写入位置，不是 buffer 偏移。
          // 传 offset:0 会让每一块都覆盖文件头，最终只剩最后一块，
          // 但 writtenBytes 仍累计为完整大小，重启校验 size!==bytes 会整批失败。
          // 不传 offset，从当前文件指针顺序追加。
          const count = await fileIo.write(file.fd, chunk, { length: chunk.byteLength });
          if (count !== chunk.byteLength) {
            throw new Error(`音频文件写入不完整 ${count}/${chunk.byteLength}`);
          }
          writtenBytes += count;
          const contentLength = Number(AudioDownloadTransport.getHeader(responseHeaders, 'content-length'));
          if (!(contentLength > 0) && writtenBytes >= nextUnknownLengthSpaceCheck) {
            AudioDownloadTransport.ensureFreeSpace(options.finalPath, MIN_FREE_BYTES);
            nextUnknownLengthSpaceCheck = writtenBytes + UNKNOWN_LENGTH_SPACE_CHECK_BYTES;
          }
          if (options.onProgress) {
            options.onProgress(writtenBytes, contentLength > 0 ? contentLength : 0);
          }
        }).catch((err: Error): void => {
          writeErrorMessage = err.message;
          if (this.request) this.request.destroy();
        });
      });

      let responseCode = 0;
      try {
        if (!network.canTransfer()) throw new Error(AudioCacheNetworkPolicy.WAITING_WIFI);
        responseCode = await this.request.requestInStream(options.url, {
          method: http.RequestMethod.GET,
          header: options.headers,
          connectTimeout: 15000,
          readTimeout: 60000,
          usingCache: false
        });
      } catch (err) {
        await writeChain;
        if (writeErrorMessage.length > 0) throw new Error(writeErrorMessage);
        if (this.cancelled) throw new Error(this.networkInterrupted ? AudioCacheNetworkPolicy.WAITING_WIFI : '下载已取消');
        throw new Error(err instanceof Error ? err.message : String(err));
      }
      await writeChain;
      if (writeErrorMessage.length > 0) throw new Error(writeErrorMessage);
      if (this.cancelled) throw new Error(this.networkInterrupted ? AudioCacheNetworkPolicy.WAITING_WIFI : '下载已取消');
      if (responseCode !== 200) throw new Error(`下载失败 ${responseCode}`);

      const contentType = AudioDownloadTransport.getHeader(responseHeaders, 'content-type');
      if (DownloadPolicy.isHls(options.url, contentType)) {
        throw new Error('暂不支持 HLS 音频离线下载');
      }
      if (!DownloadPolicy.isAllowedAudioContentType(contentType)) {
        throw new Error(`响应不是音频内容${contentType ? ` (${contentType})` : ''}`);
      }
      const contentLength = Number(AudioDownloadTransport.getHeader(responseHeaders, 'content-length'));
      if (contentLength > 0 && writtenBytes !== contentLength) {
        throw new Error(`音频下载不完整 ${writtenBytes}/${contentLength}`);
      }
      if (writtenBytes <= MIN_AUDIO_FILE_BYTES) {
        throw new Error(`音频文件过小 (${writtenBytes} bytes)`);
      }
      if (DownloadPolicy.isClearlyTextResponse(responsePrefix)) {
        throw new Error('响应是文本错误页，不是有效音频');
      }
      if (!DownloadPolicy.hasKnownAudioSignature(responsePrefix)) {
        throw new Error('响应没有有效音频文件头');
      }

      if (file) {
        try { await fileIo.fsync(file.fd); } catch (_e) { /* best effort */ }
        await fileIo.close(file);
        file = null;
      }
      // 以磁盘真实大小为准：防止累计写入计数与落盘不一致（如错误 offset 覆盖）
      const partSize = fileIo.statSync(partPath).size;
      if (partSize !== writtenBytes) {
        throw new Error(`音频文件落盘不完整 ${partSize}/${writtenBytes}`);
      }
      if (contentLength > 0 && partSize !== contentLength) {
        throw new Error(`音频下载不完整 ${partSize}/${contentLength}`);
      }
      if (partSize <= MIN_AUDIO_FILE_BYTES) {
        throw new Error(`音频文件过小 (${partSize} bytes)`);
      }
      if (this.cancelled) throw new Error(this.networkInterrupted ? AudioCacheNetworkPolicy.WAITING_WIFI : '下载已取消');
      await AudioDownloadTransport.publishFinalFile(partPath, options.finalPath);
      const finalSize = fileIo.statSync(options.finalPath).size;
      if (finalSize !== partSize) {
        throw new Error(`音频文件落盘不完整 ${finalSize}/${partSize}`);
      }
      completed = true;
      return finalSize;
    } finally {
      unsubscribe();
      if (file) {
        try { await fileIo.close(file); } catch (_e) { /* ignore */ }
      }
      if (this.request) {
        this.request.destroy();
        this.request = null;
      }
      if (!completed) await AudioDownloadTransport.deleteFile(partPath);
    }
  }

  private static toHeaderRecord(headers: Object): Record<string, string> {
    const record = headers as Record<string, Object>;
    const result: Record<string, string> = {};
    for (const key of Object.keys(record)) {
      const value = record[key];
      if (value !== undefined && value !== null) result[key] = String(value);
    }
    return result;
  }

  private static getHeader(headers: Record<string, string>, name: string): string {
    const lower = name.toLowerCase();
    for (const key of Object.keys(headers)) {
      if (key.toLowerCase() === lower) return headers[key] || '';
    }
    return '';
  }

  private static async deleteFile(path: string): Promise<void> {
    try {
      if (await fileIo.access(path)) await fileIo.unlink(path);
    } catch (_e) {
      // File does not exist or has already been removed.
    }
  }

  private static async publishFinalFile(partPath: string, finalPath: string): Promise<void> {
    await fileIo.moveFile(partPath, finalPath, 0);
  }

  private static ensureFreeSpace(filePath: string, requiredBytes: number): void {
    const slash = filePath.lastIndexOf('/');
    const dir = slash > 0 ? filePath.substring(0, slash) : filePath;
    try {
      const freeBytes = statfs.getFreeSizeSync(dir);
      if (freeBytes < requiredBytes) {
        throw new Error(`存储空间不足，需要 ${requiredBytes} bytes，剩余 ${freeBytes} bytes`);
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (message.includes('存储空间不足')) throw new Error(message);
      throw new Error(`下载目录不可用: ${message}`);
    }
  }

}
