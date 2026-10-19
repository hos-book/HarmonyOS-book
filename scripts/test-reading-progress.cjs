// Real progress service and shelf refresh method with simulated HarmonyOS preferences/events.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed DevEco Studio');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const values = new Map();
const events = new EventEmitter();
const preferences = { getPreferences: async () => ({
  getSync: (key, fallback) => values.has(key) ? values.get(key) : fallback,
  putSync: (key, value) => values.set(key, value),
  deleteSync: key => values.delete(key),
  getAll: async () => Object.fromEntries(values),
  flush: async () => {}
}) };
const cache = new Map();
function compile(source) {
  return ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
}
function load(relative) {
  const filename = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
  if (cache.has(filename)) return cache.get(filename);
  const exports = {};
  cache.set(filename, exports);
  vm.runInNewContext(compile(fs.readFileSync(filename, 'utf8').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '')), {
    exports, require: name => {
      if (name === '@kit.ArkData') return { preferences };
      if (name === '@kit.BasicServicesKit') return { emitter: events };
      if (name.startsWith('@')) return {};
      return load(path.resolve(path.dirname(filename), name));
    }
  }, { filename });
  return exports;
}
(async () => {
  const { TextReadingPosition } = load('model/TextReading');
  const { TextReadingProgressService: service, EVT_TEXT_READING_PROGRESS_CHANGED: event } =
    load('service/text/TextReadingProgressService');
  const source = fs.readFileSync(path.join(root, 'pages/FavoritePage.ets'), 'utf8');
  const method = source.slice(source.indexOf('  private async refreshTextProgress()'),
    source.indexOf('  private createMissingFavoriteBook('));
  const exports = {};
  vm.runInNewContext(compile(`export class Shelf { ${method} }`), {
    exports, TextReadingProgressService: service
  });
  const shelf = new exports.Shelf();
  shelf.context = {};
  shelf.favoriteBooks = [{ id: 'novel', contentType: 'text' }, { id: 'audio', contentType: 'audio' }];
  shelf.textProgressLoadSerial = 0;
  shelf.textProgressMap = new Map();
  let pending;
  events.on(event, () => { pending = shelf.refreshTextProgress(); });
  for (const chapter of [0, 419, 430, 12]) {
    await service.save({}, TextReadingPosition.atChar('novel', chapter, '', 123, 0, `Chapter ${chapter + 1}`));
    await pending;
    assert.equal(shelf.textProgressMap.get('novel').resourceIndex, chapter);
    assert.equal(shelf.textProgressMap.get('novel').charOffset, 123);
  }
  assert.equal(shelf.textProgressMap.has('audio'), false);
  const originalGet = service.get;
  const reads = [];
  service.get = () => new Promise(resolve => reads.push(resolve));
  const older = shelf.refreshTextProgress();
  const newer = shelf.refreshTextProgress();
  reads[1](TextReadingPosition.atChar('novel', 450, '', 99, 0, 'Chapter 451'));
  await newer;
  reads[0](TextReadingPosition.atChar('novel', 419, '', 0, 0, 'Chapter 420'));
  await older;
  assert.equal(shelf.textProgressMap.get('novel').resourceIndex, 450);
  service.get = originalGet;
  await service.remove({}, 'novel');
  await pending;
  assert.equal(shelf.textProgressMap.has('novel'), false);
  const settings = load('model/GeneralSettings').GeneralSettings.current;
  await service.save({}, TextReadingPosition.atChar('history-fixture', 1, '', 10, 0, 'Before'));
  settings.historyEnabled = false;
  await service.save({}, TextReadingPosition.atChar('history-fixture', 2, '', 25, 0, 'Disabled'));
  assert.equal((await service.get({}, 'history-fixture')).charOffset, 25, 'resume keeps moving');
  assert.equal((await service.getAll({}, true)).find(p => p.bookId === 'history-fixture').charOffset, 10, 'history is frozen while disabled');
  settings.historyEnabled = true;
  await service.save({}, TextReadingPosition.atChar('history-fixture', 3, '', 40, 0, 'Enabled'));
  assert.equal((await service.getAll({}, true)).find(p => p.bookId === 'history-fixture').charOffset, 40);
  await service.remove({}, 'history-fixture');
  assert.equal((await service.getAll({}, true)).length, 0, 'deletion removes both snapshots');
  console.log('PASS history toggle freezes history independently of resume positions');
  console.log('PASS: shelf follows chapter 420+, backward jumps, character offsets, deletion, and out-of-order refreshes');
})().catch(error => { console.error(error); process.exitCode = 1; });
