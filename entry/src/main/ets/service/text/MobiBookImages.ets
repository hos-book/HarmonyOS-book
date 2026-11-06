import { common } from '@kit.AbilityKit';
import { fileIo, statfs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { MobiBookInfo, MobiBookParser } from './MobiBookParser';
import { LocalTextImage } from './LocalTextImage';
import { LocalBookHtmlText } from './LocalBookHtmlText';
import { EpubContentProfile } from './EpubContentProfile';

/** Extract referenced images once; keep the original bytes and their reading order. */
export class MobiBookImages {
  private saved: Map<number, string> = new Map<number, string>();
  private imageBytes: number = 0;

  async body(context: common.Context, fd: number, info: MobiBookInfo,
    html: string, directory: string): Promise<string> {
    html = EpubContentProfile.body(html);
    const pattern = /<(?:img|image)\b[^>]*>/gi;
    const tokens: string[] = [];
    const placeholders: string[] = [];
    let output = '';
    let start = 0;
    let tag = pattern.exec(html);
    while (tag !== null) {
      output += html.substring(start, tag.index);
      const attribute = /\srecindex\s*=\s*(?:"(\d+)"|'(\d+)'|(\d+)(?=[\s/>]))/i.exec(tag[0]);
      if (attribute === null) throw new Error('import_mobi_image_missing');
      const index = Number(attribute[1] || attribute[2] || attribute[3]);
      let path = this.saved.get(index) ?? '';
      if (!path) {
        const bytes = await MobiBookParser.readImage(fd, info, index);
        if (this.imageBytes + bytes.byteLength > 6 * 1024 * 1024 * 1024) {
          throw new Error('import_mobi_image_limit');
        }
        const decoder = image.createImageSource(bytes);
        try {
          const dimensions = (await decoder.getImageInfo()).size;
          if (dimensions.width <= 0 || dimensions.height <= 0 ||
            dimensions.width * dimensions.height > 32 * 1024 * 1024) {
            throw new Error('import_mobi_image_limit');
          }
        } catch (error) {
          if (error instanceof Error && error.message === 'import_mobi_image_limit') throw error;
          throw new Error('import_mobi_image_missing');
        } finally { await decoder.release(); }
        if (await statfs.getFreeSize(context.filesDir) < bytes.byteLength + 256 * 1024 * 1024) {
          throw new Error('import_mobi_image_space');
        }
        path = `${directory}/image_${index}_0.img`;
        const target = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try {
          let offset = 0;
          while (offset < bytes.byteLength) {
            const written = await fileIo.write(target.fd, bytes.slice(offset));
            if (written <= 0) throw new Error('import_mobi_image_write');
            offset += written;
          }
        } finally { await fileIo.close(target); }
        this.imageBytes += bytes.byteLength;
        this.saved.set(index, path);
      }
      // Clean the source HTML before inserting local markers, as with EPUB images.
      let placeholder = `HSDAMOBIIMAGE${tokens.length}END`;
      while (html.includes(placeholder)) placeholder += 'X';
      placeholders.push(placeholder);
      tokens.push(LocalTextImage.token(path));
      output += `\n${placeholder}\n`;
      start = pattern.lastIndex;
      tag = pattern.exec(html);
    }
    output += html.substring(start);
    output = LocalBookHtmlText.clean(output);
    for (let index = 0; index < tokens.length; index++) output = output.replace(placeholders[index], tokens[index]);
    return output;
  }
}
