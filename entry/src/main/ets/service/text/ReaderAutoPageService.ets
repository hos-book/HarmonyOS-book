/** 单次计时：加载、弹层或布局变化后重新计时，不补执行后台积压的翻页。 */
export class ReaderAutoPageService {
  static readonly DEFAULT_SECONDS: number = 10;
  private timer: number = -1;
  private generation: number = 0;
  private enabled: boolean = false;
  private ready: boolean = false;
  private seconds: number = ReaderAutoPageService.DEFAULT_SECONDS;
  private advance: () => void = (): void => {};

  static normalizeSeconds(value: number): number {
    return Number.isFinite(value) ? Math.max(3, Math.min(120, Math.round(value))) :
      ReaderAutoPageService.DEFAULT_SECONDS;
  }

  start(seconds: number, advance: () => void): void {
    this.stop();
    this.seconds = ReaderAutoPageService.normalizeSeconds(seconds);
    this.advance = advance;
    this.enabled = true;
  }

  setReady(ready: boolean): void {
    if (this.ready === ready) return;
    this.ready = ready;
    this.restart();
  }

  restart(): void {
    this.clearTimer();
    if (!this.enabled || !this.ready) return;
    const ticket = this.generation;
    this.timer = setTimeout((): void => {
      if (ticket !== this.generation || !this.enabled || !this.ready) return;
      this.timer = -1;
      this.advance();
      if (ticket === this.generation) this.restart();
    }, this.seconds * 1000);
  }

  stop(): void {
    this.clearTimer();
    this.enabled = false;
    this.ready = false;
    this.advance = (): void => {};
  }

  private clearTimer(): void {
    this.generation++;
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
  }
}
