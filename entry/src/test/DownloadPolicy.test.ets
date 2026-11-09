import { describe, it, expect } from '@ohos/hypium';
import { DownloadPolicy, DownloadGenerationSnapshot } from '../main/ets/service/DownloadPolicy';
import { Chapter } from '../main/ets/model/Book';

function bytes(values: number[]): ArrayBuffer {
  const buffer = new ArrayBuffer(values.length);
  const target = new Uint8Array(buffer);
  for (let i = 0; i < values.length; i++) target[i] = values[i];
  return buffer;
}

export default function downloadPolicyTest() {
  describe('DownloadPolicy', () => {
    it('invalidates stale task generations after pause or delete', 0, () => {
      const captured: DownloadGenerationSnapshot = { global: 1, book: 2, chapter: 3 };
      expect(DownloadPolicy.isGenerationCurrent(captured, captured, false, false)).assertEqual(true);
      expect(DownloadPolicy.isGenerationCurrent(captured, { global: 1, book: 3, chapter: 3 }, false, false))
        .assertEqual(false);
      expect(DownloadPolicy.isGenerationCurrent(captured, captured, true, false)).assertEqual(false);
      expect(DownloadPolicy.isGenerationCurrent(captured, captured, false, true)).assertEqual(false);
    });

    it('prefers stable page url when matching chapters', 0, () => {
      expect(DownloadPolicy.matchesChapter('old-id', 'https://audio.test/page/1', 'new-id',
        'https://audio.test/page/1')).assertEqual(true);
      expect(DownloadPolicy.matchesChapter('same-id', 'https://audio.test/page/old', 'same-id',
        'https://audio.test/page/new')).assertEqual(false);
      expect(DownloadPolicy.matchesChapter('same-id', 'https://audio.test/page/old', 'same-id', ''))
        .assertEqual(true);
      expect(DownloadPolicy.matchesChapter('same-id', '', 'same-id', 'https://audio.test/page/new'))
        .assertEqual(true);
    });

    it('rebases only paths inside the legacy download root', 0, () => {
      const cacheRoot = '/data/storage/el2/base/cache/downloads';
      const filesRoot = '/data/storage/el2/base/files/downloads';
      expect(DownloadPolicy.rebaseStoragePath(`${cacheRoot}/audio/book/chapter.mp3`, cacheRoot, filesRoot))
        .assertEqual(`${filesRoot}/audio/book/chapter.mp3`);
      expect(DownloadPolicy.rebaseStoragePath(cacheRoot, cacheRoot, filesRoot)).assertEqual(filesRoot);
      expect(DownloadPolicy.rebaseStoragePath(`${cacheRoot}_backup/audio.mp3`, cacheRoot, filesRoot))
        .assertEqual(`${cacheRoot}_backup/audio.mp3`);
      expect(DownloadPolicy.rebaseStoragePath('', cacheRoot, filesRoot)).assertEqual('');
    });

    it('rejects unresolved page urls echoed back by the source', 0, () => {
      expect(DownloadPolicy.isResolvedAudioUrl('source://chapter/123/1', 'source://chapter/123/1'))
        .assertEqual(false);
      expect(DownloadPolicy.isResolvedAudioUrl('jianhu://audio-chapter/9', 'jianhu://audio-chapter/9'))
        .assertEqual(false);
      expect(DownloadPolicy.isResolvedAudioUrl('source://chapter/123/1', ''))
        .assertEqual(false);
      expect(DownloadPolicy.isResolvedAudioUrl('source://chapter/123/1', 'https://cdn.test/a.m4a?sign=x'))
        .assertEqual(true);
      expect(DownloadPolicy.isResolvedAudioUrl('https://audio.test/page/1', 'https://audio.test/page/1'))
        .assertEqual(false);
      expect(DownloadPolicy.isResolvedAudioUrl('https://audio.test/track.mp3', 'https://audio.test/track.mp3'))
        .assertEqual(true);
    });

    it('rejects hls and non audio responses', 0, () => {
      expect(DownloadPolicy.isHls('https://audio.test/book.m3u8?token=1', '')).assertEqual(true);
      expect(DownloadPolicy.isHls('https://audio.test/play', 'application/vnd.apple.mpegurl')).assertEqual(true);
      expect(DownloadPolicy.isAllowedAudioContentType('audio/mpeg')).assertEqual(true);
      expect(DownloadPolicy.isAllowedAudioContentType('application/octet-stream')).assertEqual(true);
      expect(DownloadPolicy.isAllowedAudioContentType('text/html; charset=utf-8')).assertEqual(false);
    });

    it('uses the original http url for chapters currently backed by a local file', 0, () => {
      const chapter: Chapter = {
        id: 'chapter-1',
        index: 1,
        title: '第一章',
        duration: 0,
        source: { type: 'file', value: '/data/storage/audio.mp3' },
        originSourceValue: 'https://audio.test/chapter/1'
      };
      expect(DownloadPolicy.stablePageUrl(chapter)).assertEqual('https://audio.test/chapter/1');
      chapter.originSourceValue = '';
      expect(DownloadPolicy.stablePageUrl(chapter)).assertEqual('');
      chapter.source = { type: 'url', value: '../chapter/1,{"webView":true}' };
      expect(DownloadPolicy.stablePageUrl(chapter)).assertEqual('../chapter/1,{"webView":true}');
    });

    it('recognizes common audio signatures', 0, () => {
      const id3 = bytes([0x49, 0x44, 0x33, 0x04]);
      const mp3 = bytes([0xFF, 0xFB, 0x90, 0x64]);
      const adts = bytes([0xFF, 0xF1, 0x50, 0x80]);
      const flac = bytes([0x66, 0x4C, 0x61, 0x43]);
      const ogg = bytes([0x4F, 0x67, 0x67, 0x53]);
      const wav = bytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]);
      const aiff = bytes([0x46, 0x4F, 0x52, 0x4D, 0, 0, 0, 0, 0x41, 0x49, 0x46, 0x46]);
      const mp4 = bytes([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70]);
      const amr = bytes([0x23, 0x21, 0x41, 0x4D, 0x52, 0x0A]);
      const asf = bytes([0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11,
        0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C]);
      const ape = bytes([0x4D, 0x41, 0x43, 0x20]);
      expect(DownloadPolicy.hasKnownAudioSignature(id3)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(mp3)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(adts)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(flac)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(ogg)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(wav)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(aiff)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(mp4)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(amr)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(asf)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(ape)).assertEqual(true);
      expect(DownloadPolicy.hasKnownAudioSignature(bytes([1, 2, 3, 4]))).assertEqual(false);
    });

    it('accumulates fragmented prefixes and rejects text payloads', 0, () => {
      let prefix = DownloadPolicy.appendPrefix(new ArrayBuffer(0), bytes([0x49]));
      prefix = DownloadPolicy.appendPrefix(prefix, bytes([0x44, 0x33, 0x04]));
      expect(DownloadPolicy.hasKnownAudioSignature(prefix)).assertEqual(true);
      const html = bytes([0x20, 0x3C, 0x68, 0x74, 0x6D, 0x6C, 0x3E]);
      const json = bytes([0x7B, 0x22, 0x65, 0x72, 0x72, 0x6F, 0x72, 0x22, 0x3A, 0x31, 0x7D]);
      expect(DownloadPolicy.isClearlyTextResponse(html)).assertEqual(true);
      expect(DownloadPolicy.isClearlyTextResponse(json)).assertEqual(true);
      expect(DownloadPolicy.isClearlyTextResponse(prefix)).assertEqual(false);
    });

    it('keeps paused only while unfinished chapters remain', 0, () => {
      expect(DownloadPolicy.deriveBookStatus('paused', ['completed', 'pending'])).assertEqual('paused');
      expect(DownloadPolicy.deriveBookStatus('paused', ['completed'])).assertEqual('completed');
      expect(DownloadPolicy.deriveBookStatus('paused', ['failed'])).assertEqual('failed');
      expect(DownloadPolicy.deriveBookStatus('downloading', ['completed', 'deleted'])).assertEqual('completed');
    });

    it('distinguishes missing files from other stat failures', 0, () => {
      expect(DownloadPolicy.classifyFileProbeErrorCode(13900002)).assertEqual('missing');
      expect(DownloadPolicy.classifyFileProbeErrorCode(13900012)).assertEqual('stat_error');
    });

    it('classifies stable download failure codes', 0, () => {
      expect(DownloadPolicy.classifyFailure('下载已取消')).assertEqual('cancelled');
      expect(DownloadPolicy.classifyFailure('暂不支持 HLS 音频离线下载')).assertEqual('unsupported_hls');
      expect(DownloadPolicy.classifyFailure('存储空间不足')).assertEqual('storage');
      expect(DownloadPolicy.classifyFailure('connect timeout')).assertEqual('network');
      expect(DownloadPolicy.classifyFailure('响应不是音频内容 text/html')).assertEqual('invalid_response');
      expect(DownloadPolicy.classifyFailure('音频文件落盘不完整 8192/3500000')).assertEqual('invalid_response');
      expect(DownloadPolicy.classifyFailure('已下载文件不完整（大小与记录不符）')).assertEqual('invalid_response');
    });
  });
}
