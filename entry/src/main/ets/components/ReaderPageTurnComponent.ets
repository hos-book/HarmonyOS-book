import { ReaderTapPolicy, ReaderTouchTracker } from '../utils/ReaderTapPolicy';
import { emitter } from '@kit.BasicServicesKit';
import { AnimatorResult, FrameCallback } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PageTurnMode } from '../model/TextReading';
import { ReaderCurlGeometry, ReaderCurlPoint } from '../utils/ReaderCurlGeometry';
import { ReaderSpreadGeometry } from '../utils/ReaderSpreadGeometry';
import { PerformanceTrace } from '../utils/PerformanceTrace';

class ReaderTurnFrame extends FrameCallback {
  private draw: () => void;
  constructor(draw: () => void) { super(); this.draw = draw; }
  onFrame(_time: number): void { this.draw(); }
}

class ReaderTurnLayoutFrame extends FrameCallback {
  private complete: () => void;
  constructor(complete: () => void) { super(); this.complete = complete; }
  onFrame(_time: number): void {}
  onIdle(_time: number): void { this.complete(); }
}

/** 只保留最近一次输入；交接时仍能接收该次滑动的移动、松手和取消。 */
class ReaderTurnInput {
  forward: boolean;
  tap: boolean;
  anchorY: number;
  progress: number = 0;
  verticalDrag: number = 0;
  released: boolean;
  commit: boolean;

  constructor(forward: boolean, tap: boolean, anchorY: number) {
    this.forward = forward;
    this.tap = tap;
    this.anchorY = anchorY;
    this.released = tap;
    this.commit = tap;
  }
}

class ReaderPanSample {
  offsetX: number;
  offsetY: number;
  velocityX: number;
  velocityY: number;
  localX: number;
  localY: number;
  constructor(event: GestureEvent) {
    this.offsetX = event.offsetX; this.offsetY = event.offsetY;
    this.velocityX = event.velocityX; this.velocityY = event.velocityY;
    this.localX = event.fingerList?.[0]?.localX ?? 0;
    this.localY = event.fingerList?.[0]?.localY ?? 0;
  }
}

class ReaderContentPan {
  start: ReaderPanSample;
  latest: ReaderPanSample;
  pending: boolean = true;
  released: boolean = false;
  cancelled: boolean = false;
  constructor(event: ReaderPanSample) { this.start = event; this.latest = event; }
}

/** 只预览目标页；动画完成才通知阅读页提交进度，回弹不改变阅读位置。 */
@ComponentV2
export struct ReaderPageTurnComponent {
  @Param selectionActive: boolean = false;
  @Param ignoreChildGestures: boolean = false;
  @Event onContentTap: (x: number, y: number) => Promise<boolean> = async (): Promise<boolean> => false;
  @Event onContentPanStart: (x: number, y: number, dx: number, dy: number) => Promise<boolean> = async (): Promise<boolean> => false;
  @Param tapLeftPercent: number = 33;
  @Param tapRightPercent: number = 33;
  @Param tapTopPercent: number = 33;
  @Param tapBottomPercent: number = 33;
  @Param tapRegions: string = ReaderTapPolicy.DEFAULT;
  @Param safeLeft: number = 0;
  @Param safeRight: number = 0;
  @Param safeTop: number = 0;
  @Param safeBottom: number = 0;
  @Param footerHeight: number = 0;
  private tapTracker: ReaderTouchTracker = new ReaderTouchTracker();
  @Param keyTurnRequest: number = 0;
  @Param mode: string = PageTurnMode.Cover;
  @Param spread: boolean = false;
  @Param revision: string = '';
  @Param paperColor: string = '#F5F2EA';
  @BuilderParam pageContent: () => void = this.emptyPage;
  @Event onPrepare: (forward: boolean) => Promise<boolean> = async (_forward: boolean): Promise<boolean> => false;
  @Event onTurnFeedback: (forward: boolean) => void = (): void => {};
  @Event onConfirm: () => void = (): void => {};
  @Event onComplete: (commit: boolean) => void | Promise<void> = (_commit: boolean): void => {};
  @Event onCenterTap: () => void = (): void => {};

  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private snapshot: image.PixelMap | null = null;
  private snapshotImage: ImageBitmap | null = null;
  private targetSnapshot: image.PixelMap | null = null;
  private targetImage: ImageBitmap | null = null;
  @Local coverSnapshot: image.PixelMap | null = null;
  @Local coverOffset: number = 0;
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
  private renderedVertical: number = 0;
  private anchor: number = 0.5;
  private verticalDrag: number = 0;
  private releaseVertical: number = 0;
  private settleStart: number = 0;
  private frameQueued: boolean = false;
  private released: boolean = false;
  private commitOnRelease: boolean = false;
  private feedbackOnConfirm: boolean = false;
  private pendingTurn: ReaderTurnInput | null = null;
  private settleAccelerated: boolean = false;
  private touchBlocked: boolean = false;
  private touchStartedAt: number = 0;
  private touchStartedSelecting: boolean = false;
  private contentPan: ReaderContentPan | null = null;

