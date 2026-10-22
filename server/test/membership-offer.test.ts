import { generateKeyPairSync, verify } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { MEMBERSHIP_APP_ID, MembershipOfferSigner } from '../src/membership-offer.js';

const keys = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const pem = keys.privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
const signer = new MembershipOfferSigner('issuer-test', 'key-test', pem);

describe('Huawei cheaplist signatures', () => {
  it.each(['iconMonth', 'iconYear', 'lastVip'])('binds %s to the fixed app and offer, with a short valid ES256 signature', (productId) => {
    const now = 1_800_000_000_000;
    const result = signer.create(productId, now);
    const [header, payload, signature] = result.jwsRepresentation.split('.');
    expect(JSON.parse(Buffer.from(header, 'base64url').toString())).toEqual({ alg: 'ES256', typ: 'JWT', kid: 'key-test' });
    const claims = JSON.parse(Buffer.from(payload, 'base64url').toString());
    expect(claims).toMatchObject({ iss: 'issuer-test', aud: 'iap-v1', aid: MEMBERSHIP_APP_ID, iat: now / 1000, exp: now / 1000 + 300 });
    const data = JSON.parse(claims.data);
    expect(data.productItem).toEqual({ applicationId: MEMBERSHIP_APP_ID, productId });
    expect(data.offerInfo.offerId).toBe('cheaplist');
    expect(data.offerInfo.nonce).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    expect(result.expiresAt).toBe(now + 300_000);
    expect(verify('sha256', Buffer.from(header + '.' + payload), { key: keys.publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url'))).toBe(true);
  });

  it('issues a new nonce for every request, even in the same second', () => {
    const first = signer.create('iconMonth');
    const second = signer.create('iconMonth');
    const nonce = (jws: string) => JSON.parse(JSON.parse(Buffer.from(jws.split('.')[1], 'base64url').toString()).data).offerInfo.nonce;
    expect(nonce(first.jwsRepresentation)).not.toBe(nonce(second.jwsRepresentation));
  });

  it('rejects arbitrary products and missing configuration', () => {
    expect(() => signer.create('another-product')).toThrow('Unsupported');
    expect(() => new MembershipOfferSigner('', 'kid', pem)).toThrow('required');
    const wrongKey = generateKeyPairSync('ec', { namedCurve: 'secp384r1' });
    expect(() => new MembershipOfferSigner('issuer', 'kid', wrongKey.privateKey.export({ type: 'pkcs8', format: 'pem' }).toString())).toThrow('P-256');
  });
});
