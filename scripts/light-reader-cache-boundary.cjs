// Keep the imported parsing helpers on the app's cache service, without the upstream reader database.
module.exports = function readerCacheBoundary(name, text) {
  const replace = (before, after) => {
    if (text.split(before).length !== 2) throw Error('Upstream reader cache boundary changed: ' + name + ': ' + before);
    text = text.replace(before, after);
  };
  if (name === 'core/book/ComicImagePipeline.ts') {
    replace("import { ReaderImageCache } from './ReaderImageCache';\n", '');
    replace("AppStorage.get<string>('appFilesDir')", "AppStorage.get<string>('appCacheDir')");
    replace('    const dir = ReaderImageCache.directory();', '    const dir = `${cacheDir}/comic_images`;');
    // ReaderCacheBudget.touchComicFile above already registers the hit with ReaderCacheService.
    replace('      await ReaderImageCache.registerExisting(existing, source.bookSourceUrl, raw, imageIndex);\n', '');
    // The bounded, cancellation-aware writer is applied next by light-image-protection.cjs.
    replace('    await ReaderImageCache.commit(path, bytes, source.bookSourceUrl, raw, imageIndex);', `    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    } finally {
      fs.closeSync(file);
    }`);
    replace('        if (ReaderImageCache.exists(path)) return path;',
      '        const stat = fs.statSync(path);\n        if (stat.isFile() && stat.size > 0) return path;');
  }
  if (name === 'core/book/WebBookService.ts') {
    for (const line of ["import { ReaderImageRecovery } from './ReaderImageRecovery';\n",
      "import { appDb } from '../../model/data/AppDatabase';\n",
      "import { ReaderImageCache } from './ReaderImageCache';\n",
      "import { ReaderImageReferences } from './ReaderImageReferences';\n"]) replace(line, '');
    // ComicReaderService owns source-bound original markers and repairs missing files through its existing pipeline.
    const method = /  \/\*\* Repair known resources[^\n]*\n  async restoreCachedImages\([\s\S]*?\n  \}\n\n/;
    if (!method.test(text)) throw Error('Upstream reader image recovery entry changed');
    text = text.replace(method, '');
  }
  return text;
};
