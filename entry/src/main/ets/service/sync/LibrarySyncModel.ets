import { Book } from '../../model/Book';

export const LIBRARY_SYNC_CHANGED: string = 'app.library.sync.changed';
export const LIBRARY_SYNC_MAX_BYTES: number = 8 * 1024 * 1024;

/** 独立字段合并，移出书架不会删除续读位置，也不会被一次进度更新重新加回。 */
export class LibrarySyncValue {
  kind: string = '';
  bookId: string = '';
  value: string = '';

  constructor(kind: string = '', bookId: string = '', value: string = '') {
    this.kind = kind;
    this.bookId = bookId;
    this.value = value;
  }

  static key(item: LibrarySyncValue): string { return `${item.kind}:${item.bookId}`; }

  static online(id: string): boolean {
    return typeof id === 'string' && id.length > 0 && id.length <= 8192 && !id.startsWith('import_');
  }
}

export class LibrarySyncRecord extends LibrarySyncValue {
  changedAt: number = 0;
  writer: string = '';
}

class LibrarySyncProgressData {
  bookId: string = '';
  chapterId: string = '';
  chapterTitle: string = '';
  chapterIndex: number = 0;
  positionMs: number = 0;
  durationMs: number = 0;
  updatedAt: number = 0;
  speed?: number;
  sourceUrl?: string;
  bookUrl?: string;
  resourceIndex: number = 0;
  charOffset: number = 0;
  pageOffset: number = 0;
  domPos: string = '';
}

/** 只传可迁移的书籍身份和显示元数据；不传 Cookie、脚本变量、章节或本机文件路径。 */
export class LibrarySyncBook {
  id: string = '';
  title: string = '';
  author: string = '';
  narrator: string = '';
  cover: string = '';
  contentType: string = 'audio';
  bookUrl: string = '';
  sourceUrl: string = '';
  chapterCount: number = 0;

  static fromBook(book: Book): LibrarySyncBook {
    const value = new LibrarySyncBook();
    value.id = book.id;
    value.title = book.title.substring(0, 4096);
    value.author = book.author.substring(0, 4096);
    value.narrator = book.narrator.substring(0, 4096);
    value.cover = LibrarySyncBook.webUrl(book.cover) ? book.cover : '';
    value.contentType = book.contentType ?? 'audio';
    value.bookUrl = book.bookUrl;
    value.sourceUrl = book.sourceUrl;
    value.chapterCount = book.chapterCount;
    return value;
  }

  static webUrl(value: string): boolean {
    return typeof value === 'string' && value.length <= 16384 && /^https?:\/\//i.test(value);
  }

  static valid(value: LibrarySyncBook): boolean {
    return !!value && LibrarySyncValue.online(value.id) &&
      [value.title, value.author, value.narrator].every((s: string): boolean =>
        typeof s === 'string' && s.length <= 4096) &&
      (value.cover === '' || LibrarySyncBook.webUrl(value.cover)) &&
      ['audio', 'text', 'comic'].includes(value.contentType) &&
      LibrarySyncBook.webUrl(value.bookUrl) && typeof value.sourceUrl === 'string' &&
      value.sourceUrl.length > 0 && value.sourceUrl.length <= 8192 &&
      !value.sourceUrl.startsWith('builtin://') &&
      Number.isSafeInteger(value.chapterCount) && value.chapterCount >= 0;
  }

  toBook(): Book {
    const kind: 'audio' | 'text' | 'comic' = this.contentType === 'text' ? 'text' :
      this.contentType === 'comic' ? 'comic' : 'audio';
    const book: Book = {
      id: this.id, title: this.title, author: this.author, narrator: this.narrator,
      cover: this.cover, contentType: kind, sourceUrl: this.sourceUrl, bookUrl: this.bookUrl,
      chapterCount: this.chapterCount, chapters: [], tocComplete: false,
      category: '', intro: '', totalDuration: 0, rating: 0, tags: []
    };
    return book;
  }
}