  private backgroundHandler = (): void => {
    this.cancelTurn(this.phase === 'settling' && this.commitOnRelease);
  };

  aboutToAppear(): void {
    emitter.on('app.reader.background', this.backgroundHandler);
  }

  @Monitor('keyTurnRequest')
  onKeyTurnRequested(): void {
    this.requestTurn(this.keyTurnRequest > 0, true, this.pageHeight / 2);
  }

  @Monitor('mode', 'spread')
  onTurnModeChanged(): void {
    this.cancelTurn(this.phase === 'settling' && this.commitOnRelease);
  }

  @Monitor('paperColor', 'safeTop', 'safeBottom', 'footerHeight')
  onPaperAppearanceChanged(): void {
    if (this.phase === 'idle') this.drawRestingSpine();
  }

  @Monitor('revision')
  onReaderChanged(): void {
    // 本次提交也会更新页码 revision；等布局交接完成后才允许开始下一次翻页。
    if (this.phase === 'completing') return;
    this.cancelTurn(this.phase === 'settling' && this.commitOnRelease);
  }

  aboutToDisappear(): void {
    emitter.off('app.reader.background', this.backgroundHandler);
    this.cancelTurn(this.phase === 'settling' && this.commitOnRelease);
    this.canvasReady = false;
  }

  private releaseSnapshot(): void {
    this.coverSnapshot = null;
    this.coverOffset = 0;
    this.snapshotImage?.close();
    this.snapshotImage = null;
    this.targetImage?.close();
    this.targetImage = null;
    const target = this.targetSnapshot;
    this.targetSnapshot = null;
    if (target !== null) target.release().catch((): void => {});
    const bitmap = this.snapshot;
    this.snapshot = null;
    // Image 节点先提交移除，再释放其 PixelMap。
    if (bitmap !== null) {
      let released = false;
      const release = (): void => {
        if (released) return;
        released = true;
        bitmap.release().catch((): void => {});
      };
      // 退后台或组件卸载后可能没有下一显示帧，超时也要释放截图。
      const timer = setTimeout(release, 100);
      this.getUIContext().postFrameCallback(new ReaderTurnLayoutFrame((): void => {
        clearTimeout(timer); release();
      }));
    }
  }

  private cancelTurn(commit: boolean = false): void {
    this.cancelContentPan();
    this.pendingTurn = null;
    if (this.phase === 'completing') return;
    const wasActive = this.phase !== 'idle';
    this.serial++;
    this.frameQueued = false;
    this.phase = 'idle';
    const running = this.animator;
    this.animator = null;
    if (running !== null) running.cancel();
    if (wasActive) { this.finishTurn(commit, this.serial); return; }
    this.drawRestingSpine();
    this.releaseSnapshot();
  }

