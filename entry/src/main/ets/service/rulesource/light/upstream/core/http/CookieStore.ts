import deviceInfo from '@ohos.deviceInfo';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { LogText } from '../../utils/LogText';
import { SetCookieParser } from './SetCookieParser';
import { SourceEngineHost, SourceCookieJar } from '../host/SourceEngineHost';

export class CookieStore {
  /** Legacy unscoped callers keep the ArkWeb jar; source execution always supplies its identity. */
  static forSource(sourceUrl: string = ''): SourceCookieJar {
    return SourceEngineHost.cookies(sourceUrl) || CookieStore;
  }

  static getRequestCookie(url: string): string {
    if (deviceInfo.sdkApiVersion < 26) return this.getCookie(url);
    for (const target of this.targetUrls(url)) {
      try {
        const value = webview.WebCookieManager.fetchCookieSync(target, false, true) || '';
        if (value) return this.withoutExpiredJwtCookies(value);
      } catch (error) {
        const code = Number((error as Record<string, Object>)['code'] || 0);
        if (code === 801) return this.getCookie(url);
        if (code !== 17100002) console.warn('[CookieStore] 分区 Cookie 读取失败，code=' + code);
      }
    }
    return '';
  }

  private static readonly TOMBSTONE_VALUE = '__removed__';

  static getCookie(url: string): string {
    if (!url) return '';
    for (const target of this.targetUrls(url)) {
      try {
        const value = webview.WebCookieManager.fetchCookieSync(target) || '';
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
          webview.WebCookieManager.configCookieSync(target, value, false, true);
        } catch (_) {
          try {
            webview.WebCookieManager.configCookieSync(target, value);
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

  static removeCookie(url: string, name?: string): void {
    if (!url) return;
    const current = this.getRequestCookie(url);
    const ordinaryNames = this.getCookie(url).split(';').map((part: string): string => part.trim().split('=')[0]);
    const names = name ? [name] : current.split(';').map(item => item.trim().split('=')[0]).filter(item => item.length > 0);
    for (const cookieName of names) {
      if (ordinaryNames.indexOf(cookieName) < 0) continue;
      // ArkWeb refuses to store expired cookies ("if the cookie has expired, it will not be
      // stored"), so the classic Max-Age=0 write is a silent no-op and the cookie survives.
      // Verify after each step and escalate: first an empty-value tombstone (server sees an
      // anonymous session), then a placeholder value that is filtered out on every read.
      this.writeCookieVariants(url, `${cookieName}=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/`);
      if (this.getCookieValue(url, cookieName)) {
        this.writeCookieVariants(url, `${cookieName}=; Max-Age=31536000; Path=/`);
      }
      if (this.getCookieValue(url, cookieName)) {
        this.writeCookieVariants(url, `${cookieName}=${this.TOMBSTONE_VALUE}; Max-Age=31536000; Path=/`);
      }
    }
    if (deviceInfo.sdkApiVersion >= 26 && /^https:/i.test(url)) {
      for (const cookieName of names) {
        // Partitioned writes remain partitioned; do not materialize them in the unpartitioned jar.
        for (const path of ['', '; Path=/']) {
          this.writeCookieVariants(url, `${cookieName}=; Secure; HttpOnly; SameSite=None; Partitioned${path}; Max-Age=0`);
          if (this.getRequestCookie(url).split(';').some((pair: string): boolean => pair.trim().startsWith(cookieName + '='))) {
            this.writeCookieVariants(url, `${cookieName}=${this.TOMBSTONE_VALUE}; Secure; HttpOnly; SameSite=None; Partitioned${path}; Max-Age=60`);
          }
        }
      }
    }
    this.saveAsync();
  }

  private static writeCookieVariants(url: string, value: string): void {
    for (const target of this.targetUrls(url)) {
      try {
        webview.WebCookieManager.configCookieSync(target, value, false, true);
        continue;
      } catch (_) {
      }
      try {
        webview.WebCookieManager.configCookieSync(target, value);
      } catch (error) {
        // Never log the cookie itself; a write that fails here silently drops the login state of that site.
        console.warn('[CookieStore] 写入 Cookie 失败:', LogText.url(target), (error as Error).message);
      }
    }
  }

  static clearAll(): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (error) {
      console.warn('[CookieStore] 清空 Cookie 失败:', (error as Error).message);
    }
  }

  static saveAsync(): void {
    try {
      webview.WebCookieManager.saveCookieAsync();
    } catch (error) {
      console.warn('[CookieStore] 持久化 Cookie 失败:', (error as Error).message);
    }
  }

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
  private static withoutExpiredJwtCookies(cookies: string): string {
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
