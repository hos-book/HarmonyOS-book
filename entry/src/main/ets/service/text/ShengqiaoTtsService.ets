import { http } from '@kit.NetworkKit';
import { util, url } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { ShengqiaoVoice } from '../../model/ShengqiaoPlugin';
import { ShengqiaoPluginService } from './ShengqiaoPluginService';
import { concatPcm, parseContainerInfo, shengqiaoWave, splitForTts } from './ShengqiaoPcm';
import { ShengqiaoCeliaApp, ShengqiaoCeliaBody, ShengqiaoCeliaProtocol } from './ShengqiaoCeliaProtocol';

class ShengqiaoTokenReply {
  access_token: string = '';
  refresh_token: string = '';
  expires_in: number = 0;
}

class ShengqiaoEdgeToken {
  t: string = '';
  r: string = '';
}

export class ShengqiaoFailure extends Error {
  readonly reason: string;
  readonly status: number;
  constructor(reason: string, status: number = 0) { super(reason); this.reason = reason; this.status = status; }
}

/** 单次合成持有自己的 HTTP 请求，停止试听与朗读时同步取消。 */
export class ShengqiaoSynthesis {
  private cancelled: boolean = false;
  private requests: Set<http.HttpRequest> = new Set<http.HttpRequest>();
  private timeoutSeconds: number;
  constructor(timeoutSeconds: number = 30) { this.timeoutSeconds = timeoutSeconds; }

  cancel(): void {
    this.cancelled = true;
    this.requests.forEach((request: http.HttpRequest): void => request.destroy());
    this.requests.clear();
  }

  private check(): void { if (this.cancelled) throw new ShengqiaoFailure('shengqiao_cancelled'); }

  async request(url: string, body: string, headers: Record<string, string>, binary: boolean): Promise<string | ArrayBuffer> {
    this.check();
    const request = http.createHttp();
    this.requests.add(request);
    try {
      const options: http.HttpRequestOptions = { method: http.RequestMethod.POST, extraData: body, header: headers,
        expectDataType: binary ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
        usingCache: false, connectTimeout: this.timeoutSeconds * 1000,
        readTimeout: Math.min(480000, this.timeoutSeconds * 4000), maxLimit: 8 * 1024 * 1024 };
      const response = await request.request(url, options);
      this.check();
      if (response.responseCode !== 200) throw new ShengqiaoFailure('shengqiao_http', response.responseCode);
      if (typeof response.result === 'string' || response.result instanceof ArrayBuffer) return response.result;
      throw new ShengqiaoFailure('shengqiao_audio');
    } catch (error) {
      this.check();
      if (error instanceof ShengqiaoFailure) throw error;
      throw new ShengqiaoFailure('shengqiao_network');
    } finally { this.requests.delete(request); request.destroy(); }
  }

  async synthesize(config: CustomTtsConfig, text: string): Promise<ArrayBuffer> {
    const plugin = ShengqiaoPluginService.instance;
    const voice = plugin.voice(config.modelId);
    if (!plugin.state.active || !voice) throw new ShengqiaoFailure('shengqiao_enable_required');
    const started = Date.now();
    plugin.state.voiceName = voice.name;
    try {
      const result = voice.channel === 'celia' ? await this.celia(text, voice) :
        (voice.channel === 'edge' ? await this.edge(text, voice) : await this.huawei(text, voice));
      this.check();
      plugin.state.elapsedMs = Date.now() - started;
      plugin.state.voiceName = voice.name;
      plugin.state.audioBytes = result.byteLength;
      plugin.state.result = $r('app.string.shengqiao_success');
      return result;
    } catch (error) {
      plugin.state.elapsedMs = Date.now() - started;
      plugin.state.voiceName = voice.name;
      plugin.state.audioBytes = 0;
      if (!this.cancelled) plugin.state.result = ShengqiaoTtsService.errorMessage(error);
      if (error instanceof Error) throw error;
      throw new ShengqiaoFailure('shengqiao_audio');
    }
  }

  private async celia(text: string, voice: ShengqiaoVoice): Promise<ArrayBuffer> {
    const token = await ShengqiaoTtsService.instance.celiaToken(this);
    const parts: Uint8Array[] = [];
    for (const chunk of splitForTts(text, 60, 80)) {
      const headers = ShengqiaoCeliaProtocol.headers('startTTS', '10-0');
      headers['token'] = 'Bearer ' + token;
      headers['language'] = 'zh';
      headers['person'] = voice.sid;
      headers['modelId'] = voice.sid;
      const body = new ShengqiaoCeliaBody(ShengqiaoCeliaProtocol.deviceId, voice.sid, chunk);
      const response = await this.request(ShengqiaoCeliaProtocol.host + '/hivoice/v3/tts',
        ShengqiaoCeliaProtocol.multipart(JSON.stringify(body)), headers, true);
      if (!(response instanceof ArrayBuffer)) throw new ShengqiaoFailure('shengqiao_audio');
      const pcm = ShengqiaoCeliaProtocol.audio(new Uint8Array(response));
      if (pcm === null || pcm.length === 0) throw new ShengqiaoFailure('shengqiao_audio');
      parts.push(pcm);
    }
    return shengqiaoWave(concatPcm(parts, voice.sampleRate, 220), voice.sampleRate);
  }

