import { text as graphicsText } from '@kit.ArkGraphics2D';
import { PlatformCompat } from '../../utils/PlatformCompat';
import { LocalTextImage } from './LocalTextImage';

export class OnlineTextPaintState {
  color: string = '';
  lines: graphicsText.TextLine[] = [];
}

export class OnlineTextPage {
  imageUrl: string = '';
  firstLine: number = 0;
  // Each native line keeps its geometry; only paragraph boundaries add a vertical translation.
  lineShifts: number[] = [];
  trailingSpacing: number = 0;
  lineMetrics: graphicsText.LineMetrics[] = [];
  paintState: OnlineTextPaintState = new OnlineTextPaintState();
  text: string = '';
  // Keep the measured paragraph: slicing text and laying it out again loses justification.
  paragraph: graphicsText.Paragraph | null = null;
  displayStart: number = 0;
  nativeOffsets: OnlineTextIndentedContent | null = null;
  layoutTop: number = 0;
  layoutHeight: number = 0;
  layoutWidth: number = 0;
  layoutKey: number = 0;
  // Offsets refer to normalized source text, excluding display-only indentation.
  startOffset: number = 0;
  endOffset: number = 0;

  static of(content: string, startOffset: number, endOffset: number): OnlineTextPage {
    const page = new OnlineTextPage();
    page.startOffset = Math.max(0, Math.min(startOffset, content.length));
    page.endOffset = Math.max(page.startOffset, Math.min(endOffset, content.length));
    page.text = content.substring(page.startOffset, page.endOffset);
    return page;
  }
}

class OnlineTextIndent {
  sourceStart: number;
  contentStart: number;
  displayStart: number;

  constructor(sourceStart: number, contentStart: number, displayStart: number) {
    this.sourceStart = sourceStart;
    this.contentStart = contentStart;
    this.displayStart = displayStart;
  }
}

/** Display indentation and collapsed blank paragraphs map back to existing reading positions. */
export class OnlineTextIndentedContent {
  text: string = '';
  private sourceLength: number = 0;
  private indents: OnlineTextIndent[] = [];
  private static readonly INDENT: string = '\u3000\u3000';

  static fromNormalized(content: string): OnlineTextIndentedContent {
    const result = new OnlineTextIndentedContent();
    result.sourceLength = content.length;
    const paragraphs = content.split('\n');
    const displayed: string[] = [];
    let sourceStart = 0;
    let displayStart = 0;
    for (let index = 0; index < paragraphs.length; index++) {
      const paragraph = paragraphs[index];
      const body = paragraph.replace(new RegExp('^\\s+'), '');
      // Source separators remain in the offset space, but must not reserve extra line boxes.
      if (body.trim().length > 0) {
        if (displayed.length > 0) displayStart += 1;
        result.indents.push(new OnlineTextIndent(
          sourceStart, sourceStart + paragraph.length - body.length, displayStart));
        const displayText = OnlineTextIndentedContent.INDENT + body;
        displayed.push(displayText);
        displayStart += displayText.length;
      }
      sourceStart += paragraph.length + 1;
    }
    result.text = displayed.join('\n');
    return result;
  }

  appendToBuilder(builder: graphicsText.ParagraphBuilder, textStyle: graphicsText.TextStyle,
    nativeIndents: boolean = false): void {
    if (nativeIndents) {
      for (let index = 0; index < this.indents.length; index++) {
        const start = this.indents[index].displayStart + OnlineTextIndentedContent.INDENT.length;
        const end = index + 1 < this.indents.length ? this.indents[index + 1].displayStart : this.text.length;
        builder.addText(this.text.substring(start, end));
      }
      return;
    }
    const measureStyle: graphicsText.ParagraphStyle = { textStyle: textStyle, align: graphicsText.TextAlign.LEFT };
    const measureBuilder = new graphicsText.ParagraphBuilder(measureStyle, graphicsText.FontCollection.getGlobalInstance());
    measureBuilder.pushStyle(textStyle);
    measureBuilder.addText('  ');
    measureBuilder.popStyle();
    const measure = measureBuilder.build();
    measure.layoutSync(Math.max(1, (textStyle.fontSize ?? 1) * 10));
    const indentStyle: graphicsText.TextStyle = {
      fontSize: textStyle.fontSize,
      fontWeight: textStyle.fontWeight,
      fontFamilies: textStyle.fontFamilies,
      fontVariations: textStyle.fontVariations,
      heightScale: textStyle.heightScale,
      heightOnly: textStyle.heightOnly,
      locale: textStyle.locale,
      letterSpacing: ((textStyle.fontSize ?? 1) * 2 - measure.getMaxIntrinsicWidth()) / 2
    };
    for (let index = 0; index < this.indents.length; index++) {
      const start = this.indents[index].displayStart + OnlineTextIndentedContent.INDENT.length;
      const end = index + 1 < this.indents.length ? this.indents[index + 1].displayStart : this.text.length;
      // Reserve 2em using the selected font on older SDKs and during the initial measurement.
      // API 26 replaces these inline spaces with native line insets after wrapping is known.
      builder.pushStyle(indentStyle);
      builder.addText('  ');
      builder.popStyle();
      builder.addText(this.text.substring(start, end));
    }
  }

