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
const scroll = source.slice(source.indexOf('  private onContentScroll'), source.indexOf('  private handleViewportSizeChange'));
const layout = source.slice(source.indexOf('  private handleViewportSizeChange'), source.indexOf('  private restoreExpandedTabBars'));
const constants = source.slice(source.indexOf('const FLOATING_BOTTOM'), source.indexOf('@ComponentV2'));
const appearance = source.slice(source.indexOf('  private get tabsAppearance'), source.indexOf('  private restoreTabBarOnWindowGrow'));
const exportsObject = {};
const platform = { floatingTabs: true, supports: () => true };
const timers = new Map(); let nextTimer = 0;
const theme = { FloatingBarMask: { id: 100, type: 10001, params: ['mask'] } };
const barModes = { NORMAL: 0, USER_CLICK: 1, CONTROLLER: 2 };
const contentAnimations = [];
const flush = () => { const work = [...timers.values()]; timers.clear(); for (const f of work) f(); };
vm.runInNewContext(ts.transpileModule(`${constants}\nexport class Page { ${helpers} ${method} ${sync} ${reset} ${scroll} ${layout} ${appearance} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, { exports: exportsObject, PlatformCompat: platform, HomeTheme: theme,
  setTimeout: f => { const id = ++nextTimer; timers.set(id, f); return id; }, clearTimeout: id => timers.delete(id),
  WindowUtils: { refreshAvoidArea() {} }, hilog: { info() {}, warn() {} }, HdsTabsBarChangeMode: barModes,
  AppMotion: { Slow: 350 }, AppCurve: { Standard: 'standard' }, ScrollState: { Scroll: 1 },
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
  verticalBarCollapsed: false, miniBarCompactControls: false, miniBarAnimationRunning: false,
  requestedMiniBarStyle: undefined, miniBarExpandTimer: -1, viewportUpdateTimerId: -1, currentTab: 2,
  scrollDistance: 0, showMiniChapters: false, navStack: { getAllPathName: () => [] },
  getUIContext: () => ({ animateTo: (options, update) => { contentAnimations.push(options); update(); } }) });
const animations = [];
page.tabController = { applyMiniBarStyle: style => animations.push(style) };
const miniBar = page.floatingBarStyle().miniBar;
miniBar.onBarStyleChange(0, 1, 328, 448, barModes.NORMAL);
for (let i = 0; i < 3; i++) {
  page.resetTabStyle(); // NavBar visible callback on returning from the background.
  page.syncVerticalBars(); // A repeated mini-player onAppear callback.
  flush();
}
assert.deepEqual(animations, [], 'foreground and onAppear must not replay an already-applied native animation');
page.onContentScroll(2, 24, 1);
assert.deepEqual(animations, [1], 'real scroll collapse submits immediately without a timer delay');
assert.equal(page.miniBarCompactControls, false, 'scroll intent cannot resize the cover before native animation starts');
assert.equal(contentAnimations.length, 0, 'scroll intent does not start a separate content animation');
miniBar.onBarStyleChange(1, 0, 384, 56, barModes.CONTROLLER);
assert.equal(page.requestedMiniBarStyle, 1, 'style-change before native start preserves the controller target');
assert.equal(page.miniBarCompactControls, false, 'style-change before native start does not resize content early');
miniBar.onMiniBarAnimationStart(0, 384);
assert.equal(page.miniBarCompactControls, true, 'native start synchronizes content to the requested target, not the source style');
assert.equal(contentAnimations.length, 1);
assert.equal(page.floatingBarStyle().miniBar, miniBar, 'animation callbacks do not recreate native bar options');
page.syncVerticalBars(); flush();
assert.deepEqual(animations, [1], 'in-flight requests are not submitted twice');
miniBar.onMiniBarAnimationEnd(1);
assert.equal(page.miniBarAnimationRunning, false);
assert.equal(page.requestedMiniBarStyle, undefined);
page.resetTabStyle(); flush();
assert.deepEqual(animations, [1, 0], 'returning to expanded layout animates only when necessary');
assert.equal(page.miniBarCompactControls, true, 'return intent also waits for the native start callback');
miniBar.onMiniBarAnimationStart(1, 448);
assert.equal(page.miniBarCompactControls, false);
miniBar.onBarStyleChange(0, 1, 448, 448, barModes.CONTROLLER);
miniBar.onMiniBarAnimationEnd(0);
assert.deepEqual(animations, [1, 0], 'a matching native end must not replay the completed animation');
console.log('PASS native animation lifecycle: immediate scroll request, synchronized content, final calibration and stable options');

const beforeUserClick = animations.length;
// Native clicks can report the new style before or after the animation-start callback.
miniBar.onMiniBarAnimationStart(0, 384);
miniBar.onBarStyleChange(1, 0, 384, 56, barModes.USER_CLICK);
miniBar.onMiniBarAnimationEnd(1);
assert.equal(page.verticalBarCollapsed, true);
assert.equal(page.miniBarCompactControls, true);
miniBar.onBarStyleChange(0, 1, 448, 448, barModes.USER_CLICK);
assert.equal(page.verticalBarCollapsed, false, 'clicking the round tab updates the requested layout');
assert.equal(page.miniBarCompactControls, true, 'style-change notification alone cannot jump the content layout');
miniBar.onMiniBarAnimationStart(1, 448);
miniBar.onMiniBarAnimationEnd(0);
assert.equal(page.miniBarCompactControls, false);
assert.equal(animations.length, beforeUserClick, 'native user clicks are not submitted again through the controller');

const beforeReverse = animations.length;
page.onContentScroll(2, 24, 1);
miniBar.onMiniBarAnimationStart(0, 384);
page.onContentScroll(2, -24, 1);
assert.deepEqual(animations.slice(beforeReverse), [1, 0], 'reverse scroll submits in the same call without waiting for native end');
assert.equal(page.miniBarCompactControls, true, 'reverse intent waits only for its own native start to resize content');
miniBar.onBarStyleChange(0, 1, 448, 448, barModes.CONTROLLER);
miniBar.onMiniBarAnimationStart(1, 448);
assert.equal(page.miniBarCompactControls, false);
miniBar.onMiniBarAnimationEnd(1);
assert.equal(page.requestedMiniBarStyle, 0, 'a stale end callback cannot clear the newer target');
assert.equal(page.appliedVerticalBarStyle, 0, 'a stale end callback cannot overwrite the latest submitted style');
assert.equal(page.miniBarCompactControls, false, 'a stale end callback cannot restore the previous content geometry');
assert.deepEqual(animations.slice(beforeReverse), [1, 0], 'a stale end callback does not resubmit the latest request');
page.onContentScroll(2, 24, 1);
assert.deepEqual(animations.slice(beforeReverse), [1, 0, 1], 'another direction change is submitted immediately');
miniBar.onMiniBarAnimationStart(0, 384);
page.onContentScroll(2, -24, 1);
assert.deepEqual(animations.slice(beforeReverse), [1, 0, 1, 0], 'every threshold-crossing reversal reaches the native controller immediately');
assert.equal(page.verticalBarCollapsed, false);
miniBar.onMiniBarAnimationStart(1, 448);
miniBar.onBarStyleChange(0, 1, 448, 448, barModes.CONTROLLER);
miniBar.onMiniBarAnimationEnd(0);
assert.equal(page.miniBarCompactControls, false);
assert.deepEqual(animations.slice(beforeReverse), [1, 0, 1, 0], 'the final end settles without an extra controller call');

const beforeCancelledEnd = animations.length;
page.onContentScroll(2, 24, 1);
miniBar.onMiniBarAnimationStart(0, 384);
page.onContentScroll(2, -24, 1);
miniBar.onMiniBarAnimationEnd(0);
assert.equal(page.miniBarCompactControls, false, 'an interrupted animation settles to the actual end style');
assert.equal(page.appliedVerticalBarStyle, 0);
assert.equal(page.requestedMiniBarStyle, undefined);
assert.equal(animations.length, beforeCancelledEnd + 2, 'the reversed request is immediate and its matching end needs no retry');
console.log('PASS native clicks and reversals: callback order, immediate reversal and stale-end protection');

page.handleViewportSizeChange({ width: 0, height: 0 }); flush();
assert.equal(page.viewportWidth, 480, 'background transient zero size cannot rebuild the bars');
page.handleViewportSizeChange({ width: 800, height: 900 }); flush(); flush();
assert.equal(animations.at(-1), 1, 'genuine fold/window resize still switches native layout');
page.handleBarStyleChange(1, 1, 380, 380, barModes.NORMAL);
assert.equal(page.miniBarCompactControls, true, 'wide-window initialization synchronizes without an animation callback');
page.handleViewportSizeChange({ width: 480, height: 800 }); flush(); flush();
assert.equal(animations.at(-1), 0);
page.handleBarStyleChange(0, 1, 448, 448, barModes.NORMAL);
assert.equal(page.miniBarCompactControls, false, 'narrow-window initialization restores two-row content');
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

page.appearance.verticalBottomTabs = false;
const beforeLegacy = animations.length;
const beforeLegacyContent = contentAnimations.length;
page.handleMiniBarAnimationStart(0, 384);
page.handleMiniBarAnimationEnd(1);
page.handleBarStyleChange(1, 0, 384, 56, barModes.USER_CLICK);
assert.equal(page.miniBarCollapsed, false, 'legacy style callbacks still mirror the expanded player');
assert.equal(page.restoreTabBarOnWindowGrow, true, 'legacy tab restore policy remains active');
assert.equal(animations.length, beforeLegacy);
assert.equal(contentAnimations.length, beforeLegacyContent, 'new content synchronization stays out of the legacy branch');
console.log('PASS legacy callbacks: native style mirroring and resize restore remain unchanged');
