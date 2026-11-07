// Exercise the real EPUB bridge and viewport script, including delayed native completion.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '..');
const script = fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/epub_original.js'), 'utf8');
const lightExports = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,
  'entry/src/main/ets/service/text/light/EpubOriginalScript.ets'), 'utf8'), { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
} }).outputText, { exports: lightExports, require: () => ({ EpubOriginalInjection: class { style = ''; script = ''; } }) });
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/components/EpubOriginalReader.ets'), 'utf8');
const component = source.slice(0, source.indexOf('  build() {')) + '}';
const sourceClasses = component.replace(/^import .*;\r?\n/gm, '').replace('@ComponentV2', '')
  .replace('export struct ', 'export class ').replace(/@(Param|Event|Local) /g, '')
  .replace(/  @Monitor\([^\n]*\)\r?\n/g, '');
class Spot { snippet = ''; fraction = 0; page = 0; count = 1; end = false; }
let reader, browser, delivered = [], events, chapterLoads = [];
function viewport(code) {
  events = {};
  const style = { setProperty(name, value) { this[name] = value; } };
  const document = { readyState: 'complete', fonts: { ready: Promise.resolve() },
    body: { style }, documentElement: { style, scrollWidth: 390 * 5, scrollHeight: 760 },
    head: { appendChild() {} }, getElementById: () => null,
    createElement: () => ({}), createTreeWalker: () => ({ nextNode: () => null }),
    addEventListener: (name, fn) => { events[name] = fn; }
  };
  browser = vm.createContext({ document, NodeFilter: { SHOW_TEXT: 4 }, innerWidth: 390, innerHeight: 760,
    scrollX: 0, scrollY: 0, setTimeout, clearTimeout, getSelection: () => '',
    getComputedStyle: () => ({}), requestAnimationFrame: fn => setImmediate(fn), cancelAnimationFrame: clearImmediate,
    addEventListener: (name, fn) => { events[name] = fn; },
    epubHost: { report(value) { setImmediate(() => reader.message(value)); } }
  });
  browser.window = browser;
  browser.scrollTo = (x, y) => { browser.scrollX = x; browser.scrollY = y; };
  browser.scrollBy = (x, y) => browser.scrollTo(browser.scrollX + x, browser.scrollY + y);
  vm.runInContext(code, browser);
}
class Controller {
  loadUrl() { chapterLoads.push(reader.active.chapter); viewport(reader.document); }
  async runJavaScript(code) { return JSON.stringify(vm.runInContext(code, browser)) ?? ''; }
}
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(sourceClasses, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
} }).outputText, { exports: exportsObject, setTimeout, clearTimeout,
  webview: { WebviewController: Controller }, EpubOriginalSpot: Spot,
  EpubOriginalLayoutOptions: lightExports.EpubOriginalLayoutOptions,
  EpubOriginalScript: lightExports.EpubOriginalScript,
  ReaderTapPolicy: { DEFAULT: '', resolve: () => 0 },
  EpubOriginalPosition: {
    spot: (text, offset) => Object.assign(new Spot(), { fraction: offset / Math.max(1, text.length) }),
    offset: (text, spot) => Math.round(text.length * spot.fraction)
  },
  EpubOriginalStore: { parts: async () => [{ spine: 0, offset: 0, length: 100 }] },
  EpubOriginalDocument: { ORIGIN: 'https://test.invalid/', build: (_source, _part, code) => code },
  fileIo: { readText: async () => '' }, util: { generateRandomUUID: () => 'test' },
  hilog: { debug() {}, error() {} }
});
const { EpubOriginalReader, EpubOriginalRequest } = exportsObject;
function request(chapter) { return Object.assign(new EpubOriginalRequest(), { root: '/book', chapter, text: 'a'.repeat(100) }); }
async function tick() { await new Promise(resolve => setImmediate(resolve)); }
(async () => {
  reader = new EpubOriginalReader();
  Object.assign(reader, { alive: true, attached: true, initialPageReady: true, script, request: request(0),
    onPosition: (chapter, offset, page, count) => delivered.push({ chapter, offset, page, count }),
    onChapter: value => { reader.request = value; },
    adjacent: async forward => request(reader.active.chapter + (forward ? 1 : -1)),
    onFailure: () => { throw Error('unexpected viewport failure'); }
  });
  await reader.load(); await tick();
  for (let page = 1; page <= 4; page++) {
    const before = delivered.length;
    assert.equal(await reader.prepare(true), true);
    assert.equal(delivered.length, before, 'preview must not persist progress');
    // A Web click synthesized at the left edge after a native swipe must not turn backwards.
    let prevented = false;
    events.click({ clientX: 8, clientY: 200, preventDefault() { prevented = true; } });
    assert.equal(prevented, true);
    assert.equal(browser.scrollX, 390 * page, 'upstream pages scroll by exactly one viewport');
    assert.equal(browser.document.body.style.transform, undefined, 'fixed backgrounds must keep the viewport as their containing block');
    await reader.complete(true);
    assert.equal(delivered.at(-1).page, page, 'consecutive left swipes advance monotonically');
  }
  const beforeEdge = delivered.length;
  assert.equal(await reader.prepare(true), true);
  assert.equal(reader.active.chapter, 1);
  assert.equal(delivered.length, beforeEdge, 'loading a chapter is still only a preview');
  await reader.complete(false);
  assert.deepEqual([delivered.at(-1).chapter, delivered.at(-1).page], [0, 4], 'cross-chapter rollback restores the exact page');
  assert.equal(await reader.prepare(true), true);
  await reader.complete(true);
  assert.deepEqual([delivered.at(-1).chapter, delivered.at(-1).page], [1, 0]);
  assert.equal(await reader.prepare(false), true);
  await reader.complete(true);
  assert.deepEqual([delivered.at(-1).chapter, delivered.at(-1).page], [0, 4], 'reverse edge opens the previous chapter at its end');
  assert.equal(await reader.prepare(false), true);
  await reader.complete(false);
  assert.equal(delivered.at(-1).page, 4, 'short/cancelled swipe must restore the current page');
  for (let page = 3; page >= 0; page--) {
    assert.equal(await reader.prepare(false), true); await reader.complete(true);
    assert.equal(delivered.at(-1).page, page);
  }
  // Abort while the asynchronous position capture is still outstanding.
  const readSpot = reader.readSpot.bind(reader);
  let release;
  reader.readSpot = () => new Promise(resolve => { release = resolve; });
  const pending = reader.prepare(true);
  const cancelling = reader.complete(false);
  release(await readSpot());
  assert.equal(await pending, false);
  await cancelling;
  assert.equal(delivered.at(-1).page, 0);
  reader.readSpot = readSpot;
  reader.alive = false; reader.finishPaint(false);
  console.log('EPUB native swipe, synthetic click, preview/commit, chapter edges and cancellation passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
