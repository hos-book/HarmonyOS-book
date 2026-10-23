import { HdsTabsAttribute, HdsTabsFloatingStyle, ScrollEffectType, SystemMaterialParams } from '@kit.UIDesignKit';
import lazy { hdsMaterial } from '@kit.UIDesignKit';
import { PlatformCompat } from './PlatformCompat';
import { AppTheme } from '../theme/Theme';

export class HdsCompat {
  static get scrollEffect(): ScrollEffectType {
    return PlatformCompat.floatingTabs ? ScrollEffectType.IMMERSIVE_GRADIENT_BLUR : ScrollEffectType.GRADIENT_BLUR;
  }

  static get material(): SystemMaterialParams | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    return {
      materialType: hdsMaterial.MaterialType.IMMERSIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    };
  }

  static get adaptiveMaterial(): SystemMaterialParams | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    return {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    };
  }
}

/** 浮动栏从 API 23 开始支持；API 20–22 使用固定底栏，保留切换和点击行为。 */
export class CompatibleTabsModifier implements AttributeModifier<HdsTabsAttribute> {
  private style: HdsTabsFloatingStyle | undefined;
  private fallbackHeight: number;

  constructor(style: HdsTabsFloatingStyle | undefined, fallbackHeight: number) {
    this.style = style;
    this.fallbackHeight = fallbackHeight;
  }

  applyNormalAttribute(instance: HdsTabsAttribute): void {
    if (PlatformCompat.floatingTabs && this.style !== undefined) {
      instance.barFloatingStyle(this.style);
    } else {
      instance.barHeight(this.fallbackHeight)
        .barBackgroundColor(AppTheme.Surface);
    }
  }
}
