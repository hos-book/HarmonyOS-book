import { AppThemeBundle } from '../model/AppThemeBundle';
import { createDefaultTheme } from './bundles/DefaultTheme';
import { createPaperTheme } from './bundles/PaperTheme';
import { createMistTheme } from './bundles/MistTheme';
import { createInkTheme } from './bundles/InkTheme';

/** 新套装只在注册表加入一次；校验、列表、解析共用同一数据源。 */
export class ThemeBundles {
  static readonly DefaultId: string = 'default';
  private static readonly bundles: AppThemeBundle[] = [
    createDefaultTheme(), createPaperTheme(), createMistTheme(), createInkTheme()
  ];

  static list(): AppThemeBundle[] {
    return ThemeBundles.bundles.slice();
  }

  static normalizeId(id: string): string {
    return ThemeBundles.resolve(id).id;
  }

  static resolve(id: string): AppThemeBundle {
    return ThemeBundles.bundles.find((bundle: AppThemeBundle): boolean => bundle.id === id) ??
      ThemeBundles.bundles[0];
  }
}
