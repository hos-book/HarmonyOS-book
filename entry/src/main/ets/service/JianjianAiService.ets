import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util, url } from '@kit.ArkTS';
import { rcp } from '@kit.RemoteCommunicationKit';
import { JianjianAiConfig, JianjianAiMessage, JianjianAiError, JianjianAiErrorCode } from '../model/JianjianAi';

class ModelEntry { id: string = ''; }
class ModelsResponse { data: ModelEntry[] = []; }
class ReplyMessage { content: string = ''; refusal: string = ''; }
class ReplyChoice { message: ReplyMessage = new ReplyMessage(); }
class ChatResponse { choices: ReplyChoice[] = []; }
class ChatRequest {
  model: string = '';
  messages: JianjianAiMessage[] = [];
  stream: boolean = false;
}

/** Each page owns its cancellable connection. Credentials are excluded from exported backups. */
export class JianjianAiService {
  private session: rcp.Session | undefined = undefined;
  private generation: number = 0;

  private static async store(context: common.Context): Promise<relationalStore.RdbStore> {
    const store = await relationalStore.getRdbStore(context, { name: 'jianjian_ai.db',
      securityLevel: relationalStore.SecurityLevel.S2, encrypt: true, allowRebuild: false });
    await store.executeSql('CREATE TABLE IF NOT EXISTS config (id INTEGER PRIMARY KEY, address TEXT, api_key TEXT, model TEXT)');
    return store;
  }

  static async loadConfig(context: common.Context): Promise<JianjianAiConfig> {
    const store = await JianjianAiService.store(context);
    const rows = await store.querySql('SELECT address, api_key, model FROM config WHERE id = 1');
    try {
      const config = new JianjianAiConfig();
      if (rows.goToFirstRow()) {
        config.address = rows.getString(0);
        config.apiKey = rows.getString(1);
        config.model = rows.getString(2);
      }
      return config;
    } finally { rows.close(); }
  }

  static async saveConfig(context: common.Context, config: JianjianAiConfig): Promise<void> {
    const valid = JianjianAiService.normalize(config, true);
    const store = await JianjianAiService.store(context);
    await store.executeSql('INSERT OR REPLACE INTO config (id, address, api_key, model) VALUES (1, ?, ?, ?)',
      [valid.address, valid.apiKey, valid.model]);
  }

  static async clearConfig(context: common.Context): Promise<void> {
    const store = await JianjianAiService.store(context);
    await store.executeSql('DELETE FROM config');
  }

  static normalize(config: JianjianAiConfig, requireModel: boolean = false): JianjianAiConfig {
    const valid = new JianjianAiConfig();
    try {
      const parsed = url.URL.parseURL(config.address.trim());
      if (!['https:', 'http:'].includes(parsed.protocol) || !parsed.hostname || parsed.username || parsed.password ||
        parsed.search || parsed.hash || config.address.length > 2048) throw new Error('Invalid address');
      let path = parsed.pathname.replace(/\/+$/, '');
      // Accept an API base or a pasted endpoint, preserving provider-specific prefixes.
      path = path.replace(/\/(chat\/completions|models)$/, '');
      if (!path) path = '/v1';
      valid.address = parsed.origin + path;
      valid.apiKey = config.apiKey.trim();
      valid.model = config.model.trim();
      if (!valid.apiKey || valid.apiKey.length > 4096 || /[\r\n]/.test(valid.apiKey)) throw new Error('Invalid key');
    } catch (_error) { throw new JianjianAiError(JianjianAiErrorCode.CONFIG); }
    if (requireModel && (!valid.model || valid.model.length > 512 || /[\r\n]/.test(valid.model))) {
      throw new JianjianAiError(JianjianAiErrorCode.MODEL);
    }
    return valid;
  }

  static parseModels(body: string): string[] {
    try {
      const response: ModelsResponse = JSON.parse(body);
      if (!response || !Array.isArray(response.data)) throw new Error('Invalid models');
      const ids: Set<string> = new Set<string>();
      for (const entry of response.data) {
        if (entry && typeof entry.id === 'string' && entry.id.trim() && entry.id.length <= 512 && !/[\r\n]/.test(entry.id)) {
          ids.add(entry.id.trim());
        }
      }
      return Array.from(ids).sort();
    } catch (_error) { throw new JianjianAiError(JianjianAiErrorCode.INVALID); }
  }

  static parseReply(body: string): string {
    try {
      const response: ChatResponse = JSON.parse(body);
      if (!response || !Array.isArray(response.choices) || !response.choices.length) throw new Error('Invalid choices');
      const message = response.choices[0]?.message;
      const text = message && typeof message.content === 'string' ? message.content.trim() : '';
      const refusal = message && typeof message.refusal === 'string' ? message.refusal.trim() : '';
      if (!text && !refusal) throw new Error('Empty reply');
      if ((text || refusal).length > 32000) throw new JianjianAiError(JianjianAiErrorCode.TOO_LARGE);
      return text || refusal;
    } catch (error) {
      if (error instanceof JianjianAiError) throw error;
      throw new JianjianAiError(JianjianAiErrorCode.INVALID);
    }
  }

