import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { CustomTtsConfig, CustomTtsImportResult } from '../../model/CustomTtsConfig';
import { CustomTtsConfigParser } from './CustomTtsConfigParser';

export class CustomTtsImportService {
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
    options.maxSelectNumber = 5;
    options.fileSuffixFilters = ['JSON|.json'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    const result = new CustomTtsImportResult();
    for (const uri of uris.slice(0, 5)) {
      try {
        const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
        try {
          const size = (await fileIo.stat(file.fd)).size;
          if (size <= 0 || size > 1024 * 1024) throw new Error('Invalid TTS file size');
          const buffer = new ArrayBuffer(size);
          const read = await fileIo.read(file.fd, buffer);
          if (read !== size) throw new Error('Incomplete TTS file');
          const raw = util.TextDecoder.create('utf-8', { fatal: true }).decodeWithStream(new Uint8Array(buffer));
          result.configs.push(...CustomTtsConfigParser.parse(raw));
        } finally { await fileIo.close(file); }
      } catch (_error) { result.failedFiles++; }
    }
    return result;
  }
}
