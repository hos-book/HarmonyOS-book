import { ThemeDocument, ThemeToken, ThemePageBackdrop } from '../model/ThemeDocument';
import { AppThemeBundle } from '../model/AppThemeBundle';
import { AppThemeColors, ThemeIconRole, ThemeCoverDecoration, THEME_BUTTON_ROLES } from '../model/AppThemeVisual';

export class ThemeDocumentResolver {
  static apply(bundle: AppThemeBundle, document: ThemeDocument, directory: string, dark: boolean): AppThemeBundle {
    const tokens: ThemeToken[] = dark ? document.dark : document.light;
    bundle.id = document.id;
    bundle.name = document.name;
    bundle.description = document.description;
    bundle.custom = true;
    for (const token of tokens) {
      if (token.key.startsWith('color.')) ThemeDocumentResolver.color(bundle.visual.colors, token.key.substring(6), token.value);
    }
    bundle.accent = ThemeDocument.value(tokens, 'color.brand', bundle.accent);
    bundle.visual.tabNormalColor = ThemeDocument.value(tokens, 'tab.normalColor') || undefined;
    bundle.visual.tabSelectedColor = ThemeDocument.value(tokens, 'tab.selectedColor') || undefined;
    bundle.visual.background.showCoverBackdrop = ThemeDocument.value(tokens, 'background.coverBackdrop',
      bundle.visual.background.showCoverBackdrop.toString()) === 'true';
    const card: string = ThemeDocumentResolver.asset(tokens, 'background.profileCard', directory);
    if (card) bundle.visual.background.profileCardImage = card;
    for (const scene of ['common', 'home', 'shelf', 'record', 'profile', 'player']) {
      bundle.visual.pages.set(scene, ThemeDocumentResolver.backdrop(tokens, scene, directory));
    }
    ThemeDocumentResolver.icon(bundle, tokens, ThemeIconRole.Home, 'tab.home.normal', directory, false);
    ThemeDocumentResolver.icon(bundle, tokens, ThemeIconRole.Home, 'tab.home.selected', directory, true);
    ThemeDocumentResolver.icon(bundle, tokens, ThemeIconRole.Shelf, 'tab.shelf.normal', directory, false);
    ThemeDocumentResolver.icon(bundle, tokens, ThemeIconRole.Shelf, 'tab.shelf.selected', directory, true);
    ThemeDocumentResolver.icon(bundle, tokens, ThemeIconRole.Record, 'tab.record.normal', directory, false);
    ThemeDocumentResolver.icon(bundle, tokens, ThemeIconRole.Record, 'tab.record.selected', directory, true);
    ThemeDocumentResolver.icon(bundle, tokens, ThemeIconRole.Profile, 'tab.profile.normal', directory, false);
    ThemeDocumentResolver.icon(bundle, tokens, ThemeIconRole.Profile, 'tab.profile.selected', directory, true);
    ThemeDocumentResolver.icon(bundle, tokens, ThemeIconRole.Search, 'icon.Search', directory, false);
    ThemeDocumentResolver.icon(bundle, tokens, ThemeIconRole.Filter, 'icon.Filter', directory, false);
    ThemeDocumentResolver.icon(bundle, tokens, ThemeIconRole.Grid, 'icon.Grid', directory, false);
    ThemeDocumentResolver.icon(bundle, tokens, ThemeIconRole.List, 'icon.List', directory, false);
    for (const role of THEME_BUTTON_ROLES) {
      const asset: string = ThemeDocumentResolver.asset(tokens, role, directory);
      if (asset) bundle.visual.buttons.set(role, asset);
    }
    const cover = bundle.visual.cover;
    cover.placeholder = ThemeDocumentResolver.asset(tokens, 'cover.placeholder', directory) || cover.placeholder;
    cover.localPlaceholder = ThemeDocumentResolver.asset(tokens, 'cover.localPlaceholder', directory) || cover.localPlaceholder;
    cover.playerPlaceholder = ThemeDocumentResolver.asset(tokens, 'cover.playerPlaceholder', directory) || cover.playerPlaceholder;
    cover.title = ThemeDocument.value(tokens, 'cover.title') || cover.title;
    cover.localTitle = ThemeDocument.value(tokens, 'cover.localTitle') || cover.localTitle;
    cover.author = ThemeDocument.value(tokens, 'cover.author') || cover.author;
    cover.authorBackground = ThemeDocument.value(tokens, 'cover.authorBackground') || cover.authorBackground;
    cover.label = ThemeDocument.value(tokens, 'cover.label') || cover.label;
    cover.edge = ThemeDocument.value(tokens, 'cover.edge') || cover.edge;
    const decoration: string = ThemeDocument.value(tokens, 'cover.decoration', cover.decoration.toString());
    cover.decoration = decoration === '1' ? ThemeCoverDecoration.Border :
      decoration === '2' ? ThemeCoverDecoration.Spine : ThemeCoverDecoration.None;
    cover.illustratedPlaceholder = ThemeDocument.value(tokens, 'cover.illustratedPlaceholder',
      cover.illustratedPlaceholder.toString()) === 'true';
    return bundle;
  }

