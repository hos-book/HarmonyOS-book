import { Book } from '../model/Book';
import { ReaderFullTextSearch, ReaderSearchMatch, ReaderSearchProgress } from '../service/text/ReaderFullTextSearch';
import { AppColor } from '../theme/Theme';

class ReaderSearchDataSource implements IDataSource {
  private items: ReaderSearchMatch[] = [];
  private listeners: DataChangeListener[] = [];
  update(items: ReaderSearchMatch[]): void {
    this.items = items.slice();
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
  totalCount(): number { return this.items.length; }
  getData(index: number): ReaderSearchMatch { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((value: DataChangeListener): boolean => value !== listener);
  }
}

@ComponentV2
export struct ReaderFullTextSearchPanel {
  @Param book: Book | null = null;
  @Event read: (index: number) => Promise<string> = async (): Promise<string> => '';
  @Event onSelect: (match: ReaderSearchMatch) => void = (): void => {};
  @Local query: string = '';
  @Local searching: boolean = false;
  @Local searched: boolean = false;
  @Local completed: number = 0;
  @Local failed: number = 0;
  @Local count: number = 0;
  @Local limited: boolean = false;
  private generation: number = 0;
  private source: ReaderSearchDataSource = new ReaderSearchDataSource();
  private scroller: Scroller = new Scroller();

  aboutToDisappear(): void { this.generation++; }

  private reset(): void {
    this.generation++;
    this.searching = false;
    this.searched = false;
    this.completed = 0;
    this.failed = 0;
    this.count = 0;
    this.limited = false;
    this.source.update([]);
  }

  private async search(): Promise<void> {
    this.reset();
    if (!this.query.trim() || this.book === null) return;
    const generation = this.generation;
    this.searching = true;
    this.searched = true;
    await ReaderFullTextSearch.search(this.query, this.book.chapters.length, this.read,
      (): boolean => generation !== this.generation,
      (progress: ReaderSearchProgress): void => {
        if (generation !== this.generation) return;
        this.completed = progress.completed;
        this.failed = progress.failed;
        this.limited = progress.limited;
        if (this.count !== progress.matches.length) {
          this.count = progress.matches.length;
          this.source.update(progress.matches);
        }
      });
    if (generation === this.generation) this.searching = false;
  }

  build() {
    Column({ space: 12 }) {
      Search({ value: this.query, placeholder: $r('app.string.reader_fulltext_placeholder') })
        .maxLength(128)
        .searchButton($r('app.string.reader_fulltext_search'))
        .onChange((value: string): void => { this.query = value; this.reset(); })
        .onSubmit((): void => { this.search(); })
        .id('reader-fulltext-query')
      if (!this.searched) {
        Text($r('app.string.reader_fulltext_hint')).fontSize(13).fontColor($r('sys.color.font_secondary'))
      } else {
        Row({ space: 8 }) {
          if (this.searching) { LoadingProgress().width(20).height(20).color(AppColor.Brand) }
          Text($r('app.string.reader_fulltext_progress', this.completed, this.book?.chapters.length ?? 0, this.count))
            .fontSize(13).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          if (this.searching) {
            Button($r('app.string.reader_fulltext_stop')).fontColor(AppColor.Brand).backgroundColor(Color.Transparent)
              .onClick((): void => { this.generation++; this.searching = false; })
          }
        }.width('100%')
        if (this.failed > 0) {
          Text($r('app.string.reader_fulltext_failed', this.failed)).fontSize(13).fontColor(AppColor.Brand)
        }
        if (this.limited) {
          Text($r('app.string.reader_fulltext_limit', ReaderFullTextSearch.MAX_RESULTS)).fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        if (!this.searching && this.count === 0) {
          Text($r('app.string.reader_fulltext_empty')).fontColor($r('sys.color.font_secondary'))
        }
      }
      List({ space: 8, scroller: this.scroller }) {
        LazyForEach(this.source, (match: ReaderSearchMatch) => {
          ListItem() {
            Column({ space: 6 }) {
              Text(this.book?.chapters[match.chapterIndex]?.title ?? '').fontSize(15)
                .fontColor(AppColor.Brand).maxLines(2)
              Text(match.preview).fontSize(14).fontColor($r('sys.color.font_primary'))
                .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.width('100%').padding(12).alignItems(HorizontalAlign.Start)
              .borderRadius(12).backgroundColor($r('sys.color.comp_background_tertiary'))
              .onClick((): void => { this.generation++; this.searching = false; this.onSelect(match); })
          }
        }, (match: ReaderSearchMatch): string => `${this.book?.chapters[match.chapterIndex]?.id}:${match.offset}`)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    }.width('100%').height('100%').padding({ left: 20, right: 20, bottom: 16 })
  }
}
