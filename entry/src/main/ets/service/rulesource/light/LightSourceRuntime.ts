import { LightLocalSource as LocalRuleSource, LightSourceHost } from './LightSourceHost';
import { BookSource } from './upstream/model/data/Book';
import { LightSourceImport } from './upstream/LightSourceImport';
import { SetCookieParser } from './upstream/core/http/SetCookieParser';
import { LightCookieSemantics } from './upstream/core/http/LightCookieSemantics';
import { webview } from '@kit.ArkWeb';
import { LightSourceTiming } from './LightSourceTiming';
import { LightSourceRequestPolicy, LightSourceRateWaiter } from './LightSourceRequestPolicy';
import { SourceEngineHost, SourceEngineHostAdapter, SourceRateWaiter } from './upstream/core/host/SourceEngineHost';
import { LightNativeScripts } from './LightNativeScripts';
import { NativeSourceInteraction } from './upstream/core/nativesource/NativeSourceInteraction';

class LightExecutionState {
  local: LocalRuleSource;
  variable: string;
  loginHeader: string;
  loginInfo: string;
  error: string = '';
  constructor(source: BookSource, local: LocalRuleSource) {
    this.local = local;
    this.variable = source.variable || '';
    this.loginHeader = source.loginHeader || '';
    this.loginInfo = source.loginInfo || '';
  }
}

/** Source execution never owns a global network queue or an ArkWeb session. */
export class LightSourceRuntime {
  static host: LightSourceHost;
  static parseDefinition: (raw: Record<string, Object>) => BookSource = raw => new LightSourceImport().parseBookSource(raw);
  private static executions = new WeakMap<BookSource, LightExecutionState>();
  private static stateWrites = new Map<string, Promise<void>>();
  static async run<T>(source: BookSource, local: LocalRuleSource, action: () => Promise<T>): Promise<T> {
    const cookies = LightCookieStore.retain(local.bookSourceUrl);
    const timingId = LightSourceTiming.id(source);
    try {
      let startedAt = Date.now();
      const state = JSON.parse(await this.host.readState(local.bookSourceUrl) || '{}');
      LightSourceTiming.end(timingId, 'state-read', startedAt);
      startedAt = Date.now();
      await cookies.hydrate(state.lightCookieRecords || []);
      LightSourceTiming.end(timingId, 'cookie-hydrate', startedAt);
      source.variable = state.definitionVariable !== undefined && state.definitionVariable !== local.variable ? local.variable : state.variable ?? local.variable;
      source.loginHeader = state.loginHeader || '';
      source.loginInfo = state.loginInfo || '';
      this.executions.set(source, new LightExecutionState(source, local));
      return await action();
    } finally {
      const flushStartedAt = Date.now();
      try { await cookies.flush(); } finally {
        LightSourceTiming.end(timingId, 'cookie-flush', flushStartedAt);
        this.executions.delete(source);
        LightCookieStore.release(local.bookSourceUrl);
      }
    }
  }
  static bindSource(source: BookSource, copy: BookSource): void {
    LightSourceRequestPolicy.copy(source, copy);
    LightSourceTiming.copy(source, copy);
    const state = this.executions.get(source);
    if (state) this.executions.set(copy,state);
  }
  static execution(source: BookSource): LightExecutionState | undefined { return this.executions.get(source); }
  static setError(source: BookSource, message: string): void {
    const state = this.executions.get(source);
    if (state) state.error = message;
  }
  static getError(source: BookSource): string { return this.executions.get(source)?.error || ''; }
  static async evaluate(script: string, sourceUrl: string, timingId: number = 0): Promise<string> {
    return this.host.evaluate(this.polyfills() + '\n' + script, sourceUrl, timingId);
  }
  /** Only real WebView/sniffing requests enter the global incognito cookie session. */
  static async withWeb<T>(sourceUrl: string, action: () => Promise<T>): Promise<T> {
    const cookies = LightCookieStore.forSource(sourceUrl);
    const lease = this.host.acquireWeb ? await this.host.acquireWeb() : 0;
    try {
      cookies.attachBrowser();
      return await action();
    } finally {
      try { cookies.detachBrowser(); } finally { this.host.releaseWeb?.(lease); }
    }
  }
  /** Serialize short read/modify/write transactions, never HTTP or script execution. */
  static async updateState(url: string, update: (state: Record<string, Object>) => void, timingId: number = 0): Promise<void> {
    const queuedAt = Date.now();
    const prior = this.stateWrites.get(url) || Promise.resolve();
    const work = prior.catch(() => {}).then(async () => {
      LightSourceTiming.end(timingId, 'state-transaction-wait', queuedAt);
      const startedAt = Date.now();
      let changed = false;
      try {
      const before = await this.host.readState(url) || '{}';
      const state: Record<string, Object> = JSON.parse(before);
      update(state);
      const after = JSON.stringify(state);
      changed = after !== JSON.stringify(JSON.parse(before));
      if (changed) await this.host.writeState(url, after);
      } finally { LightSourceTiming.end(timingId, 'state-transaction', startedAt, `changed=${changed}`); }
    });
    this.stateWrites.set(url, work);
    try { await work; } finally { if (this.stateWrites.get(url) === work) this.stateWrites.delete(url); }
  }
  private static polyfills(): string {
    return `var window=globalThis;
      function btoa(s){var c='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',o='';for(var i=0;i<s.length;i+=3){var a=s.charCodeAt(i),b=s.charCodeAt(i+1),d=s.charCodeAt(i+2);o+=c[a>>2]+c[((a&3)<<4)|((b||0)>>4)]+(i+1<s.length?c[((b&15)<<2)|((d||0)>>6)]:'=')+(i+2<s.length?c[d&63]:'=');}return o;}
      function atob(s){var c='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',o='',v=0,n=0;s=String(s).replace(/\\s/g,'');for(var i=0;i<s.length;i++){if(s[i]==='=')break;var x=c.indexOf(s[i]);if(x<0)throw Error('Invalid base64');v=(v<<6)|x;n+=6;if(n>=8){n-=8;o+=String.fromCharCode((v>>n)&255);}}return o;}
      class TextEncoder{encode(s){var x=unescape(encodeURIComponent(String(s))),a=[];for(var i=0;i<x.length;i++)a.push(x.charCodeAt(i));return new Uint8Array(a);}}
      class TextDecoder{constructor(e,o){this.encoding=e||'utf-8';this.options=o||{};this.id=typeof __lightNextDecoderId==='undefined'?0:__lightNextDecoderId++;}decode(a,o){if(typeof __lightDecodeBridge==='function')return __lightDecodeBridge(this.id,this.encoding,a,this.options,o||{});var s='';for(var i=0;i<a.length;i++)s+=String.fromCharCode(a[i]);try{return decodeURIComponent(escape(s));}catch(e){return s;}}}
    `;
  }
}

