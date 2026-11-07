import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { SettingsHintButton } from '../components/SettingsHintButton';
import { JianjianAiConfig } from '../model/JianjianAi';
import { JianjianAiService } from '../service/JianjianAiService';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { ListDataSource } from '../utils/ListDataSource';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct JianjianAiSettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param active: boolean = true;
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Local viewportWidth: number = 0;
  @Local viewportHeight: number = 0;
  @Local address: string = '';
  @Local apiKey: string = '';
  @Local model: string = '';
  @Local ready: boolean = false;
  @Local busy: boolean = false;
  @Local saving: boolean = false;
  @Local message: ResourceStr = '';
  @Local showModels: boolean = false;
  @Local modelCount: number = 0;
  @Local filter: string = '';
  private models: string[] = [];
  private modelSource: ListDataSource<string> = new ListDataSource<string>();
  private client: JianjianAiService = new JianjianAiService();
  private alive: boolean = false;
  private generation: number = 0;

  aboutToAppear(): void { this.alive = true; this.load(); }
  aboutToDisappear(): void {
    this.alive = false;
    this.generation++;
    this.client.cancel();
    this.apiKey = '';
  }

  @Monitor('active')
  onActiveChanged(): void { if (!this.active && this.busy) this.cancel(); }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.message = '';
    try {
      const config = await JianjianAiService.loadConfig(context);
      if (!this.alive) return;
      this.address = config.address;
      this.apiKey = config.apiKey;
      this.model = config.model;
      this.ready = true;
    } catch (_error) { if (this.alive) this.message = $r('app.string.settings_load_failed'); }
  }

  private config(): JianjianAiConfig {
    const config = new JianjianAiConfig();
    config.address = this.address;
    config.apiKey = this.apiKey;
    config.model = this.model;
    return config;
  }

  private invalidateModels(): void {
    this.generation++;
    this.client.cancel();
    this.busy = false;
    this.models = [];
    this.modelSource.setItems([]);
    this.modelCount = 0;
    this.model = '';
    this.message = '';
  }

  private async fetchModels(): Promise<void> {
    if (this.busy || this.saving) return;
    const generation = ++this.generation;
    this.busy = true;
    this.message = '';
    try {
      const config = JianjianAiService.normalize(this.config());
      const models = await this.client.listModels(config);
      if (!this.alive || generation !== this.generation) return;
      this.address = config.address;
      this.models = models;
      this.modelCount = models.length;
      if (!models.includes(this.model)) this.model = '';
      this.filter = '';
      this.modelSource.setItems(models);
      if (models.length) this.showModels = true;
      else this.message = $r('app.string.jianjian_ai_models_empty');
    } catch (error) {
      if (this.alive && generation === this.generation) this.message = JianjianAiService.errorText(error);
    } finally { if (this.alive && generation === this.generation) this.busy = false; }
  }

  private cancel(): void {
    this.generation++;
    this.client.cancel();
    this.busy = false;
    this.message = $r('app.string.jianjian_ai_cancelled');
  }

  private async save(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.saving || this.busy) return;
    let config: JianjianAiConfig;
    try { config = JianjianAiService.normalize(this.config(), true); }
    catch (error) { this.message = JianjianAiService.errorText(error); return; }
    this.saving = true;
    try {
      await JianjianAiService.saveConfig(context, config);
      if (!this.alive) return;
      this.address = config.address;
      this.message = $r('app.string.jianjian_ai_saved');
    } catch (_error) { if (this.alive) this.message = $r('app.string.settings_save_failed'); }
    finally { if (this.alive) this.saving = false; }
  }

  private async clear(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.saving || this.busy) return;
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: $r('app.string.jianjian_ai_clear'), message: $r('app.string.jianjian_ai_clear_confirm'),
      buttons: [{ text: $r('app.string.common_cancel'), color: AppTheme.TextSecondary },
        { text: $r('app.string.jianjian_ai_clear'), color: AppColor.Brand }] });
    if (result.index !== 1 || !this.alive) return;
    this.saving = true;
    try {
      await JianjianAiService.clearConfig(context);
      if (!this.alive) return;
      this.address = ''; this.apiKey = ''; this.invalidateModels();
      this.message = $r('app.string.jianjian_ai_cleared');
    } catch (_error) { if (this.alive) this.message = $r('app.string.settings_save_failed'); }
    finally { if (this.alive) this.saving = false; }
  }

  @Builder
  private modelsSheet() {
    Column({ space: AppSpace.Sm }) {
      Text($r('app.string.jianjian_ai_model')).fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TextPrimary).width('100%')
      Search({ value: this.filter, placeholder: $r('app.string.jianjian_ai_model_search') })
        .onChange((value: string): void => {
          this.filter = value;
          this.modelSource.setItems(this.models.filter((id: string): boolean => id.toLowerCase().includes(value.toLowerCase())));
        })
      List() {
        LazyForEach(this.modelSource, (id: string) => {
          ListItem() {
            Row({ space: AppSpace.Sm }) {
              Text(id).fontSize(AppFont.BodyL).fontColor(this.model === id ? AppColor.Brand : AppTheme.TextPrimary)
                .layoutWeight(1).maxLines(3)
              if (this.model === id) {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(20).fontColor([AppColor.Brand])
              }
            }.width('100%').constraintSize({ minHeight: 52 }).padding(AppSpace.Sm)
              .onClick((): void => { this.model = id; this.showModels = false; this.message = ''; })
          }
        }, (id: string): string => id)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    }.width('100%').height('100%').padding({ left: AppSpace.Md, right: AppSpace.Md,
      top: AppSpace.Md, bottom: WindowUtils.getBottomSafeVp() + AppSpace.Md })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: AppSpace.Md }) {
          if (this.ready) {
            Column() {
              Text($r('app.string.jianjian_ai_service')).fontSize(AppFont.Body).fontColor(AppTheme.TextTertiary)
                .padding({ left: AppSpace.Sm, bottom: 6 })
              Column({ space: AppSpace.Sm }) {
                Row({ space: 2 }) {
                  Text($r('app.string.jianjian_ai_address')).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
                  SettingsHintButton({ title: $r('app.string.jianjian_ai_address'),
                    message: $r('app.string.jianjian_ai_protocol_hint') })
                }.width('100%')
                TextInput({ text: this.address, placeholder: $r('app.string.jianjian_ai_address_hint') })
                  .id('jianjian-ai-address').type(InputType.URL).maxLength(2048)
                  .backgroundColor(AppTheme.SettingsBackground).borderRadius(AppRadius.Md)
                  .onChange((value: string): void => { if (value !== this.address) { this.address = value; this.invalidateModels(); } })
                Row({ space: 2 }) {
                  Text($r('app.string.jianjian_ai_key')).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
                  SettingsHintButton({ title: $r('app.string.jianjian_ai_key'),
                    message: $r('app.string.jianjian_ai_privacy') })
                }.width('100%')
                TextInput({ text: this.apiKey, placeholder: $r('app.string.jianjian_ai_key_hint') })
                  .id('jianjian-ai-key').type(InputType.Password).maxLength(4096)
                  .backgroundColor(AppTheme.SettingsBackground).borderRadius(AppRadius.Md)
                  .onChange((value: string): void => { if (value !== this.apiKey) { this.apiKey = value; this.invalidateModels(); } })
              }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Md)
                .backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg).enabled(!this.saving && !this.busy)
            }.width('100%').alignItems(HorizontalAlign.Start)
            Column() {
              Text($r('app.string.jianjian_ai_model')).fontSize(AppFont.Body).fontColor(AppTheme.TextTertiary)
                .padding({ left: AppSpace.Sm, bottom: 6 })
              Column() {
                Row({ space: AppSpace.Sm }) {
                  Text($r('app.string.jianjian_ai_fetch_models')).fontSize(AppFont.BodyL).fontColor(AppColor.Brand).layoutWeight(1)
                  if (this.busy) { LoadingProgress().width(20).height(20).color(AppColor.Brand) }
                  else { SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([AppColor.Brand]) }
                }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: AppSpace.Md, right: AppSpace.Md })
                  .enabled(!this.busy && !this.saving).onClick((): void => { this.fetchModels(); }).id('jianjian-ai-fetch-models')
                Divider().strokeWidth(0.5).color(AppTheme.Divider).margin({ left: AppSpace.Md })
                Row({ space: AppSpace.Sm }) {
                  Text(this.model || $r('app.string.jianjian_ai_choose_model')).fontSize(AppFont.BodyL)
                    .fontColor(this.model ? AppTheme.TextPrimary : AppTheme.TextSecondary).layoutWeight(1).maxLines(3)
                  SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(20).fontColor([AppTheme.TextTertiary])
                }.width('100%').constraintSize({ minHeight: 56 }).padding(AppSpace.Md)
                  .enabled(!this.busy && !this.saving && this.modelCount > 0)
                  .onClick((): void => { this.filter = ''; this.modelSource.setItems(this.models); this.showModels = true; })
                  .id('jianjian-ai-selected-model')
              }.width('100%').backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg)
            }.width('100%').alignItems(HorizontalAlign.Start)
            Row({ space: AppSpace.Sm }) {
              Button($r('app.string.common_save'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor(AppColor.Brand)
                .enabled(!this.saving && !this.busy && !!this.model).onClick((): void => { this.save(); }).id('jianjian-ai-save')
              if (this.busy) {
                Button($r('app.string.common_cancel'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor(AppColor.Brand)
                  .onClick((): void => this.cancel())
              } else {
                Button($r('app.string.jianjian_ai_clear'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor(AppTheme.TextSecondary)
                  .enabled(!this.saving).onClick((): void => { this.clear(); })
              }
              if (this.saving) { LoadingProgress().width(20).height(20).color(AppColor.Brand) }
            }.width('100%')
          } else if (!this.message) { LoadingProgress().width(32).height(32).color(AppColor.Brand) }
          if (this.message) { Text(this.message).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary).width('100%') }
          if (!this.ready && this.message) {
            Button($r('app.string.common_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor(AppColor.Brand)
              .onClick((): void => { this.load(); })
          }
        }.width('100%').padding({ top: this.headerHeight + AppSpace.Sm,
          left: AdaptiveLayout.isCompact(this.viewportWidth, this.viewportHeight) ? AppSpace.Sm : AppSpace.Md,
          right: AdaptiveLayout.isCompact(this.viewportWidth, this.viewportHeight) ? AppSpace.Sm : AppSpace.Md,
          bottom: WindowUtils.getBottomSafeVp() + AppSpace.Xl })
      }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.jianjian_ai_settings')).fontSize(AppFont.TitleL).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
        }.width('100%').padding({ left: AppSpace.Md, right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
          bottom: AdaptiveLayout.isCompact(this.viewportWidth, this.viewportHeight) ? AppSpace.Sm : AppSpace.Md })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        this.viewportWidth = Number(size.width); this.viewportHeight = Number(size.height);
      })
      .bindSheet($$this.showModels, this.modelsSheet(), { height: SheetSize.LARGE, showClose: true,
        dragBar: true, backgroundColor: AppTheme.Surface })
  }
}
