import { ReaderBookmark } from '../model/ReaderTools';
import { ListDataSource } from '../utils/ListDataSource';

@ComponentV2
export struct ReaderBookmarkSheet {
  @Param bookmarks: ReaderBookmark[] = [];
  @Event onJump: (mark: ReaderBookmark) => void = (): void => {};
  @Event onDelete: (mark: ReaderBookmark) => Promise<void> = async (): Promise<void> => {};
  @Local busy: boolean = false;
  @Local failed: boolean = false;
  private data: ListDataSource<ReaderBookmark> = new ListDataSource<ReaderBookmark>();
  aboutToAppear(): void { this.updateData(); }
  @Monitor('bookmarks')
  private updateData(): void { this.data.setItems(this.bookmarks); }

  private async remove(mark: ReaderBookmark): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.failed = false;
    try { await this.onDelete(mark); }
    catch (_error) { this.failed = true; }
    finally { this.busy = false; }
  }

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.reader_bookmarks')).fontSize(22).fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary')).width('100%')
      if (this.failed) {
        Text($r('app.string.reader_tools_storage_error')).fontColor($r('sys.color.ohos_id_color_warning'))
      }
      if (this.bookmarks.length === 0) {
        Text($r('app.string.reader_bookmarks_empty')).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
      } else {
        List({ space: 12 }) {
          LazyForEach(this.data, (mark: ReaderBookmark) => {
            ListItem() {
              Row({ space: 12 }) {
                Column({ space: 8 }) {
                  Text(mark.chapterTitle).fontSize(17).fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_primary')).maxLines(2).width('100%')
                  Text(mark.preview || $r('app.string.reader_bookmark_position', mark.resourceIndex + 1))
                    .fontSize(14).fontColor($r('sys.color.font_secondary')).maxLines(3).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick((): void => this.onJump(mark))
                Button() { SymbolGlyph($r('sys.symbol.trash')).fontSize(20).fontColor([$r('sys.color.font_primary')]) }
                  .backgroundColor(Color.Transparent).width(44).height(44).enabled(!this.busy)
                  .accessibilityText($r('app.string.common_delete')).onClick((): void => { this.remove(mark); })
              }.width('100%').padding({ top: 12, bottom: 12 })
            }
          }, (mark: ReaderBookmark): string => mark.id)
        }.layoutWeight(1).width('100%').divider({ strokeWidth: 0.5, color: $r('sys.color.comp_divider') })
      }
    }.width('100%').height('100%').padding({ left: 24, right: 24, top: 20, bottom: 28 })
  }
}
