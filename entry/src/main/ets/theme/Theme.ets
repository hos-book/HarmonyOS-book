import { curves } from '@kit.ArkUI';
import lazy { uiMaterial } from '@kit.ArkUI';
import { AppAppearance } from '../model/AppAppearance';
import { AppThemeBundle } from '../model/AppThemeBundle';
import { AppThemeColors, ThemeCoverDecoration } from '../model/AppThemeVisual';
import { PlatformCompat } from '../utils/PlatformCompat';
import { ThemeBundles } from './ThemeBundles';

/** 页面继续使用语义入口；显式 id 用于局部预览，空 id 始终读取响应式选择。 */
export class AppTheme {
  static resolve(themeBundleId: string = ''): AppThemeBundle {
    return ThemeBundles.resolve(themeBundleId.length > 0 ? themeBundleId : AppAppearance.current.themeBundleId);
  }
  static get colors(): AppThemeColors { return AppTheme.resolve().visual.colors; }
  static get usesRecommendedAccent(): boolean {
    return AppAppearance.current.accent === AppTheme.resolve().accent;
  }
  static get Background(): Resource { return AppTheme.colors.background; }
  static get Surface(): Resource { return AppTheme.colors.surface; }
  static get TextPrimary(): Resource { return AppTheme.colors.textPrimary; }
  static get TextSecondary(): Resource { return AppTheme.colors.textSecondary; }
  static get TextTertiary(): Resource { return AppTheme.colors.textTertiary; }
  static get IconPrimary(): Resource { return AppTheme.colors.iconPrimary; }
  static get IconSecondary(): Resource { return AppTheme.colors.iconSecondary; }
  static get Divider(): Resource { return AppTheme.colors.divider; }
  static get BackgroundImage(): Resource | undefined { return AppTheme.resolve().visual.background.image; }
  static get ShowCoverBackdrop(): boolean { return AppTheme.resolve().visual.background.showCoverBackdrop; }
  static get CoverDecorationEnabled(): boolean {
    return AppTheme.resolve().visual.cover.decoration !== ThemeCoverDecoration.None;
  }
  static get IllustratedPlaceholders(): boolean { return AppTheme.resolve().visual.cover.illustratedPlaceholder; }
  static get BrandedProfileIcons(): boolean { return AppTheme.resolve().visual.brandedProfileIcons; }
  static get SettingsBackground(): Resource { return AppTheme.colors.settingsBackground; }
  static get DetailTop(): Resource { return AppTheme.colors.detailTop; }
  static get DetailMid(): Resource { return AppTheme.colors.detailMid; }
  static get DetailBottom(): Resource { return AppTheme.colors.detailBottom; }
}

export class AppColor {
  static get Brand(): ResourceStr {
    if (AppTheme.usesRecommendedAccent) return AppTheme.colors.brand;
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? accent : ThemeBundles.resolve(ThemeBundles.DefaultId).visual.colors.brand;
  }
  static get BrandHover(): ResourceStr {
    if (AppTheme.usesRecommendedAccent) return AppTheme.colors.brandHover;
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? AppAppearance.shade(accent, 0.92) : ThemeBundles.resolve(ThemeBundles.DefaultId).visual.colors.brandHover;
  }
  static get BrandPressed(): ResourceStr {
    if (AppTheme.usesRecommendedAccent) return AppTheme.colors.brandPressed;
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? AppAppearance.shade(accent, 0.82) : ThemeBundles.resolve(ThemeBundles.DefaultId).visual.colors.brandPressed;
  }
  static get BrandDisabled(): ResourceStr {
    if (AppTheme.usesRecommendedAccent) return AppTheme.colors.brandDisabled;
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? '#66' + accent.substring(1) : ThemeBundles.resolve(ThemeBundles.DefaultId).visual.colors.brandDisabled;
  }
  static get BrandSoft(): ResourceStr {
    if (AppTheme.usesRecommendedAccent) return AppTheme.colors.brandSoft;
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? '#22' + accent.substring(1) : ThemeBundles.resolve(ThemeBundles.DefaultId).visual.colors.brandSoft;
  }
  static get BrandDark(): ResourceStr {
    if (AppTheme.usesRecommendedAccent) return AppTheme.colors.brandDark;
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? AppAppearance.shade(accent, 0.78) : ThemeBundles.resolve(ThemeBundles.DefaultId).visual.colors.brandDark;
  }
  static get OnBrand(): ResourceStr {
    if (AppTheme.usesRecommendedAccent) return AppTheme.colors.onBrand;
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? AppAppearance.foreground(accent) : ThemeBundles.resolve(ThemeBundles.DefaultId).visual.colors.onBrand;
  }
  static get Divider(): Resource { return AppTheme.colors.appDivider; }
  static get Shadow(): Resource { return AppTheme.colors.shadow; }
  static get GlassControlFallback(): Resource { return AppTheme.colors.controlFallback; }
  static get GlassControlTint(): Resource { return AppTheme.colors.controlTint; }
  static get GlassStroke(): Resource { return AppTheme.colors.stroke; }
  // 阅读与播放弹层保持系统中性配色，与套装分离。
  static readonly GlassSheetFallback: Resource = $r('app.color.glass_sheet_fallback');
  static readonly GlassSheetControlTint: Resource = $r('app.color.glass_sheet_control_tint');
  static readonly GlassSheetStroke: Resource = $r('app.color.glass_sheet_stroke');
  static readonly GlassTextPrimary: Resource = $r('app.color.glass_text_primary');
  static readonly GlassTextSecondary: Resource = $r('app.color.glass_text_secondary');
  static readonly GlassTextTertiary: Resource = $r('app.color.glass_text_tertiary');
  static readonly GlassDivider: Resource = $r('app.color.glass_divider');
  static readonly GlassShadow: Resource = $r('app.color.glass_shadow');
  static readonly GlassBg: string = '#33FFFFFF';
  static readonly GlassBgDark: string = '#33000000';
}

