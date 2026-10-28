import { SpeechSynthesisSettings } from '../model/SpeechSynthesisSettings';
import { AppColor } from '../theme/Theme';

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

  @Builder
  numberSetting(label: ResourceStr, value: number, min: number, max: number, step: number,
    changed: (value: number) => void) {
    Column({ space: 4 }) {
      Row() {
        Text(label).fontSize(14).fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Text(`${value}`).fontSize(14).fontColor(AppColor.Brand)
      }.width('100%')
      Slider({ value: value, min: min, max: max, step: step })
        .selectedColor(AppColor.Brand).blockColor(AppColor.Brand)
        .onChange((next: number): void => changed(Math.round(next)))
    }.width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Text($r('app.string.tts_synthesis_hint')).fontSize(12).fontColor($r('sys.color.font_secondary')).width('100%')
      this.numberSetting($r('app.string.tts_synthesis_paragraphs'), this.paragraphs, 1, 10, 1,
        (value: number): void => { this.paragraphs = value; })
      this.numberSetting($r('app.string.tts_synthesis_max_chars'), this.maxChars, 100, 4000, 100,
        (value: number): void => { this.maxChars = value; })
      this.numberSetting($r('app.string.tts_synthesis_timeout'), this.timeoutSeconds, 5, 120, 5,
        (value: number): void => { this.timeoutSeconds = value; })
      this.numberSetting($r('app.string.tts_synthesis_retries'), this.retries, 0, 3, 1,
        (value: number): void => { this.retries = value; })
      this.numberSetting($r('app.string.tts_synthesis_concurrency'), this.concurrency, 1, 4, 1,
        (value: number): void => { this.concurrency = value; })
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
