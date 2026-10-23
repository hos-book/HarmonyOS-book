import { AppThemeVisual } from './AppThemeVisual';

/** 内置主题定义。资源随应用发布，书籍图片与阅读纸张不属于套装数据。 */
export class AppThemeBundle {
  id: string;
  name: ResourceStr;
  description: ResourceStr;
  accent: string;
  material: number;
  visual: AppThemeVisual;

  constructor(id: string, name: ResourceStr, description: ResourceStr, accent: string, material: number,
    visual: AppThemeVisual = new AppThemeVisual()) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.accent = accent;
    this.material = material;
    this.visual = visual;
  }
}

/** 一条记录保存整个外观选择，颜色与材质为用户当前实际选择。 */
export class AppThemeSelection {
  schemaVersion: number = 1;
  themeBundleId: string = 'default';
  accentColor: string = '';
  materialStyle: number = 3;

  constructor(themeBundleId: string = 'default', accentColor: string = '', materialStyle: number = 3) {
    this.themeBundleId = themeBundleId;
    this.accentColor = accentColor;
    this.materialStyle = materialStyle;
  }
}
