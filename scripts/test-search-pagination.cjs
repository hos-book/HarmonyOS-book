// Execute real page scheduling methods; rendering is checked by ArkTS/build/device tools.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/SearchPage.ets'), 'utf8');
const start = source.indexOf('  private resetPagination(');
const end = source.indexOf('  private prefetchCovers(', start);
assert.ok(start > 0 && end > start);
const code = ts.transpileModule(`export class Page { ${source.slice(start, end)} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
let respond;
const calls = [];
const exportsObject = {};
vm.runInNewContext(code, {
  exports: exportsObject, Set, Map,
  DOMAIN: 0, TAG: 'test', hilog: { warn() {} }, LocalRuleSource: class {},
  SearchOptions: { matches: name => name !== 'filtered', matchesContentType: () => true },
  BookSourceService: { searchBooks: async (s, keyword, page) => {
    calls.push([s.bookSourceUrl, keyword, page]);
    return respond(s.bookSourceUrl, page);
  } }
});
function page() {
  const p = new exportsObject.Page();
  p.resetPagination();
  Object.assign(p, { searchGen: 1, searching: true, searchedSourceCount: 0, pageShown: true, leavingPage: false,
    audioBooks: [], textBooks: [], comicBooks: [], searchConcurrency: 2,
    refreshVisibleBooks() {}, scheduleResultsRefresh() {}, prefetchCovers() {},
    searchResultToBook: item => item });
  p.activeKeyword = 'original';
  p.activeSources = ['a', 'b'].map(bookSourceUrl => ({ bookSourceUrl, bookSourceType: 0 }));
  for (const s of p.activeSources) p.sourcePages.set(s.bookSourceUrl, 1);
  return p;
}
const item = (sourceUrl, bookUrl, name = 'book') => ({ sourceUrl, bookUrl, name });
(async () => {
  const p = page();
  respond = (s, n) => n === 1 ? [item(s, '1', s === 'a' ? 'filtered' : 'book')] :
    s === 'a' && n === 2 ? [item(s, '2')] : s === 'b' ? [item(s, '1')] : [];
  p.keyword = 'edited but not submitted';
  await p.searchSources(p.activeSources, p.activeKeyword, p.searchGen, p.searchSeen, 2);
  assert.equal(p.textBooks.length, 2);
  assert.equal(p.sourcePages.has('b'), false, 'repeated first page stops only that source');
  assert.equal(p.sourcePages.size, 0, 'one search automatically drains every source');
  assert.equal(p.searchedSourceCount, 2, 'completion progress counts sources, not pages');
  assert.deepEqual(calls, [['a','original',1],['b','original',1],['a','original',2],['b','original',2],['a','original',3]]);
  const stale = page();
  let release;
  respond = () => new Promise(resolve => { release = resolve; });
  stale.searchConcurrency = 1;
  const work = stale.searchSources(stale.activeSources, stale.activeKeyword, stale.searchGen, stale.searchSeen, 1);
  const before = calls.length;
  stale.searchGen++;
  stale.resetPagination();
  release([item('a', 'old')]);
  await work;
  assert.equal(stale.textBooks.length, 0);
  assert.equal(stale.sourcePages.size, 0);
  assert.equal(calls.length, before, 'cancelled generation does not start queued sources');
  const failures = page();
  respond = s => { if (s === 'a') throw new Error('offline'); return [item(s, 'ok')]; };
  await failures.searchSources(failures.activeSources, failures.activeKeyword, failures.searchGen, failures.searchSeen, 2);
  assert.equal(failures.textBooks.length, 1, 'one failed source does not block another');
  assert.equal(failures.sourcePages.has('a'), false);
  const fair = page();
  calls.length = 0;
  respond = (s, n) => n < 4 ? [item(s, String(n))] : [];
  await fair.searchSources(fair.activeSources, fair.activeKeyword, fair.searchGen, fair.searchSeen, 1);
  assert.deepEqual(calls.map(call => [call[0], call[2]]),
    [['a',1],['b',1],['a',2],['b',2],['a',3],['b',3],['a',4],['b',4]], 'pages queue behind other sources fairly');
  assert.equal(fair.textBooks.length, 6);
  assert.equal(fair.searchedSourceCount, 2);
  console.log('PASS automatic pagination: all pages, filtered/empty/repeated pages, dedupe, keyword snapshot, cancellation, isolated failures and fair scheduling');
})().catch(error => { console.error(error); process.exitCode = 1; });
