import { ProfileMenuDestination } from '../components/ProfileMenuDestination';
import { LocalRuleSource } from '../model/LocalRuleSource';
import { RuleSourceLoginRouteParams } from '../model/RuleSourceLogin';
import { LocalRuleBrowseRoute, LocalRuleControl } from '../model/LocalRulePanel';
import { LocalRulePanelService } from '../service/rulesource/LocalRulePanelService';
import { LocalRuleSourceRepository } from '../service/rulesource/LocalRuleSourceRepository';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

class ControlDataSource implements IDataSource {
  private items: LocalRuleControl[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.items.length; }
  getData(index: number): LocalRuleControl { return this.items[index]; }
  setItems(items: LocalRuleControl[]): void {
    this.items = items;
    for (const listener of this.listeners) listener.onDataReloaded();
  }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
}

@ComponentV2
export struct RuleSourcePanelPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param sourceUrl: string = '';
  @Param login: boolean = false;
  @Local source: LocalRuleSource | undefined = undefined;
  @Local controls: LocalRuleControl[] = [];
  @Local loading: boolean = true;
  @Local busy: boolean = false;
  @Local errorMessage: string = '';
  @Local entryCount: number = 0;
  @Local settingsPanel: boolean = false;
  @Local safeTop: number = WindowUtils.getStatusBarHeightVp();
  @Local safeBottom: number = WindowUtils.getBottomSafeVp();
  private entries: ControlDataSource = new ControlDataSource();
  private alive: boolean = true;
  private safeAreaListener: (top: number, bottom: number) => void = (top, bottom) => {
    this.safeTop = top;
    this.safeBottom = bottom;
  };

  aboutToAppear(): void {
    this.alive = true;
    WindowUtils.addSafeAreaListener(this.safeAreaListener);
    this.load();
  }

  aboutToDisappear(): void {
    this.alive = false;
    WindowUtils.removeSafeAreaListener(this.safeAreaListener);
  }

  private async load(): Promise<void> {
    this.settingsPanel = false;
    this.loading = true;
    this.errorMessage = '';
    try {
      const source = await LocalRuleSourceRepository.get(this.sourceUrl);
      if (source === undefined) throw new Error(this.getUIContext().getHostContext()?.resourceManager
        .getStringSync($r('app.string.rule_source_missing').id) ?? 'Source not found');
      const panel = await LocalRulePanelService.load(source, this.login);
      if (!this.alive) return;
      this.source = source;
      this.controls = panel.controls;
      this.entries.setItems(panel.entries);
      this.entryCount = panel.entries.length;
    } catch (error) {
      this.errorMessage = error instanceof Error ? error.message : String(error);
    } finally {
      this.loading = false;
    }
  }

  private async runAction(control: LocalRuleControl): Promise<void> {
    const source = this.source;
    if (source === undefined || this.busy) return;
    this.busy = true;
    this.errorMessage = '';
    try {
      const result = await LocalRulePanelService.act(source, control, this.controls, this.login);
      if (!this.alive) return;
      if (result.panel !== undefined) {
        this.controls = result.panel.controls;
        this.entries.setItems(result.panel.entries);
        this.entryCount = result.panel.entries.length;
        this.settingsPanel = true;
        return;
      }
      if (result.message) this.getUIContext().getPromptAction().showToast({ message: result.message });
      if (result.browserUrl) {
        const route = RuleSourceLoginRouteParams.of(source.bookSourceUrl, source.bookSourceName, result.browserUrl);
        // URL-only actions omit these fields in the engine's JSON response.
        route.initialHtml = result.browserHtml ?? '';
        route.injectJs = result.browserInjectJs ?? '';
        if (!route.isValid()) {
          throw new Error(this.getUIContext().getHostContext()?.resourceManager
            .getStringSync($r('app.string.rule_source_login_https_only').id) ?? 'Invalid HTTPS URL');
        }
        this.navStack.pushPathByName('ruleSourceLogin', route);
      } else if (result.searchKeyword) {
        const route = new LocalRuleBrowseRoute();
        route.sourceUrl = source.bookSourceUrl;
        route.sourceName = source.bookSourceName;
        route.title = result.searchKeyword;
        route.keyword = result.searchKeyword;
        this.navStack.pushPathByName('blockMore', route);
      } else if (result.browseUrl) {
        const route = new LocalRuleBrowseRoute();
        route.sourceUrl = source.bookSourceUrl;
        route.sourceName = source.bookSourceName;
        route.title = control.title;
        route.moreUrl = result.browseUrl;
        this.navStack.pushPathByName('blockMore', route);
      } else if (result.refresh && (!this.settingsPanel || result.refreshLogin)) {
        await this.load();
      }
    } catch (error) {
      this.errorMessage = error instanceof Error ? error.message : String(error);
    } finally {
      this.busy = false;
    }
  }

  private async choose(control: LocalRuleControl): Promise<void> {
    if (this.busy) return;
    if (control.type === 'dynamic-select') {
      if (this.source === undefined) return;
      this.busy = true;
      try {
        const options = await LocalRulePanelService.options(this.source, control);
        if (!this.alive) return;
        control.options = options;
        control.optionValues = options;
        this.errorMessage = '';
      } catch (error) {
        if (this.alive) this.errorMessage = error instanceof Error ? error.message : String(error);
        return;
      } finally { this.busy = false; }
    }
    if (control.options.length === 0) return;
    this.getUIContext().showTextPickerDialog({
      range: control.options,
      selected: Math.max(0, control.optionValues.indexOf(control.value)),
      onAccept: (result: TextPickerResult) => {
        const index = typeof result.index === 'number' ? result.index : (result.index?.[0] ?? -1);
        if (index < 0 || index >= control.optionValues.length) return;
        control.value = control.optionValues[index];
        if (control.id === 'light-native-var:mode') {
          console.info(`[RuleSourcePanel] accepted mode index=${index} value=${control.value}`);
        }
        if (control.action) this.runAction(control);
      }
    });
  }

  private openCategory(control: LocalRuleControl): void {
    const route = new LocalRuleBrowseRoute();
    route.sourceUrl = this.sourceUrl;
    route.sourceName = this.source?.bookSourceName ?? '';
    route.title = control.title;
    route.moreUrl = control.url;
    this.navStack.pushPathByName('blockMore', route);
  }

  private backFromSettings(): boolean {
    if (!this.settingsPanel) return false;
    if (!this.busy) this.load();
    return true;
  }

  build() {
    ProfileMenuDestination({ onBackRequested: (): boolean => this.backFromSettings() }) {
      Column() {
        Row({ space: AppSpace.Xs }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24)
              .fontColor([$r('sys.color.font_primary')])
          }
          .width(44).height(44).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.common_back'))
          .onClick(() => { if (!this.backFromSettings()) this.navStack.pop(); })
          Text(this.login ? $r('app.string.rule_source_login_panel') : $r('app.string.rule_source_explore'))
            .fontSize(AppFont.TitleL).fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary')).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button($r('app.string.common_retry'), { type: ButtonType.Normal })
            .height(44).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
            .enabled(!this.loading && !this.busy).onClick(() => this.load())
        }
        .width('100%').height(this.safeTop + 56)
        .padding({ top: this.safeTop, left: AppSpace.Xs, right: AppSpace.Xs })

        if (this.loading) {
          Column() {
            LoadingProgress().width(32).height(32).color(AppColor.Brand)
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: AppSpace.Sm }) {
            ListItem() {
              Text(this.source?.bookSourceName ?? '').fontSize(AppFont.BodyL)
                .fontColor($r('sys.color.font_primary')).width('100%')
            }
            if (this.errorMessage) {
              ListItem() {
                Text(this.errorMessage).fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary'))
                  .width('100%').copyOption(CopyOptions.LocalDevice)
              }
            }
            ForEach(this.controls, (control: LocalRuleControl) => {
              ListItem() { this.ControlField(control) }
            }, (control: LocalRuleControl): string => control.id)
            if (this.settingsPanel) {
              ListItem() {
                Button($r('app.string.rule_source_save'))
                  .width('100%').height(48).backgroundColor(AppColor.Brand).enabled(!this.busy)
                  .onClick(async () => {
                    const save = new LocalRuleControl();
                    save.action = 'java.refreshExplore();';
                    await this.runAction(save);
                    if (!this.errorMessage) {
                      this.settingsPanel = false;
                      await this.load();
                    }
                  })
              }
            }
            LazyForEach(this.entries, (entry: LocalRuleControl) => {
              ListItem() {
                if (entry.url) {
                  Button({ type: ButtonType.Normal }) {
                    Row({ space: AppSpace.Xs }) {
                      Text(entry.title).fontSize(AppFont.BodyL).layoutWeight(1)
                        .fontColor($r('sys.color.font_primary')).textAlign(TextAlign.Start)
                      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
                        .fontColor([$r('sys.color.font_tertiary')])
                    }.width('100%')
                  }
                  .width('100%').constraintSize({ minHeight: 48 }).borderRadius(AppRadius.Sm)
                  .padding(AppSpace.Sm).backgroundColor($r('sys.color.comp_background_secondary'))
                  .enabled(!this.busy).onClick(() => this.openCategory(entry))
                } else {
                  Text(entry.title).fontSize(AppFont.Body).fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_secondary')).width('100%').padding({ top: AppSpace.Sm })
                }
              }
            }, (entry: LocalRuleControl): string => entry.id)
            if (this.controls.length === 0 && this.entryCount === 0 && !this.errorMessage) {
              ListItem() {
                Text($r('app.string.rule_source_panel_empty')).fontSize(AppFont.Body)
                  .fontColor($r('sys.color.font_secondary')).padding({ top: AppSpace.Lg })
              }
            }
          }
          .width('100%').layoutWeight(1).scrollBar(BarState.Auto)
          .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Md, bottom: this.safeBottom + AppSpace.Lg })
        }
      }
      .width('100%').height('100%').backgroundColor($r('sys.color.background_primary'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }

  }

  @Builder
  ControlField(control: LocalRuleControl) {
    Column({ space: AppSpace.Xs }) {
      if (control.type !== 'button') {
        Text(control.title).fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary')).width('100%')
      }
      if (control.type === 'select' || control.type === 'dynamic-select') {
        Button(control.options[control.optionValues.indexOf(control.value)] || control.value || control.options[0] || control.title, { type: ButtonType.Normal })
          .width('100%').height(48).borderRadius(AppRadius.Sm)
          .backgroundColor(AppColor.BrandSoft).fontColor(AppColor.Brand)
          .enabled(!this.busy).onClick(() => this.choose(control))
      } else if (control.type === 'toggle' || control.type === 'switch' || control.type === 'checkbox') {
        Toggle({ type: ToggleType.Switch, isOn: control.value === (control.options[1] ?? 'true') })
          .selectedColor(AppColor.Brand).enabled(!this.busy)
          .onChange((value: boolean) => {
            control.value = value ? (control.options[1] ?? 'true') : (control.options[0] ?? 'false');
            if (control.action) this.runAction(control);
          })
      } else if (control.type === 'button') {
        Button(control.title, { type: ButtonType.Normal }).width('100%').height(48)
          .borderRadius(AppRadius.Sm).backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
          .enabled(!this.busy).onClick(() => this.runAction(control))
      } else {
        TextInput({ text: control.value, placeholder: control.placeholder })
          .width('100%').height(48).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
          .type(control.type === 'password' ? InputType.Password : control.type === 'number' ? InputType.Number : InputType.Normal)
          .caretColor(AppColor.Brand).backgroundColor($r('sys.color.comp_background_secondary'))
          .borderRadius(AppRadius.Sm).enabled(!this.busy)
          .onChange((value: string) => { control.value = value; })
      }
    }.width('100%')
  }
}
