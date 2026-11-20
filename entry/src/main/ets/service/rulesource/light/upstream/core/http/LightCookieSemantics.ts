import deviceInfo from '@ohos.deviceInfo';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { LogText } from '../../utils/LogText';
import { SetCookieParser } from './SetCookieParser';
import { SourceEngineHost, SourceCookieJar } from '../host/SourceEngineHost';

export class LightCookieSemantics {
  /** Legacy unscoped callers keep the ArkWeb jar; source execution always supplies its identity. */
  static forSource(sourceUrl: string = ''): SourceCookieJar {
    return SourceEngineHost.cookies(sourceUrl) || LightCookieSemantics;
  }

  static getRequestCookie(url: string): string {
    if (deviceInfo.sdkApiVersion < 26) return this.getCookie(url);
    for (const target of this.targetUrls(url)) {
      try {
        const value = webview.WebCookieManager.fetchCookieSync(target, true, true) || '';
        if (value) return this.withoutExpiredJwtCookies(value);
      } catch (error) {
        const code = Number((error as Record<string, Object>)['code'] || 0);
        if (code === 801) return this.getCookie(url);
        if (code !== 17100002) console.warn('[LightCookieSemantics] 分区 Cookie 读取失败，code=' + code);
      }
    }
    return '';
  }

  private static readonly TOMBSTONE_VALUE = '__removed__';

  static getCookie(url: string): string {
    if (!url) return '';
    for (const target of this.targetUrls(url)) {
      try {
        const value = webview.WebCookieManager.fetchCookieSync(target, true) || '';
        if (value) return this.withoutExpiredJwtCookies(value);
      } catch (_) {
      }
    }
    return '';
  }

  static setCookies(url: string, cookies: string): void {
    if (!url || !cookies) return;
    const values = SetCookieParser.split(cookies);
    for (const target of this.targetUrls(url)) {
      for (const value of values) {
        try {
          webview.WebCookieManager.configCookieSync(target, value, true, true);
        } catch (_) {
          try {
            webview.WebCookieManager.configCookieSync(target, value, true);
          } catch (_) {}
        }
      }
    }
  }

  static copyCookies(fromUrl: string, toUrl: string): void {
    if (!fromUrl || !toUrl) return;
    const cookies = this.getCookie(fromUrl);
    if (!cookies) return;
    for (const item of cookies.split(';')) {
      const pair = item.trim();
      if (!pair || !pair.includes('=')) continue;
      if (/^(cf_clearance|__cf_bm)=/i.test(pair) && fromUrl !== toUrl) continue;
      this.setCookies(toUrl, pair);
    }
    this.saveAsync();
  }

  static replaceCookies(url: string, cookies: string): void {
    if (!url) return;
    this.removeCookie(url);
    if (cookies) this.setCookies(url, cookies);
    this.saveAsync();
  }

  static getCookieValue(url: string, name: string): string {
    if (!name) return this.getCookie(url);
    for (const item of this.getCookie(url).split(';')) {
      const index = item.indexOf('=');
      if (index > 0 && item.substring(0, index).trim() === name) return item.substring(index + 1).trim();
    }
    return '';
  }

  /**
   * ArkWeb refuses to store expired cookies ("if the cookie has expired, it will not be stored"),
   * so the classic Max-Age=0 write is a silent no-op and the cookie survives. Removal escalates in
   * stages: Max-Age=0, then an empty value (the server sees an anonymous session), then a
   * placeholder value that is filtered out on every read.
   *
   * Every sync cookie call is a blocking round trip to the ArkWeb network service. Each stage
   * therefore writes all remaining cookies first and verifies them with a single read; verifying
   * cookie by cookie took ~10 round trips per cookie and froze the UI thread for over six seconds
   * when logging out of a site with dozens of cookies. UI paths should use removeCookieAsync().
   */
  static removeCookie(url: string, name?: string): void {
    if (!url) return;
    const names = this.removalNames(this.getRequestCookie(url), name);
    const stages = this.plainRemovalStages();
    let plain = this.presentNames(this.getCookie(url), names);
    for (let i = 0; i < stages.length && plain.length > 0; i++) {
      for (const cookieName of plain) this.writeCookieVariants(url, stages[i](cookieName));
      if (i < stages.length - 1) plain = this.namesWithValue(this.getCookie(url), plain);
    }
    if (this.removesPartitioned(url)) {
      for (const path of this.PARTITIONED_PATHS) {
        for (const cookieName of names) this.writeCookieVariants(url, this.partitionedExpiry(cookieName, path));
        for (const cookieName of this.presentNames(this.getRequestCookie(url), names)) {
          this.writeCookieVariants(url, this.partitionedTombstone(cookieName, path));
        }
      }
    }
    this.saveAsync();
  }

