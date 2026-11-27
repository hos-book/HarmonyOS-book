import { util } from '@kit.ArkTS';
import { EpubArchive } from './EpubArchive';
import { EpubXml, EpubXmlNode } from './EpubXml';
import { EpubOriginalDocument } from './EpubOriginalDocument';

export class EpubBookInfo {
  bookTitle: string = '';
  bookCreator: string = '';
  bookCoverImage: string = '';
}

export class EpubSpineItem {
  idRef: string = '';
  href: string = '';
  mediaType: string = '';
  linear: boolean = true;
}

export class EpubCatalogItem {
  idRef: string = '';
  href: string = '';
  resourceFile: string = '';
  catalogName: string = '';
}

/** 自研 EPUB 2/3 包解析：ZIP 条目、OPF 阅读顺序、NCX/nav 锚点和原始资源。 */
export class EpubParserService {
  private archive: EpubArchive;
  private info: EpubBookInfo = new EpubBookInfo();
  private spines: EpubSpineItem[] = [];
  private catalog: EpubCatalogItem[] = [];
  private spineIds: Map<string, string> = new Map();
  private capturedStyles: Map<string, ArrayBuffer> = new Map();
  private capturedStyleBytes: number = 0;

  constructor(archive: EpubArchive) { this.archive = archive; }

