import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer, util } from '@kit.ArkTS';
import lazy { ComicColorizer } from '@legado/aiengine';
import { ComicAiHost } from './ComicAiHost';
import { ComicTranslationService } from './ComicTranslationService';
import { ComicOfflineTranslationService } from './ComicOfflineTranslationService';
import { ReaderCacheService } from './ReaderCacheService';
import { MembershipState } from '../model/MembershipState';

/** 仅处理用户主动开启后的可见图片，原图不覆盖，队列和派生缓存均有界。 */
export class ComicColorizationService {
  private static queue: Promise<void> = Promise.resolve();
  private static pending: number = 0;
  private static blockedRevision: number = -1;
  private static revision: number = 0;
  private static engineUsed: boolean = false;

  static supported(): boolean { return canIUse('SystemCapability.AI.MindSporeLite'); }

  static resetFailure(): void {
    ComicColorizationService.revision++;
    ComicColorizationService.blockedRevision = -1;
  }

  static release(): void {
    ComicColorizationService.resetFailure();
    if (ComicColorizationService.engineUsed) ComicColorizer.releaseIdleWorker();
  }

  static prepare(context: common.Context, active: () => boolean): void {
    if (!active() || !ComicColorizationService.supported()) return;
    const revision = ComicColorizationService.revision;
    ComicAiHost.install(context);
    ComicColorizationService.engineUsed = true;
    ComicColorizer.prepare(context, (): boolean => active() &&
      revision === ComicColorizationService.revision).catch((): void => {});
  }

  static async colorize(context: common.Context, uri: string, active: () => boolean): Promise<string> {
    return ComicColorizationService.transform(context, uri, active, '');
  }

  static async transform(context: common.Context, uri: string, active: () => boolean,
    targetLanguage: string, colorization: boolean = false, trace: string = ''): Promise<string> {
    if (targetLanguage) ComicOfflineTranslationService.validateDirection(targetLanguage);
    const permitted = (): boolean => !targetLanguage || MembershipState.current.hasAccess;
    if (!active() || !permitted()) return '';
    if (ComicColorizationService.pending >= 4) return '';
    const revision = ComicColorizationService.revision;
    const queuedAt = Date.now();
    let dispatchedAt = 0;
    const operation = targetLanguage ? (colorization ? 'color+translate' : 'translate') : 'color';
    console.info(`[ComicAiQueue] trace=${trace} operation=${operation} ahead=${ComicColorizationService.pending}`);
    ComicColorizationService.pending++;
    const job = ComicColorizationService.queue.then(async (): Promise<string> => {
      if (!active() || !permitted() || revision !== ComicColorizationService.revision) return '';
      if (ComicColorizationService.blockedRevision === revision) return '';
      dispatchedAt = Date.now();
      ReaderCacheService.configure(context);
      ReaderCacheService.beginComicWrite();
      ReaderCacheService.hold(uri);
      try {
        const allowed = (): boolean => active() && permitted() && revision === ComicColorizationService.revision;
        // 双开时在着色结果上绘制译文，避免两个独立结果互相覆盖。
        let input = uri;
        if (colorization && targetLanguage) {
          input = await ComicColorizationService.process(context, uri, allowed, '');
          if (!allowed() || !input) return '';
        }
        ReaderCacheService.hold(input);
        try {
          const result = await ComicColorizationService.process(context, input, allowed, targetLanguage);
          return allowed() ? result : '';
        } finally { ReaderCacheService.unhold(input); }
      } catch (error) {
        if (active() && permitted() && revision === ComicColorizationService.revision) {
          // 失败后停掉本轮队列，保留原图，重新开启后允许重试。
          ComicColorizationService.blockedRevision = revision;
          throw error instanceof Error ? error : new Error('comic_ai_request_failed');
        }
        return '';
      } finally { ReaderCacheService.unhold(uri); ReaderCacheService.endComicWrite(); }
    });
    ComicColorizationService.queue = job.then((): void => {}, (): void => {});
    let status = 'error';
    try {
      const result = await job;
      status = result ? 'ready' : 'discarded';
      return result;
    } finally {
      ComicColorizationService.pending--;
      const finishedAt = Date.now();
      const queueMs = (dispatchedAt || finishedAt) - queuedAt;
      console.info(`[ComicAiTiming] trace=${trace} operation=${operation} status=${status} ` +
        `queue=${queueMs}ms work=${dispatchedAt > 0 ? finishedAt - dispatchedAt : 0}ms total=${finishedAt - queuedAt}ms`);
    }
  }

