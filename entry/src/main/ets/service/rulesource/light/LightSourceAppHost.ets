import { WebEngineGate } from '../../WebEngineGate';
import { LightNativeParserService } from './LightNativeParserService';
import { LocalRuleWebSession } from '../LocalRuleWebSession';
import { LightSourceHost, LightLocalSource } from './LightSourceHost';
import { LightSourceSandbox } from './LightSourceSandbox';
import { LocalRuleSource } from '../../../model/LocalRuleSource';
import { LocalRuleSourceRepository } from '../LocalRuleSourceRepository';
import { LocalRuleSourceCodec } from '../LocalRuleSourceCodec';
import { LocalRuleBrowserLoginCoordinator } from '../LocalRuleBrowserLoginCoordinator';
import { LightSourceCookies as LocalRuleHttpClient } from './LightSourceCookies';
import { promptAction } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';
import { SourceDataService } from '../../SourceDataService';
import { EVT_HOME_SOURCE_CHANGED } from '../../PreferenceService';
import { LocalRulePanelService } from '../LocalRulePanelService';

class NativeBrowserLoginCheck {
  check: Object | undefined = undefined;
}
class NativeBrowserDefinition {
  login: NativeBrowserLoginCheck | undefined = undefined;
}

export class LightSourceAppHost implements LightSourceHost {
  parseNative(input: string, cancelled: () => boolean, priority: number): Promise<string> {
    return LightNativeParserService.run(input, cancelled, priority);
  }
  keepWebSession: boolean = false;
  constructor(keepWebSession: boolean = false) { this.keepWebSession = keepWebSession; }
  async acquireWeb(): Promise<number> {
    WebEngineGate.instance.needRuleBrowser = true;
    return LocalRuleWebSession.acquire(20000);
  }
  releaseWeb(lease: number): void { LocalRuleWebSession.release(lease); }
  static serialize(source: LocalRuleSource, keepWebSession: boolean = false): string {
    const local = new LightLocalSource();
    local.keepWebSession = keepWebSession;
    local.bookSourceUrl = source.bookSourceUrl;
    local.variable = source.variable;
    local.definition = LocalRuleSourceCodec.stringify(source);
    local.rawSourceJson = JSON.stringify(source);
    local.engine = source.engine;
    local.enabledExplore = source.enabledExplore;
    return JSON.stringify(local);
  }
  async evaluate(script: string, sourceUrl: string, timingId: number = 0): Promise<string> {
    return LightSourceSandbox.evaluate(script, sourceUrl, timingId);
  }
  async evaluateNative(script: string, sourceUrl: string, timeoutMs: number): Promise<string> {
    return LightSourceSandbox.evaluateNative(script, sourceUrl, timeoutMs);
  }
  async evaluateNativeHost(script: string, sourceUrl: string, timeoutMs: number,
    handler: (name: string, payload: string) => Promise<string>, check: () => void): Promise<string> {
    return LightSourceSandbox.evaluateNativeHost(script, sourceUrl, timeoutMs, handler, check);
  }
  async evaluateImage(script: string, input: Uint8Array, cancelled: () => boolean): Promise<Uint8Array> {
    return LightSourceSandbox.evaluateImage(script, input, cancelled);
  }
  toast(message: string): void {
    promptAction.showToast({message:message.substring(0, 512)});
  }
  async refreshExplore(sourceUrl: string): Promise<void> {
    SourceDataService.invalidateLocalSources(sourceUrl);
    emitter.emit(EVT_HOME_SOURCE_CHANGED);
  }
  async openBrowser(sourceUrl: string, sourceName: string, address: string): Promise<void> {
    LocalRuleBrowserLoginCoordinator.open(sourceUrl, sourceName, address);
  }
  cancelBrowser(sourceUrl: string): void {
    LocalRuleBrowserLoginCoordinator.cancelForSource(sourceUrl, '书源任务已取消');
  }
  async hydrate(url: string): Promise<string> {
    await LocalRuleHttpClient.hydrateCookies(url);
    return JSON.stringify(await LocalRuleHttpClient.getCookieSnapshot(url));
  }
  async getSource(url: string): Promise<string> {
    if (!LocalRuleSourceRepository.isInitialized()) return '';
    const source = await LocalRuleSourceRepository.get(url);
    return source ? LightSourceAppHost.serialize(source) : '';
  }
  async listSources(): Promise<string> {
    if (!LocalRuleSourceRepository.isInitialized()) return '[]';
    const values: LightLocalSource[] = [];
    for (const source of await LocalRuleSourceRepository.list()) {
      if (!source.enabled) continue;
      const value: LightLocalSource = JSON.parse(LightSourceAppHost.serialize(source));
      values.push(value);
    }
    return JSON.stringify(values);
  }
  async readState(url: string): Promise<string> {
    return LocalRuleSourceRepository.isInitialized() ? await LocalRuleSourceRepository.readScriptState(url) : '';
  }
  async writeState(url: string, state: string): Promise<void> {
    if (LocalRuleSourceRepository.isInitialized()) await LocalRuleSourceRepository.writeScriptState(url, state);
  }
  async saveCookies(sourceUrl: string, origin: string, cookies: string): Promise<void> {
    await LocalRuleHttpClient.saveWebCookies(sourceUrl, origin, cookies, true);
  }
  async fetch(_serialized: string, _address: string, _sniff: boolean): Promise<string> {
    throw new Error('旧网页请求入口已停用');
  }
  async browse(sourceUrl: string, sourceName: string, address: string, html: string,
    injectJs: string): Promise<string> {
    const body = await LocalRuleBrowserLoginCoordinator.request(sourceUrl, sourceName, address, html, injectJs);
    const source = LocalRuleSourceRepository.isInitialized() ? await LocalRuleSourceRepository.get(sourceUrl) : undefined;
    if (source !== undefined && source.engine === 'light-native') {
      const definition: NativeBrowserDefinition = JSON.parse(source.rawSourceJson);
      if (definition.login?.check !== undefined) {
        await LocalRulePanelService.checkLogin(source, body, {}, address);
      }
    }
    return body;
  }
}
