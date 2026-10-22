import { createPrivateKey, randomUUID, sign, type KeyObject } from 'node:crypto';

export const MEMBERSHIP_APP_ID = '6917615941058168740';
export const MEMBERSHIP_OFFER_ID = 'cheaplist';
const productIds = new Set(['iconMonth', 'iconYear', 'lastVip']);

export interface MembershipOfferSignature {
  productId: string;
  offerId: string;
  jwsRepresentation: string;
  expiresAt: number;
}

/** Shared by HTTP/cloud-function adapters; never ship this key or module in the App. */
export class MembershipOfferSigner {
  private readonly key: KeyObject;

  constructor(private readonly issuerId: string, private readonly keyId: string, privateKey: string) {
    if (!issuerId.trim() || !keyId.trim()) throw new Error('IAP issuer ID and key ID are required');
    this.key = privateKey.includes('-----BEGIN PRIVATE KEY-----')
      ? createPrivateKey(privateKey)
      : createPrivateKey({ key: Buffer.from(privateKey.replace(/\s/g, ''), 'base64'), format: 'der', type: 'pkcs8' });
    if (this.key.asymmetricKeyType !== 'ec' || this.key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
      throw new Error('IAP signing requires an ES256 (P-256) private key');
    }
  }

  create(productId: string, now: number = Date.now()): MembershipOfferSignature {
    if (!productIds.has(productId)) throw new Error('Unsupported membership product');
    const issuedAt = Math.floor(now / 1000);
    const expires = issuedAt + 300;
    const header = { alg: 'ES256', typ: 'JWT', kid: this.keyId };
    // Huawei requires data to be a JSON string, not a nested JWT object.
    const data = JSON.stringify({
      productItem: { applicationId: MEMBERSHIP_APP_ID, productId },
      offerInfo: { offerId: MEMBERSHIP_OFFER_ID, nonce: randomUUID() }
    });
    const payload = { iss: this.issuerId, aud: 'iap-v1', iat: issuedAt, exp: expires, aid: MEMBERSHIP_APP_ID, data };
    const unsigned = Buffer.from(JSON.stringify(header)).toString('base64url') + '.' +
      Buffer.from(JSON.stringify(payload)).toString('base64url');
    const signature = sign('sha256', Buffer.from(unsigned), { key: this.key, dsaEncoding: 'ieee-p1363' });
    return {
      productId, offerId: MEMBERSHIP_OFFER_ID,
      jwsRepresentation: unsigned + '.' + signature.toString('base64url'), expiresAt: expires * 1000
    };
  }
}
