import { common } from '@kit.AbilityKit';
import { AppAppearance } from '../model/AppAppearance';
import { AppTheme } from './Theme';

/** 与 AppColor.Brand 使用同一资源，保留主题套装及深浅色限定资源的实际颜色。 */
export function resolveReaderAccent(context: common.Context | undefined, color: ResourceStr): string {
  if (typeof color === 'string') return AppAppearance.normalizeAccent(color) || AppAppearance.defaultAccent;
  if (context) {
    try {
      const rgb: number = context.resourceManager.getColorSync(color.id) & 0xFFFFFF;
      return '#' + rgb.toString(16).padStart(6, '0').toUpperCase();
    } catch (_error) { /* 资源暂不可用时保留当前套装的推荐色。 */ }
  }
  return AppAppearance.normalizeAccent(AppTheme.resolve().accent) || AppAppearance.defaultAccent;
}
