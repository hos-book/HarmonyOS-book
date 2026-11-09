/**
 * WebEngineGate - 隐藏 Web 宿主的按需挂载门控
 *
 * 导入规则需要网页渲染或媒体嗅探时使用隐藏 Web 宿主。
 * 本门控让宿主仅在首次真正需要时挂载。单调置位（false→true 永不回退），挂上不卸，
 * 避免卸载→controller 野引用的竞态。
 *
 * 模式仿 AuthService：@ObservedV2 + static get instance() + @Trace，UI 直接读字段即可响应。
 */
@ObservedV2
export class WebEngineGate {
  private static _instance: WebEngineGate | null = null;

  static get instance(): WebEngineGate {
    if (!WebEngineGate._instance) {
      WebEngineGate._instance = new WebEngineGate();
    }
    return WebEngineGate._instance;
  }

  /** 本地规则执行到 CSS/XPath 时才挂载 DOM 解析宿主。 */
  @Trace needRuleParser: boolean = false;
  @Trace needRuleBrowser: boolean = false;
}
