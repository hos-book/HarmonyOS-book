import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer, util } from '@kit.ArkTS';
import lazy { imageSuperResolution, visionBase } from '@kit.CoreVisionKit';
import { PlatformCompat } from '../utils/PlatformCompat';
import { PreferenceService } from './PreferenceService';
import { CoverPrefetcher } from './CoverPrefetcher';
import { MembershipState } from '../model/MembershipState';

/** 仅为当前播放封面运行系统超分；串行处理、小图输入、有界派生缓存。 */
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
      } catch (_error) {
        console.warn('[CoverSuperResolution] Enhancement unavailable; using original cover');
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
    const dir = `${context.cacheDir}/cover_super_resolution_v1`;
    if (!await fileIo.access(dir)) await fileIo.mkdir(dir);
    const path = `${dir}/${key}.jpg`;
    if (await fileIo.access(path)) return fileUri.getUriFromPath(path);
    const bytes = await CoverPrefetcher.loadOriginal(url);
    if (!active()) return '';
    const source = image.createImageSource(bytes);
    let input: image.PixelMap | null = null;
    try {
      const info = await source.getImageInfo();
      // 只处理低分辨率静态封面；大图无需超分，也不先缩小再放大。
      if (info.size.width < 32 || info.size.height < 32 ||
        Math.max(info.size.width, info.size.height) > 640 || await source.getFrameCount() !== 1) return '';
      input = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      if (!active()) return '';
      const engine = await imageSuperResolution.ImageSRAnalyzer.create();
      try {
        if (!active()) return '';
        const request: visionBase.Request = { inputData: { pixelMap: input } };
        const response = await engine.process(request);
        const output = response.pixelMap;
        try {
          if (!active() || !await PreferenceService.getCoverSuperResolution()) return '';
          const size = (await output.getImageInfo()).size;
          if (size.width <= info.size.width || size.height <= info.size.height ||
            size.width * size.height > 16 * 1024 * 1024) return '';
          const packer = image.createImagePacker();
          try {
            const encoded = await packer.packToData(output, { format: 'image/jpeg', quality: 95 });
            if (!active() || encoded.byteLength > 4 * 1024 * 1024) return '';
            const temporary = `${path}.tmp`;
            try {
              const file = await fileIo.open(temporary,
                fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
              try {
                let offset: number = 0;
                while (offset < encoded.byteLength) {
                  const written = await fileIo.write(file.fd, encoded.slice(offset));
                  if (written <= 0) throw new Error('Incomplete enhanced cover');
                  offset += written;
                }
              } finally {
                await fileIo.close(file);
              }
              await fileIo.rename(temporary, path);
            } finally {
              try { await fileIo.unlink(temporary); } catch (_error) { }
            }
            await CoverSuperResolutionService.trim(dir, `${key}.jpg`);
            return fileUri.getUriFromPath(path);
          } finally {
            await packer.release();
          }
        } finally {
          if (output !== input) await output.release();
        }
      } finally {
        await engine.destroy();
      }
    } finally {
      try { if (input !== null) await input.release(); } finally { await source.release(); }
    }
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
