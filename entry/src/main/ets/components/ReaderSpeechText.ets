import { ReaderParagraphComment } from '../model/ReaderComment';
import { ReaderCommentLayout, ReaderCommentAnchor } from '../service/text/ReaderCommentLayout';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { SpeechHighlightRange, SpeechTextHighlighter } from '../service/text/SpeechTextHighlighter';
import { ReaderPalette } from '../model/ReaderTheme';
import { OnlineTextPage } from '../service/text/OnlineTextPaginator';
import { ReaderParagraphNodeController } from '../service/text/ReaderParagraphNode';
import { ReaderTouchTracker } from '../utils/ReaderTapPolicy';
import { EpubPageStyle } from '../service/text/EpubPageStyle';

/** 混排页沿用同一正文绘制组件，各片段保留自己的原文坐标。 */
@ComponentV2
export struct ReaderSpeechText {
  @Param epubStyle: EpubPageStyle = new EpubPageStyle();
  @Param comments: ReaderParagraphComment[] = [];
  @Event onComment: (comment: ReaderParagraphComment) => void = () => {};
  @Param page: OnlineTextPage = new OnlineTextPage();
  @Param text: string = '';
  @Param source: string = '';
  @Param state: TextToSpeechState = new TextToSpeechState();
  @Param sourceStart: number = 0;
  @Param highlightEnabled: boolean = false;
  @Param selectionEnabled: boolean = true;
  @Event onSelectionChange: (active: boolean) => void = () => {};
  @Event onReadFrom: (offset: number) => void = () => {};
  @Param fontFamily: string = '';
  @Param fontWeight: number = 400;
  @Param letterSpacing: number = 0;
  @Param dialogueHighlight: boolean = false;
  @Param dialogueHighlightColor: string = '';
  @Param speechMark: string = 'color';
  @Param speechMarkColor: string = '';
  @Param fontSize: number = 18;
  @Param lineHeight: number = 1.9;
  @Param palette: ReaderPalette = new ReaderPalette();

  private fragmentPalette(heading: boolean): ReaderPalette {
    const style = this.epubStyle;
    const color = heading && style.headingColor ? style.headingForeground || style.foreground || '#202020' :
      (style.image || style.color ? style.foreground : '');
    if (!color) return this.palette;
    const value = ReaderPalette.of(this.palette.background, color, this.palette.secondary, this.palette.isDark);
    value.accent = this.palette.accent;
    return value;
  }

  build() {
    Column() {
      if (this.page.parts.length > 0) {
        ForEach(this.page.parts, (part: OnlineTextPage) => {
          ReaderTextFragment({
            comments: this.comments, onComment: this.onComment,
            letterSpacing: this.letterSpacing, dialogueHighlight: this.dialogueHighlight && !part.isHeading, dialogueHighlightColor: this.dialogueHighlightColor, speechMark: this.speechMark, speechMarkColor: this.speechMarkColor,
            page: part, text: part.text,
            source: this.source.substring(part.startOffset - this.sourceStart, part.endOffset - this.sourceStart),
            sourceStart: part.startOffset, state: this.state, highlightEnabled: this.highlightEnabled && !part.isHeading,
            selectionEnabled: this.selectionEnabled && !part.isHeading, onSelectionChange: this.onSelectionChange, onReadFrom: this.onReadFrom,
            fontFamily: this.fontFamily, fontWeight: this.fontWeight, fontSize: this.fontSize,
            lineHeight: this.lineHeight, palette: this.fragmentPalette(part.isHeading)
          }).margin({ top: this.getUIContext().px2vp(part.flowSpacing) })
            .backgroundColor(part.isHeading ? this.epubStyle.headingColor || Color.Transparent : Color.Transparent)
        }, (part: OnlineTextPage): string => `${part.layoutKey}:${part.startOffset}:${part.endOffset}:${part.imageUrl}:${part.imageWidth}:${part.layoutHeight}:${part.flowSpacing}`)
      } else {
        ReaderTextFragment({
          comments: this.comments, onComment: this.onComment,
          letterSpacing: this.letterSpacing, dialogueHighlight: this.dialogueHighlight && !this.page.isHeading, dialogueHighlightColor: this.dialogueHighlightColor, speechMark: this.speechMark, speechMarkColor: this.speechMarkColor,
          page: this.page, text: this.text, source: this.source, sourceStart: this.sourceStart,
          state: this.state, highlightEnabled: this.highlightEnabled && !this.page.isHeading, selectionEnabled: this.selectionEnabled && !this.page.isHeading,
          onSelectionChange: this.onSelectionChange, onReadFrom: this.onReadFrom,
          fontFamily: this.fontFamily, fontWeight: this.fontWeight, fontSize: this.fontSize,
          lineHeight: this.lineHeight, palette: this.fragmentPalette(this.page.isHeading)
        }).backgroundColor(this.page.isHeading ? this.epubStyle.headingColor || Color.Transparent : Color.Transparent)
      }
    }.width('100%').alignItems(HorizontalAlign.Center)
  }
}

