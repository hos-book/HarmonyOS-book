// DEVECO_HOME=<Release IDE> node scripts/test-ranking-menu-layout.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/RankingHomePage.ets'), 'utf8');
const start = source.indexOf('  get matchMenuHeight()');
const end = source.indexOf('  private matchMenuOptions()', start);
assert.ok(start > 0 && end > start);
const frameStart = source.indexOf('class RankingMatchRestoreFrame extends FrameCallback');
const frameEnd = source.indexOf('\n@ComponentV2', frameStart);
assert.ok(frameStart > 0 && frameEnd > frameStart);
const code = ts.transpileModule(source.slice(frameStart, frameEnd) + '\nexport class Layout { ' + source.slice(start, end)
  .replace(/  @Computed\s*/g, '').replace(/  @Monitor\([^\n]+\)\s*/g, '') + '}', {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const frames = [];
let modern = true, observers = 0;
const viewport = { leftPx: 0, topPx: 0, widthPx: 400, heightPx: 800, isValid: () => true };
const mini = { leftPx: 16, topPx: 664, widthPx: 368, heightPx: 40, isValid: () => true };
const context = { px2vp: value => value,
  getUIObserver: () => ({ on: () => { observers++; }, off: () => { observers--; } }),
  postFrameCallback: callback => frames.push(callback)
};
const compiledExports = {};
vm.runInNewContext(code, { exports: compiledExports, AppSpace: { Xs: 8, Xxs: 4 }, RANKING_SEARCH_HEIGHT: 56,
  PlatformCompat: { supports: () => modern }, WindowUtils: { getBottomSafeVp: () => 28 },
  FrameCallback: class { onFrame() {} onIdle() {} },
  PlayerDragTransition: { measure: (_context, id) => id === 'ranking-home-layout' ? viewport : mini }
});
const page = new compiledExports.Layout();
Object.assign(page, { alive: true, visible: true, showSheet: true, matchMenuReady: false,
  matchOpenPending: false, matchLayoutObserved: false, matchLayoutGeneration: 0,
  matchMenuTop: 0, matchMenuBottom: 0, contentHeight: 800, topSafe: 40,
  searchViewportHeight: 56, bottomTabInset: 90, miniPlayerVisible: true,
  getUIContext: () => context });
page.onMatchLayoutChanged();
assert.equal(page.matchMenuTop, 104, 'expanded search bottom plus gap');
assert.equal(page.matchMenuBottom, 136, 'double bars use measured mini top');
assert.equal(page.matchMenuHeight, 544);
assert.equal(page.matchMenuReady, false, 'anchor must commit before native menu opens');
page.onMatchLayoutChanged(); assert.equal(frames.length, 1, 'duplicate callbacks share one pending open');
frames.shift().onFrame(0); assert.equal(page.matchMenuReady, false, 'first onFrame still precedes anchor layout');
frames.shift().onFrame(16_000_000); assert.equal(page.matchMenuReady, true, 'opens without waiting for idle or scrolling');
page.miniPlayerVisible = false; page.onMatchLayoutChanged();
assert.equal(page.matchMenuHeight, 590, 'single bar increases available height');
page.miniPlayerVisible = true; mini.topPx = 710; page.onMatchLayoutChanged();
assert.equal(page.matchMenuHeight, 590, 'side-by-side or collapsed bars do not reserve a second row');
page.searchViewportHeight = 0; page.updateMatchMenuBounds();
assert.equal(page.matchMenuTop, 96, 'collapsed search keeps the pinned toolbar clear');
page.activeBoard = {}; page.updateMatchMenuBounds();
assert.equal(page.matchMenuTop, 104, 'standalone board keeps its title bar clear');
page.showSheet = false; page.onMatchLayoutChanged();
assert.equal(page.matchMenuReady, false); assert.equal(observers, 0);
page.showSheet = true; page.onMatchLayoutChanged();
page.showSheet = false; page.onMatchLayoutChanged();
frames.shift().onFrame(32_000_000); assert.equal(page.matchMenuReady, false, 'late frame cannot reopen a dismissed menu');
modern = false; page.activeBoard = undefined; page.searchViewportHeight = 0;
page.miniPlayerVisible = false; page.bottomTabInset = 60; page.updateMatchMenuBounds();
assert.ok(page.matchMenuHeight <= (800 - 40 - 28) * 0.8 - 8, 'legacy content fits native menu limit');
console.log('PASS: search/title boundaries, double/single/side-by-side bars, layout-before-open, dismissal race and legacy height');
