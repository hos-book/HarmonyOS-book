// Exercise actual file routing and EntryAbility delivery without starting media services.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main');
const storage = new Map();
const events = [];
const fileUri = { FileUri: class {
  constructor(uri) {
    if (uri.startsWith('content:')) throw new Error('provider URI');
    this.name = decodeURIComponent(new URL(uri).pathname.split('/').pop());
  }
} };
function load(relative, imports) {
  const filename = path.join(root, 'ets', relative);
  const exports = {};
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, Date, AppStorage: {
    setOrCreate: (key, value) => storage.set(key, value)
  }, require: name => imports[name] || {} }, { filename });
  return exports;
}
const routingModule = load('utils/FileOpenRouting.ets', { '@kit.CoreFileKit': { fileUri } });
const routing = routingModule.FileOpenRouting;
const view = (uri, type = '') => ({ action: 'ohos.want.action.viewData', uri, type });
for (const ext of ['txt', 'epub', 'mobi', 'pdf', 'html', 'htm', 'zip']) {
  for (const scheme of ['file', 'content']) {
    assert.equal(routing.target(view(`${scheme}://provider/书籍.${ext.toUpperCase()}`)), 'localBookImport');
  }
}
for (const uri of ['file://docs/书源.JSON', 'content://provider/%E4%B9%A6%E6%BA%90%2Ejson?token=x']) {
  assert.equal(routing.target(view(uri, 'text/plain')), 'ruleSourceImport');
}
assert.equal(routing.target(view('file://docs/novel.epub', 'application/json')), 'localBookImport');
assert.equal(routing.extension('content://provider/42', 'Application/EPUB+ZIP; charset=utf-8'), '.epub');
assert.equal(routing.target(view('content://provider/42', 'general.json')), 'ruleSourceImport');
assert.equal(routing.target(view('content://provider/42', 'application/x-zip-compressed')), 'localBookImport');
assert.equal(routing.target(view('content://provider/42', 'com.amazon.mobi')), 'localBookImport');
assert.equal(routing.target(view('https://example.org/novel.epub')), '');
assert.equal(routing.target(view('file://docs/novel.pdf', 'text/plain')), 'localBookImport');
assert.equal(routing.extension('content://provider/42', 'Application/PDF; version=1.7'), '.pdf');
assert.equal(routing.target(view('content://provider/42', 'com.adobe.pdf')), 'localBookImport');
assert.equal(routing.target(view('file://docs/archive.rar', 'application/pdf')), '', 'extension takes priority over PDF MIME');
assert.equal(routing.target(view('file://docs/archive.rar')), '');
assert.equal(routing.target(view('file://docs/42', 'application/octet-stream')), '');
assert.equal(routing.target({ ...view('file://docs/novel.epub'), action: 'ohos.want.action.home' }), '');

const manifest = vm.runInNewContext('(' + fs.readFileSync(path.join(root, 'module.json5'), 'utf8') + ')');
const skill = manifest.module.abilities.find(a => a.name === 'EntryAbility').skills
  .find(s => s.actions.includes('ohos.want.action.viewData'));
assert.ok(skill.uris.every(u => u.linkFeature === 'FileOpen'));
for (const entry of skill.uris) {
  assert.ok(routing.target(view(`${entry.scheme}://provider/42`, entry.type)),
    `Registered file type must have a working route: ${entry.type}`);
}
for (const type of ['general.json', 'general.plain-text', 'general.epub', 'com.adobe.pdf', 'application/pdf', 'com.amazon.mobi', 'general.html', 'general.zip-archive']) {
  assert.ok(skill.uris.some(u => u.type === type && u.scheme === 'file'));
}

const entryModule = load('entryability/EntryAbility.ets', {
  '../utils/FileOpenRouting': routingModule,
  '../utils/PlatformCompat': { PlatformCompat: { wearable: false } },
  '@kit.AbilityKit': { UIAbility: class {} },
  '@kit.BasicServicesKit': { emitter: { emit: (event, payload) => events.push({ event, payload }) } }
});
const entry = new entryModule.default();
const uri = 'content://provider/42';
entry.consumeRouteWant(view(uri, 'application/epub+zip'));
const pending = storage.get(entryModule.KEY_WIDGET_ROUTE);
assert.equal(pending.target, 'localBookImport');
assert.equal(pending.bookId, uri, 'preserve original permission-bearing URI');
assert.equal(pending.fileType, 'application/epub+zip', 'carry type when provider URI has no extension');
assert.equal(events[0].payload.data.ts, pending.ts, 'cold/hot deliveries share a deduplication token');
assert.equal(events[0].payload.data.fileType, pending.fileType);
assert.equal(entry.startupPlaybackPending, false, 'file open must not auto-play an unrelated book');
entry.captureContinuation = () => {};
entry.restoreContinuationIfNeeded = async () => {};
entry.onNewWant(view('file://docs/source.json', 'general.json'), {});
assert.equal(storage.get(entryModule.KEY_WIDGET_ROUTE).target, 'ruleSourceImport');
entry.onNewWant(view('file://docs/books.zip', 'general.zip-archive'), {});
assert.equal(storage.get(entryModule.KEY_WIDGET_ROUTE).target, 'localBookImport');
entry.onNewWant(view('content://provider/pdf-file', 'application/pdf'), {});
assert.equal(storage.get(entryModule.KEY_WIDGET_ROUTE).bookId, 'content://provider/pdf-file');
assert.equal(storage.get(entryModule.KEY_WIDGET_ROUTE).fileType, 'application/pdf');
console.log('PASS file open: supported formats, JSON priority, MIME/UTD fallback, manifest registration, cold/hot route delivery');
