// Run the actual packing, hit testing, three-mode persistence and page data refresh logic.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const read = name => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', name), 'utf8');
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
const { ShelfSpineLayout: layout } = compile(read('utils/ShelfSpineLayout.ets'));
const books = Array.from({ length: 117 }, (_, i) => ({ id: `source-book-${i}`, title: `书名${i}`,
  author: '作者', cover: '', chapters: [], chapterCount: 20, bookUrl: `book/${i}`, sourceUrl: 'source' }));
for (const width of [240, 328, 568, 720, 1280, 2560]) {
  const rows = layout.rows(books, width);
  assert.equal(rows.flatMap(row => row.items.map(item => item.book.id)).join(','), books.map(b => b.id).join(','));
  assert.equal(new Set(rows.map(row => row.key)).size, rows.length);
  for (const row of rows) {
    assert.ok(row.width <= width && row.items.length <= 32);
    let x = 0;
    for (const item of row.items) {
      assert.equal(layout.bookAt(row, x), item.book.id);
      assert.equal(layout.bookAt(row, x + item.width - 0.01), item.book.id);
      x += item.width;
    }
    for (const outside of [-1, row.width, row.width + 30, NaN]) assert.equal(layout.bookAt(row, outside), '');
    for (const item of [row.items[0], row.items[row.items.length - 1]]) {
      const hint = layout.hint(row, item.book.id, width);
      assert.equal(hint.title, item.book.title);
      assert.ok(hint.left >= 0 && hint.left + hint.width <= width, 'title stays inside the shelf edges');
      assert.ok(hint.top + hint.height < 216 - item.height - 16, 'title floats above the pulled book');
    }
    assert.equal(layout.hint(row, '', width).title, '', 'release hides the title');
  }
}
assert.equal(layout.rows([], 328).length, 0);
assert.equal(layout.title('诡秘之主', 6), '诡\n秘\n之\n主');
assert.equal(layout.title('很长很长很长的书名', 6).split('\n').length, 6);
assert.ok(layout.title('很长很长很长的书名', 6).endsWith('…'));
assert.equal(layout.rows(books, 328)[0].key, layout.rows(books, 328)[0].key);
const preferenceSource = read('service/PreferenceService.ets');
const values = new Map();
const { PreferenceService } = compile(`export class PreferenceService {
  ${method(preferenceSource, '  static async getShelfViewMode(')}
  ${method(preferenceSource, '  static async setShelfViewMode(')}
}`);
PreferenceService.ensureStore = async () => ({ get: async (k, v) => values.has(k) ? values.get(k) : v,
  put: async (k, v) => { values.set(k, v); }, flush: async () => {} });
const pageSource = read('pages/FavoritePage.ets');
const hapticCalls = [];
const { Page } = compile(`export class Page {
  ${method(pageSource, '  private toggleViewMode(')}
  ${method(pageSource, '  private updateShelfData(')}
  ${method(pageSource, '  private updateSpinePull(')}
}`, { PreferenceService, ShelfSpineLayout: layout, Curve: { FastOutSlowIn: 0 },
  ReaderHapticService: { play: value => hapticCalls.push(value) } });
(async () => {
  for (const mode of [0, 1, 2]) {
    await PreferenceService.setShelfViewMode(mode);
    assert.equal(await PreferenceService.getShelfViewMode(), mode, 'mode survives reload');
  }
  for (const invalid of [-1, 3, 1.5, '2', null]) {
    values.set('shelf_view_mode', invalid);
    assert.equal(await PreferenceService.getShelfViewMode(), 0);
  }
  const page = Object.assign(new Page(), { viewMode: 0, viewModeRevision: 0,
    viewModeSaveTask: Promise.resolve(), getUIContext: () => ({ animateTo: (_opts, run) => run() }),
    spineContentWidth: 328, visible: true, isManaging: false, removingBook: false, showBookActions: false,
    resolvingTocId: '', bookDataSource: { setBooks: b => { page.gridBooks = b; } },
    spineDataSource: { setItems: r => { page.rows = r; } } });
  for (const next of [1, 2, 0, 1, 2]) { page.toggleViewMode(); assert.equal(page.viewMode, next); }
  await page.viewModeSaveTask;
  assert.equal(await PreferenceService.getShelfViewMode(), 2, 'rapid taps persist the last mode in order');
  page.updateShelfData(books.slice(0, 3));
  const row = page.rows[0];
  page.updateSpinePull(row, { fingerList: [undefined, { localX: row.items[0].width + 1, localY: 100 }] });
  assert.equal(page.pulledSpineBookId, books[1].id, 'nonzero finger ID can pull the second book');
  assert.equal(page.pulledSpineHint.title, books[1].title, 'active title is held in page state');
  assert.deepEqual(hapticCalls, ['weak'], 'entering a book triggers one light haptic');
  page.updateSpinePull(row, { fingerList: [{ localX: row.items[0].width + 4, localY: 100 }] });
  assert.equal(hapticCalls.length, 1, 'moving inside the same book does not repeat haptics');
  page.updateSpinePull(row, { fingerList: [{ localX: 5, localY: 100 }] });
  assert.equal(page.pulledSpineHint.title, books[0].title, 'crossing a book updates the displayed title');
  assert.equal(hapticCalls.length, 2, 'entering a different book triggers its haptic');
  page.updateSpinePull(row, { fingerList: [{ localX: row.items[0].width + 1, localY: 100 }] });
  assert.equal(hapticCalls.length, 3, 'returning to a book triggers one new haptic');
  page.updateSpinePull(row, { fingerList: [{ localX: 10, localY: 230 }] });
  assert.equal(page.pulledSpineBookId, '', 'leaving the row releases the book');
  assert.equal(page.pulledSpineHint.title, '', 'leaving the row clears the title');
  assert.equal(hapticCalls.length, 3, 'leaving the row does not vibrate');
  page.isManaging = true;
  page.updateSpinePull(row, { fingerList: [{ localX: 10, localY: 100 }] });
  assert.equal(page.pulledSpineBookId, '', 'management does not pull selected books');
  assert.equal(hapticCalls.length, 3, 'management does not vibrate');
  page.pulledSpineBookId = books[0].id;
  page.updateShelfData(books.slice(1, 3));
  assert.equal(page.gridBooks.map(b => b.id).join(','), page.rows.flatMap(r => r.items.map(i => i.book.id)).join(','));
  assert.equal(page.pulledSpineBookId, '', 'filter or removal clears the pulled state');
  console.log('PASS spine reflow, stable identity, hit boundaries, floating title bounds, per-book haptics, three-mode persistence and shelf refresh');
})().catch(error => { console.error(error); process.exitCode = 1; });
