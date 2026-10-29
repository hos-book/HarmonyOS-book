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
const tabChanged = source.match(/\.onChange\(\(index: number\) => \{([\s\S]*?)\n      \}\)/)[1];
const historyChanged = source.slice(source.indexOf('  private onHistoryVisibilityChanged'),
  source.indexOf('  private async restoreLastPlayed'));
function page(read, historyEnabled = true) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} ${historyChanged}
    renderTabs() { return ${tabOptions}; }
    tabChanged(index: number) { ${tabChanged} }
  }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, PreferenceService: { getDefaultTab: read }, Curve: { EaseOut: 'ease-out' },
    MainTabPolicy: policyExports.MainTabPolicy, GestureJudgeResult: { CONTINUE: 0, REJECT: 1 } });
  const value = new exports.Page();
  Object.assign(value, { tabsReady: false, defaultTabRequest: 0, pendingInitialTab: -1,
    tabFadeRunning: false, tabFadeCommitIndex: -1, tabFadeGeneration: 0, tabContentOpacity: 1,
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
  const fade = page(async () => 1);
  await fade.restoreDefaultTab();
  const finishes = [];
  fade.getUIContext = () => ({ animateTo: (options, update) => {
    update();
    if (options.onFinish) finishes.push(options.onFinish);
  } });
  fade.tabController = { changeIndex: index => {
    if (fade.allowTabContentChange(index)) {
      fade.switches.push(index);
      fade.tabChanged(index);
    }
  } };
  fade.changeTab(2);
  assert.equal(fade.currentTab, 1, 'outgoing page stays selected until fade-out finishes');
  assert.equal(fade.tabContentOpacity, 0);
  assert.deepEqual(fade.switches, []);
  fade.changeTab(3);
  assert.equal(finishes.length, 1, 'rapid taps must not enqueue competing fade-outs');
  finishes.shift()();
  assert.equal(fade.currentTab, 2);
  assert.equal(fade.tabContentOpacity, 1);
  assert.equal(fade.tabFadeRunning, true, 'keep the transition locked until fade-in completes');
  finishes.shift()();
  assert.equal(fade.tabFadeRunning, false);
  fade.changeTab(3);
  finishes.shift()();
  finishes.shift()();
  assert.equal(fade.currentTab, 3);
  fade.changeTab(3);
  assert.equal(finishes.length, 0, 'clicking the selected tab must not animate again');
  fade.changeTab(2);
  const obsoleteFinish = finishes.shift();
  fade.generalSettings.historyEnabled = false;
  fade.onHistoryVisibilityChanged();
  obsoleteFinish();
  assert.equal(fade.currentTab, 3, 'history visibility changes cancel stale transition commits');
  assert.equal(fade.nativeTabIndex, 2);
  assert.equal(fade.tabContentOpacity, 1);
  fade.changeTab(1);
  finishes.shift()();
  finishes.shift()();
  assert.equal(fade.currentTab, 1, 'clicking shelf works with hidden history');
  fade.changeTab(0);
  const disposedFinish = finishes.shift();
  fade.resetTabFade();
  disposedFinish();
  assert.equal(fade.currentTab, 1, 'disposed transitions cannot navigate later');
  assert.equal(fade.tabContentOpacity, 1);
  assert.ok(source.includes('.scrollable(false)'), 'native bottom-tab swipes stay disabled');
  fade.generalSettings.swipeSwitchTabs = false;
  assert.equal(fade.judgeTabSwipe({ tag: 'main-tab-swipe' }), 1, 'disabled tab gesture rejects before it steals type swipes');
  assert.equal(fade.judgeTabSwipe({ tag: 'other' }), 0, 'unrelated gestures remain available');
  fade.handleTabSwipe({ offsetX: -100, offsetY: 0 });
  assert.equal(finishes.length, 0, 'disabled swipe mode never schedules navigation');
  fade.generalSettings.swipeSwitchTabs = true;
  assert.equal(fade.judgeTabSwipe({ tag: 'main-tab-swipe' }), 0);
  for (const event of [{ offsetX: -20, offsetY: 0 }, { offsetX: 60, offsetY: 100 }]) fade.handleTabSwipe(event);
  assert.equal(finishes.length, 0);
  fade.handleTabSwipe({ offsetX: -100, offsetY: 0 });
  finishes.shift()(); finishes.shift()();
  assert.equal(fade.currentTab, 3, 'profile follows shelf when history is hidden');
  fade.generalSettings.historyEnabled = true;
  fade.onHistoryVisibilityChanged();
  assert.equal(fade.currentTab, 3, 'showing history preserves profile');
  assert.equal(fade.renderTabs().index, 3);
  fade.generalSettings.historyEnabled = false;
  fade.onHistoryVisibilityChanged();
  assert.equal(fade.currentTab, 3, 'enabled swipe follows visible tab order with history hidden');
  fade.handleTabSwipe({ offsetX: -100, offsetY: 0 });
  assert.equal(finishes.length, 0, 'last tab does not wrap');
  console.log('PASS: configurable tab swipes, click navigation, fade ordering, repeated input, hidden history and stale callbacks');
  console.log('PASS: cold-start defaults, current tab across playback/return/refresh, hidden history mapping, pending navigation, disposal and storage fallback');
})().catch(error => { console.error(error); process.exitCode = 1; });
