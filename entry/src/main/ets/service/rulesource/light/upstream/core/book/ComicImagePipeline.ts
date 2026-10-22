import { BookSource } from '../../model/data/Book';
import { HttpClient } from '../http/HttpClient';
import { NativeSourceCrypto } from '../nativesource/NativeSourceCrypto';
import { NativeSourceSpec } from '../nativesource/NativeSourceSpec';
import { NativeImageScriptRunner } from '../nativesource/NativeImageScriptRunner';
import { SourceEngineHost } from '../host/SourceEngineHost';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

export class ComicImageSpec {
  url: string = '';
  headers: Record<string, string> = {};
  hasOptions: boolean = false;
  /** 原生书源给出的解密参数；空串表示不解密。 */
  decodeAlgorithm: string = '';
  decodeKey: string = '';
  decodeIv: string = '';
  ivPrefixBytes: number = 0;
  script: string = '';
  params: Object = {};
  processPlainImages: boolean = false;
  imageIndex: number = 0;
}

/**
 * Materializes protected comic images as app-owned cache files. Imported rules
 * never receive filesystem access; only bounded HTTP headers and allow-listed
 * symmetric decryption are exposed by this adapter.
 */
export class ComicImagePipeline {
  private static readonly MAX_IMAGE_BYTES: number = 20 * 1024 * 1024;

