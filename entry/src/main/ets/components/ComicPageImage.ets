import { ComicPage, ComicReaderService } from '../service/ComicReaderService';
import { ComicImageLoader } from '../service/ComicImageLoader';
import { fileUri } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { AppColor } from '../theme/Theme';
import { ComicSuperResolutionService } from '../service/ComicSuperResolutionService';
import { MembershipState } from '../model/MembershipState';
import { ReaderCacheService } from '../service/ReaderCacheService';
import { ComicColorizationService } from '../service/ComicColorizationService';
import { ComicZoomTransform } from '../utils/ComicZoomGeometry';
import { ComicCropRect } from '../utils/ComicWhiteBorderGeometry';
import { ComicWhiteBorderService } from '../service/ComicWhiteBorderService';

@ComponentV2
export struct ComicPageImage {
  @Param page: ComicPage = new ComicPage();
  @Param pageWidth: number = 360;
  @Param pageHeight: number = 600;
  @Param viewportTop: number = 0;
  @Param zoomOwner: string = '';
  @Param paged: boolean = false;
  @Param fitScreen: boolean = false;
  // 0 保留原版布局；1 铺满可用宽度；2 完整显示；3 原图大小（只缩小，不放大）。
  @Param displayMode: number = 0;
  @Param trimWhiteBorder: boolean = false;
  @Local crop: ComicCropRect = new ComicCropRect();
  private cropSerial: number = 0;
  @Param autoPageRequest: number = 0;
  @Param autoPageActive: boolean = false;
  @Event onAutoPageEnd: () => void = (): void => {};
  @Event onAutoPageFailure: () => void = (): void => {};
  @Event onAutoPageDelay: () => void = (): void => {};
  private pageScroller: Scroller = new Scroller();
  @Param superResolution: boolean = false;
  @Param colorization: boolean = false;
  @Param translation: boolean = false;
  @Param translationDirection: string = 'ja-zh';
  @Param colorizationActive: boolean = true;
  @Event onColorError: (message: string) => void = () => {};
  @Local coloredUrl: string = '';
  @Local coloredWithTranslation: boolean = false;
  @Local colorBusy: boolean = false;
  private colorSerial: number = 0;
  private colorStartedAt: number = 0;
  private colorReadyAt: number = 0;
  private colorTrace: string = '';
  @Event onToggle: (event: ClickEvent) => void = () => {};
  @Event onZoomChange: (owner: string, active: boolean) => void = () => {};
  @Event onGeometryReady: () => void = () => {};
  @Local zoomState: ComicZoomTransform = new ComicZoomTransform();
  @Local zoomLocked: boolean = false;
  @Local decodeScale: number = 1;
  private gestureStart: ComicZoomTransform = new ComicZoomTransform();
  private pinchX: number = 0;
  private pinchY: number = 0;
  private imageWindowY: number = 0;
  private pinchSequence: boolean = false;
  @Local ratio: number = 0;
  @Local failed: boolean = false;
  @Local loaded: boolean = false;
  @Local retry: number = 0;
  @Local enhancedUrl: string = '';
  @Local membership: MembershipState = MembershipState.current;
  @Local enhancementFailed: boolean = false;
  @Local resolvedUrl: string = '';
  private visible: boolean = false;
  private alive: boolean = false;
  private imageSerial: number = 0;
  private pendingUrl: string = '';
  private imageRequested: boolean = false;
  private startedAt: number = 0;
  private displayLogged: boolean = false;
  private enhancementSerial: number = 0;
  private cacheOwner: string = ReaderCacheService.owner();

  private imageReadyHandler = (): void => {
    if (this.alive && !this.imageRequested &&
      (this.page.url.startsWith('file://') || this.page.url.startsWith('/'))) this.loadImage();
  };

  aboutToAppear(): void {
    this.alive = true;
    emitter.on('app.comic.image.ready', this.imageReadyHandler);
    this.loadImage();
  }

  aboutToDisappear(): void {
    this.resetZoom();
    this.alive = false;
    emitter.off('app.comic.image.ready', this.imageReadyHandler);
    this.visible = false;
    this.imageSerial++;
    this.enhancementSerial++;
    this.colorSerial++;
    this.cropSerial++;
    ReaderCacheService.release(this.cacheOwner);
  }

  @Monitor('page')
  onPageChanged(): void {
    this.ratio = 0;
    if (this.alive) this.loadImage();
  }