  nativeOffsetForDisplay(displayOffset: number): number {
    const offset = Math.max(0, Math.min(displayOffset, this.text.length));
    let low = 0;
    let high = this.indents.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (this.indents[middle].displayStart <= offset) low = middle + 1;
      else high = middle;
    }
    if (low === 0) return offset;
    const start = this.indents[low - 1].displayStart;
    return offset - (low - 1) * 2 - Math.min(2, offset - start);
  }

  displayOffsetForNative(nativeOffset: number): number {
    const offset = Math.max(0, nativeOffset);
    let low = 0;
    let high = this.indents.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (this.indents[middle].displayStart - middle * 2 <= offset) low = middle + 1;
      else high = middle;
    }
    if (low === 0) return offset;
    const start = this.indents[low - 1].displayStart;
    return offset === start - (low - 1) * 2 ? start : Math.min(this.text.length, offset + low * 2);
  }

  sourceOffsetForDisplay(displayOffset: number): number {
    const offset = Math.max(0, Math.min(displayOffset, this.text.length));
    if (offset === 0) return 0;
    if (offset === this.text.length) return this.sourceLength;
    let low = 0;
    let high = this.indents.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (this.indents[middle].displayStart <= offset) low = middle + 1;
      else high = middle;
    }
    if (low === 0) return Math.min(offset, this.sourceLength);
    const indent = this.indents[low - 1];
    const relativeOffset = offset - indent.displayStart;
    if (relativeOffset < OnlineTextIndentedContent.INDENT.length) return indent.sourceStart;
    return Math.min(this.sourceLength,
      indent.contentStart + relativeOffset - OnlineTextIndentedContent.INDENT.length);
  }

  restoreSourceOffsets(pages: OnlineTextPage[]): OnlineTextPage[] {
    for (const page of pages) {
      page.startOffset = this.sourceOffsetForDisplay(page.startOffset);
      page.endOffset = this.sourceOffsetForDisplay(page.endOffset);
    }
    return pages;
  }
}

export class OnlineTextMeasuredLine {
  startOffset: number = 0;
  heightPx: number = 0;
  spacingAfterPx: number = 0;

  static of(startOffset: number, heightPx: number): OnlineTextMeasuredLine {
    const line = new OnlineTextMeasuredLine();
    line.startOffset = Math.max(0, startOffset);
    line.heightPx = Math.max(1, heightPx);
    return line;
  }
}

export class OnlineTextNavigationTarget {
  chapterIndex: number = 0;
  pageIndex: number = 0;
  openLastPage: boolean = false;
  moved: boolean = false;

  static of(chapterIndex: number, pageIndex: number,
    openLastPage: boolean, moved: boolean): OnlineTextNavigationTarget {
    const target = new OnlineTextNavigationTarget();
    target.chapterIndex = Math.max(0, chapterIndex);
    target.pageIndex = Math.max(0, pageIndex);
    target.openLastPage = openLastPage;
    target.moved = moved;
    return target;
  }
}

export class OnlineTextPageNavigator {
  static previous(chapterIndex: number, pageIndex: number): OnlineTextNavigationTarget {
    if (pageIndex > 0) {
      return OnlineTextNavigationTarget.of(chapterIndex, pageIndex - 1, false, true);
    }
    if (chapterIndex > 0) {
      return OnlineTextNavigationTarget.of(chapterIndex - 1, 0, true, true);
    }
    return OnlineTextNavigationTarget.of(chapterIndex, pageIndex, false, false);
  }

