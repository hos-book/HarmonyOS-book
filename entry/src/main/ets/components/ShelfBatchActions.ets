import { AppColor, AppSpace } from '../theme/Theme';

export const SHELF_BATCH_ACTIONS_HEIGHT: number = 104;

/** 两行批量操作使用普通圆角矩形，按实际高度统一避让。 */
@ComponentV2
export struct ShelfBatchActions {
  @Param selectedCount: number = 0;
  @Param totalCount: number = 0;
  @Param allSelected: boolean = false;
  @Param busy: boolean = false;
  @Param hiddenShelf: boolean = false;
  @Event onSelectAll: () => void = () => {};
  @Event onDelete: () => void = () => {};
  @Event onGroup: () => void = () => {};
  @Event onHide: () => void = () => {};
  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Capsule, stateEffect: false }) {
            Row({ space: AppSpace.Xs }) {
              SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(20).fontColor([AppColor.Brand])
              Text(this.allSelected ? $r('app.string.shelf_deselect_all') : $r('app.string.shelf_select_all'))
                .fontSize(14).fontColor(AppColor.Brand).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
            }.width('100%').justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.None)
          }
          .height(44).layoutWeight(1).padding(0).backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Transparent)
          .enabled(!this.busy && this.totalCount > 0)
          .accessibilityText(this.allSelected ? $r('app.string.shelf_deselect_all') : $r('app.string.shelf_select_all'))
          .id('shelf-batch-select-all')
          .onClick((): void => this.onSelectAll())
          Divider().vertical(true).height(20).color($r('sys.color.comp_divider'))
          Button({ type: ButtonType.Capsule, stateEffect: false }) {
            Row({ space: AppSpace.Xs }) {
              SymbolGlyph($r('sys.symbol.folder')).fontSize(20).fontColor([AppColor.Brand])
              Text($r('app.string.book_group_action')).fontSize(14).fontColor(AppColor.Brand)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
            }.width('100%').justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.None)
          }.height(44).layoutWeight(1).padding(0).backgroundColor(Color.Transparent)
            .id('shelf-batch-group')
            .enabled(this.selectedCount > 0 && !this.busy).onClick((): void => this.onGroup())
        }.width('100%').height(44)
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Capsule, stateEffect: false }) {
            Row({ space: AppSpace.Xs }) {
              SymbolGlyph(this.hiddenShelf ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'))
                .fontSize(20).fontColor([AppColor.Brand])
              Text(this.hiddenShelf ? $r('app.string.shelf_unhide_action') : $r('app.string.shelf_hide_action'))
                .fontSize(14).fontColor(AppColor.Brand).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
            }.width('100%').justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.None)
          }.height(44).layoutWeight(1).padding(0).backgroundColor(Color.Transparent)
            .id('shelf-batch-hide')
            .enabled(this.selectedCount > 0 && !this.busy).onClick((): void => this.onHide())
          Divider().vertical(true).height(20).color($r('sys.color.comp_divider'))
          Button({ type: ButtonType.Capsule, stateEffect: false }) {
            Row({ space: AppSpace.Xs }) {
              SymbolGlyph($r('sys.symbol.trash')).fontSize(20).fontColor([$r('sys.color.ohos_id_color_warning')])
              Text($r('app.string.shelf_delete_count', this.selectedCount))
                .fontSize(14).fontColor($r('sys.color.ohos_id_color_warning')).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
            }.width('100%').justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.None)
          }
          .height(44).layoutWeight(1).padding(0).backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Transparent)
          .enabled(this.selectedCount > 0 && !this.busy)
          .opacity(this.selectedCount > 0 && !this.busy ? 1 : 0.4)
          .accessibilityText($r('app.string.shelf_delete_count', this.selectedCount))
          .id('shelf-batch-delete')
          .onClick((): void => this.onDelete())
        }.width('100%').height(44)
      }.width('100%').height(SHELF_BATCH_ACTIONS_HEIGHT).padding(AppSpace.Sm)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%').height(SHELF_BATCH_ACTIONS_HEIGHT)
    .backgroundColor($r('app.color.shelf_toolbar_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .borderRadius(12).clip(true)
  }
}