  @Monitor('autoPageRequest')
  private advanceAutoPage(): void {
    if (!this.alive || !this.autoPageActive || !this.paged || this.zoomLocked) return;
    if (this.failed) { this.onAutoPageFailure(); return; }
    if (!this.loaded) return;
    // 适宽长图先读完当前图片，不能直接切走遗漏下半部分。
    if (this.fitsViewport() || this.pageScroller.isAtEnd()) this.onAutoPageEnd();
    else this.pageScroller.scrollBy(0, this.pageHeight * 0.85);
  }

  @Monitor('loaded', 'failed')
  private syncAutoPageImage(): void {
    if (this.failed) this.onAutoPageFailure();
    else if (this.loaded) this.onAutoPageDelay();
  }

  private loadImage(): void {
    this.resetZoom();
    const page = this.page;
    page.trimWhiteBorderReady = false;
    const ticket = ++this.imageSerial;
    this.startedAt = Date.now();
    this.displayLogged = false;
    this.failed = false;
    this.loaded = false;
    this.cropSerial++;
    this.crop = new ComicCropRect();
    this.resolvedUrl = '';
    this.enhancedUrl = '';
    this.enhancementFailed = false;
    this.enhancementSerial++;
    this.colorSerial++;
    this.coloredUrl = '';
    this.colorBusy = false;
    this.colorReadyAt = 0;
    this.pendingUrl = page.url;
    this.imageRequested = false;
    // LazyForEach also creates offscreen cache nodes. They must not download ahead of the visible page.
    if (!this.visible && !page.url.startsWith('file://') && !page.url.startsWith('/')) return;
    this.imageRequested = true;
    const cancelled = (): boolean => !this.alive || ticket !== this.imageSerial;
    ComicImageLoader.load(page.sourceUrl, this.pendingUrl, cancelled, this.visible).then(async (path: string): Promise<void> => {
      if (cancelled()) return;
      await ComicReaderService.prepareImage(page, path);
      if (cancelled()) return;
      if (page.width > 0 && page.height > 0) this.ratio = page.height / page.width;
      const resolved = path.startsWith('/') ? fileUri.getUriFromPath(path) : path;
      if (this.trimWhiteBorder) {
        const crop = await ComicWhiteBorderService.inspect(resolved);
        if (cancelled()) return;
        // 等待解码时允许反复开关；结果属于当前图片，按最终开关值应用。
        if (this.trimWhiteBorder) this.crop = crop;
      }
      this.resolvedUrl = resolved;
      page.trimWhiteBorderReady = true;
      this.protectImage();
      this.onGeometryReady();
      this.enhance();
      this.colorize();
      const context = this.getUIContext().getHostContext();
      if (context) ComicReaderService.imageReady(page, path, context).catch((): void => {});
    }).catch((): void => {
      if (!cancelled()) {
        this.failed = true;
        page.trimWhiteBorderReady = true;
        this.onGeometryReady();
      }
    });
  }

  private protectImage(): void {
    if (this.visible) ReaderCacheService.protect(this.cacheOwner, [this.resolvedUrl, this.enhancedUrl, this.coloredUrl]);
    else ReaderCacheService.release(this.cacheOwner);
  }

  @Monitor('superResolution')
  onEnhancementChanged(): void {
    this.enhancedUrl = '';
    this.enhancementFailed = false;
    this.enhancementSerial++;
    this.protectImage();
    this.enhance();
  }

  private enhance(): void {
    if (this.colorization || this.translation || !this.visible || !this.resolvedUrl || !this.superResolution || this.enhancedUrl || this.enhancementFailed) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const ticket = ++this.enhancementSerial;
    const active = (): boolean => this.visible && this.superResolution && ticket === this.enhancementSerial;
    ComicSuperResolutionService.enhance(context, this.resolvedUrl, active,
      this.getUIContext().vp2px(this.imageWidth())).then((uri: string): void => {
      if (!active()) return;
      this.enhancedUrl = uri;
      this.protectImage();
      this.enhancementFailed = !uri;
    }).catch((): void => { if (active()) this.enhancementFailed = true; });
  }

  @Monitor('colorization', 'translation', 'translationDirection')
  private onColorizationChanged(): void {
    this.colorSerial++;
    this.colorBusy = false;
    this.coloredUrl = '';
    this.colorReadyAt = 0;
    if (this.colorization || this.translation) { this.enhancementSerial++; this.enhancedUrl = ''; }
    this.protectImage();
    this.colorize();
    if (!this.colorization && !this.translation) this.enhance();
  }

  @Monitor('colorizationActive')
  private onAiActiveChanged(): void {
    this.colorSerial++;
    this.colorBusy = false;
    this.colorize();
  }

  @Monitor('membership.developerAccess', 'membership.revalidating', 'membership.expiresAt',
    'membership.productId', 'membership.verifiedAt')
  private onAiMembershipChanged(): void {
    this.onColorizationChanged();
    this.onEnhancementChanged();
  }

