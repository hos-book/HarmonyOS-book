import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

/** 记录书源使用须知的确认版本，不改变书源启用状态或既有数据。 */
export class RuleSourceNoticeService {
  private static readonly VERSION: number = 1;
  private static readonly STORE_NAME: string = 'rule_source_notice';

  static async isAcknowledged(context: common.Context): Promise<boolean> {
    const store = await preferences.getPreferences(context, { name: RuleSourceNoticeService.STORE_NAME });
    return await store.get('acknowledged_version', 0) === RuleSourceNoticeService.VERSION;
  }

  static async acknowledge(context: common.Context): Promise<void> {
    const store = await preferences.getPreferences(context, { name: RuleSourceNoticeService.STORE_NAME });
    const previous = await store.get('acknowledged_version', 0);
    try {
      await store.put('acknowledged_version', RuleSourceNoticeService.VERSION);
      await store.flush();
    } catch (error) {
      await store.put('acknowledged_version', previous);
      throw new Error(error instanceof Error ? error.message : 'Failed to save source notice acknowledgement');
    }
  }
}
