// Exercises the real preference writer and shelf selection/delete methods with isolated storage.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release DevEco Studio');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
function compile(source, globals) {
  const context = { exports: {}, Set, Map, JSON, console, LocalBuilder: () => {}, Builder: () => {}, ...globals };
  const output = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  vm.runInNewContext(output, context);
  return context.exports;
}
const values = new Map();
let writes = 0, flushes = 0, events = 0, failWrite = false;
const store = {
  get: async (key, fallback) => values.get(key) ?? fallback,
  put: async (key, value) => {
    if (failWrite) throw new Error('disk full');
    writes++;
    values.set(key, value);
  },
  delete: async key => { values.delete(key); },
  flush: async () => { flushes++; }
};
const presentation = compile(read('model/BookPresentation.ets'), { require: () => ({}) });
const { BookPresentation, BookPresentationEdit } = presentation;
const { PreferenceService } = compile(read('service/PreferenceService.ets'), {
  require: name => name === '@kit.BasicServicesKit' ? { emitter: { emit: () => events++ } } :
    name === '../model/BookPresentation' ? presentation : {}
});
PreferenceService.store = store;
const fileCalls = [];
let failFile = '';
const page = read('pages/FavoritePage.ets');
const methods = page.slice(page.indexOf('  private async deleteBookFilesAndRecords('), page.indexOf('  private bookMenuOptions('));
const filter = page.slice(page.indexOf('  private filteredBooks('), page.indexOf('  private handleBookTap('));
const { Shelf } = compile(`export class Shelf { ${filter}\n${methods}\n }`, {
  PreferenceService,
  BookPresentation,
  StatsService: { removeBookStats: async ids => { fileCalls.push('stats:' + ids.join(',')); } },
  TextReadingProgressService: { remove: async (ctx, id) => { fileCalls.push('reading:' + id); } },
  TextToSpeechService: { getInstance: () => ({ state: { bookId: 'audio' },
    stop: () => { fileCalls.push('stop-speech'); },
    removeSavedPositions: async (ctx, ids) => { fileCalls.push('speech:' + ids.join(',')); }
  }) },
  PlaybackStore: { getInstance: () => ({ getCurrentBookId: () => 'audio' }) },
  AudioService: { getInstance: () => ({
    stopForClear: async () => { fileCalls.push('stop-audio'); },
    unfreezePersist: () => { fileCalls.push('unfreeze'); }
  }) },
  DownloadService: { getInstance: () => ({ deleteBookDownload: async id => {
    fileCalls.push(`download:${id}`);
    if (id === failFile) throw new Error('file busy');
  } }) },
  DataService: {
    removeImportedBook: async id => { fileCalls.push(`import:${id}`); },
    getBookById: async (ctx, id) => ({ chapters: [], sourceUrl: 'test-source', bookUrl: id })
  },
  ChapterCacheService: { getInstance: () => ({ clearBook: id => { fileCalls.push(`chapters:${id}`); } }) },
  OnlineTextContentCache: { removeBook: async (ctx, source, id) => { fileCalls.push(`content:${id}`); } },
  $r: (name, ...args) => ({ name, args })
});
function makeShelf() {
  const shelf = new Shelf();
  Object.assign(shelf, {
    context: {}, visible: true, shelfFilter: 0, shelfStatusFilter: 0, shelfKeyword: '',
    isManaging: false, showBatchDelete: false,
    removingBook: false, isRefreshing: false, resolvingTocId: '', showBookActions: false,
    selectedBookIds: new Set(), favoritesLoadSerial: 0, favoriteIdsByBookId: new Map(),
    favoriteBooks: [{ id: 'audio', contentType: 'audio' }, { id: 'import_text', contentType: 'text' },
      { id: 'other', contentType: 'text' }],
    bookDataSource: { setBooks() {} },
    loadFavorites: async () => {},
    getUIContext: () => ({ getPromptAction: () => ({ showToast() {} }) })
  });
  return shelf;
}
function favorites(ids) { values.set('favorite_book_ids', JSON.stringify(ids)); }
async function run() {
  favorites(['audio', 'import_text', 'other', 'newly-added']);
  values.set('play_history', 'untouched history');
  values.set('imported_books', 'untouched local books');
  await PreferenceService.removeFavorites(['audio', 'audio', 'missing', 'other']);
  assert.deepEqual(await PreferenceService.getFavorites(), ['import_text', 'newly-added']);
  assert.equal(writes, 1); assert.equal(flushes, 1); assert.equal(events, 1);
  assert.equal(values.get('play_history'), 'untouched history');
  assert.equal(values.get('imported_books'), 'untouched local books');
  await PreferenceService.removeFavorites([]);
  await PreferenceService.removeFavorites(['absent']);
  assert.equal(writes, 1);

  const shelf = makeShelf();
  shelf.enterManagement();
  shelf.toggleBookSelection('audio');
  assert.equal(shelf.selectedBookIds.size, 1);
  shelf.selectShelfFilter(2);
  assert.equal(shelf.selectedBookIds.size, 0, 'changing category clears hidden selection');
  shelf.toggleSelectAllBooks();
  assert.deepEqual([...shelf.selectedBookIds], ['import_text', 'other']);
  shelf.toggleSelectAllBooks();
  assert.equal(shelf.selectedBookIds.size, 0);
  assert.equal(shelf.isManaging, true, 'deselecting the last book stays in management');
  shelf.toggleBookSelection('import_text');
  shelf.deleteLocalFiles = true;
  shelf.confirmBatchDelete();
  assert.equal(shelf.deleteLocalFiles, false, 'every confirmation defaults to keeping files');
  assert.equal(shelf.handleManageBack(), true);
  assert.equal(shelf.showBatchDelete, false);
  assert.equal(shelf.selectedBookIds.size, 1, 'cancel keeps the current selection');
  assert.equal(shelf.handleManageBack(), true);
  assert.equal(shelf.isManaging, false);

  favorites(['audio', 'import_text', 'other']);
  shelf.enterManagement('import_text');
  shelf.confirmBatchDelete();
  await shelf.deleteSelectedBooks();
  assert.deepEqual(await PreferenceService.getFavorites(), ['audio', 'other']);
  assert.equal(fileCalls.length, 0, 'shelf-only removal never touches local files');
  assert.equal(shelf.isManaging, false);

  values.set('play_history', JSON.stringify([{ bookId: 'legacy-id' }, { bookId: 'audio' }, { bookId: 'import_text' }, { bookId: 'other' }]));
  values.set('last_played', JSON.stringify({ bookId: 'audio' }));
  favorites(['legacy-id', 'import_text', 'other']);
  shelf.selectShelfFilter(0);
  shelf.favoriteIdsByBookId.set('audio', ['legacy-id']);
  shelf.enterManagement('audio');
  shelf.toggleBookSelection('import_text');
  shelf.confirmBatchDelete();
  shelf.deleteLocalFiles = true;
  failFile = 'import_text';
  await shelf.deleteSelectedBooks();
  assert.deepEqual(await PreferenceService.getFavorites(), ['import_text', 'other']);
  assert.deepEqual([...shelf.selectedBookIds], ['import_text']);
  assert.equal(shelf.isManaging, true, 'failed books remain selected for retry');
  assert(!fileCalls.includes('import:import_text'), 'failed download cleanup does not remove imported metadata');
  assert(fileCalls.includes('reading:audio') && fileCalls.includes('reading:legacy-id'));
  assert(fileCalls.includes('chapters:audio') && fileCalls.includes('content:legacy-id'));
  assert(!fileCalls.includes('content:import_text'), 'failed file deletion retains cached content');
  assert(!fileCalls.includes('reading:import_text'), 'failed file deletion retains records');
  assert(fileCalls.indexOf('stop-audio') < fileCalls.indexOf('download:audio'));
  assert.equal(await PreferenceService.getLastPlayed(), null);
  assert.deepEqual((await PreferenceService.getHistory()).map(x => x.bookId), ['import_text', 'other']);
  failFile = '';
  shelf.confirmBatchDelete();
  shelf.deleteLocalFiles = true;
  await shelf.deleteSelectedBooks();
  assert(fileCalls.includes('import:import_text'));
  assert(fileCalls.includes('reading:import_text'));
  assert.deepEqual((await PreferenceService.getHistory()).map(x => x.bookId), ['other']);
  assert.deepEqual(await PreferenceService.getFavorites(), ['other']);

  shelf.enterManagement('other');
  shelf.confirmBatchDelete();
  failWrite = true;
  await shelf.deleteSelectedBooks();
  assert.equal(shelf.removingBook, false);
  assert(shelf.selectedBookIds.has('other'), 'write failure preserves the selection');
  assert.deepEqual(await PreferenceService.getFavorites(), ['other']);
  failWrite = false;
  shelf.removingBook = true;
  shelf.toggleSelectAllBooks();
  assert.deepEqual([...shelf.selectedBookIds], ['other'], 'busy selection cannot change');
  assert.equal(shelf.handleManageBack(), true);
  // Moving a book updates group membership without changing metadata, favorites or files.
  const edit = new BookPresentationEdit();
  edit.bookId = 'audio'; edit.title = 'My title'; edit.cover = 'file://cover.jpg';
  BookPresentation.edits = [edit];
  favorites(['audio', 'import_text', 'other']);
  assert(BookPresentation.matchesGroup('audio', BookPresentation.UNGROUPED));
  await PreferenceService.setBookGroup(['audio', 'import_text'], '小说');
  assert(!BookPresentation.matchesGroup('audio', BookPresentation.UNGROUPED));
  assert(BookPresentation.matchesGroup('audio', '小说'));
  assert.equal(BookPresentation.get('audio').title, 'My title');
  assert.equal(BookPresentation.get('audio').cover, 'file://cover.jpg');
  const grouped = makeShelf();
  grouped.shelfGroup = '小说';
  grouped.enterManagement('audio'); grouped.confirmBatchDelete(); grouped.deleteGroupOnly = true;
  const beforeFiles = fileCalls.length;
  await grouped.deleteSelectedBooks();
  assert(BookPresentation.matchesGroup('audio', BookPresentation.UNGROUPED));
  assert(!BookPresentation.matchesGroup('audio', '小说'));
  assert(BookPresentation.matchesGroup('import_text', '小说'));
  assert.deepEqual(await PreferenceService.getFavorites(), ['audio', 'import_text', 'other']);
  assert.equal(fileCalls.length, beforeFiles);
  assert.equal(JSON.parse(values.get('book_presentation_v1')).find(x => x.bookId === 'audio').group, '');
  failWrite = true;
  await assert.rejects(PreferenceService.setBookGroup(['audio'], '失败分组'));
  failWrite = false;
  assert(BookPresentation.matchesGroup('audio', BookPresentation.UNGROUPED));
  // Pinning survives a new service instance and never rewrites the original shelf order.
  favorites(['new', 'audio', 'import_text', 'other']);
  await PreferenceService.setFavoritesPinned(['audio'], true);
  await PreferenceService.setFavoritesPinned(['other'], true);
  assert.deepEqual(await PreferenceService.getShelfFavorites(), ['other', 'audio', 'new', 'import_text']);
  assert.deepEqual(await PreferenceService.getFavorites(), ['new', 'audio', 'import_text', 'other']);
  const restarted = compile(read('service/PreferenceService.ets'), {
    require: name => name === '@kit.BasicServicesKit' ? { emitter: { emit() {} } } : {}
  }).PreferenceService;
  restarted.store = store;
  assert.deepEqual(await restarted.getPinnedFavorites(), ['other', 'audio']);
  await PreferenceService.setFavoritesPinned(['other'], false);
  assert.deepEqual(await PreferenceService.getShelfFavorites(), ['audio', 'new', 'import_text', 'other']);
  await PreferenceService.toggleFavorite('newer');
  assert.deepEqual(await PreferenceService.getShelfFavorites(), ['audio', 'newer', 'new', 'import_text', 'other']);
  await PreferenceService.removeFavorites(['audio']);
  await PreferenceService.toggleFavorite('audio');
  assert.deepEqual(await PreferenceService.getPinnedFavorites(), [], 're-adding a removed book clears its pin');
  await PreferenceService.setFavoritesPinned(['import_text'], true);
  await PreferenceService.removeFavorite('import_text');
  assert.deepEqual(await PreferenceService.getPinnedFavorites(), []);
  await PreferenceService.setFavoritesPinned(['missing'], true);
  assert.deepEqual(await PreferenceService.getPinnedFavorites(), [], 'missing favorites cannot be pinned');
  failWrite = true;
  await assert.rejects(PreferenceService.setFavoritesPinned(['other'], true));
  failWrite = false;
  assert.deepEqual(await PreferenceService.getPinnedFavorites(), [], 'failed writes leave pin state unchanged');
  favorites(['first', 'old', 'last']);
  values.set('pinned_favorite_book_ids', JSON.stringify(['old']));
  await PreferenceService.replaceFavoriteSource('old', 'replacement', false);
  assert.deepEqual(await PreferenceService.getFavorites(), ['replacement', 'first', 'old', 'last'], 'cancel keeps both sources');
  assert.deepEqual(await PreferenceService.getPinnedFavorites(), ['old']);
  await PreferenceService.replaceFavoriteSource('old', 'replacement', false);
  assert.deepEqual(await PreferenceService.getFavorites(), ['replacement', 'first', 'old', 'last'], 'keeping both never duplicates the new source');
  await PreferenceService.replaceFavoriteSource('old', 'replacement', true);
  assert.deepEqual(await PreferenceService.getFavorites(), ['first', 'replacement', 'last'], 'replacement keeps the original shelf position');
  assert.deepEqual(await PreferenceService.getPinnedFavorites(), ['replacement'], 'replacement inherits the original pin');
  const beforeNoop = writes;
  await PreferenceService.replaceFavoriteSource('', 'unused', false);
  await PreferenceService.replaceFavoriteSource('replacement', 'replacement', true);
  assert.equal(writes, beforeNoop);
  console.log('PASS: source-switch cancel keeps both, replacement preserves order/pin, deduplication and no-op guards');
  console.log('PASS: persistent pin order, unpin, newly added books, removal/re-add and write failures');
  console.log('PASS: filter-scoped selection, cancel/back, default file retention, bulk persistence, alias IDs, partial failure/retry and busy guards');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
