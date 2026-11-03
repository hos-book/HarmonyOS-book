import { drawing, text as graphicsText, common2D } from '@kit.ArkGraphics2D';
import { UIContext } from '@kit.ArkUI';
import { DrawContext, FrameNode, LayoutConstraint, NodeController, Position } from '@ohos.arkui.node';
import { OnlineTextPage } from './OnlineTextPaginator';
import { SpeechHighlightRange } from './SpeechTextHighlighter';
import { ReaderPalette } from '../../model/ReaderTheme';

/** Paint only visible native lines, retaining their original paragraph coordinates. */
class ReaderParagraphFrameNode extends FrameNode {
  private page: OnlineTextPage = new OnlineTextPage();
  private range: SpeechHighlightRange = new SpeechHighlightRange();
  private palette: ReaderPalette = new ReaderPalette();
  private speechMark: string = 'color';
  private dialogueHighlight: boolean = false;

  constructor(context: UIContext) { super(context); }

  update(page: OnlineTextPage, range: SpeechHighlightRange, palette: ReaderPalette, speechMark: string = 'color', dialogueHighlight: boolean = false): void {
    this.page = page;
    this.range = range;
    this.palette = palette;
    this.speechMark = speechMark;
    this.dialogueHighlight = dialogueHighlight;
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
      for (const range of page.dialogueRanges) this.paintRange(canvas, range.start, range.end, 'color');
    }
    this.paintRange(canvas, this.range.start, this.range.end, this.speechMark);
    // 排版对象在可见行之间共享，绘制结束恢复正文色。
    paragraph.updateColor(foreground);
    page.paintState.lines = paragraph.getTextLines();
    canvas.restore();
  }
  private paintRange(canvas: drawing.Canvas, start: number, end: number, mark: string): void {
    const page = this.page;
    const paragraph = page.paragraph;
    if (paragraph === null || start < 0 || end <= start) return;
    const displayStart = page.displayStart + start;
    const displayEnd = page.displayStart + end;
    const boxes = paragraph.getRectsForRange({
      start: page.nativeOffsets?.nativeOffsetForDisplay(displayStart) ?? displayStart,
      end: page.nativeOffsets?.nativeOffsetForDisplay(displayEnd) ?? displayEnd
    }, graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
    const accent = this.color(this.palette.isDark ? '#FFB4A8' : '#A33245');
    const brush = new drawing.Brush();
    const tint = this.color(this.palette.primary);
    tint.alpha = 51;
    brush.setColor(mark === 'highlight' ? tint : accent);
    paragraph.updateColor(mark === 'color' ? accent : this.color(this.palette.primary));
    const lines = paragraph.getTextLines();
    for (const box of boxes) {
      for (let index = 0; index < page.lineMetrics.length; index++) {
        const metric = page.lineMetrics[index];
        const nativeTop = Math.max(box.rect.top, metric.baseline - metric.ascent);
        const nativeBottom = Math.min(box.rect.bottom, metric.baseline + metric.descent);
        if (nativeBottom <= nativeTop) continue;
        const shift = page.lineShifts[index] ?? 0;
        const top = Math.max(0, nativeTop - page.layoutTop + shift);
        const bottom = Math.min(page.layoutHeight, nativeBottom - page.layoutTop + shift);
        if (bottom <= top) continue;
        canvas.save();
        canvas.clipRect({ left: box.rect.left, top: top, right: box.rect.right, bottom: bottom }, drawing.ClipOp.INTERSECT, true);
        if (mark !== 'color') {
          canvas.attachBrush(brush);
          canvas.drawRect(box.rect.left, mark === 'underline' ? Math.max(top, bottom - Math.max(1, metric.ascent / 18)) : top,
            box.rect.right, bottom);
          canvas.detachBrush();
        }
        if (mark !== 'underline') this.paintLines(canvas, lines);
        canvas.restore();
      }
    }
  }

}

export class ReaderParagraphNodeController extends NodeController {
  private node: ReaderParagraphFrameNode | null = null;
  private page: OnlineTextPage = new OnlineTextPage();
  private range: SpeechHighlightRange = new SpeechHighlightRange();
  private palette: ReaderPalette = new ReaderPalette();
  private speechMark: string = 'color';
  private dialogueHighlight: boolean = false;

  makeNode(context: UIContext): FrameNode {
    this.node = new ReaderParagraphFrameNode(context);
    this.node.update(this.page, this.range, this.palette, this.speechMark, this.dialogueHighlight);
    return this.node;
  }

  update(page: OnlineTextPage, range: SpeechHighlightRange, palette: ReaderPalette, speechMark: string = 'color', dialogueHighlight: boolean = false): void {
    if (this.page === page && this.range.start === range.start && this.range.end === range.end &&
      this.palette.primary === palette.primary && this.palette.background === palette.background && this.speechMark === speechMark && this.dialogueHighlight === dialogueHighlight) return;
    this.page = page;
    this.range = range;
    this.palette = palette;
    this.speechMark = speechMark;
    this.dialogueHighlight = dialogueHighlight;
    // Keep the mounted native node and atomically replace its retained paragraph.
    this.node?.update(page, range, palette, speechMark, dialogueHighlight);
  }

  release(): void {
    this.node?.dispose();
    this.node = null;
    this.page = new OnlineTextPage();
  }
}
