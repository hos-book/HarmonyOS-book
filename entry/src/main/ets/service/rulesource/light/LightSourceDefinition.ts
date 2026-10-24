import { NativeSourceSpec } from './upstream/core/nativesource/NativeSourceSpec';
import { NativeSourceService } from './upstream/LightNativeImport';
import { LightSourceImport } from './upstream/LightSourceImport';

/** Import validation does not initialize network, scripts or runtime singletons. */
export class LightSourceDefinition {
  // Cache immutable normalization only. Repository metadata and live login state are still read on every request.
  private static definitions = new Map<string, string>();
  private static definitionChars = 0;
  static appDefinition(raw: string): string {
    const cached = this.definitions.get(raw);
    if (cached !== undefined) return cached;
    const value = JSON.parse(raw) as Record<string, Object>;
    if (value.format || value.engine === 'native-v1' || value.nativeRules) {
      throw new Error('此定义属于已停用的简听规则格式，请导入轻页支持的书源');
    }
    const native = NativeSourceSpec.isDefinitionObject(value);
    const source = native ? NativeSourceService.importObject(value) : new LightSourceImport().parseBookSource(value);
    if (!source.bookSourceUrl || !source.bookSourceName) throw new Error('书源缺少名称或地址');
    const result = JSON.stringify({...source, engine: native ? 'light-native' : 'light', nativeSearch: !!source.searchUrl,
      ruleSearch: source.searchRule, ruleExplore: source.exploreRule, ruleBookInfo: source.bookInfoRule,
      ruleToc: source.tocRule, ruleContent: source.contentRule, rawSourceJson: raw});
    this.remember(raw, result);
    return result;
  }
  private static remember(raw: string, result: string): void {
    const size = raw.length + result.length;
    if (size <= 2 * 1024 * 1024) {
      while (this.definitions.size >= 8 || this.definitionChars + size > 2 * 1024 * 1024) {
        const first = this.definitions.keys().next().value;
        this.definitionChars -= first.length + this.definitions.get(first)!.length;
        this.definitions.delete(first);
      }
      this.definitions.set(raw, result);
      this.definitionChars += size;
    }
  }
  static normalizeDefinition(raw: string): string {
    const key = 'normalized:' + raw;
    const cached = this.definitions.get(key);
    if (cached !== undefined) return cached;
    const value = JSON.parse(raw) as Record<string, Object>;
    const result = JSON.stringify(NativeSourceSpec.isDefinitionObject(value) ? NativeSourceService.importObject(value) :
      new LightSourceImport().parseBookSource(value));
    this.remember(key, result);
    return result;
  }
}
