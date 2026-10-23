import { AppThemeBundle } from '../model/AppThemeBundle';

/** 页面只消费主题角色；新增套装集中在此注册。 */
export class ThemeBundles {
  static readonly DefaultId: string = 'default';
  static readonly PaperId: string = 'paper-study';
  static readonly PaperAccent: string = '#496D5C';

  static list(): AppThemeBundle[] {
    return [ThemeBundles.resolve(ThemeBundles.DefaultId), ThemeBundles.resolve(ThemeBundles.PaperId)];
  }

  static normalizeId(id: string): string {
    return id === ThemeBundles.PaperId ? ThemeBundles.PaperId : ThemeBundles.DefaultId;
  }

  static resolve(id: string): AppThemeBundle {
    if (id === ThemeBundles.PaperId) {
      return new AppThemeBundle(ThemeBundles.PaperId, $r('app.string.theme_bundle_paper_name'),
        $r('app.string.theme_bundle_paper_description'), ThemeBundles.PaperAccent, 3);
    }
    return new AppThemeBundle(ThemeBundles.DefaultId, $r('app.string.theme_bundle_default_name'),
      $r('app.string.theme_bundle_default_description'), '', 3);
  }
}
