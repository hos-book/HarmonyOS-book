/**
 * 手机、折叠屏、平板和电脑共用容器断点，不用设备型号代替可用窗口尺寸。
 */
export class AdaptiveLayout {
  static readonly MEDIUM_WIDTH: number = 600;
  static readonly LARGE_WIDTH: number = 840;

  /** 左栏至少 320vp，右栏至少 400vp；窄折叠窗口不强行压缩正文。 */
  static navigationUsesColumns(width: number, paths: string[]): boolean {
    if (!Number.isFinite(width) || width < 720 || paths.length === 0) return false;
    // 沉浸页及其子页面沿用全宽，返回后再恢复双栏。
    return !paths.some((name: string): boolean =>
      name === 'reader' || name === 'comicReader' || name === 'player' || name === 'ruleSourceLogin');
  }

  /** 保留手机三列基线，大窗口增加信息量而不是无限放大封面。 */
  static bookColumns(width: number): number {
    if (!Number.isFinite(width) || width <= 0) return 3;
    if (width < 320) return 2;
    if (width < AdaptiveLayout.MEDIUM_WIDTH) return 3;
    return Math.max(4, Math.floor((width - 32) / 144));
  }

  /** 榜单每列上下两本，按榜单容器宽度展示一至三列。 */
  static rankingColumns(width: number): number {
    if (!Number.isFinite(width) || width < AdaptiveLayout.MEDIUM_WIDTH) return 1;
    return width < AdaptiveLayout.LARGE_WIDTH ? 2 : 3;
  }

  static playerUsesColumns(width: number, height: number): boolean {
    return width >= AdaptiveLayout.MEDIUM_WIDTH && height > 0;
  }

  /** 正文限宽，额外缩进不写入用户的阅读边距设置。 */
  static readerGutter(width: number, leftInset: number, rightInset: number, columns: boolean = false): number {
    return Math.max(0, (width - leftInset - rightInset - (columns ? 1320 : 760)) / 2);
  }

  private static readonly COMPACT_WIDTH: number = 360;
  private static readonly COMPACT_HEIGHT: number = 760;
  /** 播放页除封面外的固定垂直占用：标题最多两行时的安全预算。 */
  private static readonly PLAYER_FIXED_HEIGHT: number = 438;
  private static readonly PLAYER_MIN_COVER: number = 136;

  static isCompact(width: number, height: number): boolean {
    if (width <= 0 || height <= 0) return false;
    return width < AdaptiveLayout.COMPACT_WIDTH || height < AdaptiveLayout.COMPACT_HEIGHT;
  }

  static horizontalPadding(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 16 : 24;
  }

  static sectionSpacing(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 16 : 24;
  }

  static playerTopSpacing(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 8 : 12;
  }

  static playerBottomSpacing(width: number, height: number): number {
    // 紧凑窗口直接贴合系统安全区，把额外空间留给底部功能栏与播控区之间的间隔。
    return AdaptiveLayout.isCompact(width, height) ? 0 : 24;
  }

  static playerCoverSize(width: number, height: number): number {
    const horizontalSpace = AdaptiveLayout.horizontalPadding(width, height) * 2;
    const availableWidth = Math.max(152, width - horizontalSpace);
    // 优先用高度剩余空间收缩封面，确保两行标题、进度条和底部播控同屏。
    const heightBound = Math.max(
      AdaptiveLayout.PLAYER_MIN_COVER,
      Math.min(260, height - AdaptiveLayout.PLAYER_FIXED_HEIGHT)
    );
    return Math.min(availableWidth, heightBound);
  }

  static playerNeedsScroll(height: number): boolean {
    return height > 0 && height < AdaptiveLayout.PLAYER_FIXED_HEIGHT + AdaptiveLayout.PLAYER_MIN_COVER;
  }

  static detailHeroHeight(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 216 : 230;
  }

  static detailCoverWidth(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 84 : 100;
  }

  static detailCoverHeight(width: number, height: number): number {
    return AdaptiveLayout.isCompact(width, height) ? 109 : 130;
  }
}
