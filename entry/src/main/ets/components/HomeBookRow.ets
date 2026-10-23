import { SearchResult } from '../model/BookSource';
import { BookRatingBadge } from './BookRatingBadge';
import { BookMetadataPolicy } from '../utils/BookMetadataPolicy';
import { AppColor, AppRadius, AppSpace, AppFont, AppTheme } from '../theme/Theme';
import { CoverImage } from './CoverImage';
import { BOOK_COVER_ASPECT_RATIO, CoverAspectRatio } from '../utils/CoverAspectRatio';
import { OneShotCoverState, OneShotTransitionCoordinator, OneShotTransitionIds } from '../utils/OneShotTransition';

export const FEATURED_ROW_HEIGHT: number = 84;
export const FEATURED_COVER_HEIGHT: number = 72;
export const FEATURED_COVER_WIDTH: number = FEATURED_COVER_HEIGHT * BOOK_COVER_ASPECT_RATIO;

/** 每个行组件独立持有封面节点，重复书籍也只从实际点击的这一行转场。 */
@ComponentV2
export struct HomeBookRow {
  @Param result: SearchResult = {
    name: '', author: '', coverUrl: '', bookUrl: '', intro: '', kind: '',
    lastChapter: '', sourceName: '', sourceUrl: ''
  };
  @Param featured: boolean = false;
  @Param showDivider: boolean = false;
  @Param favorite: boolean = false;
  @Param savingFavorite: boolean = false;
  @Event onOpen: (result: SearchResult, nodeId: string, radius: number) => void = () => {};
  @Event onFavorite: (result: SearchResult) => void = () => {};
  @Local coverState: OneShotCoverState = OneShotTransitionCoordinator.getInstance().coverState;
  @Local coverRatio: number = BOOK_COVER_ASPECT_RATIO;
  private nodeId: string = OneShotTransitionIds.nextSourceId('home-row');

  aboutToAppear(): void {
    this.coverRatio = CoverAspectRatio.get(this.result.coverUrl, BOOK_COVER_ASPECT_RATIO);
  }

  @Monitor('result')
  onResultChanged(): void {
    this.coverRatio = CoverAspectRatio.get(this.result.coverUrl, BOOK_COVER_ASPECT_RATIO);
  }

  private coverWidth(): number {
    return CoverAspectRatio.fittedWidth(this.coverRatio, 72,
      this.featured ? FEATURED_COVER_HEIGHT : 96);
  }

  private coverHeight(): number {
    return this.coverWidth() / this.coverRatio;
  }

  private rememberCoverSize(url: string, width: number, height: number): void {
    if (url !== this.result.coverUrl) return;
    CoverAspectRatio.remember(url, width, height);
    this.coverRatio = CoverAspectRatio.get(url, BOOK_COVER_ASPECT_RATIO);
  }

  build() {
    if (this.featured) {
      this.buildFeaturedRow(this.result, this.showDivider)
    } else {
      this.buildListRow(this.result)
    }
  }

  @Builder
  ratingBadge(result: SearchResult) {
    BookRatingBadge({ rating: BookMetadataPolicy.rating(result.rating, result.kind), coverWidth: this.coverWidth() })
  }

  @Builder
  buildFeaturedRow(r: SearchResult, showDivider: boolean) {
    Column() {
      Row({ space: AppSpace.Sm }) {
        Stack() {
          if (r.coverUrl && r.coverUrl.startsWith('http')) {
            CoverImage({
              url: r.coverUrl,
              imgWidth: this.coverWidth(),
              imgHeight: this.coverHeight(),
              useFixedHeight: true,
              imageFit: ImageFit.Contain,
              radius: AppRadius.Sm,
              decodeW: 162,
              decodeH: 216,
              highPriority: true,
              onImageSize: (url: string, width: number, height: number): void =>
                this.rememberCoverSize(url, width, height)
            })
          } else {
            CoverImage({
              title: AppTheme.IllustratedPlaceholders ? r.name : '',
              author: AppTheme.IllustratedPlaceholders ? r.author : '',
              imgWidth: this.coverWidth(),
              imgHeight: this.coverHeight(),
              useFixedHeight: true,
              radius: AppRadius.Sm
            })
          }
        }
        .width(this.coverWidth()).height(this.coverHeight())
        .overlay(this.ratingBadge(r), { align: Alignment.BottomEnd })
        .id(this.nodeId)
        .opacity(this.coverState.hiddenSourceId === this.nodeId ? 0 : 1)

        Column({ space: AppSpace.Xxs }) {
          Text(r.name)
            .fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary'))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (r.author) {
            Text(r.author)
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.favorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
            .fontSize(22)
            .fontColor([this.favorite ? AppColor.Brand : $r('sys.color.font_secondary')])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .enabled(!this.savingFavorite)
        .accessibilityText(this.favorite ?
          $r('app.string.home_favorite_remove') : $r('app.string.home_favorite_add'))
        .onClick(() => {
          this.onFavorite(r);
        })
      }
      .width('100%')
      .height(FEATURED_ROW_HEIGHT - 1)
      .alignItems(VerticalAlign.Center)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.99 })
      .onClick(() => {
        this.onOpen(r, this.nodeId, AppRadius.Sm);
      })

      if (showDivider) {
        Divider()
          .color(AppColor.Divider)
          .margin({ left: this.coverWidth() + AppSpace.Sm })
      }
    }
    .width('100%')
    .height(FEATURED_ROW_HEIGHT)
  }

  @Builder
  buildListRow(r: SearchResult) {
    Row({ space: AppSpace.Md }) {
      Stack() {
        if (r.coverUrl && r.coverUrl.startsWith('http')) {
          CoverImage({
            url: r.coverUrl,
            imgWidth: this.coverWidth(),
            imgHeight: this.coverHeight(),
            useFixedHeight: true,
            imageFit: ImageFit.Contain,
            radius: AppRadius.Sm,
            decodeW: 216,
            decodeH: 288,
            highPriority: true,
            onImageSize: (url: string, width: number, height: number): void =>
              this.rememberCoverSize(url, width, height)
          })
        } else if (AppTheme.IllustratedPlaceholders) {
          CoverImage({ title: r.name, author: r.author,
            imgWidth: this.coverWidth(), imgHeight: this.coverHeight(), useFixedHeight: true,
            radius: AppRadius.Sm })
        } else {
          Stack() {
            Column().width('100%').height('100%').backgroundColor($r('sys.color.brand'))
            Text(r.name ? r.name.substring(0, 1) : '?')
              .fontSize(24).fontColor($r('sys.color.font_on_primary')).fontWeight(FontWeight.Bold)
          }
          .width(this.coverWidth()).height(this.coverHeight()).borderRadius(AppRadius.Sm).clip(true)
        }
      }
      .width(this.coverWidth()).height(this.coverHeight())
      .overlay(this.ratingBadge(r), { align: Alignment.BottomEnd })
      .id(this.nodeId)
      .opacity(this.coverState.hiddenSourceId === this.nodeId ? 0 : 1)

      Column({ space: 4 }) {
        Text(r.name)
          .fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (r.author) {
          Text(r.author)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        if (r.intro) {
          Text(r.intro)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ top: AppSpace.Xs, bottom: AppSpace.Xs })
    .onClick(() => {
      this.onOpen(r, this.nodeId, AppRadius.Sm);
    })
  }

}