  private colorize(): void {
    const translate = this.translation && this.membership.hasAccess;
    if (!this.membership.hasAccess || !this.alive || !this.visible || (!this.colorization && !translate) || !this.colorizationActive ||
      !this.resolvedUrl || this.coloredUrl || this.colorBusy) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const ticket = ++this.colorSerial;
    const trace = `${this.cacheOwner}-${ticket}`;
    const started = Date.now();
    this.colorStartedAt = started;
    this.colorTrace = trace;
    this.colorReadyAt = 0;
    this.coloredWithTranslation = translate;
    this.colorBusy = true;
    const active = (): boolean => this.alive && this.visible && this.membership.hasAccess &&
      (this.colorization || translate) && this.colorizationActive &&
      ticket === this.colorSerial;
    ComicColorizationService.transform(context, this.resolvedUrl, active,
      translate ? this.translationDirection : '', this.colorization, trace).then((path: string): void => {
      if (!active()) return;
      this.colorReadyAt = path ? Date.now() : 0;
      console.info(`[ComicAiView] trace=${trace} stage=result ready=${path.length > 0} total=${Date.now() - started}ms`);
      this.coloredUrl = path;
      this.protectImage();
    }).catch((error: Error): void => {
      if (active()) this.onColorError(error.message);
    }).finally((): void => { if (ticket === this.colorSerial) this.colorBusy = false; });
  }

  @Monitor('trimWhiteBorder')
  private async onTrimChanged(): Promise<void> {
    const ticket = ++this.cropSerial;
    this.page.trimWhiteBorderReady = false;
    this.resetZoom();
    if (!this.trimWhiteBorder) this.crop = new ComicCropRect();
    else if (this.resolvedUrl) {
      const crop = await ComicWhiteBorderService.inspect(this.resolvedUrl);
      if (!this.alive || ticket !== this.cropSerial) return;
      this.crop = crop;
    }
    this.page.trimWhiteBorderReady = !this.trimWhiteBorder || this.resolvedUrl.length > 0;
    this.onGeometryReady();
  }

  private originalRatio(): number {
    return this.ratio > 0 ? this.ratio : this.page.width > 0 && this.page.height > 0 ?
      this.page.height / this.page.width : 1.45;
  }

  private imageRatio(): number {
    return this.originalRatio() * this.crop.height / this.crop.width;
  }

  private fitsViewport(): boolean {
    return this.displayMode === 2 || (this.displayMode === 3 && this.paged) ||
      (this.displayMode === 0 && this.fitScreen);
  }

  private imageHeight(): number {
    // 分片连续拼接时高度必须落在物理像素上，避免逐片取整露出深色底。
    const ui = this.getUIContext();
    const height = this.imageWidth() * this.imageRatio();
    return ui.px2vp(Math.max(1, Math.round(ui.vp2px(height))));
  }

  private imageWidth(): number {
    let width = this.fitsViewport() ? Math.min(this.pageWidth, this.pageHeight / this.imageRatio()) : this.pageWidth;
    if (this.displayMode === 3 && this.page.width > 0) {
      width = Math.min(width, this.getUIContext().px2vp(this.page.width * this.crop.width));
    }
    return Math.max(1, width);
  }

  private contentHeight(): number {
    return this.paged && this.fitsViewport() ? this.pageHeight : this.imageHeight();
  }

  private imageX(): number { return this.zoomState.scale > 1 ? this.zoomState.x : (this.pageWidth - this.imageWidth()) / 2; }
  private imageY(): number { return this.zoomState.scale > 1 ? this.zoomState.y : (this.contentHeight() - this.imageHeight()) / 2; }

  private decodeWidth(): number {
    const ratio = this.originalRatio();
    const nativeWidth = this.page.width > 0 ? this.page.width * (this.enhancedUrl ? 4 : 1) : 1536;
    const enlarged = this.decodeScale > 1;
    return Math.max(1, Math.floor(Math.min(this.getUIContext().vp2px(this.imageWidth() / this.crop.width) * this.decodeScale,
      enlarged ? 4096 : 1536, (enlarged ? 8192 : 4096) / ratio,
      Math.sqrt((enlarged ? 8 : 4) * 1024 * 1024 / ratio), nativeWidth)));
  }

  @Monitor('pageWidth', 'pageHeight', 'viewportTop', 'fitScreen', 'displayMode')
  private onZoomLayoutChanged(): void { this.resetZoom(); }

