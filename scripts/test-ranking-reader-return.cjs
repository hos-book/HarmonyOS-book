// DEVECO_HOME=<Release IDE> node scripts/test-ranking-reader-return.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const timers = [];
const frames = [];
const animations = [];
const context = {
  exports: {}, AppMotion: { Fast: 160, Base: 300 }, AppCurve: { Decelerate: 0, Accelerate: 1 },
  setTimeout: callback => { timers.push(callback); return timers.length; }, clearTimeout() {},
  OneShotLayoutCallback: class { constructor(action) { this.onFrame = action; } },
  NavigationOperation: { PUSH: 0, POP: 1, REPLACE: 2 },
  TextReaderRouteParams: class { constructor(bookId) { this.bookId = bookId; } },
  ShelfReaderRouteParams: class {},
  OneShotTransitionCoordinator: { getInstance: () => ({ discardPending() {}, canHandle: () => false }) }
};
const run = source => vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, context);
run(read('utils/RankingReaderTransition.ets').replace(/@(ObservedV2|Trace)\s*/g, ''));
const motion = context.exports.RankingReaderTransition;
context.RankingReaderTransition = motion;
const method = (source, name) => {
  const start = source.indexOf(`  private ${name}(`);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4).replace('private ', '');
};
const index = read('pages/Index.ets');
run('export class ReturnNavigation {\n' +
  ['oneShotNavigationTransition', 'rankingReaderReturnTransition'].map(name => method(index, name)).join('\n') + '\n}');
const card = read('components/RankingBookCard.ets');
run('export class ReturnCard {\n' +
  ['onReaderPushed', 'onReaderClosing', 'collapseFromReader', 'resetReaderOpen', 'close',
    'measureReturnOrigin', 'sourceOrigin', 'frameHeight', 'originScale', 'txNow', 'tyNow']
    .map(name => method(card, name)).join('\n') + '\n}');
function fixture() {
  motion.clear();
  timers.length = frames.length = animations.length = 0;
  const ui = {
    postFrameCallback: frame => frames.push(frame),
    animateTo: (options, action) => { animations.push(options); action(); }
  };
  const navigation = new context.exports.ReturnNavigation();
  Object.assign(navigation, { navigationWidth: 393, navigationEnabled: true, rankingReaderVeil: 0,
    getUIContext: () => ui });
  const detail = new context.exports.ReturnCard();
  Object.assign(detail, { alive: true, readerMotionToken: 0, readerReturnedSeen: motion.closeState.returned,
    readerSessionOpen: true, closeState: motion.closeState, awaitingPushTimer: -1,
    expanding: false, whiteFill: 0, contentFade: false, detailMode: true, detailView: 'catalog',
    getUIContext: () => ui });
  motion.begin('book');
  return { navigation, detail };
}
for (const route of ['reader', 'comicReader']) {
  const { navigation, detail } = fixture();
  const from = { name: route, index: 0, param: new context.TextReaderRouteParams('book') };
  assert.equal(navigation.oneShotNavigationTransition(from, { index: 0 }, 1), undefined,
    'only returning to the original main page uses the card return');
  const transition = navigation.oneShotNavigationTransition(from, { index: -1 }, 1);
  assert.ok(transition, `${route} replaces the default slide with a controlled return`);
  let finished = 0;
  const returned = motion.closeState.returned;
  transition.transition({ finishTransition() { finished++; transition.onTransitionEnd(true); } });
  detail.onReaderClosing();
  assert.equal(detail.expanding, true);
  assert.equal(detail.whiteFill, 1);
  assert.equal(timers.length, 0, 'the backing card holds full screen while the reader is still visible');
  frames.shift().onFrame();
  assert.equal(navigation.rankingReaderVeil, 1, 'reader fades in place to the same surface as the card');
  assert.equal(finished, 0, 'navigation waits for the native fade to finish');
  assert.equal(motion.closeState.returned, returned);
  animations.shift().onFinish();
  assert.equal(finished, 0, 'navigation remains alive through the complete card return');
  assert.equal(navigation.rankingReaderOpacity, 0, 'the white reader hands off to the backing card');
  assert.equal(navigation.navigationEnabled, false);
  detail.onReaderClosing();
  timers.shift()();
  assert.equal(detail.expanding, false, 'during the pop the full-screen card shrinks to its previous position');
  assert.equal(detail.whiteFill, 1, 'cover and text stay hidden while shrinking');
  animations.shift().onFinish();
  assert.equal(finished, 0, 'restoring detail content is part of the same transition');
  assert.equal(detail.whiteFill, 0);
  assert.equal(detail.contentFade, false);
  animations.shift().onFinish();
  assert.equal(finished, 1, 'only the completed card animation finishes navigation');
  assert.equal(navigation.navigationEnabled, true);
  assert.equal(navigation.rankingReaderOpacity, 1);
  assert.equal(detail.readerSessionOpen, false);
  assert.equal(motion.closeState.closing, false);
  assert.equal(detail.detailView, 'catalog', 'return preserves the previous detail subview');
  assert.equal(motion.canReturn(route, 'book'), false, 'the completed session is consumed once');
}
for (const finishFade of [false, true]) {
  const { navigation, detail } = fixture();
  const transition = navigation.rankingReaderReturnTransition('book');
  let finished = 0;
  transition.transition({ finishTransition() { finished++; } });
  detail.onReaderClosing();
  if (finishFade) frames.shift().onFrame();
  transition.onTransitionEnd(false);
  detail.onReaderClosing();
  for (const frame of frames.splice(0)) frame.onFrame();
  for (const animation of animations.splice(0)) animation.onFinish();
  assert.equal(finished, 0, 'a cancelled/expired return ignores late frame and native callbacks');
  assert.equal(detail.expanding, false);
  assert.equal(navigation.rankingReaderVeil, 0);
  assert.equal(navigation.navigationEnabled, true);
}
{
  const { detail } = fixture();
  detail.awaitingPush = true;
  detail.onReaderPushed();
  motion.prepareClose('book');
  detail.onReaderClosing();
  timers.shift()();
  assert.equal(detail.expanding, true, 'a fast return cannot be reset by the delayed entry callback');
  motion.beginClose('book');
  detail.onReaderClosing();
  detail.alive = false;
  detail.readerMotionToken++;
  timers.shift()();
  assert.equal(animations.length, 0, 'unmounted cards ignore delayed return work');
  assert.equal(motion.canReturn('player', 'book'), false);
}
console.log('PASS ranking text/comic reader fade, card return ordering, fast back and cancellation');

