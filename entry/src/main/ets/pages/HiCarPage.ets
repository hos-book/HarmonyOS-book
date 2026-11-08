import { ColorMetrics, LengthMetrics } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';
import { CoverImage } from '../components/CoverImage';
import { Book, Chapter } from '../model/Book';
import { HiCarLibrary, HiCarState, HiCarTab } from '../model/HiCar';
import { PlayerState } from '../model/PlayerState';
import { AudioService } from '../service/AudioService';
import { EVT_DOWNLOAD_UPDATED } from '../service/DownloadService';
import { HiCarService } from '../service/HiCarService';
import { EVT_FAVORITES_CHANGED } from '../service/PreferenceService';
import { LIBRARY_SYNC_CHANGED } from '../service/sync/LibrarySyncModel';
import { AppColor } from '../theme/Theme';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { BookDataSource } from '../utils/BookDataSource';
import { ChapterDataSource } from '../utils/ChapterDataSource';
import { WindowUtils } from '../utils/WindowUtils';

const CAR_BACKGROUND: string = '#10151D';
const CAR_SURFACE: string = '#1B2430';
const CAR_TEXT: string = '#F4F7FB';
const CAR_SECONDARY: string = '#B9C4D3';
const CAR_FOCUS: FocusBoxStyle = { strokeColor: ColorMetrics.numeric(0xFFF4F7FB),
  strokeWidth: LengthMetrics.vp(3), margin: LengthMetrics.vp(-3) };
const CAR_SPEEDS: number[] = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3];

@ComponentV2
export struct HiCarPage {
  @Event onExit: () => void = (): void => {};
  @Event onBackHandlerChange: (handler: (() => boolean) | undefined) => void = (): void => {};
  @Local player: PlayerState = HiCarService.instance.player();
  @Local car: HiCarState = HiCarService.instance.state;
  @Local tab: HiCarTab = HiCarTab.Recent;
  @Local library: HiCarLibrary = new HiCarLibrary();
  @Local selectedBook: Book | null = null;
  @Local loading: boolean = true;
  @Local loadFailed: boolean = false;
  @Local opening: boolean = false;
  @Local actionBusy: boolean = false;
  @Local playerVisible: boolean = false;
  @Local chapterStartIndex: number = 0;
  @Local bookCount: number = 0;
  @Local widthVp: number = 0;
  @Local heightVp: number = 0;
  @Local safeTop: number = 0;
  @Local safeBottom: number = 0;
  @Local safeLeft: number = 0;
  @Local safeRight: number = 0;
  private books: BookDataSource = new BookDataSource();
  private chapters: ChapterDataSource = new ChapterDataSource();
  private bookScroller: Scroller = new Scroller();
  private chapterScroller: Scroller = new Scroller();
  private alive: boolean = false;
  private loadSerial: number = 0;
  private openSerial: number = 0;
  private refreshTimer: number = -1;
  private readonly refreshListener = (): void => {
    if (!this.alive || this.refreshTimer >= 0) return;
    this.refreshTimer = setTimeout((): void => {
      this.refreshTimer = -1;
      this.reload(false);
    }, 1000);
  };
  private readonly safeChanged = (top: number, bottom: number): void => {
    this.safeTop = top;
    this.safeBottom = bottom;
    this.safeLeft = WindowUtils.getLeftSafeVp();
    this.safeRight = WindowUtils.getRightSafeVp();
  };

  aboutToAppear(): void {
    this.alive = true;
    this.playerVisible = !!this.player.currentBook;
    const insets = WindowUtils.getSafeAreaInsets();
    this.safeChanged(insets.top, insets.bottom);
    WindowUtils.addSafeAreaListener(this.safeChanged);
    WindowUtils.setReaderActive(false);
    WindowUtils.setStatusBarLight(true);
    this.onBackHandlerChange((): boolean => { this.back(); return true; });
    emitter.on(EVT_FAVORITES_CHANGED, this.refreshListener);
    emitter.on(EVT_DOWNLOAD_UPDATED, this.refreshListener);
    emitter.on(LIBRARY_SYNC_CHANGED, this.refreshListener);
    this.reload(true);
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.loadSerial++;
    this.openSerial++;
    if (this.refreshTimer >= 0) clearTimeout(this.refreshTimer);
    this.refreshTimer = -1;
    emitter.off(EVT_FAVORITES_CHANGED, this.refreshListener);
    emitter.off(EVT_DOWNLOAD_UPDATED, this.refreshListener);
    emitter.off(LIBRARY_SYNC_CHANGED, this.refreshListener);
    WindowUtils.removeSafeAreaListener(this.safeChanged);
    WindowUtils.setStatusBarLight(false);
    this.onBackHandlerChange(undefined);
  }

