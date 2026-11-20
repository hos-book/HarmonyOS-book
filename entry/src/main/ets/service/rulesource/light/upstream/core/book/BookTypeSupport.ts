import { Book, BookSource, SearchBook } from '../../model/data/Book';

/** Legado-compatible remote book type bits. Local TXT/EPUB keep their existing 1/2 values. */
export class BookTypeSupport {
  static readonly TEXT: number = 8;
  static readonly AUDIO: number = 32;
  static readonly IMAGE: number = 64;
  static readonly WEB_FILE: number = 128;
  static readonly CATEGORY_NOVEL: string = 'novel';
  static readonly CATEGORY_COMIC: string = 'comic';
  static readonly CATEGORY_AUDIO: string = 'audio';
  static readonly CATEGORY_VIDEO: string = 'video';
  static readonly MEDIA_CATEGORIES: string[] = ['novel', 'comic', 'audio', 'video'];

  static typeFromSource(source: BookSource | null): number {
    if (!source) return 0;
    if (source.bookSourceType === 1) return this.AUDIO;
    if (source.bookSourceType === 2) return this.IMAGE;
    if (source.bookSourceType === 3) return this.TEXT | this.WEB_FILE;
    // Imported sources occasionally omit bookSourceType even though their primary content rule
    // explicitly selects image elements.  Infer image mode from that rule shape, not from a site
    // name or host, so the same capability remains useful for any user-supplied comic source.
    const contentRule = source.contentRule ? String(source.contentRule.content || '') : '';
    if (/@(?:img|image)@(?:html|src|data-src|href)\b/i.test(contentRule) ||
      /(?:^|[.#@])(?:img|image)(?:\[[^\]]*\])?@(?:html|src|data-src|href)\b/i.test(contentRule)) {
      return this.IMAGE;
    }
    return 0;
  }

  static typeFromTab(tab: string): number {
    const value = String(tab || '').trim().toLowerCase();
    if (value === 'audio' || value === 'listen' || value === 'audiobook' || value === '听书' || value === '音频' ||
      value === '有声' || value === '畅听') {
      return this.AUDIO;
    }
    if (value === 'comic' || value === 'image' || value === 'manga' || value === '漫画') return this.IMAGE;
    if (value === 'novel' || value === 'text' || value === '小说') return this.TEXT;
    return 0;
  }

  static applySearchBookType(book: SearchBook, source: BookSource | null, tab: string = '', identity: string = ''): void {
    const resolved = this.typeFromTab(tab) || this.typeFromIdentity(identity, book.kind) ||
      this.typeFromVariable(book.variable) || this.typeFromSource(source);
    if (resolved) book.type = resolved;
  }

  static applyBookType(book: Book, source: BookSource | null = null, tab: string = '', identity: string = ''): void {
    if (book.origin === 'local') return;
    const resolved = this.typeFromTab(tab) || this.typeFromIdentity(identity, book.kind) ||
      this.typeFromVariable(book.variable) || this.typeFromSource(source) ||
      this.typeFromIdentity(book.originName, book.kind);
    if (resolved) book.type = resolved;
  }

  static isAudio(book: Book | SearchBook | null): boolean {
    if (!book || book.origin === 'local') return false;
    if ((Number(book.type) & this.AUDIO) !== 0) return true;
    if (this.hasDeclaredMedia(book.variable)) return this.typeFromVariable(book.variable) === this.AUDIO;
    return this.typeFromIdentity(book.originName, book.kind) === this.AUDIO;
  }

  static isImage(book: Book | SearchBook | null): boolean {
    if (!book) return false;
    if (book.origin === 'local') return this.isLocalImageVariable(book.variable);
    if ((Number(book.type) & this.IMAGE) !== 0) return true;
    if (this.hasDeclaredMedia(book.variable)) return this.typeFromVariable(book.variable) === this.IMAGE;
    return this.typeFromIdentity(book.originName, book.kind) === this.IMAGE;
  }

  /**
   * 书籍变量里明确写了媒体类型（小说/漫画/有声/视频）。写了就以它为准，不再按书源名、分类去猜：
   * 名为“漫画xx综合”的多频道书源里，声明为小说的书不能因为书源名带“漫画”被当成漫画。
   */
  static hasDeclaredMedia(variable: string): boolean {
    if (!variable) return false;
    if (this.typeFromVariable(variable) !== 0) return true;
    const match = variable.match(/["']?(?:tab|type|mediaType)["']?\s*:\s*["']video["']/i);
    return match !== null;
  }

  /** 视频类书籍（短剧等）：没有阅读形态，由书源在书籍变量里声明 tab=video。 */
  static isVideo(book: Book | SearchBook | null): boolean {
    if (!book || book.origin === 'local' || !book.variable || book.variable.indexOf('video') < 0) return false;
    try {
      const record = JSON.parse(book.variable) as Record<string, Object>;
      return String(record['tab'] || '') === 'video';
    } catch (_) {
      return false;
    }
  }

  /** Media bucket a book is listed under. Anything that is not video, audio or comic reads as a novel. */
  static mediaCategoryOf(book: Book | SearchBook | null): string {
    if (book instanceof SearchBook && book.mediaCategory) return book.mediaCategory;
    if (this.isVideo(book)) return this.CATEGORY_VIDEO;
    if (this.isAudio(book)) return this.CATEGORY_AUDIO;
    if (this.isImage(book)) return this.CATEGORY_COMIC;
    return this.CATEGORY_NOVEL;
  }

  static typeFromVariable(variable: string): number {
    if (!variable) return 0;
    try {
      const record = JSON.parse(variable) as Record<string, Object>;
      const tab = String(record['tab'] || record['type'] || record['mediaType'] || '');
      return this.typeFromTab(tab);
    } catch (_) {
      const match = variable.match(/["']?(?:tab|mediaType)["']?\s*:\s*["']([^"']+)["']/i);
      return match ? this.typeFromTab(match[1] || '') : 0;
    }
  }

  private static typeFromIdentity(originName: string, kind: string): number {
    const value = `${originName || ''}\n${kind || ''}`;
    if (/听书|畅听|有声|音频|audiobook|audio/i.test(value)) return this.AUDIO;
    if (/漫画|漫改|comic|manga/i.test(value)) return this.IMAGE;
    return 0;
  }

  private static isLocalImageVariable(variable: string): boolean {
    if (!variable) return false;
    try {
      const record = JSON.parse(variable) as Record<string, Object>;
      const manualMode = String(record['readerComicManualMode'] || '').trim().toLowerCase();
      if (manualMode === 'text') return false;
      if (manualMode === 'comic') return true;
      const autoDetected = String(record['readerComicAutoDetected'] || '').trim().toLowerCase();
      const comicMode = String(record['readerComicMode'] || '').trim().toLowerCase();
      return autoDetected === '1' || autoDetected === 'true' ||
        comicMode === '1' || comicMode === 'true';
    } catch (_) {
      return false;
    }
  }
}
