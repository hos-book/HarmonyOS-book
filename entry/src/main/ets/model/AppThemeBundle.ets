import { AppThemeVisual } from './AppThemeVisual';
import { AppAppearance } from './AppAppearance';

/** 内置主题定义。资源随应用发布，书籍图片与阅读纸张不属于套装数据。 */
export class AppThemeBundle {
  id: string;
  name: ResourceStr;
  description: ResourceStr;
  accent: string;
  visual: AppThemeVisual;
  custom: boolean = false;
  materialStyle: number = AppAppearance.systemMaterial;
  verticalBottomTabs: boolean = false;

  constructor(id: string, name: ResourceStr, description: ResourceStr, accent: string,
    visual: AppThemeVisual = new AppThemeVisual()) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.accent = accent;
    this.visual = visual;
  }
}

/** 一条记录保存整个外观选择，颜色与材质为用户当前实际选择。 */
export class AppThemeSelection {
  schemaVersion: number = 2;
  themeBundleId: string = 'default';
  accentColor: string = '';
  materialStyle: number = AppAppearance.systemMaterial;

  constructor(themeBundleId: string = 'default', accentColor: string = '',
    materialStyle: number = AppAppearance.systemMaterial) {
    this.schemaVersion = AppAppearance.current.useLegacyThemeOverrides ? 1 : 2;
    this.themeBundleId = themeBundleId;
    this.accentColor = accentColor;
    this.materialStyle = materialStyle;
  }
}