export class LibrarySyncEnvelope {
  version: number = 1;
  ownerKey: string = '';
  deviceId: string = '';
  revision: number = 0;
  records: LibrarySyncRecord[] = [];
}

export class LibrarySyncState extends LibrarySyncEnvelope {
  baseline: LibrarySyncValue[] = [];
  applying: LibrarySyncValue[] = [];
  clock: number = 0;
  cloudFile: string = '';
  cloudRevision: number = -1;
  lastSyncedAt: number = 0;
}

/** 可重复、与输入顺序无关的逐字段 LWW 合并；空值是永久保留的删除标记。 */
export class LibrarySyncModel {
  static capture(state: LibrarySyncState, values: LibrarySyncValue[], initial: boolean = false): boolean {
    const before = new Map<string, LibrarySyncValue>();
    const current = new Map<string, LibrarySyncValue>();
    const records = new Map<string, LibrarySyncRecord>();
    state.baseline.forEach((v: LibrarySyncValue): void => { before.set(LibrarySyncValue.key(v), v); });
    values.forEach((v: LibrarySyncValue): void => { current.set(LibrarySyncValue.key(v), v); });
    state.records.forEach((v: LibrarySyncRecord): void => { records.set(LibrarySyncValue.key(v), v); });
    const keys = new Set<string>(Array.from(before.keys()).concat(Array.from(current.keys())));
    let changed = false;
    keys.forEach((key: string): void => {
      const previous = before.get(key);
      const value = current.get(key);
      if ((previous?.value ?? '') === (value?.value ?? '')) return;
      const source = value ?? previous;
      if (!source) return;
      if (initial && records.has(key)) return;
      const record = new LibrarySyncRecord(source.kind, source.bookId, value?.value ?? '');
      // 初次接入的历史数据不能盖过其他设备已产生的编辑或删除。
      record.changedAt = initial ? 1 : Math.max(Date.now(), state.clock + 1);
      record.writer = state.deviceId;
      state.clock = Math.max(state.clock, record.changedAt);
      records.set(key, record);
      changed = true;
    });
    if (changed) {
      state.records = Array.from(records.values()).sort(LibrarySyncModel.order);
      state.revision++;
    }
    state.baseline = values;
    return changed;
  }

  static order(a: LibrarySyncValue, b: LibrarySyncValue): number {
    const left = LibrarySyncValue.key(a);
    const right = LibrarySyncValue.key(b);
    return left < right ? -1 : left > right ? 1 : 0;
  }

  static merge(state: LibrarySyncState, incoming: LibrarySyncEnvelope): boolean {
    if (incoming.ownerKey !== state.ownerKey) throw new Error('Account mismatch');
    const merged = new Map<string, LibrarySyncRecord>();
    state.records.forEach((v: LibrarySyncRecord): void => { merged.set(LibrarySyncValue.key(v), v); });
    let changed = false;
    incoming.records.forEach((v: LibrarySyncRecord): void => {
      const key = LibrarySyncValue.key(v);
      const old = merged.get(key);
      if (!old || v.changedAt > old.changedAt ||
        (v.changedAt === old.changedAt && v.writer > old.writer)) {
        merged.set(key, v);
        state.clock = Math.max(state.clock, v.changedAt);
        changed = true;
      }
    });
    if (merged.size > 20000) throw new Error('Sync record limit exceeded');
    if (changed) {
      state.records = Array.from(merged.values()).sort(LibrarySyncModel.order);
      state.revision++;
    }
    return changed;
  }

  static acknowledge(state: LibrarySyncState, applied: LibrarySyncValue[]): void {
    const baseline = new Map<string, LibrarySyncValue>();
    state.baseline.forEach((v: LibrarySyncValue): void => { baseline.set(LibrarySyncValue.key(v), v); });
    applied.forEach((v: LibrarySyncValue): void => {
      if (v.value) baseline.set(LibrarySyncValue.key(v), new LibrarySyncValue(v.kind, v.bookId, v.value));
      else baseline.delete(LibrarySyncValue.key(v));
    });
    state.baseline = Array.from(baseline.values()).sort(LibrarySyncModel.order);
  }

