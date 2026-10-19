const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const compile = source => ts.transpileModule(source.replace(/import lazy /g, 'import '), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const flush = () => new Promise(resolve => setImmediate(resolve));
function fixture() {
  const stores = new Map(), pushes = [], descriptors = new Set();
  let nextFd = 1, resolveCover = async (_c, id) => id ? `/cache/${id}.jpg` : null;
  const books = [], positions = [];
  const preferences = {
    async removePreferencesFromCache() {},
    async getPreferences(_context, { name }) {
      if (!stores.has(name)) stores.set(name, new Map());
      const data = stores.get(name);
      return {
        async get(k, fallback) { return data.get(k) ?? fallback; },
        async put(k, v) { data.set(k, v); }, async delete(k) { data.delete(k); },
        async flush() {}, async getAll() { return Object.fromEntries(data); }
      };
    }
  };
  const mocks = {
    '@kit.ArkData': { preferences },
    '@kit.FormKit': {
      formBindingData: { createFormBindingData: value => typeof value === 'string' ? JSON.parse(value) : value },
      formProvider: { async updateForm(id, data) { pushes.push({ id, data }); } }
    },
    '@kit.CoreFileKit': { fileIo: {
      OpenMode: { READ_ONLY: 0 }, async open() { const file = { fd: nextFd++ }; descriptors.add(file); return file; },
      async close(file) { descriptors.delete(file); }
    } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn() {} } },
    '../utils/PlatformCompat': { PlatformCompat: { wearable: false } },
    './WidgetUpdater': { WidgetUpdater: { resolveFormCover: (...args) => resolveCover(...args) } },
    './PreferenceService': { PreferenceService: {
      async invalidateCache() {}, async init() {}, async getImportedBooks() { return JSON.stringify(books); },
      async getCachedBooks() { return '[]'; }
    } },
    './text/TextReadingProgressService': { TextReadingProgressService: { async getAll() { return positions; } } }
  };
  const exports = {};
  vm.runInNewContext(compile(fs.readFileSync(path.join(root, 'service/ReaderWidgetService.ets'), 'utf8')), {
    exports, require: key => mocks[key] || {}, $r: key => ({ id: key })
  });
  const context = { resourceManager: { getStringSync: (id, ...args) => `${id}:${args.join('/')}` } };
  return { service: exports.ReaderWidgetService, context, pushes, descriptors, books, positions,
    setCover(fn) { resolveCover = fn; } };
}
const book = id => ({ id, title: `title-${id}`, author: 'author', cover: '', contentType: 'text',
  chapterCount: 2, chapters: [{ title: 'chapter one' }, { title: 'chapter two' }] });
const position = (id, index) => ({ bookId: id, resourceIndex: index, chapterTitle: `chapter-${index}` });
async function main() {
  const f = fixture();
  await f.service.refresh(f.context, 'preview');
  assert.equal(f.pushes.at(-1).data.hasBook, false);
  assert.equal(f.pushes.at(-1).data.target, 'home');
  f.books.push(book('import_old'));
  f.positions.push(position('import_old', 1));
  await f.service.refresh(f.context, 'preview');
  assert.equal(f.pushes.at(-1).data.bookId, 'import_old', 'first add restores preexisting reading history');
  await f.service.register(f.context, 'a');
  await f.service.register(f.context, 'b');
  await f.service.update(f.context, book('import_new'), position('import_new', 1));
  assert.equal(f.pushes.at(-1).data.target, 'reader');
  assert.match(f.pushes.at(-1).data.coverUri, /^memory:\/\/reader_/);
  assert.match(f.pushes.at(-1).data.progressLabel, /reader_card_progress:50$/);
  assert.deepEqual(f.pushes.slice(-2).map(item => item.id), ['a', 'b']);
  let count = f.pushes.length;
  await f.service.update(f.context, book('import_new'), position('import_new', 1));
  assert.equal(f.pushes.length, count, 'same chapter does not redraw the desktop on every page turn');
  await f.service.update(f.context, { ...book('comic'), contentType: 'comic' }, position('comic', 0));
  assert.equal(f.pushes.at(-1).data.target, 'comicReader');
  const pending = [];
  f.setCover((_c, id) => new Promise(resolve => pending.push({ id, resolve })));
  const first = f.service.update(f.context, book('slow'), position('slow', 0));
  await flush();
  const second = f.service.update(f.context, book('latest'), position('latest', 1));
  count = f.pushes.length;
  pending[0].resolve('/old.jpg');
  await flush();
  assert.equal(f.pushes.length, count, 'late old cover cannot publish an older book');
  pending[1].resolve('/new.jpg');
  await Promise.all([first, second]);
  assert.equal(f.pushes.at(-1).data.bookId, 'latest');
  assert.equal(f.descriptors.size, 0);
  await f.service.register(f.context, 'a', true);
  f.setCover(async () => null);
  await f.service.update(f.context, book('last'), position('last', 0));
  assert.equal(f.pushes.at(-1).id, 'b', 'removed card stops receiving updates');
  assert.equal((await f.service.latest(f.context)).bookId, 'last');
  console.log('PASS reader card empty state, first-add restoration, chapter sync, multiple cards, stale covers and FD cleanup');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
