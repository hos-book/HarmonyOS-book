import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

class OfferResponse {
  productId: string = '';
  offerId: string = '';
  jwsRepresentation: string = '';
  expiresAt: number = 0;
}

export class MembershipOfferError extends Error implements BusinessError {
  code: number = -3;
  constructor() { super('Membership offer unavailable'); }
}

/** 仅请求固定会员优惠签名；不接入书源服务，私钥不进入客户端。 */
export class MembershipOfferClient {
  static async request(context: common.UIAbilityContext, productId: string, offerId: string): Promise<string> {
    const endpoint = context.resourceManager.getStringSync($r('app.string.membership_offer_endpoint').id).trim();
    if (!/^https:\/\/[^/?#@\s]+\/[^#\s]*$/.test(endpoint) ||
      !['iconMonth', 'iconYear', 'lastVip'].includes(productId) || offerId !== 'cheaplist') {
      throw new MembershipOfferError();
    }
    const client = http.createHttp();
    try {
      const result = await client.request(endpoint, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        extraData: JSON.stringify({ productId: productId, offerId: offerId }),
        expectDataType: http.HttpDataType.STRING,
        usingCache: false, connectTimeout: 10000, readTimeout: 10000, maxLimit: 16384
      });
      if (result.responseCode !== 200 || typeof result.result !== 'string') throw new MembershipOfferError();
      const response: OfferResponse = JSON.parse(result.result);
      const now = Date.now();
      if (!response || response.productId !== productId || response.offerId !== offerId ||
        typeof response.jwsRepresentation !== 'string' || response.jwsRepresentation.length > 8192 ||
        !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(response.jwsRepresentation) ||
        !Number.isFinite(response.expiresAt) || response.expiresAt <= now + 15000 || response.expiresAt > now + 3600000) {
        throw new MembershipOfferError();
      }
      // 华为收银台验证签名及活动资格；客户端不把服务端返回内容作为会员权益凭据。
      return response.jwsRepresentation;
    } catch (_error) {
      throw new MembershipOfferError();
    } finally {
      client.destroy();
    }
  }
}
