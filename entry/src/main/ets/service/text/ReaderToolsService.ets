import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { ReaderBookmark, ReaderReplaceRule, ReaderTextDocument, ReaderToolsSnapshot } from '../../model/ReaderTools';

class ReaderDocumentCache {
  bookId: string = '';
  raw: string = '';
  revision: number = 0;
  document: ReaderTextDocument = new ReaderTextDocument();
}

export class ReaderToolsService {
  private static store: preferences.Preferences | null = null;
  private static opening: Promise<preferences.Preferences> | null = null;
  private static writing: Promise<void> = Promise.resolve();
  private static revision: number = 0;
  private static cache: ReaderDocumentCache[] = [];

  private static async open(context: common.Context): Promise<preferences.Preferences> {
    if (ReaderToolsService.store !== null) return ReaderToolsService.store;
    if (ReaderToolsService.opening === null) {
      ReaderToolsService.opening = preferences.getPreferences(context, { name: 'reader_tools_v1' });
    }
    try {
      ReaderToolsService.store = await ReaderToolsService.opening;
      return ReaderToolsService.store;
    } finally { ReaderToolsService.opening = null; }
  }

  static newId(): string { return util.generateRandomUUID(); }

  static validBookmark(value: ReaderBookmark): boolean {
    return !!value && typeof value.id === 'string' && value.id.length > 0 && value.id.length <= 128 &&
      typeof value.bookId === 'string' && value.bookId.length > 0 && value.bookId.length <= 8192 &&
      typeof value.chapterId === 'string' && value.chapterId.length <= 8192 &&
      typeof value.chapterUrl === 'string' && value.chapterUrl.length <= 16384 &&
      typeof value.chapterTitle === 'string' && value.chapterTitle.length <= 1024 &&
      typeof value.domPos === 'string' && value.domPos.length <= 8192 &&
      typeof value.preview === 'string' && value.preview.length <= 240 &&
      [value.resourceIndex, value.charOffset, value.createdAt].every((n: number): boolean => Number.isSafeInteger(n) && n >= 0);
  }

  static validRule(value: ReaderReplaceRule): boolean {
    return !!value && typeof value.id === 'string' && value.id.length > 0 && value.id.length <= 128 &&
      typeof value.bookId === 'string' && value.bookId.length <= 8192 &&
      typeof value.name === 'string' && value.name.length <= 80 &&
      typeof value.pattern === 'string' && value.pattern.length > 0 && value.pattern.length <= 2048 &&
      typeof value.replacement === 'string' && value.replacement.length <= 2048 &&
      typeof value.enabled === 'boolean' && typeof value.isRegex === 'boolean';
  }

  private static read(store: preferences.Preferences): ReaderToolsSnapshot {
    const raw = store.getSync('data', '');
    if (typeof raw !== 'string' || !raw) return new ReaderToolsSnapshot();
    const value: ReaderToolsSnapshot = JSON.parse(raw);
    if (!ReaderToolsService.validSnapshot(value)) throw new Error('reader_tools_storage_error');
    return value;
  }

  static validSnapshot(value: ReaderToolsSnapshot): boolean {
    return !!value && Array.isArray(value.bookmarks) && value.bookmarks.length <= 10000 &&
      value.bookmarks.every((item: ReaderBookmark): boolean => ReaderToolsService.validBookmark(item)) &&
      Array.isArray(value.rules) && value.rules.length <= 200 &&
      value.rules.every((item: ReaderReplaceRule): boolean => ReaderToolsService.validRule(item));
  }

  static async snapshot(context: common.Context): Promise<ReaderToolsSnapshot> {
    await ReaderToolsService.writing;
    return ReaderToolsService.read(await ReaderToolsService.open(context));
  }

  private static mutate(context: common.Context, change: (data: ReaderToolsSnapshot) => void): Promise<void> {
    const request = ReaderToolsService.writing.then(async (): Promise<void> => {
      const store = await ReaderToolsService.open(context);
      const previous = store.getSync('data', '');
      const data = ReaderToolsService.read(store);
      change(data);
      if (!ReaderToolsService.validSnapshot(data)) throw new Error('reader_tools_limit');
      try {
        await store.put('data', JSON.stringify(data));
        await store.flush();
      } catch (error) {
        await store.put('data', previous);
        throw new Error(error instanceof Error ? error.message : 'reader_tools_storage_error');
      }
      ReaderToolsService.revision++;
      ReaderToolsService.cache = [];
    });
    ReaderToolsService.writing = request.catch((): void => {});
    return request;
  }

  static async bookmarks(context: common.Context, bookId: string): Promise<ReaderBookmark[]> {
    return (await ReaderToolsService.snapshot(context)).bookmarks.filter((item): boolean => item.bookId === bookId)
      .sort((a, b): number => a.resourceIndex - b.resourceIndex || a.charOffset - b.charOffset);
  }

  static addBookmark(context: common.Context, mark: ReaderBookmark): Promise<void> {
    return ReaderToolsService.mutate(context, (data): void => {
      if (!ReaderToolsService.validBookmark(mark)) throw new Error('reader_tools_storage_error');
      const exists = data.bookmarks.some((item): boolean => item.bookId === mark.bookId &&
        item.chapterUrl === mark.chapterUrl && item.charOffset === mark.charOffset && item.domPos === mark.domPos);
      if (!exists) data.bookmarks.push(mark);
    });
  }

  static removeBookmark(context: common.Context, id: string): Promise<void> {
    return ReaderToolsService.mutate(context, (data): void => {
      data.bookmarks = data.bookmarks.filter((item): boolean => item.id !== id);
    });
  }

