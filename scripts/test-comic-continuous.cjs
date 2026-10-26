// Run real continuous-list methods with simulated ArkUI notifications and network timing.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const compile = code => ts.transpileModule(code, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const scope = { exports: {}, ScrollAlign: {START:0}, DataOperationType: {ADD:'add',DELETE:'delete',RELOAD:'reload'}, ComicPage: class {}, PreferenceService: { getPreloadChapters: async () => 1 },
  ComicScrollLayoutFrame: class { constructor(callback) { this.callback = callback; } } };
const data = fs.readFileSync(path.join(root, 'service/ComicScrollDataSource.ets'), 'utf8').replace(/^import .*;\r?\n/gm, '');
vm.runInNewContext(compile(data), scope);
Object.assign(scope, scope.exports);
const source = fs.readFileSync(path.join(root, 'components/ComicContinuousComponent.ets'), 'utf8');
function method(name, text = source) {
  const match = new RegExp(`  private (?:async )?${name}\\(`).exec(text);
  assert.ok(match, name);
  const start = match.index, body = text.indexOf('{', start);
  let depth = 1, end = body + 1;
  while (depth && end < text.length) {
    if (text[end] === '{') depth++;
    if (text[end] === '}') depth--;
    end++;
  }
  return text.slice(start, end);
}
vm.runInNewContext(compile(`class Continuous { ${['loadNeighbor', 'reportPosition', 'visibleChanged', 'trimChapters', 'turnFromKey', 'advanceViewport', 'restoreVisible', 'imageGeometryReady']
  .map(name => method(name)).join('\n')} }\nglobalThis.Continuous = Continuous;`), scope);
const parentSource = fs.readFileSync(path.join(root, 'pages/ComicReaderPage.ets'), 'utf8');
vm.runInNewContext(compile(`class Parent { ${['onScrollPosition', 'usesJoinedPages', 'usesContinuousPages'].map(name => method(name, parentSource)).join('\n')} }
  globalThis.Parent = Parent;`), scope);
