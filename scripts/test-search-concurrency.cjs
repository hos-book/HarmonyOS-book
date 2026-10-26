// DEVECO_HOME=<Release IDE> node scripts/test-search-concurrency.cjs
const vm = require('node:vm');
const { assert, fs, path, fixtures, snapshot, harness } = require('./backup-test-harness.cjs');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));

async function tick() {
  for (let i = 0; i < 12; i++) await Promise.resolve();
}

function searchHarness() {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/SearchPage.ets'), 'utf8');
  const start = source.indexOf('  private async searchSources(');
  const end = source.indexOf('  private prefetchCovers(', start);
  assert.ok(start >= 0 && end > start, 'load the real search queue and source failure handler');
  const code = ts.transpileModule(`export class SearchQueue {
    searchGen = 1;
    searching = true;
    sourcePages = new Map();
    searchedSourceCount = 0;
    ${source.slice(start, end)}
  }`, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
  const exports = {};
  const pending = new Map();
  const started = [];
  let active = 0;
  let peak = 0;
  vm.runInNewContext(code, {
    exports, Set,
    LightSourceRequest: class {},
    hilog: { warn() {} }, DOMAIN: 0, TAG: 'SearchTest',
    BookSourceService: { searchBooks: bookSource => {
      started.push(bookSource.id);
      active++;
      peak = Math.max(peak, active);
      return new Promise((resolve, reject) => pending.set(bookSource.id, { resolve, reject }))
        .finally(() => { active--; pending.delete(bookSource.id); });
    } }
  });
  return { queue: new exports.SearchQueue(), pending, started, peak: () => peak };
}

async function preferencesTest() {
  const h = harness();
  const { PreferenceService: prefs } = h.load('service/PreferenceService');
  await prefs.init(h.context);
  assert.equal(await prefs.getSearchConcurrency(), 3);
  for (const count of [1, 3, 6, 9, 12, 7]) {
    await prefs.setSearchConcurrency(count);
    await prefs.invalidateCache(h.context);
    await prefs.init(h.context);
    assert.equal(await prefs.getSearchConcurrency(), count, 'saved value survives a preferences reload');
  }
  for (const count of [0, 13, 1.5, NaN, Infinity]) {
    await assert.rejects(prefs.setSearchConcurrency(count));
    assert.equal(await prefs.getSearchConcurrency(), 7);
  }
  const values = h.stored('listenbook_prefs');
  for (const value of [0, 13, 2.5, '12', NaN]) {
    values.set('search_concurrency', value);
    assert.equal(await prefs.getSearchConcurrency(), 3, 'corrupt stored values use the default');
  }
  await prefs.setSearchConcurrency(12);
  const exported = await prefs.exportBackupSnapshot();
  assert.equal(exported.searchConcurrency, 12);
  await prefs.setSearchConcurrency(3);
  await prefs.restoreBackupSnapshot(exported);
  assert.equal(await prefs.getSearchConcurrency(), 12);
  delete exported.searchConcurrency;
  await prefs.restoreBackupSnapshot(exported);
  assert.equal(await prefs.getSearchConcurrency(), 3, 'legacy backups restore the default');
  const store = prefs.store;
  const flush = store.flush;
  store.flush = async () => { throw new Error('disk full'); };
  await assert.rejects(prefs.setSearchConcurrency(12), /disk full/);
  store.flush = flush;
  assert.equal(await prefs.getSearchConcurrency(), 3, 'failed save restores the old in-memory value');

  await prefs.setSearchConcurrency(12);
  h.control.member = false;
  assert.equal(await prefs.getSearchConcurrency(), 3, 'expired member uses default');
  assert.equal(values.get('search_concurrency'), 3, 'old custom value is reset durably');
  await assert.rejects(prefs.setSearchConcurrency(9), /MEMBERSHIP_REQUIRED/);
  exported.searchConcurrency = 12;
  await prefs.restoreBackupSnapshot(exported);
  assert.equal(values.get('search_concurrency'), 3, 'backup restore cannot bypass membership');
  h.control.member = true;
  assert.equal(await prefs.getSearchConcurrency(), 3, 'rejoining does not resurrect old custom value');

  const { AppBackupService: backup } = h.load('service/AppBackupService');
  const data = snapshot();
  assert.equal(backup.validSnapshot(data), true, 'legacy backup remains valid');
  for (const value of [0, 13, 1.5, '12', null]) {
    data.preferences.searchConcurrency = value;
    assert.equal(backup.validSnapshot(data), false, 'invalid backup setting is rejected');
  }
  data.preferences.searchConcurrency = 12;
  assert.equal(backup.validSnapshot(data), true);
}

async function queueTest() {
  for (const limit of [1, 3, 6, 12]) {
    const h = searchHarness();
    const sources = Array.from({ length: 25 }, (_, id) => ({ id }));
    const work = h.queue.searchSources(sources, 'book', 1, new Set(), limit);
    assert.equal(h.started.length, limit);
    while (h.pending.size) {
      // Keep the first source slow while later sources complete and refill positions.
      const id = [...h.pending.keys()].at(-1);
      h.pending.get(id).resolve([]);
      await tick();
    }
    await work;
    assert.equal(h.started.length, sources.length);
    assert.equal(h.queue.searchedSourceCount, sources.length, 'empty results still complete source progress');
    assert.equal(new Set(h.started).size, sources.length, 'each source starts once');
    assert.equal(h.peak(), limit, 'never exceeds configured concurrency');
  }
  const rolling = searchHarness();
  const work = rolling.queue.searchSources([0, 1, 2, 3].map(id => ({ id })), 'book', 1, new Set(), 2);
  rolling.pending.get(1).reject(new Error('source unavailable'));
  await tick();
  assert.deepEqual(rolling.started, [0, 1, 2], 'failure frees a position while a slow source remains');
  assert.equal(rolling.queue.searchedSourceCount, 1, 'failed source counts as completed');
  rolling.pending.get(2).resolve([]);
  await tick();
  assert.deepEqual(rolling.started, [0, 1, 2, 3], 'completion refills without a batch barrier');
  rolling.pending.get(0).resolve([]);
  rolling.pending.get(3).resolve([]);
  await work;

  assert.equal(rolling.queue.searchedSourceCount, 4, 'each finished source increments progress once');

  const cancelled = searchHarness();
  const cancelledWork = cancelled.queue.searchSources([0, 1, 2, 3].map(id => ({ id })), 'old', 1, new Set(), 2);
  cancelled.queue.searchGen++;
  for (const item of cancelled.pending.values()) item.resolve([]);
  await cancelledWork;
  assert.equal(cancelled.queue.searchedSourceCount, 0, 'stale source callbacks cannot change current progress');
  assert.deepEqual(cancelled.started, [0, 1], 'old search stops scheduling queued sources');
  await cancelled.queue.searchSources([], 'empty', 2, new Set(), 12);
  assert.equal(cancelled.started.length, 2, 'empty source list makes no requests');
}

(async () => {
  await preferencesTest();
  await queueTest();
  console.log('PASS: search concurrency persistence, legacy backup, invalid values, save rollback, rolling refill, limits 1/6/12, source failure, cancellation and empty sources');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  for (const dir of fixtures) fs.rmSync(dir, { recursive: true, force: true });
});
