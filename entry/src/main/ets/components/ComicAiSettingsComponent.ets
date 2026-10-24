import { ComicAiConfig, ComicAiModelDataSource } from '../model/ComicAiConfig';
import { ComicAiConfigService } from '../service/ComicAiConfigService';
import { AppTheme, AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';

@ComponentV2
export struct ComicAiSettingsComponent {
  @Event onSaved: () => void = () => {};
  @Local showConfig: boolean = false;
  @Local baseUrl: string = '';
  @Local apiKey: string = '';
  @Local selectedModel: string = '';
  @Local models: string[] = [];
  @Local query: string = '';
  @Local visibleCount: number = 0;
  @Local loading: boolean = true;
  @Local loadFailed: boolean = false;
  @Local busy: boolean = false;
  @Local showModels: boolean = false;
  @Local status: ResourceStr = '';
  @Local fetched: boolean = false;
  private alive: boolean = false;
  private serial: number = 0;
  private modelSource: ComicAiModelDataSource = new ComicAiModelDataSource();

  aboutToAppear(): void { this.alive = true; this.load(); }
  aboutToDisappear(): void { this.alive = false; this.serial++; this.apiKey = ''; }

  private async load(): Promise<void> {
    this.loading = true;
    this.loadFailed = false;
    const ticket = ++this.serial;
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) throw new Error('comic_ai_storage_failed');
      const config = await ComicAiConfigService.load(context);
      if (!this.alive || ticket !== this.serial) return;
      this.baseUrl = config.baseUrl;
      this.apiKey = config.apiKey;
      this.selectedModel = config.model;
      this.models = config.models;
      this.fetched = config.models.length > 0;
    } catch (_error) {
      if (this.alive) { this.loadFailed = true; this.status = $r('app.string.comic_ai_storage_failed'); }
    } finally { if (this.alive && ticket === this.serial) this.loading = false; }
  }

  private draft(): ComicAiConfig {
    const config = new ComicAiConfig();
    config.baseUrl = this.baseUrl;
    config.apiKey = this.apiKey;
    config.model = this.selectedModel;
    config.models = this.models;
    return config;
  }

  private invalidateModels(): void {
    this.serial++;
    this.selectedModel = '';
    this.models = [];
    this.showModels = false;
    this.fetched = false;
    this.status = '';
  }

  private errorText(error: Error): ResourceStr {
    switch (error.message) {
      case 'comic_ai_invalid_url': return $r('app.string.comic_ai_invalid_url');
      case 'comic_ai_invalid_key': return $r('app.string.comic_ai_invalid_key');
      case 'comic_ai_invalid_model': return $r('app.string.comic_ai_invalid_model');
      case 'comic_ai_unauthorized': return $r('app.string.comic_ai_unauthorized');
      case 'comic_ai_forbidden': return $r('app.string.comic_ai_forbidden');
      case 'comic_ai_not_found': return $r('app.string.comic_ai_not_found');
      case 'comic_ai_rate_limited': return $r('app.string.comic_ai_rate_limited');
      case 'comic_ai_invalid_response': return $r('app.string.comic_ai_invalid_response');
      case 'comic_ai_models_too_large': return $r('app.string.comic_ai_models_too_large');
      case 'comic_ai_storage_failed': return $r('app.string.comic_ai_storage_failed');
      default: return $r('app.string.comic_ai_request_failed');
    }
  }

  private async fetchModels(): Promise<void> {
    if (this.busy || this.loading) return;
    this.busy = true;
    this.status = '';
    const ticket = ++this.serial;
    try {
      const draft = this.draft();
      const models = await ComicAiConfigService.models(draft, (): boolean => !this.alive || ticket !== this.serial);
      if (!this.alive || ticket !== this.serial) return;
      this.models = models;
      this.showModels = false;
      this.fetched = true;
      this.status = $r('app.string.comic_ai_models_loaded', models.length);
      this.query = '';
      this.filterModels();
    } catch (error) {
      if (this.alive && ticket === this.serial) {
        this.status = this.errorText(error instanceof Error ? error : new Error('comic_ai_request_failed'));
      }
    } finally { if (this.alive && ticket === this.serial) this.busy = false; }
  }

  private async save(): Promise<void> {
    if (this.busy || this.loading) return;
    if (!this.selectedModel.trim()) {
      this.status = $r('app.string.comic_ai_invalid_model');
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.busy = true;
    try {
      const draft = this.draft();
      await ComicAiConfigService.save(context, draft);
      if (this.alive) {
        this.baseUrl = ComicAiConfigService.normalizeBase(draft.baseUrl);
        this.status = $r('app.string.comic_ai_saved');
        this.onSaved();
        this.showModels = false;
        this.showConfig = false;
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.comic_ai_saved') });
      }
    } catch (error) {
      if (this.alive) this.status = this.errorText(error instanceof Error ? error : new Error('comic_ai_storage_failed'));
    } finally { if (this.alive) this.busy = false; }
  }

  private async clear(): Promise<void> {
    if (this.busy || this.loading) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.busy = true;
    try {
      await ComicAiConfigService.clear(context);
      if (this.alive) {
        this.baseUrl = ''; this.apiKey = ''; this.selectedModel = ''; this.invalidateModels();
        this.status = $r('app.string.comic_ai_cleared');
        this.onSaved();
      }
    } catch (_error) { if (this.alive) this.status = $r('app.string.comic_ai_storage_failed'); }
    finally { if (this.alive) this.busy = false; }
  }

  private filterModels(): void {
    const query = this.query.trim().toLowerCase();
    const models = this.models.filter((model: string): boolean => !query || model.toLowerCase().includes(query));
    this.visibleCount = models.length;
    this.modelSource.setItems(models);
  }

  @Builder
  modelOptions() {
    Column({ space: AppSpace.Sm }) {
      Search({ value: this.query, placeholder: $r('app.string.comic_ai_search_model') })
        .onChange((value: string): void => { this.query = value; this.filterModels(); })
      Text($r('app.string.comic_ai_candidate_hint'))
        .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
      if (this.visibleCount === 0) {
        Text($r('app.string.comic_ai_no_matches')).fontColor(AppTheme.TextSecondary)
      }
      List() {
        LazyForEach(this.modelSource, (model: string) => {
          ListItem() {
            Row({ space: AppSpace.Sm }) {
              Column({ space: 4 }) {
                Text(model).fontColor(model === this.selectedModel ? AppColor.Brand : AppTheme.TextPrimary)
                  .fontSize(AppFont.Body).wordBreak(WordBreak.BREAK_ALL)
                if (ComicAiConfigService.imageCandidate(model)) {
                  Text($r('app.string.comic_ai_candidate')).fontSize(AppFont.Caption).fontColor(AppColor.Brand)
                }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              if (model === this.selectedModel) { SymbolGlyph($r('sys.symbol.checkmark')).fontColor([AppColor.Brand]) }
            }.width('100%').padding(AppSpace.Md)
          }.onClick((): void => { this.selectedModel = model; this.showModels = false; this.status = ''; })
        }, (model: string): string => model)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
        .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
    }.width('100%').height(320).padding(AppSpace.Sm)
      .border({ width: 1, color: AppColor.Brand }).borderRadius(AppRadius.Md)
  }

  @Builder
  configContent() {
    Column({ space: AppSpace.Sm }) {
      Text($r('app.string.comic_ai_settings_title'))
        .fontSize(AppFont.Body).fontColor(AppTheme.TextTertiary)
        .padding({ left: AppSpace.Sm }).width('100%')
      Column({ space: AppSpace.Sm }) {
        Text($r('app.string.comic_ai_api_address')).fontColor(AppTheme.TextPrimary).width('100%')
        TextInput({ text: this.baseUrl, placeholder: $r('app.string.comic_ai_url_placeholder') })
          .id('comic-ai-base-url').maxLength(2048)
          .enabled(!this.loading && !this.busy && !this.loadFailed)
          .onChange((value: string): void => { this.baseUrl = value; this.invalidateModels(); })
        Text($r('app.string.comic_ai_api_key')).fontColor(AppTheme.TextPrimary).width('100%')
        TextInput({ text: this.apiKey, placeholder: $r('app.string.comic_ai_key_placeholder') })
          .id('comic-ai-api-key').type(InputType.Password).showPasswordIcon(false).maxLength(4096)
          .enabled(!this.loading && !this.busy && !this.loadFailed)
          .onChange((value: string): void => { this.apiKey = value; this.invalidateModels(); })
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.comic_ai_model')).fontColor(AppTheme.TextPrimary).layoutWeight(1)
          Button($r('app.string.comic_ai_fetch_models'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('comic-ai-fetch-models').fontColor(AppColor.Brand)
            .enabled(!this.loading && !this.busy && !this.loadFailed).onClick((): void => { this.fetchModels(); })
        }.width('100%')
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: AppSpace.Sm }) {
            Text(this.selectedModel || $r('app.string.comic_ai_select_model'))
              .fontColor(AppTheme.TextPrimary).fontSize(AppFont.Body).layoutWeight(1)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Start)
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(16).fontColor([AppColor.Brand])
              .rotate({ angle: this.showModels ? 180 : 0 })
          }.width('100%')
        }.id('comic-ai-model').width('100%').constraintSize({ minHeight: 44 })
          .padding(AppSpace.Sm).border({ width: 1, color: AppColor.Brand }).borderRadius(AppRadius.Md)
          .enabled(!this.loading && !this.busy && this.models.length > 0)
          .onClick((): void => {
            this.query = ''; this.filterModels(); this.showModels = !this.showModels;
          })
        if (this.showModels) { this.modelOptions() }
        Text($r('app.string.comic_ai_config_hint'))
          .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary).width('100%')
        if (this.baseUrl.trim().startsWith('http://')) {
          Text($r('app.string.comic_ai_http_hint')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary).width('100%')
        }
        if (this.fetched && !this.models.some((model: string): boolean => ComicAiConfigService.imageCandidate(model))) {
          Text($r('app.string.comic_ai_no_image_models')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary).width('100%')
        }
        if (this.loading || this.busy) { LoadingProgress().width(24).height(24).color(AppColor.Brand) }
        if (this.status) { Text(this.status).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary).width('100%') }
        if (this.loadFailed) {
          Button($r('app.string.common_retry')).backgroundColor(AppColor.Brand).onClick((): void => { this.load(); })
        } else {
          Row({ space: AppSpace.Md }) {
            Button($r('app.string.comic_ai_save')).id('comic-ai-save')
              .backgroundColor(AppColor.Brand)
              .layoutWeight(1).onClick((): void => { this.save(); })
            Button($r('app.string.comic_ai_clear'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontColor(AppColor.Brand).onClick((): void => { this.clear(); })
          }.width('100%').enabled(!this.loading && !this.busy)
        }
      }.width('100%').padding(AppSpace.Md).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg)
    }.width('100%')
  }

  @Builder
  configSheet() {
    Scroll() { this.configContent() }.width('100%').height('100%').scrollBar(BarState.Auto)
      .padding(AppSpace.Md)
  }

  build() {
    Button($r('app.string.comic_ai_configure'), { buttonStyle: ButtonStyleMode.TEXTUAL })
      .id('comic-ai-configure').fontColor(AppColor.Brand)
      .onClick((): void => { this.showConfig = true; })
      .bindSheet($$this.showConfig, this.configSheet(), { height: '85%', dragBar: true })
  }
}
