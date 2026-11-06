import { ReaderColorPalette } from '../components/ReaderColorPalette';
import { TextReadingSettings } from '../model/TextReading';
import { ReaderPalette } from '../model/ReaderTheme';
import { TextReadingSettingsService } from '../service/text/TextReadingSettingsService';
import { AppColor, AppFont, AppTheme } from '../theme/Theme';
import { resolveReaderAccent } from '../theme/ReaderAccentColor';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct SpeechDisplaySettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local ready: boolean = false;
  @Local failed: boolean = false;
  @Local saving: boolean = false;
  @Local follow: boolean = true;
  @Local mark: string = 'color';
  @Local color: string = '';
  @Local colorFollowTheme: boolean = true;
  @Local preview: string = new ReaderPalette().accent;
  @Local themeColor: string = new ReaderPalette().accent;
  @Local revision: number = 0;
  private readonly readerColorListener = (): void => this.refreshThemeColor();

  @Computed
  get themeAccent(): ResourceStr { return AppColor.Brand; }

  @Monitor('themeAccent')
  refreshThemeColor(): void {
    this.themeColor = resolveReaderAccent(this.getUIContext().getHostContext(), this.themeAccent);
    if (this.colorFollowTheme) {
      this.preview = this.themeColor;
      this.revision++;
    }
  }

  aboutToAppear(): void {
    WindowUtils.addReaderColorListener(this.readerColorListener);
    this.load();
  }

  aboutToDisappear(): void { WindowUtils.removeReaderColorListener(this.readerColorListener); }

  private async load(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    this.failed = false;
    try {
      const settings = await TextReadingSettingsService.get(context);
      this.follow = settings.speechFollowPage;
      this.mark = settings.speechMark;
      this.color = settings.speechMarkColor;
      this.colorFollowTheme = this.color.length === 0;
      this.refreshThemeColor();
      this.preview = this.color || this.themeColor;
      this.ready = true;
    } catch (_error) { this.failed = true; }
  }

  private async save(follow: boolean, mark: string, color: string,
    followTheme: boolean = color.length === 0): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.ready || this.saving) return;
    this.saving = true;
    this.colorFollowTheme = followTheme;
    try {
      const settings = await TextReadingSettingsService.get(context);
      settings.speechFollowPage = follow;
      settings.speechMark = TextReadingSettings.normalizeSpeechMark(mark);
      const normalizedColor = TextReadingSettings.normalizeSpeechMarkColor(color);
      settings.speechMarkColor = followTheme ? '' : (normalizedColor || this.themeColor);
      await TextReadingSettingsService.save(context, settings);
      this.follow = settings.speechFollowPage;
      this.mark = settings.speechMark;
      this.color = settings.speechMarkColor;
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reading_settings_save_error') });
    } finally {
      this.colorFollowTheme = this.color.length === 0;
      this.preview = this.color || this.themeColor;
      this.revision++;
      this.saving = false;
    }
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
        }.width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
        Text($r('app.string.reader_speech_display')).fontSize(AppFont.Title)
          .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
      }.width('100%').padding({ left: 8, right: 16, top: WindowUtils.getStatusBarHeightVp() + 8, bottom: 8 })
      if (this.ready) {
        Scroll() {
          Column({ space: 12 }) {
            Column({ space: 8 }) {
              Row({ space: 12 }) {
                Text($r('app.string.reader_speech_follow_page')).fontSize(AppFont.BodyL)
                  .fontColor(AppTheme.TextPrimary).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.follow }).selectedColor(AppColor.Brand)
                  .onChange((value: boolean): void => { this.save(value, this.mark, this.color); })
                  .id('reader-speech-follow-page')
              }.width('100%')
              Text($r('app.string.reader_speech_follow_page_hint')).fontSize(AppFont.Caption)
                .fontColor(AppTheme.TextSecondary).width('100%')
            }.width('100%').padding(18).borderRadius(18).backgroundColor(AppTheme.Surface)
              .border({ width: 0.5, color: AppTheme.Divider })
            Column({ space: 12 }) {
              Text($r('app.string.reader_speech_mark')).fontSize(AppFont.BodyL)
                .fontColor(AppTheme.TextPrimary).width('100%')
              Row({ space: 6 }) {
                ForEach(['color', 'highlight', 'underline'], (mark: string) => {
                  Button(mark === 'color' ? $r('app.string.reader_mark_color') : mark === 'highlight' ?
                    $r('app.string.reader_mark_highlight') : $r('app.string.reader_mark_underline'))
                    .layoutWeight(1).fontSize(14).fontColor(this.mark === mark ? AppColor.Brand : AppTheme.TextPrimary)
                    .backgroundColor(AppTheme.SettingsBackground).accessibilitySelected(this.mark === mark)
                    .onClick((): void => { this.save(this.follow, mark, this.color); })
                }, (mark: string): string => mark)
              }.width('100%')
            }.width('100%').padding(18).borderRadius(18).backgroundColor(AppTheme.Surface)
              .border({ width: 0.5, color: AppTheme.Divider })
            if (this.mark === 'color') {
              Column({ space: 12 }) {
                Row({ space: 8 }) {
                  Text($r('app.string.reader_speech_color')).fontSize(AppFont.BodyL)
                    .fontColor(AppTheme.TextPrimary).layoutWeight(1)
                  Row({ space: 8 }) {
                    Text($r('app.string.reader_dialogue_color_auto')).fontSize(AppFont.Caption)
                      .fontColor(AppTheme.TextSecondary)
                    Toggle({ type: ToggleType.Switch, isOn: this.colorFollowTheme }).selectedColor(AppColor.Brand)
                      .accessibilityText($r('app.string.reader_dialogue_color_auto'))
                      .onChange((followTheme: boolean): void => {
                        const color = followTheme ? '' : (this.color || this.preview);
                        this.save(this.follow, this.mark, color, followTheme);
                      })
                      .id('reader-speech-color-follow-theme')
                  }
                }.width('100%')
                ReaderColorPalette({ color: this.preview, resetRevision: this.revision,
                  onChange: (color: string, commit: boolean): void => {
                    this.preview = color;
                    if (commit) this.save(this.follow, this.mark, color, false);
                  } }).id('reader-speech-color')
              }.width('100%').padding(18).borderRadius(18).backgroundColor(AppTheme.Surface)
                .border({ width: 0.5, color: AppTheme.Divider })
            }
          }.width('100%').constraintSize({ maxWidth: 760 }).padding(16).enabled(!this.saving)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      } else if (this.failed) {
        Text($r('app.string.reading_settings_load_error')).fontColor(AppTheme.TextSecondary).padding(20)
        Button($r('app.string.common_retry')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
          .onClick((): void => { this.load(); })
      } else { LoadingProgress().width(32).height(32).color(AppColor.Brand) }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .padding({ bottom: WindowUtils.getBottomSafeVp() })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
