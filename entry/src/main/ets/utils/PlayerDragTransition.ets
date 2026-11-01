import { UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { OneShotRect, OneShotTransitionIds, OneShotTransitionCoordinator } from './OneShotTransition';
import { WindowUtils } from './WindowUtils';

export class PlayerDragOrigin {
  sourceNodeId: string = 'mini-player-bar';
  radius: number = 0;
  left: number = 0;
  top: number = 0;
  width: number = 0;
  height: number = 0;
  coverLeft: number = 0;
  coverTop: number = 0;
  coverWidth: number = 0;
  coverHeight: number = 0;
  viewportWidth: number = 0;
  viewportHeight: number = 0;
  viewportLeftPx: number = 0;
  viewportTopPx: number = 0;
  snapshot: image.PixelMap | undefined = undefined;
}

@ObservedV2
export class PlayerDragState {
  @Trace sourceNodeId: string = 'mini-player-bar';
  @Trace viewportWidth: number = 0;
  @Trace viewportHeight: number = 0;
  @Trace active: boolean = false;
  @Trace frameX: number = 0;
  @Trace frameY: number = 0;
  @Trace frameWidth: number = 0;
  @Trace frameHeight: number = 0;
  @Trace radius: number = 0;
  @Trace coverX: number = 0;
  @Trace coverY: number = 0;
  @Trace coverWidth: number = 0;
  @Trace coverHeight: number = 0;
  @Trace coverRadius: number = 0;
  @Trace contentOpacity: number = 1;
  @Trace sourceOpacity: number = 1;
  @Trace snapshot: image.PixelMap | undefined = undefined;
}

/** 手势确认与页面转场分离：短拖不压栈，确认后统一执行定时展开。 */
export class PlayerDragTransition {
  private static readonly instance: PlayerDragTransition = new PlayerDragTransition();
  readonly state: PlayerDragState = new PlayerDragState();
  private gestureCommit: (() => void) | undefined = undefined;
  private distance: number = 1;
  private progress: number = 0;
  private generation: number = 0;
  private returnNodeId: string = 'mini-player-bar';
  private returnRadius: number = 0;

  static getInstance(): PlayerDragTransition {
    return PlayerDragTransition.instance;
  }

  static measure(uiContext: UIContext, id: string): OneShotRect {
    const rect = OneShotRect.fromComponentInfo(uiContext.getComponentUtils().getRectangleById(id));
    // HDS 浮动栏通过祖先节点位移定位，windowOffset 不包含这部分绘制变换。
    const node = uiContext.getFrameNodeById(id);
    if (node !== null) {
      const position = node.getPositionToWindowWithTransform();
      rect.leftPx = WindowUtils.vpToPx(Number(position.x));
      rect.topPx = WindowUtils.vpToPx(Number(position.y));
    }
    return rect;
  }

  capture(uiContext: UIContext, withSnapshot: boolean = true): PlayerDragOrigin | undefined {
    try {
      const bar = PlayerDragTransition.measure(uiContext, 'mini-player-bar');
      const cover = PlayerDragTransition.measure(uiContext, 'mini-player-cover-image');
      const viewport = PlayerDragTransition.measure(uiContext, OneShotTransitionIds.ROOT_NAVIGATION);
      if (!bar.isValid() || !cover.isValid() || !viewport.isValid()) return undefined;
      const origin = new PlayerDragOrigin();
      origin.left = WindowUtils.pxToVp(bar.leftPx - viewport.leftPx);
      origin.top = WindowUtils.pxToVp(bar.topPx - viewport.topPx);
      origin.width = WindowUtils.pxToVp(bar.widthPx);
      origin.height = WindowUtils.pxToVp(bar.heightPx);
      origin.radius = origin.height / 2;
      origin.coverLeft = WindowUtils.pxToVp(cover.leftPx - viewport.leftPx);
      origin.coverTop = WindowUtils.pxToVp(cover.topPx - viewport.topPx);
      origin.coverWidth = WindowUtils.pxToVp(cover.widthPx);
      origin.coverHeight = WindowUtils.pxToVp(cover.heightPx);
      origin.viewportWidth = WindowUtils.pxToVp(viewport.widthPx);
      origin.viewportHeight = WindowUtils.pxToVp(viewport.heightPx);
      origin.viewportLeftPx = viewport.leftPx;
      origin.viewportTopPx = viewport.topPx;
      // 截取未被父容器圆形裁剪的图片，放大时才能连续变成播放页圆角封面。
      if (withSnapshot) origin.snapshot = uiContext.getComponentSnapshot().getSync('mini-player-cover-image');
      return origin;
    } catch (_error) {
      return undefined;
    }
  }

  captureCover(uiContext: UIContext, nodeId: string, radius: number,
    withSnapshot: boolean = true): PlayerDragOrigin | undefined {
    const cover = OneShotRect.measure(uiContext, nodeId);
    const viewport = OneShotRect.measure(uiContext, OneShotTransitionIds.ROOT_NAVIGATION);
    if (cover === undefined || viewport === undefined ||
      cover.topPx >= viewport.topPx + viewport.heightPx ||
      cover.topPx + cover.heightPx <= viewport.topPx) return undefined;
    try {
      const origin = new PlayerDragOrigin();
      origin.sourceNodeId = nodeId;
      origin.radius = radius;
      origin.left = uiContext.px2vp(cover.leftPx - viewport.leftPx);
      origin.top = uiContext.px2vp(cover.topPx - viewport.topPx);
      origin.width = uiContext.px2vp(cover.widthPx);
      origin.height = uiContext.px2vp(cover.heightPx);
      origin.coverLeft = origin.left;
      origin.coverTop = origin.top;
      origin.coverWidth = origin.width;
      origin.coverHeight = origin.height;
      origin.viewportWidth = uiContext.px2vp(viewport.widthPx);
      origin.viewportHeight = uiContext.px2vp(viewport.heightPx);
      origin.viewportLeftPx = viewport.leftPx;
      origin.viewportTopPx = viewport.topPx;
      if (withSnapshot) origin.snapshot = uiContext.getComponentSnapshot().getSync(nodeId);
      return origin;
    } catch (_error) {
      return undefined;
    }
  }

  clearReturnTarget(): void {
    this.returnNodeId = 'mini-player-bar';
    this.returnRadius = 0;
  }

  begin(height: number, offsetY: number, origin: PlayerDragOrigin): boolean {
    if (this.state.active || height <= 0 || offsetY > 0 || origin.width <= 0 || origin.height <= 0) {
      OneShotTransitionCoordinator.releaseSnapshot(origin.snapshot);
      return false;
    }
    this.distance = height;
    this.generation++;
    this.returnNodeId = origin.sourceNodeId;
    this.returnRadius = origin.radius;
    this.state.sourceNodeId = origin.sourceNodeId;
    this.progress = Math.min(1, Math.max(0, -offsetY / height));
    this.state.viewportWidth = origin.viewportWidth;
    this.state.viewportHeight = origin.viewportHeight;
    this.state.frameX = origin.left;
    this.state.frameY = origin.top;
    this.state.frameWidth = origin.width;
    this.state.frameHeight = origin.height;
    this.state.radius = origin.radius;
    this.state.coverX = origin.coverLeft;
    this.state.coverY = origin.coverTop;
    this.state.coverWidth = origin.coverWidth;
    this.state.coverHeight = origin.coverHeight;
    this.state.coverRadius = origin.sourceNodeId === 'mini-player-bar'
      ? Math.min(origin.coverWidth, origin.coverHeight) / 2 : origin.radius;
    this.state.snapshot = origin.snapshot;
    this.state.contentOpacity = 0;
    this.state.sourceOpacity = 1;
    this.state.active = true;
    console.info(`[PlayerTransition] open source=${origin.sourceNodeId}` +
      ` rect=${origin.left},${origin.top},${origin.width},${origin.height}`);
    return true;
  }

  beginTap(origin: PlayerDragOrigin): boolean {
    return this.begin(origin.viewportHeight, 0, origin);
  }

  prepareReturn(uiContext: UIContext): PlayerDragOrigin | undefined {
    const origin = this.returnNodeId === 'mini-player-bar' ? this.capture(uiContext, false)
      : this.captureCover(uiContext, this.returnNodeId, this.returnRadius, false);
    if (origin === undefined) return undefined;
    try {
      const viewport = PlayerDragTransition.measure(uiContext, 'player-drag-surface');
      const cover = PlayerDragTransition.measure(uiContext, 'player-page-cover');
      if (!viewport.isValid() || !cover.isValid() || origin.top < 0 ||
        origin.top + origin.height > origin.viewportHeight + 1 || origin.left < 0 ||
        origin.left + origin.width > origin.viewportWidth + 1) return undefined;
      // 从当前播放页截取封面，不复用入场时可能已经过期的图片。
      const snapshot = uiContext.getComponentSnapshot().getSync('player-page-cover');
      this.state.viewportWidth = WindowUtils.pxToVp(viewport.widthPx);
      this.state.viewportHeight = WindowUtils.pxToVp(viewport.heightPx);
      // 返回的播控坐标也换算到播放页容器，避免安全区造成偏移。
      const offsetX = WindowUtils.pxToVp(origin.viewportLeftPx - viewport.leftPx);
      const offsetY = WindowUtils.pxToVp(origin.viewportTopPx - viewport.topPx);
      origin.left += offsetX;
      origin.top += offsetY;
      origin.coverLeft += offsetX;
      origin.coverTop += offsetY;
      this.expandToPlayer(cover, viewport);
      this.state.snapshot = snapshot;
      this.state.sourceNodeId = origin.sourceNodeId;
      this.state.contentOpacity = 1;
      this.state.sourceOpacity = 0;
      this.state.active = true;
      console.info(`[PlayerTransition] return target=${origin.left},${origin.top},${origin.width},${origin.height}`);
      return origin;
    } catch (_error) {
      return undefined;
    }
  }

  collapseToBar(origin: PlayerDragOrigin): void {
    this.state.frameX = origin.left;
    this.state.frameY = origin.top;
    this.state.frameWidth = origin.width;
    this.state.frameHeight = origin.height;
    this.state.radius = origin.radius;
    this.state.coverX = origin.coverLeft;
    this.state.coverY = origin.coverTop;
    this.state.coverWidth = origin.coverWidth;
    this.state.coverHeight = origin.coverHeight;
    this.state.coverRadius = origin.sourceNodeId === 'mini-player-bar'
      ? Math.min(origin.coverWidth, origin.coverHeight) / 2 : origin.radius;
    this.state.contentOpacity = 0;
  }

  expandToPlayer(cover: OneShotRect, viewport: OneShotRect): void {
    this.state.frameX = 0;
    this.state.frameY = 0;
    this.state.frameWidth = WindowUtils.pxToVp(viewport.widthPx);
    this.state.frameHeight = WindowUtils.pxToVp(viewport.heightPx);
    this.state.radius = 0;
    this.state.coverX = WindowUtils.pxToVp(cover.leftPx - viewport.leftPx);
    this.state.coverY = WindowUtils.pxToVp(cover.topPx - viewport.topPx);
    this.state.coverWidth = WindowUtils.pxToVp(cover.widthPx);
    this.state.coverHeight = WindowUtils.pxToVp(cover.heightPx);
    this.state.coverRadius = 16;
  }

  beginGesture(height: number, offsetY: number, commit: () => void): void {
    if (this.state.active || height <= 0 || offsetY >= 0) return;
    this.generation++;
    this.distance = height;
    this.gestureCommit = commit;
    this.update(offsetY);
  }

  update(offsetY: number): void {
    if (this.gestureCommit === undefined) return;
    this.progress = Math.min(1, Math.max(0, -offsetY / this.distance));
  }

  releaseTouch(cancelled: boolean): void {
    if (this.gestureCommit === undefined) return;
    const generation = this.generation;
    // onTouch 先于 PanGesture；先让正常 onActionEnd 使用最终速度作决定。
    setTimeout((): void => {
      if (generation !== this.generation || this.gestureCommit === undefined) return;
      this.finishGesture(!cancelled && this.progress >= 0.18);
    }, 0);
  }

  end(offsetY: number, velocityY: number): void {
    if (this.gestureCommit === undefined) return;
    this.update(offsetY);
    // 长拖或明确的向上甩动展开；往回拖/向下甩则取消，手抖不误打开。
    this.finishGesture(velocityY < 650 &&
      (this.progress >= 0.18 || (offsetY <= -24 && velocityY <= -900)));
  }

  cancel(): boolean {
    if (this.gestureCommit !== undefined) {
      this.finishGesture(false);
      return true;
    }
    return this.state.active;
  }

  private finishGesture(open: boolean): void {
    const commit = this.gestureCommit;
    this.gestureCommit = undefined;
    this.generation++;
    this.progress = 0;
    if (open) commit?.();
  }

  complete(): void {
    this.generation++;
    this.gestureCommit = undefined;
    this.progress = 0;
    this.state.active = false;
    this.state.contentOpacity = 1;
    this.state.sourceOpacity = 1;
    const snapshot = this.state.snapshot;
    this.state.snapshot = undefined;
    OneShotTransitionCoordinator.releaseSnapshot(snapshot);
  }
}
