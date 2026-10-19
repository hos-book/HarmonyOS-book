// Run real cover services with controlled platform callbacks; no network or device is used.
// Usage: DEVECO_HOME=<Release IDE> node scripts/test-cover-lifecycle.cjs
const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets/service');
const hilog = { info() {}, warn() {}, error() {} };
const flush = () => new Promise(resolve => setImmediate(resolve));

function load(name, mocks, globals = {}) {
  const exports = {};
  const code = ts.transpileModule(fs.readFileSync(path.join(root, name + '.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, require: key => mocks[key] || {}, ArrayBuffer, console, ...globals });
  return exports[name];
}

function prefetchFixture(api = 26) {
  const success = new Map();
  const failure = new Map();
  const timers = new Map();
  const downloads = [];
  let nextTimer = 0;
  const add = (map, url, callback) => {
    if (!map.has(url)) map.set(url, new Set());
    map.get(url).add(callback);
  };
  const off = (map, url, callback) => {
    if (callback) map.get(url)?.delete(callback);
    else map.delete(url);
    if (map.get(url)?.size === 0) map.delete(url);
  };
  const cacheDownload = {
    CacheStrategy: { LAZY: 1 },
    onDownloadSuccess: (url, callback) => add(success, url, callback),
    onDownloadError: (url, callback) => add(failure, url, callback),
    offDownloadSuccess: (url, callback) => off(success, url, callback),
    offDownloadError: (url, callback) => off(failure, url, callback),
    download: url => downloads.push(url), cancel() {}, getDownloadInfo() {},
    setFileCacheSize() {}, setMemoryCacheSize() {}, setDownloadInfoListSize() {}
  };
  const service = load('CoverPrefetcher', {
    './SourceCoverService': { SourceCoverService: { isEncoded: () => false } },
    '@kit.PerformanceAnalysisKit': { hilog }, '@kit.BasicServicesKit': { cacheDownload },
    './http/HttpClient': { HttpClient: { preconnect() {} } },
    '../utils/PlatformCompat': { PlatformCompat: { supports: version => api >= version } }
  }, {
    setTimeout(callback, delay) { const id = ++nextTimer; timers.set(id, { callback, delay }); return id; },
    clearTimeout: id => timers.delete(id)
  });
  const complete = url => [...(success.get(url) || [])].forEach(callback => callback());
  const runTimer = delay => {
    const entry = [...timers].find(([, timer]) => timer.delay === delay);
    assert.ok(entry, `expected a ${delay}ms timer`);
    timers.delete(entry[0]); entry[1].callback();
  };
  return { service, success, failure, timers, downloads, complete, runTimer, cacheDownload };
}

test('repeated image errors share the current download and its listeners', () => {
  const f = prefetchFixture();
  const url = 'https://cover.test/book.jpg';
  f.service.prefetch(url);
  const oldSuccess = [...f.success.get(url)][0];
  const oldFailure = [...f.failure.get(url)][0];
  for (let i = 0; i < 20; i++) f.service.retry(url);
  assert.equal(f.success.get(url).size, 1);
  assert.equal(f.failure.get(url).size, 1);
  assert.equal(f.downloads.length, 1, 'image errors must not restart an in-flight download');
  assert.equal([...f.success.get(url)][0], oldSuccess);
  oldSuccess(); oldFailure();
  assert.equal(f.service.inFlight.size, 0);
  assert.equal(f.success.size + f.failure.size + f.timers.size, 0);
});

test('successful browsing does not retain watchdogs or unlimited cover metadata', () => {
  const f = prefetchFixture();
  for (let i = 0; i < 1600; i++) {
    const url = `https://cover${i}.test/book.jpg`;
    f.service.registerHeaders(url, { Referer: `https://source${i}.test/` });
    f.service.prefetch(url); f.complete(url);
  }
  assert.equal(f.timers.size, 0, 'completed downloads must cancel their watchdog timers');
  assert.equal(f.success.size + f.failure.size, 0);
  assert.ok(f.service.succeeded.size <= 512);
  assert.ok(f.service.attemptCount.size <= 512);
  assert.ok(f.service.requestHeaders.size <= 512);
  assert.ok(f.service.warmedOrigins.size <= 64);
});

test('pending covers are bounded and a newly visible cover keeps priority', () => {
  const f = prefetchFixture();
  for (let i = 0; i < 2000; i++) f.service.prefetch(`https://cover.test/${i}.jpg`);
  assert.equal(f.downloads.length, 4);
  assert.ok(f.service.pending.length <= 128);
  const visible = 'https://cover.test/visible.jpg';
  f.service.prefetch(visible, true);
  f.complete(f.downloads[0]);
  assert.equal(f.downloads.at(-1), visible);
  assert.equal(f.service.inFlight.size, 4);
});

test('synchronous cache hits leave no watchdog and failures stop at the retry limit', () => {
  const hit = prefetchFixture();
  hit.cacheDownload.download = url => hit.complete(url);
  hit.service.prefetch('https://cover.test/hit.jpg');
  assert.equal(hit.timers.size, 0);
  const f = prefetchFixture();
  f.cacheDownload.download = url => { f.downloads.push(url); throw new Error('offline'); };
  f.service.prefetch('https://cover.test/offline.jpg');
  for (let i = 0; i < 4; i++) f.runTimer(1500);
  assert.equal(f.downloads.length, 5);
  for (let i = 0; i < 20; i++) f.service.retry('https://cover.test/offline.jpg');
  assert.equal(f.downloads.length, 5, 'image errors cannot bypass the prefetch retry limit');
  assert.equal(f.timers.size + f.success.size + f.failure.size + f.service.inFlight.size, 0);
});

test('API 20 polling and watchdogs are cleared when a download finishes', () => {
  const f = prefetchFixture(20);
  f.service.prefetch('https://cover.test/legacy.jpg');
  f.cacheDownload.getDownloadInfo = () => ({ resource: { size: 128 } });
  f.runTimer(250);
  assert.equal(f.service.inFlight.size, 0);
  assert.equal(f.timers.size + f.service.successHandlers.size + f.service.errorHandlers.size, 0);
});

function sessionFixture() {
  const sources = [];
  const pixels = [];
  let reads = 0;
  let gate = Promise.resolve();
  let failDecode = false;
  const read = async () => { reads++; await gate; return new ArrayBuffer(16); };
  const image = {
    createImageSource() {
      const source = {
        released: 0,
        async createPixelMap() {
          if (failDecode) throw new Error('bad image');
          const pixel = { released: 0, async release() { this.released++; } };
          pixels.push(pixel); return pixel;
        },
        async release() { this.released++; }
      };
      sources.push(source); return source;
    }
  };
  const Service = load('AVSessionService', {
    './LocalBookCoverService': { LocalBookCoverService: {
      async resolve(_context, id, cover, title, author) {
        return cover || (id.startsWith('import_') ? `/cache/${title}-${author}.jpg` : '');
      }
    } },
    './SourceCoverService': { SourceCoverService: { isEncoded: () => false } },
    '@kit.PerformanceAnalysisKit': { hilog }, '@kit.ImageKit': { image },
    '@kit.AVSessionKit': { avSession: { LoopMode: { LOOP_MODE_SEQUENCE: 0, LOOP_MODE_LIST: 1, LOOP_MODE_SINGLE: 2 } } },
    '@kit.NetworkKit': { http: {
      RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 2 },
      createHttp: () => ({ request: async () => ({ responseCode: 200, result: await read() }), destroy() {} })
    } },
    './CoverPrefetcher': { CoverPrefetcher: { loadOriginal: read } },
    './PlaybackCoordinator': { PlaybackCoordinator: { speechActive: false } }
  });
  return { service: Service.getInstance(), sources, pixels, reads: () => reads,
    block() { let resolve; gate = new Promise(done => { resolve = done; }); return resolve; },
    fail() { failDecode = true; } };
}

test('overlapping metadata updates share one decoded cover', async () => {
  const f = sessionFixture();
  const unblock = f.block();
  const first = f.service.loadCover('https://cover.test/book.jpg');
  const second = f.service.loadCover('https://cover.test/book.jpg');
  unblock();
  const result = await Promise.all([first, second]);
  assert.equal(f.reads(), 1);
  assert.equal(result[0], result[1]);
  assert.equal(f.sources[0].released, 1);
  await f.service.destroy();
  assert.equal(f.pixels[0].released, 1);
});

test('failed image decoding releases its native ImageSource', async () => {
  const f = sessionFixture(); f.fail();
  assert.equal(await f.service.loadCover('https://cover.test/broken.jpg'), null);
  assert.equal(f.sources[0].released, 1);
});

test('a cover finishing after session destruction is released and not cached', async () => {
  const f = sessionFixture();
  const unblock = f.block();
  const pending = f.service.loadCover('https://cover.test/late.jpg');
  await f.service.destroy(); unblock();
  assert.equal(await pending, null);
  await flush();
  assert.equal(f.service.coverCache.size, 0);
  assert.equal(f.pixels[0].released, 1);
});

test('cover eviction stays bounded and preserves the currently published media image', async () => {
  const f = sessionFixture();
  const current = await f.service.loadCover('https://cover.test/current.jpg');
  f.service.currentBook = { cover: 'https://cover.test/current.jpg' };
  f.service.currentMediaImage = current;
  for (let i = 0; i < 40; i++) await f.service.loadCover(`https://cover.test/${i}.jpg`);
  await flush();
  assert.equal(current.released, 0);
  assert.ok(f.pixels.filter(pixel => pixel.released === 0).length <= 8);
  await f.service.destroy();
  assert.ok(f.pixels.every(pixel => pixel.released === 1));
});

test('local placeholder reaches system metadata and a late image cannot replace the next book', async () => {
  const f = sessionFixture();
  const metadata = [];
  const loads = [];
  f.service.context = {};
  f.service.ensureReady = async () => true;
  f.service.session = { async setAVMetadata(value) { metadata.push({ ...value }); } };
  f.service.loadCover = path => new Promise(resolve => loads.push({ path, resolve }));
  const chapter = { id: 'chapter', title: 'chapter', duration: 0 };
  const book = { id: 'import_a', title: 'local title', author: 'local author', cover: '' };
  const first = f.service.updateMetadata(book, chapter);
  await flush();
  assert.equal(loads[0].path, '/cache/local title-local author.jpg');
  const second = f.service.updateMetadata({ ...book, id: 'import_b', cover: '/custom.jpg' }, chapter);
  await flush();
  const newest = { name: 'custom' };
  loads[1].resolve(newest);
  await second;
  const count = metadata.length;
  loads[0].resolve({ name: 'stale placeholder' });
  await first;
  assert.equal(metadata.length, count);
  assert.equal(metadata.at(-1).mediaImage, newest);
  const third = f.service.updateMetadata(book, chapter);
  await flush();
  const placeholder = { name: 'generated' };
  loads[2].resolve(placeholder);
  await third;
  assert.equal(metadata.at(-1).mediaImage, placeholder);
  assert.equal(book.cover, '');
});
