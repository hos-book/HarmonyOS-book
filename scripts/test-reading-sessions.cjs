// Run with DEVECO_HOME pointing at the Release IDE. Uses the real ArkTS services.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
let yields = 0;
let onYield = () => {};
const root = path.join(__dirname, '../entry/src/main/ets');
function load(file, dependencies = {}) {
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(path.join(root, file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, Date, Map, Set, Promise,
    setTimeout: (fn, delay) => { yields++; return setTimeout(() => { onYield(); fn(); }, delay); },
    Error, ArrayBuffer, Uint8Array, DataView, require: name => dependencies[name] || {} });
  return module.exports;
}
const memory = new Map();
let reads = 0, flushes = 0, syncReads = 0;
const store = { put: async (k, v) => memory.set(k, v), getSync: (k, v) => { syncReads++; return memory.get(k) ?? v; },
  getAll: async () => { reads++; return Object.fromEntries(memory); }, delete: async k => memory.delete(k), flush: async () => { flushes++; } };
function sessions() {
  return load('service/ReadingSessionService.ets', {
    '../model/ReadingSession': load('model/ReadingSession.ets'),
    '../model/GeneralSettings': { GeneralSettings: { current: { historyEnabled: true } } },
    '@kit.ArkTS': { util: { generateRandomUUID: () => require('node:crypto').randomUUID() } },
    '@kit.BasicServicesKit': { emitter: { emit() {} } },
    '@kit.ArkData': { preferences: { getPreferences: async () => store } },
    './DiagnosticLogService': { DiagnosticLogService: { info() {} } }
  });
}
(async () => {
  const { ReadingSessionService: service, SessionLocation } = sessions();
  service.init({});
  const book = { id: 'book', chapters: [
    { id: 'a', title: '第一章', source: { value: 'a' } },
    { id: 'b', title: '第二章', source: { value: 'b' } }
  ] };
  const position = (chapter, ms) => SessionLocation.audio(book, book.chapters[chapter], ms, 60000);
  service.checkpoint('audio', position(0, 12000), true);
  service.checkpoint('audio', position(0, 42000), true);
  service.checkpoint('audio', position(1, 0), true);
  service.checkpoint('audio', position(1, 18000), false);
  let rows = await service.list(['book']);
  assert.equal(rows.length, 2);
  const first = rows.find(row => row.start.chapterId === 'a');
  const second = rows.find(row => row.start.chapterId === 'b');
  assert.equal(first.start.position, 12000);
  assert.equal(first.end.position, 42000);
  assert.equal(second.end.position, 18000);
  assert.equal(first.sessionId, second.sessionId);
  service.checkpoint('audio', position(1, 18000), true);
  service.checkpoint('audio', position(1, 28000), false);
  rows = await service.list(['book']);
  assert.equal(rows.length, 3);
  assert.equal(new Set(rows.map(row => row.sessionId)).size, 2);
  service.checkpoint('audio', position(1, 29000), false);
  assert.equal((await service.list(['book'])).length, 3, 'idle persistence must not create a session');
  const restarted = sessions().ReadingSessionService;
  restarted.init({});
  assert.equal((await restarted.list(['book'])).length, 3, 'cold start restores committed sessions');
  memory.set('corrupt', '{broken');
  assert.equal((await restarted.list(['book'])).length, 3);
  assert.equal((await restarted.list(['different-book'])).length, 0);
  console.log('PASS session start/end, cross-chapter grouping, pause/resume, restart, corrupt record isolation');

  service.checkpoint('audio', position(1, 30000), true);
  await service.chain;
  service.checkpoint('audio', position(1, 45000), true);
  const beforeFlushes = flushes, beforeReads = reads, beforeSyncReads = syncReads;
  const activeRows = await service.list(['book']);
  const active = activeRows.find(row => row.end.position === 45000);
  assert.ok(active, 'current playback is visible without a forced save');
  assert.equal(flushes, beforeFlushes, 'opening history does not flush storage');
  assert.equal(reads - beforeReads, 1, 'one snapshot read per list');
  assert.equal(syncReads, beforeSyncReads, 'no per-record synchronous reads');
  service.checkpoint('audio', position(1, 48000), true);
  assert.equal(active.end.position, 45000, 'returned records are immutable snapshots of active playback');
  service.end('audio'); await service.chain;

  const seed = JSON.parse(JSON.stringify(active));
  memory.clear();
  for (let i = 0; i < 2000; i++) {
    memory.set(`session-${i}`, JSON.stringify({ ...seed, id: `session-${i}`, startedAt: i,
      end: { ...seed.end, bookId: i % 2 === 0 ? 'book' : 'other' } }));
  }
  const beforeYields = yields;
  const large = await service.list(['book']);
  assert.equal(large.length, 1000);
  assert.equal(large[0].startedAt, 1998);
  assert.equal(large.at(-1).startedAt, 0);
  assert.ok(yields - beforeYields >= Math.ceil(2000 / 32), 'large histories yield between bounded batches');
  let activePage = true;
  onYield = () => { activePage = false; };
  const cancelled = await service.list(['book'], () => activePage);
  assert.equal(cancelled.length, 0, 'navigation cancellation stops parsing');
  onYield = () => {};
  const emptyReads = reads;
  assert.equal((await service.list([])).length, 0);
  assert.equal(reads, emptyReads, 'empty filter does not scan storage');
  console.log('PASS history read-only snapshot, current playback, 2000-record batching, filtering and cancellation');

  const { SpeechPcmBuffer } = load('service/text/SpeechPcmBuffer.ets');
  const pcm = new SpeechPcmBuffer();
  const format = { audioType: 'pcm', sampleRate: 16000, sampleBit: 16, audioChannel: 1 };
  pcm.configure(format);
  pcm.append(new Uint8Array([3, 4]).buffer, { sequence: 1, audioType: 'pcm' });
  pcm.append(new Uint8Array([1, 2]).buffer, { sequence: 0, audioType: 'pcm' });
  pcm.append(new Uint8Array([9, 9]).buffer, { sequence: 0, audioType: 'pcm' });
  const wave = pcm.toWave();
  assert.deepEqual([...new Uint8Array(wave).slice(44)], [1, 2, 3, 4]);
  assert.equal(new DataView(wave).getUint32(24, true), 16000);
  assert.equal(new DataView(wave).getUint32(40, true), 4);
  pcm.reset(); pcm.configure(format);
  pcm.append(new ArrayBuffer(2), { sequence: 1, audioType: 'pcm' });
  assert.throws(() => pcm.toWave(), /Missing/);
  assert.throws(() => pcm.configure({ ...format, sampleBit: 8 }), /Unsupported/);
  assert.throws(() => pcm.append(new ArrayBuffer(8 * 1024 * 1024), { sequence: 2, audioType: 'pcm' }), /budget/);
  console.log('PASS PCM packet ordering, duplicate suppression, WAV format, missing packets and memory budget');
})().catch(error => { console.error(error); process.exitCode = 1; });
