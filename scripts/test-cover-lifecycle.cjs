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

function prefetchFixture() {
  const requests = [], timers = [], disk = new Map();
  let revision = 0;
  const service = load('CoverLoader', {
    './SourceCoverService': { SourceCoverService: {
      isEncoded: value => value.includes('/encoded/'), cached: () => '',
      resolve: async value => { requests.push({ url: value }); return 'file:///source-' + revision; }, invalidate() {}
    } },
    './rulesource/LocalRuleSourceRepository': { LocalRuleSourceRepository: { getCoverRevision: () => revision } },
    './rulesource/light/LightSourceCoverCache': { LightSourceCoverCache: { materialize: async (key, download) => {
      if (!disk.has(key)) { await download(); disk.set(key, 'file:///cover/' + disk.size); }
      return disk.get(key);
    } } },
    '@ohos.file.fs': { default: { accessSync: () => true } },
    '@kit.NetworkKit': { http: { HttpDataType: { ARRAY_BUFFER: 1 }, createHttp: () => ({
      request: (url, options) => new Promise((resolve, reject) => requests.push({ url, options, resolve, reject })), destroy() {}
    }) } }
  }, { Uint8Array, Error, setTimeout: callback => { timers.push(callback); return timers.length; } });
  const complete = (i = 0) => requests[i].resolve({ responseCode: 200, result: new ArrayBuffer(16) });
  return { service, requests, timers, complete, disk, revision: () => revision++ };
}

test('visible consumers share a single download and cached file with speculative work', async () => {
  const f = prefetchFixture(), url = 'https://cover.test/shared';
  f.service.prefetch(url);
  const one = f.service.acquire(url), two = f.service.acquire(url);
  assert.equal(f.requests.length, 1);
  one.cancel(); f.complete();
  assert.equal(await two.promise, await one.promise);
  await flush();
  assert.equal(await f.service.acquire(url).promise, 'file:///cover/0');
  assert.equal(f.requests.length, 1); assert.equal(f.service.active, 0);
});

test('speculation reserves foreground slots and visible queued jobs outrank prefetch', async () => {
  const f = prefetchFixture();
  f.service.prefetchMany(Array.from({ length: 100 }, (_, i) => 'https://cover.test/bg' + i));
  assert.equal(f.requests.length, 1);
  const handles = Array.from({ length: 4 }, (_, i) => f.service.acquire('https://cover.test/visible' + i));
  assert.equal(f.requests.length, 4);
  f.complete(1); await flush();
  assert.equal(f.requests[4].url, 'https://cover.test/visible3');
  assert.ok(f.service.queue.length <= 3);
  handles.forEach(handle => handle.cancel());
});

test('leaving removes unneeded queued work without cancelling another subscriber', async () => {
  const f = prefetchFixture();
  for (let i = 0; i < 4; i++) f.service.acquire('https://cover.test/active' + i);
  const first = f.service.acquire('https://cover.test/shared');
  const second = f.service.acquire('https://cover.test/shared');
  first.cancel(); assert.equal(f.service.queue.length, 1);
  second.cancel(); assert.equal(f.service.queue.length, 0);
  assert.equal(await first.promise, '');
  f.complete(); await flush(); assert.equal(f.requests.length, 4);
});

test('network errors retry once then cool down, with no extra UI download path', async () => {
  const f = prefetchFixture(), url = 'https://cover.test/offline';
  const handle = f.service.acquire(url);
  const rejected = assert.rejects(handle.promise);
  f.requests[0].reject(new Error('offline')); await flush();
  assert.equal(f.timers.length, 1); f.timers.shift()(); await flush();
  f.requests[1].reject(new Error('offline')); await rejected; await flush();
  await assert.rejects(f.service.acquire(url).promise);
  assert.equal(f.requests.length, 2); assert.equal(f.service.active, 0);
});

test('an abandoned failed download does not retry or poison a later visible request', async () => {
  const f = prefetchFixture(), url = 'https://cover.test/leaving';
  const handle = f.service.acquire(url); const rejected = assert.rejects(handle.promise);
  handle.cancel(); f.requests[0].reject(new Error('offline')); await rejected; await flush();
  assert.equal(f.timers.length, 0); assert.equal(f.service.failures.size, 0);
  const next = f.service.acquire(url); f.complete(1); await next.promise;
});

