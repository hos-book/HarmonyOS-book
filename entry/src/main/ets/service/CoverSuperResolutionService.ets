import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer, util } from '@kit.ArkTS';
import lazy { ReaderComicSuperResolution } from '@legado/aiengine';
import { PlatformCompat } from '../utils/PlatformCompat';
import { PreferenceService } from './PreferenceService';
import { CoverPrefetcher } from './CoverPrefetcher';
import { MembershipState } from '../model/MembershipState';
import { ComicAiHost } from './ComicAiHost';
import { ReaderCacheService } from './ReaderCacheService';

/** 当前播放封面复用有界分块超分；尺寸大不等于画质清晰。 */
export class CoverSuperResolutionService {
  private static queue: Promise<void> = Promise.resolve();

  static supported(): boolean {
    return PlatformCompat.supports(26) && canIUse('SystemCapability.AI.Vision.VisionBase');
  }

  static async enhance(context: common.Context, url: string, active: () => boolean): Promise<string> {
    if (!CoverSuperResolutionService.supported() || !active() ||
      (!url.startsWith('https://') && !url.startsWith('http://'))) return '';
    const job = CoverSuperResolutionService.queue.then(async (): Promise<string> => {
      try {
        if (!active() || !await PreferenceService.getCoverSuperResolution()) return '';
        const allowed = (): boolean => active() && MembershipState.current.hasAccess;
        if (!allowed()) return '';
        const result = await CoverSuperResolutionService.process(context, url, allowed);
        return allowed() ? result : '';
      } catch (error) {
        console.warn(`[CoverSuperResolution] Enhancement unavailable: ${String(error)}`);
        return '';
      }
    });
    CoverSuperResolutionService.queue = job.then((): void => {});
    return job;
  }

  private static async process(context: common.Context, url: string, active: () => boolean): Promise<string> {
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: new util.TextEncoder().encodeInto(url) });
    const key = buffer.from((await digest.digest()).data).toString('hex');
    const dir = `${context.cacheDir}/cover_super_resolution_v2`;
    if (!await fileIo.access(dir)) await fileIo.mkdir(dir);
    const path = `${dir}/${key}.jpg`;
    if (await fileIo.access(path)) return fileUri.getUriFromPath(path);
    const bytes = await CoverPrefetcher.loadOriginal(url);
    if (!active()) return '';
    const source = image.createImageSource(bytes);
    let input: image.PixelMap | null = null;
    try {
      const info = await source.getImageInfo();
      // 仅限制异常输入和解码预算，不再把大尺寸封面当作高清图跳过。
      if (info.size.width < 32 || info.size.height < 32 ||
        info.size.width * info.size.height > 32 * 1024 * 1024 || await source.getFrameCount() !== 1) return '';
      const scale = Math.min(1, 2048 / Math.max(info.size.width, info.size.height));
      const width = Math.max(1, Math.round(info.size.width * scale));
      const height = Math.max(1, Math.round(info.size.height * scale));
      let encoded = bytes;
      if (scale < 1) {
        input = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          desiredSize: { width: width, height: height } });
        const packer = image.createImagePacker();
        try { encoded = await packer.packToData(input, { format: 'image/png', quality: 100 }); }
        finally { await packer.release(); }
      }
      if (!active()) return '';
      const temporary = `${dir}/${key}.input`;
      const pending = `${path}.tmp`;
      try {
        await CoverSuperResolutionService.write(temporary, encoded);
        ComicAiHost.install(context);
        ReaderCacheService.beginComicWrite();
        try {
          // HAR 输出约为目标宽度的两倍，受 12M 像素约束；每块不超过 512K 像素。
          // 至少请求输入宽度，避免 1500px 等模糊大封面被 HAR 的收益阈值跳过。
          const result = await ReaderComicSuperResolution.enhance(fileUri.getUriFromPath(temporary),
            Math.max(1024, width), active);
          if (!result) return '';
          ReaderCacheService.hold(result);
          try {
            await ReaderCacheService.record([result]);
            if (!active() || !await PreferenceService.getCoverSuperResolution()) return '';
            const outputPath = new fileUri.FileUri(result).path;
            const stat = await fileIo.stat(outputPath);
            if (stat.size <= 0 || stat.size > 4 * 1024 * 1024) return '';
            await fileIo.copyFile(outputPath, pending);
            if (!active()) return '';
            await fileIo.rename(pending, path);
            await CoverSuperResolutionService.trim(dir, `${key}.jpg`);
            console.info(`[CoverSuperResolution] Enhanced ${info.size.width}x${info.size.height} cover`);
            return fileUri.getUriFromPath(path);
          } finally { ReaderCacheService.unhold(result); }
        } finally { ReaderCacheService.endComicWrite(); }
      } finally {
        try { await fileIo.unlink(temporary); } catch (_error) { }
        try { await fileIo.unlink(pending); } catch (_error) { }
      }
    } finally {
      try { if (input !== null) await input.release(); } finally { await source.release(); }
    }
  }

  private static async write(path: string, bytes: ArrayBuffer): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      let offset = 0;
      while (offset < bytes.byteLength) {
        const written = await fileIo.write(file.fd, bytes.slice(offset));
        if (written <= 0) throw new Error('Incomplete cover input');
        offset += written;
      }
    } finally { await fileIo.close(file); }
  }

  private static async trim(dir: string, current: string): Promise<void> {
    const files = (await fileIo.listFile(dir)).filter((name: string): boolean =>
      name.endsWith('.jpg') && name !== current);
    // 最多保留 12 张，每张不超过 4 MiB；缓存文件只用于显示，不修改书源原始封面。
    while (files.length > 11) {
      const name = files.shift();
      if (name !== undefined) await fileIo.unlink(`${dir}/${name}`);
    }
  }
}
