// Exercise real reader methods with deterministic page layouts and an in-memory Preferences adapter.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const values = new Map();
const events = new EventEmitter();
const mocks = {
  '../PreferenceService': { PreferenceService: { promoteFavorite: async () => {} } },
  '../../model/GeneralSettings': { GeneralSettings: { current: { historyEnabled: true } } },
  '@kit.InputKit': { KeyCode: { KEYCODE_VOLUME_UP: 16, KEYCODE_VOLUME_DOWN: 17,
    KEYCODE_PAGE_UP: 2012, KEYCODE_PAGE_DOWN: 2013, KEYCODE_DPAD_LEFT: 2014, KEYCODE_DPAD_RIGHT: 2015 } },
  '@kit.BasicServicesKit': { emitter: events },
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
  '@kit.ArkData': { preferences: { getPreferences: async () => ({
    getSync: (key, fallback) => values.get(key) ?? fallback,
    putSync: (key, value) => values.set(key, value),
    getAll: async () => Object.fromEntries(values),
    flush: async () => {}
  }) } }
};
function compile(relative, source) {
  const filename = path.join(root, relative + '.ets');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source ?? fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, require: name => mocks[name] || {}, setTimeout, clearTimeout, KeyType: { Down: 0, Up: 1 }, ScrollAlign: { START: 0 } }, { filename });
  return exports;
}
const subscriptions = new Map();
let subscribeCount = 0;
let rejectDown = false;
mocks['@kit.InputKit'].inputConsumer = {
  on(type, options, handler) {
    assert.equal(type, 'keyPressed');
    assert.equal(options.action, 1);
    assert.equal(options.isRepeat, false);
    if (rejectDown && options.key === 17) throw new Error('subscription rejected');
    subscriptions.set(handler, options.key); subscribeCount++;
  },
  off(type, handler) { assert.equal(type, 'keyPressed'); subscriptions.delete(handler); }
};
const { ReaderVolumeKeyService } = compile('service/text/ReaderVolumeKeyService');
const { ReaderAutoPageService } = compile('service/text/ReaderAutoPageService');
mocks['../service/text/ReaderAutoPageService'] = { ReaderAutoPageService };
const volumeKeys = new ReaderVolumeKeyService();
const directions = [];
volumeKeys.setEnabled(true, forward => directions.push(forward));
assert.equal(subscriptions.size, 2, 'volume keys use distinct system consumer callbacks');
for (const handler of subscriptions.keys()) handler();
assert.deepEqual(directions, [false, true]);
volumeKeys.setEnabled(true, forward => directions.push(forward));
assert.equal(subscribeCount, 2, 'toolbar changes must not duplicate subscriptions');
volumeKeys.setEnabled(false, () => {});
assert.equal(subscriptions.size, 0, 'modal/disabled state restores system volume behavior');
volumeKeys.setEnabled(true, () => {});
volumeKeys.dispose();
assert.equal(subscriptions.size, 0, 'leaving reader releases both volume keys');
rejectDown = true;
volumeKeys.setEnabled(true, () => {});
assert.equal(subscriptions.size, 0, 'partial subscription failure rolls back the first key');
rejectDown = false;
mocks['../utils/ReaderTapPolicy'] = compile('utils/ReaderTapPolicy');
mocks['../utils/AdaptiveLayout'] = compile('utils/AdaptiveLayout');
mocks['./ReaderTheme'] = compile('model/ReaderTheme');
mocks['../model/ReaderTheme'] = mocks['./ReaderTheme'];
const model = compile('model/TextReading');
mocks['../model/TextReading'] = model;
mocks['../service/text/LocalTextImage'] = compile('service/text/LocalTextImage');
let importedBody = '';
mocks['../service/DataService'] = { DataService: { readImportedText: async () => importedBody } };
mocks['../../model/TextReading'] = model;
mocks['../service/text/OnlineTextPaginator'] = compile('service/text/OnlineTextPaginator');
mocks['./OnlineTextPaginator'] = mocks['../service/text/OnlineTextPaginator'];
const { TextReadingProgressService: progress } = compile('service/text/TextReadingProgressService');
mocks['../service/text/TextReadingProgressService'] = { TextReadingProgressService: progress };
mocks['../service/text/ReaderFontService'] = { ReaderFontService: { register: () => 'ReaderFont_Custom' } };
mocks['../service/text/TextToSpeechService'] = { TextToSpeechService: {
  getInstance: () => ({ state: { playing: false }, setReadingPageEnds() {} })
} };
mocks['../service/ReadingSessionService'] = {
  SessionLocation: { text: () => ({}) }, ReadingSessionService: { checkpoint() {} }
};
let systemBottomVp = 0;
mocks['../utils/WindowUtils'] = { WindowUtils: { getSystemBottomVp: () => systemBottomVp } };
let source = fs.readFileSync(path.join(root, 'pages/ReaderPage.ets'), 'utf8');
const readerBottomMethods = source.slice(source.indexOf('  private readerTopInsetVp()'),
  source.indexOf('  private readerFloatingStyle()'));
