import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { ManagementBatchBar } from '../components/ManagementBatchBar';
import { sendableContextManager } from '@kit.AbilityKit';
import { CustomTtsConfig } from '../model/CustomTtsConfig';
import { SpeechVoice, TextToSpeechState } from '../model/TextToSpeechState';
import { ReaderTtsDataSource } from '../components/ReaderTtsTabs';
import { CustomTtsConfigParser } from '../service/text/CustomTtsConfigParser';
import { CustomTtsImportService } from '../service/text/CustomTtsImportService';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { AppColor, AppFont, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct VoiceManagementPage {
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Param navStack: NavPathStack = new NavPathStack();
  @Local state: TextToSpeechState = TextToSpeechService.getInstance().state;
  @Local group: string = '';
  @Local tier: string = '';
  @Local query: string = '';
  @Local ready: boolean = false;
  @Local failed: boolean = false;
  @Local busy: boolean = false;
  @Local managing: boolean = false;
  @Local selectedIds: string[] = [];
  @Local visibleConfigs: CustomTtsConfig[] = [];
  @Local showImport: boolean = false;
  @Local importMode: string = 'url';
  @Local input: string = '';
  @Local importError: ResourceStr = '';
  private service: TextToSpeechService = TextToSpeechService.getInstance();
  private source: ReaderTtsDataSource = new ReaderTtsDataSource();
  private readonly moveHandler: (from: number, to: number) => void =
    (from: number, to: number): void => { this.moveVoice(from, to); };

  aboutToAppear(): void { this.initialize(); }

  private async initialize(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.failed = false;
    try {
      await this.service.initialize(sendableContextManager.convertToUIAbilityContext(
        sendableContextManager.convertFromContext(context)));
      this.refreshConfigs();
      this.ready = true;
      this.service.refreshVoices();
    } catch (_error) { this.failed = true; }
  }

  @Monitor('state.customTtsConfigs', 'group', 'tier', 'query')
  refreshConfigs(): void {
    const query = this.query.trim().toLowerCase();
    this.visibleConfigs = this.state.customTtsConfigs.filter((config: CustomTtsConfig): boolean =>
      (!this.group || config.group === this.group) && (!this.tier || config.tier === this.tier) &&
      (!query || config.name.toLowerCase().includes(query)));
    this.selectedIds = this.selectedIds.filter((id: string): boolean =>
      this.visibleConfigs.some((config: CustomTtsConfig): boolean => config.id === id));
    this.source.update(this.visibleConfigs, false);
  }

  private selectItem(id: string, selected: boolean): void {
    if (this.busy) return;
    this.selectedIds = this.selectedIds.filter((value: string): boolean => value !== id);
    if (selected) this.selectedIds = [...this.selectedIds, id];
  }

  private async saveVoiceOrder(catalog: CustomTtsConfig[]): Promise<void> {
    if (this.busy) return;
    const previous = this.visibleConfigs;
    this.busy = true;
    // 原生落位动画要求在 onMove 返回前同步更新顺序，持久化失败再回滚。
    this.visibleConfigs = catalog;
    this.source.update(catalog, false);
    try { await this.service.reorderCustomTts(catalog.map((item: CustomTtsConfig): string => item.id)); }
    catch (_error) {
      this.visibleConfigs = previous;
      this.source.update(previous, false);
      this.toast($r('app.string.tts_save_error'));
    } finally { this.busy = false; }
  }

  private moveVoice(from: number, to: number): void {
    if (this.busy || from === to || from < 0 || to < 0 ||
      from >= this.visibleConfigs.length || to >= this.visibleConfigs.length) return;
    const catalog = this.visibleConfigs.slice();
    catalog.splice(to, 0, catalog.splice(from, 1)[0]);
    this.saveVoiceOrder(catalog);
  }

  private async applyBatch(remove: boolean, enabled: boolean): Promise<void> {
    if (this.busy || this.selectedIds.length === 0) return;
    this.busy = true;
    try {
      await this.service.updateCustomTtsBatch(this.selectedIds.slice(), remove, enabled);
      this.selectedIds = [];
      this.toast($r('app.string.tts_batch_success'));
    } catch (_error) { this.toast($r('app.string.tts_save_error')); }
    finally { this.busy = false; }
  }

  private confirmBatchDelete(): void {
    if (this.busy || this.selectedIds.length === 0) return;
    this.getUIContext().showAlertDialog({
      title: $r('app.string.tts_batch_delete'),
      message: $r('app.string.tts_batch_delete_confirm', this.selectedIds.length),
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.rule_source_delete_action'),
        action: (): void => { this.applyBatch(true, false); } }
    });
  }

  @Builder
  managementButtons() {
    Row({ space: 6 }) {
      Button(this.managing ? $r('app.string.tts_manage_done') : $r('app.string.tts_batch'))
        .height(32).fontSize(AppFont.Caption).padding({ left: 10, right: 10 })
        .fontColor(this.managing ? AppColor.OnBrand : AppColor.Brand)
        .backgroundColor(this.managing ? AppColor.Brand : AppTheme.Surface)
        .enabled(this.ready && !this.busy && (this.managing || this.visibleConfigs.length > 0))
        .onClick((): void => { this.managing = !this.managing; this.selectedIds = []; }).id('tts-batch-voices')
    }
  }

  private filterOptions(group: boolean): SelectOption[] {
    const options: SelectOption[] = [{ value: $r('app.string.tts_filter_all') }];
    const values = this.filterValues(group);
    for (const value of values) options.push({ value: value });
    return options;
  }

  private filterValues(group: boolean): string[] {
    return Array.from(new Set(this.state.customTtsConfigs.map((config: CustomTtsConfig): string =>
      group ? config.group : config.tier).filter((value: string): boolean => value.length > 0))).sort();
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private openImport(mode: string): void {
    this.importMode = mode;
    this.input = '';
    this.importError = '';
    this.showImport = true;
  }

  private async pickFile(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.busy) return;
    this.busy = true;
    try {
      const result = await CustomTtsImportService.pick(context);
      if (result.configs.length > 0) await this.service.importCustomTts(result.configs);
      if (result.failedFiles > 0) {
        this.toast($r('app.string.tts_custom_import_partial', result.configs.length, result.failedFiles));
      } else if (result.configs.length > 0) {
        this.toast($r('app.string.tts_custom_import_success', result.configs.length));
      }
    } catch (_error) { this.toast($r('app.string.tts_custom_import_error')); }
    finally { this.busy = false; }
  }

  private async importInput(): Promise<void> {
    if (this.busy || !this.input.trim()) return;
    this.busy = true;
    this.importError = '';
    try {
      const configs = this.importMode === 'url' ? await CustomTtsImportService.fromUrl(this.input) :
        CustomTtsConfigParser.parse(this.input);
      await this.service.importCustomTts(configs);
      this.showImport = false;
      this.input = '';
      this.toast($r('app.string.tts_custom_import_success', configs.length));
    } catch (_error) {
      this.importError = this.importMode === 'url' ? $r('app.string.tts_custom_url_error') :
        $r('app.string.tts_custom_import_error');
    } finally { this.busy = false; }
  }

  private async updateVoice(config: CustomTtsConfig, remove: boolean, enabled: boolean): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      if (remove) await this.service.removeCustomTts(config.id);
      else await this.service.setCustomTtsEnabled(config.id, enabled);
    } catch (_error) { this.toast($r('app.string.tts_save_error')); }
    finally { this.busy = false; }
  }

  @Builder
  importForm() {
    Column({ space: 16 }) {
      Text(this.importMode === 'url' ? $r('app.string.tts_custom_url_import') : $r('app.string.tts_custom_paste'))
        .fontSize(AppFont.Title).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
      if (this.importMode === 'url') {
        Text($r('app.string.tts_custom_url_hint')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        TextInput({ text: this.input, placeholder: $r('app.string.tts_custom_url_placeholder') })
          .type(InputType.URL).maxLength(8192).enabled(!this.busy).id('tts-import-url-input')
          .onChange((value: string): void => { this.input = value; })
      } else {
        TextArea({ text: this.input, placeholder: $r('app.string.tts_custom_paste_hint') })
          .height(150).maxLength(1024 * 1024).enabled(!this.busy)
          .onChange((value: string): void => { this.input = value; })
      }
      if (this.importError !== '') {
        Text(this.importError).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      }
      Row({ space: 12 }) {
        Button($r('app.string.common_cancel')).layoutWeight(1).fontColor(AppTheme.TextPrimary)
          .backgroundColor(AppTheme.Background).enabled(!this.busy)
          .onClick((): void => { this.showImport = false; })
        Button($r('app.string.tts_custom_confirm')).layoutWeight(1).fontColor(AppColor.OnBrand)
          .backgroundColor(AppColor.Brand).enabled(!this.busy && this.input.trim().length > 0)
          .onClick((): void => { this.importInput(); }).id('tts-import-confirm')
        if (this.busy) { LoadingProgress().width(24).height(24).color(AppColor.Brand) }
      }.width('100%')
    }.width('100%').padding(24).alignItems(HorizontalAlign.Start)
  }

  @Builder
  importDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Scroll() {
        this.importForm()
      }.width('90%').constraintSize({ maxWidth: 480, maxHeight: '80%' })
        .backgroundColor(AppTheme.Surface).borderRadius(24).clip(true)
        .scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor('#66000000')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  customRow(config: CustomTtsConfig) {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.line_3_horizontal')).fontSize(22).fontColor([AppTheme.TextSecondary])
        .width(32).height(40).accessibilityText($r('app.string.tts_sort_hint'))
        .id(`tts-drag-${config.id}`)
      if (this.managing) {
        Checkbox({ name: config.id }).select(this.selectedIds.includes(config.id))
          .selectedColor(AppColor.Brand).enabled(!this.busy).accessibilityText(config.name)
          .onChange((selected: boolean): void => { this.selectItem(config.id, selected); })
      }
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(config.name).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (config.group || config.tier) {
              Text([config.group, config.tier].filter((value: string): boolean => value.length > 0).join(' · '))
                .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.state.customTtsId === config.id) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([AppColor.Brand])
          }
        }.width('100%')
      }.layoutWeight(1).backgroundColor(Color.Transparent).padding(0)
        .enabled(!this.busy && (this.managing || (config.enabled && !this.state.downloadingVoice)))
        .opacity(config.enabled ? 1 : 0.5).accessibilitySelected(this.state.customTtsId === config.id)
        .onClick((): void => {
          if (this.managing) this.selectItem(config.id, !this.selectedIds.includes(config.id));
          else this.service.selectCustomTts(config.id);
        })
      if (!this.managing) {
      Toggle({ type: ToggleType.Switch, isOn: config.enabled }).selectedColor(AppColor.Brand)
        .enabled(!this.busy).accessibilityText($r('app.string.tts_custom_enabled', config.name))
        .onChange((enabled: boolean): void => {
          if (enabled !== config.enabled) this.updateVoice(config, false, enabled);
        })
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([AppTheme.TextSecondary])
      }.width(40).height(40).backgroundColor(Color.Transparent).enabled(!this.busy)
        .accessibilityText($r('app.string.rule_source_delete_action'))
        .onClick((): void => { this.updateVoice(config, true, false); })
      }
    }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 12, right: 8, top: 6, bottom: 6 })
      .backgroundColor(AppTheme.Surface).borderRadius(16).border({ width: 0.5, color: AppTheme.Divider })
  }

  @Builder
  systemRow(voice: SpeechVoice) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(voice.label).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.state.downloadingVoice === voice.id) {
        LoadingProgress().width(24).height(24).color(AppColor.Brand)
      } else if (!this.state.customTtsId && this.state.isVoiceSelected(voice) && voice.installed) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(20).fontColor([AppColor.Brand])
          .accessibilityText($r('app.string.tts_selected'))
      } else {
        Button(voice.installed ? $r('app.string.tts_select') : $r('app.string.tts_download'))
          .fontColor(AppColor.Brand).backgroundColor(AppTheme.Background)
          .enabled(!this.busy && !this.state.downloadingVoice)
          .onClick((): void => { this.service.selectVoice(voice); })
      }
    }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 12, right: 8, top: 6, bottom: 6 })
      .backgroundColor(AppTheme.Surface).borderRadius(16).border({ width: 0.5, color: AppTheme.Divider })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        if (this.ready) {
          Stack({ alignContent: Alignment.BottomEnd }) {
            List({ space: 6 }) {
              ListItem() {
                Text($r('app.string.tts_custom_title')).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary).padding({ top: 2, bottom: 2 })
              }
              ListItem() {
                Column({ space: 8 }) {
                  TextInput({ text: this.query, placeholder: $r('app.string.tts_voice_search') })
                    .height(36).fontSize(AppFont.Body).enabled(!this.busy)
                    .onChange((value: string): void => { this.query = value; })
                  Row({ space: 8 }) {
                    Text($r('app.string.tts_voice_group')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
                    Select(this.filterOptions(true)).value(this.group || $r('app.string.tts_filter_all'))
                      .controlSize(ControlSize.SMALL).font({ size: AppFont.Caption }).layoutWeight(1).enabled(!this.busy)
                      .onSelect((index: number): void => { this.group = index > 0 ? this.filterValues(true)[index - 1] : ''; })
                    Text($r('app.string.tts_voice_tier')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
                    Select(this.filterOptions(false)).value(this.tier || $r('app.string.tts_filter_all'))
                      .controlSize(ControlSize.SMALL).font({ size: AppFont.Caption }).layoutWeight(1).enabled(!this.busy)
                      .onSelect((index: number): void => { this.tier = index > 0 ? this.filterValues(false)[index - 1] : ''; })
                  }.width('100%')
                }.padding(10).width('100%').backgroundColor(AppTheme.Surface).borderRadius(14)
              }
              if (this.visibleConfigs.length === 0) {
                ListItem() { Text($r('app.string.tts_voice_empty')).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary).padding(20) }
              }
              LazyForEach(this.source, (config: CustomTtsConfig) => {
                ListItem() { this.customRow(config) }
              }, (config: CustomTtsConfig): string => `${config.id}:${config.enabled}`)
                .onMove(this.busy ? undefined : this.moveHandler)
              ListItem() {
                Text($r('app.string.tts_custom_enabled_hint')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
              }
              ListItem() {
                Row() {
                  Text($r('app.string.tts_system_voice')).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary).layoutWeight(1)
                  Button($r('app.string.tts_refresh')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
                    .onClick((): void => { this.service.refreshVoices(); })
                }.width('100%')
              }
              if (this.state.error) {
                ListItem() { Text(this.state.error).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary) }
              }
              ForEach(this.state.voices, (voice: SpeechVoice) => {
                ListItem() { this.systemRow(voice) }
              }, (voice: SpeechVoice): string => voice.id)
              ListItem() { Row().height(64) }
            }.width('100%').height('100%').padding({ left: 16, right: 16 }).scrollBar(BarState.Off)
              .contentStartOffset(this.headerHeight + 4)
            if (!this.managing) {
            Button({ type: ButtonType.Circle }) {
              if (this.busy) { LoadingProgress().width(28).height(28).color(AppColor.Brand) }
              else { SymbolGlyph($r('sys.symbol.plus')).fontSize(28).fontColor([AppColor.Brand]) }
            }.width(56).height(56).backgroundColor(AppTheme.Surface).shadow(ShadowStyle.OUTER_DEFAULT_SM)
              .margin({ right: 24, bottom: 20 }).enabled(!this.busy).id('tts-add-voice')
              .accessibilityText($r('app.string.tts_voice_add'))
              .bindMenu([
                { value: $r('app.string.tts_custom_import'), action: (): void => { this.pickFile(); } },
                { value: $r('app.string.tts_custom_url_import'), action: (): void => { this.openImport('url'); } },
                { value: $r('app.string.tts_custom_paste'), action: (): void => { this.openImport('paste'); } }
              ])
            }
          }.width('100%').constraintSize({ maxWidth: 760 }).layoutWeight(1)
        } else if (this.failed) {
          Text($r('app.string.reading_settings_load_error')).fontColor(AppTheme.TextSecondary).padding(20)
          Button($r('app.string.common_retry')).onClick((): void => { this.initialize(); })
            .fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
        } else { LoadingProgress().width(32).height(32).color(AppColor.Brand) }
      }.width('100%').height('100%')
        .padding({ top: this.ready ? 0 : this.headerHeight, bottom: WindowUtils.getBottomSafeVp() })
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: 6 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.tts_voice_management')).fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          this.managementButtons()
        }.width('100%').padding({ left: 8, right: 16, top: WindowUtils.getStatusBarHeightVp() + 8, bottom: 8 })
        if (this.managing) {
          ManagementBatchBar({ selectedCount: this.selectedIds.length, totalCount: this.visibleConfigs.length,
            busy: this.busy,
            onSelectAll: (): void => {
              this.selectedIds = this.selectedIds.length === this.visibleConfigs.length ? [] :
                this.visibleConfigs.map((item: CustomTtsConfig): string => item.id);
            },
            onEnable: (): void => { this.applyBatch(false, true); },
            onDisable: (): void => { this.applyBatch(false, false); },
            onDelete: (): void => { this.confirmBatchDelete(); } })
        }
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindContentCover($$this.showImport, this.importDialog(), {
        modalTransition: ModalTransition.NONE,
        onWillDismiss: (action: DismissContentCoverAction): void => {
          if (!this.busy) action.dismiss();
        }
      })
  }
}
