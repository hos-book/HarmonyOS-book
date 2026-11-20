import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

class LoginCryptoRequest {
  transformation: string = '';
  key: Object = '';
  iv: Object = '';
  method: string = '';
  data: Object = '';
}

/** Executes the asynchronous native part of java.createSymmetricCrypto during deterministic replay. */
export class BookSourceLoginCrypto {
  static async execute(raw: string): Promise<string> {
    try {
      const parsed = JSON.parse(raw || '{}') as Record<string, Object>;
      const request = new LoginCryptoRequest();
      request.transformation = String(parsed['transformation'] || '');
      request.key = parsed['key'] || '';
      request.iv = parsed['iv'] || '';
      request.method = String(parsed['method'] || '');
      request.data = parsed['data'] || '';
      const value = await this.transform(request);
      return JSON.stringify({ success: true, value: value });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return JSON.stringify({ success: false, error: message || '加密桥接失败' });
    }
  }

  private static async transform(request: LoginCryptoRequest): Promise<Object> {
    if (request.method === 'digestHex') {
      const md = cryptoFramework.createMd((request.transformation || 'MD5').toUpperCase());
      md.updateSync({ data: this.bytes(request.data) });
      return this.hex(md.digestSync().data);
    }
    const keyBytes = this.bytes(request.key);
    const spec = this.algorithm(request.transformation, keyBytes.length);
    const key = await cryptoFramework.createSymKeyGenerator(spec.keyAlgorithm)
      .convertKey({ data: keyBytes });
    try {
      const cipher = cryptoFramework.createCipher(spec.transformation);
      const params = this.params(spec.mode, request.iv);
      const decrypting = request.method.startsWith('decrypt');
      await cipher.init(decrypting ? cryptoFramework.CryptoMode.DECRYPT_MODE :
        cryptoFramework.CryptoMode.ENCRYPT_MODE, key, params);
      const input = decrypting ? this.encryptedBytes(request.data) : this.bytes(request.data);
      const output = (await cipher.doFinal({ data: input })).data;
      if (request.method === 'encryptBase64') {
        return new util.Base64Helper().encodeToStringSync(output);
      }
      if (request.method === 'encryptHex') return this.hex(output);
      if (request.method === 'decryptStr' || request.method === 'encryptStr') {
        return new util.TextDecoder('utf-8').decodeToString(output);
      }
      return this.numberArray(output);
    } finally {
      key.clearMem();
      keyBytes.fill(0);
    }
  }

  private static algorithm(raw: string, keyLength: number): { keyAlgorithm: string;
    transformation: string; mode: string } {
    const parts = (raw || '').split('/');
    const family = (parts[0] || '').toUpperCase();
    const mode = (parts[1] || 'ECB').toUpperCase();
    const paddingRaw = (parts[2] || 'PKCS5Padding').toUpperCase();
    const padding = paddingRaw.includes('NOPADDING') ? 'NoPadding' : 'PKCS7';
    if (family === 'AES') {
      if (keyLength !== 16 && keyLength !== 24 && keyLength !== 32) {
        throw new Error(`AES 密钥长度必须为16、24或32字节，当前为${keyLength}字节`);
      }
      return {
        keyAlgorithm: `AES${keyLength * 8}`,
        transformation: `AES${keyLength * 8}|${mode}|${padding}`,
        mode: mode
      };
    }
    if (family === 'DESEDE' || family === '3DES') {
      if (keyLength !== 24) throw new Error(`3DES 密钥长度必须为24字节，当前为${keyLength}字节`);
      return {
        keyAlgorithm: '3DES192',
        transformation: `3DES192|${mode}|${padding}`,
        mode: mode
      };
    }
    if (family === 'DES') {
      throw new Error('当前系统加密框架不支持单DES，请使用书源提供的兼容分支');
    }
    throw new Error(`暂不支持的对称加密算法：${raw || '空'}`);
  }

  private static params(mode: string, rawIv: Object): cryptoFramework.IvParamsSpec | null {
    if (mode === 'ECB') return null;
    const iv = this.bytes(rawIv);
    if (iv.length === 0) throw new Error(`${mode} 模式缺少IV`);
    return {
      algName: 'IvParamsSpec',
      iv: { data: iv }
    };
  }

  private static encryptedBytes(value: Object): Uint8Array {
    if (Array.isArray(value)) return this.bytes(value);
    const text = String(value || '').trim();
    if (text.length > 0 && text.length % 2 === 0 && /^[0-9A-Fa-f]+$/.test(text)) {
      const result = new Uint8Array(text.length / 2);
      for (let index = 0; index < result.length; index++) {
        result[index] = parseInt(text.substring(index * 2, index * 2 + 2), 16);
      }
      return result;
    }
    try {
      return new util.Base64Helper().decodeSync(text);
    } catch (_) {
      return this.bytes(text);
    }
  }

  private static bytes(value: Object): Uint8Array {
    if (Array.isArray(value)) {
      const values = value as Object[];
      const result = new Uint8Array(values.length);
      for (let index = 0; index < values.length; index++) result[index] = Number(values[index]) & 255;
      return result;
    }
    return new util.TextEncoder().encodeInto(String(value || ''));
  }

  private static hex(bytes: Uint8Array): string {
    let value = '';
    for (const byte of bytes) value += byte.toString(16).padStart(2, '0');
    return value;
  }

  private static numberArray(bytes: Uint8Array): number[] {
    const result: number[] = [];
    for (const byte of bytes) result.push(byte);
    return result;
  }
}