  /** Same staged removal as removeCookie() over the async ArkWeb APIs, so the caller's thread never blocks. */
  static async removeCookieAsync(url: string, name?: string): Promise<void> {
    if (!url) return;
    const names = this.removalNames(await this.fetchRequestCookieAsync(url), name);
    const stages = this.plainRemovalStages();
    let plain = this.presentNames(await this.fetchCookieAsync(url), names);
    for (let i = 0; i < stages.length && plain.length > 0; i++) {
      await this.writeAllAsync(url, plain.map(stages[i]));
      if (i < stages.length - 1) plain = this.namesWithValue(await this.fetchCookieAsync(url), plain);
    }
    if (this.removesPartitioned(url)) {
      for (const path of this.PARTITIONED_PATHS) {
        await this.writeAllAsync(url, names.map((cookieName: string): string => this.partitionedExpiry(cookieName, path)));
        const left = this.presentNames(await this.fetchRequestCookieAsync(url), names);
        await this.writeAllAsync(url, left.map((cookieName: string): string => this.partitionedTombstone(cookieName, path)));
      }
    }
    this.saveAsync();
  }

  private static readonly PARTITIONED_PATHS: string[] = ['', '; Path=/'];

  private static plainRemovalStages(): ((cookieName: string) => string)[] {
    return [
      (cookieName: string): string => `${cookieName}=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/`,
      (cookieName: string): string => `${cookieName}=; Max-Age=31536000; Path=/`,
      (cookieName: string): string => `${cookieName}=${LightCookieSemantics.TOMBSTONE_VALUE}; Max-Age=31536000; Path=/`
    ];
  }

  /** Partitioned writes remain partitioned; do not materialize them in the unpartitioned jar. */
  private static removesPartitioned(url: string): boolean {
    return deviceInfo.sdkApiVersion >= 26 && /^https:/i.test(url);
  }

  private static partitionedExpiry(cookieName: string, path: string): string {
    return `${cookieName}=; Secure; HttpOnly; SameSite=None; Partitioned${path}; Max-Age=0`;
  }

  private static partitionedTombstone(cookieName: string, path: string): string {
    return `${cookieName}=${this.TOMBSTONE_VALUE}; Secure; HttpOnly; SameSite=None; Partitioned${path}; Max-Age=60`;
  }

  private static removalNames(current: string, name?: string): string[] {
    if (name) return [name];
    const names: string[] = [];
    for (const item of (current || '').split(';')) {
      const cookieName = item.trim().split('=')[0];
      if (cookieName && names.indexOf(cookieName) < 0) names.push(cookieName);
    }
    return names;
  }

  /** Names from `names` that appear in the cookie header at all, even with an empty value. */
  private static presentNames(cookies: string, names: string[]): string[] {
    const pairs = (cookies || '').split(';').map((part: string): string => part.trim());
    return names.filter((cookieName: string): boolean =>
      pairs.some((pair: string): boolean => pair === cookieName || pair.startsWith(cookieName + '=')));
  }

  /** Names from `names` whose first occurrence in the cookie header still carries a value. */
  private static namesWithValue(cookies: string, names: string[]): string[] {
    const values = new Map<string, string>();
    for (const item of (cookies || '').split(';')) {
      const index = item.indexOf('=');
      if (index <= 0) continue;
      const cookieName = item.substring(0, index).trim();
      if (!values.has(cookieName)) values.set(cookieName, item.substring(index + 1).trim());
    }
    return names.filter((cookieName: string): boolean => !!values.get(cookieName));
  }

  private static async fetchCookieAsync(url: string): Promise<string> {
    for (const target of this.targetUrls(url)) {
      try {
        const value = await webview.WebCookieManager.fetchCookie(target) || '';
        if (value) return this.withoutExpiredJwtCookies(value);
      } catch (_) {
      }
    }
    return '';
  }

