import { emitter } from '@kit.BasicServicesKit';
import { curves } from '@kit.ArkUI';
import { Book, Chapter } from '../model/Book';
import { ChapterListItem, ChapterBadge, mapChapterBadge } from './ChapterListItem';
import { ChapterSegmentGrid } from './ChapterSegmentGrid';
import { ChapterLoadingSkeleton } from './ChapterLoadingSkeleton';
import { AppColor, AppFont, AppRadius, AppSpace, AppMotion, AppCurve } from '../theme/Theme';
import { DownloadService, EVT_DOWNLOAD_UPDATED, DownloadUpdatePayload } from '../service/DownloadService';
import { DownloadChapterRecord } from '../service/DownloadStore';
import { PreferenceService } from '../service/PreferenceService';

/**
 * 章节目录弹层内容（详情页 / 播放页 / 阅读页共用）。
 *
 * 只负责「搜索 + 正倒序 + 列表↔分段 + 回到当前章节」，章节数据由父页面传入，
 * 点章行为通过 onSelect 回抛，父页面自己决定是起播、跳读还是仅仅定位。
 */
@ComponentV2
export struct ChapterSheet {
  @Param book: Book | null = null;
  /** 当前章 id，用于高亮与「回到当前章节」。 */
  @Param currentId: string = '';
  @Param headerTitle: ResourceStr = '';
  @Param loading: boolean = false;
  @Param failed: boolean = false;
  /** 当前章已播进度文案；为空则不显示。 */
  @Param currentProgressText: string = '';
  @Event onSelect: (chapter: Chapter) => void = () => {};
  @Event onLongPress: (chapter: Chapter) => void = () => {};
  @Event onRetry: () => void = () => {};
  @Event onClose: () => void = () => {};

  @Local query: string = '';
  @Local segmentMode: boolean = false;
  @Local descending: boolean = false;
  @Local displayed: Chapter[] = [];
  @Local offsetFromCurrent: number = 0;
  /** 下载状态变化的重渲染哨兵：每次事件 +1，方法里读它建立依赖。 */
  @Local downloadTick: number = 0;
  private listScroller: Scroller = new Scroller();
  private positionTimer: number = -1;

  private downloadHandler = (evt: emitter.EventData): void => {
    const data = evt.data as DownloadUpdatePayload;
    if (!data || data.bookId !== this.book?.id) return;
    this.downloadTick = this.downloadTick + 1;
  };

