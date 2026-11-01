/** 仅用于冷启动展示，绝不能作为会员权限或购买凭据。 */
export class MembershipDisplaySnapshot {
  productId: string = '';
  expiresAt: number = 0;
  autoRenew: boolean = false;
  verifiedAt: number = 0;

  static valid(value: MembershipDisplaySnapshot | null, now: number): boolean {
    return MembershipDisplaySnapshot.validForAppearance(value, now) && value !== null &&
      now - value.verifiedAt < 24 * 60 * 60 * 1000;
  }

  /** 已选外观沿用到订阅到期；终身外观等待后台查询确认撤销，不恢复任何权益。 */
  static validForAppearance(value: MembershipDisplaySnapshot | null, now: number): boolean {
    if (!value || (value.productId !== 'iconMonth' && value.productId !== 'iconYear' && value.productId !== 'lastVip')) {
      return false;
    }
    return typeof value.autoRenew === 'boolean' && typeof value.verifiedAt === 'number' &&
      Number.isFinite(value.verifiedAt) && value.verifiedAt > 0 && now >= value.verifiedAt &&
      typeof value.expiresAt === 'number' &&
      Number.isFinite(value.expiresAt) &&
      (value.productId === 'lastVip' ? value.expiresAt === 0 : value.expiresAt > now);
  }
}