/** 当前自然段整体高亮；仅范围或分页内容改变时重新计算，不按字刷新。 */
@ComponentV2
struct ReaderTextFragment {
  @Param comments: ReaderParagraphComment[] = [];
  @Event onComment: (comment: ReaderParagraphComment) => void = () => {};
  @Param page: OnlineTextPage = new OnlineTextPage();
  private paragraphNode: ReaderParagraphNodeController = new ReaderParagraphNodeController();
  private selectionTouch: ReaderTouchTracker = new ReaderTouchTracker();
  private selectionTouchStartedAt: number = 0;
  @Param text: string = '';
  @Param source: string = '';
  @Param state: TextToSpeechState = new TextToSpeechState();
  @Param sourceStart: number = 0;
  @Param highlightEnabled: boolean = false;
  @Param selectionEnabled: boolean = true;
  @Event onSelectionChange: (active: boolean) => void = () => {};
  @Event onReadFrom: (offset: number) => void = () => {};
  @Local selecting: boolean = false;
  @Local selectionStart: number = -1;
  @Local selectionEnd: number = -1;
  @Param fontFamily: string = '';
  @Param fontWeight: number = 400;
  @Param letterSpacing: number = 0;
  @Param dialogueHighlight: boolean = false;
  @Param dialogueHighlightColor: string = '';
  @Param speechMark: string = 'color';
  @Param speechMarkColor: string = '';
  @Param fontSize: number = 18;
  @Param lineHeight: number = 1.9;
  @Param palette: ReaderPalette = new ReaderPalette();

  @Monitor('speechMarkColor', 'speechMark', 'dialogueHighlight', 'dialogueHighlightColor', 'page', 'text', 'source', 'sourceStart', 'palette', 'highlightEnabled', 'selecting', 'selectionStart', 'selectionEnd', 'selectionEnabled',
    'state.active', 'state.highlightOffset', 'state.highlightEnd')
  updateParagraph(): void {
    this.paragraphNode.update(this.page, this.highlightRange, this.palette, this.selecting ? 'highlight' : this.speechMark, this.dialogueHighlight, this.dialogueHighlightColor, this.speechMarkColor);
  }

  aboutToAppear(): void { this.updateParagraph(); }
  aboutToDisappear(): void { this.onSelectionChange(false); this.paragraphNode.release(); }

  @Monitor('page', 'selectionEnabled')
  resetSelection(): void {
    this.selecting = false;
    this.selectionStart = -1;
    this.selectionEnd = -1;
    this.onSelectionChange(false);
  }

  @Computed
  get commentAnchors(): ReaderCommentAnchor[] {
    return ReaderCommentLayout.anchors(this.page, this.source, this.sourceStart, this.comments, this.getUIContext().vp2px(1));
  }

  private updateSelection(start: number, end: number): void {
    this.selectionStart = start;
    this.selectionEnd = end;
    this.selecting = this.selectionEnabled && start >= 0 && end > start;
    this.onSelectionChange(this.selecting);
  }

