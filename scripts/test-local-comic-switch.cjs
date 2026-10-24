// Run the production reader action and shelf keys against failing storage/navigation boundaries.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const reader = fs.readFileSync(path.join(root, 'pages/ReaderPage.ets'), 'utf8');
const method = reader.slice(reader.indexOf('  private async switchToComic()'), reader.indexOf('  private async addBookmark()'));
const shelf = fs.readFileSync(path.join(root, 'pages/FavoritePage.ets'), 'utf8');
const keys = [...shelf.matchAll(/\(book: Book\) => (JSON\.stringify\(\[book\.id,[\s\S]*?\]\))/g)];
assert.equal(keys.length, 2, 'exercise both shelf layouts');
for (const key of keys) {
  const scope = {};
  vm.runInNewContext(ts.transpileModule(`globalThis.key = function(book) { return ${key[1]}; };`, {}).outputText, scope);
  const owner = { showShelfSource: false, getChapterCount: book => book.chapterCount };
  const book = { id: 'import_comic', title: 'Book', cover: '', chapterCount: 10, contentType: 'text' };
  const before = scope.key.call(owner, book);
  assert.equal(scope.key.call(owner, { ...book, pageOffset: 5 }), before, 'progress alone keeps image nodes');
  assert.notEqual(scope.key.call(owner, { ...book, contentType: 'comic' }), before, 'type change replaces stale badge and tap closure');
}
let progressFails = false, storageFails = false, navigationFails = false, hasImages = true;
let saves = 0, navigations = 0;
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(`export class Harness { ${method} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, {
  exports: exportsObject, $r: value => value, Error,
  READER_LOG_DOMAIN: 0, READER_LOG_TAG: 'Reader', hilog: { warn() {}, error() {} },
  ComicReaderService: { cached: async () => hasImages ? [{}] : [] },
  TextReadingProgressService: { save: async () => { if (progressFails) throw Error('progress unavailable'); } },
  DataService: { switchImportedBookToComic: async id => {
    if (storageFails) throw Error('metadata unavailable'); saves++; return { id, contentType: 'comic' };
  } },
  SearchCache: { put() {} }, TextReaderRouteParams: { of: bookId => ({ bookId }) }
});
const instance = new exportsObject.Harness();
instance.book = { id: 'import_comic', chapters: [{}] };
instance.context = {}; instance.speechState = {}; instance.leaving = false;
instance.persistedPosition = () => ({ bookId: 'import_comic' });
const messages = [];
instance.showToast = message => messages.push(message);
instance.navStack = { replacePath: ({ name }) => {
  assert.equal(name, 'comicReader');
  if (navigationFails) throw Error('navigation unavailable'); navigations++;
} };
(async () => {
  progressFails = true;
  await instance.switchToComic();
  assert.equal(saves, 1); assert.equal(navigations, 1); assert.equal(messages.length, 0);
  progressFails = false; storageFails = true;
  await instance.switchToComic();
  assert.equal(messages.pop(), 'app.string.reader_switch_comic_failed');
  assert.equal(navigations, 1);
  storageFails = false; navigationFails = true;
  await instance.switchToComic();
  assert.equal(messages.pop(), 'app.string.reader_switch_comic_open_failed');
  navigationFails = false; hasImages = false;
  await instance.switchToComic();
  assert.equal(messages.pop(), 'app.string.reader_switch_comic_no_images');
  assert.equal(instance.switchingComic, false);
  console.log('PASS shelf type invalidation and reader progress/storage/navigation failure boundaries');
})().catch(error => { console.error(error); process.exitCode = 1; });
