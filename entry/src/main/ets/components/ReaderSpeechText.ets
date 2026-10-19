import { TextToSpeechState } from '../model/TextToSpeechState';
import { SpeechHighlightRange, SpeechTextHighlighter } from '../service/text/SpeechTextHighlighter';
import { ReaderPalette } from '../model/ReaderTheme';
import { OnlineTextPage } from '../service/text/OnlineTextPaginator';
import { ReaderParagraphNodeController } from '../service/text/ReaderParagraphNode';
import { ReaderTouchTracker } from '../utils/ReaderTapPolicy';

/** 当前自然段整体高亮；仅范围或分页内容改变时重新计算，不按字刷新。 */
@ComponentV2
export struct ReaderSpeechText {
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
  @Local selecting: boolean = false;
  @Local selectionStart: number = -1;
  @Local selectionEnd: number = -1;
  @Param fontFamily: string = '';
  @Param fontWeight: number = 400;
  @Param fontSize: number = 18;
  @Param lineHeight: number = 1.9;
  @Param palette: ReaderPalette = new ReaderPalette();

  @Monitor('page', 'text', 'source', 'sourceStart', 'palette', 'highlightEnabled', 'selecting', 'selectionStart', 'selectionEnd', 'selectionEnabled',
    'state.active', 'state.highlightOffset', 'state.highlightEnd')
  updateParagraph(): void {
    this.paragraphNode.update(this.page, this.highlightRange, this.palette);
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

  private updateSelection(start: number, end: number): void {
    this.selectionStart = start;
    this.selectionEnd = end;
    this.selecting = this.selectionEnabled && start >= 0 && end > start;
    this.onSelectionChange(this.selecting);
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
    if (!this.selectionEnabled || !this.highlightEnabled || !this.state.active) return new SpeechHighlightRange();
    return SpeechTextHighlighter.displayRange(this.text, this.source,
      this.state.highlightOffset - this.sourceStart, this.state.highlightEnd - this.sourceStart);
  }

  build() {
    if (this.page.imageUrl) {
      Image(this.page.imageUrl).width('100%').height(this.getUIContext().px2vp(this.page.layoutHeight))
        .objectFit(ImageFit.Contain).draggable(false)
    } else if (this.page.paragraph !== null) {
      Stack({ alignContent: Alignment.TopStart }) {
      NodeContainer(this.paragraphNode)
        .width('100%')
        .height(this.getUIContext().px2vp(this.page.layoutHeight))
        .accessibilityText(this.text)
        .hitTestBehavior(HitTestMode.None)
      if (this.selectionEnabled) {
        Text(this.text).width('100%').height(this.getUIContext().px2vp(this.page.layoutHeight))
          .fontSize(this.fontSize).fontFamily(this.fontFamily || undefined)
          .fontWeight(this.fontWeight, { enableVariableFontWeight: true }).lineHeight(this.fontSize * this.lineHeight)
          .textAlign(TextAlign.JUSTIFY).wordBreak(WordBreak.BREAK_WORD)
          // 正文与选区高亮始终由原 Paragraph 绘制，选字不切换排版引擎。
          .fontColor(Color.Transparent).selectedBackgroundColor(Color.Transparent)
          .draggable(false)
          // 普通触摸不经过原生选字层，长按命中后才交给系统处理选区与菜单。
          .hitTestBehavior(this.selecting ? HitTestMode.Default : HitTestMode.None)
          .copyOption(CopyOptions.LocalDevice).textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
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
      }.width('100%').height(this.getUIContext().px2vp(this.page.layoutHeight))
        .parallelGesture(LongPressGesture({ repeat: false, duration: 500 })
          .onAction((event: GestureEvent): void => this.beginSelection(event)))
    } else {
    Text() {
      if (this.highlightRange.start >= 0) {
        Span(this.text.substring(0, this.highlightRange.start))
        Span(this.text.substring(this.highlightRange.start, this.highlightRange.end))
          .fontColor(this.palette.background)
          .textBackgroundStyle({ color: this.palette.primary, radius: 3 })
        Span(this.text.substring(this.highlightRange.end))
      } else {
        Span(this.text)
      }
    }
    .width('100%')
    .fontSize(this.fontSize)
    .fontColor(this.palette.primary)
    .fontFamily(this.fontFamily.length > 0 ? this.fontFamily : undefined)
    .fontWeight(this.fontWeight, { enableVariableFontWeight: true })
    .lineHeight(this.fontSize * this.lineHeight)
    .textAlign(TextAlign.JUSTIFY)
    .wordBreak(WordBreak.BREAK_WORD)
    .lineBreakStrategy(LineBreakStrategy.GREEDY)
    .draggable(false)
    .copyOption(this.selectionEnabled ? CopyOptions.LocalDevice : CopyOptions.None)
    .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
    .onTextSelectionChange((start: number, end: number): void => {
      this.updateSelection(start, end);
    })
    .onBlur((): void => this.updateSelection(-1, -1))
    }
  }
}
