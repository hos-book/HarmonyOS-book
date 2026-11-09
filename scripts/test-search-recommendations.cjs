// DEVECO_HOME=<Release IDE> node scripts/test-search-recommendations.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const serviceCode = compile(fs.readFileSync(path.join(root, 'service/SearchRecommendationService.ets'), 'utf8'));
const requestExports = {};
vm.runInNewContext(compile(fs.readFileSync(path.join(root, 'service/rulesource/light/LightSourceRequestPolicy.ts'), 'utf8')),
  { exports: requestExports, setTimeout, clearTimeout });
const { LightSourceRequest } = requestExports;
const book = (id, sourceUrl = 'source') => ({ name: 'Book ' + id, bookUrl: String(id), sourceUrl, contentType: 'text' });
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const tick = async () => { for (let index = 0; index < 30; index++) await Promise.resolve(); };
function harness(count = 6, home = []) {
  let revision = 0, login = 0, now = 1000000, queries = 0;
  class LocalRuleSource {
    constructor(id) { this.id = id; }
    isSearchEnabled() { return true; }
    isAudio() { return false; }
    isComic() { return false; }
  }
  const sources = Array.from({ length: count }, (_, id) => new LocalRuleSource(id));
  const started = [], pending = [], published = [], lookups = [];
  const repository = {
    getCoverRevision: () => login,
    getRecommendationSourceUrls: async limit => {
      queries++; assert.equal(limit, 6); return sources.slice(0, limit).map(value => value.id);
    }
  };
  const modules = {
    '../model/LocalRuleSource': { LocalRuleSource },
    './BookSourceService': { BookSourceService: { searchBooks: (source, _keyword, page, request) => {
      assert.equal(page, 1); assert.equal(request.priority, 0);
      started.push(source.id); const task = deferred(); pending.push(task); return task.promise;
    } } },
    './SourceDataService': { SourceDataService: {
      getInvalidationCounter: () => revision,
      getSourceByUrl: async id => { lookups.push(id); return sources[id]; },
      getEnabledSources: () => { throw new Error('full source read is forbidden'); }
    } },
    './rulesource/HomeSourceService': { HomeSourceService: {
      getCachedRecommendations: () => home,
      loadHome: () => { throw new Error('full home load is forbidden'); }
    } },
    './rulesource/LocalRuleSourceRepository': { LocalRuleSourceRepository: repository }
  };
  const exports = {};
  vm.runInNewContext(serviceCode, { exports, require: id => {
    assert.ok(modules[id], 'unexpected dependency ' + id); return modules[id];
  }, Date: { now: () => now }, setTimeout: callback => { Promise.resolve().then(callback); return 1; } });
  return { service: exports.SearchRecommendationService, started, pending, published, lookups, repository,
    run(request = new LightSourceRequest(0)) { return this.service.load(request, values => published.push(Array.from(values))); },
    queries: () => queries, changeSource: () => { revision++; }, changeLogin: () => { login++; },
    expire: () => { now += 301000; }
  };
}
async function progressAndCache() {
  const h = harness(); const work = h.run(); await tick();
  assert.deepEqual(h.started, [0], 'only one optional request runs at once');
  h.pending[0].resolve([book(1), book(1)]); await tick();
  assert.deepEqual(h.published.at(-1).map(value => value.bookUrl), ['1']);
  assert.deepEqual(h.started, [0, 1]);
  h.pending[1].reject(new Error('offline')); await tick();
  assert.deepEqual(h.started, [0, 1, 2], 'one source failure does not stop remaining candidates');
  h.pending[2].resolve(Array.from({ length: 5000 }, (_, index) => book(index + 2))); await work;
  assert.deepEqual(h.published.at(-1).map(value => value.bookUrl), ['1', '2', '3', '4', '5']);
  assert.equal(h.lookups.length, 3, 'unneeded definitions are never read');
  await h.run(); assert.equal(h.queries(), 1, 'second entry uses memory, without database or rules');
  h.changeSource(); const changed = h.run(); await tick();
  assert.equal(h.queries(), 2, 'source edits invalidate recommendation cache');
  h.pending[3].resolve([book(11), book(12), book(13), book(14), book(15)]); await changed;
  h.changeLogin(); const login = h.run(); await tick();
  h.pending[4].resolve([book(21), book(22), book(23), book(24), book(25)]); await login;
  assert.equal(h.queries(), 3, 'login changes invalidate recommendation cache');
  h.expire(); const expired = h.run(); await tick();
  h.pending[5].resolve([book(31), book(32), book(33), book(34), book(35)]); await expired;
  assert.equal(h.queries(), 4, 'cache expires after five minutes');
}
async function cachedHomeAndCancellation() {
  const cached = harness(6, Array.from({ length: 5 }, (_, index) => book(index)));
  await cached.run(); assert.equal(cached.queries(), 0); assert.equal(cached.started.length, 0);
  const h = harness(); const request = new LightSourceRequest(0);
  const work = h.run(request); await tick(); request.cancel();
  h.pending[0].resolve([book(1)]); await work;
  assert.equal(h.published.length, 0, 'late results cannot publish after input or back');
  assert.equal(h.started.length, 1, 'cancellation prevents queued sources');
  const next = h.run(); await tick();
  h.pending[1].resolve(Array.from({ length: 5 }, (_, index) => book(index))); await next;
  assert.equal(h.published.at(-1).length, 5, 're-entering after cancellation can load again');
  const changed = harness(); const old = changed.run(); await tick(); changed.changeSource();
  changed.pending[0].resolve([book(1)]); await old;
  assert.equal(changed.published.length, 0, 'source changes reject in-flight results');
  const empty = harness(0); await empty.run(); assert.equal(empty.published.at(-1).length, 0);
  const failed = harness(); failed.repository.getRecommendationSourceUrls = async () => { throw new Error('db offline'); };
  await failed.run(); assert.equal(failed.published.length, 0);
}
async function repositoryQuery() {
  const source = fs.readFileSync(path.join(root, 'service/rulesource/LocalRuleSourceRepository.ets'), 'utf8');
  const start = source.indexOf('  static async getRecommendationSourceUrls(');
  const end = source.indexOf('  static async getAll(', start);
  let query, args, closed = 0, row = 0;
  const store = { querySql: async (sql, values) => { query = sql; args = values; return {
    goToNextRow: () => row++ < 2, getString: () => 'url' + row, close: () => { closed++; }
  }; } };
  const exports = {};
  vm.runInNewContext(compile('export class LocalRuleSourceRepository { static async ensureStore() { return store; } ' +
    source.slice(start, end) + '}'), { exports, store, TABLE_NAME: 'rule_sources', LocalRuleSourceStatus: { READY: 1 } });
  const urls = await exports.LocalRuleSourceRepository.getRecommendationSourceUrls(5000);
  assert.equal(urls.length, 2); assert.equal(closed, 1); assert.equal(args[1], 6);
  assert.match(query, /SELECT source_url FROM/); assert.doesNotMatch(query, /source_json/);
  assert.match(query, /enabled = 1/); assert.ok(query.includes("NOT LIKE 'builtin://%'"));
}
(async () => {
  await progressAndCache(); await cachedHomeAndCancellation(); await repositoryQuery();
  console.log('PASS: bounded source reads, five books, one request at a time, cache reuse/expiry/invalidation, failure, cancellation, resume and empty sources');
})().catch(error => { console.error(error); process.exitCode = 1; });
