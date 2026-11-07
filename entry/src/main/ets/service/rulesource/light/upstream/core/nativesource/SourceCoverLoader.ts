import { BookSource } from '../../model/data/Book';
import { HttpClient } from '../http/HttpClient';
import { NativeImageScriptRunner } from './NativeImageScriptRunner';
import { NativeSourceSpec } from './NativeSourceSpec';
import { SourceCoverUrl } from './SourceCoverUrl';
import { SourceImageDecoder } from './SourceImageDecoder';

/** Call inside the host's source session. The host owns scheduling, cache and image rendering. */
export class SourceCoverLoader {
  static async load(http: HttpClient, source: BookSource, raw: string): Promise<Uint8Array> {
    if (SourceCoverUrl.source(raw) !== source.bookSourceUrl) throw new Error('Cover source mismatch');
    const definition = NativeSourceSpec.unpack(source.jsLib);
    const spec = definition?.coverDecode;
    const script = spec && typeof spec.script === 'string' ? spec.script.trim() : '';
    if (spec && !script) SourceImageDecoder.validate(spec);
    const address = SourceCoverUrl.address(raw);
    const response = await http.executeBinary({
      cookieSource: source.bookSourceUrl,
      url: address, method: 'GET',
      headers: { 'Accept': 'image/*', 'User-Agent': 'Mozilla/5.0',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8', ...SourceCoverUrl.headers(raw) },
      connectTimeout: 10000, readTimeout: 15000
    }, SourceImageDecoder.MAX_BYTES);
    if (!response.success) throw new Error('Cover download failed');
    if (script) {
      // Sites often mix plain and obfuscated covers under one rule; only the latter go through the script.
      if (SourceImageDecoder.isImage(response.data)) return response.data;
      let output: Uint8Array;
      try {
        output = await NativeImageScriptRunner.run(definition?.js || '', script, response.data,
          { url: address, index: 0, params: spec?.params || {} }, (): boolean => false, 'coverDecode');
      } catch (e) {
        throw new Error(`coverDecode.script (${script})：${(e as Error).message}`);
      }
      if (output.length > SourceImageDecoder.MAX_BYTES || !SourceImageDecoder.isImage(output)) {
        throw new Error(`coverDecode.script (${script})：返回的字节不是支持的图片格式`);
      }
      return output;
    }
    if (spec) return await SourceImageDecoder.decodeAsync(response.data, spec);
    // Ordinary covers keep the image component's format support (including SVG).
    // Only encrypted covers need the decoder's raster signature validation.
    if (!response.data.length || response.data.length > SourceImageDecoder.MAX_BYTES) throw new Error('Invalid cover byte length');
    return response.data;
  }
}
