// Real ArkTS cache + temporary disk; HarmonyOS file API simulated with Node fs.
// Run: node scripts/test-text-content-cache.cjs (requires DEVECO_HOME/DEVECO_PATH)
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hsda-text-cache-'));
const context = { cacheDir: path.join(root, 'cache').replaceAll('\\', '/'), filesDir: path.join(root, 'files').replaceAll('\\', '/') };
fs.mkdirSync(context.cacheDir); fs.mkdirSync(context.filesDir);
let failWrite = false;
let failMove = false;
const handles = new Map();
const fileIo = {
  OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
  listFile: p => fs.promises.readdir(p),
  stat: async p => { const s = await fs.promises.stat(p); return { size: s.size, mtime: s.mtimeMs / 1000, isFile: () => s.isFile(), isDirectory: () => s.isDirectory() }; },
  utimes: (p, ms) => fs.utimesSync(p, ms / 1000, ms / 1000),
  access: async p => fs.existsSync(p),
  copyFile: (a, b) => fs.promises.copyFile(a, b),
  rmdir: p => fs.promises.rm(p, { recursive: true }),
  readText: p => fs.promises.readFile(p, 'utf8'),
  mkdir: p => fs.promises.mkdir(p),
  open: async p => {
    if (failWrite) throw new Error('disk unavailable');
    const f = await fs.promises.open(p, 'w+');
    handles.set(f.fd, f);
    return { fd: f.fd };
  },
  // Deliberate short writes verify UTF-8 content is not truncated.
  write: async (fd, bytes) => (await handles.get(fd).write(Buffer.from(bytes).subarray(0, 13))).bytesWritten,
  fsync: fd => handles.get(fd).sync(),
  close: async f => { const h = handles.get(f.fd); handles.delete(f.fd); await h.close(); },
  moveFile: async (a, b) => {
    if (failMove) throw new Error('rename unavailable');
    await fs.promises.rename(a, b);
  },
  unlink: p => fs.promises.unlink(p)
};
function load(relative, modules) {
  const source = path.join(__dirname, '../entry/src/main/ets', relative);
  const code = ts.transpileModule(fs.readFileSync(source, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, { module, exports: module.exports, setTimeout: () => 1, require: name => {
    assert.ok(modules[name], `Unexpected module ${name}`);
    return modules[name];
  } }, { filename: source });
  return module.exports;
}
const identity = load('utils/BookIdentity.ets', {});
const migration = load('service/StorageMigrationService.ets', { '@kit.CoreFileKit': { fileIo } });
function newProcess() {
  const budget = load('service/ReaderCacheService.ts', {
    '@kit.CoreFileKit': { fileIo }, '@kit.BasicServicesKit': { emitter: { emit() {} } }
  });
  return load('service/text/OnlineTextContentCache.ets', {
    '../ReaderCacheService': budget,
    '@kit.CoreFileKit': { fileIo },
    '@kit.ArkTS': { buffer: { from: text => ({ buffer: Uint8Array.from(Buffer.from(text)).buffer }) } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn() {} } },
    '../StorageMigrationService': migration,
    '../../utils/BookIdentity': identity
  }).OnlineTextContentCache;
}
(async () => {
  let cache = newProcess();
  const key = cache.key('source-a', 'book-a', 'chapter-a');
  const text = '第一章\n　　重启后继续阅读，中文与 emoji 📚 不丢失。';
  const legacyDir = path.join(context.cacheDir, 'online_text_content');
  fs.mkdirSync(legacyDir);
  const legacyFile = path.join(legacyDir, identity.BookIdentity.onlineTextBookId(key, '') + '.json');
  fs.writeFileSync(legacyFile, JSON.stringify({ version: 1, key, content: text }));
  failMove = true;
  await assert.rejects(() => cache.read(context, key), /migration failed/);
  assert.ok(fs.existsSync(legacyFile), 'failed migration keeps the source');
  failMove = false;
  assert.equal(await cache.read(context, key), text, 'retry migrates the old chapter');
  assert.equal(fs.existsSync(legacyFile), false);
  fs.rmSync(context.cacheDir, { recursive: true }); fs.mkdirSync(context.cacheDir);
  cache = newProcess();
  assert.equal(await cache.read(context, key), text, 'system cache cleanup cannot remove saved text');
  console.log('PASS legacy migration, failed-copy publication recovery and system cache cleanup');
  await cache.write(context, key, text);
  cache = newProcess();
  assert.equal(await cache.read(context, key), text);
  const bookId = identity.BookIdentity.onlineTextBookId('source-a', 'book-a');
  let recovered = await cache.recoverBookIdentities(context, [bookId, 'search_text_missing']);
  assert.equal(recovered.length, 1);
  assert.equal(recovered[0].sourceUrl, 'source-a');
  assert.equal(recovered[0].bookUrl, 'book-a');
  await cache.write(context, cache.key('source-a', 'book-a', 'chapter-2'), 'second');
  assert.equal((await cache.recoverBookIdentities(context, [bookId])).length, 1);
  fs.writeFileSync(path.join(context.filesDir, 'online_text_content/search_text_broken.json'), '{broken');
  fs.writeFileSync(path.join(context.filesDir, 'online_text_content/search_text_wrong.json'), JSON.stringify({ version: 1, key }));
  assert.equal((await cache.recoverBookIdentities(context, ['search_text_missing'])).length, 0);
  assert.equal((await cache.recoverBookIdentities(context, [bookId])).length, 1);
  console.log('PASS legacy book identity recovery, deduplication and corrupt cache isolation');
  console.log('PASS cold process restores complete UTF-8 text');
  assert.equal(await cache.read(context, cache.key('source-b', 'book-a', 'chapter-a')), undefined);
  assert.equal(await cache.read(context, cache.key('source-a', 'book-b', 'chapter-a')), undefined);
  assert.equal(await cache.read(context, cache.key('source-a', 'book-a', 'chapter-b')), undefined);
  console.log('PASS source/book/chapter isolation independent of chapter index');
  const separateBook = cache.key('source-a', 'book-other', 'chapter-a');
  await cache.write(context, separateBook, 'keep other book');
  await cache.removeBook(context, 'source-a', 'book-other');
  assert.equal(await cache.read(context, separateBook), undefined);
  assert.equal(await cache.read(context, key), text, 'per-book cleanup keeps other books from the same source');

  const file = path.join(context.filesDir, 'online_text_content', identity.BookIdentity.onlineTextBookId(key, '') + '.json');
  fs.writeFileSync(file, '{broken');
  assert.equal(await cache.read(context, key), undefined);
  fs.writeFileSync(file, JSON.stringify({ version: 1, key: 'wrong identity', content: 'wrong book' }));
  assert.equal(await cache.read(context, key), undefined);
  console.log('PASS corrupt file and hash collision fall back to fetch');
  await cache.write(context, key, text);
  failMove = true;
  await cache.write(context, key, 'incomplete replacement');
  assert.equal(await cache.read(context, key), text);
  failMove = false;
  failWrite = true;
  await cache.write(context, key, 'failed write');
  failWrite = false;
  await Promise.all([cache.write(context, key, 'first'), cache.write(context, key, 'last')]);
  assert.equal(await newProcess().read(context, key), 'last');
  assert.equal(handles.size, 0);
  assert.equal(fs.readdirSync(path.dirname(file)).some(p => p.endsWith('.tmp')), false);
  console.log('PASS failed writes preserve old file; concurrent writes and later recovery succeed');
  await cache.write(context, key, '  ');
  assert.equal(await cache.read(context, key), 'last');
  fs.unlinkSync(file);
  assert.equal(await newProcess().read(context, key), undefined);
  console.log('PASS empty content rejected and cache cleanup treated as miss');
  // Exercise the actual reader disk-first method, with the network disconnected after the first read.
  const reader = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/ReaderPage.ets'), 'utf8');
  const method = reader.slice(reader.indexOf('  private async readOrFetchOnlineTextContent('),
    reader.indexOf('  private paginateOnlineTextContent('));
  let requests = 0;
  let offline = false;
  const hostCode = ts.transpileModule('class ReaderHost { context; ' + method + '} globalThis.ReaderHost = ReaderHost;', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const sandbox = {
    OnlineTextContentCache: newProcess(),
    BookSourceService: { getTextChapterContent: async () => {
      requests++;
      if (offline) throw new Error('offline');
      return { content: text };
    } },
    OnlineTextPaginator: { normalizeContent: content => content }
  };
  vm.runInNewContext(hostCode, sandbox);
  let host = new sandbox.ReaderHost();
  host.context = context;
  assert.equal(await host.readOrFetchOnlineTextContent({}, { title: '第一章' }, 'chapter-a', key), text);
  offline = true;
  sandbox.OnlineTextContentCache = newProcess();
  host = new sandbox.ReaderHost();
  host.context = context;
  assert.equal(await host.readOrFetchOnlineTextContent({}, { title: '第一章' }, 'chapter-a', key), text);
  assert.equal(requests, 1);
  console.log('PASS reader reopens cached chapter offline without a second network request');
  offline = false;
  await host.readOrFetchOnlineTextContent({}, { title: '第一章' }, 'chapter-a', key, true);
  assert.equal(requests, 2, 'reload must reach network even when disk contains the chapter');
  const otherKey = cache.key('source-a', 'book-a', 'chapter-2');
  const pendingWrite = cache.write(context, key, 'old in-flight write');
  await cache.removeChapter(context, key);
  await pendingWrite;
  assert.equal(await cache.read(context, key), undefined);
  assert.equal(await cache.read(context, otherKey), 'second');
  console.log('PASS reload bypasses disk; chapter eviction waits for writes and preserves adjacent chapters');

  const clearingCache = newProcess();
  const inFlight = clearingCache.write(context, key, 'write before clear');
  const cleared = await clearingCache.clear(context);
  await inFlight;
  assert.ok(cleared.releasedBytes > 0);
  assert.equal(await clearingCache.read(context, key), undefined);
  assert.equal(await clearingCache.read(context, otherKey), undefined);
  console.log('PASS settings disk cleanup waits for pending writes and removes persisted chapters');

})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  fs.rmSync(root, { recursive: true, force: true });
});
