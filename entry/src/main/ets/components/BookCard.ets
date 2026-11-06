import { Book } from '../model/Book';
import { BookRatingBadge } from './BookRatingBadge';
import { BookMetadataPolicy } from '../utils/BookMetadataPolicy';
import { AppRadius, AppSpace, AppFont, AppMotion, AppCurve } from '../theme/Theme';
import { CoverImage } from './CoverImage';
import { CoverDecoration } from './CoverDecoration';
import { CoverAspectRatio } from '../utils/CoverAspectRatio';
import {
  OneShotCoverState,
  OneShotTransitionCoordinator,
  OneShotTransitionIds
} from '../utils/OneShotTransition';

/**
 * 书架卡片：封面 + 标题 + 作者
 * 点击进入详情；按压保持封面坐标稳定；封面参与 Navigation 高级一镜到底转场
 */
@ComponentV2
export struct BookCard {
  @Param book: Book = {} as Book;
  @Param cardWidth: number = 110;
  @Param indexHint: number = 0;
  @Param coverAspectRatio: number = 1;
  @Param useOriginalCoverRatio: boolean = false;
  @Param coverImageFit: ImageFit = ImageFit.Cover;
  @Param coverRadius: number = AppRadius.Md;
  @Param showSourceBadge: boolean = true;
  @Param showRating: boolean = false;
  @Param showLatestChapter: boolean = false;
  @Event onTap: (id: string) => void = () => {};

  @Local coverState: OneShotCoverState = OneShotTransitionCoordinator.getInstance().coverState;
  @Local imageLoadFailed: boolean = false;
  @Local appeared: boolean = false;
  @Local coverPressed: boolean = false;
  @Local ratingCoverWidth: number = 100;
  @Local originalCoverRatio: number = 0.75;

  private displayCoverRatio(): number {
    return this.useOriginalCoverRatio ? this.originalCoverRatio : this.coverAspectRatio;
  }

  private rememberCoverSize(url: string, width: number, height: number): void {
    if (url !== this.book.cover) return;
    CoverAspectRatio.remember(url, width, height);
    this.originalCoverRatio = CoverAspectRatio.get(url, 0.75);
  }

  @Monitor('book')
  onBookChanged(): void {
    this.originalCoverRatio = CoverAspectRatio.get(this.book.cover, 0.75);
    this.imageLoadFailed = false;
  }

  private static shownIds: Set<string> = new Set();
  private static transitionIdSeed: number = 0;
  private transitionNodeId: string = '';
  private static openingDetail: boolean = false;
  private disposed: boolean = false;
  private entranceTimer: number = -1;
  private touchScreenX: number = 0;
  private touchScreenY: number = 0;

  aboutToAppear(): void {
    this.disposed = false;
    this.originalCoverRatio = CoverAspectRatio.get(this.book.cover, 0.75);
    if (this.transitionNodeId.length === 0) {
      BookCard.transitionIdSeed = BookCard.transitionIdSeed + 1;
      this.transitionNodeId = OneShotTransitionIds.sourceCover(this.book.id) + '-' +
        BookCard.transitionIdSeed.toString();
    }
    if (BookCard.shownIds.has(this.book.id)) {
      this.appeared = true;
      return;
    }
    BookCard.shownIds.add(this.book.id);
    // 首屏短错峰，不让后续书卡在滚动时持续等待动画。
    if (this.indexHint < 8) {
      const delay = Math.max(0, this.indexHint) * 30;
      this.entranceTimer = setTimeout((): void => {
        this.entranceTimer = -1;
        if (!this.disposed) this.appeared = true;
      }, delay);
    } else {
      this.appeared = true;
    }
  }

  static resetAnimations(): void {
    BookCard.shownIds.clear();
  }

  private sourceName(): string {
    if (this.book.narrator) return this.book.narrator;
    if (this.book.tags && this.book.tags.length > 0) return this.book.tags[0];
    return '';
  }

  private isLocalFile(path: string): boolean {
    return path.startsWith('/data/') || path.startsWith('file://');
  }

  aboutToDisappear(): void {
    this.disposed = true;
    if (this.entranceTimer !== -1) clearTimeout(this.entranceTimer);
    this.entranceTimer = -1;
  }

