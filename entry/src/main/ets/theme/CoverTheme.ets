import { AppTheme } from './Theme';
import { AppThemeCover, ThemeCoverDecoration } from '../model/AppThemeVisual';

/** 只解析呈现；真实图片地址、缓存和书籍身份由原链路管理。 */
export class CoverTheme {
  static resolve(themeBundleId: string = ''): AppThemeCover {
    return AppTheme.resolve(themeBundleId).visual.cover;
  }
  static decoration(themeBundleId: string = ''): ThemeCoverDecoration {
    return CoverTheme.resolve(themeBundleId).decoration;
  }
  static placeholder(themeBundleId: string = ''): Resource {
    return CoverTheme.resolve(themeBundleId).placeholder;
  }
  static localPlaceholder(themeBundleId: string = ''): Resource {
    return CoverTheme.resolve(themeBundleId).localPlaceholder;
  }
  static playerPlaceholder(): Resource { return CoverTheme.resolve().playerPlaceholder; }
  static titleColor(local: boolean = false, themeBundleId: string = ''): ResourceColor {
    const cover = CoverTheme.resolve(themeBundleId);
    return local ? cover.localTitle : cover.title;
  }
  static authorColor(themeBundleId: string = ''): ResourceColor {
    return CoverTheme.resolve(themeBundleId).author;
  }
  static authorBackground(themeBundleId: string = ''): ResourceColor {
    return CoverTheme.resolve(themeBundleId).authorBackground;
  }
  static titleBackground(themeBundleId: string = ''): ResourceColor {
    return CoverTheme.resolve(themeBundleId).label;
  }
  static edgeColor(themeBundleId: string = ''): ResourceColor {
    return CoverTheme.resolve(themeBundleId).edge;
  }
}
