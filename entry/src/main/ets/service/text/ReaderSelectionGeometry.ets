import { text as graphicsText } from '@kit.ArkGraphics2D';
import { OnlineTextPage } from './OnlineTextPaginator';
import { SpeechHighlightRange } from './SpeechTextHighlighter';

export class ReaderSelectionRect {
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;
  ascent: number = 0;
  rtl: boolean = false;
}

export class ReaderSelectionHandle {
  x: number = 0;
  top: number = 0;
  bottom: number = 0;
}

export class ReaderSelectionBounds {
  start: ReaderSelectionHandle = new ReaderSelectionHandle();
  end: ReaderSelectionHandle = new ReaderSelectionHandle();
  valid: boolean = false;
}

/** 所有输入/输出均为正文局部 px，与 Paragraph 绘制共用分页、缩进及段间距映射。 */
export class ReaderSelectionGeometry {
  static rects(page: OnlineTextPage, start: number, end: number): ReaderSelectionRect[] {
    const paragraph = page.paragraph;
    if (paragraph === null || start < 0 || end <= start) return [];
    const from = page.displayStart + Math.min(start, page.text.length);
    const to = page.displayStart + Math.min(end, page.text.length);
    const boxes = paragraph.getRectsForRange({
      start: page.nativeOffsets?.nativeOffsetForDisplay(from) ?? from,
      end: page.nativeOffsets?.nativeOffsetForDisplay(to) ?? to
    }, graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
    const result: ReaderSelectionRect[] = [];
    for (const box of boxes) {
      for (let index = 0; index < page.lineMetrics.length; index++) {
        const metric = page.lineMetrics[index];
        const top = Math.max(box.rect.top, metric.baseline - metric.ascent);
        const bottom = Math.min(box.rect.bottom, metric.baseline + metric.descent);
        if (bottom <= top) continue;
        const shift = -page.layoutTop + (page.lineShifts[index] ?? 0);
        const rect = new ReaderSelectionRect();
        rect.left = Math.max(0, box.rect.left);
        rect.right = Math.min(page.layoutWidth, box.rect.right);
        rect.top = Math.max(0, top + shift);
        rect.bottom = Math.min(page.layoutHeight, bottom + shift);
        rect.ascent = metric.ascent;
        rect.rtl = box.direction === graphicsText.TextDirection.RTL;
        if (rect.bottom > rect.top && rect.right > rect.left) result.push(rect);
      }
    }
    return result;
  }

  static bounds(page: OnlineTextPage, start: number, end: number): ReaderSelectionBounds {
    const bounds = new ReaderSelectionBounds();
    const rects = ReaderSelectionGeometry.rects(page, start, end);
    if (rects.length === 0) return bounds;
    const first = rects[0];
    const last = rects[rects.length - 1];
    bounds.start.x = first.rtl ? first.right : first.left;
    bounds.start.top = first.top;
    bounds.start.bottom = first.bottom;
    bounds.end.x = last.rtl ? last.left : last.right;
    bounds.end.top = last.top;
    bounds.end.bottom = last.bottom;
    bounds.valid = true;
    return bounds;
  }

  private static nativePosition(page: OnlineTextPage, x: number, y: number): number {
    const paragraph = page.paragraph;
    if (paragraph === null || page.lineMetrics.length === 0) return -1;
    let closest = 0;
    let distance = Number.MAX_VALUE;
    for (let index = 0; index < page.lineMetrics.length; index++) {
      const metric = page.lineMetrics[index];
      const shift = -page.layoutTop + (page.lineShifts[index] ?? 0);
      const top = metric.baseline - metric.ascent + shift;
      const bottom = metric.baseline + metric.descent + shift;
      const gap = Math.max(top - y, y - bottom, 0);
      if (gap < distance) { closest = index; distance = gap; }
    }
    const line = page.lineMetrics[closest];
    const nativeY = Math.max(line.baseline - line.ascent,
      Math.min(line.baseline + line.descent - 0.01,
        y + page.layoutTop - (page.lineShifts[closest] ?? 0)));
    return paragraph.getGlyphPositionAtCoordinate(Math.max(0, Math.min(page.layoutWidth, x)), nativeY).position;
  }

  static offsetAt(page: OnlineTextPage, x: number, y: number): number {
    const native = ReaderSelectionGeometry.nativePosition(page, x, y);
    if (native < 0) return -1;
    const offset = (page.nativeOffsets?.displayOffsetForNative(native) ?? native) - page.displayStart;
    return Math.max(0, Math.min(page.text.length, offset));
  }

  static wordAt(page: OnlineTextPage, x: number, y: number): SpeechHighlightRange {
    const range = new SpeechHighlightRange();
    const paragraph = page.paragraph;
    const position = ReaderSelectionGeometry.nativePosition(page, x, y);
    if (paragraph === null || position < 0 || !page.text) return range;
    const word = paragraph.getWordBoundary(position);
    range.start = Math.max(0, Math.min(page.text.length,
      (page.nativeOffsets?.displayOffsetForNative(word.start) ?? word.start) - page.displayStart));
    range.end = Math.max(0, Math.min(page.text.length,
      (page.nativeOffsets?.displayOffsetForNative(word.end) ?? word.end) - page.displayStart));
    // 原生首行缩进不含字符，反向映射会落到展示缩进之前；选词应从实际字形开始。
    while (range.start < range.end && page.text.charAt(range.start).trim().length === 0) range.start++;
    while (range.end > range.start && page.text.charAt(range.end - 1).trim().length === 0) range.end--;
    return range;
  }
}
