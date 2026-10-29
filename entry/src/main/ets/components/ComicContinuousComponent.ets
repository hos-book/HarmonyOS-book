import { FrameCallback } from '@kit.ArkUI';
import { Book } from '../model/Book';
import { ComicPage } from '../service/ComicReaderService';
import { ComicScrollChapter, ComicScrollDataSource, ComicScrollRow } from '../service/ComicScrollDataSource';
import { PreferenceService } from '../service/PreferenceService';
import { AppColor } from '../theme/Theme';
import { ComicPageImage } from './ComicPageImage';
import { ReaderAutoScrollService } from '../service/text/ReaderAutoScrollService';

class ComicScrollLayoutFrame extends FrameCallback {
  private callback: () => void;
  constructor(callback: () => void) { super(); this.callback = callback; }
  onIdle(_timeLeftInNano: number): void { this.callback(); }
}

/** 和小说连续阅读一样，在原列表两端接章，不通过整章替换和跳顶来续读。 */
@ComponentV2
export struct ComicContinuousComponent {
  @Param book: Book | null = null;
  @Param resetToken: number = 0;
  @Param initialChapterIndex: number = 0;
  @Param initialPageIndex: number = 0;
  @Param initialFraction: number = 0;
  @Param initialPages: ComicPage[] = [];
  @Param pageWidth: number = 360;
  @Param pageHeight: number = 600;
  @Param viewportTop: number = 0;
  @Param zoomOwner: string = '';
  @Param paged: boolean = false;
  @Param overlap: number = 10;
  @Param superResolution: boolean = false;
  @Param colorization: boolean = false;
  @Param translation: boolean = false;
  @Param translationDirection: string = 'ja-zh';
  @Param colorizationActive: boolean = true;
  @Event onColorError: (message: string) => void = () => {};
  @Param keyTurnRequest: number = 0;
  @Param autoPageRunning: boolean = false;
  @Param autoScrollReady: boolean = false;
  @Param autoScrollSpeed: number = 30;
  private autoScroll: ReaderAutoScrollService = new ReaderAutoScrollService();
  @Event onForwardEnd: () => void = (): void => {};
  @Event onAutoPageDelay: () => void = (): void => {};
  @Event onToggle: (event: ClickEvent) => void = () => {};
  @Event onZoomChange: (owner: string, active: boolean) => void = () => {};
  @Event onPosition: (chapterIndex: number, pageIndex: number, pages: ComicPage[], fraction: number) => void = () => {};
  @Event loadPages: (index: number, preload: boolean) => Promise<ComicPage[]> = async (): Promise<ComicPage[]> => [];
  @Local nextLoading: boolean = false;
  @Local previousLoading: boolean = false;
  @Local nextFailed: boolean = false;
  @Local previousFailed: boolean = false;
  private source: ComicScrollDataSource = new ComicScrollDataSource();
  private chapters: ComicScrollChapter[] = [];
  private scroller: Scroller = new Scroller();
  private firstVisible: number = 0;
  private lastVisible: number = 0;
  private serial: number = 0;
  private disposed: boolean = false;
  private restoring: boolean = true;
  private keyTurning: boolean = false;
  private reportedChapter: number = -1;
  private reportedPage: number = -1;
  private anchorFraction: number = 0;
  private reportedFraction: number = -1;
  private awaitingImage: boolean = false;
  private imageReady: Map<string, boolean> = new Map();
  private restoreSerial: number = 0;

  aboutToAppear(): void { this.disposed = false; this.reset(); this.syncAutoScroll(); }
  aboutToDisappear(): void { this.autoScroll.stop(); this.reportPosition(); this.disposed = true; this.serial++; }

  @Monitor('autoScrollReady')
  private syncAutoScroll(): void {
    this.autoScroll.stop();
    if (!this.autoScrollReady || this.disposed) { this.reportPosition(); return; }
    this.autoScroll.start(this.getUIContext(), (): void => this.advanceAutoScroll());
  }

  private advanceAutoScroll(): void {
    if (!this.autoScrollReady || this.disposed || this.restoring || this.awaitingImage || this.paged || this.zoomOwner.length > 0) {
      this.autoScroll.pause();
      return;
    }
    const row = this.source.getData(this.firstVisible);
    const ready = row !== undefined ? this.imageReady.get(`${row.chapterIndex}:${row.page.key}`) : undefined;
    if (ready !== true) {
      this.autoScroll.pause();
      if (ready === false) this.onForwardEnd();
      return;
    }
    if (this.scroller.isAtEnd()) {
      this.autoScroll.pause();
      if (this.nextFailed || this.chapters[this.chapters.length - 1]?.index === (this.book?.chapters.length ?? 0) - 1) {
        this.onForwardEnd();
      } else this.loadNeighbor(true);
      return;
    }
    this.autoScroll.move(this.scroller, this.autoScrollSpeed);
    this.reportPosition();
  }

