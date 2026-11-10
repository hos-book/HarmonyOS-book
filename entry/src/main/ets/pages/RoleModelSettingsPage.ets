import { sendableContextManager } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { RoleModelState } from '../model/RoleSpeech';
import { RoleModelService } from '../service/text/RoleModelService';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct RoleModelSettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
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
    if (!context || this.saving || this.state.busy) return;
    this.saving = true;
    let ticket = -2;
    let bookId = '';
    try {
      const imported = await this.model.pick(sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(context)), (): void => {
        if (!this.alive) throw new Error('role_cancelled');
        // 选中文件后才暂停，取消系统文件选择不打断朗读。
        bookId = this.speech.state.bookId; ticket = this.speech.pauseForPreview();
      });
      if (imported) this.toast($r('app.string.role_model_imported'));
    } catch (error) {
      this.toast(RoleModelService.errorMessage(error instanceof Error ? error.message : String(error)));
    } finally {
      if (ticket !== -2) await this.refreshPlayback(bookId, ticket);
      this.saving = false;
    }
  }

  private async refreshPlayback(bookId: string, ticket: number): Promise<void> {
    if (this.speech.state.bookId !== bookId || this.speech.state.playing || this.speech.state.loading) return;
    try { await this.speech.refreshRoleSpeech(this.speech.canResumePreview(ticket)); }
    catch (_error) { this.toast($r('app.string.role_save_error')); }
  }

  private removeModel(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.role_model_remove'), message: $r('app.string.role_model_remove_hint'),
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.common_delete'), action: (): void => { this.remove(); } }
    });
  }

  private async remove(): Promise<void> {
    if (this.saving || this.state.busy) return;
    this.saving = true;
    const bookId = this.speech.state.bookId;
    const ticket = this.speech.pauseForPreview();
    try { await this.model.remove(); }
    catch (_error) { this.toast($r('app.string.role_save_error')); }
    finally { await this.refreshPlayback(bookId, ticket); this.saving = false; }
  }

  private async copyDownload(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
        'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf?download=true'));
      this.toast($r('app.string.role_model_link_copied'));
    } catch (_error) { this.toast($r('app.string.role_save_error')); }
  }

  @Builder
  modelCard() {
    Column({ space: AppSpace.Sm }) {
      Text(this.state.model?.name ?? $r('app.string.role_model_empty')).fontSize(AppFont.BodyL)
        .fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.state.model !== null ? $r('app.string.role_model_size', Math.round(this.state.model.bytes / 1024 / 1024)) :
        $r('app.string.role_model_empty_hint')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      if (this.state.busy) {
        Row({ space: AppSpace.Xs }) {
          LoadingProgress().width(22).height(22).color(AppColor.Brand)
          Text(this.state.verifying ? $r('app.string.role_model_verifying') :
            $r('app.string.role_model_copying', this.state.progress)).fontSize(AppFont.Body)
            .fontColor(AppTheme.TextSecondary).layoutWeight(1)
          Button($r('app.string.common_cancel')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
            .onClick((): void => this.model.cancelImport()).id('role-model-cancel')
        }.width('100%')
        if (!this.state.verifying) {
          Progress({ value: this.state.progress, total: 100, type: ProgressType.Linear }).width('100%').color(AppColor.Brand)
        }
        Text($r('app.string.role_model_leave_hint')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      } else {
        Button(this.state.model === null ? $r('app.string.role_model_import') : $r('app.string.role_model_replace'))
          .width('100%').constraintSize({ minHeight: 44 }).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
          .enabled(!this.saving).onClick((): void => { this.importModel(); }).id('role-model-import')
      }
      if (this.state.error) { Text(this.state.error).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary) }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Md).borderRadius(AppRadius.Lg)
      .backgroundColor(AppTheme.Surface)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        if (this.ready) {
          Scroll() {
            Column({ space: AppSpace.Md }) {
              this.modelCard()
              Column({ space: AppSpace.Sm }) {
                Text($r('app.string.role_model_download_title')).fontSize(AppFont.BodyL)
                  .fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
                Text($r('app.string.role_model_help')).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
                Button($r('app.string.role_model_download_link')).fontSize(AppFont.Body).fontColor(AppColor.Brand)
                  .backgroundColor(Color.Transparent).onClick((): void => { this.copyDownload(); })
              }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Md)
                .borderRadius(AppRadius.Lg).backgroundColor(AppTheme.Surface)
              if (this.state.model !== null && !this.state.busy) {
                Button($r('app.string.role_model_remove')).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
                  .backgroundColor(Color.Transparent).enabled(!this.saving)
                  .onClick((): void => this.removeModel()).id('role-model-delete')
              }
            }.width('100%').constraintSize({ maxWidth: 760 }).padding(AppSpace.Md)
          }.width('100%').height('100%').scrollBar(BarState.Off)
        } else if (this.failed) {
          Text($r('app.string.reading_settings_load_error')).fontColor(AppTheme.TextSecondary).padding(AppSpace.Lg)
          Button($r('app.string.common_retry')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
            .onClick((): void => { this.load(); })
        } else { LoadingProgress().width(32).height(32).color(AppColor.Brand).margin({ top: AppSpace.Lg }) }
      }.width('100%').height('100%').padding({ top: this.headerHeight, bottom: WindowUtils.getBottomSafeVp() })
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.role_model_manage')).fontSize(AppFont.Title).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
        }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
