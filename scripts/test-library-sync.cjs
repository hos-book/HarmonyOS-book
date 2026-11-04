// Real merge, sync coordinator, file transport and preference adapters; simulated Huawei cloud only.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const { EventEmitter } = require('node:events');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const compiled = new Map();
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'listenbook-sync-'));
const cloud = path.join(temp, 'cloud');
fs.mkdirSync(cloud);
let clock = Date.now();
class TestDate extends Date { static now() { return clock; } }
const json = value => JSON.parse(JSON.stringify(value));

function makeStore() {
  const values = new Map();
  return {
    values, fail: false,
    getSync: (key, fallback) => values.get(key) ?? fallback,
    get: async (key, fallback) => values.get(key) ?? fallback,
    getAllSync: () => Object.fromEntries(values), getAll: async () => Object.fromEntries(values),
    putSync: (key, value) => values.set(key, value), put: async (key, value) => values.set(key, value),
    deleteSync: key => values.delete(key), delete: async key => values.delete(key),
    async flush() { if (this.fail) throw new Error('disk full'); }
  };
}

function launch(name, previous) {
  const filesDir = path.join(temp, name);
  fs.mkdirSync(filesDir, { recursive: true });
  const context = { filesDir, cloudFileDir: cloud };
  const stores = previous?.stores || new Map();
  const store = key => { if (!stores.has(key)) stores.set(key, makeStore()); return stores.get(key); };
  const control = { online: true, confirmed: true, failCloudWrite: false, partial: 23, starts: 0, api: 26,
    entitled: true, inactive: false, onRead: null,
    watch: new Map(), books: previous?.control.books || [], player: {}, speech: {} };
  const auth = { isLoggedIn: true, openID: 'account-A', logging: false, restoring: false, dataOperation: false,
    async restore() {}, beginDataOperation() { assert.equal(this.dataOperation, false); this.dataOperation = true; },
    endDataOperation() { this.dataOperation = false; } };
  const events = new EventEmitter();
  const fdPaths = new Map();
  const io = {
    OpenMode: { READ_ONLY: 0, READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
    access: async p => fs.existsSync(p), mkdir: async p => fs.mkdirSync(p),
    listFile: async p => { if (p === cloud && !control.online) throw new Error('offline'); return fs.readdirSync(p); },
    open: async (p, mode) => {
      if (p.startsWith(cloud) && mode && control.failCloudWrite) throw new Error('cloud unavailable');
      const fd = fs.openSync(p, mode ? 'w+' : 'r'); fdPaths.set(fd, p); return { fd };
    },
    close: async f => { fs.closeSync(f.fd); fdPaths.delete(f.fd); },
    stat: async p => { const s = typeof p === 'number' ? fs.fstatSync(p) : fs.statSync(p); s.location = control.confirmed ? 3 : 1; return s; },
    read: async (fd, buffer, options) => {
      if (fdPaths.get(fd)?.startsWith(cloud) && control.onRead) control.onRead();
      return fs.readSync(fd, Buffer.from(buffer), 0, Math.min(options.length, control.partial), options.offset);
    },
    write: async (fd, buffer, options) => fs.writeSync(fd, Buffer.from(buffer), 0,
      Math.min(options.length, control.partial), options.offset),
    fsync: async fd => fs.fsyncSync(fd), moveFile: async (a, b) => fs.renameSync(a, b),
    unlink: async p => fs.unlinkSync(p)
  };
  const actual = new Set(['service/LibrarySyncService', 'service/sync/LibrarySyncModel', 'service/sync/LibrarySyncFiles',
    'service/PreferenceService', 'service/text/TextReadingProgressService', 'model/BookPresentation']);
  const mocks = {
    '@kit.AbilityKit': { ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: -1 } } },
    '@kit.ArkData': { preferences: { getPreferences: async (_context, options) => store(options.name) } },
    '@kit.BasicServicesKit': { emitter: events },
    '@kit.ArkUI': { AppStorageV2: { connect: () => control.player } },
    '@kit.ArkTS': { util: { generateRandomUUID: () => crypto.randomUUID(),
      TextEncoder: class { encodeInto(s) { return new Uint8Array(Buffer.from(s)); } },
      TextDecoder: class { decodeToString(b) { return Buffer.from(b).toString('utf8'); } } } },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd: () => { const hash = crypto.createHash('sha256');
      return { update: async ({ data }) => { hash.update(data); }, digest: async () => ({ data: new Uint8Array(hash.digest()) }) }; } } },
    '@kit.CoreFileKit': { fileIo: io, fileUri: { getUriFromPath: p => p }, cloudSync: {
      FileState: { UPLOAD_SUCCESS: 4, INITIAL_AFTER_DOWNLOAD: 0 },
      getCoreFileSyncState: () => control.confirmed ? 4 : 1,
      FileSync: class { async start() { control.starts++; if (!control.online) throw new Error('offline'); } },
      registerChange: (uri, recursive, cb) => control.watch.set(uri, cb), unregisterChange: uri => control.watch.delete(uri)
    } },
    'service/AuthService': { AuthService: { instance: auth } },
    'model/MembershipState': { MembershipState: { current: {
      get hasAccess() { return control.entitled; }, get confirmedInactive() { return control.inactive; }
    } } },
    'service/MembershipService': { MembershipService: { instance: {
      hasCurrentEntitlement: async () => control.entitled
    } } },
    'utils/PlatformCompat': { PlatformCompat: { wearable: false, supports: n => control.api >= n } },
    'service/text/TextToSpeechService': { TextToSpeechService: { getInstance: () => ({ state: control.speech }) } },
    'model/GeneralSettings': { GeneralSettings: { current: { historyEnabled: true } } },
    'model/TextReading': { TextReadingPosition: class {} },
    'service/DataService': { DataService: {
      exportBackupBookShells: async () => control.books,
      restoreBackupBookShells: async books => {
        for (const book of books) { const i = control.books.findIndex(v => v.id === book.id);
          if (i < 0) control.books.push(book); else control.books[i] = book; }
      }
    } }
  };
  const modules = new Map();
  const sandbox = vm.createContext({ console, Date: TestDate, Error, ObservedV2: v => v, Trace: () => {},
    canIUse: () => true, setTimeout: () => 1, clearTimeout() {}, setInterval: () => 2, clearInterval() {} });
  function load(name) {
    if (mocks[name]) return mocks[name];
    if (!actual.has(name)) return {};
    if (modules.has(name)) return modules.get(name);
    if (!compiled.has(name)) {
      const source = fs.readFileSync(path.join(root, name + '.ets'), 'utf8');
      compiled.set(name, ts.transpileModule(source, { compilerOptions: {
        module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021, experimentalDecorators: true
      } }).outputText);
    }
    const exports = {};
    modules.set(name, exports);
    const require = request => load(request.startsWith('@') ? request :
      path.posix.normalize(path.posix.join(path.posix.dirname(name), request)));
    vm.runInContext(`(function(exports, require) {\n${compiled.get(name)}\n})`, sandbox,
      { filename: name + '.ets' })(exports, require);
    return exports;
  }
  const pref = load('service/PreferenceService').PreferenceService;
  pref.store = store('listenbook_prefs');
  const reading = load('service/text/TextReadingProgressService').TextReadingProgressService;
  reading.store = store('online_text_reading_progress');
  const module = load('service/LibrarySyncService');
  const service = module.LibrarySyncService.instance;
  return { context, stores, store, pref, reading, control, auth, service, statuses: module.LibrarySyncStatus,
    model: load('service/sync/LibrarySyncModel'), load };
}

