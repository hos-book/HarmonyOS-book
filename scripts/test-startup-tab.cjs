const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const policyExports = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/MainTabPolicy.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, { exports: policyExports });
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/MainPage.ets'), 'utf8');
const methods = source.slice(source.indexOf('  private async restoreDefaultTab'), source.indexOf("  @Monitor('generalSettings.historyEnabled')"));
const tabOptions = source.match(/HdsTabs\((\{[\s\S]*?\})\)\s*\{/)[1];
const tabChanged = source.slice(source.indexOf('  private handleTabChange'),
  source.indexOf('  @Builder', source.indexOf('  private handleTabChange')));
const historyChanged = source.slice(source.indexOf('  private onHistoryVisibilityChanged'),
  source.indexOf('  private async restoreLastPlayed'));
function page(read, historyEnabled = true) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} ${historyChanged} ${tabChanged}
    renderTabs() { return ${tabOptions}; }
    tabChanged(index: number) { this.handleTabChange(index); }
    resetTabStyle() {}
  }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, PreferenceService: { getDefaultTab: read }, Curve: { EaseOut: 'ease-out' },
    MainTabPolicy: policyExports.MainTabPolicy, GestureJudgeResult: { CONTINUE: 0, REJECT: 1 } });
  const value = new exports.Page();
  Object.assign(value, { tabsReady: false, defaultTabRequest: 0, pendingInitialTab: -1,
    currentTab: 0, generalSettings: { historyEnabled, swipeSwitchTabs: true }, switches: [] });
  value.tabController = { changeIndex: i => value.switches.push(i) };
  value.getUIContext = () => ({ animateTo: (_options, update) => update() });
  return value;
}
(async () => {
  for (const history of [true, false]) {
    for (const index of [0, 1, 2, 3]) {
      const p = page(async () => index, history);
      const work = p.restoreDefaultTab();
      assert.equal(p.tabsReady, false);
      await work;
      assert.equal(p.tabsReady, true);
      assert.equal(p.currentTab, !history && index === 2 ? 0 : index);
      assert.equal(p.renderTabs().index, (history ? [0, 1, 2, 3] : [0, 1, 0, 2])[index]);
      assert.deepEqual(p.switches, [], 'initial selection must not animate through home');
    }
  }
  let resolve;
  const pending = page(() => new Promise(r => { resolve = r; }));
  const work = pending.restoreDefaultTab();
  pending.changeTab(0);
  resolve(1);
  await work;
  assert.equal(pending.currentTab, 0, 'explicit home navigation wins over saved shelf');
  pending.changeTab(3);
  assert.deepEqual(pending.switches, [3]);
  const gone = page(async () => 1);
  const stale = gone.restoreDefaultTab();
  gone.defaultTabRequest++;
  await stale;
  assert.equal(gone.tabsReady, false);
  const failed = page(async () => { throw Error('storage'); });
  await failed.restoreDefaultTab();
  assert.equal(failed.tabsReady, true);
  assert.equal(failed.currentTab, 0);
  let preferenceReads = 0;
  let defaultTab = 1;
  const readDefault = async () => { preferenceReads++; return defaultTab; };
  const active = page(readDefault);
  await active.restoreDefaultTab();
  assert.equal(active.renderTabs().index, 1);
  active.tabChanged(0);
  assert.equal(active.currentTab, 0);
  for (const refresh of ['playback started', 'player returned', 'detail returned', 'foreground resumed']) {
    active.playerState = { currentBook: { id: 'playing-book' }, isPlaying: true };
    await active.restoreDefaultTab();
    assert.equal(active.renderTabs().index, 0, `${refresh} must preserve the selected home tab`);
  }
  defaultTab = 3;
  await active.restoreDefaultTab();
  assert.equal(active.renderTabs().index, 0, 'editing the startup preference must not navigate now');
  assert.equal(preferenceReads, 1, 'the current page reads the default only on initialization');
  const cold = page(readDefault);
  await cold.restoreDefaultTab();
  assert.equal(cold.renderTabs().index, 3, 'the new default applies on the next cold start');
  const hidden = page(async () => 1, false);
  await hidden.restoreDefaultTab();
  hidden.tabChanged(2);
  assert.equal(hidden.currentTab, 3);
  assert.equal(hidden.renderTabs().index, 2, 'refresh must preserve profile with hidden history');
  hidden.generalSettings.historyEnabled = true;
  hidden.onHistoryVisibilityChanged();
  assert.equal(hidden.renderTabs().index, 3, 'showing history must preserve the logical profile tab');
  hidden.tabChanged(2);
  hidden.generalSettings.historyEnabled = false;
  hidden.onHistoryVisibilityChanged();
  assert.equal(hidden.currentTab, 0);
  assert.equal(hidden.renderTabs().index, 0, 'hiding the active history tab must fall back to home');
  const motion = page(async () => 1);
  await motion.restoreDefaultTab();
  motion.getUIContext = () => ({ animateTo: () => {
    assert.fail('tab changes must use HdsTabs native animation');
  } });
  motion.tabController = { changeIndex: index => {
    motion.switches.push(index);
    motion.tabChanged(index);
  } };
  motion.changeTab(2);
  assert.equal(motion.currentTab, 2, 'native animation start selects the target');
  motion.changeTab(3);
  motion.changeTab(0);
  assert.equal(motion.currentTab, 0, 'new requests are delegated to the native controller');
  assert.deepEqual(motion.switches, [2, 3, 0]);
  const repeatedCount = motion.switches.length;
  motion.changeTab(0);
  motion.tabChanged(0);
  assert.equal(motion.switches.length, repeatedCount, 'reselecting the current tab does not request a switch');
  motion.changeTab(3);
  motion.generalSettings.historyEnabled = false;
  motion.onHistoryVisibilityChanged();
  assert.equal(motion.currentTab, 3);
  assert.equal(motion.nativeTabIndex, 2, 'profile follows shelf when history is hidden');
  motion.changeTab(1);
  assert.equal(motion.currentTab, 1);
  assert.ok(source.includes('.scrollable(false)'), 'native bottom-tab swipes stay disabled');
  motion.generalSettings.swipeSwitchTabs = false;
  assert.equal(motion.judgeTabSwipe({ tag: 'main-tab-swipe' }), 1);
  assert.equal(motion.judgeTabSwipe({ tag: 'other' }), 0);
  motion.handleTabSwipe({ offsetX: -100, offsetY: 0 });
  assert.equal(motion.currentTab, 1, 'disabled tab swipes leave type navigation available');
  motion.generalSettings.swipeSwitchTabs = true;
  assert.equal(motion.judgeTabSwipe({ tag: 'main-tab-swipe' }), 0);
  for (const event of [{ offsetX: -20, offsetY: 0 }, { offsetX: 60, offsetY: 100 }]) motion.handleTabSwipe(event);
  assert.equal(motion.currentTab, 1, 'short and vertical gestures do not switch tabs');
  motion.handleTabSwipe({ offsetX: -100, offsetY: 0 });
  assert.equal(motion.currentTab, 3, 'swipe skips hidden history');
  motion.generalSettings.historyEnabled = true;
  motion.onHistoryVisibilityChanged();
  assert.equal(motion.currentTab, 3);
  assert.equal(motion.renderTabs().index, 3);
  motion.generalSettings.historyEnabled = false;
  motion.onHistoryVisibilityChanged();
  const edgeSwitchCount = motion.switches.length;
  motion.handleTabSwipe({ offsetX: -100, offsetY: 0 });
  assert.equal(motion.switches.length, edgeSwitchCount, 'last tab does not wrap');
  motion.changeTab(0);
  const firstSwitchCount = motion.switches.length;
  motion.handleTabSwipe({ offsetX: 100, offsetY: 0 });
  assert.equal(motion.switches.length, firstSwitchCount, 'first tab does not wrap');
  console.log('PASS: native tab selection, rapid input, gesture preference and hidden history');
  console.log('PASS: cold-start defaults, current tab across playback/return/refresh, hidden history mapping, pending navigation, disposal and storage fallback');
})().catch(error => { console.error(error); process.exitCode = 1; });
