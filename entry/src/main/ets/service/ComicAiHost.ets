import { AbilityConstant, common } from '@kit.AbilityKit';
import { worker, util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo } from '@kit.CoreFileKit';
import lazy { AiHost, AiRuntime, ComicColorizer } from '@legado/aiengine';
import { ReaderCacheService } from './ReaderCacheService';
import { MembershipState } from '../model/MembershipState';

/** HAR 只负责着色；权限、缓存预算和 Worker 入口由应用提供。 */
export class ComicAiHost implements AiHost {
  private static installed: boolean = false;
  private static foreground: boolean = true;
  private context: common.Context;

  constructor(context: common.Context) { this.context = context; }

  static install(context: common.Context): void {
    ReaderCacheService.configure(context);
    AiRuntime.install(new ComicAiHost(context));
    ComicAiHost.installed = true;
    ComicColorizer.setAppForeground(ComicAiHost.foreground);
  }

  static setAppForeground(foreground: boolean): void {
    ComicAiHost.foreground = foreground;
    if (ComicAiHost.installed) ComicColorizer.setAppForeground(foreground);
  }

  static onMemoryPressure(level: AbilityConstant.MemoryLevel): void {
    if (!ComicAiHost.installed) return;
    if (ComicAiHost.foreground && level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_MODERATE) {
      // 中等余量先释放一次；后续用户请求可重建并复用，避免连续 60 秒每张都冷加载。
      // releaseIdleWorker 的 epoch 也让在途任务安全完成后释放，不强杀原生推理。
      ComicColorizer.releaseIdleWorker();
      console.info(`[ComicAiMemory] level=${level} action=release-once`);
    } else {
      ComicColorizer.onMemoryPressure();
      console.info(`[ComicAiMemory] level=${level} action=cooldown`);
    }
  }

  isAllowed(feature: string): boolean {
    return feature === 'colorization' && MembershipState.current.hasAccess;
  }

  cacheDir(): string { return this.context.cacheDir; }

  async downloadImage(_source: string): Promise<Uint8Array> {
    // 仅接受公共图片加载链已经缓存的本地原图，无远程上传或二次下载。
    throw new Error('comic_ai_local_image_required');
  }

  async downloadColorModel(file: string, destination: string, bytes: number, active: () => boolean,
    progress: (received: number) => void): Promise<void> {
    if (!['alac.ms', 'alac-npu-portrait.ms', 'alac-npu-landscape.ms'].includes(file) ||
      !destination.startsWith(`${this.context.filesDir}/comic_colorizer/`)) {
      throw new Error('comic_ai_request_failed');
    }
    const resource = `comic-colorizer/${file}`;
    const input = await this.context.resourceManager.getRawFd(resource);
    try {
      if (input.length !== bytes) throw new Error('comic_ai_request_failed');
      const output = await fileIo.open(destination,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        let received = 0;
        while (received < bytes) {
          if (!active() || !this.isAllowed('colorization')) throw new Error('comic_ai_request_failed');
          const chunk = new ArrayBuffer(Math.min(1024 * 1024, bytes - received));
          const count = await fileIo.read(input.fd, chunk, { offset: input.offset + received, length: chunk.byteLength });
          if (count <= 0) throw new Error('comic_ai_request_failed');
          let written = 0;
          while (written < count) {
            const size = await fileIo.write(output.fd, chunk.slice(written, count));
            if (size <= 0) throw new Error('comic_ai_request_failed');
            written += size;
          }
          received += count;
          progress(received);
        }
      } finally { await fileIo.close(output); }
    } finally { await this.context.resourceManager.closeRawFd(resource); }
  }

  digestHashHex(algorithm: string, value: string): string {
    if (algorithm !== 'SHA256') throw new Error('comic_ai_hash_unsupported');
    const digest = cryptoFramework.createMd('SHA256');
    digest.updateSync({ data: new util.TextEncoder().encodeInto(value) });
    let hex = '';
    for (const byte of digest.digestSync().data) hex += byte.toString(16).padStart(2, '0');
    return hex;
  }

  touchComicFile(path: string): void {
    ReaderCacheService.record([path]).catch((): void => {});
  }

  noteComicWrite(): void {
    // 成功结果由 ComicColorizationService 按返回路径登记；失败时再 reconcile。
    // 每张图都使索引失效，会让结果返回等待整个阅读缓存重新扫描。
  }

  resolveImageSource(marker: string): string { return marker; }

  createColorWorker(): worker.ThreadWorker {
    return new worker.ThreadWorker('entry/ets/workers/ComicColorWorker.ets', { name: 'ComicColorWorker' });
  }
}