function book(id) { return { id, title: id, author: '', narrator: '', cover: '', contentType: 'audio',
  bookUrl: 'https://books.example/' + id, sourceUrl: 'https://source.example', chapterCount: 20, chapters: [] }; }
function position(id, offset) { return { bookId: id, resourceIndex: 2, domPos: '', charOffset: offset,
  pageOffset: 0, chapterTitle: '第三章', updatedAt: clock }; }
function playback(id, ms) { return { bookId: id, chapterId: id + '-c2', chapterTitle: '第三章',
  chapterIndex: 2, positionMs: ms, durationMs: 100000, updatedAt: clock }; }
async function tick(app) { clock += 16000; await app.service.syncNow(); assert.equal(app.auth.dataOperation, false); }
async function favorite(app, id) { app.control.books.push(book(id)); await app.pref.toggleFavorite(id); }

(async () => {
  const a = launch('phone'), b = launch('tablet');
  await favorite(a, 'novel');
  await favorite(a, 'import_local');
  await a.reading.save(a.context, position('novel', 800));
  await a.pref.saveProgress(playback('novel', 44000));
  await a.service.setEnabled(a.context, true);
  await tick(a);
  assert.equal(a.service.status, a.statuses.PENDING, 'write alone is not upload confirmation');
  await b.service.setEnabled(b.context, true);
  await tick(b);
  assert.notEqual(b.service.status, b.statuses.FAILED, JSON.stringify({ state: b.service.state,
    reading: [...b.store('online_text_reading_progress').values] }));
  assert.deepEqual(json(await b.pref.getFavorites()), ['novel']);
  assert.equal((await b.reading.get(b.context, 'novel')).charOffset, 800);
  assert.equal((await b.pref.getProgress('novel')).positionMs, 44000);
  assert.ok(b.control.books.some(x => x.id === 'novel'), 'book shells allow the receiving shelf to render');
  assert.equal((await b.pref.getChapterProgress('novel', 'novel-c2')).positionMs, 44000);
  await tick(a); await tick(b);
  const versions = a.service.state.revision;
  await tick(a); await tick(b);
  assert.equal(a.service.state.revision, versions, 'received state must not echo as a fresh local edit');

  // The local/remote merge deliberately permits going backwards.
  clock += 16000;
  await b.reading.save(b.context, position('novel', 12));
  await b.pref.saveProgress(playback('novel', 1000));
  await tick(b); await tick(a);
  assert.equal((await a.reading.get(a.context, 'novel')).charOffset, 12);
  assert.equal((await a.pref.getProgress('novel')).positionMs, 1000);

  // Offline deletion survives process death, then beats an unchanged old shelf.
  a.control.online = false;
  await a.pref.removeFavorite('novel');
  await tick(a);
  assert.equal(a.service.status, a.statuses.FAILED);
  const resumed = launch('phone', a);
  await resumed.service.refresh(resumed.context);
  await tick(resumed); await tick(b);
  assert.equal((await b.pref.getFavorites()).includes('novel'), false);
  assert.equal((await b.pref.getProgress('novel')).positionMs, 1000, 'removing shelf leaves progress intact');
  await b.pref.toggleFavorite('novel');
  await tick(b); await tick(resumed);
  assert.equal((await resumed.pref.getFavorites()).includes('novel'), true, 'explicit re-add beats a tombstone');

  // Separate devices can edit different books and grouping without replacing each other.
  await favorite(resumed, 'phone-only'); await favorite(b, 'tablet-only');
  await resumed.pref.setBookGroup(['novel'], '科幻');
  await b.pref.setFavoritesPinned(['novel'], true);
  await tick(resumed); await tick(b); await tick(resumed);
  for (const app of [resumed, b]) {
    assert.ok((await app.pref.getFavorites()).includes('phone-only'));
    assert.ok((await app.pref.getFavorites()).includes('tablet-only'));
    assert.ok((await app.pref.getPinnedFavorites()).includes('novel'));
    assert.equal(app.load('model/BookPresentation').BookPresentation.get('novel').group, '科幻');
  }

  // A visible reader defers inbound progress and a subsequent genuine local save wins.
  resumed.model.LibrarySyncActivity.reading.add('novel');
  clock += 16000; await b.reading.save(b.context, position('novel', 222));
  await tick(b); await tick(resumed);
  assert.equal((await resumed.reading.get(resumed.context, 'novel')).charOffset, 12);
  assert.ok(resumed.service.deferredProgress > 0);
  clock += 16000; await resumed.reading.save(resumed.context, position('novel', 333));
  resumed.model.LibrarySyncActivity.reading.clear();
  await tick(resumed); await tick(b);
  assert.equal((await b.reading.get(b.context, 'novel')).charOffset, 333);

  // Compare-and-set rejects stale inbound writes after the user edits locally during a download.
  const expected = await b.pref.exportLibrarySyncValues();
  await b.pref.removeFavorite('novel');
  const V = b.model.LibrarySyncValue;
  const applied = await b.pref.applyLibrarySyncValues([new V('shelf', 'novel', '1')], expected);
  assert.equal(applied.length, 0);
  assert.equal((await b.pref.getFavorites()).includes('novel'), false);

  const beforeAccount = fs.readdirSync(cloud).length;
  b.auth.openID = 'account-B';
  await tick(b);
  assert.equal(b.service.enabled, false, 'account changes do not enable uploading the prior local library');
  assert.equal(fs.readdirSync(cloud).length, beforeAccount);
  b.auth.openID = 'account-A'; await tick(b);
  assert.equal(b.service.enabled, false, 'returning to an earlier account also requires explicit re-enablement');
  await b.service.setEnabled(b.context, false);
  const stopped = fs.readdirSync(cloud).length;
  await favorite(b, 'disabled-only'); await tick(b);
  assert.equal(fs.readdirSync(cloud).length, stopped, 'disabled sync does not upload');

  const c = launch('pc');
  c.control.api = 20;
  await assert.rejects(c.service.setEnabled(c.context, true));
  assert.equal(c.service.enabled, false);
  c.control.api = 26;
  c.store('library_sync_local_v1').fail = true;
  await assert.rejects(c.service.setEnabled(c.context, true));
  c.store('library_sync_local_v1').fail = false;
  assert.equal([...c.store('library_sync_local_v1').values].some(([k, v]) => k.startsWith('enabled_') && v), false);

  // Invalid/other-account envelopes cannot enter the merge state.
  const encoded = resumed.model.LibrarySyncModel.encode(resumed.service.state);
  assert.throws(() => resumed.model.LibrarySyncModel.parse(encoded, 'different-account'));
  const invalid = JSON.parse(encoded);
  invalid.records[0].changedAt = clock + 2 * 86400000;
  assert.throws(() => resumed.model.LibrarySyncModel.parse(JSON.stringify(invalid), invalid.ownerKey));
  assert.ok(!encoded.includes('import_local'));
  assert.ok(resumed.control.starts < 15, 'active refresh calls are rate limited');

  // Membership is enforced below the UI, including persisted opt-in and background work.
  const member = launch('member');
  member.control.entitled = false; member.control.inactive = true;
  await assert.rejects(member.service.setEnabled(member.context, true), /Membership required/);
  assert.equal(member.service.enabled, false);
  member.control.entitled = true; member.control.inactive = false;
  await member.service.setEnabled(member.context, true);
  const snapshotFiles = () => fs.readdirSync(cloud).sort();
  const beforeDenied = snapshotFiles();
  member.control.entitled = false; // A failed verification keeps opt-in, but allows no IO.
  await tick(member);
  assert.equal(member.service.enabled, true);
  assert.equal(member.service.status, member.statuses.MEMBERSHIP);
  assert.deepEqual(snapshotFiles(), beforeDenied);
  assert.equal(member.control.starts, 0);
  await member.service.background(member.context);
  assert.deepEqual(snapshotFiles(), beforeDenied);
  member.control.inactive = true;
  member.service.suspendForMembership();
  assert.equal(member.service.enabled, false);
  assert.equal(member.store('library_sync_local_v1').getSync(`enabled_${member.service.state.ownerKey}`, true), false);
  const restarted = launch('member', member);
  restarted.control.entitled = false; restarted.control.inactive = true;
  await restarted.service.refresh(restarted.context); await tick(restarted);
  assert.equal(restarted.service.enabled, false);
  assert.deepEqual(snapshotFiles(), beforeDenied);

  // Loss of entitlement while downloading prevents application/publication and releases the lock.
  member.control.entitled = true; member.control.inactive = false;
  await member.service.setEnabled(member.context, true);
  member.control.onRead = () => { member.control.entitled = false; member.control.inactive = true; };
  await tick(member);
  assert.equal(member.service.status, member.statuses.MEMBERSHIP);
  assert.equal(member.service.enabled, false);
  assert.deepEqual(json(await member.pref.getFavorites()), []);
  assert.deepEqual(snapshotFiles(), beforeDenied);
  member.control.onRead = null; member.control.entitled = true; member.control.inactive = false;
  await member.service.setEnabled(member.context, true); await tick(member);
  assert.ok((await member.pref.getFavorites()).length > 0, 'renewed members can re-enable sync');
  member.control.entitled = false; member.control.inactive = false;
  await tick(member);
  member.control.entitled = true; await tick(member);
  assert.notEqual(member.service.status, member.statuses.MEMBERSHIP, 'transient validation failure recovers');
  member.control.entitled = false;
  await member.service.setEnabled(member.context, false);
  assert.equal(member.service.enabled, false, 'turning off never requires membership');
  console.log('PASS membership sync: denied enable, saved opt-in, background gate, expiry persistence, interrupted download, renewal, transient recovery and free opt-out');
  console.log('PASS library sync: real two-device merge, restart/offline deletion, rewind, grouping/pins, active-reader protection, CAS, account isolation, opt-out, API fallback, short IO and validation');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  fs.rmSync(temp, { recursive: true, force: true });
});
