import { ThemePageBackdrop } from '../model/ThemeDocument';

@ComponentV2
export struct ThemeBackdropComponent {
  @Param backdrop: ThemePageBackdrop = new ThemePageBackdrop();
  @Param night: boolean = false;
  @Local viewportWidth: number = 1;
  @Local viewportHeight: number = 1;
  @Local sourceWidth: number = 1;
  @Local sourceHeight: number = 1;

  private imageWidth(): number {
    return this.sourceWidth * Math.max((this.viewportWidth + this.backdrop.blur * 4) / this.sourceWidth,
      (this.viewportHeight + this.backdrop.blur * 4) / this.sourceHeight) * this.backdrop.scale / 100;
  }

  private imageHeight(): number {
    return this.sourceHeight * Math.max((this.viewportWidth + this.backdrop.blur * 4) / this.sourceWidth,
      (this.viewportHeight + this.backdrop.blur * 4) / this.sourceHeight) * this.backdrop.scale / 100;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.backdrop.mode === 'image' && this.backdrop.image.length > 0) {
        Image(this.backdrop.image).width(this.imageWidth()).height(this.imageHeight()).objectFit(ImageFit.Fill)
          .position({ x: (this.viewportWidth - this.imageWidth()) * this.backdrop.positionX / 100,
            y: (this.viewportHeight - this.imageHeight()) * this.backdrop.positionY / 100 })
          .blur(this.backdrop.blur)
          .onComplete((event): void => {
            if (event && event.width > 0 && event.height > 0) {
              this.sourceWidth = event.width;
              this.sourceHeight = event.height;
            }
          })
      }
      Column().width('100%').height('100%').backgroundColor(this.night ? '#0D0D0D' : '#FFFFFF')
        .opacity(this.backdrop.veil / 100)
    }.width('100%').height('100%').clip(true).backgroundColor(this.backdrop.color)
      .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS).accessibilityLevel('no')
      .onSizeChange((_previous: SizeOptions, current: SizeOptions): void => {
        this.viewportWidth = Number(current.width);
        this.viewportHeight = Number(current.height);
      })
  }
}