/** 原生材质统一入口；每次外观变更清空缓存，避免重复创建或保留旧光感色。 */
export class AppMaterial {
  private static cache: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
  private static appearanceKey: string = '';

  private static resolveStyle(fallback: uiMaterial.ImmersiveStyle): uiMaterial.ImmersiveStyle {
    switch (AppAppearance.current.material) {
      case 1: return uiMaterial.ImmersiveStyle.ULTRA_THIN;
      case 2: return uiMaterial.ImmersiveStyle.THIN;
      case 3: return uiMaterial.ImmersiveStyle.REGULAR;
      case 4: return uiMaterial.ImmersiveStyle.THICK;
      case 5: return uiMaterial.ImmersiveStyle.ULTRA_THICK;
      default: return fallback;
    }
  }

  private static material(key: string, fallback: uiMaterial.ImmersiveStyle,
    shadow: boolean, interactive: boolean, invert: boolean = false,
    fixedStyle: boolean = false): uiMaterial.Material {
    const appearanceKey: string = AppAppearance.current.themeBundleId + ':' +
      AppAppearance.current.material.toString() + ':' + AppAppearance.current.accent;
    if (appearanceKey !== AppMaterial.appearanceKey) {
      AppMaterial.cache.clear();
      AppMaterial.appearanceKey = appearanceKey;
    }
    // Read the reactive brand token even on a cache hit, so mounted controls observe theme changes.
    const lightColor: ResourceColor = AppColor.Brand;
    const cached: uiMaterial.Material | undefined = AppMaterial.cache.get(key);
    if (cached !== undefined) return cached;
    const material: uiMaterial.Material = new uiMaterial.ImmersiveMaterial({
      style: fixedStyle ? fallback : AppMaterial.resolveStyle(fallback),
      applyShadow: shadow,
      interactive: interactive,
      colorInvert: invert,
      lightEffect: { color: lightColor }
    });
    AppMaterial.cache.set(key, material);
    return material;
  }

  static get InteractiveThin(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('interactiveThin', uiMaterial.ImmersiveStyle.THIN, false, true);
  }
  static get InteractiveClean(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('interactiveClean', uiMaterial.ImmersiveStyle.THIN, false, true, true);
  }
  static get SurfaceClean(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('surfaceClean', uiMaterial.ImmersiveStyle.THIN, false, false);
  }
  static get FloatingControl(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('floating', uiMaterial.ImmersiveStyle.ULTRA_THIN, true, true);
  }
  static get Sheet(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('sheet', uiMaterial.ImmersiveStyle.THIN, true, false);
  }
  static get PlayerSheet(): uiMaterial.Material | undefined {
    return AppMaterial.ReaderSheetThick;
  }
  static get PlayerSheetBlur(): BlurStyle | undefined {
    return AppMaterial.ReaderSheetBlur;
  }
  /** 阅读页底部悬浮胶囊栏：固定薄光感材质 + 柔和投影，同官方浮动 Tab 视觉。 */
  static get ReaderBar(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('readerBar', uiMaterial.ImmersiveStyle.THIN, true, false);
  }
  /** 阅读与听书弹层固定弱档（厚材质），不跟随全局材质偏好。 */
  static get ReaderSheetThick(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('readerSheetThick', uiMaterial.ImmersiveStyle.THICK, true, false, false, true);
  }
  static get ReaderSheetBlur(): BlurStyle | undefined {
    return PlatformCompat.immersiveMaterial ? undefined : BlurStyle.COMPONENT_THICK;
  }
  static get DialogUltraThick(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('dialog', uiMaterial.ImmersiveStyle.ULTRA_THICK, true, false);
  }
  static get SurfaceRegular(): uiMaterial.Material | undefined {
    if (!PlatformCompat.immersiveMaterial) return undefined;
    return AppMaterial.material('regular', uiMaterial.ImmersiveStyle.REGULAR, true, false);
  }