  private static async process(context: common.Context, uri: string, active: () => boolean,
    targetLanguage: string): Promise<string> {
    if (!uri.startsWith('file://')) return '';
    const inputPath = new fileUri.FileUri(uri).path;
    const importedRoot = `${context.filesDir}/ebooks/`;
    const importedImage = inputPath.startsWith(importedRoot) &&
      /^import_[A-Za-z0-9_]+\/image_\d+_\d+\.img$/.test(inputPath.substring(importedRoot.length));
    // EPUB 原图位于持久目录；直接交给引擎读取，派生结果仍由缓存管理。
    const coloredImage = inputPath.startsWith(`${context.cacheDir}/comic_colorization_v1/`) &&
      /^[a-f0-9]+\.jpg$/.test(inputPath.substring(`${context.cacheDir}/comic_colorization_v1/`.length));
    if (!inputPath.startsWith(`${context.cacheDir}/comic_images/`) && !coloredImage && !importedImage) return '';
    const stat = await fileIo.stat(inputPath);
    if (stat.size <= 0 || stat.size > 20 * 1024 * 1024) throw new Error('comic_ai_image_too_large');
    if (!targetLanguage) {
      if (!ComicColorizationService.supported()) throw new Error('comic_ai_color_unsupported');
      if (!active()) return '';
      ComicAiHost.install(context);
      ComicColorizationService.engineUsed = true;
      try {
        const result = await ComicColorizer.colorize(context, uri, active, (_status: string): void => {});
        const recordedAt = Date.now();
        // 即使此时离屏，已写出的结果也必须进入预算；写入租约覆盖登记过程。
        await ReaderCacheService.record([result.uri]);
        console.info(`[ComicAiCache] record=${Date.now() - recordedAt}ms`);
        return active() ? result.uri : '';
      } catch (_error) {
        // 引擎可能在写入后取消且未返回路径，仅异常路径需要重新发现遗留文件。
        ReaderCacheService.reconcile();
        if (!active()) return '';
        throw new Error('comic_ai_color_failed');
      }
    }
    const digest = cryptoFramework.createMd('SHA256');
    const operation = `translate-offline-v2:${targetLanguage}`;
    await digest.update({ data: new util.TextEncoder().encodeInto(
      `${operation}:${inputPath}:${stat.mtime}:${stat.size}::${ComicOfflineTranslationService.MODEL}`) });
    const key = buffer.from((await digest.digest()).data).toString('hex');
    const dir = `${context.cacheDir}/comic_colorization_v1`;
    if (!await fileIo.access(dir)) await fileIo.mkdir(dir);
    const target = `${dir}/${key}.jpg`;
    if (await fileIo.access(target)) {
      const cached = fileUri.getUriFromPath(target);
      await ReaderCacheService.record([cached]);
      return active() ? cached : '';
    }
    if (!active()) return '';
    const source = image.createImageSource(inputPath);
    let translated: Uint8Array = new Uint8Array(0);
    let width = 0;
    let height = 0;
    try {
      const info = await source.getImageInfo();
      width = info.size.width; height = info.size.height;
      if (width < 32 || height < 32 || width * height > 16 * 1024 * 1024 ||
        Math.max(width, height) > 16384 || await source.getFrameCount() !== 1) throw new Error('comic_ai_image_too_large');
      const scale = Math.min(1, 2048 / Math.max(width, height), Math.sqrt(2 * 1024 * 1024 / (width * height)));
      const pixels = await source.createPixelMap({ desiredSize: {
        width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale))
      }, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      try {
        translated = await ComicTranslationService.translatePixels(pixels, Math.max(1, Math.round(width * scale)),
          Math.max(1, Math.round(height * scale)), targetLanguage, active);
      } finally { await pixels.release(); }
    } finally { await source.release(); }
    if (!active()) return '';
    const bytes = translated;
    if (bytes.byteLength === 0 || bytes.byteLength > 8 * 1024 * 1024) throw new Error('comic_ai_invalid_image');
    // 本地翻译已校验尺寸并输出 JPEG，保持原有翻译缓存格式。
    const encoded = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    if (!active()) return '';
    if (encoded.byteLength > 8 * 1024 * 1024) throw new Error('comic_ai_image_too_large');
    const temporary = `${target}.tmp`;
    try {
      const file = await fileIo.open(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        let offset = 0;
        while (offset < encoded.byteLength) {
          const count = await fileIo.write(file.fd, encoded.slice(offset));
          if (count <= 0) throw new Error('comic_ai_storage_failed');
          offset += count;
        }
      } finally { await fileIo.close(file); }
      if (!active()) return '';
      await fileIo.rename(temporary, target);
      const result = fileUri.getUriFromPath(target);
      await ReaderCacheService.record([result]);
      return result;
    } finally { try { await fileIo.unlink(temporary); } catch (_error) { } }
  }
}
