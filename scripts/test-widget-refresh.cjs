// Run actual WidgetUpdater with slow cover/network and cross-process form mocks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const code = ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/service/WidgetUpdater.ets'), 'utf8').replace(/import lazy /g, 'import '), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const flush = () => new Promise(resolve => setImmediate(resolve));

function fixture() {
  const pushes = [], requests = [], files = new Set(), descriptors = new Set();
  let snapshot = null, nextFd = 1;
  const coordinator = { speechActive: false };
  const fileIo = {
    OpenMode: { READ_ONLY: 0, READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
    async stat(file) { if (!files.has(file)) throw new Error('missing'); return { size: 100 }; },
    async open(file, mode) {
      if (mode !== 0) files.add(file);
      const fd = nextFd++; descriptors.add(fd); return { fd };
    },
    async write() {}, async close(file) { descriptors.delete(file.fd); },
    closeSync(file) { descriptors.delete(file.fd); }
  };
  const modules = {
    './PlaybackCoordinator': { PlaybackCoordinator: coordinator },
    '../utils/PlatformCompat': { PlatformCompat: { wearable: false } },
    '@kit.FormKit': {
      formBindingData: { createFormBindingData: data => data },
      formProvider: { async updateForm(id, data) { pushes.push({ id, ...data }); } }
    },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {} } },
    '@kit.NetworkKit': { http: { RequestMethod: { GET: 0 }, HttpDataType: { ARRAY_BUFFER: 0 },
      createHttp: () => ({ request: url => new Promise(resolve => requests.push({ url, resolve })), destroy() {} }) } },
    '@kit.CoreFileKit': { fileIo },
    '@kit.ImageKit': { image: { createImageSource() { throw new Error('use small original'); } } },
    './StorageMigrationService': { StorageMigrationService: {
      async migrateFilesWithPrefix() {}, async migrateFile() { return false; }
    } },
    './PreferenceService': { PreferenceService: {
      async getWidgetPlayerSnapshot() { return snapshot; },
      async setWidgetPlayerSnapshot(value) { snapshot = value; },
      async invalidateCache() {}, async init() {}, async getWidgetFormIds() { return ['form-1', 'form-2']; },
      async removeWidgetFormId() {}
    } }
  };
  const module = { exports: {} };
  vm.runInNewContext(code, { module, exports: module.exports, console, setTimeout,
    require(name) { if (modules[name]) return modules[name]; throw new Error(name); } });
  const updater = module.exports.WidgetUpdater;
  updater.setContext({ filesDir: '/files', cacheDir: '/cache' });
  return { updater, pushes, requests, descriptors, coordinator, snapshot: () => snapshot };
}
function state(id, playing = false) {
  return { currentBook: { id, title: id, author: 'author', cover: `https://cover/${id}` },
    currentChapter: { id: `${id}-chapter`, title: `${id}-chapter` },
    progressMs: 0, durationMs: 0, isPlaying: playing };
}
async function main() {
  const f = fixture();
  await f.updater.updatePlayerCard(state('a'), true);
  await flush();
  assert.equal(f.pushes.length, 2, 'both cards update before cover response');
  assert.equal(f.pushes[0].bookId, 'a');
  assert.equal(f.requests.length, 1);
  await f.updater.updatePlayerCard(state('b'), true);
  await f.updater.updatePlayerCard(state('b', true));
  await f.updater.updatePlayerCard(state('b', true));
  await flush();
  assert.equal(f.requests.length, 2, 'same cover shares the in-flight download');
  const beforeOldCover = f.pushes.length;
  f.requests[0].resolve({ responseCode: 200, result: new ArrayBuffer(8) });
  await flush();
  assert.equal(f.pushes.length, beforeOldCover, 'old cover must not restore the previous book');
  f.requests[1].resolve({ responseCode: 200, result: new ArrayBuffer(8) });
  await flush();
  assert.equal(f.pushes.at(-1).bookId, 'b');
  assert.equal(f.pushes.at(-1).isPlaying, true);
  assert.ok(f.pushes.at(-1).imgName, 'same-state synchronization must not lose pending cover');
  assert.equal(f.descriptors.size, 0, 'all cover descriptors are released');
  await f.updater.updatePlayerCard(null, true);
  assert.equal(f.pushes.at(-1).hasBook, false);
  f.coordinator.speechActive = true;
  const speechBook = { id: 'ebook', title: 'ebook title', author: 'author', cover: '',
    chapters: [{ id: 'c1', title: 'chapter one' }, { id: 'c2', title: 'chapter two' }] };
  const speech = { chapterIndex: 0, charOffset: 20, playing: true, loading: false };
  await f.updater.updateSpeechCard(speechBook, speech);
  assert.equal(f.pushes.at(-1).bookId, 'ebook');
  assert.equal(f.pushes.at(-1).isPlaying, true);
  assert.equal(f.snapshot().charOffset, 20);
  await f.updater.updatePlayerCard(state('old-audio'), true);
  assert.equal(f.pushes.at(-1).bookId, 'ebook', 'old audio callbacks cannot overwrite active TTS');
  speech.playing = false; speech.chapterIndex = 1;
  await f.updater.updateSpeechCard(speechBook, speech);
  assert.equal(f.pushes.at(-1).chapterTitle, 'chapter two');
  assert.equal(f.pushes.at(-1).isPlaying, false);
  f.coordinator.speechActive = false;
  await f.updater.updatePlayerCard(state('old-audio'), true);
  assert.equal(f.pushes.at(-1).bookId, 'ebook', 'audio release cannot restore an older audio book');
  console.log('PASS immediate multi-card refresh, slow cover, rapid book/state changes, deduplication and FD cleanup');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
