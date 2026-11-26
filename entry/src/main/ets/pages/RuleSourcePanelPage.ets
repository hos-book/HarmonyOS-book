import { InfinityLoadingIndicator } from '../components/InfinityLoadingIndicator';
import { TextModifier } from '@kit.ArkUI';
import { ProfileMenuDestination } from '../components/ProfileMenuDestination';
import { LocalRuleSource } from '../model/LocalRuleSource';
import { RuleSourceLoginRouteParams } from '../model/RuleSourceLogin';
import { LocalRuleBrowseRoute, LocalRuleControl } from '../model/LocalRulePanel';
import { LocalRulePanelService } from '../service/rulesource/LocalRulePanelService';
import { LocalRuleSourceRepository } from '../service/rulesource/LocalRuleSourceRepository';
import { AppTheme, AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
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
  @Local dirty: boolean = false;
  @Local loginState: string = '';
  @Local loginUser: string = '';
  @Local runningAction: string = '';
  @Local contentWidth: number = 0;
  @Local controlRevision: number = 0;
  @Local dynamicOptions: Map<string, string[]> = new Map<string, string[]>();
  private pendingOptions: Set<LocalRuleControl> = new Set<LocalRuleControl>();
  private selectText: TextModifier = new TextModifier().fontSize(13).fontWeight(FontWeight.Regular).maxLines(3);
  private optionText: TextModifier = new TextModifier().fontSize(13).fontWeight(FontWeight.Regular)
    .maxLines(20).wordBreak(WordBreak.BREAK_ALL).textOverflow({ overflow: TextOverflow.None });
  private refreshOnReturn: boolean = false;
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

  private async load(preserveForm: boolean = false, keepPosition: boolean = false): Promise<void> {
    // Keep the mounted list and its scroll position during settings/action refreshes.
    if (!keepPosition) {
      this.settingsPanel = false;
      this.loading = true;
    }
    this.errorMessage = '';
    try {
      const source = await LocalRuleSourceRepository.get(this.sourceUrl);
      if (source === undefined) throw new Error(this.getUIContext().getHostContext()?.resourceManager
        .getStringSync($r('app.string.rule_source_missing').id) ?? 'Source not found');
      const panel = await LocalRulePanelService.load(source, this.login);
      if (!this.alive) return;
      if (preserveForm) {
        for (const control of panel.controls) {
          if (control.id.startsWith('light-native-form:')) {
            control.value = this.controls.find((old: LocalRuleControl): boolean => old.id === control.id)?.value ?? '';
          }
        }
      }
      this.source = source;
      this.dynamicOptions = new Map<string, string[]>();
      this.controls = panel.controls;
      this.controlRevision++;
      this.loginState = panel.loginState;
      this.loginUser = panel.loginUser;
      this.dirty = false;
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
    this.runningAction = control.title;
    this.errorMessage = '';
    try {
      // Account and source actions must see the settings currently displayed in the form.
      if (this.isNativeSettings() && this.dirty && control.action !== 'light-native-save') {
        await LocalRulePanelService.act(source, this.saveControl(), this.controls, true);
        this.dirty = false;
      }
      const result = await LocalRulePanelService.act(source, control, this.controls, this.login);
      if (!this.alive) return;
      if (result.panel !== undefined) {
        this.dynamicOptions = new Map<string, string[]>();
        this.controls = result.panel.controls;
        this.controlRevision++;
        this.entries.setItems(result.panel.entries);
        this.entryCount = result.panel.entries.length;
        this.settingsPanel = true;
        this.dirty = false;
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
        this.refreshOnReturn = true;
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
        await this.load(control.action !== 'light-native-submit' && control.action !== 'light-native-logout', true);
      }
      if (result.checkedLoginState) this.loginState = result.checkedLoginState;
    } catch (error) {
      this.errorMessage = error instanceof Error ? error.message : String(error);
    } finally {
      this.busy = false;
      this.runningAction = '';
    }
  }

  private async loadSelectOptions(control: LocalRuleControl): Promise<void> {
    const source = this.source;
    if (control.type !== 'dynamic-select' || source === undefined ||
      this.dynamicOptions.has(control.id) || this.pendingOptions.has(control)) return;
    this.pendingOptions.add(control);
    try {
      const options = await LocalRulePanelService.options(source, control);
      if (!this.alive || !this.controls.includes(control)) return;
      const next = new Map<string, string[]>(this.dynamicOptions);
      next.set(control.id, options);
      this.dynamicOptions = next;
    } catch (error) {
      if (this.alive && this.controls.includes(control)) {
        this.errorMessage = error instanceof Error ? error.message : String(error);
      }
    } finally {
      this.pendingOptions.delete(control);
    }
  }

  private optionLabels(control: LocalRuleControl): string[] {
    return control.type === 'dynamic-select' ? (this.dynamicOptions.get(control.id) ?? []) : control.options;
  }

  private optionValues(control: LocalRuleControl): string[] {
    return control.type === 'dynamic-select' ? this.optionLabels(control) : control.optionValues;
  }

  private optionMenuWidth(control: LocalRuleControl): number {
    const available = Math.max(120, this.contentWidth - AppSpace.Sm * 2);
    const fieldWidth = available - (this.contentWidth >= 340 ? 104 : 88) - AppSpace.Xs;
    let preferred = Math.max(120, fieldWidth);
    const uiContext = this.getUIContext();
    for (const label of this.optionLabels(control)) {
      const width = uiContext.getMeasureUtils().measureText({
        textContent: label, fontSize: 13, fontWeight: FontWeight.Regular
      });
      preferred = Math.max(preferred, uiContext.px2vp(width) + 64);
    }
    return Math.min(available, Math.ceil(preferred));
  }

  private selectOptions(control: LocalRuleControl): SelectOption[] {
    return this.optionLabels(control).map((label: string): SelectOption => { return { value: label }; });
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
    if (this.busy) return true;
    if (this.dirty) {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.rule_source_unsaved_title'),
        message: $r('app.string.rule_source_unsaved_message'),
        primaryButton: { value: $r('app.string.rule_source_save'), action: async () => {
          await this.saveSettings();
          if (!this.errorMessage && !this.dirty) this.leaveSettings();
        } },
        secondaryButton: { value: $r('app.string.rule_source_discard'), action: () => {
          this.dirty = false;
          this.leaveSettings();
        } }
      });
      return true;
    }
    if (!this.settingsPanel) return false;
    if (!this.busy) this.load();
    return true;
  }

  private leaveSettings(): void {
    if (this.settingsPanel) this.load();
    else this.navStack.pop();
  }

  private isNativeSettings(): boolean {
    return this.login && this.source?.engine === 'light-native';
  }

  private isSave(control: LocalRuleControl): boolean {
    return control.id === 'light-native-save' || control.id === 'light-login-save';
  }

  private saveControl(): LocalRuleControl {
    const existing = this.controls.find((item: LocalRuleControl): boolean => this.isSave(item));
    if (existing !== undefined) return existing;
    const save = new LocalRuleControl();
    save.action = 'java.refreshExplore();';
    return save;
  }

  private async saveSettings(): Promise<void> {
    await this.runAction(this.saveControl());
    if (!this.errorMessage && this.alive) {
      this.dirty = false;
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.rule_source_settings_saved') });
    }
  }

  private changeValue(control: LocalRuleControl, value: string, commit: boolean = false): void {
    control.value = value;
    if (this.isNativeSettings() && control.id.startsWith('light-native-var:')) {
      this.dirty = true;
    } else if (commit && control.action) {
      this.runAction(control);
    } else if (!control.id.startsWith('light-native-form:')) {
      this.dirty = true;
    }
  }

  private settingControls(): LocalRuleControl[] {
    return this.controls.filter((item: LocalRuleControl): boolean => item.type !== 'button' &&
      !item.id.startsWith('light-native-form:'));
  }

  private accountControls(): LocalRuleControl[] {
    return this.controls.filter((item: LocalRuleControl): boolean => item.id.startsWith('light-native-') &&
      !item.id.startsWith('light-native-var:') && !item.id.startsWith('light-native-action:') && !this.isSave(item));
  }

  private actionControls(): LocalRuleControl[] {
    return this.controls.filter((item: LocalRuleControl): boolean => item.type === 'button' && !this.isSave(item) &&
      (!item.id.startsWith('light-native-') || item.id.startsWith('light-native-action:')));
  }

  private accountFields(): LocalRuleControl[] {
    return this.accountControls().filter((item: LocalRuleControl): boolean => item.type !== 'button');
  }

  private accountActions(): LocalRuleControl[] {
    return this.accountControls().filter((item: LocalRuleControl): boolean => item.type === 'button');
  }

  private fieldTitle(control: LocalRuleControl): string {
    const bracket = control.title.search(/[（(]/);
    return bracket > 0 ? control.title.substring(0, bracket).trim() : control.title;
  }

  private showFieldHelp(control: LocalRuleControl): void {
    this.getUIContext().showAlertDialog({
      title: this.fieldTitle(control),
      message: control.title,
      confirm: { value: $r('app.string.common_ok'), action: (): void => {} }
    });
  }

  private controlLabel(control: LocalRuleControl): ResourceStr {
    if (control.id === 'light-native-submit') return $r('app.string.rule_source_login_action');
    if (control.id === 'light-native-check') return $r('app.string.rule_source_check_login');
    if (control.id === 'light-native-logout') return $r('app.string.rule_source_logout');
    return control.title;
  }

  build() {
    ProfileMenuDestination({ pageBackground: AppTheme.SettingsBackground,
      onBackRequested: (): boolean => this.backFromSettings() }) {
      Column() {
        Row({ space: AppSpace.Xs }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }
          .width(36).height(40).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.common_back'))
          .onClick(() => { if (!this.backFromSettings()) this.navStack.pop(); })
          Column({ space: 2 }) {
            Text(this.login || this.settingsPanel ? $r('app.string.rule_source_settings_title') : $r('app.string.rule_source_explore'))
              .fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
            if (this.source !== undefined) {
              Text(this.source.bookSourceName).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.busy) {
            InfinityLoadingIndicator({ indicatorSize: 20 })
              .accessibilityText(this.runningAction)
          }
          if (this.login || this.settingsPanel) {
            if (this.settingsPanel || this.controls.some((item: LocalRuleControl): boolean => this.isSave(item))) {
              Button($r('app.string.rule_source_save'), { type: ButtonType.Normal })
                .height(32).fontSize(13).padding({ left: AppSpace.Sm, right: AppSpace.Sm })
                .borderRadius(AppRadius.Pill).fontColor(AppColor.Brand).backgroundColor(AppColor.BrandSoft)
                .enabled(!this.loading && !this.busy && (!this.isNativeSettings() || this.dirty))
                .onClick(() => this.saveSettings())
            }
          } else {
            Button($r('app.string.common_retry'), { type: ButtonType.Normal })
              .height(44).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
              .enabled(!this.loading && !this.busy).onClick(() => this.load())
          }
        }
        .width('100%').height(this.safeTop + 44)
        .padding({ top: this.safeTop, left: AppSpace.Xs, right: AppSpace.Xs })
        if (this.loading) {
          Column() {
            InfinityLoadingIndicator({ indicatorSize: 32 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: AppSpace.Md }) {
            if (this.login || this.settingsPanel) {
              ListItem() { this.SettingsContent() }
            } else {
              ForEach(this.controls, (control: LocalRuleControl) => {
                ListItem() { this.ControlField(control) }
              }, (control: LocalRuleControl): string => `${control.id}:${this.controlRevision}`)
            }
            LazyForEach(this.entries, (entry: LocalRuleControl) => {
              ListItem() {
                if (entry.url) {
                  Button({ type: ButtonType.Normal }) {
                    Row({ space: AppSpace.Xs }) {
                      Text(entry.title).fontSize(AppFont.BodyL).layoutWeight(1)
                        .fontColor(AppTheme.TextPrimary).textAlign(TextAlign.Start)
                      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([AppTheme.TextTertiary])
                    }.width('100%')
                  }
                  .width('100%').constraintSize({ minHeight: 48 }).borderRadius(AppRadius.Md)
                  .padding(AppSpace.Sm).backgroundColor(AppTheme.Surface)
                  .enabled(!this.busy).onClick(() => this.openCategory(entry))
                } else {
                  Text(entry.title).fontSize(AppFont.Body).fontWeight(FontWeight.Medium)
                    .fontColor(AppTheme.TextSecondary).width('100%').padding({ top: AppSpace.Sm })
                }
              }
            }, (entry: LocalRuleControl): string => entry.id)
            if (this.errorMessage) {
              ListItem() {
                Text(this.errorMessage).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
                  .width('100%').copyOption(CopyOptions.LocalDevice)
              }
            }
            if (this.controls.length === 0 && this.entryCount === 0 && !this.errorMessage) {
              ListItem() {
                Text($r('app.string.rule_source_panel_empty')).fontSize(AppFont.Body)
                  .fontColor(AppTheme.TextSecondary).padding({ top: AppSpace.Lg })
              }
            }
            ListItem() { Column().height(this.safeBottom + AppSpace.Lg).width('100%') }
          }
          .width('100%').constraintSize({ maxWidth: 760 }).layoutWeight(1).scrollBar(BarState.Auto)
          .onAreaChange((_old: Area, area: Area) => { this.contentWidth = Number(area.width); })
          .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: AppSpace.Xs })
        }
      }
      .width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .onVisibleAreaChange([0], (visible: boolean) => {
        if (visible && this.refreshOnReturn && !this.busy) {
          this.refreshOnReturn = false;
          this.load(true, true);
        }
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }

  @Builder
  SettingsContent() {
    Column({ space: AppSpace.Xs }) {
      if (this.settingControls().length > 0) {
        Column({ space: AppSpace.Xs }) {
          Text($r('app.string.rule_source_settings_section')).fontSize(AppFont.Body).fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TextPrimary).width('100%')
          ForEach(this.settingControls(), (control: LocalRuleControl) => {
            this.ControlField(control)
          }, (control: LocalRuleControl): string => `${control.id}:${this.controlRevision}`)
        }.width('100%').padding(AppSpace.Sm).borderRadius(AppRadius.Lg).backgroundColor(AppTheme.Surface)
      }
      if (this.loginState.length > 0 || this.accountControls().length > 0) {
        Column({ space: AppSpace.Xs }) {
          Row({ space: AppSpace.Sm }) {
            Text($r('app.string.rule_source_account_section')).fontSize(AppFont.Body).fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TextPrimary).layoutWeight(1)
            Text(this.loginState === 'valid' ? $r('app.string.source_login_valid') :
              this.loginState === 'saved' ? $r('app.string.rule_source_session_saved') : $r('app.string.source_login_none'))
              .fontSize(AppFont.Body).fontColor(this.loginState === 'valid' ? AppColor.Brand : AppTheme.TextSecondary)
          }.width('100%')
          if (this.loginUser.length > 0) {
            Text(this.loginUser).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary).width('100%')
          }
          ForEach(this.accountFields(), (control: LocalRuleControl) => {
            this.ControlField(control)
          }, (control: LocalRuleControl): string => `${control.id}:${this.controlRevision}`)
          if (this.accountActions().length > 0) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.accountActions(), (control: LocalRuleControl) => {
                Button({ type: ButtonType.Normal }) {
                  Text(this.controlLabel(control)).fontSize(13).fontColor(AppColor.Brand)
                }.constraintSize({ minHeight: 32 }).padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: 6, bottom: 6 })
                  .borderRadius(AppRadius.Sm).backgroundColor(AppColor.BrandSoft)
                  .margin({ right: AppSpace.Xs, bottom: AppSpace.Xxs })
                  .enabled(!this.busy).onClick(() => this.runAction(control))
              }, (control: LocalRuleControl): string => `${control.id}:${this.controlRevision}`)
            }.width('100%')
          }
        }.width('100%').padding(AppSpace.Sm).borderRadius(AppRadius.Lg).backgroundColor(AppTheme.Surface)
      }
      if (this.actionControls().length > 0) {
        Column({ space: AppSpace.Xs }) {
          Text($r('app.string.rule_source_actions_section')).fontSize(AppFont.Body).fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TextPrimary).width('100%')
          GridRow({ columns: this.contentWidth >= AdaptiveLayout.MEDIUM_WIDTH ? 3 : 2,
            gutter: { x: AppSpace.Xs, y: AppSpace.Xs } }) {
            ForEach(this.actionControls(), (control: LocalRuleControl) => {
              GridCol() { this.ActionButton(control) }
            }, (control: LocalRuleControl): string => `${control.id}:${this.controlRevision}`)
          }.width('100%')
        }.width('100%').padding(AppSpace.Sm).borderRadius(AppRadius.Lg).backgroundColor(AppTheme.Surface)
      }
      if (this.errorMessage.length > 0 && this.controls.length === 0) {
        Button($r('app.string.common_retry')).fontColor(AppColor.Brand).backgroundColor(AppColor.BrandSoft)
          .enabled(!this.busy).onClick(() => this.load())
      }
    }.width('100%')
  }

  @Builder
  ActionButton(control: LocalRuleControl) {
    Button({ type: ButtonType.Normal }) {
      Text(this.controlLabel(control)).fontSize(13).fontColor(AppTheme.TextPrimary)
        .textAlign(TextAlign.Center).width('100%')
    }
    .width('100%').constraintSize({ minHeight: 36 }).padding(AppSpace.Xs)
    .borderRadius(AppRadius.Sm).backgroundColor($r('app.color.source_control_background'))
    .enabled(!this.busy).onClick(() => this.runAction(control))
  }

  @Builder
  ControlField(control: LocalRuleControl) {
    if (control.type === 'button') {
      this.ActionButton(control)
    } else {
      Row({ space: AppSpace.Xs }) {
        Row({ space: AppSpace.Xxs }) {
          Text(this.fieldTitle(control)).fontSize(13).fontColor(AppTheme.TextPrimary).layoutWeight(1)
          if (this.fieldTitle(control) !== control.title) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.info_circle')).fontSize(14).fontColor([AppTheme.TextTertiary])
            }.width(24).height(32).backgroundColor(Color.Transparent)
              .accessibilityText(control.title).onClick(() => this.showFieldHelp(control))
          }
        }.width(this.contentWidth >= 340 ? 104 : 88).alignItems(VerticalAlign.Center)
        Column() { this.ControlEditor(control) }.layoutWeight(1)
      }.width('100%').constraintSize({ minHeight: 36 }).alignItems(VerticalAlign.Center)
    }
  }

  private selectedLabel(control: LocalRuleControl): string {
    return this.optionLabels(control)[this.optionValues(control).indexOf(control.value)] ||
      control.value || this.optionLabels(control)[0] || control.title;
  }

  @Builder
  ControlEditor(control: LocalRuleControl) {
    Column() {
      if (control.type === 'select' || control.type === 'dynamic-select') {
        Select(this.selectOptions(control))
          .selected(this.optionValues(control).indexOf(control.value))
          .value(this.selectedLabel(control))
          .font({ size: 13, weight: FontWeight.Regular }).fontColor(AppTheme.TextPrimary)
          .textModifier(this.selectText)
          .optionFont({ size: 13, weight: FontWeight.Regular })
          .selectedOptionFont({ size: 13, weight: FontWeight.Regular })
          .selectedOptionFontColor(AppColor.Brand).showDefaultSelectedIcon(true)
          .optionTextModifier(this.optionText).selectedOptionTextModifier(this.optionText)
          .menuAlign(MenuAlignType.END).optionWidth(this.optionMenuWidth(control))
          .width('100%').constraintSize({ minHeight: 36 })
          .padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: 6, bottom: 6 })
          .borderRadius(AppRadius.Sm).backgroundColor($r('app.color.source_control_background'))
          .enabled(!this.busy)
          .onAppear(() => { this.loadSelectOptions(control); })
          .onClick(() => { this.loadSelectOptions(control); })
          .onSelect((index: number) => {
            const value = this.optionValues(control)[index];
            if (value !== undefined) this.changeValue(control, value, true);
          })
      } else if (control.type === 'toggle' || control.type === 'switch' || control.type === 'checkbox') {
        Toggle({ type: ToggleType.Switch, isOn: control.value === (control.options[1] ?? 'true') })
          .selectedColor(AppColor.Brand).enabled(!this.busy)
          .onChange((value: boolean) => {
            this.changeValue(control, value ? (control.options[1] ?? 'true') : (control.options[0] ?? 'false'), true);
          })
      } else if (control.type === 'button') {
        this.ActionButton(control)
      } else {
        TextInput({ text: control.value, placeholder: control.placeholder })
          .width('100%').height(36).fontSize(13).fontColor(AppTheme.TextPrimary)
          .type(control.type === 'password' ? InputType.Password : control.type === 'number' ? InputType.Number : InputType.Normal)
          .caretColor(AppColor.Brand).backgroundColor($r('app.color.source_control_background'))
          .borderRadius(AppRadius.Sm).enabled(!this.busy)
          .onChange((value: string) => { this.changeValue(control, value); })
      }
    }.width('100%')
  }
}
