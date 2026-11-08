// Execute the real HiCar and AVSession services; simulate only platform/storage dependencies.
// DEVECO_HOME must point to the installed Release IDE. No device data is changed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
function load(file, imports = {}, globals = {}) {
  const source = fs.readFileSync(path.join(root, file), 'utf8')
    .replace(/import lazy /g, 'import ').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const module = { exports: {} };
  const code = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  } }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, console, Date, Promise, Map, Set,
    $r: id => ({ id }), ...globals, require(name) {
      if (!(name in imports)) throw new Error(`Missing dependency: ${name}`);
      return imports[name];
    }
  }, { filename: file });
  return module.exports;
}
const flush = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}
function book(id, count = 3, contentType = 'audio') {
  return { id, title: id, author: '作者', cover: '', contentType, sourceUrl: 'https://source.test',
    chapters: Array.from({ length: count }, (_, i) => ({ id: `${id}-${i}`, index: i + 1,
      title: `第${i + 1}章`, duration: 120, source: { type: 'url', value: `https://source.test/${id}/${i}` } })) };
}
function carFixture({ supported = true, wearable = false, failEvent = false, failStatus = false } = {}) {
  const events = new Map(), windowEvents = new Map(), calls = [];
  const state = { connected: false, displayId: 7, defaultId: 7 };
  const player = { currentBook: null, currentChapter: null };
  const data = { books: [], downloads: [], history: [], shelf: [], progress: null, wait: null };
  const awareness = {
    on(event, _types, callback) {
      if (failEvent && event === 'smartMobilityEvent') throw new Error('event registration failed');
      if (failStatus && event === 'smartMobilityStatus') throw new Error('status registration failed');
      assert(!events.has(event), 'only one subscription per event');
      events.set(event, callback);
    },
    off(event, _types, callback) { assert.equal(events.get(event), callback); events.delete(event); },
    getSmartMobilityStatus: () => ({ type: 1, status: state.connected ? 1 : 0 })
  };
  const nativeWindow = {
    on(event, callback) { assert(!windowEvents.has(event)); windowEvents.set(event, callback); },
    off(event, callback) { assert.equal(windowEvents.get(event), callback); windowEvents.delete(event); },
    getWindowProperties: () => ({ displayId: state.displayId })
  };
  const audio = {
    whenReady: async () => { if (data.wait) await data.wait; },
    play: async () => { calls.push(['play']); },
    playChapterAndSeek: async (b, c, ms) => { calls.push(['seek', b.id, c.id, ms]); },
    playChapterFromSavedProgress: async (b, c) => { calls.push(['saved', b.id, c.id]); }
  };
  const preferences = {
    init: async () => {}, getHistory: async () => data.history,
    getShelfFavorites: async () => data.shelf, getProgress: async () => data.progress,
    applySkipConfig: async b => { calls.push(['skip', b.id]); }
  };
  const { HiCarService } = load('service/HiCarService.ets', {
    '@kit.ArkUI': { AppStorageV2: { connect: () => player }, display: { getDefaultDisplaySync: () => ({ id: state.defaultId }) } },
    '@kit.CarKit': { smartMobilityCommon: { getSmartMobilityAwareness: () => awareness,
      SmartMobilityType: { HICAR: 1 }, SmartMobilityStatus: { RUNNING: 1 } } },
    '../model/HiCar': load('model/HiCar.ets'), '../model/PlayerState': {},
    '../utils/PlatformCompat': { PlatformCompat: { wearable } },
    './AudioService': { AudioService: { getInstance: () => audio } },
    './PreferenceService': { PreferenceService: preferences },
    './BookSourceService': { BookSourceService: { loadAudioBook: async b => { calls.push(['source', b.id]); return book(b.id); } } },
    './DataService': { DataService: {
      getBooks: async () => data.books, getBookById: async (_ctx, id) => data.books.find(b => b.id === id),
      resolveChapterIndex: (b, id) => b.chapters.findIndex(c => c.id === id)
    } },
    './DownloadService': { DownloadService: { getInstance: () => ({ init: async () => {},
      getAllBookStatuses: () => data.downloads, getBookStatus: id => data.downloads.find(r => r.bookId === id) }) } }
  }, { canIUse: () => supported, console: { warn() {} } });
  return { service: HiCarService.instance, HiCarService, events, windowEvents, nativeWindow,
    calls, state, player, data, context: { moveAbilityToBackground: async () => {} } };
}
async function testCar() {
  const f = carFixture();
  f.service.initialize(f.context);
  f.service.initialize(f.context);
  f.service.bindWindow(f.nativeWindow);
  f.service.bindWindow(f.nativeWindow);
  assert.equal(f.events.size, 2); assert.equal(f.windowEvents.size, 1);
  f.state.connected = true; f.service.refresh();
  assert.equal(f.service.state.connected, true);
  assert.equal(f.service.state.carWindow, false, 'connection alone must not replace phone UI');
  f.state.displayId = 0; f.windowEvents.get('displayIdChange')(0);
  assert.equal(f.service.state.carWindow, true, 'default display ID is not necessarily zero');
  f.events.get('smartMobilityStatus')({ type: 2, status: 0 });
  assert.equal(f.service.state.connected, true, 'ignore other mobility scenes');
  f.state.connected = false; f.service.refresh();
  assert.equal(f.service.state.carWindow, false, 'disconnect restores normal layout');
  for (const id of [undefined, -1, NaN, 1.5, 7]) assert.equal(f.HiCarService.useCarWindow(true, id, 7), false);
  f.service.destroy();
  assert.equal(f.events.size, 0); assert.equal(f.windowEvents.size, 0);
  for (const options of [{ supported: false }, { wearable: true }]) {
    const unavailable = carFixture(options);
    unavailable.service.initialize(unavailable.context);
    assert.equal(unavailable.service.state.supported, false);
    assert.equal(unavailable.events.size, 0);
    unavailable.service.destroy();
  }
  for (const options of [{ failEvent: true }, { failStatus: true }, { failEvent: true, failStatus: true }]) {
    const partial = carFixture(options);
    partial.service.initialize(partial.context);
    assert.equal(partial.service.state.supported, true);
    assert.equal(partial.events.size, 2 - Number(!!options.failEvent) - Number(!!options.failStatus));
    partial.state.connected = true; partial.service.refresh();
    assert.equal(partial.service.state.connected, true, 'foreground query survives subscription failure');
    if (!options.failStatus) {
      partial.events.get('smartMobilityStatus')({ type: 1, status: 0 });
      assert.equal(partial.service.state.connected, false, 'optional event failure preserves status updates');
    }
    partial.service.destroy();
    assert.equal(partial.events.size, 0);
  }

  f.service.initialize(f.context);
  const a = book('a'), b = book('b'), local = book('import_local'); local.sourceUrl = '';
  f.data.books = [a, book('text', 3, 'text'), b, book('comic', 3, 'comic'), local];
  f.data.history = ['text', 'b', 'a', 'b', 'missing'].map(bookId => ({ bookId }));
  f.data.shelf = ['b', 'text', 'a'];
  f.data.downloads = [{ bookId: 'offline', title: '下载保留书', author: '', cover: '',
    chapterCount: 3, downloadedCount: 1, contentType: 'audio', chapters: [
      { chapterId: 'offline-2', chapterIndex: 2, title: '第二章', status: 'completed',
        filePath: '/sandbox/audio.mp3', pageUrl: 'https://source.test/chapter', durationSec: 150 },
      { chapterId: 'offline-1', chapterIndex: 1, status: 'failed' }
    ] }, { bookId: 'text', contentType: 'text', downloadedCount: 1 },
    { bookId: 'comic', contentType: 'comic', downloadedCount: 1 }];
  const library = await f.service.loadLibrary();
  const ids = rows => Array.from(rows, row => row.id);
  assert.deepEqual(ids(library.recent), ['b', 'a']);
  assert.deepEqual(ids(library.shelf), ['b', 'a']);
  assert.deepEqual(ids(library.downloaded), ['import_local', 'offline']);
  const offline = await f.service.openBook(library.downloaded[1]);
  assert.equal(offline.chapters[0].id, 'offline-2');
  assert.equal(offline.chapters[0].source.value, '/sandbox/audio.mp3');
  assert.equal(offline.chapters[0].originSourceValue, 'https://source.test/chapter');
  assert(!f.calls.some(c => c[0] === 'source'), 'offline catalog opens without fetching a source');
  assert.equal((await f.service.openBook(book('online', 0))).chapters.length, 3);
  await assert.rejects(f.service.openBook(book('text', 1, 'text')));
  f.data.progress = { chapterId: a.chapters[1].id, positionMs: 42500 };
  assert.equal(await f.service.chapterPosition(a), 1, 'catalog opens at saved chapter');
  assert.equal(await f.service.chapterPosition(b), 0, 'missing saved chapter starts at first item');
  await f.service.resume(a, () => true);
  assert.deepEqual(f.calls.at(-1), ['seek', 'a', 'a-1', 42500]);
  f.player.currentBook = a; f.player.currentChapter = a.chapters[1];
  f.data.progress = { chapterId: a.chapters[0].id, positionMs: 0 };
  assert.equal(await f.service.chapterPosition(a), 1, 'live chapter takes priority over stored progress');
  await f.service.resume(a, () => true);
  assert.deepEqual(f.calls.at(-1), ['play'], 'same-book resume does not restart saved chapter');
  const wait = deferred(); f.data.wait = wait.promise;
  let current = true;
  const count = f.calls.length, late = f.service.resume(b, () => current);
  current = false; wait.resolve(); await late;
  assert.equal(f.calls.length, count, 'leaving the page prevents delayed playback');
  f.service.destroy();
}

