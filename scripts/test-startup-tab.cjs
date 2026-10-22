const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
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
  }).outputText, { exports, PreferenceService: { getDefaultTab: read }, Curve: { EaseOut: 'ease-out' } });
  const value = new exports.Page();
  Object.assign(value, { tabsReady: false, defaultTabRequest: 0, pendingInitialTab: -1,
    currentTab: 0, generalSettings: { historyEnabled }, switches: [] });
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
      assert.equal(p.renderTabs().index, !history && index === 3 ? 2 : p.currentTab);
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
  console.log('PASS: cold-start defaults, current tab across playback/return/refresh, hidden history mapping, pending navigation, disposal and storage fallback');
})().catch(error => { console.error(error); process.exitCode = 1; });
