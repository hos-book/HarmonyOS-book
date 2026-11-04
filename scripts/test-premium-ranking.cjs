// Real membership lease and ranking order policy with controlled time/storage.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
function load(file, imports, globals = {}) {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8').replace(/import lazy /g, 'import ');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2020 } }).outputText, { exports, require: n => {
      assert.ok(imports[n], n); return imports[n];
    }, ...globals });
  return exports;
}
async function main() {
  let now = 1000, callback, delay, allowed = true, revoked = 0, refreshes = 0;
  const state = { verifiedAt: now, expiresAt: now + 60000, lifetime: false, confirmedInactive: false };
  const { MembershipFeatureLease } = load('service/membership/MembershipFeatureLease.ets', {
    '../../model/MembershipState': { MembershipState: { featureEnabled: true, current: state } },
    '../MembershipService': { MembershipService: { instance: { hasCurrentEntitlement: async () => {
      refreshes++; return allowed;
    } } } }
  }, { Date: { now: () => now }, setTimeout: (fn, ms) => { callback = fn; delay = ms; return 1; },
    clearTimeout: () => { callback = undefined; } });
  const lease = new MembershipFeatureLease();
  lease.start(() => revoked++);
  assert.equal(delay, 60000);
  now += 60000; await callback();
  assert.equal(revoked, 1); assert.equal(refreshes, 0, 'expiry closes immediately without waiting for IAP');
  state.expiresAt = now + 900000; state.verifiedAt = now;
  lease.start(() => revoked++); assert.equal(delay, 240000);
  allowed = false; now += 240000; await callback(); assert.equal(revoked, 2);
  state.verifiedAt = now; allowed = true;
  lease.start(() => revoked++);
  const fired = callback; callback = undefined;
  const pending = fired(); lease.stop(); await pending;
  assert.equal(callback, undefined, 'stopping during verification cannot restart the lease');
  assert.equal(revoked, 2);

  let stored = '', failSave = false, notifications = 0;
  const { RankingPreferences } = load('service/ranking/RankingPreferences.ets', {
    '../PreferenceService': { PreferenceService: {
      getRankingBoardOrder: async () => stored,
      setRankingBoardOrder: async value => { if (failSave) throw Error('disk'); stored = value; }
    } }, './RankingService': { RankingService: {} }
  });
  const boards = [{ id: 'comic-hot' }, { id: 'comic-new' }, { id: 'novel-hot' }, { id: 'audio-hot' }];
  const ids = values => Array.from(values, v => v.id);
  RankingPreferences.subscribe(() => notifications++);
  await RankingPreferences.saveBoardOrder(['novel-hot', 'comic-hot', 'audio-hot', 'comic-new']);
  assert.deepEqual(ids(RankingPreferences.orderBoards(boards, await RankingPreferences.loadBoardOrder())),
    ['novel-hot', 'comic-hot', 'audio-hot', 'comic-new']);
  assert.equal(notifications, 1);
  assert.deepEqual(ids(RankingPreferences.orderBoards(boards, ['removed', 'novel-hot', 'novel-hot'])),
    ['novel-hot', 'comic-hot', 'comic-new', 'audio-hot']);
  assert.deepEqual(ids(RankingPreferences.orderBoards(boards.filter(b => !b.id.startsWith('comic')), stored.split(','))),
    ['novel-hot', 'audio-hot']);
  failSave = true;
  await assert.rejects(RankingPreferences.saveBoardOrder([]));
  assert.equal(notifications, 1); assert.ok(stored);
  failSave = false; await RankingPreferences.saveBoardOrder([]);
  assert.deepEqual(ids(RankingPreferences.orderBoards(boards, await RankingPreferences.loadBoardOrder())), ids(boards));
  console.log('PASS premium expiry, renewal cancellation, mixed ranking order, unknown/duplicate IDs, disabled platforms, save failure and reset');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