  static parse(raw: string): ComicImageSpec {
    const spec = new ComicImageSpec();
    const value = this.decodeEntities(raw || '').trim().replace(/^['"]|['"]$/g, '');
    if (!value) return spec;
    const optionIndex = this.findOptionIndex(value);
    spec.url = (optionIndex >= 0 ? value.substring(0, optionIndex) : value).trim();
    if (optionIndex < 0) return spec;
    const rawOptions = value.substring(optionIndex + 1).trim();
    try {
      const options = JSON.parse(rawOptions) as Record<string, Object>;
      const headerObject = options['headers'];
      if (headerObject && typeof headerObject === 'object' && !Array.isArray(headerObject)) {
        const record = headerObject as Record<string, Object>;
        for (const key in record) {
          const headerValue = String(record[key] || '').trim();
          if (this.allowedHeader(key) && headerValue) spec.headers[key] = headerValue;
        }
      }
      const decode = options['decode'];
      if (decode && typeof decode === 'object' && !Array.isArray(decode)) {
        const record = decode as Record<string, Object>;
        spec.decodeAlgorithm = String(record['algorithm'] || '');
        spec.decodeKey = String(record['key'] || '');
        spec.decodeIv = String(record['iv'] || '');
        spec.ivPrefixBytes = Number(record['ivPrefixBytes'] || 0);
        spec.script = String(record['script'] || '');
        spec.params = record['params'] || {};
        spec.processPlainImages = record['processPlainImages'] === true;
      }
      const imageIndex = Number(options['imageIndex']);
      spec.imageIndex = Number.isSafeInteger(imageIndex) && imageIndex >= 0 ? imageIndex : 0;
      spec.hasOptions = true;
    } catch (_) {
    }
    return spec;
  }

  static async materialize(http: HttpClient, source: BookSource, raw: string, forceLocal: boolean = false): Promise<string> {
    const cancelled = (): boolean => SourceEngineHost.isCancelled(source);
    const checkCancelled = (): void => { if (cancelled()) throw new Error('Comic image prefetch cancelled'); };
    checkCancelled();
    const spec = this.parse(raw);
    if (!/^https?:\/\//i.test(spec.url)) return spec.url || raw;
    const decodeRule = source.contentRule?.imageDecode || '';
    if (!forceLocal && !spec.hasOptions && !decodeRule) return spec.url;
    const cacheDir = AppStorage.get<string>('appCacheDir') || '';
    if (!cacheDir) return spec.url;
    const dir = `${cacheDir}/comic_images`;
    this.ensureDir(dir);
    const js = spec.script ? NativeSourceSpec.unpack(source.jsLib)?.js || '' : '';
    // Include every transformation input, including script revisions, headers and page position.
    const basePath = `${dir}/${await this.hashText(JSON.stringify([source.bookSourceUrl, spec, decodeRule, js]))}`;
    checkCancelled();
    const existing = this.findExisting(basePath);
    if (existing) return existing;

    const response = await http.executeBinary({
      cookieSource: source.bookSourceUrl,
      url: spec.url,
      method: 'GET',
      headers: {
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        ...spec.headers
      },
      connectTimeout: 15000,
      readTimeout: 30000
    }, this.MAX_IMAGE_BYTES);
    checkCancelled();
    if (!response.success || response.data.length === 0) return spec.url;

    let bytes = response.data;
    if (bytes.length > this.MAX_IMAGE_BYTES) throw new Error('图片超过 20 MiB');
    if (spec.script && (spec.processPlainImages || !this.looksLikeImage(bytes))) {
      bytes = await NativeImageScriptRunner.run(js, spec.script, bytes,
        { url: spec.url, index: spec.imageIndex, params: spec.params }, cancelled);
    }
    if (spec.decodeAlgorithm && spec.decodeKey && !this.looksLikeImage(bytes)) {
      let iv = spec.decodeIv;
      if (spec.ivPrefixBytes) {
        if (spec.ivPrefixBytes !== 16 || iv || !/^AES\/CBC\/PKCS(?:5|7)Padding$/i.test(spec.decodeAlgorithm) ||
          bytes.length <= 16 || (bytes.length - 16) % 16 !== 0) throw new Error('无效的图片前置 IV');
        iv = Array.from(bytes.subarray(0, 16)).map(value => value.toString(16).padStart(2, '0')).join('');
        bytes = bytes.subarray(16);
      }
      bytes = await NativeSourceCrypto.decryptBytesAsync(spec.decodeAlgorithm, bytes, spec.decodeKey, iv);
    }
    if (decodeRule && !this.looksLikeImage(bytes)) {
      const decoded = await this.decodeImage(bytes, decodeRule);
      if (decoded.length > 0) bytes = decoded;
    }
    checkCancelled();
    if (!bytes.length || bytes.length > this.MAX_IMAGE_BYTES || !this.looksLikeImage(bytes)) {
      if (spec.script || spec.decodeAlgorithm || decodeRule) throw new Error('图片解码未返回有效图片');
      return spec.url;
    }
    const path = `${basePath}${this.imageExtension(bytes, spec.url)}`;
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      let written = 0;
      while (written < buffer.byteLength) {
        const count = fs.writeSync(file.fd, buffer.slice(written));
        if (count <= 0) throw new Error('图片缓存写入失败');
        written += count;
      }
    } catch (error) {
      try { fs.unlinkSync(path); } catch (_) {}
      throw error;
    } finally {
      fs.closeSync(file);
    }
    return path;
  }

  private static async decodeImage(input: Uint8Array, rule: string): Promise<Uint8Array> {
    if (!/createSymmetricCrypto\s*\(/.test(rule || '')) return new Uint8Array();
    const algorithm = this.readCryptoAlgorithm(rule);
    if (!/^aes\/cbc\/pkcs(?:5|7)padding$/i.test(algorithm)) return new Uint8Array();
    const key = this.readCryptoKey(rule);
    const keyBytes = new util.TextEncoder().encodeInto(key);
    if (![16, 24, 32].includes(keyBytes.length)) return new Uint8Array();
    const bits = keyBytes.length * 8;
    const generator = cryptoFramework.createSymKeyGenerator(`AES${bits}`);
    const symKey = await generator.convertKey({ data: keyBytes });
    try {
      const cipher = cryptoFramework.createCipher(`AES${bits}|CBC|PKCS7`);
      const iv = this.readCryptoIv(rule, key);
      const ivBytes = new util.TextEncoder().encodeInto(iv);
      if (ivBytes.length !== 16) return new Uint8Array();
      const params: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: { data: ivBytes }
      };
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
      const output = await cipher.doFinal({ data: input });
      return output && output.data ? output.data : new Uint8Array();
    } catch (e) {
      console.warn('[ComicImagePipeline] imageDecode failed:', e);
      return new Uint8Array();
    } finally {
      symKey.clearMem();
      keyBytes.fill(0);
    }
  }

  private static readCryptoAlgorithm(rule: string): string {
    const match = (rule || '').match(/createSymmetricCrypto\s*\(\s*(['"])(.*?)\1/i);
    return match ? match[2].trim() : '';
  }

  private static readCryptoKey(rule: string): string {
    const fallback = (rule || '').match(/cache\.get\(\s*(['"])[^'"]+\1\s*\)\s*\|\|\s*(['"])(.*?)\2/);
    if (fallback && fallback[3]) return fallback[3];
    const direct = (rule || '').match(/(?:var|let|const)?\s*key\s*=\s*(['"])(.*?)\1/);
    if (direct && direct[2]) return direct[2];
    const call = (rule || '').match(/createSymmetricCrypto\s*\(\s*(['"])[^'"]+\1\s*,\s*(['"])(.*?)\2/);
    return call && call[3] ? call[3] : '';
  }

  private static readCryptoIv(rule: string, fallback: string): string {
    const call = (rule || '').match(
      /createSymmetricCrypto\s*\(\s*(['"])[^'"]+\1\s*,\s*[^,]+,\s*(['"])(.*?)\2/);
    return call && call[3] ? call[3] : fallback;
  }

  private static findOptionIndex(value: string): number {
    for (let index = value.length - 1; index >= 0; index--) {
      if (value.charAt(index) !== ',') continue;
      const tail = value.substring(index + 1).trim();
      if (tail.startsWith('{') && tail.endsWith('}')) return index;
    }
    return -1;
  }

  private static allowedHeader(name: string): boolean {
    return /^(?:referer|origin|user-agent|accept|accept-language|authorization|cookie|range)$/i.test(name || '');
  }

  private static looksLikeImage(bytes: Uint8Array): boolean {
    if (bytes.length < 12) return false;
    if (bytes[0] === 0xFF && bytes[1] === 0xD8) return true;
    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) return true;
    if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) return true;
    if (bytes[0] === 0x42 && bytes[1] === 0x4D) return true;
    const ascii = String.fromCharCode(...Array.from(bytes.subarray(0, 16)));
    return ascii.startsWith('RIFF') && ascii.substring(8, 12) === 'WEBP' ||
      ascii.substring(4, 12).includes('ftypavif') || ascii.substring(4, 12).includes('ftypavis');
  }

  private static imageExtension(bytes: Uint8Array, url: string): string {
    if (bytes[0] === 0x89 && bytes[1] === 0x50) return '.png';
    if (bytes[0] === 0x47 && bytes[1] === 0x49) return '.gif';
    if (bytes[0] === 0x42 && bytes[1] === 0x4D) return '.bmp';
    const ascii = String.fromCharCode(...Array.from(bytes.subarray(0, 16)));
    if (ascii.startsWith('RIFF')) return '.webp';
    if (ascii.substring(4, 12).includes('ftypavi')) return '.avif';
    const match = (url || '').match(/\.(jpe?g|png|gif|webp|bmp|avif)(?:[?#]|$)/i);
    return match ? `.${match[1].toLowerCase().replace('jpeg', 'jpg')}` : '.jpg';
  }

  private static findExisting(basePath: string): string {
    for (const ext of ['.jpg', '.png', '.gif', '.webp', '.bmp', '.avif']) {
      const path = `${basePath}${ext}`;
      try {
        if (fs.accessSync(path)) return path;
      } catch (_) {
      }
    }
    return '';
  }

  private static ensureDir(path: string): void {
    try {
      fs.mkdirSync(path, true);
    } catch (_) {
    }
  }

  private static async hashText(value: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: new util.TextEncoder().encodeInto(value) });
    return Array.from((await md.digest()).data).map(value => value.toString(16).padStart(2, '0')).join('');
  }

  private static decodeEntities(value: string): string {
    return (value || '').replace(/&quot;/gi, '"').replace(/&amp;/gi, '&')
      .replace(/&#39;/g, "'").replace(/&lt;/gi, '<').replace(/&gt;/gi, '>');
  }
}
