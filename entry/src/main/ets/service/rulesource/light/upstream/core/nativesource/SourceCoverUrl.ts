/** A persistent HTTP URL with a local-only source reference. Never send the fragment to HTTP. */
export class SourceCoverUrl {
  static readonly MARKER = '#source-cover-v1=';

  private static readonly HEADERS_MARKER = '&headers=';

  static wrap(url: string, source: string, headers: Record<string, string> = {}): string {
    if (!/^https?:\/\//i.test(url) || !source) return url;
    const clean = this.cleanHeaders(headers);
    const result = url.split('#')[0] + this.MARKER + encodeURIComponent(source) +
      (Object.keys(clean).length ? this.HEADERS_MARKER + encodeURIComponent(JSON.stringify(clean)) : '');
    if (result.length > 8192) throw new Error('Cover URL and headers too long');
    return result;
  }

  static isEncoded(raw: string): boolean { return raw.includes(this.MARKER); }

  static source(raw: string): string {
    if (raw.length > 8192) throw new Error('Cover URL too long');
    const index = raw.indexOf(this.MARKER);
    if (index < 0) return '';
    const source = decodeURIComponent(raw.substring(index + this.MARKER.length).split(this.HEADERS_MARKER)[0]);
    if (!/^https?:\/\//i.test(source)) throw new Error('Invalid cover source');
    return source;
  }

  static cleanHeaders(headers: Record<string, string>): Record<string, string> {
    const result: Record<string, string> = {};
    const names: Record<string, string> = { 'accept': 'Accept', 'accept-language': 'Accept-Language',
      'referer': 'Referer', 'origin': 'Origin', 'user-agent': 'User-Agent', 'cookie': 'Cookie',
      'authorization': 'Authorization' };
    for (const name of Object.keys(headers).sort()) {
      const canonical = names[name.toLowerCase()];
      const value = headers[name];
      if (canonical && typeof value === 'string' && value.trim() && !/[\r\n]/.test(value)) result[canonical] = value.trim();
    }
    return result;
  }

  static headers(raw: string): Record<string, string> {
    this.source(raw);
    const marker = raw.indexOf(this.MARKER);
    const index = marker < 0 ? -1 : raw.indexOf(this.HEADERS_MARKER, marker + this.MARKER.length);
    if (index < 0) return {};
    const parsed = JSON.parse(decodeURIComponent(raw.substring(index + this.HEADERS_MARKER.length))) as Record<string, string>;
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('Invalid cover headers');
    return this.cleanHeaders(parsed);
  }

  static address(raw: string): string {
    const url = raw.split('#')[0];
    if (!/^https?:\/\//i.test(url)) throw new Error('Invalid cover address');
    return url;
  }
}
