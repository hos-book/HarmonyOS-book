/** Protocol preferences are process-local and expire, so a transient network fault is never permanent. */
export class HttpProtocolPolicy {
  static forceHttp1: boolean = false;
  private static readonly TTL_MS: number = 10 * 60 * 1000;
  private static readonly MAX_ORIGINS: number = 128;
  private static preferredUntil: Map<string, number> = new Map<string, number>();

  static prefersHttp1(url: string, now: number = Date.now()): boolean {
    if (this.forceHttp1) return true;
    const origin = this.origin(url);
    const expires = this.preferredUntil.get(origin) || 0;
    if (expires > now) return true;
    this.preferredUntil.delete(origin);
    return false;
  }

  static mayRetry(url: string, method: string, error: string): boolean {
    // Even a protocol error can arrive after a POST was processed. Never replay it implicitly.
    if (!this.origin(url) || !['GET', 'HEAD'].includes((method || 'GET').toUpperCase())) return false;
    return /2300016|2300999|http\/?2|framing layer|curl(?:_|\s*)code\s*(?:result\s*)?[=:]?\s*92\b/i.test(error || '');
  }

  static rememberSuccess(url: string, now: number = Date.now()): void {
    const origin = this.origin(url);
    if (!origin) return;
    const expired: string[] = [];
    this.preferredUntil.forEach((until: number, key: string): void => {
      if (until <= now) expired.push(key);
    });
    for (const key of expired) this.preferredUntil.delete(key);
    this.preferredUntil.delete(origin);
    if (this.preferredUntil.size >= this.MAX_ORIGINS) {
      const oldest = this.preferredUntil.keys().next();
      if (!oldest.done) this.preferredUntil.delete(oldest.value);
    }
    this.preferredUntil.set(origin, now + this.TTL_MS);
  }

  static forget(url: string): void {
    this.preferredUntil.delete(this.origin(url));
  }

  private static origin(url: string): string {
    const match = /^https:\/\/([^/?#]+)(?:[/?#]|$)/i.exec(url || '');
    if (!match || /[\s@]/.test(match[1])) return '';
    return 'https://' + match[1].toLowerCase().replace(/:443$/, '');
  }
}
