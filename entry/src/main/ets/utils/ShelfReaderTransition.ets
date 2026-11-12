import { UIContext } from '@kit.ArkUI';
import { TextReaderRouteParams } from '../model/TextReading';
import { OneShotLayoutCallback, OneShotRect, OneShotTransitionIds } from './OneShotTransition';

/** 书架阅读路由共用翻开与合拢；返回时重新测量封面，不复用入场坐标。 */
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
  author: string = '';
  localPlaceholder: boolean = false;
  private source: OneShotRect | undefined = undefined;
  private proxy: NavigationTransitionProxy | undefined = undefined;
  private finished: boolean = false;
  private started: boolean = false;
  private sourceNodeId: string = '';
  private closing: boolean = false;
  private generation: number = 0;

  prepare(ui: UIContext, nodeId: string, cover: string, title: string, author: string,
    localPlaceholder: boolean): void {
    this.sourceNodeId = nodeId;
    this.cover = cover;
    this.title = title;
    this.author = author;
    this.localPlaceholder = localPlaceholder;
    const source = OneShotRect.measure(ui, nodeId);
    const viewport = OneShotRect.measure(ui, OneShotTransitionIds.ROOT_NAVIGATION);
    if (source === undefined || viewport === undefined) return;
    this.source = source;
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

  navigationTransition(ui: UIContext, isPush: boolean = true): NavigationAnimatedTransition {
    const generation = ++this.generation;
    const transition: NavigationAnimatedTransition = {
      timeout: 1000,
      transition: (proxy: NavigationTransitionProxy): void => {
        if (generation !== this.generation) {
          proxy.finishTransition();
          return;
        }
        this.finished = false;
        this.started = false;
        this.closing = !isPush;
        this.proxy = proxy;
        if (!isPush) {
          this.active = true;
          this.offsetX = 0;
          this.offsetY = 0;
          this.zoomX = 1;
          this.zoomY = 1;
          this.coverAngle = -92;
          this.coverAlpha = 0;
          this.bodyAlpha = 1;
        }
        // 阅读页先完成布局，动画只改变绘制属性，不反复触发正文重排。
        ui.postFrameCallback(new OneShotLayoutCallback((): void => {
          if (!this.isCurrent(generation)) return;
          ui.postFrameCallback(new OneShotLayoutCallback((): void => {
            if (!this.isCurrent(generation)) return;
            if (isPush) this.open(ui, generation);
            else this.close(ui, generation);
          }));
        }));
      },
      onTransitionEnd: (success: boolean): void => {
        if (generation === this.generation) this.reset(isPush || !success);
      }
    };
    return transition;
  }

  private isCurrent(generation: number): boolean {
    return generation === this.generation && !this.finished;
  }

  private open(ui: UIContext, generation: number): void {
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
      onFinish: (): void => { if (this.isCurrent(generation)) this.complete(); } },
      (): void => { this.coverAlpha = 0; });
  }

  private close(ui: UIContext, generation: number): void {
    this.started = true;
    ui.animateTo({ duration: 100, curve: Curve.EaseOut },
      (): void => { this.coverAlpha = 1; });
    // 先让封面完整盖住正文，再收回书架；正文不能在合拢途中提前消失。
    ui.animateTo({ duration: 220, curve: Curve.EaseInOut,
      onFinish: (): void => {
        if (!this.isCurrent(generation)) return;
        this.bodyAlpha = 0;
        this.returnToShelf(ui, generation);
      } },
      (): void => { this.coverAngle = 0; });
  }

  private returnToShelf(ui: UIContext, generation: number): void {
    // 合拢期间书架可能按最近阅读重排，在真正归位前测量最终位置。
    const viewport = OneShotRect.measure(ui, ShelfReaderOpenState.SURFACE_ID);
    const target = OneShotRect.measure(ui, this.sourceNodeId);
    if (viewport === undefined || target === undefined ||
      target.leftPx >= viewport.leftPx + viewport.widthPx ||
      target.leftPx + target.widthPx <= viewport.leftPx ||
      target.topPx >= viewport.topPx + viewport.heightPx ||
      target.topPx + target.heightPx <= viewport.topPx) {
      // 封面已移出可见区域或被移除时，合拢后淡出，不飞向过期坐标。
      ui.animateTo({ duration: 180, curve: Curve.EaseOut,
        onFinish: (): void => { if (this.isCurrent(generation)) this.complete(); } },
        (): void => { this.coverAlpha = 0; });
      return;
    }
    ui.animateTo({ duration: 180, curve: Curve.FastOutSlowIn,
      onFinish: (): void => { if (this.isCurrent(generation)) this.complete(); } },
      (): void => { this.setOrigin(ui, target, viewport); });
  }

  viewportChanged(): void {
    // 折叠、旋转或窗口调整时直接完成当前导航，不沿用旧窗口坐标。
    if (this.started && !this.finished) this.complete();
  }

  complete(): void {
    if (this.finished) return;
    const proxy = this.proxy;
    this.reset(!this.closing);
    proxy?.finishTransition();
  }

  dispose(): void {
    this.complete();
    this.generation++;
    this.sourceNodeId = '';
  }

  private reset(bodyVisible: boolean = true): void {
    this.finished = true;
    this.proxy = undefined;
    this.source = undefined;
    this.active = false;
    this.started = false;
    this.offsetX = 0;
    this.offsetY = 0;
    this.zoomX = 1;
    this.zoomY = 1;
    this.coverAngle = 0;
    this.coverAlpha = 0;
    this.bodyAlpha = bodyVisible ? 1 : 0;
  }
}

export class ShelfReaderRouteParams extends TextReaderRouteParams {
  opening: ShelfReaderOpenState = new ShelfReaderOpenState();

  static fromShelf(bookId: string, cover: string, title: string, nodeId: string,
    ui: UIContext, author: string = ''): ShelfReaderRouteParams {
    const params = new ShelfReaderRouteParams();
    params.bookId = bookId;
    params.opening.prepare(ui, nodeId, cover, title, author, bookId.startsWith('import_'));
    return params;
  }
}
