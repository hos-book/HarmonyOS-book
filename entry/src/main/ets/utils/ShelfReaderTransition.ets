import { UIContext } from '@kit.ArkUI';
import { TextReaderRouteParams } from '../model/TextReading';
import { OneShotLayoutCallback, OneShotRect, OneShotTransitionCoordinator, OneShotTransitionIds } from './OneShotTransition';

/** 书架阅读共用等比书封与纸页展开，返回位置按当前书架布局测量。 */
@ObservedV2
export class ShelfReaderOpenState {
  static readonly SURFACE_ID: string = 'shelf-reader-open-surface';
  @Trace active: boolean = false;
  @Trace offsetX: number = 0;
  @Trace offsetY: number = 0;
  @Trace coverWidth: number = 1;
  @Trace coverHeight: number = 1;
  @Trace coverScale: number = 1;
  @Trace coverAngle: number = 0;
  @Trace coverAlpha: number = 1;
  @Trace frontAlpha: number = 1;
  @Trace insideAlpha: number = 0;
  @Trace coverShadow: number = 0;
  @Trace pageX: number = 0;
  @Trace pageY: number = 0;
  @Trace pageWidth: number = 1;
  @Trace pageHeight: number = 1;
  @Trace pageRadius: number = 1.2;
  @Trace paperAlpha: number = 0;
  @Trace spineAlpha: number = 0;
  @Trace bodyAlpha: number = 1;
  @Trace viewportWidth: number = 1;
  @Trace viewportHeight: number = 1;
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
  private liftedX: number = 0;
  private liftedY: number = 0;
  private liftedScale: number = 1;

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
    this.coverWidth = ui.px2vp(source.widthPx);
    this.coverHeight = ui.px2vp(source.heightPx);
    this.configureViewport(ui, viewport);
    this.setOrigin(ui, source, viewport);
    this.active = true;
    this.bodyAlpha = 1;
    this.coverAlpha = 1;
  }

  private configureViewport(ui: UIContext, viewport: OneShotRect): void {
    this.viewportWidth = ui.px2vp(viewport.widthPx);
    this.viewportHeight = ui.px2vp(viewport.heightPx);
    this.liftedScale = Math.min(this.viewportWidth * 0.88 / this.coverWidth,
      this.viewportHeight * 0.76 / this.coverHeight);
    this.liftedX = (this.viewportWidth - this.coverWidth * this.liftedScale) / 2;
    this.liftedY = (this.viewportHeight - this.coverHeight * this.liftedScale) / 2;
  }

  private setOrigin(ui: UIContext, source: OneShotRect, viewport: OneShotRect): void {
    this.offsetX = ui.px2vp(source.leftPx - viewport.leftPx);
    this.offsetY = ui.px2vp(source.topPx - viewport.topPx);
    this.coverScale = ui.px2vp(source.widthPx) / this.coverWidth;
    this.pageX = this.offsetX;
    this.pageY = this.offsetY;
    this.pageWidth = ui.px2vp(source.widthPx);
    this.pageHeight = ui.px2vp(source.heightPx);
    this.pageRadius = 1.2 * this.coverScale;
  }

  /** 封面统一缩放；纸页裁剪独立展开到阅读窗口。 */
  private setUnfoldedGeometry(progress: number): void {
    const remaining: number = 1 - progress;
    this.offsetX = this.liftedX * remaining;
    this.offsetY = this.liftedY * remaining;
    this.coverScale = this.liftedScale * remaining + this.viewportHeight / this.coverHeight * progress;
    this.pageX = this.offsetX;
    this.pageY = this.offsetY;
    this.pageWidth = this.coverWidth * this.liftedScale * remaining + this.viewportWidth * progress;
    this.pageHeight = this.coverHeight * this.liftedScale * remaining + this.viewportHeight * progress;
    this.pageRadius = 1.2 * this.liftedScale * remaining;
  }

  private setOpenPose(): void {
    this.setUnfoldedGeometry(1);
    this.coverAngle = -168;
    this.coverShadow = 0;
    this.paperAlpha = 0;
    this.spineAlpha = 0;
    this.coverAlpha = 1;
    this.bodyAlpha = 1;
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
          this.setOpenPose();
          this.frontAlpha = 0;
          this.insideAlpha = 1;
          this.active = true;
          OneShotTransitionCoordinator.getInstance().coverState.hiddenSourceId = this.sourceNodeId;
        }
        // 阅读页先完成最终尺寸布局，再提交书封变换与纸页裁剪动画。
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
    this.configureViewport(ui, viewport);
    this.setOrigin(ui, source, viewport);
    this.started = true;
    OneShotTransitionCoordinator.getInstance().coverState.hiddenSourceId = this.sourceNodeId;
    ui.keyframeAnimateTo({ onFinish: (): void => {
      if (this.isCurrent(generation)) this.complete();
    } }, [
      { duration: 190, curve: Curve.FastOutSlowIn, event: (): void => {
        this.setUnfoldedGeometry(0);
        this.coverAngle = -8;
        this.coverShadow = 3;
        this.paperAlpha = 0.85;
        this.spineAlpha = 0.16;
      } },
      { duration: 180, curve: Curve.EaseIn, event: (): void => {
        this.setUnfoldedGeometry(0.3);
        this.coverAngle = -84;
        this.coverShadow = 2;
        this.paperAlpha = 0.6;
        this.spineAlpha = 0.38;
      } },
      { duration: 40, curve: Curve.Linear, event: (): void => {
        this.setUnfoldedGeometry(0.42);
        this.coverAngle = -98;
        this.paperAlpha = 0.4;
        this.spineAlpha = 0.3;
      } },
      { duration: 240, curve: Curve.EaseOut, event: (): void => { this.setOpenPose(); } }
    ]);
    // 正反面仅在封面侧向的 40ms 内交接，保留翻开前段的完整封面。
    ui.animateTo({ duration: 40, delay: 370, curve: Curve.Linear }, (): void => {
      this.frontAlpha = 0;
      this.insideAlpha = 1;
    });
  }

  private close(ui: UIContext, generation: number): void {
    const viewport = OneShotRect.measure(ui, ShelfReaderOpenState.SURFACE_ID);
    if (viewport === undefined) { this.complete(); return; }
    this.configureViewport(ui, viewport);
    this.setOpenPose();
    this.started = true;
    ui.keyframeAnimateTo({ onFinish: (): void => {
      if (!this.isCurrent(generation)) return;
      this.bodyAlpha = 0;
      this.returnToShelf(ui, generation);
    } }, [
      { duration: 210, curve: Curve.EaseIn, event: (): void => {
        this.setUnfoldedGeometry(0.42);
        this.coverAngle = -98;
        this.coverShadow = 2;
        this.paperAlpha = 0.4;
        this.spineAlpha = 0.3;
      } },
      { duration: 35, curve: Curve.Linear, event: (): void => {
        this.setUnfoldedGeometry(0.3);
        this.coverAngle = -84;
        this.paperAlpha = 0.6;
        this.spineAlpha = 0.38;
      } },
      { duration: 175, curve: Curve.EaseOut, event: (): void => {
        this.setUnfoldedGeometry(0);
        this.coverAngle = 0;
        this.coverShadow = 3;
        this.paperAlpha = 0.85;
        this.spineAlpha = 0;
      } }
    ]);
    ui.animateTo({ duration: 35, delay: 210, curve: Curve.Linear }, (): void => {
      this.frontAlpha = 1;
      this.insideAlpha = 0;
    });
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
      // 来源移出视口时，书本在当前中心位置合拢并淡出。
      ui.animateTo({ duration: 180, curve: Curve.EaseOut,
        onFinish: (): void => { if (this.isCurrent(generation)) this.complete(); } },
        (): void => { this.coverAlpha = 0; this.paperAlpha = 0; });
      return;
    }
    ui.animateTo({ duration: 180, curve: Curve.FastOutSlowIn,
      onFinish: (): void => { if (this.isCurrent(generation)) this.complete(); } },
      (): void => {
        this.setOrigin(ui, target, viewport);
        this.coverShadow = 0;
        this.paperAlpha = 0;
      });
  }

  viewportChanged(): void {
    // 窗口尺寸变化时完成当前转场，阅读页使用当前窗口重新布局。
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
    const coverState = OneShotTransitionCoordinator.getInstance().coverState;
    if (coverState.hiddenSourceId === this.sourceNodeId) coverState.hiddenSourceId = '';
    this.finished = true;
    this.proxy = undefined;
    this.source = undefined;
    this.active = false;
    this.started = false;
    this.offsetX = 0;
    this.offsetY = 0;
    this.coverScale = 1;
    this.coverAngle = 0;
    this.coverAlpha = 0;
    this.frontAlpha = 1;
    this.insideAlpha = 0;
    this.coverShadow = 0;
    this.paperAlpha = 0;
    this.spineAlpha = 0;
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
