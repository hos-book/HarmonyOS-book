/** 主题定义是随包发布的只读配置；运行时选择仍由 AppAppearance 持有。 */
export enum ThemeBackgroundKind { Gradient, Solid, Image }
export enum ThemeBackgroundScene { Home, Shelf, Record }
export enum ThemeCoverDecoration { None, Border, Spine }
export enum ThemeIconRole { None, Search, Filter, Grid, List, ChevronRight, Home, Shelf, Record, Profile, Category }

export class AppThemeColors {
  background: Resource = $r('sys.color.background_primary');
  surface: Resource = $r('sys.color.comp_background_primary');
  profileMenuSurface: Resource | undefined = undefined;
  textPrimary: Resource = $r('sys.color.font_primary');
  textSecondary: Resource = $r('sys.color.font_secondary');
  textTertiary: Resource = $r('sys.color.font_tertiary');
  iconPrimary: Resource = $r('sys.color.icon_primary');
  iconSecondary: Resource = $r('sys.color.icon_secondary');
  divider: Resource = $r('sys.color.comp_divider');
  brand: Resource = $r('app.color.app_brand');
  brandHover: Resource = $r('app.color.app_brand_hover');
  brandPressed: Resource = $r('app.color.app_brand_pressed');
  brandDisabled: Resource = $r('app.color.app_brand_disabled');
  brandSoft: Resource = $r('app.color.app_brand_soft');
  brandDark: Resource = $r('app.color.app_brand_dark');
  onBrand: Resource = $r('app.color.app_on_brand');
  controlFallback: Resource = $r('app.color.glass_control_fallback');
  controlTint: Resource = $r('app.color.glass_control_tint');
  stroke: Resource = $r('app.color.glass_stroke');
  shadow: Resource = $r('app.color.app_shadow');
  appDivider: Resource = $r('app.color.app_divider');
  homeTop: Resource = $r('app.color.home_bg_warm_top');
  homeMid: Resource = $r('app.color.home_bg_warm_mid');
  homeBottom: Resource = $r('app.color.home_bg_neutral');
  statusScrim: Resource = $r('app.color.home_status_scrim');
  floatingMask: Resource = $r('app.color.floating_bar_mask');
  homeAccent: Resource = $r('app.color.home_accent');
  homeAccentSoft: Resource = $r('app.color.home_accent_soft');
  homeControl: Resource = $r('app.color.home_top_control_tint');
  homeSurface: Resource = $r('app.color.home_card_surface');
  homeShadow: Resource = $r('app.color.home_card_shadow');
  progressTrack: Resource = $r('app.color.home_progress_track');
  detailTop: Resource = $r('app.color.detail_backdrop_scrim_top');
  detailMid: Resource = $r('app.color.home_card_surface_soft');
  detailBottom: Resource = $r('sys.color.comp_background_primary');
  settingsBackground: Resource = $r('sys.color.background_secondary');
}

export class AppThemeBackground {
  kind: ThemeBackgroundKind = ThemeBackgroundKind.Gradient;
  image: Resource | undefined = undefined;
  shelfImage: Resource | undefined = undefined;
  recordImage: Resource | undefined = undefined;
  profileCardImage: Resource | undefined = undefined;

  resolveImage(scene: ThemeBackgroundScene): Resource | undefined {
    if (scene === ThemeBackgroundScene.Shelf) return this.shelfImage ?? this.image;
    if (scene === ThemeBackgroundScene.Record) return this.recordImage ?? this.image;
    return this.image;
  }
  /** 图片叠加在语义背景上；降低笔触对正文的干扰，默认保持原图。 */
  imageOpacity: number = 1;
  /** 首页/榜单/详情可否继续使用书封氛围背景。 */
  showCoverBackdrop: boolean = true;
}

export class AppThemeCover {
  placeholder: Resource = $r('app.media.book_cover_placeholder');
  localPlaceholder: Resource = $r('app.media.local_book_cover_placeholder');
  playerPlaceholder: Resource = $r('app.media.app_icon_legacy');
  title: ResourceColor = '#FFF4E6';
  localTitle: ResourceColor = '#493E35';
  author: ResourceColor = '#64584B';
  authorBackground: ResourceColor = '#00000000';
  label: ResourceColor = '#AA493E35';
  edge: ResourceColor = $r('sys.color.font_secondary');
  decoration: ThemeCoverDecoration = ThemeCoverDecoration.None;
  /** 首页、搜索和下载的无图项是否统一使用带书名的封面。 */
  illustratedPlaceholder: boolean = false;
}

export class AppThemeVisual {
  colors: AppThemeColors = new AppThemeColors();
  background: AppThemeBackground = new AppThemeBackground();
  cover: AppThemeCover = new AppThemeCover();
  icons: Map<ThemeIconRole, Resource> = new Map<ThemeIconRole, Resource>();
  brandedProfileIcons: boolean = false;
}