  @Monitor('zoomOwner')
  private onZoomOwnerChanged(): void {
    if (this.zoomLocked && this.zoomOwner !== this.cacheOwner) this.resetZoom();
  }

  private resetZoom(): void {
    this.zoomState = new ComicZoomTransform();
    this.decodeScale = 1;
    this.pinchSequence = false;
    this.reportZoom();
  }

  private reportZoom(): void {
    const active = this.pinchSequence || this.zoomState.scale > 1;
    if (active === this.zoomLocked) return;
    this.zoomLocked = active;
    this.onZoomChange(this.cacheOwner, active);
  }

  private zoomTouch(event: TouchEvent): void {
    const touch = event.touches[0] ?? event.changedTouches[0];
    if (touch !== undefined && event.type === TouchType.Down) this.imageWindowY = touch.windowY - touch.y;
    if (event.touches.length > 1) this.pinchSequence = true;
    // 部分设备在 Up 的 touches 中仍包含刚抬起的触点，按 id 排除 changedTouches。
    const remaining = event.type === TouchType.Up ? event.touches.filter((point: TouchObject): boolean =>
      !event.changedTouches.some((changed: TouchObject): boolean => changed.id === point.id)).length : event.touches.length;
    if (event.type === TouchType.Cancel || (event.type === TouchType.Up && remaining === 0)) {
      this.pinchSequence = false;
    }
    this.reportZoom();
  }

  private beginPinch(event: GestureEvent): void {
    const top = this.viewportTop - this.imageWindowY;
    const bottom = top + this.pageHeight;
    this.gestureStart = this.paged && this.fitsViewport() ? (this.zoomState.scale > 1 ? this.zoomState :
      ComicZoomTransform.contain(this.imageWidth(), this.imageHeight(), this.pageWidth, this.pageHeight)) :
      this.zoomState.scale > 1 ? this.zoomState.viewport(top, bottom) :
        ComicZoomTransform.fit(this.imageWidth(), this.imageHeight(), top, bottom, this.pageWidth);
    this.pinchX = event.pinchCenterX;
    this.pinchY = event.pinchCenterY;
    this.updatePinch(event);
  }

  private updatePinch(event: GestureEvent): void {
    this.zoomState = this.gestureStart.zoom(this.gestureStart.scale * event.scale, this.pinchX, this.pinchY)
      .pan(event.pinchCenterX - this.pinchX, event.pinchCenterY - this.pinchY);
    this.reportZoom();
  }

  private finishPinch(): void {
    // 松手后再提高解码尺寸，避免每帧重解码；回到 1 倍即恢复原图位置与滚动。
    this.decodeScale = this.zoomState.scale;
    this.reportZoom();
  }

  private displayUrl(): string {
    return (this.membership.hasAccess ? this.coloredUrl || this.enhancedUrl : '') || this.resolvedUrl;
  }

  private decodeSize(): ImageSourceSize {
    const widthPx = this.decodeWidth();
    const heightPx = Math.max(1, Math.floor(widthPx * this.originalRatio()));
    const ui = this.getUIContext();
    // Image.sourceSize numbers are vp, while decoder budgets and native image dimensions are pixels.
    return { width: ui.px2vp(widthPx), height: ui.px2vp(heightPx) };
  }

