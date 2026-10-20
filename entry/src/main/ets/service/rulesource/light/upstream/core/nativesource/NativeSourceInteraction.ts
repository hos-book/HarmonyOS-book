/**
 * 原生书源脚本与界面之间的端口：弹提示、刷新发现页、打开网页（可以等用户完成后取回页面）。
 *
 * 宿主在启动时用 setHandler 装上实现；没装时脚本里的 ui.*、browser.verify/open 报“当前环境不支持”。
 * 本文件不依赖系统 API，可直接在 Node 回归脚本中加载。
 */

export interface NativeBrowserRequest {
  url: string;
  title: string;
  sourceUrl: string;
  sourceName: string;
}

export interface NativeBrowserResult {
  /** 用户点「完成」时页面的 HTML；不等待时为空。 */
  body: string;
  /** 用户取消、超时等原因；成功时为空。 */
  error: string;
}

export interface NativeSourceInteractionHandler {
  toast(sourceName: string, message: string): void;
  /** 清掉这个书源的发现页缓存，让发现页重新加载。 */
  refreshExplore(sourceUrl: string): Promise<void>;
  /** wait 为 true 时等用户在网页里点「完成」（或取消）后返回；为 false 时打开即返回。 */
  openBrowser(request: NativeBrowserRequest, wait: boolean): Promise<NativeBrowserResult>;
}

export class NativeSourceInteraction {
  private static current: NativeSourceInteractionHandler | null = null;

  static setHandler(handler: NativeSourceInteractionHandler | null): void {
    NativeSourceInteraction.current = handler;
  }

  static handler(): NativeSourceInteractionHandler | null {
    return NativeSourceInteraction.current;
  }
}
