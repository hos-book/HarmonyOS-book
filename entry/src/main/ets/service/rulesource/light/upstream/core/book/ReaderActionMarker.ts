export class ReaderActionData {
  label: string = '';
  url: string = '';
  title: string = '';
  /** 热评原文（书源卡片上的文字或原生书源 hot 字段），阅读器可把它画成段落下方的热评卡。 */
  preview: string = '';
  /** 热评点赞数，按书源原样保存（如 "1.2k"）。 */
  likes: string = '';
}

export class ReaderActionMatch {
  marker: string = '';
  start: number = -1;
  end: number = -1;
  data: ReaderActionData = new ReaderActionData();
}

/** A persisted reader marker for source-provided actions such as paragraph comments. */
export class ReaderActionMarker {
  static readonly SOURCE_SCRIPT_SCHEME: string = 'legado-source-action:';
  static readonly PREFIX: string = '[[LEGADO_READER_ACTION_V3:';
  static readonly LEGACY_PREFIX: string = '[[LEGADO_READER_ACTION_V2:';
  static readonly ORIGINAL_PREFIX: string = '[[LEGADO_READER_ACTION:';
  static readonly SUFFIX: string = ']]';
  static readonly MAX_MARKER_LENGTH: number = 16384;
  static readonly MAX_LABEL_LENGTH: number = 96;
  static readonly MAX_TITLE_LENGTH: number = 192;
  static readonly MAX_URL_LENGTH: number = 12288;
  static readonly MAX_PREVIEW_LENGTH: number = 160;
  static readonly MAX_LIKES_LENGTH: number = 16;

  /** 热评原文：去掉标签、合并空白，最多 MAX_PREVIEW_LENGTH 个字符。 */
  static normalizePreview(value: string): string {
    return (value || '').replace(/<[^>]*>/g, ' ').replace(/[\s　]+/g, ' ').trim()
      .substring(0, ReaderActionMarker.MAX_PREVIEW_LENGTH);
  }

  static create(label: string, url: string, title: string = '', preview: string = '', likes: string = ''): string {
    const data = new ReaderActionData();
    data.label = ((label || '').trim() || '打开').substring(0, ReaderActionMarker.MAX_LABEL_LENGTH);
    data.url = (url || '').trim();
    data.title = (title || '').trim().substring(0, ReaderActionMarker.MAX_TITLE_LENGTH);
    if (!data.url || data.url.length > ReaderActionMarker.MAX_URL_LENGTH) return '';
    // 没有热评时只写 label/url/title，与旧版本标记逐字相同，已缓存章节不受影响。
    const record: Record<string, string> = { 'label': data.label, 'url': data.url, 'title': data.title };
    const safePreview = ReaderActionMarker.normalizePreview(preview);
    if (safePreview) {
      record['preview'] = safePreview;
      const safeLikes = (likes || '').trim().substring(0, ReaderActionMarker.MAX_LIKES_LENGTH);
      if (safeLikes) record['likes'] = safeLikes;
    }
    const marker = `${ReaderActionMarker.PREFIX}${encodeURIComponent(JSON.stringify(record))}` +
      `${ReaderActionMarker.SUFFIX}`;
    return marker.length <= ReaderActionMarker.MAX_MARKER_LENGTH ? marker : '';
  }

  /** Persist a user-triggered action supplied by the imported source without interpreting it. */
  static createSourceScript(label: string, script: string, title: string = '', preview: string = '',
    likes: string = ''): string {
    const code = (script || '').trim();
    if (!code || code.length > 4096) return '';
    return this.create(label, `${this.SOURCE_SCRIPT_SCHEME}${encodeURIComponent(code)}`, title, preview, likes);
  }

  static sourceScript(url: string): string {
    const value = (url || '').trim();
    if (!value.startsWith(this.SOURCE_SCRIPT_SCHEME)) return '';
    try {
      return decodeURIComponent(value.substring(this.SOURCE_SCRIPT_SCHEME.length));
    } catch (_) {
      return '';
    }
  }

  /** Compact provider action. Secrets and repeated endpoint data stay in the provider, outside measured text. */
  static createProviderComment(providerId: string, label: string, bookId: string, chapterId: string,
    paragraphId: string, mode: string = 'paragraph'): string {
    const safeLabel = (label || '').trim() || '段评';
    const safeProviderId = (providerId || '').trim();
    const safeBookId = (bookId || '').trim();
    const safeChapterId = (chapterId || '').trim();
    const safeParagraphId = (paragraphId || '').trim();
    if (!safeProviderId || !safeBookId || !safeChapterId || !safeParagraphId) return '';
    const modeCode = mode === 'chapterTitle' || mode === 'chapter' ? 'c' : 'p';
    const fields = [safeProviderId, safeLabel, safeBookId, safeChapterId, safeParagraphId]
      .map((value: string): string => encodeURIComponent(value));
    return `${ReaderActionMarker.PREFIX}P|${fields.join('|')}|${modeCode}${ReaderActionMarker.SUFFIX}`;
  }

