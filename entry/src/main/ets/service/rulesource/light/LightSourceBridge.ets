import { BookInfo, SearchResult, TocItem } from '../../../model/BookSource';
import { LocalRuleSource } from '../../../model/LocalRuleSource';
import { LocalRuleExploreResult, LocalRulePanel, LocalRulePanelAction, LocalRuleControl } from '../../../model/LocalRulePanel';
import { LocalRuleContentResult, LocalRuleFetchResult, LocalRuleReaderActionResult, LocalRuleVoice } from '../LocalRuleRuntimeTypes';
import { LightSourceCore } from './LightSourceCore';
import { LightSourceRuntime } from './LightSourceRuntime';
import { LightSourceAppHost } from './LightSourceAppHost';
import { LightSourceTiming } from './LightSourceTiming';
import { LightSourceRequest } from './LightSourceRequestPolicy';

/** Read traced UI properties explicitly before crossing the JSON engine boundary. */
class LightPanelControlData {
  id: string = '';
  title: string = '';
  type: string = '';
  action: string = '';
  url: string = '';
  group: string = '';
  value: string = '';

  constructor(control: LocalRuleControl) {
    this.id = control.id;
    this.title = control.title;
    this.type = control.type;
    this.action = control.action;
    this.url = control.url;
    this.group = control.group;
    this.value = control.value;
  }
}

/** The imported source dispatcher is the only application entry to the upstream engine. */
export class LightSourceBridge {
  static async cacheComicImages(source: LocalRuleSource, urls: string[], request?: LightSourceRequest): Promise<string[]> {
    return JSON.parse(await LightSourceCore.cacheComicImages(LightSourceBridge.prepare(source), JSON.stringify(urls), request));
  }

  static async cover(source: LocalRuleSource, raw: string, sessionKey: string): Promise<string> {
    return LightSourceCore.cover(LightSourceBridge.prepare(source), raw, sessionKey);
  }
  static async voices(source: LocalRuleSource): Promise<LocalRuleVoice[]> {
    return JSON.parse(await LightSourceCore.voices(LightSourceBridge.prepare(source)));
  }
  static async readerAction(source: LocalRuleSource, address: string,
    variables: Record<string,string> = {}): Promise<LocalRuleReaderActionResult> {
    return JSON.parse(await LightSourceCore.readerAction(LightSourceBridge.prepare(source),address,JSON.stringify(variables)));
  }
  static async fetch(source: LocalRuleSource, address: string): Promise<LocalRuleFetchResult> {
    return JSON.parse(await LightSourceCore.fetch(LightSourceBridge.prepare(source),address));
  }
  private static prepare(source: LocalRuleSource, keepWebSession: boolean = false): string {
    if (LightSourceRuntime.host === undefined) LightSourceRuntime.host = new LightSourceAppHost();
    return LightSourceAppHost.serialize(source, keepWebSession);
  }
  static async panel(source: LocalRuleSource, login: boolean): Promise<LocalRulePanel> {
    const raw: LocalRulePanel = JSON.parse(await LightSourceCore.panel(LightSourceBridge.prepare(source), login,
      AppStorage.get<string>('lightSourceSaveLabel') ?? '', AppStorage.get<string>('lightSourceLoginLabel') ?? ''));
    const panel = new LocalRulePanel();
    panel.controls = raw.controls.map((item: LocalRuleControl): LocalRuleControl => LightSourceBridge.panelControl(item));
    panel.entries = raw.entries.map((item: LocalRuleControl): LocalRuleControl => LightSourceBridge.panelControl(item));
    return panel;
  }
  static async panelOptions(source: LocalRuleSource, controlId: string): Promise<string[]> {
    const options: string[] = JSON.parse(await LightSourceCore.panelOptions(LightSourceBridge.prepare(source), controlId));
    return options;
  }
  private static panelControl(item: LocalRuleControl): LocalRuleControl {
    const control = new LocalRuleControl();
    control.id = item.id ?? '';
    control.title = item.title ?? '';
    control.type = item.type ?? 'text';
    control.value = item.value ?? '';
    control.options = item.options ?? [];
    control.optionValues = item.optionValues ?? [];
    control.action = item.action ?? '';
    control.url = item.url ?? '';
    control.group = item.group ?? '';
    control.placeholder = item.placeholder ?? '';
    return control;
  }
  static async panelAction(source: LocalRuleSource, control: LocalRuleControl,
    controls: LocalRuleControl[]): Promise<LocalRulePanelAction> {
    const action = new LightPanelControlData(control);
    if (action.id === 'light-native-var:mode') {
      console.info(`[LightSourceBridge] mode value=${action.value}`);
    }
    const values = controls.map((item: LocalRuleControl): LightPanelControlData => new LightPanelControlData(item));
    const result: LocalRulePanelAction = JSON.parse(await LightSourceCore.panelAction(LightSourceBridge.prepare(source),
      JSON.stringify(action), JSON.stringify(values)));
    return result;
  }
  static async checkLogin(source: LocalRuleSource, content: string, baseUrl: string): Promise<boolean> {
    return LightSourceCore.checkLogin(LightSourceBridge.prepare(source, true), content, baseUrl);
  }
  static async checkNativeLogin(source: LocalRuleSource): Promise<boolean> {
    return LightSourceCore.checkNativeLogin(LightSourceBridge.prepare(source));
  }
  static async clearLogin(source: LocalRuleSource): Promise<void> {
    return LightSourceCore.clearLogin(LightSourceBridge.prepare(source, true));
  }
  static async search(source: LocalRuleSource, keyword: string, page: number): Promise<SearchResult[]> {
    const values: SearchResult[] = JSON.parse(await LightSourceCore.search(LightSourceBridge.prepare(source), keyword, page));
    return values;
  }
  static async explore(source: LocalRuleSource, address: string, page: number, limit: number): Promise<LocalRuleExploreResult> {
    const result: LocalRuleExploreResult = JSON.parse(await LightSourceCore.explore(LightSourceBridge.prepare(source), address, page, limit));
    return result;
  }
  static async detail(source: LocalRuleSource, url: string, variables: Record<string, string>): Promise<BookInfo> {
    const result: BookInfo = JSON.parse(await LightSourceCore.detail(LightSourceBridge.prepare(source), url, JSON.stringify(variables)));
    return result;
  }
  static async toc(source: LocalRuleSource, url: string, variables: Record<string, string>): Promise<TocItem[]> {
    const results: TocItem[] = JSON.parse(await LightSourceCore.toc(LightSourceBridge.prepare(source), url, JSON.stringify(variables)));
    return results;
  }
  static async content(source: LocalRuleSource, url: string, variables: Record<string, string>,
    request?: LightSourceRequest, deferReaderImages: boolean = false): Promise<LocalRuleContentResult> {
    const timingId = LightSourceTiming.next();
    const startedAt = Date.now();
    const localJson = LightSourceBridge.prepare(source);
    const context = JSON.stringify(variables);
    LightSourceTiming.end(timingId, 'bridge-serialize', startedAt);
    try {
    const json = await LightSourceCore.content(localJson, url, context, timingId, request, deferReaderImages);
    const decodeStartedAt = Date.now();
    const result: LocalRuleContentResult = JSON.parse(json);
    const payload: Record<string, Object> = JSON.parse(json);
    const updates: Record<string, string> = JSON.parse(JSON.stringify(payload['variables'] ?? {}));
    for (const key of Object.keys(updates)) variables[key] = updates[key];
    LightSourceTiming.end(timingId, 'bridge-decode', decodeStartedAt);
    return result;
    } finally { LightSourceTiming.end(timingId, 'content-total', startedAt); }
  }
}
