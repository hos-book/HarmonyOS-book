import { HdsTabs } from '@kit.UIDesignKit';
import { AppColor, AppFont, AppSpace } from '../theme/Theme';
import { HdsCompat } from '../utils/HdsCompat';
import { PlatformCompat } from '../utils/PlatformCompat';

class ShelfBatchClip implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(node: CommonAttribute): void {
    if (PlatformCompat.floatingTabs) node.borderRadius(28, RenderStrategy.OFFSCREEN);
    else node.borderRadius(28);
    node.clip(true);
  }
}

/** 与 ReaderSpeechFloating 的“听”按钮一致，由原生 HDS 浮动栏承载沉浸光感。 */
@ComponentV2
export struct ShelfBatchActions {
  @Param selectedCount: number = 0;
  @Param totalCount: number = 0;
  @Param allSelected: boolean = false;
  @Param busy: boolean = false;
  @Event onSelectAll: () => void = () => {};
  @Event onDelete: () => void = () => {};
  @Event onGroup: () => void = () => {};
  @Local measuredWidth: number = 320;

  @Builder
  materialContent() {
    Stack().width('100%').height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (PlatformCompat.floatingTabs) {
        HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
          TabContent() { Column() }.height(56).tabBar(this.materialContent())
        }
        .barMode(BarMode.Fixed).barHeight(56).barOverlap(true)
        .barFloatingStyle({
          barWidth: { smallWidth: this.measuredWidth, mediumWidth: this.measuredWidth, largeWidth: this.measuredWidth },
          systemMaterialEffect: HdsCompat.material,
          lightColor: AppColor.Brand,
          barSideMargin: 0, barBottomMargin: 0,
          gradientMask: { maskColor: '#00000000', maskHeight: 56 },
          adaptToHandedness: false, thermoCtrl: true, barOpacity: 1
        })
        .scrollable(false).onContentWillChange((): boolean => false)
        .width('100%').height(56)
      } else {
        Row().width('100%').height(56)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
          .border({ width: 0.5, color: $r('sys.color.comp_divider') })
          .borderRadius(28)
      }
      Row({ space: AppSpace.Sm }) {
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row({ space: AppSpace.Xs }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(20).fontColor([AppColor.Brand])
            Text(this.allSelected ? $r('app.string.shelf_deselect_all') : $r('app.string.shelf_select_all'))
              .fontSize(AppFont.Body).fontColor(AppColor.Brand)
          }.hitTestBehavior(HitTestMode.None)
        }
        .height(44).layoutWeight(1).padding(0).backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Transparent)
        .enabled(!this.busy && this.totalCount > 0)
        .accessibilityText(this.allSelected ? $r('app.string.shelf_deselect_all') : $r('app.string.shelf_select_all'))
        .onClick((): void => this.onSelectAll())
        Divider().vertical(true).height(20).color($r('sys.color.comp_divider'))
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row({ space: AppSpace.Xs }) {
            SymbolGlyph($r('sys.symbol.folder')).fontSize(20).fontColor([AppColor.Brand])
            Text($r('app.string.book_group_action')).fontSize(AppFont.Body).fontColor(AppColor.Brand)
          }.hitTestBehavior(HitTestMode.None)
        }.height(44).layoutWeight(1).padding(0).backgroundColor(Color.Transparent)
          .enabled(this.selectedCount > 0 && !this.busy).onClick((): void => this.onGroup())
        Divider().vertical(true).height(20).color($r('sys.color.comp_divider'))
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row({ space: AppSpace.Xs }) {
            SymbolGlyph($r('sys.symbol.trash')).fontSize(20).fontColor([$r('sys.color.ohos_id_color_warning')])
            Text($r('app.string.shelf_delete_count', this.selectedCount))
              .fontSize(AppFont.Body).fontColor($r('sys.color.ohos_id_color_warning'))
          }.hitTestBehavior(HitTestMode.None)
        }
        .height(44).layoutWeight(1).padding(0).backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Transparent)
        .enabled(this.selectedCount > 0 && !this.busy)
        .opacity(this.selectedCount > 0 && !this.busy ? 1 : 0.4)
        .accessibilityText($r('app.string.shelf_delete_count', this.selectedCount))
        .onClick((): void => this.onDelete())
      }.width('100%').height(56).padding({ left: AppSpace.Sm, right: AppSpace.Sm })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%').height(56)
    .attributeModifier(new ShelfBatchClip())
    .onSizeChange((_previous: SizeOptions, current: SizeOptions): void => {
      const width = Number(current.width);
      if (width > 0 && Math.abs(width - this.measuredWidth) > 0.5) this.measuredWidth = width;
    })
  }
}
