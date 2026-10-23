import { ReaderTapPolicy, ReaderTouchTracker } from '../utils/ReaderTapPolicy';
import { emitter } from '@kit.BasicServicesKit';
import { AnimatorResult, FrameCallback } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PageTurnMode } from '../model/TextReading';
import { ReaderCurlGeometry } from '../utils/ReaderCurlGeometry';

class ReaderTurnFrame extends FrameCallback {
  private draw: () => void;
  constructor(draw: () => void) { super(); this.draw = draw; }
  onFrame(_time: number): void { this.draw(); }
}

/** 只预览目标页；动画完成才通知阅读页提交进度，回弹不改变阅读位置。 */
@ComponentV2
export struct ReaderPageTurnComponent {
  @Param selectionActive: boolean = false;
  @Param tapLeftPercent: number = 33;
  @Param tapRightPercent: number = 33;
  @Param tapTopPercent: number = 33;
  @Param tapBottomPercent: number = 33;
  @Param tapRegions: string = ReaderTapPolicy.DEFAULT;
  @Param safeLeft: number = 0;
  @Param safeRight: number = 0;
  @Param safeTop: number = 0;
  @Param safeBottom: number = 0;
  private tapTracker: ReaderTouchTracker = new ReaderTouchTracker();
  @Param keyTurnRequest: number = 0;
  @Param mode: string = PageTurnMode.Cover;
  @Param revision: string = '';
  @Param paperColor: string = '#F5F2EA';
  @BuilderParam pageContent: () => void = this.emptyPage;
  @Event onPrepare: (forward: boolean) => Promise<boolean> = async (_forward: boolean): Promise<boolean> => false;
  @Event onConfirm: () => void = (): void => {};
  @Event onComplete: (commit: boolean) => void = (_commit: boolean): void => {};
  @Event onCenterTap: () => void = (): void => {};

  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private snapshot: image.PixelMap | null = null;
  private snapshotImage: ImageBitmap | null = null;
  private animator: AnimatorResult | null = null;
  private snapshotId: string = `reader-turn-${this.getUniqueId()}`;
  private canvasReady: boolean = false;
  private pageWidth: number = 0;
  private pageHeight: number = 0;
  private phase: string = 'idle';
  private serial: number = 0;
  private forward: boolean = true;
  private progress: number = 0;
  private renderedProgress: number = 0;
  private anchor: number = 0.5;
  private verticalDrag: number = 0;
  private releaseVertical: number = 0;
  private settleStart: number = 0;
  private frameQueued: boolean = false;
  private released: boolean = false;
  private commitOnRelease: boolean = false;
  private touchBlocked: boolean = false;
  private touchStartedAt: number = 0;
  private touchStartedSelecting: boolean = false;

  private backgroundHandler = (): void => {
    this.cancelTurn(this.phase === 'settling' && this.commitOnRelease);
  };

  aboutToAppear(): void {
    emitter.on('app.reader.background', this.backgroundHandler);
  }

  @Monitor('keyTurnRequest')
  onKeyTurnRequested(): void {
    this.beginTurn(this.keyTurnRequest > 0, true, this.pageHeight / 2);
  }

  @Monitor('mode', 'revision')
  onReaderChanged(): void {
    this.cancelTurn(this.phase === 'settling' && this.commitOnRelease);
  }

  aboutToDisappear(): void {
    emitter.off('app.reader.background', this.backgroundHandler);
    this.cancelTurn(this.phase === 'settling' && this.commitOnRelease);
    this.canvasReady = false;
  }

  private releaseSnapshot(): void {
    this.snapshotImage?.close();
    this.snapshotImage = null;
    const bitmap = this.snapshot;
    this.snapshot = null;
    if (bitmap !== null) bitmap.release().catch((): void => {});
  }