  static parse(value: string): ReaderActionData | null {
    const text = (value || '').trim();
    if (!text || text.length > ReaderActionMarker.MAX_MARKER_LENGTH) return null;
    const prefix = text.startsWith(ReaderActionMarker.PREFIX) ? ReaderActionMarker.PREFIX :
      (text.startsWith(ReaderActionMarker.LEGACY_PREFIX) ? ReaderActionMarker.LEGACY_PREFIX :
        (text.startsWith(ReaderActionMarker.ORIGINAL_PREFIX) ? ReaderActionMarker.ORIGINAL_PREFIX : ''));
    if (!prefix || !text.endsWith(ReaderActionMarker.SUFFIX)) return null;
    const encoded = text.substring(prefix.length,
      text.length - ReaderActionMarker.SUFFIX.length);
    try {
      if (encoded.startsWith('P|')) {
        const fields = encoded.split('|');
        if (fields.length !== 7) return null;
        const providerId = decodeURIComponent(fields[1] || '');
        const label = (decodeURIComponent(fields[2] || '') || '段评')
          .substring(0, ReaderActionMarker.MAX_LABEL_LENGTH);
        const bookId = decodeURIComponent(fields[3] || '');
        const chapterId = decodeURIComponent(fields[4] || '');
        const paragraphId = decodeURIComponent(fields[5] || '');
        if (!providerId || !bookId || !chapterId || !paragraphId || providerId.length > 256 ||
          bookId.length > 1024 || chapterId.length > 1024 || paragraphId.length > 1024) return null;
        const data = new ReaderActionData();
        data.label = label;
        data.url = `legado-provider-action://${encodeURIComponent(providerId)}/${encodeURIComponent(bookId)}/` +
          `${encodeURIComponent(chapterId)}/${encodeURIComponent(paragraphId)}?mode=` +
          `${fields[6] === 'c' ? 'chapterTitle' : 'paragraph'}`;
        data.title = fields[6] === 'c' ? '章评' : '段评';
        return data;
      }
      const record = JSON.parse(decodeURIComponent(encoded)) as Record<string, Object>;
      const data = new ReaderActionData();
      data.label = String(record['label'] || '打开').substring(0, ReaderActionMarker.MAX_LABEL_LENGTH);
      data.url = String(record['url'] || '');
      data.title = String(record['title'] || '').substring(0, ReaderActionMarker.MAX_TITLE_LENGTH);
      data.preview = ReaderActionMarker.normalizePreview(String(record['preview'] || ''));
      data.likes = data.preview ?
        String(record['likes'] || '').trim().substring(0, ReaderActionMarker.MAX_LIKES_LENGTH) : '';
      if (data.url.length > ReaderActionMarker.MAX_URL_LENGTH) return null;
      return data.url ? data : null;
    } catch (_) {
      return null;
    }
  }

  static has(value: string): boolean {
    const text = value || '';
    return text.includes(ReaderActionMarker.PREFIX) || text.includes(ReaderActionMarker.LEGACY_PREFIX) ||
      text.includes(ReaderActionMarker.ORIGINAL_PREFIX);
  }

  static hasLegacy(value: string): boolean {
    const text = value || '';
    return text.includes(ReaderActionMarker.LEGACY_PREFIX) || text.includes(ReaderActionMarker.ORIGINAL_PREFIX);
  }

  static strip(value: string, preserveOffsets: boolean = false): string {
    const source = value || '';
    let cursor = 0;
    let result = '';
    while (cursor < source.length) {
      const bounds = this.findFirstRawRange(source, cursor);
      if (bounds.length < 2) {
        result += source.substring(cursor);
        break;
      }
      const start = bounds[0];
      const end = bounds[1];
      result += source.substring(cursor, start);
      if (preserveOffsets) result += ' '.repeat(Math.max(0, end - start));
      cursor = Math.max(start + 1, end);
    }
    return result;
  }

