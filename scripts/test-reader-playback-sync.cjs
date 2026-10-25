const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
function compile(source, mocks, globals = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText, { exports, require: name => mocks[name] || {}, ...globals });
  return exports;
}
const tick = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const coordinator = { speechActive: false };
  const playerSource = fs.readFileSync(path.join(root, 'pages/PlayerPage.ets'), 'utf8');
  const seekStart = playerSource.indexOf('  private changeSpeechProgress(');
  const seekMethod = playerSource.slice(seekStart, playerSource.indexOf('\n  }', seekStart) + 4);
  const progressCalls = [];
  const modes = { Begin: 0, Moving: 1, End: 2, Click: 3 };
  const { ProgressPlayer } = compile('export class ProgressPlayer {\n' + seekMethod + '\n}', {}, {
    SliderChangeMode: modes,
    TextToSpeechService: { getInstance: () => ({ seekProgress: value => progressCalls.push(value) }) }
  });
  const progressPlayer = new ProgressPlayer();
  progressPlayer.speechState = { bookId: 'book', chapterIndex: 0 };
  progressPlayer.canSkipPlayback = () => true;
  progressPlayer.changeSpeechProgress(10, modes.Begin);
  progressPlayer.changeSpeechProgress(40, modes.Moving);
  assert.equal(progressCalls.length, 0, 'drag previews must not repeatedly restart synthesis');
  progressPlayer.changeSpeechProgress(60, modes.End);
  assert.deepEqual(progressCalls, [60], 'release commits once');
  progressPlayer.changeSpeechProgress(20, modes.Begin);
  progressPlayer.speechState.chapterIndex = 1;
  progressPlayer.changeSpeechProgress(70, modes.End);
  assert.deepEqual(progressCalls, [60], 'chapter change during drag discards stale target');
  progressPlayer.changeSpeechProgress(25, modes.Click);
  assert.deepEqual(progressCalls, [60, 25], 'click seeks directly');
  progressPlayer.changeSpeechProgress(20, modes.Begin);
  progressPlayer.speechState.bookId = 'other';
  progressPlayer.changeSpeechProgress(80, modes.End);
  assert.deepEqual(progressCalls, [60, 25], 'book change during drag discards stale target');
  // Execute the actual ReaderPage navigation methods without its ArkUI builder.
  const readerSource = fs.readFileSync(path.join(root, 'pages/ReaderPage.ets'), 'utf8');
  const methodNames = ['syncSpeechPosition', 'followReadingWithSpeech', 'beginContinuousSpeechTurn',
    'updateContinuousPosition', 'completeOnlineTextTurn', 'readFromParagraph', 'startReaderSpeech'];
  const methods = methodNames.map(name => {
    const start = readerSource.search(new RegExp('  private (?:async )?' + name + '\\('));
    assert.ok(start >= 0, name);
    return readerSource.slice(start, readerSource.indexOf('\n  }', start) + 4);
  }).join('\n');
  const speechCalls = [];
  const speech = { state: { active: true, bookId: 'book', playing: true, loading: false },
    setReadingPageEnds() {}, initialize: async () => {}, start: async (...args) => { speechCalls.push(args); } };
  const { ReaderNavigation } = compile('export class ReaderNavigation {\n' + methods + '\n}', {}, {
    TextToSpeechService: { getInstance: () => speech },
    PageTurnMode: { Vertical: 'vertical' },
    OnlineTextPaginator: { pageIndexForOffset: (_pages, offset) => Math.floor(offset / 100) },
    TextReadingPosition: { atChar: (bookId, resourceIndex, domPos, charOffset) => ({ bookId, resourceIndex, charOffset }) }
  });
  const reader = new ReaderNavigation();
  Object.assign(reader, { book: { id: 'book' }, bookId: 'book', readerVisible: true, speechNavigationSerial: 0,
    speechState: speech.state, readingTime: { checkpoint() {} }, currentResourceIndex: 0,
    onlineTextContent: 'text', onlineTextPages: [], onlineTextPageIndex: 0,
    isOnlineTextBook: () => true, currentRawCharOffset: () => 120,
    currentOnlineTextCharOffset: () => 0, hideReaderBar() {}, saveProgress() {},
    chapterTitle: index => String(index), paginateOnlineTextContent: () => [],
    updateSpeechPageEnds() {}, updateOnlineTextPosition() {}, prefetchAdjacentOnlineTextChapters() {} });
  const preview = { content: 'next', pages: [], pageIndex: 3, chapterIndex: 1 };
  reader.onlineTextTurnPreview = preview;
  reader.completeOnlineTextTurn(false);
  assert.equal(speechCalls.length, 0, 'cancelled swipe must not seek speech');
  reader.onlineTextTurnPreview = preview;
  reader.completeOnlineTextTurn(true);
  assert.deepEqual(speechCalls.at(-1), [reader.book, 1, 120], 'committed page seeks using raw offset');
  speech.state.charOffset = 0; speech.state.chapterIndex = 0;
  reader.syncSpeechPosition();
  assert.equal(reader.currentResourceIndex, 1, 'late speech callbacks cannot pull the chapter back');
  assert.equal(reader.onlineTextPageIndex, 3, 'late speech callbacks cannot pull the page back');
  speech.state.playing = false;
  reader.followReadingWithSpeech();
  assert.equal(speechCalls.length, 1, 'paused session must not resume on navigation');
  speech.state.loading = true;
  reader.followReadingWithSpeech();
  assert.equal(speechCalls.length, 2, 'new page replaces an in-flight speech request');
  speech.state.bookId = 'other'; reader.followReadingWithSpeech();
  assert.equal(speechCalls.length, 2, 'navigation must not hijack another book');
  speech.state.bookId = 'book';
  reader.beginContinuousSpeechTurn();
  reader.updateContinuousPosition(1, 50, 'next', false);
  assert.equal(speechCalls.length, 2, 'scrolling must not restart synthesis on each position event');
  reader.updateContinuousPosition(1, 100, 'next', true);
  assert.equal(speechCalls.length, 3, 'scroll stop seeks once');
  reader.updateContinuousPosition(1, 100, 'next', true);
  assert.equal(speechCalls.length, 3, 'duplicate persistence events must not seek again');
  const { SpeechTextHighlighter } = compile(fs.readFileSync(path.join(root, 'service/text/SpeechTextHighlighter.ets'), 'utf8'), {});
  assert.equal(SpeechTextHighlighter.sourceOffset('　　第一段\n　　第二段', '第一段\n第二段', 10), 6);
  assert.equal(SpeechTextHighlighter.sourceOffset('　　😀正文', '😀正文', 3), 0, 'selection never splits a surrogate pair');
  Object.assign(reader, { context: {}, speechSelectionSerial: 0, readerVisible: true,
    book: { id: 'book', chapters: [{}, {}, {}] }, textDocuments: new Map(),
    getOnlineTextChapterContent: async () => '上一段。\n目标段第一句。目标段第二句。\n下一段。' });
  reader.textDocuments.set(2, { toRaw: offset => offset + 40 });
  await reader.readFromParagraph(2, 14);
  assert.deepEqual(speechCalls.at(-1), [reader.book, 2, 45], 'selection starts the whole paragraph with raw-coordinate mapping');
  const selectedCount = speechCalls.length;
  let finishSelectedContent;
  reader.getOnlineTextChapterContent = () => new Promise(resolve => { finishSelectedContent = resolve; });
  const pendingSelection = reader.readFromParagraph(1, 5);
  reader.readerVisible = false;
  finishSelectedContent('第一段。\n第二段。');
  await pendingSelection;
  assert.equal(speechCalls.length, selectedCount, 'leaving the page while resolving selection must not start speech');
  await tick();
  Object.assign(reader, { readerVisible: true, speechNavigationPending: false, speechScrollPending: false,
    selectingText: false, onlineTextLoading: false, onlineTextTurnPreview: null,
    currentResourceIndex: 1, speechPageFloorChapter: 1, speechPageFloor: 200 });
  Object.assign(speech.state, { chapterIndex: 1, charOffset: 180, playing: true, loading: false });
  reader.syncSpeechPosition();
  assert.equal(reader.onlineTextPageIndex, 2, 'sentence beginning on prior page must not undo manual page turn');
  speech.state.charOffset = 310;
  reader.syncSpeechPosition();
  assert.equal(reader.onlineTextPageIndex, 3, 'natural speech progression automatically turns to next page');
  assert.equal(reader.speechFollowOffset, 310, 'continuous reader follows the same speech coordinate');
  reader.speechScrollPending = true;
  speech.state.charOffset = 410;
  reader.syncSpeechPosition();
  assert.equal(reader.onlineTextPageIndex, 3, 'manual scrolling temporarily owns navigation');
  reader.speechScrollPending = false;
  speech.state.playing = false;
  reader.syncSpeechPosition();
  assert.equal(reader.onlineTextPageIndex, 3, 'paused speech does not move the reader');
  const chapterLoads = [];
  reader.loadOnlineTextChapter = (...args) => chapterLoads.push(args);
  speech.currentRawOffset = () => 45;
  speech.state.playing = true; speech.state.chapterIndex = 2;
  reader.syncSpeechPosition();
  assert.deepEqual(chapterLoads[0], [2, 45, 0, false, false], 'natural chapter transitions load next chapter');
  const { AVSessionService } = compile(fs.readFileSync(path.join(root, 'service/AVSessionService.ets'), 'utf8'), {
    './PlaybackCoordinator': { PlaybackCoordinator: coordinator },
    '@kit.AVSessionKit': { avSession: { LoopMode: {} } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn() {}, error() {} } }
  });
  const session = new AVSessionService();
  const placeholder = { id: 'placeholder' };
  const updates = [];
  const covers = new Map();
  session.session = { setAVMetadata: async data => updates.push({ ...data }) };
  session.loadCover = cover => cover === 'avsession://cover-placeholder'
    ? Promise.resolve(placeholder) : new Promise(resolve => covers.set(cover, resolve));
  const book = id => ({ id, title: id, author: 'author', cover: 'https://cover/' + id });
  const chapter = { id: 'chapter', title: 'chapter title', duration: 0 };
  const a = session.updateMetadata(book('A'), chapter);
  await tick();
  assert.equal(updates.at(-1).artist, 'A', 'publish title before stalled cover');
  assert.equal(updates.at(-1).mediaImage, placeholder);
  const b = session.updateMetadata(book('B'), chapter);
  await tick();
  assert.equal(updates.at(-1).artist, 'B');
  await session.updateMetadataDuration(120000);
  covers.get('https://cover/B')({ id: 'B-cover' });
  await b;
  assert.equal(updates.at(-1).duration, 120000, 'late cover must preserve prepared duration');
  covers.get('https://cover/A')({ id: 'A-cover' });
  await a;
  assert.equal(updates.at(-1).artist, 'B', 'stale cover cannot restore previous book');
  await session.updateMetadata({ ...book('local'), cover: '' }, chapter);
  assert.equal(updates.at(-1).artist, 'local');
  assert.equal(updates.at(-1).mediaImage, placeholder, 'coverless book must explicitly replace the old image');

  let source = fs.readFileSync(path.join(root, 'components/ReaderPageTurnComponent.ets'), 'utf8');
  source = source.slice(0, source.search(/  @Builder\r?\n/)) + '\n}';
  source = source.replace('@ComponentV2', '').replace('export struct', 'export class')
    .replace(/@(Param|Event|BuilderParam)\s+/g, '').replace(/@Monitor\([^\n]*\)\s*/g, '');
  const events = new EventEmitter();
  const { ReaderPageTurnComponent } = compile(source, {
    '@kit.ArkUI': { FrameCallback: class {} },
    '../utils/ReaderTapPolicy': compile(fs.readFileSync(path.join(root, 'utils/ReaderTapPolicy.ets'), 'utf8'), {}),
    '@kit.BasicServicesKit': { emitter: events },
    '../model/TextReading': { PageTurnMode: { Cover: 'cover', None: 'none', Vertical: 'vertical', Simulation: 'simulation' } }
  }, { CanvasRenderingContext2D: class { clearRect() {} }, RenderingContextSettings: class {},
    ImageBitmap: class { close() {} } });
  ReaderPageTurnComponent.prototype.getUniqueId = () => 1;
  const turn = new ReaderPageTurnComponent();
  const commits = [];
  turn.onComplete = value => commits.push(value);
  turn.aboutToAppear();
  turn.phase = 'settling'; turn.commitOnRelease = true;
  turn.handlePanCancel();
  events.emit('app.reader.background');
  assert.deepEqual(commits, [true], 'Home cancel must preserve a confirmed page turn');
  events.emit('app.reader.background');
  assert.deepEqual(commits, [true], 'background repeats must not double-commit');
  turn.phase = 'dragging'; turn.commitOnRelease = false;
  events.emit('app.reader.background');
  assert.deepEqual(commits, [true, false], 'unfinished drag must roll back');
  turn.mode = 'none'; turn.canvasReady = true; turn.pageWidth = 300;
  turn.onPrepare = async () => true;
  await turn.beginTurn(true, true, 100);
  assert.deepEqual(commits, [true, false, true], 'no-effect tap commits without taking a snapshot');
  turn.aboutToDisappear();
  assert.equal(events.listenerCount('app.reader.background'), 0);
  turn.phase = 'settling'; turn.commitOnRelease = true;
  turn.onReaderChanged();
  assert.equal(commits.at(-1), true, 'layout changes before the background event must preserve the confirmed turn');
  let confirmations = 0;
  turn.onConfirm = () => { confirmations++; };
  turn.settle(true);
  assert.equal(confirmations, 1, 'notify the reader of confirmed turns before completion');
  turn.phase = 'preparing'; turn.released = true; turn.commitOnRelease = true;
  turn.handlePanCancel();
  assert.equal(turn.commitOnRelease, true, 'late system Cancel must preserve a released tap during preparation');
  turn.phase = 'dragging'; turn.released = false; turn.commitOnRelease = false;
  turn.onReaderChanged();
  assert.equal(commits.at(-1), false, 'layout changes must cancel unconfirmed drags');
  const frames = [];
  const rendered = [];
  turn.getUIContext = () => ({ postFrameCallback: callback => frames.push(callback) });
  turn.drawFrame = value => rendered.push(value);
  turn.phase = 'dragging';
  for (let i = 1; i <= 20; i++) { turn.progress = i / 20; turn.scheduleFrame(); }
  assert.equal(frames.length, 1, 'rapid touch updates must share one display frame');
  frames.shift().onFrame(0);
  assert.deepEqual(rendered, [1], 'draw only the latest finger position');
  turn.scheduleFrame();
  turn.cancelTurn(false);
  frames.shift().onFrame(0);
  assert.deepEqual(rendered, [1], 'pending frame must not draw released snapshots after cancellation');
  const animations = [];
  let finishPrepare;
  turn.getUIContext = () => ({
    postFrameCallback: callback => frames.push(callback),
    getComponentSnapshot: () => ({ get: async () => ({ release: async () => {} }) }),
    createAnimator: options => {
      const animation = { options, play() {}, cancel() {} };
      animations.push(animation); return animation;
    }
  });
  turn.drawFrame = value => { turn.renderedProgress = value; };
  turn.mode = 'simulation'; turn.canvasReady = true; turn.pageWidth = 400; turn.pageHeight = 800;
  turn.onPrepare = () => new Promise(resolve => { finishPrepare = resolve; });
  const preparation = turn.beginTurn(true, false, 600);
  await tick();
  turn.handlePanEnd({ offsetX: -360, offsetY: 0, velocityX: -1200 });
  assert.equal(turn.progress, 0.45, 'paper fold travels half the finger displacement');
  finishPrepare(true); await preparation;
  assert.equal(animations.at(-1).options.begin, 0, 'quick flick during loading must animate from the visible original page');
  assert.equal(animations.at(-1).options.end, 1);
  assert.ok(animations.at(-1).options.duration >= 500, 'quick flick must retain a visible curl phase');
  animations.at(-1).onFinish();
  for (const forward of [true, false]) {
    turn.phase = 'dragging'; turn.forward = forward; turn.renderedProgress = 0.2;
    turn.handlePanEnd({ offsetX: forward ? -180 : 180, offsetY: 0, velocityX: 0 });
    assert.equal(animations.at(-1).options.begin, 0.2, 'release continues from last displayed position');
    assert.equal(animations.at(-1).options.end, 1, 'distance threshold works in both directions');
    assert.ok(animations.at(-1).options.duration >= 400);
    animations.at(-1).onFinish();
    turn.phase = 'dragging'; turn.renderedProgress = 0.05;
    turn.handlePanEnd({ offsetX: forward ? -40 : 40, offsetY: 0, velocityX: 0 });
    assert.equal(animations.at(-1).options.end, 0, 'short slow drag still rolls back');
    animations.at(-1).onFinish();
    assert.equal(commits.at(-1), false);
  }
  console.log('PASS: delayed/stale covers, coverless metadata, duration preservation, Home during page turn, unfinished drag, no-effect tap');
})().catch(error => { console.error(error); process.exitCode = 1; });
