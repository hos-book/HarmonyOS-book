import { createMobiHuff, decodeMobiBatch, releaseMobiHuff } from 'libhsda_core.so';

/** 同次导入复用原生字典；解码批次由原生后台任务串行完成。 */
export class MobiHuffDecoder {
  private handle: Object;
  private capacity: number;

  private constructor(handle: Object, capacity: number) {
    this.handle = handle;
    this.capacity = capacity;
  }

  static async create(first: number, count: number, capacity: number,
    load: (index: number) => Promise<Uint8Array>): Promise<MobiHuffDecoder> {
    if (count < 2 || count > 256 || capacity < 1 || capacity > 65535) throw new Error('import_mobi_invalid');
    const records: Uint8Array[] = [];
    for (let index = 0; index < count; index++) records.push(await load(first + index));
    return new MobiHuffDecoder(await createMobiHuff(records, capacity), capacity);
  }

  async unpackBatch(records: Uint8Array[]): Promise<Uint8Array[]> {
    return decodeMobiBatch(records, this.capacity, this.handle);
  }

  release(): void {
    releaseMobiHuff(this.handle);
  }
}