  private async huawei(text: string, voice: ShengqiaoVoice): Promise<ArrayBuffer> {
    const service = ShengqiaoTtsService.instance;
    const token = await service.huaweiToken();
    this.check();
    const chunks = splitForTts(text, 60, 80);
    const parts: Uint8Array[] = [];
    for (const chunk of chunks) {
      parts.push(await this.huaweiChunk(chunk, voice, token, 0));
    }
    return shengqiaoWave(concatPcm(parts, voice.sampleRate, 220), voice.sampleRate);
  }

  private async huaweiChunk(text: string, voice: ShengqiaoVoice, token: string, depth: number): Promise<Uint8Array> {
    this.check();
    const service = ShengqiaoTtsService.instance;
    const now = new Date();
    const pad = (value: number): string => value.toString().padStart(2, '0');
    const timestamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
      `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
    const headers: Record<string, string> = { 'Content-Type': 'application/json; charset=UTF-8',
      'x-country': 'CN', 'x-traceId': service.deviceId.replace('uuid#', '') + '1', 'x-appId': '101', 'x-support-utc': '1',
      'x-appVer': '90551300', 'timestamp': timestamp, 'User-Agent': 'hwread' };
    const body = JSON.stringify(new ShengqiaoHuaweiBody(token, text, voice, service.deviceId, timestamp));
    const response = await this.request(ShengqiaoPluginService.instance.secret(1), body, headers, true);
    if (!(response instanceof ArrayBuffer)) throw new ShengqiaoFailure('shengqiao_audio');
    const parsed = parseContainerInfo(new Uint8Array(response), voice.sampleRate);
    if (parsed.pcm === null || parsed.pcm.length === 0) throw new ShengqiaoFailure('shengqiao_audio');
    if (parsed.hasMp3) {
      if (depth >= 2 || text.length < 2) throw new ShengqiaoFailure('shengqiao_audio');
      const middle = Math.floor(text.length / 2);
      let cut = -1;
      for (const punctuation of '。！？；，、') {
        const index = text.lastIndexOf(punctuation, middle);
        if (index >= 4 && index < text.length - 4) { cut = index; break; }
      }
      if (cut < 0) cut = middle - 1;
      const left = await this.huaweiChunk(text.substring(0, cut + 1), voice, token, depth + 1);
      const right = await this.huaweiChunk(text.substring(cut + 1), voice, token, depth + 1);
      return concatPcm([left, right], voice.sampleRate, 120);
    }
    return parsed.pcm;
  }

  private async edge(text: string, voice: ShengqiaoVoice): Promise<ArrayBuffer> {
    const token = await ShengqiaoTtsService.instance.edgeToken();
    this.check();
    const escaped = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
    const content = voice.style ? `<mstts:express-as style="${voice.style}">${escaped}</mstts:express-as>` : escaped;
    const ssml = '<speak xmlns="http://www.w3.org/2001/10/synthesis" xmlns:mstts="http://www.w3.org/2001/mstts" ' +
      `version="1.0" xml:lang="zh-CN"><voice name="${voice.sid}" ` +
      `parameters="enhancePronunciation=true;temperature=0.7">${content}</voice></speak>`;
    const headers: Record<string, string> = { 'Authorization': 'Bearer ' + token.t,
      'Content-Type': 'application/ssml+xml', 'User-Agent': 'okhttp/4.5.0',
      'X-Microsoft-OutputFormat': 'audio-48khz-192kbitrate-mono-mp3' };
    const response = await this.request(`https://${token.r}.tts.speech.microsoft.com/cognitiveservices/v1`, ssml, headers, true);
    if (!(response instanceof ArrayBuffer) || response.byteLength === 0) throw new ShengqiaoFailure('shengqiao_audio');
    return response;
  }
}

