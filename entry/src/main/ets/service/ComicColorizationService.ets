import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer, util } from '@kit.ArkTS';
import { ComicAiConfigService } from './ComicAiConfigService';
import { ComicTranslationService } from './ComicTranslationService';
import { ComicOfflineTranslationService } from './ComicOfflineTranslationService';
import { ComicAiConfig } from '../model/ComicAiConfig';
import { ReaderCacheService } from './ReaderCacheService';
import { MembershipState } from '../model/MembershipState';

/** 仅处理用户主动开启后的可见图片，原图不覆盖，队列和派生缓存均有界。 */
export class ComicColorizationService {
  private static queue: Promise<void> = Promise.resolve();
  private static pending: number = 0;
  private static blockedRevision: number = -1;

  static resetFailure(): void { ComicColorizationService.blockedRevision = -1; }

  static async colorize(context: common.Context, uri: string, active: () => boolean): Promise<string> {
    return ComicColorizationService.transform(context, uri, active, '');
  }

  static async transform(context: common.Context, uri: string, active: () => boolean,
    targetLanguage: string): Promise<string> {
    if (targetLanguage) ComicOfflineTranslationService.validateDirection(targetLanguage);
    if (!active() || !MembershipState.current.hasAccess) return '';
    if (ComicColorizationService.pending >= 4) return '';
    const revision = ComicAiConfigService.revision;
    ComicColorizationService.pending++;
    const job = ComicColorizationService.queue.then(async (): Promise<string> => {
      if (!active() || !MembershipState.current.hasAccess || revision !== ComicAiConfigService.revision) return '';
      if (ComicColorizationService.blockedRevision === revision) return '';
      ReaderCacheService.configure(context);
      ReaderCacheService.beginComicWrite();
      ReaderCacheService.hold(uri);
      try {
        const allowed = (): boolean => active() && MembershipState.current.hasAccess && revision === ComicAiConfigService.revision;
        const result = await ComicColorizationService.process(context, uri, allowed, targetLanguage);
        return allowed() ? result : '';
      } catch (error) {
        if (active() && MembershipState.current.hasAccess && revision === ComicAiConfigService.revision) {
          // 账号、模型或网络失败后停掉本轮剩余队列，避免逐页重复扣费/报错。
          ComicColorizationService.blockedRevision = revision;
          throw error instanceof Error ? error : new Error('comic_ai_request_failed');
        }
        return '';
      } finally { ReaderCacheService.unhold(uri); ReaderCacheService.endComicWrite(); }
    });
    ComicColorizationService.queue = job.then((): void => {}, (): void => {});
    try { return await job; } finally { ComicColorizationService.pending--; }
  }

  private static async process(context: common.Context, uri: string, active: () => boolean,
    targetLanguage: string): Promise<string> {
    if (!uri.startsWith('file://')) return '';
    const inputPath = new fileUri.FileUri(uri).path;
    if (!inputPath.startsWith(`${context.cacheDir}/comic_images/`)) return '';
    const stat = await fileIo.stat(inputPath);
    if (stat.size <= 0 || stat.size > 20 * 1024 * 1024) throw new Error('comic_ai_image_too_large');
    const config = targetLanguage ? new ComicAiConfig() : await ComicAiConfigService.load(context);
    if (targetLanguage) config.model = ComicOfflineTranslationService.MODEL;
    else if (!config.model || !config.baseUrl || !config.apiKey) throw new Error('comic_ai_need_config');
    const digest = cryptoFramework.createMd('SHA256');
    const operation = targetLanguage ? `translate-offline-v2:${targetLanguage}` : 'color-v1';
    await digest.update({ data: new util.TextEncoder().encodeInto(
      `${operation}:${inputPath}:${stat.mtime}:${stat.size}:${config.baseUrl}:${config.model}`) });
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
    let jpeg: ArrayBuffer = new ArrayBuffer(0);
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
        if (targetLanguage) {
          translated = await ComicTranslationService.translatePixels(pixels, Math.max(1, Math.round(width * scale)),
            Math.max(1, Math.round(height * scale)), targetLanguage, active);
        } else {
          const packer = image.createImagePacker();
          try { jpeg = await packer.packToData(pixels, { format: 'image/jpeg', quality: 92 }); }
          finally { await packer.release(); }
        }
      } finally { await pixels.release(); }
    } finally { await source.release(); }
    if (!active()) return '';
    if (jpeg.byteLength > 4 * 1024 * 1024) throw new Error('comic_ai_image_too_large');
    const bytes = targetLanguage ? translated :
      await ComicAiConfigService.edit(config, jpeg, (): boolean => !active());
    if (!active()) return '';
    if (bytes.byteLength === 0 || bytes.byteLength > 8 * 1024 * 1024) throw new Error('comic_ai_invalid_image');
    let encoded: ArrayBuffer = new ArrayBuffer(0);
    if (targetLanguage) {
      // 本地渲染已校验尺寸并输出 JPEG，无需按外部图片再解码、压缩。
      encoded = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    } else {
      const output = image.createImageSource(bytes.buffer);
      try {
      const info = await output.getImageInfo();
      if (info.size.width < 32 || info.size.height < 32 || info.size.width * info.size.height > 8 * 1024 * 1024 ||
        Math.max(info.size.width, info.size.height) > 8192 || await output.getFrameCount() !== 1 ||
        Math.abs((info.size.width / info.size.height) / (width / height) - 1) > 0.03) {
        throw new Error('comic_ai_invalid_image');
      }
      const pixels = await output.createPixelMap();
      try {
        const packer = image.createImagePacker();
        try { encoded = await packer.packToData(pixels, { format: 'image/jpeg', quality: 95 }); }
        finally { await packer.release(); }
      } finally { await pixels.release(); }
      } finally { await output.release(); }
    }
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
