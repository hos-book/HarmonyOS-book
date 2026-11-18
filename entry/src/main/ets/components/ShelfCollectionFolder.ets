import { Book } from '../model/Book';
import { BookPresentation } from '../model/BookPresentation';
import { ShelfCollectionGroup } from '../model/ShelfCollection';
import { CoverImage } from './CoverImage';

// Custom palette slots first, followed by All Books and Ungrouped.
const SHELF_FOLDER_PALETTES: Resource[][] = [
  [$r('app.color.collection_sage_back'), $r('app.color.collection_sage_top'),
    $r('app.color.collection_sage_front'), $r('app.color.collection_sage_ink')],
  [$r('app.color.collection_blue_back'), $r('app.color.collection_blue_top'),
    $r('app.color.collection_blue_front'), $r('app.color.collection_blue_ink')],
  [$r('app.color.collection_sand_back'), $r('app.color.collection_sand_top'),
    $r('app.color.collection_sand_front'), $r('app.color.collection_sand_ink')],
  [$r('app.color.collection_rose_back'), $r('app.color.collection_rose_top'),
    $r('app.color.collection_rose_front'), $r('app.color.collection_rose_ink')],
  [$r('app.color.collection_lilac_back'), $r('app.color.collection_lilac_top'),
    $r('app.color.collection_lilac_front'), $r('app.color.collection_lilac_ink')],
  [$r('app.color.collection_teal_back'), $r('app.color.collection_teal_top'),
    $r('app.color.collection_teal_front'), $r('app.color.collection_teal_ink')],
  [$r('app.color.collection_clay_back'), $r('app.color.collection_clay_top'),
    $r('app.color.collection_clay_front'), $r('app.color.collection_clay_ink')],
  [$r('app.color.collection_indigo_back'), $r('app.color.collection_indigo_top'),
    $r('app.color.collection_indigo_front'), $r('app.color.collection_indigo_ink')],
  [$r('app.color.collection_olive_back'), $r('app.color.collection_olive_top'),
    $r('app.color.collection_olive_front'), $r('app.color.collection_olive_ink')],
  [$r('app.color.collection_mauve_back'), $r('app.color.collection_mauve_top'),
    $r('app.color.collection_mauve_front'), $r('app.color.collection_mauve_ink')],
  [$r('app.color.collection_mint_back'), $r('app.color.collection_mint_top'),
    $r('app.color.collection_mint_front'), $r('app.color.collection_mint_ink')],
  [$r('app.color.collection_copper_back'), $r('app.color.collection_copper_top'),
    $r('app.color.collection_copper_front'), $r('app.color.collection_copper_ink')],
  [$r('app.color.collection_ice_back'), $r('app.color.collection_ice_top'),
    $r('app.color.collection_ice_front'), $r('app.color.collection_ice_ink')],
  [$r('app.color.collection_wine_back'), $r('app.color.collection_wine_top'),
    $r('app.color.collection_wine_front'), $r('app.color.collection_wine_ink')],
  [$r('app.color.collection_denim_back'), $r('app.color.collection_denim_top'),
    $r('app.color.collection_denim_front'), $r('app.color.collection_denim_ink')],
  [$r('app.color.collection_apricot_back'), $r('app.color.collection_apricot_top'),
    $r('app.color.collection_apricot_front'), $r('app.color.collection_apricot_ink')],
  [$r('app.color.collection_fern_back'), $r('app.color.collection_fern_top'),
    $r('app.color.collection_fern_front'), $r('app.color.collection_fern_ink')],
  [$r('app.color.collection_coral_back'), $r('app.color.collection_coral_top'),
    $r('app.color.collection_coral_front'), $r('app.color.collection_coral_ink')],
  [$r('app.color.collection_pine_back'), $r('app.color.collection_pine_top'),
    $r('app.color.collection_pine_front'), $r('app.color.collection_pine_ink')],
  [$r('app.color.collection_stone_back'), $r('app.color.collection_stone_top'),
    $r('app.color.collection_stone_front'), $r('app.color.collection_stone_ink')]
];

@ComponentV2
export struct ShelfCollectionFolder {
  @Param group: ShelfCollectionGroup = new ShelfCollectionGroup('', ShelfCollectionGroup.ALL_TINT);
  @Event onOpen: (group: string) => void = () => {};
  @Local widthVp: number = 164;
  @Local lifted: boolean = false;
  private touchX: number = 0;
  private touchY: number = 0;
  private pressTimer: number = -1;

  aboutToDisappear(): void { this.cancelPressTimer(); }

  private cancelPressTimer(): void {
    if (this.pressTimer !== -1) clearTimeout(this.pressTimer);
    this.pressTimer = -1;
  }

  private color(part: number): Resource {
    return SHELF_FOLDER_PALETTES[this.group.tint][part];
  }

  private setLifted(value: boolean): void {
    if (this.lifted === value) return;
    this.getUIContext().animateTo({ duration: value ? 280 : 420, curve: Curve.FastOutSlowIn }, (): void => {
      this.lifted = value;
    });
  }

