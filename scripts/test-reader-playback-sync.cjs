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
    '../model/TextReading': { PageTurnMode: { Cover: 'cover', None: 'none', Vertical: 'vertical' } }
  }, { CanvasRenderingContext2D: class { clearRect() {} }, RenderingContextSettings: class {} });
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
  console.log('PASS: delayed/stale covers, coverless metadata, duration preservation, Home during page turn, unfinished drag, no-effect tap');
})().catch(error => { console.error(error); process.exitCode = 1; });