const chapterNavigationMethods = source.slice(source.indexOf('  private adjacentChapterIndex('),
  source.indexOf('  private chapterSliderIndex('));
source = source.slice(0, source.search(/\s*@Builder\s+readerTabStyle\(/)) + '\n' + readerBottomMethods +
  '\n' + chapterNavigationMethods + '\n}';
source = source.replace(/^  @Builder[\s\S]*?^  }\r?$/gm, '');
source = source.replace('@ComponentV2', '').replace('export struct', 'export class')
  .replace(/@(Param|Local)\s+/g, '').replace(/  @Monitor\([\s\S]*?\)\s*/g, '');
const { ReaderPage } = compile('pages/ReaderPage', source);
const { TextReadingPosition, PageTurnMode } = model;
const navigationReader = Object.create(ReaderPage.prototype);
Object.assign(navigationReader, { book: { chaptersDescending: true, chapters: [{}, {}, {}] },
  currentResourceIndex: 1, jumpingResourceIndex: -1, isOnlineTextBook: () => true });
assert.equal(navigationReader.adjacentChapterIndex(true), 2, 'next follows body order with a descending TOC');
assert.equal(navigationReader.adjacentChapterIndex(false), 0);
assert.equal(navigationReader.canSwitchChapter(true), true);
navigationReader.currentResourceIndex = 2;
assert.equal(navigationReader.canSwitchChapter(true), false, 'final chapter cannot advance');
assert.equal(navigationReader.canSwitchChapter(false), true);
navigationReader.currentResourceIndex = 0;
assert.equal(navigationReader.canSwitchChapter(false), false, 'first chapter cannot rewind');
assert.equal(navigationReader.canSwitchChapter(true), true);
const bottomReader = Object.create(ReaderPage.prototype);
Object.assign(bottomReader, { pageTurnMode: PageTurnMode.Vertical, bottomSafeVp: 32, marginBottom: 12 });
assert.equal(bottomReader.readerTextBottomPaddingVp(), 16, 'scroll footer shares gesture and reading spacing');
bottomReader.marginBottom = 40;
assert.equal(bottomReader.readerTextBottomPaddingVp(), 40, 'explicit large reading margin is preserved');
bottomReader.marginBottom = 0;
assert.equal(bottomReader.readerTextBottomPaddingVp(), 16, 'zero margin retains gesture clearance');
bottomReader.bottomSafeVp = 0;
assert.equal(bottomReader.readerTextBottomPaddingVp(), 8, 'landscape retains minimum clearance');
systemBottomVp = 48;
bottomReader.bottomSafeVp = 48;
bottomReader.marginBottom = 12;
assert.equal(bottomReader.readerTextBottomPaddingVp(), 60, 'solid navigation bar is fully avoided');
systemBottomVp = 0;
bottomReader.bottomSafeVp = 32;
bottomReader.pageTurnMode = PageTurnMode.Cover;
assert.equal(bottomReader.readerTextBottomPaddingVp(), 16, 'paged footer shares gesture and reading spacing');
Object.assign(bottomReader, { alwaysShowStatusBar: false, topSafeVp: 30, cutoutTopSafeVp: 0,
  readerViewportWidthVp: 800, readerViewportHeightVp: 400 });
