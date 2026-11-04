import { MembershipState } from '../../model/MembershipState';
import lazy { MembershipService } from '../MembershipService';

/** 持续运行的会员能力在后台也必须续验；停止后丢弃迟到的核验结果。 */
export class MembershipFeatureLease {
  private timer: number = -1;
  private revision: number = 0;

  stop(): void {
    this.revision++;
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = -1;
  }

  start(revoke: () => void): void {
    this.stop();
    if (!MembershipState.featureEnabled || MembershipState.current.developerAccess) return;
    const revision = this.revision;
    const state = MembershipState.current;
    const deadline = Math.min(state.verifiedAt + 240000,
      state.lifetime ? Number.MAX_SAFE_INTEGER : state.expiresAt);
    this.timer = setTimeout(async (): Promise<void> => {
      this.timer = -1;
      if (state.confirmedInactive || (!state.lifetime && Date.now() >= state.expiresAt)) {
        this.stop(); revoke(); return;
      }
      let allowed = false;
      try { allowed = await MembershipService.instance.hasCurrentEntitlement(true); } catch (_error) {}
      if (revision !== this.revision) return;
      if (allowed) this.start(revoke);
      else { this.stop(); revoke(); }
    }, Math.max(1, deadline - Date.now()));
  }
}