  static async rules(context: common.Context): Promise<ReaderReplaceRule[]> {
    return (await ReaderToolsService.snapshot(context)).rules;
  }

  static async saveRule(context: common.Context, rule: ReaderReplaceRule): Promise<void> {
    if (!ReaderToolsService.validRule(rule)) throw new Error('reader_replace_invalid');
    if (rule.isRegex && rule.enabled) {
      const runtime = await import('../rulesource/LocalRuleQuickJsRuntime');
      const request = new runtime.LocalRuleQuickJsRequest();
      request.script = `new RegExp(${JSON.stringify(rule.pattern)}, 'g'); 'ok';`;
      request.sourceUrl = 'reader-replace-validate';
      request.timeoutMs = 100;
      const result = await runtime.LocalRuleQuickJsRuntime.execute(request);
      if (!result.success) throw new Error('reader_replace_invalid');
    }
    await ReaderToolsService.mutate(context, (data): void => {
      const index = data.rules.findIndex((item): boolean => item.id === rule.id);
      if (index >= 0) data.rules[index] = rule;
      else data.rules.push(rule);
    });
  }

  static deleteRule(context: common.Context, id: string): Promise<void> {
    return ReaderToolsService.mutate(context, (data): void => {
      data.rules = data.rules.filter((item): boolean => item.id !== id);
    });
  }

  static restore(context: common.Context, snapshot: ReaderToolsSnapshot): Promise<void> {
    return ReaderToolsService.mutate(context, (data): void => {
      data.bookmarks = data.bookmarks.filter((mark): boolean => mark.bookId.startsWith('import_'))
        .concat(snapshot.bookmarks.filter((mark): boolean => !mark.bookId.startsWith('import_')));
      data.rules = data.rules.filter((rule): boolean => rule.bookId.startsWith('import_'))
        .concat(snapshot.rules.filter((rule): boolean => !rule.bookId.startsWith('import_')));
    });
  }

  static async render(context: common.Context, bookId: string, raw: string,
    previewRules?: ReaderReplaceRule[]): Promise<ReaderTextDocument> {
    const original = ReaderTextDocument.original(raw);
    let rules: ReaderReplaceRule[] = [];
    try {
      rules = (previewRules ?? await ReaderToolsService.rules(context))
        .filter((item): boolean => item.enabled && (!item.bookId || item.bookId === bookId));
    } catch (_error) { original.failed = true; return original; }
    if (rules.length === 0 || !raw) return original;
    const revision = ReaderToolsService.revision;
    const cached = ReaderToolsService.cache.find((item): boolean => item.bookId === bookId &&
      item.raw === raw && item.revision === revision);
    if (!previewRules && cached) return cached.document;
    // 正则在已有有界任务沙箱中执行；失败返回原文，绝不写回正文缓存。
    const runtime = await import('../rulesource/LocalRuleQuickJsRuntime');
    const request = new runtime.LocalRuleQuickJsRequest();
    request.timeoutMs = 1000;
    request.sourceUrl = 'reader-replace';
    request.script = `(() => {
      let text = ${JSON.stringify(raw)};
      const rules = ${JSON.stringify(rules)};
      const stages = [];
      for (const rule of rules) {
        const edits = [];
        const re = rule.isRegex ? new RegExp(rule.pattern, 'g') : null;
        let output = '', base = 0;
        const parts = text.split(/(\\uFFF9[^\\uFFF9\\uFFFB\\n]{1,1024}\\uFFFB)/g);
        for (const part of parts) {
          if (part.charAt(0) === '\\uFFF9') { output += part; base += part.length; continue; }
          let cursor = 0, from = 0, match;
          if (re) re.lastIndex = 0;
          while (re ? (match = re.exec(part)) !== null : (from = part.indexOf(rule.pattern, cursor)) >= 0) {
            if (re) from = match.index;
            const matched = re ? match[0] : rule.pattern;
            const replacement = re ? rule.replacement.replace(/\\$(\\$|&|[0-9]{1,2})/g, (_, key) =>
              key === '$' ? '$' : key === '&' ? matched : (match[Number(key)] ?? '')) : rule.replacement;
            edits.push({ start: base + from, end: base + from + matched.length, length: replacement.length });
            output += part.substring(cursor, from) + replacement;
            cursor = from + matched.length;
            if (edits.length > 50000 || output.length > 2097152) throw new Error('limit');
            if (re && matched.length === 0) { re.lastIndex = from + 1; if (from === part.length) break; }
          }
          output += part.substring(cursor); base += part.length;
          if (output.length > 2097152) throw new Error('limit');
        }
        text = output;
        if (edits.length) stages.push({ edits });
      }
      return JSON.stringify({ content: text, stages });
    })()`;
    const result = await runtime.LocalRuleQuickJsRuntime.execute(request);
    if (!result.success || result.value.length > 8 * 1024 * 1024) { original.failed = true; return original; }
    try {
      const parsed: ReaderTextDocument = JSON.parse(result.value);
      const document = ReaderTextDocument.original(raw);
      document.content = parsed.content;
      document.stages = parsed.stages;
      if (!previewRules && revision === ReaderToolsService.revision) {
        const entry = new ReaderDocumentCache();
        entry.bookId = bookId; entry.raw = raw; entry.revision = revision; entry.document = document;
        ReaderToolsService.cache.push(entry);
        if (ReaderToolsService.cache.length > 8) ReaderToolsService.cache.shift();
      }
      return document;
    } catch (_error) { original.failed = true; return original; }
  }
}
