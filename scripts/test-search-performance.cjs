// Execute the real search aggregation/cover scheduler and data source without ArkUI rendering.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const pageSource = fs.readFileSync(path.join(root, 'pages/SearchPage.ets'), 'utf8');
const start = pageSource.indexOf('  private resetPagination(');
const end = pageSource.indexOf('  private searchResultToBook(', start);
const taskStart = pageSource.indexOf('class SearchCoverTask {');
const taskEnd = pageSource.indexOf('@ComponentV2', taskStart);
assert.ok(start > 0 && end > start && taskStart > 0 && taskEnd > taskStart);
function compile(source) {
  return ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
}
const dataExports = {};
vm.runInNewContext(compile(fs.readFileSync(path.join(root, 'utils/BookDataSource.ets'), 'utf8')),
  { exports: dataExports });
const { BookDataSource } = dataExports;
class LightSourceRequest {
  constructor(priority = 1) { this.priority = priority; }
}
const tick = async () => { for (let index = 0; index < 12; index++) await Promise.resolve(); };
const book = (id, contentType = 'text', title = id) => ({ id, contentType, title, author: '',
  cover: '', bookUrl: id, sourceUrl: 'source', variables: {} });
function harness() {
  const timers = new Map();
  const pending = [];
  const calls = [];
  let timerId = 0;
  let active = 0;
  let peak = 0;
  const exports = {};
  vm.runInNewContext(compile(`${pageSource.slice(taskStart, taskEnd)}
    export class Page { ${pageSource.slice(start, end)} }`), {
    exports, LightSourceRequest,
    LOCAL_RULE_COVER_CONCURRENCY: 3, LOCAL_RULE_COVER_LIMIT: 12, LOCAL_RULE_COVER_PENDING_LIMIT: 96,
    DOMAIN: 0, TAG: 'test', hilog: { warn() {} },
    setTimeout: callback => { const id = ++timerId; timers.set(id, callback); return id; },
    clearTimeout: id => timers.delete(id),
    BookCoverPolicy: { setDetail: (value, cover) => { value.cover = cover; value.coverFromDetail = true; } },
    SearchCache: { put() {} }, CoverPrefetcher: { prefetchMany() {} },
    BookSourceService: { getBookInfo: (source, url, variables, request) => {
      active++; peak = Math.max(peak, active);
      calls.push({ source, url, request });
      return new Promise((resolve, reject) => pending.push({ resolve, reject, request }))
        .finally(() => { active--; });
    } }
  });
  const page = new exports.Page();
  Object.assign(page, { searchGen: 1, leavingPage: false, searchTab: 0,
    coverHydrationActive: 0, resultsRefreshTimer: -1, audioBooks: [], textBooks: [], comicBooks: [],
    resultDataSource: new BookDataSource() });
  page.resetPagination();
  return { page, pending, calls, timers, peak: () => peak,
    flush: () => { const batch = [...timers.values()]; timers.clear(); batch.forEach(callback => callback()); } };
}
function observe(source) {
  const events = [];
  source.registerDataChangeListener({ onDataReloaded: () => events.push(['reload']),
    onDataAdd: index => events.push(['add', index]), onDataChange: index => events.push(['change', index]) });
  return events;
}
function aggregationTest() {
  const h = harness();
  const events = observe(h.page.resultDataSource);
  const text = book('t', 'text', 'Shared');
  h.page.appendSearchBook(text);
  h.page.refreshVisibleBooks();
  const textKey = h.page.resultDataSource.getVersionedKey(text);
  assert.deepEqual(events, [['add', 0]]);
  events.length = 0;
  h.page.appendSearchBook(book('a', 'audio'));
  h.page.appendSearchBook(book('t2', 'text', 'S hared'));
  h.page.appendSearchBook(book('c', 'comic'));
  h.page.scheduleResultsRefresh(); h.page.scheduleResultsRefresh();
  assert.equal(h.timers.size, 1, 'burst results publish once');
  h.flush();
  assert.deepEqual(events, [['add', 0], ['add', 2]], 'insert new type before existing rows without a full reload');
  assert.deepEqual(Array.from({ length: 3 }, (_, i) => h.page.resultDataSource.getData(i).id), ['a', 't', 'c']);
  assert.equal(h.page.resultDataSource.getVersionedKey(text), textKey, 'inserting another type keeps existing keys stable');
  assert.equal(h.page.groupCount(text), 2);
  assert.equal(h.page.textCount, 2); assert.equal(h.page.comicCount, 1);
  events.length = 0;
  const updated = { ...text, cover: 'https://cover' };
  h.page.replaceSearchBook(updated); h.page.refreshVisibleBooks();
  assert.deepEqual(events, [['change', 1]], 'cover update touches its representative only');
  const updatedKey = h.page.resultDataSource.getVersionedKey(updated);
  assert.notEqual(updatedKey, textKey, 'changed plain Book must get a new LazyForEach key to rebuild its cover');
  assert.equal(h.page.resultGroups.get(h.page.groupKey(text))[0], updated);
  events.length = 0;
  h.page.selectSearchTab(2);
  assert.deepEqual(events, [['reload']], 'filter removal is a real dataset switch');
  assert.equal(h.page.visibleResultCount, 1);
  assert.equal(h.page.resultDataSource.getVersionedKey(updated), updatedKey, 'filter reload preserves content version');
  events.length = 0;
  h.page.refreshVisibleBooks();
  assert.equal(events.length, 0, 'unchanged refresh does not invalidate lazy rows');
  assert.equal(h.page.resultDataSource.getVersionedKey(updated), updatedKey);
  h.page.selectSearchTab(1);
  const hiddenUpdate = { ...updated, cover: 'https://cover/new' };
  h.page.replaceSearchBook(hiddenUpdate);
  h.page.selectSearchTab(2);
  assert.notEqual(h.page.resultDataSource.getVersionedKey(hiddenUpdate), updatedKey,
    'a hidden item updated before filtering back also changes its key');
  const hiddenKey = h.page.resultDataSource.getVersionedKey(hiddenUpdate);
  const audio = h.page.audioBooks[0];
  h.page.resultDataSource.updateBooks([hiddenUpdate, audio]);
  h.page.resultDataSource.updateBooks([audio, hiddenUpdate]);
  assert.equal(h.page.resultDataSource.getVersionedKey(hiddenUpdate), hiddenKey, 'reordering keeps unchanged item keys');
  h.page.resultDataSource.clear();
  h.page.resultDataSource.updateBooks([book('t')]);
  assert.equal(h.page.resultDataSource.getVersionedKey(hiddenUpdate), textKey, 'clear releases old session versions');
}
async function coversTest() {
  const h = harness();
  const source = { bookSourceName: 'source' };
  for (let batch = 0; batch < 8; batch++) {
    const books = Array.from({ length: 12 }, (_, index) => book(`${batch}-${index}`));
    books.forEach(value => h.page.appendSearchBook(value));
    await h.page.hydrateMissingLocalRuleCovers(source, books, 1);
  }
  assert.equal(h.calls.length, 3, 'all sources/pages share three detail requests');
  assert.equal(h.peak(), 3);
  await h.page.hydrateMissingLocalRuleCovers(source,
    Array.from({ length: 12 }, (_, index) => book(`overflow-${index}`)), 1);
  assert.equal(h.page.coverHydrationQueue.length, 96, 'optional cover backlog is bounded across pages');
  h.pending[0].reject(new Error('offline'));
  await tick();
  assert.equal(h.calls.length, 4, 'one failed cover releases its slot and continues');
  assert.equal(h.timers.size, 0, 'a failed cover does not refresh results');
  h.pending[1].resolve({ coverUrl: '' });
  await tick();
  assert.equal(h.timers.size, 0, 'empty detail does not refresh results');
  h.pending[2].resolve({ coverUrl: 'https://cover/2' });
  await tick();
  assert.equal(h.timers.size, 1, 'actual cover change uses the shared refresh timer');
  h.page.searchGen++;
  h.page.resetPagination();
  assert.equal(h.page.coverHydrationQueue.length, 0);
  assert.equal(h.page.coverHydrationActive, 3, 'old generation still occupies running slots');
  for (const item of h.pending.slice(3)) assert.equal(item.request.cancelCheck(), true);
  const next = book('new'); h.page.appendSearchBook(next);
  await h.page.hydrateMissingLocalRuleCovers(source, [next], 2);
  assert.equal(h.calls.length, 6, 'new generation waits for old running tasks to release slots');
  h.pending[3].resolve({ coverUrl: 'https://stale' });
  await tick();
  assert.equal(h.calls.length, 7);
  assert.equal(h.peak(), 3, 'cross-generation overlap stays bounded');
  assert.equal(h.timers.size, 0, 'stale result does not publish');
  h.page.leavingPage = true;
  h.page.coverHydrationQueue = [];
  for (const item of h.pending.slice(4)) item.resolve({ coverUrl: 'https://stale' });
  await tick();
  assert.equal(h.page.coverHydrationActive, 0);
  assert.equal(h.timers.size, 0, 'leaving page suppresses late UI writes');
}
(async () => {
  aggregationTest();
  await coversTest();
  console.log('PASS: incremental grouping, stable type order, precise lazy notifications, throttled covers, global concurrency, failure isolation and generation cancellation');
})().catch(error => { console.error(error); process.exitCode = 1; });
