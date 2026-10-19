import { FrameCallback } from '@kit.ArkUI';
import { Book } from '../model/Book';
import { ComicPage } from '../service/ComicReaderService';
import { ComicScrollChapter, ComicScrollDataSource, ComicScrollRow } from '../service/ComicScrollDataSource';
import { PreferenceService } from '../service/PreferenceService';
import { AppColor } from '../theme/Theme';
import { ComicPageImage } from './ComicPageImage';

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
  @Param initialPages: ComicPage[] = [];
  @Param pageWidth: number = 360;
  @Param superResolution: boolean = false;
  @Event onToggle: (event: ClickEvent) => void = () => {};
  @Event onPosition: (chapterIndex: number, pageIndex: number, pages: ComicPage[]) => void = () => {};
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

  aboutToAppear(): void { this.disposed = false; this.reset(); }
  aboutToDisappear(): void { this.disposed = true; this.serial++; }

  @Monitor('resetToken')
  onReset(): void { if (!this.disposed) this.reset(); }

  @Monitor('pageWidth')
  onWidthChanged(): void { if (!this.disposed) this.restoreVisible(); }

  private reset(): void {
    this.serial++;
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
    this.restoring = true;
    const ticket = this.serial;
    this.getUIContext().postFrameCallback(new ComicScrollLayoutFrame((): void => {
      if (this.disposed || ticket !== this.serial) return;
      try { this.scroller.scrollToIndex(this.firstVisible, false, ScrollAlign.START); } catch (_error) { }
      this.restoring = false;
      this.reportPosition();
      this.loadNeighbor(true);
    }));
  }

  private async loadNeighbor(forward: boolean, retry: boolean = false): Promise<void> {
    const book = this.book;
    if (!book || this.disposed || this.restoring || this.chapters.length === 0 || this.chapters.length >= 5 ||
      (forward ? this.nextLoading : this.previousLoading) || (!retry && (forward ? this.nextFailed : this.previousFailed))) return;
    const edge = forward ? this.chapters[this.chapters.length - 1] : this.chapters[0];
    const step: number = book.chaptersDescending ? -1 : 1;
    const index = edge.index + (forward ? step : -step);
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
      }
    }
  }

  private reportPosition(): void {
    if (this.restoring || this.disposed) return;
    const row = this.source.getData(this.firstVisible);
    if (row === undefined) return;
    const chapter = this.chapters.find((item: ComicScrollChapter): boolean => item.index === row.chapterIndex);
    if (chapter !== undefined) this.onPosition(row.chapterIndex, row.pageIndex, chapter.pages);
  }

  private visibleChanged(first: number, last: number): void {
    if (this.disposed || this.restoring || this.source.getData(first) === undefined) return;
    this.firstVisible = first;
    this.lastVisible = Math.min(last, this.source.totalCount() - 1);
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
              onToggle: (event: ClickEvent): void => this.onToggle(event) })
          }.width('100%').align(Alignment.Center)
        }, (row: ComicScrollRow): string => `${row.chapterIndex}:${row.page.key}`)
      }.width('100%').height('100%').cachedCount(2).scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None).maintainVisibleContentPosition(true)
        .onScrollIndex((first: number, last: number): void => this.visibleChanged(first, last))
        .onReachEnd((): void => { this.loadNeighbor(true); })
        .onReachStart((): void => { this.loadNeighbor(false); })
        .onScrollStop((): void => { this.reportPosition(); this.trimChapters(); })
      this.loadIndicator(true)
      this.loadIndicator(false)
    }.width('100%').height('100%')
  }
}
