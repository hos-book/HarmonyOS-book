import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { MembershipService } from './MembershipService';
import {
  AppBackgroundConfig, AppBackgroundImportError, AppBackgroundImportReason,
  AppBackgroundScene, AppBackgroundSelection
} from '../model/AppBackground';

/** 本机 App 背景文件与选择。草稿只写图片，明确应用后才发布 V2 状态。 */
@ObservedV2
export class AppBackgroundService {
  private static singleton: AppBackgroundService | null = null;

  static get instance(): AppBackgroundService {
    if (AppBackgroundService.singleton === null) AppBackgroundService.singleton = new AppBackgroundService();
    return AppBackgroundService.singleton;
  }

  @Trace ready: boolean = false;
  @Trace busy: boolean = false;
  @Trace revision: number = 0;
  @Trace private selection: AppBackgroundSelection = new AppBackgroundSelection();
  private directory: string = '';
  private store: preferences.Preferences | undefined = undefined;
  private initializing: Promise<void> | undefined = undefined;
  private pendingApply: AppBackgroundSelection | undefined = undefined;
  private deferredCleanup: string[] = [];

  async init(context: common.Context): Promise<void> {
    if (this.ready) return;
    if (!this.initializing) {
      this.initializing = this.load(context).finally((): void => { this.initializing = undefined; });
    }
    await this.initializing;
  }

  private async load(context: common.Context): Promise<void> {
    const directory: string = `${context.filesDir}/app_backgrounds`;
    const store = await preferences.getPreferences(context, { name: 'app_backgrounds' });
    const raw = await store.get('selection_v1', '');
    const selection = AppBackgroundSelection.decode(typeof raw === 'string' ? raw : '');
    for (const config of selection.configs()) {
      if (config.imageFile && !await fileIo.access(`${directory}/${config.imageFile}`).catch((): boolean => false)) {
        config.imageFile = '';
        if (config.preset === 'image') config.preset = 'theme';
      }
    }
    this.directory = directory;
    this.store = store;
    this.selection = selection;
    this.ready = true;
    this.revision++;
    await this.cleanAbandonedImages().catch((): void => {});
  }

  snapshot(): AppBackgroundSelection {
    return this.selection.copy();
  }

  resolve(scene: AppBackgroundScene): AppBackgroundConfig {
    return this.selection.resolve(scene);
  }

  resolveImage(config: AppBackgroundConfig): string | undefined {
    return this.directory && AppBackgroundConfig.validImageFile(config.imageFile)
      ? `file://${this.directory}/${config.imageFile}` : undefined;
  }

  /** isCurrent 防止相册返回或解码结束时把图片迟到地写入另一个页面。 */
  async importImage(uri: string, isCurrent: () => boolean): Promise<string> {
    if (!this.ready || this.busy || !isCurrent()) return '';
    this.busy = true;
    let name: string = '';
    let retained: boolean = false;
    try {
      name = await this.writeImage(uri);
      if (!isCurrent()) return '';
      retained = true;
      return name;
    } finally {
      if (name && !retained) await this.removeFile(name);
      this.busy = false;
    }
  }

  async apply(value: AppBackgroundSelection): Promise<void> {
    if (!this.ready || !this.store) throw new Error('Background preferences unavailable');
    if (this.busy) throw new Error('Background operation in progress');
    this.busy = true;
    const next = value.copy();
    this.pendingApply = next;
    try {
      if (!await MembershipService.instance.hasCurrentEntitlement()) throw new Error('MEMBERSHIP_REQUIRED');
      for (const name of next.imageFiles()) {
        if (!await fileIo.access(`${this.directory}/${name}`).catch((): boolean => false)) {
          throw new Error('Background image missing');
        }
      }
      const store = this.store;
      const previous = this.selection;
      const raw = await store.get('selection_v1', '');
      try {
        await store.put('selection_v1', JSON.stringify(next));
        await store.flush();
      } catch (error) {
        await store.put('selection_v1', raw);
        const failure: Error = error;
        throw new Error(failure.message);
      }
      this.selection = next;
      this.revision++;
      const retained = next.imageFiles();
      for (const name of previous.imageFiles()) {
        if (!retained.includes(name)) await this.removeFile(name);
      }
    } finally {
      this.pendingApply = undefined;
      this.busy = false;
      const cleanup = this.deferredCleanup;
      this.deferredCleanup = [];
      await this.cleanupDraftImages(cleanup);
    }
  }

  async discardDraft(value: AppBackgroundSelection): Promise<void> {
    await this.cleanupDraftImages(value.imageFiles());
  }

  /** UI 记录本次导入的全部文件名，因此连续换图后退出也不会遗留旧草稿。 */
  async cleanupDraftImages(names: string[]): Promise<void> {
    for (const name of names) {
      if (this.selection.imageFiles().includes(name)) continue;
      if (this.pendingApply && this.pendingApply.imageFiles().includes(name)) {
        if (!this.deferredCleanup.includes(name)) this.deferredCleanup.push(name);
        continue;
      }
      await this.removeFile(name);
    }
  }

  private async cleanAbandonedImages(): Promise<void> {
    if (!await fileIo.access(this.directory).catch((): boolean => false)) return;
    const names = await fileIo.listFile(this.directory);
    await this.cleanupDraftImages(names);
  }

  private async removeFile(name: string): Promise<void> {
    if (this.directory && AppBackgroundConfig.validImageFile(name)) {
      await fileIo.unlink(`${this.directory}/${name}`).catch((): void => {});
    }
  }

