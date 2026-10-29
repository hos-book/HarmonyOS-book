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
    Date: class extends Date { static now() { return now; } },
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
  Object.assign(page, { autoPage: new ReaderAutoPageService(), autoPageRunning: false, autoPagePaused: false, autoPageSeconds: 3,
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
assert.equal(page.autoPageRunning, true, 'manual keyboard turns keep automatic paging active');
assert.equal(page.autoPagePaused, false);
page.readerBarVisible = true;
page.syncAutoPage();
const manualAt = page.keyTurnRequest;
advance(2999);
assert.equal(page.keyTurnRequest, manualAt);
advance(1);
assert.equal(page.keyTurnRequest, Math.abs(manualAt) + 1, 'showing the toolbar does not pause automatic paging');
page.toggleAutoPage();
assert.equal(page.autoPageRunning, false);
assert.equal(page.autoPagePaused, true, 'only the pause action enters the resumable paused state');
assert.equal(page.screenOn.values.at(-1), 5, 'pausing restores the reading screen-on preference');
const stoppedAt = page.keyTurnRequest;
advance(60000);
assert.equal(page.keyTurnRequest, stoppedAt);
page.toggleAutoPage();
assert.equal(page.autoPagePaused, false);
advance(2999);
assert.equal(page.keyTurnRequest, stoppedAt, 'resuming starts a full interval from the current page');
advance(1);
assert.equal(page.keyTurnRequest, Math.abs(stoppedAt) + 1);
const pausedCallback = [...timers.values()][0].callback;
page.toggleAutoPage();
assert.equal(page.autoPagePaused, true, 'the floating toggle pauses a running session');
page.pauseAutoPage();
page.syncAutoPage();
const pausedAt = page.keyTurnRequest;
pausedCallback();
advance(60000);
assert.equal(page.keyTurnRequest, pausedAt, 'stale timers cannot resume a paused session');
page.stopAutoPage();
assert.equal(page.autoPagePaused, false, 'closing a paused session removes the resume control');
assert.equal(page.autoPageRunning, false);
assert.equal(timers.size, 0);
page.toggleAutoPage();
page.readerVisible = false;
page.syncAutoPage();
assert.equal(page.autoPageRunning, false, 'route changes stop timers');
assert.equal(page.autoPagePaused, false);
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
epub.pauseAutoPage();
epub.toggleAutoPage();
advance(3000);
assert.equal(epub.readerKitController.flips, 2, 'resuming ReaderKit resets its unchanged-position sentinel');
advance(3000);
assert.equal(epub.autoPageRunning, false, 'legacy EPUB ends when ReaderKit cannot advance');
assert.equal(timers.size, 0);

// Continuous mode uses a native scroll animation; page timers do not trigger full-screen jumps.
const vertical = reader();
vertical.pageTurnMode = 'vertical';
vertical.toggleAutoPage();
vertical.readerBarVisible = true;
vertical.syncAutoPage();
assert.equal(vertical.autoScrollReady, true);
advance(60000);
assert.equal(vertical.keyTurnRequest, 0);
vertical.pauseAutoPage();
assert.equal(vertical.autoScrollReady, false);
assert.equal(vertical.autoPagePaused, true);
vertical.syncAutoPage();
assert.equal(vertical.autoScrollReady, false, 'layout readiness does not resume manually paused scrolling');
vertical.toggleAutoPage();
assert.equal(vertical.autoScrollReady, true, 'continue resumes scrolling without reopening settings');
vertical.showSettingsSheet = true; vertical.syncAutoPage();
assert.equal(vertical.autoScrollReady, false);
vertical.stopAutoPage();

const comicSource = fs.readFileSync(path.join(root, 'pages/ComicReaderPage.ets'), 'utf8');
const comicMethods = comicSource.slice(comicSource.indexOf('  private toggleAutoPage()'),
  comicSource.indexOf('  private turnPage(direction:'))
  .replace(/  @Monitor\([\s\S]*?\)\s*/g, '');
const { ComicReader } = compile(`export class ComicReader { ${comicMethods} }`, {
  ReaderAutoPageService, WindowUtils: { setReaderStatusBarVisible() {} }
});
for (const mode of [0, 1]) {
  const comicReader = new ComicReader();
  Object.assign(comicReader, { autoPage: new ReaderAutoPageService(), autoPageRunning: false, autoPagePaused: false,
    autoPageSeconds: 3, autoPageRequest: 0, mode, alive: true, foreground: true, readerVisible: true,
    busy: false, failed: false, pageCount: 5, zoomActive: false, restoreTimer: -1, turning: false,
    usesContinuousPages: () => false, screenOn: { configure() {} } });
  comicReader.toggleAutoPage();
  comicReader.chrome = true;
  comicReader.syncAutoPage();
  assert.equal(comicReader.autoScrollReady, mode === 0);
  advance(3000);
  assert.equal(comicReader.autoPageRequest, mode === 0 ? 0 : 1, 'comic toolbar does not pause automatic paging');
  const comicPausedAt = comicReader.autoPageRequest;
  comicReader.pauseAutoPage();
  comicReader.syncAutoPage();
  assert.equal(comicReader.autoPagePaused, true);
  assert.equal(comicReader.autoScrollReady, false);
  advance(60000);
  assert.equal(comicReader.autoPageRequest, comicPausedAt);
  comicReader.toggleAutoPage();
  assert.equal(comicReader.autoPagePaused, false);
  assert.equal(comicReader.autoScrollReady, mode === 0);
  advance(2999);
  assert.equal(comicReader.autoPageRequest, comicPausedAt);
  advance(1);
  assert.equal(comicReader.autoPageRequest, comicPausedAt + (mode === 0 ? 0 : 1));
  comicReader.toggleAutoPage();
  comicReader.stopAutoPage();
  assert.equal(comicReader.autoPageRunning, false);
  assert.equal(comicReader.autoPagePaused, false);
  assert.equal(timers.size, 0);
}

const refreshRequests = [];
let supportsHighRefresh = true;
let refreshUnavailable = false;
const { ReaderAutoScrollService } = compile(fs.readFileSync(path.join(root, 'service/text/ReaderAutoScrollService.ets'), 'utf8'), {
  Edge: { Bottom: 'bottom' },
  require: () => ({ displaySync: { create() {
    if (refreshUnavailable) throw new Error('Display sync unavailable');
    const request = {
      running: false, range: null,
      setExpectedFrameRateRange(range) {
        if (!supportsHighRefresh && range.max > 60) throw new Error('Unsupported refresh rate');
        this.range = range;
      },
      start() { this.running = true; }, stop() { this.running = false; }
    };
    refreshRequests.push(request);
    return request;
  } } })
});
const context = { runScopedTask: task => task() };
const scrollClock = new ReaderAutoScrollService();
let nativeOffset = 120, nativeVelocity = 0, speed = 30;
const nativeStarts = [], nativeStops = [];
const nativeScroller = {
  currentOffset: () => ({ xOffset: 0, yOffset: nativeOffset }),
  scrollEdge(edge, options) { assert.equal(edge, 'bottom'); nativeStarts.push(options.velocity); nativeVelocity = options.velocity; },
  scrollTo(options) { nativeStops.push(options); nativeVelocity = 0; assert.equal(options.yOffset, nativeOffset); assert.equal(options.animation, false); }
};
function nativeAdvance(ms) { nativeOffset += nativeVelocity * ms / 1000; advance(ms); }
scrollClock.start(context, () => scrollClock.move(nativeScroller, speed));
advance(0);
assert.deepEqual(nativeStarts, [30]);
for (let i = 0; i < 30; i++) nativeAdvance(200);
assert.equal(nativeStarts.length, 1, 'normal polling must not repeatedly restart a running native animation');
assert.equal(refreshRequests.length, 1, 'native movement holds one refresh-rate request without JS frame listeners');
assert.equal(refreshRequests[0].range.min, 60);
assert.equal(refreshRequests[0].range.expected, 120);
assert.equal(nativeOffset, 300);
const staleScrollCheck = [...timers.values()][0].callback;
scrollClock.stop();
nativeAdvance(30000); staleScrollCheck();
assert.equal(nativeOffset, 300, 'pause stops native motion at the current position');
assert.equal(nativeStops.length, 1);
assert.equal(refreshRequests[0].running, false, 'pause releases the refresh-rate request');
assert.equal(timers.size, 0, 'stop clears polling and invalidates an already queued check');
scrollClock.start(context, () => scrollClock.move(nativeScroller, speed));
advance(0); staleScrollCheck();
assert.equal(nativeStarts.length, 2, 'resume starts once and old session callbacks remain invalid');
speed = 60; nativeAdvance(200);
assert.equal(nativeStarts.at(-1), 60, 'speed is passed to the native controller in vp/s');
nativeAdvance(200);
assert.equal(nativeStarts.length, 3);
scrollClock.setTouching(true);
assert.equal(refreshRequests.at(-1).running, false, 'touch hands frame-rate scheduling back to the native gesture');
nativeAdvance(2000);
assert.equal(nativeVelocity, 0, 'a held finger owns the scroller');
assert.equal(nativeStarts.length, 3);
scrollClock.setTouching(false);
nativeOffset += 20; advance(200);
assert.equal(nativeVelocity, 0, 'manual inertia is allowed to finish before resuming');
advance(200);
assert.equal(nativeStarts.length, 4);
nativeVelocity = 0; // A manual jump or the native edge has interrupted the animation.
advance(200);
assert.equal(nativeStarts.length, 5, 'stopped native scrolling recovers without per-frame callbacks');
scrollClock.pause();
scrollClock.pause();
assert.equal(nativeStops.length, 3, 'a blocked gate stops motion only once');
scrollClock.stop();
assert.equal(timers.size, 0);
supportsHighRefresh = false;
scrollClock.start(context, () => scrollClock.move(nativeScroller, speed)); advance(0);
assert.equal(refreshRequests.at(-1).range.expected, 60, '60 Hz devices retain a valid frame-rate request');
scrollClock.stop();
refreshUnavailable = true;
scrollClock.start(context, () => scrollClock.move(nativeScroller, speed)); advance(0);
assert.equal(nativeVelocity, speed, 'native scrolling still works if the refresh-rate hint is unavailable');
scrollClock.stop();
assert.ok(refreshRequests.every(request => !request.running), 'exit never leaves high refresh requested');
for (const [value, comicMode, expected] of [[NaN, false, 20], [Infinity, true, 30], [1, false, 6], [500, false, 100], [500, true, 120]]) {
  assert.equal(ReaderAutoScrollService.normalizeSpeed(value, comicMode), expected);
}

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
const scrollSpeeds = [];
let gatedPauses = 0;
let scrollEnd = false, reachedEnd = 0, loadedNext = 0;
Object.assign(continuous, { autoScrollReady: true, disposed: false, restoring: false, selectionActive: false,
  contentHeight: 800, autoScrollSpeed: 30, rowHeight: 40, chapters: [{ index: 0 }], chapterStep: 1, chapterCount: 2,
  scroller: { isAtEnd: () => scrollEnd },
  autoScroll: { move(_scroller, speed) { scrollSpeeds.push(speed); }, pause() { gatedPauses++; } },
  reportPosition() {}, loadNeighbor() { loadedNext++; }, onForwardEnd() { reachedEnd++; } });
continuous.advanceAutoScroll();
assert.equal(scrollSpeeds[0], 20, 'novel lines per minute are converted using the current row height');
continuous.restoring = true; continuous.advanceAutoScroll();
assert.equal(scrollSpeeds.length, 1, 'reflow/position restore suspends movement');
assert.equal(gatedPauses, 1, 'waiting for layout stops an existing animation');
continuous.restoring = false; continuous.selectionActive = true; continuous.advanceAutoScroll();
assert.equal(gatedPauses, 2, 'text selection stops an existing animation');
continuous.selectionActive = false; scrollEnd = true; continuous.advanceAutoScroll();
assert.equal(loadedNext, 1); assert.equal(scrollSpeeds.length, 1);
scrollEnd = false; continuous.advanceAutoScroll();
assert.equal(scrollSpeeds.length, 2, 'appended chapters allow native scrolling to resume');
scrollEnd = true; continuous.nextFailed = true; continuous.advanceAutoScroll();
assert.equal(reachedEnd, 1, 'failed chapter ends automatic movement');
continuous.autoScrollReady = false; continuous.advanceAutoScroll();
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
  const velocities = [];
  let comicPauses = 0;
  Object.assign(scroll, { disposed: false, restoring: false, keyTurning: false, zoomOwner: '',
    autoPageRunning: true, firstVisible: 0, serial: 0, paged: true, pageHeight: 1000, overlap: 10,
    book: { chapters: [{}, {}] }, chapters: [{ index: 0 }], imageReady: new Map(),
    source: { totalCount: () => 1, getData: () => ({ chapterIndex: 0, page: { key: 'image' } }) },
    scroller: { isAtEnd: () => edge, scrollBy: (_x, y) => moves.push(y) },
    autoScroll: { move(_scroller, speed) { velocities.push(speed); }, pause() { comicPauses++; } },
    reportPosition() {},
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
  scroll.advanceAutoScroll();
  assert.equal(velocities.length, 0, 'continuous movement also stops at an undecoded/failed image');
  assert.equal(comicPauses, 1);
  scroll.imageReady.clear(); scroll.advanceAutoScroll();
  assert.equal(comicPauses, 2, 'unknown image decode status stops the native animation');
  scroll.imageReady.set('0:image', true);
  scroll.advanceAutoScroll();
  assert.deepEqual(velocities, [60], 'comic speed directly controls native velocity');
  scroll.zoomOwner = 'image'; scroll.advanceAutoScroll();
  assert.equal(comicPauses, 3, 'zoom suspends native motion');
  scroll.zoomOwner = ''; scroll.awaitingImage = true; scroll.advanceAutoScroll();
  assert.equal(comicPauses, 4, 'restoring the position of a late image suspends native motion');
  scroll.awaitingImage = false;
  scroll.autoScrollReady = false;
  scroll.advanceAutoScroll();
  assert.equal(velocities.length, 1, 'hidden/background comic reader cannot keep scrolling');
  assert.equal(comicPauses, 5);
  console.log('PASS auto paging: native velocity, uninterrupted animation, touch/inertia handoff, pause/resume, chapter/image/layout gating, background/route stop, speech exclusion, EPUB end and tall images');
})().catch(error => { console.error(error); process.exitCode = 1; });
