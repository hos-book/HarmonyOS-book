import { emitter, pasteboard } from '@kit.BasicServicesKit';
import { ShengqiaoPageFrame } from '../components/ShengqiaoPageFrame';
import { InfinityLoadingIndicator } from '../components/InfinityLoadingIndicator';
import { CustomTtsConfig } from '../model/CustomTtsConfig';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { ShengqiaoState } from '../model/ShengqiaoPlugin';
import { ShengqiaoPluginService } from '../service/text/ShengqiaoPluginService';
import { VoicePreviewService, VoicePreviewState } from '../service/text/VoicePreviewService';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';

@ComponentV2
export struct ShengqiaoDebugPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local state: ShengqiaoState = ShengqiaoPluginService.instance.state;
  @Local configs: CustomTtsConfig[] = [];
  @Local selectedIndex: number = 0;
  @Local sampleText: string = '';
  @Local previewSpeed: number = 1;
  private preview: VoicePreviewService = new VoicePreviewService();
  @Local previewState: VoicePreviewState = this.preview.state;
  private readonly stopPreview = (): void => this.preview.stop();

  aboutToAppear(): void {
    this.configs = ShengqiaoPluginService.instance.voices();
    const context = this.getUIContext().getHostContext();
    if (context) this.sampleText = context.resourceManager.getStringSync($r('app.string.shengqiao_sample').id);
    emitter.on('app.reader.background', this.stopPreview);
  }

  aboutToDisappear(): void { this.preview.stop(); emitter.off('app.reader.background', this.stopPreview); }

  private voiceOptions(): SelectOption[] {
    const context = this.getUIContext().getHostContext();
    const member = context?.resourceManager.getStringSync($r('app.string.shengqiao_member_voice').id) ?? '';
    return this.configs.map((voice: CustomTtsConfig): SelectOption => {
      return { value: `${voice.group} · ${voice.name}${voice.tier === 'vip' ? ' · ' + member : ''}` };
    });
  }

  private async play(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    const voice = this.configs[this.selectedIndex];
    if (!context || !voice) return;
    const selection = new TextToSpeechState();
    selection.customTtsConfigs = this.configs;
    selection.customTtsId = voice.id;
    selection.speed = this.previewSpeed;
    this.state.result = $r('app.string.shengqiao_testing');
    await this.preview.play(context, selection, this.sampleText);
  }

  private async copy(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const summary = context.resourceManager.getStringSync($r('app.string.shengqiao_debug_summary').id,
      this.state.version, this.state.voiceName, this.state.elapsedMs, this.state.audioBytes);
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, summary));
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.log_copied') });
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.shengqiao_operation_failed') });
    }
  }

  build() {
    ShengqiaoPageFrame({ navStack: this.navStack, pageTitle: $r('app.string.shengqiao_debug_title') }) {
      Column({ space: AppSpace.Md }) {
        Text($r('app.string.shengqiao_voice')).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
        Select(this.voiceOptions()).selected(this.selectedIndex).value(this.configs[this.selectedIndex]?.name ?? '')
          .fontColor(AppTheme.TextPrimary).width('100%').enabled(!this.previewState.active)
          .onSelect((index: number): void => { this.selectedIndex = index; })
        Text($r('app.string.shengqiao_speed', this.previewSpeed.toFixed(1))).fontSize(AppFont.Body).fontColor(AppTheme.TextPrimary)
        Slider({ value: this.previewSpeed, min: 0.5, max: 2, step: 0.1 }).selectedColor(AppColor.Brand)
          .enabled(!this.previewState.active).onChange((speed: number): void => { this.previewSpeed = speed; })
        TextArea({ text: this.sampleText, placeholder: $r('app.string.shengqiao_sample_hint') }).height(140)
          .fontColor(AppTheme.TextPrimary).backgroundColor(AppTheme.SettingsBackground)
          .maxLength(300).enabled(!this.previewState.active).onChange((text: string): void => { this.sampleText = text; })
        Row({ space: AppSpace.Sm }) {
          if (this.previewState.loading) { InfinityLoadingIndicator({ indicatorSize: 20 }) }
          Button(this.previewState.active ? $r('app.string.shengqiao_stop') : $r('app.string.shengqiao_preview'))
            .layoutWeight(1).height(44).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
            .enabled(this.state.active && this.configs.length > 0 && this.sampleText.trim().length > 0)
            .onClick((): void => { if (this.previewState.active) this.preview.stop(); else this.play(); })
        }.width('100%')
      }.width('100%').padding(AppSpace.Md).borderRadius(AppRadius.Lg).backgroundColor(AppTheme.Surface)
      Column({ space: AppSpace.Sm }) {
        Text($r('app.string.shengqiao_debug_result')).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
        Text(this.state.result || $r('app.string.shengqiao_waiting')).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
        Text(this.state.loggedIn ? $r('app.string.shengqiao_logged_in') : $r('app.string.shengqiao_logged_out'))
          .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        Text($r('app.string.shengqiao_metrics', this.state.elapsedMs, Math.round(this.state.audioBytes / 1024)))
          .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        if (this.previewState.error) {
          Text($r('app.string.tts_preview_error')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        }
        Button($r('app.string.shengqiao_copy_debug')).height(40).fontColor(AppColor.Brand)
          .backgroundColor(AppTheme.SettingsBackground).onClick((): void => { this.copy(); })
      }.width('100%').padding(AppSpace.Md).borderRadius(AppRadius.Lg).backgroundColor(AppTheme.Surface)
        .alignItems(HorizontalAlign.Start)
    }
  }
}
