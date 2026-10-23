/** 柱面卷页，使用页面 vp 坐标；正反页共用几何，方向由绘制层镜像。 */
export class ReaderCurlPoint {
  x: number;
  y: number;
  constructor(x: number, y: number) { this.x = x; this.y = y; }
}

export class ReaderCurlGeometry {
  nx: number;
  ny: number;
  fold: number;
  radius: number;
  extent: number;
  min: number;
  max: number;

  constructor(width: number, height: number, progress: number, anchor: number, vertical: number) {
    const p = Math.max(0, Math.min(1, progress));
    // 横向行程末尾逐渐展平，保证整页退出；中段允许上下拖动改变折线方向。
    const slope = Math.max(-0.55, Math.min(0.55,
      (anchor - 0.5) * 0.7 - vertical / Math.max(1, height) * 1.4)) * Math.sin(Math.PI * p);
    this.nx = 1 / Math.sqrt(1 + slope * slope);
    this.ny = slope * this.nx;
    this.min = Math.min(0, this.ny * height);
    this.max = width * this.nx + Math.max(0, this.ny * height);
    this.radius = Math.min(32, width * 0.075) * Math.sin(Math.PI * p);
    this.fold = this.max - (this.max - this.min) * p - Math.PI * this.radius * 0.5;
    this.extent = width + height;
  }

  project(s: number): number {
    const d = s - this.fold;
    if (d <= 0 || this.radius < 1e-9) return d <= 0 ? s : 2 * this.fold - s;
    if (d >= Math.PI * this.radius) return 2 * this.fold + Math.PI * this.radius - s;
    return this.fold + this.radius * Math.sin(d / this.radius);
  }

  /** 只对掀起部分投影，避免页角尚未卷起时阴影覆盖整页。 */
  shadowOutline(width: number, height: number): ReaderCurlPoint[] {
    const corners: ReaderCurlPoint[] = [new ReaderCurlPoint(0, 0), new ReaderCurlPoint(width, 0),
      new ReaderCurlPoint(width, height), new ReaderCurlPoint(0, height)];
    const clipped: ReaderCurlPoint[] = [];
    for (let i = 0; i < corners.length; i++) {
      const a = corners[i];
      const b = corners[(i + 1) % corners.length];
      const da = a.x * this.nx + a.y * this.ny - this.fold;
      const db = b.x * this.nx + b.y * this.ny - this.fold;
      if (da >= 0) clipped.push(a);
      if ((da >= 0) !== (db >= 0)) {
        const t = da / (da - db);
        clipped.push(new ReaderCurlPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
      }
    }
    const result: ReaderCurlPoint[] = [];
    for (let i = 0; i < clipped.length; i++) {
      const a = clipped[i];
      const b = clipped[(i + 1) % clipped.length];
      for (let j = 0; j < 8; j++) {
        const x = a.x + (b.x - a.x) * j / 8;
        const y = a.y + (b.y - a.y) * j / 8;
        const s = this.project(x * this.nx + y * this.ny);
        const t = -x * this.ny + y * this.nx;
        result.push(new ReaderCurlPoint(s * this.nx - t * this.ny, s * this.ny + t * this.nx));
      }
    }
    return result;
  }
}
