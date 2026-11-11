import { ReaderRegionStyle } from '../model/ReaderRegionStyle';
import { AppFont } from '../theme/Theme';
import { ReaderSettingCard } from './ReaderSettingCard';
import { ReaderMarginSlider, ReaderEdgeTabs } from './ReaderMarginControls';

@ComponentV2
export struct ReaderRegionStyleEditor {
  @Param title: ResourceStr = '';
  @Param groupId: string = '';
  @Param framed: boolean = true;
  @Param showTitle: boolean = true;
  @Param value: ReaderRegionStyle = new ReaderRegionStyle();
  @Event onChange: (value: ReaderRegionStyle) => void = () => {};
  @Local edge: number = 0;
  @Local draft: ReaderRegionStyle = new ReaderRegionStyle();

  aboutToAppear(): void { this.syncValue(); }

  @Monitor('value')
  syncValue(): void { this.draft = ReaderRegionStyle.normalize(this.value); }

  private change(amount: number, commit: boolean): void {
    const next = ReaderRegionStyle.normalize(this.draft);
    if (this.edge === 0) next.top = amount;
    if (this.edge === 1) next.bottom = amount;
    if (this.edge === 2) next.left = amount;
    if (this.edge === 3) next.right = amount;
    this.draft = next;
    if (commit) this.onChange(next);
  }

  @Computed
  get edgeLabel(): Resource {
    if (this.edge === 0) return $r('app.string.reader_margin_top');
    if (this.edge === 1) return $r('app.string.reader_margin_bottom');
    if (this.edge === 2) return $r('app.string.reader_margin_left');
    return $r('app.string.reader_margin_right');
  }

  @Computed
  get edgeValue(): number {
    if (this.edge === 0) return this.draft.top;
    if (this.edge === 1) return this.draft.bottom;
    if (this.edge === 2) return this.draft.left;
    return this.draft.right;
  }

  @LocalBuilder
  private styleControls() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        if (this.showTitle) {
          Text(this.title).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
        }
        ReaderEdgeTabs({ selected: this.edge, groupId: this.groupId,
          onSelect: (index: number): void => { this.edge = index; } }).layoutWeight(1)
      }.width('100%')
      ReaderMarginSlider({ label: this.edgeLabel, value: this.edgeValue, idPrefix: this.groupId,
        onChange: (value: number, commit: boolean): void => this.change(value, commit) })
      TextInput({ text: this.value.color, placeholder: $r('app.string.reader_region_color_hint') })
        .maxLength(7).onChange((color: string): void => {
          if (color === '' || /^#[0-9a-fA-F]{6}$/.test(color)) {
            const next = ReaderRegionStyle.normalize(this.value);
            next.color = color;
            this.onChange(next);
          }
        })
    }.width('100%')
  }

  build() {
    if (this.framed) {
      ReaderSettingCard({ compact: true, showTitle: false }) {
        this.styleControls()
      }
    } else {
      this.styleControls()
    }
  }
}
