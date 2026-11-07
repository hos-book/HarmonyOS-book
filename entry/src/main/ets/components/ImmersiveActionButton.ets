import { HdsTabs } from '@kit.UIDesignKit';
import { AppFont, AppColor } from '../theme/Theme';
import { PlatformCompat } from '../utils/PlatformCompat';
import { HdsCompat } from '../utils/HdsCompat';

class ImmersiveActionClip implements AttributeModifier<CommonAttribute> {
  constructor(radius: number) { this.radius = radius; }
  private radius: number;

  applyNormalAttribute(node: CommonAttribute): void {
    if (PlatformCompat.floatingTabs) node.borderRadius(this.radius, RenderStrategy.OFFSCREEN);
    else node.borderRadius(this.radius);
    node.clip(true);
  }
}

/** HDS 原生沉浸表面；触点光晕独立跟随应用主题色，避免组件级材质兼容差异。 */
@ComponentV2
export struct ImmersiveActionButton {
  @Param label: Resource = $r('app.string.appearance_apply');
  @Param icon: Resource | null = null;
  @Param buttonHeight: number = 40;
  @Param textSize: number = AppFont.Caption;
  @Event onPress: () => void = () => {};
  @Local surfaceWidth: number = 72;
  @Local touching: boolean = false;
  @Local touchX: number = 36;
  @Local touchY: number = 20;

  private updateTouch(event: TouchEvent): void {
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.touching = false;
      return;
    }
    if (event.touches.length > 0) {
      this.touchX = Math.max(0, Math.min(this.surfaceWidth, event.touches[0].x));
      this.touchY = Math.max(0, Math.min(this.buttonHeight, event.touches[0].y));
      this.touching = true;
    }
  }

  @Builder
  materialContent() {
    Stack().width('100%').height('100%')
  }

  @Builder
  buttonLabel() {
    Row({ space: 8 }) {
      if (this.icon !== null) {
        SymbolGlyph(this.icon).fontSize(18).fontColor([$r('sys.color.font_primary')])
      }
      Text(this.label).fontSize(this.textSize).fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary')).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (HdsCompat.materialSupported) {
        HdsTabs({ barPosition: BarPosition.End, index: 0 }) {
          TabContent() { Column() }.height(this.buttonHeight).tabBar(this.materialContent())
        }
        .barMode(BarMode.Fixed).barHeight(this.buttonHeight).barOverlap(true)
        .barFloatingStyle({
          barWidth: { smallWidth: this.surfaceWidth, mediumWidth: this.surfaceWidth,
            largeWidth: this.surfaceWidth },
          systemMaterialEffect: HdsCompat.material,
          barSideMargin: 0, barBottomMargin: 0,
          gradientMask: { maskColor: '#00000000', maskHeight: this.buttonHeight },
          adaptToHandedness: false, thermoCtrl: true, barOpacity: 1
        })
        .scrollable(false).onContentWillChange((): boolean => false)
        .width('100%').height(this.buttonHeight)
        Button({ type: ButtonType.Capsule, stateEffect: false }) { this.buttonLabel() }
          .width('100%').height(this.buttonHeight).padding({ left: 4, right: 4 }).backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Transparent)
          .accessibilityText(this.label)
          .onTouch((event: TouchEvent): void => this.updateTouch(event))
          .onClick((): void => this.onPress())
      } else {
        Button({ type: ButtonType.Capsule }) { this.buttonLabel() }
          .width('100%').height(this.buttonHeight).padding({ left: 4, right: 4 })
          .backgroundColor($r('sys.color.comp_background_primary'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
          .border({ width: 0.5, color: $r('sys.color.comp_divider') })
          .accessibilityText(this.label)
          .onTouch((event: TouchEvent): void => this.updateTouch(event))
          .onClick((): void => this.onPress())
      }
      Row().width('100%').height(this.buttonHeight).borderRadius(this.buttonHeight / 2)
        .radialGradient({ center: [this.touchX, this.touchY], radius: 52,
          colors: [[AppColor.BrandSoft, 0], [Color.Transparent, 1]] })
        .opacity(this.touching ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }.width('100%').height(this.buttonHeight).attributeModifier(new ImmersiveActionClip(this.buttonHeight / 2))
      .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions): void => {
        const width = Number(newSize.width);
        if (width > 0 && Math.abs(width - this.surfaceWidth) > 0.5) this.surfaceWidth = width;
      })
  }
}
