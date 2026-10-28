// Exercise real timer and reader navigation methods with a deterministic clock.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
let now = 0;
let sequence = 0;
const timers = new Map();
function compile(source, dependencies = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, ...dependencies,
    setTimeout(callback, delay) { const id = ++sequence; timers.set(id, { callback, due: now + delay }); return id; },
    clearTimeout(id) { timers.delete(id); } });
  return exports;
}
function advance(ms) {
  now += ms;
  // A throttled event loop delivers a late timer once; it does not replay missed intervals.
  for (const [id, timer] of [...timers]) {
    if (timer.due <= now && timers.delete(id)) timer.callback();
  }
}
const { ReaderAutoPageService } = compile(fs.readFileSync(path.join(root, 'service/text/ReaderAutoPageService.ets'), 'utf8'));
const clock = new ReaderAutoPageService();
let turns = 0;
clock.start(10, () => turns++);
advance(30000);
assert.equal(turns, 0, 'loading or an open sheet must not flip');
clock.setReady(true);
advance(9999);
assert.equal(turns, 0);
advance(1);
assert.equal(turns, 1);
advance(60000);
assert.equal(turns, 2, 'a delayed callback cannot skip several pages');
clock.setReady(false);
advance(60000);
assert.equal(turns, 2);
clock.setReady(true);
advance(9000);
clock.restart(); // New chapter has just finished loading.
advance(9999);
assert.equal(turns, 2, 'a loaded page receives the full reading interval');
advance(1);
assert.equal(turns, 3);
const stale = [...timers.values()][0].callback;
clock.stop();
stale();
advance(60000);
assert.equal(turns, 3, 'background/exit invalidates callbacks already queued by the platform');
clock.start(3, () => { turns++; clock.stop(); });
clock.setReady(true);
advance(3000);
assert.equal(turns, 4);
assert.equal(timers.size, 0, 'stopping at the final page does not reschedule');
for (const [value, expected] of [[NaN, 10], [Infinity, 10], [1, 3], [500, 120], [9.8, 10]]) {
  assert.equal(ReaderAutoPageService.normalizeSeconds(value), expected);
}

const readerSource = fs.readFileSync(path.join(root, 'pages/ReaderPage.ets'), 'utf8');
const methods = readerSource.slice(readerSource.indexOf('  private autoPageAvailable()'),
  readerSource.indexOf('  @Builder\n  readerTabStyle(') >= 0 ? readerSource.indexOf('  @Builder\n  readerTabStyle(') :
    readerSource.indexOf('  @Builder\r\n  readerTabStyle('))
  .replace(/  @Monitor\([\s\S]*?\)\s*/g, '');
const { Reader } = compile(`export class Reader { ${methods} }`, { ReaderAutoPageService, PageTurnMode: { Vertical: 'vertical' } });
function reader() {
  const page = new Reader();
  Object.assign(page, { autoPage: new ReaderAutoPageService(), autoPageRunning: false, autoPageSeconds: 3,
    readingForeground: true, readerVisible: true, leaving: false, loading: false, readerError: '',
    onlineTextLoading: false, onlineTextTurnPreview: null, selectingText: false,
    speechState: { active: false }, onlineTextPages: [{}], keyTurnRequest: 0, screenOnMinutes: 5,
    isOnlineTextBook: () => true, screenOn: { values: [], configure(value) { this.values.push(value); }, touch() {} },
    hideReaderBar() { this.readerBarVisible = false; }, showSettingsSheet: true });
  return page;
}
const page = reader();
page.toggleAutoPage();
assert.equal(page.showSettingsSheet, false);
assert.equal(page.autoPageRunning, true);
assert.equal(page.screenOn.values.at(-1), -1);
advance(3000);
assert.equal(page.keyTurnRequest, 1, 'automatic paging uses the existing animated/continuous turn path');
page.onlineTextLoading = true;
page.syncAutoPage();
advance(30000);
assert.equal(page.keyTurnRequest, 1);
page.onlineTextLoading = false;
page.syncAutoPage();
advance(2999);
assert.equal(page.keyTurnRequest, 1);
advance(1);
assert.equal(page.keyTurnRequest, 2);
page.turnPageFromKey(false);
assert.equal(page.autoPageRunning, false, 'manual keyboard turns stop automatic paging');
assert.equal(page.screenOn.values.at(-1), 5, 'stopping restores the reading screen-on preference');
const stoppedAt = page.keyTurnRequest;
advance(60000);
assert.equal(page.keyTurnRequest, stoppedAt);
page.toggleAutoPage();
page.readerVisible = false;
page.syncAutoPage();
assert.equal(page.autoPageRunning, false, 'route changes stop timers');
page.readerVisible = true;
page.toggleAutoPage();
page.speechState.active = true;
page.syncAutoPage();
assert.equal(page.autoPageRunning, false, 'speech follow and automatic paging never compete');
const epub = reader();
Object.assign(epub, { isOnlineTextBook: () => false, readerKitReady: true, currentResourceIndex: 2,
  readerKitDomPos: 'last', readerKitPageOffset: 8, readerKitController: { flips: 0, flipPage() { this.flips++; } } });
