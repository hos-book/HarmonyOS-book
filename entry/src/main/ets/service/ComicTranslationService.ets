import { image } from '@kit.ImageKit';
import { LengthMetricsUnit } from '@kit.ArkUI';
import lazy { textRecognition } from '@kit.CoreVisionKit';
import { ComicTranslationRegion, ComicTextBox, ComicTranslationText } from '../model/ComicTranslation';
import { ComicOfflineTranslationService } from './ComicOfflineTranslationService';
import { MembershipState } from '../model/MembershipState';

/** 系统 OCR 定位原文、端侧模型翻译、本机回填；翻译链路不调用在线 API。 */
export class ComicTranslationService {
  static supported(): boolean { return canIUse('SystemCapability.AI.OCR.TextRecognition'); }

  static async translate(jpeg: ArrayBuffer, language: string,
    isActive: () => boolean): Promise<Uint8Array> {
    const active = (): boolean => isActive() && MembershipState.current.hasAccess;
    if (!active()) throw new Error('comic_ai_cancelled');
    if (!ComicTranslationService.supported()) throw new Error('comic_ai_ocr_unsupported');
    const source = image.createImageSource(jpeg);
    let pixels: image.PixelMap | null = null;
    try {
      const size = (await source.getImageInfo()).size;
      if (size.width < 32 || size.height < 32 || size.width * size.height > 32 * 1024 * 1024) {
        throw new Error('comic_ai_image_too_large');
      }
      pixels = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      return await ComicTranslationService.translatePixels(pixels, size.width, size.height, language, active, jpeg);
    } finally {
      try { if (pixels !== null) await pixels.release(); } finally { await source.release(); }
    }
  }

  /** 复用阅读器已解码的像素；所有权仍属于调用方，只编码一次最终结果。 */
  static async translatePixels(pixels: image.PixelMap, width: number, height: number,
    language: string, isActive: () => boolean, original?: ArrayBuffer): Promise<Uint8Array> {
    const active = (): boolean => isActive() && MembershipState.current.hasAccess;
    if (!active()) throw new Error('comic_ai_cancelled');
    if (!ComicTranslationService.supported()) throw new Error('comic_ai_ocr_unsupported');
    if (width < 32 || height < 32 || width * height > 32 * 1024 * 1024 ||
      Math.max(width, height) > 32768) throw new Error('comic_ai_image_too_large');
    const started = Date.now();
    const regions = await ComicTranslationService.recognizeTiles(pixels, width, height, active);
    const recognized = Date.now();
    if (!active()) throw new Error('comic_ai_cancelled');
    // 无文字页不请求模型；兼容字节入口可直接复用原图。
    if (regions.length === 0) return original === undefined ? new Uint8Array(0) : new Uint8Array(original);
    const input = regions.map((region: ComicTranslationRegion, id: number): ComicTranslationText =>
      new ComicTranslationText(id, region.source));
    const translated: ComicTranslationText[] = regions.length === 0 ? [] :
      await ComicOfflineTranslationService.translate(input, language, active);
    const received = Date.now();
    if (!active()) throw new Error('comic_ai_cancelled');
    const output = await ComicTranslationService.render(pixels, width, height, regions, translated, active);
    if (!active()) throw new Error('comic_ai_cancelled');
    console.info(`[ComicTranslation] ocrMs=${recognized - started} modelMs=${received - recognized} renderMs=${Date.now() - received}`);
    return output;
  }

  /** OCR 使用原尺寸的重叠分块，坐标平移回原图，回填始终保留原始像素。 */
  private static async recognizeTiles(pixels: image.PixelMap, width: number, height: number,
    active: () => boolean): Promise<ComicTranslationRegion[]> {
    if (width <= 2048 && height <= 2048 && width * height <= 2 * 1024 * 1024) {
      return ComicTranslationService.recognize(pixels, width, height);
    }
    const edge = 1280;
    const overlap = 192;
    const regions: ComicTranslationRegion[] = [];
    for (let top = 0; top < height; top += edge - overlap) {
      for (let left = 0; left < width; left += edge - overlap) {
        if (!active()) throw new Error('comic_ai_cancelled');
        const w = Math.min(edge, width - left); const h = Math.min(edge, height - top);
        const canvas = new OffscreenCanvas(w, h, LengthMetricsUnit.PX);
        let tile: image.PixelMap | null = null;
        try {
          const ctx = canvas.getContext('2d', new RenderingContextSettings(true));
          if (!ctx) throw new Error('comic_ai_translate_render_failed');
          ctx.drawImage(pixels, left, top, w, h, 0, 0, w, h);
          tile = ctx.getPixelMap(0, 0, w, h);
          const found = await ComicTranslationService.recognize(tile, w, h);
          for (const region of found) {
            region.x += left; region.y += top;
            for (const box of region.masks) { box.x += left; box.y += top; }
            ComicTranslationService.addRegion(regions, region);
          }
        } finally {
          if (tile !== null) await tile.release();
          canvas.width = 0; canvas.height = 0;
        }
        if (left + w >= width) break;
      }
      if (top + Math.min(edge, height - top) >= height) break;
    }
    if (regions.length > 128 || regions.reduce((sum: number, region: ComicTranslationRegion): number =>
      sum + region.source.length, 0) > 16000) throw new Error('comic_ai_translate_too_large');
    return regions;
  }

