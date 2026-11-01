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
