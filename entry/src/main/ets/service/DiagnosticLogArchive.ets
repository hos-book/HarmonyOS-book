import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export class DiagnosticLogEntry {
  id: string = '';
  time: string = '';
  level: string = 'INFO';
  stage: string = '';
  message: string = '';
}

/** Four rolling segments retain about 32 MiB for each diagnostic category. */
export class DiagnosticLogArchive {
  private prefix: string;
  private size: number = 0;
  private readonly segmentBytes: number = 8 * 1024 * 1024;
  private readonly segments: number = 4;

  constructor(prefix: string) { this.prefix = prefix; }

  private path(index: number): string { return `${this.prefix}.${index}.jsonl`; }

  async initialize(): Promise<void> {
    if (await fileIo.access(this.path(0))) this.size = (await fileIo.stat(this.path(0))).size;
  }

  async append(entry: DiagnosticLogEntry): Promise<void> {
    const bytes = new util.TextEncoder().encodeInto(`${JSON.stringify(entry)}\n`);
    if (this.size > 0 && this.size + bytes.byteLength > this.segmentBytes) {
      for (let index = this.segments - 1; index > 0; index--) {
        const destination = this.path(index);
        if (await fileIo.access(destination)) await fileIo.unlink(destination);
        const source = this.path(index - 1);
        if (await fileIo.access(source)) await fileIo.moveFile(source, destination);
      }
      this.size = 0;
    }
    const file = await fileIo.open(this.path(0),
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.APPEND);
    try { await fileIo.write(file.fd, bytes.buffer); }
    finally { await fileIo.close(file); }
    this.size += bytes.byteLength;
  }

  async visit(visitor: (entry: DiagnosticLogEntry) => Promise<void>): Promise<void> {
    for (let index = this.segments - 1; index >= 0; index--) {
      const path = this.path(index);
      if (!await fileIo.access(path)) continue;
      const text = await fileIo.readText(path);
      for (const line of text.split('\n')) {
        if (line.length === 0) continue;
        const entry: DiagnosticLogEntry = JSON.parse(line);
        await visitor(entry);
      }
    }
  }

  async recent(limit: number): Promise<DiagnosticLogEntry[]> {
    const entries: DiagnosticLogEntry[] = [];
    for (let index = 0; index < this.segments; index++) {
      const path = this.path(index);
      if (!await fileIo.access(path)) continue;
      const lines = (await fileIo.readText(path)).split('\n');
      for (let lineIndex = lines.length - 1; lineIndex >= 0; lineIndex--) {
        if (lines[lineIndex].length === 0) continue;
        const entry: DiagnosticLogEntry = JSON.parse(lines[lineIndex]);
        entries.push(entry);
        if (entries.length === limit) return entries.reverse();
      }
    }
    return entries.reverse();
  }

  async clear(): Promise<void> {
    for (let index = 0; index < this.segments; index++) {
      const path = this.path(index);
      if (await fileIo.access(path)) await fileIo.unlink(path);
    }
    this.size = 0;
  }
}
