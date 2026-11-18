// Exercise real hidden-book persistence, shelf derivation, lock lifecycle and navigation callbacks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release DevEco Studio');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const read = file => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8').replace(/\r\n/g, '\n');
function compile(source, globals = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source.replace(/^import .*;\n/gm, ''), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, Set, Map, JSON, ...globals });
  return exports;
}
function member(source, name, prefixes = ['private ', 'private async ', '', 'get ']) {
  const start = prefixes.map(prefix => source.indexOf(`  ${prefix}${name}(`)).find(index => index >= 0);
  assert.ok(start >= 0, `missing member ${name}`);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const presentation = compile(read('model/BookPresentation.ets'));
const { BookPresentation: model, BookPresentationEdit: Edit } = presentation;
const { ShelfCollectionData, ShelfCollectionRoute } = compile(read('model/ShelfCollection.ets'), { BookPresentation: model });
const preferenceSource = read('service/PreferenceService.ets');
const values = new Map();
let events = 0;
let flushes = 0;
let beforeFlush = async () => {};
const store = {
  getSync: (key, fallback) => values.has(key) ? values.get(key) : fallback,
  put: async (key, value) => { values.set(key, value); },
  flush: async () => { flushes++; await beforeFlush(); }
};
const { PreferenceService } = compile(`export class PreferenceService {
  static async ensureStore() { return store; }
  static async getShelfFavorites() { return JSON.parse(store.getSync('favorite_book_ids', '[]')); }
  ${member(preferenceSource, 'setBookHidden', ['static async '])}
  ${member(preferenceSource, 'setBookGroup', ['static async '])}
  ${member(preferenceSource, 'saveBookPresentation', ['static async '])}
}`, { BookPresentation: model, store, emitter: { emit: () => { events++; } }, EVT_FAVORITES_CHANGED: 'favorites' });
class Report {
  checkedAt = 0;
  checkedCount = 0;
  failedCount = 0;
  updatedCount = 0;
  entries = [];
}
const source = read('pages/FavoritePage.ets');
const names = ['shelfBooks', 'matchesShelfVisibility', 'lockHiddenShelf', 'openHiddenShelf', 'unlockHiddenShelf',
  'setBooksHidden', 'shelfGroupBooks', 'collectionGroups', 'filteredBooks', 'refreshCollectionRecent',
  'canAddCollectionBooks', 'openCollectionPicker', 'addCollectionBooks', 'applyUpdateReport', 'exitManagement',
  'onVisibleChange'];
const applicationStart = source.indexOf('  private applicationState:');
assert.ok(applicationStart >= 0);
const applicationState = source.slice(applicationStart, source.indexOf('\n  };', applicationStart) + 5);
const { Shelf } = compile(`export class Shelf {
  ${applicationState}
  ${names.map(name => member(source, name)).join('\n')}
}`, { BookPresentation: model, PreferenceService, ShelfCollectionData, ShelfCollectionRoute,
  ShelfUpdateReport: Report, TextReadingProgressService: { getAll: async () => positions }, $r: key => key });
const books = [
  { id: 'audio', title: '普通听书', author: '', narrator: '', contentType: 'audio', chapterCount: 10 },
  { id: 'text', title: '普通小说', author: '', narrator: '', contentType: 'text', completed: false, chapterCount: 10 },
  { id: 'comic', title: '普通漫画', author: '', narrator: '', contentType: 'comic', chapterCount: 10 },
  { id: 'secret', title: '秘密小说', author: '', narrator: '', contentType: 'text', chapterCount: 10 },
  { id: 'secret-free', title: '秘密未分组', author: '', narrator: '', contentType: 'text', chapterCount: 10 }
];
const positions = [{ bookId: 'text', resourceIndex: 0, chapterTitle: '第一章', updatedAt: 100 },
  { bookId: 'secret', resourceIndex: 1, chapterTitle: '秘密章节', updatedAt: 300 }];
const ids = items => Array.from(items, book => book.id).join('|');
function edit(bookId, group = '', hidden = false) {
  return Object.assign(new Edit(), { bookId, title: `自定-${bookId}`, cover: `cover-${bookId}`, group, hidden });
}
function reset() {
  model.edits = [edit('audio', '听书'), edit('text', '阅读'), edit('secret', '阅读', true),
    edit('secret-free', '', true), edit('legacy-secret', '阅读', true)];
  model.groups = ['听书', '阅读'];
  values.clear();
  values.set('book_presentation_v1', JSON.stringify(model.edits));
  values.set('shelf_groups_v1', JSON.stringify(model.groups));
  values.set('favorite_book_ids', '["audio","text","comic","legacy-secret","secret-free"]');
  values.set('play_history', 'existing history');
  beforeFlush = async () => {};
}
function shelf(hidden = false) {
  const result = Object.assign(new Shelf(), {
    favoriteBooks: books.slice(), hiddenShelf: hidden, hiddenShelfUnlocked: true, shelfFilter: 0,
    shelfStatusFilter: 0, shelfKeyword: '', shelfGroup: '', shelfGroups: model.groups.slice(),
    pendingShelfRemovalIds: new Set(), favoriteIdsByBookId: new Map([['secret', ['legacy-secret']], ['audio', ['legacy-audio']]]),
    shelfDisplaySettings: { showUngroupedShelfGroup: true, shelfCollectionOrder: '[]' },
    alive: true, visible: true, foreground: true, loading: false, isManaging: false, removingBook: false,
    savingHidden: false, selectedBookIds: new Set(), showBatchDelete: false, showBookEditor: false,
    showUpdates: false, showBatchGroup: false, addingCollectionBooks: false, showCollectionPicker: false,
    context: {}, viewMode: hidden ? 0 : 3, collectionGroup: hidden ? '' : undefined,
    historyEnabled: true, shelfScrolling: false, collectionRecentSerial: 0, collectionRecent: [],
    collectionBooks: [], updateReport: new Report(), displayed: [], toasts: [], reloads: 0, updates: [],
    updateShelfData(items) { this.displayed = Array.from(items); },
    updateData: { setItems(items) { result.updates = items; } },
    loadFavorites: async () => { result.reloads++; }, isMissingCachedBook: () => false,
    getUIContext: () => ({ getPromptAction: () => ({ showToast: options => result.toasts.push(options.message) }) }),
    cancelAutoUpdate() {}, scheduleAutoUpdate() {}, finishShelfScroll() {}, cancelShelfDissolve() {},
    syncShelfSourceVisibility() {}, scheduleInitialLoad() {},
    navStack: { size: () => 0, pushPathByName: (...args) => result.routes.push(args) }, routes: []
  });
  result.displayed = Array.from(result.filteredBooks(result.favoriteBooks));
  return result;
}
async function run() {
  reset();
  assert.equal(new Edit().hidden, false);
  assert.equal(model.isHidden('missing'), false);
  const original = model.edits;
  const changed = model.assignHidden(['audio', 'audio'], true);
  assert.equal(changed.filter(item => item.bookId === 'audio').length, 1);
  assert.equal(model.isHidden('audio'), false, 'derivation cannot mutate live preferences before save');
  assert.notEqual(changed.find(item => item.bookId === 'audio'), original[0]);
  assert.equal(changed.find(item => item.bookId === 'audio').group, '听书');
  model.edits = changed;
  const moved = model.assignGroup(['audio'], '阅读').find(item => item.bookId === 'audio');
  assert.equal(moved.hidden, true, 'moving a hidden book cannot reveal it');
  assert.equal(moved.title, '自定-audio');
  assert.equal(moved.cover, 'cover-audio');

  reset();
  let releaseFlush;
  beforeFlush = () => new Promise(resolve => { releaseFlush = resolve; });
  const saving = PreferenceService.setBookHidden(['audio'], true);
  while (!releaseFlush) await Promise.resolve();
  assert.equal(model.isHidden('audio'), false, 'publish hidden state only after successful flush');
  const eventsBefore = events;
  releaseFlush();
  await saving;
  assert.equal(model.isHidden('audio'), true);
  assert.equal(events, eventsBefore + 1);
  assert.equal(JSON.parse(values.get('book_presentation_v1')).find(item => item.bookId === 'audio').hidden, true);
  beforeFlush = async () => {};
  await PreferenceService.setBookHidden(['audio'], false);
  assert.equal(model.get('audio').group, '听书', 'restoring a book retains its group and custom presentation');
  assert.equal(model.get('audio').title, '自定-audio');
  const previous = { edits: model.edits, groups: model.groups, stored: values.get('book_presentation_v1'),
    storedGroups: values.get('shelf_groups_v1'), events };
  beforeFlush = async () => { throw new Error('disk full'); };
  await assert.rejects(PreferenceService.setBookHidden(['audio'], true), /Book presentation save failed/);
  assert.equal(model.edits, previous.edits);
  assert.equal(model.groups, previous.groups);
  assert.equal(values.get('book_presentation_v1'), previous.stored);
  assert.equal(values.get('shelf_groups_v1'), previous.storedGroups);
  assert.equal(events, previous.events, 'failed persistence cannot publish a favorites update');
  console.log('PASS hidden metadata derivation, group preservation, flush ordering and failed-save rollback');

  reset();
  const ordinary = shelf();
  assert.equal(ids(ordinary.shelfBooks), 'audio|text|comic');
  assert.equal(ids(ordinary.filteredBooks(books)), 'audio|text|comic');
  ordinary.shelfKeyword = '秘密';
  assert.equal(ordinary.filteredBooks(books).length, 0, 'search cannot reveal hidden titles');
  ordinary.shelfKeyword = '';
  ordinary.shelfGroup = '阅读';
  assert.equal(ids(ordinary.shelfGroupBooks), 'text');
  assert.equal(ids(ordinary.filteredBooks(books)), 'text');
  ordinary.shelfGroup = '';
  ordinary.shelfFilter = 3;
  assert.equal(ids(ordinary.filteredBooks(books)), 'comic');
  ordinary.shelfFilter = 0;
  assert.equal(ids(ordinary.collectionGroups.flatMap(group => group.books)), 'audio|text|comic');
  await ordinary.refreshCollectionRecent([]);
  assert.equal(ids(ordinary.collectionRecent.map(item => item.book)), 'text', 'recent cards skip hidden newer history');
  ordinary.collectionGroup = '阅读'; ordinary.shelfGroup = '阅读';
  ordinary.openCollectionPicker();
  assert.equal(ids(ordinary.collectionPickerBooks), 'comic', 'group picker excludes hidden ungrouped books');
  await assert.rejects(ordinary.addCollectionBooks(['secret-free']), /no longer ungrouped favorites/);

  const concealed = shelf(true);
  assert.equal(ids(concealed.shelfBooks), 'secret|secret-free');
  concealed.shelfGroup = '阅读';
  assert.equal(ids(concealed.filteredBooks(books)), 'secret');
  concealed.shelfGroup = '';
  concealed.isManaging = true; concealed.selectedBookIds = new Set(['secret']);
  concealed.showBookEditor = true; concealed.editingBook = books[3];
  concealed.showUpdates = true; concealed.showBatchGroup = true; concealed.showBatchDelete = true;
  concealed.applicationState.onApplicationBackground();
  assert.equal(concealed.foreground, false);
  assert.equal(concealed.hiddenShelfUnlocked, false);
  assert.equal(concealed.displayed.length, 0);
  assert.equal(concealed.shelfBooks.length, 0);
  assert.equal(concealed.filteredBooks(books).length, 0);
  assert.equal(concealed.isManaging, false);
  assert.equal(concealed.selectedBookIds.size, 0);
  assert.equal(concealed.editingBook, null);
  for (const flag of ['showBookEditor', 'showUpdates', 'showBatchGroup', 'showBatchDelete']) assert.equal(concealed[flag], false);
  concealed.unlockHiddenShelf();
  assert.equal(concealed.hiddenShelfUnlocked, false, 'background cannot unlock hidden content');
  concealed.applicationState.onApplicationForeground();
  assert.equal(concealed.hiddenShelfUnlocked, false, 'foreground return waits for the title long press');
  concealed.unlockHiddenShelf();
  assert.equal(ids(concealed.displayed), 'secret|secret-free');
  concealed.visible = false;
  concealed.onVisibleChange();
  assert.equal(concealed.displayed.length, 0, 'leaving the page also locks hidden content');
  assert.equal(concealed.hiddenShelfUnlocked, false);
  console.log('PASS normal/hidden search, groups, media filters, recent/picker isolation and background/page lock');

  reset();
  const main = shelf();
  main.collectionRecent = [{ book: books[0] }];
  main.selectedBookIds = new Set(['audio']); main.isManaging = true;
  const favoritesBefore = values.get('favorite_book_ids');
  await main.setBooksHidden(['audio']);
  assert.equal(model.isHidden('audio'), true);
  assert.equal(model.isHidden('legacy-audio'), true, 'canonical and stored alias IDs share the hidden state');
  assert.equal(ids(main.displayed), 'text|comic');
  assert.equal(main.collectionRecent.length, 0);
  assert.equal(main.isManaging, false);
  assert.equal(values.get('favorite_book_ids'), favoritesBefore, 'hiding preserves favorites and local content');
  assert.equal(values.get('play_history'), 'existing history');
  const restore = shelf(true);
  await restore.setBooksHidden(['audio']);
  assert.equal(model.isHidden('audio'), false);
  assert.equal(model.isHidden('legacy-audio'), false);
  assert.equal(model.get('audio').group, '听书');
  const failed = shelf();
  beforeFlush = async () => { throw new Error('disk full'); };
  await failed.setBooksHidden(['audio']);
  assert.equal(model.isHidden('audio'), false);
  assert.equal(ids(failed.displayed), 'audio|text|comic');
  assert.equal(failed.savingHidden, false);
  assert.equal(failed.toasts.at(-1), 'app.string.settings_save_failed');
  const beforeGuard = flushes;
  failed.savingHidden = true;
  await failed.setBooksHidden(['audio']);
  const locked = shelf(true); locked.hiddenShelfUnlocked = false;
  await locked.setBooksHidden(['secret']);
  assert.equal(flushes, beforeGuard, 'busy and locked pages cannot submit a hidden-state change');

  const route = shelf();
  route.openHiddenShelf();
  assert.equal(route.routes[0][0], 'shelfCollection');
  assert.equal(route.routes[0][1].group, '');
  assert.equal(route.routes[0][1].hidden, true);
  route.routes[0][2]();
  assert.equal(route.reloads, 1, 'return reconciles restored/hidden books');
  route.navStack.size = () => 1;
  route.openHiddenShelf();
  assert.equal(route.routes.length, 1, 'a covered shelf cannot open another hidden route');
  assert.match(source, /duration: 800[^\n]*openHiddenShelf/);
  assert.match(read('pages/ShelfCollectionPage.ets'), /hiddenShelf: this\.route\.hidden/);
  const importId = source.indexOf(".id('shelf-local-import')");
  assert.ok(importId >= 0, 'root shelf retains the local import entry');
  const importButton = source.slice(source.lastIndexOf('ImmersiveCircleButton(', importId), importId);
  const importAction = importButton.match(/onPress: \(\): void => \{([^}]+)\}/);
  assert.ok(importAction, 'import callback is available');
  const { openImport } = compile(`export function openImport() { ${importAction[1]} }`);
  openImport.call(route);
  assert.equal(route.routes.at(-1)[0], 'import');
  assert.equal(route.routes.at(-1)[1], '');
  const profileSource = read('pages/ProfilePage.ets');
  assert.match(profileSource, /const SOURCE_ITEMS:[\s\S]*?doc_text_badge_arrow_up[\s\S]*?profile_local_import[\s\S]*?'import'/,
    'profile retains its local file import entry with a document import icon');
  assert.match(profileSource, /this\.buildGroup\(SOURCE_ITEMS\)/);
  const { Profile } = compile(`export class Profile { ${member(profileSource, 'onItemTap')} }`);
  const profile = Object.assign(new Profile(), { navStack: route.navStack });
  profile.onItemTap('import');
  assert.equal(route.routes.at(-1)[0], 'import');
  assert.equal(route.routes.at(-1)[1], '', 'both entry points reuse the same import route');
  console.log('PASS canonical/alias hide and restore, save errors/guards, hidden-title route and both local import routes');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
