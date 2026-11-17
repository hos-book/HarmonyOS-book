import { Book } from '../model/Book';
import { ShelfCollectionGroup, ShelfRecentBook } from '../model/ShelfCollection';
import { AppColor, AppTheme } from '../theme/Theme';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { ShelfCollectionFolder } from './ShelfCollectionFolder';
import { ShelfCollectionRecentCard } from './ShelfCollectionRecentCard';

@ComponentV2
export struct ShelfCollectionView {
  @Param groups: ShelfCollectionGroup[] = [];
  @Param recent: ShelfRecentBook[] = [];
  @Param loading: boolean = false;
  @Param historyEnabled: boolean = true;
  @Param visible: boolean = true;
  @Param topInset: number = 100;
  @Param bottomInset: number = 100;
  @Param scroller: Scroller = new Scroller();
  @Event onGroup: (group: string) => void = () => {};
  @Event onBook: (book: Book, coverId: string) => void = () => {};
  @Event onRecords: () => void = () => {};
  @Event onRecentTouch: (active: boolean) => void = () => {};
  @Local recentIndex: number = 0;
  private recentBookIds: string = '';
  @Event onScrollStopped: () => void = () => {};
  @Event onContentScroll: (offset: number, state: ScrollState) => void = () => {};
  @Local columns: number = 2;
  @Local now: number = Date.now();
  private data: HomeRecommendationDataSource<ShelfCollectionGroup> = new HomeRecommendationDataSource<ShelfCollectionGroup>();
  private clockTimer: number = -1;

  aboutToAppear(): void { this.data.setItems(this.groups); this.syncRecentIndex(); this.refreshClock(); }
  aboutToDisappear(): void {
    if (this.clockTimer !== -1) clearTimeout(this.clockTimer);
    this.onRecentTouch(false);
  }

  @Monitor('recent')
  private syncRecentIndex(): void {
    const ids = this.recent.map((item: ShelfRecentBook): string => item.book.id).join('|');
    if (ids !== this.recentBookIds) this.recentIndex = 0;
    this.recentBookIds = ids;
  }

  @Monitor('groups')
  private updateGroups(): void { this.data.setItems(this.groups); }

  @Monitor('visible')
  private refreshClock(): void {
    if (this.clockTimer !== -1) clearTimeout(this.clockTimer);
    this.clockTimer = -1;
    if (!this.visible) return;
    this.now = Date.now();
    this.clockTimer = setTimeout((): void => this.refreshClock(), 60000);
  }

  private greeting(): Resource {
    const hour = new Date(this.now).getHours();
    if (hour < 6 || hour >= 22) return $r('app.string.collection_greeting_night');
    if (hour < 12) return $r('app.string.collection_greeting_morning');
    if (hour < 18) return $r('app.string.collection_greeting_afternoon');
    return $r('app.string.collection_greeting_evening');
  }

  private weekday(): Resource {
    return [$r('app.string.collection_sunday'), $r('app.string.collection_monday'),
      $r('app.string.collection_tuesday'), $r('app.string.collection_wednesday'),
      $r('app.string.collection_thursday'), $r('app.string.collection_friday'),
      $r('app.string.collection_saturday')][new Date(this.now).getDay()];
  }

  private dateLine(): Resource {
    const date = new Date(this.now);
    const day = this.getUIContext().getHostContext()?.resourceManager.getStringSync(this.weekday().id) ?? '';
    return $r('app.string.collection_date', date.getMonth() + 1, date.getDate(), day);
  }

  @LocalBuilder
  private recentCard(index: number) {
    ShelfCollectionRecentCard({ item: this.recent[index],
      onBook: (book: Book, coverId: string): void => this.onBook(book, coverId) })
  }

