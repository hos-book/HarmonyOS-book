import { common } from '@kit.AbilityKit';
import { fileIo, statfs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { bookParser } from '@hms.core.readerservice.bookParser';
import { Book, Chapter } from '../model/Book';
import { KkBiqugeHtmlParser } from './text/KkBiqugeHtmlParser';
import { EpubCoverService } from './text/EpubCoverService';
import { MobiBookParser, MobiBookInfo } from './text/MobiBookParser';
import { FileOpenRouting } from '../utils/FileOpenRouting';
import { DiagnosticLogService } from './DiagnosticLogService';
import { LocalImportTaskQueue } from './LocalImportTaskQueue';
import { LocalTextImage } from './text/LocalTextImage';
import { image } from '@kit.ImageKit';

class EpubReadStats {
  raw: number = 0;
  layout: number = 0;
  imageBytes: number = 0;
}

export class LocalImportFile {
  uri: string = '';
  name: string = '';
  ext: string = '';
}

export class LocalBookPreview {
  title: string = '';
  author: string = '';
  cover: string = '';
  directory: string = '';
}

export class LocalBookImportService {
  private static async epubBody(context: common.Context, handler: bookParser.BookParserHandler,
    index: number, html: string, directory: string, stats: EpubReadStats): Promise<string> {
    const tags = /<(?:img|image)\b[^>]*>/gi;
    const images: string[] = [];
    const placeholders: string[] = [];
    let marked = '';
    let start = 0;
    let match = tags.exec(html);
    while (match !== null) {
      marked += html.substring(start, match.index);
      const attr = /(?:src|(?:xlink:)?href)\s*=\s*["']([^"']+)["']/i.exec(match[0]);
      let token = '';
      if (attr !== null && !/^(?:[a-z]+:|\/\/)/i.test(attr[1])) {
        try {
          const bytes = handler.getResourceContent(index, attr[1].split('#')[0]);
          if (bytes.byteLength > 0 && bytes.byteLength <= 20 * 1024 * 1024 &&
            stats.imageBytes + bytes.byteLength <= 128 * 1024 * 1024) {
            const source = image.createImageSource(bytes);
            try {
              const info = await source.getImageInfo();
              if (info.size.width > 0 && info.size.height > 0 && info.size.width * info.size.height <= 32 * 1024 * 1024) {
                const path = `${directory}/image_${index}_${images.length}.img`;
                const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
                try {
                  let offset = 0;
                  while (offset < bytes.byteLength) {
                    const written = await fileIo.write(file.fd, bytes.slice(offset));
                    if (written <= 0) throw new Error('Incomplete EPUB image');
                    offset += written;
                  }
                } finally { await fileIo.close(file); }
                stats.imageBytes += bytes.byteLength;
                token = `HSDAEPUBIMAGE${index}X${images.length}END`;
                images.push(LocalTextImage.token(path));
                placeholders.push(token);
              }
            } finally { await source.release(); }
          }
        } catch (_error) { /* 单张无效图片不影响正文阅读 */ }
      }
      marked += token ? `\n${token}\n` : '\n';
      start = tags.lastIndex;
      match = tags.exec(html);
    }
    marked += html.substring(start);
    let text = LocalBookImportService.htmlText(marked);
    for (let position = 0; position < images.length; position++) text = text.replace(placeholders[position], images[position]);
    return text;
  }
  static readonly MAX_CHAPTERS: number = 50000;
  static readonly MAX_ARCHIVE_BYTES: number = 32 * 1024 * 1024 * 1024;
  static readonly MAX_EXPANDED_BYTES: number = 64 * 1024 * 1024 * 1024;
  static readonly TEXT_EXTS: string[] = FileOpenRouting.TEXT_EXTS;
  static readonly AUDIO_EXTS: string[] = ['.mp3', '.m4a', '.flac', '.wav', '.ogg', '.aac'];

  private static async openEpub(context: common.Context, path: string): Promise<bookParser.BookParserHandler> {
    if (!canIUse('SystemCapability.Reader.ReaderService.BookParser')) {
      throw new Error(context.resourceManager.getStringSync($r('app.string.epub_parser_unavailable').id));
    }
    // BookParser 同样依赖 ReaderKit HSP，不能在首页导入链中静态加载。
    const parserModule = await import('./text/EpubParserService');
    return parserModule.EpubParserService.open(path);
  }

  /** 选文件后预解析，不写入书架；临时封面在正式导入时复制到书籍目录。 */
  static async preview(context: common.Context, file: LocalImportFile): Promise<LocalBookPreview> {
    const result = new LocalBookPreview();
    result.title = file.name;
    if (file.ext === '.mobi') {
      result.directory = `${context.cacheDir}/book_preview_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
      await fileIo.mkdir(result.directory, true);
      try {
        const info = await LocalBookImportService.readMobi(context, file.uri, undefined, result.directory);
        result.title = info.title || file.name;
        result.author = info.author;
        result.cover = info.cover;
        if (!result.cover) {
          await fileIo.rmdir(result.directory);
          result.directory = '';
        }
        return result;
      } catch (error) {
        await fileIo.rmdir(result.directory).catch((): void => {});
        throw new Error(error instanceof Error ? error.message : String(error));
      }
    }
    if (file.ext === '.txt' || file.ext === '.html' || file.ext === '.htm') {
      const source = await fileIo.open(file.uri, fileIo.OpenMode.READ_ONLY);
      try {
        const buffer = new ArrayBuffer(16384);
        const length = await fileIo.read(source.fd, buffer);
        const sample = new Uint8Array(buffer, 0, length);
        const content = util.TextDecoder.create(LocalBookImportService.detectEncoding(sample))
          .decodeToString(sample, { stream: true });
        const title = file.ext === '.txt' ? /(?:^|\n)\s*(?:书名[：:]\s*|《)([^\n》]{1,120})/.exec(content) :
          /<title[^>]*>([^<]{1,120})<\/title\s*>/i.exec(content);
        const author = /(?:^|\n)\s*作者[：:]\s*([^\r\n]{1,80})/.exec(content);
        if (title !== null) result.title = title[1].trim();
        if (author !== null) result.author = author[1].trim();
      } finally { await fileIo.close(source); }
      return result;
    }
    if (file.ext !== '.epub') return result;
    result.directory = `${context.cacheDir}/book_preview_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
    await fileIo.mkdir(result.directory, true);
    try {
      const size = await LocalBookImportService.fileSize(file.uri);
      if (size <= 0 || size > 512 * 1024 * 1024) throw new Error('Invalid EPUB size');
      await LocalBookImportService.requireSpace(context, size * 3);
      const archive = `${result.directory}/source.zip`;
      const epub = `${result.directory}/source.epub`;
      await LocalBookImportService.copyFile(file.uri, archive);
      const expanded = await zlib.getOriginalSize(archive);
      if (expanded > 2 * 1024 * 1024 * 1024) throw new Error('Invalid EPUB expanded size');
      await LocalBookImportService.requireSpace(context, expanded * 2);
      await fileIo.moveFile(archive, epub);
      const handler = await LocalBookImportService.openEpub(context, epub);
      const info = handler.getBookInfo();
      result.title = info.bookTitle || file.name;
      result.author = info.bookCreator || await LocalBookImportService.epubCreator(handler);
      result.cover = await EpubCoverService.extract(handler, result.directory);
      return result;
    } catch (error) {
      await fileIo.rmdir(result.directory).catch((): void => {});
      throw new Error(error instanceof Error ? error.message : 'EPUB preview failed');
    }
  }

  private static async epubMetadataText(handler: bookParser.BookParserHandler, path: string): Promise<string> {
    if (handler.getSpineList().length === 0) return '';
    await handler.getSpineItemContent(0);
    const parts = path.split('/');
    const candidates: string[] = [path];
    for (let index = 1; index < parts.length; index++) candidates.push(parts.slice(index).join('/'));
    for (let depth = 1; depth <= 8; depth++) candidates.push('../'.repeat(depth) + path);
    for (const candidate of candidates) {
      try {
        const bytes = handler.getResourceContent(0, candidate);
        if (bytes !== undefined && bytes.byteLength > 0 && bytes.byteLength <= 2 * 1024 * 1024) {
          return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(bytes));
        }
      } catch (_e) { /* 尝试相对包根目录读取。 */ }
    }
    return '';
  }

  private static async epubCreator(handler: bookParser.BookParserHandler): Promise<string> {
    try {
      const container = await LocalBookImportService.epubMetadataText(handler, 'META-INF/container.xml');
      const root = /full-path\s*=\s*["']([^"']+)["']/i.exec(container);
      if (root === null) return '';
      const metadata = await LocalBookImportService.epubMetadataText(handler, root[1]);
      const creator = /<(?:[\w-]+:)?creator\b[^>]*>([\s\S]*?)<\/(?:[\w-]+:)?creator\s*>/i.exec(metadata);
      return creator === null ? '' : KkBiqugeHtmlParser.cleanContent(creator[1]).trim();
    } catch (_e) { return ''; }
  }

  /** 纯文本导入优先读资源；无法读取/解码时才调用排版接口，同一 handler 保持串行。 */
  private static async epubSpineText(handler: bookParser.BookParserHandler, index: number,
    href: string, stats: EpubReadStats = new EpubReadStats()): Promise<string> {
    const name = href.substring(href.lastIndexOf('/') + 1).split('#')[0];
    const candidates: string[] = [name, href];
    for (const path of [name, href]) {
      try {
        const decoded = decodeURIComponent(path);
        if (decoded !== path && !candidates.includes(decoded)) candidates.push(decoded);
      } catch (_decode) { /* 保留原始合法候选。 */ }
    }
    for (const candidate of candidates) {
      try {
        const bytes = handler.getResourceContent(index, candidate);
        if (bytes.byteLength === 0 || bytes.byteLength > 32 * 1024 * 1024) continue;
        const text = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(bytes));
        if (!/<(?:html|body)\b/i.test(text)) continue;
        stats.raw++;
        return text;
      } catch (_resource) { /* 仅尝试同一 spine 资源，不跳过失败章节。 */ }
    }
    stats.layout++;
    return handler.getSpineItemContent(index);
  }

  static async requireSpace(context: common.Context, bytes: number): Promise<void> {
    const free = await statfs.getFreeSize(context.filesDir);
    if (!Number.isSafeInteger(bytes) || bytes < 0 || free < bytes + 256 * 1024 * 1024) {
      throw new Error('空间不足，请清理存储后重试（另需保留 256 MiB）');
    }
  }

  static async copyFile(uri: string, destination: string): Promise<void> {
    const source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    let target: fileIo.File | null = null;
    try {
      target = await fileIo.open(destination, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.copyFile(source.fd, target.fd);
    } finally {
      if (target !== null) await fileIo.close(target);
      await fileIo.close(source);
    }
  }

  static async fileSize(uri: string): Promise<number> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try { return (await fileIo.stat(file.fd)).size; }
    finally { await fileIo.close(file); }
  }

  static async writeText(path: string, text: string): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try { await fileIo.write(file.fd, text); }
    finally { await fileIo.close(file); }
  }

  /** ZIP 中的音频直接移动；普通文件每批预留总空间，再执行最多四路复制。 */
  static async importAudioChapters(context: common.Context, bookId: string, directory: string,
    files: LocalImportFile[], extractRoot: string, probe: (path: string) => Promise<number>,
    progress: (completed: number, total: number) => void): Promise<Chapter[]> {
    const started = Date.now();
    const queue = new LocalImportTaskQueue();
    const chapters: Chapter[] = [];
    let completed = 0;
    let lastProgressAt = 0;
    try {
      for (let offset = 0; offset < files.length; offset += 4) {
        const batch = files.slice(offset, offset + 4);
        const sizes = await Promise.all(batch.map((file: LocalImportFile): Promise<number> =>
          file.uri.startsWith(extractRoot + '/') ? Promise.resolve(0) : LocalBookImportService.fileSize(file.uri)));
        const needed = sizes.reduce((sum: number, size: number): number => sum + size, 0);
        if (needed > 0) await LocalBookImportService.requireSpace(context, needed);
        for (let position = 0; position < batch.length; position++) {
          const index = offset + position;
          const file = batch[position];
          const destination = `${directory}/${index + 1}${file.ext}`;
          await queue.add(async (): Promise<void> => {
            if (file.uri.startsWith(extractRoot + '/')) await fileIo.moveFile(file.uri, destination);
            else await LocalBookImportService.copyFile(file.uri, destination);
            const duration = files.length <= 500 ? await probe(destination) : 0;
            const chapter: Chapter = {
              id: `${bookId}-c${index + 1}`, index: index + 1, title: file.name, duration: duration,
              source: { type: 'file', value: destination }
            };
            chapters[index] = chapter;
            completed++;
            const now = Date.now();
            if (now - lastProgressAt >= 150 || completed === files.length) {
              lastProgressAt = now;
              progress(completed, files.length);
            }
          });
        }
        await queue.finish();
      }
      DiagnosticLogService.info('import.timing', `format=audio; chapters=${chapters.length}; ` +
        `copyAndProbeMs=${queue.busyMs}; totalMs=${Date.now() - started}`);
      return chapters;
    } catch (error) {
      await queue.settle();
      throw new Error(DiagnosticLogService.describe(error));
    }
  }

  /** 有上限的单章节文件，正文读取不需要在线书源。 */
  static async appendText(book: Book, directory: string, title: string, text: string,
    writes?: LocalImportTaskQueue): Promise<void> {
    let offset = 0;
    while (offset < text.length) {
      let end = Math.min(text.length, offset + 32000);
      if (end < text.length) {
        const newline = text.lastIndexOf('\n', end);
        if (newline > offset + 16000) end = newline;
        const code = text.charCodeAt(end - 1);
        if (code >= 0xD800 && code <= 0xDBFF) end--;
        const imageStart = text.lastIndexOf('\uFFF9', end - 1);
        if (imageStart >= offset && text.indexOf('\uFFFB', imageStart) >= end) end = imageStart;
      }
      const content = text.substring(offset, end).trim();
      if (content.length > 0) {
        if (book.chapters.length >= LocalBookImportService.MAX_CHAPTERS) throw new Error('单书超过 50000 章');
        const index = book.chapters.length;
        const path = `${directory}/${index}.txt`;
        if (writes) {
          await writes.add((): Promise<void> => LocalBookImportService.writeText(path, content));
        } else {
          await LocalBookImportService.writeText(path, content);
        }
        const chapter: Chapter = {
          id: `${book.id}-c${index}`, index: index + 1,
          title: offset === 0 ? title : `${title}（续）`, duration: 0,
          source: { type: 'file', value: path }
        };
        book.chapters.push(chapter);
      }
      offset = end;
    }
  }

  static htmlText(html: string): string {
    const body = /<body\b[^>]*>([\s\S]*?)<\/body\s*>/i.exec(html);
    return KkBiqugeHtmlParser.cleanContent(body ? body[1] : html);
  }

  static detectEncoding(sample: Uint8Array): string {
    if (sample[0] === 0xFF && sample[1] === 0xFE) return 'utf-16le';
    if (sample[0] === 0xFE && sample[1] === 0xFF) return 'utf-16be';
    if (sample[0] === 0xEF && sample[1] === 0xBB && sample[2] === 0xBF) return 'utf-8';
    try {
      util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(sample, { stream: true });
      return 'utf-8';
    } catch (_error) { return 'gb18030'; }
  }

  /** 64 KiB 流式读取 TXT；章节标题分段，无标题的长文按 32000 字符分段。 */
  private static async importText(book: Book, directory: string, uri: string,
    html: boolean, progress: (text: string) => void, writes: LocalImportTaskQueue): Promise<void> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size = (await fileIo.stat(file.fd)).size;
      const max = (html ? 32 : 256) * 1024 * 1024;
      if (size <= 0 || size > max) throw new Error(html ? 'HTML 需为 1 字节至 32 MiB' : 'TXT 需为 1 字节至 256 MiB');
      const buffer = new ArrayBuffer(65536);
      const firstLength = await fileIo.read(file.fd, buffer, { offset: 0, length: Math.min(buffer.byteLength, size) });
      const decoder = util.TextDecoder.create(LocalBookImportService.detectEncoding(new Uint8Array(buffer, 0, firstLength)));
      let offset = 0;
      let pending = '';
      let section = '';
      let title = book.title;
      let htmlContent = '';
      while (offset < size) {
        const count = await fileIo.read(file.fd, buffer, { offset: offset, length: Math.min(buffer.byteLength, size - offset) });
        if (count <= 0) throw new Error('文件读取中断');
        offset += count;
        const decoded = decoder.decodeToString(new Uint8Array(buffer, 0, count), { stream: offset < size });
        if (html) { htmlContent += decoded; continue; }
        pending += decoded.replace(/\r/g, '');
        const lines = pending.split('\n');
        pending = lines.pop() ?? '';
        for (const line of lines) {
          const trimmed = line.trim();
          if (/^(?:第[零〇一二三四五六七八九十百千万两\d]+[章节卷回部篇].{0,70}|chapter\s+\d+.{0,70}|序章|序言|楔子|尾声|后记)$/i.test(trimmed)) {
            await LocalBookImportService.appendText(book, directory, title, section, writes);
            title = trimmed;
            section = '';
          }
          section += line + '\n';
          if (section.length >= 32000) {
            await LocalBookImportService.appendText(book, directory, title, section, writes);
            section = '';
          }
        }
        if (pending.length >= 32000) {
          section += pending;
          pending = '';
          await LocalBookImportService.appendText(book, directory, title, section, writes);
          section = '';
        }
        progress(`${book.title} ${Math.floor(offset * 100 / size)}%`);
      }
      await LocalBookImportService.appendText(book, directory, title,
        html ? LocalBookImportService.htmlText(htmlContent) : section + pending, writes);
    } finally { await fileIo.close(file); }
  }

  private static async readMobi(context: common.Context, uri: string,
    consume?: (text: string, info: MobiBookInfo, percent: number) => Promise<void>,
    coverDirectory: string = ''): Promise<MobiBookInfo> {
    try { return await MobiBookParser.read(uri, consume, coverDirectory); }
    catch (error) {
      if (error instanceof Error && error.message.startsWith('import_mobi_')) {
        throw new Error(context.resourceManager.getStringByNameSync(error.message));
      }
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  private static async importMobi(context: common.Context, book: Book, directory: string,
    file: LocalImportFile, title: string, author: string, progress: (text: string) => void,
    writes: LocalImportTaskQueue): Promise<void> {
    const chunks: string[] = [];
    const info = await LocalBookImportService.readMobi(context, file.uri,
      async (text: string, metadata: MobiBookInfo, percent: number): Promise<void> => {
        if (!title && metadata.title) book.title = metadata.title;
        chunks.push(text);
        progress(`${book.title} ${percent}%`);
      }, book.cover.length === 0 ? directory : '');
    if (!book.cover) book.cover = info.cover;
    if (!author && info.author) book.author = info.author;
    let html = chunks.join('');
    chunks.length = 0;
    const body = /<body\b[^>]*>([\s\S]*?)<\/body\s*>/i.exec(html);
    html = (body === null ? html : body[1]).replace(/<(script|style|head)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '');
    const boundary = /<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1\s*>|<mbp:pagebreak\b[^>]*\/?\s*>/gi;
    let match: RegExpExecArray | null = boundary.exec(html);
    let start = 0;
    let label = book.title;
    while (match !== null) {
      await LocalBookImportService.appendText(book, directory, label,
        LocalBookImportService.htmlText(html.substring(start, match.index)), writes);
      if (match[2] !== undefined) {
        label = LocalBookImportService.htmlText(match[2]).trim().substring(0, 200) || book.title;
        start = match.index; // Keep the visible heading in the chapter body.
      } else {
        label = `${book.title} ${book.chapters.length + 1}`;
        start = boundary.lastIndex;
      }
      match = boundary.exec(html);
    }
    await LocalBookImportService.appendText(book, directory, label,
      LocalBookImportService.htmlText(html.substring(start)), writes);
  }

  static async importBook(context: common.Context, file: LocalImportFile, id: string,
    title: string, author: string, cover: string, progress: (text: string) => void): Promise<Book> {
    const started = Date.now();
    const writes = new LocalImportTaskQueue();
    const epubStats = new EpubReadStats();
    let lastProgressAt = 0;
    let latestProgress = '';
    let shownProgress = '';
    const report = (text: string): void => {
      latestProgress = text;
      const now = Date.now();
      if (now - lastProgressAt >= 150 && shownProgress !== text) {
        lastProgressAt = now;
        shownProgress = text;
        progress(text);
      }
    };
    const directory = `${context.filesDir}/ebooks/${id}`;
    const book: Book = {
      id: id, contentType: 'text', title: title || file.name, author: author || '未知',
      narrator: '', cover: cover, category: 'import', intro: '本地电子书', totalDuration: 0,
      chapterCount: 0, rating: 0, tags: ['本地导入'], chapters: [],
      bookUrl: `local-text://${id}`, sourceUrl: ''
    };
    await fileIo.mkdir(directory, true);
    let stage = 'prepare';
    let parseStarted = started;
    let prepareMs = 0;
    try {
      if (cover.length > 0) {
        const localCover = `${directory}/cover${cover.toLowerCase().endsWith('.png') ? '.png' : '.jpg'}`;
        await LocalBookImportService.copyFile(cover, localCover);
        book.cover = localCover;
      }
      const size = await LocalBookImportService.fileSize(file.uri);
      stage = 'space';
      await LocalBookImportService.requireSpace(context, size * 3);
      DiagnosticLogService.info('import.file', `format=${file.ext}; bytes=${size}`);
      stage = 'parse';
      parseStarted = Date.now();
      prepareMs = parseStarted - started;
      if (file.ext === '.mobi') {
        await LocalBookImportService.importMobi(context, book, directory, file, title, author, report, writes);
      } else if (file.ext === '.epub') {
        if (size > 512 * 1024 * 1024) throw new Error('EPUB 超过 512 MiB');
        const archive = `${directory}/source.zip`;
        const epub = `${directory}/source.epub`;
        await LocalBookImportService.copyFile(file.uri, archive);
        const expanded = await zlib.getOriginalSize(archive);
        if (expanded > 2 * 1024 * 1024 * 1024) throw new Error('EPUB 解压内容超过 2 GiB');
        await LocalBookImportService.requireSpace(context, expanded * 2);
        await fileIo.moveFile(archive, epub);
        const handler = await LocalBookImportService.openEpub(context, epub);
        const info = handler.getBookInfo();
        if (book.cover.length === 0) book.cover = await EpubCoverService.extract(handler, directory);
        if (!title && info.bookTitle) book.title = info.bookTitle;
        if (!author) book.author = info.bookCreator || await LocalBookImportService.epubCreator(handler) || book.author;
        const spine = handler.getSpineList();
        const catalog = handler.getCatalogList();
        const titles = new Map<string, string>();
        for (const item of catalog) {
          if (item.idRef && !titles.has(item.idRef)) titles.set(item.idRef, item.catalogName);
        }
        if (spine.length > LocalBookImportService.MAX_CHAPTERS) throw new Error('EPUB 超过 50000 节');
        for (let index = 0; index < spine.length; index++) {
          report(`${book.title} ${index + 1}/${spine.length}`);
          const label = titles.get(spine[index].idRef);
          const html = await LocalBookImportService.epubSpineText(handler, index, spine[index].href, epubStats);
          await LocalBookImportService.appendText(book, directory, label || `${book.title} ${index + 1}`,
            await LocalBookImportService.epubBody(context, handler, index, html, directory, epubStats), writes);
        }
      } else {
        await LocalBookImportService.importText(book, directory, file.uri, file.ext !== '.txt', report, writes);
      }
      stage = 'write';
      await writes.finish();
      if (book.chapters.length === 0) throw new Error('没有可读取的文字章节');
      if (latestProgress && latestProgress !== shownProgress) progress(latestProgress);
      book.chapterCount = book.chapters.length;
      DiagnosticLogService.info('import.parsed', `format=${file.ext}; chapters=${book.chapterCount}`);
      // I/O 与解析重叠，writeBusyMs 不能与 parseReadMs 相加；writeWaitMs 为实际阻塞解析的时间。
      DiagnosticLogService.info('import.timing', `format=${file.ext}; chapters=${book.chapterCount}; ` +
        `prepareMs=${prepareMs}; parseReadMs=${Date.now() - parseStarted - writes.waitMs}; ` +
        `writeWaitMs=${writes.waitMs}; writeBusyMs=${writes.busyMs}; totalMs=${Date.now() - started}; ` +
        `epubRaw=${epubStats.raw}; epubLayout=${epubStats.layout}`);
      return book;
    } catch (error) {
      await writes.settle();
      DiagnosticLogService.failure(`import.${stage}`, error, `format=${file.ext}`);
      try { await fileIo.rmdir(directory); } catch (_cleanup) { /* 保留原始错误 */ }
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }
}
