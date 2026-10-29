// Real services with controlled I/O latency; host timings are not device frame/startup timings.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { performance } = require('node:perf_hooks');
const ide = process.env.DEVECO_HOME;
if (!ide) throw Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '..');
const traceEvents = [];
let traceEnabled = true;
const kit = { hiTraceMeter: {
  HiTraceOutputLevel: { INFO: 1 }, isTraceEnabled: () => traceEnabled,
  startAsyncTrace: (_level, name, id) => traceEvents.push(['begin', name, id]),
  finishAsyncTrace: (_level, name, id) => traceEvents.push(['end', name, id])
} };
function load(base, relative, imports) {
  const filename = path.join(base, 'entry/src/main/ets', relative);
  const exports = {};
  const source = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(source, { exports, require(name) {
    if (name in imports) return imports[name];
    throw Error(`Unmocked import: ${name}`);
  }, setTimeout: () => 1, DataOperationType: { ADD: 'add', DELETE: 'delete', RELOAD: 'reload' } }, { filename });
  return exports;
}
const trace = load(root, 'utils/PerformanceTrace.ts', { '@kit.PerformanceAnalysisKit': kit });
const imports = { '../../utils/PerformanceTrace': trace, './OnlineTextPaginator': {} };
function scroll(base) { return load(base, 'service/text/OnlineTextScrollDataSource.ets', imports).OnlineTextScrollDataSource; }
function rows(chapter, count) {
  return Array.from({ length: count }, (_, index) => ({ key: `${chapter}:${index}`, chapterIndex: chapter,
    startOffset: index * 20, endOffset: (index + 1) * 20, heading: false }));
}
function values(source) { return Array.from({ length: source.totalCount() }, (_, index) => source.getData(index)); }
function median(samples) { return samples.sort((a, b) => a - b)[Math.floor(samples.length / 2)]; }

function verifyScroll() {
  const Source = scroll(root);
  const source = new Source();
  const rendered = [];
  let notifications = 0;
  const listener = { onDatasetChange(operations) {
    notifications++;
    for (const op of operations) {
      if (op.type === 'reload') rendered.splice(0, rendered.length, ...values(source));
      if (op.type === 'add') rendered.splice(op.index, 0, ...Array.from({ length: op.count }, (_, i) => source.getData(op.index + i)));
      if (op.type === 'delete') rendered.splice(op.index, op.count);
    }
    assert.deepEqual(rendered, values(source), 'renderer sees the complete data for every batch');
  }, onDataReloaded() { throw Error('Do not mix notification APIs'); },
  onDataAdd() { throw Error('Do not mix notification APIs'); }, onDataDelete() { throw Error('Do not mix notification APIs'); } };
  source.registerDataChangeListener(listener);
  source.registerDataChangeListener(listener);
  const middle = rows(2, 3);
  source.reset(middle);
  source.insert(0, rows(1, 2));
  source.insert(source.totalCount(), rows(3, 2));
  source.insert(3, rows(4, 1));
  assert.equal(source.findPosition(2, 21), 4);
  source.remove(3, 1);
  assert.equal(source.getData(3), middle[1], 'retained row identity survives insertion and deletion');
  source.remove(0, 2);
  source.remove(3, 999);
  assert.deepEqual(values(source), middle);
  const before = notifications;
  source.insert(0, []); source.remove(0, 0); source.remove(99, 2);
  assert.equal(notifications, before, 'empty updates do not notify');
  source.reset([]);
  source.unregisterDataChangeListener(listener);
  source.insert(0, middle);
  assert.equal(notifications, before + 1, 'unregistered listeners stop receiving updates');
  const failing = new Source();
  failing.registerDataChangeListener({ onDatasetChange() { throw Error('renderer failure'); } });
  assert.throws(() => failing.insert(0, middle), /renderer failure/);
  console.log('PASS batched scroll notifications, order, row identity, anchors and listener lifecycle');
}

