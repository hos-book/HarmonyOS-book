import { Book } from '../model/Book';
import { Chapter } from '../model/Book';
import { BookPresentation } from '../model/BookPresentation';
import { BookSourceService } from '../service/BookSourceService';
import { ChapterSheet } from './ChapterSheet';
import { BookGroupSheet } from './BookGroupSheet';
import { PreferenceService } from '../service/PreferenceService';
import { DataService } from '../service/DataService';
import { ReadingSession, ReadingSessionService, SessionLocation } from '../service/ReadingSessionService';
import { AppColor, AppTheme, AppCurve, AppMotion } from '../theme/Theme';
import { DetailActionItem } from './DetailActionItem';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';

/**
 * 卡片内的书籍详情：选中书源后替换匹配面板。
 * 布局参考详情页，但不放封面、不放返回/收藏，底部主按钮由外层卡片统一承担。
 */
@ComponentV2
export struct RankingBookDetail {
  @Param book: Book | undefined = undefined;
  /** 榜单那本书的简介，匹配结果通常没有简介，用来兜底。 */
  @Param intro: string = '';
  /** 换源：回到匹配面板。 */
  @Event onSwitchSource: () => void = () => {};
  /** 查看目录（后续接入）。 */
  @Event onOpenCatalog: () => void = () => {};
  /** 阅读/收听记录（后续接入）。 */
  @Event onOpenHistory: () => void = () => {};
  @Local favorite: boolean = false;
  @Local chapterCount: number = -1;
  @Local tocLoading: boolean = true;
  @Local tocFailed: boolean = false;
  @Local chapters: Chapter[] = [];
  private chapterData: HomeRecommendationDataSource<Chapter> = new HomeRecommendationDataSource<Chapter>();
  /** 详情内的子视图：info / catalog / group。 */
  @Param view: string = 'info';
  /** 卡片顶到屏幕最上沿后，内容整体下移状态栏高度，避开顶部按钮。 */
  @Param topInset: number = 0;
  /** 横屏/矮卡片：压缩上下留白。 */
  @Param compact: boolean = false;
  @Event onViewChange: (view: string) => void = () => {};
  /** 当前进行中的目录拉取，点「目录」时等它完成再弹层。 */
  private tocTask: Promise<void> | undefined = undefined;
  private alive: boolean = true;
  /** 点章节：直接打开阅读/播放到该章。 */
  @Event onChapterTap: (chapter: Chapter, index: number) => void = () => {};
  /** 将记录位置交给现有阅读路由恢复。 */
  @Event onHistoryJump: (session: ReadingSession, location: SessionLocation) => void = () => {};
  @Local sessions: ReadingSession[] = [];
  @Local historyLoading: boolean = false;
  @Local historyFailed: boolean = false;
  private historyLoaded: boolean = false;

  /** 首次打开记录时加载，之后复用当前卡片缓存。 */
  private async openHistory(): Promise<void> {
    this.onViewChange('history');
    if (this.historyLoaded) return;
    await this.loadHistory();
  }

  private async loadHistory(): Promise<void> {
    const book = this.book;
    if (book === undefined) return;
    this.historyLoading = true;
    this.historyFailed = false;
    try {
      const sessions: ReadingSession[] = await ReadingSessionService.list([book.id], (): boolean => this.alive);
      if (!this.alive || this.book !== book) return;
      this.sessions = sessions;
      this.historyLoaded = true;
    } catch (_error) {
      this.historyFailed = true;
    } finally {
      this.historyLoading = false;
    }
  }