  aboutToAppear(): void {
    this.descending = this.book?.chaptersDescending ?? false;
    this.refresh();
    emitter.on(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
    this.scrollToCurrentChapter();
  }

  aboutToDisappear(): void {
    emitter.off(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
    if (this.positionTimer !== -1) clearTimeout(this.positionTimer);
    this.positionTimer = -1;
  }

  @Monitor('book')
  private onBookChanged(): void {
    this.descending = this.book?.chaptersDescending ?? false;
    this.refresh();
    this.scrollToCurrentChapter();
  }

  @Monitor('currentId')
  private onCurrentChanged(): void {
    this.offsetFromCurrent = 0;
    this.scrollToCurrentChapter();
  }

  private isReadingBook(): boolean {
    return this.book?.contentType === 'text' || this.book?.contentType === 'comic';
  }

  private unit(): string {
    return this.isReadingBook() ? '章' : '集';
  }

  private total(): number {
    return Math.max(this.book?.chapterCount ?? 0, this.book?.chapters.length ?? 0);
  }

  /** 头部计数：搜索时显示匹配数，否则显示总数并提示可切换分段目录。 */
  private headerCountText(): ResourceStr {
    if (this.query.trim().length > 0) return `匹配 ${this.displayed.length} ${this.unit()}`;
    if (this.loading && (this.book?.chapters.length ?? 0) === 0) return '目录加载中';
    return `共 ${this.total()} ${this.unit()} · 切换`;
  }

  private chapters(): Chapter[] {
    return this.book?.chapters ?? [];
  }

  private currentIndex(): number {
    const list = this.chapters();
    if (list.length === 0 || this.currentId.length === 0) return -1;
    return list.findIndex((chapter: Chapter): boolean => chapter.id === this.currentId);
  }

  /** 过滤 + 排序后的展示数组；每次返回新引用，让 Repeat 重算每行的角标与进度。 */
  private refresh(): void {
    const query = this.query.trim().toLowerCase();
    const filtered = query.length > 0
      ? this.chapters().filter((chapter: Chapter): boolean => chapter.title.toLowerCase().includes(query))
      : this.chapters().slice();
    this.displayed = this.descending ? filtered.reverse() : filtered;
  }

  private applyQuery(value: string): void {
    this.query = value;
    this.refresh();
    if (value.trim().length === 0) this.scrollToCurrentChapter();
  }

  private toggleLayout(): void {
    this.segmentMode = !this.segmentMode;
    this.offsetFromCurrent = 0;
    if (!this.segmentMode) this.scrollToCurrentChapter();
  }

  private toggleOrder(): void {
    this.descending = !this.descending;
    const book = this.book;
    if (book) {
      book.chaptersDescending = this.descending;
      PreferenceService.saveTocOrder(book.id, this.descending).catch((): void => {});
    }
    this.refresh();
    if (!this.segmentMode) this.listScroller.scrollToIndex(0, false);
  }

  private scrollToCurrentChapter(): void {
    if (this.positionTimer !== -1) clearTimeout(this.positionTimer);
    this.positionTimer = -1;
    if (this.segmentMode || this.query.trim().length > 0 || this.currentId.length === 0) return;
    this.positionTimer = setTimeout((): void => {
      this.positionTimer = -1;
      if (this.segmentMode || this.query.trim().length > 0) return;
      const idx = this.displayed.findIndex((chapter: Chapter): boolean => chapter.id === this.currentId);
      if (idx < 0) return;
      try {
        this.listScroller.scrollToIndex(idx, false, ScrollAlign.CENTER);
      } catch (_e) { /* 未挂载时忽略 */ }
    }, 60);
  }

  private shouldShowJumpButton(): boolean {
    return this.query.trim().length === 0 && this.currentIndex() >= 0 &&
      (this.book?.contentType === 'comic' || Math.abs(this.offsetFromCurrent) > 200);
  }

  private chapterRecord(chapter: Chapter): DownloadChapterRecord | null {
    if (this.downloadTick < 0) return null;
    const bookId = this.book?.id;
    if (!bookId) return null;
    return DownloadService.getInstance().getChapterStatus(bookId, chapter);
  }

  private chapterDuration(chapter: Chapter): number {
    if (chapter.duration > 0) return chapter.duration;
    return this.chapterRecord(chapter)?.durationSec ?? 0;
  }

  private isDownloaded(chapter: Chapter): boolean {
    return this.chapterRecord(chapter)?.status === 'completed';
  }

  private isDownloading(chapter: Chapter): boolean {
    const status = this.chapterRecord(chapter)?.status;
    return status === 'pending' || status === 'resolving' || status === 'downloading';
  }

  private isDownloadFailed(chapter: Chapter): boolean {
    return this.chapterRecord(chapter)?.status === 'failed';
  }

  private formatDuration(seconds: number): string {
    if (seconds <= 0) return '';
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m < 10 ? '0' : ''}${m}:${s < 10 ? '0' : ''}${s}`;
  }

  private formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  private rowKey(chapter: Chapter): string {
    return chapter.id + ':' + (chapter.originSourceValue || chapter.source.value);
  }

  @Builder
  private buildHeader() {
    Row({ space: AppSpace.Sm }) {
      Text(this.headerTitle)
        .fontSize(AppFont.Title)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (!this.loading || this.chapters().length > 0) {
        Button(this.headerCountText())
          .fontSize(AppFont.Caption)
          .fontColor(AppColor.Brand)
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.toggleLayout())
      }
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(20)
        .fontColor([$r('sys.color.font_secondary')])
        .onClick((): void => this.onClose())
    }
    .width('100%')
    .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Md })
  }

  @Builder
  private buildRow(ri: RepeatItem<Chapter>) {
    ChapterListItem({
      book: this.book,
      chapter: ri.item,
      title: ri.item.title,
      isTextBook: this.isReadingBook(),
      isPlaying: ri.item.id === this.currentId,
      durationText: this.isReadingBook() ? ''
        : (this.chapterDuration(ri.item) > 0 ? this.formatDuration(this.chapterDuration(ri.item)) : ''),
      bytesText: this.isReadingBook() ? ''
        : (this.isDownloaded(ri.item) && (this.chapterRecord(ri.item)?.bytes ?? 0) > 0
          ? this.formatBytes(this.chapterRecord(ri.item)?.bytes ?? 0)
          : ''),
      progressText: this.isReadingBook() ? ''
        : (ri.item.id === this.currentId ? this.currentProgressText : ''),
      horizontalInset: AppSpace.Lg,
      badge: this.isReadingBook() ? ChapterBadge.None
        : mapChapterBadge(this.isDownloaded(ri.item), this.isDownloading(ri.item), this.isDownloadFailed(ri.item)),
      onTap: (): void => this.onSelect(ri.item)
    })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: AppSpace.Sm }) {
        this.buildHeader()

        if (this.chapters().length > 0) {
          Search({ value: this.query, placeholder: this.isReadingBook() ? $r('app.string.reader_search_chapters') : '搜索节目' })
            .onChange((value: string): void => this.applyQuery(value))
            .fontColor($r('sys.color.font_primary'))
            .placeholderColor($r('sys.color.font_tertiary'))
            .searchIcon({ size: 18, color: $r('sys.color.font_secondary') })
            .height(40)
            .borderRadius(AppRadius.Lg)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .margin({ left: AppSpace.Lg, right: AppSpace.Lg })
        }

        if (this.loading && this.chapters().length === 0) {
          ChapterLoadingSkeleton({
            horizontalInset: AppSpace.Lg,
            isTextBook: this.isReadingBook(),
            rowCount: 8
          })
        } else if (this.chapters().length === 0) {
          Column({ space: AppSpace.Sm }) {
            Text($r('app.string.reader_no_chapters'))
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_tertiary'))
            if (this.failed) {
              Button($r('app.string.chapter_load_retry'))
                .fontSize(AppFont.Body)
                .fontColor(AppColor.Brand)
                .backgroundColor(Color.Transparent)
                .onClick((): void => this.onRetry())
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.query.trim().length > 0 && this.displayed.length === 0) {
          Column() {
            Text('无匹配章节')
              .fontSize(AppFont.Body)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.segmentMode) {
          ChapterSegmentGrid({
            book: this.book,
            chapters: this.chapters(),
            currentId: this.currentId,
            keyword: this.query,
            descending: this.descending,
            onSelect: (chapter: Chapter): void => this.onSelect(chapter),
            onLongPress: (chapter: Chapter): void => this.onLongPress(chapter)
          })
            .layoutWeight(1)
        } else {
          Row() {
            Text(this.descending ? $r('app.string.chapter_order_desc') : $r('app.string.chapter_order_asc'))
              .fontSize(AppFont.Caption)
              .fontColor(AppColor.Brand)
              .padding({ left: AppSpace.Lg, right: AppSpace.Lg, top: AppSpace.Xxs, bottom: AppSpace.Xxs })
              .onClick((): void => this.toggleOrder())
            if (this.loading) {
              LoadingProgress().width(16).height(16).color(AppColor.Brand)
            }
            Blank()
          }
          .width('100%')

          List({ space: 0, scroller: this.listScroller }) {
            Repeat<Chapter>(this.displayed)
              .each((ri: RepeatItem<Chapter>) => {
                ListItem() {
                  this.buildRow(ri)
                }
              })
              .key((chapter: Chapter): string => this.rowKey(chapter))
              .virtualScroll({ reusable: true })
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(5)
          .onAppear((): void => this.scrollToCurrentChapter())
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .transition(
            TransitionEffect.opacity(0)
              .combine(TransitionEffect.translate({ y: 12 }))
              .animation({ duration: AppMotion.Base, curve: AppCurve.Decelerate })
          )
          .onScrollIndex((firstIndex: number, lastIndex: number): void => {
            const idx = this.displayed.findIndex((chapter: Chapter): boolean => chapter.id === this.currentId);
            if (idx < 0) return;
            this.offsetFromCurrent = ((firstIndex + lastIndex) / 2 - idx) * 64;
          })
        }
      }
      .width('100%')
      .height('100%')

      if (!this.segmentMode && this.shouldShowJumpButton()) {
        Row({ space: AppSpace.Xs }) {
          SymbolGlyph($r('sys.symbol.scope'))
            .fontSize(16)
            .fontColor(['#FFFFFF'])
          Text($r('app.string.reader_back_to_current_chapter'))
            .fontSize(AppFont.Caption)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius(22)
        .backgroundColor(AppColor.Brand)
        .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
        .margin({ right: AppSpace.Lg, bottom: AppSpace.Lg })
        .onClick((): void => {
          this.offsetFromCurrent = 0;
          this.scrollToCurrentChapter();
        })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.8, y: 0.8 }))
          .animation({ curve: curves.springMotion(0.4, 0.9) }))
      }
    }
    .width('100%')
    .height('100%')
  }
}
