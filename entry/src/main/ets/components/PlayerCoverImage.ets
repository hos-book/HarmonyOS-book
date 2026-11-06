import { CoverPrefetcher } from '../service/CoverPrefetcher';
import { EnhancedPlayerCover } from './EnhancedPlayerCover';
import { CoverLoadHandle } from '../service/CoverLoader';
import { CoverImage } from './CoverImage';
import { CoverDecoration } from './CoverDecoration';
import { CoverTheme } from '../theme/CoverTheme';

class PlayerCoverRequest {
  url: string;
  size: number;
  key: string;
  constructor(url: string, size: number) {
    this.url = url;
    this.size = size;
    this.key = JSON.stringify([url, size]);
  }
}

/** 原图按布局尺寸提前解码，完成后通知转场复用；增强处理仍由 highQuality 控制。 */
@ComponentV2
export struct PlayerCoverImage {
  @Param url: string = '';
  @Param title: string = '';
  @Param author: string = '';
  @Param localPlaceholder: boolean = false;
  @Param fallback: string = '';
  @Param highQuality: boolean = false;
  @Param radius: number = 16;
  @Event onImageReady: (source: string, decodeSize: number) => void = () => {};
  @Local decodeSize: number = 300;
  @Local loadedKey: string = '';
  @Local failedKey: string = '';
  @Local previewFailed: boolean = false;
  @Local resolvedUrl: string = '';
  @Local resolvedFallback: string = '';
  private generation: number = 0;
  private handles: CoverLoadHandle[] = [];
  private resizeTimer: number = -1;
  private measured: boolean = false;
  private appeared: boolean = false;

  aboutToAppear(): void { this.appeared = true; this.reset(); }
  aboutToDisappear(): void { this.appeared = false; this.cancelResize(); this.generation++; this.releaseLoads(); }

  @Monitor('url', 'fallback')
  onCoverChanged(): void { this.reset(); }

  private reset(): void {
    this.loadedKey = '';
    this.failedKey = '';
    this.previewFailed = false;
    const generation = ++this.generation;
    this.releaseLoads();
    this.resolvedUrl = this.url.startsWith('http') ? CoverPrefetcher.cached(this.url) : this.url;
    this.resolvedFallback = this.fallback.startsWith('http') ? CoverPrefetcher.cached(this.fallback) : this.fallback;
    if (this.url.startsWith('http') && !this.resolvedUrl) {
      const handle = CoverPrefetcher.acquire(this.url);
      this.handles.push(handle);
      handle.promise.then((url: string): void => {
        if (generation === this.generation) this.resolvedUrl = url;
      }).catch((): void => {});
    }
    if (this.fallback.startsWith('http') && !this.resolvedFallback) {
      const handle = CoverPrefetcher.acquire(this.fallback);
      this.handles.push(handle);
      handle.promise.then((url: string): void => {
        if (generation === this.generation) this.resolvedFallback = url;
      }).catch((): void => {});
    }
  }

  private releaseLoads(): void {
    for (const handle of this.handles) handle.cancel();
    this.handles = [];
  }

  private cancelResize(): void {
    if (this.resizeTimer !== -1) clearTimeout(this.resizeTimer);
    this.resizeTimer = -1;
  }

  private resize(width: number): void {
    if (!Number.isFinite(width) || width <= 0) return;
    // sourceSize 单位为 vp，不能再乘屏幕密度；分档减少小窗拖动时反复解码。
    const size = Math.min(1024, Math.max(64, Math.ceil(width / 32) * 32));
    this.cancelResize();
    if (!this.measured) {
      this.measured = true;
      this.decodeSize = size;
      return;
    }
    if (size === this.decodeSize) return;
    this.resizeTimer = setTimeout((): void => {
      this.resizeTimer = -1;
      this.decodeSize = size;
    }, 80);
  }

  private source(url: string): ResourceStr {
    if (!url) return CoverTheme.playerPlaceholder();
    if (url.startsWith('/')) return `file://${url}`;
    if (url.startsWith('http') || url.startsWith('file://')) return url;
    return $rawfile(url);
  }

  private requestKey(): string { return JSON.stringify([this.resolvedUrl, this.decodeSize]); }

  build() {
    Stack() {
      if (!this.resolvedUrl && !this.resolvedFallback) {
        CoverImage({ title: this.title, author: this.author, localPlaceholder: this.localPlaceholder,
          useFixedHeight: true, imgHeight: '100%', imageFit: ImageFit.Contain, themedDecoration: false })
      } else {
      Image(this.source(this.previewFailed ? this.resolvedUrl : (this.resolvedFallback || this.resolvedUrl)))
        .draggable(false)
        .width('100%').height('100%').objectFit(ImageFit.Cover)
        .sourceSize({ width: this.decodeSize, height: this.decodeSize })
        .interpolation(ImageInterpolation.Medium)
        .alt(CoverTheme.playerPlaceholder())
        .onError((): void => { this.previewFailed = true; })
      if (this.resolvedUrl) {
        ForEach([new PlayerCoverRequest(this.resolvedUrl, this.decodeSize)], (request: PlayerCoverRequest) => {
          Image(this.source(request.url))
            .draggable(false)
            .width('100%').height('100%').objectFit(ImageFit.Cover)
            .sourceSize({ width: request.size, height: request.size })
            .interpolation(ImageInterpolation.Medium)
            .opacity(this.loadedKey === request.key && this.failedKey !== request.key ? 1 : 0)
            .transition(TransitionEffect.IDENTITY)
            .onComplete((event) => {
              if (this.appeared && event?.loadingStatus === 1 && this.requestKey() === request.key) {
                this.loadedKey = request.key;
                this.onImageReady(request.url, request.size);
              }
            })
            .onError((): void => {
              if (this.requestKey() === request.key) this.failedKey = request.key;
            })
        }, (request: PlayerCoverRequest): string => request.key)
        if (this.highQuality) {
          EnhancedPlayerCover({ url: this.failedKey === this.requestKey() ? (this.resolvedFallback || this.resolvedUrl) : this.resolvedUrl })
        }
      }
      }
      CoverDecoration({ radius: this.radius, compact: true })
    }
    .width('100%').height('100%')
    .onSizeChange((_oldValue, newValue) => {
      if (typeof newValue.width === 'number') this.resize(newValue.width);
    })
  }
}
