import { fileIo } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

class EpubZipEntry {
  path: string = '';
  offset: number = 0;
  compressed: number = 0;
  size: number = 0;
  method: number = 0;
  flags: number = 0;
  crc: number = 0;
}

/** 按中央目录随机读取 ZIP 条目；不把原书路径直接解压到文件系统。 */
export class EpubArchive {
  static readonly MAX_FILE: number = 3 * 1024 * 1024 * 1024;
  static readonly MAX_EXPANDED: number = 6 * 1024 * 1024 * 1024;
  static readonly MAX_RESOURCE: number = 64 * 1024 * 1024;
  expandedSize: number = 0;
  private file: fileIo.File | null = null;
  private size: number = 0;
  private entries: Map<string, EpubZipEntry> = new Map();

  static async open(path: string): Promise<EpubArchive> {
    const archive = new EpubArchive();
    archive.file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      archive.size = (await fileIo.stat(archive.file.fd)).size;
      if (archive.size > EpubArchive.MAX_FILE) throw new Error('EPUB_SIZE_LIMIT');
      await archive.index();
      return archive;
    } catch (error) {
      await archive.close();
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  async close(): Promise<void> {
    const file = this.file;
    this.file = null;
    if (file !== null) await fileIo.close(file);
  }

  has(path: string): boolean { return this.entries.has(path); }
  resourceSize(path: string): number { return this.entries.get(path)?.size ?? 0; }

  private async bytes(offset: number, length: number): Promise<ArrayBuffer> {
    if (this.file === null || !Number.isSafeInteger(offset) || !Number.isSafeInteger(length) ||
      offset < 0 || length < 0 || length > EpubArchive.MAX_RESOURCE || offset + length > this.size) {
      throw new Error('EPUB 压缩包数据越界或文件已关闭');
    }
    const result = new ArrayBuffer(length);
    let at = 0;
    while (at < length) {
      const chunk = at === 0 ? result : new ArrayBuffer(length - at);
      const count = await fileIo.read(this.file.fd, chunk, { offset: offset + at, length: chunk.byteLength });
      if (count <= 0) throw new Error('EPUB 压缩包数据不完整');
      if (at > 0) new Uint8Array(result).set(new Uint8Array(chunk, 0, count), at);
      at += count;
    }
    return result;
  }

  private static uint64(view: DataView, at: number): number {
    if (at + 8 > view.byteLength) throw new Error('EPUB ZIP64 数据不完整');
    const value = view.getUint32(at, true) + view.getUint32(at + 4, true) * 4294967296;
    if (!Number.isSafeInteger(value)) throw new Error('EPUB ZIP64 数值超出范围');
    return value;
  }

  private async index(): Promise<void> {
    if (this.size < 22) throw new Error('不是有效的 EPUB 压缩包');
    const tailStart = Math.max(0, this.size - 65557);
    const tail = new DataView(await this.bytes(tailStart, this.size - tailStart));
    let end = -1;
    for (let at = tail.byteLength - 22; at >= 0; at--) {
      if (tail.getUint32(at, true) === 0x06054b50 && at + 22 + tail.getUint16(at + 20, true) === tail.byteLength) {
        end = at; break;
      }
    }
    if (end < 0) throw new Error('EPUB 中央目录缺失');
    if (tail.getUint16(end + 4, true) !== 0 || tail.getUint16(end + 6, true) !== 0) throw new Error('不支持分卷 EPUB');
    let count = tail.getUint16(end + 10, true);
    let length = tail.getUint32(end + 12, true);
    let offset = tail.getUint32(end + 16, true);
    if (count === 0xffff || length === 0xffffffff || offset === 0xffffffff) {
      const locator = new DataView(await this.bytes(tailStart + end - 20, 20));
      if (locator.getUint32(0, true) !== 0x07064b50 || locator.getUint32(4, true) !== 0 ||
        locator.getUint32(16, true) !== 1) throw new Error('EPUB ZIP64 目录无效');
      const zip64 = new DataView(await this.bytes(EpubArchive.uint64(locator, 8), 56));
      if (zip64.getUint32(0, true) !== 0x06064b50 || zip64.getUint32(16, true) !== 0 ||
        zip64.getUint32(20, true) !== 0) throw new Error('EPUB ZIP64 目录无效');
      count = EpubArchive.uint64(zip64, 32); length = EpubArchive.uint64(zip64, 40); offset = EpubArchive.uint64(zip64, 48);
    }
    if (count > 50000 || length > 16 * 1024 * 1024 || offset + length > tailStart + end) {
      throw new Error('EPUB 资源目录过大或损坏');
    }
    const directory = await this.bytes(offset, length);
    const view = new DataView(directory);
    let at = 0;
    for (let index = 0; index < count; index++) {
      if (at + 46 > length || view.getUint32(at, true) !== 0x02014b50) throw new Error('EPUB 资源目录损坏');
      const entry = new EpubZipEntry();
      entry.flags = view.getUint16(at + 8, true); entry.method = view.getUint16(at + 10, true);
      entry.crc = view.getUint32(at + 16, true); entry.compressed = view.getUint32(at + 20, true);
      entry.size = view.getUint32(at + 24, true); entry.offset = view.getUint32(at + 42, true);
      const nameLength = view.getUint16(at + 28, true), extraLength = view.getUint16(at + 30, true);
      const next = at + 46 + nameLength + extraLength + view.getUint16(at + 32, true);
      if (next > length || (entry.flags & 1) !== 0 || view.getUint16(at + 34, true) !== 0) {
        throw new Error('EPUB 资源损坏、加密或使用分卷');
      }
      const name = new Uint8Array(directory, at + 46, nameLength);
      try { entry.path = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(name); }
      catch (_encoding) { entry.path = util.TextDecoder.create('gb18030').decodeToString(name); }
      if (!entry.path || entry.path.startsWith('/') || /[\u0000-\u001f\\]/.test(entry.path) ||
        entry.path.split('/').some((part: string): boolean => part === '..' || part === '.')) throw new Error('EPUB 资源路径无效');
      let extra = at + 46 + nameLength;
      while (extra + 4 <= at + 46 + nameLength + extraLength) {
        const tag = view.getUint16(extra, true), size = view.getUint16(extra + 2, true);
        const limit = extra + 4 + size;
        if (limit > at + 46 + nameLength + extraLength) throw new Error('EPUB ZIP 扩展字段损坏');
        if (tag === 1) {
          const zip64 = new DataView(directory, extra + 4, size);
          let field = 0;
          if (entry.size === 0xffffffff) { entry.size = EpubArchive.uint64(zip64, field); field += 8; }
          if (entry.compressed === 0xffffffff) { entry.compressed = EpubArchive.uint64(zip64, field); field += 8; }
          if (entry.offset === 0xffffffff) entry.offset = EpubArchive.uint64(zip64, field);
        }
        extra = limit;
      }
      this.expandedSize += entry.size;
      if (this.expandedSize > EpubArchive.MAX_EXPANDED) throw new Error('EPUB_EXPANDED_LIMIT');
      if (!entry.path.endsWith('/')) {
        const previous = this.entries.get(entry.path);
        if (previous !== undefined && (previous.size !== entry.size || previous.crc !== entry.crc)) {
          throw new Error('EPUB 包含内容冲突的重复资源');
        }
        this.entries.set(entry.path, entry);
      }
      at = next;
    }
  }

  async read(path: string, maximum: number = EpubArchive.MAX_RESOURCE): Promise<ArrayBuffer> {
    const entry = this.entries.get(path);
    if (entry === undefined) throw new Error('EPUB 资源不存在');
    if (entry.size > maximum || entry.compressed > EpubArchive.MAX_RESOURCE) throw new Error('EPUB 单个资源过大');
    const local = new DataView(await this.bytes(entry.offset, 30));
    if (local.getUint32(0, true) !== 0x04034b50 || local.getUint16(8, true) !== entry.method ||
      (local.getUint16(6, true) & 1) !== 0) throw new Error('EPUB 资源头损坏');
    const input = await this.bytes(entry.offset + 30 + local.getUint16(26, true) + local.getUint16(28, true), entry.compressed);
    let output: ArrayBuffer;
    if (entry.method === 0) output = input;
    else if (entry.method === 8) {
      const inflater = await zlib.createZip();
      const stream: zlib.ZStream = {};
      await inflater.inflateInit2(stream, -15);
      try {
        stream.nextIn = input; stream.availableIn = input.byteLength;
        const buffer = new ArrayBuffer(Math.max(1, entry.size));
        stream.nextOut = buffer; stream.availableOut = buffer.byteLength;
        const status = await inflater.inflate(stream, zlib.CompressFlushMode.FINISH);
        const result = await inflater.getZStream();
        if (status !== zlib.ReturnStatus.STREAM_END || result.totalOut !== entry.size) {
          throw new Error('EPUB 资源解压不完整');
        }
        // getZStream 只返回计数/状态，输出字节在调用方传入的缓冲区中。
        output = entry.size === buffer.byteLength ? buffer : buffer.slice(0, entry.size);
      } finally { await inflater.inflateEnd(stream); }
    } else throw new Error('EPUB 使用不支持的压缩方式');
    if (output.byteLength !== entry.size || ((await (await zlib.createChecksum()).crc32(0, output)) >>> 0) !== entry.crc) {
      throw new Error('EPUB 资源完整性校验失败');
    }
    return output;
  }
}
