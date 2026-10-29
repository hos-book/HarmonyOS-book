import { UIContext } from '@kit.ArkUI';
import { displaySync } from '@kit.ArkGraphics2D';

/** 位移交给 List 原生匀速动画；业务仅低频检查加载、边界和阅读进度。 */
export class ReaderAutoScrollService {
  private generation: number = 0;
  private timer: number = -1;
  private active: boolean = false;
  private scroller: Scroller | null = null;
  private velocity: number = 0;
  private touching: boolean = false;
  private waitingForIdle: boolean = false;
  private sampledAt: number = -1;
  private sampledOffset: number = 0;
  private display: displaySync.DisplaySync | null = null;
  private readonly checkInterval: number = 200;

  static normalizeSpeed(value: number, comic: boolean = false): number {
    return Number.isFinite(value) ? Math.max(6, Math.min(comic ? 120 : 100, Math.round(value / 2) * 2)) :
      (comic ? 30 : 20);
  }

  start(context: UIContext, check: () => void): void {
    this.stop();
    this.active = true;
    const ticket = this.generation;
    const poll = (): void => {
      if (ticket !== this.generation) return;
      this.timer = -1;
      context.runScopedTask(check);
      if (ticket === this.generation) this.timer = setTimeout(poll, this.checkInterval);
    };
    this.timer = setTimeout(poll, 0);
  }

  move(scroller: Scroller, velocity: number): void {
    if (!this.active || this.touching || !Number.isFinite(velocity) || velocity <= 0) return;
    const offset = scroller.currentOffset().yOffset;
    const now = Date.now();
    const sameScroller = this.scroller === scroller;
    const sampled = sameScroller && this.sampledAt >= 0;
    if (sampled && now - this.sampledAt < this.checkInterval &&
      (this.waitingForIdle || this.velocity === velocity)) return;
    const moved = sampled && Math.abs(offset - this.sampledOffset) > 0.01;
    this.sampledAt = now;
    this.sampledOffset = offset;
    if (this.waitingForIdle && moved) return;
    this.waitingForIdle = false;
    // 触摸/手动跳转可中断原生动画。仅在位移停止后恢复，不依赖迟到的 onScrollStop 重启动画。
    if (sameScroller && this.velocity === velocity && moved) return;
    if (!sameScroller) this.pause();
    this.scroller = scroller;
    this.velocity = velocity;
    this.requestSmoothFrames();
    scroller.scrollEdge(Edge.Bottom, { velocity: velocity });
  }

  pause(): void {
    this.releaseSmoothFrames();
    const scroller = this.scroller;
    if (scroller === null || this.velocity === 0) return;
    this.velocity = 0;
    // 非动画 scrollTo 会停止原生滚动；以当前偏移为目标，暂停不改变阅读位置。
    const offset = scroller.currentOffset();
    scroller.scrollTo({ xOffset: offset.xOffset, yOffset: offset.yOffset, animation: false });
  }

  private requestSmoothFrames(): void {
    if (this.display !== null) return;
    try {
      const display = displaySync.create();
      this.display = display;
      try {
        display.setExpectedFrameRateRange({ min: 60, max: 120, expected: 120 });
      } catch (_error) {
        display.setExpectedFrameRateRange({ min: 60, max: 60, expected: 60 });
      }
      // start 使帧率范围生效；不订阅 frame，不为原生滚动添加 ArkTS 逐帧回调。
      display.start();
    } catch (_error) {
      this.releaseSmoothFrames();
    }
  }

  private releaseSmoothFrames(): void {
    const display = this.display;
    this.display = null;
    if (display !== null) {
      try { display.stop(); } catch (_error) { }
    }
  }

  setTouching(touching: boolean): void {
    if (!this.active) return;
    this.touching = touching;
    this.pause();
    this.waitingForIdle = !touching;
    this.sampledAt = Date.now();
    this.sampledOffset = this.scroller?.currentOffset().yOffset ?? 0;
  }

  stop(): void {
    this.generation++;
    this.active = false;
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = -1;
    this.pause();
    this.scroller = null;
    this.touching = false;
    this.waitingForIdle = false;
    this.sampledAt = -1;
  }
}
