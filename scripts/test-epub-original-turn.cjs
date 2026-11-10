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
const positionExports = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,
  'entry/src/main/ets/service/text/EpubOriginalPosition.ets'), 'utf8'), { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
} }).outputText, { exports: positionExports, require: () => ({ LocalTextImage: { speechContent: text => text } }) });
const indexedText = ' 开头。\n重复句子 重复句子\n结尾¹。';
const indexed = new positionExports.EpubOriginalPositionIndex(indexedText);
for (const offset of [0, 4, 10, 17, indexedText.length]) {
  const spot = positionExports.EpubOriginalPosition.spot(indexedText, offset);
  const restored = indexed.offset(spot);
  assert.equal(positionExports.EpubOriginalPosition.compact(indexedText.slice(restored, restored + 32)).startsWith(spot.snippet), true);
}
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
let reader, browser, delivered = [], events, chapterLoads = [], delayReady = false, pendingReady = [];
function viewport(code) {
  events = {};
  const style = { setProperty(name, value) { this[name] = value; } };
  const document = { readyState: 'complete', fonts: { ready: Promise.resolve() },
    body: { style, querySelectorAll: () => [] },
    documentElement: { style, scrollWidth: 390 * 5, scrollHeight: 760, appendChild() {} },
    head: { appendChild() {} }, getElementById: () => null, querySelectorAll: () => [],
    createElement: () => ({ style: { setProperty() {} }, setAttribute() {} }),
    createTreeWalker: () => ({ nextNode: () => null }),
    addEventListener: (name, fn) => { events[name] = fn; }
  };
  browser = vm.createContext({ document, NodeFilter: { SHOW_TEXT: 4 }, innerWidth: 390, innerHeight: 760,
    scrollX: 0, scrollY: 0, setTimeout, clearTimeout, getSelection: () => '',
    getComputedStyle: () => ({ getPropertyValue: () => '' }),
    requestAnimationFrame: fn => setImmediate(fn), cancelAnimationFrame: clearImmediate,
    addEventListener: (name, fn) => { events[name] = fn; },
    epubHost: { report(value) {
      if (delayReady && JSON.parse(value).kind === 'ready') pendingReady.push(value);
      else setImmediate(() => reader.message(value));
    } }
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
const originalStore = { parts: async () => [{ spine: 0, offset: 0, length: 100 }] };
vm.runInNewContext(ts.transpileModule(sourceClasses, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
} }).outputText, { exports: exportsObject, setTimeout, clearTimeout,
  webview: { WebviewController: Controller }, EpubOriginalSpot: Spot,
  ReaderCommentMessages: class { items = []; empty = false; },
  EpubOriginalPositionIndex: positionExports.EpubOriginalPositionIndex,
  EpubOriginalLayoutOptions: lightExports.EpubOriginalLayoutOptions,
  EpubOriginalScript: lightExports.EpubOriginalScript,
  ReaderTapPolicy: { DEFAULT: '', resolve: () => 0 },
  EpubOriginalPosition: {
    spot: (text, offset) => Object.assign(new Spot(), { fraction: offset / Math.max(1, text.length) }),
    offset: (text, spot) => Math.round(text.length * spot.fraction)
  },
  EpubOriginalStore: originalStore,
  EpubOriginalDocument: { ORIGIN: 'https://test.invalid/', assetPath: value => value || '', build: (_source, _part, code) => code },
  fileIo: { readText: async () => '' }, util: { generateRandomUUID: () => 'test' },
  hilog: { debug() {}, error() {} }
});
const { EpubOriginalReader, EpubOriginalRequest } = exportsObject;
function request(chapter) { return Object.assign(new EpubOriginalRequest(), { root: '/book', chapter, text: 'a'.repeat(100) }); }
async function tick() { await new Promise(resolve => setImmediate(resolve)); }
async function settled(condition) {
  const deadline = Date.now() + 2000;
  while (!condition()) {
    assert.ok(Date.now() < deadline, 'EPUB layout did not settle');
    await new Promise(resolve => setTimeout(resolve, 10));
  }
}
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
  // Chrome/safe-area changes must reflow at the current character, not request.offset or an old page number.
  await reader.seek(63);
  const currentFraction = browser.hsdaEpub.spot().fraction;
  reader.insetTop = 56; reader.insetBottom = 48; reader.insetsChanged();
  await settled(() => !reader.layoutUpdating && reader.layoutInsets === reader.insetKey());
  assert.equal(browser.hsdaEpubConfig.spot.fraction, currentFraction);
  assert.equal(browser.hsdaEpubConfig.restorePage, -1, 'new geometry restores characters, not old page indices');
  assert.equal(browser.hsdaEpub.spot().page, 3, 'inset updates must not jump to the original request offset');

  const beforePreviewReflow = chapterLoads.length;
  assert.equal(await reader.prepare(true), true);
  reader.insetTop = 72; reader.insetsChanged();
  await reader.refreshLayout();
  assert.equal(chapterLoads.length, beforePreviewReflow, 'layout changes wait for a preview to finish');
  await reader.complete(false);
  await settled(() => !reader.layoutUpdating && reader.layoutInsets === reader.insetKey());
  assert.equal(browser.hsdaEpub.spot().fraction, currentFraction, 'cancelled preview retains its confirmed character');

  // Insets changed after document construction are applied once the outstanding paint completes.
  delayReady = true;
  const repaint = reader.loadPart(reader.partIndex, 0, false, await reader.readSpot(), false);
  await settled(() => pendingReady.length > 0);
  reader.insetBottom = 80; reader.insetsChanged();
  await reader.refreshLayout();
  assert.equal(reader.loading, true);
  delayReady = false;
  pendingReady.splice(0).forEach(value => reader.message(value));
  await repaint;
  await settled(() => !reader.layoutUpdating && reader.layoutInsets === reader.insetKey());
  assert.equal(browser.hsdaEpub.spot().fraction, currentFraction);
  assert.match(reader.document, /"bottom":80/, 'the final page uses the latest insets');

  // Continuous prefetch is relative to the buffered boundary, not the visible chapter.
  const continuous = new EpubOriginalReader();
  const commands = [], adjacentCalls = [];
  Object.assign(continuous, { alive: true, attached: true, paged: false, active: request(3), serial: 20,
    controller: { runJavaScript: async code => { commands.push(code); return ''; } },
    adjacent: async (forward, chapter, notify) => {
      adjacentCalls.push({ forward, chapter, notify }); return request(chapter + (forward ? 1 : -1));
    },
    onChapter: value => { continuous.request = value; },
    onPosition: (chapter, offset) => delivered.push({ chapter, offset })
  });
  let frameId = 100;
  continuous.continuousFrame = async (value, parts, index) =>
    ({ id: ++frameId, request: value, parts, index, url: `/frame/${frameId}` });
  const boundary = { id: 5, request: request(5), parts: await originalStore.parts(), index: 0 };
  continuous.frames = [boundary];
  await continuous.extendContinuous(5, true);
  assert.deepEqual(adjacentCalls, [{ forward: true, chapter: 5, notify: false }]);
  assert.equal(continuous.active.chapter, 3, 'prefetch does not commit reading progress');
  assert.match(commands.at(-1), /\.append\(/);
  const next = continuous.frames.at(-1);
  continuous.message(JSON.stringify({ kind: 'position', token: 20, frame: next.id,
    snippet: '', fraction: 0.25, page: 1, count: 3 }));
  assert.equal(continuous.request.chapter, 6);
  assert.deepEqual(delivered.at(-1), { chapter: 6, offset: 25 }, 'visible frame commits chapter before position');
  continuous.requestChanged();
  assert.equal(continuous.serial, 20, 'committing a buffered chapter must not reload the Web document');

  const reflow = new EpubOriginalReader();
  const restoredFrames = [];
  Object.assign(reflow, { alive: true, attached: true, initialPageReady: true, loading: false, paged: false,
    active: request(3), parts: await originalStore.parts(), frames: [next], activeFrame: 0,
    insetTop: 60, insetBottom: 40, layoutInsets: 'old',
    controller: { runJavaScript: async () => JSON.stringify({ kind: 'position', frame: next.id,
      snippet: 'same visible line', fraction: 0.65, page: 2, count: 4 }) },
    onChapter: value => { reflow.request = value; },
    loadPart: async (index, offset, end, spot, restorePage) => {
      restoredFrames.push({ chapter: reflow.active.chapter, index, spot, restorePage });
      reflow.layoutInsets = reflow.insetKey();
    }
  });
  await reflow.refreshLayout();
  assert.equal(restoredFrames[0].chapter, 6, 'continuous reflow selects the visible frame before rebuilding');
  assert.equal(restoredFrames[0].spot.fraction, 0.65);
  assert.equal(restoredFrames[0].spot.snippet, 'same visible line');
  assert.equal(restoredFrames[0].restorePage, false);
  reflow.alive = false;

  continuous.adjacent = async () => null;
  await continuous.extendContinuous(next.id, true);
  assert.match(commands.at(-1), /\.finish\(1,false\)/, 'book end silently completes prefetch');
  const multiple = { id: 9, request: request(7), index: 0, parts: [
    { spine: 0, offset: 0, length: 50 }, { spine: 1, offset: 50, length: 50 }
  ] };
  continuous.frames = [multiple];
  await continuous.extendContinuous(9, true);
  assert.equal(continuous.frames.at(-1).index, 1, 'same-chapter spine parts are appended before the next chapter');
  assert.equal(continuous.frames.at(-1).request.chapter, 7);
  let finishRead;
  continuous.adjacent = () => new Promise(resolve => { finishRead = resolve; });
  const stale = continuous.extendContinuous(continuous.frames.at(-1).id, true);
  continuous.serial++;
  const beforeStale = commands.length;
  finishRead(request(8));await stale;
  assert.equal(commands.length, beforeStale, 'late prefetch cannot append to a new reading session');
  continuous.alive = false;
  reader.alive = false; reader.finishPaint(false);
  console.log('EPUB native swipe, preview/commit, cancellation, inset reflow and continuous prefetch/position/session boundaries passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
