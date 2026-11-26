import { InfinityLoadingIndicator } from './InfinityLoadingIndicator';
import { Book } from '../model/Book';
import { ShelfCollectionData, ShelfCollectionGroup, ShelfRecentBook } from '../model/ShelfCollection';
import { AppColor, AppTheme } from '../theme/Theme';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { ShelfCollectionFolder } from './ShelfCollectionFolder';
import { ShelfCollectionRecentCard, SHELF_RECENT_CARD_HEIGHT } from './ShelfCollectionRecentCard';

@ComponentV2
export struct ShelfCollectionView {
  @Param groups: ShelfCollectionGroup[] = [];
  @Param recent: ShelfRecentBook[] = [];
  @Param loading: boolean = false;
  @Param historyEnabled: boolean = true;
  @Param reorderEnabled: boolean = true;
  @Param visible: boolean = true;
  @Param topInset: number = 100;
  @Param bottomInset: number = 100;
  @Param scroller: Scroller = new Scroller();
  @Event onGroup: (group: string) => void = () => {};
  @Event onBook: (book: Book, coverId: string) => void = () => {};
  @Event onRecords: () => void = () => {};
  @Event onRecentTouch: (active: boolean) => void = () => {};
  @Event onReorder: (groups: string[]) => Promise<void> = async (): Promise<void> => {};
  @Local recentIndex: number = 0;
  @Local wideRecent: boolean = false;
  @Local draggingGroupId: string = '';
  private recentBookIds: string = '';
  @Event onScrollStopped: () => void = () => {};
  @Event onContentScroll: (offset: number, state: ScrollState) => void = () => {};
  @Local columns: number = 2;
  @Local now: number = Date.now();
  private data: HomeRecommendationDataSource<ShelfCollectionGroup> = new HomeRecommendationDataSource<ShelfCollectionGroup>();
  private renderedGroups: ShelfCollectionGroup[] = [];
  private savedOrder: string[] = [];
  private pendingOrderSaves: number = 0;
  private orderSaveTask: Promise<void> = Promise.resolve<void>(undefined);
  private dragging: boolean = false;
  private clockTimer: number = -1;
  private dropTimer: number = -1;
  private dragAppearanceTimer: number = -1;
  private readonly moveHandler: (from: number, to: number) => void =
    (from: number, to: number): void => { this.reorder(from, to); };
  private readonly dragEvents: ItemDragEventHandler = {
    onLongPress: (index: number): void => this.beginDrag(index),
    onDragStart: (index: number): void => this.beginDrag(index),
    onDrop: (_index: number): void => this.finishDrag()
  };

  aboutToAppear(): void { this.updateGroups(); this.syncRecentIndex(); this.refreshClock(); }
  aboutToDisappear(): void {
    if (this.clockTimer !== -1) clearTimeout(this.clockTimer);
    if (this.dropTimer !== -1) clearTimeout(this.dropTimer);
    if (this.dragAppearanceTimer !== -1) clearTimeout(this.dragAppearanceTimer);
    this.onRecentTouch(false);
  }

  @Monitor('recent')
  private syncRecentIndex(): void {
    const ids = this.recent.map((item: ShelfRecentBook): string => item.book.id).join('|');
    if (ids !== this.recentBookIds) this.recentIndex = 0;
    this.recentBookIds = ids;
  }

  @Monitor('groups')
  private updateGroups(): void {
    // 原生拖拽负责移动占位；期间不能用宿主刷新重载正在拖动的节点。
    if (this.dragging || this.pendingOrderSaves > 0) return;
    const folders = this.draggableGroups();
    this.savedOrder = folders.map((group: ShelfCollectionGroup): string => group.id);
    this.renderGroups(folders);
  }

  private draggableGroups(): ShelfCollectionGroup[] {
    return this.groups.filter((group: ShelfCollectionGroup): boolean => group.id !== '');
  }

  private renderGroups(groups: ShelfCollectionGroup[]): void {
    this.renderedGroups = groups.slice();
    this.data.setItems(this.renderedGroups);
  }

  private beginDrag(index: number): void {
    if (this.dropTimer !== -1) clearTimeout(this.dropTimer);
    this.dropTimer = -1;
    if (this.dragAppearanceTimer !== -1) clearTimeout(this.dragAppearanceTimer);
    this.dragging = true;
    this.onRecentTouch(true);
    const id = this.renderedGroups[index]?.id ?? '';
    // 原生 onMove 在长按回调之后强制设置整项阴影；退出该回调后重设外观，保留原生位移和排序。
    this.dragAppearanceTimer = setTimeout((): void => {
      this.dragAppearanceTimer = -1;
      if (this.dragging) this.draggingGroupId = id;
    }, 0);
  }

  private finishDrag(): void {
    this.dragging = false;
    if (this.dragAppearanceTimer !== -1) clearTimeout(this.dragAppearanceTimer);
    this.dragAppearanceTimer = -1;
    this.draggingGroupId = '';
    this.onRecentTouch(false);
    if (this.dropTimer !== -1) clearTimeout(this.dropTimer);
    // onDrop 与 onMove 的分发顺序由框架决定，退出本次回调后再合并延迟的数据刷新。
    this.dropTimer = setTimeout((): void => {
      this.dropTimer = -1;
      if (this.pendingOrderSaves === 0 && !this.dragging) {
        this.renderGroups(ShelfCollectionData.ordered(this.draggableGroups(), JSON.stringify(this.savedOrder)));
      }
    }, 0);
  }

