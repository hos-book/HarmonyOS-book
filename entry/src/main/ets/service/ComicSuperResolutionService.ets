import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer, util } from '@kit.ArkTS';
import lazy { imageSuperResolution, visionBase } from '@kit.CoreVisionKit';
import { PlatformCompat } from '../utils/PlatformCompat';
import { PreferenceService } from './PreferenceService';
import { CoverPrefetcher } from './CoverPrefetcher';
import { ReaderCacheService } from './ReaderCacheService';
import { MembershipState } from '../model/MembershipState';

/** 当前可见漫画图片的本地超分；串行处理，原图不覆盖，派生缓存有界。 */
export class ComicSuperResolutionService {
  private static queue: Promise<void> = Promise.resolve();
  private static stalled: boolean = false;

  static supported(): boolean {
    return PlatformCompat.supports(26) && canIUse('SystemCapability.AI.Vision.VisionBase');
  }

  static async enhance(context: common.Context, url: string, active: () => boolean): Promise<string> {
    if (!ComicSuperResolutionService.supported() || !active() || ComicSuperResolutionService.stalled ||
      (!url.startsWith('file://') && !/^https?:\/\//.test(url))) return '';
    let expired = false;
    let processing = false;
    const job = ComicSuperResolutionService.queue.then(async (): Promise<string> => {
      try {
        if (expired || ComicSuperResolutionService.stalled || !active() || !await PreferenceService.getComicSuperResolution()) return '';
        processing = true;
        ReaderCacheService.configure(context);
        ReaderCacheService.beginComicWrite();
        try {
          const allowed = (): boolean => active() && MembershipState.current.hasAccess;
          if (!allowed()) return '';
          const result = await ComicSuperResolutionService.process(context, url, allowed);
          if (result) await ReaderCacheService.record([result]);
          return allowed() ? result : '';
        } finally { ReaderCacheService.endComicWrite(); }
      } catch (_error) {
        console.warn('[ComicSuperResolution] Enhancement unavailable; using original comic image');
        return '';
      } finally {
        processing = false;
      }
    });
    ComicSuperResolutionService.queue = job.then((): void => {});
    let timer = -1;
    const timeout = new Promise<string>((resolve): void => {
      timer = setTimeout((): void => {
        expired = true;
        if (processing) ComicSuperResolutionService.stalled = true;
        resolve('');
      }, 30000);
    });
    try { return await Promise.race([job, timeout]); }
    finally { if (timer >= 0) clearTimeout(timer); }
  }

  private static async process(context: common.Context, url: string, active: () => boolean): Promise<string> {
    const remote = /^https?:\/\//.test(url);
    const localPath = remote ? '' : new fileUri.FileUri(url).path;
    if (!remote && !localPath.startsWith(`${context.cacheDir}/comic_images/`)) return '';
    const stat = remote ? null : await fileIo.stat(localPath);
    if (stat !== null && (stat.size <= 0 || stat.size > 20 * 1024 * 1024)) return '';
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: new util.TextEncoder().encodeInto(`${url}:${stat?.mtime ?? 0}:${stat?.size ?? 0}`) });
    const key = buffer.from((await digest.digest()).data).toString('hex');
    const dir = `${context.cacheDir}/comic_super_resolution_v1`;
    if (!await fileIo.access(dir)) await fileIo.mkdir(dir);
    const path = `${dir}/${key}.jpg`;
    if (await fileIo.access(path)) return fileUri.getUriFromPath(path);
    if (!active()) return '';
    const source = remote ? image.createImageSource(await CoverPrefetcher.loadOriginal(url)) : image.createImageSource(localPath);
    let input: image.PixelMap | null = null;
    try {
      const info = await source.getImageInfo();
      // 限制解码输入和推理输出，超长图保留原图，不先缩小再冒充超分。
      if (info.size.width < 32 || info.size.height < 32 ||
        Math.max(info.size.width, info.size.height) > 4096 || info.size.width * info.size.height > 4 * 1024 * 1024 || await source.getFrameCount() !== 1) return '';
      input = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      if (!active()) return '';
      const engine = await imageSuperResolution.ImageSRAnalyzer.create();
      try {
        if (!active()) return '';
        const request: visionBase.Request = { inputData: { pixelMap: input } };
        const response = await engine.process(request);
        const output = response.pixelMap;
        try {
          if (!active() || !await PreferenceService.getComicSuperResolution()) return '';
          const size = (await output.getImageInfo()).size;
          if (size.width < info.size.width || size.height < info.size.height ||
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
                  if (written <= 0) throw new Error('Incomplete enhanced image');
                  offset += written;
                }
              } finally {
                await fileIo.close(file);
              }
              await fileIo.rename(temporary, path);
            } finally {
              try { await fileIo.unlink(temporary); } catch (_error) { }
            }
            await ComicSuperResolutionService.trim(dir, `${key}.jpg`);
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
    // 最多保留 12 张，每张不超过 4 MiB；缓存文件只用于显示，不修改漫画原图。
    while (files.length > 11) {
      const name = files.shift();
      if (name !== undefined) await fileIo.unlink(`${dir}/${name}`);
    }
  }
}