  static async open(path: string): Promise<EpubParserService> {
    const parser = new EpubParserService(await EpubArchive.open(path));
    try { await parser.parse(); return parser; }
    catch (error) {
      await parser.close();
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  get expandedSize(): number { return this.archive.expandedSize; }
  getBookInfo(): EpubBookInfo { return this.info; }
  getSpineList(): EpubSpineItem[] { return this.spines; }
  getCatalogList(): EpubCatalogItem[] { return this.catalog; }
  async close(): Promise<void> { await this.archive.close(); }

  async readResource(path: string, maximum: number = EpubArchive.MAX_RESOURCE): Promise<ArrayBuffer> {
    return this.archive.read(path, maximum);
  }

  getResourcePath(index: number, relative: string): string {
    if (!this.spines[index]) throw new Error('EPUB 正文章节不存在');
    return EpubOriginalDocument.resolve(this.spines[index].href, relative);
  }

  async getResourceContent(index: number, relative: string): Promise<ArrayBuffer> {
    const path = this.getResourcePath(index, relative);
    const captured = this.capturedStyles.get(path);
    if (captured !== undefined) {
      this.capturedStyles.delete(path);
      this.capturedStyleBytes -= captured.byteLength;
      return captured;
    }
    return path ? this.archive.read(path) : new ArrayBuffer(0);
  }

  /** 每批最多 16 项、512 KiB；大资源独占一批，返回已消费的前缀。 */
  async getResourceBatch(index: number, relatives: string[]): Promise<Array<ArrayBuffer | undefined>> {
    const result: Array<ArrayBuffer | undefined> = [];
    const paths: string[] = [];
    const positions: number[] = [];
    let size = 0;
    for (const relative of relatives) {
      const path = this.getResourcePath(index, relative);
      const resourceSize = this.archive.resourceSize(path);
      if (result.length > 0 && (result.length >= 16 || size + resourceSize > 512 * 1024)) break;
      size += resourceSize;
      const position = result.length;
      result.push(undefined);
      if (path && this.archive.has(path)) { paths.push(path); positions.push(position); }
    }
    try {
      const resources = await this.archive.readBatch(paths);
      for (let at = 0; at < resources.length; at++) result[positions[at]] = resources[at];
    } catch (_batch) {
      // 保留可选资源逐项读取语义，成功项继续参与原版布局。
      for (let at = 0; at < paths.length; at++) {
        try { result[positions[at]] = await this.archive.read(paths[at]); } catch (_resource) {}
      }
    }
    for (let at = 0; at < paths.length; at++) {
      const bytes = result[positions[at]];
      if (bytes === undefined || !paths[at].toLowerCase().endsWith('.css') || bytes.byteLength > 512 * 1024 ||
        this.capturedStyles.has(paths[at]) || this.capturedStyles.size >= 128 ||
        this.capturedStyleBytes + bytes.byteLength > 8 * 1024 * 1024) continue;
      this.capturedStyles.set(paths[at], bytes);
      this.capturedStyleBytes += bytes.byteLength;
    }
    return result;
  }

  async getSpineItemContent(index: number): Promise<string> {
    const spine = this.spines[index];
    if (!spine) throw new Error('EPUB 正文章节不存在');
    if (spine.mediaType.startsWith('image/')) {
      const name = spine.href.substring(spine.href.lastIndexOf('/') + 1);
      return `<html><body><img src="./${encodeURIComponent(name)}"/></body></html>`;
    }
    return this.text(spine.href, 32 * 1024 * 1024);
  }

  /** 四章/512 KiB 以内批量读取；超大单章独占一批，结果按原阅读顺序返回。 */
  async getSpineBatch(start: number): Promise<string[]> {
    if (!this.spines[start]) throw new Error('EPUB 正文章节不存在');
    const items: EpubSpineItem[] = [];
    const paths: string[] = [];
    let bytes = 0;
    for (let index = start; index < this.spines.length && items.length < 4; index++) {
      const spine = this.spines[index];
      const size = spine.mediaType.startsWith('image/') ? 1024 : this.archive.resourceSize(spine.href);
      if (items.length > 0 && bytes + size > 512 * 1024) break;
      bytes += size;
      items.push(spine);
      if (!spine.mediaType.startsWith('image/')) paths.push(spine.href);
    }
    // 后台任务独立持有 ZIP fd，按批次返回正文资源。
    const resources = await this.archive.readBatch(paths, 32 * 1024 * 1024);
    const content: string[] = [];
    let resourceIndex = 0;
    for (const item of items) {
      if (item.mediaType.startsWith('image/')) {
        const name = item.href.substring(item.href.lastIndexOf('/') + 1);
        content.push(`<html><body><img src="./${encodeURIComponent(name)}"/></body></html>`);
      } else content.push(EpubParserService.decodeText(resources[resourceIndex++]));
    }
    return content;
  }

  private async text(path: string, maximum: number = 8 * 1024 * 1024): Promise<string> {
    return EpubParserService.decodeText(await this.archive.read(path, maximum));
  }

  private static decodeText(content: ArrayBuffer): string {
    const bytes = new Uint8Array(content);
    let encoding = 'utf-8';
    if (bytes[0] === 0xff && bytes[1] === 0xfe) encoding = 'utf-16le';
    else if (bytes[0] === 0xfe && bytes[1] === 0xff) encoding = 'utf-16be';
    else {
      const prefix = util.TextDecoder.create('utf-8').decodeToString(bytes.slice(0, 256));
      const declared = /<\?xml\b[^>]*encoding\s*=\s*["']([^"']+)/i.exec(prefix)?.[1].toLowerCase() ?? '';
      if (['gbk', 'gb2312', 'gb18030', 'big5', 'utf-8'].includes(declared)) encoding = declared;
    }
    return util.TextDecoder.create(encoding).decodeToString(bytes).replace(/^\uFEFF/, '');
  }

  private addCatalog(base: string, href: string, title: string): void {
    const path = EpubOriginalDocument.resolve(base, href);
    if (!path || !this.archive.has(path) || !title.trim()) return;
    const item = new EpubCatalogItem();
    const hash = href.indexOf('#');
    item.resourceFile = path; item.href = path + (hash >= 0 ? href.substring(hash) : '');
    item.idRef = this.spineIds.get(path) ?? '';
    item.catalogName = title.replace(/\s+/g, ' ').trim().substring(0, 200);
    this.catalog.push(item);
  }

  private async parse(): Promise<void> {
    const container = await EpubXml.parse(await this.text('META-INF/container.xml'));
    const root = container.all('rootfile')[0];
    const opfPath = EpubOriginalDocument.resolve('', root?.attr('full-path') ?? '');
    if (!opfPath) throw new Error('EPUB 缺少有效的 OPF 路径');
    const opf = await EpubXml.parse(await this.text(opfPath));
    const metadata = opf.all('metadata')[0];
    this.info.bookTitle = metadata?.all('title')[0]?.text.trim() ?? '';
    this.info.bookCreator = metadata?.all('creator').map((node: EpubXmlNode): string => node.text.trim()).filter(
      (value: string): boolean => value.length > 0).join('、') ?? '';
    const manifest = new Map<string, EpubXmlNode>();
    const items = opf.all('manifest')[0]?.all('item') ?? [];
    for (const item of items) manifest.set(item.attr('id'), item);
    const spine = opf.all('spine')[0];
    for (const ref of spine?.all('itemref') ?? []) {
      const item = manifest.get(ref.attr('idref'));
      if (item === undefined) throw new Error('EPUB 阅读顺序引用了不存在的资源');
      const part = new EpubSpineItem();
      part.idRef = ref.attr('idref'); part.href = EpubOriginalDocument.resolve(opfPath, item.attr('href'));
      part.mediaType = item.attr('media-type'); part.linear = ref.attr('linear').toLowerCase() !== 'no';
      if (!part.href || !this.archive.has(part.href)) throw new Error('EPUB 缺少正文文件');
      this.spines.push(part);
      if (!this.spineIds.has(part.href)) this.spineIds.set(part.href, part.idRef);
    }
    if (!this.spines.length) throw new Error('EPUB 没有正文阅读顺序');
    const nav = items.find((item: EpubXmlNode): boolean => item.attr('properties').split(/\s+/).includes('nav'));
    if (nav !== undefined) {
      const path = EpubOriginalDocument.resolve(opfPath, nav.attr('href'));
      if (this.archive.has(path)) {
        const doc = await EpubXml.parse(await this.text(path));
        const toc = doc.all('nav').find((node: EpubXmlNode): boolean =>
          (node.attr('epub:type') || node.attr('type')).split(/\s+/).includes('toc') || node.attr('role') === 'doc-toc');
        for (const link of toc?.all('a') ?? []) this.addCatalog(path, link.attr('href'), link.text);
      }
    }
    if (!this.catalog.length) {
      const ncx = manifest.get(spine?.attr('toc') ?? '') ?? items.find(
        (item: EpubXmlNode): boolean => item.attr('media-type') === 'application/x-dtbncx+xml');
      const path = EpubOriginalDocument.resolve(opfPath, ncx?.attr('href') ?? '');
      if (this.archive.has(path)) {
        const doc = await EpubXml.parse(await this.text(path));
        for (const point of doc.all('navmap')[0]?.all('navpoint') ?? []) {
          this.addCatalog(path, point.child('content')?.attr('src') ?? '', point.child('navlabel')?.text ?? '');
        }
      }
    }
    const tocPaths = new Set(this.catalog.map((item: EpubCatalogItem): string => item.resourceFile));
    this.spines = this.spines.filter((item: EpubSpineItem): boolean => item.linear || tocPaths.has(item.href));
    const coverId = metadata?.all('meta').find((node: EpubXmlNode): boolean => node.attr('name').toLowerCase() === 'cover')?.attr('content') ?? '';
    const cover = items.find((item: EpubXmlNode): boolean => item.attr('properties').split(/\s+/).includes('cover-image')) ?? manifest.get(coverId);
    this.info.bookCoverImage = EpubOriginalDocument.resolve(opfPath, cover?.attr('href') ?? '');
    if (!this.info.bookCoverImage) {
      const page = opf.all('reference').find((node: EpubXmlNode): boolean => node.attr('type') === 'cover');
      const path = page ? EpubOriginalDocument.resolve(opfPath, page.attr('href')) : this.spines[0]?.href ?? '';
      if (this.archive.has(path)) {
        const html = await this.text(path);
        const image = /<(?:img|image)\b[^>]*\s(?:src|(?:xlink:)?href)\s*=\s*["']([^"']+)/i.exec(html);
        if (image !== null) this.info.bookCoverImage = EpubOriginalDocument.resolve(path, image[1]);
      }
    }
  }
}
