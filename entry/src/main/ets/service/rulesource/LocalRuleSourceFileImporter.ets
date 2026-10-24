import { fileIo } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { CharsetCodec } from '../../utils/CharsetCodec';
import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleSourceImportParser } from './LocalRuleSourceImportParser';
import { LocalRuleSourceImportService } from './LocalRuleSourceImportService';
import { parseImportFile } from './LocalRuleSourceImportWorker';

export class RuleSourceFileImportResult {
  imported: number = 0;
  skippedSources: number = 0;
  skippedFiles: number = 0;
  oversizedFiles: number = 0;
  budgetFiles: number = 0;
  invalidFiles: number = 0;
  readFailedFiles: number = 0;
  writeFailedFiles: number = 0;
}

/** 文件串行读取，后台解析，限制整批输入和同时驻留内存的数据。 */
export class LocalRuleSourceFileImporter {
  static readonly MAX_FILES: number = 10;
  static readonly MAX_FILE_BYTES: number = 25 * 1024 * 1024;
  static readonly MAX_TOTAL_BYTES: number = 250 * 1024 * 1024;
  static readonly MAX_SOURCES: number = Number.MAX_SAFE_INTEGER;

  static async importFiles(uris: string[], progress: (current: number, total: number) => void):
    Promise<RuleSourceFileImportResult> {
    const result = new RuleSourceFileImportResult();
    const selected = Array.from(new Set<string>(uris));
    const total = Math.min(selected.length, LocalRuleSourceFileImporter.MAX_FILES);
    result.skippedFiles = selected.length - total;
    let totalBytes = 0;
    let sourceCount = 0;
    for (let index = 0; index < total; index++) {
      progress(index + 1, total);
      await LocalRuleSourceFileImporter.yieldToUi();
      if (sourceCount >= LocalRuleSourceFileImporter.MAX_SOURCES) {
        result.skippedFiles += total - index;
        break;
      }
      let file: fileIo.File | undefined = undefined;
      let stage: string = 'read';
      try {
        file = await fileIo.open(selected[index], fileIo.OpenMode.READ_ONLY);
        const stat = await fileIo.stat(file.fd);
        if (stat.size <= 0 || stat.size > LocalRuleSourceFileImporter.MAX_FILE_BYTES ||
          totalBytes + stat.size > LocalRuleSourceFileImporter.MAX_TOTAL_BYTES) {
          result.skippedFiles++;
          if (stat.size <= 0) result.invalidFiles++;
          else if (stat.size > LocalRuleSourceFileImporter.MAX_FILE_BYTES) result.oversizedFiles++;
          else result.budgetFiles++;
          continue;
        }
        // 无效文件也计入读取预算，防止反复消耗解析资源。
        totalBytes += stat.size;
        const buffer = new ArrayBuffer(stat.size);
        let offset = 0;
        while (offset < stat.size) {
          const chunk = new ArrayBuffer(Math.min(64 * 1024, stat.size - offset));
          // offset 相对当前文件指针；连续读取不能再次传入累计位置，否则会跳过正文。
          const read = await fileIo.read(file.fd, chunk, { length: chunk.byteLength });
          if (read <= 0) throw new Error('Incomplete source file');
          new Uint8Array(buffer).set(new Uint8Array(chunk, 0, read), offset);
          offset += read;
        }
        await fileIo.close(file);
        file = undefined;
        stage = 'parse';
        const parsed = await taskpool.execute(parseImportFile, CharsetCodec.decodeBuffer(buffer));
        if (!Array.isArray(parsed) || parsed.length <= 1) {
          result.skippedFiles++;
          result.invalidFiles++;
          continue;
        }
        result.skippedSources += Number(parsed[0]);
        const sources: LocalRuleSource[] = [];
        for (let item = 1; item < parsed.length; item++) {
          if (sourceCount >= LocalRuleSourceFileImporter.MAX_SOURCES) {
            result.skippedSources += parsed.length - item;
            break;
          }
          sourceCount++;
          const raw: Object = parsed[item];
          if (typeof raw !== 'string') { result.skippedSources++; continue; }
          try {
            const report = LocalRuleSourceImportParser.parse(raw);
            if (report.sources.length > 0) sources.push(report.sources[0]);
            else result.skippedSources++;
          } catch (_error) {
            result.skippedSources++;
          }
          if (item % 8 === 0) await LocalRuleSourceFileImporter.yieldToUi();
        }
        stage = 'write';
        const imported = await LocalRuleSourceImportService.importSources(sources);
        result.imported += imported;
        result.skippedSources += sources.length - imported;
      } catch (error) {
        result.skippedFiles++;
        if (stage === 'read') result.readFailedFiles++;
        else if (stage === 'parse') result.invalidFiles++;
        else result.writeFailedFiles++;
        // 不记录原始 JSON、授权 URI 或账号字段。
        console.error(`[SourceFileImport] ${stage} failed: ${error instanceof Error ? error.name : 'BusinessError'}`);
      } finally {
        if (file !== undefined) {
          try { await fileIo.close(file); } catch (_error) { /* 保留其他文件的导入结果。 */ }
        }
      }
    }
    return result;
  }

  private static async yieldToUi(): Promise<void> {
    await new Promise<void>((resolve) => setTimeout(resolve, 16));
  }
}