  static encode(state: LibrarySyncState): string {
    const envelope = new LibrarySyncEnvelope();
    envelope.ownerKey = state.ownerKey;
    envelope.deviceId = state.deviceId;
    envelope.revision = state.revision;
    envelope.records = state.records;
    return JSON.stringify(envelope);
  }

  static parse(raw: string, ownerKey: string): LibrarySyncEnvelope {
    if (raw.length > LIBRARY_SYNC_MAX_BYTES) throw new Error('Sync file too large');
    const value: LibrarySyncEnvelope = JSON.parse(raw);
    if (!value || value.version !== 1 || value.ownerKey !== ownerKey ||
      typeof value.deviceId !== 'string' || !/^[0-9a-f-]{36}$/.test(value.deviceId) ||
      !Number.isSafeInteger(value.revision) || value.revision < 0 ||
      !Array.isArray(value.records) || value.records.length > 20000) throw new Error('Invalid sync file');
    const keys = new Set<string>();
    for (const record of value.records) {
      if (!LibrarySyncModel.validRecord(record) || keys.has(LibrarySyncValue.key(record))) {
        throw new Error('Invalid sync record');
      }
      keys.add(LibrarySyncValue.key(record));
    }
    return value;
  }

  static validRecord(record: LibrarySyncRecord): boolean {
    if (!record || !LibrarySyncValue.online(record.bookId) ||
      !['shelf', 'pin', 'group', 'book', 'play', 'text'].includes(record.kind) ||
      typeof record.value !== 'string' || record.value.length > 64 * 1024 ||
      !Number.isSafeInteger(record.changedAt) || record.changedAt < 1 ||
      record.changedAt > Date.now() + 24 * 60 * 60 * 1000 ||
      typeof record.writer !== 'string' || !/^[0-9a-f-]{36}$/.test(record.writer)) return false;
    if (!record.value) return true;
    if (record.kind === 'shelf' || record.kind === 'pin') return record.value === '1';
    if (record.kind === 'group') return record.value.length <= 256;
    if (record.kind === 'book') {
      try {
        const book: LibrarySyncBook = JSON.parse(record.value);
        return LibrarySyncBook.valid(book) && book.id === record.bookId;
      } catch (_error) { return false; }
    }
    return LibrarySyncModel.validProgress(record.kind, record.bookId, record.value);
  }

  static validProgress(kind: string, bookId: string, raw: string): boolean {
    try {
      const p: LibrarySyncProgressData = JSON.parse(raw);
      if (!p || p.bookId !== bookId || typeof p.chapterTitle !== 'string' || p.chapterTitle.length > 8192 ||
        !Number.isSafeInteger(p.updatedAt) || p.updatedAt < 0 || p.updatedAt > Date.now() + 86400000) return false;
      if (kind === 'text') return typeof p.domPos === 'string' && p.domPos.length <= 8192 &&
        [p.resourceIndex, p.charOffset, p.pageOffset].every((n: number): boolean => Number.isSafeInteger(n) && n >= 0);
      return typeof p.chapterId === 'string' && p.chapterId.length <= 8192 &&
        [p.chapterIndex, p.positionMs, p.durationMs].every((n: number): boolean => Number.isFinite(n) && n >= 0) &&
        (p.speed === undefined || (Number.isFinite(p.speed) && p.speed > 0 && p.speed <= 10)) &&
        (p.sourceUrl === undefined || (typeof p.sourceUrl === 'string' && p.sourceUrl.length <= 8192)) &&
        (p.bookUrl === undefined || (typeof p.bookUrl === 'string' && p.bookUrl.length <= 16384));
    } catch (_error) { return false; }
  }
}

/** 页面生命周期标记；服务后台同步不触发正在阅听的页面跳转。 */
export class LibrarySyncActivity {
  static reading: Set<string> = new Set();
  static playing: Set<string> = new Set();
  static remotePlayback: Set<string> = new Set();
}
