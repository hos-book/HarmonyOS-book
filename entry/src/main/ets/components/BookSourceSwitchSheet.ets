import { Book, Chapter } from '../model/Book';
import { BookSourceService } from '../service/BookSourceService';
import { SourceSwitchSearch, SourceSwitchBookDataSource } from '../service/BookSourceSwitchService';
import { ChapterDataSource } from '../utils/ChapterDataSource';
import { AppColor, AppMaterial, AppSpace } from '../theme/Theme';
import { PreferenceService } from '../service/PreferenceService';
import { PlatformCompat } from '../utils/PlatformCompat';
import { promptAction } from '@kit.ArkUI';

@ComponentV2
export struct BookSourceSwitchSheet {
  @Param book: Book | null = null;
  @Param chapterTitle: string = '';
  @Param chapterIndex: number = 0;
  @Event onSelect: (book: Book, index: number, matched: boolean, oldFavoriteId: string, replace: boolean) => Promise<void> =
    async (_book: Book, _index: number, _matched: boolean, _oldFavoriteId: string, _replace: boolean): Promise<void> => {};
  @Local searching: boolean = true;
  @Local busy: boolean = false;
  @Local count: number = 0;
  @Local keyword: string = '';
  @Local completed: number = 0;
  @Local total: number = 0;
  @Local failed: number = 0;
  @Local selected: Book | null = null;
  @Local matchedIndex: number = -1;
  @Local query: string = '';
  @Local errorText: string = '';
  private search: SourceSwitchSearch = new SourceSwitchSearch();
  private results: SourceSwitchBookDataSource = new SourceSwitchBookDataSource();
  private chapters: ChapterDataSource = new ChapterDataSource();
  private disposed: boolean = false;
  private chapterScroller: Scroller = new Scroller();
  private chapterScrollTimer: number = -1;

  aboutToAppear(): void {
    this.disposed = false;
    this.keyword = SourceSwitchSearch.searchKeyword(this.book?.title ?? '');
    this.findSources();
  }
  aboutToDisappear(): void {
    this.disposed = true;
    this.search.cancelled = true;
    if (this.chapterScrollTimer !== -1) clearTimeout(this.chapterScrollTimer);
  }

  private scrollToSelectedChapter(): void {
    if (this.chapterScrollTimer !== -1) clearTimeout(this.chapterScrollTimer);
    this.chapterScrollTimer = setTimeout((): void => {
      this.chapterScrollTimer = -1;
      if (this.disposed || !this.selected || this.query || this.matchedIndex < 0) return;
      try { this.chapterScroller.scrollToIndex(this.matchedIndex, false, ScrollAlign.CENTER); } catch (_error) { /* sheet closed */ }
    }, 50);
  }

  private async findSources(): Promise<void> {
    if (!this.book || !this.keyword.trim()) { this.searching = false; return; }
    this.search.cancelled = true;
    const task = new SourceSwitchSearch();
    this.search = task;
    this.searching = true;
    this.count = 0;
    this.failed = 0;
    this.completed = 0;
    this.total = 0;
    this.errorText = '';
    this.results.setBooks([]);
    try {
      await task.run(this.book, (books: Book[]): void => {
        if (this.disposed || this.search !== task) return;
        this.results.setBooks(books);
        this.count = books.length;
        this.failed = task.failed;
        this.completed = task.completed;
        this.total = task.total;
      }, this.keyword);
    } catch (error) {
      if (!this.disposed) this.errorText = error instanceof Error ? error.message : String(error);
    } finally {
      if (!this.disposed && this.search === task) this.searching = false;
    }
  }

  private async chooseBook(candidate: Book): Promise<void> {
    if (this.busy || !this.book) return;
    this.search.cancelled = true;
    this.searching = false;
    this.busy = true;
    this.errorText = '';
    try {
      const loaded = candidate.contentType === 'text' || candidate.contentType === 'comic' ? await BookSourceService.loadTextBook(candidate) :
        await BookSourceService.loadAudioBook(candidate, (_book: Book): void => {});
      if (this.disposed) return;
      if (loaded.chapters.length === 0) {
        this.errorText = this.getUIContext().getHostContext()!.resourceManager.getStringSync($r('app.string.source_switch_no_chapters').id);
        return;
      }
      this.selected = loaded;
      this.matchedIndex = SourceSwitchSearch.locateChapter(this.book, this.chapterTitle, this.chapterIndex, loaded);
      this.query = '';
      this.chapters.setChapters(loaded.chapters);
    } catch (error) {
      if (!this.disposed) this.errorText = error instanceof Error ? error.message : String(error);
    } finally { if (!this.disposed) this.busy = false; }
  }

  private async confirmChapter(index: number): Promise<void> {
    if (this.busy || !this.selected) return;
    this.busy = true;
    this.errorText = '';
    const selected = this.selected;
    const original = this.book;
    try {
      const oldFavoriteId = original !== null && original.id !== selected.id &&
        await PreferenceService.isFavorite(original.id) ? original.id : '';
      if (this.disposed) return;
      let replace = false;
      if (oldFavoriteId) {
        const options: promptAction.ShowDialogOptions = {
          title: $r('app.string.source_switch_replace_title'),
          message: $r('app.string.source_switch_replace_message'),
          alignment: DialogAlignment.Center,
          backgroundBlurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
          buttons: [
            { text: $r('app.string.common_cancel'), color: $r('sys.color.font_secondary') },
            { text: $r('app.string.source_switch_replace_confirm'), color: AppColor.Brand }
          ]
        };
        if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.DialogUltraThick;
        try {
          const response = await this.getUIContext().getPromptAction().showDialog(options);
          replace = response.index === 1;
        } catch (_) { return; }
      }
      if (this.disposed) return;
      await this.onSelect(selected, index, original !== null &&
        index === SourceSwitchSearch.matchChapter(original, this.chapterTitle, selected), oldFavoriteId, replace);
    }
    catch (error) {
      if (!this.disposed) this.errorText = error instanceof Error ? error.message : String(error);
    } finally { if (!this.disposed) this.busy = false; }
  }

