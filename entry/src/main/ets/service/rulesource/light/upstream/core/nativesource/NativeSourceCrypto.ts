/**
 * 原生书源表达式里 hash / hmac / encrypt / decrypt / rsaEncrypt 的系统实现。
 * 表达式使用同步接口和数字列表；图片使用异步接口和 Uint8Array。
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';

function toBytes(value: Object): Uint8Array {
  const list = Array.isArray(value) ? value as Object[] : [];
  const bytes = new Uint8Array(list.length);
  for (let i = 0; i < list.length; i++) bytes[i] = Number(list[i]) & 255;
  return bytes;
}

function toList(bytes: Uint8Array): number[] {
  const list: number[] = [];
  for (let i = 0; i < bytes.length; i++) list.push(bytes[i]);
  return list;
}

function digestName(raw: string): string {
  const name = raw.toUpperCase().replace(/-/g, '');
  if (['MD5', 'SHA1', 'SHA224', 'SHA256', 'SHA384', 'SHA512', 'SM3'].indexOf(name) < 0) {
    throw new Error(`不支持的摘要算法：${raw}`);
  }
  return name;
}

interface CipherSpec {
  keyAlgorithm: string;
  transformation: string;
  needsIv: boolean;
}

/** 把 AES/CBC/PKCS5Padding 这类通用写法换成系统加密框架的算法串。 */
function cipherSpec(raw: string, keyLength: number): CipherSpec {
  const parts = (raw || '').split('/');
  const family = (parts[0] || '').toUpperCase();
  const mode = (parts[1] || 'ECB').toUpperCase();
  const padding = (parts[2] || 'PKCS5Padding').toUpperCase().indexOf('NOPADDING') >= 0 ? 'NoPadding' : 'PKCS7';
  if (['ECB', 'CBC', 'CTR', 'OFB', 'CFB'].indexOf(mode) < 0) throw new Error(`不支持的加密模式：${mode}`);
  if (family === 'AES') {
    if (keyLength !== 16 && keyLength !== 24 && keyLength !== 32) {
      throw new Error(`AES 密钥长度必须为 16、24 或 32 字节，当前为 ${keyLength} 字节`);
    }
    return {
      keyAlgorithm: `AES${keyLength * 8}`,
      transformation: `AES${keyLength * 8}|${mode}|${padding}`,
      needsIv: mode !== 'ECB'
    };
  }
  if (family === 'DESEDE' || family === '3DES') {
    if (keyLength !== 24) throw new Error(`3DES 密钥长度必须为 24 字节，当前为 ${keyLength} 字节`);
    return { keyAlgorithm: '3DES192', transformation: `3DES192|${mode}|${padding}`, needsIv: mode !== 'ECB' };
  }
  throw new Error(`不支持的加密算法：${raw || '空'}`);
}

function symmetricBytes(decrypting: boolean, transformation: string, data: Uint8Array, keyBytes: Uint8Array,
  iv: Uint8Array): Uint8Array {
  const spec = cipherSpec(transformation, keyBytes.length);
  if (spec.needsIv && iv.length === 0) throw new Error(`${transformation} 需要提供 IV`);
  const key = cryptoFramework.createSymKeyGenerator(spec.keyAlgorithm).convertKeySync({ data: keyBytes });
  try {
    const cipher = cryptoFramework.createCipher(spec.transformation);
    const params: cryptoFramework.IvParamsSpec | null = spec.needsIv ? { algName: 'IvParamsSpec', iv: { data: iv } } : null;
    cipher.initSync(decrypting ? cryptoFramework.CryptoMode.DECRYPT_MODE : cryptoFramework.CryptoMode.ENCRYPT_MODE,
      key, params);
    return cipher.doFinalSync({ data: data }).data;
  } finally {
    key.clearMem();
  }
}

function symmetric(decrypting: boolean, transformation: string, data: Uint8Array, keyBytes: Uint8Array,
  iv: Uint8Array): number[] {
  return toList(symmetricBytes(decrypting, transformation, data, keyBytes, iv));
}

