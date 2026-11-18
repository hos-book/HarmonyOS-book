// Exercise the real three-view cycle, persistence and shared cover identity after retiring upright shelves.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release DevEco Studio');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const read = name => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', name), 'utf8').replace(/\r\n/g, '\n');
function compile(source, context = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, ...context });
  return exports;
}
function method(source, name) {
  const start = source.indexOf(name);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const preferenceSource = read('service/PreferenceService.ets');
const values = new Map();
const { PreferenceService } = compile(`export class PreferenceService {
  ${method(preferenceSource, '  static async getShelfViewMode(')}
  ${method(preferenceSource, '  static async setShelfViewMode(')}
}`);
PreferenceService.ensureStore = async () => ({
  get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
  put: async (key, value) => { values.set(key, value); }, flush: async () => {}
});
const pageSource = read('pages/FavoritePage.ets');
const { Page } = compile(`export class Page {
  ${method(pageSource, '  private toggleViewMode(')}
  ${method(pageSource, '  private updateShelfData(')}
  ${method(pageSource, '  private shelfCoverId(')}
}`, { PreferenceService, Curve: { FastOutSlowIn: 0 },
  OneShotTransitionIds: { sourceCover: id => `cover-${id}` } });
(async () => {
  assert.equal(await PreferenceService.getShelfViewMode(), 3, 'a fresh install defaults to collection');
  for (const mode of [0, 1, 3]) {
    await PreferenceService.setShelfViewMode(mode);
    assert.equal(await PreferenceService.getShelfViewMode(), mode, 'supported view survives reload');
  }
  values.set('shelf_view_mode', 2);
  assert.equal(await PreferenceService.getShelfViewMode(), 3, 'retired upright preference restores collection');
  for (const invalid of [-1, 4, 1.5, '2', null]) {
    values.set('shelf_view_mode', invalid);
    assert.equal(await PreferenceService.getShelfViewMode(), 3);
  }
  const refreshes = [];
  const page = Object.assign(new Page(), { viewMode: 0, viewModeRevision: 0,
    viewModeSaveTask: Promise.resolve(), collectionGroup: undefined,
    refreshCollectionRecent: () => refreshes.push('collection'), onHistoryUpdated: () => refreshes.push('books'),
    getUIContext: () => ({ animateTo: (_options, update) => { update(); update(); } }),
    bookDataSource: { setBooks: books => { page.books = books; } } });
  for (const next of [1, 3, 0, 1, 3]) { page.toggleViewMode(); assert.equal(page.viewMode, next); }
  await page.viewModeSaveTask;
  assert.equal(await PreferenceService.getShelfViewMode(), 3, 'rapid taps persist the last view in order');
  assert.equal(refreshes.join('|'), 'books|collection|books|books|collection');
  assert.equal(page.viewModeRevision, 5, 'manual switches invalidate pending startup restoration');
  const books = [{ id: 'book-a' }, { id: 'book-b' }];
  page.updateShelfData(books);
  assert.equal(page.books, books, 'grid and list retain the shared data source');
  assert.equal(page.shelfCoverId(books[0], false), 'shelf-grid-cover-book-a');
  assert.equal(page.shelfCoverId(books[0], true), 'shelf-list-cover-book-a');
  page.collectionGroup = '阅读';
  assert.equal(page.shelfCoverId(books[0], false), 'shelf-collection-cover-book-a');
  const icon = pageSource.slice(pageSource.indexOf("icon: this.viewMode === 0 ?"),
    pageSource.indexOf("}).id('shelf-view-toggle')"));
  assert.match(icon, /viewMode === 1 \? \$r\('sys\.symbol\.bookshelf'\)/);
  assert.match(icon, /viewMode === 1 \? \$r\('app\.string\.shelf_view_collection'\)/);
  assert.doesNotMatch(icon, /sys\.symbol\.folder|shelf_view_spine/);
  console.log('PASS grid/list/collection cycle, retired preference fallback, ordered saves, shared cover identity and collection icon');
})().catch(error => { console.error(error); process.exitCode = 1; });
