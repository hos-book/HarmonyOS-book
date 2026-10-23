import { AppThemeBundle } from '../../model/AppThemeBundle';

/** 系统语义色与原有默认资源由 AppThemeVisual 提供。 */
export function createDefaultTheme(): AppThemeBundle {
  return new AppThemeBundle('default', $r('app.string.theme_bundle_default_name'),
    $r('app.string.theme_bundle_default_description'), '', 3);
}
