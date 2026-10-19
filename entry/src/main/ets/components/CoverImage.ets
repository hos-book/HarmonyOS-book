import { AppRadius } from '../theme/Theme';
import { LocalBookCover } from './LocalBookCover';
import { CoverPrefetcher } from '../service/CoverPrefetcher';
import { CoverAspectRatio } from '../utils/CoverAspectRatio';
import { PlatformCompat } from '../utils/PlatformCompat';
import { SourceCoverService } from '../service/SourceCoverService';

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
  // 旋转封面先统一裁剪再合成，避免图片与占位的裁剪边缘叠加。
  @Param compositeEdges: boolean = false;
  @Param imageFit: ImageFit = ImageFit.Cover;
  @Param decodeW: number = 300;
  @Param decodeH: number = 400;
  @Param highPriority: boolean = true;
  @Event onImageSize: (url: string, width: number, height: number) => void = () => {};
  @Event onImageReady: (url: string) => void = () => {};

  @Local showImage: boolean = true;
  @Local giveUp: boolean = false;
  @Local retryCount: number = 0;
  @Local imageReady: boolean = false;
  @Local originalRatio: number = 0.75;
  @Local resolvedUrl: string = '';
  private resolveGeneration: number = 0;

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

  aboutToAppear(): void {
    this.appeared = true;
    this.resetCover();
  }

  aboutToDisappear(): void {
    this.appeared = false;
    this.resolveGeneration++;
    this.cancelRetry();
  }

  @Monitor('url')
  onUrlChanged(): void {
    if (this.appeared) this.resetCover();
  }

  private resetCover(): void {
    this.cancelRetry();
    this.originalRatio = CoverAspectRatio.get(this.url, this.aspectRatioValue);
    this.showImage = true;
    this.imageReady = false;
    this.giveUp = (CoverImage.failedUntil.get(this.url) ?? 0) > Date.now();
    this.retryCount = 0;
    this.resolvedUrl = SourceCoverService.isEncoded(this.url) ? '' : this.url;
    this.resolveGeneration++;
    if (this.url.startsWith('http') && !this.giveUp) {
      CoverImage.failedUntil.delete(this.url);
      if (SourceCoverService.isEncoded(this.url)) this.resolveCover();
      else CoverPrefetcher.prefetch(this.url, this.highPriority);
    }
  }

  private resolveCover(): void {
    const raw = this.url;
    const generation = ++this.resolveGeneration;
    SourceCoverService.resolve(raw).then((resolved: string): void => {
      if (!this.appeared || this.url !== raw || generation !== this.resolveGeneration) return;
      this.resolvedUrl = resolved;
      this.showImage = true;
    }).catch((): void => {
      if (this.appeared && this.url === raw && generation === this.resolveGeneration) this.scheduleRetry();
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
    this.showImage = false;
    this.imageReady = false;
    CoverPrefetcher.retry(this.url);
    const delayMs: number = Math.min(800 * this.retryCount, 5000);
    const url = this.url;
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      if (!this.appeared || this.url !== url) return;
      if (SourceCoverService.isEncoded(url)) this.resolveCover();
      else this.showImage = true;
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
        .sourceSize(this.imageFit === ImageFit.Contain ? undefined : { width: this.decodeW, height: this.decodeH })
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
        .sourceSize(this.imageFit === ImageFit.Contain ? undefined : { width: this.decodeW, height: this.decodeH })
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
      Image($r('app.media.book_cover_placeholder'))
        .draggable(false)
        .width(this.imgWidth)
        .height(this.imgHeight)
        .borderRadius(this.compositeEdges ? 0 : this.radius)
        .clip(!this.compositeEdges)
        .objectFit(ImageFit.Cover)
    } else {
      Image($r('app.media.book_cover_placeholder'))
        .draggable(false)
        .width(this.displayWidth())
        .aspectRatio(this.displayRatio())
        .borderRadius(this.compositeEdges ? 0 : this.radius)
        .clip(!this.compositeEdges)
        .objectFit(ImageFit.Cover)
    }
  }

  build() {
    Stack() {
      if (this.localPlaceholder && !this.url) {
        LocalBookCover({ title: this.title, author: this.author, imgWidth: this.displayWidth(),
          imgHeight: this.imgHeight, useFixedHeight: this.useFixedHeight,
          aspectRatioValue: this.displayRatio(), radius: this.radius })
      } else {
        this.placeholderImage()
      }
      if (this.title && !this.imageReady && !(this.localPlaceholder && !this.url)) {
        Text(this.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#FFF4E6')
          .copyOption(CopyOptions.None).draggable(false)
          .maxLines(5).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center)
          .width('86%').padding(8).backgroundColor('#AA493E35').borderRadius(6)
      }
      if (this.url.startsWith('http') && this.resolvedUrl && this.showImage && !this.giveUp) {
        this.networkImage(this.url)
      } else if (this.url.startsWith('file://') || this.url.startsWith('/data/')) {
        Image(this.url.startsWith('file://') ? this.url : `file://${this.url}`)
          .draggable(false)
          .width(this.displayWidth()).height(this.useFixedHeight ? this.imgHeight : undefined)
          .aspectRatio(this.useFixedHeight ? undefined : this.displayRatio()).objectFit(this.imageFit)
          .borderRadius(this.radius).sourceSize({ width: this.decodeW, height: this.decodeH })
      }
    }
    .width(this.displayWidth())
    .attributeModifier(new CoverCompositeClip(this.compositeEdges, this.radius))
  }
}
