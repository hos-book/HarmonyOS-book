import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { ComicModelAsset, COMIC_MODEL_ASSETS } from '../model/ComicModelAssets';

/** 固定版本语言包，下载至临时文件，校验后才提供给推理宿主。 */
export class ComicTranslationModelService {
  private static verified: Set<string> = new Set<string>();
  private static busy: boolean = false;

  static assets(direction: string): ComicModelAsset[] {
    const ids = direction === 'ja-zh' ? ['ja-en', 'en-zh'] : direction === 'ko-zh' ? ['ko-en', 'en-zh'] :
      direction === 'en-zh' ? ['en-zh'] : direction === 'zh-en' ? ['zh-en'] : [];
    if (ids.length === 0) throw new Error('comic_offline_direction');
    return COMIC_MODEL_ASSETS.filter((asset: ComicModelAsset): boolean => ids.includes(asset.model));
  }

  static path(context: common.Context, asset: ComicModelAsset): string {
    return `${context.filesDir}/comic_translation_models/${asset.revision}/${asset.model}/${asset.path}`;
  }

  static localPath(context: common.Context, resource: string): string {
    const asset = COMIC_MODEL_ASSETS.find((item: ComicModelAsset): boolean => `models/${item.model}/${item.path}` === resource);
    if (!asset) return '';
    const path = ComicTranslationModelService.path(context, asset);
    return ComicTranslationModelService.verified.has(path) ? path : '';
  }

  private static async valid(path: string, asset: ComicModelAsset, active: () => boolean): Promise<boolean> {
    try {
      if (fileIo.statSync(path).size !== asset.size) return false;
      if (ComicTranslationModelService.verified.has(path)) return true;
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      try {
        const md = cryptoFramework.createMd('SHA256');
        let offset = 0;
        while (offset < asset.size) {
          if (!active()) throw new Error('comic_offline_cancelled');
          const buffer = new ArrayBuffer(Math.min(1024 * 1024, asset.size - offset));
          const count = await fileIo.read(file.fd, buffer, { offset: offset });
          if (count !== buffer.byteLength) return false;
          await md.update({ data: new Uint8Array(buffer) });
          offset += count;
        }
        const digest = await md.digest();
        let hex = '';
        for (const byte of digest.data) hex += byte.toString(16).padStart(2, '0');
        if (hex !== asset.sha256) return false;
        ComicTranslationModelService.verified.add(path);
        return true;
      } finally { fileIo.closeSync(file); }
    } catch (_error) { return false; }
  }

  static async missingBytes(context: common.Context, direction: string, active: () => boolean): Promise<number> {
    let bytes = 0;
    for (const asset of ComicTranslationModelService.assets(direction)) {
      if (!active()) throw new Error('comic_offline_cancelled');
      if (!await ComicTranslationModelService.valid(ComicTranslationModelService.path(context, asset), asset, active)) bytes += asset.size;
    }
    return bytes;
  }

  static async ensure(context: common.Context, direction: string, active: () => boolean,
    progress: (percent: number) => void): Promise<void> {
    if (ComicTranslationModelService.busy) throw new Error('comic_offline_download_busy');
    ComicTranslationModelService.busy = true;
    try {
      const assets = ComicTranslationModelService.assets(direction);
      const total = assets.reduce((sum: number, asset: ComicModelAsset): number => sum + asset.size, 0);
      let done = 0;
      for (const asset of assets) {
        if (!active()) throw new Error('comic_offline_cancelled');
        const path = ComicTranslationModelService.path(context, asset);
        if (!await ComicTranslationModelService.valid(path, asset, active)) {
          const temporary = `${context.cacheDir}/comic_model_download.tmp`;
          try {
            try { fileIo.unlinkSync(temporary); } catch (_error) {}
            await ComicTranslationModelService.download(asset, temporary, active,
              (bytes: number): void => progress(Math.floor((done + bytes) * 100 / total)));
            if (!await ComicTranslationModelService.valid(temporary, asset, active) || !active()) {
              throw new Error('comic_offline_download_invalid');
            }
            const directory = path.substring(0, path.lastIndexOf('/'));
            if (!fileIo.accessSync(directory)) fileIo.mkdirSync(directory, true);
            fileIo.renameSync(temporary, path);
            ComicTranslationModelService.verified.add(path);
          } finally {
            ComicTranslationModelService.verified.delete(temporary);
            try { fileIo.unlinkSync(temporary); } catch (_error) {}
          }
        }
        done += asset.size;
        progress(Math.floor(done * 100 / total));
      }
    } finally { ComicTranslationModelService.busy = false; }
  }

  private static async download(asset: ComicModelAsset, path: string,
    active: () => boolean, progress: (bytes: number) => void): Promise<void> {
    const url = `https://www.modelscope.cn/api/v1/models/Xenova/opus-mt-${asset.model}/repo?Revision=${asset.revision}&FilePath=${encodeURIComponent(asset.path)}`;
    const client = http.createHttp();
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    let received = 0;
    let failure = '';
    const deadline = Date.now() + 600000;
    const timer = setInterval((): void => {
      if (!active() || Date.now() > deadline) {
        failure = active() ? 'comic_offline_download_timeout' : 'comic_offline_cancelled';
        client.destroy();
      }
    }, 250);
    try {
      client.on('dataReceive', (chunk: ArrayBuffer): void => {
        if (failure) return;
        if (!active() || received + chunk.byteLength > asset.size) {
          failure = active() ? 'comic_offline_download_invalid' : 'comic_offline_cancelled';
          client.destroy(); return;
        }
        try {
          // 小块顺序写入，无异步队列累积，也不将完整权重装入 JS 内存。
          const count = fileIo.writeSync(file.fd, chunk);
          if (count !== chunk.byteLength) throw new Error('comic_offline_download_write');
          received += count;
          progress(received);
        } catch (_error) { failure = 'comic_offline_download_write'; client.destroy(); }
      });
      const status = await client.requestInStream(url, { method: http.RequestMethod.GET,
        header: { 'Accept': '*/*', 'User-Agent': 'ComicTranslation/1.0' },
        connectTimeout: 15000, readTimeout: 60000, usingCache: false });
      if (failure) throw new Error(failure);
      if (status !== 200 || received !== asset.size) throw new Error(`comic_offline_download_failed:${status}`);
    } catch (error) {
      throw new Error(failure || (error instanceof Error ? error.message : 'comic_offline_download_failed'));
    } finally {
      clearInterval(timer);
      client.destroy();
      fileIo.closeSync(file);
    }
  }
}
