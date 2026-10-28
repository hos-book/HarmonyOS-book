/** 合成输入配置与阅读正文分离；替换采用字面匹配，不执行脚本或正则。 */
export class SpeechSynthesisSettings {
  paragraphs: number = 1;
  maxChars: number = 4000;
  timeoutSeconds: number = 30;
  retries: number = 2;
  concurrency: number = 3;
  filterSymbols: boolean = true;
  replacements: string = '';

  private static bounded(value: number, fallback: number, min: number, max: number): number {
    return typeof value === 'number' && Number.isFinite(value) ? Math.max(min, Math.min(max, Math.round(value))) : fallback;
  }

  static normalize(value: SpeechSynthesisSettings): SpeechSynthesisSettings {
    const result = new SpeechSynthesisSettings();
    result.paragraphs = SpeechSynthesisSettings.bounded(value.paragraphs, 1, 1, 10);
    result.maxChars = SpeechSynthesisSettings.bounded(value.maxChars, 4000, 100, 4000);
    result.timeoutSeconds = SpeechSynthesisSettings.bounded(value.timeoutSeconds, 30, 5, 120);
    result.retries = SpeechSynthesisSettings.bounded(value.retries, 2, 0, 3);
    result.concurrency = SpeechSynthesisSettings.bounded(value.concurrency, 3, 1, 4);
    result.filterSymbols = value.filterSymbols !== false;
    result.replacements = typeof value.replacements === 'string' ? value.replacements.slice(0, 4096) : '';
    return result;
  }

  static parse(raw: string): SpeechSynthesisSettings {
    try {
      const value: SpeechSynthesisSettings | null = JSON.parse(raw);
      if (value !== null && typeof value === 'object') return SpeechSynthesisSettings.normalize(value);
    } catch (_error) { /* 旧版本和损坏配置使用默认值。 */ }
    return new SpeechSynthesisSettings();
  }

  static validRules(text: string): boolean {
    if (text.length > 4096) return false;
    const lines = text.split('\n').filter((line: string): boolean => line.trim().length > 0);
    return lines.length <= 64 && lines.every((line: string): boolean => {
      const at = line.indexOf('=>');
      return at > 0 && line.substring(0, at).trim().length > 0 && at <= 128 && line.length - at - 2 <= 128;
    });
  }

  static replace(text: string, rules: string): string {
    if (!SpeechSynthesisSettings.validRules(rules)) return text;
    for (const line of rules.split('\n')) {
      const at = line.indexOf('=>');
      if (at <= 0) continue;
      text = text.split(line.substring(0, at).trim()).join(line.substring(at + 2).trim());
      if (text.length > 32768) throw new Error('TTS replacement expansion exceeded');
    }
    return text;
  }
}
