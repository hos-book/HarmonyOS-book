import { fileIo } from '@kit.CoreFileKit';
import { EpubPageStyle, EpubStyleRun } from './EpubPageStyle';

/** 样式只从本书的目录读取，图片只允许导入器生成的文件名。旧书缺少样式文件时正常重排。 */
export class EpubStyleStore {
  static async read(filesDir: string, bookId: string, chapterPath: string): Promise<EpubStyleRun[]> {
    if (!/^import_[A-Za-z0-9_]+$/.test(bookId)) return [];
    const directory = `${filesDir}/ebooks/${bookId}/`;
    if (!chapterPath.startsWith(directory) || !/^\d+\.txt$/.test(chapterPath.substring(directory.length))) return [];
    const path = chapterPath.replace(/\.txt$/, '.style.json');
    try {
      if ((await fileIo.stat(path)).size > 1024 * 1024) return [];
      const stored: EpubStyleRun[] = JSON.parse(await fileIo.readText(path));
      if (!Array.isArray(stored) || stored.length > 4096) return [];
      const result: EpubStyleRun[] = [];
      for (const run of stored) {
        if (!run || !run.style || !Number.isInteger(run.start) || run.start < 0 ||
          (result.length > 0 && run.start <= result[result.length - 1].start)) return [];
        const style = new EpubPageStyle();
        const input = run.style;
        if (typeof input.image === 'string' && /^image_\d+_\d+\.img$/.test(input.image)) style.image = directory + input.image;
        if (typeof input.color === 'string') style.color = EpubPageStyle.color(input.color);
        if (typeof input.foreground === 'string') style.foreground = EpubPageStyle.color(input.foreground);
        if (typeof input.headingColor === 'string') style.headingColor = EpubPageStyle.color(input.headingColor);
        if (typeof input.headingForeground === 'string') style.headingForeground = EpubPageStyle.color(input.headingForeground);
        if (['cover', 'contain'].includes(input.size)) style.size = input.size;
        if (['no-repeat', 'repeat-x', 'repeat-y'].includes(input.repeat)) style.repeat = input.repeat;
        if (typeof input.position === 'string') style.position = EpubPageStyle.position(input.position);
        result.push(new EpubStyleRun(run.start, style));
      }
      return result;
    } catch (_error) { return []; }
  }

  static at(runs: EpubStyleRun[], offset: number): EpubPageStyle {
    for (let index = runs.length - 1; index >= 0; index--) if (runs[index].start <= offset) return runs[index].style;
    return new EpubPageStyle();
  }
}
