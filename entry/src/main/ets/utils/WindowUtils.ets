import { window } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PlatformCompat } from './PlatformCompat';

interface SafeAreaInsets {
  top: number;
  bottom: number;
}

/**
 * 沉浸式 + 安全区域工具
 * 全屏布局 + 透明系统栏，业务页面用 expandSafeArea 自行延伸
 */
export class WindowUtils {
  private static topPx: number = 0;
  private static bottomPx: number = 0;
  private static leftPx: number = 0;
  private static rightPx: number = 0;
  private static systemBottomPx: number = 0;
  private static density: number = 3.25;
  private static mainWindow: window.Window | null = null;
  private static safeAreaListeners: Array<(topVp: number, bottomVp: number) => void> = [];
  private static layoutRefreshTimerId: number = -1;
  private static settledRefreshTimerId: number = -1;
  private static readonly FALLBACK_BOTTOM_SAFE_VP: number = 24;
  /** 当前生效的深浅色模式（由 EntryAbility 的 config / onConfigurationUpdate 同步） */
  private static colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  /** 最近一次页面请求的状态栏诉求：true=强制白字(深色背景页)，false=跟随系统 */
  private static forceLight: boolean = false;
  private static readerActive: boolean = false;
  private static readerStatusBarVisible: boolean = true;
  private static readerStatusBarLight: boolean = false;
  private static cutoutTopPx: number = 0;
  private static readerWindowShape: string = '';
  private static readerTopPx: number = 0;
  private static readerStatusBarUpdate: Promise<void> = Promise.resolve();

  /** 由阅读路由的显示/隐藏生命周期控制，覆盖跳转详情后返回的场景。 */
  static setReaderActive(active: boolean): void {
    if (WindowUtils.readerActive === active) return;
    WindowUtils.readerTopPx = active ? WindowUtils.topPx : 0;
    WindowUtils.readerActive = active;
    // 首次绘制前就使用阅读安全区，不等待系统栏动画或异步回调。
    WindowUtils.refreshAvoidArea();
    WindowUtils.updateReaderStatusBar();
  }

  static setReaderStatusBarVisible(visible: boolean): void {
    if (WindowUtils.readerStatusBarVisible === visible) return;
    WindowUtils.readerStatusBarVisible = visible;
    if (WindowUtils.readerActive) WindowUtils.updateReaderStatusBar();
  }

  private static updateReaderStatusBar(): void {
    // 显隐只作用于系统状态栏，阅读安全区不随它收缩。
    WindowUtils.readerStatusBarUpdate = WindowUtils.readerStatusBarUpdate.then(async (): Promise<void> => {
      const win = WindowUtils.mainWindow;
      if (win === null) return;
      await win.setSpecificSystemBarEnabled('status',
        !WindowUtils.readerActive || WindowUtils.readerStatusBarVisible, false);
      await WindowUtils.applySystemBarContent();
      WindowUtils.refreshAvoidArea();
    }).catch((): void => {
      // 窗口销毁或切换期间忽略失败，下次页面切换重新应用。
    });
  }

