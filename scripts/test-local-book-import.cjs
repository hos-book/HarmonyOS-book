// Real import/persistence services with temporary files and platform adapters.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const fsp = fs.promises;
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const { mobiFixture, MOBI_COVER_PNG } = require('./mobi-fixture.cjs');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hsda-import-test-'));
const context = { filesDir: temp.replaceAll('\\', '/'), cacheDir: temp.replaceAll('\\', '/') + '/cache' };
const strings = new Map(JSON.parse(fs.readFileSync(path.join(root, '../resources/base/element/string.json'), 'utf8'))
  .string.map(item => [item.name, item.value]));
context.resourceManager = {
  getStringByNameSync: name => strings.get(name),
  getStringSync: id => strings.get(id.replace('app.string.', ''))
};
let parserAvailable = true;
let parserLoads = 0;
let epubCount = 2;
let epubRaw = false;
let layoutCalls = 0;
let writeDelay = 0;
let failingWrite = '';
let activeWrites = 0;
let maxWrites = 0;
const handlePaths = new Map();
const handles = new Map();
let free = 256 * 1024 ** 3;
const fileIo = {
  OpenMode: { READ_ONLY: 0, CREATE: 1, WRITE_ONLY: 2, TRUNC: 4, READ_WRITE: 8 },
  async open(filename, flags) {
    const handle = await fsp.open(filename, flags ? 'w+' : 'r');
    handles.set(handle.fd, handle); handlePaths.set(handle.fd, filename); return { fd: handle.fd };
  },
  async close(file) { const fd = typeof file === 'number' ? file : file.fd; await handles.get(fd).close(); handles.delete(fd); handlePaths.delete(fd); },
  async stat(file) { return typeof file === 'number' ? handles.get(file).stat() : fsp.stat(file); },
  async read(fd, buffer, options = { length: buffer.byteLength, offset: 0 }) {
    return (await handles.get(fd).read(Buffer.from(buffer), 0, options.length, options.offset)).bytesRead;
  },
  async write(fd, text) {
    activeWrites++; maxWrites = Math.max(maxWrites, activeWrites);
    try {
      if (writeDelay) await new Promise(resolve => setTimeout(resolve, writeDelay));
      if (failingWrite && handlePaths.get(fd).endsWith(failingWrite)) throw new Error('injected write failure');
      return (await handles.get(fd).write(typeof text === 'string' ? text : Buffer.from(text))).bytesWritten;
    } finally { activeWrites--; }
  },
  async copyFile(source, target) {
    if (typeof source === 'string') return fsp.copyFile(source, target);
    await handles.get(target).writeFile(await handles.get(source).readFile());
  },
  async mkdir(directory) {
    // HarmonyOS recursive mkdir still reports EEXIST for an existing leaf directory.
    if (fs.existsSync(directory)) throw new Error('File exists');
    await fsp.mkdir(directory, { recursive: true });
  },
  rmdir: (directory) => fsp.rm(directory, { recursive: true, force: true }),
  readText: (filename) => fsp.readFile(filename, 'utf8'),
  listFile: directory => fsp.readdir(directory),
  async access(filename) { try { await fsp.access(filename); return true; } catch { return false; } },
  moveFile: (a, b) => fsp.rename(a, b),
  unlink: filename => fsp.unlink(filename),
  fsync: fd => handles.get(fd).sync()
};
const values = new Map();
const diagnosticSettings = new Map();
let diagnosticFlushFails = false;
let diagnosticOutputCount = 0;
const favorites = new Set();
const readingIds = new Set();
const historyIds = new Set();
const preference = {
  async getFavorites() { return [...favorites]; },
  async getHistory() { return [...historyIds].map(bookId => ({ bookId })); },
  async getCachedBooks() { return '[]'; },
  async getImportedBooks() { return values.get('books') || '[]'; },
  async saveImportedBooks(json) { values.set('books', json); }
};
const modules = new Map();
const decodedImages = [];
let liveImages = 0;
const image = {
  createImageSource(input) {
    liveImages++;
    const bytes = Buffer.from(input);
    return {
      async getImageInfo() {
        if (!bytes.equals(MOBI_COVER_PNG)) throw new Error('invalid image');
        return { size: { width: 60, height: 90 } };
      },
      async createPixelMap(options) {
        decodedImages.push(bytes); liveImages++;
        assert.equal(options.desiredSize.width, 60);
        return { release: async () => { liveImages--; } };
      },
      release: async () => { liveImages--; }
    };
  },
  createImagePacker() {
    liveImages++;
    return {
      async packToData(_pixels, options) {
        assert.equal(options.format, 'image/jpeg');
        return Uint8Array.from([0xff, 0xd8, 0xff, 0xd9]).buffer;
      },
      release: async () => { liveImages--; }
    };
  }
};
function load(relative) {
  let filename = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
  if (!fs.existsSync(filename)) filename = filename.slice(0, -4) + '.ts';
  if (modules.has(filename)) return modules.get(filename);
  const exports = {}; modules.set(filename, exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, console, Error, ArrayBuffer, Uint8Array, setTimeout,
    canIUse: () => parserAvailable, $r: id => ({ id }), require: name => {
    if (name === '@kit.CoreFileKit') return { fileIo, statfs: { getFreeSize: async () => free } };
    if (name === '@kit.ImageKit') return { image };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: {
      info() { diagnosticOutputCount++; }, error() { diagnosticOutputCount++; }
    } };
    if (name === '@kit.ArkData') return { preferences: { getPreferencesSync: () => ({
      getSync: (key, fallback) => diagnosticSettings.has(key) ? diagnosticSettings.get(key) : fallback,
      putSync: (key, value) => diagnosticSettings.set(key, value),
      async flush() { if (diagnosticFlushFails) throw new Error('settings write failed'); }
    }) } };
    if (name === '@kit.ArkTS') return { taskpool: { execute: async (fn, ...args) => fn(...args) }, util: { TextDecoder: { create(encoding, options) {
      const decoder = new TextDecoder(encoding, options);
      return { decodeToString: (bytes, opts) => decoder.decode(bytes, opts) };
    } } } };
    if (name === '@kit.BasicServicesKit') return {
      deviceInfo: { sdkApiVersion: 20, deviceType: 'phone' },
      zlib: { getOriginalSize: async () => 1024 }
    };
    if (name === '@hms.core.readerservice.bookParser') {
      parserLoads++;
      assert.ok(parserAvailable, 'unsupported devices must never load the ReaderKit HSP');
      return { bookParser: {
      getDefaultHandler: async () => ({
        getBookInfo: () => ({ bookTitle: 'EPUB 标题', bookCreator: '作者' }),
        getSpineList: () => Array.from({ length: epubCount }, (_, index) => ({ idRef: String(index), href: `text/${index}.html` })),
        getCatalogList: () => [{ idRef: '0', catalogName: '第一章' }, { idRef: '1', catalogName: '第二章' },
          { idRef: '1', catalogName: '同章内的二级目录，不应覆盖' }],
        getSpineItemContent: async index => { layoutCalls++; return `<body><p>章节 ${index + 1}</p><script>bad()</script></body>`; },
        getResourceContent: index => {
          if (!epubRaw) throw new Error('resource unavailable');
          return Uint8Array.from(Buffer.from(`<body><p>章节 ${index + 1}</p><script>bad()</script></body>`)).buffer;
        }
      })
    } };
    }
    if (name.endsWith('/TextReadingProgressService')) return { TextReadingProgressService: {
      async getAll() { return [...readingIds].map(bookId => ({ bookId })); }
    } };
    if (name.endsWith('/PreferenceService')) return { PreferenceService: preference };
    if (name.startsWith('@')) return {};
    return load(path.resolve(path.dirname(filename), name));
  } }, { filename });
  return exports;
}
(async () => {
  const { LocalBookImportService: service } = load('service/LocalBookImportService');
  const imageDirectory = path.join(context.filesDir, 'ebooks/import_image_fixture').replaceAll('\\', '/');
  await fsp.mkdir(imageDirectory, { recursive: true });
  const imageStats = { raw: 0, layout: 0, imageBytes: 0 };
  const body = await service.epubBody(context, { getResourceContent(index, relative) {
    assert.equal(index, 0); assert.equal(relative, 'images/figure.png');
    return Uint8Array.from(MOBI_COVER_PNG).buffer;
  } }, 0, '<p>图前文字</p><img src="images/figure.png"/><p>图后文字</p><img src="https://remote/blocked.png"/>', imageDirectory, imageStats);
  const { LocalTextImage: images } = load('service/text/LocalTextImage');
  images.setRoot(context.filesDir);
  const marker = images.pattern().exec(body);
  assert.ok(marker && body.includes('图前文字') && body.includes('图后文字'));
  assert.ok(images.resolve(marker[1]).startsWith('file://'));
  assert.equal(images.resolve(imageDirectory + '/../secret'), '');
  assert.deepEqual(await fsp.readFile(marker[1]), MOBI_COVER_PNG);
  assert.equal(imageStats.imageBytes, MOBI_COVER_PNG.length);
  assert.equal(images.speechContent(body).length, body.length);
  assert.ok(!images.speechContent(body).includes('image_0_0'));
  assert.equal(liveImages, 0, 'EPUB extraction releases decoder without decoding full bitmap');
  console.log('PASS EPUB body image extraction, local path confinement, remote rejection and speech offsets');
  assert.equal(parserLoads, 0, 'loading import service at startup must not load ReaderKit');
  parserAvailable = false;
  await assert.rejects(service.openEpub(context, '/unavailable.epub'), /当前设备不支持 EPUB 解析/);
  assert.equal(parserLoads, 0, 'capability failure must be handled before resolving the HSP');
  parserAvailable = true;
  const rawHtml = '<html><body>带空格路径的完整章节</body></html>';
  const rawBytes = Uint8Array.from(Buffer.from(rawHtml)).buffer;
  assert.equal(await service.epubSpineText({
    getSpineItemContent: async () => { throw new Error('Invalid request.'); },
    getResourceContent: (_index, name) => {
      if (name !== '33 - 副本.html') throw new Error('Not found');
      return rawBytes;
    }
  }, 29, 'text/33%20-%20副本.html'), rawHtml);
  await assert.rejects(service.epubSpineText({
    getSpineItemContent: async () => { throw new Error('Invalid request.'); },
    getResourceContent: () => { throw new Error('Not found'); }
  }, 29, 'missing.html'), /Invalid request/);
  const { DataService: data } = load('service/DataService');
  // A real release-cache fixture: preserve false, prefer canonical fields, tolerate malformed entries.
  const oldMetadata = { id: 'release_metadata', title: 'Release book', i36: 'Chapter 90', b40: false,
    i40: true, j40: 'https://example.test/search.jpg', chapters: [] };
  const migrated = data.parseBookList(JSON.stringify([null, 42, oldMetadata]));
  assert.equal(migrated.length, 1);
  assert.equal(migrated[0].latestChapterTitle, 'Chapter 90');
  assert.equal(migrated[0].tocComplete, false);
  assert.equal(migrated[0].coverFromDetail, true);
  assert.equal(migrated[0].coverFallback, oldMetadata.j40);
  const canonical = data.parseBookList(JSON.stringify([{ ...oldMetadata, latestChapterTitle: '',
    tocComplete: true, coverFromDetail: false, coverFallback: '' }]))[0];
  assert.equal(canonical.latestChapterTitle, '');
  assert.equal(canonical.tocComplete, true);
  assert.equal(canonical.coverFromDetail, false);
  assert.equal(canonical.coverFallback, '');
  const invalidMetadata = data.parseBookList(JSON.stringify([{ id: 'bad', b40: 'false', i40: 1, i36: 42 }]))[0];
  assert.equal(invalidMetadata.tocComplete, undefined);
  assert.equal(invalidMetadata.coverFromDetail, undefined);
  assert.equal(invalidMetadata.latestChapterTitle, undefined);
  values.set('books', JSON.stringify([oldMetadata]));
  assert.equal((await data.getImportedBooks())[0].tocComplete, false);
  values.delete('books');
  await fsp.mkdir(path.join(context.cacheDir, 'cached_toc'), { recursive: true });
  await fsp.mkdir(path.join(context.filesDir, 'cached_toc'), { recursive: true });
  const legacyBook = { id: 'migration_book', title: 'current cache', sourceUrl: 'source', bookUrl: 'book', chapters: [] };
  const legacyChapter = { id: 'migration_chapter', title: 'cached chapter', source: { type: 'url', value: 'chapter' } };
  await fsp.writeFile(path.join(context.cacheDir, 'cached_books_v1.json'), JSON.stringify([legacyBook]));
  await fsp.writeFile(path.join(context.cacheDir, 'cached_toc/migration_book.json'), JSON.stringify([legacyChapter]));
  await fsp.writeFile(path.join(context.filesDir, 'cached_books_v1.json'), JSON.stringify([{ ...legacyBook, title: 'stale' }]));
  await fsp.writeFile(path.join(context.filesDir, 'cached_toc/migration_book.json'), '[]');
  data.setContext(context);
  await data.migrationPromise;
  await fsp.rm(context.cacheDir, { recursive: true }); await fsp.mkdir(context.cacheDir);
  assert.equal((await data.getBookById(context, legacyBook.id)).title, 'current cache');
  assert.equal((await data.getChaptersForBook(legacyBook.id))[0].title, 'cached chapter');
  await data.clearCachedBooks(); data.cachedBooksMem = null;
  data.migrationPromise = null;
  assert.equal(await data.getBookById(context, legacyBook.id), undefined, 'explicit clear cannot resurrect old metadata');
  console.log('PASS metadata/TOC upgrade prefers current cache, survives system cleanup and respects explicit clear');
  const file = { uri: path.join(temp, 'novel.txt'), name: '小说', ext: '.txt' };
  const source = '第一章 初见\n你好世界\n第二章 重逢\n' + '文字😀'.repeat(20000);
  await fsp.writeFile(file.uri, source);
  const book = await service.importBook(context, file, 'import_123_text_0', '', '', '', () => {});
  assert.ok(book.chapters.length >= 3);
  assert.equal(book.chapters[0].title, '第一章 初见');
  const texts = await Promise.all(book.chapters.map(ch => fsp.readFile(ch.source.value, 'utf8')));
  assert.ok(texts.every(text => text.length <= 32000 && !text.includes('\uFFFD')));
  assert.equal(texts.join('').replaceAll('\n', ''), source.replaceAll('\n', ''));
  await data.addImportedBook(book);
  assert.equal(JSON.parse(values.get('books'))[0].chapters.length, 0);
  data.cache = null;
  const restored = await data.getBookById(context, book.id);
  assert.equal(restored.chapters.length, book.chapters.length);
  assert.equal(await data.readImportedText(restored, restored.chapters[0].source.value), texts[0]);
  await assert.rejects(() => data.readImportedText(restored, context.filesDir + '/other.txt'));

  for (const [name, bytes, expected] of [
    ['utf16', Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from('中文内容', 'utf16le')]), '中文内容'],
    ['gb18030', Buffer.from([0xd6, 0xd0, 0xce, 0xc4]), '中文']
  ]) {
    await fsp.writeFile(file.uri, bytes);
    const result = await service.importBook(context, file, 'import_' + name, '', '', '', () => {});
    assert.equal(await fsp.readFile(result.chapters[0].source.value, 'utf8'), expected);
  }
  file.ext = '.html';
  await fsp.writeFile(file.uri, '<html><head><title>ignore</title></head><body><h1>章节</h1><p>甲&amp;乙</p><script>bad()</script><p>尾声</p></body></html>');
  const html = await service.importBook(context, file, 'import_html', '', '', '', () => {});
  assert.equal(await fsp.readFile(html.chapters[0].source.value, 'utf8'), '章节\n\n甲&乙\n\n尾声');
  file.ext = '.epub';
  const epub = await service.importBook(context, file, 'import_epub', '', '', '', () => {});
  await data.addImportedBook(epub); // Existing imported_toc must not block a second import.
  assert.equal((await data.getImportedBooks()).length, 2);
  assert.equal(epub.title, 'EPUB 标题');
  assert.equal(epub.chapters.map(ch => ch.title).join(','), '第一章,第二章');
  assert.equal(await fsp.readFile(epub.chapters[1].source.value, 'utf8'), '章节 2');

  epubCount = 2200; epubRaw = true; layoutCalls = 0;
  writeDelay = 2; maxWrites = 0;
  const updates = [];
  const largeEpub = await service.importBook(context, file, 'import_pipeline', '', '', '', value => updates.push(value));
  assert.equal(largeEpub.chapters.length, 2200);
  assert.equal(layoutCalls, 0, 'available raw HTML must bypass layout conversion');
  assert.ok(maxWrites > 1 && maxWrites <= 4, `bounded writes: ${maxWrites}`);
  assert.ok(updates.length < 220 && updates.at(-1).endsWith('2200/2200'), 'throttled progress still emits final update');
  for (let index = 0; index < largeEpub.chapters.length; index++) {
    const chapter = largeEpub.chapters[index];
    assert.equal(chapter.index, index + 1);
    assert.equal(await fsp.readFile(chapter.source.value, 'utf8'), `章节 ${index + 1}`);
  }
  failingWrite = '/2.txt'; epubCount = 8;
  await assert.rejects(service.importBook(context, file, 'import_pipeline_fail', '', '', '', () => {}), /injected write failure/);
  assert.equal(activeWrites, 0, 'pending writes must settle before rollback');
  assert.equal(handles.size, 0);
  assert.equal(fs.existsSync(path.join(temp, 'ebooks/import_pipeline_fail')), false);
  failingWrite = ''; writeDelay = 0; epubCount = 2; epubRaw = false;
  console.log('PASS 2200-chapter EPUB: raw fast path, order/content, bounded writes, final progress, failure rollback');

  const audioInputs = [];
  for (let index = 0; index < 9; index++) {
    const uri = path.join(temp, `audio_${index}.mp3`);
    await fsp.writeFile(uri, `audio ${index}`);
    audioInputs.push({ uri, name: `track ${index}`, ext: '.mp3' });
  }
  const audioDir = path.join(temp, 'audio_test'); await fsp.mkdir(audioDir);
  let activeProbes = 0, maxProbes = 0;
  const audio = await service.importAudioChapters(context, 'import_audio', audioDir, audioInputs, '/not-an-extract-root', async path => {
    activeProbes++; maxProbes = Math.max(maxProbes, activeProbes);
    const n = Number(require('node:path').basename(path, '.mp3'));
    await new Promise(resolve => setTimeout(resolve, (5 - n % 4) * 2));
    activeProbes--; return n;
  }, () => {});
  assert.ok(maxProbes > 1 && maxProbes <= 4);
  for (let index = 0; index < audio.length; index++) {
    assert.equal(audio[index].index, index + 1);
    assert.equal(audio[index].duration, index + 1);
    assert.equal(await fsp.readFile(audio[index].source.value, 'utf8'), `audio ${index}`);
    assert.ok(fs.existsSync(audioInputs[index].uri), 'picker source files are not moved/deleted');
  }
  const zipRoot = path.join(temp, 'extract_test').replaceAll('\\', '/'); await fsp.mkdir(zipRoot);
  const zipAudio = `${zipRoot}/track.mp3`; await fsp.writeFile(zipAudio, 'zip audio');
  const zipAudioDir = path.join(temp, 'zip_audio_test'); await fsp.mkdir(zipAudioDir);
  await service.importAudioChapters(context, 'import_zip_audio', zipAudioDir,
    [{ uri: zipAudio, name: 'track', ext: '.mp3' }], zipRoot, async () => 0, () => {});
  assert.equal(fs.existsSync(zipAudio), false);
  assert.equal(await fsp.readFile(path.join(zipAudioDir, '1.mp3'), 'utf8'), 'zip audio');
  const reserveDir = path.join(temp, 'reserve_test'); await fsp.mkdir(reserveDir);
  free = 256 * 1024 ** 2 + 10; // One source fits, but four together do not.
  await assert.rejects(service.importAudioChapters(context, 'import_audio_full', reserveDir,
    audioInputs, '/not-an-extract-root', async () => 0, () => {}), /空间不足/);
  assert.equal((await fsp.readdir(reserveDir)).length, 0);
  free = 256 * 1024 ** 3;
  console.log('PASS audio: out-of-order completion retains chapter order, ZIP move, batch space reservation');

  assert.ok(service.TEXT_EXTS.includes('.mobi'), 'ZIP collection uses the same supported extensions');
  assert.ok(strings.get('import_file_filter').includes('.mobi'), 'Document picker exposes MOBI');
  file.ext = '.mobi';
  for (const compression of [1, 2]) {
    await fsp.writeFile(file.uri, mobiFixture({ compression }));
    const preview = await service.preview(context, file);
    assert.equal(preview.title, 'MOBI 测试书');
    assert.equal(preview.author, '测试作者');
    const mobi = await service.importBook(context, file, `import_mobi_${compression}`, '', '', '', () => {});
    assert.equal(mobi.title, preview.title);
    assert.equal(mobi.author, preview.author);
    assert.equal(mobi.chapters.map(ch => ch.title).join(','), '第一章 初见,第二章 重逢');
    assert.equal(await fsp.readFile(mobi.chapters[0].source.value, 'utf8'), '第一章 初见\n\n中文😀 & 正文');
    await data.addImportedBook(mobi);
    data.cache = null;
    const restoredMobi = await data.getBookById(context, mobi.id);
    assert.equal(await data.readImportedText(restoredMobi, restoredMobi.chapters[1].source.value),
      '第二章 重逢\n\n第二章内容');
    await data.removeImportedBook(mobi.id);
    assert.equal(fs.existsSync(path.join(temp, 'ebooks', mobi.id)), false);
  }
  // All PalmDOC opcodes: literals, overlapping LZ backrefs, space+char, binary literal runs.
  const opcodes = Buffer.from([0x61, 0x62, 0x63, 0x80, 0x1b, 0xd8, 3, 0xe4, 0xb8, 0xad]);
  await fsp.writeFile(file.uri, mobiFixture({ bytes: Buffer.from('abcabcabc X中'), records: [opcodes] }));
  const compressedMobi = await service.importBook(context, file, 'import_mobi_opcodes', '自定义书名', '自定义作者', '', () => {});
  assert.equal(compressedMobi.title, '自定义书名');
  assert.equal(compressedMobi.author, '自定义作者');
  assert.equal(await fsp.readFile(compressedMobi.chapters[0].source.value, 'utf8'), 'abcabcabc X中');

  // Trailing extra-data and multibyte overlap must be removed before decoding.
  await fsp.writeFile(file.uri, mobiFixture({ bytes: Buffer.from('ABC'), compression: 1, flags: 3,
    records: [Buffer.from([65, 66, 67, 0, 0, 0x82])], extraRecords: [Buffer.from('BOUNDARY'), Buffer.from('KF8')] }));
  const hybrid = await service.importBook(context, file, 'import_mobi_hybrid', '', '', '', () => {});
  assert.equal(await fsp.readFile(hybrid.chapters[0].source.value, 'utf8'), 'ABC');
  await fsp.writeFile(file.uri, mobiFixture({ bytes: Buffer.from([0x63, 0x61, 0x66, 0xe9]), compression: 1, encoding: 1252 }));
  const western = await service.importBook(context, file, 'import_mobi_1252', '', '', '', () => {});
  assert.equal(await fsp.readFile(western.chapters[0].source.value, 'utf8'), 'café');

  const invalidTable = mobiFixture(); invalidTable.writeUInt32BE(1, 86);
  const overLimit = mobiFixture(); overLimit.writeUInt32BE(33 * 1024 ** 2, overLimit.readUInt32BE(78) + 4);
  const badExth = mobiFixture(); badExth.writeUInt32BE(0xffffffff, badExth.readUInt32BE(78) + 248 + 4);
  for (const [bytes, message] of [
    [mobiFixture({ encryption: 1 }), /加密/],
    [mobiFixture({ version: 8 }), /KF8/],
    [mobiFixture({ compression: 17480 }), /HUFF/],
    [mobiFixture({ encoding: 936 }), /字符编码/],
    [mobiFixture().subarray(0, 50), /损坏/],
    [invalidTable, /损坏/], [badExth, /损坏/], [overLimit, /32 MiB/],
    [mobiFixture({ bytes: Buffer.from('test'), records: [Buffer.from([0x80, 0])] }), /损坏/],
    [mobiFixture({ bytes: Buffer.from('test'), records: [Buffer.from([8, 65])] }), /损坏/],
    [mobiFixture({ bytes: Buffer.from('test'), compression: 1, records: [Buffer.from('a')] }), /损坏/],
    [mobiFixture({ bytes: Buffer.from('test'), compression: 1, flags: 2, records: [Buffer.from([0])] }), /损坏/]
  ]) {
    await fsp.writeFile(file.uri, bytes);
    await assert.rejects(() => service.importBook(context, file, 'import_bad_mobi', '', '', '', () => {}), message);
    assert.equal(fs.existsSync(path.join(temp, 'ebooks/import_bad_mobi')), false);
    assert.equal(handles.size, 0);
  }
  console.log('PASS MOBI: metadata, uncompressed/PalmDOC, Chinese/emoji, chapters, persistence, trailing records, CP1252, rejection/cleanup');

  // The EXTH cover offset is relative to the first image record, not the file or text record list.
  for (const options of [
    { images: [Buffer.from('not a cover'), MOBI_COVER_PNG], coverOffset: 1 },
    { images: [Buffer.from('broken cover'), MOBI_COVER_PNG], coverOffset: 0, thumbnailOffset: 1 },
    { images: [MOBI_COVER_PNG] } // Legacy MOBI without EXTH cover index.
  ]) {
    await fsp.writeFile(file.uri, mobiFixture(options));
    const preview = await service.preview(context, file);
    assert.ok(preview.cover.endsWith('/cover.jpg'));
    const result = await service.importBook(context, file, 'import_mobi_cover', '', '', preview.cover, () => {});
    assert.equal(result.cover, context.filesDir + '/ebooks/import_mobi_cover/cover.jpg');
    await fsp.rm(preview.directory, { recursive: true });
    assert.ok(fs.existsSync(result.cover), 'saved cover survives preview cleanup');
    await data.addImportedBook(result);
    data.cache = null;
    assert.equal((await data.getBookById(context, result.id)).cover, result.cover);
    await data.removeImportedBook(result.id);
    assert.equal(fs.existsSync(result.cover), false);
    assert.equal(liveImages, 0);
  }
  await fsp.writeFile(file.uri, mobiFixture({ cover: true }));
  const directMobi = await service.importBook(context, file, 'import_mobi_direct_cover', '', '', '', () => {});
  assert.ok(fs.existsSync(directMobi.cover), 'ZIP imports extract a cover even without preview');
  const manualCover = path.join(temp, 'manual.jpg');
  await fsp.writeFile(manualCover, 'manual cover');
  const beforeManual = decodedImages.length;
  const manualMobi = await service.importBook(context, file, 'import_mobi_manual_cover', '', '', manualCover, () => {});
  assert.equal(await fsp.readFile(manualMobi.cover, 'utf8'), 'manual cover');
  assert.equal(decodedImages.length, beforeManual, 'user selected cover is not replaced');
  for (const options of [
    { images: [MOBI_COVER_PNG], coverOffset: 99999 },
    { images: [Buffer.from('bad image')], coverOffset: 0 },
    { images: [MOBI_COVER_PNG], firstImage: 1, coverOffset: 0 }
  ]) {
    await fsp.writeFile(file.uri, mobiFixture(options));
    const preview = await service.preview(context, file);
    assert.equal(preview.cover, '');
    assert.equal(preview.directory, '', 'empty preview directories are removed');
    const result = await service.importBook(context, file, 'import_mobi_no_cover', '', '', '', () => {});
    assert.equal(result.cover, '');
    assert.ok(result.chapters.length > 0);
    await fsp.rm(path.join(temp, 'ebooks/import_mobi_no_cover'), { recursive: true });
    assert.equal(liveImages, 0);
  }
  console.log('PASS MOBI covers: EXTH index, thumbnail/legacy fallback, direct ZIP import, persisted cover, manual override, corrupt image isolation');

  const online = { ...book, id: 'search_text_history', sourceUrl: 'source', bookUrl: 'book' };
  const largeChapters = Array.from({length:600},(_,i)=>({...online.chapters[0],id:`large_${i}`,
    variables:{payload:'中文'.repeat(120),__audioTocDefinition:'source'.repeat(4096)}}));
  await data.writeToc('large_chunks',largeChapters);
  const savedToc = JSON.parse(await fsp.readFile(path.join(temp,'library_toc/large_chunks.json'),'utf8'));
  assert.equal(savedToc.length,600,'all write chunks preserve one valid JSON array');
  assert.equal(savedToc[599].id,'large_599');
  assert.equal(savedToc[0].variables.__audioTocDefinition,undefined);
  const concurrentReads = await Promise.all([data.getChaptersForBook('large_chunks'),data.getChaptersForBook('large_chunks')]);
  assert.equal(concurrentReads[0],concurrentReads[1],'concurrent catalog loads share one parsed result');
  failingWrite = 'large_chunks.json.tmp';
  await data.writeToc('large_chunks',[online.chapters[0]]);
  failingWrite = '';
  assert.equal(JSON.parse(await fsp.readFile(path.join(temp,'library_toc/large_chunks.json'),'utf8')).length,600,
    'failed streaming write preserves the previous complete directory');
  // 未收藏直接阅读的书经过进程重启后仍可按进度 id 找回完整信息。
  await data.upsertCachedBook(online);
  readingIds.add(online.id);
  await data.upsertCachedBook({ ...online, id: 'favorite' });
  favorites.add('favorite');
  await data.upsertCachedBook({ ...online, id: 'audio_history' });
  historyIds.add('audio_history');
  for (let i = 0; i < 205; i++) await data.upsertCachedBook({ ...online, id: 'temporary_' + i });
  await fsp.rm(context.cacheDir, { recursive: true, force: true });
  await fsp.mkdir(context.cacheDir);
  data.cachedBooksMem = null;
  const readAgain = await data.getBookById(context, online.id);
  assert.equal(readAgain.title, online.title);
  assert.equal(readAgain.bookUrl, online.bookUrl);
  assert.equal(readAgain.chapters.length, online.chapters.length);
  assert.ok(await data.getBookById(context, 'favorite'));
  assert.ok(await data.getBookById(context, 'audio_history'));
  assert.equal(await data.getBookById(context, 'temporary_0'), undefined);
  assert.equal(data.cachedBooksMem.length, 203);
  console.log('PASS uncollected reading identity survives restart and 200-book cache eviction');

  const other = { ...online, id: 'other_source', sourceUrl: 'other' };
  await data.upsertCachedBook(other);
  const { OnlineTextContentCache: textCache } = load('service/text/OnlineTextContentCache');
  const textDirectory = path.join(context.filesDir, 'online_text_content');
  await fsp.mkdir(textDirectory, { recursive: true });
  const keys = ['source', 'other'].map(sourceUrl => textCache.key(sourceUrl, 'book', 'chapter'));
  for (const key of keys) await fsp.writeFile(textCache.path(context, key),
    JSON.stringify({ version: 1, key, content: 'cached text' }));
  data.cachedBooksMem = null;
  const invalidatedChapters = new Map();
  const removed = await data.invalidateSourceCaches(new Set(['source']), (id, chapters) => {
    invalidatedChapters.set(id, chapters);
  });
  assert.ok(removed.includes(online.id));
  assert.equal(invalidatedChapters.get(online.id).length, online.chapters.length,
    'Disk-only chapters are provided for targeted audio cleanup before the TOC is removed');
  assert.equal(fs.existsSync(path.join(context.filesDir, 'library_toc', online.id + '.json')), true, 'reading references preserve their directory');
  assert.equal(await textCache.read(context, keys[0]), 'cached text', 'reading references preserve cached body');
  assert.equal(await textCache.read(context, keys[1]), 'cached text');
  data.cachedBooksMem = null;
  const invalidated = await data.getBookById(context, online.id);
  assert.equal(invalidated.title, online.title);
  assert.equal(invalidated.chapters.length, online.chapters.length);
  assert.equal(invalidated.tocComplete, false);
  assert.equal((await data.getBookById(context, other.id)).chapters.length, other.chapters.length);
  assert.ok(favorites.has('favorite') && historyIds.has('audio_history'));
  console.log('PASS source replacement retains referenced TOC/body and invalidates stale definition context');

  free = 0;
  await assert.rejects(() => service.importBook(context, file, 'import_full', '', '', '', () => {}), /空间不足/);
  assert.equal(fs.existsSync(path.join(temp, 'ebooks/import_full')), false);
  await data.removeImportedBook(book.id);
  assert.equal(fs.existsSync(path.join(temp, 'ebooks', book.id)), false);
  assert.equal(fs.existsSync(path.join(temp, 'imported_toc', book.id + '.json')), false);
  assert.equal(handles.size, 0);
  console.log('PASS: streaming chapters, Unicode/GB18030, HTML, EPUB adapter, restart persistence, space failure, deletion');
  await data.restoreBackupBookShells([oldMetadata], true);
  data.cachedBooksMem = null;
  const restoredMetadata = await data.getBookById(context, oldMetadata.id);
  assert.equal(restoredMetadata.tocComplete, false, 'backup restore retains incomplete-TOC flag after restart');
  assert.equal(restoredMetadata.latestChapterTitle, 'Chapter 90');
  const storedMetadata = JSON.parse(await fsp.readFile(path.join(context.filesDir, 'library_books_v1.json'), 'utf8'))
    .find(item => item.id === oldMetadata.id);
  assert.equal(storedMetadata.coverFallback, oldMetadata.j40);
  assert.equal(storedMetadata.b40, undefined, 'new writes contain canonical metadata only');
  console.log('PASS release book metadata: old cache/import/backup, canonical precedence, false flags, restart');
  const { DiagnosticLogService: logs } = load('service/DiagnosticLogService');
  await logs.list();
  logs.init(context);
  assert.equal(logs.isEnabled(), false);
  logs.info('disabled', 'must not record');
  logs.failure('disabled', new Error('must not record'));
  await logs.check();
  assert.equal((await logs.list()).length, 0);
  assert.equal(diagnosticOutputCount, 0);
  assert.equal(fs.existsSync(path.join(temp, 'diagnostic_log.json')), false);
  diagnosticFlushFails = true;
  await assert.rejects(logs.setEnabled(true), /settings write failed/);
  assert.equal(logs.isEnabled(), false);
  assert.equal(diagnosticSettings.get('enabled'), false);
  diagnosticFlushFails = false;
  await logs.setEnabled(true);
  await logs.clear();
  for (let index = 0; index < 205; index++) logs.info('test', 'entry=' + index);
  let entries = await logs.list();
  assert.equal(entries.length, 200);
  assert.equal(entries[0].message, 'entry=204');
  const sensitive = new Error('open file:///storage/secret.txt token=abc https://example.com/?token=def');
  sensitive.code = 13900012;
  logs.failure('import.read', sensitive);
  entries = await logs.list();
  assert.match(entries[0].message, /code=13900012/);
  assert.doesNotMatch(entries[0].message, /secret.txt|abc|example.com|def/);
  const persisted = JSON.parse(await fsp.readFile(path.join(temp, 'diagnostic_log.json'), 'utf8'));
  assert.equal(persisted.length, 200);
  modules.delete(path.join(root, 'service/DiagnosticLogService.ets'));
  const restoredLogs = load('service/DiagnosticLogService').DiagnosticLogService;
  restoredLogs.init(context);
  assert.equal(restoredLogs.isEnabled(), true, 'manual choice survives restart');
  assert.ok((await restoredLogs.list()).some(entry => entry.stage === 'import.read'));
  await restoredLogs.clear();
  await restoredLogs.check();
  assert.ok((await restoredLogs.list()).some(entry => entry.level === 'ERROR' && entry.stage === 'check.storage'));
  await restoredLogs.setEnabled(false);
  const retained = JSON.stringify(await restoredLogs.list());
  const outputBefore = diagnosticOutputCount;
  restoredLogs.info('disabled', 'must not record');
  restoredLogs.failure('disabled', new Error('must not record'));
  await restoredLogs.check();
  assert.equal(JSON.stringify(await restoredLogs.list()), retained, 'disabled logs remain readable without new entries');
  assert.equal(diagnosticOutputCount, outputBefore);
  modules.delete(path.join(root, 'service/DiagnosticLogService.ets'));
  const disabledLogs = load('service/DiagnosticLogService').DiagnosticLogService;
  disabledLogs.init(context);
  assert.equal(disabledLogs.isEnabled(), false, 'disabled choice survives restart');
  assert.equal(JSON.stringify(await disabledLogs.list()), retained);
  await restoredLogs.clear();
  assert.equal((await restoredLogs.list()).length, 0);
  assert.equal(handles.size, 0);
  console.log('PASS diagnostics: default off, toggle persistence/failure, disabled retention, bounded persistence, restart, redaction, check and clear');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  for (const handle of handles.values()) await handle.close();
  await fsp.rm(temp, { recursive: true, force: true });
});