  static get SheetBackground(): ResourceColor {
    return PlatformCompat.immersiveMaterial ? Color.Transparent : $r('sys.color.comp_background_primary');
  }

  static get SheetBlur(): BlurStyle | undefined {
    return PlatformCompat.immersiveMaterial ? undefined : AppMaterial.fallbackBlur;
  }

  private static get fallbackBlur(): BlurStyle {
    switch (AppAppearance.current.material) {
      case 1: return BlurStyle.COMPONENT_ULTRA_THIN;
      case 2: return BlurStyle.COMPONENT_THIN;
      case 4: return BlurStyle.COMPONENT_THICK;
      case 5: return BlurStyle.COMPONENT_ULTRA_THICK;
      default: return BlurStyle.COMPONENT_REGULAR;
    }
  }

  static modifier(material: uiMaterial.Material | undefined,
    fallbackColor: ResourceColor = AppColor.GlassControlFallback,
    fallbackShadow: ShadowOptions | undefined = undefined): CompatibleMaterialModifier {
    return new CompatibleMaterialModifier(material, fallbackColor, AppMaterial.fallbackBlur, fallbackShadow);
  }

  static selectModifier(): CompatibleSelectMaterialModifier {
    return new CompatibleSelectMaterialModifier(AppMaterial.InteractiveClean, AppMaterial.Sheet,
      AppMaterial.fallbackBlur);
  }
}

/** API 20 使用背景色和磨砂；旧设备不调用 systemMaterial，也不加载 uiMaterial。 */
class CompatibleMaterialModifier implements AttributeModifier<CommonAttribute> {
  private material: uiMaterial.Material | undefined;
  private fallbackColor: ResourceColor;
  private blur: BlurStyle;
  private fallbackShadow: ShadowOptions | undefined;

  constructor(material: uiMaterial.Material | undefined, fallbackColor: ResourceColor, blur: BlurStyle,
    fallbackShadow: ShadowOptions | undefined = undefined) {
    this.material = material;
    this.fallbackColor = fallbackColor;
    this.blur = blur;
    this.fallbackShadow = fallbackShadow;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (PlatformCompat.immersiveMaterial && this.material !== undefined) {
      instance.systemMaterial(this.material);
    } else {
      instance.backgroundColor(this.fallbackColor).backgroundBlurStyle(this.blur);
      if (this.fallbackShadow !== undefined) {
        instance.shadow(this.fallbackShadow);
      }
    }
  }
}

/** 下拉入口和弹出菜单分别应用材质，避免菜单保留系统默认厚背景。 */
class CompatibleSelectMaterialModifier extends CompatibleMaterialModifier {
  private menuMaterial: uiMaterial.Material | undefined;
  private menuBlur: BlurStyle;

  constructor(controlMaterial: uiMaterial.Material | undefined, menuMaterial: uiMaterial.Material | undefined,
    blur: BlurStyle) {
    super(controlMaterial, AppColor.GlassControlFallback, blur);
    this.menuMaterial = menuMaterial;
    this.menuBlur = blur;
  }

  applyNormalAttribute(instance: SelectAttribute): void {
    super.applyNormalAttribute(instance);
    if (PlatformCompat.immersiveMaterial && this.menuMaterial !== undefined) {
      instance.menuBackgroundColor(Color.Transparent)
        .menuBackgroundBlurStyle(BlurStyle.NONE).menuSystemMaterial(this.menuMaterial);
    } else {
      instance.menuBackgroundColor($r('sys.color.comp_background_primary')).menuBackgroundBlurStyle(this.menuBlur);
    }
  }
}

/**
 * System blur presets used by the current frosted-glass surfaces.
 * Legacy blur options for surfaces that do not use native sheet materials.
 */
