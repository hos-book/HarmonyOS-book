import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LocalRuleQuickJsRequest, LocalRuleQuickJsRuntime } from '../../../main/ets/service/rulesource/LocalRuleQuickJsRuntime';
import { LocalRuleSourceImportParser } from '../../../main/ets/service/rulesource/LocalRuleSourceImportParser';
import { LightSourceBridge } from '../../../main/ets/service/rulesource/light/LightSourceBridge';
import { HttpClient } from '../../../main/ets/service/http/HttpClient';
import { LocalRuleSource } from '../../../main/ets/model/LocalRuleSource';
import { LightSourceRuntime } from '../../../main/ets/service/rulesource/light/LightSourceRuntime';
import { LightSourceAppHost } from '../../../main/ets/service/rulesource/light/LightSourceAppHost';

class NativeSourceSmokeHost extends LightSourceAppHost {
  private source: LocalRuleSource;
  constructor(source: LocalRuleSource) { super(); this.source = source; }
  async getSource(url: string): Promise<string> {
    return url === this.source.bookSourceUrl ? LightSourceAppHost.serialize(this.source) : '';
  }
}

export default function localRuleQuickJsHostTest() {
  describe('LocalRuleQuickJsHost', () => {
    it('continues_600_host_calls_in_one_isolated_task', 0, async () => {
      const request = new LocalRuleQuickJsRequest();
      request.timeoutMs = 2000;
      request.script = '(function(){let n=0;for(let i=0;i<600;i++){' +
        'let r=JSON.parse(__boundedHost("read",String(i)));n+=JSON.parse(r.value);}' +
        'return String(n);})()';
      let calls = 0;
      request.hostHandler = async (_name: string, payload: string): Promise<string> => {
        expect(Number(payload)).assertEqual(calls++);
        return '1';
      };
      request.hostCheck = (): void => {};
      const result = await LocalRuleQuickJsRuntime.execute(request);
      abilityDelegatorRegistry.getAbilityDelegator().printSync(`[NativeHost] success=${result.success} ` +
        `calls=${calls} cpu=${result.elapsedMs} error=${result.errorMessage}\n`);
      expect(result.success).assertTrue();
      expect(result.value).assertEqual('600');
      expect(calls).assertEqual(600);
    });
    it('excludes_host_wait_from_cpu_budget_and_interrupts_busy_scripts', 0, async () => {
      const request = new LocalRuleQuickJsRequest();
      request.timeoutMs = 100;
      request.script = '__boundedHost("wait","[]");"done"';
      request.hostHandler = async (): Promise<string> => {
        await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 300); });
        return 'null';
      };
      request.hostCheck = (): void => {};
      const waited = await LocalRuleQuickJsRuntime.execute(request);
      expect(waited.success).assertTrue();
      expect(waited.value).assertEqual('done');
      request.script = 'while(true){}';
      const busy = await LocalRuleQuickJsRuntime.execute(request);
      expect(busy.success).assertFalse();
      expect(busy.timedOut).assertTrue();
      request.script = 'String(typeof savedFromOtherContext)';
      const fresh = await LocalRuleQuickJsRuntime.execute(request);
      expect(fresh.success).assertTrue();
      expect(fresh.value).assertEqual('undefined');
    });
    it('cancels_an_unanswered_host_call_and_releases_the_task', 0, async () => {
      const request = new LocalRuleQuickJsRequest();
      let cancel = false;
      request.script = '__boundedHost("wait","[]")';
      request.hostHandler = async (): Promise<string> => {
        cancel = true;
        return new Promise<string>(() => {});
      };
      request.hostCheck = (): void => { if (cancel) throw new Error('fixture cancelled'); };
      const result = await LocalRuleQuickJsRuntime.execute(request);
      expect(result.success).assertFalse();
      expect(result.errorMessage).assertEqual('fixture cancelled');
    });
  });

  // Opt-in real source verification. Source definitions are supplied by the caller, never bundled.
  const params = abilityDelegatorRegistry.getArguments().parameters;
  const importUrl = params['-s nativeImportUrl'] ?? params['nativeImportUrl'] ?? '';
  if (!importUrl) return;
  describe('NativeScriptSourceSmoke', () => {
    it('loads_discovery_and_search_from_the_original_definition', 0, async () => {
      const definition = await HttpClient.get(importUrl);
      const source = LocalRuleSourceImportParser.parse(definition).sources[0];
      expect(source !== undefined).assertTrue();
      if (source === undefined) return;
      LightSourceRuntime.host = new NativeSourceSmokeHost(source);
      const panel = await LightSourceBridge.panel(source, false);
      const entry = panel.entries.find((item) => item.url.length > 0);
      expect(entry !== undefined).assertTrue();
      if (entry === undefined) return;
      const discovery = await LightSourceBridge.explore(source, entry.url, 1, 100);
      abilityDelegatorRegistry.getAbilityDelegator().printSync(
        `[NativeSourceSmoke] ${source.bookSourceName} discovery=${discovery.books.length}\n`);
      expect(discovery.books.length > 0).assertTrue();
      const keyword = params['-s nativeKeyword'] ?? params['nativeKeyword'] ?? '我';
      const books = await LightSourceBridge.search(source, keyword, 1);
      abilityDelegatorRegistry.getAbilityDelegator().printSync(
        `[NativeSourceSmoke] ${source.bookSourceName} search=${books.length}\n`);
      expect(books.length > 0).assertTrue();
    });
  });
}
