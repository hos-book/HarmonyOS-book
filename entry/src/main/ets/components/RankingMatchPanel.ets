import { RankingBook } from '../model/Ranking';
import { BookMatchService, RankingMatch, RankingMatchProgress } from '../service/ranking/BookMatchService';
import { AppColor, AppTheme } from '../theme/Theme';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';
import { ImmersiveTabComponent } from './ImmersiveTabComponent';

/**
 * 卡片内的书源匹配面板：卡片展开后整块白底内容。
 * 只负责搜索、筛选和选中，确认打开交给外层（导航无法在组件内完成）。
 */
@ComponentV2
export struct RankingMatchPanel {
  @Require @Param book: RankingBook;
  /** 当前选中的结果（sourceUrl + bookUrl），由外层持有，按钮也要读它。 */
  @Param selectedKey: string = '';
  @Param refreshToken: number = 0;
  /** 卡片顶到屏幕最上沿后，内容整体下移状态栏高度，避开顶部按钮。 */
  @Param topInset: number = 0;
  /** 横屏/矮卡片：压缩上下留白，把高度让给结果列表。 */
  @Param compact: boolean = false;
  @Event onSelect: (match: RankingMatch) => void = () => {};
  @Event onManageSources: () => void = () => {};
  @Local keyword: string = '';
  @Local matchType: string = '';
  @Local searching: boolean = false;
  @Local sourceTotal: number = -1;
  @Local completed: number = 0;
  @Local failed: number = 0;
  @Local matchesCount: number = 0;
  /** 分类计数：和状态行一样用标量，避免数组长度不刷新。 */
  @Local audioCount: number = 0;
  @Local textCount: number = 0;
  @Local comicCount: number = 0;
  @Local matchError: boolean = false;
  /** 必须是状态：标签上的计数要跟着结果刷新。 */
  @Local allMatches: RankingMatch[] = [];
  private matchData: HomeRecommendationDataSource<RankingMatch> = new HomeRecommendationDataSource<RankingMatch>();
  private matcher: BookMatchService = new BookMatchService();
  private generation: number = 0;
  private alive: boolean = true;

  aboutToAppear(): void {
    this.alive = true;
    this.keyword = BookMatchService.keyword(this.book);
    this.search();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.generation++;
    this.matcher.cancel();
  }

  @Monitor('book')
  onBookChange(): void {
    this.keyword = BookMatchService.keyword(this.book);
    this.matchType = '';
    this.search();
  }

  @Monitor('refreshToken')
  onSourcesReturned(): void {
    if (this.alive) this.search();
  }

  private keyOf(match: RankingMatch): string {
    return `${match.book.sourceUrl}\u001f${match.book.bookUrl}`;
  }

