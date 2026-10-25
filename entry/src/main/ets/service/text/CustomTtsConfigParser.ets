import { http } from '@kit.NetworkKit';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { CustomTtsTemplate as LocalRuleTemplate } from './CustomTtsTemplate';
import { LocalRuleQuickJsRequest, LocalRuleQuickJsRuntime } from '../rulesource/LocalRuleQuickJsRuntime';

/** JSON 字典仅透传给系统 HTTP API，不作动态属性访问。 */
class TtsHeaders {}
class TtsBody {}
class TtsImportEntry {
  name: string = '';
  enabled: boolean = true;
  url: string = '';
  method: string = '';
  body: string = '';
  header: string | TtsHeaders = '';
  loginUrl: string = '';
  loginUi: string = '';
  loginCheckJs: string = '';
  jsLib: string = '';
  jsEngine: string = '';
  contentType: string = '';
}
class TtsUrlOptions {
  method: string = '';
  body: string | TtsBody = '';
  headers: string | TtsHeaders = '';
  bodyJs: string = '';
  charset: string = '';
}

export class CustomTtsConfigParser {
  static readonly MAX_CONFIGS: number = 100;

  static parse(raw: string): CustomTtsConfig[] {
    if (raw.length > 1024 * 1024) throw new Error('TTS config too large');
    const text = raw.replace(/^\uFEFF/, '').trim();
    const entries: TtsImportEntry[] = JSON.parse(text.startsWith('[') ? text : `[${text}]`);
    if (!Array.isArray(entries) || entries.length === 0 || entries.length > CustomTtsConfigParser.MAX_CONFIGS) {
      throw new Error('Invalid TTS config count');
    }
    return entries.map((entry: TtsImportEntry): CustomTtsConfig => CustomTtsConfigParser.normalize(entry));
  }

