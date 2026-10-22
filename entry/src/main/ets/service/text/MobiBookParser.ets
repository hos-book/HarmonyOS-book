import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BookCoverImageService } from './BookCoverImageService';

export class MobiBookInfo {
  title: string = '';
  author: string = '';
  textLength: number = 0;
  cover: string = '';
  coverOffset: number = -1;
  thumbnailOffset: number = -1;
  encoding: string = 'utf-8';
}

/** MOBI6/PalmDOC: bounded record reads; hybrid MOBI uses its legacy rendition. */
export class MobiBookParser {
  static readonly MAX_FILE_BYTES: number = 128 * 1024 * 1024;
  static readonly MAX_TEXT_BYTES: number = 32 * 1024 * 1024;

  private static invalid(): Error { return new Error('import_mobi_invalid'); }

  private static u16(bytes: Uint8Array, offset: number): number {
    if (offset < 0 || offset + 2 > bytes.length) throw MobiBookParser.invalid();
    return bytes[offset] * 256 + bytes[offset + 1];
  }

  private static u32(bytes: Uint8Array, offset: number): number {
    return MobiBookParser.u16(bytes, offset) * 65536 + MobiBookParser.u16(bytes, offset + 2);
  }

  private static signature(bytes: Uint8Array, offset: number, value: string): boolean {
    for (let index = 0; index < value.length; index++) {
      if (bytes[offset + index] !== value.charCodeAt(index)) return false;
    }
    return true;
  }

  private static async readBytes(fd: number, offset: number, length: number,
    limit: number = 1024 * 1024): Promise<Uint8Array> {
    if (length <= 0 || length > limit) throw MobiBookParser.invalid();
    const bytes = new Uint8Array(length);
    let read = 0;
    while (read < length) {
      const buffer = new ArrayBuffer(length - read);
      const count = await fileIo.read(fd, buffer, { offset: offset + read, length: length - read });
      if (count <= 0) throw MobiBookParser.invalid();
      bytes.set(new Uint8Array(buffer, 0, count), read);
      read += count;
    }
    return bytes;
  }

  private static decode(bytes: Uint8Array, encoding: string): string {
    return util.TextDecoder.create(encoding).decodeToString(bytes).replace(/\u0000/g, '').trim();
  }

  private static metadata(header: Uint8Array, headerLength: number, encoding: string): MobiBookInfo {
    const info = new MobiBookInfo();
    info.encoding = encoding;
    info.textLength = MobiBookParser.u32(header, 4);
    const titleOffset = MobiBookParser.u32(header, 84);
    const titleLength = MobiBookParser.u32(header, 88);
    if (titleLength > 0) {
      if (titleOffset < 16 + headerLength || titleOffset + titleLength > header.length) {
        throw MobiBookParser.invalid();
      }
      info.title = MobiBookParser.decode(header.subarray(titleOffset, titleOffset + titleLength), encoding);
    }
    if (headerLength < 116 || (MobiBookParser.u32(header, 128) & 0x40) === 0) return info;
    const start = 16 + headerLength;
    if (!MobiBookParser.signature(header, start, 'EXTH')) throw MobiBookParser.invalid();
    const end = start + MobiBookParser.u32(header, start + 4);
    const count = MobiBookParser.u32(header, start + 8);
    if (end > header.length || end < start + 12 || count > (end - start - 12) / 8) {
      throw MobiBookParser.invalid();
    }
    let offset = start + 12;
    for (let index = 0; index < count; index++) {
      if (offset + 8 > end) throw MobiBookParser.invalid();
      const type = MobiBookParser.u32(header, offset);
      const length = MobiBookParser.u32(header, offset + 4);
      if (length < 8 || offset + length > end) throw MobiBookParser.invalid();
      if (type === 100 || type === 503) {
        const value = MobiBookParser.decode(header.subarray(offset + 8, offset + length), encoding);
        if (type === 100 && !info.author) info.author = value;
        if (type === 503 && value) info.title = value;
      } else if ((type === 201 || type === 202) && length === 12) {
        const imageOffset = MobiBookParser.u32(header, offset + 8);
        if (imageOffset !== 0xFFFFFFFF) {
          if (type === 201) info.coverOffset = imageOffset;
          else info.thumbnailOffset = imageOffset;
        }
      }
      offset += length;
    }
    info.title = info.title.substring(0, 512);
    info.author = info.author.substring(0, 512);
    return info;
  }

