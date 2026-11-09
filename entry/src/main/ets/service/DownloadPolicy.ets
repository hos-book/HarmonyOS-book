import { Chapter } from '../model/Book';

export interface DownloadGenerationSnapshot {
  global: number;
  book: number;
  chapter: number;
}

export type DownloadFailureCode = 'network' | 'storage' | 'invalid_response'
  | 'unsupported_hls' | 'cancelled' | 'unknown';

export type DownloadBookDerivedStatus = 'idle' | 'queued' | 'downloading' | 'paused' | 'completed' | 'failed';
export type DownloadChapterDerivedStatus = 'pending' | 'resolving' | 'downloading'
  | 'completed' | 'failed' | 'deleted';
export type DownloadFileProbeResult = 'ok' | 'missing' | 'size_mismatch' | 'too_small' | 'stat_error';

export class DownloadPolicy {
  static stablePageUrl(chapter: Chapter): string {
    const origin = chapter.originSourceValue || '';
    if (origin && !DownloadPolicy.isLocalPath(origin)) return origin;
    if (chapter.source.type === 'url' && chapter.source.value && !DownloadPolicy.isLocalPath(chapter.source.value)) {
      return chapter.source.value;
    }
    return '';
  }

  static isHttpUrl(url: string): boolean {
    const lower = (url || '').toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  static isLocalPath(value: string): boolean {
    const lower = (value || '').trim().toLowerCase();
    return lower.startsWith('/') || lower.startsWith('file://') || lower.startsWith('rawfile://');
  }

  static isGenerationCurrent(snapshot: DownloadGenerationSnapshot, current: DownloadGenerationSnapshot,
    paused: boolean, deleted: boolean): boolean {
    return snapshot.global === current.global && snapshot.book === current.book
      && snapshot.chapter === current.chapter && !paused && !deleted;
  }

  static generationToken(snapshot: DownloadGenerationSnapshot): string {
    return `${snapshot.global}:${snapshot.book}:${snapshot.chapter}`;
  }

  static taskKey(bookId: string, pageUrl: string): string {
    return `${bookId}|${pageUrl}`;
  }

  static rebaseStoragePath(path: string, sourceRoot: string, destinationRoot: string): string {
    if (!path || !sourceRoot || !destinationRoot) return path;
    if (path === sourceRoot) return destinationRoot;
    const sourcePrefix = sourceRoot.endsWith('/') ? sourceRoot : sourceRoot + '/';
    if (!path.startsWith(sourcePrefix)) return path;
    const destinationPrefix = destinationRoot.endsWith('/') ? destinationRoot : destinationRoot + '/';
    return destinationPrefix + path.substring(sourcePrefix.length);
  }

  static matchesChapter(chapterId: string, pageUrl: string, targetChapterId: string,
    targetPageUrl: string): boolean {
    const sourceUrl = (pageUrl || '').trim();
    const expectedUrl = (targetPageUrl || '').trim();
    if (sourceUrl && expectedUrl) return sourceUrl === expectedUrl;
    return chapterId === targetChapterId;
  }

  static deriveBookStatus(currentStatus: DownloadBookDerivedStatus,
    chapterStatuses: DownloadChapterDerivedStatus[]): DownloadBookDerivedStatus {
    const tracked = chapterStatuses.filter((status: DownloadChapterDerivedStatus) => status !== 'deleted');
    const active = tracked.some((status: DownloadChapterDerivedStatus) => status === 'pending'
      || status === 'resolving' || status === 'downloading');
    if (currentStatus === 'paused' && active) return 'paused';
    if (active) return 'downloading';
    if (tracked.some((status: DownloadChapterDerivedStatus) => status === 'failed')) return 'failed';
    if (tracked.length > 0
      && tracked.every((status: DownloadChapterDerivedStatus) => status === 'completed')) return 'completed';
    return 'idle';
  }

  static classifyFileProbeErrorCode(code: number): DownloadFileProbeResult {
    return code === 13900002 ? 'missing' : 'stat_error';
  }

  /**
   * 判定书源解析结果是否是可用的音频地址。
   * 解析失败时上游会原样回传章节页 URL（如 source://chapter/...），
   * 这类值不能当作解析成功，否则会被装进播放器/下载器产生误导性报错。
   */
  static isResolvedAudioUrl(pageUrl: string, audioUrl: string, resolved: boolean = false): boolean {
    if (!audioUrl || !DownloadPolicy.isHttpUrl(audioUrl)) return false;
    if (resolved || audioUrl !== pageUrl) return true;
    return DownloadPolicy.looksLikeDirectAudioUrl(audioUrl);
  }

  static looksLikeDirectAudioUrl(url: string): boolean {
    const lower = (url || '').toLowerCase();
    return lower.indexOf('.mp3') >= 0 || lower.indexOf('.m4a') >= 0
      || lower.indexOf('.aac') >= 0 || lower.indexOf('.flac') >= 0
      || lower.indexOf('.wav') >= 0 || lower.indexOf('.ogg') >= 0
      || /\.m3u8(?:[?#]|$)/i.test(url);
  }

  static isHls(url: string, contentType: string): boolean {
    const cleanUrl = url.toLowerCase().split('?')[0];
    const type = contentType.toLowerCase();
    return cleanUrl.endsWith('.m3u8') || type.includes('mpegurl');
  }

  static isAllowedAudioContentType(contentType: string): boolean {
    if (!contentType) return true;
    const type = contentType.toLowerCase().split(';')[0].trim();
    if (type.startsWith('audio/')) return true;
    return type === 'application/octet-stream' || type === 'binary/octet-stream'
      || type === 'application/mp4' || type === 'video/mp4'
      || type === 'application/ogg' || type === 'application/x-ogg' || type === 'video/ogg'
      || type === 'application/vnd.ms-asf' || type === 'video/x-ms-asf';
  }

  static appendPrefix(current: ArrayBuffer, chunk: ArrayBuffer, maxLength: number = 64): ArrayBuffer {
    if (maxLength <= 0) return new ArrayBuffer(0);
    const existing = new Uint8Array(current);
    const incoming = new Uint8Array(chunk);
    const length = Math.min(maxLength, existing.length + incoming.length);
    const result = new Uint8Array(length);
    const existingLength = Math.min(existing.length, length);
    for (let i = 0; i < existingLength; i++) result[i] = existing[i];
    const incomingLength = length - existingLength;
    for (let i = 0; i < incomingLength; i++) result[existingLength + i] = incoming[i];
    return result.buffer;
  }

  static hasKnownAudioSignature(buffer: ArrayBuffer): boolean {
    const bytes = new Uint8Array(buffer);
    if (DownloadPolicy.matchesAscii(bytes, 0, 'ID3') || DownloadPolicy.matchesAscii(bytes, 0, 'fLaC')
      || DownloadPolicy.matchesAscii(bytes, 0, 'OggS') || DownloadPolicy.matchesAscii(bytes, 0, 'MAC ')) return true;
    if (DownloadPolicy.matchesAscii(bytes, 0, 'RIFF') && DownloadPolicy.matchesAscii(bytes, 8, 'WAVE')) return true;
    if (DownloadPolicy.matchesAscii(bytes, 0, 'FORM')
      && (DownloadPolicy.matchesAscii(bytes, 8, 'AIFF') || DownloadPolicy.matchesAscii(bytes, 8, 'AIFC'))) return true;
    if (bytes.length >= 8 && DownloadPolicy.matchesAscii(bytes, 4, 'ftyp')) return true;
    if (DownloadPolicy.matchesAscii(bytes, 0, '#!AMR\n')
      || DownloadPolicy.matchesAscii(bytes, 0, '#!AMR-WB\n')) return true;
    if (DownloadPolicy.matchesBytes(bytes, 0,
      [0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C])) return true;
    if (bytes.length >= 2 && bytes[0] === 0xFF && (bytes[1] & 0xE0) === 0xE0) return true;
    return false;
  }

  static isClearlyTextResponse(buffer: ArrayBuffer): boolean {
    if (DownloadPolicy.hasKnownAudioSignature(buffer)) return false;
    const bytes = new Uint8Array(buffer);
    let offset = 0;
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) offset = 3;
    while (offset < bytes.length && DownloadPolicy.isAsciiWhitespace(bytes[offset])) offset++;
    if (offset >= bytes.length) return true;
    let text = '';
    for (let i = offset; i < bytes.length; i++) {
      const value = bytes[i];
      if (!DownloadPolicy.isPrintableAscii(value) && !DownloadPolicy.isAsciiWhitespace(value)) return false;
      text += String.fromCharCode(value);
    }
    const lower = text.trim().toLowerCase();
    if (lower.startsWith('<') || lower.startsWith('{') || lower.startsWith('[')) return true;
    if (lower.startsWith('error') || lower.startsWith('access denied') || lower.startsWith('forbidden')
      || lower.startsWith('not found') || lower.startsWith('unauthorized') || lower.startsWith('bad gateway')
      || lower.startsWith('service unavailable') || lower.startsWith('too many requests')) return true;
    return lower.length >= 8;
  }

  static classifyFailure(message: string): DownloadFailureCode {
    const lower = (message || '').toLowerCase();
    if (lower.includes('取消') || lower.includes('cancel')) return 'cancelled';
    if (lower.includes('hls') || lower.includes('m3u8') || lower.includes('mpegurl')) return 'unsupported_hls';
    if (lower.includes('空间') || lower.includes('目录') || lower.includes('存储')
      || lower.includes('enospc') || lower.includes('no space')) return 'storage';
    if (lower.includes('响应不是音频') || lower.includes('文本错误页') || lower.includes('有效音频')
      || lower.includes('文件过小') || lower.includes('文件头')
      || lower.includes('下载不完整') || lower.includes('写入不完整') || lower.includes('落盘不完整')
      || lower.includes('大小与记录不符') || lower.includes('http ')
      || lower.includes('下载失败 4') || lower.includes('下载失败 5')) return 'invalid_response';
    if (lower.includes('timeout') || lower.includes('timed out') || lower.includes('network')
      || lower.includes('socket') || lower.includes('connect') || lower.includes('econn')
      || lower.includes('网络')) return 'network';
    return 'unknown';
  }

  static failureText(code: DownloadFailureCode): string {
    if (code === 'network') return '网络中断，请稍后重试';
    if (code === 'storage') return '存储空间不足或目录不可用';
    if (code === 'invalid_response') return '下载响应不是有效音频';
    if (code === 'unsupported_hls') return '暂不支持 HLS 音频离线下载';
    if (code === 'cancelled') return '下载已取消';
    return '下载失败，请重试';
  }

  private static matchesAscii(bytes: Uint8Array, offset: number, value: string): boolean {
    if (offset < 0 || bytes.length < offset + value.length) return false;
    for (let i = 0; i < value.length; i++) {
      if (bytes[offset + i] !== value.charCodeAt(i)) return false;
    }
    return true;
  }

  private static matchesBytes(bytes: Uint8Array, offset: number, values: number[]): boolean {
    if (offset < 0 || bytes.length < offset + values.length) return false;
    for (let i = 0; i < values.length; i++) {
      if (bytes[offset + i] !== values[i]) return false;
    }
    return true;
  }

  private static isAsciiWhitespace(value: number): boolean {
    return value === 0x09 || value === 0x0A || value === 0x0D || value === 0x20;
  }

  private static isPrintableAscii(value: number): boolean {
    return value >= 0x21 && value <= 0x7E;
  }
}
