// Exercise the actual comic input handlers without ArkUI rendering.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };
const policyExports = {};
const compile = code => ts.transpileModule(code, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
vm.runInNewContext(compile(fs.readFileSync(path.join(root, 'utils/ReaderTapPolicy.ets'), 'utf8')),
  { exports: policyExports, TouchType });
const source = fs.readFileSync(path.join(root, 'pages/ComicReaderPage.ets'), 'utf8');
function method(name) {
  const start = source.indexOf(`  private ${name}(`);
  assert.ok(start >= 0, name);
  const body = source.indexOf('{', start);
  let depth = 1, end = body + 1;
  while (depth && end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
    end++;
  }
  return source.slice(start, end);
}
let now = 1000;
const scope = { ...policyExports, TouchType, Date: { now: () => now }, Curve: { EaseInOut: 0 } };
const handlers = ['onContentTap', 'contentTouch', 'turnPage', 'adjacent', 'canChange',
  'canUseVolumeKeys', 'syncVolumeKeys', 'handleVolumePageTurn'].map(method).join('\n');
vm.runInNewContext(compile(`class ComicInput { ${handlers} }\nglobalThis.ComicInput = ComicInput;`), scope);
function reader(mode = 1) {
  const r = new scope.ComicInput();
  Object.assign(r, { mode, pageIndex: 1, pageCount: 4, widthVp: 300, heightVp: 600,
    leftSafe: 0, rightSafe: 0, tapLeftPercent: 33, tapRightPercent: 33,
    tapTopPercent: 33, tapBottomPercent: 33, generation: 1, restoreTimer: -1,
    touchTracker: new policyExports.ReaderTouchTracker(), chapterIndex: 0,
    book: { chapters: [{}, {}] }, turns: [], chapters: [], toggles: 0,
    toggleChrome() { this.toggles++; }, scheduleSave() {}, continueScroll() {},
    loadChapter(index) { this.chapters.push(index); },
    getUIContext() { return { animateTo(options, update) { update(); options.onFinish(); } }; }
  });
  r.swiper = { changeIndex(index, animated) { r.turns.push([index, animated]); r.pageIndex = index; } };
  return r;
}
function touch(r, type, x = 280, y = 300) {
  r.contentTouch({ type, touches: type === TouchType.Up ? [] : [{ x, y }],
    changedTouches: [{ x, y, windowX: x, windowY: y }] });
}
const r = reader();
touch(r, TouchType.Down); now += 100; touch(r, TouchType.Up);
assert.deepEqual(r.turns, [[2, true]], 'side tap starts animation on release');
r.onContentTap({ windowX: 280, windowY: 300 });
assert.equal(r.turns.length, 1, 'later native click cannot turn twice');
touch(r, TouchType.Down, 150); now += 100; touch(r, TouchType.Up, 150);
r.onContentTap({ windowX: 150, windowY: 300 });
assert.equal(r.toggles, 1, 'center click still opens toolbar');
touch(r, TouchType.Down); now += 600; touch(r, TouchType.Up);
assert.equal(r.turns.length, 1, 'holding cannot become a page tap');
touch(r, TouchType.Down); touch(r, TouchType.Move, 240); touch(r, TouchType.Up);
assert.equal(r.turns.length, 1, 'movement returning to start cannot become a tap');
touch(r, TouchType.Down); touch(r, TouchType.Cancel); touch(r, TouchType.Up);
assert.equal(r.turns.length, 1, 'cancelled touch cannot turn');
r.turning = true;
touch(r, TouchType.Down); now += 100; touch(r, TouchType.Up);
assert.equal(r.turns.length, 1, 'ongoing animation rejects a second page request');
const dissolve = reader(3);
touch(dissolve, TouchType.Down); now += 100; touch(dissolve, TouchType.Up);
assert.equal(dissolve.pageIndex, 2, 'dissolve also starts on release');
console.log('comic page input: immediate turn, no duplicate, center toolbar, hold/move/cancel and animation lock passed');

const zoomed = reader(); zoomed.zoomActive = true;
touch(zoomed, TouchType.Down); now += 100; touch(zoomed, TouchType.Up);
zoomed.onContentTap({ windowX: 150, windowY: 300 });
assert.equal(zoomed.turns.length, 0, 'zoom gestures cannot turn the underlying page');
assert.equal(zoomed.toggles, 0, 'zoom taps cannot toggle the underlying toolbar');
zoomed.zoomActive = false;
touch(zoomed, TouchType.Up, 280);
zoomed.onContentTap({ windowX: 150, windowY: 300 });
assert.equal(zoomed.turns.length, 0, 'last finger after shrinking cannot turn the page');
assert.equal(zoomed.toggles, 0, 'last finger after shrinking cannot show toolbar');
touch(zoomed, TouchType.Down, 280); now += 100; touch(zoomed, TouchType.Up, 280);
assert.equal(zoomed.turns.length, 1, 'fresh single touch works after returning to original size');
const multi = reader(3);
touch(multi, TouchType.Down, 280);
multi.contentTouch({ type: TouchType.Down, touches: [{x:280,y:300},{x:100,y:300}], changedTouches: [] });
touch(multi, TouchType.Up, 20);
assert.equal(multi.pageIndex, 1, 'two-finger gesture cannot trigger dissolve or chapter swipes');

const keys = reader();
Object.assign(keys, { alive: true, foreground: true, readerVisible: true, volumeKeyPageTurn: false,
  keyTurnRequest: 0, volumeKeys: { setEnabled(enabled, callback) { keys.subscribed = enabled; keys.keyCallback = callback; } } });
keys.syncVolumeKeys();
assert.equal(keys.subscribed, false);
keys.volumeKeyPageTurn = true;
keys.syncVolumeKeys();
assert.equal(keys.subscribed, true);
keys.keyCallback(true);
assert.equal(keys.pageIndex, 2);
keys.keyCallback(false);
assert.equal(keys.pageIndex, 1);
keys.chrome = true;
assert.equal(keys.canUseVolumeKeys(), true, 'toolbar alone does not disable volume page turns');
for (const field of ['busy', 'failed', 'showChapters', 'showSettings', 'showSourceSwitch', 'zoomActive',
  'sheetPresented', 'chapterSliderDragging', 'chapterSliderConfirming']) {
  keys[field] = true; keys.syncVolumeKeys();
  assert.equal(keys.subscribed, false, field);
  const count = keys.turns.length;
  keys.keyCallback(true);
  assert.equal(keys.turns.length, count, 'late callbacks must not turn behind overlays');
  keys[field] = false;
}
for (const field of ['alive', 'foreground', 'readerVisible', 'volumeKeyPageTurn']) {
  keys[field] = false; keys.syncVolumeKeys();
  assert.equal(keys.subscribed, false, field);
  keys[field] = true;
}
keys.mode = 0;
keys.handleVolumePageTurn(true);
assert.equal(keys.keyTurnRequest, 1);
keys.handleVolumePageTurn(false);
assert.equal(keys.keyTurnRequest, -2);
keys.mode = 3;
keys.handleVolumePageTurn(true);
assert.equal(keys.pageIndex, 2, 'dissolve mode supports volume turns');
keys.pageIndex = 3;
keys.handleVolumePageTurn(true);
assert.deepEqual(keys.chapters, [1], 'last image advances to the next chapter');
console.log('PASS: comic volume keys default off, both directions/modes, chapter crossing and lifecycle/overlay subscription guards');
