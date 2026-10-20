const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/ReadingStatsPage.ets'), 'utf8');
const start = source.indexOf('  private clearSelection(');
const end = source.indexOf('  private openDetail(', start);
assert.ok(start > 0 && end > start);
const code = ts.transpileModule(`class Page { ${source.slice(start, end)} }`, {
  compilerOptions: { target: ts.ScriptTarget.ES2021 }
}).outputText;
const writes = [];
const Page = vm.runInNewContext(`${code}; Page`, {
  Set, Array, $r: (...args) => args, AppColor: { BrandDark: 'brand' },
  DiagnosticLogService: { info() {} },
  StatsService: { removeBookStats: async ids => writes.push(['stats', ...ids]) },
  PreferenceService: { removeHistory: async id => writes.push(['history', id]),
    removeProgress: async id => writes.push(['audio', id]) },
  TextReadingProgressService: { remove: async (_, id) => writes.push(['text', id]) }
});
let resolveDialog;
let dialogs = 0;
function page() {
  const p = new Page();
  Object.assign(p, { selectedIds: new Set(['book']), records: [{ bookId: 'book', aliasBookIds: ['alias'] }],
    recoveryActive: true, deletingRecords: false, selectMode: true,
    getUIContext: () => ({ getHostContext: () => ({}), getPromptAction: () => ({
      showDialog: () => { dialogs++; return new Promise(resolve => { resolveDialog = resolve; }); },
      showToast() {}
    }) }), loadStats: async () => {} });
  return p;
}
(async () => {
  const p = page();
  let work = p.confirmDeleteSelected();
  assert.equal(writes.length, 0, 'opening confirmation cannot delete');
  await p.confirmDeleteSelected();
  assert.equal(dialogs, 1, 'repeated tap cannot open another confirmation');
  resolveDialog({ index: 0 }); await work;
  assert.equal(writes.length, 0);
  assert.equal(p.selectedIds.has('book'), true, 'cancel preserves selection');
  work = p.confirmDeleteSelected();
  p.selectedIds = new Set(['other']);
  resolveDialog({ index: 1 }); await work;
  assert.deepEqual(writes[0], ['stats', 'book', 'alias'], 'confirmed snapshot includes original aliases only');
  assert.equal(writes.length, 7);
  assert.equal(p.deletingRecords, false);
  writes.length = 0;
  const leaving = page();
  work = leaving.confirmDeleteSelected();
  leaving.recoveryActive = false;
  resolveDialog({ index: 1 }); await work;
  assert.equal(writes.length, 0, 'leaving page invalidates confirmation');
  const editing = page();
  assert.equal(editing.handleBack(), true, 'first back consumes edit state');
  assert.equal(editing.selectMode, false);
  assert.equal(editing.selectedIds.size, 0);
  assert.equal(editing.handleBack(), false, 'next back follows normal navigation');
  editing.selectMode = true;
  assert.equal(editing.handleBack(), true, 'editing with no selection still consumes back');
  editing.deletingRecords = true;
  assert.equal(editing.handleBack(), true, 'pending deletion must not pop the page');
  const main = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/MainPage.ets'), 'utf8');
  const routeStart = main.indexOf('    this.onBackHandlerChange((): boolean => {');
  const routeEnd = main.indexOf('\n    });', routeStart) + '\n    });'.length;
  assert.ok(routeStart > 0 && routeEnd > routeStart);
  const routeCode = ts.transpileModule(main.slice(routeStart, routeEnd), {
    compilerOptions: { target: ts.ScriptTarget.ES2021 }
  }).outputText;
  let handler;
  const host = { currentTab: 2, generalSettings: { historyEnabled: true },
    recordsBackHandler: () => true, onBackHandlerChange: value => { handler = value; } };
  vm.runInNewContext(`(function() { ${routeCode} })`).call(host);
  assert.equal(handler(), true);
  host.currentTab = 3;
  assert.equal(handler(), false, 'inactive record tab must not consume back');
  host.currentTab = 2;
  host.generalSettings.historyEnabled = false;
  assert.equal(handler(), false, 'hidden record tab must not consume profile back');
  console.log('PASS record edit back: clear selection, empty edit, normal back, deletion guard, active-tab routing');
  console.log('PASS record delete confirmation: no pre-confirm writes, cancel, reentry, snapshot/aliases and page exit');
})().catch(error => { console.error(error); process.exitCode = 1; });
