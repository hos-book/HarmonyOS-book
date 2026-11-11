import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { getKey, getKeyId } from 'libmodel_pack_crypto.so';

/** Each bounded chunk authenticates its pack, asset name and index before writing. */
export class AiModelPackCrypto {
  private key: cryptoFramework.SymKey;

  private constructor(key: cryptoFramework.SymKey) { this.key = key; }

  static async open(keyId: string): Promise<AiModelPackCrypto> {
    if (keyId !== getKeyId()) throw new Error('model_pack_invalid');
    const bytes = new Uint8Array(getKey());
    try {
      const key = await cryptoFramework.createSymKeyGenerator('AES256').convertKey({ data: bytes });
      return new AiModelPackCrypto(key);
    } finally { bytes.fill(0); }
  }

  async decrypt(data: ArrayBuffer, id: string, name: string, index: number): Promise<ArrayBuffer> {
    const bytes = new Uint8Array(data);
    if (bytes.length <= 28) throw new Error('model_pack_invalid');
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec', iv: { data: bytes.slice(0, 12) },
      aad: { data: new util.TextEncoder().encodeInto(`JiantingModelPack/v2/${id}/${name}/${index}`) },
      authTag: { data: bytes.slice(bytes.length - 16) }
    };
    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, this.key, params);
    const plain = await cipher.doFinal({ data: bytes.slice(12, bytes.length - 16) });
    return new Uint8Array(plain.data).buffer;
  }

  close(): void { this.key.clearMem(); }
}
