import { CoverImage } from './CoverImage';
import { ShelfReaderOpenState } from '../utils/ShelfReaderTransition';

@ComponentV2
export struct ShelfReaderOpenSurface {
  @Param motion: ShelfReaderOpenState = new ShelfReaderOpenState();
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent(): void {}

  aboutToDisappear(): void {
    this.motion.complete();
  }

  @Builder
  openingCover() {
    Stack({ alignContent: Alignment.Start }) {
      if (this.motion.cover) {
        if (this.motion.cover.startsWith('http') || this.motion.cover.startsWith('file://') ||
          this.motion.cover.startsWith('/data/')) {
          CoverImage({ url: this.motion.cover, title: this.motion.title,
            imgWidth: '100%', imgHeight: '100%', useFixedHeight: true, radius: 0,
            themedDecoration: false, themeBundleId: 'default', eagerLoad: true })
        } else {
          Image($rawfile(this.motion.cover)).width('100%').height('100%')
            .objectFit(ImageFit.Cover).draggable(false)
        }
      } else {
        Text(this.motion.title).fontSize(28).fontWeight(FontWeight.Medium)
          .fontColor('#FFF8EB').textAlign(TextAlign.Center)
          .maxLines(5).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%').padding(40)
      }
    }.width('100%').height('100%').backgroundColor('#344B4D').borderRadius(2).clip(true)
      .renderGroup(true)
      .rotate({ x: 0, y: 1, z: 0, angle: this.motion.coverAngle,
        centerX: '0%', centerY: '50%', perspective: 1800 })
      .opacity(this.motion.coverAlpha)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.content()
      }.width('100%').height('100%').opacity(this.motion.bodyAlpha)
      if (this.motion.active) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.openingCover()
        }.width('100%').height('100%')
          .scale({ x: this.motion.zoomX, y: this.motion.zoomY, centerX: '0%', centerY: '0%' })
          .translate({ x: this.motion.offsetX, y: this.motion.offsetY })
          .hitTestBehavior(HitTestMode.None)
      }
    }.width('100%').height('100%').id(ShelfReaderOpenState.SURFACE_ID)
      .enabled(!this.motion.active)
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
        [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
      .onSizeChange((): void => this.motion.viewportChanged())
  }
}