  @Builder
  imageContent(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(this.displayUrl())
          .id(`${this.page.key}:${this.retry}`)
          .width(this.imageWidth() * this.zoomState.scale / this.crop.width)
          .height(this.imageHeight() * this.zoomState.scale / this.crop.height)
          .position({ x: -this.crop.x * this.imageWidth() * this.zoomState.scale / this.crop.width,
            y: -this.crop.y * this.imageHeight() * this.zoomState.scale / this.crop.height })
          .draggable(false)
          // 容器已按原图比例计算；Fill 消除解码宽高取整造成的亚像素留边。
          .objectFit(ImageFit.Fill)
          .syncLoad(false)
          .autoResize(true)
          .sourceSize(this.decodeSize())
          .onComplete((event) => {
            if (event && event.width > 0 && event.height > 0) {
              if (this.coloredUrl && this.colorReadyAt > 0 && event.loadingStatus === 1) {
                console.info(`[ComicAiView] trace=${this.colorTrace} stage=image-complete ` +
                  `display=${Date.now() - this.colorReadyAt}ms total=${Date.now() - this.colorStartedAt}ms`);
                this.colorReadyAt = 0;
              }
              if (!this.coloredUrl && !this.enhancedUrl && this.ratio <= 0) this.ratio = event.height / event.width;
              // 懒加载节点回收后仍保留已知比例，避免回滚时先按占位高度再跳一次。
              if (!this.coloredUrl && !this.enhancedUrl && this.page.width <= 0) {
                this.page.width = event.width; this.page.height = event.height;
              }
              this.loaded = true;
              if (!this.displayLogged) {
                this.displayLogged = true;
                hilog.info(0x0001, 'ComicReader', 'image displayed page=%{public}d ms=%{public}d',
                  this.page.index + 1, Date.now() - this.startedAt);
              }
            }
          })
          .onError(() => {
            if (this.coloredUrl) { this.coloredUrl = ''; this.onColorError('comic_ai_invalid_image'); }
            else if (this.enhancedUrl) { this.enhancedUrl = ''; this.enhancementFailed = true; }
            else this.failed = true;
          })
          .accessibilityText($r('app.string.comic_page_number', this.page.index + 1))
      }.width(this.imageWidth() * this.zoomState.scale).height(this.imageHeight() * this.zoomState.scale)
        .position({ x: this.imageX(), y: this.imageY() }).clip(true)
      if (this.colorBusy) {
        Row({ space: 6 }) {
          LoadingProgress().width(18).height(18).color(AppColor.Brand)
          Text(this.coloredWithTranslation && this.colorization ? $r('app.string.comic_ai_color_translate_working') :
            this.coloredWithTranslation ? $r('app.string.comic_ai_translate_working') : $r('app.string.comic_ai_color_working'))
            .fontSize(12).fontColor(Color.White)
        }.padding(8).backgroundColor('#99000000').borderRadius(12).margin({ top: 8, left: 8 })
          .hitTestBehavior(HitTestMode.None)
      }
    }.width(this.pageWidth).height(this.contentHeight()).clip(true)
      .onTouch((event: TouchEvent): void => this.zoomTouch(event))
      .priorityGesture(GestureGroup(GestureMode.Exclusive,
        PinchGesture({ fingers: 2 })
          .onActionStart((event: GestureEvent): void => this.beginPinch(event))
          .onActionUpdate((event: GestureEvent): void => this.updatePinch(event))
          .onActionEnd((): void => this.finishPinch())
          .onActionCancel((): void => this.finishPinch()),
        PanGesture({ fingers: 1, direction: PanDirection.All }).tag('comic-image-pan')
          .onActionStart((): void => { this.gestureStart = this.zoomState; })
          .onActionUpdate((event: GestureEvent): void => {
            this.zoomState = this.gestureStart.pan(event.offsetX, event.offsetY);
          })
      ))
      .onGestureJudgeBegin((info: GestureInfo): GestureJudgeResult =>
        info.tag === 'comic-image-pan' && (this.zoomState.scale <= 1 || this.pinchSequence) ?
          GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE)
  }

  build() {
    Stack() {
      if (!this.loaded && !this.failed) {
        LoadingProgress().width(28).height(28).color(AppColor.Brand)
      }
      if (this.failed) {
        Column({ space: 12 }) {
          Text($r('app.string.comic_image_failed', this.page.index + 1)).fontColor('#CCCCCC').fontSize(14)
          Button($r('app.string.comic_retry')).backgroundColor(AppColor.Brand).fontColor(Color.White)
            .onClick(() => { this.retry++; this.loadImage(); })
        }
      } else if (this.resolvedUrl && this.fitsViewport()) {
        this.imageContent()
      } else if (this.resolvedUrl && this.paged) {
        Scroll(this.pageScroller) {
          this.imageContent()
        }.width(this.pageWidth).height(this.pageHeight)
          .scrollable(ScrollDirection.Vertical).scrollBar(BarState.Off).enableScrollInteraction(!this.zoomLocked)
      } else if (this.resolvedUrl) {
        // 连续模式由外层 List 统一滚动，不为每张长图创建一个禁用滚动的 Scroll。
        this.imageContent()
      }

    }
    .width(this.pageWidth).height(this.paged ? this.pageHeight : this.imageHeight()).clip(true)
    .backgroundColor('#121212')
    .onVisibleAreaChange([0.01], (_visible: boolean, ratio: number) => {
      const visible = ratio > 0;
      if (this.visible === visible) return;
      this.visible = visible;
      if (this.colorization || this.translation) {
        console.info(`[ComicAiView] owner=${this.cacheOwner} stage=visibility visible=${visible} resolved=${this.resolvedUrl.length > 0}`);
      }
      this.protectImage();
      if (visible) {
        if (!this.imageRequested) this.loadImage();
        else ComicImageLoader.promote(this.page.sourceUrl, this.pendingUrl);
        this.enhance();
        this.colorize();
      }
      else { this.resetZoom(); this.enhancementSerial++; this.colorSerial++; this.colorBusy = false; }
    })
  }
}
