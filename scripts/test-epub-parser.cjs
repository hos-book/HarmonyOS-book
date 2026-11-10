// Run the project's ZIP/XML/EPUB parser; only OS file and compression primitives are adapted.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { platformZlib, zip } = require('./epub-fixture.cjs');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets/service/text');
const temp = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'hsda-epub-parser-'));
const handles = new Map();
let readLimit = 97;
let activeReads = 0, peakReads = 0;
const fileIo = {
  OpenMode: { READ_ONLY: 0 },
  async open(name) { const file = await fs.promises.open(name); handles.set(file.fd, file); return { fd: file.fd }; },
  async close(file) { const handle = handles.get(file.fd); handles.delete(file.fd); await handle.close(); },
  async stat(fd) { return handles.get(fd).stat(); },
  async read(fd, bytes, opts) {
    activeReads++; peakReads = Math.max(peakReads, activeReads);
    try {
      // Exercise the short-read loop too.
      return (await handles.get(fd).read(Buffer.from(bytes), 0, Math.min(opts.length, readLimit), opts.offset)).bytesRead;
    } finally { activeReads--; }
  }
};
const modules = new Map();
function load(name) {
  const filename = path.resolve(root, name.endsWith('.ets') ? name : name + '.ets');
  if (modules.has(filename)) return modules.get(filename);
  const exports = {}; modules.set(filename, exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText;
  vm.runInNewContext(code, { exports, Error, ArrayBuffer, Uint8Array, require(name) {
    if (name === '@kit.CoreFileKit') return { fileIo };
    if (name === '@kit.BasicServicesKit') return { zlib: platformZlib };
    if (name === '@kit.ArkTS') return { util: { TextDecoder: { create(encoding, options) {
      const decoder = new TextDecoder(encoding, options);
      return { decodeToString: bytes => decoder.decode(bytes) };
    } } } };
    return load(name);
  } }, { filename });
  return exports;
}

(async () => {
  const { EpubParserService: Parser } = load('EpubParserService');
  const { EpubArchive: Archive } = load('EpubArchive');
  const chapter = '<html><body><h1 id="a">一</h1><p>正文 😀</p><h1 id="b">二</h1></body></html>';
  const entries = new Map([
    ['mimetype', 'application/epub+zip'],
    ['META-INF/container.xml', '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>'],
    ['OEBPS/book.opf', '<package><metadata><dc:title>原版 &amp; 精排</dc:title><dc:creator>作者</dc:creator></metadata>' +
      '<manifest><item id="body" href="Text/一:*.xhtml" media-type="application/xhtml+xml"/>' +
      '<item id="extra" href="extra.xhtml" media-type="application/xhtml+xml"/>' +
      '<item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>' +
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>' +
      '<item id="cover" href="Images/cover.png" properties="cover-image" media-type="image/png"/></manifest>' +
      '<spine toc="ncx"><itemref idref="body"/><itemref idref="extra" linear="no"/></spine></package>'],
    ['OEBPS/Text/一:*.xhtml', chapter], ['OEBPS/extra.xhtml', '<p>辅助页</p>'],
    ['OEBPS/Images/cover.png', Buffer.from([137, 80, 78, 71])],
    ['OEBPS/nav.xhtml', '<html><nav epub:type="toc"><ol><li><a href="Text/%E4%B8%80%3A*.xhtml#a">第一章</a>' +
      '<ol><li><a href="Text/一:*.xhtml#b">第二章</a></li></ol></li></ol></nav></html>'],
    ['OEBPS/toc.ncx', '<ncx><navMap><navPoint><navLabel><text>NCX 第一章</text></navLabel>' +
      '<content src="Text/一:*.xhtml#a"/></navPoint><navPoint><navLabel><text>附录</text></navLabel>' +
      '<content src="extra.xhtml"/></navPoint></navMap></ncx>']
  ]);
  for (const stored of [false, true]) {
    const filename = path.join(temp, `valid-${stored}.epub`); fs.writeFileSync(filename, zip(entries, { stored }));
    const parser = await Parser.open(filename);
    assert.equal(parser.getBookInfo().bookTitle, '原版 & 精排');
    assert.equal(parser.getBookInfo().bookCreator, '作者');
    assert.equal(parser.getBookInfo().bookCoverImage, 'OEBPS/Images/cover.png');
    assert.equal(parser.getSpineList().length, 1, 'unlisted non-linear appendix is not main text');
    assert.equal(parser.getCatalogList().map(item => item.catalogName).join(','), '第一章,第二章');
    assert.equal(parser.getCatalogList()[1].href, 'OEBPS/Text/一:*.xhtml#b');
    assert.equal(await parser.getSpineItemContent(0), chapter);
    assert.equal((await parser.getSpineBatch(0)).join(''), chapter);
    assert.deepEqual(Buffer.from(await parser.getResourceContent(0, '../Images/cover.png')), entries.get('OEBPS/Images/cover.png'));
    await parser.close(); await parser.close();
    assert.equal(handles.size, 0);
  }
  entries.delete('OEBPS/nav.xhtml');
  const filename = path.join(temp, 'ncx.epub'); fs.writeFileSync(filename, zip(entries));
  const ncx = await Parser.open(filename);
  assert.equal(ncx.getCatalogList().map(item => item.catalogName).join(','), 'NCX 第一章,附录');
  assert.equal(ncx.getSpineList().length, 2, 'explicit TOC reference includes non-linear appendix');
  await ncx.close();
  fs.writeFileSync(filename, zip([...entries, ['mimetype', entries.get('mimetype')]]));
  const duplicate = await Parser.open(filename); await duplicate.close();
  for (const [bytes, pattern] of [
    [Buffer.from('invalid archive'), /有效/],
    [zip(new Map([['../escape', 'data']])), /路径/],
    [zip([['mimetype', 'one'], ['mimetype', 'two']]), /内容冲突/],
    [zip(new Map([['META-INF/container.xml', '<container/>']])), /OPF/]
  ]) {
    fs.writeFileSync(filename, bytes);
    await assert.rejects(Parser.open(filename), pattern); assert.equal(handles.size, 0);
  }
  const corrupt = zip(new Map([['body', 'checksum']]), { stored: true }); corrupt[34] ^= 1;
  fs.writeFileSync(filename, corrupt); const archive = await Archive.open(filename);
  await assert.rejects(archive.read('body'), /完整性/); await archive.close();

  readLimit = 1024 * 1024;
  const bodies = [1024, 1024, 220 * 1024, 320 * 1024, 600 * 1024, 1024, 1024, 1024]
    .map((size, index) => `<html><body>正文${index}😀${'文'.repeat(size / 3)}</body></html>`);
  const batchEntries = new Map([
    ['META-INF/container.xml', '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>'],
    ['book.opf', '<package><metadata><dc:title>并行读取</dc:title></metadata><manifest>' +
      '<item id="cover" href="cover.png" properties="cover-image" media-type="image/png"/>' +
      bodies.map((_, i) => `<item id="c${i}" href="${i}.xhtml" media-type="application/xhtml+xml"/>`).join('') +
      '</manifest><spine>' + bodies.map((_, i) => `<itemref idref="c${i}"/>`).join('') + '</spine></package>'],
    ...bodies.map((html, i) => [`${i}.xhtml`, html])
  ]);
  fs.writeFileSync(filename, zip(batchEntries));
  const parallel = await Parser.open(filename);
  const restored = [];
  peakReads = 0;
  while (restored.length < bodies.length) {
    const batch = await parallel.getSpineBatch(restored.length);
    assert.ok(batch.length >= 1 && batch.length <= 4);
    assert.ok(batch.length === 1 || batch.reduce((sum, html) => sum + Buffer.byteLength(html), 0) <= 512 * 1024,
      'prefetched chapters must respect both count and byte budgets');
    restored.push(...batch);
  }
  assert.deepEqual(restored, bodies, 'out-of-order I/O preserves Unicode content and spine order');
  assert.ok(peakReads > 1 && peakReads <= 4, `bounded parallel reads: ${peakReads}`);
  await parallel.close();
  const damaged = zip(batchEntries, { stored: true });
  damaged[damaged.indexOf(Buffer.from(bodies[0]))] ^= 1;
  fs.writeFileSync(filename, damaged);
  const brokenBatch = await Parser.open(filename);
  await assert.rejects(brokenBatch.getSpineBatch(0), /完整性/);
  assert.equal(activeReads, 0, 'failed batch drains all reads before releasing the archive');
  await brokenBatch.close();
  assert.equal(handles.size, 0);
  console.log('PASS bounded EPUB prefetch: concurrency, byte budget, oversized single chapter, order and failure drain');
  console.log('PASS self EPUB parser: stored/deflate + CRC, short reads, metadata, nav/NCX anchors, non-linear items, Unicode/special paths, resource bytes and failure cleanup');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  for (const handle of handles.values()) await handle.close();
  await fs.promises.rm(temp, { recursive: true, force: true });
});
