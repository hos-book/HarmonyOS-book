// Keep selector batching and Rust tag indexing reproducible through the source sync entry.
module.exports = function nativeSelectorBatch(name, text) {
  if (name === 'core/rule/AnalyzeRule.ts') {
    text = text.replace('export class AnalyzeRule {', `export class AnalyzeRule {
  static elementTagScanner: ((html: string, tag: string) => number[]) | undefined;
  private sharedElementSpans: Map<string, ElementSpanIndex> | null = null;

  reuseElementSpansFrom(analyzer: AnalyzeRule): AnalyzeRule {
    if (analyzer.sharedElementSpans === null) analyzer.sharedElementSpans = new Map<string, ElementSpanIndex>();
    this.sharedElementSpans = analyzer.sharedElementSpans;
    return this;
  }

  private elementSpans(html: string): ElementSpanIndex {
    if (this.sharedElementSpans === null) return new ElementSpanIndex(html);
    let spans = this.sharedElementSpans.get(html);
    if (spans === undefined) {
      spans = new ElementSpanIndex(html);
      this.sharedElementSpans.set(html, spans);
    }
    return spans;
  }
`);
    text = text.replaceAll('const spans = new ElementSpanIndex(', 'const spans = this.elementSpans(');
    text = text.replace('  private pairTags(tag: string): Map<number, number> {', `  private pairTags(tag: string): Map<number, number> {
    if (AnalyzeRule.elementTagScanner) {
      const pairs = AnalyzeRule.elementTagScanner(this.html, tag);
      const indexed = new Map<number, number>();
      for (let i = 0; i < pairs.length; i += 2) indexed.set(pairs[i], pairs[i + 1]);
      return indexed;
    }`);
  }
  if (name === 'core/nativesource/NativeSourceRunner.ts') {
    const methods = `  /** Group pure HTML fields while each field retains its own evaluation context. */
  private async readSelectorFields(fields: Record<string, NativeValue>, names: string[], scope: NativeScope,
    items: NativeValue[] | null, prefix: string): Promise<Record<string, NativeValue>[]> {
    if (!this.host.parsePure) return [];
    const rules: Record<string, NativeValue> = {};
    for (const name of names) {
      const rule = fields[name];
      if (typeof rule !== 'string' || !rule.trim()) continue;
      const text = rule.trim();
      if (name === 'type' && /^(text|audio|comic|image|video)$/i.test(text) && prefix !== 'toc') continue;
      if (text.startsWith('=') || !NativePureRule.isPure(text)) return [];
      rules[name] = text;
    }
    if (Object.keys(rules).length === 0) return [];
    const contents = items || [scope.get('item')];
    if (contents.some(item => typeof item !== 'string')) return [];
    const result = await this.host.parsePure(JSON.stringify({kind:'selectBatch', rule:'',
      contents, rules, baseUrl:NativeExpr.toText(scope.get('baseUrl'))}));
    return result === null ? [] : JSON.parse(result) as Record<string, NativeValue>[];
  }

  private async selectorField(selected: Record<string, NativeValue>, fields: Record<string, NativeValue>,
    name: string, scope: NativeScope, prefix: string): Promise<NativeValue> {
    if (!Object.prototype.hasOwnProperty.call(selected, name)) {
      return this.value(fields[name], scope, false, prefix + '.fields.' + name);
    }
    const result = selected[name] as Record<string, NativeValue>;
    if (result.failed) throw this.fieldError(prefix + '.fields.' + name, fields[name], new Error(String(result.error)));
    this.traceRule(prefix + '.fields.' + name, fields[name], result.value, false, scope);
    return result.value;
  }

`;
    text = text.replace('  private async readBooks(', methods + '  private async readBooks(');
    text = text.replace('    let scriptValues: Record<string, NativeValue>[] = [];',
      '    let scriptValues: Record<string, NativeValue>[] = [];\n    let selectorValues: Record<string, NativeValue>[] = [];');
    text = text.replace('      if (i % 16 === 0) scriptValues = await this.readScriptFields(stage.fields || {}, loaded.scope,\n' +
      '        items.slice(i, i + 16), i, prefix);',
      '      if (i % 16 === 0) {\n' +
      '        scriptValues = await this.readScriptFields(stage.fields || {}, loaded.scope, items.slice(i, i + 16), i, prefix);\n' +
      '        selectorValues = await this.readSelectorFields(stage.fields || {}, BOOK_FIELD_NAMES, loaded.scope,\n' +
      '          items.slice(i, i + 16), prefix);\n      }');
    text = text.replace('        scriptValues[i % 16] || {}));', '        scriptValues[i % 16] || {}, selectorValues[i % 16] || {}));');
    text = text.replace('    prefix: string, scriptValues?: Record<string, NativeValue>): Promise<NativeBookRecord> {',
      '    prefix: string, scriptValues?: Record<string, NativeValue>, selectorValues?: Record<string, NativeValue>): Promise<NativeBookRecord> {');
    text = text.replace('    const read = async (name: string): Promise<NativeValue> => {',
      '    const selected = selectorValues || (await this.readSelectorFields(fields, BOOK_FIELD_NAMES, scope, null, prefix))[0] || {};\n' +
      '    const read = async (name: string): Promise<NativeValue> => {');
    text = text.replace('        return await this.value(fields[name], scope, false, `${prefix}.fields.${name}`);',
      '        return await this.selectorField(selected, fields, name, scope, prefix);');
    text = text.replace("    for (const item of (await this.listItems(stage.list || '', loaded.scope, loaded.baseUrl, 'toc.list'))) {",
      "    const items = await this.listItems(stage.list || '', loaded.scope, loaded.baseUrl, 'toc.list');\n" +
      '    let selectorValues: Record<string, NativeValue>[] = [];\n' +
      '    for (let itemIndex = 0; itemIndex < items.length; itemIndex++) {\n' +
      '      const item = items[itemIndex];');
    text = text.replace("      const itemScope = loaded.scope.child().set('item', item).set('index', chapters.length);",
      "      const itemScope = loaded.scope.child().set('item', item).set('index', chapters.length);\n" +
      '      if (itemIndex % 16 === 0) selectorValues = await this.readSelectorFields(fields, CHAPTER_FIELD_NAMES,\n' +
      "        loaded.scope, items.slice(itemIndex, itemIndex + 16), 'toc');\n" +
      '      const selected = selectorValues[itemIndex % 16] || {};\n' +
      '      const read = (name: string): Promise<NativeValue> => this.selectorField(selected, fields, name, itemScope, \'toc\');');
    text = text.replace(/this\.value\(fields\['(\w+)'\], itemScope, false, 'toc\.fields\.\1'\)/g, "read('$1')");
  }
  return text;
};
