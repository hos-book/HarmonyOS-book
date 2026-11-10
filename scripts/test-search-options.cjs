const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const modules = new Map();
let installedSources = [];
function load(relative) {
  if (modules.has(relative)) return modules.get(relative);
  const code = ts.transpileModule(fs.readFileSync(path.join(root, relative + '.ets'), 'utf8')
    .replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, ''), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const exportsObject = {};
  modules.set(relative, exportsObject);
  vm.runInNewContext(code, {
    exports: exportsObject, console, Map, Set,
    require: name => name.endsWith('/LocalRuleSourceRepository')
      ? { LocalRuleSourceRepository: { getAll: async () => installedSources } }
      : load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), name)))
  });
  return exportsObject;
}
const { SearchOptions } = load('utils/SearchOptions');
const { LocalRuleSource } = load('model/LocalRuleSource');
const { SourceDataService } = load('service/SourceDataService');
for (let mask = 0; mask < 8; mask++) {
  const flags = [Boolean(mask & 1), Boolean(mask & 2), Boolean(mask & 4)];
  for (const [sourceType, contentType, flag] of [[0, 'text', 0], [3, 'text', 0], [1, 'audio', 1], [2, 'comic', 2]]) {
    const expected = mask === 0 || flags[flag];
    assert.equal(SearchOptions.matchesSourceType(sourceType, ...flags), expected);
    assert.equal(SearchOptions.matchesContentType(contentType, ...flags), expected);
    const source = LocalRuleSource.descriptor('https://ordinary.test', 'ordinary');
    source.bookSourceType = sourceType;
    source.engine = 'light';
    assert.equal(SearchOptions.matchesSource(source, ...flags), expected);
    source.engine = 'light-native';
    assert.equal(SearchOptions.matchesSource(source, ...flags), true, 'native default type cannot exclude mixed results');
  }
  assert.equal(SearchOptions.matchesSourceType(undefined, ...flags), mask === 0);
}
assert.equal(SearchOptions.matchesSourceType(2, false, false), true);
assert.equal(SearchOptions.matchesContentType('comic', true, false), false);
console.log('PASS: all 8 search type combinations, comic source/result filtering and default compatibility');

// Exercise the actual page's selection, scheduling and result filtering with real imported-source models.
const pageSource = fs.readFileSync(path.join(root, 'pages/SearchPage.ets'), 'utf8');
const start = pageSource.indexOf('  private async doSearch(');
const end = pageSource.indexOf('  private booksForType(', start);
assert.ok(start > 0 && end > start);
const pageCode = ts.transpileModule(`export class Page { ${pageSource.slice(start, end)} }`, {
  compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
}).outputText;
const pageExports = {};
const calls = [];
const rows = ['text', 'audio', 'comic'].map(contentType => ({ name: 'book', author: 'author', contentType,
  sourceUrl: 'https://aggregate.test', bookUrl: `srv://${contentType}/book` }));
vm.runInNewContext(pageCode, {
  exports: pageExports, Map, Set, clearTimeout, SearchOptions, LocalRuleSource, SourceDataService,
  DOMAIN: 0, TAG: 'test', Edge: { Top: 0 }, BookCard: { resetAnimations() {} },
  hilog: { info() {}, warn() {}, error(...args) { throw new Error(args.join(' ')); } },
  PreferenceService: { getSearchConcurrency: async () => 2 }, LightSourceRequest: class {},
  BookSourceService: { searchBooks: async (source, keyword, page) => {
    calls.push([source.bookSourceUrl, page]);
    // Text occupies page 1. Audio/comics on page 2 must remain reachable after page 1 is filtered out.
    return source.bookSourceUrl === rows[0].sourceUrl ? page === 1 ? rows.slice(0, 1) :
      page === 2 ? rows.slice(1) : [] : [];
  } }
});
function makePage(flags) {
  const p = new pageExports.Page();
  Object.assign(p, { keyword: 'book', searchHistory: [], searchGen: 0, leavingPage: false,
    searchTextOnly: flags[0], searchAudioOnly: flags[1], searchComicOnly: flags[2],
    sourceFilterEnabled: false, selectedSourceUrls: [], resultsRefreshTimer: -1,
    resultDataSource: { clear() {} }, resultScroller: { scrollEdge() {} },
    cancelRecommendations() {}, trimHistory() {}, persistHistory() {}, refreshVisibleBooks() {},
    scheduleResultsRefresh() {}, prefetchCovers() {}, searchResultToBook: item => item,
    appendSearchBook(book) { this[book.contentType + 'Books'].push(book); } });
  return p;
}
(async () => {
  const aggregate = LocalRuleSource.descriptor(rows[0].sourceUrl, 'aggregate');
  aggregate.engine = 'light-native';
  aggregate.nativeSearch = true;
  const ordinary = LocalRuleSource.descriptor('https://ordinary.test', 'ordinary');
  ordinary.engine = 'light';
  ordinary.searchUrl = '/search';
  installedSources = [aggregate, ordinary];
  for (let mask = 0; mask < 8; mask++) {
    const flags = [Boolean(mask & 1), Boolean(mask & 2), Boolean(mask & 4)];
    const p = makePage(flags);
    calls.length = 0;
    await p.doSearch();
    assert.deepEqual(calls.filter(call => call[0] === aggregate.bookSourceUrl).map(call => call[1]), [1, 2, 3]);
    for (const [index, type] of ['text', 'audio', 'comic'].entries()) {
      assert.equal(p[type + 'Books'].length, mask === 0 || flags[index] ? 1 : 0, `mask ${mask}, ${type}`);
    }
    assert.equal(calls.some(call => call[0] === ordinary.bookSourceUrl), mask === 0 || flags[0]);
  }
  const specified = makePage([false, true, false]);
  specified.sourceFilterEnabled = true;
  specified.selectedSourceUrls = [ordinary.bookSourceUrl];
  calls.length = 0;
  await specified.doSearch();
  assert.equal(calls.length, 0, 'type eligibility does not bypass specified source selection');
  for (const state of ['disabled', 'no-search', 'deleted']) {
    aggregate.enabled = state !== 'disabled';
    aggregate.nativeSearch = state !== 'no-search';
    installedSources = state === 'deleted' ? [] : [aggregate];
    calls.length = 0;
    const p = makePage([false, true, false]);
    await p.doSearch();
    assert.equal(calls.length, 0, state);
    assert.equal(p.audioBooks.length, 0, state);
    assert.equal(p.searching, false, state);
  }
  console.log('PASS: native aggregate page filtering, filtered-page continuation, source selection and enabled/search/empty-state gates');
})().catch(error => { console.error(error); process.exitCode = 1; });
