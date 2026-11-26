import { Book } from '../model/Book';
import { ShelfRecentBook } from '../model/ShelfCollection';
import { AppColor, AppTheme } from '../theme/Theme';
import { OneShotCoverState, OneShotTransitionCoordinator, OneShotTransitionIds } from '../utils/OneShotTransition';
import { PlayerDragState, PlayerDragTransition } from '../utils/PlayerDragTransition';
import { PhysicalBookCover } from './PhysicalBookCover';

export const SHELF_RECENT_CARD_HEIGHT: number = 88;

@ComponentV2
export struct ShelfCollectionRecentCard {
  @Require @Param item: ShelfRecentBook;
  @Event onBook: (book: Book, coverId: string) => void = () => {};
  @Local playerTransition: PlayerDragState = PlayerDragTransition.getInstance().state;
  @Local sourceCoverState: OneShotCoverState = OneShotTransitionCoordinator.getInstance().coverState;

  private recentCoverId(book: Book): string { return 'shelf-recent-' + OneShotTransitionIds.sourceCover(book.id); }

  build() {
    Row({ space: 12 }) {
      PhysicalBookCover({ url: this.item.book.cover, title: this.item.book.title, author: this.item.book.author,
        localPlaceholder: this.item.book.id.startsWith('import_'),
        // 最近阅听最多三张，侧边预览也主动恢复磁盘缓存，不等待 Swiper 可见性回调。
        eagerLoad: true, imgWidth: 44 })
        .id(this.recentCoverId(this.item.book))
        .opacity(this.sourceCoverState.hiddenSourceId === this.recentCoverId(this.item.book) ||
          (this.playerTransition.active && this.playerTransition.sourceNodeId === this.recentCoverId(this.item.book)) ? 0 : 1)
        .hitTestBehavior(HitTestMode.None)
      Column({ space: 4 }) {
        Row({ space: 5 }) {
          Row().width(4).height(4).borderRadius(2).backgroundColor(AppColor.Brand)
          Text(this.item.book.contentType === 'text' || this.item.book.contentType === 'comic' ?
            $r('app.string.collection_continue_read') : $r('app.string.collection_continue_listen'))
            .fontSize(10).fontColor(AppColor.Brand)
        }.width('100%')
        Text(this.item.book.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.item.chapterTitle || $r('app.string.collection_continue_position'))
          .fontSize(10).fontColor(AppTheme.TextSecondary).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Progress({ value: this.item.progress, total: 100, type: ProgressType.Linear })
          .color(AppColor.Brand).backgroundColor(AppColor.BrandSoft).height(3).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.item.book.contentType === 'text' || this.item.book.contentType === 'comic' ?
          $r('sys.symbol.arrow_right') : $r('sys.symbol.play_fill'))
          .fontSize(15).fontColor([AppColor.Brand])
      }.width(32).height(32).borderRadius(16).backgroundColor(AppColor.BrandSoft)
        .hitTestBehavior(HitTestMode.None)
    }.width('100%').height(SHELF_RECENT_CARD_HEIGHT).padding(12).borderRadius(16)
      .backgroundColor(Color.Transparent)
      .backgroundEffect({ radius: 12, saturation: 1, brightness: 1,
        color: $r('app.color.collection_recent_glass') })
      .border({ width: 0.5, color: $r('app.color.collection_recent_edge') }).clip(true)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
      .id('shelf-collection-recent-' + this.item.book.id)
      .onClick((): void => this.onBook(this.item.book, this.recentCoverId(this.item.book)))
      .accessibilityGroup(true).accessibilityRole(AccessibilityRoleType.BUTTON)
  }

}
