import { HdsCompat } from '../utils/HdsCompat';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { AppRadius, AppSpace, AppFont, AppColor } from '../theme/Theme';
import { Book, Chapter } from '../model/Book';
import { SearchResult } from '../model/BookSource';
import { SourceDataService } from '../service/SourceDataService';
import { BookSourceService, ExploreFetchResult } from '../service/BookSourceService';
import { SearchCache } from '../utils/SearchCache';
import { BookDataSource } from '../utils/BookDataSource';
import { BookCard } from '../components/BookCard';
import { WindowUtils } from '../utils/WindowUtils';
import { PlaybackStore } from '../service/PlaybackStore';
import { BookIdentity } from '../utils/BookIdentity';
import { CoverPrefetcher } from '../service/CoverPrefetcher';

const DOMAIN = 0x0000;
const TAG = 'BlockMorePage';
const MINI_TITLE_BAR_HEIGHT: number = 56;

@ComponentV2
export struct BlockMorePage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param sourceUrl: string = '';
  @Param sourceName: string = '';
  @Param title: string = '';
  @Param moreUrl: string = '';
  @Param keyword: string = '';

  @Local books: Book[] = [];
  @Local bookColumns: number = 3;
  @Local loading: boolean = true;
  @Local loadingMore: boolean = false;
  @Local hasMore: boolean = true;
  @Local errorMsg: string = '';

  private dataSource: BookDataSource = new BookDataSource();
  private nextUrl: string = '';
  private nextPage: number = 2;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.nextUrl = this.moreUrl;
    this.nextPage = 2;
    this.loading = true;
    this.loadFirstPage();
  }

  private async loadFirstPage(): Promise<void> {
    if ((!this.moreUrl && !this.keyword) || !this.sourceUrl) {
      this.errorMsg = '参数错误';
      this.loading = false;
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    this.books = [];
    this.dataSource.clear();
    BookCard.resetAnimations();
    this.nextPage = 2;
    await this.fetchPage(this.moreUrl, false);
    this.loading = false;
  }

  private async loadNextPage(): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMore || (!this.nextUrl && !this.keyword)) return;
    this.loadingMore = true;
    await this.fetchPage(this.nextUrl, true);
    this.loadingMore = false;
  }

  private async fetchPage(url: string, append: boolean): Promise<void> {
    try {
      const source = await SourceDataService.getSourceByUrl(this.sourceUrl);
      if (!source) {
        this.errorMsg = this.getUIContext().getHostContext()?.resourceManager
          .getStringSync($r('app.string.imported_source_unavailable').id) ?? '';
        this.hasMore = false;
        return;
      }

      const newBooks: Book[] = [];
      const page = append ? this.nextPage : 1;
      const result: ExploreFetchResult = this.keyword.length > 0
        ? { books: await BookSourceService.searchBooks(source, this.keyword, page), nextUrl: this.keyword }
        : await BookSourceService.getExploreBooksByUrl(source, url, page);
      const seen = new Set<string>(append ? this.books.map((book: Book): string => book.bookUrl ?? '') : []);
      for (const item of result.books) {
        if (seen.has(item.bookUrl)) continue;
        seen.add(item.bookUrl);
        newBooks.push(this.searchResultToBook(item));
      }
      const nextUrl = result.nextUrl || '';
      this.nextPage = result.nextPage ?? (page + 1);

      if (append) {
        this.books = this.books.concat(newBooks);
        this.dataSource.appendBooks(newBooks);
      } else {
        this.books = newBooks;
        this.dataSource.setBooks(newBooks);
      }
      this.nextUrl = nextUrl;
      this.hasMore = this.nextUrl.length > 0 && newBooks.length > 0;
      const covers: string[] = [];
      for (const b of newBooks) {
        if (b.cover && b.cover.startsWith('http')) covers.push(b.cover);
      }
      CoverPrefetcher.prefetchMany(covers, 16);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'fetchPage failed: %{public}s', msg);
      if (!append) this.errorMsg = '加载失败：' + msg;
      this.hasMore = false;
    }
  }

  private searchResultToBook(r: SearchResult): Book {
    const emptyChapters: Chapter[] = [];
    const book: Book = {
      id: r.contentType === 'comic' ? BookIdentity.onlineComicBookId(r.sourceUrl, r.bookUrl) :
      r.contentType === 'text' ? BookIdentity.onlineTextBookId(r.sourceUrl, r.bookUrl) :
        BookIdentity.onlineAudioBookId(r.sourceUrl || '', r.bookUrl || r.name),
      title: r.name,
      author: r.author || '未知',
      narrator: r.sourceName,
      cover: r.coverUrl || '',
      category: r.kind || '',
      contentType: r.contentType ?? 'audio',
      intro: r.intro || '',
      wordCount: r.wordCount,
      latestChapterTitle: r.lastChapter,
      updateTime: r.updateTime,
      totalDuration: 0,
      chapterCount: 0,
      rating: r.rating ?? 0,
      tags: [r.sourceName],
      chapters: emptyChapters,
      bookUrl: r.bookUrl,
      sourceUrl: r.sourceUrl,
      variables: r.variables,
      completed: r.completed,
    };
    SearchCache.put(book);
    return book;
  }

  private handleBookTap(bookId: string): void {
    if (PlaybackStore.getInstance().isCurrentBook(bookId)) {
      this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, () => {
        this.navStack.pushPathByName('player', bookId, false);
      });
      return;
    }
    this.navStack.pushPathByName('detail', bookId);
  }

  build() {
    HdsNavigation() {
      Column() {
        if (this.loading && this.books.length === 0) {
          this.buildLoading()
        } else if (this.errorMsg && this.books.length === 0) {
          this.buildError()
        } else if (this.books.length === 0) {
          this.buildEmpty()
        } else {
          this.buildGrid()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_primary'))
    }
    .mode(NavigationMode.Stack)
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: {
          mainTitle: this.title || '更多'
        },
        backIcon: {
          icon: $r('sys.symbol.chevron_left'),
          action: () => this.navStack.pop()
        }
      },
      style: {
        scrollEffectOpts: {
          scrollEffectType: HdsCompat.scrollEffect
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: Color.Transparent
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('sys.color.font_primary'),
              subTitleColor: $r('sys.color.font_secondary')
            },
            backIconStyle: {
              iconColor: $r('sys.color.icon_primary')
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: Color.Transparent
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('sys.color.font_primary'),
              subTitleColor: $r('sys.color.font_secondary')
            },
            backIconStyle: {
              iconColor: $r('sys.color.icon_primary')
            }
          }
        },
        systemMaterialEffect: HdsCompat.material
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  buildEmpty() {
    Column({ space: AppSpace.Md }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('sys.color.font_tertiary')])
      Text('暂无内容')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
      Text(this.moreUrl)
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
        .textAlign(TextAlign.Center)
      Text('点击重试')
        .fontSize(AppFont.Body)
        .fontColor(AppColor.Brand)
        .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
        .borderRadius(AppRadius.Md)
        .onClick(() => this.loadFirstPage())
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildLoading() {
    Column() {
      LoadingProgress().width(40).height(40).color(AppColor.Brand)
      Text('加载中...')
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: AppSpace.Sm })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildError() {
    Column({ space: AppSpace.Md }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('sys.color.font_tertiary')])
      Text(this.errorMsg)
        .fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
        .textAlign(TextAlign.Center)
        .padding({ left: AppSpace.Lg, right: AppSpace.Lg })
      Text('点击重试')
        .fontSize(AppFont.Body)
        .fontColor(AppColor.Brand)
        .padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
        .borderRadius(AppRadius.Md)
        .onClick(() => this.loadFirstPage())
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildGrid() {
    Grid(this.scroller) {
      LazyForEach(this.dataSource, (book: Book, idx: number) => {
        GridItem() {
          BookCard({
            book: book,
            indexHint: idx,
            showRating: true,
            onTap: () => this.handleBookTap(book.id)
          })
        }
      }, (book: Book) => book.id)

      if (this.loadingMore) {
        GridItem() {
          Row({ space: AppSpace.Xs }) {
            LoadingProgress().width(20).height(20).color(AppColor.Brand)
            Text('加载更多...')
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .height(48)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .columnStart(0).columnEnd(this.bookColumns - 1)
      } else if (!this.hasMore && this.books.length > 0) {
        GridItem() {
          Text('— 没有更多了 —')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .height(48)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .columnStart(0).columnEnd(this.bookColumns - 1)
      }
    }
    .columnsTemplate(`repeat(${this.bookColumns}, 1fr)`)
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
      if (typeof size.width === 'number' && size.width > 0) {
        this.bookColumns = AdaptiveLayout.bookColumns(size.width);
      }
    })
    .columnsGap(AppSpace.Sm)
    .rowsGap(AppSpace.Md)
    .cachedCount(6)
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({
      left: AppSpace.Md, right: AppSpace.Md,
      top: WindowUtils.getStatusBarHeightVp() + MINI_TITLE_BAR_HEIGHT + AppSpace.Sm,
      bottom: WindowUtils.getBottomSafeVp() + AppSpace.Lg
    })
    .onReachEnd(() => this.loadNextPage())
  }
}