  private cancelTurn(commit: boolean = false): void {
    const wasActive = this.phase !== 'idle';
    this.serial++;
    this.frameQueued = false;
    this.phase = 'idle';
    const running = this.animator;
    this.animator = null;
    if (running !== null) running.cancel();
    if (wasActive) this.onComplete(commit);
    if (this.canvasReady) this.canvas.clearRect(0, 0, this.pageWidth, this.pageHeight);
    this.releaseSnapshot();
  }

  private async beginTurn(forward: boolean, tap: boolean, anchorY: number): Promise<void> {
    if (this.phase !== 'idle' || !this.canvasReady || this.pageWidth <= 0) return;
    const ticket = ++this.serial;
    this.phase = 'preparing';
    this.forward = forward;
    this.progress = 0;
    this.renderedProgress = 0;
    this.verticalDrag = 0;
    this.anchor = Math.max(0, Math.min(1, anchorY / Math.max(1, this.pageHeight)));
    this.released = tap;
    this.commitOnRelease = tap;
    try {
      if (this.mode === PageTurnMode.None && tap) {
        const prepared = await this.onPrepare(forward);
        if (ticket !== this.serial) return;
        this.phase = 'idle';
        this.onComplete(prepared);
        return;
      }
      const bitmap = await this.getUIContext().getComponentSnapshot().get(this.snapshotId);
      if (ticket !== this.serial) {
        bitmap.release().catch((): void => {});
        return;
      }
      this.snapshot = bitmap;
      this.snapshotImage = new ImageBitmap(bitmap);
      // 先用原页覆盖，再异步准备底层目标页，避免等待正文时提前跳页。
      this.drawFrame(0);
      const prepared = await this.onPrepare(forward);
      if (ticket !== this.serial) return;
      if (!prepared) {
        this.cancelTurn();
        return;
      }
      this.phase = 'dragging';
      // 快划可能在截图/目标页准备期间已结束，从已显示的纸面接续，不跳过卷起阶段。
      if (this.released) this.settle(this.commitOnRelease);
      else this.drawFrame(this.progress);
    } catch (e) {
      if (ticket === this.serial) {
        hilog.warn(0, 'ReaderPageTurn', 'page capture/animation failed: %{public}s',
          e instanceof Error ? e.message : String(e));
        this.cancelTurn();
      }
    }
  }

  private handleTouch(event: TouchEvent): void {
    this.tapTracker.update(event);
    if (event.type === TouchType.Down) {
      this.touchStartedAt = Date.now();
      this.touchStartedSelecting = this.selectionActive;
      const touch = event.touches[0];
      // 整段手势沿用落点判定，避免从状态栏下拉到正文后触发翻页。
      this.touchBlocked = touch === undefined || touch.y < this.safeTop || touch.x < this.safeLeft ||
        touch.x >= this.pageWidth - this.safeRight || touch.y >= this.pageHeight - this.safeBottom;
    } else if (event.type === TouchType.Up) {
      const touch = event.changedTouches[0] ?? event.touches[0];
      // 点击走原始触摸链，避免原生选字的识别器吞掉工具栏点击。
      // 长按及从活动选区开始的操作只处理选字，不转成翻页或工具栏点击。
      if (touch !== undefined && !this.touchStartedSelecting && Date.now() - this.touchStartedAt < 500) {
        this.handleTap(touch.x, touch.y);
      }
    } else if (event.type === TouchType.Cancel) {
      this.touchBlocked = true;
      this.handlePanCancel();
    }
  }

  private handlePanStart(event: GestureEvent): void {
    if (this.selectionActive) return;
    this.tapTracker.cancel();
    const finger = event.fingerList[0];
    if (this.touchBlocked || finger === undefined ||
      finger.localY - event.offsetY < this.safeTop) return;
    this.beginTurn((this.mode === PageTurnMode.Vertical ? event.offsetY : event.offsetX) < 0, false, finger !== undefined ? finger.localY : this.pageHeight / 2);
    this.handlePanUpdate(event);
  }

