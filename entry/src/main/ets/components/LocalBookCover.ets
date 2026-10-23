import { AppRadius } from '../theme/Theme';
import { CoverTheme } from '../theme/CoverTheme';
import { CoverDecoration } from './CoverDecoration';

/** 本地无封面书籍的实时排版，不把占位图写入用户封面字段。 */
@ComponentV2
export struct LocalBookCover {
  @Param title: string = '';
  @Param author: string = '';
  @Param imgWidth: Length = '100%';
  @Param imgHeight: Length = 0;
  @Param useFixedHeight: boolean = false;
  @Param aspectRatioValue: number = 0.75;
  @Param radius: number = AppRadius.Md;
  @Param themedDecoration: boolean = true;
  @Param themeBundleId: string = '';
  @Local measuredWidth: number = 100;

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Image(CoverTheme.localPlaceholder(this.themeBundleId))
        .width('100%').height('100%').objectFit(ImageFit.Fill).draggable(false)
        .borderRadius(this.radius).clip(true)
      Column() {
        Blank().height('22%')
        Text(this.title)
          .fontSize(Math.min(28, this.measuredWidth * 0.125))
          .fontWeight(FontWeight.Bold).fontColor(CoverTheme.titleColor(true, this.themeBundleId))
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center).width('72%').height('32%')
          .copyOption(CopyOptions.None).draggable(false)
        Blank().height('12%')
        Text(this.author)
          .fontSize(Math.min(18, this.measuredWidth * 0.085))
          .fontColor(CoverTheme.authorColor(this.themeBundleId)).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center).width('68%').height('14%')
          .copyOption(CopyOptions.None).draggable(false)
      }.width('100%').height('100%')
      if (this.themedDecoration) {
        CoverDecoration({ radius: this.radius, themeBundleId: this.themeBundleId })
      }
    }
    .width(this.imgWidth)
    .height(this.useFixedHeight ? this.imgHeight : undefined)
    .aspectRatio(this.useFixedHeight ? undefined : this.aspectRatioValue)
    .borderRadius(this.radius).clip(true)
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions): void => {
      this.measuredWidth = Number(newValue.width);
    })
    .accessibilityText(`${this.title} ${this.author}`)
  }
}
