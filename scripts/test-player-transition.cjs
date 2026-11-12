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
  assert.equal(drag.state.coverSource, '');
  assert.equal(drag.state.coverImageOpacity, 0);
  assert.equal(drag.state.coverRevealed, false);
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

const cardOrigin = origin();
cardOrigin.sourceNodeId = 'detail-cover-book-a';
cardOrigin.radius = 8;
cardOrigin.coverWidth = 120;
cardOrigin.coverHeight = 160;
drag.beginPreviewGesture(320, -8, cardOrigin, 'book-a', () => {}, cancelPreview);
drag.setPreviewTarget(rect(48, 200, 704, 704), rect(0, 40, 800, 1600));
drag.update(0);
assert.equal(drag.state.coverRadius, cardOrigin.radius,
  'detail cover starts at its measured corner radius instead of a circular mini-player radius');
drag.update(-350);
const intermediateCardRadius = drag.state.coverRadius;
drag.update(-cardOrigin.top);
assert.ok(intermediateCardRadius > cardOrigin.radius && intermediateCardRadius < drag.state.coverRadius,
  'detail cover corners interpolate continuously to the expanded cover');
drag.cancel(); finishCancel(); resetCheck(); drag.clearReturnTarget();
console.log('PASS non-mini-player cover preserves its source corner geometry');

const opacityOrigin = origin();
const offsets = [0, 35, 140, 350, 560, opacityOrigin.top];
const sourceOpacities = [];
drag.beginPreviewGesture(320, -8, opacityOrigin, 'book-a', () => {}, cancelPreview);
drag.setPreviewTarget(rect(48, 200, 704, 704), rect(0, 40, 800, 1600));
const opacities = offsets.map(offset => {
  drag.update(-offset);
  sourceOpacities.push(drag.state.sourceOpacity);
  return drag.state.contentOpacity;
});
assert.equal(opacities[0], 0, 'collapsed content remains hidden');
assert.equal(opacities.at(-1), 1, 'fully expanded content is visible');
assert.ok(opacities.some(value => value > 0 && value < 1), 'content fades through intermediate states');
opacities.forEach((value, index) => {
  assert.ok(value >= 0 && value <= 1, 'opacity stays within the drawable range');
  if (index > 0) assert.ok(value >= opacities[index - 1], 'opacity increases monotonically during expansion');
});
assert.equal(sourceOpacities[0], 1, 'mini text and controls are already visible at the collapsed position');
assert.equal(sourceOpacities.at(-1), 0, 'expanded player does not leave duplicate mini controls visible');
assert.ok(sourceOpacities.some(value => value > 0 && value < 1),
  'mini contents crossfade during the gesture instead of appearing only after completion');
sourceOpacities.forEach((value, index) => {
  assert.ok(value >= 0 && value <= 1);
  if (index > 0) assert.ok(value <= sourceOpacities[index - 1]);
});
drag.complete();
drag.beginDismissGesture(ui, 8, () => {}, cancelDismiss);
for (let index = offsets.length - 1; index >= 0; index--) {
  drag.update(opacityOrigin.top - offsets[index]);
  assert.ok(Math.abs(drag.state.contentOpacity - opacities[index]) < 1e-8,
    'dismissal retraces the same opacity for every sampled geometry');
  assert.ok(Math.abs(drag.state.sourceOpacity - sourceOpacities[index]) < 1e-8,
    'mini contents return at the same held position before the dismissal finishes');
}
drag.cancel();
assert.equal(drag.state.sourceOpacity, 0, 'cancel fades mini contents away while restoring the full player');
finishCancel(); resetCheck(); drag.clearReturnTarget();
console.log('PASS bounded, monotonic and reversible player/mini content crossfade');

const separateFadeOrigin = origin();
drag.beginTap(separateFadeOrigin);
drag.state.contentOpacity = 0.6;
drag.state.sourceOpacity = 0;
drag.collapseToBar(separateFadeOrigin, false);
assert.equal(drag.state.active, true, 'return is still animating before Navigation completion');
assert.equal(drag.state.sourceOpacity, 1, 'return animation targets visible mini contents before complete()');
assert.equal(drag.state.contentOpacity, 0.6, 'geometry-only collapse leaves the independent fade untouched');
assert.equal(drag.state.frameY, separateFadeOrigin.top, 'geometry-only collapse still reaches its target');
drag.collapseToBar(separateFadeOrigin);
assert.equal(drag.state.contentOpacity, 0, 'default collapse still hides content for preview cancellation');
drag.complete(); resetCheck(); drag.clearReturnTarget();
console.log('PASS independent return fade and default preview cancellation');