  static backdrop(tokens: ThemeToken[], scene: string, directory: string): ThemePageBackdrop {
    const prefix: string = 'background.' + scene + '.';
    const result: ThemePageBackdrop = new ThemePageBackdrop();
    result.mode = ThemeDocument.value(tokens, prefix + 'mode', scene === 'player' ? 'cover' : scene === 'common' ? 'theme' : 'common');
    if (result.mode === 'common') return ThemeDocumentResolver.backdrop(tokens, 'common', directory);
    result.image = ThemeDocumentResolver.asset(tokens, prefix + 'image', directory);
    result.color = ThemeDocument.value(tokens, prefix + 'color', scene === 'player' ? '#3B4650' : '#F7F4EF');
    result.veil = Number(ThemeDocument.value(tokens, prefix + 'veil', scene === 'player' ? '70' : '0'));
    result.blur = Number(ThemeDocument.value(tokens, prefix + 'blur', scene === 'player' ? '40' : '0'));
    result.positionX = Number(ThemeDocument.value(tokens, prefix + 'positionX', '50'));
    result.positionY = Number(ThemeDocument.value(tokens, prefix + 'positionY', '50'));
    result.scale = Number(ThemeDocument.value(tokens, prefix + 'scale', '100'));
    return result;
  }

  static asset(tokens: ThemeToken[], key: string, directory: string): string {
    const path: string = ThemeDocument.value(tokens, key);
    return path.startsWith('assets/') ? 'file://' + directory + '/' + path : '';
  }

  private static icon(bundle: AppThemeBundle, tokens: ThemeToken[], role: ThemeIconRole, key: string,
    directory: string, selected: boolean): void {
    const asset: string = ThemeDocumentResolver.asset(tokens, key, directory);
    if (asset) (selected ? bundle.visual.selectedIcons : bundle.visual.icons).set(role, asset);
  }

  private static color(colors: AppThemeColors, key: string, value: string): void {
    switch (key) {
      case 'background': colors.background = value; break;
      case 'surface': colors.surface = value; break;
      case 'settingsBackground': colors.settingsBackground = value; break;
      case 'profileMenuSurface': colors.profileMenuSurface = value; break;
      case 'textPrimary': colors.textPrimary = value; break;
      case 'textSecondary': colors.textSecondary = value; break;
      case 'textTertiary': colors.textTertiary = value; break;
      case 'iconPrimary': colors.iconPrimary = value; break;
      case 'iconSecondary': colors.iconSecondary = value; break;
      case 'divider': colors.divider = value; break;
      case 'appDivider': colors.appDivider = value; break;
      case 'brand': colors.brand = value; break;
      case 'brandHover': colors.brandHover = value; break;
      case 'brandPressed': colors.brandPressed = value; break;
      case 'brandDisabled': colors.brandDisabled = value; break;
      case 'brandSoft': colors.brandSoft = value; break;
      case 'brandDark': colors.brandDark = value; break;
      case 'onBrand': colors.onBrand = value; break;
      case 'controlFallback': colors.controlFallback = value; break;
      case 'controlTint': colors.controlTint = value; break;
      case 'stroke': colors.stroke = value; break;
      case 'shadow': colors.shadow = value; break;
      case 'homeTop': colors.homeTop = value; break;
      case 'homeMid': colors.homeMid = value; break;
      case 'homeBottom': colors.homeBottom = value; break;
      case 'statusScrim': colors.statusScrim = value; break;
      case 'floatingMask': colors.floatingMask = value; break;
      case 'homeAccent': colors.homeAccent = value; break;
      case 'homeAccentSoft': colors.homeAccentSoft = value; break;
      case 'homeControl': colors.homeControl = value; break;
      case 'homeSurface': colors.homeSurface = value; break;
      case 'homeShadow': colors.homeShadow = value; break;
      case 'progressTrack': colors.progressTrack = value; break;
      case 'detailTop': colors.detailTop = value; break;
      case 'detailMid': colors.detailMid = value; break;
      case 'detailBottom': colors.detailBottom = value; break;
    }
  }
}
