// DEVECO_HOME=<Release IDE> node scripts/test-search-recommendations.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/SearchPage.ets'), 'utf8');
const start = source.indexOf('  private async loadRecommendations(');
const end = source.indexOf('  private async doSearch(', start);
assert.ok(start >= 0 && end > start);
const constants = source.slice(source.indexOf('const SEARCH_RECOMMENDATION_COUNT:'), source.indexOf('@ComponentV2'));
const code = ts.transpileModule(`${constants}
export class RecommendationQueue {
  recommendationGen = 0;
  recommendationBooks = [];
  recommendationsLoading = false;
  recommendationsStarted = false;
  recommendationsLoaded = false;
  prefetched = [];
  prefetchCovers(books) { this.prefetched.push(...books); }
  searchResultToBook(book) { return book; }
  ${source.slice(start, end)}
}`, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
async function tick() { for (let index = 0; index < 20; index++) await Promise.resolve(); }
function book(id) { return { title: `Book ${id}`, sourceUrl: 'source', bookUrl: String(id) }; }
function harness(count = 6, home = false) {
  class LocalRuleSource {
    constructor(id) { this.id = id; this.validationStatus = 'READY'; this.bookSourceType = 0; }
  }
  const sources = Array.from({ length: count }, (_, index) => new LocalRuleSource(index));
  const pending = new Map();
  const started = [];
  const discovery = deferred();
  let update;
  const exports = {};
  vm.runInNewContext(code, {
    exports, Set, LocalRuleSource, LocalRuleSourceStatus: { READY: 'READY' }, LightSourceRequest: class {},
    hilog: { warn() {} }, DOMAIN: 0, TAG: 'RecommendationsTest',
    SourceDataService: { getEnabledSources: async () => sources },
    HomeSourceService: {
      isEligible: () => home,
      loadHome: (_source, _refresh, onUpdate) => { update = onUpdate; return discovery.promise; }
    },
    BookSourceService: { searchBooks: (source, _keyword, page, request) => {
      const task = deferred();
      task.request = request;
      assert.equal(page, 1);
      started.push(source.id);
      pending.set(source.id, task);
      return task.promise;
    } }
  });
  const queue = new exports.RecommendationQueue();
  queue.shuffleSources = values => values;
  return { queue, pending, started, discovery, update: books => update({ blocks: [{ books }] }) };
}

async function searchProgress() {
  const h = harness();
  const work = h.queue.loadRecommendations();
  await tick();
  assert.deepEqual(h.started, [0, 1, 2]);
  h.pending.get(1).resolve([book(1), book(1)]);
  await tick();
  assert.deepEqual(Array.from(h.queue.recommendationBooks, value => value.bookUrl), ['1'],
    'fast source is visible before slow source completes; duplicates appear once');
  assert.deepEqual(h.started, [0, 1, 2, 3], 'free slot refills without waiting for the slow source');
  h.pending.get(2).reject(new Error('offline'));
  await tick();
  assert.deepEqual(h.started, [0, 1, 2, 3, 4], 'failure frees a slot');
  h.pending.get(3).resolve([book(2), book(3), book(4), book(5), book(6)]);
  await tick();
  assert.deepEqual(Array.from(h.queue.recommendationBooks, value => value.bookUrl), ['1', '2', '3', '4', '5'],
    'append order is stable and results stop at five');
  assert.equal(h.queue.recommendationsLoading, false);
  h.pending.get(0).resolve([book(7)]);
  h.pending.get(4).resolve([book(8)]);
  await work;
  assert.equal(h.started.includes(5), false, 'full list stops queued requests');
  assert.equal(h.queue.prefetched.length, 5, 'only new covers are prefetched');
}

async function discoveryProgress() {
  const h = harness(1, true);
  const work = h.queue.loadRecommendations();
  await tick();
  h.update([book(1)]);
  assert.equal(h.queue.recommendationBooks.length, 1, 'first discovery block appears before loadHome completes');
  h.update([book(1), book(2)]);
  assert.equal(h.queue.recommendationBooks.length, 2, 'repeated discovery snapshots append without duplicates');
  h.discovery.reject(new Error('later discovery block failed'));
  await tick();
  h.pending.get(0).reject(new Error('search also failed'));
  await work;
  assert.equal(h.queue.recommendationBooks.length, 2, 'later failures preserve already displayed books');
}

async function cancellationAndResume() {
  const h = harness(1, true);
  const work = h.queue.loadRecommendations();
  await tick();
  h.update([book(1)]);
  h.queue.recommendationGen++;
  h.update([book(2)]);
  h.discovery.resolve({ blocks: [{ books: [book(3)] }] });
  await work;
  assert.deepEqual(Array.from(h.queue.recommendationBooks, value => value.bookUrl), ['1'],
    'late discovery callbacks cannot update a cancelled generation');
  assert.equal(h.started.length, 0, 'cancelled discovery cannot start fallback search');

  const search = harness();
  search.queue.recommendationBooks = [book(9)];
  const searchWork = search.queue.loadRecommendations();
  await tick();
  search.pending.get(1).resolve([book(9), book(1)]);
  await tick();
  assert.deepEqual(Array.from(search.queue.recommendationBooks, value => value.bookUrl), ['9', '1'],
    'resuming preserves existing books and deduplicates arriving results');
  search.queue.recommendationGen++;
  for (const task of search.pending.values()) {
    assert.equal(task.request.cancelCheck(), true, 'submitting a keyword cancels in-flight recommendation requests');
  }
  for (const task of search.pending.values()) task.resolve([book(2)]);
  await searchWork;
  assert.equal(search.queue.recommendationBooks.length, 2, 'late search results are discarded');
  assert.equal(search.started.length, 4, 'cancelled generation stops scheduling sources');

  const empty = harness(0);
  await empty.queue.loadRecommendations();
  assert.equal(empty.queue.recommendationsLoading, false);
  assert.equal(empty.queue.recommendationBooks.length, 0);
}

(async () => {
  await searchProgress();
  await discoveryProgress();
  await cancellationAndResume();
  console.log('PASS: progressive discovery/search, rolling concurrency, stable order, deduplication, five-book limit, partial failure, cancellation, resume and empty sources');
})().catch(error => { console.error(error); process.exitCode = 1; });