  static next(chapterIndex: number, pageIndex: number,
    pageCount: number, chapterCount: number): OnlineTextNavigationTarget {
    const safePageCount = Math.max(1, pageCount);
    const safeChapterCount = Math.max(1, chapterCount);
    if (pageIndex + 1 < safePageCount) {
      return OnlineTextNavigationTarget.of(chapterIndex, pageIndex + 1, false, true);
    }
    if (chapterIndex + 1 < safeChapterCount) {
      return OnlineTextNavigationTarget.of(chapterIndex + 1, 0, false, true);
    }
    return OnlineTextNavigationTarget.of(chapterIndex, pageIndex, false, false);
  }
}

class OnlineTextLayout {
  source: string = '';
  key: string = '';
  serial: number = 0;
  width: number = 0;
  displayed: OnlineTextIndentedContent = new OnlineTextIndentedContent();
  paragraph: graphicsText.Paragraph | null = null;
  metrics: graphicsText.LineMetrics[] = [];
  lines: OnlineTextMeasuredLine[] = [];
  paintState: OnlineTextPaintState = new OnlineTextPaintState();
  nativeIndents: boolean = false;
}

export class OnlineTextPaginator {
  private static layouts: OnlineTextLayout[] = [];

  static invalidateLayouts(): void { OnlineTextPaginator.layouts = []; }

  private static layoutSerial: number = 0;
  static normalizeContent(content: string): string {
    let value = content
      .replace(new RegExp('\\r\\n?', 'g'), '\n')
      .replace(new RegExp('[\\u200B\\uFEFF]', 'g'), '')
      .replace(new RegExp('&nbsp;|&#160;', 'gi'), ' ');
    const hasHtmlBlocks = new RegExp(
      '<(?:br|p|div|section|article|li|h[1-6])(?:\\s[^>]*)?/?>|</(?:p|div|section|article|li|h[1-6])\\s*>', 'i')
      .test(value);
    if (hasHtmlBlocks) {
      value = value
        .replace(new RegExp('<!--[\\s\\S]*?-->', 'g'), '')
        .replace(new RegExp('<script[\\s\\S]*?</script>', 'gi'), '')
        .replace(new RegExp('<style[\\s\\S]*?</style>', 'gi'), '')
        .replace(new RegExp('<br\\s*/?>', 'gi'), '\n')
        .replace(new RegExp('</(?:p|div|section|article|li|h[1-6])\\s*>', 'gi'), '\n')
        .replace(new RegExp('<(?:p|div|section|article|li|h[1-6])\\b[^>]*>', 'gi'), '\n')
        .replace(new RegExp('<[^>]+>', 'g'), '');
    }
    return OnlineTextPaginator.decodeEntities(value)
      .replace(new RegExp('[ \\t]+\\n', 'g'), '\n')
      .replace(new RegExp('\\n[ \\t]+', 'g'), '\n')
      .replace(new RegExp('\\n{3,}', 'g'), '\n\n')
      .trim();
  }

  static paginate(content: string, widthPx: number, heightPx: number,
    fontSizePx: number, lineHeight: number, fontFamily: string = '', fontWeight: number = 400,
    alignment: string = 'justify', paragraphSpacing: number = 0): OnlineTextPage[] {
    const images = LocalTextImage.pattern();
    let match = images.exec(content);
    if (match !== null) {
      const pages: OnlineTextPage[] = [];
      let start = 0;
      while (match !== null) {
        OnlineTextPaginator.appendImageText(pages, content, start, match.index, widthPx, heightPx,
          fontSizePx, lineHeight, fontFamily, fontWeight, alignment, paragraphSpacing);
        const page = OnlineTextPage.of(content, match.index, images.lastIndex);
        page.imageUrl = LocalTextImage.resolve(match[1]);
        if (!page.imageUrl) {
          start = images.lastIndex;
          match = images.exec(content);
          continue;
        }
        page.text = '';
        page.layoutHeight = heightPx <= 1 ? Math.max(fontSizePx, widthPx * 1.4) : Math.max(fontSizePx, heightPx);
        page.layoutWidth = widthPx;
        pages.push(page);
        start = images.lastIndex;
        match = images.exec(content);
      }
      OnlineTextPaginator.appendImageText(pages, content, start, content.length, widthPx, heightPx,
        fontSizePx, lineHeight, fontFamily, fontWeight, alignment, paragraphSpacing);
      return pages;
    }
    const layout = OnlineTextPaginator.measure(content, widthPx, fontSizePx, lineHeight, fontFamily, fontWeight, alignment, paragraphSpacing);
    const displayed = layout.displayed;
    const metrics = layout.metrics;
    const pages = OnlineTextPaginator.paginateMeasuredLines(displayed.text, layout.lines, heightPx);
    let lineIndex = 0;
    for (const page of pages) {
      page.paragraph = layout.paragraph;
      page.paintState = layout.paintState;
      page.layoutKey = layout.serial;
      page.displayStart = page.startOffset;
      page.nativeOffsets = layout.nativeIndents ? displayed : null;
      page.layoutWidth = layout.width;
      page.firstLine = lineIndex;
      const first = metrics[lineIndex];
      if (first !== undefined) {
        page.layoutTop = first.baseline - first.ascent;
        let last = first;
        let shift = 0;
        while (lineIndex < metrics.length && metrics[lineIndex].startIndex < page.endOffset) {
          page.lineShifts.push(shift);
          last = metrics[lineIndex];
          page.trailingSpacing = layout.lines[lineIndex].spacingAfterPx;
          shift += page.trailingSpacing;
          lineIndex++;
        }
        page.layoutHeight = last.baseline + last.descent - page.layoutTop + shift - page.trailingSpacing;
        page.lineMetrics = metrics.slice(page.firstLine, lineIndex);
      }
    }
    return displayed.restoreSourceOffsets(pages);
  }