const pages = index => Array.from({ length: 6 }, (_, n) => ({ key: `${index}:${n}`, index: n, url: `${index}/${n}` }));
function reader(index = 2, descending = false) {
  const r = new scope.Continuous(), events = [], requests = [], positions = [];
  const chapter = scope.ComicScrollChapter.create(index, pages(index));
  Object.assign(r, { source: new scope.ComicScrollDataSource(), chapters: [chapter], serial: 1,
    firstVisible: 0, lastVisible: 2, disposed: false, restoring: false, restoreSerial: 0, zoomOwner: '',
    nextLoading: false, previousLoading: false, nextFailed: false, previousFailed: false,
    book: { chapters: new Array(20), chaptersDescending: descending },
    scroller: { isAtEnd: () => false, currentOffset: () => ({ yOffset: 100 }),
      scrollToIndex: () => assert.fail('joining chapters must not reposition the list') },
    loadPages: async i => { requests.push(i); return pages(i); },
    onPosition: (i, p, list) => positions.push([i, p, list.length]), events, requests, positions });
  r.source.reset(chapter.rows);
  r.source.registerDataChangeListener({ onDatasetChange: operations => {
    for (const op of operations) { assert.notEqual(op.type,'reload'); events.push([op.type,op.index,op.count]); }
  }, onDataAdd: () => assert.fail('per-row notifications are forbidden'),
    onDataDelete: () => assert.fail('per-row notifications are forbidden'), onDataReloaded: () => assert.fail('unexpected full reload') });
  return r;
}
(async () => {
  const r = reader();
  const first = r.source.getData(0);
  await r.loadNeighbor(true);
  assert.equal(r.source.getData(0), first, 'append retains original row identity');
  assert.equal(r.source.totalCount(), 12);
  assert.deepEqual(r.events, [['add',6,6]], 'one batch notification preserves the full appended range');
  const large = reader();
  large.loadPages = async i => Array.from({length:193},(_,n)=>({key:`large:${i}:${n}`,index:n}));
  await large.loadNeighbor(true);
  assert.deepEqual(large.events,[['add',6,193]],'a long chapter does not send 193 layout notifications');
  r.firstVisible = 7; r.reportPosition();
  assert.deepEqual(r.positions.at(-1), [3, 1, 6], 'progress is chapter-local');
  const reported = r.positions.length;
  r.reportPosition();
  assert.equal(r.positions.length, reported, 'same first-visible page does not repeat parent updates');
  r.firstVisible = 2; r.lastVisible = 4;
  const visible = r.source.getData(2);
  await r.loadNeighbor(false);
  assert.equal(r.firstVisible, 8);
  assert.equal(r.lastVisible, 10);
  assert.equal(r.source.getData(r.firstVisible), visible, 'prepend preserves visible anchor identity');
  assert.equal(r.source.getData(0).chapterIndex, 1);
  const reverse = reader(10, true);
  await reverse.loadNeighbor(true);
  await reverse.loadNeighbor(false);
  assert.deepEqual(reverse.requests, [11, 9], 'descending TOC cannot reverse chapter progression');

  const pending = reader();
  let finish;
  pending.loadPages = i => { pending.requests.push(i); return new Promise(resolve => { finish = resolve; }); };
  const task = pending.loadNeighbor(true);
  await Promise.resolve(); await Promise.resolve();
  await pending.loadNeighbor(true);
  assert.equal(pending.requests.length, 1, 'same boundary has one in-flight request');
  pending.serial++;
  finish(pages(3)); await task;
  assert.equal(pending.source.totalCount(), 6, 'reset discards stale response');

  const failed = reader();
  failed.loadPages = async () => { throw new Error('offline'); };
  await failed.loadNeighbor(true);
  assert.equal(failed.nextFailed, true);
  assert.equal(failed.source.totalCount(), 6, 'failure retains current images');
  failed.loadPages = async i => pages(i);
  await failed.loadNeighbor(true);
  assert.equal(failed.source.totalCount(), 6, 'failed boundary waits for retry');
  await failed.loadNeighbor(true, true);
  assert.equal(failed.nextFailed, false);
  assert.equal(failed.source.totalCount(), 12);

  const bounded = reader(0);
  for (let n = 0; n < 3; n++) await bounded.loadNeighbor(true);
  bounded.firstVisible = 19; bounded.lastVisible = 21;
  const anchor = bounded.source.getData(19);
  bounded.trimChapters();
  assert.equal(bounded.chapters.length, 3);
  assert.equal(bounded.source.getData(bounded.firstVisible), anchor, 'trim only removes offscreen chapters');
  assert.ok(bounded.events.some(e => e[0] === 'delete'));

  const parent = new scope.Parent();
  let saves = 0, resets = 0;
  Object.assign(parent, { busy: false, mode: 0, alive: true, chapterIndex: 2, book: {}, generation: 1,
    preparedComicChapters: new Map([[0, []], [10, []]]), pages: { setPages: () => resets++ },
    scheduleSave: () => saves++, preloadChapters() {}, protectComicCache() {},
    restorePage: () => assert.fail('visible progress must not reposition'),
    loadChapter: () => assert.fail('visible progress must not replace the chapter'), scrollResetToken: 9 });
  parent.onScrollPosition(3, 2, pages(3));
  assert.equal(parent.chapterIndex, 3);
  assert.equal(parent.pageIndex, 2);
  assert.equal(parent.pageCount, 6);
  assert.equal(parent.scrollResetToken, 9, 'normal crossing does not reset continuous reader');
  parent.onScrollPosition(3, 3, pages(3));
  assert.equal(resets, 1, 'paged datasource only switches when chapter actually changes');
  assert.equal(saves, 2);
  parent.onScrollPosition(3, 3, pages(3));
  assert.equal(saves, 2, 'unchanged visible position does not schedule another progress write');
  parent.mode = 1; parent.pageLayout = 2;
  parent.onScrollPosition(3, 3, pages(3), 0.45);
  assert.equal(saves, 3, 'moving inside the same long image saves progress');
  assert.equal(parent.pageFraction, 0.45);
  assert.equal(parent.preparedComicChapters.has(10), false);

  scope.PreferenceService.getPreloadChapters = async () => 0;
  const noPreload = reader();
  await noPreload.loadNeighbor(true);
  assert.equal(noPreload.requests.length, 0);
  noPreload.scroller.isAtEnd = () => true;
  await noPreload.loadNeighbor(true);
  assert.equal(noPreload.source.totalCount(), 12, 'disabled prefetch still permits boundary continuation');
  const keyReader = reader();
  const turns = [], frames = [];
  keyReader.getUIContext = () => ({ postFrameCallback: frame => frames.push(frame) });
  keyReader.scroller.scrollPage = options => turns.push(options.next);
  await keyReader.turnFromKey(true);
  await keyReader.turnFromKey(false);
  assert.deepEqual(turns, [true, false], 'long images move by viewport, without skipping to another image');
  keyReader.scroller.isAtEnd = () => true;
  await keyReader.turnFromKey(true);
  assert.equal(keyReader.source.totalCount(), 12, 'volume down appends next chapter even with prefetch off');
  assert.equal(turns.length, 2, 'wait for layout before scrolling appended content');
  frames.shift().callback();
  assert.deepEqual(turns, [true, false, true]);
  await keyReader.turnFromKey(true);
  keyReader.serial++;
  frames.shift().callback();
  assert.equal(turns.length, 3, 'stale layout callback cannot scroll after reset');
  keyReader.disposed = true;
  await keyReader.turnFromKey(false);
  assert.equal(turns.length, 3, 'leaving reader stops key scrolling');
  const joined = reader();
  joined.paged = true; joined.pageHeight = 800; joined.overlap = 20;
  let offset = 0;
  joined.scroller.scrollBy = (_x, y) => { offset += y; };
  await joined.turnFromKey(true); assert.equal(offset, 640);
  await joined.turnFromKey(false); assert.equal(offset, 0, 'forward/back preserve the same overlap');
  joined.zoomOwner = 'image'; await joined.turnFromKey(true); assert.equal(offset, 0);
  joined.zoomOwner = ''; joined.anchorFraction = 0.45;
  joined.source.getData(0).page.width = 600; joined.source.getData(0).page.height = 2400;
  const restoreFrames = [];
  joined.getUIContext = () => ({ postFrameCallback: frame => restoreFrames.push(frame) });
  joined.scroller.scrollToIndex = () => { offset = 0; };
  joined.scroller.getItemRect = () => ({ y: -offset, height: 1600 });
  joined.restoreVisible();
  restoreFrames.shift().callback(); restoreFrames.shift().callback(); restoreFrames.shift().callback();
  assert.equal(offset, 720, 'restores the fraction using the current image layout after resize');
  assert.equal(joined.anchorFraction, 0.45);
  joined.source.getData(0).page.width = 0;
  joined.restoreVisible(); restoreFrames.shift().callback(); restoreFrames.shift().callback(); restoreFrames.shift().callback();
  assert.equal(joined.awaitingImage, true, 'unknown image size cannot erase saved progress');
  joined.source.getData(0).page.width = 600;
  joined.imageGeometryReady(joined.source.getData(0));
  restoreFrames.shift().callback(); restoreFrames.shift().callback(); restoreFrames.shift().callback();
  assert.equal(offset, 720, 'restores after the downloaded image reports its actual size');
  joined.scroller.getItemIndex = () => 2;
  joined.scroller.getItemRect = index => ({ y: index === 2 ? -100 : 600, height: 500 });
  joined.reportPosition();
  assert.equal(joined.firstVisible, 2, 'chapter-end clamping reports the actual first image');
  assert.equal(joined.anchorFraction, 0.2);
  console.log('comic continuous: append/prepend anchors, chapter progress/order, request isolation, retry, trimming and disabled prefetch passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
