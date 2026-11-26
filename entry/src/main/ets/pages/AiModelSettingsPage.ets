import { InfinityLoadingIndicator } from '../components/InfinityLoadingIndicator';
import { sendableContextManager } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { OfflineTtsModelCard } from '../components/OfflineTtsModelCard';
import { ModelManagementRow } from '../components/ModelManagementRow';
import { AiModelPack, AiModelPackState, AiModelPackUsage, AI_MODEL_PACKS } from '../model/AiModelPack';
import { AiModelPackService } from '../service/AiModelPackService';
import { ComicColorizationService } from '../service/ComicColorizationService';
import { AudioSubtitleService } from '../service/subtitle/AudioSubtitleService';
import { AppColor, AppSpace, AppTheme } from '../theme/Theme';

@ComponentV2
export struct AiModelSettingsPage {
  @Param blocked: boolean = false;
  @Event onChanging: (changing: boolean) => void = () => {};
  @Local state: AiModelPackState = AiModelPackService.instance.state;
  @Local colorUsage: AiModelPackUsage = new AiModelPackUsage();
  @Local subtitleUsage: AiModelPackUsage = new AiModelPackUsage();
  @Local loading: boolean = true;
  @Local failed: boolean = false;
  @Local picking: boolean = false;
  @Local offlineChanging: boolean = false;
  private alive: boolean = false;
  private service: AiModelPackService = AiModelPackService.instance;

  aboutToAppear(): void { this.alive = true; this.load(); }
  aboutToDisappear(): void { this.alive = false; this.service.cancel(); }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.loading = true; this.failed = false;
    try {
      await this.service.recover(context);
      this.refresh();
    } catch (_error) { this.failed = true; }
    finally { if (this.alive) this.loading = false; }
  }

  private refresh(): void {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.alive) return;
    this.colorUsage = this.service.usage(context, 'comic-color-v1');
    this.subtitleUsage = this.service.usage(context, 'audio-subtitle-v1');
  }

  private title(id: string): Resource {
    return id === 'comic-color-v1' ? $r('app.string.model_pack_color') : $r('app.string.model_pack_subtitle');
  }

  private usage(id: string): AiModelPackUsage { return id === 'comic-color-v1' ? this.colorUsage : this.subtitleUsage; }

  private async beforeMutation(id: string): Promise<void> {
    if (id === 'comic-color-v1') await ComicColorizationService.pauseForModelChange();
    else await AudioSubtitleService.instance.pauseForModelChange();
  }

  private toast(message: ResourceStr): void {
    if (this.alive) this.getUIContext().getPromptAction().showToast({ message });
  }

  private async importPack(id: string): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.state.busyId || this.picking || this.offlineChanging || this.blocked) return;
    this.picking = true; this.onChanging(true);
    try {
      const imported = await this.service.pick(sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(context)), id, (): boolean => this.alive,
        (): Promise<void> => this.beforeMutation(id));
      if (imported) this.toast($r('app.string.model_pack_imported'));
    } catch (error) {
      this.toast(AiModelPackService.errorMessage(error instanceof Error ? error.message : ''));
    } finally {
      this.picking = false; this.refresh(); this.onChanging(false);
      emitter.emit('app.ai.models.changed');
    }
  }

  private confirmRemove(id: string): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.model_pack_delete'), message: $r('app.string.model_pack_delete_hint'),
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.common_delete'), action: (): void => { this.remove(id); } }
    });
  }

  private async remove(id: string): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.state.busyId || this.picking || this.offlineChanging || this.blocked) return;
    this.onChanging(true);
    try { await this.service.remove(context, id, (): Promise<void> => this.beforeMutation(id)); }
    catch (_error) { this.toast($r('app.string.model_pack_write')); }
    finally { this.refresh(); this.onChanging(false); emitter.emit('app.ai.models.changed'); }
  }

  private showDescription(pack: AiModelPack): void {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const resources = context.resourceManager;
    const description = resources.getStringSync(pack.id === 'comic-color-v1' ?
      $r('app.string.model_pack_color_hint').id : $r('app.string.model_pack_subtitle_hint').id);
    const usage = this.usage(pack.id);
    const status = resources.getStringSync(usage.installed ? $r('app.string.model_pack_installed').id :
      $r('app.string.model_pack_missing').id);
    const size = resources.getStringSync($r('app.string.model_pack_size').id,
      Math.round(pack.bytes() / 1024 / 1024), Math.round(usage.bytes / 1024 / 1024));
    const usageHint = resources.getStringSync($r('app.string.model_pack_help').id);
    this.getUIContext().showAlertDialog({ title: this.title(pack.id),
      message: `${description}\n\n${status}\n${size}\n\n${usageHint}`,
      confirm: { value: $r('app.string.common_ok'), action: (): void => {} } });
  }

  private operationStatus(): Resource {
    return this.state.removing ? $r('app.string.model_pack_deleting') :
      this.state.verifying ? $r('app.string.model_pack_verifying') :
        $r('app.string.model_pack_importing', this.state.progress);
  }

  @Builder
  packCard(pack: AiModelPack) {
    ModelManagementRow({ itemId: pack.id, label: this.title(pack.id),
      blocked: this.blocked || this.state.busyId.length > 0 || this.picking || this.offlineChanging,
      removable: this.usage(pack.id).bytes > 0, processing: this.state.busyId === pack.id,
      cancellable: !this.state.removing, status: this.operationStatus(),
      importLabel: this.usage(pack.id).installed ? $r('app.string.model_pack_replace') : $r('app.string.model_pack_import'),
      onInfo: (): void => this.showDescription(pack),
      onImport: (): void => { this.importPack(pack.id); },
      onRemove: (): void => this.confirmRemove(pack.id),
      onCancel: (): void => this.service.cancel() })
  }

  build() {
    Column({ space: AppSpace.Sm }) {
      if (this.loading) {
        InfinityLoadingIndicator({ indicatorSize: 32 })
      } else if (this.failed) {
        Text($r('app.string.model_pack_write')).fontColor(AppTheme.TextSecondary)
        Button($r('app.string.common_retry')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
          .onClick((): void => { this.load(); })
      } else {
        ForEach(AI_MODEL_PACKS, (pack: AiModelPack): void => { this.packCard(pack) },
          (pack: AiModelPack): string => pack.id)
        OfflineTtsModelCard({ modelId: 'piper-chaowen-int8-v1',
          blocked: this.blocked || this.state.busyId.length > 0 || this.picking || this.offlineChanging,
          onChanging: (changing: boolean): void => { this.offlineChanging = changing; this.onChanging(changing); } })
        OfflineTtsModelCard({ modelId: 'piper-xiaoya-int8-v1',
          blocked: this.blocked || this.state.busyId.length > 0 || this.picking || this.offlineChanging,
          onChanging: (changing: boolean): void => { this.offlineChanging = changing; this.onChanging(changing); } })
        OfflineTtsModelCard({ blocked: this.blocked || this.state.busyId.length > 0 || this.picking || this.offlineChanging,
          onChanging: (changing: boolean): void => { this.offlineChanging = changing; this.onChanging(changing); } })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
