import { sendableContextManager } from '@kit.AbilityKit';
import { ShengqiaoState } from '../model/ShengqiaoPlugin';
import { ShengqiaoPluginService } from '../service/text/ShengqiaoPluginService';
import { ShengqiaoSynthesis, ShengqiaoTtsService } from '../service/text/ShengqiaoTtsService';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { InfinityLoadingIndicator } from './InfinityLoadingIndicator';
import { ModelManagementRow } from './ModelManagementRow';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';

@ComponentV2
export struct ShengqiaoPluginCard {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param blocked: boolean = false;
  @Event onChanging: (changing: boolean) => void = () => {};
  @Local expanded: boolean = false;
  @Local state: ShengqiaoState = ShengqiaoPluginService.instance.state;
  private plugin: ShengqiaoPluginService = ShengqiaoPluginService.instance;
  private testRequest: ShengqiaoSynthesis | null = null;

  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void { this.testRequest?.cancel(); }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    try { await this.plugin.initialize(context); }
    catch (_error) { this.state.result = $r('app.string.shengqiao_operation_failed'); }
  }

  private async change(action: string, active: boolean = false): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.blocked || this.state.busy || this.state.testing) return;
    this.onChanging(true);
    try {
      const speech = TextToSpeechService.getInstance();
      await speech.initialize(sendableContextManager.convertToUIAbilityContext(sendableContextManager.convertFromContext(context)));
      if (action === 'import') {
        if (!await this.plugin.pick(sendableContextManager.convertToUIAbilityContext(sendableContextManager.convertFromContext(context)))) return;
      } else if (action === 'remove') await this.plugin.remove();
      else await this.plugin.setActive(active);
      await speech.refreshShengqiaoVoices(action === 'import');
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.shengqiao_operation_failed') });
    } finally { this.onChanging(false); }
  }

  private confirmRemove(): void {
    this.getUIContext().showAlertDialog({ title: $r('app.string.shengqiao_remove_title'),
      message: $r('app.string.shengqiao_remove_hint'),
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.comic_plugin_remove'), action: (): void => { this.change('remove'); } } });
  }

  private async test(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    const voice = this.plugin.voices().find((item): boolean => this.plugin.voice(item.modelId)?.channel === 'edge');
    if (!context || !voice || this.state.testing) return;
    this.state.testing = true;
    this.state.result = $r('app.string.shengqiao_testing');
    this.testRequest = new ShengqiaoSynthesis();
    try { await this.testRequest.synthesize(voice, context.resourceManager.getStringSync($r('app.string.shengqiao_sample').id)); }
    catch (error) { this.state.result = ShengqiaoTtsService.errorMessage(error); }
    finally { this.testRequest = null; this.state.testing = false; }
  }

  private info(): void {
    this.getUIContext().showAlertDialog({ title: $r('app.string.shengqiao_title'),
      message: $r('app.string.shengqiao_description'),
      confirm: { value: $r('app.string.common_ok'), action: (): void => {} } });
  }

  build() {
    Column() {
      ModelManagementRow({ itemId: 'shengqiao', label: $r('app.string.shengqiao_title'),
        blocked: this.blocked || !this.state.ready || this.state.busy || this.state.testing,
        removable: this.state.installed, showSwitch: true, switchEnabled: this.state.installed,
        active: this.state.active, expandable: true, expanded: this.expanded,
        importLabel: this.state.installed ? $r('app.string.comic_plugin_replace') : $r('app.string.comic_plugin_import'),
        onInfo: (): void => this.info(), onImport: (): void => { this.change('import'); },
        onRemove: (): void => this.confirmRemove(),
        onActive: (active: boolean): void => { if (active !== this.state.active) this.change('active', active); },
        onExpand: (): void => { this.expanded = !this.expanded; } })
      if (this.expanded) {
        Column() {
          Divider().strokeWidth(0.5).color(AppTheme.Divider)
          Text(this.state.installed ? $r('app.string.shengqiao_installed', this.state.version, this.state.voiceCount) :
            $r('app.string.comic_plugin_missing')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
            .width('100%').padding({ top: AppSpace.Sm, bottom: AppSpace.Sm })
          Button({ type: ButtonType.Normal }) {
            Row({ space: AppSpace.Sm }) {
              Text($r('app.string.shengqiao_account')).fontSize(AppFont.Body).fontColor(AppTheme.TextPrimary).layoutWeight(1)
              Text(this.state.loggedIn ? $r('app.string.shengqiao_account_ready') : $r('app.string.shengqiao_account_pending'))
                .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppTheme.TextTertiary])
            }.width('100%')
          }.width('100%').height(48).padding(0).backgroundColor(Color.Transparent).borderRadius(AppRadius.Sm)
            .enabled(this.state.installed && !this.blocked && !this.state.busy && !this.state.testing)
            .onClick((): void => { this.navStack.pushPathByName('shengqiaoAccount', null); })
          Button({ type: ButtonType.Normal }) {
            Row({ space: AppSpace.Sm }) {
              Text($r('app.string.tts_voice_management')).fontSize(AppFont.Body).fontColor(AppTheme.TextPrimary).layoutWeight(1)
              Text($r('app.string.shengqiao_voice_count', this.state.voiceCount)).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppTheme.TextTertiary])
            }.width('100%')
          }.width('100%').height(48).padding(0).backgroundColor(Color.Transparent).borderRadius(AppRadius.Sm)
            .enabled(this.state.active && !this.blocked && !this.state.busy && !this.state.testing)
            .onClick((): void => { this.navStack.pushPathByName('voiceManagement', null); })
          Button({ type: ButtonType.Normal }) {
            Row({ space: AppSpace.Sm }) {
              Text($r('app.string.shengqiao_voice_debug')).fontSize(AppFont.Body).fontColor(AppTheme.TextPrimary).layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppTheme.TextTertiary])
            }.width('100%')
          }.width('100%').height(48).padding(0).backgroundColor(Color.Transparent).borderRadius(AppRadius.Sm)
            .enabled(this.state.active && !this.blocked && !this.state.busy && !this.state.testing)
            .onClick((): void => { this.navStack.pushPathByName('shengqiaoDebug', null); })
          Divider().strokeWidth(0.5).color(AppTheme.Divider).margin({ top: AppSpace.Sm })
          Row({ space: AppSpace.Sm }) {
            if (this.state.testing || this.state.busy) { InfinityLoadingIndicator({ indicatorSize: 16 }) }
            Column({ space: AppSpace.Xs }) {
              Text($r('app.string.shengqiao_recent_result')).fontSize(AppFont.Caption).fontColor(AppTheme.TextTertiary)
              Text(this.state.result || $r('app.string.shengqiao_result_pending')).fontSize(AppFont.Caption)
                .fontColor(AppTheme.TextSecondary).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button($r('app.string.shengqiao_test'), { type: ButtonType.Normal }).height(36)
              .fontSize(AppFont.Caption).fontColor(AppColor.Brand).backgroundColor(AppTheme.SettingsBackground)
              .borderRadius(AppRadius.Sm).padding({ left: AppSpace.Md, right: AppSpace.Md })
              .enabled(this.state.active && !this.blocked && !this.state.busy && !this.state.testing)
              .onClick((): void => { this.test(); })
          }.width('100%').padding({ top: AppSpace.Sm, bottom: AppSpace.Sm })
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Sm })
      }
    }.width('100%').alignItems(HorizontalAlign.Start).borderRadius(AppRadius.Lg)
      .backgroundColor(AppTheme.Surface)
  }
}
