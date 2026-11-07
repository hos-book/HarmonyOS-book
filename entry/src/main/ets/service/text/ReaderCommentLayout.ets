import { text as graphicsText } from '@kit.ArkGraphics2D';
import { ReaderParagraphComment } from '../../model/ReaderComment';
import { OnlineTextPage } from './OnlineTextPaginator';
import { SpeechTextHighlighter } from './SpeechTextHighlighter';

export class ReaderCommentAnchor {
  comment: ReaderParagraphComment = new ReaderParagraphComment();
  x: number = 0;
  y: number = 0;
  size: number = 0;
}

export class ReaderCommentLayout {
  static readonly ICON_SIZE: number = 24;

  static anchors(page: OnlineTextPage, source: string, sourceStart: number,
    comments: ReaderParagraphComment[], density: number): ReaderCommentAnchor[] {
    if (page.isHeading || page.paragraph === null || page.imageUrl) return [];
    const result: ReaderCommentAnchor[] = [];
    for (const comment of comments) {
      if (comment.offset <= sourceStart || comment.offset > page.endOffset) continue;
      const end = comment.offset - sourceStart;
      const range = SpeechTextHighlighter.displayRange(page.text, source, Math.max(0, end - 2), end);
      if (range.end < 0) continue;
      let glyphStart = Math.max(range.start, range.end - 1);
      const low = page.text.charCodeAt(glyphStart);
      const high = page.text.charCodeAt(glyphStart - 1);
      if (low >= 0xDC00 && low <= 0xDFFF && high >= 0xD800 && high <= 0xDBFF) glyphStart--;
      const start = page.displayStart + glyphStart;
      const stop = page.displayStart + range.end;
      const boxes = page.paragraph.getRectsForRange({
        start: page.nativeOffsets?.nativeOffsetForDisplay(start) ?? start,
        end: page.nativeOffsets?.nativeOffsetForDisplay(stop) ?? stop
      }, graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
      const box = boxes[boxes.length - 1];
      if (!box) continue;
      const line = page.lineMetrics.findIndex((metric: graphicsText.LineMetrics): boolean =>
        box.rect.bottom > metric.baseline - metric.ascent && box.rect.top < metric.baseline + metric.descent);
      if (line < 0) continue;
      const metric = page.lineMetrics[line];
      const anchor = new ReaderCommentAnchor();
      anchor.comment = comment;
      anchor.size = Math.min(ReaderCommentLayout.ICON_SIZE * density, metric.ascent + metric.descent, page.layoutHeight);
      const extra = page.commentLineExtra[line] ?? 0;
      anchor.x = extra > 0 ? Math.max(0, page.layoutWidth - anchor.size) :
        Math.max(0, Math.min(page.layoutWidth - anchor.size, box.rect.right + 2 * density));
      anchor.y = Math.max(0, Math.min(page.layoutHeight - anchor.size,
        extra > 0 ? metric.baseline + metric.descent - page.layoutTop + (page.lineShifts[line] ?? 0) :
          metric.baseline - metric.ascent - page.layoutTop + (page.lineShifts[line] ?? 0) +
            (metric.ascent + metric.descent - anchor.size) / 2));
      result.push(anchor);
    }
    return result;
  }
}
