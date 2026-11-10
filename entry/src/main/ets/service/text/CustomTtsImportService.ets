import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { CustomTtsConfig, CustomTtsImportResult } from '../../model/CustomTtsConfig';
import { CustomTtsConfigParser } from './CustomTtsConfigParser';

export class CustomTtsImportService {
  static readonly MAX_FILES: number = 50;
  private static readonly IMPORT_CONCURRENCY: number = 4;

  static async fromUrl(input: string): Promise<CustomTtsConfig[]> {
    const address = input.trim();
    if (address.length > 8192 || !/^https?:\/\/[^\s/@?#]+(?:[/?#][^\s]*)?$/i.test(address)) {
      throw new Error('Invalid TTS import URL');
    }
    const request = http.createHttp();
    try {
      const response = await request.request(address, {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING,
        header: { 'User-Agent': CustomTtsConfigParser.DEFAULT_USER_AGENT },
        usingCache: false, connectTimeout: 15000, readTimeout: 15000, maxLimit: 1024 * 1024
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        throw new Error('TTS URL request failed');
      }
      return CustomTtsConfigParser.parse(response.result);
    } finally { request.destroy(); }
  }

  static async pick(context: common.Context): Promise<CustomTtsImportResult> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = CustomTtsImportService.MAX_FILES;
    options.fileSuffixFilters = ['JSON|.json'];
    const uris = Array.from(new Set(await new picker.DocumentViewPicker(context).select(options)));
    const result = new CustomTtsImportResult();
    const total = Math.min(uris.length, CustomTtsImportService.MAX_FILES);
    result.failedFiles = uris.length - total;
    for (let offset = 0; offset < total; offset += CustomTtsImportService.IMPORT_CONCURRENCY) {
      const tasks: Promise<CustomTtsImportResult>[] = [];
      const end = Math.min(total, offset + CustomTtsImportService.IMPORT_CONCURRENCY);
      for (let index = offset; index < end; index++) tasks.push(CustomTtsImportService.importOne(uris[index]));
      for (const item of await Promise.all(tasks)) {
        result.configs.push(...item.configs);
        result.failedFiles += item.failedFiles;
      }
    }
    return result;
  }

  private static async importOne(uri: string): Promise<CustomTtsImportResult> {
    const result = new CustomTtsImportResult();
    try {
      const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      try {
        const size = (await fileIo.stat(file.fd)).size;
        if (size <= 0 || size > 1024 * 1024) throw new Error('Invalid TTS file size');
        const buffer = new ArrayBuffer(size);
        let offset = await fileIo.read(file.fd, buffer);
        const chunk = offset < size ? new ArrayBuffer(Math.min(64 * 1024, size)) : undefined;
        while (offset < size && chunk !== undefined) {
          const read = await fileIo.read(file.fd, chunk, { length: Math.min(chunk.byteLength, size - offset) });
          if (read <= 0) throw new Error('Incomplete TTS file');
          new Uint8Array(buffer).set(new Uint8Array(chunk, 0, read), offset);
          offset += read;
        }
        const raw = util.TextDecoder.create('utf-8', { fatal: true }).decodeWithStream(new Uint8Array(buffer));
        result.configs = CustomTtsConfigParser.parse(raw);
      } finally { await fileIo.close(file); }
    } catch (_error) {
      result.configs = [];
      result.failedFiles = 1;
    }
    return result;
  }
}
