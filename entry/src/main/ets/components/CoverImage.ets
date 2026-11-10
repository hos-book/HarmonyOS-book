import { AppRadius } from '../theme/Theme';
import { CoverTheme } from '../theme/CoverTheme';
import { CoverDecoration } from './CoverDecoration';
import { LocalBookCover } from './LocalBookCover';
import { CoverPrefetcher } from '../service/CoverPrefetcher';
import { CoverAspectRatio } from '../utils/CoverAspectRatio';
import { PlatformCompat } from '../utils/PlatformCompat';
import { CoverLoadHandle } from '../service/CoverLoader';
import { emitter } from '@kit.BasicServicesKit';

class CoverCompositeClip implements AttributeModifier<CommonAttribute> {
  private enabled: boolean;
  private radius: number;

  constructor(enabled: boolean, radius: number) {
    this.enabled = enabled;
    this.radius = radius;
  }

  applyNormalAttribute(node: CommonAttribute): void {
    if (this.enabled && PlatformCompat.supports(22)) {
      node.borderRadius(this.radius, RenderStrategy.OFFSCREEN);
    } else {
      node.borderRadius(this.enabled ? this.radius : 0);
    }
    node.clip(this.enabled).renderGroup(this.enabled);
  }
}

/**
 * 网络封面图：占位始终保留，完整出图后显示；失败只后台重试一次。
 * 短期复用失败结果，避免列表重建时反复请求和闪动。
 */
@ComponentV2
export struct CoverImage {
  @Param url: string = '';
  @Param title: string = '';
  @Param author: string = '';
  @Param localPlaceholder: boolean = false;
  @Param imgWidth: Length = '100%';
  @Param imgHeight: Length = 0;
  @Param useFixedHeight: boolean = false;
  @Param aspectRatioValue: number = 0.75;
  @Param useOriginalRatio: boolean = false;
  @Param maxOriginalHeight: number = 0;
  @Param radius: number = AppRadius.Md;
  @Param themedDecoration: boolean = true;
  @Param themeBundleId: string = '';
  // 旋转封面先统一裁剪再合成，避免图片与占位的裁剪边缘叠加。
  @Param compositeEdges: boolean = false;
  @Param imageFit: ImageFit = ImageFit.Cover;
  @Param interpolationQuality: ImageInterpolation = ImageInterpolation.Medium;
  @Param highPriority: boolean = true;
  /** 固定播放栏不依赖滚动可见性回调，挂载和回前台即可加载。 */
  @Param eagerLoad: boolean = false;
  @Event onImageSize: (url: string, width: number, height: number) => void = () => {};
  @Event onImageReady: (url: string) => void = () => {};

  @Local showImage: boolean = true;
  @Local giveUp: boolean = false;
  @Local retryCount: number = 0;
  @Local imageReady: boolean = false;
  @Local originalRatio: number = 0.75;
  @Local resolvedUrl: string = '';
  private resolveGeneration: number = 0;
  private loadHandle: CoverLoadHandle | undefined = undefined;
  private visible: boolean = false;

  private displayRatio(): number {
    return this.useOriginalRatio ? this.originalRatio : this.aspectRatioValue;
  }

  private displayWidth(): Length {
    if (this.useOriginalRatio && this.maxOriginalHeight > 0 && typeof this.imgWidth === 'number') {
      return CoverAspectRatio.fittedWidth(this.originalRatio, this.imgWidth, this.maxOriginalHeight);
    }
    return this.imgWidth;
  }

  private static readonly MAX_UI_RETRY: number = 1;
  private static readonly FAILURE_COOLDOWN_MS: number = 5 * 60 * 1000;
  private static failedUntil: Map<string, number> = new Map<string, number>();
  private retryTimer: number = -1;
  private appeared: boolean = false;
  private appForeground: boolean = true;
  private foregroundHandler = (): void => {
    this.appForeground = true;
    if (this.appeared && this.eagerLoad) this.visibilityChanged(true);
  };
  private backgroundHandler = (): void => {
    this.appForeground = false;
    this.visibilityChanged(false);
  };

  aboutToAppear(): void {
    this.appeared = true;
    if (this.eagerLoad) {
      this.visible = true;
      emitter.on('app.reader.foreground', this.foregroundHandler);
      emitter.on('app.reader.background', this.backgroundHandler);
    }
    this.resetCover();
  }

