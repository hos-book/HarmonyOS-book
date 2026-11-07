import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

/** On-device scheduling only; never wakes the app, sends requests or pauses playback. */
export class JianjianCareService {
  private static busy: boolean = false;
  private static claimed: string = '';

  static nightKey(now: Date): string {
    const hour = now.getHours();
    if (hour >= 5 && hour < 23) return '';
    const night = new Date(now.getTime());
    if (hour < 5) night.setDate(night.getDate() - 1);
    return `${night.getFullYear()}-${night.getMonth() + 1}-${night.getDate()}`;
  }

  static async claim(context: common.Context, now: Date, eligible: () => boolean): Promise<boolean> {
    const key = JianjianCareService.nightKey(now);
    if (!key || !eligible() || JianjianCareService.busy || JianjianCareService.claimed === key) return false;
    JianjianCareService.busy = true;
    try {
      const store = await preferences.getPreferences(context, { name: 'jianjian_care_v1' });
      if (!eligible() || store.getSync('last_night', '') === key) return false;
      await store.put('last_night', key);
      await store.flush();
      JianjianCareService.claimed = key;
      return eligible();
    } catch (_error) { return false; }
    finally { JianjianCareService.busy = false; }
  }
}
