import { hiTraceMeter } from '@kit.PerformanceAnalysisKit';

/** 本机按需 Trace：使用固定业务名称，不记录正文、书名、地址或账号。API 19+。 */
export class PerformanceTrace {
  private static sequence: number = 0;

  static begin(name: string): number {
    try {
      if (!hiTraceMeter.isTraceEnabled()) return -1;
      PerformanceTrace.sequence = (PerformanceTrace.sequence + 1) % 0x7fffffff;
      const id = PerformanceTrace.sequence;
      hiTraceMeter.startAsyncTrace(hiTraceMeter.HiTraceOutputLevel.INFO, name, id, 'reader');
      return id;
    } catch (_error) {
      return -1;
    }
  }

  static end(name: string, id: number): void {
    if (id < 0) return;
    try {
      hiTraceMeter.finishAsyncTrace(hiTraceMeter.HiTraceOutputLevel.INFO, name, id);
    } catch (_error) { /* 性能采集不可影响业务结果。 */ }
  }
}
