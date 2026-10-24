import { LightNativePureParser } from './LightNativePureParser';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Concurrent
export function parseNativeRule(input: string): string {
  const started = Date.now();
  try { return LightNativePureParser.run(input); }
  finally {
    hilog.info(0x0001, 'LightNativeParser', 'worker parse ms=%{public}d chars=%{public}d', Date.now() - started, input.length);
  }
}
