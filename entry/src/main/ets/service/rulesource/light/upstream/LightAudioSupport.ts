import { BookSource } from './model/data/Book';
import { AudioRuleSupport } from './core/book/AudioRuleSupport';
import { BookUrlResolver } from './core/book/BookUrlResolver';
import { VerificationSupport } from './core/http/VerificationSupport';
export class LightAudioSupport {
  resolveAudioUrl(raw: string, baseUrl: string = ''): string {
    let value = String(raw || '').trim();
    if (!value) return '';
    if (value.startsWith('"') && value.endsWith('"')) {
      try { value = String(JSON.parse(value)); } catch (_) {}
    }
    value = this.decodeAudioRuleValue(value);
    try {
      const parsed = JSON.parse(value) as Record<string, Object>;
      const candidate = this.audioUrlFromObject(parsed, baseUrl);
      if (candidate) return candidate;
    } catch (_) {}

    const tagMatch = value.match(/<(?:audio|source)\b[^>]*\b(?:src|data-src|data-url)\s*=\s*["']([^"']+)["'][^>]*>/i) ||
      value.match(/<(?:audio|source)\b[^>]*\b(?:src|data-src|data-url)\s*=\s*([^\s>]+)[^>]*>/i);
    if (tagMatch && tagMatch[1]) {
      const taggedUrl = this.normalizeAudioCandidate(tagMatch[1], baseUrl, true);
      if (taggedUrl) return taggedUrl;
    }

    const fieldMatch = value.match(/["']?(?:audio_url|audioUrl|play_url|playUrl|playurl|listenUrl|streamUrl|mediaUrl|src|file|path|url)["']?\s*[:=]\s*["']([^"']+)["']/i);
    if (fieldMatch && fieldMatch[1]) {
      const fieldUrl = this.normalizeAudioCandidate(fieldMatch[1], baseUrl, true);
      if (fieldUrl) return fieldUrl;
    }

    // HTML/JS chapter pages often contain covers, analytics and API links before the player.
    // Prefer a media-looking address so a generic first URL cannot mask the actual stream.
    const mediaMatch = value.match(/(?:https?:)?\/\/[^\s"'<>\\]+?\.(?:aac|flac|m3u8|m4a|mp3|mp4|ogg|opus|wav)(?:\?[^\s"'<>\\]*)?/i);
    if (mediaMatch) {
      const mediaUrl = this.normalizeAudioCandidate(mediaMatch[0], baseUrl, true);
      if (mediaUrl) return mediaUrl;
    }

    const absoluteMatch = value.match(/https?:\/\/[^\s"'<>]+/i);
    if (absoluteMatch) {
      const absoluteUrl = this.normalizeAudioCandidate(absoluteMatch[0], baseUrl, true);
      if (absoluteUrl) return absoluteUrl;
    }
    const protocolRelativeMatch = value.match(/\/\/[A-Za-z0-9.-]+(?::\d+)?\/[^\s"'<>]*/);
    if (protocolRelativeMatch) {
      const protocolRelativeUrl = this.normalizeAudioCandidate(protocolRelativeMatch[0], baseUrl, true);
      if (protocolRelativeUrl) return protocolRelativeUrl;
    }
    return this.normalizeAudioCandidate(value, baseUrl, false);
  }

  audioUrlFromObject(value: Record<string, Object>, baseUrl: string): string {
    const keys = ['audio_url', 'audioUrl', 'play_url', 'playUrl', 'playurl', 'main_url', 'mainUrl',
      'listenUrl', 'downloadUrl', 'streamUrl', 'mediaUrl', 'backup_url', 'backupUrl', 'src', 'file', 'path',
      'url', 'url_list', 'urlList', 'backup_urls', 'backupUrls', 'audio_list', 'audioList', 'play_info',
      'playInfo', 'decodedContent', 'content', 'data', 'result', 'payload', 'audio', 'media'];
    for (const key of keys) {
      const item = value[key];
      if (typeof item === 'string') {
        const candidate = this.resolveAudioUrl(item, baseUrl);
        if (candidate) return candidate;
      } else if (item && typeof item === 'object' && !Array.isArray(item)) {
        const nested = this.audioUrlFromObject(item as Record<string, Object>, baseUrl);
        if (nested) return nested;
      } else if (Array.isArray(item)) {
        for (const entry of item as Object[]) {
          if (typeof entry === 'string') {
            const candidate = this.resolveAudioUrl(entry, baseUrl);
            if (candidate) return candidate;
          }
          if (entry && typeof entry === 'object') {
            const nested = this.audioUrlFromObject(entry as Record<string, Object>, baseUrl);
            if (nested) return nested;
          }
        }
      }
    }
    return '';
  }

  invalidAudioAddressMessage(raw: string): string {
    // 取正文失败时内容为空，原因记在书源阶段错误里（例如接口返回的 code/message、书源给的说明）。
    if (!(raw || '').trim()) {
      const stageError = (AppStorage.get<string>('bookSourceStageLastError') || '').trim();
      if (stageError) return stageError;
    }
    try {
      const root = JSON.parse(raw || '{}') as Record<string, Object>;
      let data: Record<string, Object> = root;
      if (root['data'] && typeof root['data'] === 'object' && !Array.isArray(root['data'])) {
        data = root['data'] as Record<string, Object>;
      }
      const message = String(root['error'] || root['message'] || root['msg'] ||
        data['error'] || data['message'] || data['msg'] || '').trim();
      if (message) return `音频接口未返回可播放地址：${message}`;
    } catch (_) {}
    return '正文规则没有返回有效音频地址';
  }

  decodeAudioRuleValue(raw: string): string {
    return String(raw || '').trim()
      .replace(/&amp;/gi, '&')
      .replace(/&quot;/gi, '"')
      .replace(/&#39;|&apos;/gi, "'")
      .replace(/\\u002[fF]|\\x2[fF]/g, '/')
      .replace(/\\u003[aA]|\\x3[aA]/g, ':')
      .replace(/\\u0026|\\x26/gi, '&')
      .replace(/\\u003[dD]|\\x3[dD]/g, '=')
      .replace(/\\\//g, '/');
  }

  normalizeAudioCandidate(raw: string, baseUrl: string, trustPlainValue: boolean): string {
    let value = this.decodeAudioRuleValue(raw)
      .replace(/^url\(\s*|\s*\)$/gi, '')
      .replace(/^["']|["']$/g, '')
      .trim();
    value = value.replace(/,\s*\{[\s\S]*$/, '').replace(/[),.;\]}]+$/, '');
    if (!value || /\s/.test(value) || /^(?:javascript:|data:|about:|#)/i.test(value)) return '';

    const isExplicitUrl = /^(?:https?:)?\/\//i.test(value) || /^\.?\.?\//.test(value);
    const isLikelyMediaPath = /\.(?:aac|flac|m3u8|m4a|mp3|mp4|ogg|opus|wav)(?:[?#].*)?$/i.test(value);
    const isLikelyRelativeEndpoint = /^[A-Za-z0-9._~-]+(?:\/|\?)[^\s<>{}\[\]"']+$/.test(value);
    if (!isExplicitUrl && !isLikelyMediaPath && !isLikelyRelativeEndpoint && !trustPlainValue) return '';
    const resolved = BookUrlResolver.resolve(value, baseUrl);
    return /^https?:\/\//i.test(resolved) ? resolved : '';
  }

  audioHeaders(url: string, source: BookSource | null, ruleValue: string = ''): Record<string, string> {
    const explicit = AudioRuleSupport.splitRequestOptions(this.decodeAudioRuleValue(ruleValue)).headers;
    let headers = this.sourceAudioHeaders(source);
    if (source) {
      headers = AudioRuleSupport.scopeHeadersToMediaHost(headers, source.bookSourceUrl, url);
      // The cookie jar is already scoped to the media address, so it applies on any host.
      const cookie = VerificationSupport.sourceCookieHeader(source, url);
      if (cookie) headers = AudioRuleSupport.mergeHeaders(headers, { 'Cookie': cookie });
    }
    return AudioRuleSupport.mergeHeaders(headers, explicit);
  }

  private sourceAudioHeaders(source: BookSource | null): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36'
    };
    if (!source) return headers;
    const rawHeader = source.header || '';
    try {
      const parsed = JSON.parse(rawHeader.replace(/'/g, '"')) as Record<string, string>;
      for (const key of Object.keys(parsed)) {
        const value = String(parsed[key] || '');
        if (key && value && !value.includes('java.')) headers[key] = value;
      }
    } catch (_) {
      const regex = /["']([A-Za-z0-9_-]+)["']\s*:\s*["']([^"']+)["']/g;
      let match: RegExpExecArray | null;
      while ((match = regex.exec(rawHeader)) !== null) {
        const key = match[1] || '';
        const value = match[2] || '';
        if (key && value && !value.includes('java.')) headers[key] = value;
      }
    }
    return headers;
  }
}
