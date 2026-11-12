import { sendableContextManager } from '@kit.AbilityKit';
import { emitter, pasteboard } from '@kit.BasicServicesKit';
import { OfflineTtsModelState } from '../model/OfflineTts';
import { getOfflineTtsModel } from '../model/OfflineTtsCatalog';
import { OfflineTtsModelService } from '../service/text/OfflineTtsModelService';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { SettingsHintButton } from './SettingsHintButton';

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

  private controlId(action: string): string {
    const id = `offline-tts-model-${action}`;
    return this.modelId === 'kokoro-int8-v1_1' ? id : `${id}-${this.modelId}`;
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

  private showDownload(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.offline_tts_download_title'), message: this.modelId === 'piper-xiaoya-int8-v1' ?
        $r('app.string.offline_tts_piper_xiaoya_download_message') : this.modelId === 'piper-chaowen-int8-v1' ?
        $r('app.string.offline_tts_piper_download_message') : $r('app.string.offline_tts_download_message'),
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
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

  build() {
    Column({ space: AppSpace.Sm }) {
      Row() {
        Row({ space: AppSpace.Xxs }) {
          Text(this.title()).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TextPrimary)
          SettingsHintButton({ title: this.title(), message: this.hint() })
            .id(this.controlId('hint'))
        }.layoutWeight(1)
        if (this.ready) {
          Text(this.state.installed ? $r('app.string.offline_tts_installed', this.voiceCount()) : $r('app.string.offline_tts_missing'))
            .fontSize(AppFont.Caption).fontColor(this.state.installed ? AppColor.Brand : AppTheme.TextSecondary)
        }
      }.width('100%')
      if (this.ready) {
        if (this.state.installed) {
          Text($r('app.string.offline_tts_size', Math.round(this.state.bytes / 1024 / 1024)))
            .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        }
        if (this.state.busy || this.removing) {
          Row({ space: AppSpace.Sm }) {
            LoadingProgress().width(22).height(22).color(AppColor.Brand)
            Text(this.removing ? $r('app.string.model_pack_deleting') : this.state.verifying ?
              $r('app.string.model_pack_verifying') : $r('app.string.model_pack_importing', this.state.progress))
              .fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary).layoutWeight(1)
            if (!this.removing) {
              Button($r('app.string.common_cancel')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
                .onClick((): void => this.model.cancel()).id(this.controlId('cancel'))
            }
          }.width('100%')
        } else {
          Row({ space: AppSpace.Sm }) {
            Button(this.state.installed ? $r('app.string.model_pack_replace') : $r('app.string.model_pack_import'))
              .fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand).layoutWeight(1)
              .enabled(!this.saving && !this.blocked).onClick((): void => { this.importModel(); })
              .id(this.controlId('import'))
            if (this.state.installed) {
              Button($r('app.string.common_delete')).fontColor(AppTheme.TextSecondary).backgroundColor(Color.Transparent)
                .enabled(!this.saving && !this.blocked).onClick((): void => this.confirmRemove()).id(this.controlId('delete'))
            }
          }.width('100%')
        }
        if (this.state.error) {
          Text($r('app.string.offline_tts_failed')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        }
        Button($r('app.string.offline_tts_download_link')).fontSize(AppFont.Caption).fontColor(AppColor.Brand)
          .backgroundColor(Color.Transparent).onClick((): void => this.showDownload()).id(this.controlId('download'))
      } else if (this.failed) {
        Text($r('app.string.offline_tts_failed')).fontColor(AppTheme.TextSecondary)
        Button($r('app.string.common_retry')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
          .onClick((): void => { this.load(); })
      } else {
        LoadingProgress().width(28).height(28).color(AppColor.Brand)
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Md)
      .borderRadius(AppRadius.Lg).backgroundColor(AppTheme.Surface)
      .id(this.modelId === 'kokoro-int8-v1_1' ? 'model-pack-offline-tts' : `model-pack-offline-tts-${this.modelId}`)
  }
}