  private handlePanUpdate(event: GestureEvent): void {
    if (this.phase !== 'preparing' && this.phase !== 'dragging') return;
    const offset = this.mode === PageTurnMode.Vertical ? event.offsetY : event.offsetX;
    const distance = this.forward ? -offset : offset;
    const size = this.mode === PageTurnMode.Vertical ? this.pageHeight : this.pageWidth;
    // 折线移动一份，反折纸边移动两份；仿真进度以两倍页宽为完整行程。
    const travel = this.mode === PageTurnMode.Simulation ? size * 2 : size;
    this.progress = Math.max(0, Math.min(1, distance / Math.max(1, travel)));
    this.verticalDrag = event.offsetY;
    if (this.phase === 'dragging') this.scheduleFrame();
  }

  private handlePanEnd(event: GestureEvent): void {
    if (this.phase !== 'preparing' && this.phase !== 'dragging') return;
    this.handlePanUpdate(event);
    const speed = this.mode === PageTurnMode.Vertical ? event.velocityY : event.velocityX;
    const velocity = this.forward ? -speed : speed;
    this.released = true;
    const threshold = this.mode === PageTurnMode.Simulation ? 0.14 : 0.28;
    this.commitOnRelease = velocity > 650 || (velocity > -650 && this.progress >= threshold);
    if (this.phase === 'dragging') this.settle(this.commitOnRelease);
  }

  private handlePanCancel(): void {
    // 系统返回桌面的 Cancel 不得撤销已经松手确认、正在收尾的翻页。
    if (this.released || (this.phase !== 'preparing' && this.phase !== 'dragging')) return;
    this.released = true;
    this.commitOnRelease = false;
    if (this.phase === 'dragging') this.settle(false);
  }

  private handleTap(x: number, y: number): void {
    if (this.selectionActive || this.phase !== 'idle' || this.touchBlocked || !this.tapTracker.canTap()) return;
    const action = ReaderTapPolicy.resolve(this.tapRegions, x - this.safeLeft,
      y - this.safeTop, this.pageWidth - this.safeLeft - this.safeRight,
      this.pageHeight - this.safeTop - this.safeBottom, this.tapLeftPercent, this.tapRightPercent, this.tapTopPercent, this.tapBottomPercent);
    if (action === 0 || action === 2) this.beginTurn(action === 2, true, y);
    else if (action === 1) this.onCenterTap();
  }

  private settle(commit: boolean): void {
    if (commit) this.onConfirm();
    if (this.mode === PageTurnMode.None) {
      this.phase = 'idle';
      this.onComplete(commit);
      this.canvas.clearRect(0, 0, this.pageWidth, this.pageHeight);
      this.releaseSnapshot();
      return;
    }
    const ticket = this.serial;
    const end = commit ? 1 : 0;
    const simulation = this.mode === PageTurnMode.Simulation;
    if (simulation) this.progress = this.renderedProgress;
    this.releaseVertical = this.verticalDrag;
    this.settleStart = this.progress;
    this.phase = 'settling';
    const animation = this.getUIContext().createAnimator({
      duration: simulation ? (commit ? Math.max(300, Math.round(520 * Math.sqrt(1 - this.progress))) :
        Math.max(180, Math.round(320 * Math.sqrt(this.progress)))) :
        Math.max(140, Math.round(380 * Math.abs(end - this.progress))),
      easing: simulation && commit ? 'ease-in-out' : 'ease-out',
      delay: 0, fill: 'forwards', direction: 'normal',
      iterations: 1, begin: this.progress, end: end
    });
    this.animator = animation;
    animation.onFrame = (value: number): void => {
      if (ticket !== this.serial) return;
      this.progress = value;
      const remaining = Math.abs(end - this.settleStart);
      this.verticalDrag = this.releaseVertical * (remaining > 0.001 ? Math.abs(end - value) / remaining : 0);
      this.scheduleFrame();
    };
    animation.onFinish = (): void => {
      if (ticket !== this.serial) return;
      this.animator = null;
      this.phase = 'idle';
      this.onComplete(commit);
      this.canvas.clearRect(0, 0, this.pageWidth, this.pageHeight);
      this.releaseSnapshot();
    };
    animation.play();
  }