export class LightSourceDatabase {
  private static instance = new LightSourceDatabase();
  private source: BookSource | null;
  constructor(source: BookSource | null = null) { this.source = source; }
  static getInstance(source: BookSource | null = null): LightSourceDatabase {
    return source ? new LightSourceDatabase(source) : this.instance;
  }
  async getBookSource(url: string): Promise<BookSource | null> {
    if (this.source?.bookSourceUrl === url) return this.source;
    const local = JSON.parse(await LightSourceRuntime.host.getSource(url) || 'null');
    if (!local || local.engine === 'native-v1') return null;
    const raw: Record<string, Object> = JSON.parse(local.definition || local.rawSourceJson || JSON.stringify(local));
    const source = LightSourceRuntime.parseDefinition(raw);
    const state = JSON.parse(await LightSourceRuntime.host.readState(url) || '{}');
    source.variable = state.definitionVariable !== undefined && state.definitionVariable !== local.variable ? local.variable : state.variable ?? local.variable;
    source.loginHeader = state.loginHeader || '';
    source.loginInfo = state.loginInfo || '';
    return source;
  }
  async getEnabledBookSourcesForSearch(): Promise<BookSource[]> { return this.list(false); }
  async getEnabledBookSourcesForExplore(): Promise<BookSource[]> { return this.list(true); }
  private async list(explore: boolean): Promise<BookSource[]> {
    const output: BookSource[] = [];
    const locals: LocalRuleSource[] = JSON.parse(await LightSourceRuntime.host.listSources());
    for (const local of locals) {
      if (explore && !local.enabledExplore) continue;
      const source = await this.getBookSource(local.bookSourceUrl);
      if (source) output.push(source);
    }
    return output;
  }
  async updateBookSourceVariable(url: string, variable: string): Promise<void> {
    const source = await this.getBookSource(url);
    if (source) await this.updateBookSourceLoginRuntime(url, variable, source.loginHeader, source.loginInfo);
  }
  private mergeValue(current: string, before: string, next: string): string {
    if (before === next) return current;
    if (!next || !before || !current) return next;
    try {
      const oldValue = JSON.parse(before), newValue = JSON.parse(next), merged = JSON.parse(current);
      if (!oldValue || !newValue || !merged || Array.isArray(oldValue) || Array.isArray(newValue) ||
        Array.isArray(merged) || typeof oldValue !== 'object' || typeof newValue !== 'object' || typeof merged !== 'object') return next;
      for (const key of new Set([...Object.keys(oldValue), ...Object.keys(newValue)])) {
        if (JSON.stringify(oldValue[key]) === JSON.stringify(newValue[key])) continue;
        if (Object.prototype.hasOwnProperty.call(newValue,key)) merged[key] = newValue[key];
        else delete merged[key];
      }
      return JSON.stringify(merged);
    } catch (_) { return next; }
  }
  async updateBookSourceLoginRuntime(url: string, variable: string, loginHeader: string, loginInfo: string): Promise<void> {
    const source = this.source;
    const execution = source ? LightSourceRuntime.execution(source) : undefined;
    if (execution && variable === execution.variable && loginHeader === execution.loginHeader && loginInfo === execution.loginInfo) return;
    await LightSourceRuntime.updateState(url, state => {
      const definitionChanged = execution && state.definitionVariable !== undefined && state.definitionVariable !== execution.local.variable;
      const currentVariable = String(definitionChanged ? execution.variable : state.variable ?? execution?.variable ?? '');
      const currentHeader = String(state.loginHeader ?? execution?.loginHeader ?? '');
      const currentInfo = String(state.loginInfo ?? execution?.loginInfo ?? '');
      state.variable = this.mergeValue(currentVariable, execution?.variable ?? currentVariable, variable);
      state.loginHeader = this.mergeValue(currentHeader, execution?.loginHeader ?? currentHeader, loginHeader);
      state.loginInfo = this.mergeValue(currentInfo, execution?.loginInfo ?? currentInfo, loginInfo);
      state.definitionVariable = execution?.local.variable ?? state.definitionVariable ?? '';
      if (source) {
        source.variable = String(state.variable); source.loginHeader = String(state.loginHeader); source.loginInfo = String(state.loginInfo);
      }
      if (execution) {
        execution.variable = String(state.variable); execution.loginHeader = String(state.loginHeader); execution.loginInfo = String(state.loginInfo);
      }
    }, LightSourceTiming.id(source));
  }
}

