/** Script-visible headers use lowercase names; Set-Cookie lines are never comma-joined. */
export class HttpHeaderValues {
  static normalize(headers: Record<string, Object>): Record<string, string> {
    const result: Record<string, string> = {};
    for (const name of Object.keys(headers || {})) {
      const key = name.toLowerCase();
      if (key === '__proto__' || key === 'constructor' || key === 'prototype') continue;
      const raw = headers[name];
      if (raw === undefined || raw === null) continue;
      const separator = key === 'set-cookie' ? '\n' : ', ';
      const value = Array.isArray(raw) ? raw.map((part: Object): string => String(part)).join(separator) : String(raw);
      result[key] = result[key] === undefined ? value : result[key] + separator + value;
    }
    return result;
  }
}
