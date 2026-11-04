// Verify real HdsTabs options across window widths; native geometry still requires device checks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/MainPage.ets'), 'utf8');
const helpers = source.slice(source.indexOf('  private useFloatingTabs'), source.indexOf("  @Monitor('appearance.verticalBottomTabs')"));
const method = source.slice(source.indexOf('  private floatingBarStyle'), source.indexOf('  private handleTabBarClick'));
const sync = source.slice(source.indexOf('  private syncVerticalBars'), source.indexOf('  private floatingBarStyle'));
const reset = source.slice(source.indexOf('  private resetTabStyle'), source.indexOf('  @Local currentTab'));
const layout = source.slice(source.indexOf('  private handleViewportSizeChange'), source.indexOf('  private restoreExpandedTabBars'));
const constants = source.slice(source.indexOf('const FLOATING_BOTTOM'), source.indexOf('@ComponentV2'));
const appearance = source.slice(source.indexOf('  private get tabsAppearance'), source.indexOf('  private restoreTabBarOnWindowGrow'));
const exportsObject = {};
const platform = { floatingTabs: true, supports: () => true };
const timers = new Map(); let nextTimer = 0;
const theme = { FloatingBarMask: { id: 100, type: 10001, params: ['mask'] } };
const flush = () => { const work = [...timers.values()]; timers.clear(); for (const f of work) f(); };
vm.runInNewContext(ts.transpileModule(`${constants}\nexport class Page { ${helpers} ${method} ${sync} ${reset} ${layout} ${appearance} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, { exports: exportsObject, PlatformCompat: platform, HomeTheme: theme,
  setTimeout: f => { const id = ++nextTimer; timers.set(id, f); return id; }, clearTimeout: id => timers.delete(id),
  WindowUtils: { refreshAvoidArea() {} }, hilog: { info() {}, warn() {} }, HdsTabsBarChangeMode: { USER_CLICK: 1 },
  HdsCompat: { adaptiveMaterial: 'material' }, AppColor: { Brand: 'brand' }, Color: { Transparent: 'transparent' }, AppTheme: { Surface: 'surface' },
  HdsBarStyle: { EXPAND: 1, COLLAPSE: 0 }, HdsBarLayoutMode: { HORIZONTAL: 0, VERTICAL: 1 } });
const page = new exportsObject.Page();
Object.assign(page, { appearance: { verticalBottomTabs: true }, bottomSafeVp: 10, sideSafeVp: 0,
  generalSettings: { adaptiveHandedness: true }, miniPlayerVisible: () => true,
  stableMiniBarBuilder: () => {} });
for (const width of [320, 360, 440, 480, 520, 599]) {
  page.viewportWidth = width;
  const style = page.floatingBarStyle();
  assert.equal(style.miniBar.barLayoutMode, 1, 'wide phones retain two rows');
  assert.equal(style.barWidth.smallWidth, width - 32);
  assert.equal(style.barWidth.mediumWidth, width - 32, '440–599vp must not retain 328vp default');
  assert.equal(style.barWidth.largeWidth, width - 32);
  assert.equal(style.miniBar.miniBarWidth, undefined, 'native collapse keeps room for the round tab');
}
for (const width of [600, 720, 840, 1200]) {
  page.viewportWidth = width;
  const style = page.floatingBarStyle();
  assert.equal(style.miniBar.barLayoutMode, 0, 'expanded large windows use one row');
  assert.equal(style.barWidth.largeWidth + style.miniBar.miniBarWidth.largeWidth + 8, width - 32);
}
page.viewportWidth = 480; page.sideSafeVp = 20;
assert.equal(page.floatingBarStyle().barWidth.mediumWidth, 408, 'safe areas remain outside the bar');
const stableStyle = page.floatingBarStyle();
assert.equal(page.floatingBarStyle(), stableStyle, 'unchanged foreground appearance retains native options identity');
theme.FloatingBarMask = { id: 100, type: 10001, params: ['mask'] };
assert.equal(page.floatingBarStyle(), stableStyle, 'equivalent resource objects from membership revalidation do not recreate the bar');
theme.FloatingBarMask = { id: 101, type: 10001, params: ['other-mask'] };
assert.notEqual(page.floatingBarStyle(), stableStyle, 'real theme changes still update the bar');
page.generalSettings.adaptiveHandedness = false;
const updatedStyle = page.floatingBarStyle();
assert.notEqual(updatedStyle, stableStyle, 'actual preference change updates native options');
assert.equal(updatedStyle.miniBar.miniBarBuilder, stableStyle.miniBar.miniBarBuilder,
  'layout and appearance updates preserve playback builder identity');
const resolvedAppearance = page.tabsAppearance;
assert.equal(page.tabsAppearance, resolvedAppearance, 'unchanged computed appearance preserves identity');
page.bottomSafeVp += 10;
assert.notEqual(page.tabsAppearance, resolvedAppearance, 'actual safe-area change updates computed appearance');
page.bottomSafeVp -= 10;
page.miniPlayerVisible = () => false;
for (const width of [480, 800]) {
  page.viewportWidth = width;
  const style = page.floatingBarStyle();
  assert.equal(style.miniBar, undefined);
  assert.equal(style.barWidth.mediumWidth, width - 72, 'without playback navigation gets the full safe row');
}
page.viewportWidth = 480; page.appearance.verticalBottomTabs = false;
assert.equal(page.floatingBarStyle().barWidth, undefined, 'legacy appearance retains native widths');
platform.floatingTabs = false;
assert.equal(page.floatingBarStyle(), undefined, 'API fallback retains fixed tabs');
console.log('PASS floating tabs: phone/wide-phone growth, two-row retention, large-window shared width, safe areas, no playback and legacy fallback');

platform.floatingTabs = true;
Object.assign(page, { viewportWidth: 480, viewportHeight: 800, appearance: { verticalBottomTabs: true },
  miniPlayerVisible: () => true, currentPlaybackBook: () => ({ id: 'book' }),
  verticalBarCollapsed: false, miniBarExpandTimer: -1, viewportUpdateTimerId: -1, currentTab: 2 });
const animations = [];
page.tabController = { applyMiniBarStyle: style => animations.push(style) };
page.handleBarStyleChange(0, 1, 328, 448, 0);
for (let i = 0; i < 3; i++) {
  page.resetTabStyle(); // NavBar visible callback on returning from the background.
  page.syncVerticalBars(); // A repeated mini-player onAppear callback.
  flush();
}
assert.deepEqual(animations, [], 'foreground and onAppear must not replay an already-applied native animation');
page.verticalBarCollapsed = true; page.syncVerticalBars(); flush();
assert.deepEqual(animations, [1], 'real scroll collapse still animates');
page.syncVerticalBars(); flush();
assert.deepEqual(animations, [1], 'in-flight requests are not submitted twice');
page.handleBarStyleChange(1, 0, 384, 56, 2);
page.resetTabStyle(); flush();
assert.deepEqual(animations, [1, 0], 'returning to expanded layout animates only when necessary');
page.handleBarStyleChange(0, 1, 328, 448, 0);
page.handleViewportSizeChange({ width: 0, height: 0 }); flush();
assert.equal(page.viewportWidth, 480, 'background transient zero size cannot rebuild the bars');
page.handleViewportSizeChange({ width: 800, height: 900 }); flush(); flush();
assert.equal(animations.at(-1), 1, 'genuine fold/window resize still switches native layout');
page.handleBarStyleChange(1, 1, 380, 380, 0);
page.handleViewportSizeChange({ width: 480, height: 800 }); flush(); flush();
assert.equal(animations.at(-1), 0);
page.appliedVerticalBarStyle = undefined;
page.tabController.applyMiniBarStyle = () => { throw Error('not ready'); };
page.syncVerticalBars(); flush();
assert.equal(page.appliedVerticalBarStyle, undefined, 'failed application may retry');
page.tabController.applyMiniBarStyle = style => animations.push(style);
const before = animations.length;
page.syncVerticalBars(); flush();
assert.equal(animations.length, before + 1);
assert.equal(page.currentTab, 2, 'layout updates preserve the active tab');
console.log('PASS floating tab resume: unchanged-state no-op, in-flight deduplication, real collapse/expand, resize, zero-size guard and retry');
