import { AppMaterial, AppRadius } from '../theme/Theme';
import { PlatformCompat } from '../utils/PlatformCompat';

/** 与累计阅听胶囊共用无阴影沉浸材质，折叠时由卡片外层裁剪。 */
@ComponentV2
export struct RecordCardBackdrop {
  @Param cardHeight: number = 238;

  build() {
    Stack() {
      if (PlatformCompat.immersiveMaterial) {
        Row().width('100%').height('100%')
          .attributeModifier(AppMaterial.modifier(AppMaterial.SurfaceClean))
      } else {
        Row().width('100%').height('100%')
          .backgroundColor($r('sys.color.comp_background_primary'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      }
    }.width('100%').height(this.cardHeight)
      .borderRadius(AppRadius.Lg).clip(true)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
  }
}

