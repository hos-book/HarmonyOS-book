import { CoverImage } from './CoverImage';

/** 书架与阅听足迹共用固定长方形书体，原图片只作等比裁切。 */
export const PHYSICAL_BOOK_COVER_RATIO: number = 0.7;
export const PHYSICAL_BOOK_COVER_RADIUS: number = 1.2;
const PAPER_EDGE_WIDTH: number = 2;

@ComponentV2
export struct PhysicalBookCover {
  @Param url: string = '';
  @Param title: string = '';
  @Param author: string = '';
  @Param localPlaceholder: boolean = false;
  @Param imgWidth: Length = '100%';
  @Param imgHeight: Length = 0;
  @Param useFixedHeight: boolean = false;
  @Param eagerLoad: boolean = false;
  @Param antialiasEdges: boolean = false;
  @Param interpolationQuality: ImageInterpolation = ImageInterpolation.Medium;
  @Param showImage: boolean = true;
  @BuilderParam overlayContent: () => void = this.emptyContent;

  @Builder
  emptyContent(): void {}

  private imageUrl(): string {
    return this.url.startsWith('/') ? `file://${this.url}` : this.url;
  }

  @LocalBuilder
  imageContent() {
    if (this.url && !this.url.startsWith('http') && !this.url.startsWith('file://') && !this.url.startsWith('/')) {
      Image($rawfile(this.url)).width('100%').height('100%').objectFit(ImageFit.Cover)
        .draggable(false).autoResize(true).interpolation(this.interpolationQuality)
        .alt($r('app.media.app_icon_legacy'))
    } else {
      CoverImage({ url: this.imageUrl(), title: this.title, author: this.author,
        localPlaceholder: this.localPlaceholder, imgWidth: '100%', imgHeight: '100%', useFixedHeight: true,
        radius: 0, themedDecoration: false, themeBundleId: 'default', imageFit: ImageFit.Cover,
        eagerLoad: this.eagerLoad, antialiasEdges: this.antialiasEdges,
        interpolationQuality: this.interpolationQuality })
    }
  }

  build() {
    Row() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.showImage) this.imageContent()
        Row().width('14%').height('100%')
          .linearGradient({ direction: GradientDirection.Right,
            colors: [['#4D000000', 0], ['#17000000', 0.18], ['#30FFFFFF', 0.34],
              ['#0CFFFFFF', 0.5], ['#26000000', 0.67], ['#00000000', 1]] })
          .accessibilityLevel('no')
        Row().width('100%').height('100%')
          .border({ width: 0.4, color: '#29000000', radius: PHYSICAL_BOOK_COVER_RADIUS })
          .accessibilityLevel('no')
        this.overlayContent()
      }.layoutWeight(1).height('100%').borderRadius(PHYSICAL_BOOK_COVER_RADIUS).clip(true)
      Column() {
        Row().width('100%').layoutWeight(1)
          .linearGradient({ direction: GradientDirection.Right,
            colors: [['#F8F4EB', 0], ['#C8C0B2', 0.3], ['#E7E1D5', 0.62], ['#B0A697', 1]] })
          .borderRadius({ topRight: 0.6, bottomRight: 0.6 })
      }.width(PAPER_EDGE_WIDTH).height('100%').padding({ top: 1, bottom: 0.8 }).accessibilityLevel('no')
    }.width(this.imgWidth).height(this.useFixedHeight ? this.imgHeight : undefined)
      .aspectRatio(this.useFixedHeight ? undefined : PHYSICAL_BOOK_COVER_RATIO)
      .shadow({ radius: 2.5, color: '#26000000', offsetX: 0.8, offsetY: 1.8 })
      .hitTestBehavior(HitTestMode.None)
  }
}
