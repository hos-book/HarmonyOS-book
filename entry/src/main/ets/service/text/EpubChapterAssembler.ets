import { EpubPageStyle, EpubStyleRun } from './EpubPageStyle';
import { EpubOriginalPart } from './EpubOriginalDocument';

/** 一章可以跨越多个正文文件；只在原目录边界提交章节。 */
export class EpubChapterAssembler {
  private title: string = '';
  private pieces: string[] = [];
  private chars: number = 0;
  private styles: EpubStyleRun[] = [];
  private originals: EpubOriginalPart[] = [];
  private write: (title: string, text: string, styles: EpubStyleRun[], originals: EpubOriginalPart[]) => Promise<void>;

  constructor(write: (title: string, text: string, styles: EpubStyleRun[], originals: EpubOriginalPart[]) => Promise<void>) {
    this.write = write;
  }

  async add(title: string, text: string, fallback: string, style: EpubPageStyle = new EpubPageStyle(),
    original: EpubOriginalPart | null = null): Promise<void> {
    if (title) {
      await this.finish();
      this.title = title;
    }
    // 只有背景的卷首也保留一页；零宽字符不会被读成文件路径或伪造正文。
    const content = text.replace(/[\u200B\uFEFF]/g, '').replace(/&#160;/gi, ' ').trim() ||
      (style.image || style.color ? '\u2060' : '');
    if (!content) return;
    if (!this.title) this.title = fallback;
    const length = this.chars + content.length + (this.pieces.length > 0 ? 2 : 0);
    if (length > 8 * 1024 * 1024) throw new Error('EPUB_CHAPTER_TOO_LARGE');
    const previous = this.styles.length > 0 ? this.styles[this.styles.length - 1].style : new EpubPageStyle();
    if (JSON.stringify(previous) !== JSON.stringify(style)) {
      if (this.styles.length >= 4096) throw new Error('EPUB_CHAPTER_TOO_LARGE');
      this.styles.push(new EpubStyleRun(this.chars + (this.pieces.length > 0 ? 2 : 0), style));
    }
    if (original !== null) {
      original.offset = this.chars + (this.pieces.length > 0 ? 2 : 0);
      original.length = content.length;
      this.originals.push(original);
    }
    this.pieces.push(content);
    this.chars = length;
  }

  async finish(): Promise<void> {
    if (this.pieces.length > 0) await this.write(this.title, this.pieces.join('\n\n'), this.styles, this.originals);
    this.title = '';
    this.pieces = [];
    this.chars = 0;
    this.styles = [];
    this.originals = [];
  }
}
