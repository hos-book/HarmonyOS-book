// Regression tests execute the real medal service/model; platform storage and statistics are simulated.
// DEVECO_HOME must point to the Release IDE.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { createHash } = require('node:crypto');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hsda-medals-'));
const disk = path.join(root, 'medals.json');
const context = { filesDir: root };
const compiled = new Map();
let passed = 0;
function processFixture(seconds = 0) {
  const control = { seconds, failRead: false, failWrite: false, statsUnavailable: false, writes: 0 };
  const listeners = new Map();
  const emitter = { on: (id, fn) => listeners.set(id, fn), emit: (id, data = {}) => listeners.get(id)?.(data) };
  let memory = fs.existsSync(disk) ? JSON.parse(fs.readFileSync(disk, 'utf8')) : {};
  if (memory.version === 1) memory = { medal_state_v1: JSON.stringify(memory) };
  const store = {
    get: async (key, fallback) => { if (control.failRead) throw new Error('read failed'); return memory[key] ?? fallback; },
    put: async (key, value) => { memory[key] = value; },
    flush: async () => { if (control.failWrite) throw new Error('disk full'); fs.writeFileSync(disk, JSON.stringify(memory)); control.writes++; }
  };
  const modules = new Map();
  function load(relative) {
    if (modules.has(relative)) return modules.get(relative);
    if (!compiled.has(relative)) compiled.set(relative, ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', relative + '.ets'), 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021, experimentalDecorators: true }
    }).outputText);
    const exports = {};
    modules.set(relative, exports);
    vm.runInNewContext(compiled.get(relative), {
      exports, ObservedV2: value => value, Trace: () => {}, $r: name => ({ id: name }),
      console: { warn() {} },
      require: name => {
        if (name === '@kit.ArkData') return { preferences: { getPreferences: async () => store } };
        if (name === '@kit.ArkTS') return { util: { TextEncoder: class { encodeInto(s) { return Buffer.from(s); } } } };
        if (name === '@kit.CryptoArchitectureKit') return { cryptoFramework: { createMd: () => {
          const hash = createHash('sha256'); return { update: async b => hash.update(b.data), digest: async () => ({ data: hash.digest() }) };
        } } };
        if (name === '@kit.BasicServicesKit') return { emitter };
        if (name === './StatsService') return { EVT_USAGE_STATS_UPDATED: 'stats', StatsService: {
          init: async () => { if (control.statsUnavailable) throw new Error('stats failed'); },
          getCachedStatsBundle: () => control.statsUnavailable ? undefined : { summary: { totalSeconds: control.seconds } }
        } };
        if (name.startsWith('.')) return load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), name)));
        throw new Error(`Unexpected dependency ${name}`);
      }
    }, { filename: relative });
    return exports;
  }
  const { MedalService } = load('service/MedalService');
  const service = MedalService.instance;
  return { control, service, MedalService, model: load('model/Medal'), event: historical => emitter.emit('stats', { data: { historical } }) };
}
async function check(name, run) { fs.rmSync(disk, { force: true }); await run(); passed++; console.log(`PASS ${name}`); }
(async () => {
  await check('accounts isolate awards, survive deletion/restart and claim legacy achievements only once', async () => {
    let f = processFixture(100 * 3600);
    await f.service.bindAccount(context, 'account-A');
    assert.equal(f.service.usageLevel(), 4);
    assert.equal(f.service.usageLevelName().id, 'app.string.account_reading_medal_100h_name');
    await f.service.equipMedal('reading_100h');
    f.control.seconds = 0; await f.service.refreshUnlocks();
    assert.equal(f.service.usageLevel(), 4); assert.equal(f.service.totalSeconds, 100 * 3600);
    f = processFixture(0); await f.service.bindAccount(context, 'account-A');
    assert.equal(f.service.usageLevel(), 4); assert.equal(f.service.selectedMedalId, 'reading_100h');
    await f.service.bindAccount(context, 'account-B');
    assert.equal(f.service.usageLevel(), 1); assert.equal(f.service.awards.length, 0);
    f.control.seconds = 10 * 3600; await f.service.refreshUnlocks();
    assert.equal(f.service.usageLevel(), 2);
    await f.service.bindAccount(context, 'account-A');
    assert.equal(f.service.totalSeconds, 100 * 3600, 'B time must not be awarded to A');
    assert.equal(f.service.selectedMedalId, 'reading_100h');
    f.service.clearAccount(); await new Promise(resolve => setImmediate(resolve)); await f.service.flush();
    assert.equal(f.service.accountId, '');
    f.control.seconds += 1000 * 3600; await f.service.refreshUnlocks();
    await f.service.bindAccount(context, 'account-B');
    assert.equal(f.service.totalSeconds, 10 * 3600, 'guest time must not be claimed after migration');
  });
  await check('account backup only restores to same identity and never drops earned level', async () => {
    const f = processFixture(500 * 3600); await f.service.bindAccount(context, 'account-A');
    const saved = await f.service.exportSnapshot(context, 500 * 3600);
    assert.match(saved.ownerKey, /^[a-f0-9]{64}$/);
    assert.equal(JSON.stringify(saved).includes('account-A'), false);
    await f.service.bindAccount(context, 'account-B');
    f.control.seconds += 5000 * 3600;
    await f.service.refreshUnlocks(true, true);
    await f.service.restoreSnapshot(context, saved);
    assert.equal(f.service.awards.length, 0);
    assert.equal(f.service.totalSeconds, 0);
    await f.service.bindAccount(context, 'account-A');
    assert.equal(f.service.usageLevel(), 6);
    await f.service.restoreSnapshot(context, saved);
    assert.equal(f.service.totalSeconds, 500 * 3600);
    f.control.seconds += 500 * 3600; await f.service.refreshUnlocks();
    await f.service.restoreSnapshot(context, saved);
    assert.equal(f.service.usageLevel(), 7);
  });
  await check('usage levels follow listening thresholds, cap at V9 and ignore equipped medals', async () => {
    const f = processFixture(); await f.service.init(context);
    assert.equal(f.service.usageLevel(), 1);
    for (const [index, hours] of [1, 10, 50, 100, 300, 500, 1000, 2000, 5000].entries()) {
      f.control.seconds = hours * 3600 - 1; await f.service.refreshUnlocks();
      assert.equal(f.service.usageLevel(), Math.max(1, index));
      f.control.seconds++; await f.service.refreshUnlocks();
      assert.equal(f.service.usageLevel(), index + 1);
    }
    await f.service.equipMedal('reading_1h');
    assert.equal(f.service.usageLevel(), 9);
    f.control.seconds = 9000 * 3600; await f.service.refreshUnlocks();
    assert.equal(f.service.usageLevel(), 9);
    f.control.seconds = 0; await f.service.refreshUnlocks();
    assert.equal(f.service.usageLevel(), 9);
  });
  await check('first install hides national medal; locked medals cannot be equipped', async () => {
    const { service } = processFixture(); await service.init(context);
    assert.equal(service.awards.length, 0); assert.equal(service.selectedMedalId, '');
    await assert.rejects(service.equipMedal('reading_1h')); await assert.rejects(service.equipMedal('invalid'));
  });
  await check('all 9 boundaries unlock at exact seconds and never replace selected medal', async () => {
    const f = processFixture(); await f.service.init(context);
    for (const h of [1, 10, 50, 100, 300, 500, 1000, 2000, 5000]) {
      f.control.seconds = h * 3600 - 1; await f.service.refreshUnlocks();
      assert.equal(f.service.isUnlocked(`reading_${h}h`), false);
      f.control.seconds++; await f.service.refreshUnlocks();
      assert.equal(f.service.isUnlocked(`reading_${h}h`), true);
      assert.equal(f.service.selectedMedalId, '');
    }
    assert.equal(f.service.awards.length, 9);
  });
  await check('historical hours grant multiple medals without invented dates', async () => {
    const f = processFixture(120 * 3600); await f.service.init(context);
    assert.equal(f.service.awards.length, 4);
    assert.ok(f.service.awards.every(a => a.historical && a.unlockedAt === 0));
    assert.equal(f.service.newAwardCount, 0);
  });
  await check('selection and intentional unequip persist after restart', async () => {
    let f = processFixture(3600); await f.service.init(context); await f.service.equipMedal('reading_1h');
    f = processFixture(3600); await f.service.init(context); assert.equal(f.service.selectedMedalId, 'reading_1h');
    await f.service.equipMedal(''); f = processFixture(3600); await f.service.init(context); assert.equal(f.service.selectedMedalId, '');
  });
  await check('event captures threshold before deletion; permanent awards survive restart', async () => {
    let f = processFixture(); await f.service.init(context);
    f.control.seconds = 3600; f.event(false); f.control.seconds = 0; f.event(false); await f.service.flush();
    assert.ok(f.service.isUnlocked('reading_1h')); assert.equal(f.service.totalSeconds, 3600);
    assert.equal(f.service.awards.find(a => a.medalId === 'reading_1h').historical, false);
    f = processFixture(); await f.service.init(context); assert.ok(f.service.isUnlocked('reading_1h'));
  });
  await check('duplicate refreshes grant once and avoid repeated writes', async () => {
    const f = processFixture(); await f.service.init(context); const before = f.control.writes;
    f.control.seconds = 3600; await Promise.all([f.service.refreshUnlocks(), f.service.refreshUnlocks(), f.service.refreshUnlocks()]);
    assert.equal(f.service.awards.length, 1); assert.equal(f.service.newAwardCount, 1); assert.equal(f.control.writes, before + 1);
  });
  await check('failed equip rolls back and does not poison future operations', async () => {
    const f = processFixture(3600); await f.service.init(context); f.control.failWrite = true;
    await assert.rejects(f.service.equipMedal('reading_1h')); assert.equal(f.service.selectedMedalId, '');
    f.control.failWrite = false; await f.service.refreshUnlocks();
    const next = processFixture(3600); await next.service.init(context); assert.equal(next.service.selectedMedalId, '');
  });
  await check('failed unlock retries even after statistics are deleted', async () => {
    const f = processFixture(); await f.service.init(context); f.control.failWrite = true;
    f.control.seconds = 3600; await assert.rejects(f.service.refreshUnlocks());
    f.control.seconds = 0; f.control.failWrite = false; await f.service.refreshUnlocks();
    assert.ok(f.service.isUnlocked('reading_1h'));
  });
  await check('broken storage and statistics never overwrite existing awards', async () => {
    let f = processFixture(3600); await f.service.init(context); const saved = fs.readFileSync(disk, 'utf8');
    f = processFixture(); f.control.failRead = true; await assert.rejects(f.service.init(context));
    assert.equal(fs.readFileSync(disk, 'utf8'), saved); assert.equal(f.service.ready, false);
    f.control.failRead = false; await f.service.init(context); assert.ok(f.service.isUnlocked('reading_1h'));
    const beforeStatsFailure = fs.readFileSync(disk, 'utf8');
    f = processFixture(); f.control.statsUnavailable = true; await assert.rejects(f.service.init(context)); assert.equal(fs.readFileSync(disk, 'utf8'), beforeStatsFailure);
    fs.writeFileSync(disk, JSON.stringify({ medal_accounts_v2: '{broken' })); f = processFixture(); await assert.rejects(f.service.init(context));
    assert.equal(JSON.parse(fs.readFileSync(disk, 'utf8')).medal_accounts_v2, '{broken');
  });
  await check('backup restore merges permanent awards and restores unequipped state', async () => {
    const f = processFixture(3600); await f.service.init(context); await f.service.equipMedal('');
    const saved = await f.service.exportSnapshot(context, f.control.seconds);
    f.control.seconds = 360000; await f.service.refreshUnlocks(); await f.service.equipMedal('reading_100h');
    await f.service.restoreSnapshot(context, saved); assert.equal(f.service.awards.length, 4); assert.equal(f.service.selectedMedalId, '');
    saved.awards.length = 0; assert.equal(f.service.awards.length, 4);
  });
  await check('legacy backup grants restored hours as historical and keeps current choice', async () => {
    const f = processFixture(); await f.service.init(context); await f.service.equipMedal('');
    f.control.seconds = 36000; f.event(true); await f.service.restoreSnapshot(context, undefined);
    assert.equal(f.service.awards.length, 2); assert.equal(f.service.selectedMedalId, '');
    assert.ok(f.service.awards.every(a => a.historical && a.unlockedAt === 0));
  });
  await check('backup uses sanitized totals without initializing broken original statistics', async () => {
    const f = processFixture(); f.control.statsUnavailable = true;
    const saved = await f.service.exportSnapshot(context, 36000);
    assert.equal(saved.awards.length, 2); assert.equal(f.service.ready, false); assert.equal(fs.existsSync(disk), false);
  });
  await check('malformed, duplicate and locked-selection backups are rejected', async () => {
    const f = processFixture(3600); await f.service.init(context);
    const valid = await f.service.exportSnapshot(context, f.control.seconds);
    const variants = [null, {}, { ...valid, version: 2 }, { ...valid, selectedMedalId: 'reading_10h' },
      { ...valid, awards: [valid.awards[0], valid.awards[0]] },
      { ...valid, awards: [{ medalId: 'national_day', unlockedAt: -1, historical: true }] }];
    for (const v of variants) { assert.equal(f.MedalService.isValidSnapshot(v), false); await assert.rejects(f.service.restoreSnapshot(context, v)); }
    assert.equal(f.service.awards.length, 1);
  });
  await check('old national and 3000h awards stay backup-compatible but hidden after restart and restore', async () => {
    const legacy = { version: 1, selectedMedalId: 'national_day', awards: [
      { medalId: 'national_day', unlockedAt: 0, historical: true },
      { medalId: 'reading_1h', unlockedAt: 123, historical: false },
      { medalId: 'reading_3000h', unlockedAt: 0, historical: true }
    ] };
    fs.writeFileSync(disk, JSON.stringify(legacy));
    const f = processFixture(); await f.service.init(context);
    assert.equal(f.service.awards.length, 1); assert.equal(f.service.selectedMedalId, '');
    assert.equal(f.service.selected(), undefined);
    await assert.rejects(f.service.equipMedal('national_day'));
    await assert.rejects(f.service.equipMedal('reading_3000h'));
    await f.service.equipMedal('reading_1h');
    legacy.selectedMedalId = 'reading_3000h';
    await f.service.restoreSnapshot(context, legacy);
    assert.equal(f.service.selectedMedalId, ''); assert.equal(f.service.awards.length, 1);
    const exported = await f.service.exportSnapshot(context, 0);
    assert.equal(exported.awards.length, 3); assert.ok(f.MedalService.isValidSnapshot(exported));
    assert.equal(f.service.awards[0].unlockedAt, 123);
  });
  await check('real app backup carries medal selection and rejects invalid medal data', async () => {
    const backup = require('./backup-test-harness.cjs');
    try {
      const h = backup.harness();
      h.control.backupStats = [{ bookId: 'book', title: 'book', author: '', cover: '', listenSeconds: 3600, updatedAt: 1, days: [] }];
      const medals = h.load('service/MedalService').MedalService.instance;
      await medals.init(h.context); await medals.equipMedal('reading_1h');
      const app = h.load('service/AppBackupService').AppBackupService;
      const file = path.join(h.context.filesDir, 'medal-backup.json');
      await app.createSnapshot(h.context, file, true);
      const data = await app.readSnapshot(file);
      assert.equal(data.medals.selectedMedalId, 'reading_1h');
      await medals.equipMedal('');
      await app.restoreSnapshot(h.context, file, true);
      assert.equal(medals.selectedMedalId, 'reading_1h');
      data.medals.selectedMedalId = 'reading_3000h'; fs.writeFileSync(file, JSON.stringify(data));
      await assert.rejects(app.readSnapshot(file));
    } finally { for (const directory of backup.fixtures) fs.rmSync(directory, { recursive: true, force: true }); }
  });
  console.log(`PASS ${passed} medal scenarios`);
})().finally(() => fs.rmSync(root, { recursive: true, force: true })).catch(error => { console.error(error); process.exitCode = 1; });
