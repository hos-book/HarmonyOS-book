/** 主题定义是随包发布的只读配置；运行时选择仍由 AppAppearance 持有。 */
import { ThemePageBackdrop } from './ThemeDocument';

export enum ThemeBackgroundKind { Gradient, Solid, Image }
export enum ThemeBackgroundScene { Home, Shelf, Record }
export enum ThemeCoverDecoration { None, Border, Spine }
export enum ThemeIconRole { None, Search, Filter, Grid, List, ChevronRight, Home, Shelf, Record, Profile, Category }

export enum ThemeButtonRole {
  None = '',
  ShelfSearch = 'button.shelf.search',
  ShelfSearchActive = 'button.shelf.searchActive',
  ShelfFilter = 'button.shelf.filter',
  ShelfGroup = 'button.shelf.group',
  ShelfGroupActive = 'button.shelf.groupActive',
  ShelfGroupManage = 'button.shelf.groupManage',
  ShelfImport = 'button.shelf.import',
  ShelfUpdates = 'button.shelf.updates',
  ShelfViewList = 'button.shelf.viewList',
  ShelfViewCollection = 'button.shelf.viewCollection',
  ShelfViewGrid = 'button.shelf.viewGrid',
  ShelfAdd = 'button.shelf.add',
  ShelfExpand = 'button.shelf.expand',
  ShelfCollapse = 'button.shelf.collapse',
  ShelfClose = 'button.shelf.close',
  RecordBack = 'button.record.back',
  RecordFilter = 'button.record.filter',
  RecordFilterActive = 'button.record.filterActive',
  RecordExcerpt = 'button.record.excerpt',
  RecordHistory = 'button.record.history',
  RecordEdit = 'button.record.edit',
  RecordDone = 'button.record.done',
  RecordLocked = 'button.record.locked'
}

export const THEME_BUTTON_ROLES: ThemeButtonRole[] = [
  ThemeButtonRole.ShelfSearch, ThemeButtonRole.ShelfSearchActive, ThemeButtonRole.ShelfFilter,
  ThemeButtonRole.ShelfGroup, ThemeButtonRole.ShelfGroupActive, ThemeButtonRole.ShelfGroupManage,
  ThemeButtonRole.ShelfImport, ThemeButtonRole.ShelfUpdates, ThemeButtonRole.ShelfViewList,
  ThemeButtonRole.ShelfViewCollection, ThemeButtonRole.ShelfViewGrid, ThemeButtonRole.ShelfAdd,
  ThemeButtonRole.ShelfExpand, ThemeButtonRole.ShelfCollapse, ThemeButtonRole.ShelfClose,
  ThemeButtonRole.RecordBack, ThemeButtonRole.RecordFilter, ThemeButtonRole.RecordFilterActive,
  ThemeButtonRole.RecordExcerpt, ThemeButtonRole.RecordHistory, ThemeButtonRole.RecordEdit,
  ThemeButtonRole.RecordDone, ThemeButtonRole.RecordLocked
];

export class AppThemeColors {
  background: ResourceStr = $r('sys.color.background_primary');
  surface: ResourceStr = $r('sys.color.comp_background_primary');
  profileMenuSurface: ResourceStr | undefined = undefined;
  textPrimary: ResourceStr = $r('sys.color.font_primary');
  textSecondary: ResourceStr = $r('sys.color.font_secondary');
  textTertiary: ResourceStr = $r('sys.color.font_tertiary');
  iconPrimary: ResourceStr = $r('sys.color.icon_primary');
  iconSecondary: ResourceStr = $r('sys.color.icon_secondary');
  divider: ResourceStr = $r('sys.color.comp_divider');
  brand: ResourceStr = $r('app.color.app_brand');
  brandHover: ResourceStr = $r('app.color.app_brand_hover');
  brandPressed: ResourceStr = $r('app.color.app_brand_pressed');
  brandDisabled: ResourceStr = $r('app.color.app_brand_disabled');
  brandSoft: ResourceStr = $r('app.color.app_brand_soft');
  brandDark: ResourceStr = $r('app.color.app_brand_dark');
  onBrand: ResourceStr = $r('app.color.app_on_brand');
  controlFallback: ResourceStr = $r('app.color.glass_control_fallback');
  controlTint: ResourceStr = $r('app.color.glass_control_tint');
  stroke: ResourceStr = $r('app.color.glass_stroke');
  shadow: ResourceStr = $r('app.color.app_shadow');
  appDivider: ResourceStr = $r('app.color.app_divider');
  homeTop: ResourceStr = $r('app.color.home_bg_warm_top');
  homeMid: ResourceStr = $r('app.color.home_bg_warm_mid');
  homeBottom: ResourceStr = $r('app.color.home_bg_neutral');
  statusScrim: ResourceStr = $r('app.color.home_status_scrim');
  floatingMask: ResourceStr = $r('app.color.floating_bar_mask');
  homeAccent: ResourceStr = $r('app.color.home_accent');
  homeAccentSoft: ResourceStr = $r('app.color.home_accent_soft');
  homeControl: ResourceStr = $r('app.color.home_top_control_tint');
  homeSurface: ResourceStr = $r('app.color.home_card_surface');
  homeShadow: ResourceStr = $r('app.color.home_card_shadow');
  progressTrack: ResourceStr = $r('app.color.home_progress_track');
  detailTop: ResourceStr = $r('app.color.detail_backdrop_scrim_top');
  detailMid: ResourceStr = $r('app.color.home_card_surface_soft');
  detailBottom: ResourceStr = $r('sys.color.comp_background_primary');
  settingsBackground: ResourceStr = $r('sys.color.background_secondary');
}

export class AppThemeBackground {
  kind: ThemeBackgroundKind = ThemeBackgroundKind.Gradient;
  image: ResourceStr | undefined = undefined;
  shelfImage: ResourceStr | undefined = undefined;
  recordImage: ResourceStr | undefined = undefined;
  profileCardImage: ResourceStr | undefined = undefined;

  resolveImage(scene: ThemeBackgroundScene): ResourceStr | undefined {
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
  placeholder: ResourceStr = $r('app.media.book_cover_placeholder');
  localPlaceholder: ResourceStr = $r('app.media.local_book_cover_placeholder');
  playerPlaceholder: ResourceStr = $r('app.media.app_icon_legacy');
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
  buttons: Map<ThemeButtonRole, ResourceStr> = new Map<ThemeButtonRole, ResourceStr>();
  pages: Map<string, ThemePageBackdrop> = new Map<string, ThemePageBackdrop>();
  selectedIcons: Map<ThemeIconRole, ResourceStr> = new Map<ThemeIconRole, ResourceStr>();
  tabNormalColor: ResourceColor | undefined = undefined;
  tabSelectedColor: ResourceColor | undefined = undefined;
  colors: AppThemeColors = new AppThemeColors();
  background: AppThemeBackground = new AppThemeBackground();
  cover: AppThemeCover = new AppThemeCover();
  icons: Map<ThemeIconRole, ResourceStr> = new Map<ThemeIconRole, ResourceStr>();
  brandedProfileIcons: boolean = false;
}