  private touch(event: TouchEvent): void {
    const point = event.touches[0];
    if (event.type === TouchType.Down && point) {
      this.touchX = point.windowX;
      this.touchY = point.windowY;
      this.cancelPressTimer();
      this.pressTimer = setTimeout((): void => { this.pressTimer = -1; this.setLifted(true); }, 90);
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel ||
      (event.type === TouchType.Move && point &&
        Math.hypot(point.windowX - this.touchX, point.windowY - this.touchY) > 8)) {
      this.cancelPressTimer();
      this.setLifted(false);
    }
  }

  private coverWidth(): number { return Math.max(36, (this.widthVp - 24) * 0.42); }

  private coverLeft(index: number): number {
    const count = Math.min(3, this.group.books.length);
    const width = this.coverWidth();
    const step = width - (this.widthVp - 24) * 0.15;
    const start = (this.widthVp - width - Math.max(0, count - 1) * step) / 2;
    const shift = index === 0 ? (this.lifted ? 0.05 : 0.13) : index === 2 ? (this.lifted ? -0.03 : -0.12) : 0;
    return start + index * step + width * shift;
  }

  @Builder
  private cover(book: Book, index: number) {
    // 缓存边界保留透明像素，让旋转时的纹理采样平滑过渡；旧 API 同样生效。
    Stack({ alignContent: Alignment.Center }) {
      CoverImage({ url: book.cover, title: book.title, author: book.author, themeBundleId: 'default',
        localPlaceholder: book.id.startsWith('import_'), themedDecoration: false, compositeEdges: true,
        antialiasEdges: true, interpolationQuality: ImageInterpolation.High,
        imgWidth: this.coverWidth(), imgHeight: this.coverWidth() / 0.68, useFixedHeight: true, radius: 4 })
    }.width(this.coverWidth() + 2).height(this.coverWidth() / 0.68 + 2).padding(1)
      .renderGroup(true)
      .rotate({ angle: index === 0 ? (this.lifted ? -16 : -12) :
        (index === 1 ? -2 : (this.lifted ? 16 : 12)) })
      .position({ x: this.coverLeft(index) - 1,
        y: Math.max(8, this.widthVp * 0.74 - 23 - this.coverWidth() / 0.68) + (index === 1 ? -10 : 1) - 1 })
      .translate({ y: this.lifted ? -9 : 0 })
      .zIndex(index + 1)
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Row().width('46%').height(22).borderRadius({ topLeft: 12, topRight: 12 })
          .backgroundColor(this.color(0)).position({ x: 0, y: this.widthVp * 0.12 - 8 })
        Row().width('100%').height('82%').borderRadius({ topLeft: 6, topRight: 16, bottomLeft: 17, bottomRight: 17 })
          .backgroundColor(this.color(0)).position({ x: 0, y: this.widthVp * 0.74 * 0.18 })
          .border({ width: 0.5, color: '#40FFFFFF' })
        ForEach(this.group.books.slice(0, 3), (book: Book, index: number) => {
          this.cover(book, index)
        }, (book: Book): string => book.id)
        if (this.group.books.length === 0) {
          SymbolGlyph($r('sys.symbol.book')).fontSize(32).fontColor([this.color(3)]).opacity(0.45)
            .position({ x: this.widthVp / 2 - 16, y: this.widthVp * 0.24 })
        }
        Row() {
          Text($r('app.string.collection_monogram')).fontSize(8).letterSpacing(2)
            .fontColor(this.color(3)).opacity(0.75)
          Blank()
          SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(14).fontColor([this.color(3)]).opacity(0.6)
        }.width('100%').height('57%').padding(12).alignItems(VerticalAlign.Bottom)
          .linearGradient({ angle: 165, colors: [[this.color(1), 0], [this.color(2), 1]] })
          .border({ width: 1, color: $r('app.color.collection_folder_edge') })
          .borderRadius({ topLeft: 12, topRight: 12, bottomLeft: 16, bottomRight: 16 })
          .rotate({ x: 1, angle: this.lifted ? -20 : -9, centerY: '100%', perspective: 600 })
          .position({ x: 0, y: this.widthVp * 0.74 * 0.43 }).zIndex(5)
          .renderGroup(true)
      }.width('100%').height(this.widthVp * 0.74).clip(false).hitTestBehavior(HitTestMode.None)
      Row({ space: 6 }) {
        Text(this.group.id === '' ? $r('app.string.collection_all_books') :
          this.group.id === BookPresentation.UNGROUPED ? $r('app.string.shelf_group_none') : this.group.id)
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Text($r('app.string.collection_book_count', this.group.books.length)).fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
      }.width('100%').margin({ top: 8 })
      Text(this.group.books.length > 0 ? this.group.books.slice(0, 2).map((book: Book): string => book.title).join(' · ') :
        $r('app.string.collection_empty_folder_hint'))
        .fontSize(10).fontColor($r('sys.color.font_tertiary')).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').margin({ top: 5 })
    }.width('100%').padding({ top: 8, bottom: 4 }).clip(false)
      .id(this.group.id === '' ? 'shelf-collection-all-books' : 'shelf-collection-folder-' + this.group.id)
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        if (typeof size.width === 'number' && size.width > 0) this.widthVp = size.width;
      })
      .onTouch((event: TouchEvent): void => this.touch(event))
      .onHover((hovered: boolean): void => this.setLifted(hovered))
      .onClick((): void => this.onOpen(this.group.id))
      .accessibilityGroup(true).accessibilityRole(AccessibilityRoleType.BUTTON)
  }
}
