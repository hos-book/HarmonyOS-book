import { RankingBoard } from '../model/Ranking';
import { RankingPreferences } from '../service/ranking/RankingPreferences';
import { RankingService } from '../service/ranking/RankingService';
import { HomeRecommendationDataSource } from '../utils/HomeRecommendationDataSource';
import { AppColor, AppTheme } from '../theme/Theme';

@ComponentV2
export struct RankingBoardOrderComponent {
  @Event onClose: () => void = (): void => {};
  @Local boards: RankingBoard[] = [];
  @Local saving: boolean = false;
  @Local loaded: boolean = false;
  @Local failed: boolean = false;
  private source: HomeRecommendationDataSource<RankingBoard> = new HomeRecommendationDataSource();
  private defaults: RankingBoard[] = [];

  aboutToAppear(): void { this.load(); }

  private async load(): Promise<void> {
    try {
      const settings = await RankingPreferences.load();
      const all = RankingService.boards();
      this.defaults = [];
      for (const platform of settings) {
        this.defaults = this.defaults.concat(all.filter((board: RankingBoard): boolean => board.platformId === platform.id));
      }
      this.boards = RankingPreferences.orderBoards(this.defaults, await RankingPreferences.loadBoardOrder());
      this.source.setItems(this.boards);
      this.loaded = true; this.failed = false;
    } catch (_error) { this.failed = true; }
  }

  private async move(from: number, to: number): Promise<void> {
    if (!this.loaded || this.saving) return;
    if (from === to || from < 0 || to < 0 || from >= this.boards.length || to >= this.boards.length) return;
    const next = this.boards.slice();
    next.splice(to, 0, next.splice(from, 1)[0]);
    await this.save(next, false);
  }

  private async save(next: RankingBoard[], reset: boolean): Promise<void> {
    if (!this.loaded || this.saving) return;
    this.saving = true;
    const previous = this.boards;
    // 原生拖拽落位前同步更新数据，保存失败才恢复旧顺序。
    this.boards = next;
    this.source.setItems(next);
    try {
      await RankingPreferences.saveBoardOrder(reset ? [] : next.map((board: RankingBoard): string => board.id));
    } catch (_error) {
      this.boards = previous;
      this.source.setItems(previous);
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ranking_settings_save_failed') });
    } finally { this.saving = false; }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text($r('app.string.ranking_board_order_title')).fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TextPrimary).layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([AppTheme.TextSecondary])
        }.width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.ranking_order_reset')).enabled(this.loaded && !this.saving)
          .onClick((): void => { this.save(this.defaults.slice(), true); })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([AppTheme.TextPrimary])
        }.width(40).height(40).backgroundColor(AppTheme.Surface)
          .accessibilityText($r('app.string.ranking_order_close')).onClick((): void => this.onClose())
      }.width('100%').padding({ left: 20, right: 16, top: 12, bottom: 8 })
      Text($r('app.string.ranking_board_order_desc')).fontSize(13).fontColor(AppTheme.TextSecondary).width('100%')
        .padding({ left: 20, right: 20, bottom: 16 })
      if (!this.loaded && !this.failed) {
        LoadingProgress().width(28).height(28).color(AppColor.Brand).margin(20)
      }
      if (this.failed) {
        Button($r('app.string.ranking_settings_retry')).onClick((): void => { this.load(); })
      }
      List() {
        LazyForEach(this.source, (board: RankingBoard) => {
          ListItem() {
            Row({ space: 16 }) {
              Column({ space: 4 }) {
                Text(board.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(board.platformName).fontSize(12).fontColor(AppTheme.TextSecondary).maxLines(1)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              SymbolGlyph($r('sys.symbol.line_3_horizontal')).fontSize(21).fontColor([AppTheme.TextTertiary])
                .accessibilityText($r('app.string.ranking_board_order_desc'))
            }.width('100%').constraintSize({ minHeight: 68 }).padding({ left: 16, right: 16, top: 10, bottom: 10 })
          }.backgroundColor($r('sys.color.comp_background_primary')).borderRadius(12)
        }, (board: RankingBoard): string => board.id)
          .onMove((from: number, to: number): void => { this.move(from, to); })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).cachedCount(2).enabled(!this.saving)
        .divider({ strokeWidth: 0.5, color: AppColor.Divider, startMargin: 16, endMargin: 16 })
        .padding({ left: 16, right: 16 }).clip(true)
    }.width('100%').height('100%').padding({ bottom: 24 })
      .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
