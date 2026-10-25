import { ReaderTapPolicy, ReaderTouchTracker } from '../utils/ReaderTapPolicy';
import { AppColor } from '../theme/Theme';
import { LengthMetrics } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';
import { ReaderPalette } from '../model/ReaderTheme';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { OnlineTextPaginator } from '../service/text/OnlineTextPaginator';
import { OnlineTextScrollChapter, OnlineTextScrollDataSource, OnlineTextScrollRow } from '../service/text/OnlineTextScrollDataSource';
import { ReaderSpeechText } from './ReaderSpeechText';

/** 按真实排版行懒加载的连续正文。只保留当前章附近内容，补章不替换可见正文。 */
@ComponentV2
export struct ReaderContinuousComponent {
  @Param selectionEnabled: boolean = true;
  @Local selectionActive: boolean = false;
  @Event onSelectionChange: (active: boolean) => void = () => {};
  @Event onReadFrom: (chapter: number, offset: number) => void = () => {};
  @Param tapLeftPercent: number = 33;
  @Param tapRightPercent: number = 33;
  @Param tapTopPercent: number = 33;
  @Param tapBottomPercent: number = 33;
  @Param tapRegions: string = ReaderTapPolicy.DEFAULT;
  private tapTracker: ReaderTouchTracker = new ReaderTouchTracker();
  private touchStartedAt: number = 0;
  private touchStartedSelecting: boolean = false;
  private contentHeight: number = 0;
  @Param keyTurnRequest: number = 0;
  @Param revision: number = 0;
  @Param chapterIndex: number = 0;
  @Param content: string = '';
  @Param charOffset: number = 0;
  @Param chapterCount: number = 0;
  @Param chapterStep: number = 1;
  @Param fontFamily: string = '';
  @Param fontWeight: number = 400;
  @Param textAlignment: string = 'justify';
  @Param fontSize: number = 18;
  @Param lineHeight: number = 1.9;
  @Param paragraphSpacing: number = 0;
  @Param palette: ReaderPalette = new ReaderPalette();
  @Param speechState: TextToSpeechState = new TextToSpeechState();
  @Param bookId: string = '';
  @Param followOffset: number = -1;
  @Param topGestureInset: number = 0;
  @Event getContent: (index: number) => Promise<string> = async (): Promise<string> => '';
  @Event getTitle: (index: number) => string = (): string => '';
  @Event getKey: (index: number) => string = (index: number): string => `${index}`;
  @Event onPosition: (chapter: number, offset: number, content: string, persist: boolean) => void = () => {};
  @Event onCenterTap: () => void = () => {};
  @Event onScrollStart: () => void = () => {};
  @Local previousLoading: boolean = false;
  @Local nextLoading: boolean = false;
  @Local previousFailed: boolean = false;
  @Local nextFailed: boolean = false;
  @Local rowHeight: number = 34.2;
  private source: OnlineTextScrollDataSource = new OnlineTextScrollDataSource();
  private scroller: Scroller = new Scroller();
  private chapters: OnlineTextScrollChapter[] = [];
  private contentWidth: number = 0;
  private firstVisible: number = 0;
  private lastVisible: number = 0;
  private serial: number = 0;
  private restoreTimer: number = -1;
  private reflowTimer: number = -1;
  private positionTimer: number = -1;
  private restoring: boolean = false;
  private followingSpeech: boolean = false;
  private restoreTarget: number = -1;
  private disposed: boolean = false;
  private readonly backgroundHandler = (): void => this.reportPosition(true);

  aboutToAppear(): void {
    this.disposed = false;
    emitter.on('app.reader.background', this.backgroundHandler);
  }

  @Monitor('revision', 'fontFamily', 'fontWeight', 'fontSize', 'lineHeight', 'paragraphSpacing', 'textAlignment')
  onRevisionChanged(): void { this.scheduleReset(); }

  private scheduleReset(): void {
    if (this.reflowTimer !== -1) clearTimeout(this.reflowTimer);
    this.reflowTimer = setTimeout((): void => {
      this.reflowTimer = -1;
      this.reset();
    }, 48);
  }

  @Monitor('keyTurnRequest')
  onKeyTurnRequested(): void {
    if (this.disposed || this.restoring || this.contentHeight <= 0) return;
    this.onScrollStart();
    this.scroller.scrollBy(0, (this.keyTurnRequest > 0 ? 1 : -1) * this.contentHeight * 0.85);
  }

