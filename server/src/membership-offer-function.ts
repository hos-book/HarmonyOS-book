import { MembershipOfferSigner, MEMBERSHIP_OFFER_ID } from './membership-offer.js';

export interface OfferFunctionEvent {
  httpMethod?: string;
  body?: string;
  isBase64Encoded?: boolean;
}

/** FunctionGraph + APIG proxy integration. The gateway must enforce per-client throttling. */
export function createMembershipOfferHandler(env: NodeJS.ProcessEnv = process.env) {
  const products = new Set((env.IAP_OFFER_PRODUCTS ?? '').split(',').map(id => id.trim()).filter(Boolean));
  const issuer = env.IAP_ISSUER_ID ?? '';
  const kid = env.IAP_KEY_ID ?? '';
  const privateKey = env.IAP_PRIVATE_KEY ?? '';
  let signer: MembershipOfferSigner | undefined;
  if (issuer && kid && privateKey && products.size) {
    signer = new MembershipOfferSigner(issuer, kid, privateKey);
  }
  let windowStart = 0;
  let requests = 0;
  const reply = (statusCode: number, body: object) => ({
    statusCode, isBase64Encoded: false,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
    body: JSON.stringify(body)
  });
  return async (event: OfferFunctionEvent) => {
    if (event.httpMethod !== 'POST') return reply(405, { code: 'METHOD_NOT_ALLOWED' });
    const now = Date.now();
    if (now < windowStart || now - windowStart >= 60_000) { windowStart = now; requests = 0; }
    if (++requests > 120) return reply(429, { code: 'RATE_LIMITED' });
    if (!signer) return reply(503, { code: 'OFFER_UNAVAILABLE' });
    if (typeof event.body !== 'string' || event.body.length > 2048) return reply(400, { code: 'INVALID_REQUEST' });
    try {
      const raw = event.isBase64Encoded ? Buffer.from(event.body, 'base64').toString('utf8') : event.body;
      const data: unknown = JSON.parse(raw);
      if (!data || typeof data !== 'object' || Array.isArray(data)) return reply(400, { code: 'INVALID_REQUEST' });
      const request = data as Record<string, unknown>;
      if (Object.keys(request).some(key => !['productId', 'offerId'].includes(key)) ||
        typeof request.productId !== 'string' || !products.has(request.productId) || request.offerId !== MEMBERSHIP_OFFER_ID) {
        return reply(400, { code: 'INVALID_REQUEST' });
      }
      return reply(200, signer.create(request.productId, now));
    } catch {
      return reply(400, { code: 'INVALID_REQUEST' });
    }
  };
}

let handler: ReturnType<typeof createMembershipOfferHandler> | undefined;
export async function handlerEntry(event: OfferFunctionEvent) {
  handler ??= createMembershipOfferHandler();
  return handler(event);
}
