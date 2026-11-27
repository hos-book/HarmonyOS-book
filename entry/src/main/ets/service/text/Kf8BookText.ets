import { util } from '@kit.ArkTS';
import { rebuildKf8 } from 'libhsda_core.so';

/** Load index records; native asynchronous work parses and assembles KF8 sections. */
export class Kf8BookText {
  private static number(bytes: Uint8Array, offset: number): number {
    if (offset + 4 > bytes.length) throw new Error('import_mobi_invalid');
    return bytes[offset] * 16777216 + bytes[offset + 1] * 65536 + bytes[offset + 2] * 256 + bytes[offset + 3];
  }

  private static async records(record: number,
    load: (index: number) => Promise<Uint8Array>): Promise<Uint8Array[]> {
    const header = await load(record);
    const count = Kf8BookText.number(header, 24);
    if (count > 4096) throw new Error('import_mobi_invalid');
    const records: Uint8Array[] = [header];
    for (let group = 1; group <= count; group++) records.push(await load(record + group));
    return records;
  }

  static async sections(header: Uint8Array, raw: Uint8Array, encoding: string,
    load: (index: number) => Promise<Uint8Array>): Promise<string[]> {
    const skeletons = await Kf8BookText.records(Kf8BookText.number(header, 252), load);
    const fragments = await Kf8BookText.records(Kf8BookText.number(header, 248), load);
    const sections = await rebuildKf8(skeletons, fragments, raw);
    const decoder = util.TextDecoder.create(encoding);
    return sections.map((bytes: Uint8Array): string => decoder.decodeToString(bytes));
  }
}