function hexToBytes(hex: string): Uint8Array {
  const clean = (hex || '').replace(/[^0-9a-f]/gi, '');
  const bytes = new Uint8Array(Math.floor(clean.length / 2));
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
  return bytes;
}

export class NativeSourceCrypto {
  /** The only host operations exposed to image scripts; metadata is strictly validated. */
  private static imageArguments(name: string, data: Uint8Array, options: string): Record<string, string> {
    if (data.length > 20 * 1024 * 1024 || options.length > 16384) throw new Error('图片运算参数过大');
    if (!['decrypt', 'encrypt', 'hash', 'hmac'].includes(name)) throw new Error('图片脚本不支持此宿主操作');
    const args = JSON.parse(options) as Record<string, Object>;
    if (!args || typeof args !== 'object' || Array.isArray(args)) throw new Error('图片运算参数必须是对象');
    const algorithm = args['algorithm'];
    const key = args['keyHex'] === undefined ? '' : args['keyHex'];
    const iv = args['ivHex'] === undefined ? '' : args['ivHex'];
    if (typeof algorithm !== 'string' || algorithm.length > 80 || typeof key !== 'string' ||
      typeof iv !== 'string' || !/^(?:[a-f0-9]{2})*$/i.test(key) || !/^(?:[a-f0-9]{2})*$/i.test(iv)) {
      throw new Error('图片运算需要算法名称和完整的十六进制 keyHex/ivHex');
    }
    if (name === 'hash') return { algorithm, key, iv };
    if (name === 'hmac') {
      if (!key || key.length > 8192) throw new Error('HMAC 密钥须为 1 至 4096 字节');
      return { algorithm, key, iv };
    }
    if (!/^(AES|3DES|DESEDE)\/(ECB|CBC|CTR|OFB|CFB)\/(NoPadding|PKCS5Padding|PKCS7Padding)$/i.test(algorithm)) {
      throw new Error('图片运算算法必须明确指定 AES/3DES、模式和填充');
    }
    const blockSize = /^AES\//i.test(algorithm) ? 16 : 8;
    if (/\/ECB\//i.test(algorithm) ? iv.length !== 0 : iv.length !== blockSize * 2) {
      throw new Error('图片运算 IV 长度与模式不匹配');
    }
    return { algorithm, key, iv };
  }

  /** Only for an isolated taskpool worker, never the application UI thread. */
  static imageOperationSync(name: string, data: Uint8Array, options: string): Uint8Array {
    const { algorithm, key, iv } = this.imageArguments(name, data, options);
    if (name === 'hash') {
      const md = cryptoFramework.createMd(digestName(algorithm));
      md.updateSync({ data });
      return md.digestSync().data;
    }
    const keyBytes = hexToBytes(key);
    try {
      if (name !== 'hmac') return symmetricBytes(name === 'decrypt', algorithm, data, keyBytes, hexToBytes(iv));
      const symKey = cryptoFramework.createSymKeyGenerator('HMAC').convertKeySync({ data: keyBytes });
      try {
        const mac = cryptoFramework.createMac(digestName(algorithm));
        mac.initSync(symKey);
        mac.updateSync({ data });
        return mac.doFinalSync().data;
      } finally { symKey.clearMem(); }
    } finally { keyBytes.fill(0); }
  }

  static async imageOperation(name: string, data: Uint8Array, options: string): Promise<Uint8Array> {
    const { algorithm, key, iv } = this.imageArguments(name, data, options);
    if (name === 'hash') {
      const md = cryptoFramework.createMd(digestName(algorithm));
      await md.update({ data: data });
      return (await md.digest()).data;
    }
    if (name === 'hmac') {
      if (!key || key.length > 8192) throw new Error('HMAC 密钥须为 1 至 4096 字节');
      const keyBytes = hexToBytes(key);
      const symKey = await cryptoFramework.createSymKeyGenerator('HMAC').convertKey({ data: keyBytes });
      try {
        const mac = cryptoFramework.createMac(digestName(algorithm));
        await mac.init(symKey);
        await mac.update({ data: data });
        return (await mac.doFinal()).data;
      } finally { symKey.clearMem(); keyBytes.fill(0); }
    }
    return await this.transformBytesAsync(name === 'decrypt', algorithm, data, key, iv);
  }

