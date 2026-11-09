import { ReaderCurlPoint } from './ReaderCurlGeometry';

/**
 * 双页的页角折叠几何。采用 StPageFlip 的页角/书脊约束思路：
 * 折线是原页角与拖动页角的垂直平分线，纸背沿折线反射。
 * https://github.com/Nodlik/StPageFlip/blob/master/src/Flip/FlipCalculation.ts
 * 不按整页进度压缩文字，也不让折线穿过装订边。
 */
export class ReaderSpreadGeometry {
  readonly width: number;
  readonly height: number;
  readonly strength: number;
  readonly nx: number;
  readonly ny: number;
  readonly fold: number;
  readonly extent: number;
  readonly shadowWidth: number;
  readonly corner: ReaderCurlPoint;
  readonly touch: ReaderCurlPoint;
  readonly front: ReaderCurlPoint[];
  readonly back: ReaderCurlPoint[];

  constructor(width: number, height: number, progress: number, anchor: number, vertical: number) {
    this.width = Math.max(1, width);
    this.height = Math.max(1, height);
    const p = Math.max(0, Math.min(1, progress));
    const grip = Math.max(0, Math.min(1, anchor));
    const bottom = grip >= 0.5;
    const cornerY = bottom ? this.height : 0;
    this.corner = new ReaderCurlPoint(this.width, cornerY);
    this.strength = Math.sin(Math.PI * p);
    this.extent = this.width + this.height;
    this.shadowWidth = Math.min(64, this.width * 0.12) * this.strength;

    // 页角横向位移与手指一比一。点击沿弧线掀起，纵向拖动直接改变折线。
    const x = this.width * (1 - 2 * p);
    const lift = Math.min(this.width * 0.28, Math.abs(cornerY - grip * this.height)) * this.strength;
    const requestedY = cornerY + (bottom ? -lift : lift) + vertical;
    // 圆约束：页角到同侧书脊端点的距离不得超过纸宽。
    // 保持横向跟手，只限制纵向拉伸；上下书脊端点都落在未折区域。
    const reach = Math.min(this.height, Math.sqrt(Math.max(0, this.width * this.width - x * x)));
    const y = bottom ? Math.max(cornerY - reach, Math.min(cornerY, requestedY)) :
      Math.min(reach, Math.max(0, requestedY));
    this.touch = new ReaderCurlPoint(x, y);
    const dx = this.corner.x - x;
    const dy = this.corner.y - y;
    const length = Math.sqrt(dx * dx + dy * dy);
    this.nx = length > 0.000001 ? dx / length : 1;
    this.ny = length > 0.000001 ? dy / length : 0;
    this.fold = ((this.corner.x + x) * this.nx + (this.corner.y + y) * this.ny) / 2;

    const rectangle: ReaderCurlPoint[] = [new ReaderCurlPoint(0, 0), new ReaderCurlPoint(this.width, 0),
      new ReaderCurlPoint(this.width, this.height), new ReaderCurlPoint(0, this.height)];
    this.front = p >= 1 ? [] : this.clip(rectangle, false);
    const lifted: ReaderCurlPoint[] = p <= 0 ? [] : this.clip(rectangle, true);
    this.back = lifted.map((point: ReaderCurlPoint): ReaderCurlPoint => this.reflect(point));
  }

  reflect(point: ReaderCurlPoint): ReaderCurlPoint {
    const distance = point.x * this.nx + point.y * this.ny - this.fold;
    return new ReaderCurlPoint(point.x - 2 * distance * this.nx, point.y - 2 * distance * this.ny);
  }

  private clip(polygon: ReaderCurlPoint[], lifted: boolean): ReaderCurlPoint[] {
    const result: ReaderCurlPoint[] = [];
    for (let i = 0; i < polygon.length; i++) {
      const a = polygon[i];
      const b = polygon[(i + 1) % polygon.length];
      const da = (a.x * this.nx + a.y * this.ny - this.fold) * (lifted ? 1 : -1);
      const db = (b.x * this.nx + b.y * this.ny - this.fold) * (lifted ? 1 : -1);
      if (da >= 0) result.push(a);
      if ((da >= 0) !== (db >= 0)) {
        const t = da / (da - db);
        result.push(new ReaderCurlPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
      }
    }
    return result;
  }
}
