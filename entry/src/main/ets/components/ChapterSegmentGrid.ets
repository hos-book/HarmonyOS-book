import { ChapterCacheIndicator } from './ChapterCacheIndicator';
import { Book, Chapter } from '../model/Book';
import { ChapterDataSource } from '../utils/ChapterDataSource';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';

class ChapterSegment {
  start: number;
  label: string;
  constructor(start: number, total: number) {
    this.start = start;
    this.label = `${start + 1}-${Math.min(start + 40, total)}`;
  }
}

class ChapterSegmentSource implements IDataSource {
  private values: ChapterSegment[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.values.length; }
  getData(index: number): ChapterSegment { return this.values[index]; }
  update(total: number): void {
    this.values = [];
    for (let start = 0; start < total; start += 40) this.values.push(new ChapterSegment(start, total));
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
}

/** 40 章一段，使用真实章节身份懒加载；搜索覆盖整本书。 */
@ComponentV2
export struct ChapterSegmentGrid {
  @Param book: Book | null = null;
  @Param chapters: Chapter[] = [];
  @Param currentId: string = '';
  @Param readChapterIds: Set<string> = new Set<string>();
  @Param keyword: string = '';
  @Param descending: boolean = false;
  @Param columns: number = 2;
  @Param highlightCurrent: boolean = true;
  @Param topRequest: number = 0;
  @Param bottomRequest: number = 0;

  @Monitor('bottomRequest')
  onBottomRequested(): void {
    if (this.positionTimer !== -1) clearTimeout(this.positionTimer);
    this.positionTimer = -1;
    this.selectedStart = this.descending ? 0 : Math.floor(Math.max(0, this.chapters.length - 1) / 40) * 40;
    this.refresh();
    if (this.chapters.length > 0) this.tabScroller.scrollToIndex(this.selectedStart / 40, false, ScrollAlign.END);
    if (!this.empty) this.listScroller.scrollToIndex(this.source.totalCount() - 1, false, ScrollAlign.END);
  }

  @Monitor('topRequest')
  onTopRequested(): void {
    if (this.positionTimer !== -1) clearTimeout(this.positionTimer);
    this.positionTimer = -1;
    this.selectedStart = this.descending ? Math.floor(Math.max(0, this.chapters.length - 1) / 40) * 40 : 0;
    this.refresh();
    if (this.chapters.length > 0) this.tabScroller.scrollToIndex(this.selectedStart / 40, false, ScrollAlign.START);
    if (!this.empty) this.listScroller.scrollToIndex(0, false, ScrollAlign.START);
  }
  @Event onSelect: (chapter: Chapter) => void = () => {};
  @Event onLongPress: (chapter: Chapter) => void = () => {};
  @Local selectedStart: number = 0;
  @Local empty: boolean = false;
  private segments: ChapterSegmentSource = new ChapterSegmentSource();
  private source: ChapterDataSource = new ChapterDataSource();
  private listScroller: Scroller = new Scroller();
  private tabScroller: Scroller = new Scroller();
  private positionTimer: number = -1;

  aboutToAppear(): void {
    this.locateCurrent();
  }

  @Monitor('currentId')
  onCurrentChanged(): void { this.locateCurrent(); }

  private locateCurrent(): void {
    const index = this.chapters.findIndex((chapter: Chapter): boolean => chapter.id === this.currentId);
    this.selectedStart = Math.floor(Math.max(0, index) / 40) * 40;
    this.refresh();
    if (this.positionTimer !== -1) clearTimeout(this.positionTimer);
    this.positionTimer = setTimeout((): void => {
      this.positionTimer = -1;
      if (this.keyword.trim().length > 0 || index < 0) return;
      this.tabScroller.scrollToIndex(this.selectedStart / 40, false, ScrollAlign.CENTER);
      const count = Math.min(40, this.chapters.length - this.selectedStart);
      const offset = index - this.selectedStart;
      this.listScroller.scrollToIndex(this.descending ? count - 1 - offset : offset, false, ScrollAlign.CENTER);
    }, 100);
  }

