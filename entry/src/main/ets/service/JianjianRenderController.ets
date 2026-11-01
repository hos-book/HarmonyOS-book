import { drawing } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DrawContext, FrameNode, LayoutConstraint, NodeController, Position } from '@ohos.arkui.node';
import { JianjianRig } from './JianjianRig';

class JianjianFrameNode extends FrameNode {
  readonly rig: JianjianRig = new JianjianRig();
  private readonly brush: drawing.Brush = new drawing.Brush();
  base: image.PixelMap | null = null;
  left: image.PixelMap | null = null;
  right: image.PixelMap | null = null;
  leftClosed: boolean = false;
  rightClosed: boolean = false;

  constructor(context: UIContext) {
    super(context);
    this.brush.setAntiAlias(true);
  }

  onMeasure(constraint: LayoutConstraint): void {
    this.setMeasuredSize({ width: constraint.maxSize.width, height: constraint.maxSize.height });
  }

  onLayout(position: Position): void { this.setLayoutPosition(position); }

  onDraw(context: DrawContext): void {
    if (this.base === null) return;
    const size = context.sizeInPixel;
    const scale: number = Math.min(size.width / (JianjianRig.WIDTH + 40), size.height / (JianjianRig.HEIGHT + 16));
    const canvas: drawing.Canvas = context.canvas;
    canvas.save();
    canvas.translate((size.width - JianjianRig.WIDTH * scale) / 2, 8 * scale);
    canvas.scale(scale, scale);
    canvas.attachBrush(this.brush);
    canvas.drawPixelMapMesh(this.base, JianjianRig.COLUMNS, JianjianRig.ROWS, this.rig.vertices, 0, null, 0);
    if (this.leftClosed && this.left !== null) {
      canvas.drawPixelMapMesh(this.left, JianjianRig.COLUMNS, JianjianRig.ROWS, this.rig.vertices, 0, null, 0);
    }
    if (this.rightClosed && this.right !== null) {
      canvas.drawPixelMapMesh(this.right, JianjianRig.COLUMNS, JianjianRig.ROWS, this.rig.vertices, 0, null, 0);
    }
    canvas.detachBrush();
    canvas.restore();
  }
}

/** 低分辨率贴图常驻，30fps 仅更新网格坐标；不重建 ArkUI 树或逐帧解码图片。 */
export class JianjianRenderController extends NodeController {
  onReady: () => void = (): void => {};
  private node: JianjianFrameNode | null = null;
  private context: UIContext | null = null;
  private maps: image.PixelMap[] = [];
  private timer: number = -1;
  private generation: number = 0;
  private running: boolean = false;
  private time: number = 0;
  private lastFrame: number = 0;
  private reactionAt: number = -1;
  private expression: number = -1;
  private reacting: boolean = false;
  private leftClosed: boolean = false;
  private rightClosed: boolean = false;

  makeNode(context: UIContext): FrameNode {
    this.context = context;
    this.node = new JianjianFrameNode(context);
    const generation: number = ++this.generation;
    this.load(context, generation);
    return this.node;
  }

  private async decode(context: UIContext, resource: Resource): Promise<image.PixelMap> {
    const host = context.getHostContext();
    if (!host) throw new Error('Jianjian context unavailable');
    const bytes: Uint8Array = await host.resourceManager.getMediaContent(resource.id);
    const source: image.ImageSource = image.createImageSource(bytes.buffer);
    try { return await source.createPixelMap(); } finally {
      try { await source.release(); } catch (_) { /* 已解码贴图仍可显示。 */ }
    }
  }

  private async load(context: UIContext, generation: number): Promise<void> {
    const loaded: image.PixelMap[] = [];
    try {
      const resources: Resource[] = [$r('app.media.jianjian_native_idle'),
        $r('app.media.jianjian_native_lid_left'), $r('app.media.jianjian_native_lid_right')];
      for (const resource of resources) {
        loaded.push(await this.decode(context, resource));
        if (generation !== this.generation) return;
      }
      const node = this.node;
      if (node === null) return;
      this.maps = loaded;
      node.base = loaded[0];
      node.left = loaded[1];
      node.right = loaded[2];
      node.leftClosed = this.leftClosed;
      node.rightClosed = this.rightClosed;
      node.invalidate();
      this.onReady();
      this.syncTimer();
    } catch (error) {
      hilog.warn(0xFF00, 'Jianjian', 'native artwork load failed: %{public}s', String(error));
    } finally {
      if (this.maps !== loaded) {
        for (const map of loaded) { try { await map.release(); } catch (_) {} }
      }
    }
  }

  update(running: boolean, reacting: boolean, expression: number): void {
    if (reacting && (!this.reacting || expression !== this.expression)) this.reactionAt = this.time;
    if (!reacting) this.reactionAt = -1;
    this.running = running;
    this.reacting = reacting;
    this.expression = expression;
    this.syncTimer();
  }

  setEyes(left: boolean, right: boolean): void {
    this.leftClosed = left;
    this.rightClosed = right;
    if (this.node !== null) {
      this.node.leftClosed = left;
      this.node.rightClosed = right;
      this.node.invalidate();
    }
  }

  private syncTimer(): void {
    if (!this.running || this.maps.length === 0 || this.node === null) {
      if (this.timer !== -1) clearInterval(this.timer);
      this.timer = -1;
      return;
    }
    if (this.timer !== -1) return;
    this.lastFrame = Date.now();
    const generation: number = this.generation;
    this.timer = setInterval((): void => {
      if (generation !== this.generation || !this.running) return;
      this.context?.runScopedTask((): void => this.frame());
    }, 33);
  }

  private frame(): void {
    if (this.node === null) return;
    const now: number = Date.now();
    this.time += Math.min(0.1, Math.max(0, (now - this.lastFrame) / 1000));
    this.lastFrame = now;
    this.node.rig.update(this.time, this.reactionAt < 0 ? -1 : this.time - this.reactionAt, this.expression);
    this.node.invalidate();
  }

  release(): void {
    this.generation++;
    this.running = false;
    if (this.timer !== -1) clearInterval(this.timer);
    this.timer = -1;
    if (this.node !== null) {
      this.node.base = null;
      this.node.left = null;
      this.node.right = null;
      this.node.dispose();
      this.node = null;
    }
    for (const map of this.maps) map.release().catch((): void => {});
    this.maps = [];
    this.context = null;
    this.onReady = (): void => {};
  }
}