  @LocalBuilder
  private header() {
    Column() {
      Row().height(this.topInset).hitTestBehavior(HitTestMode.None)
      Row({ space: 8 }) {
        Column({ space: 6 }) {
          Text(this.dateLine()).fontSize(11).fontColor(AppTheme.TextSecondary).letterSpacing(1)
          Text(this.greeting()).fontSize(24).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
            .maxLines(2)
          Text($r('app.string.collection_greeting_hint')).fontSize(11).fontColor(AppTheme.TextSecondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Stack({ alignContent: Alignment.Center }) {
          Row().width(56).height(56).borderRadius(28)
            .radialGradient({ center: ['50%', '50%'], radius: 28,
              colors: [[$r('app.color.collection_sun_halo'), 0], [$r('app.color.collection_sun_halo_clear'), 0.8]] })
          SymbolGlyph(new Date(this.now).getHours() >= 18 || new Date(this.now).getHours() < 6 ?
            $r('sys.symbol.moon') : $r('sys.symbol.sun_max'))
            .fontSize(38).fontWeight(FontWeight.Lighter).fontColor([$r('app.color.collection_sun')])
        }.width(56).height(56).hitTestBehavior(HitTestMode.None)
      }.width('100%').margin({ bottom: 12 })
      if (this.historyEnabled && this.recent.length > 0) {
        Row() {
          Text($r('app.string.collection_recent')).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TextPrimary).layoutWeight(1)
          Row({ space: 4 }) {
            Text($r('app.string.collection_all_records')).fontSize(11).fontColor(AppTheme.TextSecondary)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(11).fontColor([AppTheme.TextSecondary])
          }.height(30).onClick((): void => this.onRecords()).id('shelf-collection-all-records')
            .accessibilityGroup(true).accessibilityRole(AccessibilityRoleType.BUTTON)
        }.width('100%').margin({ bottom: 8 })
        Swiper() {
          this.recentCard(0)
          if (this.recent.length > 1) { this.recentCard(1) }
          if (this.recent.length > 2) { this.recentCard(2) }
        }.width(this.recent.length > 1 ? 'calc(100% + 20vp)' : '100%').height(86).index(this.recentIndex)
          .displayCount(1).loop(this.recent.length > 1).autoPlay(false).indicator(false).itemSpace(12)
          .nextMargin(this.recent.length > 1 ? 32 : 0, true).disableSwipe(this.recent.length < 2)
          .nestedScroll(SwiperNestedScrollMode.SELF_ONLY).effectMode(EdgeEffect.Spring)
          .duration(320).curve(Curve.EaseOut)
          .onChange((index: number): void => { this.recentIndex = index; })
          .onTouch((event: TouchEvent): void => {
            if (event.type === TouchType.Down) this.onRecentTouch(true);
            else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.onRecentTouch(false);
          }).id('shelf-collection-recent-swiper')
        if (this.recent.length > 1) {
          Row({ space: 5 }) {
            ForEach([0, 1, 2].slice(0, this.recent.length), (index: number) => {
              Row().width(index === this.recentIndex ? 14 : 5).height(5).borderRadius(3)
                .backgroundColor(index === this.recentIndex ? AppColor.Brand : AppColor.Divider)
            }, (index: number): string => index.toString())
          }.width('100%').justifyContent(FlexAlign.Center).margin({ top: 8 }).accessibilityLevel('no')
        }
      }
      Row({ space: 6 }) {
        Text($r('app.string.collection_groups')).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TextPrimary)
        Text(this.groups.length.toString()).fontSize(11).fontColor(AppTheme.TextTertiary)
        Blank()
        Text($r('app.string.collection_all_books')).fontSize(11).fontColor(AppColor.Brand)
          .height(32).onClick((): void => this.onGroup('')).id('shelf-collection-all-books')
      }.width('100%').margin({ top: 12 })
      if (this.loading) {
        LoadingProgress().color(AppColor.Brand).width(28).height(28).margin(24)
      } else if (this.groups.length === 0) {
        Text($r('app.string.shelf_filter_empty')).fontSize(13).fontColor(AppTheme.TextSecondary).padding(24)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    List({ scroller: this.scroller }) {
      ListItemGroup({ header: this.header(), space: 12 }) {
        LazyForEach(this.data, (group: ShelfCollectionGroup) => {
          ListItem() {
            ShelfCollectionFolder({ group: group, onOpen: (id: string): void => this.onGroup(id) })
          }.clip(false)
        }, (group: ShelfCollectionGroup): string => JSON.stringify([group.id, group.tint,
          group.books.map((book: Book): string => book.id + book.title + book.cover)]))
      }.padding({ left: 20, right: 20 }).clip(false)
    }.lanes(this.columns, 16).width('100%').height('100%')
      .contentEndOffset(this.bottomInset).cachedCount(2).scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onDidScroll((offset: number, state: ScrollState): void => this.onContentScroll(offset, state))
      .onScrollStop((): void => this.onScrollStopped())
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        if (typeof size.width === 'number') {
          this.columns = size.width < AdaptiveLayout.MEDIUM_WIDTH ? 2 : Math.max(3, Math.floor(size.width / 220));
        }
      })
  }
}