  private search(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined || this.keyword.trim().length === 0) return;
    const generation = ++this.generation;
    this.searching = true;
    this.matchError = false;
    this.sourceTotal = -1;
    this.completed = 0;
    this.failed = 0;
    this.matchesCount = 0;
    this.allMatches = [];
    this.matchData.setItems([]);
    this.matcher.search(context, this.book, this.keyword.trim(), (progress: RankingMatchProgress): void => {
      if (!this.alive || generation !== this.generation) return;
      this.sourceTotal = progress.total;
      this.completed = progress.completed;
      this.failed = progress.failed;
      this.allMatches = progress.matches.slice();
      this.filter();
    }).catch((): void => {
      if (this.alive && generation === this.generation) this.matchError = true;
    }).finally((): void => {
      if (this.alive && generation === this.generation) this.searching = false;
    });
  }

  private filter(): void {
    const visible: RankingMatch[] = this.allMatches.filter((match: RankingMatch): boolean =>
      this.matchType.length === 0 || match.book.contentType === this.matchType);
    this.matchesCount = visible.length;
    this.audioCount = this.allMatches.filter((match: RankingMatch): boolean => match.book.contentType === 'audio').length;
    this.textCount = this.allMatches.filter((match: RankingMatch): boolean => match.book.contentType === 'text').length;
    this.comicCount = this.allMatches.filter((match: RankingMatch): boolean => match.book.contentType === 'comic').length;
    this.matchData.setItems(visible);
  }

  private selectType(type: string): void {
    if (type === this.matchType) return;
    this.matchType = type;
    this.filter();
  }

  private statusText(): Resource {
    if (this.searching) return $r('app.string.ranking_matching', this.completed, Math.max(0, this.sourceTotal));
    if (this.sourceTotal === 0) return $r('app.string.ranking_no_sources');
    if (this.matchesCount === 0) {
      return this.matchError || this.failed > 0 ? $r('app.string.ranking_match_failed') : $r('app.string.ranking_no_match');
    }
    return $r('app.string.ranking_choose_version');
  }

  /** 直接解析成字符串：避免 $r 带参在重建时不刷新。 */
  private countLabel(name: Resource, count: number): string {
    const context = this.getUIContext().getHostContext();
    try {
      if (context !== undefined) return context.resourceManager.getStringSync(name.id, count);
    } catch (_error) { /* 解析失败退回数字 */ }
    return String(count);
  }

  @Builder
  private typeTab(type: string) {
    // 计数在 builder 体内读取：@Builder 的参数是值快照，传进来不会随状态更新。
    Text(this.tabLabel(type))
      .fontSize(13)
      .fontColor(this.matchType === type ? AppColor.Brand : AppTheme.TextSecondary)
      .fontWeight(this.matchType === type ? FontWeight.Medium : FontWeight.Normal)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(999)
      .backgroundColor(this.matchType === type ? AppColor.BrandSoft : Color.Transparent)
      .onClick((): void => this.selectType(type))
  }

  private tabLabel(type: string): string {
    if (type === 'audio') return this.countLabel($r('app.string.shelf_filter_audio_count'), this.audioCount);
    if (type === 'text') return this.countLabel($r('app.string.shelf_filter_text_count'), this.textCount);
    if (type === 'comic') return this.countLabel($r('app.string.shelf_filter_comic_count'), this.comicCount);
    return this.countLabel($r('app.string.shelf_filter_all_count'), this.matchesCount);
  }

  build() {
    Column({ space: this.compact ? 6 : 10 }) {
      // 书名在左、搜索在右：把纵向空间让给结果列表
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(this.book.title).fontSize(15).fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TextPrimary).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.book.author || this.book.narrator).fontSize(10)
            .fontColor(AppTheme.TextSecondary).maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)

        Search({ value: this.keyword, placeholder: $r('app.string.ranking_search_keyword') })
          .width(186).height(this.compact ? 34 : 40)
          .textFont({ size: 13 }).placeholderFont({ size: 13 })
          .searchButton($r('app.string.ranking_search'), { fontColor: AppTheme.TextPrimary, fontSize: 13 })
          .onChange((text: string): void => { this.keyword = text; })
          .onSubmit((): void => this.search())
      }.width('100%').alignItems(VerticalAlign.Center)

      Scroll() {
        Row({ space: 8 }) {
          this.typeTab('')
          this.typeTab('audio')
          this.typeTab('text')
          this.typeTab('comic')
        }.height(this.compact ? 30 : 36)
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

      Text(this.statusText()).fontSize(11).fontColor(AppTheme.TextTertiary)
        .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

      List({ space: 8 }) {
        LazyForEach(this.matchData, (match: RankingMatch) => {
          ListItem() {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Text(match.sourceName).fontSize(11).fontColor(AppTheme.TextSecondary)
                  .maxLines(1).layoutWeight(1)
                Text(match.book.contentType === 'comic' ? $r('app.string.comic_type')
                  : match.book.contentType === 'text' ? $r('app.string.search_type_text')
                  : $r('app.string.search_type_audio'))
                  .fontSize(10).fontColor(AppTheme.TextTertiary)
                if (match.remembered) {
                  Text($r('app.string.ranking_last_choice')).fontSize(10).fontColor(AppTheme.TextTertiary)
                }
              }.width('100%')
              Text(match.book.title).fontSize(15).fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TextPrimary).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(match.book.author || match.book.intro).fontSize(11).maxLines(1)
                .fontColor(AppTheme.TextSecondary).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%').padding(12).alignItems(HorizontalAlign.Start)
            .borderRadius(14)
            .backgroundColor($r('app.color.ranking_match_surface'))
            .border({ width: this.selectedKey === this.keyOf(match) ? 2 : 1,
              color: this.selectedKey === this.keyOf(match) ? AppColor.Brand : $r('app.color.ranking_match_border') })
            .onClick((): void => this.onSelect(match))
          }
        }, (match: RankingMatch): string => this.keyOf(match))
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off).cachedCount(4)
      // 避让属于滚动内容，列表继续绘制到悬浮按钮后方。
      .contentEndOffset(68)

      if (!this.searching && this.matchesCount === 0) {
        Button($r('app.string.ranking_manage_sources'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontColor(AppTheme.TextPrimary).height(36)
          .onClick((): void => this.onManageSources())
      }
    }
    .width('100%').height('100%')
    // 横屏/矮卡片压缩顶部按钮区，把高度让给列表
    .padding({ left: 20, right: 20, top: (this.compact ? 34 : 52) + this.topInset,
      bottom: 0 })
    .alignItems(HorizontalAlign.Start)
  }
}
