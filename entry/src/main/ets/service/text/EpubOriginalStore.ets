import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { EpubOriginalDocument, EpubOriginalPart } from './EpubOriginalDocument';
import { LocalImportTaskQueue } from '../LocalImportTaskQueue';

export class EpubOriginalTheme {
  version: number = 1;
  bookId: string = '';
  themeId: string = '';
  enabled: boolean = true;
  chapters: number = 0;
}

/** 原版主题随书籍目录持久保存和删除，不占用全局自定义主题名额。 */
export class EpubOriginalStore {
  static readonly MAX_RESOURCE: number = 64 * 1024 * 1024;
  private directory: string;
  private saved: Set<string> = new Set();
  private directories: Set<string> = new Set();
  private bytes: number = 0;
  private writes: LocalImportTaskQueue | null;

  constructor(directory: string, writes: LocalImportTaskQueue | null = null) {
    this.directory = directory + '/original'; this.writes = writes;
  }

  private async save(path: string, data: string | ArrayBuffer): Promise<void> {
    if (this.writes) await this.writes.add((): Promise<void> => EpubOriginalStore.write(path, data));
    else await EpubOriginalStore.write(path, data);
  }

  static root(filesDir: string, bookId: string): string {
    return /^import_[A-Za-z0-9_]+$/.test(bookId) ? `${filesDir}/ebooks/${bookId}/original` : '';
  }

  private async mkdir(path: string): Promise<void> {
    if (this.directories.has(path)) return;
    if (!await fileIo.access(path)) await fileIo.mkdir(path, true);
    this.directories.add(path);
  }

  static async write(path: string, data: string | ArrayBuffer): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const bytes = typeof data === 'string' ? util.TextEncoder.create('utf-8').encodeInto(data).buffer : data;
      let offset = 0;
      while (offset < bytes.byteLength) {
        const count = await fileIo.write(file.fd, bytes.slice(offset));
        if (count <= 0) throw new Error('Incomplete EPUB original resource');
        offset += count;
      }
    } finally { await fileIo.close(file); }
  }

  async capture(index: number, href: string, html: string,
    read: (relative: string) => Promise<ArrayBuffer | undefined>): Promise<void> {
    await this.mkdir(this.directory);
    await this.save(`${this.directory}/${index}.html`, html);
    this.bytes += html.length * 3;
    const queue = EpubOriginalDocument.dependencies(html, href, false);
    for (let at = 0; at < queue.length; at++) {
      const path = queue[at];
      if (this.saved.has(path)) continue;
      if (this.saved.size >= 50000 || this.bytes > 6 * 1024 * 1024 * 1024) throw new Error('EPUB original resources too large');
      const base = href.split('/').slice(0, -1);
      const target = path.split('/');
      let shared = 0;
      while (shared < base.length && shared < target.length && base[shared] === target[shared]) shared++;
      const relative = '../'.repeat(base.length - shared) + target.slice(shared).join('/');
      let bytes: ArrayBuffer | undefined;
      try { bytes = await read(relative) ?? undefined; }
      catch (_missing) { continue; } // 原书损坏的可选资源保持浏览器正常回退。
      if (bytes === undefined || bytes.byteLength === 0 || bytes.byteLength > EpubOriginalStore.MAX_RESOURCE) continue;
      this.saved.add(path);
      this.bytes += bytes.byteLength;
      const local = `${this.directory}/assets/${EpubOriginalDocument.assetPath(path)}`;
      await this.mkdir(local.substring(0, local.lastIndexOf('/')));
      const mime = EpubOriginalDocument.mime(path);
      if (mime === 'text/css' || mime === 'image/svg+xml') {
        const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(bytes));
        queue.push(...EpubOriginalDocument.dependencies(text, path, mime === 'text/css'));
      }
      await this.save(local, bytes);
    }
  }

  async saveChapter(index: number, parts: EpubOriginalPart[]): Promise<void> {
    await this.save(`${this.directory}/chapter_${index}.json`, JSON.stringify(parts));
  }

  async finish(bookId: string, count: number): Promise<void> {
    const theme = new EpubOriginalTheme();
    theme.bookId = bookId; theme.themeId = `epub-original:${bookId}`; theme.chapters = count;
    await this.save(`${this.directory}/theme.json`, JSON.stringify(theme));
  }

  static async theme(filesDir: string, bookId: string, chapterCount: number): Promise<EpubOriginalTheme | null> {
    const root = EpubOriginalStore.root(filesDir, bookId);
    if (!root) return null;
    try {
      const theme: EpubOriginalTheme = JSON.parse(await fileIo.readText(`${root}/theme.json`));
      return theme.version === 1 && theme.bookId === bookId && theme.themeId === `epub-original:${bookId}` &&
        theme.chapters === chapterCount && typeof theme.enabled === 'boolean' ? theme : null;
    } catch (_error) { return null; }
  }

  static async select(filesDir: string, theme: EpubOriginalTheme, enabled: boolean): Promise<void> {
    const root = EpubOriginalStore.root(filesDir, theme.bookId);
    if (!root) throw new Error('Invalid EPUB theme');
    const next = new EpubOriginalTheme();
    next.bookId = theme.bookId; next.themeId = theme.themeId; next.chapters = theme.chapters; next.enabled = enabled;
    await EpubOriginalStore.write(`${root}/theme.next.json`, JSON.stringify(next));
    await fileIo.moveFile(`${root}/theme.next.json`, `${root}/theme.json`);
    theme.enabled = enabled;
  }

  static async parts(root: string, chapter: number): Promise<EpubOriginalPart[]> {
    if (!root || !Number.isSafeInteger(chapter) || chapter < 0) throw new Error('Invalid EPUB chapter');
    const value: EpubOriginalPart[] = JSON.parse(await fileIo.readText(`${root}/chapter_${chapter}.json`));
    if (!Array.isArray(value) || !value.length || value.length > 4096) throw new Error('Invalid EPUB original layout');
    for (const part of value) {
      if (!Number.isSafeInteger(part.spine) || part.spine < 0 || !Number.isSafeInteger(part.start) || part.start < 0 ||
        !Number.isSafeInteger(part.end) || part.end < part.start || typeof part.href !== 'string' ||
        !Number.isSafeInteger(part.offset) || part.offset < 0 || !Number.isSafeInteger(part.length) || part.length < 0) {
        throw new Error('Invalid EPUB original segment');
      }
    }
    return value;
  }

  static async resource(root: string, path: string): Promise<ArrayBuffer> {
    const file = await fileIo.open(`${root}/assets/${EpubOriginalDocument.assetPath(path)}`, fileIo.OpenMode.READ_ONLY);
    try {
      const size = (await fileIo.stat(file.fd)).size;
      if (size <= 0 || size > EpubOriginalStore.MAX_RESOURCE) throw new Error('Invalid EPUB resource size');
      const bytes = new ArrayBuffer(size);
      let offset = 0;
      while (offset < size) {
        const chunk = new ArrayBuffer(size - offset);
        const count = await fileIo.read(file.fd, chunk, { offset: offset, length: chunk.byteLength });
        if (count <= 0) throw new Error('Incomplete EPUB resource');
        new Uint8Array(bytes).set(new Uint8Array(chunk, 0, count), offset);
        offset += count;
      }
      return bytes;
    } finally { await fileIo.close(file); }
  }
}