assert.equal(bottomReader.readerTopInsetVp(), 16, 'hidden-status landscape header clears the camera-free corner');
bottomReader.topSafeVp = 0;
assert.equal(bottomReader.readerTopInsetVp(), 16, 'temporary status bar visibility cannot shift the header');
bottomReader.cutoutTopSafeVp = 24;
assert.equal(bottomReader.readerTopInsetVp(), 24, 'actual camera clearance remains protected');
bottomReader.readerViewportWidthVp = 300;
bottomReader.cutoutTopSafeVp = 0;
assert.equal(bottomReader.readerTopInsetVp(), 0, 'portrait does not inherit the landscape gap');
bottomReader.alwaysShowStatusBar = true;
bottomReader.topSafeVp = 30;
assert.equal(bottomReader.readerTopInsetVp(), 30, 'always-visible status bar uses its measured height');
const keyReader = Object.create(ReaderPage.prototype);
Object.assign(keyReader, { volumeKeyPageTurn: false, readerVisible: true, leaving: false, loading: false,
  autoPage: new ReaderAutoPageService(), autoPageRunning: false,
  readerError: '', keyTurnRequest: 0, screenOn: { touch() {} }, isOnlineTextBook: () => true });
assert.equal(keyReader.canUseVolumeKeys(), false);
keyReader.volumeKeyPageTurn = true;
for (const visible of [true, false]) {
  keyReader.readerBarVisible = visible;
  assert.equal(keyReader.canUseVolumeKeys(), true, 'toolbar visibility must not govern key consumption');
  keyReader.handleVolumePageTurn(true);
  assert.ok(keyReader.keyTurnRequest > 0);
  keyReader.handleVolumePageTurn(false);
  assert.ok(keyReader.keyTurnRequest < 0);
}
for (const field of ['showSettingsSheet', 'showChapterSheet', 'showSpeechSheet', 'showSourceSwitch',
  'showBookmarkSheet', 'showReplaceSheet', 'showReaderMenu', 'pickingFont', 'pickingBackgroundImage', 'loading', 'leaving']) {
  const request = keyReader.keyTurnRequest;
  keyReader[field] = true;
  assert.equal(keyReader.canUseVolumeKeys(), false, field);
  keyReader.handleVolumePageTurn(true);
  assert.equal(keyReader.keyTurnRequest, request);
  keyReader[field] = false;
}
keyReader.readerVisible = false;
assert.equal(keyReader.canUseVolumeKeys(), false);
// External keyboard does not depend on volume-key preference and must not steal modal input.
Object.assign(keyReader, { readerVisible: true, readerBarVisible: false, volumeKeyPageTurn: false });
let consumed = 0;
const keyboardEvent = keyCode => ({ type: 0, keyCode, stopPropagation() { consumed++; } });
keyReader.handleReaderKey(keyboardEvent(2013));
assert.ok(keyReader.keyTurnRequest > 0);
keyReader.handleReaderKey(keyboardEvent(2014));
assert.ok(keyReader.keyTurnRequest < 0);
assert.equal(consumed, 2);
for (const field of ['readerBarVisible', 'showSettingsSheet', 'showChapterSheet', 'showSpeechSheet', 'showSourceSwitch']) {
  const before = keyReader.keyTurnRequest;
  keyReader[field] = true;
  keyReader.handleReaderKey(keyboardEvent(2013));
  assert.equal(keyReader.keyTurnRequest, before, `${field} retains keyboard control`);
  keyReader[field] = false;
}
assert.equal(consumed, 2);
// Real ReaderKit settings must follow the window, including density on an external display.
const windowReader = Object.create(ReaderPage.prototype);
Object.assign(windowReader, { readerViewportWidthVp: 1200, readerViewportHeightVp: 700,
  marginLeft: 16, marginRight: 24, leftSafeVp: 0, rightSafeVp: 0, marginTop: 12,
  fontSize: 20, lineHeight: 1.5, palette: { primary: '#000000', background: '#ffffff', isDark: false },
  getUIContext: () => ({ vp2px: value => value * 2, fp2px: value => value * 2.4 }),
  readerTopInsetVp: () => 30, readerTextBottomPaddingVp: () => 16, readerFooterHeight: () => 24 });
