// Native paragraph geometry is the authority for painted ranges, selection handles and hit testing.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets/service/text');
const mocks = { '@kit.ArkGraphics2D': { text: {
  RectWidthStyle: { TIGHT: 0 }, RectHeightStyle: { TIGHT: 0 }, TextDirection: { LTR: 0, RTL: 1 }
} } };
function load(name) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, name + '.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, require: id => mocks[id] || {} }, { filename: name + '.ets' });
  mocks['./' + name] = exports;
  return exports;
}
const { OnlineTextPage, OnlineTextIndentedContent } = load('OnlineTextPaginator');
load('SpeechTextHighlighter');
const { ReaderSelectionGeometry: geometry } = load('ReaderSelectionGeometry');
const displayed = OnlineTextIndentedContent.fromNormalized('前页文字\n缩进正文\n第二段文字');
const page = new OnlineTextPage();
page.text = displayed.text.substring(7);
page.displayStart = 7;
page.nativeOffsets = displayed;
page.layoutTop = 260;
page.layoutWidth = 300;
page.layoutHeight = 100;
page.lineMetrics = [{ baseline: 280, ascent: 20, descent: 5 }, { baseline: 320, ascent: 20, descent: 5 }];
page.lineShifts = [0, 16];
const boxes = [
  { rect: { left: 144, right: 192, top: 260, bottom: 285 }, direction: 0 },
  { rect: { left: 48, right: 96, top: 300, bottom: 325 }, direction: 0 }
];
let requestedRange;
let requestedPoint;
let hitOffset = 11;
page.paragraph = {
  getRectsForRange(range) { requestedRange = range; return boxes; },
  getGlyphPositionAtCoordinate(x, y) { requestedPoint = { x, y }; return { position: hitOffset }; },
  getWordBoundary() { return { start: 10, end: 12 }; }
};
const snapshot = value => JSON.parse(JSON.stringify(value));
let rects = geometry.rects(page, 4, 11);
assert.deepEqual(snapshot(requestedRange), { start: 7, end: 12 }, 'API 26 indentation is removed only in native offset space');
assert.deepEqual(snapshot(rects).map(r => [r.left, r.top, r.right, r.bottom]), [[144, 0, 192, 25], [48, 56, 96, 81]],
  'page origin and each paragraph shift are applied exactly once');
let bounds = geometry.bounds(page, 4, 11);
assert.deepEqual(snapshot(bounds.start), { x: 144, top: 0, bottom: 25 });
assert.deepEqual(snapshot(bounds.end), { x: 96, top: 56, bottom: 81 });
assert.equal(geometry.offsetAt(page, 70, 60), 10);
assert.deepEqual(snapshot(requestedPoint), { x: 70, y: 304 }, 'drag hit testing reverses the same line transform');
const word = geometry.wordAt(page, 70, 60);
assert.equal(page.text.substring(word.start, word.end), '第二', 'AI and read-from actions receive the visible word');
geometry.offsetAt(page, 70, 40);
assert.equal(requestedPoint.y, 284.99, 'spacing nearer the preceding line stays on that line');
geometry.offsetAt(page, 70, 42);
assert.equal(requestedPoint.y, 300, 'spacing nearer the following line resolves to that line');
geometry.offsetAt(page, -20, -40);
assert.deepEqual(snapshot(requestedPoint), { x: 0, y: 260 });
geometry.offsetAt(page, 900, 900);
assert.deepEqual(snapshot(requestedPoint), { x: 300, y: 324.99 });
hitOffset = 0;
assert.equal(geometry.offsetAt(page, 0, 0), 0, 'drag cannot select text on the preceding page');
hitOffset = 1000;
assert.equal(geometry.offsetAt(page, 300, 100), page.text.length, 'drag cannot select beyond the visible fragment');
page.layoutTop = 270;
page.layoutHeight = 60;
rects = geometry.rects(page, 4, 11);
assert.deepEqual(snapshot(rects).map(r => [r.top, r.bottom]), [[0, 15], [46, 60]], 'handles follow clipped visible ink');
page.nativeOffsets = null;
geometry.rects(page, 4, 11);
assert.deepEqual(snapshot(requestedRange), { start: 11, end: 18 }, 'API 20 fallback keeps display offsets');
boxes[0].direction = boxes[1].direction = 1;
bounds = geometry.bounds(page, 4, 11);
assert.equal(bounds.start.x, 192);
assert.equal(bounds.end.x, 48, 'RTL handles follow logical selection endpoints');
assert.equal(geometry.bounds(page, -1, -1).valid, false);
page.paragraph = null;
assert.equal(geometry.rects(page, 0, 2).length, 0);
assert.equal(geometry.offsetAt(page, 1, 1), -1);
assert.equal(geometry.wordAt(page, 1, 1).start, -1);
console.log('PASS selection geometry: indentation, page offsets, paragraph spacing, drag bounds, selected words, clipping, RTL and API 20 fallback');