  private static appendImageText(pages: OnlineTextPage[], content: string, start: number, end: number,
    width: number, height: number, fontSize: number, lineHeight: number, family: string, weight: number,
    alignment: string, spacing: number): void {
    const section = content.substring(start, end);
    if (!section.trim()) return;
    const sourceStart = start + section.length - section.trimStart().length;
    const textPages = OnlineTextPaginator.paginate(section.trim(), width, height, fontSize, lineHeight, family, weight, alignment, spacing);
    for (const page of textPages) { page.startOffset += sourceStart; page.endOffset += sourceStart; pages.push(page); }
    if (textPages.length > 0) textPages[textPages.length - 1].endOffset = end;
  }

  private static measure(content: string, widthPx: number, fontSizePx: number, lineHeight: number,
    fontFamily: string, fontWeight: number, alignment: string, paragraphSpacing: number): OnlineTextLayout {
    const spacing = Number.isFinite(paragraphSpacing) ? Math.max(0, Math.min(2, paragraphSpacing)) : 0;
    const key = `${widthPx}:${fontSizePx}:${lineHeight}:${fontWeight}:${alignment}:${fontFamily}:${spacing}`;
    const cachedIndex = OnlineTextPaginator.layouts.findIndex((item: OnlineTextLayout): boolean =>
      item.key === key && item.source === content);
    if (cachedIndex >= 0) {
      const cached = OnlineTextPaginator.layouts.splice(cachedIndex, 1)[0];
      OnlineTextPaginator.layouts.push(cached);
      return cached;
    }
    const layout = new OnlineTextLayout();
    layout.source = content;
    layout.key = key;
    layout.serial = ++OnlineTextPaginator.layoutSerial;
    // 获取正文时已标准化；替换后的文字必须保持坐标，不能再次 trim/解码/去标签。
    layout.displayed = OnlineTextIndentedContent.fromNormalized(content);
    if (layout.displayed.text.length === 0) return layout;
    const safeWidth = Math.max(1, widthPx);
    const safeFontSize = Math.max(1, fontSizePx);
    const safeLineHeight = Math.max(1, lineHeight);
    const textStyle: graphicsText.TextStyle = {
      fontSize: safeFontSize,
      fontWeight: Math.max(0, Math.min(8, Math.round(fontWeight / 100) - 1)),
      // 空列表由全局字体集合匹配用户当前的系统字体。
      fontFamilies: fontFamily.length > 0 ? [fontFamily] : [],
      fontVariations: [{ axis: 'wght', value: fontWeight }],
      heightScale: safeLineHeight,
      heightOnly: true,
      locale: 'zh-Hans'
    };
    const paragraphStyle: graphicsText.ParagraphStyle = {
      textStyle: textStyle,
      align: OnlineTextPaginator.textAlign(alignment),
      wordBreak: graphicsText.WordBreak.BREAK_WORD,
      breakStrategy: graphicsText.BreakStrategy.GREEDY
    };
    const builder = new graphicsText.ParagraphBuilder(
      paragraphStyle, graphicsText.FontCollection.getGlobalInstance());
    builder.pushStyle(textStyle);
    layout.displayed.appendToBuilder(builder, textStyle);
    builder.popStyle();
    let paragraph = builder.build();
    paragraph.layoutSync(safeWidth);
    let metrics = paragraph.getLineMetrics();
    if (PlatformCompat.supports(26)) {
      // Use layout insets rather than inline content: justification must start after the indent.
      // The first layout determines which physical lines begin a source paragraph.
      paragraphStyle.headIndents = metrics.map((line: graphicsText.LineMetrics, index: number): number =>
        index === 0 || layout.displayed.text.charAt(line.startIndex - 1) === '\n' ? safeFontSize * 2 : 0);
      const insetBuilder = new graphicsText.ParagraphBuilder(paragraphStyle, graphicsText.FontCollection.getGlobalInstance());
      insetBuilder.pushStyle(textStyle);
      layout.displayed.appendToBuilder(insetBuilder, textStyle, true);
      insetBuilder.popStyle();
      paragraph = insetBuilder.build();
      paragraph.layoutSync(safeWidth);
      metrics = paragraph.getLineMetrics();
      layout.nativeIndents = true;
      for (const metric of metrics) {
        metric.startIndex = layout.displayed.displayOffsetForNative(metric.startIndex);
      }
    }
    const lines: OnlineTextMeasuredLine[] = [];
    for (let i = 0; i < metrics.length; i++) {
      const line = OnlineTextMeasuredLine.of(metrics[i].startIndex, metrics[i].height);
      const next = metrics[i + 1];
      if (next !== undefined && layout.displayed.text.charAt(next.startIndex - 1) === '\n') {
        line.spacingAfterPx = safeFontSize * spacing;
      }
      lines.push(line);
    }
    layout.width = safeWidth;
    layout.paragraph = paragraph;
    layout.metrics = metrics;
    layout.lines = lines;
    // Bound retained native layouts by both count and source size; oversized chapters remain uncached.
    if (content.length <= 160000) {
      OnlineTextPaginator.layouts.push(layout);
      let total = OnlineTextPaginator.layouts.reduce((sum: number, item: OnlineTextLayout): number => sum + item.source.length, 0);
      while (OnlineTextPaginator.layouts.length > 4 || total > 160000) {
        const removed = OnlineTextPaginator.layouts.shift();
        if (removed !== undefined) total -= removed.source.length;
      }
    }
    return layout;
  }

