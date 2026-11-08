import { ReaderParagraphComment } from '../model/ReaderComment';
import { ReaderCommentLayout, ReaderCommentAnchor } from '../service/text/ReaderCommentLayout';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { SpeechHighlightRange, SpeechTextHighlighter } from '../service/text/SpeechTextHighlighter';
import { ReaderPalette } from '../model/ReaderTheme';
import { OnlineTextPage } from '../service/text/OnlineTextPaginator';
import { ReaderParagraphNodeController } from '../service/text/ReaderParagraphNode';
import { EpubPageStyle } from '../service/text/EpubPageStyle';
import { ReaderAiAction } from '../model/ReaderAi';
import { ReaderSelectionMenu } from '../utils/ReaderSelectionMenu';
import { ReaderSelectionGeometry, ReaderSelectionBounds, ReaderSelectionHandle } from '../service/text/ReaderSelectionGeometry';
import { AppMaterial } from '../theme/Theme';
import { PlatformCompat } from '../utils/PlatformCompat';

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
  @Param selectionRevision: number = 0;
  @Event onSelectionChange: (active: boolean) => void = () => {};
  @Event onReadFrom: (offset: number) => void = () => {};
  @Event onAi: (action: ReaderAiAction, text: string) => void = () => {};
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
            selectionEnabled: this.selectionEnabled && !part.isHeading, selectionRevision: this.selectionRevision,
            onSelectionChange: this.onSelectionChange, onReadFrom: this.onReadFrom, onAi: this.onAi,
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
          selectionRevision: this.selectionRevision,
          onSelectionChange: this.onSelectionChange, onReadFrom: this.onReadFrom, onAi: this.onAi,
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
  private selectionDragX: number = 0;
  private selectionDragY: number = 0;
  private selectionDragAnchor: number = 0;
  @Param text: string = '';
  @Param source: string = '';
  @Param state: TextToSpeechState = new TextToSpeechState();
  @Param sourceStart: number = 0;
  @Param highlightEnabled: boolean = false;
  @Param selectionEnabled: boolean = true;
  @Param selectionRevision: number = 0;
  @Event onSelectionChange: (active: boolean) => void = () => {};
  @Event onReadFrom: (offset: number) => void = () => {};
  @Event onAi: (action: ReaderAiAction, text: string) => void = () => {};
  @Local selecting: boolean = false;
  @Local selectionStart: number = -1;
  @Local selectionEnd: number = -1;
  @Local selectionMenuVisible: boolean = false;
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
  aboutToDisappear(): void {
    if (this.selecting) this.onSelectionChange(false);
    this.paragraphNode.release();
  }

  @Monitor('page', 'selectionEnabled', 'selectionRevision')
  resetSelection(): void {
    this.updateSelection(-1, -1);
  }

  @Computed
  get commentAnchors(): ReaderCommentAnchor[] {
    return ReaderCommentLayout.anchors(this.page, this.source, this.sourceStart, this.comments, this.getUIContext().vp2px(1));
  }

  private updateSelection(start: number, end: number): void {
    const previous = this.selecting;
    this.selectionStart = start;
    this.selectionEnd = end;
    this.selecting = this.selectionEnabled && start >= 0 && end > start;
    if (!this.selecting) this.selectionMenuVisible = false;
    if (previous !== this.selecting) this.onSelectionChange(this.selecting);
  }

  private runSelectionAction(id: TextMenuItemId, start: number, end: number): void {
    if (!this.selectionEnabled || start < 0 || end <= start) return;
    if (id.equals(TextMenuItemId.of(ReaderSelectionMenu.LISTEN))) {
      const offset = this.sourceStart + SpeechTextHighlighter.sourceOffset(this.text, this.source, start);
      this.onReadFrom(offset);
    } else if (id.equals(TextMenuItemId.of(ReaderSelectionMenu.DICTIONARY))) {
      this.onAi(ReaderAiAction.Dictionary, this.text.substring(start, end));
    } else if (id.equals(TextMenuItemId.of(ReaderSelectionMenu.SUMMARIZE))) {
      this.onAi(ReaderAiAction.Summarize, '');
    }
    this.updateSelection(-1, -1);
  }

  private speechSelectionMenu(): EditMenuOptions {
    return {
      onCreateMenu: (_items: TextMenuItem[]): TextMenuItem[] => ReaderSelectionMenu.items(),
      onPrepareMenu: (_items: TextMenuItem[]): TextMenuItem[] => ReaderSelectionMenu.items(),
      onMenuItemClick: (item: TextMenuItem, range: TextRange): boolean => {
        const start = range.start ?? this.selectionStart;
        const end = range.end ?? this.selectionEnd;
        this.runSelectionAction(item.id, start, end);
        return true;
      }
    };
  }

  private beginSelection(event: GestureEvent): void {
    const finger = event.fingerList[0];
    if (!this.selectionEnabled || this.selecting || finger === undefined || !this.text) return;
    const context = this.getUIContext();
    const word = ReaderSelectionGeometry.wordAt(this.page, context.vp2px(finger.localX), context.vp2px(finger.localY));
    this.updateSelection(word.start, word.end);
    this.selectionMenuVisible = this.selecting;
  }

  @Computed
  get selectionBounds(): ReaderSelectionBounds {
    return ReaderSelectionGeometry.bounds(this.page, this.selectionStart, this.selectionEnd);
  }

  private selectionHandle(leading: boolean): ReaderSelectionHandle {
    return leading ? this.selectionBounds.start : this.selectionBounds.end;
  }

  private beginSelectionDrag(leading: boolean): void {
    const handle = this.selectionHandle(leading);
    this.selectionDragX = handle.x;
    this.selectionDragY = (handle.top + handle.bottom) / 2;
    this.selectionDragAnchor = leading ? this.selectionEnd : this.selectionStart;
    this.selectionMenuVisible = false;
  }

  private dragSelection(event: GestureEvent): void {
    if (!this.selecting) return;
    const context = this.getUIContext();
    const offset = ReaderSelectionGeometry.offsetAt(this.page,
      this.selectionDragX + context.vp2px(event.offsetX), this.selectionDragY + context.vp2px(event.offsetY));
    if (offset < 0 || offset === this.selectionDragAnchor) return;
    this.updateSelection(Math.min(offset, this.selectionDragAnchor), Math.max(offset, this.selectionDragAnchor));
  }

  private selectionPopupOptions(): CustomPopupOptions {
    const options: CustomPopupOptions = {
      builder: (): void => this.buildSelectionMenu(), placement: Placement.Top,
      enableArrow: false, autoCancel: false, mask: false, focusable: false,
      targetSpace: 10, radius: 24, popupColor: AppMaterial.SheetBackground,
      onStateChange: (event): void => {
        if (!event.isVisible && this.selectionMenuVisible) this.updateSelection(-1, -1);
      }
    };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    else options.backgroundBlurStyle = AppMaterial.SheetBlur;
    return options;
  }

  @LocalBuilder
  private buildSelectionAction(label: Resource, action: string) {
    Text(label).fontSize(14).fontColor($r('sys.color.font_primary')).maxLines(1)
      .padding({ left: 10, right: 10, top: 12, bottom: 12 })
      .onClick((): void => this.runSelectionAction(TextMenuItemId.of(action), this.selectionStart, this.selectionEnd))
  }

  @LocalBuilder
  private buildSelectionMenu() {
    Row() {
      this.buildSelectionAction($r('app.string.reader_listen_from_paragraph'), ReaderSelectionMenu.LISTEN)
      this.buildSelectionAction($r('app.string.reader_ai_dictionary'), ReaderSelectionMenu.DICTIONARY)
      this.buildSelectionAction($r('app.string.reader_ai_summarize'), ReaderSelectionMenu.SUMMARIZE)
    }.padding({ left: 4, right: 4 }).onTouch((event: TouchEvent): void => event.stopPropagation())
  }

  @LocalBuilder
  private buildSelectionHandle(leading: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      Row().width(1.5)
        .height(this.getUIContext().px2vp(this.selectionHandle(leading).bottom - this.selectionHandle(leading).top))
        .backgroundColor(this.palette.accent).position({ x: 19.25, y: 20 })
      Row().width(10).height(10).borderRadius(5).backgroundColor(this.palette.accent)
        .position({ x: 15, y: leading ? 10 :
          20 + this.getUIContext().px2vp(this.selectionHandle(leading).bottom - this.selectionHandle(leading).top) })
    }
    .width(40).height(40 + this.getUIContext().px2vp(this.selectionHandle(leading).bottom - this.selectionHandle(leading).top))
    .position({ x: this.getUIContext().px2vp(this.selectionHandle(leading).x) - 20,
      y: this.getUIContext().px2vp(this.selectionHandle(leading).top) - 20 })
    .hitTestBehavior(HitTestMode.Block)
    .onTouch((event: TouchEvent): void => event.stopPropagation())
    .priorityGesture(PanGesture({ direction: PanDirection.All, distance: 1 })
      .onActionStart((event: GestureEvent): void => { this.beginSelectionDrag(leading); this.dragSelection(event); })
      .onActionUpdate((event: GestureEvent): void => this.dragSelection(event))
      .onActionEnd((): void => { this.selectionMenuVisible = this.selecting; })
      .onActionCancel((): void => { this.selectionMenuVisible = this.selecting; }))
    .id(leading ? 'reader-selection-start' : 'reader-selection-end')
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
      if (this.selecting && this.selectionBounds.valid) {
        this.buildSelectionHandle(true)
        this.buildSelectionHandle(false)
        Row().width(1).height(1)
          .position({ x: this.getUIContext().px2vp((this.selectionBounds.start.x + this.selectionBounds.end.x) / 2),
            y: this.getUIContext().px2vp(this.selectionBounds.start.top) })
          .hitTestBehavior(HitTestMode.None)
          .bindPopup(this.selectionMenuVisible, this.selectionPopupOptions())
      }
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
