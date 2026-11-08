import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { SettingsHintButton } from '../components/SettingsHintButton';
import { GeneralSettings } from '../model/GeneralSettings';
import { PreferenceService } from '../service/PreferenceService';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct JianjianSettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Local companionEnabled: boolean = false;
  @Local nightCareEnabled: boolean = true;
  @Local ready: boolean = false;
  @Local failed: boolean = false;
  @Local saving: boolean = false;
  private alive: boolean = false;
  private loadSerial: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.loadSerial++;
  }

  private async load(): Promise<void> {
    const serial = ++this.loadSerial;
    this.ready = false;
    this.failed = false;
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) throw new Error('Settings context unavailable');
      await PreferenceService.init(context);
      if (!this.alive || serial !== this.loadSerial) return;
      this.companionEnabled = GeneralSettings.current.jianjianCompanionEnabled;
      this.nightCareEnabled = GeneralSettings.current.jianjianNightCareEnabled;
      this.ready = true;
    } catch (_error) {
      if (this.alive && serial === this.loadSerial) this.failed = true;
    }
  }

  private async saveToggle(companion: boolean, value: boolean): Promise<void> {
    if (!this.ready || this.saving) return;
    const previous = companion ? this.companionEnabled : this.nightCareEnabled;
    if (previous === value) return;
    this.saving = true;
    if (companion) this.companionEnabled = value;
    else this.nightCareEnabled = value;
    try {
      if (companion) await PreferenceService.setJianjianCompanionEnabled(value);
      else await PreferenceService.setJianjianNightCareEnabled(value);
    } catch (_error) {
      if (this.alive) {
        if (companion) this.companionEnabled = previous;
        else this.nightCareEnabled = previous;
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
      }
    } finally {
      if (this.alive) this.saving = false;
    }
  }

  @Builder
  private routeRow(title: Resource, route: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Text(title).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary).layoutWeight(1)
          .textAlign(TextAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(20).fontColor([AppTheme.TextTertiary])
      }.width('100%').padding(16)
    }.width('100%').constraintSize({ minHeight: 60 }).backgroundColor(Color.Transparent)
      .borderRadius(AppRadius.Md).onClick((): void => { this.navStack.pushPathByName(route, ''); })
      .id(`jianjian-settings-${route}`).accessibilityText(title)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: 18 }) {
          if (!this.ready) {
            Row({ space: 10 }) {
              if (!this.failed) { LoadingProgress().color(AppColor.Brand).width(24).height(24) }
              Text(this.failed ? $r('app.string.settings_load_failed') : $r('app.string.settings_loading'))
                .fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary).layoutWeight(1)
              if (this.failed) {
                Button($r('app.string.common_retry')).backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
                  .onClick((): void => { this.load(); })
              }
            }.width('100%')
          }
          Column() {
            JianjianSettingToggle({ title: $r('app.string.settings_jianjian_companion'),
              hint: $r('app.string.settings_jianjian_companion_desc'), value: this.companionEnabled,
              interactive: this.ready && !this.saving, controlId: 'jianjian-companion-toggle',
              onToggle: (value: boolean): void => { this.saveToggle(true, value); } })
            Divider().color(AppTheme.Divider).strokeWidth(0.5).margin({ left: 16, right: 16 })
            JianjianSettingToggle({ title: $r('app.string.jianjian_night_care'),
              hint: $r('app.string.jianjian_night_care_desc'), value: this.nightCareEnabled,
              interactive: this.ready && !this.saving, controlId: 'jianjian-night-care-toggle',
              onToggle: (value: boolean): void => { this.saveToggle(false, value); } })
          }.width('100%').backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg)
          Column() {
            this.routeRow($r('app.string.jianjian_ai_settings'), 'jianjianAiSettings')
            Divider().color(AppTheme.Divider).strokeWidth(0.5).margin({ left: 16, right: 16 })
            this.routeRow($r('app.string.jianjian_prompt_settings'), 'jianjianPromptSettings')
            Divider().color(AppTheme.Divider).strokeWidth(0.5).margin({ left: 16, right: 16 })
            this.routeRow($r('app.string.jianjian_open_chat'), 'jianjianChat')
          }.width('100%').backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg)
        }.width('100%').constraintSize({ maxWidth: 760 })
          .padding({ left: 16, right: 16, top: this.headerHeight + 12,
            bottom: WindowUtils.getBottomSafeVp() + 24 })
      }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text($r('app.string.jianjian_settings_title')).fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
          SettingsHintButton({ title: $r('app.string.jianjian_settings_title'),
            message: $r('app.string.jianjian_settings_desc') })
        }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

@ComponentV2
struct JianjianSettingToggle {
  @Param title: Resource = $r('app.string.jianjian_settings_title');
  @Param hint: Resource = $r('app.string.jianjian_settings_desc');
  @Param value: boolean = false;
  @Param interactive: boolean = true;
  @Param controlId: string = '';
  @Event onToggle: (value: boolean) => void = (_value: boolean): void => {};

  build() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Row({ space: 2 }) {
          Text(this.title).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary).flexShrink(1)
          SettingsHintButton({ title: this.title, message: this.hint })
        }.width('100%')
        Text($r('app.string.settings_limited_trial')).fontSize(AppFont.Caption).fontColor(AppColor.Brand)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.value }).selectedColor(AppColor.Brand)
        .enabled(this.interactive).onChange((value: boolean): void => this.onToggle(value))
        .id(this.controlId).accessibilityText(this.title)
    }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 }).constraintSize({ minHeight: 72 })
  }
}
