import { HdsTabs } from '@kit.UIDesignKit';
import { PlatformCompat } from '../utils/PlatformCompat';
import { HdsCompat } from '../utils/HdsCompat';

class SpeechCircleClip implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(node: CommonAttribute): void {
    if (PlatformCompat.floatingTabs) node.borderRadius(24, RenderStrategy.OFFSCREEN);
    else node.borderRadius(24);
    node.clip(true);
  }
}

/** HDS 原生浮动栏承载圆形材质，与阅读底栏使用相同渲染路径。 */
@ComponentV2
export struct ReaderSpeechFloating {
  @Param playing: boolean = false;
  @Event onOpen: () => void = () => {};

  @Builder
  materialContent() {
    Stack().width('100%').height('100%')
  }

  @Builder
  label() {
    Text($r('app.string.reader_listen_short'))
      .fontSize(22).fontWeight(this.playing ? FontWeight.Bold : FontWeight.Medium)
      .fontColor($r('sys.color.font_primary')).hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (PlatformCompat.floatingTabs) {
        HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
          TabContent() { Column() }.height(48).tabBar(this.materialContent())
        }
        .barMode(BarMode.Fixed).barHeight(48).barOverlap(true)
        .barFloatingStyle({
          barWidth: { smallWidth: 48, mediumWidth: 48, largeWidth: 48 },
          systemMaterialEffect: HdsCompat.material,
          barSideMargin: 0, barBottomMargin: 0,
          gradientMask: { maskColor: '#00000000', maskHeight: 48 },
          adaptToHandedness: false, thermoCtrl: true, barOpacity: 1
        })
        .scrollable(false).onContentWillChange((): boolean => false)
        .width(48).height(48)
        Button({ type: ButtonType.Circle, stateEffect: false }) { this.label() }
          .width(48).height(48).padding(0).backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Transparent)
          .accessibilityText($r('app.string.tts_title')).onClick((): void => this.onOpen())
          .accessibilityDescription($r('app.string.tts_entry_hint'))
      } else {
        Button({ type: ButtonType.Circle }) { this.label() }
          .width(48).height(48).padding(0).backgroundColor($r('sys.color.comp_background_primary'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
          .border({ width: 0.5, color: $r('sys.color.comp_divider') })
          .accessibilityText($r('app.string.tts_title')).onClick((): void => this.onOpen())
          .accessibilityDescription($r('app.string.tts_entry_hint'))
      }
    }.width(48).height(48).attributeModifier(new SpeechCircleClip()).id('reader-listen')
  }
}
