import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { ReadingExcerpt } from '../../model/ReadingExcerpt';

/** 按完整文字分页生成卡片，一次只编码一张，分享只携带沙箱 URI。 */
export class ReadingExcerptShareService {
  static date(value: number): string {
    const date = new Date(value);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-` +
      String(date.getDate()).padStart(2, '0');
  }

  static attribution(excerpt: ReadingExcerpt): string {
    return `《${excerpt.bookTitle}》` + (excerpt.author ? ` / ${excerpt.author}` : '');
  }

  static text(excerpt: ReadingExcerpt): string {
    return `${excerpt.text}\n\n${ReadingExcerptShareService.attribution(excerpt)}`;
  }

  private static wrap(context: OffscreenCanvasRenderingContext2D, text: string): string[] {
    const lines: string[] = [];
    let line = '';
    for (const character of text.replace(new RegExp('\r\n?', 'g'), '\n')) {
      if (character === '\n') { lines.push(line); line = ''; continue; }
      if (line && context.measureText(line + character).width > 832) {
        lines.push(line); line = character;
      } else { line += character; }
    }
    lines.push(line);
    return lines;
  }

  private static async prune(directory: string): Promise<void> {
    const names = (await fileIo.listFile(directory)).filter((name: string): boolean =>
      new RegExp('^excerpt_[0-9]+_[0-9]+\\.png$').test(name)).sort();
    const expired = Date.now() - 24 * 60 * 60 * 1000;
    for (let i = 0; i < names.length; i++) {
      if (i < names.length - 60 || Number(names[i].split('_')[1]) < expired) {
        await fileIo.unlink(`${directory}/${names[i]}`).catch((): void => {});
      }
    }
  }

  /** 与摘录卡片的 reading_excerpt_pattern.svg 同源几何，按 2 倍尺寸铺在右下角。 */
  private static pattern(canvas: OffscreenCanvasRenderingContext2D, height: number): void {
    canvas.strokeStyle = '#E9E5E0'; canvas.lineWidth = 2;
    canvas.beginPath();
    canvas.moveTo(740, height);
    canvas.bezierCurveTo(744, height - 120, 848, height - 204, 960, height - 204);
    canvas.moveTo(776, height);
    canvas.bezierCurveTo(782, height - 100, 868, height - 164, 960, height - 164);
    canvas.moveTo(816, height);
    canvas.bezierCurveTo(822, height - 64, 886, height - 122, 960, height - 122);
    canvas.moveTo(856, height);
    canvas.bezierCurveTo(860, height - 32, 902, height - 76, 960, height - 76);
    canvas.stroke();
    canvas.fillStyle = '#E9E5E0';
    canvas.beginPath(); canvas.arc(896, height - 236, 3, 0, Math.PI * 2); canvas.fill();
    canvas.beginPath(); canvas.arc(918, height - 222, 2, 0, Math.PI * 2); canvas.fill();
    canvas.beginPath(); canvas.arc(938, height - 246, 2.4, 0, Math.PI * 2); canvas.fill();
  }

  private static brandIcon(canvas: OffscreenCanvasRenderingContext2D, icon: image.PixelMap, x: number, y: number): void {
    canvas.save();
    try {
      canvas.beginPath();
      canvas.moveTo(x + 16, y);
      canvas.lineTo(x + 48, y); canvas.arcTo(x + 64, y, x + 64, y + 16, 16);
      canvas.lineTo(x + 64, y + 48); canvas.arcTo(x + 64, y + 64, x + 48, y + 64, 16);
      canvas.lineTo(x + 16, y + 64); canvas.arcTo(x, y + 64, x, y + 48, 16);
      canvas.lineTo(x, y + 16); canvas.arcTo(x, y, x + 16, y, 16);
      canvas.closePath(); canvas.clip();
      canvas.drawImage(icon, x, y, 64, 64);
    } finally { canvas.restore(); }
  }

  static async cards(context: common.Context, excerpt: ReadingExcerpt, cancelled: () => boolean): Promise<string[]> {
    const directory = `${context.cacheDir}/reading_excerpt_cards`;
    if (!fileIo.accessSync(directory)) fileIo.mkdirSync(directory);
    await ReadingExcerptShareService.prune(directory);
    const canvas = new OffscreenCanvasRenderingContext2D(960, 2200,
      new RenderingContextSettings(true), LengthMetricsUnit.PX);
    const paths: string[] = [];
    let iconSource: image.ImageSource | undefined = undefined;
    let appIcon: image.PixelMap | undefined = undefined;
    try {
      canvas.font = '38px sans-serif';
      const lines = ReadingExcerptShareService.wrap(canvas, excerpt.text);
      const pageCount = Math.ceil(lines.length / 28);
      if (pageCount > 60) throw new Error('reading_excerpt_card_limit');
      if (cancelled()) throw new Error('reading_excerpt_cancelled');
      const iconBytes = await context.resourceManager.getMediaContent($r('app.media.app_icon_legacy').id);
      iconSource = image.createImageSource(iconBytes.buffer);
      appIcon = await iconSource.createPixelMap({ desiredSize: { width: 64, height: 64 } });
      const stamp = Date.now();
      for (let page = 0; page < pageCount; page++) {
        if (cancelled()) throw new Error('reading_excerpt_cancelled');
        canvas.reset();
        const content = lines.slice(page * 28, (page + 1) * 28);
        const height = Math.max(640, 390 + content.length * 60);
        canvas.fillStyle = '#FFFFFF'; canvas.fillRect(0, 0, 960, height);
        ReadingExcerptShareService.pattern(canvas, height);
        canvas.textBaseline = 'top'; canvas.textAlign = 'left';
        canvas.fillStyle = '#7B8487'; canvas.font = '28px sans-serif';
        canvas.fillText(context.resourceManager.getStringSync($r('app.string.reader_excerpt_date').id,
          ReadingExcerptShareService.date(excerpt.createdAt)), 64, 64);
        canvas.fillStyle = '#20262C'; canvas.font = '38px sans-serif';
        content.forEach((line: string, index: number): void => { canvas.fillText(line, 64, 132 + index * 60); });
        canvas.fillStyle = '#7B8487'; canvas.font = '28px sans-serif';
        canvas.fillText(ReadingExcerptShareService.attribution(excerpt), 64, 162 + content.length * 60, 832);
        canvas.font = 'bold 28px sans-serif';
        canvas.fillStyle = '#3C4247';
        const brand = context.resourceManager.getStringSync($r('app.string.reader_excerpt_brand').id);
        const brandLeft = (960 - 64 - 16 - canvas.measureText(brand).width) / 2;
        ReadingExcerptShareService.brandIcon(canvas, appIcon, brandLeft, height - 112);
        canvas.fillText(brand, brandLeft + 80, height - 94);
        if (pageCount > 1) {
          canvas.textAlign = 'right'; canvas.font = '24px sans-serif';
          canvas.fillStyle = '#899092'; canvas.fillText(`${page + 1} / ${pageCount}`, 896, height - 88);
        }
        const path = `${directory}/excerpt_${stamp}_${String(page).padStart(2, '0')}.png`;
        paths.push(path);
        const pixels = canvas.getPixelMap(0, 0, 960, height);
        let packer: image.ImagePacker | undefined = undefined;
        let file: fileIo.File | undefined = undefined;
        try {
          packer = image.createImagePacker();
          file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
          await packer.packToFile(pixels, file.fd, { format: 'image/png', quality: 100 });
        } finally {
          if (file) await fileIo.close(file).catch((): void => {});
          if (packer) await packer.release().catch((): void => {});
          await pixels.release().catch((): void => {});
        }
      }
      if (cancelled()) throw new Error('reading_excerpt_cancelled');
      return paths;
    } catch (error) {
      for (const path of paths) await fileIo.unlink(path).catch((): void => {});
      throw new Error(error instanceof Error ? error.message : 'reading_excerpt_share_failed');
    } finally {
      if (appIcon) await appIcon.release().catch((): void => {});
      if (iconSource) await iconSource.release().catch((): void => {});
      canvas.reset();
    }
  }

  static imageController(paths: string[], title: string): systemShare.ShareController {
    if (paths.length === 0) throw new Error('reading_excerpt_share_failed');
    const data = new systemShare.SharedData({ utd: uniformTypeDescriptor.UniformDataType.PNG,
      uri: fileUri.getUriFromPath(paths[0]), title });
    for (let i = 1; i < paths.length; i++) {
      data.addRecord({ utd: uniformTypeDescriptor.UniformDataType.PNG, uri: fileUri.getUriFromPath(paths[i]), title });
    }
    return new systemShare.ShareController(data);
  }
}
