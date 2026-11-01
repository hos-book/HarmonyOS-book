import { image } from '@kit.ImageKit';
import { LocalTextImage } from './LocalTextImage';

/** 分页前只读取图片头的尺寸，不解码整幅位图；旧导入书籍也无需重新导入。 */
export class LocalTextImageSizing {
  private static pending: Map<string, Promise<void>> = new Map();

  static async prepare(content: string): Promise<void> {
    const pattern = LocalTextImage.pattern();
    let match = pattern.exec(content);
    let batch: Promise<void>[] = [];
    while (match !== null) {
      const path = match[1];
      if (LocalTextImage.resolve(path) && LocalTextImage.size(path) === undefined) {
        batch.push(LocalTextImageSizing.read(path));
        if (batch.length === 4) { await Promise.all(batch); batch = []; }
      }
      match = pattern.exec(content);
    }
    await Promise.all(batch);
  }

  private static async read(path: string): Promise<void> {
    const current = LocalTextImageSizing.pending.get(path);
    if (current !== undefined) return current;
    const task = LocalTextImageSizing.probe(path);
    LocalTextImageSizing.pending.set(path, task);
    try { await task; } finally { LocalTextImageSizing.pending.delete(path); }
  }

  private static async probe(path: string): Promise<void> {
    let source: image.ImageSource | null = null;
    try {
      source = image.createImageSource(path);
      const info = await source.getImageInfo();
      LocalTextImage.rememberSize(path, info.size.width, info.size.height);
    } catch (_error) {
      // 缺失或损坏图片不阻断前后正文，也不预留整页空白。
      LocalTextImage.rememberSize(path, 0, 0);
    } finally {
      if (source !== null) { try { await source.release(); } catch (_error) {} }
    }
  }
}
