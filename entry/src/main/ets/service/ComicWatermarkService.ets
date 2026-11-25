import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { load, process } from 'libcomic_watermark.so';
import { ReaderCacheService } from './ReaderCacheService';

@ObservedV2
export class ComicWatermarkState {
  @Trace installed: boolean = false;
  @Trace bytes: number = 0;
  @Trace busy: boolean = false;
  @Trace enabled: boolean = false;
}

/** 模型与像素处理留在本机，输出进入已有漫画图片缓存。 */
export class ComicWatermarkService {
  static readonly instance: ComicWatermarkService = new ComicWatermarkService();
  readonly state: ComicWatermarkState = new ComicWatermarkState();
  private modelPath: string = '';
  private store: preferences.Preferences | null = null;
  private queue: Promise<void> = Promise.resolve();
  private results: Map<string, string> = new Map<string, string>();

  async initialize(context: common.Context): Promise<void> {
    this.modelPath = `${context.filesDir}/comic_watermark/slbr-v1.onnx`;
    this.store = await preferences.getPreferences(context, { name: 'comic_watermark' });
    this.state.installed = await fileIo.access(this.modelPath);
    this.state.bytes = this.state.installed ? (await fileIo.stat(this.modelPath)).size : 0;
    this.state.enabled = this.state.installed && this.store.getSync('enabled', false) === true;
  }

  async setEnabled(enabled: boolean): Promise<void> {
    if (this.store === null) return;
    await this.store.put('enabled', enabled);
    await this.store.flush();
    this.state.enabled = enabled;
  }

  async pick(context: common.UIAbilityContext): Promise<boolean> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['SLBR ONNX|.onnx'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) return false;
    this.state.busy = true;
    try {
      await this.queue;
      const directory = `${context.filesDir}/comic_watermark`;
      if (!await fileIo.access(directory)) await fileIo.mkdir(directory, true);
      const source = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
      try {
        await load(`/proc/self/fd/${source.fd}`);
        await fileIo.copyFile(source.fd, this.modelPath);
      }
      finally { await fileIo.close(source); }
      this.results.clear();
      await this.initialize(context);
      return true;
    } catch (error) {
      await this.initialize(context);
      throw error instanceof Error ? error : new Error(String(error));
    } finally { this.state.busy = false; }
  }

  async remove(): Promise<void> {
    this.state.busy = true;
    try {
      await this.queue;
      await this.setEnabled(false);
      await fileIo.unlink(this.modelPath);
      this.state.installed = false; this.state.bytes = 0;
      this.results.clear();
    } finally { this.state.busy = false; }
  }

  transform(context: common.Context, uri: string, active: () => boolean): Promise<string> {
    const task = this.queue.then(async (): Promise<string> => {
      if (!active() || !this.state.enabled || this.state.busy) return '';
      const cached = this.results.get(uri);
      if (cached && await fileIo.access(new fileUri.FileUri(cached).path)) return cached;
      const sourcePath = uri.startsWith('file://') ? new fileUri.FileUri(uri).path : uri;
      const source = image.createImageSource(sourcePath);
      let bitmap: image.PixelMap | null = null;
      let cleaned: image.PixelMap | null = null;
      ReaderCacheService.hold(uri);
      ReaderCacheService.beginComicWrite();
      try {
        const info = await source.getImageInfo();
        const scale = Math.min(1, Math.sqrt(12000000 / (info.size.width * info.size.height)));
        bitmap = await source.createPixelMap({ desiredSize: { width: Math.round(info.size.width * scale),
          height: Math.round(info.size.height * scale) }, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
        const decoded = await bitmap.getImageInfo();
        const width = decoded.size.width;
        const height = decoded.size.height;
        const pixels = new ArrayBuffer(width * height * 4);
        await bitmap.readPixelsToBuffer(pixels);
        if (!active()) return '';
        const output = await process(this.modelPath, pixels, width, height);
        if (!active()) return '';
        cleaned = await image.createPixelMap(output, { size: { width: width, height: height },
          pixelFormat: image.PixelMapFormat.RGBA_8888 });
        const directory = `${context.cacheDir}/comic_images`;
        if (!await fileIo.access(directory)) await fileIo.mkdir(directory, true);
        const path = `${directory}/wm_${util.generateRandomUUID()}.png`;
        const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        const packer = image.createImagePacker();
        try { await packer.packToFile(cleaned, file.fd, { format: 'image/png', quality: 100 }); }
        finally { await packer.release(); await fileIo.close(file); }
        const result = fileUri.getUriFromPath(path);
        await ReaderCacheService.record([result]);
        this.results.set(uri, result);
        return result;
      } finally {
        if (cleaned) await cleaned.release();
        if (bitmap) await bitmap.release();
        await source.release();
        ReaderCacheService.unhold(uri);
        ReaderCacheService.endComicWrite();
      }
    });
    this.queue = task.then((): void => {}, (): void => {});
    return task;
  }
}
