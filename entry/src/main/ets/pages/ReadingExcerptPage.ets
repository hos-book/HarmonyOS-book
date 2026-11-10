import { common, sendableContextManager } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { CoverImage } from '../components/CoverImage';
import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { ReadingExcerpt, ReadingExcerptBook } from '../model/ReadingExcerpt';
import { ReadingExcerptRoute } from '../model/ReadingExcerptRoute';
import { ReadingExcerptService } from '../service/text/ReadingExcerptService';
import { AppColor, AppFont, AppTheme } from '../theme/Theme';
import { ListDataSource } from '../utils/ListDataSource';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct ReadingExcerptPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param route: ReadingExcerptRoute = new ReadingExcerptRoute();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Local books: ReadingExcerptBook[] = [];
  @Local excerpts: ReadingExcerpt[] = [];
  @Local ready: boolean = false;
  @Local failed: boolean = false;
  @Local loading: boolean = false;
  @Local deleting: boolean = false;
  @Local hasMore: boolean = false;
  private context: common.UIAbilityContext | null = null;
  private alive: boolean = false;
  private generation: number = 0;
  private retryReset: boolean = true;
  private reloadPending: boolean = false;
  private bookData: ListDataSource<ReadingExcerptBook> = new ListDataSource<ReadingExcerptBook>();
  private excerptData: ListDataSource<ReadingExcerpt> = new ListDataSource<ReadingExcerpt>();

  aboutToAppear(): void {
    this.alive = true;
    const context = this.getUIContext().getHostContext();
    if (context) this.context = sendableContextManager.convertToUIAbilityContext(
      sendableContextManager.convertFromContext(context));
    this.load(true);
  }

  aboutToDisappear(): void { this.alive = false; this.generation++; }

  private toast(message: ResourceStr): void {
    if (this.alive) this.getUIContext().getPromptAction().showToast({ message });
  }

  private async load(reset: boolean): Promise<void> {
    if (!this.alive) return;
    if (this.loading || this.deleting) {
      if (reset) this.reloadPending = true;
      return;
    }
    if (!this.context) { this.failed = true; return; }
    const generation = ++this.generation;
    this.retryReset = reset;
    this.reloadPending = false;
    this.loading = true;
    this.failed = false;
    try {
      if (this.route.bookKey) {
        const offset = reset ? 0 : this.excerpts.length;
        const page = await ReadingExcerptService.list(this.context, this.route.bookKey, offset, 50);
        if (!this.alive || generation !== this.generation) return;
        this.excerpts = reset ? page : this.excerpts.concat(page);
        this.excerptData.setItems(this.excerpts);
        this.hasMore = page.length === 50;
      } else {
        const offset = reset ? 0 : this.books.length;
        const page = await ReadingExcerptService.books(this.context, offset, 50);
        if (!this.alive || generation !== this.generation) return;
        this.books = reset ? page : this.books.concat(page);
        this.bookData.setItems(this.books);
        this.hasMore = page.length === 50;
      }
      this.ready = true;
    } catch (_error) {
      if (this.alive && generation === this.generation) this.failed = true;
    } finally {
      if (this.alive && generation === this.generation) {
        this.loading = false;
        if (this.reloadPending) this.load(true);
      }
    }
  }

  private openBook(book: ReadingExcerptBook): void {
    this.navStack.pushPath({ name: 'readingExcerpts',
      param: new ReadingExcerptRoute(book.bookKey, book.bookTitle),
      onPop: (): void => { this.load(true); } });
  }

  private openExcerpt(excerpt: ReadingExcerpt): void {
    if (this.deleting) return;
    this.navStack.pushPath({ name: 'readingExcerptDetail', param: excerpt,
      onPop: (): void => { this.load(true); } });
  }

  private async copyExcerpt(excerpt: ReadingExcerpt): Promise<void> {
    try {
      const source = excerpt.author ? `《${excerpt.bookTitle}》 / ${excerpt.author}` : `《${excerpt.bookTitle}》`;
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, `${excerpt.text}\n\n${source}`));
      this.toast($r('app.string.reader_excerpt_copied'));
    } catch (_error) { this.toast($r('app.string.reader_excerpt_copy_failed')); }
  }

  private confirmDelete(excerpt: ReadingExcerpt): void {
    if (this.loading || this.deleting) return;
    this.getUIContext().showAlertDialog({
      title: $r('app.string.reader_excerpt_delete'),
      message: $r('app.string.reader_excerpt_delete_confirm'),
      primaryButton: { value: $r('app.string.common_cancel'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.common_delete'),
        action: (): void => { this.removeExcerpt(excerpt); } }
    });
  }

  private async removeExcerpt(excerpt: ReadingExcerpt): Promise<void> {
    if (!this.context || this.deleting || this.loading) return;
    this.deleting = true;
    try {
      await ReadingExcerptService.remove(this.context, excerpt.id);
      if (!this.alive) return;
      this.excerpts = this.excerpts.filter((item: ReadingExcerpt): boolean => item.id !== excerpt.id);
      this.excerptData.setItems(this.excerpts);
      this.toast($r('app.string.reader_excerpt_deleted'));
    } catch (_error) { this.toast($r('app.string.reader_excerpt_delete_failed')); }
    finally {
      if (this.alive) {
        this.deleting = false;
        if (this.reloadPending) this.load(true);
      }
    }
  }

  private timeLabel(value: number): string {
    const date = new Date(value);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-` +
      `${String(date.getDate()).padStart(2, '0')}  ${String(date.getHours()).padStart(2, '0')}:` +
      `${String(date.getMinutes()).padStart(2, '0')}`;
  }

  private coverAngle(book: ReadingExcerptBook): number {
    const order = this.books.findIndex((item: ReadingExcerptBook): boolean => item.bookKey === book.bookKey);
    return order % 2 === 0 ? -8 : 8;
  }

  @Builder
  private bookRow(book: ReadingExcerptBook) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Image($r('app.media.reading_excerpt_pattern')).width(132).height(100)
        .objectFit(ImageFit.Fill).draggable(false).hitTestBehavior(HitTestMode.None)
      Row({ space: 16 }) {
        // 透明边距随封面整体离屏合成，旋转时不会把纹理边界直接变成硬锯齿。
        Stack({ alignContent: Alignment.Center }) {
          CoverImage({ url: book.cover, title: book.bookTitle, author: book.author,
            localPlaceholder: true, imgWidth: 52, imgHeight: 72, useFixedHeight: true,
            radius: 4, themedDecoration: false, compositeEdges: true,
            interpolationQuality: ImageInterpolation.High })
        }.width(56).height(76).renderGroup(true).rotate({ angle: this.coverAngle(book) })
          .margin({ left: 1 }).flexShrink(0)
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text($r('app.string.reader_excerpt_count', book.count)).fontSize(16)
              .fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary).layoutWeight(1)
            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([AppTheme.TextSecondary])
            }.width(24).height(24).backgroundColor(AppTheme.SettingsBackground).borderRadius(12).flexShrink(0)
          }.width('100%')
          Text(book.bookTitle).fontSize(13).fontColor(AppTheme.TextSecondary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(book.author || book.latestText).fontSize(12).fontColor(AppTheme.TextSecondary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').margin({ top: 6 })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').constraintSize({ minHeight: 100 }).padding({ left: 16, right: 14, top: 12, bottom: 12 })
    }.width('100%').backgroundColor(AppTheme.Surface)
      .borderRadius(18).border({ width: 0.5, color: AppTheme.Divider }).clip(true)
      .onClick((): void => this.openBook(book))
      .accessibilityText($r('app.string.reader_excerpt_book_accessibility', book.bookTitle, book.count))
  }

  @Builder
  private excerptMenu(excerpt: ReadingExcerpt) {
    Menu() {
      MenuItem({ content: $r('app.string.reader_excerpt_copy') })
        .onClick((): void => { this.copyExcerpt(excerpt); })
      MenuItem({ content: $r('app.string.reader_excerpt_share') })
        .onClick((): void => this.openExcerpt(excerpt))
      MenuItem({ content: $r('app.string.reader_excerpt_delete') }).enabled(!this.deleting && !this.loading)
        .onClick((): void => this.confirmDelete(excerpt))
    }
  }

  @Builder
  private excerptRow(excerpt: ReadingExcerpt) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Image($r('app.media.reading_excerpt_pattern')).width(162).height(122)
        .objectFit(ImageFit.Fill).draggable(false).hitTestBehavior(HitTestMode.None)
      Column({ space: 8 }) {
        Row({ space: 2 }) {
          Text(this.timeLabel(excerpt.createdAt)).fontSize(12).fontColor(AppTheme.TextSecondary).layoutWeight(1)
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(17).fontColor([AppTheme.TextSecondary])
          }.width(32).height(32).backgroundColor(Color.Transparent).enabled(!this.deleting)
            .accessibilityText($r('app.string.reader_excerpt_share'))
            .onClick((): void => this.openExcerpt(excerpt))
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.more')).fontSize(18).fontColor([AppTheme.TextSecondary])
          }.width(32).height(32).backgroundColor(Color.Transparent).enabled(!this.deleting)
            .accessibilityText($r('app.string.reader_excerpt_more')).bindMenu(this.excerptMenu(excerpt))
        }.width('100%')
        Text(excerpt.text).fontSize(15).lineHeight(24).fontColor(AppTheme.TextPrimary).width('100%')
          .maxLines(6).textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick((): void => this.openExcerpt(excerpt))
        if (excerpt.chapterTitle) {
          Text(excerpt.chapterTitle).fontSize(12).fontColor(AppTheme.TextSecondary).width('100%')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 4 })
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 10, top: 6, bottom: 14 })
    }.width('100%').backgroundColor(AppTheme.Surface)
      .borderRadius(18).border({ width: 0.5, color: AppTheme.Divider }).clip(true)
  }

  @Builder
  private emptyState() {
    Column({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.bookmark')).fontSize(42).fontColor([AppColor.Brand]).opacity(0.75)
      Text(this.route.bookKey ? $r('app.string.reader_excerpt_book_empty') : $r('app.string.reader_excerpt_empty'))
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
      Text($r('app.string.reader_excerpt_empty_hint')).fontSize(14).fontColor(AppTheme.TextSecondary)
        .textAlign(TextAlign.Center).lineHeight(22)
    }.width('100%').padding({ left: 32, right: 32, top: 80, bottom: 24 })
  }

  @Builder
  private footer() {
    Column({ space: 8 }) {
      if (this.failed) {
        Text($r('app.string.reader_excerpt_load_failed')).fontSize(13).fontColor(AppTheme.TextSecondary)
      }
      if (this.loading) {
        LoadingProgress().width(28).height(28).color(AppColor.Brand)
      } else if (this.hasMore || this.failed) {
        Button(this.failed ? $r('app.string.common_retry') : $r('app.string.reader_excerpt_load_more'))
          .fontSize(14).fontColor(AppColor.Brand).backgroundColor(Color.Transparent).enabled(!this.deleting)
          .onClick((): void => { this.load(this.failed ? this.retryReset : false); })
      }
    }.width('100%').padding({ top: 10, bottom: 16 })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        if (this.ready) {
          List({ space: 10 }) {
            if (this.route.bookKey) {
              if (this.excerpts.length === 0) { ListItem() { this.emptyState() } }
              LazyForEach(this.excerptData, (excerpt: ReadingExcerpt) => {
                ListItem() { this.excerptRow(excerpt) }
              }, (excerpt: ReadingExcerpt): string => excerpt.id)
            } else {
              ListItem() {
                Text($r('app.string.reader_excerpt_subtitle')).fontSize(14).fontColor(AppTheme.TextSecondary)
                  .padding({ left: 4, top: 2, bottom: 2 })
              }
              if (this.books.length === 0) { ListItem() { this.emptyState() } }
              LazyForEach(this.bookData, (book: ReadingExcerptBook) => {
                ListItem() { this.bookRow(book) }
              }, (book: ReadingExcerptBook): string => `${book.bookKey}:${book.count}:${book.latestAt}`)
            }
            ListItem() { this.footer() }
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
            .padding({ left: 16, right: 16 }).contentStartOffset(this.headerHeight + 8)
            .contentEndOffset(WindowUtils.getBottomSafeVp() + 16)
        } else {
          Column({ space: 14 }) {
            if (this.failed) {
              Text($r('app.string.reader_excerpt_load_failed')).fontSize(15).fontColor(AppTheme.TextSecondary)
              Button($r('app.string.common_retry')).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
                .onClick((): void => { this.load(true); })
            } else { LoadingProgress().width(32).height(32).color(AppColor.Brand) }
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding({ top: this.headerHeight })
        }
      }.width('100%').height('100%').constraintSize({ maxWidth: 760 })
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back')).onClick((): void => { this.navStack.pop(); })
          Text(this.route.bookTitle || $r('app.string.reader_excerpt_title')).fontSize(AppFont.Title)
            .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.deleting) { LoadingProgress().width(22).height(22).color(AppColor.Brand) }
        }.width('100%').padding({ left: 8, right: 20, top: WindowUtils.getStatusBarHeightVp() + 8, bottom: 8 })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