  /**
   * Drop damaged or excessive interaction metadata while retaining every正文 character. Imported sources can
   * attach a script to every paragraph; without a chapter budget those encoded scripts dominate memory during
   * open/pagination and may make the process look as if comments must be disabled to read the book.
   */
  static limit(value: string, maxCount: number = 320, maxTotalLength: number = 384 * 1024): string {
    const source = value || '';
    if (!ReaderActionMarker.has(source)) return source;
    let cursor = 0;
    const parts: string[] = [];
    let count = 0;
    let totalLength = 0;
    while (cursor < source.length) {
      const bounds = ReaderActionMarker.findFirstRawRange(source, cursor);
      if (bounds.length < 2) {
        parts.push(source.substring(cursor));
        break;
      }
      const start = bounds[0];
      const end = bounds[1];
      parts.push(source.substring(cursor, start));
      const marker = source.substring(start, end);
      const keep = marker.length <= ReaderActionMarker.MAX_MARKER_LENGTH && !!ReaderActionMarker.parse(marker) &&
        count < Math.max(0, maxCount) && totalLength + marker.length <= Math.max(0, maxTotalLength);
      if (keep) {
        parts.push(marker);
        count++;
        totalLength += marker.length;
      }
      cursor = end;
    }
    return parts.join('');
  }

  /**
   * Locate marker-shaped structure without requiring its payload to parse. Rendering still uses findFirst(),
   * but speech/copy sanitizers must never expose a damaged marker's URL, dimensions or script as正文.
   */
  static findFirstRawRange(value: string, fromIndex: number = 0): number[] {
    const source = value || '';
    const searchStart = Math.max(0, Math.min(Math.round(fromIndex), source.length));
    let start = -1;
    let matchedPrefix = '';
    for (const prefix of [ReaderActionMarker.PREFIX, ReaderActionMarker.LEGACY_PREFIX,
      ReaderActionMarker.ORIGINAL_PREFIX]) {
      const index = source.indexOf(prefix, searchStart);
      if (index >= 0 && (start < 0 || index < start)) {
        start = index;
        matchedPrefix = prefix;
      }
    }
    if (start < 0 || !matchedPrefix) return [];
    const suffix = source.indexOf(ReaderActionMarker.SUFFIX, start + matchedPrefix.length);
    if (suffix >= 0) return [start, suffix + ReaderActionMarker.SUFFIX.length];
    // A truncated marker is structural corruption, not prose. Limit recovery to its line when possible so a
    // damaged provider comment cannot consume the following paragraph.
    const lineEnd = source.indexOf('\n', start + matchedPrefix.length);
    return [start, lineEnd >= 0 ? lineEnd : source.length];
  }

  /** Return a marker-shaped range that already began before offset. */
  static findRawRangeContaining(value: string, offset: number): number[] {
    const source = value || '';
    const target = Math.max(0, Math.min(Math.round(offset), source.length));
    const searchStart = Math.max(0, target - ReaderActionMarker.MAX_MARKER_LENGTH);
    let start = -1;
    let matchedPrefix = '';
    for (const prefix of [ReaderActionMarker.PREFIX, ReaderActionMarker.LEGACY_PREFIX,
      ReaderActionMarker.ORIGINAL_PREFIX]) {
      const index = source.lastIndexOf(prefix, target);
      if (index >= searchStart && index > start) {
        start = index;
        matchedPrefix = prefix;
      }
    }
    if (start < 0 || !matchedPrefix) return [];
    const suffix = source.indexOf(ReaderActionMarker.SUFFIX, start + matchedPrefix.length);
    const end = suffix >= 0 && suffix - start <= ReaderActionMarker.MAX_MARKER_LENGTH ?
      suffix + ReaderActionMarker.SUFFIX.length :
      (() => {
        const lineEnd = source.indexOf('\n', start + matchedPrefix.length);
        return lineEnd >= 0 ? lineEnd : source.length;
      })();
    return target >= start && target < end ? [start, end] : [];
  }

  static findFirst(value: string, fromIndex: number = 0): ReaderActionMatch | null {
    const source = value || '';
    const searchStart = Math.max(0, Math.min(Math.round(fromIndex), source.length));
    let start = -1;
    for (const prefix of [ReaderActionMarker.PREFIX, ReaderActionMarker.LEGACY_PREFIX,
      ReaderActionMarker.ORIGINAL_PREFIX]) {
      const index = source.indexOf(prefix, searchStart);
      if (index >= 0 && (start < 0 || index < start)) start = index;
    }
    if (start < 0) return null;
    const endIndex = source.indexOf(ReaderActionMarker.SUFFIX, start + 1);
    if (endIndex < 0) return null;
    const end = endIndex + ReaderActionMarker.SUFFIX.length;
    const marker = source.substring(start, end);
    const data = ReaderActionMarker.parse(marker);
    if (!data) return null;
    const match = new ReaderActionMatch();
    match.marker = marker;
    match.start = start;
    match.end = end;
    match.data = data;
    return match;
  }

}