  private handleCoverTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      const touch = event.touches[0];
      if (touch === undefined) return;
      this.touchScreenX = touch.screenX;
      this.touchScreenY = touch.screenY;
      this.coverPressed = true;
    } else if (this.coverPressed) {
      const touch = event.touches[0];
      if (event.type === TouchType.Up || event.type === TouchType.Cancel ||
        (event.type === TouchType.Move && touch !== undefined &&
          (Math.abs(touch.screenX - this.touchScreenX) > 8 || Math.abs(touch.screenY - this.touchScreenY) > 8))) {
        this.coverPressed = false;
      }
    }
  }

  private async openDetail(): Promise<void> {
    if (BookCard.openingDetail) return;
    BookCard.openingDetail = true;
    const bookId = this.book.id;
    try {
      await OneShotTransitionCoordinator.getInstance().captureAsync(
        this.getUIContext(), bookId, this.transitionNodeId, this.coverRadius);
      if (!this.disposed && this.book.id === bookId) {
        this.onTap(bookId);
      }
    } finally {
      BookCard.openingDetail = false;
    }
  }

  build() {
    Column({ space: AppSpace.Xs }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (this.book.cover && this.book.cover.startsWith('http')) {
          CoverImage({
            url: this.book.cover,
            imgWidth: '100%',
            aspectRatioValue: this.displayCoverRatio(),
            imageFit: this.coverImageFit,
            radius: this.coverRadius,
            themedDecoration: false,
            highPriority: this.indexHint < 24,
            onImageSize: (url: string, width: number, height: number): void =>
              this.rememberCoverSize(url, width, height)
          })
        } else if (this.book.cover && this.isLocalFile(this.book.cover) && !this.imageLoadFailed) {
          Image('file://' + this.book.cover.replace(/^file:\/\//, ''))
            .width('100%')
            .aspectRatio(this.displayCoverRatio())
            .borderRadius(this.coverRadius)
            .objectFit(this.coverImageFit)
            .autoResize(true)
            .interpolation(ImageInterpolation.Medium)
            .onComplete((event) => {
              if (event?.loadingStatus === 0) this.rememberCoverSize(this.book.cover, event.width, event.height);
            })
            .onError(() => { this.imageLoadFailed = true; })
        } else if (this.book.cover && !this.book.cover.startsWith('http') && !this.isLocalFile(this.book.cover) && !this.imageLoadFailed) {
          Image($rawfile(this.book.cover))
            .width('100%')
            .aspectRatio(this.displayCoverRatio())
            .borderRadius(this.coverRadius)
            .objectFit(this.coverImageFit)
            .autoResize(true)
            .interpolation(ImageInterpolation.Medium)
            .onComplete((event) => {
              if (event?.loadingStatus === 0) this.rememberCoverSize(this.book.cover, event.width, event.height);
            })
            .onError(() => { this.imageLoadFailed = true; })
        } else {
          CoverImage({
            title: this.book.title,
            author: this.book.author,
            localPlaceholder: this.book.id.startsWith('import_') && !this.book.cover,
            imgWidth: '100%',
            aspectRatioValue: this.displayCoverRatio(),
            radius: this.coverRadius,
            themedDecoration: false,
            imageFit: this.coverImageFit
          })
        }

        CoverDecoration({ radius: this.coverRadius })

        Row().width('100%').height('100%').backgroundColor(Color.Black)
          .opacity(this.coverPressed ? 0.12 : 0)
          .animation({ duration: AppMotion.Fast, curve: AppCurve.Standard })
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')

        if (this.showSourceBadge && this.sourceName()) {
          Text(this.sourceName())
            .fontSize(10)
            .fontColor(Color.White)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#99000000')
            .borderRadius({ topRight: AppRadius.Sm, bottomLeft: this.coverRadius })
            .constraintSize({ maxWidth: this.showRating && BookMetadataPolicy.rating(this.book.rating, this.book.category) > 0 ? '65%' : '80%' })
        }
        if (this.showRating) {
          Row() {
            Blank()
            BookRatingBadge({ rating: BookMetadataPolicy.rating(this.book.rating, this.book.category),
              coverWidth: this.ratingCoverWidth, sizeScale: 0.7 })
          }.width('100%').hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .aspectRatio(this.displayCoverRatio())
      .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions): void => {
        const width = Number(newSize.width);
        if (width > 0) this.ratingCoverWidth = width;
      })
      .borderRadius(this.coverRadius)
      .clip(true)
      .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
      .id(this.transitionNodeId)
      .opacity(this.coverState.hiddenSourceId === this.transitionNodeId ? 0 : 1)

      Column({ space: 2 }) {
        Text(this.book.title)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.showLatestChapter && this.book.latestChapterTitle) {
          Text($r('app.string.source_latest_chapter', this.book.latestChapterTitle))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }
        Text(this.book.author)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .scale({
      x: this.appeared ? 1 : 0.97,
      y: this.appeared ? 1 : 0.97
    })
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : 12 })
    .animation({ duration: AppMotion.Base, curve: AppCurve.Emphasized })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 1 })
    .onTouch((event: TouchEvent): void => this.handleCoverTouch(event))
    .onClick(() => {
      this.openDetail();
    })
  }
}