export class AppGlass {
  static readonly ControlBlur: BlurStyle = BlurStyle.BACKGROUND_THIN;
  static readonly SheetBlur: BlurStyle = BlurStyle.BACKGROUND_REGULAR;

  static readonly ControlOptions: BackgroundBlurStyleOptions = {
    colorMode: ThemeColorMode.SYSTEM,
    adaptiveColor: AdaptiveColor.AVERAGE,
    scale: 0.62,
    policy: BlurStyleActivePolicy.FOLLOWS_WINDOW_ACTIVE_STATE,
    inactiveColor: AppColor.GlassControlFallback
  };

  static readonly SheetOptions: BackgroundBlurStyleOptions = {
    colorMode: ThemeColorMode.DARK,
    adaptiveColor: AdaptiveColor.AVERAGE,
    scale: 0.65,
    policy: BlurStyleActivePolicy.FOLLOWS_WINDOW_ACTIVE_STATE,
    inactiveColor: AppColor.GlassSheetFallback
  };

}

export class AppRadius {
  static readonly Xs: number = 4;
  static readonly Sm: number = 8;
  static readonly Md: number = 12;
  static readonly Lg: number = 16;
  static readonly Xl: number = 24;
  static readonly Pill: number = 999;
}

export class AppSpace {
  static readonly Xxs: number = 4;
  static readonly Xs: number = 8;
  static readonly Sm: number = 12;
  static readonly Md: number = 16;
  static readonly Lg: number = 24;
  static readonly Xl: number = 32;
}

export class AppFont {
  static readonly Caption: number = 12;
  static readonly Body: number = 14;
  static readonly BodyL: number = 16;
  static readonly Title: number = 18;
  static readonly TitleL: number = 22;
  static readonly Display: number = 28;
}

export class AppMotion {
  static readonly Fast: number = 150;
  static readonly Base: number = 250;
  static readonly Standard: number = 250; // 标准动画时长（与 Base 相同）
  static readonly Slow: number = 350;
  static readonly Page: number = 380;
}

/**
 * 统一动效曲线 token
 * - Standard: 通用进出场（默认）
 * - Emphasized: 大幅位移/页面级强调
 * - Decelerate: 入场（慢出快进）
 * - Accelerate: 出场（快出慢进）
 * - Spring: 轻量弹簧（点选/Tab）
 * - SpringSoft: 柔性弹簧（Sheet/弹层）
 */
export class AppCurve {
  static readonly Standard = curves.cubicBezierCurve(0.2, 0, 0, 1);
  static readonly Emphasized = curves.cubicBezierCurve(0.33, 0, 0.1, 1);
  static readonly Decelerate = curves.cubicBezierCurve(0, 0, 0, 1);
  static readonly Accelerate = curves.cubicBezierCurve(0.4, 0, 1, 1);
  static readonly Spring = curves.springMotion(0.4, 0.85);
  static readonly SpringSoft = curves.springMotion(0.6, 0.9);
}

/** 首页与记录页共享语义色；不绑定套装名称。 */
export class HomeTheme {
  static get BgWarmTop(): Resource { return AppTheme.colors.homeTop; }
  static get BgWarmMid(): Resource { return AppTheme.colors.homeMid; }
  static get BgNeutral(): Resource { return AppTheme.colors.homeBottom; }
  static get StatusScrim(): Resource { return AppTheme.colors.statusScrim; }
  static get FloatingBarMask(): Resource { return AppTheme.colors.floatingMask; }
  static get TopControlTint(): Resource { return AppTheme.colors.homeControl; }
  static get CardSurface(): Resource { return AppTheme.colors.homeSurface; }
  static get CardShadow(): Resource { return AppTheme.colors.homeShadow; }
  static get ProgressTrack(): Resource { return AppTheme.colors.progressTrack; }
  static get Accent(): ResourceStr {
    if (AppAppearance.current.accent.length > 0) return AppColor.Brand;
    return AppTheme.usesRecommendedAccent ? AppTheme.colors.homeAccent :
      ThemeBundles.resolve(ThemeBundles.DefaultId).visual.colors.homeAccent;
  }
  static get AccentSoft(): ResourceStr {
    if (AppAppearance.current.accent.length > 0) return AppColor.BrandSoft;
    return AppTheme.usesRecommendedAccent ? AppTheme.colors.homeAccentSoft :
      ThemeBundles.resolve(ThemeBundles.DefaultId).visual.colors.homeAccentSoft;
  }
}
