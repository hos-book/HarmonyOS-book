import { util } from '@kit.ArkTS';

class Kf8Tag {
  id: number = 0;
  values: number = 0;
  mask: number = 0;
  end: number = 0;
}

class Kf8Entry {
  name: string = '';
  tags: Map<number, number[]> = new Map();
  value(tag: number, index: number = 0): number {
    const value = this.tags.get(tag)?.[index];
    if (value === undefined) throw new Error('import_mobi_invalid');
    return value;
  }
}

class Kf8Cursor {
  position: number;
  end: number;
  bytes: Uint8Array;
  constructor(bytes: Uint8Array, start: number, end: number) {
    this.bytes = bytes; this.position = start; this.end = end;
  }
  integer(): number {
    let result = 0;
    for (let index = 0; index < 4 && this.position < this.end; index++) {
      const byte = this.bytes[this.position++];
      result = result * 128 + (byte & 127);
      if ((byte & 128) !== 0) return result;
    }
    throw new Error('import_mobi_invalid');
  }
}

/** KF8 INDX/TAGX skeleton and fragment reconstruction, before HTML text extraction. */
export class Kf8BookText {
  private static invalid(): Error { return new Error('import_mobi_invalid'); }
  private static number(bytes: Uint8Array, offset: number, length: number = 4): number {
    if (offset < 0 || offset + length > bytes.length) throw Kf8BookText.invalid();
    let value = 0;
    for (let index = 0; index < length; index++) value = value * 256 + bytes[offset + index];
    return value;
  }
  private static signature(bytes: Uint8Array, offset: number, text: string): void {
    if (offset < 0 || offset + text.length > bytes.length) throw Kf8BookText.invalid();
    for (let index = 0; index < text.length; index++) {
      if (bytes[offset + index] !== text.charCodeAt(index)) throw Kf8BookText.invalid();
    }
  }
  private static async index(record: number, load: (index: number) => Promise<Uint8Array>): Promise<Kf8Entry[]> {
    const header = await load(record);
    Kf8BookText.signature(header, 0, 'INDX');
    const tagStart = Kf8BookText.number(header, 4);
    Kf8BookText.signature(header, tagStart, 'TAGX');
    const tagEnd = tagStart + Kf8BookText.number(header, tagStart + 4);
    const controls = Kf8BookText.number(header, tagStart + 8);
    const records = Kf8BookText.number(header, 24);
    if (tagEnd > header.length || controls < 1 || controls > 32 || records > 4096 ||
      tagEnd < tagStart + 12 || (tagEnd - tagStart - 12) % 4 !== 0) throw Kf8BookText.invalid();
    const tags: Kf8Tag[] = [];
    for (let at = tagStart + 12; at < tagEnd; at += 4) {
      const tag = new Kf8Tag();
      tag.id = header[at]; tag.values = header[at + 1]; tag.mask = header[at + 2]; tag.end = header[at + 3];
      tags.push(tag);
    }
    const result: Kf8Entry[] = [];
    const decoder = util.TextDecoder.create('utf-8');
    for (let group = 1; group <= records; group++) {
      const bytes = await load(record + group);
      Kf8BookText.signature(bytes, 0, 'INDX');
      const table = Kf8BookText.number(bytes, 20);
      const count = Kf8BookText.number(bytes, 24);
      Kf8BookText.signature(bytes, table, 'IDXT');
      if (count > 50000 - result.length || table + 4 + count * 2 > bytes.length) throw Kf8BookText.invalid();
      for (let row = 0; row < count; row++) {
        const start = Kf8BookText.number(bytes, table + 4 + row * 2, 2);
        const end = row + 1 < count ? Kf8BookText.number(bytes, table + 6 + row * 2, 2) : table;
        if (start >= end || end > table) throw Kf8BookText.invalid();
        const nameEnd = start + 1 + bytes[start];
        if (nameEnd + controls > end) throw Kf8BookText.invalid();
        const item = new Kf8Entry();
        item.name = decoder.decodeToString(bytes.subarray(start + 1, nameEnd));
        const cursor = new Kf8Cursor(bytes, nameEnd + controls, end);
        const counts: number[] = [];
        const sizes: number[] = [];
        let control = 0;
        for (const tag of tags) {
          if ((tag.end & 1) !== 0) { control++; counts.push(0); sizes.push(-1); continue; }
          if (control >= controls || tag.mask === 0) throw Kf8BookText.invalid();
          let value = bytes[nameEnd + control] & tag.mask;
          if (value === tag.mask && (tag.mask & (tag.mask - 1)) !== 0) {
            counts.push(0); sizes.push(cursor.integer());
          } else {
            let mask = tag.mask;
            while ((mask & 1) === 0) { mask >>= 1; value >>= 1; }
            counts.push(value === tag.mask ? 1 : value); sizes.push(-1);
          }
        }
        for (let index = 0; index < tags.length; index++) {
          const tag = tags[index];
          if ((tag.end & 1) !== 0) continue;
          const values: number[] = [];
          if (sizes[index] >= 0) {
            const until = cursor.position + sizes[index];
            if (until > end) throw Kf8BookText.invalid();
            while (cursor.position < until) values.push(cursor.integer());
            if (cursor.position !== until) throw Kf8BookText.invalid();
          } else {
            const count = counts[index] * tag.values;
            if (count > end - cursor.position) throw Kf8BookText.invalid();
            for (let value = 0; value < count; value++) values.push(cursor.integer());
          }
          item.tags.set(tag.id, values);
        }
        result.push(item);
      }
    }
    return result;
  }

  static async sections(header: Uint8Array, raw: Uint8Array, encoding: string,
    load: (index: number) => Promise<Uint8Array>): Promise<string[]> {
    const skeletons = await Kf8BookText.index(Kf8BookText.number(header, 252), load);
    const fragments = await Kf8BookText.index(Kf8BookText.number(header, 248), load);
    const decoder = util.TextDecoder.create(encoding);
    const output: string[] = [];
    let fragmentIndex = 0;
    let total = 0;
    for (const skeleton of skeletons) {
      const start = skeleton.value(6), length = skeleton.value(6, 1), count = skeleton.value(1);
      if (start + length > raw.length || count > fragments.length - fragmentIndex) throw Kf8BookText.invalid();
      let bytes = raw.slice(start, start + length);
      for (let index = 0; index < count; index++) {
        const fragment = fragments[fragmentIndex++];
        const insert = Number(fragment.name) - start;
        const from = start + length + fragment.value(6), size = fragment.value(6, 1);
        if (!Number.isInteger(insert) || insert < 0 || insert > bytes.length || from + size > raw.length ||
          bytes.length + size > 32 * 1024 * 1024) throw Kf8BookText.invalid();
        const merged = new Uint8Array(bytes.length + size);
        merged.set(bytes.subarray(0, insert)); merged.set(raw.subarray(from, from + size), insert);
        merged.set(bytes.subarray(insert), insert + size); bytes = merged;
      }
      total += bytes.length;
      if (total > 32 * 1024 * 1024) throw new Error('import_mobi_size');
      output.push(decoder.decodeToString(bytes));
    }
    if (fragmentIndex !== fragments.length || output.length === 0) throw Kf8BookText.invalid();
    return output;
  }
}