context.RankingCardReturnFrame = class { constructor(action) { this.onFrame = action; } };
context.WindowUtils = { pxToVp: value => value / 3 };
context.CardOrigin = class {
  constructor(centerX, centerY, width, key, height) { Object.assign(this, { centerX, centerY, width, key, height }); }
};
for (const [width, height] of [[152, 152], [134, 180], [92, 123]]) {
  const { detail } = fixture();
  const target = { leftPx: 120, topPx: 900, widthPx: width * 3, heightPx: height * 3, isValid: () => true };
  context.PlayerDragTransition = { measure: (_ui, key) => {
    assert.equal(key, 'source-cover');
    return target;
  } };
  let sourceVisible = false, removed = 0;
  Object.assign(detail, { closing: false, leaving: false, entered: true, expanding: false,
    origin: { centerX: 190, centerY: 420, width: 120, height: 120, key: 'source-cover' },
    book: { contentType: width === height ? 'audio' : 'comic' },
    cardWidth: () => 360, cardHeight: () => 610, anchorX: () => 190, anchorY: () => 420,
    vBias: () => 10, onRestoreSource: () => { sourceVisible = true; }, onExit: () => removed++ });
  detail.close();
  assert.equal(detail.sourceOrigin().width, width, 'closing remeasures the actual source after resize or scrolling');
  assert.equal(detail.originScale() * 360, width);
  assert.ok(Math.abs(detail.frameHeight() * detail.originScale() - height) < 0.00001,
    'the landing restores the actual square or portrait source height');
  assert.equal(detail.txNow() + 190, 40 + width / 2);
  assert.equal(detail.tyNow() + 420, 300 + height / 2);
  assert.equal(sourceVisible, false, 'the source stays hidden throughout the flight');
  assert.equal(removed, 0);
  animations.shift().onFinish();
  assert.equal(sourceVisible, true, 'the landing restores the original card first');
  assert.equal(removed, 0, 'animation completion must not remove the relay before the source renders');
  frames.shift().onFrame();
  assert.equal(removed, 0);
  frames.shift().onFrame();
  assert.equal(removed, 1, 'only the committed original card permits removing the expanded layer');
}
console.log('PASS ranking card returns to measured source bounds and commits the original before unmount');
