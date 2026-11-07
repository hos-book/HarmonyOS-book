import { SliderGestureModifier } from '../utils/SliderGestureModifier';
import { ReaderAutoPageService } from '../service/text/ReaderAutoPageService';
import { ReaderAutoScrollService } from '../service/text/ReaderAutoScrollService';
import { AppColor, AppFont } from '../theme/Theme';
import { ReaderSettingCard } from './ReaderSettingCard';
import { SettingsHintButton } from './SettingsHintButton';

@ComponentV2
export struct ReaderAutoPageSettings {
  @Param seconds: number = ReaderAutoPageService.DEFAULT_SECONDS;
  @Param scrolling: boolean = false;
  @Param comic: boolean = false;
  @Param speed: number = 20;
  @Param running: boolean = false;
  @Param paused: boolean = false;
  @Param available: boolean = true;
  @Param compact: boolean = false;
  @Event onInterval: (seconds: number) => void = (): void => {};
  @Event onSpeed: (speed: number) => void = (): void => {};
  @Event onToggle: () => void = (): void => {};
  @Local draft: number = ReaderAutoPageService.DEFAULT_SECONDS;

  aboutToAppear(): void { this.syncDraft(); }

  @Monitor('scrolling', 'seconds', 'speed')
  private syncDraft(): void { this.draft = this.scrolling ? this.speed : this.seconds; }

  private speedLabel(): Resource {
    if (!this.scrolling) return $r('app.string.reader_auto_page_interval', this.draft);
    if (this.comic) return $r('app.string.reader_auto_scroll_comic_speed', this.draft);
    return $r('app.string.reader_auto_scroll_speed', this.draft);
  }

  private toggleLabel(): Resource {
    if (this.paused) return $r('app.string.reader_auto_page_resume');
    if (!this.running) return $r('app.string.reader_auto_page_start');
    return $r('app.string.reader_auto_page_pause');
  }

  build() {
    ReaderSettingCard({ compact: this.compact, showTitle: false }) {
      Row({ space: 4 }) {
        Text(this.scrolling ? $r('app.string.reader_auto_scroll_title') : $r('app.string.reader_auto_page_title'))
          .fontSize(AppFont.Body).fontColor($r('sys.color.font_primary')).maxLines(1)
        SettingsHintButton({
          title: this.scrolling ? $r('app.string.reader_auto_scroll_title') : $r('app.string.reader_auto_page_title'),
          message: this.scrolling ? $r('app.string.reader_auto_scroll_hint') : $r('app.string.reader_auto_page_hint') })
        Slider({ value: this.draft, min: this.scrolling ? 6 : 3, max: this.scrolling && !this.comic ? 100 : 120,
          step: this.scrolling ? 2 : 1 })
          .attributeModifier(new SliderGestureModifier(this.scrolling ? 6 : 3, this.scrolling && !this.comic ? 100 : 120))
          .layoutWeight(1).height(40)
          .selectedColor(AppColor.Brand).blockColor(AppColor.Brand)
          .accessibilityText(this.speedLabel()).id('reader-auto-page-interval')
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.draft = this.scrolling ? ReaderAutoScrollService.normalizeSpeed(value, this.comic) :
              ReaderAutoPageService.normalizeSeconds(value);
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              if (this.scrolling) this.onSpeed(this.draft);
              else this.onInterval(this.draft);
            }
          })
        Text(this.scrolling ? `${this.draft}` : $r('app.string.reader_auto_page_seconds_short', this.draft))
          .fontSize(AppFont.Caption).fontColor($r('sys.color.font_primary')).width(38).textAlign(TextAlign.End)
        Button(this.toggleLabel()).height(36).padding({ left: 10, right: 10 }).fontSize(AppFont.Body)
          .fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
          .enabled(this.available || this.running).id('reader-auto-page-start')
          .onClick((): void => this.onToggle())
      }.width('100%').alignItems(VerticalAlign.Center)
    }
  }
}
