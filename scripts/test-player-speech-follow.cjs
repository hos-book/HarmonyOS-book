// Execute the actual PlayerPage positioning methods with measured glyph/list geometry.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/PlayerPage.ets'), 'utf8');
function method(name) {
  const start = new RegExp(`  private ${name}\\(`).exec(source).index;
  let end = source.indexOf('{', start) + 1, depth = 1;
  while (depth && end < source.length) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; end++; }
  return source.slice(start, end);
}
const content = '甲'.repeat(240) + '\n下一段。';
const scope = { Map, graphicsText: { RectWidthStyle: { TIGHT: 0 }, RectHeightStyle: { TIGHT: 0 } },
  ScrollAlign: { START: 0 }, Curve: { EaseOut: 0 },
  PlayerLayoutReadyFrame: class { constructor(run) { this.run = run; } },
  LocalTextImage: { speechContent: text => text },
  TextToSpeechService: { getInstance: () => ({ currentChapterContent: () => content }) } };
vm.runInNewContext(ts.transpileModule(`class Player { ${['syncSpeechParagraphs', 'positionSpeechParagraph'].map(method).join('\n')} }
  globalThis.Player = Player;`, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText, scope);
const frames = [], scrolls = [];
let scrollY = 0, mounted = true;
const p = new scope.Player();
Object.assign(p, { speechState: { bookId: 'test', chapterIndex: 0, contentLength: content.length, charOffset: 0, playbackOffset: 0 },
  speechChapterKey: '', speechParagraphs: [], speechParagraphOffsets: [], speechParagraphIndex: 0,
  speechListReady: true, speechPositionQueued: false, speechPositionGeneration: 0, speechPositionedChapter: '',
  speechPositionedLine: '', speechTextControllers: new Map(), speechViewportHeight: 220, isLeaving: false,
  speechMatchesBook: () => true,
  getUIContext: () => ({ postFrameCallback: f => frames.push(f.run), px2vp: n => n / 2 }),
  speechScroller: {
    getItemRect: () => ({ y: 89 - scrollY, width: 320, height: mounted ? 640 : 0 }),
    currentOffset: () => ({ yOffset: scrollY }),
    scrollTo: o => { scrollY = o.yOffset; scrolls.push(o); },
    scrollToIndex: () => { mounted = true; }
  } });
function flush() { let max = 10; while (frames.length) { assert(max-- > 0); frames.shift()(); } }
const controller = { getLayoutManager: () => ({ getRectsForRange: range => {
  const top = Math.floor(range.start / 10) * 52;
  return [{ rect: { top, bottom: top + 52 } }];
} }) };
p.syncSpeechParagraphs(); p.speechTextControllers.set(0, controller); flush();
assert.equal(scrolls.length, 0, '第一行由顶部留白保持居中');
p.speechState.playbackOffset = 35; p.syncSpeechParagraphs(); flush();
assert.equal(p.speechParagraphIndex, 0);
assert.equal(scrollY, 78, '同一长段内的第4行移至视口中心');
p.speechState.playbackOffset = 39; p.syncSpeechParagraphs(); flush();
assert.equal(scrolls.length, 1, '同一行不重复启动动画');
p.speechState.playbackOffset = 105; p.syncSpeechParagraphs(); flush();
assert.equal(scrollY, 260, '后续行继续跟随，不等待切段');
p.speechViewportHeight = 300; p.positionSpeechParagraph(false); flush();
assert.equal(scrollY, 220, '窗口尺寸变化后重新居中');
mounted = false; p.speechPositionedLine = ''; p.positionSpeechParagraph(false); flush();
assert.equal(p.speechPositionQueued, false, '懒加载未布局时有限重试');
p.speechState.playbackOffset = 155; p.syncSpeechParagraphs(); p.isLeaving = true; const count = scrolls.length; flush();
assert.equal(scrolls.length, count, '离页后不再滚动');
console.log('PASS: long paragraph line centering, no repeated animation within a line, resize, lazy layout and leaving');
