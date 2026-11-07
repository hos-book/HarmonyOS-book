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
  const context = { exports: {}, Set, Map, JSON, console, setTimeout, clearTimeout,
    LocalBuilder: () => {}, Builder: () => {}, ...globals };
  const output = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  vm.runInNewContext(output, context);
  return context.exports;
}
const values = new Map();
let writes = 0, flushes = 0, events = 0, failWrite = false;
let beforeFlush = async () => {};
const store = {
  getSync: (key, fallback) => values.get(key) ?? fallback,
  putSync: (key, value) => {
    if (failWrite) throw new Error('disk full');
    writes++; values.set(key, value);
  },
  get: async (key, fallback) => values.get(key) ?? fallback,
  put: async (key, value) => {
    if (failWrite) throw new Error('disk full');
    writes++;
    values.set(key, value);
  },
  delete: async key => { values.delete(key); },
  flush: async () => { flushes++; await beforeFlush(); }
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
const methods = page.slice(page.indexOf('  private markShelfBookVisible('), page.indexOf('  private bookMenuOptions('));
const filter = page.slice(page.indexOf('  private filteredBooks('), page.indexOf('  private handleBookTap('));
const single = page.slice(page.indexOf('  private async removeActionBook('), page.indexOf('  private markShelfBookVisible('));
const remove = page.slice(page.indexOf('  private async doRemove('), page.indexOf('\n  build() {', page.indexOf('  private async doRemove(')));
const { Shelf } = compile(`export class Shelf { ${filter}\n${single}\n${methods}\n${remove}\n }`, {
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
    context: {}, alive: true, visible: true, shelfFilter: 0, shelfStatusFilter: 0, shelfKeyword: '',
    isManaging: false, showBatchDelete: false,
    removingBook: false, isRefreshing: false, resolvingTocId: '', showBookActions: false,
    selectedBookIds: new Set(), favoritesLoadSerial: 0, favoriteIdsByBookId: new Map(),
    visibleShelfBookIds: new Set(), pendingDissolveIds: new Set(), dissolvingBookIds: new Set(),
    pendingShelfRemovalIds: new Set(), displayedBooks: [],
    cancelAutoUpdate: () => {}, scheduleAutoUpdate: () => {},
    pinnedBookIds: new Set(), isMissingCachedBook: () => false, reloads: 0,
    favoriteBooks: [{ id: 'audio', contentType: 'audio' }, { id: 'import_text', contentType: 'text' },
      { id: 'other', contentType: 'text' }],
    bookDataSource: { setBooks(books) { shelf.displayedBooks = books; } },
    updateShelfData(books) { this.bookDataSource.setBooks(books); },
    loadFavorites: async () => { shelf.reloads++; },
    dismissDeleteSheet: async () => { shelf.showBatchDelete = false; },
    getUIContext: () => ({ getPromptAction: () => ({ showToast() {} }) })
  });
  shelf.bookDataSource.setBooks(shelf.favoriteBooks);
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

  let shelf = makeShelf();
  // The real animation gate must wait for all visible cards and ignore offscreen selections.
  const animated = makeShelf();
  animated.visibleShelfBookIds = new Set(['audio', 'import_text']);
  let animationDone = false;
  const animation = animated.animateShelfDelete(['audio', 'import_text', 'other'])
    .then(() => { animationDone = true; });
  assert.deepEqual([...animated.dissolvingBookIds], ['audio', 'import_text']);
  assert.equal(animated.lightweightShelfDelete, true, 'bulk removal uses lightweight feedback');
  animated.completeShelfDissolve('audio');
  await Promise.resolve();
  assert.equal(animationDone, false);
  animated.completeShelfDissolve('import_text');
  await animation;
  animated.cancelShelfDissolve();
  assert.equal(animated.dissolvingBookIds.size, 0);
  const leaving = animated.animateShelfDelete(['audio']);
  animated.cancelShelfDissolve();
  await leaving;

  const offscreen = animated.animateShelfDelete(['audio']);
  animated.markShelfBookVisible('audio', 0);
  assert.equal(animated.pendingDissolveIds.size, 0, 'offscreen cards cannot hold the animation gate');
  await offscreen;
  animated.cancelShelfDissolve();

  // File cleanup/persistence waits for the snapshot animation, preventing missing-cover frames.
  favorites(['audio', 'import_text', 'other']);
  animated.enterManagement('import_text');
  animated.confirmBatchDelete();
  const deleting = animated.deleteSelectedBooks();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(animated.pendingDissolveIds.has('import_text'), true);
  assert.deepEqual(await PreferenceService.getFavorites(), ['audio', 'import_text', 'other']);
  animated.completeShelfDissolve('import_text');
  await deleting;
  assert.deepEqual(await PreferenceService.getFavorites(), ['audio', 'other']);
  assert.equal(animated.dissolvingBookIds.size, 0);
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
  assert.deepEqual(shelf.favoriteBooks.map(book => book.id), ['audio', 'other']);
  assert.equal(shelf.reloads, 0, 'successful removal does not reload the book catalog');
  shelf = makeShelf();

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
  // Select-all immediately publishes an empty shelf, without parsing remaining catalogs.
  const all = makeShelf();
  favorites(['audio', 'import_text', 'other']);
  all.enterManagement(); all.toggleSelectAllBooks(); all.confirmBatchDelete();
  await all.deleteSelectedBooks();
  assert.deepEqual(all.favoriteBooks, []);
  assert.equal(all.reloads, 0);
  assert.equal(all.isManaging, false);
  // A concurrent addition still triggers reconciliation instead of disappearing from the UI.
  const concurrent = makeShelf();
  favorites(['audio', 'import_text', 'other', 'newly-added']);
  concurrent.enterManagement('audio'); concurrent.confirmBatchDelete();
  await concurrent.deleteSelectedBooks();
  assert.equal(concurrent.reloads, 1);
  assert.deepEqual(await PreferenceService.getFavorites(), ['import_text', 'other', 'newly-added']);

  // A slow file cleanup must not leave invisible cards occupying shelf slots.
  const slowFiles = makeShelf();
  favorites(['audio', 'import_text', 'other']);
  slowFiles.enterManagement('audio'); slowFiles.toggleBookSelection('import_text');
  slowFiles.confirmBatchDelete(); slowFiles.deleteLocalFiles = true;
  let releaseFiles, reportFilesStarted;
  const filesGate = new Promise(resolve => { releaseFiles = resolve; });
  const filesStarted = new Promise(resolve => { reportFilesStarted = resolve; });
  slowFiles.deleteBookFilesAndRecords = async id => {
    reportFilesStarted(); await filesGate;
    if (id === 'import_text') throw new Error('file busy');
  };
  const fileDeletion = slowFiles.deleteSelectedBooks();
  await filesStarted;
  assert.deepEqual(slowFiles.displayedBooks.map(book => book.id), ['other'],
    'the shelf closes gaps while file cleanup is still pending');
  assert.deepEqual(await PreferenceService.getFavorites(), ['audio', 'import_text', 'other'],
    'preview does not commit favorites before file deletion succeeds');
  releaseFiles(); await fileDeletion;
  assert.deepEqual(slowFiles.displayedBooks.map(book => book.id), ['import_text', 'other']);
  assert.deepEqual([...slowFiles.selectedBookIds], ['import_text']);
  assert.equal(slowFiles.pendingShelfRemovalIds.size, 0);
  assert.equal(slowFiles.reloads, 0, 'partial file failure restores from the loaded shelf');

  // Single-book removal also publishes the remaining list before a slow storage flush.
  const slowSave = makeShelf();
  favorites(['audio', 'import_text', 'other']);
  let releaseSave, reportSaveStarted;
  const saveGate = new Promise(resolve => { releaseSave = resolve; });
  const saveStarted = new Promise(resolve => { reportSaveStarted = resolve; });
  beforeFlush = async () => { reportSaveStarted(); await saveGate; };
  const saving = slowSave.removeActionBook(slowSave.favoriteBooks[0], false);
  await saveStarted;
  assert.deepEqual(slowSave.displayedBooks.map(book => book.id), ['import_text', 'other']);
  assert.equal(slowSave.favoriteBooks.length, 3, 'original entries stay available until commit');
  releaseSave(); await saving; beforeFlush = async () => {};
  assert.equal(slowSave.pendingShelfRemovalIds.size, 0);
  assert.equal(slowSave.reloads, 0);

  const failedSingle = makeShelf();
  favorites(['audio', 'import_text', 'other']);
  failWrite = true;
  await failedSingle.removeActionBook(failedSingle.favoriteBooks[0], false);
  failWrite = false;
  assert.deepEqual(failedSingle.displayedBooks.map(book => book.id), ['audio', 'import_text', 'other'],
    'failed persistence restores the original shelf order');
  assert.equal(failedSingle.removingBook, false);
  assert.equal(failedSingle.pendingShelfRemovalIds.size, 0);
  console.log('PASS: shelf reflow before slow cleanup/flush, partial failure restore and offscreen animation completion');
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
  favorites(['new', 'audio', 'import_text', 'comic', 'pinned']);
  values.set('pinned_favorite_book_ids', JSON.stringify(['pinned']));
  await PreferenceService.saveProgress({ bookId: 'audio', chapterId: 'a', chapterTitle: '第一章',
    chapterIndex: 0, positionMs: 1000, durationMs: 10000, updatedAt: Date.now() });
  assert.deepEqual(await PreferenceService.getShelfFavorites(), ['pinned', 'audio', 'new', 'import_text', 'comic']);
  const beforeRepeat = { writes, events };
  await PreferenceService.promoteFavorite('audio');
  await PreferenceService.promoteFavorite('not-favorited');
  assert.equal(writes, beforeRepeat.writes, 'repeated progress and non-favorites do not rewrite the shelf');
  assert.equal(events, beforeRepeat.events, 'repeated progress does not reload the shelf');
  const readingValues = new Map();
  const { TextReadingProgressService: reading } = compile(read('service/text/TextReadingProgressService.ets'), {
    require: name => name === '../PreferenceService' ? { PreferenceService } :
      name === '../../model/GeneralSettings' ? { GeneralSettings: { current: { historyEnabled: false } } } :
        name === '@kit.BasicServicesKit' ? { emitter: { emit() {} } } : {}
  });
  reading.store = { getSync: (key, fallback) => readingValues.get(key) ?? fallback,
    putSync: (key, value) => readingValues.set(key, value), getAll: async () => ({}), flush: async () => {} };
  for (const bookId of ['import_text', 'comic']) {
    await reading.save({}, { bookId, updatedAt: Date.now() });
    assert.equal((await PreferenceService.getShelfFavorites())[1], bookId,
      'reading, comic and shared speech progress promote books even with history disabled');
  }
  await PreferenceService.toggleFavorite('newest');
  assert.deepEqual(await restarted.getShelfFavorites(), ['pinned', 'newest', 'comic', 'import_text', 'audio', 'new'],
    'new books lead ordinary books and recency order survives restart');
  await PreferenceService.removeFavorite('audio');
  await PreferenceService.promoteFavorite('audio');
  assert.equal(await PreferenceService.isFavorite('audio'), false, 'late progress cannot restore removed favorites');
  console.log('PASS: recent audio/text/comic activity, stable pins, new favorites, restart, history disabled and no repeated shelf reload');
  console.log('PASS: source-switch cancel keeps both, replacement preserves order/pin, deduplication and no-op guards');
  console.log('PASS: persistent pin order, unpin, newly added books, removal/re-add and write failures');
  console.log('PASS: filter-scoped selection, cancel/back, default file retention, bulk persistence, alias IDs, partial failure/retry and busy guards');
  console.log('PASS: visible-card dissolve completion, offscreen exclusion, page-exit cleanup and persistence after animation');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
