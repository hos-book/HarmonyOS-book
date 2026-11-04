// DEVECO_HOME=<Release IDE> node scripts/test-player-transition.cjs
// Executes the real transition coordinator with a simulated Navigation proxy and touch queue.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
if (!process.env.DEVECO_HOME) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/utils/PlayerDragTransition.ets'), 'utf8');
const timers = [];
let released = 0;
const rects = new Map();
const mod = { exports: {} };
const code = ts.transpileModule(source.replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, ''), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
vm.runInNewContext(code, {
  module: mod, exports: mod.exports, console,
  setTimeout: fn => timers.push(fn),
  require: id => id === './WindowUtils' ? {
    WindowUtils: { pxToVp: value => value / 2, vpToPx: value => value * 2 }
  } : {
    OneShotTransitionCoordinator: { releaseSnapshot: value => { if (value) released++; } },
    OneShotRect: { measure: (_ui, id) => rects.get(id) },
    OneShotTransitionIds: { ROOT_NAVIGATION: 'root' }
  }
});
const { PlayerDragTransition, PlayerDragOrigin } = mod.exports;
const drag = PlayerDragTransition.getInstance();
function origin() {
  return Object.assign(new PlayerDragOrigin(), {
    left: 16, top: 700, width: 368, height: 60, radius: 30,
    coverLeft: 24, coverTop: 708, coverWidth: 44, coverHeight: 44,
    viewportWidth: 400, viewportHeight: 800, snapshot: {}
  });
}
let opened = 0;
const open = () => { opened++; assert.equal(drag.beginTap(origin()), true); };
const flush = () => { while (timers.length) timers.shift()(); };
const resetCheck = () => {
  assert.equal(drag.state.active, false);
  assert.equal(drag.state.sourceOpacity, 1);
  assert.equal(drag.state.contentOpacity, 1);
  assert.equal(drag.state.snapshot, undefined);
};
assert.equal(drag.beginTap(origin()), true);
drag.complete(); resetCheck();
drag.beginGesture(800, -8, open);
assert.equal(drag.state.active, false, 'a pending gesture must not start a Navigation transition');
drag.end(-20, 0); resetCheck(); assert.equal(opened, 0);
drag.beginGesture(800, -8, open);
drag.releaseTouch(false); drag.end(-30, -1000); flush();
assert.equal(opened, 1, 'normal fling wins over the raw touch fallback');
drag.complete(); resetCheck();
drag.beginGesture(800, -200, open); drag.releaseTouch(false); flush();
assert.equal(opened, 2, 'missing pan end must commit a completed upward drag');
drag.complete(); resetCheck();
drag.beginGesture(800, -200, open); drag.releaseTouch(true); flush();
resetCheck(); assert.equal(opened, 2, 'system interruption cancels without touching Navigation');
drag.beginGesture(800, -200, open); drag.releaseTouch(false);
drag.cancel(); drag.beginGesture(800, -8, open); flush();
assert.equal(opened, 2, 'old callback must not commit a newer gesture');
drag.update(-200); drag.end(-200, 0);
assert.equal(opened, 3, 'new gesture remains usable after stale callback');
drag.complete(); resetCheck(); assert.equal(released, 4);
console.log('PASS tap, short drag without routing, fling, lost end, system cancel, stale callback and cleanup');
// Dual-row bars use a capped gesture reference height instead of the full window height.
const beforeDualRow = opened;
drag.beginGesture(320, -8, open); drag.end(-32, 0);
resetCheck(); assert.equal(opened, beforeDualRow, 'small movements still cancel');
drag.beginGesture(320, -8, open); drag.end(-60, 0);
assert.equal(opened, beforeDualRow + 1, 'an ordinary slow upward drag opens the dual-row player');
drag.complete(); resetCheck();
drag.beginGesture(320, -8, open); drag.update(-70); drag.update(-16); drag.end(-16, 0);
assert.equal(opened, beforeDualRow + 1, 'dragging back cancels before routing');
drag.beginGesture(320, -8, open); drag.update(-60); drag.releaseTouch(false); flush();
assert.equal(opened, beforeDualRow + 2, 'isolated mini-bar touch fallback commits without a root touch');
drag.complete(); resetCheck();
console.log('PASS dual-row slow drag, small movement, drag-back and local touch fallback');
const rect = (leftPx, topPx, widthPx, heightPx) => ({
  leftPx, topPx, widthPx, heightPx, isValid: () => true
});
rects.set('root', rect(0, 40, 800, 1600));
rects.set('shelf-grid-book-a', rect(32, 240, 224, 300));
rects.set('player-drag-surface', rect(0, 40, 800, 1600));
rects.set('player-page-cover', rect(48, 200, 704, 704));
const snapshots = [];
const ui = {
  px2vp: value => value / 2,
  getComponentSnapshot: () => ({ getSync: id => { snapshots.push(id); return {}; } })
};
PlayerDragTransition.measure = (_ui, id) => rects.get(id);
const shelf = drag.captureCover(ui, 'shelf-grid-book-a', 5);
assert.equal(shelf.left, 16);
assert.equal(shelf.top, 100);
assert.equal(drag.beginTap(shelf), true);
assert.equal(drag.state.frameX, 16);
assert.equal(drag.state.frameY, 100);
assert.equal(drag.state.radius, 5, 'shelf must retain cover corners, not mini-bar capsule corners');
drag.complete();
rects.set('shelf-grid-book-a', rect(32, 280, 224, 300));
const returning = drag.prepareReturn(ui);
assert.equal(returning.top, 120, 'return remeasures the clicked shelf cover');
drag.collapseToBar(returning);
assert.equal(drag.state.frameY, 120);
assert.equal(drag.state.sourceNodeId, 'shelf-grid-book-a');
assert.deepEqual(snapshots, ['shelf-grid-book-a', 'player-page-cover']);
drag.complete(); drag.clearReturnTarget();
assert.equal(drag.beginTap(origin()), true);
assert.equal(drag.state.sourceNodeId, 'mini-player-bar', 'mini player must not reuse the last shelf target');
drag.complete();
console.log('PASS shelf capture, live return coordinates, cover radius and independent mini-player origin');