/** HTTP cookies live in source-owned memory; ArkWeb is attached only under its lease. */
export class LightCookieStore {
  private static stores = new Map<string, LightCookieStore>();
  private sourceUrl: string;
  private users: number = 0;
  private ready: Promise<void> | null = null;
  private flushing: Promise<void> = Promise.resolve();
  private persistedRecords: string = '[]';
  private persistedCookies: Record<string, string> = {};
  private browserActive: boolean = false;
  constructor(sourceUrl: string = '') { this.sourceUrl = sourceUrl; }
  static retain(sourceUrl: string): LightCookieStore {
    let store = this.stores.get(sourceUrl);
    if (!store) { store = new LightCookieStore(sourceUrl); this.stores.set(sourceUrl,store); }
    store.users++;
    return store;
  }
  static forSource(sourceUrl: string = ''): LightCookieStore {
    const store = this.stores.get(sourceUrl);
    if (store) return store;
    // Non-source utility requests have no credentials or persistent Cookie access.
    if (!sourceUrl) return new LightCookieStore();
    throw new Error('书源 Cookie 上下文未初始化');
  }
  static release(sourceUrl: string): void {
    const store = this.stores.get(sourceUrl);
    if (store && --store.users === 0) this.stores.delete(sourceUrl);
  }
  async hydrate(records: {url:string;cookie:string}[]): Promise<void> {
    if (!this.ready) this.ready = LightSourceRuntime.host.hydrate(this.sourceUrl).then(raw => {
      this.load(JSON.parse(raw),false,records);
    });
    await this.ready;
  }
  attachBrowser(): void {
    this.browserActive = true;
    webview.WebCookieManager.clearAllCookiesSync(true);
    for (const record of this.records) LightCookieSemantics.setCookies(record.url,record.cookie);
    for (const origin of Object.keys(this.cookies)) {
      if (!this.records.some(record => this.matchesHost(origin,record))) this.inject(origin,this.cookies[origin]);
    }
  }
  detachBrowser(): void {
    if (!this.browserActive) return;
    try {
      const urls = new Set(Object.keys(this.cookies));
      for (const record of this.records) urls.add(this.origin(record.url)+this.recordKey(record).split('\n')[1]);
      for (const url of urls) this.captureBrowserCookie(url);
    } finally { this.close(); this.browserActive = false; }
  }
  private captureBrowserCookie(url: string): string {
    const value = LightCookieSemantics.withoutExpiredJwtCookies(webview.WebCookieManager.fetchCookieSync(url,true));
    const origin = this.origin(url);
    const before = JSON.stringify(this.records);
    const values = new Map<string, string[]>();
    for (const pair of value.split(';')) {
      const index = pair.indexOf('=');
      if (index <= 0) continue;
      const name = pair.slice(0,index).trim();
      const entries = values.get(name) || [];
      entries.push(pair.slice(index+1).trim()); values.set(name,entries);
    }
    const path = this.path(url);
    const visible = this.records.filter(record => {
      const cookiePath = this.recordKey(record).split('\n')[1];
      return this.matchesHost(url,record) && (path === cookiePath || (path.startsWith(cookiePath) &&
        (cookiePath.endsWith('/') || path[cookiePath.length] === '/'))) &&
        (!/;\s*secure(?:;|$)/i.test(record.cookie) || /^https:/i.test(url));
    }).sort((a,b) => this.recordKey(b).split('\n')[1].length-this.recordKey(a).split('\n')[1].length);
    for (const record of visible) {
      const name = record.cookie.split('=')[0].trim();
      const entries = values.get(name) || [];
      if (!entries.length) this.records = this.records.filter(item => item !== record);
      else {
        const attributes = record.cookie.slice(record.cookie.indexOf(';') < 0 ? record.cookie.length : record.cookie.indexOf(';'));
        record.cookie = name+'='+entries.shift()+attributes;
      }
    }
    for (const [name,entries] of values) {
      if (entries.length) this.record(url,name+'='+entries[0]+'; Path=/');
    }
    if (origin && (value !== (this.cookies[origin] || '') || before !== JSON.stringify(this.records))) {
      this.cookies[origin] = value; this.dirty.add(origin);
    }
    return value;
  }