  private static async fetchRequestCookieAsync(url: string): Promise<string> {
    if (deviceInfo.sdkApiVersion < 26) return await this.fetchCookieAsync(url);
    for (const target of this.targetUrls(url)) {
      try {
        const value = await webview.WebCookieManager.fetchCookie(target, false, true) || '';
        if (value) return this.withoutExpiredJwtCookies(value);
      } catch (error) {
        const code = Number((error as Record<string, Object>)['code'] || 0);
        if (code === 801) return await this.fetchCookieAsync(url);
        if (code !== 17100002) console.warn('[LightCookieSemantics] 分区 Cookie 读取失败，code=' + code);
      }
    }
    return '';
  }

  private static async writeAllAsync(url: string, values: string[]): Promise<void> {
    const writes: Promise<void>[] = [];
    for (const target of this.targetUrls(url)) {
      for (const value of values) writes.push(this.writeCookieAsync(target, value));
    }
    await Promise.all(writes);
  }

  private static async writeCookieAsync(target: string, value: string): Promise<void> {
    try {
      await webview.WebCookieManager.configCookie(target, value, false, true);
      return;
    } catch (_) {
    }
    try {
      await webview.WebCookieManager.configCookie(target, value);
    } catch (error) {
      // Never log the cookie itself; a write that fails here silently drops the login state of that site.
      console.warn('[LightCookieSemantics] 写入 Cookie 失败:', LogText.url(target), (error as Error).message);
    }
  }

  private static writeCookieVariants(url: string, value: string): void {
    for (const target of this.targetUrls(url)) {
      try {
        webview.WebCookieManager.configCookieSync(target, value, true, true);
        continue;
      } catch (_) {
      }
      try {
        webview.WebCookieManager.configCookieSync(target, value, true);
      } catch (error) {
        // Never log the cookie itself; a write that fails here silently drops the login state of that site.
        console.warn('[LightCookieSemantics] 写入 Cookie 失败:', LogText.url(target), (error as Error).message);
      }
    }
  }

  static clearAll(): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync(true);
    } catch (error) {
      console.warn('[LightCookieSemantics] 清空 Cookie 失败:', (error as Error).message);
    }
  }

  static saveAsync(): void { /* Encrypted persistence is flushed by the source lease. */ }

  static saveSync(): void {
    try {
      webview.WebCookieManager.saveCookieSync();
    } catch (_) {
      this.saveAsync();
    }
  }

  /**
   * WebCookieManager can retain a session cookie after the JWT carried by that cookie has
   * expired. Sending it again may prevent an authentication bootstrap endpoint from issuing a
   * replacement. Filter only self-describing JWT cookie values whose `exp` is unequivocally in
   * the past; opaque cookies and malformed values are preserved unchanged.
   */
  static withoutExpiredJwtCookies(cookies: string): string {
    const valid: string[] = [];
    for (const item of (cookies || '').split(';')) {
      const pair = item.trim();
      const separator = pair.indexOf('=');
      if (separator <= 0) continue;
      const value = pair.substring(separator + 1).trim();
      if (this.isExpiredJwt(value)) continue;
      // Tombstones written by removeCookie() when ArkWeb would not drop the cookie outright.
      if (value === this.TOMBSTONE_VALUE) continue;
      valid.push(pair);
    }
    return valid.join('; ');
  }

  private static isExpiredJwt(value: string): boolean {
    const segments = (value || '').split('.');
    if (segments.length !== 3 || !segments[1]) return false;
    try {
      let payload = segments[1].replace(/-/g, '+').replace(/_/g, '/');
      while (payload.length % 4 !== 0) payload += '=';
      const bytes = new util.Base64Helper().decodeSync(payload);
      const text = util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false });
      const parsed = JSON.parse(text) as Record<string, Object>;
      const expiresAt = Number(parsed['exp'] || 0) * 1000;
      return Number.isFinite(expiresAt) && expiresAt > 0 && expiresAt <= Date.now();
    } catch (_) {
      return false;
    }
  }

  private static targetUrls(url: string): string[] {
    const value = (url || '').trim();
    if (!value) return [];
    const result: string[] = [value];
    if (!/^https?:\/\//i.test(value) && /^[A-Za-z0-9.-]+(?::\d+)?(?:\/.*)?$/.test(value) && value.includes('.')) {
      result.push(`https://${value}`);
    }
    return result;
  }
}