  /** 图片使用异步系统加密接口，避免大块数据的同步解密阻塞 UI。 */
  static async decryptBytesAsync(transformation: string, data: Uint8Array, keyHex: string,
    ivHex: string): Promise<Uint8Array> {
    return await this.transformBytesAsync(true, transformation, data, keyHex, ivHex);
  }

  private static async transformBytesAsync(decrypting: boolean, transformation: string, data: Uint8Array,
    keyHex: string, ivHex: string): Promise<Uint8Array> {
    const keyBytes = hexToBytes(keyHex);
    const iv = hexToBytes(ivHex);
    const spec = cipherSpec(transformation, keyBytes.length);
    if (spec.needsIv && iv.length === 0) throw new Error(`${transformation} 需要提供 IV`);
    const key = await cryptoFramework.createSymKeyGenerator(spec.keyAlgorithm).convertKey({ data: keyBytes });
    try {
      const cipher = cryptoFramework.createCipher(spec.transformation);
      const params: cryptoFramework.IvParamsSpec | null = spec.needsIv ? { algName: 'IvParamsSpec', iv: { data: iv } } : null;
      await cipher.init(decrypting ? cryptoFramework.CryptoMode.DECRYPT_MODE : cryptoFramework.CryptoMode.ENCRYPT_MODE, key, params);
      return (await cipher.doFinal({ data: data })).data;
    } finally {
      key.clearMem();
      keyBytes.fill(0);
    }
  }

  /** 解密整张图片这类大块数据：不经过表达式引擎，密钥与 IV 用十六进制传入。 */
  static decryptBytes(transformation: string, data: Uint8Array, keyHex: string, ivHex: string): Uint8Array {
    return symmetricBytes(true, transformation, data, hexToBytes(keyHex), hexToBytes(ivHex));
  }

  static run(name: string, args: Object[]): Object {
    switch (name) {
      case 'hash': {
        const md = cryptoFramework.createMd(digestName(String(args[0])));
        md.updateSync({ data: toBytes(args[1]) });
        return toList(md.digestSync().data);
      }
      case 'hmac': {
        const key = cryptoFramework.createSymKeyGenerator('HMAC').convertKeySync({ data: toBytes(args[1]) });
        try {
          const mac = cryptoFramework.createMac(digestName(String(args[0])));
          mac.initSync(key);
          mac.updateSync({ data: toBytes(args[2]) });
          return toList(mac.doFinalSync().data);
        } finally {
          key.clearMem();
        }
      }
      case 'encrypt':
        return symmetric(false, String(args[0]), toBytes(args[1]), toBytes(args[2]), toBytes(args[3]));
      case 'decrypt':
        return symmetric(true, String(args[0]), toBytes(args[1]), toBytes(args[2]), toBytes(args[3]));
      case 'rsaEncrypt': {
        const pem = String(args[1]).trim();
        const bits = pem.length > 600 ? 'RSA4096' : (pem.length > 320 ? 'RSA2048' : 'RSA1024');
        const padding = String(args[2] || 'PKCS1').toUpperCase() === 'OAEP' ? 'PKCS1_OAEP|SHA256|MGF1_SHA256' : 'PKCS1';
        const pair = cryptoFramework.createAsyKeyGenerator(bits).convertPemKeySync(pem, null);
        const cipher = cryptoFramework.createCipher(`${bits}|${padding}`);
        cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, pair.pubKey, null);
        return toList(cipher.doFinalSync({ data: toBytes(args[0]) }).data);
      }
      default:
        throw new Error(`不支持的运算：${name}`);
    }
  }
}
