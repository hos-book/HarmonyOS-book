// Real cache manager, real disposable files, scaled budgets; no device data is touched.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hsda-cache-budget-')).replaceAll('\\', '/');
const context = { filesDir: root + '/files', cacheDir: root + '/cache' };
const textRoot = context.filesDir + '/online_text_content';
const comicRoot = context.cacheDir + '/comic_images';
const enhancedRoot = context.cacheDir + '/comic_super_resolution_v1';
let failingPath = '';
let accessFails = false;
let pendingTimer;
let directoryReads = 0;
const fileIo = {
  listFile: p => { directoryReads++; return fs.promises.readdir(p); },
  stat: async p => { const s = await fs.promises.stat(p); return { size: s.size, mtime: s.mtimeMs / 1000, isFile: () => s.isFile() }; },
  access: async p => { if (accessFails && p === failingPath) throw Error('access denied'); return fs.existsSync(p); },
  unlink: async p => { if (p === failingPath) throw Error('busy'); await fs.promises.unlink(p); },
  utimes: (p, ms) => fs.utimesSync(p, ms / 1000, ms / 1000)
};
const code = ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/ReaderCacheService.ts'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
function processCache() {
  const module = { exports: {} };
  vm.runInNewContext(code, { module, exports: module.exports, setTimeout: fn => { pendingTimer = fn; return 1; }, require: name => {
    if (name === '@kit.CoreFileKit') return { fileIo, fileUri: { FileUri: class { constructor(uri) { this.path = uri.slice(7); } } } };
    if (name === '@kit.BasicServicesKit') return { emitter: { emit() {} } };
    if (name.endsWith('/PerformanceTrace')) return { PerformanceTrace: { begin: () => -1, end() {} } };
    throw Error(name);
  } });
  const manager = module.exports.ReaderCacheService;
  manager.TEXT_LIMIT = 100;
  manager.COMIC_LIMIT = 100;
  manager.configure(context);
  return manager;
}
function colorHost(cache) {
  const exports = {};
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/ComicAiHost.ets'), 'utf8');
  vm.runInNewContext(ts.transpileModule(source.replace(/import lazy /g, 'import '), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, require: name => {
    if (name.endsWith('ReaderCacheService')) return { ReaderCacheService: cache };
    if (['@kit.AbilityKit', '@kit.ArkTS', '@kit.CoreFileKit', '@kit.CryptoArchitectureKit', '@legado/aiengine'].includes(name) || name.endsWith('MembershipState')) return {};
    throw Error(name);
  } });
  return new exports.ComicAiHost(context);
}
function write(p, size = 40, age = 100) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, Buffer.alloc(size));
  const time = Date.now() / 1000 - age;
  fs.utimesSync(p, time, time);
  return p;
}
function reset() {
  fs.rmSync(root, { recursive: true, force: true });
  for (const dir of [textRoot, comicRoot, enhancedRoot]) fs.mkdirSync(dir, { recursive: true });
  failingPath = ''; accessFails = false; pendingTimer = undefined;
}
(async () => {
  reset();
  let cache = processCache();
  const a = write(textRoot + '/search_text_a.json', 40, 300);
  const b = write(textRoot + '/search_text_b.json', 40, 200);
  const c = write(textRoot + '/search_text_c.json', 40, 100);
  await cache.record([a]);
  cache = processCache();
  await cache.initialize(context);
  assert.ok(fs.existsSync(a), 'recent access persists across restart');
  assert.equal(fs.existsSync(b), false, 'oldest is evicted first');
  assert.equal((await cache.usage()).textBytes, 80);
  console.log('PASS restart scans disk, persisted LRU and 90% low-water target');

  reset(); cache = processCache();
  write(a, 60); write(b, 60); write(c, 60);
  cache.protect('reader', [a]); cache.hold(b);
  await cache.initialize(context);
  assert.ok(fs.existsSync(a) && fs.existsSync(b));
  assert.equal(fs.existsSync(c), false);
  assert.equal((await cache.clear(0)).protectedCount, 2);
  cache.release('reader'); cache.unhold(b);
  assert.ok(pendingTimer, 'release schedules another sweep');
  pendingTimer(); await cache.chain;
  assert.ok((await cache.usage()).textBytes <= 90);
  console.log('PASS active reading and writes protected; release resumes trimming');

  reset(); cache = processCache();
  const image = write(comicRoot + '/abc.jpg', 60);
  const derived = write(enhancedRoot + '/def.webp', 60);
  cache.beginComicWrite(); await cache.initialize(context);
  assert.equal((await cache.usage()).comicBytes, 120);
  assert.equal((await cache.clear(1)).protectedCount, 2);
  cache.endComicWrite(); pendingTimer(); await cache.chain;
  assert.equal((await cache.usage()).comicBytes, 60);
  cache.protect('visible', ['file://' + (fs.existsSync(image) ? image : derived)]);
  assert.equal((await cache.clear(1)).protectedCount, 1);
  console.log('PASS comic writes deferred, derived images share budget and file URI pins work');

  reset(); cache = processCache();
  const permanent = [write(context.filesDir + '/ebooks/book.txt'), write(context.filesDir + '/downloads/audio.mp3'),
    write(context.filesDir + '/imported_toc/book.json'), write(context.filesDir + '/progress.json'),
    write(textRoot + '/unrelated.json'), write(comicRoot + '/nested/abc.jpg')];
  write(a); write(b); write(image);
  failingPath = a; accessFails = true;
  const cleared = await cache.clear(0);
  assert.equal(cleared.failed, 1); assert.equal(cleared.removed, 1); assert.equal(cleared.releasedBytes, 40);
  assert.ok(fs.existsSync(image), 'text clear never deletes comic files');
  failingPath = ''; accessFails = false;
  await cache.clear(0); await cache.clear(1);
  for (const p of permanent) assert.ok(fs.existsSync(p), p);
  assert.equal((await cache.usage()).textBytes, 0);
  console.log('PASS disk clearing, deletion failure isolation and permanent-data exclusion');
  reset(); cache = processCache();
  write(a,20); await cache.record([a]);
  const kind = cache.kind;
  let classified = 0;
  cache.kind = p => {classified++; return kind(p);};
  await cache.trim(0,false); await cache.trim(1,false);
  assert.equal(classified,0,'below-budget periodic trimming does not traverse or classify every cached file');
  write(a,70); await cache.record([a]);
  assert.equal(cache.textBytes,70,'rewriting a known file replaces its byte contribution');
  cache.forget(a); cache.forget(a);
  assert.equal(cache.textBytes,0,'forget is idempotent');
  write(image,35); await cache.record([image]);
  fs.unlinkSync(image); await cache.record([image]);
  assert.equal(cache.comicBytes,0,'missing files release their accounted bytes');
  console.log('PASS constant-time below-budget trim and byte totals after replacement/deletion');

  reset(); cache = processCache();
  await cache.initialize(context);
  const host = colorHost(cache);
  const scansBefore = directoryReads;
  const colorA = write(comicRoot + '/color_alac-fp16-v4_' + 'a'.repeat(64) + '.jpg', 40, 300);
  host.noteComicWrite();
  await cache.record(['file://' + colorA]);
  const colorB = write(comicRoot + '/color_alac-fp16-v4_' + 'b'.repeat(64) + '.jpg', 40, 200);
  host.noteComicWrite();
  await cache.record(['file://' + colorB]);
  assert.equal(directoryReads, scansBefore, 'successive HAR writes register only their returned paths, without rescanning all caches');
  assert.equal(cache.comicBytes, 80, 'engine output filenames count toward the shared comic budget');
  const ignored = [write(colorA + '.part'), write(comicRoot + '/color_alac-fp16-v4_short.jpg'),
    write(enhancedRoot + '/color_alac-fp16-v4_' + 'c'.repeat(64) + '.jpg')];
  cache.protect('color-reader', ['file://' + colorA]); cache.hold(colorB);
  assert.equal((await cache.clear(1)).protectedCount, 2, 'visible and in-flight engine results are protected');
  cache.release('color-reader'); cache.unhold(colorB);
  cache = processCache();
  assert.equal((await cache.usage()).comicBytes, 80, 'a fresh process discovers versioned engine outputs');
  const colorsCleared = await cache.clear(1);
  assert.equal(colorsCleared.removed, 2);
  assert.equal(colorsCleared.releasedBytes, 80);
  for (const p of ignored) assert.ok(fs.existsSync(p), 'incomplete and unrelated files are excluded');
  console.log('PASS incremental HAR output registration, restart discovery, pins and cache cleanup');

  reset(); cache = processCache();
  const retainedSource = write(comicRoot + '/abc.jpg', 40);
  const aiHost = colorHost(cache);
  const releaseColor = aiHost.retainComicFile('file://' + retainedSource);
  const releaseSuperResolution = aiHost.retainComicFile(retainedSource);
  assert.equal((await cache.clear(1)).protectedCount, 1, 'queued AI work retains its original file');
  releaseColor(); releaseColor();
  assert.equal((await cache.clear(1)).protectedCount, 1, 'idempotent release keeps another AI consumer protected');
  releaseSuperResolution();
  assert.equal((await cache.clear(1)).removed, 1, 'completed or cancelled AI work releases its file');
  assert.equal(fs.existsSync(retainedSource), false);
  console.log('PASS AI source leases protect concurrent work and release exactly once');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => fs.rmSync(root, { recursive: true, force: true }));
