import { AppThemeBundle } from '../model/AppThemeBundle';
import { AppAppearance } from '../model/AppAppearance';
import { ThemeDocument, ThemeDraft } from '../model/ThemeDocument';
import { ThemeDocumentResolver } from './ThemeDocumentResolver';
import { createDefaultTheme } from './bundles/DefaultTheme';
import { createPaperTheme } from './bundles/PaperTheme';
import { createMistTheme } from './bundles/MistTheme';
import { createInkTheme } from './bundles/InkTheme';
import { createJianjianTheme } from './bundles/JianjianTheme';
import { createApricotTheme } from './bundles/ApricotTheme';

/** 新套装只在注册表加入一次；校验、列表、解析共用同一数据源。 */
export class ThemeBundles {
  private static customLight: Map<string, AppThemeBundle> = new Map<string, AppThemeBundle>();
  private static customDark: Map<string, AppThemeBundle> = new Map<string, AppThemeBundle>();
  private static documents: Map<string, ThemeDraft> = new Map<string, ThemeDraft>();
  static readonly DefaultId: string = 'default';
  private static readonly bundles: AppThemeBundle[] = [
    createDefaultTheme(), createPaperTheme(), createMistTheme(), createInkTheme(), createJianjianTheme(),
    createApricotTheme()
  ];

  static list(): AppThemeBundle[] {
    AppAppearance.current.themeRevision;
    return ThemeBundles.bundles.concat(Array.from((AppAppearance.current.darkMode ?
      ThemeBundles.customDark : ThemeBundles.customLight).values()));
  }

  static fresh(id: string): AppThemeBundle {
    const factories: (() => AppThemeBundle)[] = [createDefaultTheme, createPaperTheme, createMistTheme,
      createInkTheme, createJianjianTheme, createApricotTheme];
    return (factories.find((factory: () => AppThemeBundle): boolean => factory().id === id) ?? createDefaultTheme)();
  }

  static register(document: ThemeDocument, directory: string): void {
    ThemeBundles.documents.set(document.id, new ThemeDraft(document, directory));
    ThemeBundles.customLight.set(document.id, ThemeDocumentResolver.apply(ThemeBundles.fresh(document.baseThemeId),
      document, directory, false));
    ThemeBundles.customDark.set(document.id, ThemeDocumentResolver.apply(ThemeBundles.fresh(document.baseThemeId),
      document, directory, true));
    AppAppearance.current.themeRevision++;
  }

  static document(id: string): ThemeDraft | undefined {
    return ThemeBundles.documents.get(id);
  }

  static unregister(id: string): void {
    ThemeBundles.documents.delete(id);
    ThemeBundles.customLight.delete(id);
    ThemeBundles.customDark.delete(id);
    AppAppearance.current.themeRevision++;
  }

  static normalizeId(id: string): string {
    return ThemeBundles.resolve(id).id;
  }

  static resolve(id: string): AppThemeBundle {
    AppAppearance.current.themeRevision;
    const custom: AppThemeBundle | undefined = (AppAppearance.current.darkMode ?
      ThemeBundles.customDark : ThemeBundles.customLight).get(id);
    if (custom) return custom;
    return ThemeBundles.bundles.find((bundle: AppThemeBundle): boolean => bundle.id === id) ??
      ThemeBundles.bundles[0];
  }
}
