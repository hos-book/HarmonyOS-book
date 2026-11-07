import { text as graphicsText } from '@kit.ArkGraphics2D';
import { PlatformCompat } from '../../utils/PlatformCompat';
import { ReaderDialogueHighlighter, ReaderDialogueRange } from './ReaderDialogueHighlighter';
import { LocalTextImage } from './LocalTextImage';

export class OnlineTextPaintState {
  color: string = '';
  lines: graphicsText.TextLine[] = [];
}

export class OnlineTextPage {
  isHeading: boolean = false;
  dialogueRanges: ReaderDialogueRange[] = [];
  parts: OnlineTextPage[] = [];
  flowSpacing: number = 0;
  columns: OnlineTextPage[] = [];

  static spreads(content: string, pages: OnlineTextPage[]): OnlineTextPage[] {
    const spreads: OnlineTextPage[] = [];
    for (let index = 0; index < pages.length; index += 2) {
      const columns = pages.slice(index, index + 2);
      const spread = OnlineTextPage.of(content, columns[0].startOffset, columns[columns.length - 1].endOffset);
      spread.columns = columns;
      spreads.push(spread);
    }
    return spreads;
  }

  imageUrl: string = '';
  imageWidth: number = 0;
  firstLine: number = 0;
  // Each native line keeps its geometry; only paragraph boundaries add a vertical translation.
  lineShifts: number[] = [];
  commentLineExtra: number[] = [];
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
  commentLineExtra: number[] = [];
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
    alignment: string = 'justify', paragraphSpacing: number = 0, letterSpacingPx: number = 0,
    headingTitle: string = '', headingSizePx: number = fontSizePx, headingStyle: string = 'center',
    commentOffsets: number[] = [], commentSizePx: number = 0): OnlineTextPage[] {
    const heading = headingTitle.trim();
    const images = LocalTextImage.pattern();
    let match = images.exec(content);
    if (match !== null) {
      const pages: OnlineTextPage[] = [];
      let start = 0;
      while (match !== null) {
        OnlineTextPaginator.appendImageText(pages, content, start, match.index, widthPx, 1,
          fontSizePx, lineHeight, fontFamily, fontWeight, alignment, paragraphSpacing, letterSpacingPx, commentOffsets, commentSizePx);
        const page = OnlineTextPage.of(content, match.index, images.lastIndex);
        page.imageUrl = LocalTextImage.resolve(match[1]);
        if (!page.imageUrl) {
          start = images.lastIndex;
          match = images.exec(content);
          continue;
        }
        page.text = '';
        const size = LocalTextImage.size(match[1]);
        const naturalWidth = size !== undefined && size.width > 0 ? size.width : Math.min(widthPx, fontSizePx * 6);
        const naturalHeight = size !== undefined && size.height > 0 ? size.height : fontSizePx * 4;
        const scale = Math.min(1, Math.max(1, widthPx) / naturalWidth,
          heightPx > 1 ? heightPx / naturalHeight : 1);
        page.imageWidth = naturalWidth * scale;
        page.layoutHeight = naturalHeight * scale;
        page.layoutWidth = widthPx;
        page.trailingSpacing = fontSizePx * Math.max(0, Math.min(2, paragraphSpacing));
        pages.push(page);
        start = images.lastIndex;
        match = images.exec(content);
      }
      OnlineTextPaginator.appendImageText(pages, content, start, content.length, widthPx, 1,
        fontSizePx, lineHeight, fontFamily, fontWeight, alignment, paragraphSpacing, letterSpacingPx, commentOffsets, commentSizePx);
      return OnlineTextPaginator.composeHeading(content, pages, widthPx, heightPx, heading, headingSizePx, fontFamily, headingStyle);
    }
    const layout = OnlineTextPaginator.measure(content, widthPx, fontSizePx, lineHeight, fontFamily, fontWeight, alignment, paragraphSpacing, letterSpacingPx, commentOffsets, commentSizePx);
    const displayed = layout.displayed;
    const metrics = layout.metrics;
    const pages = OnlineTextPaginator.paginateMeasuredLines(displayed.text, layout.lines, heading ? 1 : heightPx);
    const dialogueRanges = ReaderDialogueHighlighter.ranges(displayed.text);
    let lineIndex = 0;
    for (const page of pages) {
      page.paragraph = layout.paragraph;
      page.paintState = layout.paintState;
      page.layoutKey = layout.serial;
      page.displayStart = page.startOffset;
      page.dialogueRanges = dialogueRanges.filter((range: ReaderDialogueRange): boolean =>
        range.end > page.startOffset && range.start < page.endOffset).map((range: ReaderDialogueRange): ReaderDialogueRange =>
          new ReaderDialogueRange(Math.max(0, range.start - page.startOffset),
            Math.min(page.text.length, range.end - page.startOffset)));
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
          page.commentLineExtra.push(layout.commentLineExtra[lineIndex] ?? 0);
          last = metrics[lineIndex];
          page.trailingSpacing = layout.lines[lineIndex].spacingAfterPx;
          shift += page.trailingSpacing + (layout.commentLineExtra[lineIndex] ?? 0);
          lineIndex++;
        }
        page.layoutHeight = last.baseline + last.descent - page.layoutTop + shift - page.trailingSpacing;
        page.lineMetrics = metrics.slice(page.firstLine, lineIndex);
      }
    }
    const restored = displayed.restoreSourceOffsets(pages);
    return heading ? OnlineTextPaginator.composeHeading(content, restored, widthPx, heightPx,
      heading, headingSizePx, fontFamily, headingStyle) : restored;
  }

  /** 标题只占布局空间，不进入正文、朗读或书签的字符坐标。 */
  private static composeHeading(content: string, parts: OnlineTextPage[], width: number, height: number,
    title: string, size: number, family: string, style: string): OnlineTextPage[] {
    const headings: OnlineTextPage[] = [];
    if (title.length > 0) {
      const fontSize = Number.isFinite(size) ? Math.max(1, size) : 26;
      const weight = style === 'plain' ? 400 : 700;
      const textStyle: graphicsText.TextStyle = {
        fontSize: fontSize, fontWeight: weight / 100 - 1,
        fontFamilies: family ? [family] : [], fontVariations: [{ axis: 'wght', value: weight }],
        heightScale: 1.4, heightOnly: true, locale: 'zh-Hans'
      };
      const paragraphStyle: graphicsText.ParagraphStyle = {
        textStyle: textStyle, align: style === 'center' ? graphicsText.TextAlign.CENTER : graphicsText.TextAlign.LEFT,
        wordBreak: graphicsText.WordBreak.BREAK_WORD, breakStrategy: graphicsText.BreakStrategy.GREEDY
      };
      const builder = new graphicsText.ParagraphBuilder(paragraphStyle, graphicsText.FontCollection.getGlobalInstance());
      builder.pushStyle(textStyle);
      builder.addText(title);
      builder.popStyle();
      const paragraph = builder.build();
      paragraph.layoutSync(Math.max(1, width));
      const metrics = paragraph.getLineMetrics();
      const serial = ++OnlineTextPaginator.layoutSerial;
      const paintState = new OnlineTextPaintState();
      for (let index = 0; index < metrics.length; index++) {
        const metric = metrics[index];
        const part = new OnlineTextPage();
        part.isHeading = true;
        part.text = title.substring(metric.startIndex, metrics[index + 1]?.startIndex ?? title.length);
        part.paragraph = paragraph;
        part.paintState = paintState;
        part.layoutKey = serial;
        part.layoutWidth = width;
        part.layoutTop = metric.baseline - metric.ascent;
        part.layoutHeight = metric.ascent + metric.descent;
        part.firstLine = index;
        part.lineMetrics = [metric];
        part.lineShifts = [0];
        part.trailingSpacing = index === metrics.length - 1 ? fontSize * 0.6 : 0;
        headings.push(part);
      }
    }
    const all = headings.concat(parts);
    return height <= 1 ? all : OnlineTextPaginator.flowParts(content, all, width, height);
  }

  private static appendImageText(pages: OnlineTextPage[], content: string, start: number, end: number,
    width: number, height: number, fontSize: number, lineHeight: number, family: string, weight: number,
    alignment: string, spacing: number, letterSpacingPx: number, commentOffsets: number[], commentSizePx: number): void {
    const section = content.substring(start, end);
    if (!section.trim()) return;
    const sourceStart = start + section.length - section.trimStart().length;
    const offsets = commentOffsets.filter((offset: number): boolean => offset > sourceStart && offset <= end)
      .map((offset: number): number => offset - sourceStart);
    const textPages = OnlineTextPaginator.paginate(section.trim(), width, height, fontSize, lineHeight, family, weight, alignment, spacing, letterSpacingPx,
      '', fontSize, 'center', offsets, commentSizePx);
    for (const page of textPages) { page.startOffset += sourceStart; page.endOffset += sourceStart; pages.push(page); }
    if (textPages.length > 0) textPages[textPages.length - 1].endOffset = end;
  }

  /** 以正文行和完整插图为单位装页；剩余空间不足才换页，不放大小图。 */
  private static flowParts(content: string, parts: OnlineTextPage[], width: number, height: number): OnlineTextPage[] {
    const pages: OnlineTextPage[] = [];
    let page = OnlineTextPage.of(content, 0, 0);
    let spacing = 0;
    for (const part of parts) {
      if (page.parts.length > 0 && page.layoutHeight + spacing + part.layoutHeight > Math.max(1, height)) {
        page.endOffset = part.startOffset;
        pages.push(page);
        page = OnlineTextPage.of(content, part.startOffset, part.startOffset);
        spacing = 0;
      }
      part.flowSpacing = page.parts.length > 0 ? spacing : 0;
      const previous = page.parts[page.parts.length - 1];
      if (previous !== undefined && part.paragraph !== null && previous.paragraph === part.paragraph) {
        const shift = previous.layoutHeight + part.flowSpacing - (part.layoutTop - previous.layoutTop);
        for (const value of part.lineShifts) previous.lineShifts.push(value + shift);
        previous.lineMetrics.push(...part.lineMetrics);
        previous.commentLineExtra.push(...part.commentLineExtra);
        for (const range of part.dialogueRanges) {
          previous.dialogueRanges.push(new ReaderDialogueRange(previous.text.length + range.start, previous.text.length + range.end));
        }
        previous.text += part.text;
        previous.endOffset = part.endOffset;
        previous.layoutHeight += part.flowSpacing + part.layoutHeight;
        previous.trailingSpacing = part.trailingSpacing;
      } else {
        page.parts.push(part);
      }
      page.layoutWidth = width;
      page.layoutHeight += part.flowSpacing + part.layoutHeight;
      page.endOffset = part.endOffset;
      spacing = part.trailingSpacing;
    }
    if (page.parts.length > 0) { page.endOffset = content.length; pages.push(page); }
    return pages;
  }

  private static measure(content: string, widthPx: number, fontSizePx: number, lineHeight: number,
    fontFamily: string, fontWeight: number, alignment: string, paragraphSpacing: number, letterSpacingPx: number,
    commentOffsets: number[], commentSizePx: number): OnlineTextLayout {
    const spacing = Number.isFinite(paragraphSpacing) ? Math.max(0, Math.min(2, paragraphSpacing)) : 0;
    const key = `${widthPx}:${fontSizePx}:${lineHeight}:${fontWeight}:${alignment}:${fontFamily}:${spacing}:${letterSpacingPx}:${commentSizePx}:${commentOffsets.join(',')}`;
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
      letterSpacing: Math.max(0, letterSpacingPx),
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
    const comments = new Set<number>(commentOffsets);
    for (let i = 0; i < metrics.length; i++) {
      const line = OnlineTextMeasuredLine.of(metrics[i].startIndex, metrics[i].height);
      const next = metrics[i + 1];
      let extra = 0;
      if (comments.size > 0 && commentSizePx > 0) {
        const displayedEnd = next?.startIndex ?? layout.displayed.text.length;
        const body = layout.displayed.text.substring(metrics[i].startIndex, displayedEnd).trimEnd();
        const end = metrics[i].startIndex + body.length;
        if (body.length > 0 && comments.has(layout.displayed.sourceOffsetForDisplay(end))) {
          let start = end - 1;
          const low = layout.displayed.text.charCodeAt(start);
          const high = layout.displayed.text.charCodeAt(start - 1);
          if (low >= 0xDC00 && low <= 0xDFFF && high >= 0xD800 && high <= 0xDBFF) start--;
          const boxes = paragraph.getRectsForRange({
            start: layout.nativeIndents ? layout.displayed.nativeOffsetForDisplay(start) : start,
            end: layout.nativeIndents ? layout.displayed.nativeOffsetForDisplay(end) : end
          }, graphicsText.RectWidthStyle.TIGHT, graphicsText.RectHeightStyle.TIGHT);
          const last = boxes[boxes.length - 1];
          // 仅段尾放不下图标时增加一行图标高度，正文始终使用完整对称宽度。
          if (last && last.rect.right + commentSizePx > safeWidth) extra = commentSizePx;
        }
      }
      layout.commentLineExtra.push(extra);
      line.heightPx += extra;
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
    if (offset === 0) return 0;
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
