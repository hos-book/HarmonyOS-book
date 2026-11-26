import { sendableContextManager } from '@kit.AbilityKit';
import { emitter, pasteboard } from '@kit.BasicServicesKit';
import { OfflineTtsModelState } from '../model/OfflineTts';
import { getOfflineTtsModel } from '../model/OfflineTtsCatalog';
import { OfflineTtsModelService } from '../service/text/OfflineTtsModelService';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { ModelManagementRow } from './ModelManagementRow';

/** 权重由用户导入，音色通过现有朗读和角色配音入口选择。 */
@ComponentV2
export struct OfflineTtsModelCard {
  @Param modelId: string = 'kokoro-int8-v1_1';
  @Param blocked: boolean = false;
  @Event onChanging: (changing: boolean) => void = () => {};
  @Local state: OfflineTtsModelState = new OfflineTtsModelState();
  @Local ready: boolean = false;
  @Local failed: boolean = false;
  @Local saving: boolean = false;
  @Local removing: boolean = false;
  private model: OfflineTtsModelService = OfflineTtsModelService.instance;
  private speech: TextToSpeechService = TextToSpeechService.getInstance();
  private alive: boolean = false;

  aboutToAppear(): void {
    this.state = this.model.stateFor(this.modelId);
    this.alive = true; this.load();
  }
  aboutToDisappear(): void { this.alive = false; if (this.state.busy && !this.removing) this.model.cancel(); }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.failed = false;
    try { await this.model.ensure(context); if (this.alive) this.ready = true; }
    catch (_error) { if (this.alive) this.failed = true; }
  }

  private toast(message: ResourceStr): void {
    if (this.alive) this.getUIContext().getPromptAction().showToast({ message });
  }

  private title(): Resource {
    if (this.modelId === 'piper-chaowen-int8-v1') return $r('app.string.offline_tts_piper_chaowen_voice');
    if (this.modelId === 'piper-xiaoya-int8-v1') return $r('app.string.offline_tts_piper_xiaoya_voice');
    return $r('app.string.offline_tts_model_name');
  }

  private hint(): Resource {
    if (this.modelId === 'piper-chaowen-int8-v1' || this.modelId === 'piper-xiaoya-int8-v1') {
      return $r('app.string.offline_tts_piper_hint');
    }
    return $r('app.string.offline_tts_kokoro_hint');
  }

  private voiceCount(): number {
    const definition = getOfflineTtsModel(this.modelId);
    return definition ? definition.maxSpeaker - definition.minSpeaker + 1 : 0;
  }

  private errorMessage(error: Error): Resource {
    if (error.message === 'offline_tts_space') return $r('app.string.offline_tts_space');
    if (error.message === 'offline_tts_invalid' || error.message === 'offline_tts_pack_invalid') {
      return $r('app.string.offline_tts_invalid');
    }
    return $r('app.string.offline_tts_failed');
  }

  private async importModel(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.saving || this.model.isBusy() || this.blocked) return;
    this.saving = true; this.onChanging(true);
    try {
      const imported = await this.model.pick(sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(context)), (): boolean => this.alive,
        (): Promise<void> => this.speech.pauseForOfflineModelChange(), this.modelId);
      if (imported) {
        await this.speech.refreshOfflineVoices(this.modelId);
        emitter.emit('app.ai.models.changed');
        this.toast($r('app.string.offline_tts_imported'));
      }
    } catch (error) {
      this.toast(this.errorMessage(error instanceof Error ? error : new Error('offline_tts_failed')));
    } finally {
      this.saving = false; this.onChanging(false);
    }
  }

  private confirmRemove(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.model_pack_delete'), message: $r('app.string.model_pack_delete_hint'),
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.common_delete'), action: (): void => { this.remove(); } }
    });
  }

  private async remove(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.saving || this.model.isBusy() || this.blocked) return;
    this.saving = true; this.removing = true; this.onChanging(true);
    try {
      await this.model.remove(context, (): Promise<void> => this.speech.pauseForOfflineModelChange(), this.modelId);
      await this.speech.refreshOfflineVoices(this.modelId);
      emitter.emit('app.ai.models.changed');
    } catch (_error) { this.toast($r('app.string.offline_tts_failed')); }
    finally { this.saving = false; this.removing = false; this.onChanging(false); }
  }

  private showDescription(): void {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const resources = context.resourceManager;
    const sections: string[] = [resources.getStringSync(this.hint().id)];
    if (this.ready) {
      sections.push(this.state.installed ? resources.getStringSync($r('app.string.offline_tts_installed').id,
        this.voiceCount()) : resources.getStringSync($r('app.string.offline_tts_missing').id));
      if (this.state.installed) {
        sections.push(resources.getStringSync($r('app.string.offline_tts_size').id,
          Math.round(this.state.bytes / 1024 / 1024)));
      }
    }
    if (this.failed || this.state.error) sections.push(resources.getStringSync($r('app.string.offline_tts_failed').id));
    const download = this.modelId === 'piper-xiaoya-int8-v1' ?
      $r('app.string.offline_tts_piper_xiaoya_download_message') : this.modelId === 'piper-chaowen-int8-v1' ?
        $r('app.string.offline_tts_piper_download_message') : $r('app.string.offline_tts_download_message');
    sections.push(resources.getStringSync(download.id));
    this.getUIContext().showAlertDialog({
      title: this.title(), message: sections.join('\n\n'),
      primaryButton: { value: $r('app.string.common_ok'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.role_model_download_link'), action: (): void => { this.copyDownload(); } }
    });
  }

  private async copyDownload(): Promise<void> {
    const definition = getOfflineTtsModel(this.modelId);
    if (!definition) return;
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
        definition.downloadUrl));
      this.toast($r('app.string.role_model_link_copied'));
    } catch (_error) { this.toast($r('app.string.offline_tts_failed')); }
  }

  private operationStatus(): ResourceStr {
    if (!this.ready) return '';
    return this.removing ? $r('app.string.model_pack_deleting') : this.state.verifying ?
      $r('app.string.model_pack_verifying') : $r('app.string.model_pack_importing', this.state.progress);
  }

  build() {
    ModelManagementRow({ itemId: this.modelId, label: this.title(),
      blocked: this.blocked || this.saving, removable: this.state.installed,
      processing: this.state.busy || this.removing || (!this.ready && !this.failed),
      cancellable: this.state.busy && !this.removing, status: this.operationStatus(),
      importLabel: this.failed ? $r('app.string.common_retry') : this.state.installed ?
        $r('app.string.model_pack_replace') : $r('app.string.model_pack_import'),
      onInfo: (): void => this.showDescription(),
      onImport: (): void => { if (this.failed) this.load(); else this.importModel(); },
      onRemove: (): void => this.confirmRemove(), onCancel: (): void => this.model.cancel() })
      .id(this.modelId === 'kokoro-int8-v1_1' ? 'model-pack-offline-tts' : `model-pack-offline-tts-${this.modelId}`)
  }
}