test('request headers and source revision isolate shared cover identities', async () => {
  const f = prefetchFixture(), url = 'https://cover.test/same';
  f.service.registerHeaders(url, { Authorization: 'first' }); const first = f.service.acquire(url);
  f.service.registerHeaders(url, { Authorization: 'second' }); const second = f.service.acquire(url);
  assert.equal(f.requests.length, 2);
  assert.equal(f.requests[0].options.header.authorization, 'first');
  assert.equal(f.requests[1].options.header.authorization, 'second');
  f.complete(0); f.complete(1); await Promise.all([first.promise, second.promise]); await flush();
  const encoded = 'https://cover.test/encoded/book';
  assert.equal(await f.service.acquire(encoded).promise, 'file:///source-0');
  f.revision(); assert.equal(await f.service.acquire(encoded).promise, 'file:///source-1');
});


function sessionFixture() {
  const sources = [];
  const pixels = [];
  const opened = [];
  const closed = [];
  let reads = 0;
  let gate = Promise.resolve();
  let failDecode = false;
  const read = async () => { reads++; await gate; return new ArrayBuffer(16); };
  const image = {
    createImageSource(data) {
      const source = {
        released: 0,
        async createPixelMap() {
          if (failDecode) throw new Error('bad image');
          const pixel = { kind: new Uint8Array(data)[0] === 1 ? 'placeholder' : 'cover',
            released: 0, async release() { this.released++; } };
          pixels.push(pixel); return pixel;
        },
        async release() { this.released++; }
      };
      sources.push(source); return source;
    }
  };
  const Service = load('AVSessionService', {
    '../model/DesktopLyric': { DesktopLyricState: class { visible = false; supported = false; } },
    '../utils/PlatformCompat': { PlatformCompat: { supports: () => false } },
    './membership/MembershipFeatureLease': { MembershipFeatureLease: class { stop() {} } },
    './LocalBookCoverService': { LocalBookCoverService: {
      async resolve(_context, id, cover, title, author) {
        return cover || (id.startsWith('import_') ? `/cache/${title}-${author}.jpg` : '');
      }
    } },
    './SourceCoverService': { SourceCoverService: { isEncoded: () => false } },
    '@kit.PerformanceAnalysisKit': { hilog }, '@kit.ImageKit': { image },
    '@kit.CoreFileKit': { fileIo: {
      OpenMode: { READ_ONLY: 0 },
      async open(path) { opened.push(path); return { fd: 7 }; },
      async stat() { return { size: 16 }; },
      async close(file) { closed.push(file.fd); }
    } },
    '@kit.AVSessionKit': { avSession: { LoopMode: { LOOP_MODE_SEQUENCE: 0, LOOP_MODE_LIST: 1, LOOP_MODE_SINGLE: 2 } } },
    '@kit.NetworkKit': { http: {
      RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 2 },
      createHttp: () => { throw Error('System artwork must use the shared cover cache'); }
    } },
    './CoverPrefetcher': { CoverPrefetcher: { loadOriginal: read } },
    './PlaybackCoordinator': { PlaybackCoordinator: { speechActive: false } }
  }, { $r: name => ({ id: name }) });
  const service = Service.getInstance();
  const displayed = {};
  service.context = { resourceManager: { async getMediaContent() { return new Uint8Array([1]); } } };
  service.session = {
    async setAVMetadata(value) {
      // The system artwork cache is independent of the title: omitted/undefined artwork
      // does not prove that an old rendered image has been replaced.
      for (const [key, field] of Object.entries(value)) {
        if (field !== undefined) displayed[key] = field;
      }
    }
  };
  return { service, displayed, sources, pixels, opened, closed, reads: () => reads,
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

test('switching away from a failed source replaces stale system artwork before the next cover loads', async () => {
  const f = sessionFixture();
  const chapter = { id: 'chapter', title: 'chapter', duration: 0 };
  const book = id => ({ id, title: id, author: 'author', cover: `https://cover.test/${id}.jpg` });
  await f.service.updateMetadata(book('failed-source'), chapter);
  const previous = f.displayed.mediaImage;
  const unblock = f.block();
  const switching = f.service.updateMetadata(book('next'), chapter);
  await flush();
  assert.equal(f.displayed.artist, 'next');
  assert.notEqual(f.displayed.mediaImage, previous, 'the new title must never retain the previous book artwork');
  assert.equal(f.displayed.mediaImage.kind, 'placeholder');
  await f.service.updateMetadataDuration(120000);
  assert.equal(f.displayed.mediaImage.kind, 'placeholder');
  unblock();
  await switching;
  assert.equal(f.displayed.mediaImage.kind, 'cover');
  assert.equal(f.displayed.duration, 120000);
});

test('a missing or broken next cover keeps explicit placeholder artwork, including metadata retry', async () => {
  const f = sessionFixture();
  const chapter = { id: 'chapter', title: 'chapter', duration: 0 };
  const book = { id: 'first', title: 'first', author: 'author', cover: 'https://cover.test/first.jpg' };
  await f.service.updateMetadata(book, chapter);
  await f.service.updateMetadata({ ...book, id: 'missing', title: 'missing', cover: '' }, chapter);
  assert.equal(f.displayed.mediaImage.kind, 'placeholder');
  await f.service.updateMetadata(book, chapter);
  const publish = f.service.session.setAVMetadata;
  let failFirstPublish = true;
  f.service.session.setAVMetadata = async value => {
    if (failFirstPublish) { failFirstPublish = false; throw new Error('system update failed'); }
    await publish(value);
  };
  f.fail();
  await f.service.updateMetadata({ ...book, id: 'broken', title: 'broken', cover: 'https://cover.test/broken.jpg' }, chapter);
  assert.equal(f.displayed.artist, 'broken');
  assert.equal(f.displayed.mediaImage.kind, 'placeholder', 'failed image decode and retry must not retain old artwork');
  await f.service.destroy();
  assert.ok(f.pixels.every(pixel => pixel.released === 1));
});

test('failed image decoding releases its native ImageSource', async () => {
  const f = sessionFixture(); f.fail();
  assert.equal(await f.service.loadCover('https://cover.test/broken.jpg'), null);
  assert.equal(f.sources[0].released, 1);
});

test('source cache file URIs publish the new cover instead of going through rawfile resources', async () => {
  const f = sessionFixture();
  const chapter = { id: 'chapter', title: 'chapter', duration: 0 };
  const book = { id: 'source-book', title: 'source book', author: 'author',
    cover: 'file:///data/storage/el2/base/cache/source_covers/cover.img' };
  await f.service.updateMetadata(book, chapter);
  assert.equal(f.displayed.mediaImage.kind, 'cover');
  assert.deepEqual(f.opened, ['/data/storage/el2/base/cache/source_covers/cover.img']);
  assert.deepEqual(f.closed, [7]);
  assert.equal(f.reads(), 0, 'the source has already downloaded the image');
  f.fail();
  assert.equal(await f.service.loadCover('file:///data/storage/el2/base/cache/source_covers/broken.img'), null);
  assert.deepEqual(f.closed, [7, 7], 'failed decoding must also close the cover file');
});

test('chapter changes retain resolved source artwork without publishing a placeholder', async () => {
  const f = sessionFixture();
  const book = { id: 'source-book', sourceUrl: 'source', title: 'book', author: 'author',
    cover: 'https://cover.test/encoded/book' };
  const decoded = { kind: 'decoded source cover' };
  f.service.loadCover = async key => key === 'avsession://cover-placeholder'
    ? { kind: 'placeholder' } : decoded;
  await f.service.updateMetadata(book, { id: 'one', title: 'one', duration: 0 });
  const images = [];
  f.service.session.setAVMetadata = async value => { images.push(value.mediaImage); };
  await f.service.updateMetadata(book, { id: 'two', title: 'two', duration: 0 });
  assert.ok(images.length > 0);
  assert.ok(images.every(value => value === decoded), 'no placeholder between chapters even if raw URL is not the decoded cache key');
  images.length = 0;
  book.cover = 'https://cover.test/replaced';
  await f.service.updateMetadata(book, { id: 'three', title: 'three', duration: 0 });
  assert.equal(images[0].kind, 'placeholder', 'a changed cover must not keep stale artwork, even with a mutated Book instance');
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
  f.service.loadCover = path => path === 'avsession://cover-placeholder'
    ? Promise.resolve({ name: 'default placeholder' }) : new Promise(resolve => loads.push({ path, resolve }));
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
