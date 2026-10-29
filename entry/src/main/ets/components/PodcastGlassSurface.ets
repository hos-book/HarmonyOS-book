import { HdsTabs } from '@kit.UIDesignKit';
import { AppColor, AppMaterial } from '../theme/Theme';
import { HdsCompat } from '../utils/HdsCompat';
import { PlatformCompat } from '../utils/PlatformCompat';

class PodcastSurfaceClip implements AttributeModifier<CommonAttribute> {
  private radius: number;
  constructor(radius: number) { this.radius = radius; }
  applyNormalAttribute(node: CommonAttribute): void {
    if (PlatformCompat.floatingTabs) node.borderRadius(this.radius, RenderStrategy.OFFSCREEN);
    else node.borderRadius(this.radius);
    node.clip(true);
  }
}

/** Search uses the same native immersive carrier and clipping as the app's circular controls. */
@ComponentV2
export struct PodcastSearchSurface {
  @Param surfaceWidth: number = 260;
  @Param surfaceHeight: number = 42;
  @BuilderParam content: () => void = this.empty;
  @Builder empty() { Row() }
  build() {
    Stack() {
      if (PlatformCompat.floatingTabs) {
        HdsTabs({ index: 0, barPosition: BarPosition.End }) {
          TabContent() { Column() }.height(this.surfaceHeight).tabBar(this.empty())
        }.barMode(BarMode.Fixed).barHeight(this.surfaceHeight).barOverlap(true)
          .barFloatingStyle({ barWidth: { smallWidth: this.surfaceWidth, mediumWidth: this.surfaceWidth, largeWidth: this.surfaceWidth },
            barSideMargin: 0, barBottomMargin: 0, systemMaterialEffect: HdsCompat.material,
            lightColor: AppColor.Brand, gradientMask: { maskColor: '#00000000', maskHeight: this.surfaceHeight },
            adaptToHandedness: false, thermoCtrl: true })
          .scrollable(false).onContentWillChange((): boolean => false)
          .width('100%').height(this.surfaceHeight).hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
      } else {
        Row().width('100%').height('100%').attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveClean))
          .hitTestBehavior(HitTestMode.None)
      }
      this.content()
    }.width(this.surfaceWidth).height(this.surfaceHeight)
      .attributeModifier(new PodcastSurfaceClip(this.surfaceHeight / 2))
  }
}

/** Content cards share the system material tokens; only controls use a separate HDS tab carrier. */
@ComponentV2
export struct PodcastGlassPanel {
  @Param cornerRadius: number = 24;
  @BuilderParam content: () => void = this.empty;
  @Builder empty() { Row() }
  build() {
    Column() { this.content() }
      .width('100%').borderRadius(this.cornerRadius)
      .attributeModifier(AppMaterial.modifier(AppMaterial.SurfaceClean))
      .border({ width: 0.5, color: AppColor.GlassStroke, radius: this.cornerRadius })
      .clip(true)
  }
}
