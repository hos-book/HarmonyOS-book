import { HomeSourceCategory } from '../service/rulesource/HomeSourceService';
import { HomeCategoryOverviewDataSource, HomeCategoryOverviewRow, HomeCategoryOverviewItem } from '../utils/HomeCategoryOverviewDataSource';
import { ImmersiveCircleButton } from './ImmersiveCircleButton';
import { AppColor, AppFont, AppMaterial, AppRadius, AppSpace, AppTheme, HomeTheme } from '../theme/Theme';

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
      Row() {
        Column({ space: 3 }) {
          Text($r('app.string.home_categories_all')).fontSize(AppFont.TitleL)
            .fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
          Text($r('app.string.home_categories_count', this.categories.length))
            .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        ImmersiveCircleButton({ icon: $r('sys.symbol.xmark'),
          label: $r('app.string.home_categories_close'), onPress: (): void => this.onClose() })
      }.width('100%')
      Search({ value: this.query, placeholder: $r('app.string.home_categories_search') })
        .height(40).width('100%').fontColor(AppTheme.TextPrimary)
        .placeholderColor(AppTheme.TextSecondary).borderRadius(AppRadius.Pill)
        .onChange((value: string): void => { this.query = value; })
      List({ space: AppSpace.Lg, scroller: this.scroller }) {
        if (this.resultCount === 0) {
          ListItem() {
            Column({ space: AppSpace.Sm }) {
              if (this.loading) { LoadingProgress().width(28).height(28).color(AppColor.Brand) }
              else {
                Text(this.query.trim() ? $r('app.string.home_categories_no_match') : $r('app.string.home_categories_empty'))
                  .fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
              }
            }.width('100%').padding({ top: 40, bottom: 40 })
          }
        }
        LazyForEach(this.data, (row: HomeCategoryOverviewRow) => {
          ListItem() {
            Column({ space: AppSpace.Sm }) {
              Text(this.groupTitle(row)).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
                .fontWeight(FontWeight.Medium)
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(row.categories, (item: HomeCategoryOverviewItem) => {
                  Button({ type: ButtonType.Capsule }) {
                    Text(item.label || $r('app.string.home_categories_all_tag'))
                      .fontSize(14).fontColor(this.selected(item) ? HomeTheme.Accent : AppTheme.TextPrimary)
                      .fontWeight(this.selected(item) ? FontWeight.Medium : FontWeight.Regular)
                      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                      .constraintSize({ maxWidth: '100%', minHeight: 40 })
                      // 独立覆色层避免被外层原生材质的透明背景重置。
                      .backgroundColor(this.selected(item) ? HomeTheme.AccentSoft : AppColor.GlassSheetControlTint)
                      .borderRadius(AppRadius.Pill)
                  }
                    .padding(0)
                    .constraintSize({ maxWidth: '100%', minHeight: 40 })
                    .borderRadius(AppRadius.Pill).backgroundColor(AppColor.GlassControlFallback)
                    .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveThin))
                    .border({ width: 0.5, color: this.selected(item) ? HomeTheme.Accent : AppColor.GlassStroke })
                    .clip(true)
                    .margin({ right: 8, bottom: 8 }).flexShrink(0)
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
    }.width('100%').height('100%').padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Sm, bottom: AppSpace.Lg })
  }
}
