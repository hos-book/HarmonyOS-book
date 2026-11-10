import { drawing, text as graphicsText, common2D } from '@kit.ArkGraphics2D';
import { UIContext } from '@kit.ArkUI';
import { DrawContext, FrameNode, LayoutConstraint, NodeController, Position } from '@ohos.arkui.node';
import { OnlineTextPage } from './OnlineTextPaginator';
import { SpeechHighlightRange } from './SpeechTextHighlighter';
import { ReaderPalette } from '../../model/ReaderTheme';
import { ReaderSelectionGeometry } from './ReaderSelectionGeometry';

/** Paint only visible native lines, retaining their original paragraph coordinates. */
class ReaderParagraphFrameNode extends FrameNode {
  private page: OnlineTextPage = new OnlineTextPage();
  private range: SpeechHighlightRange = new SpeechHighlightRange();
  private palette: ReaderPalette = new ReaderPalette();
  private speechMark: string = 'color';
  private speechMarkColor: string = '';
  private dialogueHighlight: boolean = false;
  private dialogueHighlightColor: string = '';

  constructor(context: UIContext) { super(context); }

  update(page: OnlineTextPage, range: SpeechHighlightRange, palette: ReaderPalette, speechMark: string = 'color', dialogueHighlight: boolean = false, dialogueHighlightColor: string = '', speechMarkColor: string = ''): void {
    this.page = page;
    this.range = range;
    this.palette = palette;
    this.speechMark = speechMark;
    this.speechMarkColor = speechMarkColor;
    this.dialogueHighlight = dialogueHighlight;
    this.dialogueHighlightColor = dialogueHighlightColor;
    // onDraw 属于 FrameNode，必须使自绘节点失效才能更新已挂载的正文。
    this.invalidate();
  }

  onMeasure(constraint: LayoutConstraint): void {
    this.setMeasuredSize({ width: constraint.maxSize.width, height: constraint.maxSize.height });
  }

  onLayout(position: Position): void { this.setLayoutPosition(position); }

  private color(hex: string): common2D.Color {
    const value = Number.parseInt(hex.substring(1), 16);
    return { alpha: 255, red: (value >>> 16) & 255, green: (value >>> 8) & 255, blue: value & 255 };
  }

  private paintLines(canvas: drawing.Canvas, lines: graphicsText.TextLine[]): void {
    for (let index = 0; index < this.page.lineMetrics.length; index++) {
      const line = lines[this.page.firstLine + index];
      if (line !== undefined) {
        line.paint(canvas, 0, -this.page.layoutTop + (this.page.lineShifts[index] ?? 0));
      }
    }
  }

  onDraw(context: DrawContext): void {
    const page = this.page;
    const paragraph = page.paragraph;
    if (paragraph === null) return;
    const canvas = context.canvas;
    const foreground = this.color(this.palette.primary);
    canvas.save();
    canvas.clipRect({ left: 0, top: 0, right: page.layoutWidth, bottom: page.layoutHeight },
      drawing.ClipOp.INTERSECT, true);
    if (page.paintState.color !== this.palette.primary) {
      paragraph.updateColor(foreground);
      page.paintState.lines = paragraph.getTextLines();
      page.paintState.color = this.palette.primary;
    }
    this.paintLines(canvas, page.paintState.lines);
    if (this.dialogueHighlight) {
      for (const range of page.dialogueRanges) this.paintRange(canvas, range.start, range.end, 'color', this.dialogueHighlightColor);
    }
    this.paintRange(canvas, this.range.start, this.range.end, this.speechMark, this.speechMarkColor);
    // 排版对象在可见行之间共享，绘制结束恢复正文色。
    paragraph.updateColor(foreground);
    page.paintState.lines = paragraph.getTextLines();
    canvas.restore();
  }
  private paintRange(canvas: drawing.Canvas, start: number, end: number, mark: string, customColor: string = ''): void {
    const page = this.page;
    const paragraph = page.paragraph;
    if (paragraph === null || start < 0 || end <= start) return;
    const boxes = ReaderSelectionGeometry.rects(page, start, end);
    const accent = this.color(customColor || this.palette.accent);
    const brush = new drawing.Brush();
    const tint = this.color(customColor || this.palette.accent);
    tint.alpha = 51;
    brush.setColor(mark === 'highlight' ? tint : accent);
    paragraph.updateColor(mark === 'color' ? accent : this.color(this.palette.primary));
    const lines = paragraph.getTextLines();
    for (const box of boxes) {
        canvas.save();
        canvas.clipRect({ left: box.left, top: box.top, right: box.right, bottom: box.bottom }, drawing.ClipOp.INTERSECT, true);
        if (mark !== 'color') {
          canvas.attachBrush(brush);
          canvas.drawRect(box.left, mark === 'underline' ? Math.max(box.top, box.bottom - Math.max(1, box.ascent / 18)) : box.top,
            box.right, box.bottom);
          canvas.detachBrush();
        }
        if (mark !== 'underline') this.paintLines(canvas, lines);
        canvas.restore();
    }
  }

}

export class ReaderParagraphNodeController extends NodeController {
  private node: ReaderParagraphFrameNode | null = null;
  private page: OnlineTextPage = new OnlineTextPage();
  private range: SpeechHighlightRange = new SpeechHighlightRange();
  private palette: ReaderPalette = new ReaderPalette();
  private speechMark: string = 'color';
  private speechMarkColor: string = '';
  private dialogueHighlight: boolean = false;
  private dialogueHighlightColor: string = '';

  makeNode(context: UIContext): FrameNode {
    this.node = new ReaderParagraphFrameNode(context);
    this.node.update(this.page, this.range, this.palette, this.speechMark, this.dialogueHighlight, this.dialogueHighlightColor, this.speechMarkColor);
    return this.node;
  }

  update(page: OnlineTextPage, range: SpeechHighlightRange, palette: ReaderPalette, speechMark: string = 'color', dialogueHighlight: boolean = false, dialogueHighlightColor: string = '', speechMarkColor: string = ''): void {
    if (this.page === page && this.range.start === range.start && this.range.end === range.end &&
      this.palette.primary === palette.primary && this.palette.background === palette.background &&
      this.palette.accent === palette.accent && this.speechMark === speechMark &&
      this.dialogueHighlight === dialogueHighlight && this.dialogueHighlightColor === dialogueHighlightColor &&
      this.speechMarkColor === speechMarkColor) return;
    this.page = page;
    this.range = range;
    this.palette = palette;
    this.speechMark = speechMark;
    this.speechMarkColor = speechMarkColor;
    this.dialogueHighlight = dialogueHighlight;
    this.dialogueHighlightColor = dialogueHighlightColor;
    // Keep the mounted native node and atomically replace its retained paragraph.
    this.node?.update(page, range, palette, speechMark, dialogueHighlight, dialogueHighlightColor, speechMarkColor);
  }

  release(): void {
    this.node?.dispose();
    this.node = null;
    this.page = new OnlineTextPage();
  }
}