class ShengqiaoHuaweiUser {
  accessToken: string;
  accountType: number = 0;
  rcmMode: number = 1;
  userId: string = '1';
  constructor(token: string) { this.accessToken = token; }
}
class ShengqiaoHuaweiConfig {
  volume: number = 200;
  outputEncoderFormat: number = 0;
  pitch: number = 100;
  type: number = 2;
  sampleRate: number;
  speed: number = 116;
  playSpeed: string = '1.0';
  constructor(rate: number) { this.sampleRate = rate; }
}
class ShengqiaoCoordinate { spChapterId: string = ''; dompos: string = ''; chapterFilePath: string = ''; bookId: string = ''; }
class ShengqiaoHuaweiData {
  config: ShengqiaoHuaweiConfig;
  coordinate: ShengqiaoCoordinate = new ShengqiaoCoordinate();
  speakerId: string;
  text: string;
  constructor(text: string, voice: ShengqiaoVoice) {
    this.config = new ShengqiaoHuaweiConfig(voice.sampleRate); this.speakerId = voice.sid; this.text = text;
  }
}
class ShengqiaoHuaweiApp {
  appId: string = '101'; appVer: string = '90551300'; beId: string = '10010001';
  country: string = 'CN'; i18n: string = 'zh_CN'; packageName: string = 'com.huawei.hwread.dz';
}
class ShengqiaoHuaweiDevice {
  deviceId: string; uuid: string; deviceIdType: string = '11'; emuiVer: string = '0';
  handsetManufacturer: string = 'HUAWEI'; hansetBrand: string = 'HUAWEI'; romVer: string = 'V417IR release-keys';
  terminalType: string = 'DCO-AL00';
  constructor(id: string) { this.deviceId = id; this.uuid = id; }
}
class ShengqiaoHuaweiBody {
  userInfo: ShengqiaoHuaweiUser;
  data: ShengqiaoHuaweiData;
  reqTimestamp: string;
  appInfo: ShengqiaoHuaweiApp = new ShengqiaoHuaweiApp();
  deviceInfo: ShengqiaoHuaweiDevice;
  constructor(token: string, text: string, voice: ShengqiaoVoice, id: string, timestamp: string) {
    this.userInfo = new ShengqiaoHuaweiUser(token); this.data = new ShengqiaoHuaweiData(text, voice);
    this.deviceInfo = new ShengqiaoHuaweiDevice(id); this.reqTimestamp = timestamp;
  }
}

/** 华为令牌续期与微软换票沿用声桥协议，播放倍速由现有播放器处理。 */
export class ShengqiaoTtsService {
  static readonly instance: ShengqiaoTtsService = new ShengqiaoTtsService();
  static readonly REDIRECT: string = 'http://localhost:9382/callback';
  readonly deviceId: string = 'uuid#' + util.generateRandomUUID(false).replace(/-/g, '');
  private access: string = '';
  private accessExpires: number = 0;
  private credentialUsed: string = '';
  private huaweiPending: Promise<string> | null = null;
  private edgeAccess: ShengqiaoEdgeToken | null = null;
  private edgeExpires: number = 0;
  private edgePending: Promise<ShengqiaoEdgeToken> | null = null;
  private celiaAccess: string = '';
  private celiaExpires: number = 0;
  private oauthState: string = '';

  authorizationUrl(): string {
    this.oauthState = util.generateRandomUUID(false);
    return 'https://oauth-login.cloud.huawei.com/oauth2/v3/authorize?client_id=' +
      encodeURIComponent(ShengqiaoPluginService.instance.secret(3)) + '&response_type=code&redirect_uri=' +
      encodeURIComponent(ShengqiaoTtsService.REDIRECT) + '&scope=openid%20profile&access_type=offline&state=' + this.oauthState;
  }

  async completeAuthorization(callback: string): Promise<void> {
    const callbackUrl = url.URL.parseURL(callback);
    const code = callbackUrl.params.get('code');
    if (!code || callbackUrl.params.get('state') !== this.oauthState) throw new ShengqiaoFailure('shengqiao_login_failed');
    await this.tokenRequest('grant_type=authorization_code&code=' + encodeURIComponent(code) +
      '&redirect_uri=' + encodeURIComponent(ShengqiaoTtsService.REDIRECT));
    this.oauthState = '';
  }

