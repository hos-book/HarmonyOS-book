import { ComicReaderAppearance } from '../model/ComicReaderAppearance';
import { ReaderSettingCard } from './ReaderSettingCard';
import { ImmersiveOptionTabs } from './ImmersiveOptionTabs';
import { AppFont } from '../theme/Theme';
import { ReaderEdgeTabs, ReaderMarginSlider } from './ReaderMarginControls';
import { SettingsHintButton } from './SettingsHintButton';

@ComponentV2
export struct ComicAppearanceSettings {
  @Param value: ComicReaderAppearance = new ComicReaderAppearance();
  @Event onChange: (value: ComicReaderAppearance) => void = () => {};
  @Local cropEdge: number = 0;
  @Local draft: ComicReaderAppearance = new ComicReaderAppearance();

  aboutToAppear(): void { this.syncValue(); }

  @Monitor('value')
  syncValue(): void { this.draft = ComicReaderAppearance.normalize(this.value); }

  private update(field: string, value: number): void {
    const next = ComicReaderAppearance.normalize(this.draft);
    if (field === 'split') next.split = value;
    if (field === 'light') next.lightBackground = value;
    if (field === 'dark') next.darkBackground = value;
    this.draft = next;
    this.onChange(next);
  }

  @Computed
  get cropLabel(): Resource {
    if (this.cropEdge === 0) return $r('app.string.reader_margin_top');
    if (this.cropEdge === 1) return $r('app.string.reader_margin_bottom');
    if (this.cropEdge === 2) return $r('app.string.reader_margin_left');
    return $r('app.string.reader_margin_right');
  }

  @Computed
  get cropValue(): number {
    if (this.cropEdge === 0) return this.draft.cropTop;
    if (this.cropEdge === 1) return this.draft.cropBottom;
    if (this.cropEdge === 2) return this.draft.cropLeft;
    return this.draft.cropRight;
  }

  private changeCrop(amount: number, commit: boolean): void {
    const next = ComicReaderAppearance.normalize(this.draft);
    if (this.cropEdge === 0) next.cropTop = amount;
    if (this.cropEdge === 1) next.cropBottom = amount;
    if (this.cropEdge === 2) next.cropLeft = amount;
    if (this.cropEdge === 3) next.cropRight = amount;
    this.draft = next;
    if (commit) this.onChange(next);
  }

  build() {
    Column({ space: 6 }) {
      ReaderSettingCard({ compact: true, inline: true, title: $r('app.string.comic_split_title'),
        description: $r('app.string.comic_split_hint') }) {
        ImmersiveOptionTabs({ labels: [$r('app.string.comic_split_off'), $r('app.string.comic_split_ltr'),
          $r('app.string.comic_split_rtl')], selected: this.draft.split,
          onSelect: (index: number): void => this.update('split', index) })
          .id('comic-split-mode')
      }
      ReaderSettingCard({ compact: true, showTitle: false }) {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Row({ space: 2 }) {
              Text($r('app.string.comic_custom_crop')).fontSize(AppFont.Body)
                .fontColor($r('sys.color.font_primary'))
              SettingsHintButton({ title: $r('app.string.comic_custom_crop'),
                message: $r('app.string.comic_custom_crop_hint') })
            }
            ReaderEdgeTabs({ selected: this.cropEdge, groupId: 'comic-crop-edge',
              onSelect: (index: number): void => { this.cropEdge = index; } }).layoutWeight(1)
          }.width('100%')
          ReaderMarginSlider({ label: this.cropLabel, value: this.cropValue, max: 25, unit: '%',
            idPrefix: 'comic-crop-percent',
            onChange: (amount: number, commit: boolean): void => this.changeCrop(amount, commit) })
        }.width('100%')
      }
      ReaderSettingCard({ compact: true, inline: true, title: $r('app.string.comic_background_light') }) {
        ImmersiveOptionTabs({ labels: [$r('app.string.comic_background_black'), $r('app.string.comic_background_plain'),
          $r('app.string.comic_background_kraft'), $r('app.string.comic_background_green')], selected: this.draft.lightBackground,
          onSelect: (index: number): void => this.update('light', index) })
          .id('comic-background-light')
      }
      ReaderSettingCard({ compact: true, inline: true, title: $r('app.string.comic_background_dark') }) {
        ImmersiveOptionTabs({ labels: [$r('app.string.comic_background_black'), $r('app.string.comic_background_plain'),
          $r('app.string.comic_background_kraft'), $r('app.string.comic_background_green')], selected: this.draft.darkBackground,
          onSelect: (index: number): void => this.update('dark', index) })
          .id('comic-background-dark')
      }
    }.width('100%')
  }
}
