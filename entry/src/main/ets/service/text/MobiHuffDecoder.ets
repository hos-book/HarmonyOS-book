class MobiHuffPhrase {
  bytes: Uint8Array;
  expanded: boolean;
  expanding: boolean = false;
  constructor(bytes: Uint8Array, expanded: boolean) {
    this.bytes = bytes;
    this.expanded = expanded;
  }
}

/** Bounded MOBI HUFF/CDIC dictionary decoding; shared by MOBI6 and KF8. */
export class MobiHuffDecoder {
  private prefixes: number[] = [];
  private minimum: number[] = [0];
  private maximum: number[] = [0];
  private phrases: MobiHuffPhrase[] = [];
  private dictionaryBytes: number = 0;
  private operations: number = 0;
  private readonly capacity: number;
  private static readonly MAX_DICTIONARY_BYTES: number = 32 * 1024 * 1024;

  private constructor(capacity: number) { this.capacity = capacity; }
  private static invalid(): Error { return new Error('import_mobi_invalid'); }
  private static number(bytes: Uint8Array, offset: number, length: number = 4): number {
    if (offset < 0 || offset + length > bytes.length) throw MobiHuffDecoder.invalid();
    let value = 0;
    for (let index = 0; index < length; index++) value = value * 256 + bytes[offset + index];
    return value;
  }
  private static signature(bytes: Uint8Array, text: string): void {
    for (let index = 0; index < text.length; index++) {
      if (bytes[index] !== text.charCodeAt(index)) throw MobiHuffDecoder.invalid();
    }
  }

  static async create(first: number, count: number, capacity: number,
    load: (index: number) => Promise<Uint8Array>): Promise<MobiHuffDecoder> {
    if (count < 2 || count > 256 || capacity < 1 || capacity > 65535) throw MobiHuffDecoder.invalid();
    const decoder = new MobiHuffDecoder(capacity);
    const header = await load(first);
    MobiHuffDecoder.signature(header, 'HUFF');
    if (MobiHuffDecoder.number(header, 4) !== 24) throw MobiHuffDecoder.invalid();
    const prefixOffset = MobiHuffDecoder.number(header, 8);
    const rangeOffset = MobiHuffDecoder.number(header, 12);
    if (prefixOffset < 24 || rangeOffset < 24) throw MobiHuffDecoder.invalid();
    for (let index = 0; index < 256; index++) {
      const prefix = MobiHuffDecoder.number(header, prefixOffset + index * 4);
      const length = prefix & 31;
      if (length === 0 || (length <= 8 && (prefix & 128) === 0)) throw MobiHuffDecoder.invalid();
      decoder.prefixes.push(prefix);
    }
    for (let length = 1; length <= 32; length++) {
      decoder.minimum.push(MobiHuffDecoder.number(header, rangeOffset + (length - 1) * 8));
      decoder.maximum.push(MobiHuffDecoder.number(header, rangeOffset + (length - 1) * 8 + 4));
    }
    let expected = 0;
    for (let record = 1; record < count; record++) {
      const bytes = await load(first + record);
      MobiHuffDecoder.signature(bytes, 'CDIC');
      if (MobiHuffDecoder.number(bytes, 4) !== 16) throw MobiHuffDecoder.invalid();
      const total = MobiHuffDecoder.number(bytes, 8);
      const bits = MobiHuffDecoder.number(bytes, 12);
      if (total < 1 || total > 65536 || bits < 1 || bits > 16 ||
        (record > 1 && total !== expected)) throw MobiHuffDecoder.invalid();
      expected = total;
      const entries = Math.min(Math.pow(2, bits), total - decoder.phrases.length);
      if (entries <= 0 || 16 + entries * 2 > bytes.length) throw MobiHuffDecoder.invalid();
      for (let index = 0; index < entries; index++) {
        const offset = 16 + MobiHuffDecoder.number(bytes, 16 + index * 2, 2);
        if (offset < 16 + entries * 2) throw MobiHuffDecoder.invalid();
        const flags = MobiHuffDecoder.number(bytes, offset, 2);
        const length = flags & 0x7FFF;
        if (offset + 2 + length > bytes.length) throw MobiHuffDecoder.invalid();
        decoder.dictionaryBytes += length;
        if (decoder.dictionaryBytes > MobiHuffDecoder.MAX_DICTIONARY_BYTES) throw new Error('import_mobi_size');
        decoder.phrases.push(new MobiHuffPhrase(bytes.slice(offset + 2, offset + 2 + length),
          (flags & 0x8000) !== 0));
      }
    }
    if (decoder.phrases.length !== expected) throw MobiHuffDecoder.invalid();
    return decoder;
  }

  // Read a zero-padded 32-bit lookahead without signed shifts or BigInt.
  private static lookahead(bytes: Uint8Array, bit: number): number {
    const start = Math.floor(bit / 8);
    let value = 0;
    for (let index = 0; index < 5; index++) value = value * 256 + (bytes[start + index] ?? 0);
    return Math.floor(value / Math.pow(2, 8 - bit % 8)) % 4294967296;
  }

  unpack(bytes: Uint8Array): Uint8Array {
    this.operations = 0;
    return this.expand(bytes, 0);
  }

  private expand(bytes: Uint8Array, depth: number): Uint8Array {
    if (depth > 32) throw MobiHuffDecoder.invalid();
    const output = new Uint8Array(this.capacity);
    let written = 0;
    let bit = 0;
    while (bit < bytes.length * 8) {
      if (++this.operations > 1024 * 1024) throw MobiHuffDecoder.invalid();
      const lookahead = MobiHuffDecoder.lookahead(bytes, bit);
      const prefix = this.prefixes[Math.floor(lookahead / 16777216)];
      let length = prefix & 31;
      let code = Math.floor(lookahead / Math.pow(2, 32 - length));
      let maximum = Math.floor(prefix / 256);
      if ((prefix & 128) === 0) {
        while (length <= 32 && code < this.minimum[length]) {
          length++;
          code = Math.floor(lookahead / Math.pow(2, 32 - length));
        }
        if (length > 32) throw MobiHuffDecoder.invalid();
        maximum = this.maximum[length];
      }
      if (bit + length > bytes.length * 8) break;
      bit += length;
      const index = maximum - code;
      if (index < 0 || index >= this.phrases.length) throw MobiHuffDecoder.invalid();
      const phrase = this.phrases[index];
      if (!phrase.expanded) {
        if (phrase.expanding) throw MobiHuffDecoder.invalid();
        phrase.expanding = true;
        try {
          const expanded = this.expand(phrase.bytes, depth + 1);
          const size = this.dictionaryBytes - phrase.bytes.length + expanded.length;
          if (size > MobiHuffDecoder.MAX_DICTIONARY_BYTES) throw new Error('import_mobi_size');
          phrase.bytes = expanded;
          phrase.expanded = true;
          this.dictionaryBytes = size;
        } finally { phrase.expanding = false; }
      }
      if (written + phrase.bytes.length > output.length) throw MobiHuffDecoder.invalid();
      output.set(phrase.bytes, written);
      written += phrase.bytes.length;
    }
    return output.slice(0, written);
  }
}
