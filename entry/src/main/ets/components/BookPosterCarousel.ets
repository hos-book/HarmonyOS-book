import { CoverImage } from './CoverImage';
import { BookRatingBadge } from './BookRatingBadge';
import { AppColor, AppRadius, AppTheme } from '../theme/Theme';
import { OneShotCoverState, OneShotTransitionCoordinator, OneShotTransitionIds } from '../utils/OneShotTransition';

export const BOOK_POSTER_HEIGHT: number = 232;
export const BOOK_POSTER_DECK_HEIGHT: number = 208;
export const BOOK_POSTER_COVER_WIDTH: number = 120;

/** 仅用于轮播展示，真实书源身份和详情路由仍由调用方保留。 */
export class BookPosterItem {
  id: string;
  title: string;
  author: string;
  intro: string;
  coverUrl: string;
  aspectRatio: number;
  rating: number;

  constructor(id: string, title: string, author: string, intro: string, coverUrl: string, aspectRatio: number,
    rating: number = 0) {
    this.id = id;
    this.title = title;
    this.author = author;
    this.intro = intro;
    this.coverUrl = coverUrl;
    this.aspectRatio = aspectRatio;
    this.rating = rating;
  }
}
/** 两种首页轮播共用占位，加载前后不改变分类栏位置。 */
@ComponentV2
export struct BookPosterSkeleton {
  build() {
    Column() {
      Row({ space: 16 }) {
        Column({ space: 12 }) {
          Row().width('80%').height(20).borderRadius(AppRadius.Xs).backgroundColor(AppColor.Divider)
          Row().width('50%').height(12).borderRadius(AppRadius.Xs).backgroundColor(AppColor.Divider)
          Row().width('100%').height(10).borderRadius(AppRadius.Xs).backgroundColor(AppColor.Divider)
          Row().width('90%').height(10).borderRadius(AppRadius.Xs).backgroundColor(AppColor.Divider)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Stack() {
          Row().width(BOOK_POSTER_COVER_WIDTH).height(BOOK_POSTER_COVER_WIDTH / 0.75)
            .borderRadius(AppRadius.Sm).backgroundColor(AppColor.Divider)
        }.width(BOOK_POSTER_COVER_WIDTH).height(BOOK_POSTER_DECK_HEIGHT)
      }.width('100%').layoutWeight(1).padding({ left: 24, right: 42, top: 8 })
      Row().height(16)
    }.height(BOOK_POSTER_HEIGHT).width('100%')
  }
}

@ComponentV2
struct BookPosterIntroduction {
  @Require @Param item: BookPosterItem;
  @Event onChoose: (item: BookPosterItem, nodeId: string, radius: number) => void = () => {};
  build() {
    Column({ space: 9 }) {
      Text(this.item.title).fontSize(23).fontWeight(FontWeight.Bold).maxLines(2)
        .fontColor($r('sys.color.font_primary')).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.item.author).fontSize(12).maxLines(1)
        .fontColor($r('sys.color.font_secondary')).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.item.intro.trim().length > 0) {
        Text(this.item.intro).fontSize(12).lineHeight(19).maxLines(4)
          .fontColor($r('sys.color.font_secondary')).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.width('100%').alignItems(HorizontalAlign.Start).onClick(() => this.onChoose(this.item, '', AppRadius.Sm))
  }
}

@ComponentV2
export struct BookPosterCarousel {
  @Param items: BookPosterItem[] = [];
  @Param autoPlay: boolean = false;
  @Param openCover: boolean = false;
  @Param useOriginalCoverRatio: boolean = false;
  @Local coverState: OneShotCoverState = OneShotTransitionCoordinator.getInstance().coverState;
  private nodePrefix: string = OneShotTransitionIds.nextSourceId('poster');
  @Event onChoose: (item: BookPosterItem, nodeId: string, radius: number) => void = () => {};
  @Event onCoverChange: (cover: string) => void = () => {};
  @Event onVerticalScroll: (offset: number) => void = () => {};
  @Event onVerticalFling: (velocity: number) => void = () => {};
  @Local current: number = 0;
  @Local dragX: number = 0;
  @Local turning: boolean = false;
  @Local returningIndex: number = -1;
  @Local returnProgress: number = 0;
  @Local deckWidth: number = BOOK_POSTER_COVER_WIDTH;
  private exitX: number = 0;
  private dragging: boolean = false;
  private touching: boolean = false;
  private verticalTouch: boolean = false;
  private touchX: number = 0;
  private deckLeft: number = 0;
  private deckTop: number = 0;
  private canDragCover: boolean = false;
  private lastTouchY: number = 0;
  private touchY: number = 0;
  private touchStarted: number = 0;
  private lastSwipe: number = 0;
  private alive: boolean = false;
  private revision: number = 0;
  private timer: number = -1;

