import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { drawing, text as graphicsText } from '@kit.ArkGraphics2D';
import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const SIZE: number = 384;

/** 系统媒体和桌面卡片共享的本地占位封面；不修改用户的 book.cover。 */
export class LocalBookCoverService {
  private static pending: Map<string, Promise<string>> = new Map();

  static async resolve(context: common.Context, bookId: string, cover: string,
    title: string, author: string): Promise<string> {
    if (cover || !bookId.startsWith('import_')) return cover;
    const identity = JSON.stringify([title, author]);
    const key = `${context.cacheDir}:${identity}`;
    const active = LocalBookCoverService.pending.get(key);
    if (active) return active;
    const task = LocalBookCoverService.create(context, identity, title, author);
    LocalBookCoverService.pending.set(key, task);
    try {
      return await task;
    } finally {
      LocalBookCoverService.pending.delete(key);
    }
  }

  private static async create(context: common.Context, identity: string, title: string,
    author: string): Promise<string> {
    let source: image.ImageSource | undefined;
    let background: image.PixelMap | undefined;
    let output: image.PixelMap | undefined;
    let packer: image.ImagePacker | undefined;
    let temporary: string = '';
    try {
      const digest = cryptoFramework.createMd('SHA256');
      await digest.update({ data: new util.TextEncoder().encodeInto(identity) });
      const hash = (await digest.digest()).data;
      const name = Array.from(hash).map((byte: number): string => byte.toString(16).padStart(2, '0')).join('');
      const directory = `${context.cacheDir}/local_book_covers_v1`;
      if (!fileIo.accessSync(directory)) {
        try { fileIo.mkdirSync(directory, true); } catch (error) {
          if (!fileIo.accessSync(directory)) throw new Error(String(error));
        }
      }
      const path = `${directory}/${name}.jpg`;
      if (fileIo.accessSync(path) && fileIo.statSync(path).size > 0) return path;
      const bytes = await context.resourceManager.getMediaContent($r('app.media.local_book_cover_placeholder').id);
      source = image.createImageSource(bytes.buffer);
      background = await source.createPixelMap();
      output = await image.createPixelMap(new ArrayBuffer(SIZE * SIZE * 4), {
        size: { width: SIZE, height: SIZE }, pixelFormat: image.PixelMapFormat.RGBA_8888, editable: true
      });
      const canvas = new drawing.Canvas(output);
      canvas.drawImageRect(background, { left: 0, top: 0, right: SIZE, bottom: SIZE });
      LocalBookCoverService.drawText(canvas, title, 44, 3, 0.22, 0.32, 0.72, true);
      LocalBookCoverService.drawText(canvas, author, 28, 2, 0.66, 0.14, 0.68, false);
      packer = image.createImagePacker();
      const encoded = await packer.packToData(output, { format: 'image/jpeg', quality: 92 });
      temporary = `${path}.${util.generateRandomUUID()}.tmp`;
      const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try { fileIo.writeSync(file.fd, encoded); } finally { fileIo.closeSync(file); }
      fileIo.renameSync(temporary, path);
      temporary = '';
      LocalBookCoverService.trimCache(directory, path);
      return path;
    } catch (error) {
      hilog.warn(0xFF00, 'LocalBookCover', 'render failed: %{public}s', String(error));
      return '';
    } finally {
      if (temporary) { try { fileIo.unlinkSync(temporary); } catch (_) {} }
      if (packer) { try { await packer.release(); } catch (_) {} }
      if (output) { try { await output.release(); } catch (_) {} }
      if (background) { try { await background.release(); } catch (_) {} }
      if (source) { try { await source.release(); } catch (_) {} }
    }
  }

  private static drawText(canvas: drawing.Canvas, text: string, size: number, maxLines: number,
    top: number, height: number, width: number, bold: boolean): void {
    const style: graphicsText.TextStyle = {
      fontSize: size, fontWeight: bold ? graphicsText.FontWeight.W700 : graphicsText.FontWeight.W400,
      fontFamilies: [], heightScale: 1.15, heightOnly: true, locale: 'zh-Hans', ellipsis: '…',
      color: { alpha: 255, red: bold ? 73 : 100, green: bold ? 62 : 88, blue: bold ? 53 : 75 }
    };
    const paragraphStyle: graphicsText.ParagraphStyle = {
      textStyle: style, align: graphicsText.TextAlign.CENTER, maxLines: maxLines,
      wordBreak: graphicsText.WordBreak.BREAK_WORD, breakStrategy: graphicsText.BreakStrategy.GREEDY
    };
    const builder = new graphicsText.ParagraphBuilder(paragraphStyle, graphicsText.FontCollection.getGlobalInstance());
    builder.pushStyle(style);
    builder.addText(text.trim().replace(/\s+/g, ' ').slice(0, 512));
    builder.popStyle();
    const paragraph = builder.build();
    paragraph.layoutSync(SIZE * width);
    paragraph.paint(canvas, SIZE * (1 - width) / 2, SIZE * top + (SIZE * height - paragraph.getHeight()) / 2);
  }

  private static trimCache(directory: string, current: string): void {
    try {
      const files = fileIo.listFileSync(directory).filter((name: string): boolean => name.endsWith('.jpg'));
      if (files.length <= 32) return;
      files.sort((a: string, b: string): number =>
        fileIo.statSync(`${directory}/${a}`).mtime - fileIo.statSync(`${directory}/${b}`).mtime);
      let remaining = files.length;
      for (const name of files) {
        if (remaining <= 32) break;
        const path = `${directory}/${name}`;
        if (path === current) continue;
        fileIo.unlinkSync(path);
        remaining--;
      }
    } catch (_) { /* 缓存清理不影响已生成的封面。 */ }
  }
}
