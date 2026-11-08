// Real component state machine; native frame, capture and animation completion are deterministic.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/ReaderPageTurnComponent.ets'), 'utf8');
const code = (source.slice(0, source.search(/  @Builder\r?\n/)) + '}')
  .replace(/^import .*;\r?\n/gm, '').replace('@ComponentV2', '')
  .replace('export struct ReaderPageTurnComponent', 'export class ReaderPageTurnComponent extends ComponentBase')
  .replace(/@(Param|Event|Local|BuilderParam) /g, '').replace(/  @Monitor\([^\n]*\)\r?\n/g, '');
let frames = [], animations = [], draws = 0, releases = 0, captures = 0;
const ui = {
  getComponentSnapshot: () => ({ get: async () => {
    captures++;
    return { release: async () => { releases++; } };
  } }),
  postFrameCallback: frame => frames.push(frame),
  animateTo(options, mutate) { mutate(); if (options.duration > 0) animations.push(options); },
  createAnimator(options) {
    return { options, play() { animations.push(this); }, cancel() {
      this.cancelled = true;
      this.onFrame?.(this.options.begin);
    } };
  }
};
const mode = { Cover: 'cover', Simulation: 'simulation', None: 'none', Vertical: 'vertical' };
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(code, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
} }).outputText, {
  exports: exportsObject, setTimeout, clearTimeout,
  ComponentBase: class { getUIContext() { return ui; } getUniqueId() { return 1; } },
  FrameCallback: class {}, RenderingContextSettings: class {},
  CanvasRenderingContext2D: class { clearRect() {} drawImage() { draws++; } },
  ImageBitmap: class { close() {} }, PageTurnMode: mode,
  ReaderTapPolicy: { DEFAULT: '', resolve: (_regions, x) => x < 260 ? 0 : x > 540 ? 2 : 1 },
  ReaderTouchTracker: class { canTap() { return true; } cancel() {} },
  hilog: { warn() {} }, emitter: { on() {}, off() {} }, Curve: { EaseOut: 'easeOut' }
});
const { ReaderPageTurnComponent } = exportsObject;
async function flush() { for (let i = 0; i < 15; i++) await Promise.resolve(); }
async function frame() {
  const batch = frames; frames = [];
  batch.forEach(f => { f.onFrame?.(0); f.onIdle?.(0); });
  await flush();
}
function make() {
  const component = new ReaderPageTurnComponent();
  Object.assign(component, { canvasReady: true, pageWidth: 800, pageHeight: 600 });
  component.completed = [];
  component.onPrepare = async () => true;
  component.onComplete = commit => { component.completed.push(commit); };
  return component;
}
async function startTap(component, forward = true) {
  await component.handleTap(forward ? 700 : 100, 300);
  await flush(); await frame(); await frame();
  assert.equal(component.phase, 'settling');
  return animations.shift();
}
async function handoff(animation) {
  animation.onFinish(); await flush();
  await frame(); await frame(); await frame();
}
function pan(offsetX, velocityX = 0) {
  return { offsetX, offsetY: 0, velocityX, fingerList: [{ localX: 500 + offsetX, localY: 300 }] };
}
async function checkContentPan() {
  const gallery = make(); gallery.ignoreChildGestures = true;
  let resolve, updates = [];
  gallery.onContentPanStart = (x, y) => { assert.equal(x, 500); assert.equal(y, 300); return new Promise(done => { resolve = done; }); };
  gallery.onContentPanUpdate = (...args) => updates.push(args);
  const count = captures;
  gallery.handlePanStart(pan(-20)); gallery.handlePanUpdate(pan(-230)); gallery.handlePanEnd(pan(-300));
  resolve(true); await flush();
  assert.deepEqual(updates, [[-300, 0, true, false]], 'a quick gallery swipe retains its final movement while hit testing');
  assert.equal(captures, count, 'page-internal scrolling never captures or turns a reading page');
  assert.equal(gallery.phase, 'idle');
  assert.equal(gallery.contentPan, null);

  const ordinary = make(); ordinary.ignoreChildGestures = true;
  ordinary.handlePanStart(pan(-20)); ordinary.handlePanEnd(pan(-350, -900));
  await flush(); await frame(); await frame();
  assert.equal(ordinary.phase, 'settling', 'a non-scrollable region retains ordinary page turning');
  await handoff(animations.shift());
  assert.deepEqual(ordinary.completed, [true]);

  gallery.handlePanStart(pan(-20)); gallery.handlePanCancel(); resolve(true); await flush();
  assert.equal(gallery.contentPan, null, 'late hit-test results cannot resume a cancelled gesture');
  assert.deepEqual(updates.at(-1), [0, 0, true, true]);
  console.log('PASS EPUB nested scroll handoff, rapid release, ordinary page fallback and cancellation');
}
async function checkContinuousInput() {
  captures = 0; releases = 0;
  const burst = make();
  let confirms = 0;
  burst.onConfirm = () => { confirms++; };
  const original = await startTap(burst);
  original.onFrame(0.4); await frame();
  await burst.handleTap(700, 300);
  const accelerated = animations.shift();
  assert.equal(original.cancelled, true);
  assert.equal(accelerated.options.duration, 80);
  assert.equal(accelerated.options.begin, 0.4, 'accelerated tail continues from the displayed position');
  assert.equal(burst.coverOffset, -320, 'cancelling the old animator cannot reset the cover');
  for (let i = 0; i < 20; i++) await burst.handleTap(700, 300);
  assert.equal(animations.length, 0, 'repeated input does not keep restarting the accelerated tail');
  original.onFrame(0); original.onFinish(); await flush();
  assert.deepEqual(burst.completed, [], 'replaced animator cannot update or commit');
  assert.equal(burst.progress, 0.4);
  accelerated.onFinish(); await flush();
  assert.equal(burst.phase, 'completing');
  burst.revision = 'page-1'; burst.onReaderChanged();
  assert.notEqual(burst.pendingTurn, null, 'own page revision must preserve the next input');
  await frame(); await frame(); await frame();
  assert.equal(burst.phase, 'settling');
  assert.equal(confirms, 2, 'acceleration never repeats confirmation');
  await handoff(animations.shift());
  original.onFinish(); accelerated.onFinish(); await flush();
  assert.deepEqual(burst.completed, [true, true], 'a burst retains at most one next page');
  assert.equal(burst.phase, 'idle');
  assert.equal(captures, 2);
  assert.equal(releases, 2, 'each page snapshot is released once');

  const asyncBook = make();
  const directions = [];
  let complete;
  asyncBook.onPrepare = async forward => { directions.push(forward); return true; };
  asyncBook.onComplete = commit => {
    asyncBook.completed.push(commit);
    if (asyncBook.completed.length === 1) return new Promise(resolve => { complete = resolve; });
  };
  const first = await startTap(asyncBook);
  first.onFinish(); await flush();
  const beforeCapture = captures;
  asyncBook.handlePanStart(pan(20));
  asyncBook.handlePanUpdate(pan(400));
  asyncBook.handlePanEnd(pan(500, 900));
  assert.equal(captures, beforeCapture, 'EPUB completion must finish before capturing or preparing another page');
  assert.deepEqual(directions, [true]);
  complete(); await flush(); asyncBook.onReaderChanged();
  await frame(); await frame(); await frame();
  assert.equal(asyncBook.phase, 'settling', 'a swipe released during completion is replayed');
  assert.equal(asyncBook.forward, false, 'opposite direction starts from the committed page');
  assert.equal(asyncBook.settleStart, 0, 'released queued swipe keeps a visible animation');
  assert.deepEqual(directions, [true, false]);
  await handoff(animations.shift());
  assert.deepEqual(asyncBook.completed, [true, true]);

  const held = make();
  await startTap(held);
  held.handlePanStart(pan(-40));
  held.handlePanUpdate(pan(-320));
  await handoff(animations.shift());
  assert.equal(held.phase, 'dragging', 'held swipe takes over after the previous page completes');
  assert.equal(held.coverOffset, -320, 'handoff preserves the current finger distance');
  held.handlePanUpdate(pan(-400)); await frame();
  assert.equal(held.coverOffset, -400);
  held.handlePanEnd(pan(-500, -900));
  await handoff(animations.shift());
  assert.deepEqual(held.completed, [true, true]);

  for (const cancel of [false, true]) {
    const abandoned = make();
    await startTap(abandoned);
    abandoned.handlePanStart(pan(-20));
    if (cancel) abandoned.handlePanCancel();
    else abandoned.handlePanEnd(pan(-40, 0));
    await handoff(animations.shift());
    assert.equal(abandoned.phase, 'idle');
    assert.deepEqual(abandoned.completed, [true], 'cancelled/short queued swipe cannot turn an extra page');
  }

  for (const stop of ['background', 'disappear', 'mode', 'revision']) {
    const stopped = make();
    await startTap(stopped);
    await stopped.handleTap(700, 300);
    const tail = animations.shift();
    if (stop !== 'revision') { tail.onFinish(); await flush(); }
    if (stop === 'background') stopped.backgroundHandler();
    else if (stop === 'disappear') stopped.aboutToDisappear();
    else if (stop === 'mode') { stopped.mode = mode.None; stopped.onTurnModeChanged(); }
    else stopped.onReaderChanged();
    await flush(); await frame(); await frame();
    tail.onFinish(); await flush();
    assert.equal(stopped.pendingTurn, null);
    assert.equal(stopped.phase, 'idle');
    assert.deepEqual(stopped.completed, [true], `${stop} clears deferred input without repeating the finished page`);
  }

  const loading = make(); let prepare;
  loading.onPrepare = () => new Promise(resolve => { prepare = resolve; });
  await loading.handleTap(700, 300); await flush(); await frame();
  await loading.handleTap(100, 300);
  prepare(false); await flush(); await frame();
  assert.equal(loading.phase, 'idle');
  assert.equal(loading.pendingTurn, null, 'failed preparation drops deferred turns');
  assert.deepEqual(loading.completed, [false]);
  assert.equal(animations.length, 0);
  assert.equal(captures, releases, 'continuous input never leaks a page snapshot');
}
async function main() {
  for (const forward of [true, false]) {
    const tap = make();
    const starting = tap.beginTurn(forward, true, 300);
    await flush(); await frame(); await frame(); await starting;
    assert.equal(tap.phase, 'settling');
    assert.equal(Math.abs(tap.coverOffset), 0, 'a tap starts from the visible page, not the destination');
    const animation = animations.shift();
    const snapshot = tap.coverSnapshot;
    for (const progress of [0.2, 0.5, 0.8]) {
      animation.onFrame(progress); await frame();
      assert.equal(tap.coverOffset, (forward ? -800 : 800) * progress, 'tap visibly moves through intermediate positions');
      assert.equal(tap.coverSnapshot, snapshot, 'all frames reuse the captured page');
      assert.deepEqual(tap.completed, [], 'tap progress is committed only when animation finishes');
    }
    animation.onFinish(); await flush(); await frame();
    assert.deepEqual(tap.completed, [true]);
    assert.equal(tap.coverSnapshot, null);
  }
  assert.equal(releases, 2);
  releases = 0;

  const drag = make();
  const starting = drag.beginTurn(true, false, 300);
  await flush(); await frame(); await frame(); await starting;
  assert.equal(drag.phase, 'dragging');
  drag.progress = 0.2; drag.drawFrame(0.2);
  drag.progress = 0.5; drag.scheduleFrame(); // pending old drag frame
  drag.handlePanEnd({ offsetX: -400, offsetY: 0, velocityX: -900 });
  assert.equal(drag.coverOffset, -160, 'release starts at the last displayed drag position');
  await frame();
  assert.equal(drag.coverOffset, -160, 'queued drag frame cannot jump ahead to an unrendered touch position');
  animations[0].onFrame(0.6); await frame();
  assert.equal(drag.coverOffset, -480, 'release animation continues moving the same cover layer');
  assert.equal(draws, 0, 'cover mode never redraws the full bitmap through Canvas');
  assert.deepEqual(drag.completed, [], 'preview cannot persist progress');
  animations.shift().onFinish(); await flush(); await frame();
  assert.deepEqual(drag.completed, [true]);
  assert.equal(releases, 1);

  const rapid = make(); let prepared;
  rapid.onPrepare = () => new Promise(resolve => { prepared = resolve; });
  const pending = rapid.beginTurn(false, false, 300);
  await flush(); await frame();
  rapid.handlePanEnd({ offsetX: 500, offsetY: 0, velocityX: 900 });
  prepared(true); await flush(); await frame(); await pending;
  assert.equal(rapid.settleStart, 0, 'release before preparation animates from the last displayed position');
  assert.equal(Math.abs(rapid.coverOffset), 0);
  const oldFinish = animations.shift().onFinish;
  rapid.cancelTurn(true); await flush(); await frame(); oldFinish(); await flush();
  assert.deepEqual(rapid.completed, [true], 'late animation completion cannot commit twice');

  const aborted = make(); let resolve;
  aborted.onPrepare = () => new Promise(done => { resolve = done; });
  const attempt = aborted.beginTurn(true, false, 300);
  await flush(); await frame(); aborted.cancelTurn(); await flush();
  resolve(true); await attempt; await frame();
  assert.equal(aborted.phase, 'idle');
  assert.deepEqual(aborted.completed, [false], 'cancel during loading restores the previous page');
  assert.equal(aborted.coverSnapshot, null);
  assert.equal(releases, 3, 'all snapshots released exactly once');
  await checkContinuousInput();
  await checkContentPan();
  console.log('PASS cover tap frames in both directions, compositing, queued-frame race, quick swipe, delayed capture, cancellation, progress commit and snapshot release');
  console.log('PASS continuous taps and swipes, accelerated tails, bounded queue, reverse direction, async EPUB handoff, held/released/cancelled gestures and lifecycle cleanup');
}
let finished = false;
process.on('beforeExit', () => { if (!finished) { console.error('Reader turn checks did not finish'); process.exitCode = 1; } });
main().then(() => { finished = true; }).catch(error => { finished = true; console.error(error); process.exitCode = 1; });