  static addRegion(regions: ComicTranslationRegion[], region: ComicTranslationRegion): void {
    const index = regions.findIndex((other: ComicTranslationRegion): boolean => {
      const overlap = Math.max(0, Math.min(other.x + other.width, region.x + region.width) - Math.max(other.x, region.x)) *
        Math.max(0, Math.min(other.y + other.height, region.y + region.height) - Math.max(other.y, region.y));
      return overlap > Math.min(other.width * other.height, region.width * region.height) * 0.65;
    });
    if (index < 0) regions.push(region);
    else if (region.source.length > regions[index].source.length) regions[index] = region;
  }

  private static async recognize(pixels: image.PixelMap, width: number, height: number): Promise<ComicTranslationRegion[]> {
    let result: textRecognition.TextRecognitionResult;
    try {
      if (!await textRecognition.init()) throw new Error('unavailable');
      result = await textRecognition.recognizeText({ pixelMap: pixels }, { isDirectionDetectionSupported: false });
    } catch (_error) { throw new Error('comic_ai_ocr_failed'); }
    finally { try { await textRecognition.release(); } catch (_error) { } }
    return ComicTranslationService.regions(result, width, height);
  }

  static regions(result: textRecognition.TextRecognitionResult, width: number, height: number): ComicTranslationRegion[] {
    const regions: ComicTranslationRegion[] = [];
    let total = 0;
    for (const block of result.blocks) {
      let current: ComicTranslationRegion | null = null;
      for (const line of block.lines) {
        const value = line.value.trim();
        if (!value || line.cornerPoints.length !== 4) continue;
        const box = new ComicTextBox();
        const xs = line.cornerPoints.map((point: textRecognition.PixelPoint): number => point.x);
        const ys = line.cornerPoints.map((point: textRecognition.PixelPoint): number => point.y);
        if (xs.some((n: number): boolean => !Number.isFinite(n)) || ys.some((n: number): boolean => !Number.isFinite(n))) continue;
        box.x = Math.max(0, Math.floor(Math.min(...xs)) - 1);
        box.y = Math.max(0, Math.floor(Math.min(...ys)) - 1);
        box.width = Math.min(width, Math.ceil(Math.max(...xs)) + 2) - box.x;
        box.height = Math.min(height, Math.ceil(Math.max(...ys)) + 2) - box.y;
        if (box.width < 3 || box.height < 3 || box.width * box.height > width * height * 0.25) continue;
        total += value.length;
        if (value.length > 2000 || total > 16000) throw new Error('comic_ai_translate_too_large');
        if (current !== null && ComicTranslationService.adjacent(current.masks[current.masks.length - 1], box) &&
          current.source.length + value.length + 1 <= 2000) {
          const right = Math.max(current.x + current.width, box.x + box.width);
          const bottom = Math.max(current.y + current.height, box.y + box.height);
          current.x = Math.min(current.x, box.x); current.y = Math.min(current.y, box.y);
          current.width = right - current.x; current.height = bottom - current.y;
          current.source += '\n' + value;
          current.masks.push(box);
        } else {
          current = new ComicTranslationRegion();
          current.x = box.x; current.y = box.y; current.width = box.width; current.height = box.height;
          current.source = value; current.masks = [box];
          regions.push(current);
          if (regions.length > 128) throw new Error('comic_ai_translate_too_large');
        }
      }
    }
    return regions;
  }

