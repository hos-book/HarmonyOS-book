import { HdsTabsAttribute, HdsTabsFloatingStyle, ScrollEffectType, SystemMaterialParams } from '@kit.UIDesignKit';
import lazy { hdsMaterial } from '@kit.UIDesignKit';
import { PlatformCompat } from './PlatformCompat';
import { AppTheme } from '../theme/Theme';
import { AppAppearance } from '../model/AppAppearance';

export class HdsCompat {
  static get materialSupported(): boolean {
    if (!PlatformCompat.floatingTabs) return false;
    return HdsCompat.resolveMaterialType(false) !== hdsMaterial.MaterialType.NONE;
  }

  static get scrollEffect(): ScrollEffectType {
    return HdsCompat.materialSupported ? ScrollEffectType.IMMERSIVE_GRADIENT_BLUR : ScrollEffectType.GRADIENT_BLUR;
  }

  static get material(): SystemMaterialParams | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    const followsSystem: boolean = AppAppearance.current.effectiveMaterial === AppAppearance.systemMaterial;
    return {
      materialType: HdsCompat.resolveMaterialType(followsSystem),
      materialLevel: HdsCompat.materialLevel
    };
  }

  /** ADAPTIVE 只是系统策略，不能作为设备能绘制沉浸材质的证明。 */
  private static resolveMaterialType(followsSystem: boolean): hdsMaterial.MaterialType {
    if (PlatformCompat.supports(26) && !PlatformCompat.immersiveMaterial) return hdsMaterial.MaterialType.NONE;
    try {
      const supported: hdsMaterial.MaterialType[] = hdsMaterial.getSystemMaterialTypes();
      if (!supported.includes(hdsMaterial.MaterialType.IMMERSIVE)) return hdsMaterial.MaterialType.NONE;
      if (followsSystem && supported.includes(hdsMaterial.MaterialType.ADAPTIVE)) {
        return hdsMaterial.MaterialType.ADAPTIVE;
      }
      return hdsMaterial.MaterialType.IMMERSIVE;
    } catch (_error) { /* 能力查询失败时保留系统普通控件。 */ }
    return hdsMaterial.MaterialType.NONE;
  }

  private static get materialLevel(): hdsMaterial.MaterialLevel {
    switch (AppAppearance.current.effectiveMaterial) {
      case 2: return hdsMaterial.MaterialLevel.EXQUISITE;
      case 3: return hdsMaterial.MaterialLevel.GENTLE;
      case 4: return hdsMaterial.MaterialLevel.SMOOTH;
      default: return hdsMaterial.MaterialLevel.ADAPTIVE;
    }
  }

  static get adaptiveMaterial(): SystemMaterialParams | undefined {
    if (!PlatformCompat.floatingTabs) return undefined;
    return HdsCompat.material;
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
      if (!HdsCompat.materialSupported) {
        instance.barBackgroundColor(AppTheme.Surface).barBackgroundBlurStyle(BlurStyle.COMPONENT_REGULAR);
      } else {
        instance.barBackgroundColor(Color.Transparent).barBackgroundBlurStyle(BlurStyle.NONE);
      }
    } else {
      if (PlatformCompat.floatingTabs) instance.barFloatingStyle(undefined);
      instance.barHeight(this.fallbackHeight)
        .barBackgroundColor(AppTheme.Surface);
    }
  }
}
