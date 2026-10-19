import { ReaderTapPolicy, ReaderTouchTracker } from '../utils/ReaderTapPolicy';
import { emitter } from '@kit.BasicServicesKit';
import { AnimatorResult } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PageTurnMode } from '../model/TextReading';

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
  private anchor: number = 0.5;
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
      this.drawFrame(this.progress);
      if (this.released) this.settle(this.commitOnRelease);
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
    this.progress = Math.max(0, Math.min(1, distance / Math.max(1, size)));
    if (this.phase === 'dragging') this.drawFrame(this.progress);
  }

  private handlePanEnd(event: GestureEvent): void {
    if (this.phase !== 'preparing' && this.phase !== 'dragging') return;
    this.handlePanUpdate(event);
    const speed = this.mode === PageTurnMode.Vertical ? event.velocityY : event.velocityX;
    const velocity = this.forward ? -speed : speed;
    this.released = true;
    this.commitOnRelease = velocity > 650 || (velocity > -650 && this.progress >= 0.28);
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
    this.phase = 'settling';
    const animation = this.getUIContext().createAnimator({
      duration: Math.max(140, Math.round(380 * Math.abs(end - this.progress))),
      easing: 'ease-out', delay: 0, fill: 'forwards', direction: 'normal',
      iterations: 1, begin: this.progress, end: end
    });
    this.animator = animation;
    animation.onFrame = (value: number): void => {
      if (ticket !== this.serial) return;
      this.progress = value;
      this.drawFrame(value);
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
    const edge = w * (1 - p);
    const wave = Math.sin(Math.PI * p);
    const curl = w * 0.22 * wave;
    const bend = curl * 0.28;
    const skew = (this.anchor - 0.5) * curl * 0.65;
    const top = edge + skew;
    const bottom = edge - skew;

    // 原页正面沿弯曲折线裁切，逐渐露出底层目标页。
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(top, 0);
    ctx.bezierCurveTo(top - bend, h * 0.3, bottom - bend, h * 0.7, bottom, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    ctx.clip();
    this.drawPaper();
    ctx.restore();

    if (curl > 0.1) {
      // 卷起纸张在下一页上的投影。
      const shadow = ctx.createLinearGradient(edge, 0, edge + curl + 22 * wave, 0);
      shadow.addColorStop(0, 'rgba(0,0,0,0.24)');
      shadow.addColorStop(0.7, 'rgba(0,0,0,0.12)');
      shadow.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = shadow;
      ctx.fillRect(edge, 0, curl + 22 * wave, h);

      // 弯曲纸背：反射原页文字，再覆盖纸色和明暗渐变。
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(top, 0);
      ctx.bezierCurveTo(top - bend, h * 0.3, bottom - bend, h * 0.7, bottom, h);
      ctx.lineTo(bottom + curl * 0.65, h);
      ctx.bezierCurveTo(bottom + curl, h * 0.7, top + curl, h * 0.3, top + curl * 0.65, 0);
      ctx.closePath();
      ctx.clip();
      ctx.fillStyle = this.paperColor;
      ctx.fillRect(edge - curl, 0, curl * 3, h);
      ctx.save();
      ctx.translate(edge * 2 + curl * 0.65, 0);
      ctx.scale(-1, 1);
      ctx.globalAlpha = 0.16;
      this.drawPaper();
      ctx.restore();
      const fold = ctx.createLinearGradient(edge - bend, 0, edge + curl, 0);
      fold.addColorStop(0, 'rgba(0,0,0,0.22)');
      fold.addColorStop(0.22, 'rgba(255,255,255,0.18)');
      fold.addColorStop(0.65, 'rgba(255,255,255,0.06)');
      fold.addColorStop(1, 'rgba(0,0,0,0.18)');
      ctx.fillStyle = fold;
      ctx.fillRect(edge - curl, 0, curl * 3, h);
      ctx.restore();
    }
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