rects.set('detail-cover-book-a', rect(40, 260, 240, 320));
const detail = drag.captureCover(ui, 'detail-cover-book-a', 8);
assert.equal(drag.beginTap(detail, 'detail'), true);
assert.equal(drag.canReturnTo('detail'), true, 'nested detail remains the return destination');
assert.equal(drag.canReturnTo('search'), false, 'a different destination must not reuse the detail origin');
drag.complete();
assert.equal(drag.canReturnTo('detail'), true, 'finishing entry retains the return destination');
rects.set('detail-cover-book-a', rect(40, 300, 240, 320));
const detailReturn = drag.prepareReturn(ui);
assert.equal(detailReturn.top, 130, 'return measures the current detail cover position');
drag.collapseToBar(detailReturn);
assert.equal(drag.state.radius, 8);
assert.equal(drag.state.sourceNodeId, 'detail-cover-book-a');
drag.complete(); drag.clearReturnTarget();
assert.equal(drag.canReturnTo('detail'), false, 'completed return releases the destination');
assert.equal(drag.beginTap(detail, 'detail'), true);
drag.complete();
assert.equal(drag.beginTap(origin()), true);
assert.equal(drag.canReturnTo('detail'), false, 'later mini-player entry clears the previous detail destination');
drag.complete(); drag.clearReturnTarget();
console.log('PASS nested detail entry, return coordinates, destination matching and cleanup');