  private cookies: Record<string, string> = {};
  private records: {url:string;cookie:string}[] = [];
  private dirty = new Set<string>();
  load(cookies: Record<string, string>, keepWebSession: boolean = false,
    records: {url:string;cookie:string}[] = []): void {
    this.cookies = cookies;
    this.persistedCookies = {...cookies};
    const baseline = [...records];
    this.records = records.filter(record => !this.expired(record.cookie));
    this.dirty.clear();
    for (const origin of Object.keys(cookies)) {
      if (!records.some(record => this.matchesHost(origin,record))) {
        for (const pair of cookies[origin].split(';')) {
          if (!pair.includes('=')) continue;
          const record = {url:origin+'/',cookie:pair.trim()+'; Path=/'};
          this.records.push(record); baseline.push(record);
        }
      }
      if (records.some(record => this.matchesHost(origin,record)) &&
        !this.records.some(record => this.matchesHost(origin,record))) {
        this.cookies[origin] = ''; this.dirty.add(origin);
      }
    }
    this.persistedRecords = JSON.stringify(baseline);
  }

  private attribute(cookie: string, name: string): string {
    const match = new RegExp(';\\s*'+name+'=([^;]*)','i').exec(cookie);
    return match ? match[1].trim() : '';
  }
  private host(address: string): string {
    return (this.origin(address).replace(/^https?:\/\//i,'').replace(/:\d+$/,'')).toLowerCase();
  }
  private path(address: string): string {
    const match = /^https?:\/\/[^/?#]+([^?#]*)/i.exec(address);
    return match?.[1] || '/';
  }
  private recordKey(record: {url:string;cookie:string}): string {
    const path = this.path(record.url);
    const defaultPath = path.slice(0,path.lastIndexOf('/')) || '/';
    return (this.attribute(record.cookie,'domain').replace(/^\./,'') || this.host(record.url)) + '\n' +
      (this.attribute(record.cookie,'path') || defaultPath) + '\n' + record.cookie.split('=')[0].trim();
  }
  private matchesHost(address: string, record: {url:string;cookie:string}): boolean {
    const host = this.host(address);
    const domain = this.attribute(record.cookie,'domain').replace(/^\./,'').toLowerCase();
    return domain ? host === domain || host.endsWith('.'+domain) : host === this.host(record.url);
  }
  private expired(cookie: string): boolean {
    const age = this.attribute(cookie,'max-age');
    if (age && Number(age) <= 0) return true;
    const expires = Date.parse(this.attribute(cookie,'expires'));
    return Number.isFinite(expires) && expires <= Date.now();
  }
  private record(url: string, cookie: string): void {
    const record = {url,cookie};
    if (!this.matchesHost(url,record)) return;
    const key = this.recordKey(record);
    this.records = this.records.filter(item => this.recordKey(item) !== key && !this.expired(item.cookie));
    if (this.expired(cookie)) return;
    const age = this.attribute(cookie,'max-age');
    if (age && Number.isFinite(Number(age))) {
      record.cookie = cookie.replace(/;\s*max-age=[^;]*/ig,'').replace(/;\s*expires=[^;]*/ig,'') +
        '; Expires='+new Date(Date.now()+Number(age)*1000).toUTCString();
    }
    this.records.push(record);
  }
  close(): void { if (this.browserActive) { try { webview.WebCookieManager.clearAllCookiesSync(true); } catch (_) {} } }
  private inject(url: string, cookies: string): void {
    for (const pair of cookies.split(';')) {
      if (!pair.trim().includes('=')) continue;
      try { webview.WebCookieManager.configCookieSync(url,pair.trim(),true,true); } catch (_) {}
    }
  }
  private origin(url: string): string {
    const match = /^https?:\/\/[^/?#]+/i.exec(url || '');
    return match ? match[0].toLowerCase() : '';
  }
  getCookie(url: string): string {
    const origin = this.origin(url);
    if (this.browserActive) {
      try { return this.captureBrowserCookie(url); } catch (_) {}
    }
    if (this.records.some(record => this.matchesHost(url,record))) {
      const path = this.path(url);
      const matching = this.records.filter(record => {
        if (!this.matchesHost(url,record) || this.expired(record.cookie)) return false;
        if (/;\s*secure(?:;|$)/i.test(record.cookie) && !/^https:/i.test(url)) return false;
        const cookiePath = this.recordKey(record).split('\n')[1];
        return path === cookiePath || (path.startsWith(cookiePath) &&
          (cookiePath.endsWith('/') || path[cookiePath.length] === '/'));
      }).sort((a,b) => this.recordKey(b).split('\n')[1].length-this.recordKey(a).split('\n')[1].length);
      return LightCookieSemantics.withoutExpiredJwtCookies(matching.map(record => record.cookie.split(';')[0]).join('; '));
    }
    return LightCookieSemantics.withoutExpiredJwtCookies(this.cookies[origin] || '');
  }
  getCookieValue(url: string, name: string): string {
    for (const pair of this.getCookie(url).split(';')) {
      const index = pair.indexOf('=');
      if (index > 0 && pair.slice(0, index).trim() === name) return pair.slice(index + 1).trim();
    }
    return '';
  }
  setCookies(url: string, value: string): void {
    const origin = this.origin(url);
    if (!origin) return;
    const jar: Record<string, string> = {};
    for (const pair of this.getCookie(url).split(';')) {
      const index = pair.indexOf('=');
      if (index > 0) jar[pair.slice(0, index).trim()] = pair.slice(index + 1).trim();
    }
    const records = /;\s*(?:(path|domain|expires|max-age|samesite)\s*=|secure\b|httponly\b)/i.test(value) ?
      SetCookieParser.split(value) : value.split(/[;\r\n]+/);
    for (const record of records) {
      const pair = record.split(';')[0];
      const index = pair.indexOf('=');
      if (index <= 0) continue;
      const name = pair.slice(0, index).trim();
      if (this.expired(record)) {
        this.expire(url, name);
        delete jar[name];
      } else jar[name] = pair.slice(index + 1).trim();
      this.record(url, record);
      if (this.browserActive && record.includes(';')) LightCookieSemantics.setCookies(url, record);
    }
    this.cookies[origin] = Object.keys(jar).map(name => `${name}=${jar[name]}`).join('; ');
    if (this.browserActive) for (const record of records) if (!this.expired(record)) LightCookieSemantics.setCookies(url,record);
    this.dirty.add(origin);
  }
  replaceCookies(url: string, cookies: string): void { this.removeCookie(url); this.setCookies(url, cookies); }
  private expire(url: string, name: string): void {
    for (const record of this.records) {
      if (!this.matchesHost(url,record) || record.cookie.split('=')[0].trim() !== name) continue;
      const attrs = record.cookie.split(';').slice(1).filter(value => !/^\s*(max-age|expires)=/i.test(value));
      if (this.browserActive) LightCookieSemantics.setCookies(record.url, `${name}=__removed__; Max-Age=31536000;${attrs.join(';')}`);
    }
    if (this.browserActive) LightCookieSemantics.removeCookie(url, name);
  }
  removeCookie(url: string, name?: string): void {
    const pairs = this.getCookie(url).split(';');
    for (const record of this.records) {
      const key = record.cookie.split('=')[0].trim();
      if (this.matchesHost(url,record) && (!name || key === name)) this.expire(url,key);
    }
    for (const pair of pairs) {
      const key = pair.trim().split('=')[0];
      if (key && (!name || key === name)) this.expire(url, key);
    }
    this.cookies[this.origin(url)] = name ? pairs.filter(pair => pair.trim().split('=')[0] !== name).join('; ') : '';
    this.records = this.records.filter(record => !this.matchesHost(url,record) ||
      (!!name && record.cookie.split('=')[0].trim() !== name));
    this.dirty.add(this.origin(url));
  }
  copyCookies(from: string, to: string): void { this.setCookies(to, this.getCookie(from)); }
  saveAsync(): void { /* Flushed before the source lease is released. */ }
  saveSync(): void { this.saveAsync(); }
  clearAll(): void {
    const origins = new Set(Object.keys(this.cookies));
    for (const record of this.records) origins.add(this.origin(record.url));
    for (const origin of origins) this.removeCookie(origin);
    this.records = [];
  }
  async flush(): Promise<void> {
    const work = this.flushing.catch(() => {}).then(() => this.flushPending());
    this.flushing = work;
    await work;
  }
  private async flushPending(): Promise<void> {
    if (!this.sourceUrl || !this.ready) return;
    await this.ready;
    for (const origin of Array.from(this.dirty)) {
      if (!origin) continue;
      const header = this.getCookie(origin);
      if (header !== (this.persistedCookies[origin] || '')) {
        await LightSourceRuntime.host.saveCookies(this.sourceUrl, origin, header);
        this.persistedCookies[origin] = header;
      }
      if (header === this.getCookie(origin)) this.dirty.delete(origin);
      for (const pair of header.split(';')) {
        const name = pair.trim().split('=')[0];
        if (pair.includes('=') && !this.records.some(record => this.matchesHost(origin,record) &&
          record.cookie.split('=')[0].trim() === name)) this.record(origin+'/',pair.trim()+'; Path=/');
      }
    }
    const records = this.records.filter(record => !this.expired(record.cookie));
    const serialized = JSON.stringify(records);
    if (serialized === this.persistedRecords) return;
    await LightSourceRuntime.updateState(this.sourceUrl,state => { state.lightCookieRecords = records; });
    this.persistedRecords = serialized;
  }
}

export { WebBookFetchRuntime as LightWebFetchRuntime } from './upstream/core/book/WebBookFetchRuntime';
export { BookSourceAudioWebRuntime as LightAudioWebRuntime } from './upstream/core/book/BookSourceAudioWebRuntime';

class LightEngineRateWaiter implements SourceRateWaiter {
  waiter: LightSourceRateWaiter;
  constructor(waiter: LightSourceRateWaiter) { this.waiter = waiter; }
  isCancelled(): boolean { return this.waiter.isCancelled(); }
  wait(ms: number): Promise<void> { return this.waiter.wait(ms); }
}

// One startup installation. All mutable execution state remains bound to source instances.
const engineHost: SourceEngineHostAdapter = {
  imageScripts: {run: async (script, input, cancelled) => {
    if (!LightSourceRuntime.host.evaluateImage) throw new Error('图片脚本执行器未初始化');
    return LightSourceRuntime.host.evaluateImage(script, input, cancelled);
  }},
  nativeScripts: {create: (source, host) => LightNativeScripts.create(source, host)},
  cookies: sourceUrl => LightCookieStore.forSource(sourceUrl),
  persistence: source => LightSourceDatabase.getInstance(source),
  scripts: {
    concurrent: true, forceFullScripts: true, allowSynchronousQuickJs: false,
    evaluate: (script, sourceUrl, timingId) => LightSourceRuntime.evaluate(script, sourceUrl, timingId)
  },
  web: {run: <T>(sourceUrl: string, action: () => Promise<T>): Promise<T> => LightSourceRuntime.withWeb(sourceUrl, action)},
  state: {
    bindSource: (source, target) => LightSourceRuntime.bindSource(source, target),
    setError: (source, message) => LightSourceRuntime.setError(source, message),
    getError: source => LightSourceRuntime.getError(source)
  },
  diagnostics: {
    id: source => LightSourceTiming.id(source),
    end: (id, stage, startedAt, details) => LightSourceTiming.end(id, stage, startedAt, details)
  },
  requests: {
    isCancelled: source => LightSourceRequestPolicy.isCancelled(source),
    priority: source => LightSourceRequestPolicy.priority(source),
    enqueue: (key, source, cancelCheck) => new LightEngineRateWaiter(LightSourceRequestPolicy.enqueue(key, source, cancelCheck)),
    first: (key, waiter) => waiter instanceof LightEngineRateWaiter && LightSourceRequestPolicy.first(key, waiter.waiter),
    remove: (key, waiter) => { if (waiter instanceof LightEngineRateWaiter) LightSourceRequestPolicy.remove(key, waiter.waiter); }
  }
};
SourceEngineHost.install(engineHost);
NativeSourceInteraction.setHandler({
  toast: (_name, message) => {
    if (!LightSourceRuntime.host.toast) throw new Error('当前环境不支持提示');
    LightSourceRuntime.host.toast(message);
  },
  refreshExplore: async sourceUrl => {
    if (!LightSourceRuntime.host.refreshExplore) throw new Error('当前环境不支持刷新发现页');
    await LightSourceRuntime.host.refreshExplore(sourceUrl);
  },
  openBrowser: async (request, wait) => {
    if (!/^https:\/\//i.test(request.url)) return {body:'',error:'网页登录仅支持 HTTPS 地址'};
    const host = LightSourceRuntime.host;
    const cookies = LightCookieStore.forSource(request.sourceUrl);
    try {
      await cookies.flush();
      if (!wait) {
        if (!host.openBrowser) throw new Error('网页登录入口不可用');
        await host.openBrowser(request.sourceUrl,request.sourceName,request.url);
        return {body:'',error:''};
      }
      if (!host.browse) throw new Error('网页登录入口不可用');
      const body = await host.browse(request.sourceUrl,request.sourceName,request.url,'','');
      return {body,error:''};
    } catch (error) { return {body:'',error:error instanceof Error ? error.message : String(error)}; }
    finally {
      if (wait) {
        const state = JSON.parse(await host.readState(request.sourceUrl) || '{}');
        cookies.load(JSON.parse(await host.hydrate(request.sourceUrl)),false,state.lightCookieRecords || []);
      }
    }
  }
});
