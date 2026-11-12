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
function fixture(bookId = 'book', cover = 'cover.jpg', author = '') {
  const frames = [], finishes = [];
  const ui = { px2vp: value => value / 3,
    postFrameCallback: callback => frames.push(callback.action),
    animateTo: (options, action) => { action(); if (options.onFinish) finishes.push(options.onFinish); } };
  let ended = 0;
  const proxy = { finishTransition: () => { ended++; } };
  const route = ShelfReaderRouteParams.fromShelf(bookId, cover, '书名', 'cover', ui, author);
  return { route, ui, frames, finishes, proxy, ended: () => ended,
    layout: () => { while (frames.length) frames.shift()(); } };
}
const entry = fixture();
assert.ok(entry.route instanceof TextReaderRouteParams);
assert.equal(entry.route.bookId, 'book');
assert.equal(entry.route.opening.localPlaceholder, false);
const localBook = fixture('import_local', '', '本地作者');
assert.equal(localBook.route.opening.localPlaceholder, true, 'local book uses the shelf default cover');
assert.equal(localBook.route.opening.author, '本地作者', 'default cover retains the shelf author');
assert.equal(localBook.route.opening.title, '书名');
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
disposed.route.opening.dispose();
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

const movedSource = { leftPx: 240, topPx: 600, widthPx: 180, heightPx: 360 };
const returning = entry.route.opening.navigationTransition(entry.ui, false);
returning.transition(entry.proxy);
assert.equal(entry.route.opening.active, true);
assert.equal(entry.route.opening.bodyAlpha, 1, 'return starts from the visible reader');
assert.equal(entry.route.opening.coverAngle, -92, 'close starts with the cover open');
entry.layout();
assert.equal(entry.route.opening.coverAngle, 0);
assert.equal(entry.route.opening.offsetX, 0, 'cover closes at full size before returning to the shelf');
assert.equal(entry.route.opening.zoomX, 1);
assert.equal(entry.route.opening.bodyAlpha, 1, 'reader stays visible until the cover fully closes');
rectangles.set('cover', movedSource);
entry.finishes.shift()();
assert.equal(entry.route.opening.offsetX, 80, 'return measures the current shelf position');
assert.equal(entry.route.opening.offsetY, 200);
assert.equal(entry.route.opening.zoomX, 0.15);
assert.equal(entry.route.opening.zoomY, 0.15);
assert.equal(entry.route.opening.bodyAlpha, 0);
entry.finishes.shift()();
returning.onTransitionEnd(true);
assert.equal(entry.ended(), 2);
assert.equal(entry.route.opening.bodyAlpha, 0, 'closed reader cannot flash over the shelf');

const cancelledReturn = fixture();
const cancelledTransition = cancelledReturn.route.opening.navigationTransition(cancelledReturn.ui, false);
cancelledTransition.transition(cancelledReturn.proxy);
cancelledReturn.layout();
cancelledTransition.onTransitionEnd(false);
cancelledReturn.finishes.shift()();
assert.equal(cancelledReturn.route.opening.bodyAlpha, 1, 'cancel restores readable content');
assert.equal(cancelledReturn.ended(), 0, 'late callback cannot complete a cancelled navigation');

const superseded = fixture();
const oldOpening = superseded.route.opening.navigationTransition(superseded.ui);
oldOpening.transition(superseded.proxy);
superseded.layout();
const newClosing = superseded.route.opening.navigationTransition(superseded.ui, false);
newClosing.transition(superseded.proxy);
oldOpening.onTransitionEnd(true);
superseded.finishes.shift()();
assert.equal(superseded.ended(), 0, 'old opening completion cannot finish the new return');
superseded.layout();
superseded.finishes.shift()();
superseded.finishes.shift()();
newClosing.onTransitionEnd(true);
assert.equal(superseded.ended(), 1);

rectangles.set('cover', { ...source, topPx: root.heightPx + 20 });
const offscreen = fixture();
offscreen.route.opening.navigationTransition(offscreen.ui, false).transition(offscreen.proxy);
offscreen.layout();
assert.equal(offscreen.route.opening.zoomX, 1, 'offscreen target still closes the cover at full size');
assert.equal(offscreen.route.opening.bodyAlpha, 1, 'offscreen fallback also covers the reader first');
offscreen.finishes.shift()();
assert.equal(offscreen.route.opening.zoomX, 1, 'offscreen target never starts a return shrink');
offscreen.finishes.shift()();
assert.equal(offscreen.ended(), 1, 'offscreen target fades out and completes');
rectangles.set('cover', source);

rectangles.delete('shelf-reader-open-surface');
const noTarget = fixture();
noTarget.route.opening.navigationTransition(noTarget.ui).transition(noTarget.proxy);
noTarget.layout();
assert.equal(noTarget.ended(), 1, 'missing target still opens the reader');
rectangles.delete('cover');
assert.equal(fixture().route.opening.active, false, 'missing source uses the normal route');
const missingReturn = fixture();
missingReturn.route.opening.navigationTransition(missingReturn.ui, false).transition(missingReturn.proxy);
missingReturn.layout();
missingReturn.finishes.shift()();
missingReturn.finishes.shift()();
assert.equal(missingReturn.ended(), 1, 'missing return target still leaves the reader');
console.log('PASS shelf reader open/close, fresh return geometry, saved position, cancellation, stale callbacks, resize and fallback');
