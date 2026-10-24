import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { rcp } from '@kit.RemoteCommunicationKit';
import { url, util } from '@kit.ArkTS';
import { ComicAiConfig, ComicAiModelPage } from '../model/ComicAiConfig';

class ComicAiImageResult {
  b64_json: string = '';
  url: string = '';
}

class ComicAiImageResponse {
  data: ComicAiImageResult[] = [];
}

/** 用户自己的图片 API 配置，与书源及可选音频服务完全独立；密钥不进入偏好备份。 */
export class ComicAiConfigService {
  private static opening: Promise<relationalStore.RdbStore> | null = null;
  static revision: number = 0;

  static normalizeBase(raw: string): string {
    let value = raw.trim().replace(/\/+$/, '');
    if (!value || value.length > 2048) throw new Error('comic_ai_invalid_url');
    try {
      const parsed = new url.URL(value);
      if (!['https:', 'http:'].includes(parsed.protocol) || !parsed.hostname || parsed.username ||
        parsed.password || parsed.search || parsed.hash) throw new Error('invalid');
      value = parsed.href.replace(/\/+$/, '');
    } catch (_error) { throw new Error('comic_ai_invalid_url'); }
    if (value.endsWith('/models')) value = value.substring(0, value.length - 7);
    return value.endsWith('/v1') ? value : `${value}/v1`;
  }

  static validate(config: ComicAiConfig): ComicAiConfig {
    const result = new ComicAiConfig();
    result.baseUrl = ComicAiConfigService.normalizeBase(config.baseUrl);
    result.apiKey = config.apiKey.trim();
    result.model = config.model.trim();
    result.models = Array.from(new Set<string>(config.models.filter((item: string): boolean =>
      typeof item === 'string' && item.length > 0 && item.length <= 256)));
    if (result.models.length > 10000) throw new Error('comic_ai_models_too_large');
    if (!result.apiKey || result.apiKey.length > 4096 || /[\r\n]/.test(result.apiKey)) {
      throw new Error('comic_ai_invalid_key');
    }
    if (result.model.length > 256 || /[\r\n]/.test(result.model)) throw new Error('comic_ai_invalid_model');
    return result;
  }

  private static async open(context: common.Context): Promise<relationalStore.RdbStore> {
    const config: relationalStore.StoreConfig = {
      name: 'comic_ai.db', securityLevel: relationalStore.SecurityLevel.S2, encrypt: true, allowRebuild: false
    };
    const store = await relationalStore.getRdbStore(context, config);
    await store.execute('CREATE TABLE IF NOT EXISTS api_config (id INTEGER PRIMARY KEY, base_url TEXT NOT NULL, ' +
      'api_key TEXT NOT NULL, model TEXT NOT NULL, model_list TEXT NOT NULL DEFAULT \'[]\')');
    const columns = await store.querySql('PRAGMA table_info(api_config)');
    let hasModels = false;
    try { while (columns.goToNextRow()) { if (columns.getString(1) === 'model_list') hasModels = true; } }
    finally { columns.close(); }
    if (!hasModels) await store.execute('ALTER TABLE api_config ADD COLUMN model_list TEXT NOT NULL DEFAULT \'[]\'');
    return store;
  }

  private static async database(context: common.Context): Promise<relationalStore.RdbStore> {
    if (ComicAiConfigService.opening === null) ComicAiConfigService.opening = ComicAiConfigService.open(context);
    try { return await ComicAiConfigService.opening; }
    catch (_error) { ComicAiConfigService.opening = null; throw new Error('comic_ai_storage_failed'); }
  }

  static async load(context: common.Context): Promise<ComicAiConfig> {
    const store = await ComicAiConfigService.database(context);
    const rows = await store.querySql(`SELECT base_url, api_key, model, model_list FROM api_config WHERE id = 1`);
    try {
      const config = new ComicAiConfig();
      if (rows.goToFirstRow()) {
        config.baseUrl = rows.getString(0);
        config.apiKey = rows.getString(1);
        config.model = rows.getString(2);
        try {
          const models: string[] = JSON.parse(rows.getString(3));
          if (Array.isArray(models) && models.length <= 10000) config.models = models.filter((item: string): boolean =>
            typeof item === 'string' && item.length > 0 && item.length <= 256);
        } catch (_error) { /* 旧列表损坏时允许重新获取，不丢失用户密钥和所选模型。 */ }
      }
      return config;
    } finally { rows.close(); }
  }

