import { PhysicalBookCover, PHYSICAL_BOOK_COVER_RADIUS } from './PhysicalBookCover';
import { ShelfReaderOpenState } from '../utils/ShelfReaderTransition';

@ComponentV2
export struct ShelfReaderOpenSurface {
  @Param motion: ShelfReaderOpenState = new ShelfReaderOpenState();
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent(): void {}

  aboutToDisappear(): void {
    this.motion.dispose();
  }

  @LocalBuilder
  bookLeaf() {
    Stack({ alignContent: Alignment.Start }) {
      PhysicalBookCover({ url: this.motion.cover, title: this.motion.title, author: this.motion.author,
        localPlaceholder: this.motion.localPlaceholder, imgWidth: '100%', imgHeight: '100%',
        useFixedHeight: true, eagerLoad: true, interpolationQuality: ImageInterpolation.High })
        .opacity(this.motion.frontAlpha)
      Stack() {
        Row().width('100%').height('100%')
          .backgroundColor($r('sys.color.comp_background_primary'))
        Row().width('100%').height('100%')
          .linearGradient({ direction: GradientDirection.Right,
            colors: [['#35000000', 0], ['#0D000000', 0.08], ['#00FFFFFF', 0.28], ['#12FFFFFF', 1]] })
      }.width('100%').height('100%').opacity(this.motion.insideAlpha)
    }.width(this.motion.coverWidth).height(this.motion.coverHeight)
      .borderRadius(PHYSICAL_BOOK_COVER_RADIUS).clip(true)
      .shadow({ radius: this.motion.coverShadow, color: '#33000000', offsetY: this.motion.coverShadow * 0.4 })
      .renderGroup(true)
      .rotate({ x: 0, y: 1, z: 0, angle: this.motion.coverAngle,
        centerX: '0%', centerY: '50%', perspective: this.motion.coverWidth * 8 })
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
  }

  @LocalBuilder
  openingCover() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.bookLeaf()
    }.width(this.motion.coverWidth).height(this.motion.coverHeight)
      .scale({ x: this.motion.coverScale, y: this.motion.coverScale, centerX: '0%', centerY: '0%' })
      .translate({ x: this.motion.offsetX, y: this.motion.offsetY })
      .opacity(this.motion.coverAlpha)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
  }

  @LocalBuilder
  paperEdge() {
    Row().width(this.motion.pageWidth + 2).height(this.motion.pageHeight)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .border({ width: 0.7, color: '#28000000' }).borderRadius(this.motion.pageRadius)
      .shadow({ radius: 18, color: '#24000000', offsetY: 8 })
      .translate({ x: this.motion.pageX, y: this.motion.pageY })
      .opacity(this.motion.paperAlpha)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.motion.active) {
        this.paperEdge()
      }
      Stack({ alignContent: Alignment.TopStart }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.content()
        }.width(this.motion.active ? this.motion.viewportWidth : '100%')
          .height(this.motion.active ? this.motion.viewportHeight : '100%')
          .translate({ x: this.motion.active ? -this.motion.pageX : 0,
            y: this.motion.active ? -this.motion.pageY : 0 })
      }.width(this.motion.active ? this.motion.pageWidth : '100%')
        .height(this.motion.active ? this.motion.pageHeight : '100%')
        .translate({ x: this.motion.active ? this.motion.pageX : 0,
          y: this.motion.active ? this.motion.pageY : 0 })
        .borderRadius(this.motion.active ? this.motion.pageRadius : 0)
        .renderFit(RenderFit.TOP_LEFT).clip(true).opacity(this.motion.bodyAlpha)
      if (this.motion.active) {
        Row().width(32).height(this.motion.pageHeight)
          .linearGradient({ direction: GradientDirection.Right,
            colors: [['#80000000', 0], ['#28000000', 0.3], ['#00000000', 1]] })
          .translate({ x: this.motion.pageX, y: this.motion.pageY }).opacity(this.motion.spineAlpha)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
        this.openingCover()
      }
    }.width('100%').height('100%').id(ShelfReaderOpenState.SURFACE_ID)
      .enabled(!this.motion.active).clip(true)
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
        [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
      .onSizeChange((): void => this.motion.viewportChanged())
  }
}
