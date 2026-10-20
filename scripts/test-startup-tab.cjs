const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/MainPage.ets'), 'utf8');
const methods = source.slice(source.indexOf('  private async restoreDefaultTab'), source.indexOf("  @Monitor('generalSettings.historyEnabled')"));
function page(read, historyEnabled = true) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, PreferenceService: { getDefaultTab: read } });
  const value = new exports.Page();
  Object.assign(value, { tabsReady: false, defaultTabRequest: 0, pendingInitialTab: -1,
    currentTab: 0, initialTabIndex: 0, generalSettings: { historyEnabled }, switches: [] });
  value.tabController = { changeIndex: i => value.switches.push(i) };
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
      assert.equal(p.initialTabIndex, !history && index === 3 ? 2 : p.currentTab);
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
  console.log('PASS: direct startup tabs, hidden history mapping, pending navigation, disposal and storage fallback');
})().catch(error => { console.error(error); process.exitCode = 1; });