  private async writeImage(uri: string): Promise<string> {
    let file: fileIo.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let name: string = '';
    let completed: boolean = false;
    let reason: AppBackgroundImportReason = AppBackgroundImportReason.ReadFailed;
    try {
      file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      if (stat.size > 20 * 1024 * 1024) {
        throw new AppBackgroundImportError(AppBackgroundImportReason.InputTooLarge, 0,
          'Background input exceeds budget');
      }
      if (stat.size <= 0) throw new AppBackgroundImportError(AppBackgroundImportReason.InvalidImage);
      reason = AppBackgroundImportReason.DecodeFailed;
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      if (info.size.width <= 0 || info.size.height <= 0) {
        throw new AppBackgroundImportError(AppBackgroundImportReason.InvalidImage);
      }
      if (info.size.width * info.size.height > 100000000) {
        throw new AppBackgroundImportError(AppBackgroundImportReason.DimensionsTooLarge, 0,
          'Invalid background dimensions');
      }
      const scale = Math.min(1, 2560 / Math.max(info.size.width, info.size.height));
      // App 背景以静态图片保存；GIF/WebP 动图明确取首帧。
      pixels = await source.createPixelMap({ index: 0, editable: true, desiredSize: {
        width: Math.max(1, Math.round(info.size.width * scale)),
        height: Math.max(1, Math.round(info.size.height * scale))
      } });
      // PropertyKey API 11 与 PixelMap.flip/rotate API 9/7 可覆盖最低 API 20。
      const orientation = await this.readOrientation(source);
      await this.orientPixels(pixels, orientation);
      reason = AppBackgroundImportReason.EncodeFailed;
      packer = image.createImagePacker();
      const png: boolean = info.mimeType !== 'image/jpeg' && info.mimeType !== 'image/heic' && info.mimeType !== 'image/heif';
      const bytes = await this.encodeImage(pixels, packer, png);
      name = `background_${Date.now()}_${Math.floor(Math.random() * 1000000000)}.${png ? 'png' : 'jpg'}`;
      reason = AppBackgroundImportReason.SaveFailed;
      if (!await fileIo.access(this.directory).catch((): boolean => false)) await fileIo.mkdir(this.directory, true);
      const output = await fileIo.open(`${this.directory}/${name}`,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        let offset: number = 0;
        while (offset < bytes.byteLength) {
          const written = await fileIo.write(output.fd, bytes.slice(offset));
          if (written <= 0) throw new Error('Incomplete background file');
          offset += written;
        }
      } finally { await fileIo.close(output); }
      completed = true;
      return name;
    } catch (error) {
      const original: BusinessError = error;
      const failure: AppBackgroundImportError = error instanceof AppBackgroundImportError ? error :
        new AppBackgroundImportError(reason, Number.isFinite(original.code) ? original.code : 0, original.message);
      // 不记录相册 URI、文件路径或图片内容。
      console.warn(`[AppBackground] import failed: reason=${failure.reason}, code=${failure.originalCode}`);
      throw failure;
    } finally {
      if (!completed && name) await this.removeFile(name);
      if (pixels) await pixels.release().catch((): void => {});
      if (source) await source.release().catch((): void => {});
      if (packer) await packer.release().catch((): void => {});
      if (file) await fileIo.close(file).catch((): void => {});
    }
  }

  private async readOrientation(source: image.ImageSource): Promise<string> {
    try {
      // 部分原生实现要求 options 显式提供 index，缺少时会在返回 Promise 前同步抛错。
      const value = await source.getImageProperty(image.PropertyKey.ORIENTATION, { index: 0, defaultValue: '1' });
      return typeof value === 'string' ? value : '1';
    } catch (_error) {
      // EXIF 是可选元数据；缺少或不支持方向信息不能阻断正常图片导入。
      return '1';
    }
  }

  private async encodeImage(pixels: image.PixelMap, packer: image.ImagePacker, png: boolean): Promise<ArrayBuffer> {
    // PNG 重编码会改变压缩率，原文件大小不能代替输出体积。保留透明度并有界缩小后重试。
    for (let attempt: number = 0; attempt < 3; attempt++) {
      const bytes = await packer.packToData(pixels, { format: png ? 'image/png' : 'image/jpeg',
        quality: png ? 100 : 88, bufferSize: 32 * 1024 * 1024, needsPackProperties: false });
      if (bytes.byteLength === 0) throw new AppBackgroundImportError(AppBackgroundImportReason.EncodeFailed);
      if (bytes.byteLength <= 12 * 1024 * 1024) return bytes;
      if (attempt < 2) await pixels.scale(0.7, 0.7);
    }
    throw new AppBackgroundImportError(AppBackgroundImportReason.EncodeFailed, 0, 'Background output exceeds budget');
  }

  private async orientPixels(pixels: image.PixelMap, raw: string): Promise<void> {
    const value: string = raw.trim().toLowerCase();
    if (value === '2' || value === 'top-right') {
      await pixels.flip(true, false);
    } else if (value === '3' || value === 'bottom-right') {
      await pixels.rotate(180);
    } else if (value === '4' || value === 'bottom-left') {
      await pixels.flip(false, true);
    } else if (value === '5' || value === 'left-top') {
      await pixels.flip(true, false);
      await pixels.rotate(270);
    } else if (value === '6' || value === 'right-top') {
      await pixels.rotate(90);
    } else if (value === '7' || value === 'right-bottom') {
      await pixels.flip(true, false);
      await pixels.rotate(90);
    } else if (value === '8' || value === 'left-bottom') {
      await pixels.rotate(270);
    }
  }
}