function sessionFixture() {
  const calls = [], events = new Map(), coordinator = { speechActive: false };
  const waits = { queue: null };
  const native = new Proxy({
    on: (event, callback) => events.set(event, callback),
    off: event => events.delete(event),
    async setAVQueueTitle(value) { calls.push(['title', value]); },
    async setAVQueueItems(items) {
      assert(items.length <= 100);
      const wait = waits.queue; waits.queue = null;
      if (wait) await wait;
      calls.push(['queue', items]);
    },
    async setAVPlaybackState(value) { calls.push(['playback', value]); },
    async setAVMetadata(value) { calls.push(['metadata', value]); }
  }, { get(target, key) { return key === 'then' ? undefined : key in target ? target[key] : () => {}; } });
  const lyric = load('model/DesktopLyric.ets', { './AudioSubtitle': load('model/AudioSubtitle.ets') });
  const { AVSessionService } = load('service/AVSessionService.ets', {
    './MembershipService': {}, '../model/MembershipState': { MembershipState: { current: { hasAccess: true } } },
    './membership/MembershipFeatureLease': { MembershipFeatureLease: class { start() {} stop() {} } },
    './SourceCoverService': { SourceCoverService: { isEncoded: () => false } },
    './LocalBookCoverService': { LocalBookCoverService: { resolve: async () => '' } },
    './CoverPrefetcher': {}, './PlaybackCoordinator': { PlaybackCoordinator: coordinator },
    '../model/DesktopLyric': lyric,
    '@kit.AVSessionKit': { avSession: { createAVSession: async () => native,
      PlaybackState: { PLAYBACK_STATE_PAUSE: 3, PLAYBACK_STATE_PLAY: 2 },
      LoopMode: { LOOP_MODE_SEQUENCE: 0, LOOP_MODE_LIST: 1, LOOP_MODE_SINGLE: 2 } } },
    '../utils/PlatformCompat': { PlatformCompat: { supports: n => n <= 20, wearable: false } },
    '@kit.ImageKit': {}, '@kit.CoreFileKit': {},
    '@kit.AbilityKit': { wantAgent: { getWantAgent: async () => ({}),
      OperationType: { START_ABILITY: 0 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 0 } } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn() {}, error() {} } }
  });
  const service = AVSessionService.getInstance();
  service.coverCache.set('avsession://cover-placeholder', { release: async () => {} });
  return { service, calls, events, coordinator, waits,
    ready: () => service.init({ abilityInfo: { bundleName: 'fixture', name: 'EntryAbility' } }),
    queue: () => calls.filter(c => c[0] === 'queue').at(-1)[1] };
}
async function testQueue() {
  const f = sessionFixture(); await f.ready();
  const selected = [];
  const callbacks = { onSelectChapter: (b, c) => selected.push([b.id, c.id]) };
  f.service.setCallbacks(callbacks);
  const a = book('a', 250), b = book('b', 3);
  await f.service.updateMetadata(a, a.chapters[137]); await flush();
  const items = f.queue();
  assert.equal(items.length, 100);
  assert.equal(items[0].description.assetId, 'a_a-100');
  const active = f.calls.filter(c => c[0] === 'playback').at(-1)[1].activeItemId;
  assert.equal(active, items[37].itemId);
  f.events.get('skipToQueueItem')(items[40].itemId);
  assert.deepEqual(selected.at(-1), ['a', 'a-140']);
  await f.service.updateMetadata(a, a.chapters[138]);
  await f.service.updatePlaybackState(true, 10000, 1.5, 120000);
  assert.equal(f.calls.filter(c => c[0] === 'playback').at(-1)[1].activeItemId, items[38].itemId);
  const wait = deferred(); f.waits.queue = wait.promise;
  await f.service.updateMetadata(b, b.chapters[0]); await flush();
  f.events.get('skipToQueueItem')(items[40].itemId);
  assert.equal(selected.length, 1, 'old book command is rejected while next queue is pending');
  await f.service.updateMetadata(a, a.chapters[249]);
  wait.resolve(); await flush();
  const latest = f.queue();
  assert.equal(latest.length, 50);
  assert.equal(latest[0].description.assetId, 'a_a-200', 'a delayed queue cannot overwrite the newest one');
  assert(!latest.some(item => items.some(old => old.itemId === item.itemId)), 'queue item IDs cannot be reused');
  f.events.get('skipToQueueItem')(items[40].itemId);
  assert.equal(selected.length, 1, 'old window remains invalid after returning to the same book');
  f.events.get('skipToQueueItem')(latest[0].itemId);
  assert.deepEqual(selected.at(-1), ['a', 'a-200']);
  f.coordinator.speechActive = true;
  f.service.setSpeechCallbacks({});
  f.events.get('skipToQueueItem')(latest[0].itemId);
  assert.equal(selected.length, 2, 'TTS immediately blocks audio chapter commands');
  await flush(); assert.equal(f.queue().length, 0, 'TTS clears the published audio queue');
  f.coordinator.speechActive = false; f.service.restoreAudioCallbacks();
  await f.service.updateMetadata(b, b.chapters[1]); await flush();
  f.events.get('skipToQueueItem')(f.queue()[2].itemId);
  assert.deepEqual(selected.at(-1), ['b', 'b-2']);
  await f.service.destroy();
  assert.equal(f.service.queueChapters.size, 0);
}
async function main() {
  await testCar(); await testQueue();
  console.log('HiCar regression passed: lifecycle, display routing, audio library, resume and media queue.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