epub.toggleAutoPage();
advance(3000);
assert.equal(epub.readerKitController.flips, 1);
advance(3000);
assert.equal(epub.autoPageRunning, false, 'legacy EPUB ends when ReaderKit cannot advance');
assert.equal(timers.size, 0);

// Continuous mode schedules native frames; no page interval or full-screen jump is involved.
const vertical = reader();
vertical.pageTurnMode = 'vertical';
vertical.toggleAutoPage();
assert.equal(vertical.autoScrollReady, true);
advance(60000);
assert.equal(vertical.keyTurnRequest, 0);
vertical.showSettingsSheet = true; vertical.syncAutoPage();
assert.equal(vertical.autoScrollReady, false);
vertical.stopAutoPage();

const { ReaderAutoScrollService } = compile(fs.readFileSync(path.join(root, 'service/text/ReaderAutoScrollService.ets'), 'utf8'), {
  require: () => ({ FrameCallback: class {} })
});
const frames = [];
const context = { postFrameCallback: frame => frames.push(frame) };
const scrollClock = new ReaderAutoScrollService();
let distance = 0;
scrollClock.start(context, seconds => { distance += seconds * 30; });
const frameAt = ms => frames.shift().onFrame(ms * 1000000);
frameAt(0);
for (let time = 16; time <= 160; time += 16) frameAt(time);
assert.ok(Math.abs(distance - 4.8) < 0.001, 'speed controls continuous distance, independent of timer ticks');
frameAt(5000);
assert.ok(Math.abs(distance - 6.72) < 0.001, 'a late frame is capped instead of skipping unread content');
scrollClock.stop(); frameAt(5016);
assert.equal(frames.length, 0, 'stale native callbacks cannot restart a stopped session');

function extractMethod(source, name) {
  const start = source.indexOf(`  private ${name}(`);
  assert.ok(start >= 0);
  let end = source.indexOf('{', start) + 1, depth = 1;
  while (depth && end < source.length) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; end++; }
  return source.slice(start, end);
}
const continuousSource = fs.readFileSync(path.join(root, 'components/ReaderContinuousComponent.ets'), 'utf8');
const { ContinuousReader } = compile(`export class ContinuousReader { ${extractMethod(continuousSource, 'advanceAutoScroll')} }`);
const continuous = new ContinuousReader();
const scrollDistances = [];
let scrollEnd = false, reachedEnd = 0, loadedNext = 0;
Object.assign(continuous, { autoScrollReady: true, disposed: false, restoring: false, selectionActive: false,
  contentHeight: 800, autoScrollSpeed: 30, rowHeight: 40, chapters: [{ index: 0 }], chapterStep: 1, chapterCount: 2,
  scroller: { isAtEnd: () => scrollEnd, scrollBy: (_x, y) => scrollDistances.push(y) },
  reportPosition() {}, loadNeighbor() { loadedNext++; }, onForwardEnd() { reachedEnd++; } });
continuous.advanceAutoScroll(0.016);
assert.equal(scrollDistances[0], 0.32);
continuous.restoring = true; continuous.advanceAutoScroll(0.016);
assert.equal(scrollDistances.length, 1, 'reflow/position restore suspends movement');
continuous.restoring = false; scrollEnd = true; continuous.advanceAutoScroll(0.016);
assert.equal(loadedNext, 1); assert.equal(scrollDistances.length, 1);
continuous.nextFailed = true; continuous.advanceAutoScroll(0.016);
assert.equal(reachedEnd, 1, 'failed chapter ends automatic movement');
continuous.autoScrollReady = false; continuous.advanceAutoScroll(0.016);
assert.equal(reachedEnd, 1);
const imageSource = fs.readFileSync(path.join(root, 'components/ComicPageImage.ets'), 'utf8');
const imageMethods = imageSource.slice(imageSource.indexOf('  private advanceAutoPage()'),
  imageSource.indexOf('  private loadImage()')).replace(/  @Monitor\([^\n]*\)\s*/g, '');