function benchmarkScroll(base) {
  const Source = scroll(base);
  const existing = rows(2, 6000), added = rows(1, 2000);
  const times = [];
  let notifications = 0;
  for (let iteration = 0; iteration < 23; iteration++) {
    const source = new Source();
    source.reset(existing);
    const count = () => { notifications++; };
    source.registerDataChangeListener({ onDatasetChange: count, onDataAdd: count, onDataDelete: count });
    const start = performance.now();
    source.insert(0, added);
    source.remove(0, added.length);
    if (iteration >= 3) times.push(performance.now() - start);
    assert.equal(source.totalCount(), existing.length);
    assert.equal(source.getData(0), existing[0]);
  }
  return { existingRows: 6000, insertedRows: 2000, samples: times.length,
    medianMs: Number(median(times).toFixed(3)), notificationsPerInsertAndRemove: notifications / 23 };
}

async function benchmarkCache(base, verify) {
  const count = 256;
  const names = Array.from({ length: count }, (_, i) => `search_text_${i.toString(36)}.json`);
  let active = 0, maximum = 0, calls = 0;
  const context = { filesDir: '/sandbox/files', cacheDir: '/sandbox/cache' };
  const fileIo = {
    async listFile(dir) { return dir.endsWith('online_text_content') ? names.concat('unrelated.json') : []; },
    async stat(file) {
      calls++; active++; maximum = Math.max(maximum, active);
      try {
        await new Promise(resolve => setTimeout(resolve, 2));
        if (verify && file.endsWith('search_text_3.json')) throw Error('concurrent deletion');
        return { size: 64, mtime: 0, isFile: () => !verify || !file.endsWith('search_text_4.json') };
      } finally { active--; }
    }, utimes() {}
  };
  const { ReaderCacheService: cache } = load(base, 'service/ReaderCacheService.ts', {
    '../utils/PerformanceTrace': trace, '@kit.CoreFileKit': { fileIo },
    '@kit.BasicServicesKit': { emitter: { emit() {} } }
  });
  const start = performance.now();
  const ready = cache.initialize(context);
  // A cache-hit record must remain ordered behind initialization and survive its index publication.
  const queued = verify ? cache.record([context.filesDir + '/online_text_content/search_text_queued.json']) : Promise.resolve();
  await Promise.all([ready, queued]);
  assert.equal(active, 0, 'all in-flight operations are settled');
  assert.equal(cache.textBytes, (verify ? count - 1 : count) * 64);
  assert.equal(cache.entries.size, verify ? count - 1 : count);
  if (verify) {
    assert.ok(maximum > 1 && maximum <= 4, 'scan concurrency is bounded by four');
    assert.equal(calls, count + 1, 'unrelated paths are never probed');
    assert.ok(cache.entries.has(context.filesDir + '/online_text_content/search_text_queued.json'));
  }
  return { files: count, simulatedStatDelayMs: 2, elapsedMs: Number((performance.now() - start).toFixed(2)),
    maximumConcurrentStats: maximum };
}

(async () => {
  verifyScroll();
  await benchmarkCache(root, true);
  console.log('PASS bounded cache scanning, concurrent deletion, non-files and queued record ordering');
  const live = new Map();
  for (const [kind, name, id] of traceEvents) {
    const key = `${name}:${id}`;
    if (kind === 'begin') { assert.ok(!live.has(key)); live.set(key, true); }
    else { assert.ok(live.delete(key), 'finish must match a started trace'); }
  }
  assert.equal(live.size, 0, 'including error paths, every trace finishes');
  traceEnabled = false;
  const eventsBefore = traceEvents.length;
  assert.equal(trace.PerformanceTrace.begin('disabled'), -1);
  trace.PerformanceTrace.end('disabled', -1);
  assert.equal(traceEvents.length, eventsBefore);
  console.log('PASS paired traces and zero events while capture is disabled');
  const baseline = process.argv[2];
  if (baseline) {
    const results = { environment: 'host Node; simulated I/O, not real-device startup/FPS',
      baseline: { scroll: benchmarkScroll(path.resolve(baseline)), cache: await benchmarkCache(path.resolve(baseline), false) },
      optimized: { scroll: benchmarkScroll(root), cache: await benchmarkCache(root, false) } };
    console.log(JSON.stringify(results, null, 2));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
