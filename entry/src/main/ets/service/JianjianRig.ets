/** 连续二维网格绑定。各部位独立权重，连接处平滑过渡，脚底保持固定。 */
export class JianjianRig {
  static readonly COLUMNS: number = 24;
  static readonly ROWS: number = 40;
  static readonly WIDTH: number = 231;
  static readonly HEIGHT: number = 384;
  readonly vertices: number[] = [];

  constructor() {
    for (let i = 0; i < (JianjianRig.COLUMNS + 1) * (JianjianRig.ROWS + 1) * 2; i++) {
      this.vertices.push(0);
    }
    this.update(0, -1, -1);
  }

  private smooth(start: number, end: number, value: number): number {
    const t: number = Math.max(0, Math.min(1, (value - start) / (end - start)));
    return t * t * (3 - 2 * t);
  }

  update(seconds: number, reactionSeconds: number, expression: number): void {
    const breath: number = Math.sin(seconds * 1.8);
    const sway: number = Math.sin(seconds * 0.95);
    const reacting: boolean = reactionSeconds >= 0 && reactionSeconds < 2.4;
    const impulse: number = reacting ? Math.sin(reactionSeconds * 6) * Math.exp(-reactionSeconds * 1.5) : 0;
    const nod: number = reacting ? Math.sin(Math.min(1, reactionSeconds / 0.8) * Math.PI) : 0;
    const headAngle: number = sway * 0.085 + impulse * (expression === 6 ? -0.14 : 0.14);
    const cos: number = Math.cos(headAngle);
    const sin: number = Math.sin(headAngle);
    let index: number = 0;
    for (let row = 0; row <= JianjianRig.ROWS; row++) {
      const v: number = row / JianjianRig.ROWS;
      for (let col = 0; col <= JianjianRig.COLUMNS; col++) {
        const u: number = col / JianjianRig.COLUMNS;
        const x: number = u * JianjianRig.WIDTH;
        const y: number = v * JianjianRig.HEIGHT;
        const upper: number = 1 - this.smooth(0.40, 0.59, v);
        const body: number = 1 - this.smooth(0.66, 0.94, v);
        const hair: number = this.smooth(0.19, 0.37, Math.abs(u - 0.5)) *
          this.smooth(0.34, 0.49, v) * (1 - this.smooth(0.77, 0.86, v));
        const book: number = Math.exp(-Math.pow((u - 0.5) / 0.22, 4) - Math.pow((v - 0.605) / 0.085, 4));
        const skirt: number = Math.exp(-Math.pow((v - 0.76) / 0.07, 2)) *
          (1 - this.smooth(0.29, 0.43, Math.abs(u - 0.5)));
        const ahoge: number = 1 - this.smooth(0.035, 0.115, v);
        const dx: number = x - JianjianRig.WIDTH * 0.5;
        const dy: number = y - JianjianRig.HEIGHT * 0.455;
        // 颈部为转轴，头部保持局部刚性；躯干到腿部逐渐回到固定脚底。
        let outX: number = x + ((dx * cos - dy * sin) - dx) * upper + sway * 2.2 * body;
        let outY: number = y + ((dx * sin + dy * cos) - dy) * upper - breath * 2.2 * body;
        outY += nod * 5 * upper;
        // 两侧发梢错相并滞后于头部，呆毛有更快的小幅二级摆动。
        outX += hair * (Math.sin(seconds * 1.65 - v * 4 + (u < 0.5 ? 0 : 0.8)) * 8 - sway * 3);
        outY += hair * Math.cos(seconds * 1.65 - v * 4) * 2;
        outX += ahoge * Math.sin(seconds * 2.6 - 0.7) * 5;
        // 双手和书本作为同一绑定区域起伏，维持当前捧书姿态。
        outY -= book * (Math.sin(seconds * 1.8 - 0.55) * 3 + nod * 4);
        outX += skirt * dx * 0.018 * Math.sin(seconds * 1.8 - 0.3);
        this.vertices[index++] = outX;
        this.vertices[index++] = outY;
      }
    }
  }
}
