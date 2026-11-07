import { SliderGestureModifier } from '../utils/SliderGestureModifier';
import { SpeechSynthesisSettings } from '../model/SpeechSynthesisSettings';
import { AppColor, AppTheme } from '../theme/Theme';
import { SettingsHintButton } from './SettingsHintButton';
import { ReaderSettingsSectionHeader } from './ReaderSettingCard';

/** 独立 V2 参数保持滑条和数值同步，避免 Builder 按值参数冻结显示。 */
@ComponentV2
struct SynthesisNumberSetting {
  @Param label: ResourceStr = '';
  @Param value: number = 0;
  @Param min: number = 0;
  @Param max: number = 1;
  @Param step: number = 1;
  @Event changed: (value: number) => void = (): void => {};

  build() {
    Row({ space: 8 }) {
      Text(this.label).fontSize(14).fontColor($r('sys.color.font_primary')).width('45%')
      Slider({ value: this.value, min: this.min, max: this.max, step: this.step })
        .attributeModifier(new SliderGestureModifier(this.min, this.max))
        .layoutWeight(1).height(40)
        .selectedColor(AppColor.Brand).blockColor(AppColor.Brand)
        .onChange((next: number): void => this.changed(Math.round(next)))
      Text(`${this.value}`).fontSize(14).fontColor(AppColor.Brand).width(32).textAlign(TextAlign.End)
    }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .borderRadius(16).backgroundColor(AppTheme.Surface)
      .border({ width: 0.5, color: AppTheme.Divider })
  }
}

@ComponentV2
export struct SpeechSynthesisSettingsPanel {
  @Param settings: SpeechSynthesisSettings = new SpeechSynthesisSettings();
  @Event onSave: (value: SpeechSynthesisSettings) => Promise<void> = async (): Promise<void> => {};
  @Local quickStart: boolean = false;
  @Local paragraphs: number = 1;
  @Local maxChars: number = 4000;
  @Local timeoutSeconds: number = 30;
  @Local retries: number = 2;
  @Local concurrency: number = 3;
  @Local filterSymbols: boolean = true;
  @Local replacements: string = '';
  @Local saving: boolean = false;
  @Local message: ResourceStr = '';

  aboutToAppear(): void {
    this.quickStart = this.settings.quickStart;
    this.paragraphs = this.settings.paragraphs;
    this.maxChars = this.settings.maxChars;
    this.timeoutSeconds = this.settings.timeoutSeconds;
    this.retries = this.settings.retries;
    this.concurrency = this.settings.concurrency;
    this.filterSymbols = this.settings.filterSymbols;
    this.replacements = this.settings.replacements;
  }

  private async save(): Promise<void> {
    if (this.saving) return;
    if (!SpeechSynthesisSettings.validRules(this.replacements)) {
      this.message = $r('app.string.tts_synthesis_rules_error'); return;
    }
    const value = new SpeechSynthesisSettings();
    value.quickStart = this.quickStart;
    value.paragraphs = this.paragraphs;
    value.maxChars = this.maxChars;
    value.timeoutSeconds = this.timeoutSeconds;
    value.retries = this.retries;
    value.concurrency = this.concurrency;
    value.filterSymbols = this.filterSymbols;
    value.replacements = this.replacements;
    this.saving = true;
    try { await this.onSave(value); this.message = $r('app.string.tts_synthesis_saved'); }
    catch (_error) { this.message = $r('app.string.tts_synthesis_save_error'); }
    finally { this.saving = false; }
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Row({ space: 2 }) {
          Text($r('app.string.tts_continuous_title')).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TextPrimary).flexShrink(1)
          SettingsHintButton({ title: $r('app.string.tts_continuous_title'), message: $r('app.string.tts_continuous_hint') })
            .id('tts-continuous-help')
          Blank()
          Button($r('app.string.tts_continuous_preset')).fontSize(14).fontColor(AppColor.Brand)
            .backgroundColor(Color.Transparent).id('tts-continuous-preset')
            .onClick((): void => {
              this.paragraphs = 3; this.maxChars = 500; this.concurrency = 3; this.quickStart = true; this.save();
            })
        }.width('100%')
        Row({ space: 8 }) {
          Text($r('app.string.tts_quick_start')).fontSize(14).fontColor(AppTheme.TextPrimary).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.quickStart }).selectedColor(AppColor.Brand)
            .onChange((value: boolean): void => { this.quickStart = value; }).id('tts-quick-start')
        }.width('100%')
      }.width('100%').padding(16).borderRadius(16).backgroundColor(AppTheme.Surface)
      Row({ space: 2 }) {
        Text($r('app.string.tts_synthesis_length_group')).fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TextSecondary)
        SettingsHintButton({ title: $r('app.string.tts_synthesis_title'), message: $r('app.string.tts_synthesis_hint') })
          .id('tts-synthesis-help')
      }.width('100%').padding({ left: 6 })
      SynthesisNumberSetting({ label: $r('app.string.tts_synthesis_paragraphs'), value: this.paragraphs,
        min: 1, max: 10, step: 1, changed: (value: number): void => { this.paragraphs = value; } })
      SynthesisNumberSetting({ label: $r('app.string.tts_synthesis_max_chars'), value: this.maxChars,
        min: 100, max: 4000, step: 100, changed: (value: number): void => { this.maxChars = value; } })
      ReaderSettingsSectionHeader({ title: $r('app.string.tts_synthesis_network_group') })
      SynthesisNumberSetting({ label: $r('app.string.tts_synthesis_concurrency'), value: this.concurrency,
        min: 1, max: 4, step: 1, changed: (value: number): void => { this.concurrency = value; } })
      SynthesisNumberSetting({ label: $r('app.string.tts_synthesis_timeout'), value: this.timeoutSeconds,
        min: 5, max: 120, step: 5, changed: (value: number): void => { this.timeoutSeconds = value; } })
      SynthesisNumberSetting({ label: $r('app.string.tts_synthesis_retries'), value: this.retries,
        min: 0, max: 3, step: 1, changed: (value: number): void => { this.retries = value; } })
      ReaderSettingsSectionHeader({ title: $r('app.string.tts_synthesis_text_group') })
      Row() {
        Text($r('app.string.tts_synthesis_filter')).fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.filterSymbols }).selectedColor(AppColor.Brand)
          .onChange((value: boolean): void => { this.filterSymbols = value; })
      }.width('100%').padding(16).borderRadius(16).backgroundColor(AppTheme.Surface)
        .border({ width: 0.5, color: AppTheme.Divider })
      Column({ space: 12 }) {
      Text($r('app.string.tts_synthesis_rules')).fontSize(14).fontColor($r('sys.color.font_primary')).width('100%')
      TextArea({ text: this.replacements, placeholder: $r('app.string.tts_synthesis_rules_hint') })
        .height(100).maxLength(4096).onChange((value: string): void => { this.replacements = value; })
      }.width('100%').padding(16).borderRadius(16).backgroundColor(AppTheme.Surface)
        .border({ width: 0.5, color: AppTheme.Divider })
      Button($r('app.string.tts_synthesis_apply')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
        .onClick((): void => { this.save(); }).id('tts-synthesis-save')
      if (this.message !== '') {
        Text(this.message).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
      }
    }.width('100%').enabled(!this.saving)
  }
}