  @Monitor('followOffset')
  onFollowChanged(): void {
    if (this.followOffset < 0 || this.restoring) return;
    const target = this.source.findPosition(this.chapterIndex, this.followOffset);
    if (target >= 0 && (target < this.firstVisible || target >= this.lastVisible)) {
      this.followingSpeech = true;
      this.scroller.scrollToIndex(target, false, ScrollAlign.START);
    }
  }

  aboutToDisappear(): void {
    this.reportPosition(true);
    emitter.off('app.reader.background', this.backgroundHandler);
    this.disposed = true;
    if (this.positionTimer !== -1) clearTimeout(this.positionTimer);
    if (this.reflowTimer !== -1) clearTimeout(this.reflowTimer);
    this.serial++;
    if (this.restoreTimer !== -1) clearTimeout(this.restoreTimer);
  }

  private makeChapter(index: number, content: string): OnlineTextScrollChapter {
    const ui = this.getUIContext();
    const fontPx = ui.fp2px(this.fontSize);
    this.rowHeight = ui.px2vp(fontPx) * this.lineHeight;
    // 高度 1px 将测量结果按行输出；列表按像素连续滚动，不做分页吸附。
    const lines = OnlineTextPaginator.paginate(content, ui.vp2px(this.contentWidth), 1, fontPx, this.lineHeight, this.fontFamily, this.fontWeight, this.textAlignment, this.paragraphSpacing);
    return OnlineTextScrollChapter.create(index, this.getKey(index), this.getTitle(index), content, lines);
  }

