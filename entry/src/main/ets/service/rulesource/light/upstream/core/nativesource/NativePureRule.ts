/** 后台纯解析的路由规则。没有任何依赖，运行器可以引用它而不把选择器引擎带进来。 */
export class NativePureRule {
  /** 输入、输出各自的上限（UTF-16 代码单元）。调用方超过时应留在原线程解析。 */
  static readonly MAX_CHARS: number = 8 * 1024 * 1024;

  /**
   * 选择器规则能否离开原书源上下文解析。除了显式的 js:、<js>、{{ }}，AnalyzeRule 还会把
   * 同时含 result 和 + 的规则当 JS 求值（见 analyzeFirst），java. 调用也会进脚本引擎；
   * 这些在关闭同步 QuickJS 的工作线程里结果可能不同，一律留在原线程。
   */
  static isPure(rule: string): boolean {
    if (/js\s*:|<js>|\{\{|java\./i.test(rule)) return false;
    return !(rule.includes('result') && rule.includes('+'));
  }
}