  aboutToAppear(): void { this.alive = true; this.schedule(); }
  aboutToDisappear(): void { this.alive = false; this.revision++; this.stopTimer(); }

  @Monitor('items')
  resetDeck(): void {
    this.revision++;
    this.current = 0;
    this.dragX = 0;
    this.turning = false;
    this.returningIndex = -1;
    this.returnProgress = 0;
    this.dragging = false;
    this.touching = false;
    this.onCoverChange(this.items[0]?.coverUrl ?? '');
    this.schedule();
  }

  @Monitor('autoPlay')
  updatePlayback(): void { this.schedule(); }

  private stopTimer(): void {
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
  }

  private schedule(): void {
    this.stopTimer();
    if (!this.alive || !this.autoPlay || this.items.length < 2 || this.touching || this.dragging || this.turning) return;
    this.timer = setTimeout((): void => { this.timer = -1; this.turn(-1); }, 5000);
  }

  private depth(index: number): number {
    return (index - this.current + this.items.length) % Math.max(1, this.items.length);
  }

  private travel(): number { return this.deckWidth + 24; }
  private progress(): number { return Math.min(1, Math.abs(this.dragX) / this.travel()); }
  private layer(index: number): number { return Math.min(2, Math.max(0, this.depth(index) - this.progress())); }
  private returnLayer(): number { return Math.min(2, this.items.length - 1); }
  private cardX(index: number): number {
    if (index === this.returningIndex) return this.exitX * (1 - this.returnProgress) + this.returnLayer() * 13 * this.returnProgress;
    return this.depth(index) === 0 ? this.dragX : this.layer(index) * 13;
  }
  private cardY(index: number): number {
    if (index === this.returningIndex) return -12 + (12 - this.returnLayer() * 10) * this.returnProgress;
    return this.depth(index) === 0 ? -this.progress() * 12 : -this.layer(index) * 10;
  }
  private cardAngle(index: number): number {
    if (index === this.returningIndex) return this.exitX / 14 * (1 - this.returnProgress) + this.returnLayer() * 5 * this.returnProgress;
    return this.depth(index) === 0 ? this.dragX / 14 : this.layer(index) * 5;
  }
  private cardScale(index: number): number {
    if (index === this.returningIndex) return 0.92 + (0.08 - this.returnLayer() * 0.07) * this.returnProgress;
    return this.depth(index) === 0 ? 1 - this.progress() * 0.08 : 1 - this.layer(index) * 0.07;
  }