  private speechSelectionMenu(): EditMenuOptions {
    return {
      onCreateMenu: (items: TextMenuItem[]): TextMenuItem[] => {
        const listen: TextMenuItem = {
          content: $r('app.string.reader_listen_from_paragraph'),
          id: TextMenuItemId.of('reader-listen-from-paragraph')
        };
        return [listen, ...items];
      },
      onMenuItemClick: (item: TextMenuItem, range: TextRange): boolean => {
        if (!item.id.equals(TextMenuItemId.of('reader-listen-from-paragraph'))) return false;
        const start = range.start ?? this.selectionStart;
        if (this.selectionEnabled && start >= 0) {
          const offset = this.sourceStart + SpeechTextHighlighter.sourceOffset(this.text, this.source, start);
          this.onReadFrom(offset);
          this.updateSelection(-1, -1);
        }
        return true;
      }
    };
  }

  private beginSelection(event: GestureEvent): void {
    const paragraph = this.page.paragraph;
    const finger = event.fingerList[0];
    if (!this.selectionEnabled || this.selecting || paragraph === null || finger === undefined || !this.text) return;
    const context = this.getUIContext();
    const y: number = context.vp2px(finger.localY);
    let lineIndex: number = 0;
    for (let index = 0; index < this.page.lineMetrics.length; index++) {
      const metric = this.page.lineMetrics[index];
      const top: number = metric.baseline - metric.ascent - this.page.layoutTop + (this.page.lineShifts[index] ?? 0);
      if (y >= top) lineIndex = index;
    }
    const position = paragraph.getGlyphPositionAtCoordinate(context.vp2px(finger.localX),
      y + this.page.layoutTop - (this.page.lineShifts[lineIndex] ?? 0));
    const word = paragraph.getWordBoundary(position.position);
    const start: number = (this.page.nativeOffsets?.displayOffsetForNative(word.start) ?? word.start) - this.page.displayStart;
    const end: number = (this.page.nativeOffsets?.displayOffsetForNative(word.end) ?? word.end) - this.page.displayStart;
    this.updateSelection(Math.max(0, Math.min(this.text.length, start)), Math.max(0, Math.min(this.text.length, end)));
  }

  @Computed
  get highlightRange(): SpeechHighlightRange {
    if (this.selectionEnabled && this.selecting) {
      const range: SpeechHighlightRange = new SpeechHighlightRange();
      range.start = this.selectionStart;
      range.end = this.selectionEnd;
      return range;
    }
    if (!this.highlightEnabled || !this.state.active) return new SpeechHighlightRange();
    return SpeechTextHighlighter.displayRange(this.text, this.source,
      this.state.highlightOffset - this.sourceStart, this.state.highlightEnd - this.sourceStart);
  }

