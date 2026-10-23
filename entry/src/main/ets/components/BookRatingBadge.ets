import { BookMetadataPolicy } from '../utils/BookMetadataPolicy';

/** 封面评分角标；由父级放在右下角，无真实评分时不创建内容。 */
@ComponentV2
export struct BookRatingBadge {
  @Param rating: number = 0;
  @Param coverWidth: number = 100;

  private scaled(value: number): number {
    return value * this.coverWidth / 100;
  }

  build() {
    if (BookMetadataPolicy.rating(this.rating) > 0) {
      Text(this.rating.toFixed(1))
        .fontSize(`${this.scaled(12)}vp`)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .padding({ left: this.scaled(5), right: this.scaled(5), top: this.scaled(2), bottom: this.scaled(2) })
        .backgroundColor('#B3000000')
        .borderRadius(this.scaled(6))
        .margin(this.scaled(4))
        .maxLines(1)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityText($r('app.string.book_detail_score', this.rating.toFixed(1)))
    }
  }
}
