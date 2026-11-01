import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { MembershipDisplaySnapshot } from '../../model/MembershipDisplaySnapshot';

/** 单独保存显示数据，不包含订单、身份令牌，也不进入 App 备份快照。 */
export class MembershipDisplayStore {
  static async read(context: common.Context): Promise<MembershipDisplaySnapshot | null> {
    const store = await preferences.getPreferences(context, { name: 'membership_display_v1' });
    const raw = await store.get('snapshot', '');
    if (typeof raw !== 'string' || raw.length === 0 || raw.length > 512) return null;
    const value: MembershipDisplaySnapshot = JSON.parse(raw);
    if (!MembershipDisplaySnapshot.validForAppearance(value, Date.now())) return null;
    const snapshot = new MembershipDisplaySnapshot();
    snapshot.productId = value.productId;
    snapshot.expiresAt = value.expiresAt;
    snapshot.autoRenew = value.autoRenew;
    snapshot.verifiedAt = value.verifiedAt;
    return snapshot;
  }

  static async write(context: common.Context, snapshot: MembershipDisplaySnapshot | null): Promise<void> {
    const store = await preferences.getPreferences(context, { name: 'membership_display_v1' });
    if (snapshot && MembershipDisplaySnapshot.valid(snapshot, Date.now())) {
      await store.put('snapshot', JSON.stringify(snapshot));
    } else {
      await store.delete('snapshot');
    }
    await store.flush();
  }
}
