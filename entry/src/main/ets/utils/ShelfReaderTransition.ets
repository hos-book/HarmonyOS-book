import { UIContext } from '@kit.ArkUI';
import { TextReaderRouteParams } from '../model/TextReading';
import { OneShotLayoutCallback, OneShotRect, OneShotTransitionIds } from './OneShotTransition';

/** 仅书架入场使用；状态随本次路由保存，返回和其他阅读入口不重播。 */
@ObservedV2
export class ShelfReaderOpenState {
  static readonly SURFACE_ID: string = 'shelf-reader-open-surface';
  @Trace active: boolean = false;
  @Trace offsetX: number = 0;
  @Trace offsetY: number = 0;
  @Trace zoomX: number = 1;
  @Trace zoomY: number = 1;
  @Trace coverAngle: number = 0;
  @Trace coverAlpha: number = 1;
  @Trace bodyAlpha: number = 1;
  cover: string = '';
  title: string = '';
  private source: OneShotRect | undefined = undefined;
  private proxy: NavigationTransitionProxy | undefined = undefined;
  private finished: boolean = false;
  private started: boolean = false;

  prepare(ui: UIContext, nodeId: string, cover: string, title: string): void {
    const source = OneShotRect.measure(ui, nodeId);
    const viewport = OneShotRect.measure(ui, OneShotTransitionIds.ROOT_NAVIGATION);
    if (source === undefined || viewport === undefined) return;
    this.source = source;
    this.cover = cover;
    this.title = title;
    this.active = true;
    this.bodyAlpha = 0;
    this.setOrigin(ui, source, viewport);
  }

  private setOrigin(ui: UIContext, source: OneShotRect, viewport: OneShotRect): void {
    this.offsetX = ui.px2vp(source.leftPx - viewport.leftPx);
    this.offsetY = ui.px2vp(source.topPx - viewport.topPx);
    this.zoomX = source.widthPx / viewport.widthPx;
    this.zoomY = source.heightPx / viewport.heightPx;
  }

  navigationTransition(ui: UIContext): NavigationAnimatedTransition {
    const transition: NavigationAnimatedTransition = {
      timeout: 1000,
      transition: (proxy: NavigationTransitionProxy): void => {
        this.proxy = proxy;
        // 阅读页先完成布局，动画只改变绘制属性，不反复触发正文重排。
        ui.postFrameCallback(new OneShotLayoutCallback((): void => {
          ui.postFrameCallback(new OneShotLayoutCallback((): void => this.open(ui)));
        }));
      },
      onTransitionEnd: (): void => this.reset()
    };
    return transition;
  }

  private open(ui: UIContext): void {
    if (this.finished) return;
    const viewport = OneShotRect.measure(ui, ShelfReaderOpenState.SURFACE_ID);
    const source = this.source;
    if (viewport === undefined || source === undefined) {
      this.complete();
      return;
    }
    this.setOrigin(ui, source, viewport);
    this.started = true;
    ui.animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, (): void => {
      this.offsetX = 0;
      this.offsetY = 0;
      this.zoomX = 1;
      this.zoomY = 1;
    });
    ui.animateTo({ duration: 180, delay: 60, curve: Curve.EaseOut }, (): void => {
      this.bodyAlpha = 1;
    });
    // 封面绕左侧书脊翻开，正文留在书页下方，避免整页旋转影响阅读布局。
    ui.animateTo({ duration: 340, delay: 60, curve: Curve.EaseInOut }, (): void => {
      this.coverAngle = -92;
    });
    ui.animateTo({ duration: 100, delay: 300, curve: Curve.EaseOut,
      onFinish: (): void => this.complete() }, (): void => { this.coverAlpha = 0; });
  }

  viewportChanged(): void {
    // 折叠、旋转或窗口调整时直接落到正文，不沿用旧窗口的封面坐标。
    if (this.started && !this.finished) this.complete();
  }

  complete(): void {
    const proxy = this.proxy;
    this.reset();
    proxy?.finishTransition();
  }

  private reset(): void {
    this.finished = true;
    this.proxy = undefined;
    this.source = undefined;
    this.active = false;
    this.offsetX = 0;
    this.offsetY = 0;
    this.zoomX = 1;
    this.zoomY = 1;
    this.coverAlpha = 0;
    this.bodyAlpha = 1;
  }
}

export class ShelfReaderRouteParams extends TextReaderRouteParams {
  opening: ShelfReaderOpenState = new ShelfReaderOpenState();

  static fromShelf(bookId: string, cover: string, title: string, nodeId: string,
    ui: UIContext): ShelfReaderRouteParams {
    const params = new ShelfReaderRouteParams();
    params.bookId = bookId;
    params.opening.prepare(ui, nodeId, cover, title);
    return params;
  }
}