  /** 同一显示帧只画最新手势位置，不把高频触摸事件逐个堆入 Canvas。 */
  private scheduleFrame(): void {
    if (this.frameQueued) return;
    this.frameQueued = true;
    const ticket = this.serial;
    this.getUIContext().postFrameCallback(new ReaderTurnFrame((): void => {
      if (ticket !== this.serial) return;
      this.frameQueued = false;
      if (this.phase === 'dragging' || this.phase === 'settling') this.drawFrame(this.progress);
    }));
  }

  /** 前一页的几何方向反转，但正文位图保持正常阅读方向。 */
  private drawPaper(): void {
    const bitmap = this.snapshotImage;
    if (bitmap === null) return;
    this.canvas.save();
    if (!this.forward) {
      this.canvas.translate(this.pageWidth, 0);
      this.canvas.scale(-1, 1);
    }
    this.canvas.fillStyle = this.paperColor;
    this.canvas.fillRect(0, 0, this.pageWidth, this.pageHeight);
    this.canvas.drawImage(bitmap, 0, 0, this.pageWidth, this.pageHeight);
    this.canvas.restore();
  }

  private drawFrame(value: number): void {
    if (!this.canvasReady || this.snapshot === null) return;
    const ctx = this.canvas;
    const w = this.pageWidth;
    const h = this.pageHeight;
    const p = this.mode === PageTurnMode.None ? 0 : Math.max(0, Math.min(1, value));
    this.renderedProgress = p;
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, w, h);
    ctx.save();
    if (this.mode === PageTurnMode.Vertical) {
      ctx.translate(0, (this.forward ? -1 : 1) * h * p);
      ctx.fillStyle = this.paperColor;
      ctx.fillRect(0, 0, w, h);
      if (this.snapshotImage !== null) ctx.drawImage(this.snapshotImage, 0, 0, w, h);
      ctx.restore();
      return;
    }
    if (!this.forward) {
      ctx.translate(w, 0);
      ctx.scale(-1, 1);
    }
    if (this.mode !== PageTurnMode.Simulation) {
      ctx.translate(-w * p, 0);
      this.drawPaper();
      ctx.restore();
      return;
    }
    if (p <= 0.0001) {
      this.drawPaper();
    } else if (p < 0.9999) {
      this.drawCurl(new ReaderCurlGeometry(w, h, p, this.anchor, this.verticalDrag));
    }
    ctx.restore();
  }

  private drawCurl(shape: ReaderCurlGeometry): void {
    const ctx = this.canvas;
    const outline = shape.shadowOutline(this.pageWidth, this.pageHeight);
    if (outline.length > 2) {
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(outline[0].x, outline[0].y);
      for (let i = 1; i < outline.length; i++) ctx.lineTo(outline[i].x, outline[i].y);
      ctx.closePath();
      // 不对整页做逐帧高斯模糊；用投影轮廓绘制接触阴影。
      ctx.fillStyle = 'rgba(0,0,0,0.12)';
      ctx.fill();
      ctx.restore();
    }

    // 曲面最多 8 条，源位图按条带包围盒裁取；平直区域各一次。
    ctx.save();
    ctx.transform(shape.nx, shape.ny, -shape.ny, shape.nx, 0, 0);
    this.drawCurlStrip(shape, shape.min, Math.min(shape.fold, shape.max), false, 0);
    const arc = Math.PI * shape.radius;
    for (let i = 0; i < 8; i++) {
      const start = shape.fold + arc * i / 8;
      const end = Math.min(shape.max, shape.fold + arc * (i + 1) / 8);
      const angle = Math.PI * (i + 0.5) / 8;
      this.drawCurlStrip(shape, Math.max(shape.min, start), end, i >= 4,
        0.22 * Math.pow(Math.sin(angle), 3));
    }
    this.drawCurlStrip(shape, Math.max(shape.min, shape.fold + arc), shape.max, true, 0.025);
    ctx.restore();
  }

  private drawCurlStrip(shape: ReaderCurlGeometry, start: number, end: number,
    back: boolean, shade: number): void {
    if (end <= start) return;
    const left = shape.project(start);
    const right = shape.project(end);
    const scale = (right - left) / (end - start);
    if (Math.abs(scale) < 0.0001) return;
    const ctx = this.canvas;
    ctx.save();
    ctx.beginPath();
    // 少量重叠消除抗锯齿接缝，正文与纸背都限制在原页边界内。
    ctx.rect(Math.min(left, right) - 0.2, -shape.extent, Math.abs(right - left) + 0.4, shape.extent * 2);
    ctx.clip();
    ctx.translate(left, 0);
    ctx.scale(scale, 1);
    ctx.translate(-start, 0);
    ctx.transform(shape.nx, -shape.ny, shape.ny, shape.nx, 0, 0);
    this.drawPaperStrip(shape, start, end);
    if (back) {
      ctx.globalAlpha = 0.9;
      ctx.fillStyle = this.paperColor;
      ctx.fillRect(0, 0, this.pageWidth, this.pageHeight);
      ctx.globalAlpha = 1;
    }
    if (shade > 0) {
      ctx.fillStyle = `rgba(0,0,0,${shade})`;
      ctx.fillRect(0, 0, this.pageWidth, this.pageHeight);
      // 深色纸面也保留卷曲高光，不让暗色主题的折痕消失。
      ctx.fillStyle = `rgba(255,255,255,${shade * 0.32})`;
      ctx.fillRect(0, 0, this.pageWidth, this.pageHeight);
    }
    ctx.restore();
  }

  private drawPaperStrip(shape: ReaderCurlGeometry, start: number, end: number): void {
    const bitmap = this.snapshotImage;
    if (bitmap === null) return;
    const w = this.pageWidth;
    const h = this.pageHeight;
    // nx 始终为正；斜条带在页面顶/底的交点给出保守且有界的源矩形。
    const x0 = Math.max(0, Math.min(start / shape.nx, (start - shape.ny * h) / shape.nx));
    const x1 = Math.min(w, Math.max(end / shape.nx, (end - shape.ny * h) / shape.nx));
    if (x1 <= x0) return;
    const ctx = this.canvas;
    ctx.save();
    const x = this.forward ? x0 : w - x1;
    if (!this.forward) { ctx.translate(w, 0); ctx.scale(-1, 1); }
    ctx.fillStyle = this.paperColor;
    ctx.fillRect(x, 0, x1 - x0, h);
    ctx.drawImage(bitmap, x / w * bitmap.width, 0, (x1 - x0) / w * bitmap.width, bitmap.height,
      x, 0, x1 - x0, h);
    ctx.restore();
  }

  @Builder
  emptyPage(): void {
    Column()
  }

  build() {
    Stack() {
      Stack() {
        this.pageContent()
      }
      .width('100%')
      .height('100%')
      .id(this.snapshotId)

      Canvas(this.canvas)
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
        .onReady((): void => {
          this.canvasReady = true;
        })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
      if (typeof size.width !== 'number' || typeof size.height !== 'number') return;
      if (this.pageWidth !== size.width || this.pageHeight !== size.height) {
        this.cancelTurn(this.phase === 'settling' && this.commitOnRelease);
      }
      this.pageWidth = size.width;
      this.pageHeight = size.height;
    })
    .onTouch((event: TouchEvent): void => this.handleTouch(event))
    .gesture(PanGesture({ fingers: 1, direction: this.mode === PageTurnMode.Vertical ? PanDirection.Vertical : PanDirection.Horizontal, distance: 8 })
        .onActionStart((event: GestureEvent): void => this.handlePanStart(event))
        .onActionUpdate((event: GestureEvent): void => this.handlePanUpdate(event))
        .onActionEnd((event: GestureEvent): void => this.handlePanEnd(event))
        .onActionCancel((): void => this.handlePanCancel()))
  }
}