  @Monitor('resetToken')
  onReset(): void { if (!this.disposed) this.reset(); }

  @Monitor('pageWidth', 'pageHeight')
  onWidthChanged(): void { if (!this.disposed) this.restoreVisible(); }

  @Monitor('keyTurnRequest')
  private onKeyTurnRequest(): void { this.turnFromKey(this.keyTurnRequest > 0).catch((): void => {}); }

  private async turnFromKey(forward: boolean): Promise<void> {
    if (this.disposed || this.restoring || this.keyTurning || this.zoomOwner.length > 0 || this.source.totalCount() === 0) return;
    if (this.autoPageRunning) {
      const row = this.source.getData(this.firstVisible);
      const ready = row !== undefined ? this.imageReady.get(`${row.chapterIndex}:${row.page.key}`) : undefined;
      if (ready === false) this.onForwardEnd();
      if (ready !== true) return;
    }
    // 用户主动翻页后，不再等待先前进度对应的图片回调。
    this.awaitingImage = false;
    this.keyTurning = true;
    const ticket = this.serial;
    const automatic = this.autoPageRunning;
    try {
      const atEdge = forward ? this.scroller.isAtEnd() : this.scroller.currentOffset().yOffset <= 0;
      if (forward && atEdge && (this.nextFailed ||
        this.chapters[this.chapters.length - 1]?.index === (this.book?.chapters.length ?? 0) - 1)) {
        this.onForwardEnd();
        return;
      }
      if (atEdge) await this.loadNeighbor(forward);
      if (this.disposed || this.restoring || ticket !== this.serial || (automatic && !this.autoPageRunning)) return;
      if (forward && this.nextFailed && atEdge) { this.onForwardEnd(); return; }
      // 一屏一翻，长图不会因跳到下一张而漏读；沿用列表的边界续章。
      if (atEdge) {
        this.getUIContext().postFrameCallback(new ComicScrollLayoutFrame((): void => {
          if (this.disposed || this.restoring || ticket !== this.serial || (automatic && !this.autoPageRunning)) return;
          try { this.advanceViewport(forward); } catch (_error) { }
        }));
      } else {
        this.advanceViewport(forward);
      }
    } finally { this.keyTurning = false; }
  }

  private advanceViewport(forward: boolean): void {
    if (this.zoomOwner.length > 0) return;
    if (this.paged) {
      // 拼接按屏即时翻页，保留一段上下文；不对长图做破坏性裁剪或合成大位图。
      const distance = Math.max(1, this.pageHeight * (1 - Math.max(0, Math.min(30, this.overlap)) / 100));
      this.scroller.scrollBy(0, forward ? distance : -distance);
    } else {
      this.scroller.scrollPage({ next: forward, animation: true });
    }
  }

  private reset(): void {
    this.autoScroll.pause();
    this.serial++;
    this.reportedChapter = -1;
    this.reportedPage = -1;
    this.reportedFraction = -1;
    this.anchorFraction = Math.max(0, Math.min(1, this.initialFraction));
    this.awaitingImage = this.anchorFraction > 0;
    this.restoring = true;
    this.nextLoading = false;
    this.previousLoading = false;
    this.nextFailed = false;
    this.previousFailed = false;
    const chapter = ComicScrollChapter.create(this.initialChapterIndex, this.initialPages);
    this.chapters = [chapter];
    this.firstVisible = Math.max(0, Math.min(this.initialPageIndex, chapter.rows.length - 1));
    this.lastVisible = this.firstVisible;
    this.source.reset(chapter.rows);
    this.restoreVisible();
  }