// Decoded covers must survive preview-to-page handoff, but never leak into a later return.
drag.setReadyCover('/cover-before-opening.jpg', 352);
assert.equal(drag.state.coverSource, '', 'idle pages cannot populate the transition cover');
drag.beginPreviewGesture(320, -140, origin(), 'book-a', () => {}, cancelPreview);
const coverSnapshot = drag.state.snapshot;
drag.setReadyCover('', 352);
drag.setReadyCover('/invalid.jpg', NaN);
drag.setReadyCover('/invalid.jpg', 0);
assert.equal(drag.state.coverSource, '', 'invalid decode notifications keep the snapshot fallback');
drag.setReadyCover('/ready-cover.jpg', 352);
drag.state.coverImageOpacity = 1;
drag.end(-140, 0);
assert.equal(drag.state.previewing, false);
assert.equal(drag.state.coverSource, '/ready-cover.jpg');
assert.equal(drag.state.coverDecodeSize, 352);
assert.equal(drag.state.coverImageOpacity, 1, 'formal page keeps the already-visible decoded cover');
assert.equal(drag.state.snapshot, coverSnapshot, 'snapshot remains available until handoff finishes');
drag.state.coverRevealed = true;
drag.complete(); resetCheck();
drag.setReadyCover('/late-cover.jpg', 352);
assert.equal(drag.state.coverSource, '', 'late decode after entry completion is ignored');
drag.beginDismissGesture(ui, 8, () => {}, cancelDismiss);
drag.setReadyCover('/late-cover.jpg', 352);
assert.equal(drag.state.coverSource, '', 'return uses the current full-size snapshot');
drag.cancel(); finishCancel(); resetCheck(); drag.clearReturnTarget();
drag.beginPreviewGesture(320, -12, origin(), 'book-a', () => {}, cancelPreview);
drag.setReadyCover('/cancelled-cover.jpg', 352);
drag.end(-12, 0);
assert.equal(drag.state.coverSource, '/cancelled-cover.jpg', 'cancellation retains the cover while settling');
finishCancel(); resetCheck(); drag.clearReturnTarget();
console.log('PASS decoded cover handoff, snapshot fallback, late callback isolation and cancellation cleanup');

// The first render must already use the final full viewport, before deferred size callbacks run.
const playerPageSource = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/pages/PlayerPage.ets'), 'utf8');
const pageMethods = playerPageSource.slice(playerPageSource.indexOf('  private initializeViewport('),
  playerPageSource.indexOf('  private landscapeBodyHeight('));
const viewportFields = playerPageSource.slice(playerPageSource.indexOf('  @Local viewportWidth:'),
  playerPageSource.indexOf('  @Local topSafeVp:')).replace(/@Local\s*/g, '');
const appearMethod = playerPageSource.slice(playerPageSource.indexOf('  aboutToAppear('),
  playerPageSource.indexOf('  /** 同步从 SearchCache'));
const cancelViewportMethod = playerPageSource.slice(playerPageSource.indexOf('  private cancelViewportUpdateTimer('),
  playerPageSource.indexOf('  aboutToAppear('));
const adaptiveExports = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/utils/AdaptiveLayout.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, { exports: adaptiveExports });
const layoutExports = {};
const sizeTasks = new Map();
let sizeSequence = 0;
let rootViewport = rect(0, 0, 1740, 800);
let rootAvailable = true;
vm.runInNewContext(ts.transpileModule(
  'export class Page { ' + viewportFields + pageMethods + appearMethod + cancelViewportMethod + ' }', {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, {
  exports: layoutExports,
  AdaptiveLayout: adaptiveExports.AdaptiveLayout,
  WindowUtils: { getWindowWidthVp: () => 870, getWindowHeightVp: () => 400 },
  OneShotTransitionIds: { ROOT_NAVIGATION: 'root' },
  PlayerDragTransition: { measure: () => {
    if (!rootAvailable) throw new Error('root not mounted');
    return rootViewport;
  } },
  setTimeout: callback => { const id = ++sizeSequence; sizeTasks.set(id, callback); return id; },
  clearTimeout: id => sizeTasks.delete(id)
});
function layoutPage(dragState) {
  const page = new layoutExports.Page();
  Object.assign(page, { dragState, previewOnly: true, isLeaving: false, viewportUpdateTimerId: -1,
    getUIContext: () => ({ px2vp: value => value / 2 }),
    primeFromCache() { this.firstLayout = [this.viewportWidth, this.viewportHeight, this.isLandscapePlayer()]; }
  });
  return page;
}
const landscapePage = layoutPage({ active: true, viewportWidth: 870, viewportHeight: 400 });
rootViewport = rect(0, 0, 736, 120); // A source bar/split pane must not replace the captured full viewport.
landscapePage.aboutToAppear();
assert.deepEqual(landscapePage.firstLayout, [870, 400, true]);
assert.equal(sizeTasks.size, 0, 'landscape entry does not wait for an asynchronous layout correction');
const portraitPage = layoutPage({ active: true, viewportWidth: 400, viewportHeight: 870 });
portraitPage.aboutToAppear();
assert.deepEqual(portraitPage.firstLayout, [400, 870, false]);
rootViewport = rect(0, 0, 1740, 800);
const directPage = layoutPage({ active: false });
directPage.aboutToAppear();
assert.deepEqual(directPage.firstLayout, [870, 400, true], 'direct entry measures the root in vp');
rootAvailable = false;
const fallbackPage = layoutPage({ active: false });
fallbackPage.aboutToAppear();
assert.deepEqual(fallbackPage.firstLayout, [870, 400, true], 'missing root retains the actual window fallback');
landscapePage.handleViewportSizeChange({ width: 400, height: 870 });
landscapePage.handleViewportSizeChange({ width: 820, height: 420 });
assert.equal(sizeTasks.size, 1, 'resizing replaces stale pending dimensions');
for (const callback of sizeTasks.values()) callback();
sizeTasks.clear();
assert.equal(landscapePage.viewportWidth, 820);
assert.equal(landscapePage.isLandscapePlayer(), true);
landscapePage.handleViewportSizeChange({ width: 400, height: 870 });
landscapePage.isLeaving = true;
for (const callback of sizeTasks.values()) callback();
assert.equal(landscapePage.viewportWidth, 820, 'late resize cannot mutate a removed player');
console.log('PASS first-frame landscape/portrait, preview/full viewport, direct entry, missing root and resize cleanup');
