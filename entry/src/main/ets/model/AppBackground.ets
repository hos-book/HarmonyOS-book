/** App 主界面的背景；与阅读纸张、桌面应用图标和主题套装独立。 */
export enum AppBackgroundScene { Common, Home, Shelf, Record, Profile }

export enum AppBackgroundImportReason {
  InputTooLarge = 'inputTooLarge',
  InvalidImage = 'invalidImage',
  DimensionsTooLarge = 'dimensionsTooLarge',
  ReadFailed = 'readFailed',
  DecodeFailed = 'decodeFailed',
  EncodeFailed = 'encodeFailed',
  SaveFailed = 'saveFailed'
}

export class AppBackgroundImportError extends Error {
  reason: AppBackgroundImportReason;
  originalCode: number;

  constructor(reason: AppBackgroundImportReason, originalCode: number = 0, message: string = '') {
    super(message || reason);
    this.name = 'AppBackgroundImportError';
    this.reason = reason;
    this.originalCode = originalCode;
  }
}

export class AppBackgroundConfig {
  preset: string = 'theme';
  imageFile: string = '';
  /** 0–80%，深色模式在渲染端补足最低遮罩。 */
  veil: number = 22;
  blur: number = 0;
  positionX: number = 50;
  positionY: number = 50;
  scale: number = 100;
  surfaceOpacity: number = 92;

  copy(): AppBackgroundConfig {
    return AppBackgroundConfig.normalize(this);
  }

  static validImageFile(name: string): boolean {
    return typeof name === 'string' && /^background_[0-9]+_[0-9]+\.(png|jpg)$/.test(name);
  }

  private static bounded(value: number, fallback: number, low: number, high: number): number {
    return typeof value === 'number' && Number.isFinite(value) ? Math.max(low, Math.min(high, value)) : fallback;
  }

  static normalize(value: AppBackgroundConfig | null | undefined): AppBackgroundConfig {
    const next = new AppBackgroundConfig();
    if (!value || typeof value !== 'object') return next;
    if (value.preset === 'paper' || value.preset === 'mist' || value.preset === 'image') next.preset = value.preset;
    next.imageFile = AppBackgroundConfig.validImageFile(value.imageFile) ? value.imageFile : '';
    if (next.preset === 'image' && !next.imageFile) next.preset = 'theme';
    next.veil = AppBackgroundConfig.bounded(value.veil, 22, 0, 80);
    next.blur = AppBackgroundConfig.bounded(value.blur, 0, 0, 16);
    next.positionX = AppBackgroundConfig.bounded(value.positionX, 50, 0, 100);
    next.positionY = AppBackgroundConfig.bounded(value.positionY, 50, 0, 100);
    next.scale = AppBackgroundConfig.bounded(value.scale, 100, 100, 180);
    next.surfaceOpacity = AppBackgroundConfig.bounded(value.surfaceOpacity, 92, 82, 100);
    return next;
  }
}

export class AppPageBackground {
  followCommon: boolean = true;
  config: AppBackgroundConfig = new AppBackgroundConfig();

  copy(): AppPageBackground {
    return AppPageBackground.normalize(this);
  }

  static normalize(value: AppPageBackground | null | undefined): AppPageBackground {
    const next = new AppPageBackground();
    if (!value || typeof value !== 'object') return next;
    next.followCommon = value.followCommon !== false;
    next.config = AppBackgroundConfig.normalize(value.config);
    return next;
  }
}

/** 任何页面独立配置都保留，包括当前选择跟随通用时暂不显示的图片。 */
export class AppBackgroundSelection {
  schemaVersion: number = 1;
  common: AppBackgroundConfig = new AppBackgroundConfig();
  home: AppPageBackground = new AppPageBackground();
  shelf: AppPageBackground = new AppPageBackground();
  record: AppPageBackground = new AppPageBackground();
  profile: AppPageBackground = new AppPageBackground();

  page(scene: AppBackgroundScene): AppPageBackground {
    switch (scene) {
      case AppBackgroundScene.Home: return this.home;
      case AppBackgroundScene.Shelf: return this.shelf;
      case AppBackgroundScene.Record: return this.record;
      case AppBackgroundScene.Profile: return this.profile;
      default: throw new Error('Common background has no page override');
    }
  }

  resolve(scene: AppBackgroundScene): AppBackgroundConfig {
    if (scene === AppBackgroundScene.Common) return this.common;
    const page = this.page(scene);
    return page.followCommon ? this.common : page.config;
  }

  configs(): AppBackgroundConfig[] {
    return [this.common, this.home.config, this.shelf.config, this.record.config, this.profile.config];
  }

  imageFiles(): string[] {
    const files: string[] = [];
    for (const config of this.configs()) {
      // 切换预设时仍保留上次自选图，便于重新选择；所有保留引用都参与回收判断。
      if (AppBackgroundConfig.validImageFile(config.imageFile) && !files.includes(config.imageFile)) {
        files.push(config.imageFile);
      }
    }
    return files;
  }

  copy(): AppBackgroundSelection {
    const next = new AppBackgroundSelection();
    next.common = AppBackgroundConfig.normalize(this.common);
    next.home = AppPageBackground.normalize(this.home);
    next.shelf = AppPageBackground.normalize(this.shelf);
    next.record = AppPageBackground.normalize(this.record);
    next.profile = AppPageBackground.normalize(this.profile);
    return next;
  }

  static decode(raw: string): AppBackgroundSelection {
    if (!raw || raw.length > 8192) return new AppBackgroundSelection();
    try {
      const parsed: AppBackgroundSelection | null = JSON.parse(raw);
      if (!parsed || typeof parsed !== 'object' || parsed.schemaVersion !== 1) return new AppBackgroundSelection();
      const next = new AppBackgroundSelection();
      next.common = AppBackgroundConfig.normalize(parsed.common);
      next.home = AppPageBackground.normalize(parsed.home);
      next.shelf = AppPageBackground.normalize(parsed.shelf);
      next.record = AppPageBackground.normalize(parsed.record);
      next.profile = AppPageBackground.normalize(parsed.profile);
      return next;
    } catch (_error) {
      return new AppBackgroundSelection();
    }
  }
}
