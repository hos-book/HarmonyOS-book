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
  @Param navStack: NavPathStack = new NavPathStack();
  @Local state: TextToSpeechState = TextToSpeechService.getInstance().state;
  @Local group: string = '';
  @Local tier: string = '';
  @Local query: string = '';
  @Local ready: boolean = false;
  @Local failed: boolean = false;
  @Local busy: boolean = false;
  @Local managing: boolean = false;
  @Local sorting: boolean = false;
  @Local selectedIds: string[] = [];
  @Local visibleConfigs: CustomTtsConfig[] = [];
  @Local showImport: boolean = false;
  @Local importMode: string = 'url';
  @Local input: string = '';
  @Local importError: ResourceStr = '';
  private service: TextToSpeechService = TextToSpeechService.getInstance();
  private source: ReaderTtsDataSource = new ReaderTtsDataSource();

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

  private async sortVoices(descending: boolean, id: string = '', step: number = 0): Promise<void> {
    if (this.busy) return;
    const catalog = this.visibleConfigs.slice();
    if (id) {
      const index = catalog.findIndex((item: CustomTtsConfig): boolean => item.id === id);
      const target = index + step;
      if (index < 0 || target < 0 || target >= catalog.length) return;
      const item = catalog[index];
      catalog[index] = catalog[target];
      catalog[target] = item;
    } else {
      catalog.sort((a: CustomTtsConfig, b: CustomTtsConfig): number =>
        (descending ? -1 : 1) * a.name.localeCompare(b.name));
    }
    this.busy = true;
    try { await this.service.reorderCustomTts(catalog.map((item: CustomTtsConfig): string => item.id)); }
    catch (_error) { this.toast($r('app.string.tts_save_error')); }
    finally { this.busy = false; }
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
  managementTools() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button(this.sorting ? $r('app.string.tts_manage_done') : $r('app.string.tts_sort'))
          .layoutWeight(1).fontColor(AppColor.Brand).backgroundColor(AppTheme.Background)
          .enabled(!this.busy && !this.managing && (this.sorting || this.visibleConfigs.length > 0))
          .onClick((): void => { this.sorting = !this.sorting; })
        Button(this.managing ? $r('app.string.tts_manage_done') : $r('app.string.tts_batch'))
          .layoutWeight(1).fontColor(AppColor.Brand).backgroundColor(AppTheme.Background)
          .enabled(!this.busy && !this.sorting && (this.managing || this.visibleConfigs.length > 0))
          .onClick((): void => { this.managing = !this.managing; this.selectedIds = []; })
      }.width('100%')
      if (this.sorting) {
        Row({ space: 8 }) {
          Button($r('app.string.tts_sort_name_asc')).layoutWeight(1)
            .fontColor(AppColor.Brand).backgroundColor(AppTheme.Background).enabled(!this.busy)
            .onClick((): void => { this.sortVoices(false); })
          Button($r('app.string.tts_sort_name_desc')).layoutWeight(1)
            .fontColor(AppColor.Brand).backgroundColor(AppTheme.Background).enabled(!this.busy)
            .onClick((): void => { this.sortVoices(true); })
        }.width('100%')
        Text($r('app.string.tts_sort_hint')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      }
    }.width('100%')
  }

  @Builder
  batchBar() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.tts_batch_selected', this.selectedIds.length)).layoutWeight(1)
          .fontColor(AppTheme.TextPrimary)
        Button(this.selectedIds.length === this.visibleConfigs.length && this.visibleConfigs.length > 0 ?
          $r('app.string.tts_batch_clear') : $r('app.string.tts_batch_all'))
          .fontColor(AppColor.Brand).backgroundColor(Color.Transparent).enabled(!this.busy)
          .onClick((): void => {
            this.selectedIds = this.selectedIds.length === this.visibleConfigs.length ? [] :
              this.visibleConfigs.map((item: CustomTtsConfig): string => item.id);
          })
      }.width('100%')
      Row({ space: 8 }) {
        Button($r('app.string.tts_batch_enable')).layoutWeight(1)
          .fontColor(AppColor.Brand).backgroundColor(AppTheme.Background)
          .onClick((): void => { this.applyBatch(false, true); })
        Button($r('app.string.tts_batch_disable')).layoutWeight(1)
          .fontColor(AppColor.Brand).backgroundColor(AppTheme.Background)
          .onClick((): void => { this.applyBatch(false, false); })
        Button($r('app.string.tts_batch_delete')).layoutWeight(1)
          .fontColor(AppColor.Brand).backgroundColor(AppTheme.Background)
          .onClick((): void => { this.confirmBatchDelete(); })
      }.width('100%').enabled(!this.busy && this.selectedIds.length > 0)
    }.width('100%').constraintSize({ maxWidth: 760 }).padding(16).backgroundColor(AppTheme.Surface)
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
      if (this.managing) {
        Checkbox({ name: config.id }).select(this.selectedIds.includes(config.id))
          .selectedColor(AppColor.Brand).enabled(!this.busy).accessibilityText(config.name)
          .onChange((selected: boolean): void => { this.selectItem(config.id, selected); })
      }
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
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
        .enabled(!this.busy && (this.managing || (config.enabled && !this.sorting && !this.state.downloadingVoice)))
        .opacity(config.enabled ? 1 : 0.5).accessibilitySelected(this.state.customTtsId === config.id)
        .onClick((): void => {
          if (this.managing) this.selectItem(config.id, !this.selectedIds.includes(config.id));
          else this.service.selectCustomTts(config.id);
        })
      if (this.sorting) {
        Column({ space: 4 }) {
          Button($r('app.string.tts_sort_up')).fontSize(AppFont.Caption).fontColor(AppColor.Brand)
            .backgroundColor(AppTheme.Background)
            .enabled(!this.busy && this.visibleConfigs[0]?.id !== config.id)
            .onClick((): void => { this.sortVoices(false, config.id, -1); })
          Button($r('app.string.tts_sort_down')).fontSize(AppFont.Caption).fontColor(AppColor.Brand)
            .backgroundColor(AppTheme.Background)
            .enabled(!this.busy && this.visibleConfigs[this.visibleConfigs.length - 1]?.id !== config.id)
            .onClick((): void => { this.sortVoices(false, config.id, 1); })
        }
      } else if (!this.managing) {
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
    }.width('100%').constraintSize({ minHeight: 76 }).padding(16)
      .backgroundColor(AppTheme.Surface).borderRadius(16).border({ width: 0.5, color: AppTheme.Divider })
  }

  @Builder
  systemRow(voice: SpeechVoice) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(voice.label).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(voice.language).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
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
    }.width('100%').constraintSize({ minHeight: 76 }).padding(16)
      .backgroundColor(AppTheme.Surface).borderRadius(16).border({ width: 0.5, color: AppTheme.Divider })
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
        }.width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
        Text($r('app.string.tts_voice_management')).fontSize(AppFont.Title)
          .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
      }.width('100%').padding({ left: 8, right: 16, top: WindowUtils.getStatusBarHeightVp() + 8, bottom: 8 })
      if (this.ready) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          List({ space: 12 }) {
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
            ListItem() {
              Text($r('app.string.tts_custom_title')).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary).padding({ top: 12 })
            }
            ListItem() {
              Column({ space: 12 }) {
                TextInput({ text: this.query, placeholder: $r('app.string.tts_voice_search') })
                  .onChange((value: string): void => { this.query = value; })
                Row({ space: 12 }) {
                  Text($r('app.string.tts_voice_group')).fontColor(AppTheme.TextSecondary)
                  Select(this.filterOptions(true)).value(this.group || $r('app.string.tts_filter_all'))
                    .onSelect((index: number): void => { this.group = index > 0 ? this.filterValues(true)[index - 1] : ''; })
                  Text($r('app.string.tts_voice_tier')).fontColor(AppTheme.TextSecondary)
                  Select(this.filterOptions(false)).value(this.tier || $r('app.string.tts_filter_all'))
                    .onSelect((index: number): void => { this.tier = index > 0 ? this.filterValues(false)[index - 1] : ''; })
                }.width('100%')
                this.managementTools()
              }.padding(12).width('100%').backgroundColor(AppTheme.Surface).borderRadius(16)
            }
            if (this.visibleConfigs.length === 0) {
              ListItem() { Text($r('app.string.tts_voice_empty')).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary).padding(20) }
            }
            LazyForEach(this.source, (config: CustomTtsConfig) => {
              ListItem() { this.customRow(config) }
            }, (config: CustomTtsConfig): string => `${config.id}:${config.enabled}`)
            ListItem() {
              Text($r('app.string.tts_custom_enabled_hint')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
            }
            ListItem() { Row().height(84) }
          }.width('100%').height('100%').padding({ left: 16, right: 16 }).scrollBar(BarState.Off)
          if (!this.managing && !this.sorting) {
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
        if (this.managing) { this.batchBar() }
      } else if (this.failed) {
        Text($r('app.string.reading_settings_load_error')).fontColor(AppTheme.TextSecondary).padding(20)
        Button($r('app.string.common_retry')).onClick((): void => { this.initialize(); })
          .fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
      } else { LoadingProgress().width(32).height(32).color(AppColor.Brand) }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .padding({ bottom: WindowUtils.getBottomSafeVp() })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindContentCover($$this.showImport, this.importDialog(), {
        modalTransition: ModalTransition.NONE,
        onWillDismiss: (action: DismissContentCoverAction): void => {
          if (!this.busy) action.dismiss();
        }
      })
  }
}