  private async finishTurn(commit: boolean, ticket: number): Promise<void> {
    if (ticket !== this.serial || this.phase === 'completing') return;
    this.phase = 'completing';
    const trace = PerformanceTrace.begin('ReaderTurn.Commit');
    try { await this.onComplete(commit); }
    catch (e) {
      this.pendingTurn = null;
      hilog.warn(0, 'ReaderPageTurn', 'page completion failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
    finally {
      PerformanceTrace.end('ReaderTurn.Commit', trace);
      if (ticket === this.serial) {
        // 仿真取消时底层仍是预览页，等还原/提交完成布局后再撤去纸面，避免闪出另一页。
        if (this.mode === PageTurnMode.Simulation && this.canvasReady) await this.pageFrame(100);
        this.drawRestingSpine();
        this.releaseSnapshot();
        // 先提交父页面的位置及截图移除，避免截到旧页或被迟到的 revision 撤销。
        if (this.mode === PageTurnMode.Cover && this.canvasReady) await this.pageFrame(100);
        if (ticket === this.serial) {
          this.phase = 'idle';
          this.startPendingTurn();
        }
      }
    }
  }

  private requestTurn(forward: boolean, tap: boolean, anchorY: number): boolean {
    if (!this.canvasReady || this.pageWidth <= 0 || this.selectionActive) return false;
    if (this.phase === 'idle') {
      this.beginTurn(forward, tap, anchorY);
      return true;
    }
    if (this.mode !== PageTurnMode.Cover || this.phase === 'dragging' ||
      (this.phase === 'preparing' && !this.released)) return false;
    this.pendingTurn = new ReaderTurnInput(forward, tap, anchorY);
    if (this.phase === 'settling' && !this.settleAccelerated) {
      const running = this.animator;
      this.animator = null;
      if (running !== null) running.cancel();
      this.animateSettle(this.commitOnRelease, true);
    }
    return true;
  }

  private startPendingTurn(): void {
    const input = this.pendingTurn;
    this.pendingTurn = null;
    if (input === null || this.mode !== PageTurnMode.Cover || this.selectionActive ||
      (!input.tap && input.released && !input.commit)) return;
    this.beginTurn(input.forward, input.tap, input.anchorY, input);
  }

  private async beginTurn(forward: boolean, tap: boolean, anchorY: number,
    input: ReaderTurnInput | null = null): Promise<void> {
    if (this.phase !== 'idle' || !this.canvasReady || this.pageWidth <= 0) return;
    const ticket = ++this.serial;
    this.phase = 'preparing';
    this.forward = forward;
    this.progress = input !== null ? input.progress : 0;
    this.renderedProgress = 0;
    this.verticalDrag = input !== null ? input.verticalDrag : 0;
    this.frameQueued = false;
    this.settleAccelerated = false;
    this.anchor = Math.max(0, Math.min(1, anchorY / Math.max(1, this.pageHeight)));
    this.released = input !== null ? input.released : tap;
    this.commitOnRelease = input !== null ? input.commit : tap;
    this.feedbackOnConfirm = !tap;
    // 点击反馈先于截图、跨章加载和动画；拖动则等确认翻页再反馈。
    if (tap) this.onTurnFeedback(forward);
    try {
      if (this.mode === PageTurnMode.None && tap) {
        const prepared = await this.preparePage(forward);
        if (ticket !== this.serial) return;
        await this.finishTurn(prepared, ticket);
        return;
      }
      const bitmap = await this.capturePage();
      if (ticket !== this.serial) {
        bitmap.release().catch((): void => {});
        return;
      }
      this.snapshot = bitmap;
      if (this.mode === PageTurnMode.Cover) {
        this.coverOffset = 0;
        this.coverSnapshot = bitmap;
        this.canvas.clearRect(0, 0, this.pageWidth, this.pageHeight);
      } else this.snapshotImage = new ImageBitmap(bitmap);
      // 先用原页覆盖，再异步准备底层目标页，避免等待正文时提前跳页。
      this.drawFrame(0);
      await this.pageFrame();
      if (ticket !== this.serial) return;
      const prepared = await this.preparePage(forward);
      if (ticket !== this.serial) return;
      if (!prepared) {
        this.cancelTurn();
        return;
      }
      // 目标页状态必须完成布局再开始动画，避免边翻边补正文。
      await this.pageFrame();
      if (ticket !== this.serial) return;
      if (this.spread && this.mode === PageTurnMode.Simulation) {
        // 布局 onIdle 不代表原生正文节点已提交绘制；必须等待渲染完成才缓存纸背。
        const target = await this.capturePage();
        if (ticket !== this.serial) { target.release().catch((): void => {}); return; }
        this.targetSnapshot = target;
        this.targetImage = new ImageBitmap(target);
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

  private async capturePage(): Promise<image.PixelMap> {
    const trace = PerformanceTrace.begin('ReaderTurn.Capture');
    try {
      return await this.getUIContext().getComponentSnapshot().get(this.snapshotId,
        { waitUntilRenderFinished: true });
    } finally { PerformanceTrace.end('ReaderTurn.Capture', trace); }
  }

  private async preparePage(forward: boolean): Promise<boolean> {
    const trace = PerformanceTrace.begin('ReaderTurn.Prepare');
    try { return await this.onPrepare(forward); }
    finally { PerformanceTrace.end('ReaderTurn.Prepare', trace); }
  }

  private async pageFrame(timeout: number = 0): Promise<void> {
    const trace = PerformanceTrace.begin('ReaderTurn.Layout');
    try {
      await new Promise<void>((resolve): void => {
        const timer = timeout > 0 ? setTimeout(resolve, timeout) : -1;
        this.getUIContext().postFrameCallback(new ReaderTurnLayoutFrame((): void => {
          if (timer >= 0) clearTimeout(timer);
          resolve();
        }));
      });
    } finally { PerformanceTrace.end('ReaderTurn.Layout', trace); }
  }

  private handleTouch(event: TouchEvent): void {
    this.tapTracker.update(event);
    if (event.type === TouchType.Down) {
      this.cancelContentPan();
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
    if (this.ignoreChildGestures && this.phase === 'idle') {
      // 跨 Web 桥异步命中测试只保留值快照，不能在回调结束后继续持有原生事件。
      const input = new ReaderContentPan(new ReaderPanSample(event));
      this.contentPan = input;
      this.startContentPan(input);
      return;
    }
    this.beginPagePan(new ReaderPanSample(event));
  }

  private beginPagePan(event: ReaderPanSample): void {
    // 精排接收双轴输入供书内滚动使用；普通翻页仍只响应所选方向。
    if (this.ignoreChildGestures && this.mode !== PageTurnMode.Vertical &&
      Math.abs(event.offsetY) > Math.abs(event.offsetX)) return;
    if (!this.requestTurn((this.mode === PageTurnMode.Vertical ? event.offsetY : event.offsetX) < 0,
      false, event.localY - event.offsetY)) return;
    this.updatePagePan(event);
  }

  private async startContentPan(input: ReaderContentPan): Promise<void> {
    const start = input.start;
    let consumed = false;
    try {
      consumed = await this.onContentPanStart(start.localX - start.offsetX, start.localY - start.offsetY,
        start.offsetX, start.offsetY);
    } catch (_error) { /* 页面已切换时仍可按普通翻页处理。 */ }
    if (this.contentPan !== input) return;
    input.pending = false;
    if (consumed) {
      // 书内滚动由 Web 的原生滚动链和吸附处理，不再跨桥逐帧改写位置。
      if (input.released) this.contentPan = null;
      return;
    }
    this.contentPan = null;
    if (input.cancelled) return;
    this.beginPagePan(start);
    this.updatePagePan(input.latest);
    if (input.released) this.endPagePan(input.latest);
  }

  private cancelContentPan(): void {
    if (this.contentPan === null) return;
    this.contentPan.cancelled = true;
    this.contentPan = null;
  }

  private handlePanUpdate(event: GestureEvent): void {
    this.updatePagePan(new ReaderPanSample(event));
  }

  private updatePagePan(event: ReaderPanSample, render: boolean = true): void {
    const content = this.contentPan;
    if (content !== null) {
      content.latest = event;
      return;
    }
    const pending = this.pendingTurn;
    if (pending !== null && !pending.tap && !pending.released) {
      pending.progress = Math.max(0, Math.min(1,
        (pending.forward ? -event.offsetX : event.offsetX) / Math.max(1, this.pageWidth)));
      pending.verticalDrag = event.offsetY;
      return;
    }
    if (this.released || (this.phase !== 'preparing' && this.phase !== 'dragging')) return;
    const offset = this.mode === PageTurnMode.Vertical ? event.offsetY : event.offsetX;
    const distance = this.forward ? -offset : offset;
    const size = this.mode === PageTurnMode.Vertical ? this.pageHeight : this.pageWidth;
    // 折线移动一份，反折纸边移动两份；仿真进度以两倍页宽为完整行程。
    const travel = this.mode === PageTurnMode.Simulation && !this.spread ? size * 2 : size;
    this.progress = Math.max(0, Math.min(1, distance / Math.max(1, travel)));
    this.verticalDrag = event.offsetY;
    if (render && this.phase === 'dragging') {
      // Image 的位移由 ArkUI 合并提交；再排帧会让手指位置多等待一轮 VSync。
      if (this.mode === PageTurnMode.Cover) this.drawFrame(this.progress);
      else this.scheduleFrame();
    }
  }

  private handlePanEnd(event: GestureEvent): void {
    this.endPagePan(new ReaderPanSample(event));
  }

  private endPagePan(event: ReaderPanSample): void {
    const content = this.contentPan;
    if (content !== null) {
      content.latest = event; content.released = true;
      if (!content.pending) {
        this.contentPan = null;
      }
      return;
    }
    const pending = this.pendingTurn;
    if (pending !== null && !pending.tap && !pending.released) {
      this.updatePagePan(event);
      const velocity = pending.forward ? -event.velocityX : event.velocityX;
      pending.released = true;
      pending.commit = velocity > 650 || (velocity > -650 && pending.progress >= 0.28);
      return;
    }
    if (this.released || (this.phase !== 'preparing' && this.phase !== 'dragging')) return;
    // 松手样本只参与提交判定，收尾仍从上一笔已提交的纸面位置接续。
    this.updatePagePan(event, false);
    const speed = this.mode === PageTurnMode.Vertical ? event.velocityY : event.velocityX;
    const velocity = this.forward ? -speed : speed;
    this.released = true;
    const threshold = this.mode === PageTurnMode.Simulation && !this.spread ? 0.14 : 0.28;
    this.commitOnRelease = velocity > 650 || (velocity > -650 && this.progress >= threshold);
    if (this.phase === 'dragging') this.settle(this.commitOnRelease);
  }

  private handlePanCancel(): void {
    this.cancelContentPan();
    if (this.pendingTurn !== null && !this.pendingTurn.tap) {
      this.pendingTurn = null;
      return;
    }
    // 系统返回桌面的 Cancel 不得撤销已经松手确认、正在收尾的翻页。
    if (this.released || (this.phase !== 'preparing' && this.phase !== 'dragging')) return;
    this.released = true;
    this.commitOnRelease = false;
    if (this.phase === 'dragging') this.settle(false);
  }

  private async handleTap(x: number, y: number): Promise<void> {
    if (this.selectionActive || this.touchBlocked || !this.tapTracker.canTap() ||
      (this.phase !== 'idle' && this.mode !== PageTurnMode.Cover)) return;
    // 动画中的 Web 已是目标页；此时不能把截图上的点击命中到底层链接。
    if (this.ignoreChildGestures && this.phase === 'idle') {
      const ticket = this.serial;
      if (await this.onContentTap(x, y) || ticket !== this.serial || this.phase !== 'idle' ||
        this.selectionActive || !this.tapTracker.canTap()) return;
    }
    const action = ReaderTapPolicy.resolve(this.tapRegions, x - this.safeLeft,
      y - this.safeTop, this.pageWidth - this.safeLeft - this.safeRight,
      this.pageHeight - this.safeTop - this.safeBottom, this.tapLeftPercent, this.tapRightPercent, this.tapTopPercent, this.tapBottomPercent);
    if (action === 0 || action === 2) this.requestTurn(action === 2, true, y);
    else if (action === 1 && this.phase === 'idle') this.onCenterTap();
  }

  private settle(commit: boolean): void {
    if (commit && this.feedbackOnConfirm) {
      this.feedbackOnConfirm = false;
      this.onTurnFeedback(this.forward);
    }
    if (commit) this.onConfirm();
    if (this.mode === PageTurnMode.None) {
      this.finishTurn(commit, this.serial);
      return;
    }
    this.animateSettle(commit, this.mode === PageTurnMode.Cover && this.pendingTurn !== null);
  }

  private animateSettle(commit: boolean, accelerated: boolean): void {
    const ticket = this.serial;
    const end = commit ? 1 : 0;
    const simulation = this.mode === PageTurnMode.Simulation;
    if (simulation || this.mode === PageTurnMode.Cover) this.progress = this.renderedProgress;
    const heldSpread = simulation && this.spread && this.progress > 0.001;
    if (simulation) this.verticalDrag = this.renderedVertical;
    this.releaseVertical = this.verticalDrag;
    this.settleStart = this.progress;
    this.phase = 'settling';
    this.settleAccelerated = accelerated;
    // 点击与松手都由显式进度驱动，避免新挂载的 V2 截图层只收到属性过渡终点。
    // 覆盖模式仍只平移同一张 Image，不逐帧清空、重画 Canvas。
    const animation = this.getUIContext().createAnimator({
      duration: heldSpread ? Math.max(160, Math.round((commit ? 420 : 300) * Math.sqrt(Math.abs(end - this.progress)))) :
        simulation ? (commit ? Math.max(300, Math.round((this.spread ? 600 : 520) * Math.sqrt(1 - this.progress))) :
        Math.max(180, Math.round(320 * Math.sqrt(this.progress)))) :
        this.mode === PageTurnMode.Cover ?
          (accelerated ? 80 : Math.max(90, Math.round(280 * Math.abs(end - this.progress)))) :
          Math.max(140, Math.round(380 * Math.abs(end - this.progress))),
      easing: simulation && commit && !heldSpread ? 'ease-in-out' : 'ease-out',
      delay: 0, fill: 'forwards', direction: 'normal',
      iterations: 1, begin: this.progress, end: end
    });
    this.animator = animation;
    animation.onFrame = (value: number): void => {
      if (ticket !== this.serial || this.animator !== animation) return;
      this.progress = value;
      const remaining = Math.abs(end - this.settleStart);
      this.verticalDrag = this.releaseVertical * (remaining > 0.001 ? Math.abs(end - value) / remaining : 0);
      // Animator 已按显示帧回调，覆盖层直接提交位移，避免二次排帧造成滞后。
      if (this.mode === PageTurnMode.Cover) this.drawFrame(value);
      else this.scheduleFrame();
    };
    animation.onFinish = (): void => {
      if (ticket !== this.serial || this.animator !== animation) return;
      this.animator = null;
      this.progress = end;
      this.drawFrame(end);
      this.finishTurn(commit, ticket);
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
    this.renderedVertical = this.verticalDrag;
    if (this.mode === PageTurnMode.Cover) {
      this.coverOffset = (this.forward ? -1 : 1) * w * p;
      return;
    }
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
    if (this.spread && this.mode === PageTurnMode.Simulation && this.targetImage !== null) {
      this.drawSpread(p);
      ctx.restore();
      return;
    }
    if (this.mode !== PageTurnMode.Simulation) {
      ctx.translate(-w * p, 0);
      this.drawPaper();
      this.drawBookSpine(w / 2, 1, !this.forward);
      ctx.restore();
      return;
    }
    if (p <= 0.0001) {
      this.drawPaper();
      this.drawBookSpine(w / 2, 1, !this.forward);
    } else if (p < 0.9999) {
      this.drawCurl(new ReaderCurlGeometry(w, h, p, this.anchor, this.verticalDrag));
    }
    ctx.restore();
  }

  private drawSpreadImage(bitmap: ImageBitmap, sourceX: number, sourceWidth: number,
    x: number, y: number, width: number): void {
    if (width < 0.01) return;
    const ctx = this.canvas;
    ctx.save();
    if (!this.forward) { ctx.translate(x * 2 + width, 0); ctx.scale(-1, 1); }
    ctx.fillStyle = this.paperColor;
    ctx.fillRect(x, y, width, this.pageHeight);
    ctx.drawImage(bitmap, sourceX / this.pageWidth * bitmap.width, 0,
      sourceWidth / this.pageWidth * bitmap.width, bitmap.height, x, y, width, this.pageHeight);
    ctx.restore();
  }

  private spreadPath(points: ReaderCurlPoint[]): void {
    const ctx = this.canvas;
    ctx.beginPath();
    if (points.length < 3) return;
    ctx.moveTo(points[0].x, points[0].y);
    for (let i = 1; i < points.length; i++) ctx.lineTo(points[i].x, points[i].y);
    ctx.closePath();
  }

  /** 纸背使用目标内页；两次反射后，落页文字保持正常阅读方向。 */
  private drawSpreadLeaf(back: boolean): void {
    const bitmap = back ? this.targetImage : this.snapshotImage;
    if (bitmap === null) return;
    const ctx = this.canvas;
    const half = this.pageWidth / 2;
    const mirrored = back === this.forward;
    ctx.save();
    ctx.globalAlpha = 1;
    if (mirrored) { ctx.translate(half, 0); ctx.scale(-1, 1); }
    ctx.fillStyle = this.paperColor;
    ctx.fillRect(0, 0, half, this.pageHeight);
    ctx.drawImage(bitmap, mirrored ? 0 : bitmap.width / 2, 0, bitmap.width / 2, bitmap.height,
      0, 0, half, this.pageHeight);
    ctx.restore();
  }

  private drawSpread(progress: number): void {
    const old = this.snapshotImage;
    const next = this.targetImage;
    if (old === null || next === null) return;
    // 端点直接使用完整静止页，不能留下反射矩阵、折线阴影或纸边描线。
    if (progress <= 0.0001 || progress >= 0.9999) {
      this.drawSpreadImage(progress >= 0.9999 ? next : old, 0, this.pageWidth, 0, 0, this.pageWidth);
      this.drawBookSpine(this.pageWidth / 2, 1, !this.forward);
      return;
    }
    const half = this.pageWidth / 2;
    // 两张静止底页明确绘制，背景图片、页眉和安全区也与正文一起保持连续。
    this.drawSpreadImage(old, this.forward ? 0 : half, half, 0, 0, half);
    this.drawSpreadImage(next, this.forward ? half : 0, half, half, 0, half);
    const ctx = this.canvas;
    ctx.save();
    ctx.translate(half, 0);
    const shape = new ReaderSpreadGeometry(half, this.pageHeight, progress, this.anchor, this.verticalDrag);
    if (shape.front.length >= 3) {
      ctx.save();
      this.spreadPath(shape.front);
      ctx.clip();
      this.drawSpreadLeaf(false);
      ctx.restore();
    }
    this.drawBookSpine(0, 1, !this.forward);
    this.drawSpreadFoldShadow(shape, false);
    if (shape.back.length >= 3) {
      ctx.save();
      this.spreadPath(shape.back);
      // 先在屏幕中的纸背轮廓上铺实色，再变换正文纹理。
      // 遮挡层不依赖截图 alpha 或反射后的矩形覆盖，底页不能穿过纸背。
      ctx.globalAlpha = 1;
      ctx.fillStyle = this.paperColor;
      ctx.fill();
      ctx.clip();
      ctx.save();
      // 反射矩阵只旋转/翻面纸张，不压缩正文，不产生条带接缝。
      ctx.transform(1 - 2 * shape.nx * shape.nx, -2 * shape.nx * shape.ny,
        -2 * shape.nx * shape.ny, 1 - 2 * shape.ny * shape.ny,
        2 * shape.fold * shape.nx, 2 * shape.fold * shape.ny);
      this.drawSpreadLeaf(true);
      ctx.restore();
      this.drawSpreadFoldShadow(shape, true);
      // 纸背接近落平时才恢复其书脊阴影，交接到静止正文时亮度连续。
      const landing = Math.max(0, Math.min(1, (progress - 0.75) / 0.25));
      this.drawBookSpine(0, landing * landing * (3 - 2 * landing), !this.forward);
      ctx.restore();
    }
    ctx.restore();
  }

  private drawRestingSpine(): void {
    if (!this.canvasReady) return;
    this.canvas.clearRect(0, 0, this.pageWidth, this.pageHeight);
    this.drawBookSpine(this.pageWidth / 2);
  }

  /** 参考 StPageFlip CanvasRender.drawBookShadow；书缝独立于正文截图，位于翻动纸背之下。 */
  private drawBookSpine(center: number, opacity: number = 1, mirrored: boolean = false): void {
    if (!this.spread || this.pageWidth <= 0 || opacity <= 0) return;
    const top = Math.max(8, this.safeTop - 4);
    const bottom = this.pageHeight - Math.max(8, this.safeBottom + this.footerHeight - 4);
    const height = bottom - top;
    if (height <= 0) return;
    const width = Math.min(36, this.pageWidth * 0.045);
    const fade = Math.min(20, height / 4);
    const ctx = this.canvas;
    ctx.save();
    ctx.translate(center, 0);
    if (mirrored) ctx.scale(-1, 1);
    // 中央凹陷和纸面反光均平滑过渡，不再用描边模拟装订缝。
    const shade = ctx.createLinearGradient(-width / 2, 0, width / 2, 0);
    shade.addColorStop(0, 'rgba(0,0,0,0)');
    shade.addColorStop(0.16, 'rgba(0,0,0,0.015)');
    shade.addColorStop(0.32, 'rgba(0,0,0,0.055)');
    shade.addColorStop(0.44, 'rgba(0,0,0,0.13)');
    shade.addColorStop(0.5, 'rgba(0,0,0,0.24)');
    shade.addColorStop(0.56, 'rgba(0,0,0,0.11)');
    shade.addColorStop(0.7, 'rgba(255,255,255,0.10)');
    shade.addColorStop(0.88, 'rgba(255,255,255,0.03)');
    shade.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = shade;
    ctx.globalAlpha = opacity;
    ctx.fillRect(-width / 2, top + fade, width, height - 2 * fade);
    // 端部在正文留白内渐隐，避开页眉、页脚与中央阅听状态；不模糊整张纸。
    const step = fade / 8;
    for (let i = 0; i < 8; i++) {
      const t = (i + 0.5) / 8;
      ctx.globalAlpha = opacity * t * t * (3 - 2 * t);
      ctx.fillRect(-width / 2, top + i * step, width, step);
      ctx.fillRect(-width / 2, bottom - (i + 1) * step, width, step);
    }
    ctx.restore();
  }

  /** 参照 StPageFlip 的内外折痕渐变，阴影范围由纸张抬起程度决定。 */
  private drawSpreadFoldShadow(shape: ReaderSpreadGeometry, inner: boolean): void {
    const width = shape.shadowWidth;
    if (width < 0.01) return;
    const ctx = this.canvas;
    ctx.save();
    if (!inner) {
      ctx.beginPath();
      ctx.rect(0, 0, shape.width, shape.height);
      ctx.clip();
    }
    ctx.transform(shape.nx, shape.ny, -shape.ny, shape.nx,
      shape.fold * shape.nx, shape.fold * shape.ny);
    const shade = ctx.createLinearGradient(inner ? -width : 0, 0, inner ? 0 : width, 0);
    if (inner) {
      shade.addColorStop(0, 'rgba(0,0,0,0)');
      shade.addColorStop(0.45, `rgba(255,255,255,${0.12 * shape.strength})`);
      shade.addColorStop(0.78, `rgba(0,0,0,${0.06 * shape.strength})`);
      shade.addColorStop(1, `rgba(0,0,0,${0.28 * shape.strength})`);
    } else {
      shade.addColorStop(0, `rgba(0,0,0,${0.24 * shape.strength})`);
      shade.addColorStop(0.25, `rgba(0,0,0,${0.12 * shape.strength})`);
      shade.addColorStop(1, 'rgba(0,0,0,0)');
    }
    ctx.fillStyle = shade;
    ctx.fillRect(inner ? -width : 0, -shape.extent, width, shape.extent * 2);
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

      if (this.coverSnapshot !== null) {
        Image(this.coverSnapshot).width('100%').height('100%').objectFit(ImageFit.Fill)
          .syncLoad(true)
          .backgroundColor(this.paperColor).translate({ x: this.coverOffset })
          .draggable(false).hitTestBehavior(HitTestMode.None)
      }

      Canvas(this.canvas)
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
        .onReady((): void => {
          this.canvasReady = true;
          this.drawRestingSpine();
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
      if (this.phase === 'idle') this.drawRestingSpine();
    })
    .onTouch((event: TouchEvent): void => this.handleTouch(event))
    .gesture(PanGesture({ fingers: 1, direction: this.ignoreChildGestures ? PanDirection.None :
      this.mode === PageTurnMode.Vertical ? PanDirection.Vertical : PanDirection.Horizontal, distance: 8 })
        .onActionStart((event: GestureEvent): void => this.handlePanStart(event))
        .onActionUpdate((event: GestureEvent): void => this.handlePanUpdate(event))
        .onActionEnd((event: GestureEvent): void => this.handlePanEnd(event))
        .onActionCancel((): void => this.handlePanCancel()))
    // 与 Web 同时观察位移。页内画廊、滚动区和媒体保留完整的浏览器触摸序列。
    .parallelGesture(PanGesture({ fingers: 1,
      direction: this.ignoreChildGestures ? PanDirection.All : PanDirection.None, distance: 8 })
        .onActionStart((event: GestureEvent): void => this.handlePanStart(event))
        .onActionUpdate((event: GestureEvent): void => this.handlePanUpdate(event))
        .onActionEnd((event: GestureEvent): void => this.handlePanEnd(event))
        .onActionCancel((): void => this.handlePanCancel()))
  }
}
