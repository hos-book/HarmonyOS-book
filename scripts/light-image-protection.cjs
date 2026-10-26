// Host protections are reapplied by sync-light-source.cjs, never edited into generated files.
module.exports = function protectComicImages(text) {
  const replace = (before, after) => {
    if (text.split(before).length !== 2) throw Error('Upstream comic image protection entry changed: ' + before);
    text = text.replace(before, after);
  };
  replace("import { ReaderCacheBudget } from './ReaderCacheBudget';",
    "import { ReaderCacheBudget } from './ReaderCacheBudget';\nimport { SourceEngineHost } from '../host/SourceEngineHost';");
  replace('forceLocal: boolean = false, cancelled: () => boolean = (): boolean => false, index: number = 0,',
    'forceLocal: boolean = false, shouldCancel: () => boolean = (): boolean => false, index: number = 0,');
  replace('    timing: ComicImageTiming | null = null): Promise<string> {',
    '    timing: ComicImageTiming | null = null): Promise<string> {\n' +
    '    const cancelled = (): boolean => shouldCancel() || SourceEngineHost.isCancelled(source);');
  replace('    if (spec.decodeScript && (spec.processPlainImages || !this.looksLikeImage(bytes))) {',
    "    if (bytes.length > this.MAX_IMAGE_BYTES) throw new Error('图片超过 20 MiB');\n" +
    '    if (spec.decodeScript && (spec.processPlainImages || !this.looksLikeImage(bytes))) {');
  replace('      if (decoded.length > 0) bytes = decoded;', '      bytes = decoded;');
  replace('    if (!this.looksLikeImage(bytes)) return spec.url;',
    "    if (bytes.length > this.MAX_IMAGE_BYTES) throw new Error('图片解码结果超过 20 MiB');\n" +
    '    if (!bytes.length || !this.looksLikeImage(bytes)) {\n' +
    "      if (spec.decodeScript || spec.decodeAlgorithm || decodeRule) throw new Error('图片解码未返回有效图片');\n" +
    '      return spec.url;\n    }');
  replace(`    try {
      fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    } finally {
      fs.closeSync(file);
    }`, `    try {
      try {
        let written = 0;
        while (written < bytes.byteLength) {
          if (cancelled()) throw new Error(HttpClient.CANCELLED_ERROR);
          const end = Math.min(bytes.byteLength, written + 1024 * 1024);
          const count = fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset + written, bytes.byteOffset + end));
          if (!Number.isInteger(count) || count <= 0 || count > end - written) throw new Error('图片缓存写入失败');
          written += count;
        }
        if (cancelled()) throw new Error(HttpClient.CANCELLED_ERROR);
      } finally {
        fs.closeSync(file);
      }
    } catch (error) {
      // Close first, then remove incomplete output so the next request cannot hit a corrupt cache.
      try { fs.unlinkSync(path); } catch (_) {}
      throw error;
    }`);
  return text;
};
