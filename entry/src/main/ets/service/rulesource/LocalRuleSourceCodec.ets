import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleSourceImportParser } from './LocalRuleSourceImportParser';

/** Merge editable fields into the original definition so extension fields survive a round trip. */
export class LocalRuleSourceCodec {
  static exportFileName(sources: LocalRuleSource[]): string {
    const original = sources.length > 0 ? sources[0].bookSourceName : '';
    const name = original.replace(/[\\/:*?"<>|\x00-\x1f]/g, '_').trim()
      .slice(0, 60).replace(/[. ]+$/g, '') || 'book-source';
    const count = sources.length > 1 ? `-${sources.length}` : '';
    return `${name}${count}-${Date.now()}.json`;
  }

  static exportBatch(sources: LocalRuleSource[]): string {
    const definitions: Record<string, Object>[] = [];
    for (const source of sources) {
      const definition: Record<string, Object> = JSON.parse(LocalRuleSourceCodec.stringify(source));
      definitions.push(definition);
    }
    return JSON.stringify(definitions);
  }

  static stringify(source: LocalRuleSource): string {
    if (source.engine === 'light-native') {
      const definition: Record<string, Object> = JSON.parse(source.rawSourceJson);
      definition['name'] = source.bookSourceName;
      definition['group'] = source.bookSourceGroup;
      definition['enabled'] = source.enabled;
      definition['enabledExplore'] = source.enabledExplore;
      definition['variable'] = source.variable;
      return JSON.stringify(definition);
    }
    if (source.engine === 'native-v1') {
      return source.rawSourceJson;
    }
    const original: Record<string, Object> = source.rawSourceJson.trim().length > 0
      ? JSON.parse(source.rawSourceJson) : {};
    const current = LocalRuleSourceCodec.snapshot(source);
    const originals = LocalRuleSourceImportParser.parse(source.rawSourceJson).sources;
    const baselineSource = originals.length === 1 ? originals[0] : new LocalRuleSource();
    // The parser supplies the current time when the definition has no timestamp.
    // It is an import default, not an edit to the portable definition.
    if (originals.length === 1 && original['lastUpdateTime'] === undefined) {
      baselineSource.lastUpdateTime = source.lastUpdateTime;
    }
    const baseline = LocalRuleSourceCodec.snapshot(baselineSource);
    const result: Record<string, Object> = {};
    const omitted: string[] = ['rawSourceJson', 'nativeBaseUrl', 'nativeRulesJson', 'nativeRulesValid', 'nativeSearch',
      'engine', 'validationStatus', 'validationMessage', 'locked',
      'loginHeader', 'loginInfo', 'loginResult', 'cookie', 'cookies', 'cookieHeader',
      'token', 'accessToken', 'refreshToken', 'deviceId', 'accountLabel', 'session', 'scriptState'];
    for (const key of Object.keys(original)) {
      if (!omitted.includes(key)) result[key] = original[key];
    }
    const groups: string[] = ['ruleSearch', 'ruleExplore', 'ruleBookInfo', 'ruleToc', 'ruleContent'];
    for (const key of Object.keys(current)) {
      if (omitted.includes(key)) continue;
      if (originals.length === 1 && JSON.stringify(current[key]) === JSON.stringify(baseline[key]) &&
        !(key === 'isLocked' && original['locked'] !== undefined)) continue;
      if (groups.includes(key)) {
        result[key] = LocalRuleSourceCodec.mergeGroup(original[key], current[key], baseline[key]);
      } else {
        result[key] = current[key];
      }
    }
    return JSON.stringify(result);
  }

  private static snapshot(source: LocalRuleSource): Record<string, Object> {
    const serialized: Record<string, Object> = JSON.parse(JSON.stringify(source));
    const result: Record<string, Object> = {};
    for (const key of Object.keys(serialized)) {
      if (!key.startsWith('__ob_')) result[key] = serialized[key];
    }
    result['enabled'] = source.enabled;
    result['enabledExplore'] = source.enabledExplore;
    result['isLocked'] = source.isLocked;
    result['isPinned'] = source.isPinned;
    result['validationStatus'] = source.validationStatus;
    result['validationMessage'] = source.validationMessage;
    return result;
  }

  private static mergeGroup(original: Object | undefined, current: Object,
    baseline: Object): Record<string, Object> {
    const result: Record<string, Object> = {};
    const hasOriginalFields = original !== undefined && original !== null &&
      typeof original === 'object' && !Array.isArray(original);
    if (hasOriginalFields) {
      const fields: Record<string, Object> = JSON.parse(JSON.stringify(original));
      for (const key of Object.keys(fields)) result[key] = fields[key];
    }
    const edited: Record<string, Object> = JSON.parse(JSON.stringify(current));
    const previous: Record<string, Object> = JSON.parse(JSON.stringify(baseline));
    for (const key of Object.keys(edited)) {
      if (hasOriginalFields && JSON.stringify(edited[key]) === JSON.stringify(previous[key])) continue;
      if (!hasOriginalFields && edited[key] === '') continue;
      result[key] = edited[key];
    }
    return result;
  }
}
