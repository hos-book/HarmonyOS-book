import { Book } from '../model/Book';
import { AppColor, AppTheme } from '../theme/Theme';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';
import { WindowUtils } from '../utils/WindowUtils';
import { CoverImage } from './CoverImage';
import { ImmersiveCircleButton } from './ImmersiveCircleButton';

/** 只选择未分组书籍；持久化由书架已有流程完成。 */
@ComponentV2
export struct ShelfCollectionBookPicker {
  @Param group: string = '';
  @Param books: Book[] = [];
  @Event onConfirm: (ids: string[]) => Promise<void> = async (): Promise<void> => {};
  @Event onClose: () => void = () => {};
  @Local selectedIds: Set<string> = new Set();
  @Local keyword: string = '';
  @Local saving: boolean = false;
  @Local failed: boolean = false;
  @Local resultCount: number = 0;
  private data: HomeRecommendationDataSource<Book> = new HomeRecommendationDataSource<Book>();

  aboutToAppear(): void { this.refreshBooks(); }

  @Monitor('books', 'keyword')
  private refreshBooks(): void {
    const available = new Set(this.books.map((book: Book): string => book.id));
    this.selectedIds = new Set(Array.from(this.selectedIds).filter((id: string): boolean => available.has(id)));
    const books = this.filteredBooks();
    this.resultCount = books.length;
    this.data.setItems(books);
  }

  private filteredBooks(): Book[] {
    const query = this.keyword.trim().toLocaleLowerCase();
    return this.books.filter((book: Book): boolean => !query ||
      [book.title, book.author].some((value: string): boolean => (value || '').toLocaleLowerCase().includes(query)));
  }

  private toggle(id: string): void {
    if (this.saving) return;
    const next = new Set(this.selectedIds);
    if (next.has(id)) next.delete(id); else next.add(id);
    this.selectedIds = next;
    this.failed = false;
  }

  private allSelected(): boolean {
    const books = this.filteredBooks();
    return books.length > 0 && books.every((book: Book): boolean => this.selectedIds.has(book.id));
  }

  private toggleAll(): void {
    if (this.saving) return;
    const remove = this.allSelected();
    const next = new Set(this.selectedIds);
    for (const book of this.filteredBooks()) {
      if (remove) next.delete(book.id); else next.add(book.id);
    }
    this.selectedIds = next;
    this.failed = false;
  }

  private async save(): Promise<void> {
    if (this.saving || this.selectedIds.size === 0) return;
    this.saving = true;
    this.failed = false;
    try { await this.onConfirm(Array.from(this.selectedIds)); }
    catch (_error) { this.failed = true; }
    finally { this.saving = false; }
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text($r('app.string.collection_add_books')).fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TextPrimary).layoutWeight(1)
        Button({ type: ButtonType.Capsule }) {
          if (this.saving) {
            LoadingProgress().color(AppColor.Brand).width(18).height(18)
          } else {
            Text($r('app.string.collection_add_books_confirm')).fontSize(12).fontColor(AppColor.Brand)
          }
        }.height(30).padding({ left: 12, right: 12 }).backgroundColor(AppColor.BrandSoft)
          .enabled(!this.saving && this.selectedIds.size > 0)
          .onClick((): void => { this.save(); }).id('shelf-collection-picker-confirm')
        ImmersiveCircleButton({ icon: $r('sys.symbol.xmark'), label: $r('app.string.common_close'),
          diameter: 30, iconSize: 16, useMaterial: false,
          onPress: (): void => { if (!this.saving) this.onClose(); } })
          .enabled(!this.saving).id('shelf-collection-picker-close')
      }.width('100%').height(36)
      Text($r('app.string.collection_add_books_hint', this.group)).fontSize(12).fontColor(AppTheme.TextSecondary)
        .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Search({ value: this.keyword, placeholder: $r('app.string.collection_add_books_search') })
        .height(36).fontColor(AppTheme.TextPrimary).enabled(!this.saving)
        .onChange((value: string): void => { this.keyword = value; })
      Row() {
        Text($r('app.string.shelf_selected_count', this.selectedIds.size)).fontSize(12)
          .fontColor(AppTheme.TextSecondary).layoutWeight(1)
        Text(this.allSelected() ? $r('app.string.collection_clear_selection') : $r('app.string.collection_select_all'))
          .fontSize(12).fontColor(AppColor.Brand).height(28).enabled(!this.saving && this.resultCount > 0)
          .onClick((): void => this.toggleAll()).id('shelf-collection-picker-select-all')
          .accessibilityRole(AccessibilityRoleType.BUTTON)
      }.width('100%')
      if (this.failed) {
        Text($r('app.string.collection_add_books_failed')).fontSize(12).fontColor(AppTheme.TextSecondary).width('100%')
      }
      List({ space: 8 }) {
        if (this.resultCount === 0) {
          ListItem() {
            Text(this.books.length === 0 ? $r('app.string.collection_add_books_empty') :
              $r('app.string.collection_add_books_no_results')).fontSize(14).fontColor(AppTheme.TextSecondary)
              .width('100%').textAlign(TextAlign.Center).padding({ top: 36, bottom: 36 })
          }
        }
        LazyForEach(this.data, (book: Book) => {
          ListItem() {
            Row({ space: 12 }) {
              CoverImage({ url: book.cover, title: book.title, author: book.author,
                localPlaceholder: book.id.startsWith('import_'), themedDecoration: false, themeBundleId: 'default',
                imgWidth: 38, imgHeight: 54, useFixedHeight: true, radius: 4 }).hitTestBehavior(HitTestMode.None)
              Column({ space: 6 }) {
                Text(book.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(book.author).fontSize(11).fontColor(AppTheme.TextSecondary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Stack({ alignContent: Alignment.Center }) {
                if (this.selectedIds.has(book.id)) {
                  SymbolGlyph($r('sys.symbol.checkmark')).fontSize(12).fontColor([Color.White])
                }
              }.width(22).height(22).borderRadius(11)
                .backgroundColor(this.selectedIds.has(book.id) ? AppColor.Brand : Color.Transparent)
                .border({ width: 1, color: this.selectedIds.has(book.id) ? AppColor.Brand : AppColor.Divider })
            }.width('100%').padding(10).borderRadius(14)
              .backgroundColor(this.selectedIds.has(book.id) ? AppColor.BrandSoft : AppTheme.Surface)
              .enabled(!this.saving).onClick((): void => this.toggle(book.id))
              .accessibilityGroup(true).accessibilityRole(AccessibilityRoleType.CHECKBOX)
              .accessibilityChecked(this.selectedIds.has(book.id))
              .id('shelf-collection-picker-book-' + book.id)
          }
        }, (book: Book): string => book.id)
      }.layoutWeight(1).width('100%').cachedCount(4).scrollBar(BarState.Auto)
        .contentEndOffset(Math.max(20, WindowUtils.getBottomSafeVp()))
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 12 })
  }
}
