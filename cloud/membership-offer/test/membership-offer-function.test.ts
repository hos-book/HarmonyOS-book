import { generateKeyPairSync } from 'node:crypto';
import { describe, it, expect } from 'vitest';
import { createMembershipOfferHandler } from '../src/membership-offer-function.js';

const privateKey = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey
  .export({ type: 'pkcs8', format: 'pem' }).toString();
const env = { IAP_ISSUER_ID: 'issuer', IAP_KEY_ID: 'kid', IAP_PRIVATE_KEY: privateKey, IAP_OFFER_PRODUCTS: 'iconMonth,lastVip' };
const event = { httpMethod: 'POST', body: JSON.stringify({ productId: 'lastVip', offerId: 'lifetime_half_2026' }) };

describe('Huawei FunctionGraph offer adapter', () => {
  it('returns an uncached signature bound to the configured promotion', async () => {
    const response = await createMembershipOfferHandler(env)(event);
    expect(response.statusCode).toBe(200);
    expect(response.headers['Cache-Control']).toBe('no-store');
    expect(JSON.parse(response.body)).toMatchObject({ productId: 'lastVip', offerId: 'lifetime_half_2026' });
  });
  it('fails closed without configuration and rejects unconfigured products and injected signing claims', async () => {
    expect((await createMembershipOfferHandler({})(event)).statusCode).toBe(503);
    const handler = createMembershipOfferHandler(env);
    for (const body of ['null', '{', JSON.stringify({ productId: 'lastVip', offerId: 'cheaplist' }),
      JSON.stringify({ productId: 'iconYear', offerId: 'lifetime_half_2026' }),
      JSON.stringify({ productId: 'lastVip', offerId: 'lifetime_half_2026', applicationId: 'another-app' }),
      JSON.stringify({ productId: 'lastVip', offerId: 'another-offer' })]) {
      expect((await handler({ ...event, body })).statusCode).toBe(400);
    }
    expect((await handler({ ...event, httpMethod: 'GET' })).statusCode).toBe(405);
  });
  it('bounds request size and signing rate', async () => {
    const handler = createMembershipOfferHandler(env);
    expect((await handler({ ...event, body: 'x'.repeat(2049) })).statusCode).toBe(400);
    for (let i = 0; i < 119; i++) await handler(event);
    expect((await handler(event)).statusCode).toBe(429);
  });
});
