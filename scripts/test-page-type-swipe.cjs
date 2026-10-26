// Run actual page gesture handlers with lightweight selection/scroll dependencies.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const generalSettings = { swipeSwitchTabs: false };
function page(file, methods) {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages', file), 'utf8');
  const body = methods.map(name => {
    const start = source.indexOf(`  private ${name}(`);
    assert.ok(start >= 0, `${file}: ${name} exists`);
    return source.slice(start, source.indexOf('\n  }', start) + 4);
  }).join('\n');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(`export class Page { ${body} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, CATEGORY_OVERVIEW_INDEX: -2, ScrollAlign: { AUTO: 0 },
    GeneralSettings: { current: generalSettings } });
  return new exports.Page();
}
const left = { offsetX: -100, offsetY: 5 };
const right = { offsetX: 100, offsetY: 5 };
const ignored = [{ offsetX: -20, offsetY: 0 }, { offsetX: 60, offsetY: 100 }, { offsetX: 0, offsetY: -100 }];
const shelf = page('FavoritePage.ets', ['handleShelfTypeSwipe', 'selectShelfFilter']);
Object.assign(shelf, { visible: true, loading: false, isManaging: false, removingBook: false,
  isRefreshing: false, showBatchDelete: false, shelfFilter: 0, favoriteBooks: [
    { id: 'audio', contentType: 'audio' }, { id: 'text', contentType: 'text' }, { id: 'comic', contentType: 'comic' }
  ], selectedBookIds: new Set(['audio']) });
shelf.filteredBooks = books => shelf.shelfFilter === 0 ? books : books.filter(book =>
  book.contentType === ['audio', 'text', 'comic'][shelf.shelfFilter - 1]);
let displayed = [];
shelf.bookDataSource = { setBooks: books => { displayed = books; } };
shelf.handleShelfTypeSwipe(right);
assert.equal(shelf.shelfFilter, 0, 'first shelf type does not wrap');
for (const [index, id] of [[1, 'audio'], [2, 'text'], [3, 'comic']]) {
  shelf.handleShelfTypeSwipe(left);
  assert.equal(shelf.shelfFilter, index);
  assert.equal(displayed[0].id, id, 'swipe refreshes the existing filtered data source');
}
shelf.handleShelfTypeSwipe(left);
assert.equal(shelf.shelfFilter, 3, 'last shelf type does not wrap');
assert.equal(shelf.selectedBookIds.size, 0);
for (const event of ignored) shelf.handleShelfTypeSwipe(event);
assert.equal(shelf.shelfFilter, 3);
for (const flag of ['isManaging', 'removingBook', 'isRefreshing', 'loading', 'showBatchDelete']) {
  shelf[flag] = true;
  shelf.handleShelfTypeSwipe(right);
  assert.equal(shelf.shelfFilter, 3, `${flag} blocks accidental selection changes`);
  shelf[flag] = false;
}
shelf.visible = false;
shelf.handleShelfTypeSwipe(right);
assert.equal(shelf.shelfFilter, 3);
shelf.visible = true;
shelf.handleShelfTypeSwipe(right);
assert.equal(shelf.shelfFilter, 2);

const home = page('HomePage.ets', ['handleCategorySwipe']);
Object.assign(home, { visible: true, homeResolved: true, rankingMode: false, homeSourceMenuVisible: false,
  isRefreshing: false, openingCarouselBook: false, selectedCategoryIndex: -2, homeCategories: [{}, {}] });
home.showCategoryOverview = () => { home.selectedCategoryIndex = -2; };
home.switchCategory = index => { home.selectedCategoryIndex = index; };
home.handleCategorySwipe(right);
assert.equal(home.selectedCategoryIndex, -2);
for (const next of [-1, 0, 1, 1]) {
  home.handleCategorySwipe(left);
  assert.equal(home.selectedCategoryIndex, next);
}
for (const event of ignored) home.handleCategorySwipe(event);
assert.equal(home.selectedCategoryIndex, 1);
for (const flag of ['rankingMode', 'homeSourceMenuVisible', 'isRefreshing', 'openingCarouselBook']) {
  home[flag] = true;
  home.handleCategorySwipe(right);
  assert.equal(home.selectedCategoryIndex, 1);
  home[flag] = false;
}
for (const next of [0, -1, -2, -2]) {
  home.handleCategorySwipe(right);
  assert.equal(home.selectedCategoryIndex, next);
}

const ranking = page('RankingHomePage.ets', ['handlePlatformSwipe']);
Object.assign(ranking, { visible: true, showSheet: false, boardTransitioning: false, refreshing: false,
  overview: true, platformId: '', platforms: [{ id: '' }, { id: 'audio' }, { id: 'novel' }] });
const revealed = [];
ranking.categoryScroller = { scrollToIndex: index => revealed.push(index) };
ranking.selectPlatform = id => { ranking.platformId = id; ranking.overview = false; };
ranking.handlePlatformSwipe(right);
assert.equal(ranking.overview, true);
for (const id of ['', 'audio', 'novel', 'novel']) {
  ranking.handlePlatformSwipe(left);
  assert.equal(ranking.platformId, id);
  assert.equal(ranking.overview, false);
}
assert.deepEqual(revealed, [0, 1, 2], 'selected category is scrolled into view');
for (const event of ignored) ranking.handlePlatformSwipe(event);
assert.equal(ranking.platformId, 'novel');
for (const flag of ['showSheet', 'boardTransitioning', 'refreshing']) {
  ranking[flag] = true;
  ranking.handlePlatformSwipe(right);
  assert.equal(ranking.platformId, 'novel');
  ranking[flag] = false;
}
ranking.activeBoard = {};
ranking.handlePlatformSwipe(right);
assert.equal(ranking.platformId, 'novel', 'an open board retains its own navigation');
ranking.activeBoard = undefined;
ranking.platforms = [{ id: '' }, { id: 'novel' }];
ranking.handlePlatformSwipe(right);
assert.equal(ranking.platformId, '', 'swipe follows the current enabled category order');
ranking.handlePlatformSwipe(right);
assert.equal(ranking.overview, true);
generalSettings.swipeSwitchTabs = true;
const before = [shelf.shelfFilter, home.selectedCategoryIndex, ranking.platformId, ranking.overview];
shelf.handleShelfTypeSwipe(right);
home.handleCategorySwipe(left);
ranking.handlePlatformSwipe(left);
assert.deepEqual([shelf.shelfFilter, home.selectedCategoryIndex, ranking.platformId, ranking.overview], before,
  'tab-swipe mode disables all page type handlers immediately');
console.log('PASS: shelf types, source categories, ranking categories, boundaries, vertical/short gestures and modal/edit guards');
