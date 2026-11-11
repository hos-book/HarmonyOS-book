import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ReaderReplaceRule } from '../../model/ReaderTools';

class ImportedReplaceRule {
  name?: string;
  pattern?: string;
  replacement?: string;
  isRegex?: boolean;
  enabled?: boolean;
  isEnabled?: boolean;
  scopeContent?: boolean;
  scope?: string;
  excludeScope?: string;
  scopeSource?: boolean;
}

class ImportedReplaceFile extends ImportedReplaceRule {
  rules?: ImportedReplaceRule[];
}

/** 只读取 JSON 数据，正则校验和执行仍交给有界 QuickJS。 */
export class ReaderReplaceImport {
  static readonly MAX_BYTES: number = 1024 * 1024;

  static parse(raw: string): ReaderReplaceRule[] {
    const text = raw.replace(/^\uFEFF/, '').trim();
    if (!text || text.length > ReaderReplaceImport.MAX_BYTES) throw new Error('reader_replace_import_invalid');
    let entries: ImportedReplaceRule[];
    try {
      if (text.startsWith('[')) entries = JSON.parse(text);
      else {
        const file: ImportedReplaceFile = JSON.parse(text);
        entries = file.rules === undefined ? [file] : file.rules;
      }
    } catch (_error) { throw new Error('reader_replace_import_invalid'); }
    if (Array.isArray(entries) && entries.length > 1000) throw new Error('reader_tools_limit');
    if (!Array.isArray(entries) || entries.length === 0) {
      throw new Error('reader_replace_import_invalid');
    }
    const rules: ReaderReplaceRule[] = [];
    for (const entry of entries) {
      if (!entry || typeof entry.pattern !== 'string' || !entry.pattern || entry.pattern.length > 2048 ||
        (entry.name !== undefined && (typeof entry.name !== 'string' || entry.name.length > 80)) ||
        (entry.replacement !== undefined && (typeof entry.replacement !== 'string' || entry.replacement.length > 2048)) ||
        (entry.isRegex !== undefined && typeof entry.isRegex !== 'boolean') ||
        (entry.enabled !== undefined && typeof entry.enabled !== 'boolean') ||
        (entry.isEnabled !== undefined && typeof entry.isEnabled !== 'boolean')) {
        throw new Error('reader_replace_import_invalid');
      }
      // 不能把只用于标题、特定书源或排除范围的规则悄悄扩大到全部正文。
      if (entry.scopeContent === false || entry.scopeSource === true || entry.scope || entry.excludeScope) {
        throw new Error('reader_replace_import_scope_error');
      }
      const rule = new ReaderReplaceRule();
      rule.id = util.generateRandomUUID();
      rule.name = entry.name ?? '';
      rule.pattern = entry.pattern;
      rule.replacement = entry.replacement ?? '';
      rule.isRegex = entry.isRegex ?? true;
      rule.enabled = entry.enabled ?? entry.isEnabled ?? true;
      rules.push(rule);
    }
    return rules;
  }

  static async pick(context: common.Context): Promise<ReaderReplaceRule[]> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['JSON|.json'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) return [];
    const file = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
    try {
      const size = (await fileIo.stat(file.fd)).size;
      if (size <= 0 || size > ReaderReplaceImport.MAX_BYTES) throw new Error('reader_replace_import_invalid');
      const bytes = new Uint8Array(size);
      let offset = 0;
      while (offset < size) {
        const chunk = new ArrayBuffer(Math.min(65536, size - offset));
        const count = await fileIo.read(file.fd, chunk);
        if (count <= 0 || count > chunk.byteLength) throw new Error('reader_replace_import_invalid');
        bytes.set(new Uint8Array(chunk, 0, count), offset);
        offset += count;
      }
      const raw = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes);
      return ReaderReplaceImport.parse(raw);
    } finally { await fileIo.close(file); }
  }
}
