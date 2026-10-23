import { curves } from '@kit.ArkUI';
import lazy { uiMaterial } from '@kit.ArkUI';
import { AppAppearance } from '../model/AppAppearance';
import { PlatformCompat } from '../utils/PlatformCompat';
import { ThemeBundles } from './ThemeBundles';

/** App 外观语义入口；深浅色由同名 base/dark 资源解析，阅读正文继续使用 ReaderTheme。 */
export class AppTheme {
  static get isPaper(): boolean { return AppAppearance.current.themeBundleId === ThemeBundles.PaperId; }
  static get usesPaperAccent(): boolean {
    return AppTheme.isPaper && AppAppearance.current.accent === ThemeBundles.PaperAccent;
  }
  static get Background(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_background') : $r('sys.color.background_primary');
  }
  static get Surface(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_surface') : $r('sys.color.comp_background_primary');
  }
  static get TextPrimary(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_text_primary') : $r('sys.color.font_primary');
  }
  static get TextSecondary(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_text_secondary') : $r('sys.color.font_secondary');
  }
  static get TextTertiary(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_text_tertiary') : $r('sys.color.font_tertiary');
  }
  static get IconPrimary(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_text_primary') : $r('sys.color.icon_primary');
  }
  static get IconSecondary(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_text_secondary') : $r('sys.color.icon_secondary');
  }
  static get Divider(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_divider') : $r('sys.color.comp_divider');
  }
  static get BackgroundImage(): Resource | undefined {
    return AppTheme.isPaper ? $r('app.media.theme_paper_background') : undefined;
  }
}

export class AppColor {
  static get Brand(): ResourceStr {
    if (AppTheme.usesPaperAccent) return $r('app.color.theme_paper_brand');
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? accent : $r('app.color.app_brand');
  }
  static get BrandHover(): ResourceStr {
    if (AppTheme.usesPaperAccent) return $r('app.color.theme_paper_brand_hover');
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? AppAppearance.shade(accent, 0.92) : $r('app.color.app_brand_hover');
  }
  static get BrandPressed(): ResourceStr {
    if (AppTheme.usesPaperAccent) return $r('app.color.theme_paper_brand_pressed');
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? AppAppearance.shade(accent, 0.82) : $r('app.color.app_brand_pressed');
  }
  static get BrandDisabled(): ResourceStr {
    if (AppTheme.usesPaperAccent) return $r('app.color.theme_paper_brand_disabled');
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? '#66' + accent.substring(1) : $r('app.color.app_brand_disabled');
  }
  static get BrandSoft(): ResourceStr {
    if (AppTheme.usesPaperAccent) return $r('app.color.theme_paper_brand_soft');
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? '#22' + accent.substring(1) : $r('app.color.app_brand_soft');
  }
  static get BrandDark(): ResourceStr {
    if (AppTheme.usesPaperAccent) return $r('app.color.theme_paper_brand_pressed');
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? AppAppearance.shade(accent, 0.78) : $r('app.color.app_brand_dark');
  }
  static get OnBrand(): ResourceStr {
    if (AppTheme.usesPaperAccent) return $r('app.color.theme_paper_on_brand');
    const accent: string = AppAppearance.current.accent;
    return accent.length > 0 ? AppAppearance.foreground(accent) : $r('app.color.app_on_brand');
  }
  static get Divider(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_divider') : $r('app.color.app_divider');
  }
  static get Shadow(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_shadow') : $r('app.color.app_shadow');
  }
  static get GlassControlFallback(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_control') : $r('app.color.glass_control_fallback');
  }
  static readonly GlassSheetFallback: Resource = $r('app.color.glass_sheet_fallback');
  static get GlassControlTint(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_control') : $r('app.color.glass_control_tint');
  }
  static readonly GlassSheetControlTint: Resource = $r('app.color.glass_sheet_control_tint');
  static readonly GlassSheetStroke: Resource = $r('app.color.glass_sheet_stroke');
  static readonly GlassTextPrimary: Resource = $r('app.color.glass_text_primary');
  static readonly GlassTextSecondary: Resource = $r('app.color.glass_text_secondary');
  static readonly GlassTextTertiary: Resource = $r('app.color.glass_text_tertiary');
  static readonly GlassDivider: Resource = $r('app.color.glass_divider');
  static get GlassStroke(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_divider') : $r('app.color.glass_stroke');
  }
  static readonly GlassShadow: Resource = $r('app.color.glass_shadow');

  // Legacy literal overlays retained for existing call sites.
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
    instance.menuBackgroundColor(Color.Transparent);
    if (PlatformCompat.immersiveMaterial && this.menuMaterial !== undefined) {
      instance.menuBackgroundBlurStyle(BlurStyle.NONE).menuSystemMaterial(this.menuMaterial);
    } else {
      instance.menuBackgroundBlurStyle(this.menuBlur);
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

/**
 * 首页与记录页共用的暖色主题。
 * 走 base/dark element/color.json 双份资源，自动深浅切换。
 */
export class HomeTheme {
  static get BgWarmTop(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_background') : $r('app.color.home_bg_warm_top');
  }
  static get BgWarmMid(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_background') : $r('app.color.home_bg_warm_mid');
  }
  static get BgNeutral(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_background') : $r('app.color.home_bg_neutral');
  }
  /** 状态栏窄条：与 BgNeutral 同色半透明，配合 backdropBlur */
  static get StatusScrim(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_status_scrim') : $r('app.color.home_status_scrim');
  }
  static get FloatingBarMask(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_floating_mask') : $r('app.color.floating_bar_mask');
  }
  static get Accent(): ResourceStr {
    return AppAppearance.current.accent.length > 0 ? AppColor.Brand : $r('app.color.home_accent');
  }
  static get AccentSoft(): ResourceStr {
    return AppAppearance.current.accent.length > 0 ? AppColor.BrandSoft : $r('app.color.home_accent_soft');
  }
  static get TopControlTint(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_control') : $r('app.color.home_top_control_tint');
  }
  static get CardSurface(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_surface') : $r('app.color.home_card_surface');
  }
  static get CardShadow(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_shadow') : $r('app.color.home_card_shadow');
  }
  static get ProgressTrack(): Resource {
    return AppTheme.isPaper ? $r('app.color.theme_paper_divider') : $r('app.color.home_progress_track');
  }
}
