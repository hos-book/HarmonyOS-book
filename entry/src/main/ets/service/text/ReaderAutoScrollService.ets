import { FrameCallback, UIContext } from '@kit.ArkUI';

class ReaderScrollFrame extends FrameCallback {
  private callback: (time: number) => void;
  constructor(callback: (time: number) => void) { super(); this.callback = callback; }
  onFrame(time: number): void { this.callback(time / 1000000); }
}

/** 按实际帧间隔连续移动；加载和掉帧不积累位移，不跳过未读内容。 */
export class ReaderAutoScrollService {
  private generation: number = 0;
  private lastFrame: number = -1;

  static normalizeSpeed(value: number, comic: boolean = false): number {
    return Number.isFinite(value) ? Math.max(6, Math.min(comic ? 120 : 100, Math.round(value / 2) * 2)) :
      (comic ? 30 : 20);
  }

  start(context: UIContext, advance: (elapsedSeconds: number) => void): void {
    this.stop();
    const ticket = this.generation;
    const frame: ReaderScrollFrame = new ReaderScrollFrame((now: number): void => {
      if (ticket !== this.generation) return;
      const previous = this.lastFrame;
      this.lastFrame = now;
      if (previous >= 0) advance(Math.max(0, Math.min(64, now - previous)) / 1000);
      if (ticket === this.generation) context.postFrameCallback(frame);
    });
    context.postFrameCallback(frame);
  }

  stop(): void { this.generation++; this.lastFrame = -1; }
}
