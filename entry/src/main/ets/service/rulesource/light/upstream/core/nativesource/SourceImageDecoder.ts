import { NativeSourceCrypto } from './NativeSourceCrypto';
import { NativeCoverDecodeSpec, NativeSourceSpec } from './NativeSourceSpec';
import { util } from '@kit.ArkTS';

/** Bounded reusable image decoding; no networking, files, scripts or website-specific keys. */
export class SourceImageDecoder {
  static readonly MAX_BYTES = 8 * 1024 * 1024;
  /** AVIF/HEIF brands. */
  private static readonly ISO_BRANDS = ['ftypavif', 'ftypavis', 'ftypheic', 'ftypheix', 'ftypmif1', 'ftypmsf1'];

  static validate(spec: NativeCoverDecodeSpec): void {
    if (!spec || !/^AES\/CBC\/PKCS(?:5|7)Padding$/i.test(spec.algorithm || '')) {
      throw new Error('coverDecode requires AES/CBC/PKCS7Padding');
    }
    if (![16, 24, 32].includes(NativeSourceSpec.coverKeyBytes(spec))) throw new Error('Invalid AES key');
    if (spec.ivPrefixBytes === 16) {
      if (spec.iv) throw new Error('Choose iv or ivPrefixBytes');
    } else if ((spec.ivPrefixBytes !== undefined && spec.ivPrefixBytes !== 0) ||
      !/^[a-f0-9]{32}$/i.test(spec.iv || '')) throw new Error('AES CBC requires a 16-byte IV');
  }

  /** Call after validate(). */
  private static keyHex(spec: NativeCoverDecodeSpec): string {
    if (spec.keyEncoding !== 'utf8') return spec.key;
    return Array.from(new util.TextEncoder().encodeInto(spec.key))
      .map(value => value.toString(16).padStart(2, '0')).join('');
  }

  static decode(input: Uint8Array, spec: NativeCoverDecodeSpec): Uint8Array {
    this.validate(spec);
    if (!input.length || input.length > this.MAX_BYTES) throw new Error('Image exceeds byte limit');
    // Some sites mix encrypted and ordinary covers under the same rule.
    if (this.isImage(input)) return input;
    const offset = spec.ivPrefixBytes === 16 ? 16 : 0;
    if (input.length <= offset || (input.length - offset) % 16 !== 0) throw new Error('Truncated AES image');
    const iv = offset ? Array.from(input.subarray(0, offset))
      .map(value => value.toString(16).padStart(2, '0')).join('') : spec.iv || '';
    const output = NativeSourceCrypto.decryptBytes(spec.algorithm, input.subarray(offset), this.keyHex(spec), iv);
    if (!this.isImage(output)) throw new Error('Decoded content is not an image');
    return output;
  }

  static isImage(bytes: Uint8Array): boolean {
    if (bytes.length < 12) return false;
    if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return true;
    const head = Array.from(bytes.subarray(0, 12)).map(value => String.fromCharCode(value)).join('');
    return head.startsWith('\x89PNG\r\n\x1a\n') || head.startsWith('GIF87a') || head.startsWith('GIF89a') ||
      this.isBmp(bytes) || head.startsWith('RIFF') && head.substring(8) === 'WEBP' ||
      SourceImageDecoder.ISO_BRANDS.includes(head.substring(4));
  }

  /**
   * "BM" alone also starts 1 in 65536 random IVs, so require the reserved words to be zero and a
   * pixel offset that lies past the headers and inside the data.
   */
  private static isBmp(bytes: Uint8Array): boolean {
    if (bytes.length < 26 || bytes[0] !== 0x42 || bytes[1] !== 0x4d) return false;
    if (bytes[6] || bytes[7] || bytes[8] || bytes[9]) return false;
    const offset = bytes[10] | (bytes[11] << 8) | (bytes[12] << 16) | (bytes[13] << 24);
    return offset >= 26 && offset < bytes.length;
  }
}
