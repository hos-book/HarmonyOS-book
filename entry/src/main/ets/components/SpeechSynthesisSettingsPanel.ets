import { SpeechSynthesisSettings } from '../model/SpeechSynthesisSettings';
import { AppColor } from '../theme/Theme';

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
    Column({ space: 4 }) {
      Row() {
        Text(this.label).fontSize(14).fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Text(`${this.value}`).fontSize(14).fontColor(AppColor.Brand)
      }.width('100%')
      Slider({ value: this.value, min: this.min, max: this.max, step: this.step })
        .selectedColor(AppColor.Brand).blockColor(AppColor.Brand)
        .onChange((next: number): void => this.changed(Math.round(next)))
    }.width('100%')
  }
}

@ComponentV2
export struct SpeechSynthesisSettingsPanel {
  @Param settings: SpeechSynthesisSettings = new SpeechSynthesisSettings();
  @Event onSave: (value: SpeechSynthesisSettings) => Promise<void> = async (): Promise<void> => {};
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
      Text($r('app.string.tts_synthesis_hint')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
      SynthesisNumberSetting({ label: $r('app.string.tts_synthesis_paragraphs'), value: this.paragraphs,
        min: 1, max: 10, step: 1, changed: (value: number): void => { this.paragraphs = value; } })
      SynthesisNumberSetting({ label: $r('app.string.tts_synthesis_max_chars'), value: this.maxChars,
        min: 100, max: 4000, step: 100, changed: (value: number): void => { this.maxChars = value; } })
      SynthesisNumberSetting({ label: $r('app.string.tts_synthesis_timeout'), value: this.timeoutSeconds,
        min: 5, max: 120, step: 5, changed: (value: number): void => { this.timeoutSeconds = value; } })
      SynthesisNumberSetting({ label: $r('app.string.tts_synthesis_retries'), value: this.retries,
        min: 0, max: 3, step: 1, changed: (value: number): void => { this.retries = value; } })
      SynthesisNumberSetting({ label: $r('app.string.tts_synthesis_concurrency'), value: this.concurrency,
        min: 1, max: 4, step: 1, changed: (value: number): void => { this.concurrency = value; } })
      Row() {
        Text($r('app.string.tts_synthesis_filter')).fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.filterSymbols }).selectedColor(AppColor.Brand)
          .onChange((value: boolean): void => { this.filterSymbols = value; })
      }.width('100%')
      Text($r('app.string.tts_synthesis_rules')).fontSize(14).fontColor($r('sys.color.font_primary')).width('100%')
      TextArea({ text: this.replacements, placeholder: $r('app.string.tts_synthesis_rules_hint') })
        .height(100).maxLength(4096).onChange((value: string): void => { this.replacements = value; })
      Button($r('app.string.tts_synthesis_apply')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
        .onClick((): void => { this.save(); }).id('tts-synthesis-save')
      if (this.message !== '') {
        Text(this.message).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
      }
    }.width('100%').enabled(!this.saving)
  }
}
