import { InfinityLoadingIndicator } from './InfinityLoadingIndicator';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';

@ComponentV2
export struct ModelManagementRow {
  @Param itemId: string = '';
  @Param label: Resource = $r('app.string.model_pack_manage');
  @Param blocked: boolean = false;
  @Param removable: boolean = false;
  @Param showSwitch: boolean = false;
  @Param switchEnabled: boolean = false;
  @Param active: boolean = false;
  @Param expandable: boolean = false;
  @Param expanded: boolean = false;
  @Param processing: boolean = false;
  @Param cancellable: boolean = false;
  @Param status: ResourceStr = '';
  @Param importLabel: Resource = $r('app.string.model_pack_import');
  @Event onInfo: () => void = () => {};
  @Event onImport: () => void = () => {};
  @Event onRemove: () => void = () => {};
  @Event onCancel: () => void = () => {};
  @Event onActive: (active: boolean) => void = () => {};
  @Event onExpand: () => void = () => {};

  build() {
    Row({ space: AppSpace.Xs }) {
      Row({ space: AppSpace.Xs }) {
        Text(this.label).fontSize(AppFont.Body).fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TextPrimary).flexShrink(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick((): void => { if (this.expandable) this.onExpand(); })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(18).fontColor([AppTheme.TextSecondary])
        }.width(28).height(40).flexShrink(0).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.comic_plugin_description'))
          .onClick((): void => this.onInfo()).id(`model-management-info-${this.itemId}`)
        if (this.processing) {
          Text(this.status).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.layoutWeight(1)
      if (this.expandable) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(18).fontColor([AppTheme.TextSecondary])
        }.width(28).height(40).backgroundColor(Color.Transparent)
          .accessibilityText(this.expanded ? $r('app.string.source_collapse') : $r('app.string.source_expand'))
          .onClick((): void => this.onExpand()).id(`model-management-expand-${this.itemId}`)
      }
      Row() {
        if (this.showSwitch) {
          Toggle({ type: ToggleType.Switch, isOn: this.active }).selectedColor(AppColor.Brand)
            .width(32).height(20).enabled(this.switchEnabled && !this.blocked)
            .accessibilityText(this.label).onChange((active: boolean): void => this.onActive(active))
            .id(`model-management-toggle-${this.itemId}`)
        } else if (this.processing) {
          InfinityLoadingIndicator({ indicatorSize: 18 })
        }
      }.width(32).height(40).justifyContent(FlexAlign.Center)
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(this.processing && this.cancellable ? $r('sys.symbol.xmark') : $r('sys.symbol.folder'))
          .fontSize(20).fontColor([AppColor.Brand])
      }.width(32).height(40).backgroundColor(Color.Transparent)
        .enabled(this.processing ? this.cancellable : !this.blocked)
        .accessibilityText(this.processing && this.cancellable ? $r('app.string.common_cancel') : this.importLabel)
        .onClick((): void => {
          if (this.processing) this.onCancel();
          else this.onImport();
        }).id(`model-management-import-${this.itemId}`)
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([AppTheme.TextSecondary])
      }.width(32).height(40).backgroundColor(Color.Transparent)
        .enabled(this.removable && !this.blocked && !this.processing)
        .accessibilityText($r('app.string.comic_plugin_remove'))
        .onClick((): void => this.onRemove()).id(`model-management-remove-${this.itemId}`)
    }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Sm, top: AppSpace.Sm, bottom: AppSpace.Sm })
      .borderRadius(AppRadius.Lg).backgroundColor(AppTheme.Surface)
  }
}