  aboutToDisappear(): void {
    if (this.positionTimer !== -1) clearTimeout(this.positionTimer);
  }

  @Monitor('chapters', 'keyword', 'descending')
  onDataChanged(): void { this.locateCurrent(); }

  private refresh(): void {
    this.selectedStart = Math.min(this.selectedStart, Math.floor(Math.max(0, this.chapters.length - 1) / 40) * 40);
    this.segments.update(this.chapters.length);
    const query = this.keyword.trim().toLowerCase();
    const filtered = query.length > 0 ? this.chapters.filter((chapter: Chapter): boolean =>
      chapter.title.toLowerCase().includes(query)) : this.chapters.slice(this.selectedStart, this.selectedStart + 40);
    this.source.setChapters(this.descending ? filtered.reverse() : filtered);
    this.empty = filtered.length === 0;
  }

  build() {
    Column({ space: AppSpace.Sm }) {
      if (this.keyword.trim().length === 0 && this.chapters.length > 0) {
        List({ space: 24, scroller: this.tabScroller }) {
          LazyForEach(this.segments, (segment: ChapterSegment) => {
            ListItem() {
              Column({ space: 7 }) {
                Text(segment.label).fontSize(AppFont.Body)
                  .fontColor(this.selectedStart === segment.start ? AppColor.Brand : $r('sys.color.font_secondary'))
                  .fontWeight(this.selectedStart === segment.start ? FontWeight.Medium : FontWeight.Normal)
                Row().width(26).height(3).borderRadius(2)
                  .backgroundColor(this.selectedStart === segment.start ? AppColor.Brand : Color.Transparent)
              }.padding({ top: 8, bottom: 4 })
              .onClick((): void => {
                this.selectedStart = segment.start;
                this.refresh();
                this.listScroller.scrollToIndex(0, false);
              })
            }
          }, (segment: ChapterSegment): string => segment.start.toString())
        }.listDirection(Axis.Horizontal).height(44).width('100%').scrollBar(BarState.Off)
      }
      if (this.empty) {
        Text($r('app.string.chapter_grid_empty')).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
      } else {
        List({ space: 12, scroller: this.listScroller }) {
          LazyForEach(this.source, (chapter: Chapter) => {
            ListItem() {
              Row({ space: 6 }) {
                Text(chapter.title).layoutWeight(1)
                .fontSize(AppFont.Body).fontColor(this.highlightCurrent && chapter.id === this.currentId ? AppColor.Brand :
                  chapter.id !== this.currentId && this.readChapterIds.has(chapter.id) ?
                    $r('sys.color.font_secondary') : $r('sys.color.font_primary'))
                .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (chapter.id === this.currentId) {
                  SymbolGlyph($r('sys.symbol.scope')).fontSize(16).fontColor([AppColor.Brand])
                }
                ChapterCacheIndicator({ book: this.book, chapter: chapter })
              }
                .width('100%').height(64).padding({ left: 14, right: 14 })
                .backgroundColor(this.highlightCurrent && chapter.id === this.currentId ? AppColor.BrandSoft : $r('sys.color.comp_background_tertiary'))
                .borderRadius(AppRadius.Md)
                .onClick((): void => this.onSelect(chapter))
                .gesture(LongPressGesture({ repeat: false }).onAction((): void => this.onLongPress(chapter)))
            }
          }, (chapter: Chapter): string => chapter.id + ':' + (chapter.originSourceValue || chapter.source.value))
        }.lanes(this.columns, 12).layoutWeight(1).width('100%').scrollBar(BarState.Off).cachedCount(4)
      }
    }.width('100%').height('100%').padding({ left: AppSpace.Lg, right: AppSpace.Lg, bottom: AppSpace.Md })
  }
}