  private async reorder(from: number, to: number): Promise<void> {
    if (!this.reorderEnabled || from === to || from < 0 || to < 0 ||
      from >= this.renderedGroups.length || to >= this.renderedGroups.length) return;
    const next = this.renderedGroups.slice();
    next.splice(to, 0, next.splice(from, 1)[0]);
    // 先同步更新实际数据源，再串行保存；快速连续拖动也以当前可见顺序为准。
    this.renderGroups(next);
    const ids = next.map((group: ShelfCollectionGroup): string => group.id);
    this.pendingOrderSaves++;
    const save = this.orderSaveTask.then(async (): Promise<void> => {
      await this.onReorder(ids);
      this.savedOrder = ids;
    });
    this.orderSaveTask = save.catch((): void => {});
    try { await save; }
    catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
    } finally {
      this.pendingOrderSaves--;
      if (this.pendingOrderSaves === 0 && !this.dragging) {
        // @Param 的同步可能晚于保存完成，使用最近成功顺序恢复，避免落位后跳回旧位置。
        this.renderGroups(ShelfCollectionData.ordered(this.draggableGroups(), JSON.stringify(this.savedOrder)));
      }
    }
  }

  private updateWidth(width: number): void {
    this.columns = width < AdaptiveLayout.MEDIUM_WIDTH ? 2 : Math.max(3, Math.floor(width / 220));
    const wide = width >= AdaptiveLayout.MEDIUM_WIDTH;
    if (wide !== this.wideRecent) {
      this.wideRecent = wide;
      this.recentIndex = 0;
      this.onRecentTouch(false);
    }
  }

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
        if (this.wideRecent) {
          Row({ space: 12 }) {
            ForEach(this.recent.slice(0, 3), (item: ShelfRecentBook) => {
              ShelfCollectionRecentCard({ item: item,
                onBook: (book: Book, coverId: string): void => this.onBook(book, coverId) })
                .layoutWeight(1)
            }, (item: ShelfRecentBook): string => item.book.id)
          }.width('100%').height(SHELF_RECENT_CARD_HEIGHT).id('shelf-collection-recent-row')
        } else {
          Swiper() {
            this.recentCard(0)
            if (this.recent.length > 1) { this.recentCard(1) }
            if (this.recent.length > 2) { this.recentCard(2) }
          }.width(this.recent.length > 1 ? 'calc(100% + 20vp)' : '100%').height(SHELF_RECENT_CARD_HEIGHT).index(this.recentIndex)
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
      }
      Row({ space: 6 }) {
        Text($r('app.string.collection_groups')).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TextPrimary)
        Text(this.groups.length.toString()).fontSize(11).fontColor(AppTheme.TextTertiary)
      }.width('100%').margin({ top: 12 })
      if (this.loading) {
        InfinityLoadingIndicator({ indicatorSize: 28 }).margin(24)
      } else if (this.groups.length === 0) {
        Text($r('app.string.shelf_filter_empty')).fontSize(13).fontColor(AppTheme.TextSecondary).padding(24)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    List({ scroller: this.scroller, space: 12 }) {
      // 头部独占整行；可排序的 ListItem 必须直接归属 List。
      ListItemGroup({ header: this.header() }) {}.clip(false)
      if (this.groups[0]?.id === '') {
        ListItem() {
          ShelfCollectionFolder({ group: this.groups[0], onOpen: (id: string): void => this.onGroup(id) })
        }.clip(false)
      }
      LazyForEach(this.data, (group: ShelfCollectionGroup) => {
        ListItem() {
          ShelfCollectionFolder({ group: group, onOpen: (id: string): void => this.onGroup(id) })
        }.clip(false)
          .backgroundColor(this.draggingGroupId === group.id ? '#00000000' : Color.Transparent)
          .borderRadius(this.draggingGroupId === group.id ?
            { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 } : 0)
          .shadow({ radius: this.draggingGroupId === group.id ? 0 : 0.01, color: Color.Transparent })
          .accessibilityDescription($r('app.string.shelf_group_drag_hint'))
      }, (group: ShelfCollectionGroup): string => JSON.stringify([group.id, group.tint, group.books.length,
        group.books.slice(0, 3).map((book: Book): string => book.id + book.title + book.cover)]))
        .onMove(this.reorderEnabled ? this.moveHandler : undefined, this.dragEvents)
    }.lanes(this.columns, 16).width('100%').height('100%')
      .padding({ left: 20, right: 20 }).clip(false)
      .contentEndOffset(this.bottomInset).cachedCount(2).scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onDidScroll((offset: number, state: ScrollState): void => this.onContentScroll(offset, state))
      .onScrollStop((): void => this.onScrollStopped())
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.onRecentTouch(false);
      })
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        if (typeof size.width === 'number') {
          this.updateWidth(size.width);
        }
      })
  }
}
