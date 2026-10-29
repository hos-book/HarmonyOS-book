import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';

/** 相册授权只在选图期间有效，主题引用可持久使用的沙箱副本。 */
export class ReaderBackgroundImageService {
  static async pick(context: common.Context): Promise<string> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const result = await new photoAccessHelper.PhotoViewPicker().select(options);
    if (result.photoUris.length === 0) return '';
    const dir = `${context.filesDir}/reader_bg`;
    if (!await fileIo.access(dir)) await fileIo.mkdir(dir, true);
    const destination = `${dir}/bg_${Date.now()}_${Math.floor(Math.random() * 1000000)}.img`;
    try {
      const source = await fileIo.open(result.photoUris[0], fileIo.OpenMode.READ_ONLY);
      try { await fileIo.copyFile(source.fd, destination); }
      finally { await fileIo.close(source); }
      const imageSource = image.createImageSource(destination);
      try { await imageSource.getImageInfo(); }
      finally { await imageSource.release(); }
      return destination;
    } catch (error) {
      await ReaderBackgroundImageService.remove(context, destination);
      const failure: Error = error;
      throw failure;
    }
  }

  static async remove(context: common.Context, path: string): Promise<void> {
    const prefix = `${context.filesDir}/reader_bg/`;
    if (!path.startsWith(prefix)) return;
    const name = path.substring(prefix.length);
    if (!name || name.includes('/') || name.includes('\\') || name.includes('..')) return;
    try { await fileIo.unlink(path); } catch (_e) { /* 已删除或不可访问不影响主题保存。 */ }
  }
}
