/** Bounded immutable conversion results. One cache instance owns exactly one converter. */
export class SourceDefinitionCache {
  private entries: Map<string, string> = new Map();
  private chars: number = 0;
  private convert: (raw: string) => string;
  private maxEntries: number;
  private maxChars: number;

  constructor(convert: (raw: string) => string,
    maxEntries: number = 8, maxChars: number = 2 * 1024 * 1024) {
    this.convert = convert;
    this.maxEntries = maxEntries;
    this.maxChars = maxChars;
  }

  normalize(raw: string): string {
    const cached = this.entries.get(raw);
    if (cached !== undefined) {
      this.entries.delete(raw);
      this.entries.set(raw, cached);
      return cached;
    }
    const result = this.convert(raw);
    const size = raw.length + result.length;
    if (this.maxEntries < 1 || size > this.maxChars) return result;
    while (this.entries.size >= this.maxEntries || this.chars + size > this.maxChars) {
      const oldest = this.entries.keys().next().value;
      if (oldest === undefined) break;
      this.chars -= oldest.length + this.entries.get(oldest)!.length;
      this.entries.delete(oldest);
    }
    this.entries.set(raw, result);
    this.chars += size;
    return result;
  }

  clear(): void {
    this.entries.clear();
    this.chars = 0;
  }
}