  private async reload(showLoading: boolean): Promise<void> {
    if (!this.alive) return;
    const serial = ++this.loadSerial;
    if (showLoading) this.loading = true;
    try {
      const library = await HiCarService.instance.loadLibrary();
      if (!this.alive || serial !== this.loadSerial) return;
      this.library = library;
      this.loadFailed = false;
      this.updateBooks();
    } catch (error) {
      if (!this.alive || serial !== this.loadSerial) return;
      this.loadFailed = true;
      console.warn('[HiCarPage] library failed: ' + String(error));
    } finally {
      if (this.alive && serial === this.loadSerial) this.loading = false;
    }
  }

  private updateBooks(): void {
    const books = this.library.books(this.tab);
    this.books.updateBooks(books);
    this.bookCount = books.length;
  }

  private chooseTab(tab: HiCarTab): void {
    this.openSerial++;
    this.opening = false;
    this.selectedBook = null;
    this.chapters.setChapters([]);
    this.tab = tab;
    this.updateBooks();
    this.bookScroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private back(): void {
    if (!this.usesColumns() && this.playerVisible) {
      this.playerVisible = false;
      return;
    }
    this.openSerial++;
    this.opening = false;
    if (this.selectedBook) {
      this.selectedBook = null;
      this.chapters.setChapters([]);
    } else this.onExit();
  }

  private async openBook(book: Book): Promise<void> {
    const serial = ++this.openSerial;
    this.opening = true;
    try {
      const opened = await HiCarService.instance.openBook(book);
      if (!this.alive || serial !== this.openSerial) return;
      const position = await HiCarService.instance.chapterPosition(opened);
      if (!this.alive || serial !== this.openSerial) return;
      this.chapterStartIndex = position;
      this.selectedBook = opened;
      this.chapters.setChapters(opened.chapters);
    } catch (error) {
      if (this.alive && serial === this.openSerial) this.showFailure(String(error));
    } finally {
      if (this.alive && serial === this.openSerial) this.opening = false;
    }
  }

  private showFailure(detail: string): void {
    console.warn('[HiCarPage] playback action failed: ' + detail);
    this.getUIContext().getPromptAction().showToast({ message: $r('app.string.hicar_action_failed') });
  }

  private async runAction(action: () => Promise<void>): Promise<void> {
    if (this.actionBusy) return;
    this.actionBusy = true;
    try { await action(); }
    catch (error) { if (this.alive) this.showFailure(String(error)); }
    finally { if (this.alive) this.actionBusy = false; }
  }

  private resumeSelected(): void {
    const book = this.selectedBook;
    const serial = this.openSerial;
    if (book) this.runAction(async (): Promise<void> => {
      await HiCarService.instance.resume(book, (): boolean => this.alive && serial === this.openSerial);
      if (this.alive && serial === this.openSerial) this.playerVisible = true;
    });
  }

  private selectChapter(chapter: Chapter): void {
    const book = this.selectedBook;
    const serial = this.openSerial;
    if (!book) return;
    this.runAction(async (): Promise<void> => {
      await AudioService.getInstance().whenReady(5000);
      if (this.alive && serial === this.openSerial) {
        await AudioService.getInstance().playChapterFromSavedProgress(book, chapter);
        if (this.alive && serial === this.openSerial) this.playerVisible = true;
      }
    });
  }

  private togglePlayback(): void {
    if (this.player.isPlaying || this.player.isLoading) AudioService.getInstance().pause();
    else this.runAction((): Promise<void> => AudioService.getInstance().play());
  }

  private changeSpeed(): void {
    const next = CAR_SPEEDS.find((speed: number): boolean => speed > this.player.speed + 0.01);
    AudioService.getInstance().setSpeed(next ?? CAR_SPEEDS[0]);
  }

  private timeLabel(milliseconds: number): string {
    const seconds = Math.max(0, Math.floor(Number.isFinite(milliseconds) ? milliseconds / 1000 : 0));
    const minutes = Math.floor(seconds / 60);
    return `${minutes}:${(seconds % 60).toString().padStart(2, '0')}`;
  }

  private tabLabel(tab: HiCarTab): Resource {
    if (tab === HiCarTab.Shelf) return $r('app.string.hicar_shelf');
    if (tab === HiCarTab.Downloaded) return $r('app.string.hicar_downloaded');
    return $r('app.string.hicar_recent');
  }

  private usesColumns(): boolean {
    return AdaptiveLayout.playerUsesColumns(this.widthVp, this.heightVp);
  }

  private isCurrentChapter(chapter: Chapter): boolean {
    return this.player.currentBook?.id === this.selectedBook?.id && this.player.currentChapter?.id === chapter.id;
  }

  private locateChapter(): void {
    const book = this.selectedBook;
    if (!book) return;
    const current = this.player.currentBook?.id === book.id ?
      book.chapters.findIndex((chapter: Chapter): boolean => chapter.id === this.player.currentChapter?.id) : -1;
    this.chapterScroller.scrollToIndex(current >= 0 ? current : this.chapterStartIndex, false, ScrollAlign.CENTER);
  }

  private showCurrentChapters(): void {
    const book = this.player.currentBook;
    if (!book) return;
    this.playerVisible = false;
    this.openBook(book);
  }

  private emptyHint(): Resource {
    if (this.loadFailed) return $r('app.string.hicar_retry_hint');
    if (this.tab === HiCarTab.Downloaded) return $r('app.string.hicar_downloaded_hint');
    if (this.tab === HiCarTab.Shelf) return $r('app.string.hicar_shelf_hint');
    return $r('app.string.hicar_recent_hint');
  }

  @Builder
  private header() {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([CAR_TEXT])
      }.width(52).height(52).borderRadius(14).backgroundColor(CAR_SURFACE)
        .focusBox(CAR_FOCUS)
        .accessibilityText($r('app.string.hicar_back')).onClick((): void => this.back()).id('hicar-back')
      Column({ space: 3 }) {
        Text($r('app.string.hicar_title')).fontSize(24).fontWeight(FontWeight.Bold).fontColor(CAR_TEXT)
        Text(this.car.connected ? $r('app.string.hicar_connected') : $r('app.string.hicar_phone_mode'))
          .fontSize(14).fontColor(CAR_SECONDARY)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(24).fontColor([CAR_TEXT])
      }.width(52).height(52).borderRadius(14).backgroundColor(CAR_SURFACE)
        .focusBox(CAR_FOCUS)
        .accessibilityText($r('app.string.hicar_refresh')).onClick((): void => {
          HiCarService.instance.refresh();
          this.reload(true);
        })
        .enabled(!this.loading).id('hicar-refresh')
    }.width('100%').height(60)
  }

  @Builder
  private libraryPanel() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        ForEach([HiCarTab.Recent, HiCarTab.Shelf, HiCarTab.Downloaded], (tab: HiCarTab) => {
          Button(this.tabLabel(tab), { type: ButtonType.Normal })
            .layoutWeight(1).height(50).fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor(this.tab === tab ? AppColor.OnBrand : CAR_TEXT)
            .backgroundColor(this.tab === tab ? AppColor.Brand : CAR_SURFACE).borderRadius(12)
            .focusBox(CAR_FOCUS)
            .onClick((): void => this.chooseTab(tab)).id(`hicar-tab-${tab}`)
        }, (tab: HiCarTab): string => String(tab))
      }.width('100%')
      if (this.opening || this.loading) {
        Column({ space: 12 }) {
          LoadingProgress().color(AppColor.Brand).width(40).height(40)
          Text($r('app.string.hicar_loading')).fontSize(18).fontColor(CAR_SECONDARY)
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.selectedBook) {
        Row({ space: 8 }) {
          Text(this.selectedBook.title).fontSize(20).fontColor(CAR_TEXT).fontWeight(FontWeight.Medium)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.scope')).fontSize(22).fontColor([CAR_TEXT])
          }.width(48).height(48).borderRadius(12).backgroundColor(CAR_SURFACE)
            .focusBox(CAR_FOCUS)
            .onClick((): void => this.locateChapter()).accessibilityText($r('app.string.hicar_locate_chapter'))
            .id('hicar-locate-chapter')
          Button($r('app.string.hicar_resume'), { type: ButtonType.Normal })
            .fontSize(18).height(48).borderRadius(12).backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
            .focusBox(CAR_FOCUS)
            .enabled(!this.actionBusy).onClick((): void => this.resumeSelected()).id('hicar-resume-book')
        }.width('100%')
        List({ space: 6, scroller: this.chapterScroller, initialIndex: this.chapterStartIndex }) {
          LazyForEach(this.chapters, (chapter: Chapter) => {
            ListItem() {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 10 }) {
                  Text(String(chapter.index)).fontSize(16).fontColor(CAR_SECONDARY).width(42)
                  Text(chapter.title).fontSize(20).fontColor(CAR_TEXT).maxLines(2)
                    .fontWeight(this.isCurrentChapter(chapter) ? FontWeight.Bold : FontWeight.Regular)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  if (this.isCurrentChapter(chapter)) {
                    SymbolGlyph($r('sys.symbol.speaker_wave_2_fill')).fontSize(23).fontColor([AppColor.Brand])
                  }
                }.width('100%').padding(12)
              }.width('100%').constraintSize({ minHeight: 68 }).backgroundColor(CAR_SURFACE)
                .border({ width: this.isCurrentChapter(chapter) ? 2 : 0, color: AppColor.Brand })
                .borderRadius(12)
                .focusBox(CAR_FOCUS)
                .enabled(!this.actionBusy).onClick((): void => this.selectChapter(chapter))
            }
          }, (chapter: Chapter): string => `${this.selectedBook?.id ?? ''}:${chapter.id}`)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).cachedCount(4)
      } else if (this.loadFailed || this.bookCount === 0) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.bookshelf')).fontSize(42).fontColor([CAR_SECONDARY])
          Text(this.loadFailed ? $r('app.string.hicar_load_failed') : $r('app.string.hicar_empty'))
            .fontSize(21).fontColor(CAR_TEXT).textAlign(TextAlign.Center)
          Text(this.emptyHint()).fontSize(16).fontColor(CAR_SECONDARY)
            .textAlign(TextAlign.Center).maxLines(3)
          if (this.loadFailed) {
            Button($r('app.string.common_retry')).backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
              .height(48).onClick((): void => { this.reload(true); })
              .focusBox(CAR_FOCUS)
          }
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(16)
      } else {
        List({ space: 8, scroller: this.bookScroller }) {
          LazyForEach(this.books, (book: Book) => {
            ListItem() {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 14 }) {
                  CoverImage({ url: book.cover, title: book.title, author: book.author,
                    localPlaceholder: !book.cover, imgWidth: 46, imgHeight: 62, useFixedHeight: true,
                    radius: 8, themedDecoration: false })
                  Column({ space: 5 }) {
                    Text(book.title).fontSize(21).fontWeight(FontWeight.Medium).fontColor(CAR_TEXT)
                      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(book.narrator || book.author).fontSize(16).fontColor(CAR_SECONDARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(20).fontColor([CAR_SECONDARY])
                }.width('100%').padding(12)
              }.width('100%').backgroundColor(CAR_SURFACE).borderRadius(14)
                .focusBox(CAR_FOCUS)
                .onClick((): void => { this.openBook(book); }).accessibilityText(book.title)
            }
          }, (book: Book): string => this.books.getVersionedKey(book))
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).cachedCount(3)
      }
    }.width('100%').height('100%')
  }

  @Builder
  private playbackControls() {
    Row({ space: 10 }) {
      HiCarControl({ icon: $r('sys.symbol.backward_end_fill'), label: $r('app.string.hicar_previous'),
        controlEnabled: !!this.player.currentBook && !this.actionBusy && !this.player.isLoading,
        onAction: (): void => { this.runAction((): Promise<void> => AudioService.getInstance().playPrevious()); } })
        .layoutWeight(1)
      HiCarControl({ icon: this.player.isPlaying ? $r('sys.symbol.pause_round_triangle_fill') :
        $r('sys.symbol.play_round_triangle_fill'), label: this.player.isPlaying || this.player.isLoading ?
          $r('app.string.hicar_pause') : $r('app.string.hicar_play'), primary: true, loading: this.player.isLoading,
        controlEnabled: !!this.player.currentBook, onAction: (): void => this.togglePlayback() }).layoutWeight(1)
      HiCarControl({ icon: $r('sys.symbol.forward_end_fill'), label: $r('app.string.hicar_next'),
        controlEnabled: !!this.player.currentBook && !this.actionBusy && !this.player.isLoading,
        onAction: (): void => { this.runAction((): Promise<void> => AudioService.getInstance().playNext()); } })
        .layoutWeight(1)
    }.width('100%').id('hicar-primary-controls')
  }

  @Builder
  private playerDetails() {
    Column({ space: 14 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 14 }) {
          CoverImage({ url: this.player.currentBook?.cover ?? '', title: this.player.currentBook?.title ?? '',
            author: this.player.currentBook?.author ?? '', localPlaceholder: !this.player.currentBook?.cover,
            imgWidth: 56, imgHeight: 72, useFixedHeight: true, radius: 10, themedDecoration: false, eagerLoad: true })
          Column({ space: 7 }) {
            Text(this.player.currentBook?.title ?? $r('app.string.hicar_choose_book'))
              .fontSize(24).fontWeight(FontWeight.Bold).fontColor(CAR_TEXT).maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.player.currentChapter?.title ?? $r('app.string.hicar_choose_hint'))
              .fontSize(18).fontColor(CAR_SECONDARY).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.player.currentBook) {
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(20).fontColor([CAR_SECONDARY])
          }
        }.width('100%')
      }.width('100%').backgroundColor(Color.Transparent).padding(4).borderRadius(12)
        .focusBox(CAR_FOCUS)
        .onClick((): void => this.showCurrentChapters()).enabled(!!this.player.currentBook)
        .accessibilityText($r('app.string.hicar_open_current')).id('hicar-current-book')
        Column({ space: 6 }) {
          Progress({ value: this.player.progressMs, total: Math.max(1, this.player.durationMs || this.player.savedDurationMs),
            type: ProgressType.Linear }).color(AppColor.Brand).backgroundColor('#354353').width('100%')
          Row() {
            Text(this.timeLabel(this.player.progressMs)).fontSize(16).fontColor(CAR_SECONDARY)
            Blank()
            Text(this.player.isLive ? $r('app.string.hicar_live') :
              this.timeLabel(this.player.durationMs || this.player.savedDurationMs)).fontSize(16).fontColor(CAR_SECONDARY)
          }.width('100%')
        }.width('100%')
        Row({ space: 10 }) {
          HiCarControl({ icon: $r('sys.symbol.gobackward_15'), label: $r('app.string.hicar_rewind'),
            compact: true,
            controlEnabled: !!this.player.currentBook && !this.player.isLive && !this.player.isLoading,
            onAction: (): void => { AudioService.getInstance().seekBy(-15000); } }).layoutWeight(1)
          HiCarControl({ icon: $r('sys.symbol.arrow_left_arrow_right'),
            compact: true,
            label: $r('app.string.hicar_speed_value', this.player.speed.toFixed(2)),
            controlEnabled: !!this.player.currentBook && !this.player.isLive,
            onAction: (): void => this.changeSpeed() }).layoutWeight(1)
          HiCarControl({ icon: $r('sys.symbol.goforward_15'), label: $r('app.string.hicar_forward'),
            compact: true,
            controlEnabled: !!this.player.currentBook && !this.player.isLive && !this.player.isLoading,
            onAction: (): void => { AudioService.getInstance().seekBy(15000); } }).layoutWeight(1)
        }.width('100%')
    }.width('100%')
  }

  @Builder
  private playerPanel() {
    Column({ space: 12 }) {
      Scroll() {
        this.playerDetails()
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
      this.playbackControls()
    }.width('100%').height('100%').padding(14).backgroundColor(CAR_SURFACE).borderRadius(18)
  }

  @Builder
  private paneTabs() {
    Row({ space: 10 }) {
      Button($r('app.string.hicar_library'), { type: ButtonType.Normal })
        .height(48).layoutWeight(1).fontSize(18).borderRadius(12)
        .fontColor(this.playerVisible ? CAR_TEXT : AppColor.OnBrand)
        .backgroundColor(this.playerVisible ? CAR_SURFACE : AppColor.Brand)
        .focusBox(CAR_FOCUS)
        .onClick((): void => { this.playerVisible = false; }).id('hicar-library-pane')
      Button($r('app.string.hicar_now_playing'), { type: ButtonType.Normal })
        .height(48).layoutWeight(1).fontSize(18).borderRadius(12)
        .fontColor(this.playerVisible ? AppColor.OnBrand : CAR_TEXT)
        .backgroundColor(this.playerVisible ? AppColor.Brand : CAR_SURFACE)
        .focusBox(CAR_FOCUS)
        .onClick((): void => { this.playerVisible = true; }).id('hicar-player-pane')
    }.width('100%')
  }

  build() {
    Column({ space: 12 }) {
      this.header()
      if (this.usesColumns()) {
        Row({ space: 14 }) {
          Column() { this.libraryPanel() }.layoutWeight(1).height('100%')
          Column() { this.playerPanel() }.layoutWeight(1).height('100%')
        }.width('100%').layoutWeight(1)
      } else {
        this.paneTabs()
        Stack() {
          Column() { this.libraryPanel() }.width('100%').height('100%')
            .visibility(this.playerVisible ? Visibility.None : Visibility.Visible)
          Column() { this.playerPanel() }.width('100%').height('100%')
            .visibility(this.playerVisible ? Visibility.Visible : Visibility.None)
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').backgroundColor(CAR_BACKGROUND)
      .padding({ left: Math.max(16, this.safeLeft + 12), right: Math.max(16, this.safeRight + 12),
        top: this.safeTop + 8, bottom: this.safeBottom + 8 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        this.widthVp = Number(size.width);
        this.heightVp = Number(size.height);
      }).id('hicar-page')
  }
}

@ComponentV2
struct HiCarControl {
  @Param icon: Resource = $r('sys.symbol.play_round_triangle_fill');
  @Param label: Resource = $r('app.string.hicar_play');
  @Param primary: boolean = false;
  @Param controlEnabled: boolean = true;
  @Param loading: boolean = false;
  @Param compact: boolean = false;
  @Local focused: boolean = false;
  @Event onAction: () => void = (): void => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 5 }) {
        if (this.loading) {
          LoadingProgress().color(AppColor.Brand).width(28).height(28)
        } else {
          SymbolGlyph(this.icon).fontSize(this.compact ? 22 : 28).fontColor([this.primary ? AppColor.OnBrand : CAR_TEXT])
        }
        Text(this.label).fontSize(this.compact ? 14 : 16).fontColor(this.primary ? AppColor.OnBrand : CAR_TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%')
    }.width('100%').height(this.compact ? 62 : 78)
      .backgroundColor(this.loading ? '#354353' : (this.primary ? AppColor.Brand : '#293647'))
      .border({ width: this.focused ? 3 : 0, color: CAR_TEXT })
      .borderRadius(14)
      .opacity(this.controlEnabled ? 1 : 0.4).enabled(this.controlEnabled).accessibilityText(this.label)
      .onFocus((): void => { this.focused = true; }).onBlur((): void => { this.focused = false; })
      .onClick((): void => this.onAction())
  }
}
