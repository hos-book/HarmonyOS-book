import { sendableContextManager } from '@kit.AbilityKit';
import { ComicImagePlugin, ComicImagePluginState } from '../model/ComicImagePlugin';
import { ComicImagePluginService } from '../service/ComicImagePluginService';
import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { InfinityLoadingIndicator } from '../components/InfinityLoadingIndicator';
import { ModelManagementRow } from '../components/ModelManagementRow';
import { AiModelSettingsPage } from './AiModelSettingsPage';
import { AppFont, AppSpace, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
struct ComicImagePluginCard {
  @Param plugin: ComicImagePlugin = new ComicImagePlugin('comic-watermarks');
  @Param busy: boolean = false;
  @Event onImport: (id: string) => void = () => {};
  @Event onRemove: (id: string) => void = () => {};
  @Event onActive: (id: string, active: boolean) => void = () => {};

  private showDescription(): void {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const resources = context.resourceManager;
    const description = resources.getStringSync(this.plugin.id === 'comic-watermarks' ?
      $r('app.string.comic_plugin_watermarks_hint').id : $r('app.string.comic_plugin_banners_hint').id);
    const status = this.plugin.installed ? resources.getStringSync($r('app.string.comic_plugin_installed').id,
      this.plugin.version, Math.round(this.plugin.bytes / 1024)) :
      resources.getStringSync($r('app.string.comic_plugin_missing').id);
    const usage = resources.getStringSync($r('app.string.comic_plugin_manage_hint').id);
    this.getUIContext().showAlertDialog({
      title: this.plugin.id === 'comic-watermarks' ? $r('app.string.comic_plugin_watermarks') :
        $r('app.string.comic_plugin_banners'),
      message: `${description}\n\n${status}\n\n${usage}`,
      confirm: { value: $r('app.string.common_ok'), action: (): void => {} }
    });
  }

  build() {
    ModelManagementRow({ itemId: this.plugin.id,
      label: this.plugin.id === 'comic-watermarks' ? $r('app.string.comic_plugin_watermarks') :
        $r('app.string.comic_plugin_banners'),
      blocked: this.busy, removable: this.plugin.installed, showSwitch: true,
      switchEnabled: this.plugin.installed, active: this.plugin.active,
      importLabel: this.plugin.installed ? $r('app.string.comic_plugin_replace') : $r('app.string.comic_plugin_import'),
      onInfo: (): void => this.showDescription(),
      onImport: (): void => this.onImport(this.plugin.id),
      onRemove: (): void => this.onRemove(this.plugin.id),
      onActive: (active: boolean): void => this.onActive(this.plugin.id, active) })
  }
}

@ComponentV2
export struct PluginManagementPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Local state: ComicImagePluginState = ComicImagePluginService.instance.state;
  @Local loading: boolean = true;
  @Local picking: boolean = false;
  @Local failed: boolean = false;
  @Local modelChanging: boolean = false;
  private service: ComicImagePluginService = ComicImagePluginService.instance;

  aboutToAppear(): void { this.load(); }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.loading = true;
    try { await this.service.initialize(context); this.failed = false; }
    catch (_error) { this.failed = true; }
    finally { this.loading = false; }
  }

  private toast(message: Resource): void { this.getUIContext().getPromptAction().showToast({ message }); }

  private async importPlugin(id: string): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.picking || this.state.busyId) return;
    this.picking = true;
    try {
      const imported = await this.service.pick(sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(context)), id);
      if (imported) this.toast($r('app.string.comic_plugin_imported'));
    } catch (_error) { this.toast($r('app.string.comic_plugin_import_error')); }
    finally { this.picking = false; }
  }

  private async removePlugin(id: string): Promise<void> {
    try { await this.service.remove(id); }
    catch (_error) { this.toast($r('app.string.comic_plugin_operation_error')); }
  }

  private async setActive(id: string, active: boolean): Promise<void> {
    try { await this.service.setActive(id, active); }
    catch (_error) { this.toast($r('app.string.comic_plugin_operation_error')); }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: AppSpace.Sm }) {
          if (this.loading) {
            InfinityLoadingIndicator({ indicatorSize: 32 })
          } else if (this.failed) {
            Text($r('app.string.comic_plugin_operation_error')).fontColor(AppTheme.TextSecondary)
          } else {
            ForEach(this.state.plugins, (plugin: ComicImagePlugin): void => {
              ComicImagePluginCard({ plugin, busy: this.picking || this.state.busyId.length > 0 || this.modelChanging,
                onImport: (id: string): void => { this.importPlugin(id); },
                onRemove: (id: string): void => { this.removePlugin(id); },
                onActive: (id: string, active: boolean): void => { this.setActive(id, active); } })
            }, (plugin: ComicImagePlugin): string => plugin.id)
          }
          AiModelSettingsPage({ blocked: this.picking || this.state.busyId.length > 0,
            onChanging: (changing: boolean): void => { this.modelChanging = changing; } })
        }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: AppSpace.Md, right: AppSpace.Md,
          top: this.headerHeight + AppSpace.Md, bottom: WindowUtils.getBottomSafeVp() + AppSpace.Xl })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.plugin_management')).fontSize(AppFont.Title).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
        }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
