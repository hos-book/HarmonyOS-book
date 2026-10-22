export class SubscriptionOrder {
  environment: string = '';
  applicationId: string = '';
  productId: string = '';
  productType: string = '';
  purchaseToken: string = '';
  purchaseOrderId: string = '';
  finishStatus: string = '';
  purchaseTime: number = 0;
}

export class SubscriptionRenewal {
  autoRenewStatusCode: string = '';
  nextRenewPeriodProductId?: string;
}

export class SubscriptionStatus {
  status: string = '';
  expiresTime: number = 0;
  lastPurchaseOrder?: SubscriptionOrder;
  renewalInfo?: SubscriptionRenewal;
}

export class SubscriptionPayload {
  environment: string = '';
  applicationId: string = '';
  packageName: string = '';
  subGroupId: string = '';
  lastSubscriptionStatus?: SubscriptionStatus;
}

export class SubscriptionEnvelope {
  jwsSubscriptionStatus: string = '';
}

/** 在密码学验证之后校验应用、商品、环境及有效期，不信任反序列化的类型声明。 */
export class SubscriptionPolicy {
  static readonly month: string = 'iconMonth';
  static readonly year: string = 'iconYear';

  static knownProduct(id: string): boolean {
    return id === SubscriptionPolicy.month || id === SubscriptionPolicy.year;
  }

  static validate(payload: SubscriptionPayload, sandbox: boolean, now: number): SubscriptionStatus | undefined {
    if (!payload || payload.packageName !== 'com.huan.listenbook' ||
      typeof payload.applicationId !== 'string' || payload.applicationId.length === 0 ||
      typeof payload.subGroupId !== 'string' || payload.subGroupId.length === 0 ||
      (payload.environment !== 'NORMAL' && !(sandbox && payload.environment === 'SANDBOX'))) {
      throw new Error('Invalid subscription application or environment');
    }
    const status = payload.lastSubscriptionStatus;
    if (!status) return undefined;
    if (!['1', '2', '3', '5'].includes(status.status) ||
      !Number.isFinite(status.expiresTime) || status.expiresTime <= 0) {
      throw new Error('Invalid subscription status');
    }
    const order = status.lastPurchaseOrder;
    if (!order || !SubscriptionPolicy.knownProduct(order.productId)) return undefined;
    if (order.applicationId !== payload.applicationId || order.environment !== payload.environment ||
      order.productType !== '2' || typeof order.purchaseToken !== 'string' || !order.purchaseToken ||
      typeof order.purchaseOrderId !== 'string' || !order.purchaseOrderId ||
      !Number.isFinite(order.purchaseTime) || order.purchaseTime <= 0 || order.purchaseTime > now + 60000 ||
      status.expiresTime <= order.purchaseTime || !['1', '2'].includes(order.finishStatus)) {
      throw new Error('Invalid subscription order');
    }
    return status;
  }

  static active(status: SubscriptionStatus, now: number): boolean {
    return status.status === '1' && status.expiresTime > now;
  }

  /** 未来续订计划只用于展示，不能提前授予目标套餐权益。 */
  static pendingProduct(status: SubscriptionStatus): string {
    const renewal = status.renewalInfo;
    const next = renewal?.nextRenewPeriodProductId;
    return renewal?.autoRenewStatusCode === '1' && typeof next === 'string' &&
      SubscriptionPolicy.knownProduct(next) && next !== status.lastPurchaseOrder?.productId ? next : '';
  }

  static matchesPurchase(status: SubscriptionStatus, requested: string, previous: string): boolean {
    if (status.lastPurchaseOrder?.productId === requested) return true;
    return previous === SubscriptionPolicy.month && requested === SubscriptionPolicy.year &&
      status.lastPurchaseOrder?.productId === previous && SubscriptionPolicy.pendingProduct(status) === requested;
  }
}