  private static normalize(entry: TtsImportEntry): CustomTtsConfig {
    if (!entry || typeof entry.name !== 'string' || !entry.name.trim() || entry.name.length > 100 ||
      typeof entry.url !== 'string' || entry.url.length > 32768 || entry.jsLib || entry.jsEngine ||
      entry.loginUrl || entry.loginUi || entry.loginCheckJs) throw new Error('Unsupported TTS config');
    const config = new CustomTtsConfig();
    config.name = entry.name.trim();
    config.enabled = entry.enabled !== false;
    config.url = entry.url.trim();
    config.method = typeof entry.method === 'string' && entry.method ? entry.method.toUpperCase() : 'GET';
    config.body = typeof entry.body === 'string' ? entry.body : '';
    config.contentType = typeof entry.contentType === 'string' ? entry.contentType : '';
    if (entry.header) config.header = typeof entry.header === 'string' ? entry.header : JSON.stringify(entry.header);
    const optionsAt = CustomTtsConfigParser.optionsIndex(config.url);
    if (optionsAt >= 0) {
      const options: TtsUrlOptions = JSON.parse(config.url.substring(optionsAt + 1));
      if (!options || options.bodyJs || (options.charset && !/^utf-?8$/i.test(options.charset))) {
        throw new Error('Unsupported TTS options');
      }
      config.url = config.url.substring(0, optionsAt).trim();
      if (typeof options.method === 'string') config.method = options.method.toUpperCase();
      if (options.body !== undefined && options.body !== null) {
        config.body = typeof options.body === 'string' ? options.body : JSON.stringify(options.body);
      }
      if (options.headers) {
        const extra = typeof options.headers === 'string' ? options.headers : JSON.stringify(options.headers);
        config.header = CustomTtsConfigParser.mergeHeaders(config.header, extra);
      }
    }
    // 轻页原生 @URL 是 POST，查询串移动为表单请求体。
    if (config.url.startsWith('@')) {
      config.method = 'POST';
      config.url = config.url.substring(1);
      const queryAt = config.url.indexOf('?');
      if (queryAt > 0 && !config.body) {
        config.body = config.url.substring(queryAt + 1);
        config.url = config.url.substring(0, queryAt);
      }
    }
    const headers: TtsHeaders = JSON.parse(config.header);
    if (!headers || typeof headers !== 'object' || Array.isArray(headers) || config.header.length > 16384 ||
      (config.method !== 'GET' && config.method !== 'POST') || config.body.length > 65536 ||
      !/^https?:\/\/[^\s/@]+(?::\d+)?(?:[/?#]|$)/i.test(config.url) ||
      !/\{\{[\s\S]*?\b(speakText|text)\b[\s\S]*?\}\}/.test(config.url + config.body)) {
      throw new Error('Invalid HTTP TTS template');
    }
    CustomTtsConfigParser.templateExpression(config.url, false);
    CustomTtsConfigParser.templateExpression(config.body, false);
    // 无 id 的轻页配置也能稳定去重；不同请求体中的音色独立保留。
    config.id = JSON.stringify([config.name, config.url, config.body]);
    return config;
  }

  private static mergeHeaders(first: string, second: string): string {
    const a = first.trim().slice(1, -1).trim();
    const b = second.trim().slice(1, -1).trim();
    return `{${a}${a && b ? ',' : ''}${b}}`;
  }

  private static optionsIndex(value: string): number {
    for (let index = 0; index < value.length; index++) {
      if (value.substring(index, index + 2) === '{{') {
        const end = LocalRuleTemplate.end(value, index + 2);
        if (end < 0) throw new Error('Invalid TTS template');
        index = end + 1;
      } else if (value.charAt(index) === ',' && /^\s*\{/.test(value.substring(index + 1))) return index;
    }
    return -1;
  }

  private static templateExpression(template: string, encodeText: boolean): string {
    const parts: string[] = [];
    let position = 0;
    let count = 0;
    while (position < template.length) {
      const start = template.indexOf('{{', position);
      if (start < 0) { parts.push(JSON.stringify(template.substring(position))); break; }
      const end = LocalRuleTemplate.end(template, start + 2);
      if (end < 0 || ++count > 64) throw new Error('Invalid TTS template');
      parts.push(JSON.stringify(template.substring(position, start)));
      const code = template.substring(start + 2, end).trim();
      parts.push(encodeText && /^(speakText|text)$/.test(code) ? `encodeURIComponent(${code})` : `String((${code}))`);
      position = end + 2;
    }
    return parts.length > 0 ? parts.join('+') : '""';
  }

  static async expand(template: string, text: string, speed: number, jsonBody: boolean): Promise<string> {
    if (!template.includes('{{')) return template;
    const input = jsonBody ? JSON.stringify(text).slice(1, -1) : text;
    const request = new LocalRuleQuickJsRequest();
    request.sourceUrl = 'custom-tts-template';
    request.timeoutMs = 100;
    request.memoryLimitBytes = 2 * 1024 * 1024;
    request.maxPendingJobs = 0;
    request.script = `(()=>{const speakText=${JSON.stringify(input)},text=speakText;` +
      `const speed=${speed},rate=speed,speechRate=speed,speakSpeed=${Math.max(0, Math.min(20, Math.round(speed * 10)))},` +
      `speakSpeedPercent=${Math.round(speed * 100)};` +
      'const java={encodeURI:(v)=>encodeURIComponent(String(v)),encodeURIComponent:(v)=>encodeURIComponent(String(v))};' +
      `return ${CustomTtsConfigParser.templateExpression(template, !jsonBody)};})()`;
    const result = await LocalRuleQuickJsRuntime.execute(request);
    if (!result.success || result.value.length > 128 * 1024) throw new Error('TTS template failed');
    return result.value;
  }

  static usesSpeed(config: CustomTtsConfig): boolean {
    return /\{\{[^}]*\b(speakSpeed|speakSpeedPercent|speechRate|speed|rate)\b[^}]*\}\}/.test(config.url + config.body);
  }

  static async requestOptions(config: CustomTtsConfig, text: string, speed: number): Promise<http.HttpRequestOptions> {
    const structured = /^[\s]*[\[{]/.test(config.body);
    let headers = config.header;
    if (!/"content-type"\s*:/i.test(headers) && config.method === 'POST') {
      headers = CustomTtsConfigParser.mergeHeaders(headers, structured ? '{"Content-Type":"application/json; charset=utf-8"}' :
        '{"Content-Type":"application/x-www-form-urlencoded; charset=utf-8"}');
    }
    const options: http.HttpRequestOptions = {
      method: config.method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
      header: JSON.parse(headers), expectDataType: http.HttpDataType.ARRAY_BUFFER,
      usingCache: false, connectTimeout: 15000, readTimeout: 45000, maxLimit: 8 * 1024 * 1024
    };
    if (config.method === 'POST') options.extraData = await CustomTtsConfigParser.expand(config.body, text, speed, structured);
    return options;
  }
}