  private stampLabel(ms: number): string {
    const date = new Date(ms);
    return `${(date.getMonth() + 1).toString().padStart(2, '0')}.${date.getDate().toString().padStart(2, '0')} ` +
      `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  private positionLabel(location: SessionLocation): string {
    const percent = location.total > 0
      ? ` · ${Math.min(100, Math.floor(location.position / location.total * 100))}%` : '';
    return `${location.chapterTitle}${percent}`;
  }

  aboutToAppear(): void {
    this.alive = true;
    this.syncFavorite();
    // 让 200ms 的详情转场先完成，再拉目录，避免第一次点源时动画被后台任务拖顿。
    setTimeout((): void => {
      if (!this.alive || this.chapters.length > 0 || this.tocTask !== undefined) return;
      this.syncChapters();
    }, 220);
  }

  aboutToDisappear(): void {
    this.alive = false;
  }

  @Monitor('book')
  onBookChange(): void {
    this.syncFavorite();
    this.syncChapters();
  }

  private async syncFavorite(): Promise<void> {
    const book = this.book;
    if (book === undefined) return;
    try {
      const favorite: boolean = await PreferenceService.isFavorite(book.id);
      if (this.alive && this.book === book) this.favorite = favorite;
    } catch (_error) { /* 读取失败按未加入书架显示 */ }
  }

  /** 打开目录：先切视图显示 loading，目录在后台补齐，不再等待拉取完成。 */
  private openCatalog(): void {
    if (this.chapters.length === 0 && this.tocTask === undefined) {
      this.syncChapters();
    }
    this.onViewChange('catalog');
  }

  private async syncChapters(): Promise<void> {
    const book = this.book;
    this.tocLoading = true;
    this.tocFailed = false;
    const task = this.loadChapters(book);
    this.tocTask = task;
    try {
      await task;
    } finally {
      if (this.tocTask === task) this.tocTask = undefined;
    }
  }

  private async loadChapters(book: Book | undefined): Promise<void> {
    try {
      // 先看本地缓存，没有再从书源拉一次目录（与详情页同一套服务）。
      const cached: Chapter[] = book === undefined ? [] : await DataService.getChaptersForBook(book.id);
      if (!this.alive || this.book !== book) return;
      if (cached.length > 0) {
        this.applyChapters(cached);
        return;
      }
      if (book === undefined) return;
      const onUpdate = (loaded: Book): void => {
        if (!this.alive || this.book !== book || book.id !== loaded.id) return;
        this.applyChapters(loaded.chapters);
        this.tocLoading = loaded.tocComplete === false;
      };
      if (book.contentType === 'audio') await BookSourceService.loadAudioBook(book, onUpdate);
      else await BookSourceService.loadTextBook(book, onUpdate);
    } catch (_error) {
      this.tocFailed = true;
      this.chapterCount = -1;
    } finally {
      this.tocLoading = false;
    }
  }

  /** ChapterSheet 读的是 book.chapters，这里同时写回，保证弹层与计数同源。 */
  private applyChapters(chapters: Chapter[]): void {
    this.chapters = chapters;
    this.chapterData.setItems(chapters);
    this.chapterCount = chapters.length;
    const book = this.book;
    if (book !== undefined) book.chapters = chapters;
  }

  private async toggleFavorite(): Promise<void> {
    const book = this.book;
    if (book === undefined) return;
    try {
      await DataService.upsertCachedBook(book);
      await PreferenceService.toggleFavorite(book.id);
      this.favorite = await PreferenceService.isFavorite(book.id);
    } catch (_error) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ranking_open_failed') });
      } catch (_ignored) { /* 页面离开时不显示提示。 */ }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.view === 'info') {
        this.infoView()
      } else if (this.view === 'catalog') {
        this.catalogView()
      } else if (this.view === 'history') {
        this.historyView()
      } else {
        this.groupView()
      }


    }
    .width('100%').height('100%')
    .padding({ left: 20, right: 20, top: (this.compact ? 34 : 52) + this.topInset,
      bottom: this.view === 'catalog' || this.view === 'history' ? 16 :
        (this.compact ? 60 : 76) })
  }

  @Builder
  private infoView() {
    Column({ space: 10 }) {
      Column({ space: 6 }) {
        Text(this.book?.title ?? '').fontSize(19).fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TextPrimary).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 8 }) {
          Text(this.tocLoading ? '—' : $r('app.string.ranking_card_chapter_count', Math.max(0, this.chapterCount)))
            .fontSize(11).fontColor(AppTheme.TextSecondary)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .backgroundColor($r('app.color.ranking_match_surface'))
            .borderRadius(999)
          Text(this.book?.author ?? '').fontSize(11)
            .fontColor(AppTheme.TextSecondary).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)

      Row() {
        DetailActionItem({
          icon: $r('sys.symbol.bookshelf'),
          label: this.favorite ? $r('app.string.book_detail_action_in_shelf')
            : $r('app.string.book_detail_action_add_shelf'),
          active: this.favorite,
          onTap: (): void => { this.toggleFavorite(); }
        })
        DetailActionItem({ icon: $r('sys.symbol.list_bullet'),
          label: $r('app.string.book_detail_action_chapters'), active: false,
          onTap: (): void => { this.openCatalog(); } })
        DetailActionItem({ icon: $r('sys.symbol.arrow_left_arrow_right'),
          label: $r('app.string.book_detail_action_switch_source'), active: false,
          onTap: (): void => this.onSwitchSource() })
        DetailActionItem({ icon: $r('sys.symbol.folder'),
          label: $r('app.string.book_group_action'), active: false,
          onTap: (): void => { this.onViewChange('group'); } })
        DetailActionItem({ icon: $r('sys.symbol.calendar_fill'),
          label: $r('app.string.book_detail_action_read_record'), active: false,
          onTap: (): void => { this.openHistory(); } })
      }.width('100%')

      Column({ space: 4 }) {
        Text($r('app.string.book_detail_intro_label')).fontSize(11).fontColor(AppTheme.TextTertiary)
        Scroll() {
          Text(this.intro.length > 0 ? this.intro : (this.book?.intro ?? '—'))
            .fontSize(12).lineHeight(18).fontColor(AppTheme.TextSecondary)
            .width('100%')
        }
        .layoutWeight(1).width('100%').scrollBar(BarState.Off)
        .align(Alignment.TopStart)
      }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%').height('100%').alignItems(HorizontalAlign.Start)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
        .animation({ duration: AppMotion.Base, curve: AppCurve.Decelerate }),
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -4 }))
        .animation({ duration: AppMotion.Fast, curve: AppCurve.Accelerate })))
  }

  @Builder
  private catalogView() {
    Column({ space: 8 }) {
      Text(this.tocFailed ? $r('app.string.session_load_failed') : $r('app.string.book_detail_action_chapters'))
        .fontSize(12).fontColor(AppTheme.TextTertiary).width('100%')
        .onClick((): void => { if (this.tocFailed) this.syncChapters(); })
      if (this.tocLoading) {
        LoadingProgress().width(28).height(28).color(AppColor.Brand)
      }
      List({ space: 2 }) {
        LazyForEach(this.chapterData, (chapter: Chapter, index: number) => {
          ListItem() {
            Text(chapter.title).fontSize(13).fontColor(AppTheme.TextPrimary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%').padding({ top: 10, bottom: 10 })
              .onClick((): void => this.onChapterTap(chapter, index))
          }
        }, (chapter: Chapter): string => chapter.id)
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').alignItems(HorizontalAlign.Start)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
        .animation({ duration: AppMotion.Base, curve: AppCurve.Decelerate }),
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -4 }))
        .animation({ duration: AppMotion.Fast, curve: AppCurve.Accelerate })))
  }

  @Builder
  private groupView() {
    Column() {
      BookGroupSheet({
        initialGroup: this.book === undefined ? '' : (BookPresentation.get(this.book.id)?.group ?? ''),
        onConfirm: async (group: string, groups: string[]): Promise<void> => {
          const book = this.book;
          if (book === undefined) return;
          await DataService.upsertCachedBook(book);
          await PreferenceService.setBookGroup([book.id], group, groups);
          if (!await PreferenceService.isFavorite(book.id)) await PreferenceService.toggleFavorite(book.id);
          this.syncFavorite();
          this.onViewChange('info');
        }
      })
    }.width('100%').height('100%')
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
        .animation({ duration: AppMotion.Base, curve: AppCurve.Decelerate }),
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -4 }))
        .animation({ duration: AppMotion.Fast, curve: AppCurve.Accelerate })))
  }

  @Builder
  private historyView() {
    Column({ space: 8 }) {
      Text(this.historyFailed ? $r('app.string.session_load_failed')
        : $r('app.string.book_detail_action_read_record'))
        .fontSize(12).fontColor(AppTheme.TextTertiary).width('100%')
        .onClick((): void => { if (this.historyFailed) this.loadHistory(); })
      if (this.historyLoading) {
        LoadingProgress().width(28).height(28).color(AppColor.Brand)
      } else if (this.sessions.length === 0) {
        Text($r('app.string.session_empty')).fontSize(12).fontColor(AppTheme.TextTertiary)
      }
      List({ space: 12 }) {
        ForEach(this.sessions.slice(0, 20), (entry: ReadingSession) => {
          ListItem() {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Circle().width(8).height(8).fill(AppColor.Brand)
                Text(this.stampLabel(entry.startedAt)).fontSize(13)
                  .fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
                Blank()
                Text(entry.kind === 'audio' ? $r('app.string.search_type_audio')
                  : $r('app.string.search_type_text')).fontSize(10).fontColor(AppTheme.TextTertiary)
              }.width('100%')
              Text(this.positionLabel(entry.end)).fontSize(11).fontColor(AppTheme.TextSecondary)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              Button($r('app.string.session_jump_start')).fontSize(11).height(30).width('100%')
                .backgroundColor($r('app.color.ranking_match_surface'))
                .fontColor(AppColor.Brand)
                .borderRadius(999)
                .onClick((): void => this.onHistoryJump(entry, entry.start))
              Button($r('app.string.session_jump_end')).fontSize(11).height(30).width('100%')
                .backgroundColor(AppColor.Brand)
                .fontColor(AppColor.OnBrand)
                .borderRadius(999)
                .onClick((): void => this.onHistoryJump(entry, entry.end))
            }.width('100%').alignItems(HorizontalAlign.Start)
            .borderWidth({ left: 1 }).borderColor({ left: AppTheme.Divider })
            .padding({ left: 14 })
          }
        }, (entry: ReadingSession): string => entry.id)
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').alignItems(HorizontalAlign.Start)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
        .animation({ duration: AppMotion.Base, curve: AppCurve.Decelerate }),
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -4 }))
        .animation({ duration: AppMotion.Fast, curve: AppCurve.Accelerate })))
  }
}
