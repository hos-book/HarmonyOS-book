import { image } from '@kit.ImageKit';
import { FrameCallback } from '@kit.ArkUI';
import { shatterPrepare, shatterAttach, shatterBegin, shatterClose } from 'librecord_dissolve.so';

// Motion/fragment rendering adapted from Petrel (Apache-2.0).
// Upstream: miramira8295/Petrel@ed218f4559cf083b51b08c5bf0bb27ea6215cbb9
class RecordDissolveFrame extends FrameCallback {
  private ready: () => void;
  constructor(ready: () => void) { super(); this.ready = ready; }
  onIdle(_time: number): void { this.ready(); }
}

/** 单行原色消散：后台准备像素/碎片，NativeVSync 驱动 GPU，无 ArkTS 逐帧绘制。 */
@ComponentV2
export struct RecordDissolveEffect {
  @Require @Param snapshotId: string;
  @Param active: boolean = false;
  @Param itemHeight: number | undefined = 88;
  @Param particleBudget: number = 3000;
  @BuilderParam content: () => void = this.emptyContent;
  @Event onFinished: () => void = (): void => {};
  @Local gpuVisible: boolean = false;
  @Local contentAlpha: number = 1;
  @Local surfaceWidth: number = 0;
  @Local surfaceHeight: number = 0;
  @Local topPadding: number = 0;
  private controller: XComponentController = new XComponentController();
  private handle: number = 0;
  private rowWidth: number = 0;
  private rowHeight: number = 0;
  private generation: number = 0;
  private completed: boolean = true;
  private timeout: number = -1;

  @Monitor('active')
  onActiveChanged(): void {
    if (this.active) this.capture();
    else this.reset();
  }

  aboutToDisappear(): void {
    this.finish();
    this.reset();
  }

  private clearTimer(): void {
    if (this.timeout !== -1) clearTimeout(this.timeout);
    this.timeout = -1;
  }

  private closeRenderer(): void {
    if (this.handle > 0) shatterClose(this.handle);
    this.handle = 0;
    this.gpuVisible = false;
  }

  private finish(): void {
    if (this.completed) return;
    this.completed = true;
    this.generation++;
    this.clearTimer();
    this.closeRenderer();
    this.contentAlpha = 0;
    this.onFinished();
  }

  private reset(): void {
    this.generation++;
    this.completed = true;
    this.clearTimer();
    this.closeRenderer();
    this.contentAlpha = 1;
  }

  private valid(ticket: number): boolean {
    return ticket === this.generation && this.active && !this.completed;
  }

  private async capture(): Promise<void> {
    this.reset();
    this.completed = false;
    const ticket = this.generation;
    if (this.rowWidth <= 0) { this.fadeOut(ticket); return; }
    // 超时仅撤销本次 UI；正在 native worker 中读取的 PixelMap 要等 prepare 返回再释放。
    this.timeout = setTimeout((): void => this.fadeOut(ticket), 650);
    let snapshot: image.PixelMap | null = null;
    try {
      snapshot = await this.getUIContext().getComponentSnapshot().get(this.snapshotId, {
        scale: Math.min(1, 720 / this.getUIContext().vp2px(Math.max(this.rowWidth, this.rowHeight)))
      });
      if (!this.valid(ticket)) return;
      const density = snapshot.getImageInfoSync().size.width / this.rowWidth;
      const scene = await shatterPrepare(snapshot, density, this.particleBudget);
      if (!this.valid(ticket)) {
        if (scene !== null) shatterClose(scene.handle);
        return;
      }
      if (scene === null) { this.fadeOut(ticket); return; }
      this.handle = scene.handle;
      this.surfaceWidth = scene.surfaceWidth / density;
      this.surfaceHeight = scene.surfaceHeight / density;
      this.topPadding = scene.top / density;
      this.clearTimer();
      this.timeout = setTimeout((): void => this.fadeOut(ticket), 1600);
      this.gpuVisible = true;
    } catch (_error) {
      this.fadeOut(ticket);
    } finally {
      if (snapshot !== null) snapshot.release().catch((): void => {});
    }
  }

  private attachRenderer(): void {
    const ticket = this.generation;
    if (!this.valid(ticket) || this.handle === 0) return;
    try {
      const attached = shatterAttach(this.handle, this.controller.getXComponentSurfaceId(),
        (event: number): void => {
          if (!this.valid(ticket)) return;
          if (event === 1) { this.finish(); return; }
          if (event < 0) { this.fadeOut(ticket); return; }
          // 首帧提交后才隐藏原行；后续帧全部在 native 渲染线程。
          this.getUIContext().postFrameCallback(new RecordDissolveFrame((): void => {
            if (!this.valid(ticket)) return;
            this.clearTimer();
            this.timeout = setTimeout((): void => this.fadeOut(ticket), 1500);
            this.contentAlpha = 0;
            shatterBegin(this.handle, 1100);
          }));
        });
      if (!attached) this.fadeOut(ticket);
    } catch (_error) {
      this.fadeOut(ticket);
    }
  }

  private fadeOut(ticket: number): void {
    if (!this.valid(ticket)) return;
    console.warn('[RecordDissolve] GPU unavailable or timed out; using opacity fallback');
    this.generation++;
    const fadeTicket = this.generation;
    this.clearTimer();
    this.closeRenderer();
    // GPU 不可用时只执行轻量属性动画，不再回退到密集 Canvas 绘制。
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut,
      onFinish: (): void => { if (this.generation === fadeTicket) this.finish(); } },
      (): void => { this.contentAlpha = 0; });
    this.timeout = setTimeout((): void => { if (this.generation === fadeTicket) this.finish(); }, 260);
  }

  @Builder
  emptyContent() { Column() }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack() { this.content() }
        .width('100%').height(this.itemHeight).id(this.snapshotId).opacity(this.contentAlpha)
      if (this.gpuVisible) {
        XComponent({ id: `${this.snapshotId}-gpu`, type: XComponentType.TEXTURE, controller: this.controller })
          .width(this.surfaceWidth).height(this.surfaceHeight)
          .position({ x: 0, y: -this.topPadding })
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.None)
          .onLoad((): void => this.attachRenderer())
          .onDestroy((): void => {
            if (this.handle > 0) this.finish();
          })
      }
    }
    // 自动高度书卡在挂载绝对定位 GPU 层前锁住原高度，避免 Stack 被粒子留白撑高。
    .width('100%').height(this.itemHeight ?? (this.gpuVisible ? this.rowHeight : undefined)).clip(false)
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
      const nextWidth = Number(size.width);
      const nextHeight = Number(size.height);
      if (this.active && this.rowWidth > 0 &&
        (Math.abs(this.rowWidth - nextWidth) > 0.5 || Math.abs(this.rowHeight - nextHeight) > 0.5)) this.finish();
      this.rowWidth = nextWidth;
      this.rowHeight = nextHeight;
    })
  }
}