  build() {
    if (this.page.imageUrl) {
      Image(this.page.imageUrl).width(this.getUIContext().px2vp(this.page.imageWidth))
        .height(this.getUIContext().px2vp(this.page.layoutHeight))
        .objectFit(ImageFit.Contain).draggable(false)
    } else if (this.page.paragraph !== null) {
      Stack({ alignContent: Alignment.TopStart }) {
      NodeContainer(this.paragraphNode)
        .width('100%')
        .height(this.getUIContext().px2vp(this.page.layoutHeight))
        .accessibilityText(this.text)
        .hitTestBehavior(HitTestMode.None)
      if (this.selectionEnabled) {
        Text(this.text).width(this.getUIContext().px2vp(this.page.layoutWidth)).height(this.getUIContext().px2vp(this.page.layoutHeight))
          .fontSize(this.fontSize).letterSpacing(this.letterSpacing).fontFamily(this.fontFamily || undefined)
          .fontWeight(this.fontWeight, { enableVariableFontWeight: true }).lineHeight(this.fontSize * this.lineHeight)
          .textAlign(TextAlign.JUSTIFY).wordBreak(WordBreak.BREAK_WORD)
          // 正文与选区高亮始终由原 Paragraph 绘制，选字不切换排版引擎。
          .fontColor(Color.Transparent).selectedBackgroundColor(Color.Transparent)
          .draggable(false)
          // 普通触摸不经过原生选字层，长按命中后才交给系统处理选区与菜单。
          .hitTestBehavior(this.selecting ? HitTestMode.Default : HitTestMode.None)
          .copyOption(CopyOptions.LocalDevice).textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
          .editMenuOptions(this.speechSelectionMenu())
          .selection(this.selectionStart, this.selectionEnd)
          .onTextSelectionChange((start: number, end: number): void => {
            this.updateSelection(start, end);
          })
          .onBlur((): void => this.updateSelection(-1, -1))
          .onTouch((event: TouchEvent): void => {
            this.selectionTouch.update(event);
            if (event.type === TouchType.Down) this.selectionTouchStartedAt = Date.now();
            // 点击正文显式退出选区；拖动手柄及长按继续交给系统选字。
            if (event.type === TouchType.Up && Date.now() - this.selectionTouchStartedAt < 500 &&
              this.selectionTouch.canTap()) this.updateSelection(-1, -1);
          })
      }
      ForEach(this.commentAnchors, (anchor: ReaderCommentAnchor) => {
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.reader_comment')).width(16).height(16).fillColor(this.palette.secondary)
        }
        .width(this.getUIContext().px2vp(anchor.size)).height(this.getUIContext().px2vp(anchor.size))
        .padding(2).backgroundColor(Color.Transparent).borderRadius(6)
        .position({ x: this.getUIContext().px2vp(anchor.x), y: this.getUIContext().px2vp(anchor.y) })
        .accessibilityText(anchor.comment.label || this.getUIContext().getHostContext()?.resourceManager
          .getStringSync($r('app.string.reader_comment_title').id) || '')
        .enabled(!this.selecting)
        .onTouch((event: TouchEvent): void => { event.stopPropagation(); })
        .onClick((): void => { if (!this.selecting) this.onComment(anchor.comment); })
        .id('reader-comment-' + anchor.comment.offset)
      }, (anchor: ReaderCommentAnchor): string => anchor.comment.offset + ':' + anchor.comment.url)
      }.width('100%').height(this.getUIContext().px2vp(this.page.layoutHeight))
        .parallelGesture(LongPressGesture({ repeat: false, duration: 500 })
          .onAction((event: GestureEvent): void => this.beginSelection(event)))
    } else {
    Text() {
      if (this.highlightRange.start >= 0) {
        Span(this.text.substring(0, this.highlightRange.start))
        Span(this.text.substring(this.highlightRange.start, this.highlightRange.end))
          .fontColor(this.speechMark === 'color' && !this.selecting ? (this.speechMarkColor || this.palette.accent) : this.palette.primary)
          .decoration({ type: this.speechMark === 'underline' && !this.selecting ? TextDecorationType.Underline : TextDecorationType.None })
          .textBackgroundStyle({ color: this.speechMark === 'highlight' || this.selecting ? '#33' + this.palette.primary.substring(1) : '#00000000', radius: 3 })
        Span(this.text.substring(this.highlightRange.end))
      } else {
        Span(this.text)
      }
    }
    .width('100%')
    .fontSize(this.fontSize).letterSpacing(this.letterSpacing)
    .fontColor(this.palette.primary)
    .fontFamily(this.fontFamily.length > 0 ? this.fontFamily : undefined)
    .fontWeight(this.fontWeight, { enableVariableFontWeight: true })
    .lineHeight(this.fontSize * this.lineHeight)
    .textAlign(TextAlign.JUSTIFY)
    .wordBreak(WordBreak.BREAK_WORD)
    .lineBreakStrategy(LineBreakStrategy.GREEDY)
    .draggable(false)
    .copyOption(this.selectionEnabled ? CopyOptions.LocalDevice : CopyOptions.None)
    .editMenuOptions(this.speechSelectionMenu())
    .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
    .onTextSelectionChange((start: number, end: number): void => {
      this.updateSelection(start, end);
    })
    .onBlur((): void => this.updateSelection(-1, -1))
    }
  }
}