let windowSettings = windowReader.createReaderSetting();
assert.equal(windowSettings.viewPortWidth, 760 * 2, 'large-screen reading line width is bounded');
assert.equal(windowSettings.viewPortHeight, (700 - 30 - 16 - 24) * 2);
windowReader.readerViewportWidthVp = 360;
windowReader.readerViewportHeightVp = 500;
windowSettings = windowReader.createReaderSetting();
assert.equal(windowSettings.viewPortWidth, (360 - 16 - 24) * 2, 'split window restores phone content width');
assert.equal(windowSettings.viewPortHeight, (500 - 30 - 16 - 24) * 2);
assert.equal(windowReader.marginLeft, 16, 'automatic gutter never overwrites user preferences');
assert.equal(windowReader.marginRight, 24);
const content = '文'.repeat(300);
const pages = starts => starts.map((startOffset, index) => ({
  startOffset, endOffset: starts[index + 1] ?? content.length,
  text: content.slice(startOffset, starts[index + 1] ?? content.length)
}));
const normal = pages([0, 100, 200]);
const expanded = pages([0, 110, 220]);
function reader() {
  // Skip ArkUI construction, retaining the actual progress, load, reflow and turn methods.
  const page = Object.create(ReaderPage.prototype);
  Object.assign(page, {
    autoPage: new ReaderAutoPageService(), autoPageRunning: false,
    context: {}, textDocuments: new Map(), book: { id: 'test-book', chapters: [{ title: '第一章' }, { title: '第二章' }] },
    readingTime: { checkpoint() {} },
    speechState: { active: false, bookId: '' },
    pageTurnMode: PageTurnMode.Cover, currentResourceIndex: 0, currentChapterTitle: '第一章',
    onlineTextContent: content, onlineTextPages: normal, onlineTextPageIndex: 1,
    onlineTextTurnSerial: 0, onlineTextLoadSerial: 0, onlineTextTurnPreview: null,
    onlineTextTurnConfirmed: false, onlineTextTurnLoading: false, leaving: false,
    currentPosition: TextReadingPosition.atChar('test-book', 0, '', 100, 1, '第一章'),
    isOnlineTextBook: () => true, paginateOnlineTextContent: () => expanded,
    prefetchAdjacentOnlineTextChapters() {}, getOnlineTextChapterContent: async () => content
  });
  return page;
}
const tick = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const { LocalTextImage } = mocks['../service/text/LocalTextImage'];
  const tokens = [0, 1, 2].map(index => LocalTextImage.token(`/files/ebooks/import_pdf/image_${index}_0.img`));
  importedBody = '前言\n' + tokens.join('\n说明\n');
  for (const [imageIndex, expectedIndex] of [[0, 0], [1, 1], [2, 2], [99, 2]]) {
    const comicReturn = reader();
    const book = { id: 'import_pdf', chapters: [{ title: '原版页面', source: { value: '/files/ebooks/import_pdf/0.txt' } }] };
    comicReturn.book = book;
    let restoredOffset = -1;
    comicReturn.loadOnlineTextChapter = async (_chapter, offset) => { restoredOffset = offset; return false; };
    await comicReturn.prepareOnlineTextReader(book, TextReadingPosition.of(book.id, 0, 'comic:scroll@0.5', imageIndex, '原版页面'));
    assert.equal(restoredOffset, importedBody.indexOf(tokens[expectedIndex]), 'comic image position must restore the same image in text layout');
  }
  console.log('PASS comic-to-reader restores image character positions, including an out-of-range old page');
  const fontPage = reader();
  fontPage.fontPath = '/files/reader_fonts/custom.ttf';
  fontPage.fontName = 'Custom';
  fontPage.fontFamily = 'ReaderFont_Custom';
  fontPage.saveReadingSettings = () => {};
  fontPage.selectReaderFont({ path: '', name: '' });
  assert.equal(fontPage.fontFamily, '', 'system selection removes the imported font override');
  assert.equal(fontPage.fontPath, '');
  assert.equal(fontPage.currentPosition.charOffset, 100, 'system font reflow preserves the reading position');
  fontPage.selectReaderFont({ path: '/files/reader_fonts/custom.ttf', name: 'Custom' });
  assert.equal(fontPage.fontFamily, 'ReaderFont_Custom');
  assert.equal(fontPage.currentPosition.charOffset, 100);

  const typographyStart = source.indexOf('  private systemTypographyKey:');
  const typographyEnd = source.indexOf('  holdingHandSide:', typographyStart);
  assert.ok(typographyStart >= 0 && typographyEnd > typographyStart);
  mocks['../service/text/ReadingTimeTracker'] = compile('service/text/ReadingTimeTracker');
  const { Typography } = compile('pages/ReaderPage', `import { OnlineTextPaginator } from '../service/text/OnlineTextPaginator';
  import { ReadingTimeTracker } from '../service/text/ReadingTimeTracker';
  export class Typography {
    ${source.slice(typographyStart, typographyEnd)}
  }`);
  const typography = new Typography();
  let typographyReflows = 0;
  Object.assign(typography, {
    context: { config: { fontId: 'system-A', fontSizeScale: 1, fontWeightScale: 1 } },
    leaving: false, systemTypographyRevision: 0,
    scheduleReaderSettingsRefresh() { typographyReflows++; }
  });
  typography.systemTypographyKey = typography.currentSystemTypographyKey();
  typography.typographyChangeHandler();
  assert.equal(typographyReflows, 0, 'foreground without a font change keeps the existing layout');
  typography.context.config.fontId = 'system-B';
  typography.typographyChangeHandler();
  assert.equal(typographyReflows, 1, 'system font changes schedule a reflow');
  assert.equal(typography.systemTypographyRevision, 1, 'font change invalidates captured page turns');
  typography.context.config.fontSizeScale = 1.2;
  typography.typographyChangeHandler();
  assert.equal(typographyReflows, 2, 'system text scaling also refreshes layout');
  typography.leaving = true;
  typography.context.config.fontId = 'system-C';
  typography.typographyChangeHandler();
  assert.equal(typographyReflows, 2, 'disposed reader ignores subsequent font changes');

  const stable = reader();
  let layoutRefreshes = 0;
  Object.assign(stable, {
    readerViewportWidthVp: 400, readerViewportHeightVp: 800,
    updateMarginTopMax() {}, scheduleReaderSettingsRefresh() { layoutRefreshes++; }
  });
  const viewport = { width: 400, height: 800 };
  stable.handleViewportSizeChange(viewport, { width: 0, height: 0 });
  stable.handleViewportSizeChange({ width: 0, height: 0 }, viewport);
  assert.equal(layoutRefreshes, 0, 'a hidden zero-sized viewport followed by the same viewport must not reflow');
  assert.equal(stable.currentPosition.charOffset, 100);
  stable.handleViewportSizeChange(viewport, { width: 600, height: 800 });
  assert.equal(layoutRefreshes, 1, 'a real window resize must still refresh pagination');

  const page = reader();
  const dragging = reader();
  let reflows = 0;
  let saves = 0;
  Object.assign(dragging, { fontSize: 18, lineHeight: 1.9,
    cancelReaderSettingsRefresh() {}, applyReadingSettings() { reflows++; }, saveReadingSettings() { saves++; } });
  for (let size = 19; size <= 35; size++) dragging.handleFontSizeChange(size, false);
  assert.equal(reflows, 0, 'slider movement must not synchronously repaginate the chapter');
  assert.equal(dragging.fontSize, 18, 'mounted text keeps its previous geometry while dragging');
  assert.equal(dragging.previewFontSize, 35);
  dragging.handleFontSizeChange(35, true);
  assert.equal(reflows, 1);
  assert.equal(saves, 1);
  assert.equal(dragging.fontSize, 35);
  assert.equal(dragging.previewFontSize, 0);
  dragging.handleLineHeightChange(2.2, false);
  assert.equal(reflows, 1);
  dragging.handleLineHeightChange(2.2, true);
  assert.equal(reflows, 2);
  assert.equal(dragging.currentPosition.charOffset, 100);
  for (let repeat = 0; repeat < 3; repeat++) {
    page.paginateOnlineTextContent = () => expanded;
    page.repaginateOnlineText();
    assert.equal(page.currentPosition.charOffset, 100, 'temporary viewport must preserve the reading anchor');
    page.saveProgress();
    await tick();
    assert.equal((await progress.get({}, 'test-book')).charOffset, 100, 'background save must keep the confirmed character');
    page.paginateOnlineTextContent = () => normal;
    page.repaginateOnlineText();
    assert.equal(page.onlineTextPageIndex, 1, 'returning to the same viewport must restore the same page');
  }

  const reopened = reader();
  const saved = await progress.get({}, 'test-book');
  await reopened.loadOnlineTextChapter(saved.resourceIndex, saved.charOffset, saved.pageOffset, false, true);
  assert.equal(reopened.currentPosition.charOffset, 100, 'initial loading must preserve saved offset until layout settles');
  reopened.paginateOnlineTextContent = () => normal;
  reopened.repaginateOnlineText();
  assert.equal(reopened.onlineTextPageIndex, 1, 'reopening with an interim layout must not move back a page');

  const { ReaderTextDocument, ReaderTextStage, ReaderTextEdit } = compile('model/ReaderTools');
  const document = ReaderTextDocument.original('广告'.repeat(50) + content);
  document.content = content;
  const stage = new ReaderTextStage();
  const edit = new ReaderTextEdit();
  edit.start = 0; edit.end = 100; edit.length = 0; stage.edits = [edit]; document.stages = [stage];
  const replaced = reader();
  replaced.textDocuments.set(0, document);
  replaced.saveProgress(); await tick();
  assert.equal((await progress.get({}, 'test-book')).charOffset, 200, 'progress persists original coordinates after removing ads');
  await replaced.loadOnlineTextChapter(0, 200, 2, false, true);
  assert.equal(replaced.currentPosition.charOffset, 100, 'restoration maps original coordinates into the current text');
  replaced.repaginateOnlineText();
  assert.equal(replaced.persistedPosition().charOffset, 200, 'font/window reflow retains the original anchor');
  await replaced.loadOnlineTextChapter(0, 50, 2, false, true);
  assert.equal(replaced.onlineTextPageIndex, 0, 'a deleted saved anchor maps to page zero instead of reusing a stale page number');

  const confirmed = reader();
  confirmed.onlineTextTurnPreview = { chapterIndex: 1, pageIndex: 1, content, pages: normal };
  confirmed.onlineTextTurnConfirmed = true;
  confirmed.repaginateOnlineText();
  assert.equal(confirmed.currentResourceIndex, 1, 'confirmed cross-chapter turn must survive reflow before animation finishes');
  assert.equal(confirmed.currentPosition.charOffset, 100);
  confirmed.paginateOnlineTextContent = () => normal;
  confirmed.repaginateOnlineText();
  assert.equal(confirmed.onlineTextPageIndex, 1);

  const cancelled = reader();
  cancelled.onlineTextTurnPreview = { chapterIndex: 1, pageIndex: 1, content, pages: normal };
  cancelled.repaginateOnlineText();
  assert.equal(cancelled.currentResourceIndex, 0, 'unconfirmed drag must keep the original chapter');
  assert.equal(cancelled.currentPosition.charOffset, 100);

  page.onlineTextPageIndex = 2;
  page.updateOnlineTextPosition(true);
  await tick();
  assert.equal((await progress.get({}, 'test-book')).charOffset, 200, 'a deliberate turn must advance the saved anchor');
  const scrollModel = compile('service/text/OnlineTextScrollDataSource');
  mocks['../service/text/OnlineTextScrollDataSource'] = scrollModel;
  let continuousSource = fs.readFileSync(path.join(root, 'components/ReaderContinuousComponent.ets'), 'utf8');
  continuousSource = continuousSource.slice(0, continuousSource.indexOf('  @Builder')) + '\n}';
  continuousSource = continuousSource.replace('@ComponentV2', '').replace('export struct', 'export class')
    .replace(/@(Param|Local|Event)\s+/g, '').replace(/@Monitor\([^\n]+\)\s*/g, '');
  const { ReaderContinuousComponent } = compile('components/ReaderContinuousComponent', continuousSource);
  const continuous = Object.create(ReaderContinuousComponent.prototype);
  const makeChapter = index => scrollModel.OnlineTextScrollChapter.create(index, `chapter-${index}`,
    `Chapter ${index}`, content, expanded);
  let positioned = -1;
  let reported = -1;
  Object.assign(continuous, {
    autoScroll: { stop() {} }, autoScrollReady: false,
    contentWidth: 360, disposed: false, serial: 0, restoreTimer: -1, positionTimer: -1,
    chapters: [makeChapter(9), makeChapter(10), makeChapter(11)],
    chapterIndex: 10, charOffset: 150, content, source: new scrollModel.OnlineTextScrollDataSource(),
    makeChapter, scroller: { scrollToIndex: index => { positioned = index; } },
    onPosition: chapter => { reported = chapter; }, loadNeighbor() {}
  });
  continuous.reset();
  continuous.visibleChanged(0, 2); // platform's stale pre-layout callback
  assert.equal(reported, -1, 'old list indexes must not overwrite the restored chapter');
  assert.equal(continuous.chapters.length, 3, 'font reflow retains already loaded neighbors');
  // reset() restores through setTimeout(0); setImmediate can run before that timer.
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.ok(positioned >= 0, 'the restore timer must position the list before checking its row');
  assert.equal(continuous.source.getData(positioned).chapterIndex, 10);
  assert.equal(continuous.source.getData(positioned).startOffset, 110);
  continuous.visibleChanged(positioned, positioned + 2);
  continuous.reportPosition(true);
  assert.equal(reported, 10, 'font change stays in the current chapter');
  let positionReports = 0;
  let persisted = false;
  continuous.onPosition = (_chapter, _offset, _content, persist) => { positionReports++; persisted = persist; };
  for (let i = 0; i < 20; i++) continuous.visibleChanged(positioned, positioned + 2);
  assert.equal(positionReports, 0, 'scroll callbacks must not synchronously update the parent');
  await new Promise(resolve => setTimeout(resolve, 180));
  assert.equal(positionReports, 1, 'rapid scroll callbacks share one progress update');
  continuous.visibleChanged(positioned, positioned + 2);
  continuous.backgroundHandler = () => continuous.reportPosition(true);
  continuous.aboutToAppear();
  events.emit('app.reader.background');
  assert.equal(persisted, true, 'backgrounding immediately persists the latest visible position');
  assert.equal(continuous.positionTimer, -1, 'background flush cancels pending progress update');
  continuous.aboutToDisappear();
  const short = Object.create(ReaderContinuousComponent.prototype);
  Object.assign(short, {
    autoScroll: { stop() {} }, autoScrollReady: false,
    contentWidth: 360, contentHeight: 800, rowHeight: 34, disposed: false, serial: 0,
    restoreTimer: -1, positionTimer: -1, chapters: [], chapterIndex: 0, charOffset: 0,
    chapterCount: 30, chapterStep: 1, content: '短章', source: new scrollModel.OnlineTextScrollDataSource(),
    makeChapter: index => scrollModel.OnlineTextScrollChapter.create(index, `short-${index}`, '扉页', '短章',
      [mocks['./OnlineTextPaginator'].OnlineTextPage.of('短章', 0, 2)]),
    scroller: { scrollToIndex() {} }, getContent: async () => '短章', onPosition() {}, backgroundHandler() {},
    onAutoPageDelay() {}
  });
  short.reset();
  short.visibleChanged(0, 1);
  assert.equal(short.restoring, true, 'ignore callbacks before restore scroll is issued');
  await new Promise(resolve => setTimeout(resolve, 10));
  assert.ok(short.chapters.length > 5, 'short chapters fill the viewport even while restoring');
  assert.ok(short.chapters.length <= short.chapterLimit(), 'loading stays bounded');
  short.visibleChanged(0, short.source.totalCount() - 1);
  assert.equal(short.restoring, false, 'bottom-clamped target visible on screen releases restore lock');
  short.aboutToDisappear();
  console.log('PASS: system/custom font selection, typography changes, repeated Home/layout restoration, saved-position reload, confirmed cross-chapter turn, cancelled drag, deliberate page turn');
})().catch(error => { console.error(error); process.exitCode = 1; });
