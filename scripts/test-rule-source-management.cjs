// Run with DEVECO_HOME pointing to the installed Release IDE.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release DevEco Studio');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
function compile(text, globals = {}) {
  const context = { exports: {}, Map, Set, console, ...globals };
  const code = ts.transpileModule(text.replace(/import lazy /g, 'import ').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, ''), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  vm.runInNewContext(code, context);
  return context.exports;
}
const page = fs.readFileSync(path.join(root, 'pages/RuleSourcePage.ets'), 'utf8').replace(/\r\n/g, '\n');
const dataCode = page.slice(page.indexOf('@ObservedV2\nclass RuleSourceListItem'), page.indexOf('@ComponentV2'));
const { RuleSourceDataSource } = compile(`${dataCode}\nexport { RuleSourceDataSource };`);
const source = (url, extra = {}) => ({ bookSourceUrl: url, bookSourceName: url,
  enabled: true, enabledExplore: false, isLocked: false, isPinned: false, customOrder: 0,
  canExecute: () => true, ...extra });
function testRows() {
  const data = new RuleSourceDataSource();
  let notifications = 0;
  const listener = { onDataReloaded: () => notifications++ };
  data.registerDataChangeListener(listener);
  data.registerDataChangeListener(listener);
  data.setSources([source('a'), source('b')]);
  const a = data.getData(0), b = data.getData(1);
  // A cached UI callback must resolve the new object and the current row position.
  const click = () => [a.source.bookSourceName, a.source.isPinned, a.index];
  const edited = source('a', { bookSourceName: 'Edited', isPinned: true, enabled: false,
    enabledExplore: true, isLocked: true, bookSourceGroup: 'New group', validationMessage: 'Updated' });
  data.setSources([source('b'), edited]);
  assert.equal(data.getData(1), a);
  assert.equal(data.getData(0), b);
  assert.equal(a.source, edited);
  assert.deepEqual(click(), ['Edited', true, 1]);
  data.setSources([edited, source('b')]);
  assert.deepEqual(click(), ['Edited', true, 0]);
  data.setSources([source('b')]);
  assert.equal(data.totalCount(), 1);
  assert.equal(data.getData(0), b);
  data.setSources([]);
  assert.equal(data.totalCount(), 0);
  assert.equal(notifications, 5);
  data.unregisterDataChangeListener(listener);
  data.setSources([source('c')]);
  assert.equal(notifications, 5);
}
const repositoryText = fs.readFileSync(path.join(root, 'service/rulesource/LocalRuleSourceRepository.ets'), 'utf8');
let membershipCalls = 0;
const { LocalRuleSourceRepository: repo } = compile(repositoryText, {
  require: name => {
    if (name === '@kit.ArkData') return { relationalStore: { ConflictResolution: { ON_CONFLICT_REPLACE: 1 } } };
    if (name === '../MembershipService') return { MembershipService: { instance: {
      hasCurrentEntitlement: async () => {
        membershipCalls++;
        throw new Error('Membership verification unavailable');
      }
    } } };
    if (name === '../../model/MembershipState') return { MembershipState: { current: { get hasAccess() { return false; } } } };
    return {};
  }
});
async function testImportOrder() {
  let rows = new Map([
    ['pin-a', source('pin-a', { isPinned: true, customOrder: 3 })],
    ['pin-b', source('pin-b', { isPinned: true, customOrder: 5 })],
    ['old', source('old', { customOrder: 8 })],
    ['locked', source('locked', { customOrder: 9, isLocked: true })],
    ['reimport', source('reimport', { customOrder: 10, enabled: false })]
  ]);
  let failUrl = '';
  const result = (values, existing) => ({ goToFirstRow: () => values.length > 0,
    getLong: index => values[index] || 0, close() {}, existing });
  repo.ensureStore = async () => ({ createTransaction: async () => {
    const pending = new Map([...rows].map(([url, row]) => [url, { ...row }]));
    return {
      querySql: async (sql, args) => {
        if (sql.includes('MAX(custom_order)')) {
          const orders = [...pending.values()].map(row => row.customOrder);
          return result(orders.length ? [Math.max(...orders), Math.min(...orders), pending.size] : [0, 0, 0]);
        }
        const existing = pending.get(args[0]);
        return result(existing ? [1] : [], existing);
      },
      insert: async (_table, row) => {
        if (row.bookSourceUrl === failUrl) throw new Error('fixture write failure');
        pending.set(row.bookSourceUrl, { ...row });
        return 1;
      },
      commit: async () => { rows = pending; },
      rollback: async () => {}
    };
  } });
  // Keep actual transaction/order/preservation logic; isolate SQL encoding and SDK storage.
  repo.prepare = item => ({ source: item });
  repo.readSource = result => result.existing;
  repo.toValues = item => item.source;
  const count = await repo.upsertImportedBatch([
    source('new-a', { customOrder: 999 }), source('reimport'), source('new-b'),
    source('pin-b'), source('locked', { bookSourceName: 'Must not replace' })
  ]);
  assert.equal(count, 4);
  const sorted = () => [...rows.values()].sort((a, b) =>
    Number(b.isPinned) - Number(a.isPinned) || a.customOrder - b.customOrder).map(row => row.bookSourceUrl);
  assert.deepEqual(sorted(), ['pin-a', 'pin-b', 'new-a', 'reimport', 'new-b', 'old', 'locked']);
  assert.equal(rows.get('pin-b').customOrder, 5);
  assert.equal(rows.get('reimport').enabled, false);
  assert.equal(rows.get('locked').bookSourceName, 'locked');
  await repo.upsertImportedBatch([source('latest')]);
  assert.equal(sorted()[2], 'latest');
  const oldOrder = rows.get('old').customOrder;
  await repo.update(source('old', { bookSourceName: 'Edited old' }));
  assert.equal(rows.get('old').customOrder, oldOrder);
  const beforeFailure = sorted();
  failUrl = 'broken';
  await assert.rejects(repo.upsertImportedBatch([source('rollback'), source('broken')]), /fixture write failure/);
  assert.deepEqual(sorted(), beforeFailure);
  rows = new Map();
  failUrl = '';
  await repo.upsertImportedBatch([source('first'), source('second')]);
  assert.deepEqual(sorted(), ['first', 'second']);
  await repo.upsertImportedBatch(Array.from({ length: 8 }, (_, i) => source('free-' + i)));
  assert.equal(rows.size, 10);
  await repo.insert(source('eleventh'));
  assert.equal(rows.size, 11, 'non-member can manually add the eleventh source');
  await repo.upsertImportedBatch([source('first', { bookSourceName: 'Updated' }), source('twelfth')]);
  assert.equal(rows.size, 12);
  assert.equal(rows.get('first').bookSourceName, 'Updated');
  await repo.upsertImportedBatch(Array.from({ length: 58 }, (_, i) => source('more-' + i)));
  assert.equal(rows.size, 70, 'non-member imports have no membership count cap');
  const existing = [...rows.keys()].map(url => source(url));
  assert.equal(await repo.upsertImportedBatch(existing), 70);
  assert.equal(rows.size, 70, 'reimport updates rather than duplicates sources');
  await repo.upsertImportedBatch([source('extra'), source('extra')]);
  assert.equal(rows.size, 71);
  assert.equal(membershipCalls, 0, 'imports and edits never depend on membership verification');
}
(async () => {
  testRows();
  await testImportOrder();
  console.log('PASS: cached row refresh, current action/index, removal, import precedence, pinned order, locked sources, edit order and rollback');
})().catch(error => { console.error(error); process.exitCode = 1; });
