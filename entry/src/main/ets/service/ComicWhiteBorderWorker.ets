import { image } from '@kit.ImageKit';
import { fileUri } from '@kit.CoreFileKit';
import { ComicWhiteBorderGeometry } from '../utils/ComicWhiteBorderGeometry';

@Concurrent
export async function detectComicWhiteBorder(uri: string): Promise<number[]> {
  const path: string = uri.startsWith('file://') ? new fileUri.FileUri(uri).path : uri;
  if (!path.startsWith('/')) return [0, 0, 1, 1];
  const source = image.createImageSource(path);
  let bitmap: image.PixelMap | null = null;
  try {
    const info = await source.getImageInfo();
    const scale = Math.min(1, 768 / Math.max(info.size.width, info.size.height));
    const width = Math.max(1, Math.floor(info.size.width * scale));
    const height = Math.max(1, Math.floor(info.size.height * scale));
    if (width < 16 || height < 16) return [0, 0, 1, 1];
    bitmap = await source.createPixelMap({ desiredSize: { width: width, height: height },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    const decoded = await bitmap.getImageInfo();
    const buffer = new ArrayBuffer(decoded.size.width * decoded.size.height * 4);
    await bitmap.readPixelsToBuffer(buffer);
    const crop = ComicWhiteBorderGeometry.detect(new Uint8Array(buffer), decoded.size.width, decoded.size.height);
    return [crop.x, crop.y, crop.width, crop.height];
  } finally {
    try { if (bitmap) await bitmap.release(); }
    finally { await source.release(); }
  }
}