  aboutToDisappear(): void {
    this.appeared = false;
    if (this.eagerLoad) {
      emitter.off('app.reader.foreground', this.foregroundHandler);
      emitter.off('app.reader.background', this.backgroundHandler);
    }
    this.visible = false;
    this.loadHandle?.cancel();
    this.loadHandle = undefined;
    this.resolveGeneration++;
    this.cancelRetry();
  }

  @Monitor('url')
  onUrlChanged(): void {
    if (this.appeared) this.resetCover();
  }

  private resetCover(): void {
    this.cancelRetry();
    this.loadHandle?.cancel();
    this.loadHandle = undefined;
    this.originalRatio = CoverAspectRatio.get(this.url, this.aspectRatioValue);
    this.showImage = true;
    const cached = CoverPrefetcher.cached(this.url);
    this.imageReady = cached.length > 0;
    this.giveUp = (CoverImage.failedUntil.get(this.url) ?? 0) > Date.now();
    this.retryCount = 0;
    this.resolvedUrl = cached;
    this.resolveGeneration++;
    if (this.visible && this.url.startsWith('http') && !this.giveUp && !cached) this.resolveCover();
  }

  private visibilityChanged(visible: boolean): void {
    this.visible = visible;
    if (!visible) {
      this.loadHandle?.cancel();
      this.loadHandle = undefined;
      this.resolveGeneration++;
      this.cancelRetry();
    } else if (!this.loadHandle && !this.resolvedUrl && !this.giveUp && this.url.startsWith('http')) {
      this.resolveCover();
    }
  }

  private resolveCover(): void {
    const raw = this.url;
    const generation = ++this.resolveGeneration;
    this.loadHandle?.cancel();
    const handle = CoverPrefetcher.acquire(raw);
    this.loadHandle = handle;
    handle.promise.then((resolved: string): void => {
      if (!this.appeared || this.url !== raw || generation !== this.resolveGeneration) return;
      this.loadHandle = undefined;
      this.resolvedUrl = resolved;
      this.showImage = true;
    }).catch((): void => {
      if (this.appeared && this.url === raw && generation === this.resolveGeneration) {
        this.loadHandle = undefined;
        this.giveUp = true;
      }
    });
  }

  private cancelRetry(): void {
    if (this.retryTimer >= 0) clearTimeout(this.retryTimer);
    this.retryTimer = -1;
  }

