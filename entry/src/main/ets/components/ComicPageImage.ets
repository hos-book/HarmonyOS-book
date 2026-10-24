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

@ComponentV2
export struct ComicPageImage {
  @Param page: ComicPage = new ComicPage();
  @Param pageWidth: number = 360;
  @Param pageHeight: number = 600;
  @Param paged: boolean = false;
  @Param zoomRegionLeft: number = 33;
  @Param zoomRegionRight: number = 33;
  @Param superResolution: boolean = false;
  @Param colorization: boolean = false;
  @Param translation: boolean = false;
  @Param translationDirection: string = 'ja-zh';
  @Param colorizationActive: boolean = true;
  @Event onColorError: (message: string) => void = () => {};
  @Local coloredUrl: string = '';
  @Local colorBusy: boolean = false;
  private colorSerial: number = 0;
  @Event onToggle: (event: ClickEvent) => void = () => {};
  @Local ratio: number = 0;
  @Local failed: boolean = false;
  @Local loaded: boolean = false;
  @Local retry: number = 0;
  @Local zoom: number = 1;
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
    this.alive = false;
    emitter.off('app.comic.image.ready', this.imageReadyHandler);
    this.visible = false;
    this.imageSerial++;
    this.enhancementSerial++;
    this.colorSerial++;
    ReaderCacheService.release(this.cacheOwner);
  }

  @Monitor('page')
  onPageChanged(): void {
    this.ratio = 0;
    this.zoom = 1;
    if (this.alive) this.loadImage();
  }

  private loadImage(): void {
    const page = this.page;
    const ticket = ++this.imageSerial;
    this.startedAt = Date.now();
    this.displayLogged = false;
    this.failed = false;
    this.loaded = false;
    this.resolvedUrl = '';
    this.enhancedUrl = '';
    this.enhancementFailed = false;
    this.enhancementSerial++;
    this.colorSerial++;
    this.coloredUrl = '';
    this.colorBusy = false;
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
      this.resolvedUrl = path.startsWith('/') ? fileUri.getUriFromPath(path) : path;
      this.protectImage();
      this.enhance();
      this.colorize();
      const context = this.getUIContext().getHostContext();
      if (context) ComicReaderService.imageReady(page, path, context).catch((): void => {});
    }).catch((): void => { if (!cancelled()) this.failed = true; });
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
    ComicSuperResolutionService.enhance(context, this.resolvedUrl, active).then((uri: string): void => {
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

  private colorize(): void {
    if (!this.alive || !this.visible || !this.membership.hasAccess || (!this.colorization && !this.translation) || !this.colorizationActive ||
      !this.resolvedUrl || this.coloredUrl || this.colorBusy) return;
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const ticket = ++this.colorSerial;
    this.colorBusy = true;
    const active = (): boolean => this.alive && this.visible && this.membership.hasAccess && (this.colorization || this.translation) && this.colorizationActive &&
      ticket === this.colorSerial;
    ComicColorizationService.transform(context, this.resolvedUrl, active,
      this.translation ? this.translationDirection : '').then((path: string): void => {
      if (!active()) return;
      this.coloredUrl = path;
      this.protectImage();
    }).catch((error: Error): void => {
      if (active()) this.onColorError(error.message);
    }).finally((): void => { if (ticket === this.colorSerial) this.colorBusy = false; });
  }

  private imageHeight(): number {
    const ratio = this.ratio > 0 ? this.ratio : this.page.width > 0 && this.page.height > 0 ?
      this.page.height / this.page.width : 1.45;
    // 分片连续拼接时高度必须落在物理像素上，避免逐片取整露出深色底。
    const ui = this.getUIContext();
    return ui.px2vp(Math.max(1, Math.round(ui.vp2px(this.pageWidth * ratio))));
  }

  private decodeWidth(): number {
    const ratio = this.imageHeight() / Math.max(1, this.pageWidth);
    return Math.max(1, Math.floor(Math.min(this.getUIContext().vp2px(this.pageWidth) * this.zoom, 1536, 4096 / ratio,
      Math.sqrt(4 * 1024 * 1024 / ratio), this.page.width > 0 ? this.page.width : 1536)));
  }

  private decodeSize(): ImageSourceSize {
    const widthPx = this.decodeWidth();
    const heightPx = Math.max(1, Math.floor(widthPx * this.imageHeight() / Math.max(1, this.pageWidth)));
    const ui = this.getUIContext();
    // Image.sourceSize numbers are vp, while decoder budgets and native image dimensions are pixels.
    return { width: ui.px2vp(widthPx), height: ui.px2vp(heightPx) };
  }

  @Builder
  imageContent(): void {
        Image((this.membership.hasAccess ? this.coloredUrl || this.enhancedUrl : '') || this.resolvedUrl)
          .id(`${this.page.key}:${this.retry}`)
          .width(this.pageWidth).height(this.imageHeight())
          // 容器已按原图比例计算；Fill 消除解码宽高取整造成的亚像素留边。
          .objectFit(ImageFit.Fill)
          .syncLoad(false)
          .autoResize(true)
          .sourceSize(this.decodeSize())
          .scale({ x: this.zoom, y: this.zoom })
          .onComplete((event) => {
            if (event && event.width > 0 && event.height > 0) {
              if (!this.coloredUrl && this.ratio <= 0) this.ratio = event.height / event.width;
              // 懒加载节点回收后仍保留已知比例，避免回滚时先按占位高度再跳一次。
              if (!this.coloredUrl) { this.page.width = event.width; this.page.height = event.height; }
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
          .gesture(TapGesture({ count: 2 }).onAction((event: GestureEvent): void => {
            const finger = event.fingerList[0];
            if (finger === undefined) return;
            const percent = finger.localX / Math.max(1, this.pageWidth) * 100;
            if (percent >= this.zoomRegionLeft && percent < 100 - this.zoomRegionRight) {
              this.zoom = this.zoom === 1 ? 2 : 1;
            }
          }))
          .accessibilityText($r('app.string.comic_page_number', this.page.index + 1))
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
      } else if (this.resolvedUrl && this.paged) {
        Scroll() {
          this.imageContent()
        }.width(this.pageWidth).height(this.pageHeight)
          .scrollable(ScrollDirection.Vertical).scrollBar(BarState.Off)
      } else if (this.resolvedUrl) {
        // 连续模式由外层 List 统一滚动，不为每张长图创建一个禁用滚动的 Scroll。
        this.imageContent()
      }

      if (this.colorBusy) {
        Row({ space: 6 }) {
          LoadingProgress().width(18).height(18).color(AppColor.Brand)
          Text(this.translation ? $r('app.string.comic_ai_translate_working') : $r('app.string.comic_ai_color_working'))
            .fontSize(12).fontColor(Color.White)
        }.padding(8).backgroundColor('#99000000').borderRadius(12).align(Alignment.TopEnd)
          .hitTestBehavior(HitTestMode.None)
      }

    }
    .width(this.pageWidth).height(this.paged ? this.pageHeight : this.imageHeight()).clip(true)
    .backgroundColor('#121212')
    .onVisibleAreaChange([0.01], (_visible: boolean, ratio: number) => {
      const visible = ratio > 0;
      if (this.visible === visible) return;
      this.visible = visible;
      this.protectImage();
      if (visible) {
        if (!this.imageRequested) this.loadImage();
        else ComicImageLoader.promote(this.page.sourceUrl, this.pendingUrl);
        this.enhance();
        this.colorize();
      }
      else { this.enhancementSerial++; this.colorSerial++; this.colorBusy = false; }
    })
  }
}