  private static textAlign(value: string): graphicsText.TextAlign {
    if (value === 'start') return graphicsText.TextAlign.LEFT;
    if (value === 'center') return graphicsText.TextAlign.CENTER;
    if (value === 'end') return graphicsText.TextAlign.RIGHT;
    return graphicsText.TextAlign.JUSTIFY;
  }

  static paginateMeasuredLines(content: string, lines: OnlineTextMeasuredLine[],
    heightPx: number): OnlineTextPage[] {
    if (content.length === 0) return [OnlineTextPage.of('', 0, 0)];
    if (lines.length === 0) return [OnlineTextPage.of(content, 0, content.length)];

    const pages: OnlineTextPage[] = [];
    const safeHeight = Math.max(1, heightPx);
    let pageStart = 0;
    let usedHeight = 0;
    let pendingSpacing = 0;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineStart = Math.max(pageStart, Math.min(line.startOffset, content.length));
      if (usedHeight > 0 && usedHeight + pendingSpacing + line.heightPx > safeHeight && lineStart > pageStart) {
        pages.push(OnlineTextPage.of(content, pageStart, lineStart));
        pageStart = lineStart;
        usedHeight = 0;
        pendingSpacing = 0;
      }
      usedHeight += pendingSpacing + line.heightPx;
      pendingSpacing = line.spacingAfterPx;
    }
    if (pageStart < content.length || pages.length === 0) {
      pages.push(OnlineTextPage.of(content, pageStart, content.length));
    }
    return pages;
  }

  static pageIndexForOffset(pages: OnlineTextPage[], charOffset: number): number {
    if (pages.length === 0) return 0;
    const offset = Math.max(0, charOffset);
    for (let i = 0; i < pages.length; i++) {
      if (offset < pages[i].endOffset) return i;
    }
    return pages.length - 1;
  }

  private static decodeEntities(content: string): string {
    return content
      .replace(new RegExp('&quot;', 'gi'), '"')
      .replace(new RegExp('&#39;|&apos;', 'gi'), "'")
      .replace(new RegExp('&lt;', 'gi'), '<')
      .replace(new RegExp('&gt;', 'gi'), '>')
      .replace(new RegExp('&amp;', 'gi'), '&');
  }
}
