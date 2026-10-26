import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import lazy { ReaderComicSuperResolution } from '@legado/aiengine';
import { PlatformCompat } from '../utils/PlatformCompat';
import { PreferenceService } from './PreferenceService';
import { ReaderCacheService } from './ReaderCacheService';
import { MembershipState } from '../model/MembershipState';
import { ComicAiHost } from './ComicAiHost';

/** 复用轻页 HAR 的重叠分块超分；宿主负责权限、取消和缓存预算。 */
export class ComicSuperResolutionService {
  private static queue: Promise<void> = Promise.resolve();
  private static stalled: boolean = false;
  private static pending: number = 0;

  static supported(): boolean {
    return PlatformCompat.supports(26) && canIUse('SystemCapability.AI.Vision.VisionBase');
  }

  static async enhance(context: common.Context, url: string, active: () => boolean,
    targetWidth: number = 1024): Promise<string> {
    if (!ComicSuperResolutionService.supported() || !active() || ComicSuperResolutionService.stalled ||
      ComicSuperResolutionService.pending >= 4 || !url.startsWith('file://') ||
      !Number.isFinite(targetWidth) || targetWidth < 64) return '';
    const path = new fileUri.FileUri(url).path;
    // 图片必须先经过现有下载/解密链；不把远程地址交给 HAR。
    if (!path.startsWith(`${context.cacheDir}/comic_images/`) || path.split('/').includes('..')) return '';
    let expired = false;
    let processing = false;
    ComicSuperResolutionService.pending++;
    const job = ComicSuperResolutionService.queue.then(async (): Promise<string> => {
      const allowed = (): boolean => !expired && active() && MembershipState.current.hasAccess;
      try {
        if (!allowed() || !await PreferenceService.getComicSuperResolution()) return '';
        const stat = await fileIo.stat(path);
        if (!allowed() || stat.size <= 0 || stat.size > 20 * 1024 * 1024) return '';
        processing = true;
        ComicAiHost.install(context);
        ReaderCacheService.beginComicWrite();
        ReaderCacheService.hold(url);
        try {
          // 系统原生接口固定四倍且单块不超过 2048；HAR 按 512K 像素切块，
          // 上下各留 16 行重叠后只拼中部，并把整图限制在 12M 像素以内。
          // sr_ 缓存按目标物理宽度区分，不再读取旧的整图 v1 结果。
          const result = await ReaderComicSuperResolution.enhance(url, Math.round(targetWidth), allowed);
          if (result) await ReaderCacheService.record([result]);
          return allowed() && await PreferenceService.getComicSuperResolution() ? result : '';
        } finally {
          ReaderCacheService.unhold(url);
          ReaderCacheService.endComicWrite();
        }
      } catch (_error) {
        console.warn('[ComicSuperResolution] Enhancement unavailable; using original comic image');
        return '';
      } finally {
        processing = false;
        ComicSuperResolutionService.stalled = false;
        ComicSuperResolutionService.pending--;
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
}
