/** App 外观偏好。阅读纸张主题独立保存，不随 App 强调色变化。 */
@ObservedV2
export class AppAppearance {
  static readonly defaultAccent: string = '#C4475B';
  private static singleton: AppAppearance | null = null;

  static get current(): AppAppearance {
    if (AppAppearance.singleton === null) {
      AppAppearance.singleton = new AppAppearance();
    }
    return AppAppearance.singleton;
  }

  /** 2 强、3 均衡、4 弱；兼容旧超薄/超厚偏好。 */
  @Trace material: number = 3;
  /** 空字符串表示使用默认玫瑰红。 */
  @Trace accent: string = '';
  /** 当前套装；继续与阅读纸张和桌面应用图标独立保存。 */
  @Trace themeBundleId: string = 'default';

  static normalizeMaterial(value: number): number {
    if (value === 1 || value === 2) return 2;
    if (value === 4 || value === 5) return 4;
    return 3;
  }

  static normalizeAccent(value: string): string {
    const hex: string = value.trim().toUpperCase();
    return /^#[0-9A-F]{6}$/.test(hex) ? hex : '';
  }

  static shade(hex: string, scale: number): string {
    const red: number = Math.round(parseInt(hex.substring(1, 3), 16) * scale);
    const green: number = Math.round(parseInt(hex.substring(3, 5), 16) * scale);
    const blue: number = Math.round(parseInt(hex.substring(5, 7), 16) * scale);
    return '#' + red.toString(16).padStart(2, '0') + green.toString(16).padStart(2, '0') +
      blue.toString(16).padStart(2, '0');
  }

  static foreground(hex: string): string {
    const red: number = parseInt(hex.substring(1, 3), 16);
    const green: number = parseInt(hex.substring(3, 5), 16);
    const blue: number = parseInt(hex.substring(5, 7), 16);
    return red * 0.299 + green * 0.587 + blue * 0.114 > 165 ? '#191919' : '#FFFFFF';
  }
}
