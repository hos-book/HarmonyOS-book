import { HdsTabs, HdsTabsFloatingStyle } from '@kit.UIDesignKit';
import { CompatibleTabsModifier, HdsCompat } from '../utils/HdsCompat';
import { PlatformCompat } from '../utils/PlatformCompat';
import { AppFont } from '../theme/Theme';

class ChapterJumpHintClip implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(node: CommonAttribute): void {
    if (PlatformCompat.floatingTabs) node.borderRadius(28, RenderStrategy.OFFSCREEN);
    else node.borderRadius(28);
    node.clip(true);
  }
}

/** 文字和漫画共用的章节预览、撤销入口。宿主需保留实际布局高度以保证按钮命中。 */
@ComponentV2
export struct ReaderChapterJumpHint {
  @Param availableWidth: number = 300;
  @Param chapterTitle: string = '';
  @Param percent: string = '';
  @Param undoEnabled: boolean = false;
  @Param idPrefix: string = 'reader';
  @Event onUndo: () => void = (): void => {};

  private floatingStyle(): HdsTabsFloatingStyle | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    const width = Math.min(300, this.availableWidth);
    return {
      barWidth: { smallWidth: width, mediumWidth: width, largeWidth: width },
      barSideMargin: 0, barBottomMargin: 0,
      gradientMask: { maskColor: Color.Transparent, maskHeight: 56 },
      systemMaterialEffect: HdsCompat.adaptiveMaterial,
      adaptToHandedness: false
    };
  }

  @Builder
  materialContent(): void { Row().width('100%').height(56) }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (HdsCompat.materialSupported) {
        HdsTabs() {
          TabContent() {}.tabBar(this.materialContent())
        }.width('100%').height(56).barPosition(BarPosition.End).barMode(BarMode.Fixed)
          .barHeight(56).barOverlap(true).scrollable(false)
          .attributeModifier(new CompatibleTabsModifier(this.floatingStyle(), 56))
          .backgroundColor(Color.Transparent).onContentWillChange((): boolean => false)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
      } else {
        Row().width('100%').height(56)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN).hitTestBehavior(HitTestMode.None)
      }
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(this.chapterTitle).fontSize(AppFont.Caption).fontColor($r('sys.color.font_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.percent).fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
        Divider().vertical(true).height(28).color($r('sys.color.comp_divider'))
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.undo')).fontSize(22).fontColor([$r('sys.color.font_primary')])
        }.width(48).height(48).padding(0).backgroundColor(Color.Transparent)
          .enabled(this.undoEnabled).opacity(this.undoEnabled ? 1 : 0.4)
          .accessibilityText($r('app.string.reader_chapter_jump_undo'))
          .id(`${this.idPrefix}-chapter-jump-undo`).onClick((): void => this.onUndo())
      }.width('100%').height(56).padding({ left: 18, right: 4 })
    }.width(Math.min(300, this.availableWidth)).height(56)
      .attributeModifier(new ChapterJumpHintClip()).hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
      .id(`${this.idPrefix}-chapter-jump-hint`)
  }
}
