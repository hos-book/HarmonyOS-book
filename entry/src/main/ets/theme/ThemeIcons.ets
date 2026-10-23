import { AppTheme } from './Theme';
import { ThemeIconRole } from '../model/AppThemeVisual';
export { ThemeIconRole } from '../model/AppThemeVisual';

/** 未配置的角色返回 undefined，由调用方保留原系统符号。 */
export class ThemeIcons {
  static resolve(role: ThemeIconRole, themeBundleId: string = ''): Resource | undefined {
    return AppTheme.resolve(themeBundleId).visual.icons.get(role);
  }
}