  private static async extractCover(fd: number, firstImage: number, offsets: number[], textRecords: number,
    info: MobiBookInfo, directory: string): Promise<string> {
    if (directory.length === 0 || firstImage <= textRecords || firstImage >= offsets.length - 1) return '';
    const candidates: number[] = [];
    if (info.coverOffset >= 0) candidates.push(firstImage + info.coverOffset);
    if (info.thumbnailOffset >= 0) candidates.push(firstImage + info.thumbnailOffset);
    // Older MOBI books may omit EXTH cover metadata and use the first image as their cover.
    if (candidates.length === 0) candidates.push(firstImage);
    for (const record of candidates) {
      if (record < firstImage || record >= offsets.length - 1) continue;
      const length = offsets[record + 1] - offsets[record];
      if (length <= 0 || length > 16 * 1024 * 1024) continue;
      try {
        const bytes = await MobiBookParser.readBytes(fd, offsets[record], length, 16 * 1024 * 1024);
        const cover = await BookCoverImageService.decode(bytes.buffer, directory);
        if (cover.length > 0) return cover;
      } catch (_error) {
        // A broken optional image must not prevent the book text from being imported.
        await fileIo.unlink(`${directory}/cover.jpg`).catch((): void => {});
      }
    }
    return '';
  }

  /** Extra-data lengths are reverse variable integers, including their own length bytes. */
  private static textRecord(bytes: Uint8Array, flags: number): Uint8Array {
    let end = bytes.length;
    for (let bit = 1; bit < 16; bit++) {
      if ((flags & (1 << bit)) === 0) continue;
      let size = 0;
      let shift = 0;
      let cursor = end;
      let terminated = false;
      while (cursor > 0 && shift < 28) {
        const value = bytes[--cursor];
        size += (value & 0x7F) * Math.pow(2, shift);
        shift += 7;
        if ((value & 0x80) !== 0) { terminated = true; break; }
      }
      if (!terminated || size < end - cursor || size > end) throw MobiBookParser.invalid();
      end -= size;
    }
    if ((flags & 1) !== 0) {
      if (end === 0) throw MobiBookParser.invalid();
      end -= (bytes[end - 1] & 3) + 1;
      if (end < 0) throw MobiBookParser.invalid();
    }
    return bytes.subarray(0, end);
  }

  private static unpack(bytes: Uint8Array, capacity: number): Uint8Array {
    const output = new Uint8Array(capacity);
    let written = 0;
    let cursor = 0;
    while (cursor < bytes.length) {
      const value = bytes[cursor++];
      if (value >= 1 && value <= 8) {
        if (cursor + value > bytes.length || written + value > capacity) throw MobiBookParser.invalid();
        output.set(bytes.subarray(cursor, cursor + value), written);
        cursor += value;
        written += value;
      } else if (value >= 0x80 && value <= 0xBF) {
        if (cursor === bytes.length) throw MobiBookParser.invalid();
        const pair = (value << 8) | bytes[cursor++];
        const distance = (pair & 0x3FFF) >> 3;
        const count = (pair & 7) + 3;
        if (distance === 0 || distance > written || written + count > capacity) throw MobiBookParser.invalid();
        for (let index = 0; index < count; index++) {
          output[written] = output[written - distance];
          written++;
        }
      } else {
        const count = value >= 0xC0 ? 2 : 1;
        if (written + count > capacity) throw MobiBookParser.invalid();
        if (count === 2) output[written++] = 0x20;
        output[written++] = count === 2 ? value ^ 0x80 : value;
      }
    }
    return output.subarray(0, written);
  }