  static async save(context: common.Context, draft: ComicAiConfig): Promise<void> {
    const config = ComicAiConfigService.validate(draft);
    const store = await ComicAiConfigService.database(context);
    const values: relationalStore.ValuesBucket = {
      id: 1, base_url: config.baseUrl, api_key: config.apiKey, model: config.model,
      model_list: JSON.stringify(config.models)
    };
    await store.insert('api_config', values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    ComicAiConfigService.revision++;
  }

  static async clear(context: common.Context): Promise<void> {
    const store = await ComicAiConfigService.database(context);
    await store.execute(`DELETE FROM api_config WHERE id = 1`);
    ComicAiConfigService.revision++;
  }

  /** 候选提示仅根据名称，不将模型列表当作图片编辑能力证明。 */
  static imageCandidate(model: string): boolean {
    return /gpt-image|image[-_ ]edit|flux.*kontext|qwen.*image.*edit|gemini.*image/i.test(model);
  }

  static async models(draft: ComicAiConfig, cancelled: () => boolean): Promise<string[]> {
    const config = ComicAiConfigService.validate(draft);
    const models = new Set<string>();
    const cursors = new Set<string>();
    let cursor = '';
    for (let index = 0; index < 100; index++) {
      if (cancelled()) throw new Error('comic_ai_cancelled');
      const address = `${config.baseUrl}/models${cursor ? `?after=${encodeURIComponent(cursor)}` : ''}`;
      const body = await ComicAiConfigService.request(address, config.apiKey, cancelled);
      let page: ComicAiModelPage;
      try { page = JSON.parse(body); } catch (_error) { throw new Error('comic_ai_invalid_response'); }
      if (!page || !Array.isArray(page.data)) throw new Error('comic_ai_invalid_response');
      for (const model of page.data) {
        if (model && typeof model.id === 'string' && model.id.trim() && model.id.length <= 256) models.add(model.id);
      }
      if (models.size > 10000) throw new Error('comic_ai_models_too_large');
      if (page.has_more !== true) {
        return Array.from(models).sort((a: string, b: string): number => {
          const priority = Number(ComicAiConfigService.imageCandidate(b)) - Number(ComicAiConfigService.imageCandidate(a));
          return priority || a.localeCompare(b);
        });
      }
      cursor = typeof page.last_id === 'string' && page.last_id ? page.last_id : page.data[page.data.length - 1]?.id ?? '';
      if (!cursor || cursors.has(cursor)) throw new Error('comic_ai_invalid_response');
      cursors.add(cursor);
    }
    throw new Error('comic_ai_models_too_large');
  }

  private static async request(address: string, apiKey: string, cancelled: () => boolean): Promise<string> {
    const bytes = await ComicAiConfigService.requestBytes(address, apiKey, cancelled, 2 * 1024 * 1024);
    return new util.TextDecoder('utf-8').decodeWithStream(bytes, { stream: false });
  }

  static async edit(draft: ComicAiConfig, jpeg: ArrayBuffer, cancelled: () => boolean): Promise<Uint8Array> {
    const config = ComicAiConfigService.validate(draft);
    if (!config.model) throw new Error('comic_ai_invalid_model');
    const boundary = `ComicAiBoundary${Date.now()}`;
    const prompt = 'Colorize this black-and-white comic page. Preserve all original line art, panel layout, ' +
      'characters, facial features, text, speech balloons and dimensions. Add natural restrained colors only. ' +
      'Do not redraw, crop, add, remove or translate anything. Return only the colored image.';
    const prefix = new util.TextEncoder().encodeInto(
      `--${boundary}\r\nContent-Disposition: form-data; name="model"\r\n\r\n${config.model}\r\n` +
      `--${boundary}\r\nContent-Disposition: form-data; name="prompt"\r\n\r\n${prompt}\r\n` +
      `--${boundary}\r\nContent-Disposition: form-data; name="n"\r\n\r\n1\r\n` +
      `--${boundary}\r\nContent-Disposition: form-data; name="image"; filename="page.jpg"\r\nContent-Type: image/jpeg\r\n\r\n`);
    const suffix = new util.TextEncoder().encodeInto(`\r\n--${boundary}--\r\n`);
    const bodyBuffer = new ArrayBuffer(prefix.length + jpeg.byteLength + suffix.length);
    const body = new Uint8Array(bodyBuffer);
    body.set(prefix); body.set(new Uint8Array(jpeg), prefix.length); body.set(suffix, prefix.length + jpeg.byteLength);
    const bytes = await ComicAiConfigService.requestBytes(`${config.baseUrl}/images/edits`, config.apiKey,
      cancelled, 16 * 1024 * 1024, bodyBuffer, `multipart/form-data; boundary=${boundary}`);
    let parsed: ComicAiImageResponse;
    try { parsed = JSON.parse(new util.TextDecoder('utf-8').decodeWithStream(bytes, { stream: false })); }
    catch (_error) { throw new Error('comic_ai_invalid_image'); }
    if (!parsed || !Array.isArray(parsed.data) || !parsed.data[0]) throw new Error('comic_ai_invalid_image');
    const item = parsed.data[0];
    if (typeof item.b64_json === 'string' && item.b64_json.length > 0) {
      if (item.b64_json.length > 12 * 1024 * 1024) throw new Error('comic_ai_image_too_large');
      try { return new util.Base64Helper().decodeSync(item.b64_json); }
      catch (_error) { throw new Error('comic_ai_invalid_image'); }
    }
    // 图片 CDN 请求绝不携带 API Key，也不跟随重定向。
    if (typeof item.url !== 'string' || !item.url.startsWith('https://') || item.url.length > 8192) {
      throw new Error('comic_ai_invalid_image');
    }
    try {
      const address = new url.URL(item.url);
      if (address.username || address.password) throw new Error('invalid');
    } catch (_error) { throw new Error('comic_ai_invalid_image'); }
    return ComicAiConfigService.requestBytes(item.url, '', cancelled, 8 * 1024 * 1024);
  }

  private static async requestBytes(address: string, apiKey: string, cancelled: () => boolean, limit: number,
    body?: ArrayBuffer, contentType: string = ''): Promise<Uint8Array> {
    if (cancelled()) throw new Error('comic_ai_cancelled');
    const session = rcp.createSession();
    const headers: rcp.RequestHeaders = {
      Accept: 'application/json', 'User-Agent': 'Mozilla/5.0'
    };
    if (apiKey) headers.Authorization = `Bearer ${apiKey}`;
    if (contentType) headers['Content-Type'] = contentType;
    const request = new rcp.Request(address, body ? 'POST' : 'GET', headers, body);
    const chunks: ArrayBuffer[] = [];
    let size = 0;
    let overflow = false;
    request.configuration = {
      transfer: { autoRedirect: false, timeout: { connectMs: 15000, transferMs: body ? 120000 : 25000 } },
      tracing: { httpEventsHandler: { onDataReceive: (chunk: ArrayBuffer): void => {
        size += chunk.byteLength;
        if (size > limit) { overflow = true; session.cancel(request); return; }
        chunks.push(chunk);
      } } }
    };
    const timer = setInterval((): void => { if (cancelled()) session.cancel(request); }, 200);
    try {
      const response = await session.fetch(request);
      if (cancelled()) throw new Error('comic_ai_cancelled');
      if (response.statusCode === 401) throw new Error('comic_ai_unauthorized');
      if (response.statusCode === 403) throw new Error('comic_ai_forbidden');
      if (response.statusCode === 404) throw new Error('comic_ai_not_found');
      if (response.statusCode === 429) throw new Error('comic_ai_rate_limited');
      if (body && response.statusCode === 400) throw new Error('comic_ai_edit_unsupported');
      if (body && response.statusCode === 503) throw new Error('comic_ai_model_unavailable');
      if (response.statusCode < 200 || response.statusCode >= 300) throw new Error('comic_ai_request_failed');
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(new Uint8Array(chunk), offset); offset += chunk.byteLength; }
      return bytes;
    } catch (error) {
      if (cancelled()) throw new Error('comic_ai_cancelled');
      if (overflow) throw new Error(body || !apiKey ? 'comic_ai_image_too_large' : 'comic_ai_models_too_large');
      // 不向 UI 或日志传递第三方错误体，避免网关回显密钥。
      if (error instanceof Error && /^comic_ai_[a-z_]+$/.test(error.message)) throw error;
      throw new Error('comic_ai_request_failed');
    } finally { clearInterval(timer); session.close(); }
  }
}
