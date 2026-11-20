import { util } from '@kit.ArkTS';

/**
 * 按书源声明的字符集把文字编成字节，用于 GBK / GB2312 一类老站的查询参数和表单。
 *
 * 先用系统 TextEncoder，但用之前拿“中”做一次校验：构造抛错、忽略参数照旧输出 UTF-8，或者按同一字符集解不回原字，
 * 都算系统不支持。GB 系字符集这时改用系统 TextDecoder 反推的码表（解码一直可用，响应就是靠它解的）。
 * 校验结果和码表进程内只做一次。都不行时返回 null，由调用方报错，不再把文字原样发出去、让站点静默返回 0 条。
 */
export class LegacyCharsetEncoder {
  private static readonly PROBE: string = '中';
  private static readonly PROBE_GB: number = 0xD6D0;
  private static systemSupport: Map<string, boolean> = new Map<string, boolean>();
  // 码点 → (首字节 << 8) | 尾字节
  private static gbTable: Map<number, number> | null = null;
  private static gbTableTried: boolean = false;

  static normalize(charset: string): string {
    const value = (charset || '').toLowerCase().replace(/["']/g, '').trim();
    if (value === 'gbk' || value === 'gb2312' || value === 'gb18030') return 'gb18030';
    if (value === 'utf8') return 'utf-8';
    return value || 'utf-8';
  }

  static isGb(charset: string): boolean {
    return LegacyCharsetEncoder.normalize(charset) === 'gb18030';
  }

  /** 编码失败（系统不支持且没有码表可用）时返回 null。 */
  static encode(text: string, charset: string): Uint8Array | null {
    if (!text) return new Uint8Array(0);
    const normalized = LegacyCharsetEncoder.normalize(charset);
    if (normalized === 'utf-8') return new util.TextEncoder().encodeInto(text);
    if (LegacyCharsetEncoder.systemSupports(normalized)) {
      return new util.TextEncoder(normalized).encodeInto(text);
    }
    if (normalized === 'gb18030') {
      const table = LegacyCharsetEncoder.gbkTable();
      if (table) return LegacyCharsetEncoder.encodeWithTable(text, table);
    }
    return null;
  }

  private static systemSupports(charset: string): boolean {
    const cached = LegacyCharsetEncoder.systemSupport.get(charset);
    if (cached !== undefined) return cached;
    let ok = false;
    try {
      const bytes = new util.TextEncoder(charset).encodeInto(LegacyCharsetEncoder.PROBE);
      const utf8 = bytes && bytes.length === 3 && bytes[0] === 0xE4 && bytes[1] === 0xB8 && bytes[2] === 0xAD;
      ok = !!bytes && bytes.length > 0 && !utf8;
      if (ok) {
        try {
          ok = util.TextDecoder.create(charset).decodeToString(bytes, { stream: false }) === LegacyCharsetEncoder.PROBE;
        } catch (_) {
          // 解码器不认时只能相信编码器的输出（它至少不是 UTF-8）。
        }
      }
    } catch (_) {
      ok = false;
    }
    LegacyCharsetEncoder.systemSupport.set(charset, ok);
    console.info(`[LegacyCharsetEncoder] system TextEncoder ${charset}: ${ok ? 'ok' : 'unsupported'}`);
    return ok;
  }

  /** 用系统解码器把 GBK 双字节区逐行解一遍，反推出“字 → 字节”的码表。 */
  private static gbkTable(): Map<number, number> | null {
    if (LegacyCharsetEncoder.gbTableTried) return LegacyCharsetEncoder.gbTable;
    LegacyCharsetEncoder.gbTableTried = true;
    try {
      const trails: number[] = [];
      for (let t = 0x40; t <= 0xFE; t++) if (t !== 0x7F) trails.push(t);
      const table = new Map<number, number>();
      const add = (char: string, lead: number, trail: number): void => {
        const point = char.codePointAt(0);
        if (point === undefined || point === 0xFFFD || point < 0x80 || table.has(point)) return;
        table.set(point, (lead << 8) | trail);
      };
      for (let lead = 0x81; lead <= 0xFE; lead++) {
        const row = new Uint8Array(trails.length * 2);
        for (let i = 0; i < trails.length; i++) {
          row[i * 2] = lead;
          row[i * 2 + 1] = trails[i];
        }
        const chars = Array.from(util.TextDecoder.create('gb18030').decodeToString(row, { stream: false }));
        if (chars.length === trails.length) {
          for (let i = 0; i < trails.length; i++) add(chars[i], lead, trails[i]);
          continue;
        }
        // 这一行有解成多个或零个字符的组合，对不上位置：逐个解。
        for (const trail of trails) {
          const one = Array.from(util.TextDecoder.create('gb18030')
            .decodeToString(new Uint8Array([lead, trail]), { stream: false }));
          if (one.length === 1) add(one[0], lead, trail);
        }
      }
      if (table.get(LegacyCharsetEncoder.PROBE.codePointAt(0) as number) !== LegacyCharsetEncoder.PROBE_GB) {
        throw new Error('码表校验失败');
      }
      LegacyCharsetEncoder.gbTable = table;
      console.info(`[LegacyCharsetEncoder] GBK table built from TextDecoder: ${table.size} chars`);
    } catch (e) {
      console.warn('[LegacyCharsetEncoder] GBK table unavailable:', (e as Error).message);
      LegacyCharsetEncoder.gbTable = null;
    }
    return LegacyCharsetEncoder.gbTable;
  }

  /** 码表里没有的字编成 “?”，与按 GBK 编码的 Java URLEncoder 一致。 */
  private static encodeWithTable(text: string, table: Map<number, number>): Uint8Array {
    const bytes: number[] = [];
    for (const char of Array.from(text)) {
      const point = char.codePointAt(0) as number;
      if (point < 0x80) {
        bytes.push(point);
        continue;
      }
      const code = table.get(point);
      if (code === undefined) bytes.push(0x3F);
      else bytes.push(code >> 8, code & 0xFF);
    }
    return new Uint8Array(bytes);
  }
}
