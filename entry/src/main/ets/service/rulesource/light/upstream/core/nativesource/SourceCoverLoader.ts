import { BookSource } from '../../model/data/Book';
import { HttpClient } from '../http/HttpClient';
import { NativeSourceSpec } from './NativeSourceSpec';
import { SourceCoverUrl } from './SourceCoverUrl';
import { SourceImageDecoder } from './SourceImageDecoder';

/** Call inside the host's source session. The host owns scheduling, cache and image rendering. */
export class SourceCoverLoader {
  static async load(http: HttpClient, source: BookSource, raw: string): Promise<Uint8Array> {
    if (SourceCoverUrl.source(raw) !== source.bookSourceUrl) throw new Error('Cover source mismatch');
    const spec = NativeSourceSpec.unpack(source.jsLib)?.coverDecode;
    if (spec) SourceImageDecoder.validate(spec);
    const response = await http.executeBinary({
      cookieSource: source.bookSourceUrl,
      url: SourceCoverUrl.address(raw), method: 'GET',
      headers: { 'Accept': 'image/*', 'User-Agent': 'Mozilla/5.0',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8', ...SourceCoverUrl.headers(raw) },
      connectTimeout: 10000, readTimeout: 15000
    }, SourceImageDecoder.MAX_BYTES);
    if (!response.success) throw new Error('Cover download failed');
    if (spec) return await SourceImageDecoder.decodeAsync(response.data, spec);
    // Ordinary covers keep the image component's format support (including SVG).
    // Only encrypted covers need the decoder's raster signature validation.
    if (!response.data.length || response.data.length > SourceImageDecoder.MAX_BYTES) throw new Error('Invalid cover byte length');
    return response.data;
  }
}
