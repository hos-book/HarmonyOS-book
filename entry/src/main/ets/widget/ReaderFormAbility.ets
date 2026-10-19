import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ReaderWidgetService } from '../service/ReaderWidgetService';

export default class ReaderFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const id = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
    if (typeof id === 'string') {
      const temporary = want.parameters?.[formInfo.FormParam.TEMPORARY_KEY] === true;
      this.refresh(id, !temporary);
    }
    return formBindingData.createFormBindingData(ReaderWidgetService.emptyData(this.context));
  }

  onUpdateForm(formId: string): void { this.refresh(formId, true); }
  onCastToNormalForm(formId: string): void { this.refresh(formId, true); }

  onRemoveForm(formId: string): void {
    ReaderWidgetService.register(this.context, formId, true).catch((error: Error): void => {
      hilog.warn(0xFF00, 'ReaderForm', 'remove failed: %{public}s', error.message);
    });
  }

  private refresh(formId: string, register: boolean): void {
    const task = register ? ReaderWidgetService.register(this.context, formId) : Promise.resolve();
    task.then((): Promise<void> => ReaderWidgetService.refresh(this.context, formId))
      .catch((error: Error): void => {
        hilog.warn(0xFF00, 'ReaderForm', 'refresh failed: %{public}s', error.message);
      });
  }
}