const { ComicImage } = compile(`export class ComicImage { ${imageMethods} }`);
const comic = new ComicImage();
let atEnd = false;
let imageEnds = 0;
let imageFailures = 0;
const distances = [];
Object.assign(comic, { alive: true, autoPageActive: true, paged: true, zoomLocked: false,
  loaded: false, failed: false, fitScreen: false, pageHeight: 800,
  pageScroller: { isAtEnd: () => atEnd, scrollBy: (_x, y) => distances.push(y) },
  onAutoPageEnd() { imageEnds++; }, onAutoPageFailure() { imageFailures++; }, onAutoPageDelay() {} });
comic.advanceAutoPage();
assert.equal(imageEnds, 0, 'an undecoded image cannot be skipped');
assert.equal(distances.length, 0);
comic.loaded = true;
comic.advanceAutoPage();
assert.deepEqual(distances, [680], 'a tall image advances by viewport with context overlap');
assert.equal(imageEnds, 0, 'a tall image must be finished before switching images');
atEnd = true;
comic.advanceAutoPage();
assert.equal(imageEnds, 1);
comic.failed = true;
comic.advanceAutoPage();
assert.equal(imageFailures, 1, 'failed images stop automatic paging');
comic.autoPageActive = false;
comic.advanceAutoPage();
assert.equal(imageFailures, 1, 'cached offscreen images cannot drive automatic paging');
const scrollSource = fs.readFileSync(path.join(root, 'components/ComicContinuousComponent.ets'), 'utf8');
const scrollMethods = scrollSource.slice(scrollSource.indexOf('  private async turnFromKey('),
  scrollSource.indexOf('  private reset('));
const { ComicScroll } = compile(`export class ComicScroll { ${scrollMethods} ${extractMethod(scrollSource, 'advanceAutoScroll')} }`, {
  ComicScrollLayoutFrame: class { constructor(callback) { this.callback = callback; } }
});
(async () => {
  const scroll = new ComicScroll();
  let edge = false;
  let ends = 0;
  const moves = [];
  Object.assign(scroll, { disposed: false, restoring: false, keyTurning: false, zoomOwner: '',
    autoPageRunning: true, firstVisible: 0, serial: 0, paged: true, pageHeight: 1000, overlap: 10,
    book: { chapters: [{}, {}] }, chapters: [{ index: 0 }], imageReady: new Map(),
    source: { totalCount: () => 1, getData: () => ({ chapterIndex: 0, page: { key: 'image' } }) },
    scroller: { isAtEnd: () => edge, scrollBy: (_x, y) => moves.push(y) },
    loadNeighbor: async () => {}, onForwardEnd() { ends++; },
    getUIContext: () => ({ postFrameCallback(frame) { frame.callback(); } }) });
  await scroll.turnFromKey(true);
  assert.equal(moves.length, 0, 'continuous comics wait for the current visible image to decode');
  scroll.imageReady.set('0:image', true);
  await scroll.turnFromKey(true);
  assert.deepEqual(moves, [900], 'joined pages retain configured overlap');
  edge = true;
  let finishLoad;
  scroll.loadNeighbor = () => new Promise(resolve => { finishLoad = resolve; });
  const loading = scroll.turnFromKey(true);
  scroll.autoPageRunning = false;
  finishLoad();
  await loading;
  assert.equal(moves.length, 1, 'late chapter loading cannot scroll after background/manual stop');
  scroll.autoPageRunning = true;
  scroll.chapters = [{ index: 1 }];
  await scroll.turnFromKey(true);
  assert.equal(ends, 1, 'the end of the last image ends automatic paging');
  scroll.imageReady.set('0:image', false);
  await scroll.turnFromKey(true);
  assert.equal(ends, 2, 'image failure cannot leave a running timer skipping failed pages');
  scroll.autoScrollReady = true; scroll.autoScrollSpeed = 60; scroll.paged = false; edge = false;
  scroll.advanceAutoScroll(0.016);
  assert.equal(moves.length, 1, 'continuous movement also stops at an undecoded/failed image');
  scroll.imageReady.set('0:image', true);
  scroll.advanceAutoScroll(0.016);
  assert.equal(moves.at(-1), 0.96, 'comic speed advances a small distance every frame');
  scroll.autoScrollReady = false;
  scroll.advanceAutoScroll(0.016);
  assert.equal(moves.length, 2, 'hidden/background comic reader cannot keep scrolling');
  console.log('PASS auto paging: interval, delayed frames, load/modal gating, manual/background/route stop, screen-on restore, speech exclusion, EPUB end, tall images and continuous comic cancellation');
})().catch(error => { console.error(error); process.exitCode = 1; });
