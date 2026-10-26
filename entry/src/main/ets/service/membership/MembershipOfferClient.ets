import lazy { cloudFunction } from '@kit.CloudFoundationKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PlatformCompat } from '../../utils/PlatformCompat';

class OfferResponse {
  productId: string = '';
  offerId: string = '';
  jwsRepresentation: string = '';
  expiresAt: number | string = 0;
}

export class MembershipOfferError extends Error implements BusinessError {
  code: number = -3;
  constructor() { super('Membership offer unavailable'); }
}

/** 仅请求固定会员优惠签名；不接入书源服务，私钥不进入客户端。 */
export class MembershipOfferClient {
  static async request(context: common.UIAbilityContext, productId: string, offerId: string): Promise<string> {
    const functionName = context.resourceManager.getStringSync($r('app.string.membership_offer_function').id).trim();
    if (functionName !== 'membership-offer' ||
      !canIUse('SystemCapability.DeviceCloudGateway.CloudFoundation') ||
      (PlatformCompat.desktopWindow && !PlatformCompat.supports(23)) ||
      productId !== 'lastVip' || offerId !== 'lifetime_half_2026') {
      throw new MembershipOfferError();
    }
    try {
      // 系统 SDK 负责应用身份鉴权；固定已发布版本，不向 App 下发服务端密钥。
      const result = await cloudFunction.call({
        name: functionName, version: '1', timeout: 10000,
        data: JSON.stringify({ productId: productId, offerId: offerId })
      });
      const raw = typeof result.result === 'string' ? result.result : JSON.stringify(result.result);
      if (!raw || raw.length > 16384) throw new MembershipOfferError();
      const response: OfferResponse = JSON.parse(raw);
      const now = Date.now();
      // AGC 网关可能把 13 位毫秒时间戳序列化为十进制字符串。
      const expiresAt = typeof response?.expiresAt === 'number' ? response.expiresAt :
        (typeof response?.expiresAt === 'string' && /^\d{13}$/.test(response.expiresAt) ? Number(response.expiresAt) : 0);
      if (!response || response.productId !== productId || response.offerId !== offerId ||
        typeof response.jwsRepresentation !== 'string' || response.jwsRepresentation.length > 8192 ||
        !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(response.jwsRepresentation) ||
        !Number.isFinite(expiresAt) || expiresAt <= now + 15000 || expiresAt > now + 3600000) {
        throw new MembershipOfferError();
      }
      // 华为收银台验证签名及活动资格；客户端不把服务端返回内容作为会员权益凭据。
      return response.jwsRepresentation;
    } catch (_error) {
      throw new MembershipOfferError();
    }
  }
}
