import { MembershipDisplaySnapshot } from './MembershipDisplaySnapshot';

/** 权益只来自本次进程验签；磁盘快照仅提供展示，不恢复 VIP 开关。 */
@ObservedV2
export class MembershipState {
  /** 会员功能总开关：开启会员入口、购买验签及权益校验。 */
  static readonly featureEnabled: boolean = true;
  private static singleton: MembershipState | null = null;
  static get current(): MembershipState {
    if (!MembershipState.singleton) MembershipState.singleton = new MembershipState();
    return MembershipState.singleton;
  }
  @Trace developerAccess: boolean = false;
  @Trace confirmedInactive: boolean = false;
  /** 回前台时保留有效的展示快照，新的会员操作等待当前账号核验。 */
  @Trace revalidating: boolean = false;

  get hasAccess(): boolean {
    return !MembershipState.featureEnabled || this.developerAccess || (!this.revalidating && this.active);
  }

  @Trace expiresAt: number = 0;
  @Trace productId: string = '';
  @Trace subscriptionGroupId: string = '';
  @Trace pendingProductId: string = '';
  @Trace autoRenew: boolean = false;
  @Trace verifiedAt: number = 0;
  @Trace private displaySnapshot: MembershipDisplaySnapshot | null = null;

  get displayActive(): boolean {
    return MembershipState.featureEnabled &&
      (this.active || MembershipDisplaySnapshot.valid(this.displaySnapshot, Date.now()));
  }

  get displayProductId(): string {
    return this.active ? this.productId : this.displayActive ? this.displaySnapshot?.productId ?? '' : '';
  }

  get displayExpiresAt(): number {
    return this.active ? this.expiresAt : this.displaySnapshot?.expiresAt ?? 0;
  }

  get displayAutoRenew(): boolean {
    return this.active ? this.autoRenew : this.displaySnapshot?.autoRenew ?? false;
  }

  get displayLifetime(): boolean { return this.displayProductId === 'lastVip'; }

  restoreDisplay(snapshot: MembershipDisplaySnapshot | null): void {
    this.displaySnapshot = MembershipDisplaySnapshot.valid(snapshot, Date.now()) ? snapshot : null;
  }

  createDisplaySnapshot(): MembershipDisplaySnapshot | null {
    if (!this.active) return null;
    const snapshot = new MembershipDisplaySnapshot();
    snapshot.productId = this.productId;
    snapshot.expiresAt = this.expiresAt;
    snapshot.autoRenew = this.autoRenew;
    snapshot.verifiedAt = this.verifiedAt;
    return snapshot;
  }

  get lifetime(): boolean { return this.productId === 'lastVip'; }

  get nameColor(): Resource {
    if (!this.displayActive) return $r('sys.color.font_primary');
    if (this.displayLifetime) return $r('app.color.membership_name_lifetime');
    return this.displayProductId === 'iconMonth' ? $r('app.color.membership_name_month') : $r('app.color.membership_name_year');
  }

  get active(): boolean {
    const now = Date.now();
    return this.productId.length > 0 && now >= this.verifiedAt && (this.lifetime || now < this.expiresAt) &&
      now - this.verifiedAt < 5 * 60 * 1000;
  }

  clear(): void {
    this.displaySnapshot = null;
    this.clearEntitlement();
  }

  clearEntitlement(): void {
    this.expiresAt = 0;
    this.productId = '';
    this.subscriptionGroupId = '';
    this.pendingProductId = '';
    this.autoRenew = false;
    this.verifiedAt = 0;
  }
}