  async listModels(config: JianjianAiConfig): Promise<string[]> {
    const valid = JianjianAiService.normalize(config);
    return JianjianAiService.parseModels(await this.send(valid, '/models', 'GET', ''));
  }

  async chat(config: JianjianAiConfig, messages: JianjianAiMessage[], prompt: string): Promise<string> {
    const valid = JianjianAiService.normalize(config, true);
    const request = new ChatRequest();
    request.model = valid.model;
    request.messages = [new JianjianAiMessage('system', prompt)];
    // Bound conversation independently of displayed history. Book mode supplies only its bounded, user-invoked evidence.
    let characters = 0;
    const recent: JianjianAiMessage[] = [];
    for (let index = messages.length - 1; index >= 0 && recent.length < 20; index--) {
      const item = messages[index];
      if (!['user', 'assistant'].includes(item.role) || !item.content.trim()) continue;
      if (characters + item.content.length > 24000) break;
      recent.unshift(new JianjianAiMessage(item.role, item.content));
      characters += item.content.length;
    }
    while (recent.length > 0 && recent[0].role !== 'user') recent.shift();
    if (!recent.length || recent[recent.length - 1].role !== 'user') throw new JianjianAiError(JianjianAiErrorCode.INVALID);
    request.messages.push(...recent);
    return JianjianAiService.parseReply(await this.send(valid, '/chat/completions', 'POST', JSON.stringify(request)));
  }

  cancel(): void {
    this.generation++;
    this.session?.close();
    this.session = undefined;
  }

  private async send(config: JianjianAiConfig, path: string, method: string, body: string): Promise<string> {
    this.cancel();
    const generation = this.generation;
    const session = rcp.createSession();
    this.session = session;
    const headers: Record<string, string> = { 'Authorization': `Bearer ${config.apiKey}`,
      'Content-Type': 'application/json', 'Accept': 'application/json' };
    const request = new rcp.Request(config.address + path, method, headers, body || undefined);
    request.configuration = { transfer: { autoRedirect: false, timeout: { connectMs: 15000, transferMs: 60000 } },
      security: { remoteValidation: 'system' } };
    const chunks: Uint8Array[] = [];
    let total: number = 0;
    let oversized: boolean = false;
    request.destination = (chunk: ArrayBuffer): void => {
      total += chunk.byteLength;
      if (total > 2 * 1024 * 1024) { oversized = true; session.close(); return; }
      chunks.push(new Uint8Array(chunk));
    };
    try {
      const response = await session.fetch(request);
      if (generation !== this.generation) throw new JianjianAiError(JianjianAiErrorCode.CANCELLED);
      if (oversized) throw new JianjianAiError(JianjianAiErrorCode.TOO_LARGE);
      const status = response.statusCode;
      if (status === 401 || status === 403) throw new JianjianAiError(JianjianAiErrorCode.AUTH, status);
      if (status === 404 || status === 405) throw new JianjianAiError(JianjianAiErrorCode.ENDPOINT, status);
      if (status === 429) throw new JianjianAiError(JianjianAiErrorCode.LIMIT, status);
      if (status < 200 || status >= 300) throw new JianjianAiError(JianjianAiErrorCode.SERVER, status);
      const bytes = new Uint8Array(total);
      let offset: number = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      return util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch (error) {
      if (generation !== this.generation) throw new JianjianAiError(JianjianAiErrorCode.CANCELLED);
      if (oversized) throw new JianjianAiError(JianjianAiErrorCode.TOO_LARGE);
      if (error instanceof JianjianAiError) throw error;
      throw new JianjianAiError(JianjianAiErrorCode.NETWORK);
    } finally {
      session.close();
      if (this.session === session) this.session = undefined;
    }
  }

  static errorText(error: Error): ResourceStr {
    const code = error instanceof JianjianAiError ? error.code : JianjianAiErrorCode.SERVER;
    switch (code) {
      case JianjianAiErrorCode.CONFIG: return $r('app.string.jianjian_ai_config_invalid');
      case JianjianAiErrorCode.MODEL: return $r('app.string.jianjian_ai_choose_model');
      case JianjianAiErrorCode.AUTH: return $r('app.string.jianjian_ai_auth_error');
      case JianjianAiErrorCode.ENDPOINT: return $r('app.string.jianjian_ai_endpoint_error');
      case JianjianAiErrorCode.LIMIT: return $r('app.string.jianjian_ai_limit_error');
      case JianjianAiErrorCode.NETWORK: return $r('app.string.jianjian_ai_network_error');
      case JianjianAiErrorCode.INVALID: return $r('app.string.jianjian_ai_response_error');
      case JianjianAiErrorCode.TOO_LARGE: return $r('app.string.jianjian_ai_too_large');
      case JianjianAiErrorCode.CANCELLED: return $r('app.string.jianjian_ai_cancelled');
      default: return $r('app.string.jianjian_ai_server_error', error instanceof JianjianAiError ? error.status : 0);
    }
  }
}