  private scheduleRetry(): void {
    if (!this.appeared || this.retryTimer >= 0) return;
    if (this.retryCount >= CoverImage.MAX_UI_RETRY) {
      CoverImage.failedUntil.delete(this.url);
      CoverImage.failedUntil.set(this.url, Date.now() + CoverImage.FAILURE_COOLDOWN_MS);
      for (const key of CoverImage.failedUntil.keys()) {
        if (CoverImage.failedUntil.size <= 512) break;
        CoverImage.failedUntil.delete(key);
      }
      this.giveUp = true;
      return;
    }
    this.retryCount = this.retryCount + 1;
    CoverPrefetcher.invalidate(this.url);
    this.resolvedUrl = '';
    this.showImage = false;
    this.imageReady = false;
    const delayMs: number = Math.min(800 * this.retryCount, 5000);
    const url = this.url;
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      if (!this.appeared || this.url !== url) return;
      if (this.visible) this.resolveCover();
    }, delayMs);
  }

  @Builder
  private networkImage(url: string) {
    if (this.useFixedHeight) {
      Image(this.resolvedUrl)
        .draggable(false)
        .width(this.imgWidth)
        .height(this.imgHeight)
        .borderRadius(this.compositeEdges ? 0 : this.radius)
        .clip(!this.compositeEdges)
        .objectFit(this.imageFit)
        // 按布局尺寸和 objectFit 等比降采样；sourceSize 的数字单位是 vp，不能传像素预算。
        .autoResize(true)
        .interpolation(this.interpolationQuality)
        .opacity(this.imageReady ? 1 : 0)
        .onComplete((event) => {
          // 数据加载阶段为原图尺寸；不能用 sourceSize 缩略解码后的尺寸覆盖它。
          if (!this.appeared || this.url !== url) return;
          if (event?.loadingStatus === 0) {
            CoverAspectRatio.remember(url, event.width, event.height);
            this.onImageSize(url, event.width, event.height);
          } else if (event?.loadingStatus === 1) {
            this.cancelRetry();
            CoverImage.failedUntil.delete(url);
            this.imageReady = true;
            this.onImageReady(url);
          }
        })
        .onError(() => {
          if (this.url === url) this.scheduleRetry();
        })
    } else {
      Image(this.resolvedUrl)
        .draggable(false)
        .width(this.displayWidth())
        .aspectRatio(this.displayRatio())
        .borderRadius(this.compositeEdges ? 0 : this.radius)
        .clip(!this.compositeEdges)
        .objectFit(this.imageFit)
        .autoResize(true)
        .interpolation(this.interpolationQuality)
        .opacity(this.imageReady ? 1 : 0)
        .onComplete((event) => {
          if (!this.appeared || this.url !== url) return;
          if (event?.loadingStatus === 0) {
            CoverAspectRatio.remember(url, event.width, event.height);
            this.originalRatio = CoverAspectRatio.get(url, this.aspectRatioValue);
            this.onImageSize(url, event.width, event.height);
          } else if (event?.loadingStatus === 1) {
            this.cancelRetry();
            CoverImage.failedUntil.delete(url);
            this.imageReady = true;
            this.onImageReady(url);
          }
        })
        .onError(() => {
          if (this.url === url) this.scheduleRetry();
        })
    }
  }

  @Builder
  private placeholderImage() {
    // 占位素材是方图，必须填满封面框；不能跟随真实封面的 Contain 留白。
    if (this.useFixedHeight) {
      Image(CoverTheme.placeholder(this.themeBundleId))
        .draggable(false)
        .width(this.imgWidth)
        .height(this.imgHeight)
        .borderRadius(this.compositeEdges ? 0 : this.radius)
        .clip(!this.compositeEdges)
        .objectFit(ImageFit.Cover)
        .autoResize(true)
    } else {
      Image(CoverTheme.placeholder(this.themeBundleId))
        .draggable(false)
        .width(this.displayWidth())
        .aspectRatio(this.displayRatio())
        .borderRadius(this.compositeEdges ? 0 : this.radius)
        .clip(!this.compositeEdges)
        .objectFit(ImageFit.Cover)
        .autoResize(true)
    }
  }

  build() {
    Stack() {
      if (this.localPlaceholder && !this.url) {
        LocalBookCover({ title: this.title, author: this.author, imgWidth: this.displayWidth(),
          imgHeight: this.imgHeight, useFixedHeight: this.useFixedHeight,
          aspectRatioValue: this.displayRatio(), radius: this.radius,
          themedDecoration: false, themeBundleId: this.themeBundleId })
      } else {
        this.placeholderImage()
      }
      if (this.url.startsWith('http') && this.resolvedUrl && this.showImage && !this.giveUp) {
        this.networkImage(this.url)
      } else if (this.url.startsWith('file://') || this.url.startsWith('/data/')) {
        Image(this.url.startsWith('file://') ? this.url : `file://${this.url}`)
          .draggable(false)
          .width(this.displayWidth()).height(this.useFixedHeight ? this.imgHeight : undefined)
          .aspectRatio(this.useFixedHeight ? undefined : this.displayRatio()).objectFit(this.imageFit)
          .borderRadius(this.compositeEdges ? 0 : this.radius).autoResize(true)
          .interpolation(this.interpolationQuality)
      }
    }
    .width(this.displayWidth())
    .height(this.useFixedHeight ? this.imgHeight : undefined)
    .aspectRatio(this.useFixedHeight ? undefined : this.displayRatio())
    .attributeModifier(new CoverCompositeClip(this.compositeEdges, this.radius))
    .overlay(this.coverDecoration(), { align: Alignment.Center })
    .onVisibleAreaChange([0], (visible: boolean): void => {
      this.visibilityChanged(this.eagerLoad ? this.appForeground : visible);
    })
  }

  @Builder
  private coverDecoration() {
    if (this.themedDecoration) {
      CoverDecoration({ radius: this.radius, themeBundleId: this.themeBundleId })
    }
  }
}
