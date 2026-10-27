import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { PlatformCompat } from '../utils/PlatformCompat';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want } from '@kit.AbilityKit';
import { PreferenceService } from '../service/PreferenceService';
import { PlayerFormData, WidgetUpdater, WIDGET_PLAYER } from '../service/WidgetUpdater';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_PlayerForm';

/**
 * 听书卡片 FormExtensionAbility:
 * - onAddForm: 必须同步返回初始 binding;真实快照通过 onUpdateForm 异步推送
 * - onRemoveForm: 从 preference 删除 formId
 * - onUpdateForm: 系统刷新触发,重新读快照
 */
export default class PlayerFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string ?? '';
    // 异步把 formId 入库 + 推真实快照(不阻塞返回)
    this.persistAndPushAsync(formId).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'persistAndPushAsync failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
    // 初始空态与后续推送共用同一显式类型，避免字段类型或 formImages 结构漂移。
    return formBindingData.createFormBindingData(new PlayerFormData());
  }

  private async persistAndPushAsync(formId: string): Promise<void> {
    if (!formId) return;
    // 卡片登记与播放快照独立存储，跨进程读取只刷新各自的卡片缓存。
    await PreferenceService.init(this.context);
    WidgetUpdater.setContext(this.context);
    await PreferenceService.addWidgetFormId(WIDGET_PLAYER, formId);
    hilog.info(DOMAIN, TAG, 'form registered on add id=%{public}s', formId);
    let snap = await PreferenceService.getWidgetPlayerSnapshot();
    if (!snap) {
      snap = await WidgetUpdater.seedSnapshotFromLastPlayed();
    }
    if (!snap) return;
    try {
      await WidgetUpdater.pushPlayerSnapshotToForm(formId, snap, true);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'first push failed: %{public}s', e?.message ?? JSON.stringify(err));
    }
  }

  onRemoveForm(formId: string): void {
    PreferenceService.init(this.context).then(() => {
      return PreferenceService.removeWidgetFormId(WIDGET_PLAYER, formId);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'onRemoveForm failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
  }

  onUpdateForm(formId: string, _wantParams?: Record<string, Object>): void {
    PreferenceService.init(this.context).then(async () => {
      WidgetUpdater.setContext(this.context);
      // 覆盖安装或旧版本升级时系统可能只触发 onUpdateForm，不再触发 onAddForm。
      // 每次刷新都自愈登记 formId，确保主进程能立即主动推送播控和封面。
      await PreferenceService.addWidgetFormId(WIDGET_PLAYER, formId);
      hilog.info(DOMAIN, TAG, 'form registered on update id=%{public}s', formId);
      let snap = await PreferenceService.getWidgetPlayerSnapshot();
      if (!snap) {
        snap = await WidgetUpdater.seedSnapshotFromLastPlayed();
      }
      if (!snap) {
        // 已安装的手表空卡片也需收到布局标识；手机维持原刷新逻辑。
        if (PlatformCompat.wearable) {
          await formProvider.updateForm(formId, formBindingData.createFormBindingData(new PlayerFormData()));
        }
        return;
      }
      await WidgetUpdater.pushPlayerSnapshotToForm(formId, snap, true);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'onUpdateForm failed: %{public}s',
        err?.message ?? JSON.stringify(err));
    });
  }

  onFormEvent(formId: string, message: string): void {
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
