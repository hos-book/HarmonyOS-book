// DEVECO_HOME=<Release IDE> node scripts/test-ranking-menu-layout.cjs
// Match UI now lives inside the expanding ranking card. Exercise real geometry and selection logic.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/components/RankingBookCard.ets'), 'utf8');
const prefix = source.slice(0, source.indexOf('@ComponentV2')).replace(/^import .*;\r?\n/gm, '');
const logic = source.slice(source.indexOf('export struct RankingBookCard'), source.indexOf('  build() {'))
  .replace('export struct RankingBookCard', 'export class RankingBookCard')
  .replace(/@(Require|Param|Local|Event)\s+/g, '')
  .replace(/@Monitor\([^\n]+\)\s*/g, '') + '\n}';
const compiled = ts.transpileModule(prefix + logic, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const exportsObject = {};
vm.runInNewContext(compiled, {
  exports: exportsObject, $r: name => name, FrameCallback: class {},
  WindowUtils: { getWindowWidthVp: () => 393, getWindowHeightVp: () => 852,
    getStatusBarHeightVp: () => 40, getBottomSafeVp: () => 28, getFloatingTabBottomVp: () => 100 },
  RankingBook: class {}, CardOrigin: class {}, RankingReaderTransition: { closeState: {} },
  GeneralSettings: { current: { adaptiveHandedness: true } },
  ReaderHoldingHandService: class { setVisible() {} },
  curves: { responsiveSpringMotion() {}, springMotion() {} },
  AppMotion: { Base: 300 }, AppCurve: { Accelerate: 0 }, setTimeout, clearTimeout
});
(async () => {
  for (const [width, height, top, bottom, boundary = 0, hostTop = 0] of [
    [393, 852, 40, 90], [915, 412, 24, 90], [600, 960, 32, 160],
    [1280, 800, 24, 72], [360, 320, 24, 100],
    [393, 852, 40, 160, 104], [393, 852, 40, 160, 96],
    [393, 812, 40, 160, 64, 40], [915, 320, 24, 90, 80]
  ]) {
    const card = new exportsObject.RankingBookCard();
    Object.assign(card, { vpW: width, vpH: height, topInsetVp: top,
      bottomTabInset: bottom, topBoundary: boundary, hostTop,
      baseCy: hostTop + height / 2, entered: true });
    const cardTop = card.anchorY() + card.tyNow() - card.cardHeight() / 2;
    assert.ok(cardTop >= Math.max(top, hostTop + boundary) - 0.001,
      'card clears the status bar and the search/category/title boundary');
    assert.ok(cardTop + card.cardHeight() <= hostTop + height - bottom - 12 + 0.001,
      'card clears the complete bottom bar, including in short split windows');
    assert.ok(card.cardWidth() < width, 'card fits the current container');
    card.entered = false;
    card.origin = { centerX: 80, centerY: 150, width: 88 };
    assert.equal(card.anchorX() + card.txNow(), 80, 'opening starts at the tapped cover');
    assert.equal(card.anchorY() + card.tyNow(), 150);
    card.entered = true;
    card.closing = true;
    assert.equal(card.anchorX() + card.txNow(), 80, 'closing returns to the same cover');
  }
  const card = new exportsObject.RankingBookCard();
  card.matchMode = true;
  card.getUIContext = () => ({ animateTo: (_options, action) => action() });
  const match = { book: { sourceUrl: 'source', bookUrl: '/book' } };
  card.onPrepareMatch = async () => { throw Error('source disabled'); };
  await card.pick(match);
  assert.equal(card.detailMode, false, 'disabled/deleted sources do not enter detail');
  let complete;
  card.onPrepareMatch = () => new Promise(resolve => { complete = resolve; });
  const selecting = card.pick(match);
  card.matchMode = false;
  complete();
  await selecting;
  assert.equal(card.detailMode, false, 'late preparation cannot reopen a dismissed match panel');
  const page = fs.readFileSync(path.join(__dirname,
    '../entry/src/main/ets/pages/RankingHomePage.ets'), 'utf8');
  const podiumStart = page.indexOf('struct RankingPodiumCard {');
  const podiumLogic = page.slice(podiumStart, page.indexOf('  build() {', podiumStart))
    .replace('struct RankingPodiumCard', 'export class RankingPodiumCard')
    .replace(/@(Param|Local|Event)\s+/g, '').replace(/@Monitor\([^\n]+\)\s*/g, '') + '\n}';
  const podiumExports = {};
  vm.runInNewContext(ts.transpileModule(podiumLogic, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports: podiumExports, RankingBook: class {}, BoardDeckCardData: class {},
    FLOW_PULL_CARD_MS: 280, FLOW_PULL_STAGGER_MS: 150, FLOW_PULL_CURVE: 0,
    AppCurve: { Decelerate: 0 } });
  for (const count of [1, 2, 3, 5]) {
    const finished = [];
    for (let order = 0; order < count; order++) {
      const current = new podiumExports.RankingPodiumCard();
      const pending = [];
      Object.assign(current, { prepareToken: 10, pullToken: 1, flowToken: 10, lastOrder: count - 1,
        entry: { key: 'book', hostX: 18, hostY: 146, startCx: 220, startCy: 640,
          startW: 80, startH: order % 2 === 0 ? 80 : 108, order },
        cardWidth: 140, cardHeight: 188, frameX: 120, frameY: 12, cardScale: 0.8,
        onArrived: token => finished.push(token),
        getUIContext: () => ({ animateTo: (options, action) => { pending.push(options); action(); } }) });
      current.aboutToAppear();
      assert.equal(current.entry.hostX + current.xNow() + current.cardWidth / 2, current.entry.startCx);
      assert.equal(current.entry.hostY + current.yNow() + current.cardHeight / 2, current.entry.startCy,
        'the shared scale/rotate center remains exact for square and portrait cards');
      assert.equal(current.scaleX() * current.cardWidth, 80);
      current.pull();
      assert.equal(pending[0].delay, order * 150);
      pending[0].onFinish();
      assert.equal(current.xNow(), 120, 'the same card settles at its normal podium transform');
      assert.equal(current.yNow(), 12);
      assert.equal(current.scaleY(), 0.8);
    }
    assert.deepEqual(finished, [10], 'the actual last TOP card starts grid dealing once');
  }
  {
    const shelfSource = fs.readFileSync(path.join(__dirname,
      '../entry/src/main/ets/components/RankingShelf.ets'), 'utf8');
    const start = shelfSource.indexOf('  private emitGatherSnapshot(');
    const snapshotMethod = shelfSource.slice(start, shelfSource.indexOf('\n  }', start) + 4)
      .replace('private ', '');
    const shelfPrefix = shelfSource.slice(0, shelfSource.indexOf('@ComponentV2'))
      .replace(/^import .*;\r?\n/gm, '');
    const shelfExports = {};
    vm.runInNewContext(ts.transpileModule(shelfPrefix +
      '\nexport class GatherShelf {\n' + snapshotMethod + '\n}', {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
    }).outputText, { exports: shelfExports, FrameCallback: class {} });
    // Real snapshot -> real TOP card, with different layout sizes and a scrolled source host.
    for (const sourceWidth of [120, 168]) {
      const sourceHeight = sourceWidth / (88 / 118);
      const shelf = new shelfExports.GatherShelf();
      let cells;
      Object.assign(shelf, { gatherBoardId: 'board', shelfKey: 'board', gatherProgress: 1,
        gatherAnchorVirtual: 2, ensureGatherAnchor() {},
        bookAt: () => ({ coverUrl: 'cover' }), focusAt: index => index - 2,
        scaleOf: focus => 1 - Math.abs(focus) * 0.2, gatherShrinkFactor: () => 0.7,
        cardW: () => sourceWidth, cardH: () => sourceHeight,
        xOfVirtual: index => 30 + index * 24, yOf: focus => 40 + Math.abs(focus) * 12,
        gatherDx: index => (2 - index) * 14, gatherDy: index => 300 + index * 3,
        gatherAngle: index => (index - 2) * 2, onGatherSnapshot: result => { cells = result; } });
      shelf.emitGatherSnapshot();
      for (const [index, cell] of cells.entries()) {
        const sourceHostY = -140;
        const actualCenterY = sourceHostY + shelf.yOf(index - 2) + sourceHeight / 2 + shelf.gatherDy(index);
        assert.equal(sourceHostY + cell.cy, actualCenterY, 'snapshot uses the rendered center after rotate');
        const current = new podiumExports.RankingPodiumCard();
        Object.assign(current, { prepareToken: 1, cardWidth: 190, cardHeight: 190 / (88 / 118),
          entry: { key: 'book', hostX: 18, hostY: 146, startCx: cell.cx,
            startCy: sourceHostY + cell.cy, startW: cell.width, startH: cell.height } });
        current.aboutToAppear();
        assert.equal(current.entry.hostY + current.yNow() + current.cardHeight / 2, actualCenterY,
          'handoff preserves the actual center across different card base sizes');
        assert.ok(Math.abs(current.scaleY() * current.cardHeight - cell.height) < 1e-9);
      }
    }
  }
  {
    const current = new podiumExports.RankingPodiumCard();
    const pending = [], returned = [], arrived = [];
    Object.assign(current, { entry: { key: 'book', order: 0 }, prepareToken: 1, pullToken: 1,
      flowToken: 7, lastOrder: 0, onArrived: token => arrived.push(token),
      onReturned: token => returned.push(token),
      getUIContext: () => ({ animateTo: (options, action) => { pending.push(options); action(); } }) });
    current.prepare(); current.pull(); current.cancelToken = 8; current.returnToStack();
    pending[0].onFinish(); pending[1].onFinish();
    assert.deepEqual(arrived, [], 'cancelled native TOP arrival cannot start the grid');
    assert.deepEqual(returned, [8]);
    current.aboutToDisappear(); pending[1].onFinish();
    assert.deepEqual(returned, [8]);
  }
  const deckStart = page.indexOf('struct RankingDeckCard {');
  const deckLogic = page.slice(deckStart, page.indexOf('  build() {', deckStart))
    .replace('struct RankingDeckCard', 'export class RankingDeckCard')
    .replace(/@(Param|Local|Event)\s+/g, '').replace(/@Monitor\([^\n]+\)\s*/g, '') + '\n}';
  const deckExports = {};
  vm.runInNewContext(ts.transpileModule(deckLogic, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports: deckExports, BoardDeckCardData: class {},
    FLOW_PULL_CARD_MS: 280, FLOW_PULL_STAGGER_MS: 150, FLOW_PULL_CURVE: 0,
    AppCurve: { Decelerate: 0 } });
  const deck = new deckExports.RankingDeckCard();
  const animations = [];
  const arrived = [], returned = [];
  Object.assign(deck, { card: { order: 4 }, pullToken: 1, flowToken: 10,
    onArrived: token => arrived.push(token), onReturned: token => returned.push(token),
    getUIContext: () => ({ animateTo: (options, action) => { animations.push(options); action(); } }) });
  deck.pull();
  deck.cancelToken = 11;
  deck.returnToStack();
  animations[0].onFinish();
  assert.deepEqual(arrived, [], 'an interrupted pull must not finish the old board flow');
  animations[1].onFinish();
  assert.deepEqual(returned, [11], 'cancellation returns control to the current flow');
  deck.aboutToDisappear();
  animations[1].onFinish();
  assert.deepEqual(returned, [11], 'unmounted cards ignore native animation completion');
  for (const count of [1, 2, 3, 5]) {
    const finished = [];
    for (let order = 0; order < count; order++) {
      const current = new deckExports.RankingDeckCard();
      const pending = [];
      Object.assign(current, { card: { order }, lastOrder: count - 1, pullToken: 1, flowToken: 20,
        onArrived: token => finished.push(token),
        getUIContext: () => ({ animateTo: (options, action) => { pending.push(options); action(); } }) });
      current.pull();
      assert.equal(pending[0].delay, order * 150, 'cards leave the center one at a time');
      pending[0].onFinish();
    }
    assert.deepEqual(finished, [20], 'short and full podiums complete exactly once');
  }
  const method = name => {
    const start = page.indexOf(`  private ${name}(`);
    assert.ok(start >= 0, name);
    return page.slice(start, page.indexOf('\n  }', start) + 4).replace('private ', '');
  };
  const centerExports = {};
  const timeouts = [];
  const Rect = class {
    constructor(x = 0, y = 0, w = 0, h = 0) { Object.assign(this, { x, y, w, h }); }
  };
  vm.runInNewContext(ts.transpileModule('export class GatherDeal {\n' +
    ['bottomDeckRect', 'podiumBookCount', 'beginBoardDeckFlow', 'startBoardGatherDealFlow',
      'setPodiumDealOrigin', 'showBoardFlowGrid', 'startAudioHomeGather', 'finishBoardDeckPull',
      'sectionShelfOpacity', 'sectionChromeOpacity', 'sectionGatherProgress',
      'sectionGatherShrink', 'measureDeckStarts', 'onBoardListScroll', 'homeLayerVisibility',
      'currentRefreshPullOffset', 'closeBoard'].map(method).join('\n') + '\n}', {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports: centerExports, BoardFlowRect: Rect, BoardDeckCardData: class {},
    Scroller: class {}, RankingCoverResolver: {}, AppCurve: { Standard: 0, Decelerate: 1 },
    AppMotion: { Base: 300 }, Visibility: { Hidden: 'hidden', Visible: 'visible' },
    RankingBoardSnapFrame: class { constructor(action) { this.onFrame = action; } },
    FLOW_DECK_FADE_MS: 180, FLOW_GATHER_MS: 320,
    WindowUtils: { getWindowWidthVp: () => 393, getWindowHeightVp: () => 852 },
    FLOW_BAR_GAP: 12, PODIUM_CENTER_W: 134, FLOW_PULL_CARD_MS: 280,
    RankingCardStyle: { COVER_ASPECT: 88 / 118 },
    FLOW_PULL_SETTLE_MS: 160, setTimeout: callback => timeouts.push(callback) });
  for (const [width, height, rootTop, top, bottom] of [
    [393, 852, 0, 96, 680], [915, 412, 24, 80, 306],
    [600, 960, 32, 88, 790], [360, 320, 0, 80, 208]
  ]) {
    for (const contentType of ['text', 'audio']) {
      const flow = new centerExports.GatherDeal();
      const root = new Rect(18, rootTop, width, height - rootTop);
      Object.assign(flow, { measureFlowRect: () => root,
        boardFlowTopLimit: () => top, boardFlowBottomLimit: () => bottom + 5,
        measureBoardFlowTargetBottom: () => bottom });
      const rect = flow.bottomDeckRect({ books: [{ contentType }] });
      assert.equal(rect.x + rect.w / 2, root.x + root.w / 2, 'deck centers in its actual host');
      assert.equal(rect.y + rect.h, bottom - 12, 'the gathered deck stops above the bottom navigation');
      assert.ok(rect.y >= top + 12 && rect.y + rect.h <= bottom - 12, 'deck clears both safe boundaries');
      assert.equal(rect.w / rect.h, contentType === 'audio' ? 1 : 0.75,
        'audio uses square cards before activeBoard is assigned');
    }
  }
  for (const total of [1, 2, 3, 4, 5, 12]) {
    const flow = new centerExports.GatherDeal();
    const board = { id: 'board', books: Array.from({ length: total }, (_, i) =>
      ({ id: `book-${i}`, rank: i + 1, coverUrl: `cover-${i}`, contentType: 'audio' })) };
    const root = new Rect(0, 24, 393, 828);
    let content, scroller, waiting;
    Object.assign(flow, { alive: true, boardFlowToken: 0, homeFocusBooks: new Map(),
      boardHomeRelayReady: true,
      measureFlowRect: id => id.startsWith('rankingAudioCover-') ? new Rect(24, 400, 152, 152) : root,
      measureBoardFlowSources: () => [], boardCardWidth: () => 100,
      getUIContext: () => ({ animateTo: (_options, action) => action(), postFrameCallback() {} }),
      boardFlowTopLimit: () => 96, boardFlowBottomLimit: () => 680,
      measureBoardFlowTargetBottom: () => 680,
      setBoardContent: value => { content = value; }, onScrollerReady: value => { scroller = value; },
      waitBoardOpenTargets: (...args) => { waiting = args; },
      collectBoardTargets: value => value.books.slice(0, flow.podiumBookCount(value))
        .map((_, i) => new Rect(40 + i * 30, 150, 100, 100)) });
    flow.startBoardGatherDealFlow(board);
    assert.equal(flow.boardHomeRelayReady, false, 'reopening resets the home-to-podium handoff');
    assert.equal(content, board, 'entry populates the lazy grid for this board');
    assert.equal(scroller, flow.boardScroller, 'parent scrolling uses the active board');
    assert.equal(flow.boardFanVisible, false, 'final cards stay hidden before bottom gathering and podium dealing starts');
    assert.equal(waiting[0], board);
    flow.startAudioHomeGather(board, flow.boardFlowToken);
    assert.ok(flow.boardDeckCards.every(card => card.startW < card.sourceW),
      'audio cards shrink while gathering above the bottom bar');
    const gathered = flow.boardDeckCards.map(card => ({ x: card.startCx, y: card.startCy }));
    flow.beginBoardDeckFlow(flow.boardFlowToken);
    assert.equal(flow.boardDeckCards.length, total >= 5 ? 5 : Math.min(3, total));
    for (const [i, card] of flow.boardDeckCards.entries()) {
      assert.equal(card.startCx, gathered[i].x, 'pull preserves the gathered position');
      assert.equal(card.startCy, gathered[i].y);
      assert.equal(card.startW, card.startH, 'audio keeps square geometry throughout the deal');
      assert.equal(card.startCover, card.endCover, 'a dealt card preserves its cover');
    }
    flow.boardFlowLayerW = () => 87;
    flow.setPodiumDealOrigin();
    assert.equal(flow.boardFlowGridFromX, 90);
    assert.equal(flow.boardFlowGridFromY + flow.boardFlowGridFromW / 2, 250,
      'more books emerge downwards from the bottom of the top cards');
    assert.equal(flow.boardFlowGridFromW, 72);
    timeouts.length = 0;
    flow.showBoardFlowGrid(flow.boardFlowToken);
    flow.boardFlowGridVisible = false;
    flow.boardFlowToken++;
    timeouts[0]();
    assert.equal(flow.boardFlowGridVisible, false, 'cancelled grid callbacks cannot restart a later flow');
    timeouts.length = 0;
  }
  {
    const flow = new centerExports.GatherDeal();
    Object.assign(flow, { boardFlowActive: true, boardFlowPhase: 1, boardFlowT: 1,
      boardFlowBoard: { id: 'audio', books: [{ contentType: 'audio' }] },
      boardDeckVisible: true, boardHomeRelayReady: false });
    assert.equal(flow.sectionShelfOpacity('audio'), 0, 'the audio deck owns the covers during gathering');
    flow.boardFlowPhase = 2;
    assert.equal(flow.sectionShelfOpacity('audio'), 0,
      'the original audio shelf cannot flash back while TOP cards prepare for handoff');
    flow.boardHomeRelayReady = true; flow.boardDeckVisible = false;
    assert.equal(flow.sectionShelfOpacity('audio'), 0, 'the source stays hidden after TOP cards take over');
    flow.boardFlowPhase = 3;
    assert.equal(flow.sectionShelfOpacity('audio'), 1, 'cancellation can reveal the original shelf again');
  }
  {
    const flow = new centerExports.GatherDeal();
    const frames = [];
    let nextPhase = 0;
    Object.assign(flow, { alive: true, boardFlowActive: true, boardFlowPhase: 2, boardFlowToken: 10,
      boardFlowBoard: { id: 'board' }, boardFlowT: 0, boardFlowShrink: 0, boardDeckVisible: false,
      boardPodiumPulling: true, boardFanVisible: true,
      boardHomeRelayReady: false,
      getUIContext: () => ({ postFrameCallback: frame => frames.push(frame) }),
      onBoardPullFinished: () => nextPhase++ });
    assert.equal(flow.sectionGatherProgress('board'), 1, 'the hidden home deck never resets during handoff');
    assert.equal(flow.sectionGatherShrink('board'), 1);
    assert.equal(flow.sectionShelfOpacity('board'), 1, 'source stays until the relay has rendered');
    assert.equal(flow.sectionChromeOpacity('board'), 0, 'faded home labels must not flash back');
    assert.equal(flow.sectionShelfOpacity('other'), 0, 'other shelves stay faded');
    flow.boardHomeRelayReady = true;
    assert.equal(flow.sectionShelfOpacity('board'), 0);
    flow.finishBoardDeckPull(10);
    assert.equal(flow.boardFanVisible, true);
    assert.equal(flow.boardDeckVisible, false);
    assert.equal(frames.length, 0, 'landing does not replace or re-show a second card tree');
    assert.equal(nextPhase, 1, 'grid dealing continues from the same TOP card nodes');
    flow.finishBoardDeckPull(10);
    assert.equal(nextPhase, 1, 'duplicate completion cannot redeal the grid');
    for (const total of [1, 2, 3, 4]) {
      flow.boardFlowDeckCells = Array.from({ length: 5 }, (_, i) =>
        ({ cx: 100 + i * 3, cy: 600, width: 90, cover: 'cover', angle: 0 }));
      flow.boardFlowSourceShelf = new Rect(0, 100, 393, 200);
      flow.measureDeckStarts({ books: Array.from({ length: total }, () => ({})) });
      assert.deepEqual(Array.from(flow.boardFlowStartOrder),
        Array.from({ length: Math.min(3, total) }, (_, i) => i),
        'short text boards use the actual last card for completion');
    }
  }
  {
    const flow = new centerExports.GatherDeal();
    let total = 360, updates = 0;
    Object.assign(flow, { boardFlowActive: false, boardFlowGridMode: '', boardFlowListOffset: 0,
      boardScroller: { currentOffset: () => ({ yOffset: total }) }, onContentScroll() {},
      onBoardFlowScroll: () => updates++ });
    flow.onBoardListScroll(5, 1);
    assert.equal(flow.boardFabVisible, true, 'back-to-top uses accumulated distance, not this frame delta');
    assert.equal(flow.boardFlowListOffset, 0, 'normal scrolling does not dirty every card');
    flow.boardFlowActive = true; flow.boardFlowGridMode = 'dealAll';
    flow.onBoardListScroll(-8, 1);
    assert.equal(flow.boardFlowListOffset, total, 'in-flight cards follow total list displacement');
    assert.equal(updates, 1);
    flow.boardFlowActive = false; total = 0; flow.onBoardListScroll(-12, 1);
    assert.equal(flow.boardFabVisible, false);
    assert.equal(flow.boardFlowListOffset, 360, 'settled cards stop observing scrolling again');
  }
  {
    const flow = new centerExports.GatherDeal();
    const pending = [];
    Object.assign(flow, { alive: true, activeBoard: undefined, boardTransitioning: false,
      boardFlowActive: false, refreshPullOffset: 48, boardRefreshPullOffset: 0,
      onScrollerReady() {}, getUIContext: () => ({ animateTo: (options, action) => {
        assert.equal(flow.homeLayerVisibility(), 'visible', 'home is ready before the closing fade starts');
        pending.push(options); action();
      } }) });
    assert.equal(flow.homeLayerVisibility(), 'visible');
    flow.activeBoard = { id: 'board' };
    flow.boardFlowActive = true; flow.boardTransitioning = true;
    assert.equal(flow.homeLayerVisibility(), 'visible', 'gathering and dealing retain the source deck');
    flow.boardFlowActive = false; flow.boardTransitioning = false;
    assert.equal(flow.homeLayerVisibility(), 'hidden', 'the covered home stops drawing after entry');
    flow.boardRefreshPullOffset = 72;
    assert.equal(flow.currentRefreshPullOffset(), 72, 'board refresh has its own indicator displacement');
    assert.equal(flow.refreshPullOffset, 48, 'board pull leaves the home geometry untouched');
    flow.closeBoard();
    assert.equal(flow.boardRefreshPullOffset, 0);
    assert.equal(flow.homeLayerVisibility(), 'visible');
    pending[0].onFinish();
    assert.equal(flow.activeBoard, undefined);
    assert.equal(flow.currentRefreshPullOffset(), 48, 'return restores the original home refresh state');
  }
  console.log('PASS ranking safe boundaries, gathering/podium handoffs, scroll isolation and cancellation');
})().catch(error => { console.error(error); process.exitCode = 1; });