  private async tokenRequest(grant: string, refreshCredential: string = ''): Promise<string> {
    const plugin = ShengqiaoPluginService.instance;
    const body = grant + '&client_id=' + encodeURIComponent(plugin.secret(3)) + '&client_secret=' + encodeURIComponent(plugin.secret(0));
    const headers: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'User-Agent': 'Mozilla/5.0' };
    const raw = await new ShengqiaoSynthesis().request(plugin.secret(2), body, headers, false);
    if (typeof raw !== 'string') throw new ShengqiaoFailure('shengqiao_login_failed');
    const token: ShengqiaoTokenReply = JSON.parse(raw);
    const refresh = token.refresh_token || refreshCredential;
    if (!token.access_token || !refresh) throw new ShengqiaoFailure('shengqiao_login_failed');
    if (token.refresh_token) await plugin.saveCredential(token.refresh_token);
    this.access = token.access_token;
    this.credentialUsed = refresh;
    this.accessExpires = Date.now() + Number(token.expires_in) * 1000;
    return this.access;
  }

  async huaweiToken(): Promise<string> {
    const credential = ShengqiaoPluginService.instance.refreshCredential();
    if (!credential) throw new ShengqiaoFailure('shengqiao_login_required');
    if (this.credentialUsed === credential && this.access && Date.now() < this.accessExpires - 300000) return this.access;
    if (this.huaweiPending === null) this.huaweiPending = this.tokenRequest('grant_type=refresh_token&refresh_token=' + encodeURIComponent(credential), credential);
    try { return await this.huaweiPending; }
    finally { this.huaweiPending = null; }
  }

  async celiaToken(synthesis: ShengqiaoSynthesis): Promise<string> {
    if (this.celiaAccess && Date.now() < this.celiaExpires) return this.celiaAccess;
    const plugin = ShengqiaoPluginService.instance;
    const body = new ShengqiaoCeliaApp(plugin.secret(5), plugin.secret(6));
    const raw = await synthesis.request(ShengqiaoCeliaProtocol.host + '/auth/v3/generateToken',
      ShengqiaoCeliaProtocol.multipart(JSON.stringify(body)), ShengqiaoCeliaProtocol.headers('generateToken', ''), false);
    if (typeof raw !== 'string') throw new ShengqiaoFailure('shengqiao_login_failed');
    const token = /"accessToken"\s*:\s*"([^"]+)"/.exec(raw);
    if (token === null) throw new ShengqiaoFailure('shengqiao_login_failed');
    this.celiaAccess = token[1];
    this.celiaExpires = Date.now() + 12 * 60 * 60 * 1000;
    return this.celiaAccess;
  }

  async edgeToken(): Promise<ShengqiaoEdgeToken> {
    if (this.edgeAccess !== null && Date.now() < this.edgeExpires) return this.edgeAccess;
    if (this.edgePending === null) this.edgePending = this.fetchEdgeToken();
    try { return await this.edgePending; }
    finally { this.edgePending = null; }
  }

  private async fetchEdgeToken(): Promise<ShengqiaoEdgeToken> {
    const url = 'https://dev.microsofttranslator.com/apps/endpoint?api-version=1.0';
    const id = util.generateRandomUUID(false).replace(/-/g, '');
    const date = new Date().toUTCString();
    const message = ('MSTranslatorAndroidApp' + encodeURIComponent(url.split('://')[1]) + date + id).toLowerCase();
    const generator = cryptoFramework.createSymKeyGenerator('HMAC');
    const key = await generator.convertKey({ data: new util.Base64Helper().decodeSync(ShengqiaoPluginService.instance.secret(4)) });
    const signer = cryptoFramework.createMac('SHA256');
    await signer.init(key);
    await signer.update({ data: new util.TextEncoder().encodeInto(message) });
    const signature = new util.Base64Helper().encodeToStringSync((await signer.doFinal()).data);
    const headers: Record<string, string> = { 'Accept-Language': 'zh-Hans', 'X-ClientVersion': '4.0.530a 5fe1dc6c',
      'X-UserId': id, 'X-HomeGeographicRegion': 'zh-Hans-CN', 'X-ClientTraceId': id,
      'X-MT-Signature': `MSTranslatorAndroidApp::${signature}::${date}::${id}`, 'User-Agent': 'okhttp/4.5.0',
      'Content-Type': 'application/json; charset=utf-8' };
    const raw = await new ShengqiaoSynthesis().request(url, '{}', headers, false);
    if (typeof raw !== 'string') throw new ShengqiaoFailure('shengqiao_login_failed');
    const token: ShengqiaoEdgeToken = JSON.parse(raw);
    if (!token.t || !token.r) throw new ShengqiaoFailure('shengqiao_login_failed');
    this.edgeAccess = token; this.edgeExpires = Date.now() + 8 * 60 * 1000;
    return token;
  }

  static errorMessage(error: Error): ResourceStr {
    if (error instanceof ShengqiaoFailure && error.reason === 'shengqiao_http') return $r('app.string.shengqiao_http', error.status);
    if (error instanceof ShengqiaoFailure && error.reason === 'shengqiao_login_failed') return $r('app.string.shengqiao_login_failed');
    if (error instanceof ShengqiaoFailure && error.reason === 'shengqiao_network') return $r('app.string.tts_error_network');
    if (error instanceof ShengqiaoFailure && error.reason === 'shengqiao_login_required') return $r('app.string.shengqiao_login_required');
    if (error instanceof ShengqiaoFailure && error.reason === 'shengqiao_enable_required') return $r('app.string.shengqiao_enable_required');
    if (error instanceof ShengqiaoFailure && error.reason === 'shengqiao_audio') return $r('app.string.shengqiao_audio_error');
    return $r('app.string.shengqiao_operation_failed');
  }
}
