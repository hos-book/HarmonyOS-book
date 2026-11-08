/** 双页书脊固定在 x=0，页外缘从右半页转到左半页。坐标由绘制层平移到书脊。 */
export class ReaderSpreadGeometry {
  readonly back: boolean;
  readonly width: number;
  readonly angle: number;
  readonly lift: number;

  constructor(width: number, height: number, progress: number, anchor: number, vertical: number) {
    const p = Math.max(0, Math.min(1, progress));
    this.width = Math.max(1, width);
    this.angle = Math.PI * p;
    this.back = p >= 0.5;
    this.lift = Math.max(-height * 0.06, Math.min(height * 0.06,
      (anchor - 0.5) * height * 0.05 + vertical * 0.12)) * Math.sin(this.angle);
  }

  x(fraction: number): number {
    const t = Math.max(0, Math.min(1, fraction));
    // 页根不动；小幅曲率让纸面弯曲，同时保持条带顺序，不越过书脊。
    return this.width * Math.cos(this.angle) * (t + 0.06 * Math.sin(Math.PI * t) * Math.sin(this.angle));
  }

  y(fraction: number): number { return this.lift * Math.sin(Math.PI * fraction / 2); }
}