  private restoreVisible(): void {
    this.autoScroll.pause();
    this.restoring = true;
    const ticket = this.serial;
    const restoreTicket = ++this.restoreSerial;
    this.getUIContext().postFrameCallback(new ComicScrollLayoutFrame((): void => {
      if (this.disposed || ticket !== this.serial || restoreTicket !== this.restoreSerial) return;
      try { this.scroller.scrollToIndex(this.firstVisible, false, ScrollAlign.START); } catch (_error) { }
      this.getUIContext().postFrameCallback(new ComicScrollLayoutFrame((): void => {
        if (this.disposed || ticket !== this.serial || restoreTicket !== this.restoreSerial) return;
        const row = this.source.getData(this.firstVisible);
        this.awaitingImage = this.anchorFraction > 0 && (row === undefined || row.page.width <= 0 || row.page.height <= 0);
        if (!this.awaitingImage && this.anchorFraction > 0) {
          try {
            const rect = this.scroller.getItemRect(this.firstVisible);
            this.scroller.scrollBy(0, rect.y + rect.height * this.anchorFraction);
          } catch (_error) { }
        }
        // scrollBy 在下一帧应用；落位前不能把旧布局的 0 偏移写回进度。
        this.getUIContext().postFrameCallback(new ComicScrollLayoutFrame((): void => {
          if (this.disposed || ticket !== this.serial || restoreTicket !== this.restoreSerial) return;
          this.restoring = false;
          this.reportPosition();
          this.loadNeighbor(true);
        }));
      }));
    }));
  }

  private imageGeometryReady(row: ComicScrollRow): void {
    if (this.source.getData(this.firstVisible) === row) this.onAutoPageDelay();
    if (this.awaitingImage && this.source.getData(this.firstVisible) === row && !this.disposed) this.restoreVisible();
  }