  private reset(): void {
    if (this.contentWidth <= 0 || this.disposed) return;
    const ticket = ++this.serial;
    if (this.restoreTimer !== -1) clearTimeout(this.restoreTimer);
    this.restoring = true;
    this.previousLoading = false;
    this.nextLoading = false;
    this.previousFailed = false;
    this.nextFailed = false;
    // 字体重排保留已加载的相邻章节，避免清空后再次前插上一章改变恢复锚点。
    const retained = this.chapters.find((item: OnlineTextScrollChapter): boolean =>
      item.index === this.chapterIndex && item.content === this.content);
    const nextChapters: OnlineTextScrollChapter[] = retained !== undefined ?
      this.chapters.map((item: OnlineTextScrollChapter): OnlineTextScrollChapter =>
        this.makeChapter(item.index, item.content)) : [this.makeChapter(this.chapterIndex, this.content)];
    const sameLayout = this.source.totalCount() > 0 && nextChapters.length === this.chapters.length && nextChapters.every(
      (chapter: OnlineTextScrollChapter, index: number): boolean => {
        const previous = this.chapters[index];
        return chapter.index === previous.index && chapter.content === previous.content &&
          chapter.rows[1]?.page.layoutKey === previous.rows[1]?.page.layoutKey;
      });
    this.chapters = nextChapters;
    if (!sameLayout) {
      const rows: OnlineTextScrollRow[] = [];
      for (const chapter of this.chapters) rows.push(...chapter.rows);
      this.source.reset(rows);
    }
    const target = Math.max(0, this.source.findPosition(this.chapterIndex, this.charOffset));
    this.restoreTarget = target;
    this.firstVisible = target;
    this.lastVisible = target;
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      if (this.disposed || ticket !== this.serial) return;
      this.scroller.scrollToIndex(target, false, ScrollAlign.START);
      // 等待列表确认目标行；不让重排过程中旧索引回调覆盖章节/字符位置。
      this.loadNeighbor(true);
    }, 0);
  }

  private chapterLimit(): number {
    // 极短的扉页也必须能够填满视口，否则固定五章会使列表无法继续滚动。
    return Math.max(5, Math.ceil(this.contentHeight / Math.max(1, this.rowHeight * 2)) + 4);
  }

  private async loadNeighbor(forward: boolean): Promise<void> {
    // 后追加不会改变恢复目标索引；恢复期间仅禁止前插。
    if (this.disposed || (this.restoring && !forward) || this.chapters.length === 0 ||
      this.chapters.length >= this.chapterLimit()) return;
    if (forward ? this.nextLoading || this.nextFailed : this.previousLoading || this.previousFailed) return;
    const edge = this.chapters[forward ? this.chapters.length - 1 : 0];
    const index = edge.index + (forward ? this.chapterStep : -this.chapterStep);
    if (index < 0 || index >= this.chapterCount) return;
    const ticket = this.serial;
    if (forward) this.nextLoading = true;
    else this.previousLoading = true;
    try {
      const content = await this.getContent(index);
      if (ticket !== this.serial || this.disposed || this.chapters.length >= this.chapterLimit()) return;
      const chapter = this.makeChapter(index, content);
      if (forward) {
        this.chapters.push(chapter);
        this.source.insert(this.source.totalCount(), chapter.rows);
      } else {
        this.chapters.unshift(chapter);
        this.firstVisible += chapter.rows.length;
        this.lastVisible += chapter.rows.length;
        this.source.insert(0, chapter.rows);
      }
    } catch (_error) {
      if (ticket !== this.serial || this.disposed) return;
      if (forward) this.nextFailed = true;
      else this.previousFailed = true;
    } finally {
      if (ticket === this.serial && !this.disposed) {
        if (forward) this.nextLoading = false;
        else this.previousLoading = false;
        // 内容不足一屏时可能没有新的索引事件，继续补齐视口，仍受章节窗口限制。
        if (forward && this.source.totalCount() < Math.ceil(this.contentHeight / Math.max(1, this.rowHeight)) + 2) {
          this.loadNeighbor(true);
        }
      }
    }
  }

  private reportPosition(persist: boolean): void {
    if (persist && this.positionTimer !== -1) {
      clearTimeout(this.positionTimer);
      this.positionTimer = -1;
    }
    if (this.restoring || this.disposed) return;
    const row = this.source.getData(this.firstVisible);
    if (row === undefined) return;
    const chapter = this.chapters.find((item: OnlineTextScrollChapter): boolean => item.index === row.chapterIndex);
    if (chapter !== undefined) this.onPosition(row.chapterIndex, row.startOffset, chapter.content, persist);
  }

  private visibleChanged(first: number, last: number): void {
    if (first < 0) return;
    if (this.restoring) {
      if (this.restoreTimer !== -1) return;
      const clampedAtEnd = first <= this.restoreTarget && last >= this.restoreTarget &&
        last === this.source.totalCount() - 1;
      if (first !== this.restoreTarget && !clampedAtEnd) return;
      this.restoring = false;
      this.restoreTarget = -1;
      this.firstVisible = first;
      this.lastVisible = last;
      this.loadNeighbor(true);
      return;
    }
    this.firstVisible = first;
    this.lastVisible = last;
    if (this.positionTimer === -1) {
      this.positionTimer = setTimeout((): void => {
        this.positionTimer = -1;
        this.reportPosition(false);
      }, 150);
    }
    this.trimChapters();
    if (this.firstVisible < 24) this.loadNeighbor(false);
    if (this.lastVisible >= this.source.totalCount() - 24) this.loadNeighbor(true);
  }

  private trimChapters(): void {
    // 仅移除可见区之外的章节。增删通知配合 maintainVisibleContentPosition 保持视觉锚点。
    const first = this.source.getData(this.firstVisible);
    const last = this.source.getData(this.lastVisible);
    if (first === undefined || last === undefined) return;
    while (this.chapters.length > 3 &&
      Math.abs(this.chapters[0].index - first.chapterIndex) > 1 &&
      this.chapters[0].index !== last.chapterIndex) {
      const removed = this.chapters.shift();
      if (removed === undefined) break;
      this.firstVisible -= removed.rows.length;
      this.lastVisible -= removed.rows.length;
      this.source.remove(0, removed.rows.length);
    }
    while (this.chapters.length > 3 &&
      Math.abs(this.chapters[this.chapters.length - 1].index - last.chapterIndex) > 1 &&
      this.chapters[this.chapters.length - 1].index !== first.chapterIndex) {
      const removed = this.chapters.pop();
      if (removed === undefined) break;
      this.source.remove(this.source.totalCount() - removed.rows.length, removed.rows.length);
    }
  }

  private retry(forward: boolean): void {
    if (forward) this.nextFailed = false;
    else this.previousFailed = false;
    this.loadNeighbor(forward);
  }

  @Builder
  loadIndicator(forward: boolean): void {
    Row({ space: 6 }) {
      if (forward ? this.nextFailed : this.previousFailed) {
        Button($r('app.string.reader_scroll_retry'))
          .fontSize(12).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
          .onClick((): void => this.retry(forward))
      } else if (forward ? this.nextLoading : this.previousLoading) {
        LoadingProgress().width(20).height(20).color(AppColor.Brand)
      }
    }
    .padding(4)
    .align(forward ? Alignment.BottomEnd : Alignment.TopEnd)
  }

  build() {
    Stack() {
      List({ scroller: this.scroller, space: 0 }) {
        LazyForEach(this.source, (row: OnlineTextScrollRow) => {
          ListItem() {
            if (row.heading) {
              Text(row.text)
                .fontSize(this.fontSize).fontWeight(FontWeight.Medium).fontColor(this.palette.primary)
                .width('100%').height(this.rowHeight * 2).maxLines(2)
            } else {
              ReaderSpeechText({
                selectionEnabled: this.selectionEnabled,
                onSelectionChange: (active: boolean): void => { this.selectionActive = active; this.onSelectionChange(active); },
                onReadFrom: (offset: number): void => this.onReadFrom(row.chapterIndex, offset),
                page: row.page, text: row.text, source: row.source, sourceStart: row.startOffset,
                fontFamily: this.fontFamily, fontWeight: this.fontWeight,
                state: this.speechState, fontSize: this.fontSize, lineHeight: this.lineHeight, palette: this.palette,
                highlightEnabled: this.speechState.bookId === this.bookId && this.speechState.chapterIndex === row.chapterIndex
              })
                .width('100%').height(this.getUIContext().px2vp(row.page.layoutHeight))
                .margin({ bottom: this.getUIContext().px2vp(row.page.trailingSpacing) })
            }
          }
        }, (row: OnlineTextScrollRow): string => row.key)
      }
      .width('100%').height('100%')
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(12) })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .cachedCount(12)
      .maintainVisibleContentPosition(true)
      .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
        if (typeof size.height === 'number') this.contentHeight = size.height;
        if (typeof size.width !== 'number' || size.width <= 0 || Math.abs(this.contentWidth - size.width) < 0.5) return;
        this.contentWidth = size.width;
        this.scheduleReset();
      })
      .onTouchIntercept((event: TouchEvent): HitTestMode => {
        const touch = event.touches[0];
        return touch !== undefined && touch.y < this.topGestureInset ? HitTestMode.None : HitTestMode.Default;
      })
      .onScrollIndex((first: number, last: number): void => this.visibleChanged(first, last))
      .onReachEnd((): void => { this.loadNeighbor(true); })
      .onReachStart((): void => { this.loadNeighbor(false); })
      .onTouch((event: TouchEvent): void => {
        this.tapTracker.update(event);
        if (event.type === TouchType.Down) {
          this.followingSpeech = false;
          this.touchStartedAt = Date.now();
          this.touchStartedSelecting = this.selectionActive;
        }
        // 索引未变化时平台不会重复上报；完成定位后的首次真实触摸解除恢复锁。
        if (event.type === TouchType.Down && this.restoreTimer === -1) {
          this.restoring = false;
          this.restoreTarget = -1;
        }
        if (event.type === TouchType.Up && !this.touchStartedSelecting && !this.selectionActive &&
          Date.now() - this.touchStartedAt < 500 && this.tapTracker.canTap()) {
          const touch = event.changedTouches[0] ?? event.touches[0];
          if (touch !== undefined) {
            const action = ReaderTapPolicy.resolve(this.tapRegions, touch.x,
              touch.y - this.topGestureInset, this.contentWidth, this.contentHeight - this.topGestureInset,
              this.tapLeftPercent, this.tapRightPercent, this.tapTopPercent, this.tapBottomPercent);
            if (action === 1) this.onCenterTap();
            else if (action === 0 || action === 2) {
              this.onScrollStart();
              this.scroller.scrollBy(0, (action === 2 ? 1 : -1) * this.contentHeight * 0.85);
            }
          }
        }
      })
      .onScrollStart((): void => {
        this.tapTracker.cancel();
        if (!this.restoring && !this.followingSpeech) this.onScrollStart();
      })
      .onScrollStop((): void => {
        if (this.followingSpeech) { this.followingSpeech = false; return; }
        this.reportPosition(true);
      })
      this.loadIndicator(false)
      this.loadIndicator(true)
    }
    .width('100%').height('100%')
  }
}
