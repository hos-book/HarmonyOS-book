import { fileUri } from '@kit.CoreFileKit';
import { EpubPageStyle } from '../service/text/EpubPageStyle';
import { LocalTextImage } from '../service/text/LocalTextImage';

/** 书内背景铺在正文下方，不占用正文排版高度。 */
@ComponentV2
export struct EpubPageBackground {
  @Param style: EpubPageStyle = new EpubPageStyle();

  private repeat(): ImageRepeat {
    if (this.style.repeat === 'no-repeat') return ImageRepeat.NoRepeat;
    if (this.style.repeat === 'repeat-x') return ImageRepeat.X;
    if (this.style.repeat === 'repeat-y') return ImageRepeat.Y;
    return ImageRepeat.XY;
  }

  private imagePosition(): Alignment {
    if (this.style.position === 'top left') return Alignment.TopStart;
    if (this.style.position === 'top center') return Alignment.Top;
    if (this.style.position === 'top right') return Alignment.TopEnd;
    if (this.style.position === 'center left') return Alignment.Start;
    if (this.style.position === 'center right') return Alignment.End;
    if (this.style.position === 'bottom left') return Alignment.BottomStart;
    if (this.style.position === 'bottom center') return Alignment.Bottom;
    if (this.style.position === 'bottom right') return Alignment.BottomEnd;
    return Alignment.Center;
  }

  build() {
    Stack() {
      if (this.style.color) {
        Column().width('100%').height('100%').backgroundColor(this.style.color)
      }
      if (LocalTextImage.resolve(this.style.image)) {
        Column().width('100%').height('100%')
          .backgroundImage(fileUri.getUriFromPath(this.style.image), this.repeat())
          .backgroundImageSize(this.style.size === 'cover' ? ImageSize.Cover :
            this.style.size === 'contain' ? ImageSize.Contain : ImageSize.Auto)
          .backgroundImagePosition(this.imagePosition())
      }
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.None).clip(true)
  }
}