  static async setupImmersive(stage: window.WindowStage, colorMode?: ConfigurationConstant.ColorMode): Promise<void> {
    const win = await stage.getMainWindow();
    const previousWindow = WindowUtils.mainWindow;
    if (previousWindow !== null) {
      try {
        previousWindow.off('avoidAreaChange', WindowUtils.handleAvoidAreaChange);
        previousWindow.off('windowSizeChange', WindowUtils.handleWindowSizeChange);
        previousWindow.off('windowStatusDidChange', WindowUtils.handleWindowStatusDidChange);
      } catch (_e) { /* ignore */ }
    }
    WindowUtils.cancelPendingRefreshes();
    WindowUtils.mainWindow = win;
    if (colorMode !== undefined) {
      WindowUtils.colorMode = colorMode;
    }
    // 先注册窗口监听；电脑没有手机系统栏时，样式能力失败不能中断尺寸/安全区同步。
    win.on('avoidAreaChange', WindowUtils.handleAvoidAreaChange);
    win.on('windowSizeChange', WindowUtils.handleWindowSizeChange);
    if (canIUse('SystemCapability.Window.SessionManager')) {
      win.on('windowStatusDidChange', WindowUtils.handleWindowStatusDidChange);
    }
    try {
      await win.setWindowLayoutFullScreen(true);
      await win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000'
      });
    } catch (_e) { /* 无手机系统栏的窗口保留系统默认装饰。 */ }
    try {
      if (PlatformCompat.supports(26)) {
        await win.setFloatNavigationAvoidAreaEnabled(true);
      }
    } catch (_e) {
      // Keep the regular system/nav-indicator fallback on devices without float-navigation support.
    }
    try { await WindowUtils.applySystemBarContent(); } catch (_e) { /* 系统栏能力可选。 */ }
    WindowUtils.refreshAvoidArea();
  }

  static releaseWindow(): void {
    const win = WindowUtils.mainWindow;
    WindowUtils.cancelPendingRefreshes();
    if (win !== null) {
      try { win.off('avoidAreaChange', WindowUtils.handleAvoidAreaChange); } catch (_e) {}
      try { win.off('windowSizeChange', WindowUtils.handleWindowSizeChange); } catch (_e) {}
      try { win.off('windowStatusDidChange', WindowUtils.handleWindowStatusDidChange); } catch (_e) {}
    }
    WindowUtils.mainWindow = null;
    WindowUtils.readerWindowShape = '';
  }

  static minimize(): void {
    const win = WindowUtils.mainWindow;
    if (win === null || !canIUse('SystemCapability.Window.SessionManager')) return;
    try { win.minimize().catch((): void => {}); } catch (_e) {}
  }

  static getWindowWidthVp(): number {
    try {
      const win = WindowUtils.mainWindow;
      if (win !== null) {
        const width = win.getWindowProperties().windowRect.width;
        if (width > 0) return win.getUIContext().px2vp(width);
      }
    } catch (_e) {}
    return 360;
  }

  static getWindowHeightVp(): number {
    try {
      const win = WindowUtils.mainWindow;
      if (win !== null) {
        const height = win.getWindowProperties().windowRect.height;
        if (height > 0) return win.getUIContext().px2vp(height);
      }
    } catch (_e) {}
    return 640;
  }

  static addSafeAreaListener(listener: (topVp: number, bottomVp: number) => void): void {
    if (WindowUtils.safeAreaListeners.indexOf(listener) < 0) {
      WindowUtils.safeAreaListeners.push(listener);
    }
    listener(WindowUtils.getStatusBarHeightVp(), WindowUtils.getBottomSafeVp());
  }

  static removeSafeAreaListener(listener: (topVp: number, bottomVp: number) => void): void {
    const index = WindowUtils.safeAreaListeners.indexOf(listener);
    if (index >= 0) WindowUtils.safeAreaListeners.splice(index, 1);
  }

  static refreshAvoidArea(): void {
    const currentWindow = WindowUtils.mainWindow;
    if (currentWindow === null) return;
    WindowUtils.syncAvoidArea(currentWindow);
    WindowUtils.scheduleAvoidAreaRefresh();
  }

  /**
   * 设置状态栏/导航栏文字色。
   * @param isLight true 强制白字（用于封面/播放器等始终深色背景的页面）；
   *                false 跟随系统深浅色（浅色→黑字，深色→白字）。
   */
  static async setStatusBarLight(isLight: boolean): Promise<void> {
    WindowUtils.forceLight = isLight;
    await WindowUtils.applySystemBarContent();
  }

  static async setReaderStatusBarLight(isLight: boolean): Promise<void> {
    WindowUtils.readerStatusBarLight = isLight;
    if (WindowUtils.readerActive) await WindowUtils.applySystemBarContent();
  }

  /** 与 HDS/Navigation 页面级状态栏样式保持同一套深浅色判断。 */
  static getSystemBarContentColor(): string {
    if (WindowUtils.readerActive) return WindowUtils.readerStatusBarLight ? '#FFFFFFFF' : '#FF000000';
    const isDark = WindowUtils.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    return WindowUtils.forceLight || isDark ? '#FFFFFFFF' : '#FF000000';
  }

  /** 深浅色模式变更时调用（EntryAbility.onConfigurationUpdate），重新刷新当前状态栏字色 */
  private static readerColorListeners: Set<() => void> = new Set();

  static isDarkMode(): boolean {
    return WindowUtils.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  static addReaderColorListener(listener: () => void): void {
    WindowUtils.readerColorListeners.add(listener);
  }

  static removeReaderColorListener(listener: () => void): void {
    WindowUtils.readerColorListeners.delete(listener);
  }

  static updateColorMode(colorMode: ConfigurationConstant.ColorMode): void {
    if (WindowUtils.colorMode === colorMode) {
      WindowUtils.updateReaderStatusBar();
      return;
    }
    WindowUtils.colorMode = colorMode;
    WindowUtils.readerColorListeners.forEach((listener: () => void): void => listener());
    WindowUtils.applySystemBarContent().catch(() => { /* ignore */ });
  }

  private static async applySystemBarContent(): Promise<void> {
    if (!WindowUtils.mainWindow) return;
    const content = WindowUtils.getSystemBarContentColor();
    await WindowUtils.mainWindow.setWindowSystemBarProperties({
      statusBarContentColor: content,
      navigationBarContentColor: content
    });
  }

  static getCutoutTopVp(): number { return WindowUtils.cutoutTopPx / WindowUtils.density; }

  static getStatusBarHeightVp(): number {
    return WindowUtils.topPx / WindowUtils.density;
  }

  static getBottomSafeVp(): number {
    const measuredVp = WindowUtils.bottomPx / WindowUtils.density;
    return Math.max(measuredVp, WindowUtils.FALLBACK_BOTTOM_SAFE_VP);
  }

  static getLeftSafeVp(): number {
    return WindowUtils.leftPx / WindowUtils.density;
  }

  static getRightSafeVp(): number {
    return WindowUtils.rightPx / WindowUtils.density;
  }

  /** TYPE_SYSTEM 底部分量：大于 0 说明是三键导航等实体底栏，需要完整避让。 */
  static getSystemBottomVp(): number {
    return WindowUtils.systemBottomPx / WindowUtils.density;
  }

  static getSafeAreaInsets(): SafeAreaInsets {
    return {
      top: WindowUtils.getStatusBarHeightVp(),
      bottom: WindowUtils.getBottomSafeVp()
    };
  }

  static pxToVp(valuePx: number): number {
    return valuePx / WindowUtils.density;
  }

  static vpToPx(valueVp: number): number {
    return valueVp * WindowUtils.density;
  }

  /** 按所在屏幕的物理对角线分档，窗口缩放和字体大小不影响页面转场时长。 */
  static getPageTransitionDuration(): number {
    try {
      const displayId = WindowUtils.mainWindow?.getWindowProperties().displayId;
      const screen = displayId === undefined ? display.getDefaultDisplaySync() : display.getDisplayByIdSync(displayId);
      if (!Number.isFinite(screen.width) || !Number.isFinite(screen.height) ||
        !Number.isFinite(screen.xDPI) || !Number.isFinite(screen.yDPI) ||
        screen.width <= 0 || screen.height <= 0 || screen.xDPI <= 0 || screen.yDPI <= 0) return 450;
      const widthInches = screen.width / screen.xDPI;
      const heightInches = screen.height / screen.yDPI;
      const diagonalInches = Math.sqrt(widthInches * widthInches + heightInches * heightInches);
      // 缓入缓出首尾的微小位移可能不计入可见帧；为 200/250/300ms 下限保留余量。
      if (diagonalInches < 8.5) return 320;
      return diagonalInches <= 12 ? 380 : 450;
    } catch (_e) {
      // 屏幕信息不可用时按最高下限兜底，避免未知大屏使用过短的转场。
      return 450;
    }
  }

  // 与 MainPage 中常量保持一致
  private static readonly FLOATING_TAB_HEIGHT: number = 60;
  private static readonly FLOATING_GAP: number = 12;
  private static readonly FLOATING_BOTTOM: number = 4;

  /**
   * TabContent 底部需要为浮动 Tab 栏让出的高度(vp)。
   * 计算公式: bottomSafe + FLOATING_BOTTOM + FLOATING_TAB_HEIGHT + FLOATING_GAP
   * 说明: FloatingTabBar 内部用 padding-bottom = bottomSafe 把自身抬到导航条之上,
   *       所以业务页留出的高度也要包含 bottomSafe,否则最后一行会被手势条遮住一截。
   */
  static getFloatingTabBottomVp(bottomSafeVp?: number): number {
    const safeBottom = bottomSafeVp !== undefined ? bottomSafeVp : WindowUtils.getBottomSafeVp();
    return safeBottom +
           WindowUtils.FLOATING_BOTTOM +
           WindowUtils.FLOATING_TAB_HEIGHT +
           WindowUtils.FLOATING_GAP;
  }

  private static handleAvoidAreaChange(_data: window.AvoidAreaOptions): void {
    WindowUtils.refreshAvoidArea();
  }

  private static handleWindowSizeChange(_size: window.Size): void {
    WindowUtils.refreshAvoidArea();
  }

  private static handleWindowStatusDidChange(_status: window.WindowStatusType): void {
    WindowUtils.refreshAvoidArea();
  }

  private static cancelPendingRefreshes(): void {
    if (WindowUtils.layoutRefreshTimerId !== -1) {
      clearTimeout(WindowUtils.layoutRefreshTimerId);
      WindowUtils.layoutRefreshTimerId = -1;
    }
    if (WindowUtils.settledRefreshTimerId !== -1) {
      clearTimeout(WindowUtils.settledRefreshTimerId);
      WindowUtils.settledRefreshTimerId = -1;
    }
  }

  private static scheduleAvoidAreaRefresh(): void {
    WindowUtils.cancelPendingRefreshes();
    WindowUtils.layoutRefreshTimerId = setTimeout((): void => {
      WindowUtils.layoutRefreshTimerId = -1;
      const currentWindow = WindowUtils.mainWindow;
      if (currentWindow !== null) WindowUtils.syncAvoidArea(currentWindow);
    }, 32);
    WindowUtils.settledRefreshTimerId = setTimeout((): void => {
      WindowUtils.settledRefreshTimerId = -1;
      const currentWindow = WindowUtils.mainWindow;
      if (currentWindow !== null) WindowUtils.syncAvoidArea(currentWindow);
    }, 240);
  }

  private static notifySafeAreaChange(): void {
    const topVp = WindowUtils.getStatusBarHeightVp();
    const bottomVp = WindowUtils.getBottomSafeVp();
    WindowUtils.safeAreaListeners.forEach((listener: (topVp: number, bottomVp: number) => void): void => {
      listener(topVp, bottomVp);
    });
  }

  private static readAvoidArea(win: window.Window, type: window.AvoidAreaType): window.AvoidArea | null {
    try {
      return win.getWindowAvoidArea(type);
    } catch (_e) {
      return null;
    }
  }

  private static updateDensity(win: window.Window): void {
    try {
      const densityInfo = win.getWindowDensityInfo();
      const windowDensity = densityInfo.customDensity > 0 ? densityInfo.customDensity : densityInfo.systemDensity;
      if (windowDensity > 0) {
        WindowUtils.density = windowDensity;
        return;
      }
    } catch (_e) { /* use display density */ }
    const displayDensity = display.getDefaultDisplaySync().densityPixels;
    if (displayDensity > 0) WindowUtils.density = displayDensity;
  }

  private static syncAvoidArea(win: window.Window): void {
    try {
      // 最小化时系统可能上报空避让区，不能用它重排仍在栈顶的阅读页。
      if (WindowUtils.readerActive && win.getWindowStatus() === window.WindowStatusType.MINIMIZE) return;
      WindowUtils.updateDensity(win);
      const systemArea = WindowUtils.readAvoidArea(win, window.AvoidAreaType.TYPE_SYSTEM);
      const navigationArea = WindowUtils.readAvoidArea(win, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const floatNavigationArea = PlatformCompat.supports(26)
        ? WindowUtils.readAvoidArea(win, window.AvoidAreaType.TYPE_FLOAT_NAVIGATION) : null;
      const cutoutArea = WindowUtils.readAvoidArea(win, window.AvoidAreaType.TYPE_CUTOUT);
      const rect = win.getWindowProperties().windowRect;
      const shape = `${rect.width}:${rect.height}`;
      if (shape !== WindowUtils.readerWindowShape) {
        WindowUtils.readerTopPx = 0;
        WindowUtils.readerWindowShape = shape;
      }
      if (cutoutArea !== null) WindowUtils.cutoutTopPx = cutoutArea.topRect.top + cutoutArea.topRect.height;
      const windowWidthPx: number = rect.width;
      const sideAreas: Array<window.AvoidArea | null> = [
        systemArea, cutoutArea, navigationArea, floatNavigationArea
      ];
      let hasSideArea: boolean = false;
      let nextLeftPx: number = 0;
      let nextRightPx: number = 0;
      for (const area of sideAreas) {
        if (area === null) continue;
        hasSideArea = true;
        // 挖孔矩形可能不贴边，避让距离应包含矩形到窗口边缘的间隙。
        if (area.leftRect.width > 0) {
          nextLeftPx = Math.max(nextLeftPx, area.leftRect.left + area.leftRect.width);
        }
        if (area.rightRect.width > 0) {
          nextRightPx = Math.max(nextRightPx, windowWidthPx - area.rightRect.left);
        }
      }
      if (hasSideArea && windowWidthPx > 0) {
        WindowUtils.leftPx = Math.min(windowWidthPx, Math.max(0, nextLeftPx));
        WindowUtils.rightPx = Math.min(windowWidthPx, Math.max(0, nextRightPx));
      }
      let hasBottomArea: boolean = false;
      let nextBottomPx: number = 0;
      if (systemArea !== null) {
        WindowUtils.topPx = systemArea.topRect.height;
        WindowUtils.systemBottomPx = systemArea.bottomRect.height;
        if (WindowUtils.readerActive && win.getWindowStatus() === window.WindowStatusType.FULL_SCREEN) {
          // API 22 起直接取不受显隐影响的安全区；API 20–21 保留本次阅读已测得的高度。
          if (PlatformCompat.supports(22)) {
            try {
              WindowUtils.readerTopPx = win.getWindowAvoidAreaIgnoringVisibility(
                window.AvoidAreaType.TYPE_SYSTEM).topRect.height;
            } catch (_e) { /* use the measured inset below */ }
          }
          WindowUtils.readerTopPx = Math.max(WindowUtils.readerTopPx,
            systemArea.topRect.height, cutoutArea?.topRect.height ?? 0);
          WindowUtils.topPx = WindowUtils.readerTopPx;
        }
        nextBottomPx = Math.max(nextBottomPx, systemArea.bottomRect.height);
        hasBottomArea = true;
      }
      if (navigationArea !== null) {
        nextBottomPx = Math.max(nextBottomPx, navigationArea.bottomRect.height);
        hasBottomArea = true;
      }
      if (floatNavigationArea !== null) {
        nextBottomPx = Math.max(nextBottomPx, floatNavigationArea.bottomRect.height);
        hasBottomArea = true;
      }
      if (hasBottomArea) WindowUtils.bottomPx = nextBottomPx;
      WindowUtils.notifySafeAreaChange();
    } catch (_e) {
      // keep previous cached values
    }
  }
}
