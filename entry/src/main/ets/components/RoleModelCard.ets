import { sendableContextManager } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { RoleModelState } from '../model/RoleSpeech';
import { RoleModelService } from '../service/text/RoleModelService';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { SettingsHintButton } from './SettingsHintButton';

/** 模型管理页中的多角色模型卡片，沿用原 GGUF 导入和朗读暂停/恢复流程。 */
@ComponentV2
export struct RoleModelCard {
  @Param blocked: boolean = false;
  @Event onChanging: (changing: boolean) => void = () => {};
  @Local state: RoleModelState = RoleModelService.getInstance().state;
  @Local ready: boolean = false;
  @Local failed: boolean = false;
  @Local saving: boolean = false;
  private model: RoleModelService = RoleModelService.getInstance();
  private speech: TextToSpeechService = TextToSpeechService.getInstance();
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; this.load(); }
  aboutToDisappear(): void { this.alive = false; if (this.state.busy) this.model.cancelImport(); }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.failed = false;
    try { await this.model.initialize(context); if (this.alive) this.ready = true; }
    catch (_error) { if (this.alive) this.failed = true; }
  }

  private toast(message: ResourceStr): void {
    if (this.alive) this.getUIContext().getPromptAction().showToast({ message });
  }

  private async importModel(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.saving || this.state.busy || this.blocked) return;
    this.saving = true; this.onChanging(true);
    let ticket = -2;
    let bookId = '';
    try {
      const imported = await this.model.pick(sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(context)), (): void => {
        if (!this.alive) throw new Error('role_cancelled');
        bookId = this.speech.state.bookId; ticket = this.speech.pauseForPreview();
      });
      if (imported) this.toast($r('app.string.role_model_imported'));
    } catch (error) {
      this.toast(RoleModelService.errorMessage(error instanceof Error ? error.message : String(error)));
    } finally {
      if (ticket !== -2) await this.refreshPlayback(bookId, ticket);
      this.saving = false; this.onChanging(false);
    }
  }

  private async refreshPlayback(bookId: string, ticket: number): Promise<void> {
    if (this.speech.state.bookId !== bookId || this.speech.state.playing || this.speech.state.loading) return;
    try { await this.speech.refreshRoleSpeech(this.speech.canResumePreview(ticket)); }
    catch (_error) { this.toast($r('app.string.role_save_error')); }
  }

  private confirmRemove(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.role_model_remove'), message: $r('app.string.role_model_remove_hint'),
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.common_delete'), action: (): void => { this.remove(); } }
    });
  }

  private async remove(): Promise<void> {
    if (this.saving || this.state.busy || this.blocked) return;
    this.saving = true; this.onChanging(true);
    const bookId = this.speech.state.bookId;
    const ticket = this.speech.pauseForPreview();
    try { await this.model.remove(); }
    catch (_error) { this.toast($r('app.string.role_save_error')); }
    finally {
      await this.refreshPlayback(bookId, ticket);
      this.saving = false; this.onChanging(false);
    }
  }

  private async copyDownload(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
        'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf?download=true'));
      this.toast($r('app.string.role_model_link_copied'));
    } catch (_error) { this.toast($r('app.string.role_save_error')); }
  }

  build() {
    Column({ space: AppSpace.Sm }) {
      Row() {
        Row({ space: AppSpace.Xxs }) {
          Text($r('app.string.model_pack_role')).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TextPrimary)
          SettingsHintButton({ title: $r('app.string.model_pack_role'), message: $r('app.string.role_model_help') })
            .id('model-pack-hint-role-speech')
        }.layoutWeight(1)
        if (this.ready) {
          Text(this.state.model !== null ? $r('app.string.model_pack_installed') : $r('app.string.role_model_empty'))
            .fontSize(AppFont.Caption).fontColor(this.state.model !== null ? AppColor.Brand : AppTheme.TextSecondary)
        }
      }.width('100%')
      if (this.ready) {
        if (this.state.model !== null) {
          Text(this.state.model.name).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text($r('app.string.role_model_size', Math.round(this.state.model.bytes / 1024 / 1024)))
            .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        }
        if (this.state.busy) {
          Row({ space: AppSpace.Sm }) {
            LoadingProgress().width(22).height(22).color(AppColor.Brand)
            Text(this.state.verifying ? $r('app.string.role_model_verifying') :
              $r('app.string.role_model_copying', this.state.progress)).fontSize(AppFont.Body)
              .fontColor(AppTheme.TextSecondary).layoutWeight(1)
            Button($r('app.string.common_cancel')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
              .onClick((): void => this.model.cancelImport()).id('role-model-cancel')
          }.width('100%')
        } else {
          Row({ space: AppSpace.Sm }) {
            Button(this.state.model === null ? $r('app.string.role_model_import') : $r('app.string.role_model_replace'))
              .fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand).layoutWeight(1)
              .enabled(!this.saving && !this.blocked).onClick((): void => { this.importModel(); }).id('role-model-import')
            if (this.state.model !== null) {
              Button($r('app.string.common_delete')).fontColor(AppTheme.TextSecondary).backgroundColor(Color.Transparent)
                .enabled(!this.saving && !this.blocked).onClick((): void => this.confirmRemove()).id('role-model-delete')
            }
          }.width('100%')
        }
        if (this.state.error) { Text(this.state.error).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary) }
        Button($r('app.string.role_model_download_link')).fontSize(AppFont.Caption).fontColor(AppColor.Brand)
          .backgroundColor(Color.Transparent).onClick((): void => { this.copyDownload(); })
      } else if (this.failed) {
        Text($r('app.string.reading_settings_load_error')).fontColor(AppTheme.TextSecondary)
        Button($r('app.string.common_retry')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
          .onClick((): void => { this.load(); })
      } else {
        LoadingProgress().width(28).height(28).color(AppColor.Brand)
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Md)
      .borderRadius(AppRadius.Lg).backgroundColor(AppTheme.Surface).id('model-pack-role-speech')
  }
}
