import { PreferenceService } from '../PreferenceService';

/** 按全局章数顺序预取；换章取消旧队列，始终只运行一个后台正文请求。 */
export class TextChapterPreloader {
  private generation: number = 0;
  private queue: Promise<void> = Promise.resolve();

  start(current: number, total: number, fetch: (index: number) => Promise<void>,
    active: () => boolean): void {
    const generation = ++this.generation;
    this.queue = this.queue.catch((): void => {}).then(async (): Promise<void> => {
      for (let index = current + 1; index < total; index++) {
        if (generation !== this.generation || !active()) return;
        const count = await PreferenceService.getPreloadChapters();
        if (generation !== this.generation || !active() || index - current > count) return;
        try { await fetch(index); } catch (_error) { /* 单章失败不阻塞后续预取或当前阅读。 */ }
      }
    }).catch((): void => { /* 偏好未就绪时跳过预取，正文按需加载不受影响。 */ });
  }

  cancel(): void { this.generation++; }
}