  private turn(direction: number): void {
    if (!this.alive || this.turning || this.items.length < 2) return;
    this.stopTimer();
    this.dragging = false;
    this.turning = true;
    this.exitX = direction * this.travel();
    const revision = this.revision;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut,
      onFinish: (): void => {
        if (!this.alive || revision !== this.revision) return;
        // 出牌后再降低层级，保留封面实体，沿侧边收回队尾。
        this.returningIndex = this.current;
        this.returnProgress = 0;
        this.current = (this.current + 1) % this.items.length;
        this.dragX = 0;
        this.onCoverChange(this.items[this.current].coverUrl);
        this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut,
          onFinish: (): void => {
            if (!this.alive || revision !== this.revision) return;
            this.returningIndex = -1;
            this.turning = false;
            this.schedule();
          }
        }, (): void => { this.returnProgress = 1; });
      }
    }, (): void => { this.dragX = this.exitX; });
  }

  private rebound(): void {
    this.dragging = false;
    this.turning = true;
    const revision = this.revision;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut,
      onFinish: (): void => {
        if (!this.alive || revision !== this.revision) return;
        this.turning = false;
        this.schedule();
      }
    }, (): void => { this.dragX = 0; });
  }

  private handleTouch(event: TouchEvent): void {
    const point = event.changedTouches[0];
    if (event.type === TouchType.Down) {
      if (point === undefined) return;
      this.touching = true;
      this.verticalTouch = false;
      this.touchX = point.windowX;
      this.touchY = point.windowY;
      this.lastTouchY = point.windowY;
      this.canDragCover = !this.turning && this.items.length > 1 &&
        point.windowX >= this.deckLeft - 12 && point.windowX <= this.deckLeft + this.deckWidth + 30 &&
        point.windowY >= this.deckTop - 12 && point.windowY <= this.deckTop + BOOK_POSTER_DECK_HEIGHT + 12;
      this.touchStarted = Date.now();
      this.stopTimer();
      return;
    }
    if (!this.touching) return;
    if (event.type === TouchType.Move && point !== undefined) {
      const dx = point.windowX - this.touchX;
      const dy = point.windowY - this.touchY;
      if (!this.dragging && !this.verticalTouch) {
        if (Math.abs(dy) > 8 && Math.abs(dy) > Math.abs(dx)) this.verticalTouch = true;
        else if (this.canDragCover && Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(dy) * 1.2) this.dragging = true;
      }
      if (this.verticalTouch) this.onVerticalScroll(this.lastTouchY - point.windowY);
      this.lastTouchY = point.windowY;
      if (this.dragging) this.dragX = Math.max(-this.travel(), Math.min(this.travel(), dx));
      return;
    }
    if (event.type !== TouchType.Up && event.type !== TouchType.Cancel) return;
    this.touching = false;
    if (this.verticalTouch) {
      this.lastSwipe = Date.now();
      const velocity = (this.lastTouchY - this.touchY) * 1000 / Math.max(1, Date.now() - this.touchStarted);
      if (event.type === TouchType.Up && Math.abs(velocity) > 80) {
        this.onVerticalFling(Math.max(-1600, Math.min(1600, velocity)));
      }
      this.schedule();
      return;
    }
    if (!this.dragging) { this.schedule(); return; }
    this.lastSwipe = Date.now();
    const speed = Math.abs(this.dragX) * 1000 / Math.max(1, Date.now() - this.touchStarted);
    if (event.type === TouchType.Up && (Math.abs(this.dragX) >= 48 || speed >= 650)) {
      this.turn(this.dragX < 0 ? -1 : 1);
    } else { this.rebound(); }
  }

  private choose(): void {
    if (!this.turning && !this.dragging && Date.now() - this.lastSwipe > 350 && this.items[this.current] !== undefined) {
      this.onChoose(this.items[this.current], this.coverNodeId(this.items[this.current]), AppRadius.Sm);
    }
  }


  private coverNodeId(item: BookPosterItem): string { return this.nodePrefix + '-' + item.id; }

  build() {
    Column() {
      Row({ space: 16 }) {
        if (this.items[this.current] !== undefined) {
          BookPosterIntroduction({ item: this.items[this.current],
            onChoose: (): void => this.choose() }).layoutWeight(1)
        }
        Stack({ alignContent: Alignment.Center }) {
          ForEach(this.items, (item: BookPosterItem, index: number) => {
            Column() {
              Stack({ alignContent: Alignment.BottomEnd }) {
              CoverImage({ url: item.coverUrl, title: AppTheme.IllustratedPlaceholders ? item.title : '', author: item.author,
                imgWidth: BOOK_POSTER_COVER_WIDTH,
                aspectRatioValue: item.aspectRatio,
                useOriginalRatio: this.useOriginalCoverRatio, maxOriginalHeight: 160,
                radius: AppRadius.Sm, compositeEdges: true,
                imageFit: ImageFit.Contain, decodeW: 480, decodeH: 640 })
                BookRatingBadge({ rating: item.rating, sizeScale: 0.85,
                  coverWidth: this.useOriginalCoverRatio ? Math.min(BOOK_POSTER_COVER_WIDTH, 160 * item.aspectRatio) : BOOK_POSTER_COVER_WIDTH })
              }
            }
            // 为离屏纹理留下透明采样边，避免旋转时纹理边界直接形成硬锯齿。
            // 封面本身尺寸不变，留白随卡片一起合成，不对合成层再次裁剪。
            .padding(1)
            .constraintSize({ maxWidth: BOOK_POSTER_COVER_WIDTH + 2 })
            .id(this.coverNodeId(item))
            .renderGroup(true)
            .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
            .opacity(this.coverState.hiddenSourceId === this.coverNodeId(item) ? 0 : 1)
            .scale({ x: this.cardScale(index), y: this.cardScale(index) })
            .rotate({ angle: this.cardAngle(index),
              centerX: '50%', centerY: '85%' })
            .translate({ x: this.cardX(index), y: this.cardY(index) })
            .zIndex(this.items.length - this.depth(index))
            .hitTestBehavior(HitTestMode.None)
            .accessibilityLevel('no')
          }, (item: BookPosterItem): string => item.id)
        }.width(BOOK_POSTER_COVER_WIDTH).height(BOOK_POSTER_DECK_HEIGHT)
        .onAreaChange((_old: Area, area: Area): void => {
          this.deckWidth = Number(area.width);
          this.deckLeft = Number(area.globalPosition.x);
          this.deckTop = Number(area.globalPosition.y);
        })
        // 覆盖右侧整叠牌及周围留白，不延伸到左侧介绍。
        .responseRegion({ x: -12, y: -12, width: this.deckWidth + 42, height: BOOK_POSTER_DECK_HEIGHT + 24 })
        .accessibilityGroup(true).accessibilityText(this.items[this.current]?.title ?? '')
        .onClick((): void => { if (this.openCover) this.choose(); })
      }.width('100%').layoutWeight(1).padding({ left: 24, right: 42, top: 8 })
      Row({ space: 5 }) {
        ForEach(this.items, (indicatorItem: BookPosterItem, index: number) => {
          Row().width(index === this.current ? 16 : 5).height(5).borderRadius(3)
            .id('ranking-poster-dot-' + indicatorItem.id)
            .backgroundColor(index === this.current ? $r('sys.color.font_secondary') : AppColor.Divider)
        }, (item: BookPosterItem): string => item.id)
      }.height(16).justifyContent(FlexAlign.Center)
    }.height(BOOK_POSTER_HEIGHT).width('100%').clip(true)
    .onTouch((event: TouchEvent): void => this.handleTouch(event))
    .onTouchTestDone((_event: BaseGestureEvent, recognizers: GestureRecognizer[]): void => {
      // 在本次触摸识别前排除外层横滑，包括 MainPage 自定义的切页手势。
      // 不能仅筛选内置手势或停止 Touch 冒泡，否则翻牌时仍会切到书架。
      // 作用域是整个轮播区，右侧切牌仍由 handleTouch 驱动，纵向滚动不拦截。
      for (const recognizer of recognizers) {
        if (recognizer instanceof PanRecognizer &&
          recognizer.getDirection() === PanDirection.Horizontal) {
          recognizer.preventBegin();
        }
      }
    })
  }
}
