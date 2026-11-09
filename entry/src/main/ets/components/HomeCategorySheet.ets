import { HomeSourceCategory } from '../service/rulesource/HomeSourceService';
import { HomeCategoryOverviewDataSource, HomeCategoryOverviewRow, HomeCategoryOverviewItem } from '../utils/HomeCategoryOverviewDataSource';
import { ImmersiveMenuHeader } from './ImmersiveMenuHeader';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';

@ComponentV2
export struct HomeCategorySheet {
  @Param categories: HomeSourceCategory[] = [];
  @Param loading: boolean = false;
  @Param selectedUrl: string = '';
  @Param selectedGroup: string = '';
  @Event onSelect: (category: HomeSourceCategory) => void = () => {};
  @Event onClose: () => void = () => {};
  @Local query: string = '';
  @Local resultCount: number = 0;
  private data: HomeCategoryOverviewDataSource = new HomeCategoryOverviewDataSource();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.refresh(); }

  @Monitor('categories', 'query')
  refresh(): void {
    this.data.setCategories(this.categories, this.query);
    this.resultCount = this.data.totalCount();
    try { this.scroller.scrollEdge(Edge.Top); } catch (_error) {}
  }

  private selected(item: HomeCategoryOverviewItem): boolean {
    return item.category.url === this.selectedUrl && item.category.group === this.selectedGroup;
  }

  private groupTitle(row: HomeCategoryOverviewRow): ResourceStr {
    if (!row.title) return $r('app.string.home_categories_all');
    return row.channel && row.channel !== row.title &&
      this.categories.some((category: HomeSourceCategory): boolean => category.group !== row.channel) ?
      `${row.channel} · ${row.title}` : row.title;
  }

  build() {
    Column({ space: AppSpace.Sm }) {
      ImmersiveMenuHeader({ title: $r('app.string.home_categories_all'), onClose: (): void => this.onClose() })
      Text($r('app.string.home_categories_count', this.categories.length))
        .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary')).width('100%')
        .padding({ left: AppSpace.Xs })
      Search({ value: this.query, placeholder: $r('app.string.home_categories_search') })
        .height(40).width('100%').fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_secondary')).borderRadius(AppRadius.Pill)
        .onChange((value: string): void => { this.query = value; })
      List({ space: AppSpace.Lg, scroller: this.scroller }) {
        if (this.resultCount === 0) {
          ListItem() {
            Column({ space: AppSpace.Sm }) {
              if (this.loading) { LoadingProgress().width(28).height(28).color(AppColor.Brand) }
              else {
                Text(this.query.trim() ? $r('app.string.home_categories_no_match') : $r('app.string.home_categories_empty'))
                  .fontSize(AppFont.Body).fontColor($r('sys.color.font_secondary'))
              }
            }.width('100%').padding({ top: 40, bottom: 40 })
          }
        }
        LazyForEach(this.data, (row: HomeCategoryOverviewRow) => {
          ListItem() {
            Column({ space: AppSpace.Sm }) {
              Text(this.groupTitle(row)).fontSize(AppFont.BodyL).fontColor($r('sys.color.font_primary'))
                .fontWeight(FontWeight.Medium)
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(row.categories, (item: HomeCategoryOverviewItem) => {
                  Button({ type: ButtonType.Capsule }) {
                    Row({ space: AppSpace.Xs }) {
                      Text(item.label || $r('app.string.home_categories_all_tag'))
                        .fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
                        .fontWeight(this.selected(item) ? FontWeight.Medium : FontWeight.Regular)
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
                      if (this.selected(item)) {
                        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([AppColor.Brand])
                          .flexShrink(0)
                      }
                    }.padding({ left: 12, right: 12, top: 8, bottom: 8 })
                      .constraintSize({ maxWidth: '100%', minHeight: 40 })
                      .borderRadius(AppRadius.Pill)
                  }
                    .padding(0)
                    .constraintSize({ maxWidth: '100%', minHeight: 40 })
                    .borderRadius(AppRadius.Pill).backgroundColor($r('sys.color.comp_background_tertiary'))
                    .clip(true)
                    .margin({ right: AppSpace.Sm, bottom: AppSpace.Sm }).flexShrink(0)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
                    .accessibilitySelected(this.selected(item))
                    .onClick((): void => this.onSelect(item.category))
                }, (item: HomeCategoryOverviewItem): string => item.key)
              }.width('100%')
            }.alignItems(HorizontalAlign.Start).width('100%')
          }
        }, (row: HomeCategoryOverviewRow): string => `${row.key}:${this.query}:${JSON.stringify(row.categories.map((item: HomeCategoryOverviewItem): string => item.key))}`)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring).padding({ top: AppSpace.Sm })
    }.width('100%').height('100%').padding(AppSpace.Xs)
  }
}