  build() {
    Column({ space: AppSpace.Md }) {
      Text($r('app.string.source_switch_title')).fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary')).width('100%').textAlign(TextAlign.Start).padding({ right: 36 })
      if (this.selected) {
        Text(this.selected.narrator).fontSize(14).fontColor($r('sys.color.font_secondary'))
        Text($r('app.string.source_switch_chapter_hint')).fontSize(13).fontColor($r('sys.color.font_secondary'))
        if (this.matchedIndex >= 0) {
          Button($r('app.string.source_switch_continue', this.selected.chapters[this.matchedIndex].title))
            .backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand).enabled(!this.busy)
            .onClick((): void => { this.confirmChapter(this.matchedIndex); })
        }
        TextInput({ text: this.query, placeholder: $r('app.string.source_switch_filter') })
          .fontColor($r('sys.color.font_primary')).placeholderColor($r('sys.color.font_tertiary'))
          .onChange((value: string): void => {
            this.query = value;
            this.chapters.setChapters(this.selected?.chapters.filter((chapter: Chapter): boolean =>
              chapter.title.includes(value.trim())) ?? []);
            if (!value.trim()) this.scrollToSelectedChapter();
          })
        List({ scroller: this.chapterScroller }) {
          LazyForEach(this.chapters, (chapter: Chapter): void => {
            ListItem() {
              Text(chapter.title)
                .fontColor(chapter.id === this.selected?.chapters[this.matchedIndex]?.id ? AppColor.Brand : $r('sys.color.font_primary'))
                .fontWeight(chapter.id === this.selected?.chapters[this.matchedIndex]?.id ? FontWeight.Medium : FontWeight.Normal)
                .fontSize(16).width('100%').padding(16)
            }
            .backgroundColor(chapter.id === this.selected?.chapters[this.matchedIndex]?.id ? AppColor.BrandSoft : Color.Transparent)
            .borderRadius(12).enabled(!this.busy).onClick((): void => {
              const index = this.selected?.chapters.findIndex((item: Chapter): boolean => item.id === chapter.id) ?? -1;
              if (index >= 0) this.confirmChapter(index);
            })
          }, (chapter: Chapter): string => chapter.id)
        }.width('100%').layoutWeight(1).onAppear((): void => this.scrollToSelectedChapter())
        Button($r('app.string.source_switch_back')).fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_tertiary')).enabled(!this.busy)
          .onClick((): void => { this.selected = null; this.errorText = ''; })
      } else {
        Search({ value: this.keyword, placeholder: $r('app.string.source_switch_keyword') })
          .fontColor($r('sys.color.font_primary')).placeholderColor($r('sys.color.font_tertiary'))
          .enabled(!this.searching && !this.busy)
          .onChange((value: string): void => { this.keyword = value; })
          .onSubmit((): void => { this.findSources(); })
        Text($r('app.string.source_switch_progress', this.completed, this.total, this.count))
          .fontSize(13).fontColor($r('sys.color.font_secondary'))
        Text($r('app.string.source_switch_hint')).fontSize(13).fontColor($r('sys.color.font_secondary'))
        if (this.count === 0 && !this.searching) {
          Text($r('app.string.source_switch_empty')).fontColor($r('sys.color.font_secondary'))
        }
        if (this.failed > 0) {
          Text($r('app.string.source_switch_failed', this.failed)).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
        List() {
          LazyForEach(this.results, (book: Book): void => {
            ListItem() {
              Row({ space: 12 }) {
                Column({ space: 6 }) {
                  Text(book.narrator).fontColor($r('sys.color.font_primary')).fontSize(16).fontWeight(FontWeight.Medium)
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(book.title + ' · ' + book.author).fontSize(13).fontColor($r('sys.color.font_secondary'))
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (book.latestChapterTitle) {
                  Text($r('app.string.source_latest_chapter', book.latestChapterTitle))
                    .fontSize(12).fontColor($r('sys.color.font_secondary')).maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.End).width('42%')
                }
              }.width('100%').padding(16)
            }.enabled(!this.busy).onClick((): void => { this.chooseBook(book); })
          }, (book: Book): string => book.id)
        }.width('100%').layoutWeight(1)
        Button() {
          Row({ space: 8 }) {
            if (this.searching || this.busy) {
              LoadingProgress().width(18).height(18).color(AppColor.Brand).hitTestBehavior(HitTestMode.None)
            }
            Text(this.busy ? $r('app.string.source_switch_loading_chapters') :
              (this.searching ? $r('app.string.source_switch_stop') : $r('app.string.source_switch_retry')))
              .fontColor($r('sys.color.font_primary')).hitTestBehavior(HitTestMode.None)
          }.justifyContent(FlexAlign.Center).padding({ left: 16, right: 16 })
            .hitTestBehavior(HitTestMode.None)
        }
          .height(40)
          .backgroundColor($r('sys.color.comp_background_tertiary')).enabled(this.searching || !this.busy)
          .onClick((): void => {
            if (this.searching) { this.search.cancelled = true; this.searching = false; }
            else this.findSources();
          })
      }
      if (this.busy && this.selected !== null) {
        LoadingProgress().width(28).height(28).color(AppColor.Brand)
      }
      if (this.errorText) { Text(this.errorText).fontSize(13).fontColor($r('sys.color.font_secondary')) }
    }.width('100%').height('100%').padding(20).alignItems(HorizontalAlign.Start)
  }
}