  private static adjacent(a: ComicTextBox, b: ComicTextBox): boolean {
    const vertical = a.height > a.width * 1.8;
    if (vertical !== (b.height > b.width * 1.8)) return false;
    if (vertical) {
      const overlap = Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y);
      const gap = Math.max(a.x, b.x) - Math.min(a.x + a.width, b.x + b.width);
      return overlap > Math.min(a.height, b.height) * 0.3 && gap >= -2 && gap < Math.min(a.width, b.width);
    }
    const overlap = Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x);
    const gap = b.y - (a.y + a.height);
    return overlap > Math.min(a.width, b.width) * 0.3 && gap >= -2 && gap < Math.min(a.height, b.height);
  }

  /** 保留文本区域之外的画面；用邻近底色擦字，并按真实文字宽度换行和缩放。 */
  static async render(pixels: image.PixelMap, width: number, height: number, regions: ComicTranslationRegion[],
    translations: ComicTranslationText[], active: () => boolean): Promise<Uint8Array> {
    const canvas = new OffscreenCanvas(width, height, LengthMetricsUnit.PX);
    const ctx = canvas.getContext('2d', new RenderingContextSettings(true));
    if (!ctx) throw new Error('comic_ai_translate_render_failed');
    let output: image.PixelMap | null = null;
    try {
      ctx.drawImage(pixels, 0, 0, width, height);
      for (let index = 0; index < regions.length; index++) {
        if (!active()) throw new Error('comic_ai_cancelled');
        const region = regions[index];
        const translated = translations.find((item: ComicTranslationText): boolean => item.id === index);
        if (!translated) throw new Error('comic_ai_translate_invalid_response');
        if (translated.text.trim() === region.source.trim()) continue;
        let font = Math.max(6, Math.min(48, region.height * 0.8, region.width * 0.8));
        let lines: string[] = [];
        while (font >= 6) {
          ctx.font = `${font}px sans-serif`;
          lines = ComicTranslationService.wrap(translated.text, Math.max(1, region.width - 2),
            (text: string): number => ctx.measureText(text).width);
          if (lines.length * font * 1.15 <= region.height && lines.every((line: string): boolean =>
            ctx.measureText(line).width <= region.width)) break;
          font -= 1;
        }
        // 放不下就报告明确错误，不裁掉译文或悄悄显示缺字结果。
        if (font < 6) throw new Error('comic_ai_translate_layout_failed');
        const background = ComicTranslationService.background(ctx, width, height, region);
        ctx.save();
        try {
          ctx.beginPath(); ctx.rect(region.x, region.y, region.width, region.height); ctx.clip();
          ctx.fillStyle = background;
          for (const box of region.masks) ctx.fillRect(box.x, box.y, box.width, box.height);
          const rgb = Number.parseInt(background.substring(1), 16);
          const brightness = ((rgb >> 16) & 255) * 0.299 + ((rgb >> 8) & 255) * 0.587 + (rgb & 255) * 0.114;
          ctx.fillStyle = brightness > 140 ? '#171717' : '#FFFFFF';
          ctx.textAlign = 'center'; ctx.textBaseline = 'top';
          const top = region.y + (region.height - lines.length * font * 1.15) / 2;
          for (let row = 0; row < lines.length; row++) {
            ctx.fillText(lines[row], region.x + region.width / 2, top + row * font * 1.15);
          }
        } finally { ctx.restore(); }
        if (index % 8 === 7) await new Promise<void>((resolve): void => { setTimeout(resolve, 0); });
      }
      if (!active()) throw new Error('comic_ai_cancelled');
      output = ctx.getPixelMap(0, 0, width, height);
      const packer = image.createImagePacker();
      try {
        const bytes = await packer.packToData(output, { format: 'image/png', quality: 100 });
        if (!active()) throw new Error('comic_ai_cancelled');
        if (bytes.byteLength > 20 * 1024 * 1024) throw new Error('comic_ai_image_too_large');
        return new Uint8Array(bytes);
      } finally { await packer.release(); }
    } finally {
      if (output !== null) await output.release();
      canvas.width = 0; canvas.height = 0;
    }
  }

  static wrap(text: string, width: number, measure: (value: string) => number): string[] {
    const lines: string[] = [];
    let current = '';
    // 西文优先整词换行；中日韩逐字换行，超长单词再拆开。
    const tokens = text.replace(/\r/g, '').match(/[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)*|[^\r]/gu) ?? [];
    for (const token of tokens) {
      if (token === '\n') { lines.push(current); current = ''; continue; }
      if (current && measure(current + token) > width) { lines.push(current.trimEnd()); current = ''; }
      if (!current && !token.trim()) continue;
      if (measure(token) > width) {
        for (const character of Array.from(token)) {
          if (current && measure(current + character) > width) { lines.push(current); current = ''; }
          current += character;
        }
      } else current += token;
    }
    if (current || lines.length === 0) lines.push(current.trimEnd());
    return lines;
  }

  private static background(ctx: OffscreenCanvasRenderingContext2D, width: number, height: number, box: ComicTextBox): string {
    const reds: number[] = []; const greens: number[] = []; const blues: number[] = [];
    for (let n = 0; n < 8; n++) {
      const x = Math.round(box.x + box.width * n / 7);
      const y = Math.round(box.y + box.height * n / 7);
      ComicTranslationService.sample(ctx, width, height, x, box.y - 2, reds, greens, blues);
      ComicTranslationService.sample(ctx, width, height, x, box.y + box.height + 1, reds, greens, blues);
      ComicTranslationService.sample(ctx, width, height, box.x - 2, y, reds, greens, blues);
      ComicTranslationService.sample(ctx, width, height, box.x + box.width + 1, y, reds, greens, blues);
    }
    const median = (values: number[]): number => values.sort((a: number, b: number): number => a - b)[Math.floor(values.length / 2)] ?? 255;
    return '#' + [median(reds), median(greens), median(blues)].map((v: number): string => v.toString(16).padStart(2, '0')).join('');
  }

  private static sample(ctx: OffscreenCanvasRenderingContext2D, width: number, height: number,
    x: number, y: number, r: number[], g: number[], b: number[]): void {
    const px = Math.max(0, Math.min(width - 1, Math.round(x)));
    const py = Math.max(0, Math.min(height - 1, Math.round(y)));
    const pixel = ctx.getImageData(px, py, 1, 1).data;
    r.push(pixel[0]); g.push(pixel[1]); b.push(pixel[2]);
  }
}
