// Verify the actual route state: coordinates, fallbacks, completion and interrupted entry.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const read = name => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', name), 'utf8');
const code = read('utils/ShelfReaderTransition.ets').replace(/^import .*;\r?\n/gm, '')
  .replace(/@ObservedV2\s*/g, '').replace(/@Trace /g, '');
const exportsObject = {};
class TextReaderRouteParams { bookId = ''; resourceIndex = -1; domPos = ''; }
class OneShotLayoutCallback { constructor(action) { this.action = action; } }
const root = { leftPx: 0, topPx: 0, widthPx: 1200, heightPx: 2400 };
const source = { leftPx: 120, topPx: 360, widthPx: 120, heightPx: 480 };
const rectangles = new Map([['cover', source], ['navigation', root], ['shelf-reader-open-surface', root]]);
vm.runInNewContext(ts.transpileModule(code, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, { exports: exportsObject, TextReaderRouteParams, OneShotLayoutCallback,
  OneShotRect: { measure: (_ui, id) => rectangles.get(id) },
  OneShotTransitionIds: { ROOT_NAVIGATION: 'navigation' },
  Curve: { FastOutSlowIn: 0, EaseInOut: 1, EaseOut: 2 } });
const { ShelfReaderRouteParams } = exportsObject;
function fixture() {
  const frames = [], finishes = [];
  const ui = { px2vp: value => value / 3,
    postFrameCallback: callback => frames.push(callback.action),
    animateTo: (options, action) => { action(); if (options.onFinish) finishes.push(options.onFinish); } };
  let ended = 0;
  const proxy = { finishTransition: () => { ended++; } };
  const route = ShelfReaderRouteParams.fromShelf('book', 'cover.jpg', '书名', 'cover', ui);
  return { route, ui, frames, finishes, proxy, ended: () => ended,
    layout: () => { while (frames.length) frames.shift()(); } };
}
const entry = fixture();
assert.ok(entry.route instanceof TextReaderRouteParams);
assert.equal(entry.route.bookId, 'book');
assert.equal(entry.route.resourceIndex, -1, 'preserve saved reading position');
assert.equal(entry.route.opening.offsetX, 40);
assert.equal(entry.route.opening.offsetY, 120);
assert.equal(entry.route.opening.zoomX, 0.1);
assert.equal(entry.route.opening.zoomY, 0.2);
const transition = entry.route.opening.navigationTransition(entry.ui);
transition.transition(entry.proxy);
assert.equal(entry.ended(), 0, 'wait for destination layout');
entry.layout();
assert.equal(entry.route.opening.coverAngle, -92);
entry.finishes.shift()();
transition.onTransitionEnd(true);
assert.equal(entry.ended(), 1);
assert.equal(entry.route.opening.active, false);
assert.equal(entry.route.opening.zoomX, 1);
assert.equal(entry.route.opening.offsetY, 0);
entry.route.opening.complete();
assert.equal(entry.ended(), 1, 'completion is idempotent');

const resized = fixture();
resized.route.opening.navigationTransition(resized.ui).transition(resized.proxy);
resized.layout();
resized.route.opening.viewportChanged();
resized.finishes.shift()();
assert.equal(resized.ended(), 1, 'resize settles navigation exactly once');
assert.equal(resized.route.opening.active, false);

const disposed = fixture();
disposed.route.opening.navigationTransition(disposed.ui).transition(disposed.proxy);
disposed.route.opening.complete();
disposed.layout();
assert.equal(disposed.finishes.length, 0, 'late layout cannot restart a disposed transition');
assert.equal(disposed.ended(), 1);

const timedOut = fixture();
const timeoutTransition = timedOut.route.opening.navigationTransition(timedOut.ui);
timeoutTransition.transition(timedOut.proxy);
timeoutTransition.onTransitionEnd(false);
timedOut.layout();
assert.equal(timedOut.route.opening.active, false);
assert.equal(timedOut.finishes.length, 0, 'navigation timeout releases animation state');

rectangles.delete('shelf-reader-open-surface');
const noTarget = fixture();
noTarget.route.opening.navigationTransition(noTarget.ui).transition(noTarget.proxy);
noTarget.layout();
assert.equal(noTarget.ended(), 1, 'missing target still opens the reader');
rectangles.delete('cover');
assert.equal(fixture().route.opening.active, false, 'missing source uses the normal route');
console.log('PASS shelf reader coordinates, saved-position defaults, completion, resize, disposal, timeout and fallback');
