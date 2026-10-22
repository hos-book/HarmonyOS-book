const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const compile = code => ts.transpileModule(code, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const files = new Map(), records = new Map(), events = [], calls = [];
let openId = 0, active = 0, maxActive = 0, barrier;
const handles = new Map();
const fileIo = { OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 }, mkdirSync() {},
  accessSync: name => files.has(name),
  openSync(name) { handles.set(++openId, name); return { fd: openId }; },
  writeSync(fd, bytes) { files.set(handles.get(fd), bytes); return bytes.byteLength; }, closeSync() {},
  stat: async name => { if (!files.has(name)) throw Error('missing'); return { size: files.get(name).byteLength }; },
  unlink: async name => files.delete(name) };
const fileUri = { getUriFromPath: name => 'file://' + name,
  FileUri: class { constructor(url) { this.path = url.slice(7); } } };
class HttpClient {
  async executeBinary(options, limit) {
    assert.equal(options.cookieSource, 'https://source.test');
    assert.equal(limit, 20 * 1024 * 1024);
    calls.push(options.url); active++; maxActive = Math.max(active, maxActive);
    if (barrier) await barrier;
    await Promise.resolve(); active--;
    const bytes = new Uint8Array(32); bytes[0] = 255; bytes[1] = 216;
    return { success: !options.url.includes('failed'), data: bytes };
  }
}
function evaluate(relative, require, globals = {}) {
  const exports = {};
  vm.runInNewContext(compile(fs.readFileSync(path.join(root, relative), 'utf8')),
    { exports, require, console, ...globals });
  return exports;
}
const { ComicImagePipeline } = evaluate('service/rulesource/light/upstream/core/book/ComicImagePipeline.ts',
  name => {
    if (name === '@ohos.file.fs') return { default: fileIo };
    if (name.endsWith('SourceEngineHost')) return { SourceEngineHost: { isCancelled: () => false } };
    if (name === '@kit.ArkTS') return { util: { TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } } } };
    if (name === '@kit.CryptoArchitectureKit') return { cryptoFramework: { createMd: () => {
      const hash = crypto.createHash('sha256');
      return { update: async blob => hash.update(blob.data), digest: async () => ({ data: hash.digest() }) };
    } } };
    return {};
  },
  { AppStorage: { get: () => '/cache' } });
const { LightSourceRequest } = evaluate('service/rulesource/light/LightSourceRequestPolicy.ts', () => ({}));
const text = fs.readFileSync(path.join(root, 'service/rulesource/light/LightSourceCore.ts'), 'utf8');
const start = text.indexOf('  static async cacheComicImages(');
let end = text.indexOf('{', start) + 1, depth = 1;
while (depth && end < text.length) {
  if (text[end] === '{') depth++;
  if (text[end] === '}') depth--;
  end++;
}
const ReaderCacheService = { configure() {}, beginComicWrite() {}, endComicWrite() {}, record: async () => {},
  touch: async () => {}, enforce: async () => {} };
const coreScope = { ComicImagePipeline, HttpClient, LightSourceRequestPolicy: { bind() {} }, ReaderCacheService,
  LightSourceRuntime: { run: (_source, _local, action) => action(), setError() {} } };
vm.runInNewContext(compile(`class Core { static source(local) { return local; } ${text.slice(start, end)} }
  globalThis.Core = Core;`), coreScope);
const source = { bookSourceUrl: 'https://source.test' };
const book = { sourceUrl: source.bookSourceUrl, bookUrl: 'https://source.test/book', id: 'book' };
const chapter = n => ({ id: `c${n}`, source: { value: `https://source.test/c${n}` } });
const urls = Array.from({ length: 9 }, (_, n) => `https://images.test/${n}.jpg`);
const { ComicReaderService: reader } = evaluate('service/ComicReaderService.ets', name => {
  if (name === './BookSourceService') return { BookSourceService: {
    cacheComicImages: (_book, list, request) => coreScope.Core.cacheComicImages(
      JSON.stringify(source), JSON.stringify(list), request).then(JSON.parse),
    getSourceChapterContent: async () => ({ imageUrls: urls, richContent: '', content: '', mediaType: 'comic' })
  } };
  if (name === '@kit.CoreFileKit') return { fileUri, fileIo };
  if (name === '@kit.BasicServicesKit') return { emitter: { emit: (...args) => events.push(args) } };
  if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {} } };
  if (name.endsWith('LightSourceRequestPolicy')) return { LightSourceRequest };
  if (name.endsWith('ReaderCacheService')) return { ReaderCacheService };
  if (name.endsWith('OnlineTextContentCache')) return { OnlineTextContentCache: {
    key: (...parts) => parts.join('|'), read: async (_ctx, key) => records.get(key),
    write: async (_ctx, key, body) => records.set(key, body), removeChapter: async (_ctx, key) => records.delete(key)
  } };
  return {};
});
const context = { cacheDir: '/cache' };
(async () => {
  const pages = await reader.load(book, chapter(1), context, false, true);
  assert.equal((await reader.cached(context, book, chapter(1))).length, 0, 'URL lists are not offline cache');
  assert.equal(calls.length, 0, 'opening a chapter does not wait for background image downloads');
  assert.equal(await reader.preloadImages(book, chapter(1), pages, context, () => false), true);
  assert.equal(calls.length, 9, 'ordinary image URLs are actually fetched');
  assert.ok(maxActive <= 4, 'image concurrency stays bounded');
  assert.ok(pages.every(p => p.url.startsWith('file:///cache/comic_images/')));
  assert.equal((await reader.cached(context, book, chapter(1))).length, 9);
  assert.equal((await reader.load(book, chapter(1), context)).length, 9);
  assert.equal(calls.length, 9, 'reopening a cached chapter makes no image requests');

  let release;
  barrier = new Promise(resolve => { release = resolve; });
  const nextPages = urls.map((url, n) => ({ key: `next:${n}`, url: url.replace('/images.test/', '/other.test/'), index: n }));
  const task = reader.preloadImages(book, chapter(2), nextPages, context, () => false);
  const duplicate = reader.preloadImages(book, chapter(2), nextPages, context, () => false);
  const opened = await reader.load(book, chapter(2), context);
  assert.equal(opened.length, 9, 'foreground list is available while image preload is pending');
  release(); barrier = undefined;
  assert.equal(await task, true); assert.equal(await duplicate, true);
  assert.equal(calls.length, 18, 'duplicate preload shares one image task');

  const cancelled = urls.map((url, n) => ({ key: `cancel:${n}`, url, index: n }));
  const before = events.length;
  await assert.rejects(reader.preloadImages(book, chapter(3), cancelled, context, () => true), /cancelled/);
  assert.equal((await reader.cached(context, book, chapter(3))).length, 0);
  assert.equal(events.length, before, 'cancelled preload cannot report a cached chapter');
  const failed = [{ key: 'failed', url: 'https://images.test/failed.jpg', index: 0 }];
  assert.equal(await reader.preloadImages(book, chapter(4), failed, context, () => false), false);
  assert.equal((await reader.cached(context, book, chapter(4))).length, 0, 'failed image is never reported as offline cache');
  const local = (await reader.cached(context, book, chapter(1)))[0];
  files.delete(local.url.slice(7));
  assert.equal((await reader.cached(context, book, chapter(1))).length, 0, 'deleted image invalidates whole chapter cache');
  console.log('comic prefetch: real bounded pipeline download, local restore, task reuse, nonblocking open, cancellation/failure and missing-file invalidation passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