  private async loadNeighbor(forward: boolean, retry: boolean = false): Promise<void> {
    const book = this.book;
    if (!book || this.disposed || this.restoring || this.chapters.length === 0 || this.chapters.length >= 5 ||
      (forward ? this.nextLoading : this.previousLoading) || (!retry && (forward ? this.nextFailed : this.previousFailed))) return;
    const edge = forward ? this.chapters[this.chapters.length - 1] : this.chapters[0];
    const index = edge.index + (forward ? 1 : -1);
    if (index < 0 || index >= book.chapters.length) return;
    const ticket = this.serial;
    if (forward) { this.nextLoading = true; this.nextFailed = false; }
    else { this.previousLoading = true; this.previousFailed = false; }
    try {
      // 关闭预缓存时仍可在真正读到边界后接章。
      const preload = forward ? !this.scroller.isAtEnd() : this.scroller.currentOffset().yOffset > 0;
      if (preload && await PreferenceService.getPreloadChapters() === 0) return;
      if (this.disposed || ticket !== this.serial) return;
      const pages = await this.loadPages(index, preload);
      if (this.disposed || ticket !== this.serial) return;
      if (pages.length === 0) throw new Error('No comic images');
      if (this.chapters.some((item: ComicScrollChapter): boolean => item.index === index)) return;
      const chapter = ComicScrollChapter.create(index, pages);
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
        this.onAutoPageDelay();
      }
    }
  }

  private reportPosition(): void {
    if (this.restoring || this.disposed || this.awaitingImage) return;
    try {
      // 章尾不足一屏时 List 会向前夹紧，实际首图可能早于请求恢复的图片。
      const index = this.scroller.getItemIndex(this.pageWidth / 2, 1);
      if (index >= 0 && index < this.source.totalCount()) this.firstVisible = index;
    } catch (_error) { }
    const row = this.source.getData(this.firstVisible);
    if (row === undefined) return;
    let fraction = 0;
    try {
      const rect = this.scroller.getItemRect(this.firstVisible);
      if (rect.height > 0) fraction = Math.max(0, Math.min(1, -rect.y / rect.height));
    } catch (_error) { }
    fraction = Math.round(fraction * 10000) / 10000;
    this.anchorFraction = fraction;
    if (row.chapterIndex === this.reportedChapter && row.pageIndex === this.reportedPage && fraction === this.reportedFraction) return;
    const chapter = this.chapters.find((item: ComicScrollChapter): boolean => item.index === row.chapterIndex);
    if (chapter !== undefined) {
      this.reportedChapter = row.chapterIndex;
      this.reportedPage = row.pageIndex;
      this.reportedFraction = fraction;
      this.onPosition(row.chapterIndex, row.pageIndex, chapter.pages, fraction);
    }
  }

  private visibleChanged(first: number, last: number): void {
    if (this.disposed || this.restoring || this.awaitingImage || this.source.getData(first) === undefined) return;
    this.firstVisible = first;
    this.lastVisible = Math.min(last, this.source.totalCount() - 1);
    const row = this.source.getData(first);
    if (row !== undefined && this.imageReady.get(`${row.chapterIndex}:${row.page.key}`) !== true) this.autoScroll.pause();
    this.reportPosition();
    this.trimChapters();
    if (this.firstVisible < 3) this.loadNeighbor(false);
    if (this.lastVisible >= this.source.totalCount() - 4) this.loadNeighbor(true);
  }

  private trimChapters(): void {
    const first = this.source.getData(this.firstVisible);
    const last = this.source.getData(this.lastVisible);
    if (first === undefined || last === undefined) return;
    // 保留当前章与相邻章，只删除屏幕外的数据，List 保持原可见图片的像素锚点。
    while (this.chapters.length > 3 && Math.abs(this.chapters[0].index - first.chapterIndex) > 1 &&
      this.chapters[0].index !== last.chapterIndex) {
      const removed = this.chapters.shift();
      if (removed === undefined) break;
      for (const row of removed.rows) this.imageReady.delete(`${row.chapterIndex}:${row.page.key}`);
      this.firstVisible -= removed.rows.length;
      this.lastVisible -= removed.rows.length;
      this.source.remove(0, removed.rows.length);
    }
    while (this.chapters.length > 3 &&
      Math.abs(this.chapters[this.chapters.length - 1].index - last.chapterIndex) > 1 &&
      this.chapters[this.chapters.length - 1].index !== first.chapterIndex) {
      const removed = this.chapters.pop();
      if (removed === undefined) break;
      for (const row of removed.rows) this.imageReady.delete(`${row.chapterIndex}:${row.page.key}`);
      this.source.remove(this.source.totalCount() - removed.rows.length, removed.rows.length);
    }
  }

  @Builder
  loadIndicator(forward: boolean): void {
    Stack({ alignContent: forward ? Alignment.BottomEnd : Alignment.TopEnd }) {
    Row({ space: 6 }) {
      if (forward ? this.nextFailed : this.previousFailed) {
        Button($r('app.string.comic_retry')).fontSize(12).fontColor(Color.White).backgroundColor(AppColor.Brand)
          .onClick((): void => { this.loadNeighbor(forward, true); })
      } else if (forward ? this.nextLoading : this.previousLoading) {
        LoadingProgress().width(20).height(20).color(AppColor.Brand)
      }
    }.padding(8)
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
  }

  build() {
    Stack() {
      List({ scroller: this.scroller, space: 0, initialIndex: this.initialPageIndex }) {
        LazyForEach(this.source, (row: ComicScrollRow) => {
          ListItem() {
            ComicPageImage({ page: row.page, pageWidth: this.pageWidth, superResolution: this.superResolution,
              pageHeight: this.pageHeight, viewportTop: this.viewportTop, zoomOwner: this.zoomOwner,
              colorization: this.colorization, colorizationActive: this.colorizationActive,
              translation: this.translation, translationDirection: this.translationDirection,
              onColorError: (message: string): void => this.onColorError(message),
              onZoomChange: (owner: string, active: boolean): void => {
                if (active) this.autoScroll.pause();
                this.onZoomChange(owner, active);
              },
              onGeometryReady: (): void => this.imageGeometryReady(row),
              onAutoPageDelay: (): void => {
                this.imageReady.set(`${row.chapterIndex}:${row.page.key}`, true);
                if (this.source.getData(this.firstVisible) === row) this.onAutoPageDelay();
              },
              onAutoPageFailure: (): void => {
                this.imageReady.set(`${row.chapterIndex}:${row.page.key}`, false);
                if (this.source.getData(this.firstVisible) === row) {
                  this.autoScroll.pause();
                  this.onForwardEnd();
                }
              },
              onToggle: (event: ClickEvent): void => this.onToggle(event) })
          }.width('100%').align(Alignment.Center)
        }, (row: ComicScrollRow): string => `${row.chapterIndex}:${row.page.key}`)
      }.width('100%').height('100%').cachedCount(2).scrollBar(BarState.Off)
        .enableScrollInteraction(!this.paged && this.zoomOwner.length === 0)
        .edgeEffect(EdgeEffect.None).maintainVisibleContentPosition(true)
        .onScrollIndex((first: number, last: number): void => this.visibleChanged(first, last))
        .onDidScroll(this.autoScrollReady ? undefined : (): void => this.reportPosition())
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Down) this.autoScroll.setTouching(true);
          else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.autoScroll.setTouching(false);
          if (event.type === TouchType.Move && !this.restoring && !this.paged && this.zoomOwner.length === 0) this.awaitingImage = false;
        })
        .onReachEnd((): void => { this.loadNeighbor(true); })
        .onReachStart((): void => { this.loadNeighbor(false); })
        .onScrollStop((): void => {
          if (!this.autoScrollReady) { this.reportPosition(); this.trimChapters(); this.onAutoPageDelay(); }
        })
      this.loadIndicator(true)
      this.loadIndicator(false)
    }.width('100%').height('100%')
  }
}
