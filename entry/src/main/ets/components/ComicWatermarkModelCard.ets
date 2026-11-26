import { InfinityLoadingIndicator } from './InfinityLoadingIndicator';
import { sendableContextManager } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ComicWatermarkService, ComicWatermarkState } from '../service/ComicWatermarkService';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { SettingsHintButton } from './SettingsHintButton';

@ComponentV2
export struct ComicWatermarkModelCard {
  @Param blocked: boolean = false;
  @Event onChanging: (changing: boolean) => void = () => {};
  @Local state: ComicWatermarkState = ComicWatermarkService.instance.state;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    const context = this.getUIContext().getHostContext();
    if (context) ComicWatermarkService.instance.initialize(context).catch((error: Error): void => this.showError(error));
  }

  aboutToDisappear(): void { this.alive = false; }

  private showError(error: Error): void {
    hilog.error(0x0000, 'ComicWatermark', 'Model operation failed: %{public}s', error.message);
    if (this.alive) {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.comic_watermark_model_error'),
        message: error.message,
        confirm: { value: $r('app.string.common_ok'), action: (): void => {} }
      });
    }
  }

  private async importModel(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.onChanging(true);
    try {
      await ComicWatermarkService.instance.pick(sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(context)));
    } catch (error) { this.showError(error instanceof Error ? error : new Error(String(error))); }
    finally { this.onChanging(false); }
  }

  private async removeModel(): Promise<void> {
    this.onChanging(true);
    try { await ComicWatermarkService.instance.remove(); }
    catch (error) { this.showError(error instanceof Error ? error : new Error(String(error))); }
    finally { this.onChanging(false); }
  }

  private async copySource(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
        'https://github.com/bcmi/SLBR-Visible-Watermark-Removal'));
      if (this.alive) this.getUIContext().getPromptAction().showToast({ message: $r('app.string.role_model_link_copied') });
    } catch (error) { this.showError(error instanceof Error ? error : new Error(String(error))); }
  }

  build() {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Xs }) {
        Text($r('app.string.comic_watermark_title')).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TextPrimary)
        SettingsHintButton({ title: $r('app.string.comic_watermark_title'), message: $r('app.string.comic_watermark_model_hint') })
        Blank()
        Text(this.state.installed ? $r('app.string.model_pack_installed') : $r('app.string.model_pack_missing'))
          .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      }.width('100%')
      Text($r('app.string.comic_watermark_model_size', Math.round(this.state.bytes / 1024 / 1024)))
        .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      if (this.state.busy) {
        Row({ space: AppSpace.Sm }) {
          InfinityLoadingIndicator({ indicatorSize: 22 })
          Text($r('app.string.comic_watermark_model_loading')).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
        }
      } else {
        Row({ space: AppSpace.Sm }) {
          Button(this.state.installed ? $r('app.string.model_pack_replace') : $r('app.string.model_pack_import'))
            .fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand).layoutWeight(1).enabled(!this.blocked)
            .onClick((): void => { this.importModel(); }).id('comic-watermark-model-import')
          if (this.state.installed) {
            Button($r('app.string.common_delete')).fontColor(AppTheme.TextSecondary).backgroundColor(Color.Transparent)
              .enabled(!this.blocked).onClick((): void => {
                this.getUIContext().showAlertDialog({ title: $r('app.string.model_pack_delete'),
                  message: $r('app.string.model_pack_delete_hint'),
                  primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
                  secondaryButton: { value: $r('app.string.common_delete'), action: (): void => { this.removeModel(); } } });
              }).id('comic-watermark-model-delete')
          }
        }.width('100%')
      }
      Button($r('app.string.comic_watermark_source')).fontSize(AppFont.Caption).fontColor(AppColor.Brand)
        .backgroundColor(Color.Transparent).onClick((): void => { this.copySource(); })
    }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Md)
      .borderRadius(AppRadius.Lg).backgroundColor(AppTheme.Surface)
  }
}
