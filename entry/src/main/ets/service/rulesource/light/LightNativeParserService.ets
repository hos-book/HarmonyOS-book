import { taskpool } from '@kit.ArkTS';
import { parseNativeRule } from './LightNativeParserWorker';

/** Bounded queue; parsing owns no application state and never falls back to the UI thread. */
export class LightNativeParserService {
  private static chain: Promise<void> = Promise.resolve();
  private static pending: number = 0;

  static async run(input: string, cancelled: () => boolean, priority: number): Promise<string> {
    if (cancelled()) throw new Error('解析已取消');
    if (input.length > 8 * 1024 * 1024) throw new Error('解析输入超过 8 MiB');
    if (LightNativeParserService.pending >= 16) throw new Error('解析队列已满');
    LightNativeParserService.pending++;
    const task = LightNativeParserService.chain.then(async (): Promise<string> => {
      if (cancelled()) throw new Error('解析已取消');
      const result = String(await taskpool.execute(new taskpool.Task(parseNativeRule, input),
        priority === 2 ? taskpool.Priority.HIGH : taskpool.Priority.LOW));
      if (cancelled()) throw new Error('解析已取消');
      return result;
    });
    LightNativeParserService.chain = task.then((): void => {}, (): void => {});
    try { return await task; } finally { LightNativeParserService.pending--; }
  }
}