let previewOpened = 0;
let finishCancel;
const cancelPreview = done => { drag.collapsePreview(); finishCancel = done; };
drag.beginPreviewGesture(320, -8, origin(), 'book-a', () => previewOpened++, cancelPreview);
drag.setPreviewTarget(rect(48, 200, 704, 704), rect(0, 40, 800, 1600));
drag.update(-140);
assert.equal(previewOpened, 0, 'holding and moving must not push Navigation');
assert.equal(drag.state.previewing, true);
assert.equal(drag.state.previewBookId, 'book-a');
assert.equal(drag.state.frameY, 560, 'preview top follows the finger exactly');
assert.equal(drag.state.frameWidth, 374.4, 'width expands while still holding');
assert.ok(drag.state.coverWidth > 44, 'cover grows during the gesture');
assert.ok(drag.state.contentOpacity > 0, 'player content appears before release');
drag.update(-16);
assert.equal(drag.state.frameY, 684, 'reversing the finger reverses the expansion');
drag.end(-16, 0);
assert.equal(previewOpened, 0);
assert.equal(drag.state.frameY, 700, 'cancel settles back to the measured mini bar');
assert.equal(drag.state.active, true, 'preview survives until the cancel animation finishes');
finishCancel(); resetCheck();
assert.equal(drag.state.previewing, false);
drag.beginPreviewGesture(320, -8, origin(), 'book-a', () => previewOpened++, cancelPreview);
drag.update(-140);
const releaseY = drag.state.frameY;
const releaseSnapshot = drag.state.snapshot;
drag.releaseTouch(false); drag.end(-140, 0); flush();
assert.equal(previewOpened, 1);
assert.equal(drag.state.previewing, false);
assert.equal(drag.state.active, true, 'confirmed drag hands off to the existing Navigation animation');
assert.equal(drag.state.frameY, releaseY, 'handoff does not jump back to the mini bar');
assert.equal(drag.state.snapshot, releaseSnapshot, 'handoff retains the same cover snapshot');
drag.complete(); resetCheck();
drag.beginPreviewGesture(320, -120, origin(), 'book-a', () => previewOpened++, cancelPreview);
drag.releaseTouch(true); flush(); finishCancel(); resetCheck();
assert.equal(previewOpened, 1, 'system interruption cancels the interactive preview');
console.log('PASS held preview geometry, cover growth, reversal, animated cancellation, continuous handoff and interruption');

let dismissed = 0;
const cancelDismiss = done => { drag.restoreDismiss(); finishCancel = done; };
drag.beginDismissGesture(ui, 8, () => dismissed++, cancelDismiss);
drag.update(180);
assert.equal(dismissed, 0, 'holding a downward drag does not pop Navigation');
assert.equal(drag.state.dismissing, true);
assert.ok(Math.abs(drag.state.frameY - 180) < 1e-8);
assert.ok(drag.state.frameWidth < drag.state.viewportWidth, 'page shrinks while the finger is held');
assert.ok(drag.state.coverWidth < 352, 'cover follows the shrinking page');
drag.update(12); drag.end(12, 0);
assert.equal(dismissed, 0);
assert.equal(drag.state.frameY, 0, 'short dismissal animates back to full screen');
finishCancel(); resetCheck();
assert.equal(drag.state.dismissing, false);
drag.beginDismissGesture(ui, 8, () => dismissed++, cancelDismiss);
drag.update(180);
const dismissY = drag.state.frameY;
drag.releaseTouch(false); drag.end(180, 0); flush();
assert.equal(dismissed, 1);
assert.equal(drag.state.frameY, dismissY, 'confirmed dismissal retains held geometry for POP');
assert.equal(drag.state.dismissing, true);
drag.complete(); resetCheck();
drag.beginDismissGesture(ui, 8, () => dismissed++, cancelDismiss);
drag.update(180); drag.releaseTouch(true); flush(); finishCancel(); resetCheck();
assert.equal(dismissed, 1, 'interruption must not close the player');
console.log('PASS held downward drag, shrinking cover, reversal, cancel, continuous POP handoff and interruption');

drag.beginPreviewGesture(320, -520, origin(), 'book-a', () => {}, cancelPreview);
drag.setPreviewTarget(rect(48, 200, 704, 704), rect(0, 40, 800, 1600));
const geometryKeys = ['frameX', 'frameY', 'frameWidth', 'frameHeight', 'radius',
  'coverX', 'coverY', 'coverWidth', 'coverHeight', 'coverRadius', 'contentOpacity'];
const expandedGeometry = geometryKeys.map(key => drag.state[key]);
drag.complete();
drag.beginDismissGesture(ui, 180, () => {}, cancelDismiss);
geometryKeys.forEach((key, i) => assert.ok(Math.abs(drag.state[key] - expandedGeometry[i]) < 1e-8,
  `${key}: downward drag must exactly reverse the held upward drag`));
drag.cancel(); finishCancel(); resetCheck();
console.log('PASS identical geometry and opacity at the same held position in both directions');