  static async read(uri: string,
    consume?: (text: string, info: MobiBookInfo, percent: number) => Promise<void>,
    coverDirectory: string = ''): Promise<MobiBookInfo> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size = (await fileIo.stat(file.fd)).size;
      if (size > MobiBookParser.MAX_FILE_BYTES) throw new Error('import_mobi_size');
      if (size < 94) throw MobiBookParser.invalid();
      const pdb = await MobiBookParser.readBytes(file.fd, 0, 78);
      if (!MobiBookParser.signature(pdb, 60, 'BOOKMOBI') || MobiBookParser.u32(pdb, 72) !== 0) {
        throw MobiBookParser.invalid();
      }
      const count = MobiBookParser.u16(pdb, 76);
      if (count < 2 || 78 + count * 8 > size) throw MobiBookParser.invalid();
      const table = await MobiBookParser.readBytes(file.fd, 78, count * 8);
      const offsets: number[] = [];
      for (let index = 0; index < count; index++) {
        const offset = MobiBookParser.u32(table, index * 8);
        if (offset < 78 + count * 8 || offset >= size || (index > 0 && offset <= offsets[index - 1])) {
          throw MobiBookParser.invalid();
        }
        offsets.push(offset);
      }
      offsets.push(size);
      const header = await MobiBookParser.readBytes(file.fd, offsets[0], offsets[1] - offsets[0]);
      if (MobiBookParser.u16(header, 12) !== 0) throw new Error('import_mobi_encrypted');
      if (!MobiBookParser.signature(header, 16, 'MOBI')) throw MobiBookParser.invalid();
      const headerLength = MobiBookParser.u32(header, 20);
      if (headerLength < 76 || headerLength + 16 > header.length) throw MobiBookParser.invalid();
      const version = MobiBookParser.u32(header, 36);
      if (version > 7) throw new Error('import_mobi_kf8');
      const compression = MobiBookParser.u16(header, 0);
      if (compression !== 1 && compression !== 2) throw new Error('import_mobi_compression');
      const codepage = MobiBookParser.u32(header, 28);
      if (codepage !== 65001 && codepage !== 1252) throw new Error('import_mobi_encoding');
      const encoding = codepage === 65001 ? 'utf-8' : 'windows-1252';
      const info = MobiBookParser.metadata(header, headerLength, encoding);
      const records = MobiBookParser.u16(header, 8);
      const recordSize = MobiBookParser.u16(header, 10);
      if (info.textLength > MobiBookParser.MAX_TEXT_BYTES) throw new Error('import_mobi_size');
      if (records === 0 || records >= count || recordSize === 0 || info.textLength === 0 ||
        info.textLength > records * recordSize) throw MobiBookParser.invalid();
      if (headerLength >= 96 && coverDirectory.length > 0) {
        info.cover = await MobiBookParser.extractCover(file.fd, MobiBookParser.u32(header, 108),
          offsets, records, info, coverDirectory);
      }
      if (consume === undefined) return info;
      const flags = version >= 5 && headerLength >= 228 ? MobiBookParser.u16(header, 242) : 0;
      const decoder = util.TextDecoder.create(encoding);
      let decoded = 0;
      for (let index = 1; index <= records; index++) {
        const raw = await MobiBookParser.readBytes(file.fd, offsets[index], offsets[index + 1] - offsets[index]);
        const packed = MobiBookParser.textRecord(raw, flags);
        const bytes = compression === 2 ? MobiBookParser.unpack(packed, recordSize) : packed;
        if (bytes.length > recordSize) throw MobiBookParser.invalid();
        // PalmDOC textLength excludes possible padding at the end of the last record.
        const remaining = info.textLength - decoded;
        if (remaining <= 0 || (index < records && bytes.length > remaining)) throw MobiBookParser.invalid();
        const actual = bytes.subarray(0, Math.min(bytes.length, remaining));
        decoded += actual.length;
        await consume(decoder.decodeToString(actual, { stream: index < records }), info,
          Math.floor(index * 100 / records));
      }
      if (decoded !== info.textLength) throw MobiBookParser.invalid();
      return info;
    } finally { await fileIo.close(file); }
  }
}
