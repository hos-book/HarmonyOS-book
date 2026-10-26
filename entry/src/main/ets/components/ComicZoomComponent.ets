import { ComicZoomTransform } from '../utils/ComicZoomGeometry';
import { ReaderCacheService } from '../service/ReaderCacheService';
import { AppColor } from '../theme/Theme';

/** 独立全屏图片视口，拖动与缩放不交给底层 List/Swiper 翻页。 */
@ComponentV2
export struct ComicZoomComponent {
  @Param url: string = '';
  @Param imageRatio: number = 1;
  @Param focusY: number = 0.5;
  @Param topSafe: number = 0;
  @Param bottomSafe: number = 0;
  @Event onClose: () => void = () => {};
  @Local zoomState: ComicZoomTransform = new ComicZoomTransform();
  @Local loaded: boolean = false;
  @Local failed: boolean = false;
  @Local initialized: boolean = false;
  private gestureStart: ComicZoomTransform = new ComicZoomTransform();
  private pinchX: number = 0;
  private pinchY: number = 0;
  private cacheOwner: string = ReaderCacheService.owner();

  aboutToAppear(): void { ReaderCacheService.protect(this.cacheOwner, [this.url]); }
  aboutToDisappear(): void { ReaderCacheService.release(this.cacheOwner); }

  private decodeSize(): ImageSourceSize {
    const ratio = Math.max(0.01, this.imageRatio);
    const width = Math.max(1, Math.floor(Math.min(4096, 8192 / ratio, Math.sqrt(8 * 1024 * 1024 / ratio))));
    const ui = this.getUIContext();
    return { width: ui.px2vp(width), height: ui.px2vp(Math.max(1, Math.floor(width * ratio))) };
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.initialized) {
          Image(this.url).width(this.zoomState.width()).height(this.zoomState.height())
            .position({ x: this.zoomState.x, y: this.zoomState.y })
            .objectFit(ImageFit.Fill).sourceSize(this.decodeSize()).syncLoad(false).draggable(false)
            .hitTestBehavior(HitTestMode.None)
            .onComplete((): void => { this.loaded = true; })
            .onError((): void => { this.failed = true; })
        }
      }.width('100%').height('100%').clip(true)
        .gesture(GestureGroup(GestureMode.Exclusive,
          PinchGesture({ fingers: 2 })
            .onActionStart((event: GestureEvent): void => {
              this.gestureStart = this.zoomState;
              this.pinchX = event.pinchCenterX;
              this.pinchY = event.pinchCenterY;
            })
            .onActionUpdate((event: GestureEvent): void => {
              this.zoomState = this.gestureStart.zoom(this.gestureStart.scale * event.scale, this.pinchX, this.pinchY)
                .pan(event.pinchCenterX - this.pinchX, event.pinchCenterY - this.pinchY);
            }),
          PanGesture({ fingers: 1, direction: PanDirection.All })
            .onActionStart((): void => { this.gestureStart = this.zoomState; })
            .onActionUpdate((event: GestureEvent): void => {
              this.zoomState = this.gestureStart.pan(event.offsetX, event.offsetY);
            }),
          TapGesture({ count: 2 }).onAction((event: GestureEvent): void => {
            const finger = event.fingerList[0];
            if (finger) this.zoomState = this.zoomState.zoom(this.zoomState.scale > 1 ? 1 : 2,
              finger.localX, finger.localY);
          })
        ))
      if (!this.loaded && !this.failed) {
        LoadingProgress().width(32).height(32).color(AppColor.Brand).align(Alignment.Center)
      }
      if (this.failed) {
        Text($r('app.string.comic_zoom_failed')).fontColor(Color.White).fontSize(16).align(Alignment.Center)
      }
      Row({ space: 12 }) {
        Button($r('app.string.comic_zoom_close')).backgroundColor('#404040').fontColor(Color.White)
          .onClick((): void => this.onClose())
        Blank()
        Text($r('app.string.comic_zoom_scale', Math.round(this.zoomState.scale * 100))).fontColor(Color.White)
        Button($r('app.string.comic_zoom_reset')).backgroundColor('#404040').fontColor(Color.White).onClick((): void => {
          this.zoomState = this.zoomState.zoom(1, this.zoomState.viewportWidth / 2, this.zoomState.viewportHeight / 2);
        })
      }.width('100%').padding({ left: 16, right: 16, top: this.topSafe + 8, bottom: 8 })
        .backgroundColor('#AA121212')
      Text($r('app.string.comic_zoom_hint')).fontSize(12).fontColor(Color.White)
        .padding(12).backgroundColor('#AA121212').borderRadius(12).align(Alignment.Bottom)
        .margin({ bottom: this.bottomSafe + 16 }).hitTestBehavior(HitTestMode.None)
    }.width('100%').height('100%').backgroundColor('#121212')
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((_old, area): void => {
        const width = Number(area.width);
        const height = Number(area.height);
        if (width <= 0 || height <= 0) return;
        this.zoomState = this.initialized ? this.zoomState.resize(width, height) :
          ComicZoomTransform.open(width, height, this.imageRatio, this.focusY);
        this.initialized = true;
      })
  }
}
