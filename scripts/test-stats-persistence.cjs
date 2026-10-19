// Runs the real ArkTS service with temporary disk files and simulated HarmonyOS APIs.
// Usage: node scripts/test-stats-persistence.cjs [StatsService.ets]
// Requires DEVECO_HOME (or DEVECO_PATH) to point to the installed IDE.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');

const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed DevEco Studio directory');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = process.argv[2] || path.join(__dirname, '../entry/src/main/ets/service/StatsService.ets');
const code = ts.transpileModule(fs.readFileSync(source, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hsda-stats-test-'));
const primaryPath = path.join(root, 'preferences.json');
const snapshotPath = path.join(root, 'listening_stats_v3.json');
const context = { filesDir: root };
const book = { bookId: 'audio-fixture', title: 'Statistics fixture' };
let now = new Date(2026, 8, 13, 23, 59, 50).getTime();
let failPrimaryRead = false;
let failPrimaryWrite = false;
let failSnapshotWrite = false;
let failInitialization = false;
let passed = 0;

class TestDate extends Date {
  constructor(...args) { super(...(args.length ? args : [now])); }
  static now() { return now; }
}

function newProcess() {
  const handles = new Map();
  let nextFd = 0;
  const fileIo = {
    OpenMode: { CREATE: 1, TRUNC: 2, READ_WRITE: 4 },
    access: async name => fs.existsSync(name),
    readText: async name => fs.promises.readFile(name, 'utf8'),
    open: async name => {
      if (failSnapshotWrite) throw new Error('Snapshot storage unavailable');
      const fd = ++nextFd;
      handles.set(fd, await fs.promises.open(name, 'w'));
      return { fd };
    },
    write: async (fd, data) => handles.get(fd).write(data),
    fsync: async fd => handles.get(fd).sync(),
    close: async file => { const fd = typeof file === 'number' ? file : file.fd; await handles.get(fd).close(); handles.delete(fd); },
    rename: async (from, to) => fs.promises.rename(from, to)
  };
  const preferences = {
    getPreferences: async () => {
      if (failInitialization) throw new Error('Initialization unavailable');
      let memory = fs.existsSync(primaryPath) ? JSON.parse(fs.readFileSync(primaryPath, 'utf8')) : {};
      return {
        get: async (key, fallback) => {
          if (failPrimaryRead) throw new Error('Primary read unavailable');
          return memory[key] ?? fallback;
        },
        put: async (key, value) => {
          if (failPrimaryWrite) throw new Error('Primary write unavailable');
          memory[key] = value;
        },
        flush: async () => fs.promises.writeFile(primaryPath, JSON.stringify(memory))
      };
    }
  };
  const modules = {
    '../model/GeneralSettings': { GeneralSettings: { current: { historyEnabled: true } } },
    '@kit.ArkData': { preferences },
    '@kit.CoreFileKit': { fileIo },
    '@kit.BasicServicesKit': { emitter: { emit() {} } }
  };
  const module = { exports: {} };
  vm.runInNewContext(code, {
    module, exports: module.exports, Date: TestDate, Error, Promise, Set, Map,
    console: process.env.STATS_TEST_VERBOSE ? console : { warn() {}, error() {} },
    require: name => {
      if (!modules[name]) throw new Error(`Unexpected dependency: ${name}`);
      return modules[name];
    }
  }, { filename: source });
  return module.exports.StatsService;
}

async function check(name, test) {
  await test();
  passed++;
  console.log(`PASS ${name}`);
}

// Execute page lifecycle/loading methods; ArkUI rendering remains covered by ArkTS build/device checks.
function statsPage(service, preference) {
  const file = path.join(__dirname, '../entry/src/main/ets/pages/ReadingStatsPage.ets');
  const pageSource = fs.readFileSync(file, 'utf8').split('  build() {')[0]
    .replace('export struct ReadingStatsPage', 'export class ReadingStatsPage')
    .replace(/@(ObservedV2|ComponentV2|Trace|Local|Param|Event)\s*/g, '') + '\n}';
  const pageCode = ts.transpileModule(pageSource, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(pageCode, {
    module, exports: module.exports, Date: TestDate, Scroller: class {}, NavPathStack: class {},
    console: { error() {} }, setTimeout: () => 1, clearTimeout() {},
    require: name => name === '../service/StatsService' ? { StatsService: service } :
      name === '../service/DiagnosticLogService' ? { DiagnosticLogService: { info() {} } } :
      name === '../service/PreferenceService' ? { PreferenceService: preference } : {}
  }, { filename: file });
  const page = new module.exports.ReadingStatsPage();
  page.getUIContext = () => ({ getHostContext: () => context });
  return page;
}

(async () => {
  let service = newProcess();
  await service.init(context);
  await check('concurrent increments are all retained', async () => {
    await Promise.all(Array.from({ length: 12 }, () => service.addListenSeconds(10, book)));
    assert.equal((await service.getSummary()).totalSeconds, 120);
  });
  await check('midnight starts a new day without resetting lifetime totals', async () => {
    const beforeMidnight = service.addListenSeconds(10, book);
    now = new Date(2026, 8, 14, 0, 0, 5).getTime();
    const afterMidnight = service.addListenSeconds(20, book);
    await Promise.all([beforeMidnight, afterMidnight]);
    const summary = await service.getSummary();
    assert.equal(summary.totalSeconds, 150);
    assert.equal(summary.todaySeconds, 20);
    assert.equal((await service.getBookStats())[0].days.find(day => day.day === '2026-09-13').listenSeconds, 130);
  });
  await check('a new process restores persisted records and summary', async () => {
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getStatsBundle(2)).summary.totalSeconds, 150);
    const copy = await service.getBookStats();
    copy[0].listenSeconds = 0;
    copy[0].days[0].listenSeconds = 0;
    assert.equal((await service.getSummary()).totalSeconds, 150);
  });
  await check('corrupt primary records recover from the independent snapshot', async () => {
    const primary = JSON.parse(fs.readFileSync(primaryPath, 'utf8'));
    primary.book_usage_records_v2 = '{broken';
    fs.writeFileSync(primaryPath, JSON.stringify(primary));
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getSummary()).totalSeconds, 150);
    await service.addListenSeconds(10, book);
    assert.equal((await service.getSummary()).totalSeconds, 160);
  });
  await check('failed primary reads and writes retain the newest disk snapshot', async () => {
    failPrimaryRead = true;
    failPrimaryWrite = true;
    service = newProcess();
    await service.init(context);
    await service.addListenSeconds(10, book);
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getSummary()).totalSeconds, 170);
    failPrimaryRead = false;
    failPrimaryWrite = false;
    await service.flush();
  });
  await check('failed writes retry cached increments without blocking later work', async () => {
    failSnapshotWrite = true;
    failPrimaryWrite = true;
    await assert.rejects(service.addListenSeconds(10, book));
    assert.equal((await service.getSummary()).totalSeconds, 180);
    failSnapshotWrite = false;
    failPrimaryWrite = false;
    await service.flush();
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getSummary()).totalSeconds, 180);
  });
  await check('lifetime totals outlive daily-detail retention', async () => {
    now = new Date(2029, 8, 14, 0, 0, 0).getTime();
    assert.equal((await service.getSummary()).totalSeconds, 180);
    assert.equal((await service.getSummary()).todaySeconds, 0);
    await service.addListenSeconds(10, book);
    assert.equal((await service.getSummary()).totalSeconds, 190);
  });
  await check('删书和清记录只隐藏明细，累计与每日时长重启后仍保留', async () => {
    const before = await service.getSummary();
    await service.removeBookStats([book.bookId]);
    service = newProcess();
    await service.init(context);
    assert.deepEqual({ ...await service.getSummary() }, { ...before });
    assert.equal((await service.getStatsBundle(7)).records.length, 0);
    await service.addListenSeconds(10, book);
    assert.equal((await service.getStatsBundle(7)).records.length, 1);
    await service.clearBookStats();
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getSummary()).totalSeconds, before.totalSeconds + 10);
    assert.equal((await service.getStatsBundle(7)).records.length, 0);
    await service.restoreBackupStats([]);
    assert.equal((await service.getSummary()).totalSeconds, before.totalSeconds + 10);
    await service.restoreBackupStats([{ bookId: book.bookId, title: book.title, listenSeconds: 1,
      updatedAt: now, days: [] }]);
    assert.equal((await service.getSummary()).totalSeconds, before.totalSeconds + 10);
  });
  await check('仅专门清除时长操作清零，重启不恢复旧快照', async () => {
    await service.resetListeningTime();
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getBookStats()).length, 0);
    assert.equal((await service.getSummary()).totalSeconds, 0);
  });
  await check('initialization retries after an error', async () => {
    service = newProcess();
    failInitialization = true;
    await assert.rejects(service.init(context));
    failInitialization = false;
    await service.init(context);
    await service.addListenSeconds(10, book);
    assert.equal((await service.getSummary()).totalSeconds, 10);
  });
  await check('legacy records migrate without changing existing cumulative hours', async () => {
    now = new Date(2026, 8, 14, 0, 0, 5).getTime();
    const legacy = [{ bookId: book.bookId, title: book.title, listenSeconds: 28800,
      updatedAt: new Date(2026, 8, 13).getTime(), days: [{ day: '2026-09-13', listenSeconds: 28800 }] }];
    fs.unlinkSync(snapshotPath);
    fs.writeFileSync(primaryPath, JSON.stringify({ book_usage_records_v2: JSON.stringify(legacy) }));
    service = newProcess();
    await service.init(context);
    assert.equal(service.getCachedStatsBundle(1).summary.totalSeconds, 28800);
    assert.equal(JSON.parse(fs.readFileSync(snapshotPath, 'utf8')).records[0].listenSeconds, 28800);
  });
  await check('unreadable primary and snapshot are never replaced with zeroes', async () => {
    const primary = fs.readFileSync(primaryPath, 'utf8');
    const snapshot = fs.readFileSync(snapshotPath, 'utf8');
    fs.writeFileSync(primaryPath, JSON.stringify({ book_usage_records_v2: 'invalid' }));
    fs.writeFileSync(snapshotPath, 'invalid');
    service = newProcess();
    await assert.rejects(service.init(context));
    await assert.rejects(service.addListenSeconds(10, book));
    assert.equal(fs.readFileSync(snapshotPath, 'utf8'), 'invalid');
    assert.equal(JSON.parse(fs.readFileSync(primaryPath, 'utf8')).book_usage_records_v2, 'invalid');
    fs.writeFileSync(primaryPath, primary);
    fs.writeFileSync(snapshotPath, snapshot);
    await service.init(context);
    assert.equal((await service.getSummary()).totalSeconds, 28800);
  });
  await check('本月按自然月计算，旧累计不随再次播放被转入或移出本月', async () => {
    await service.resetListeningTime();
    now = new Date(2026, 8, 2, 12).getTime();
    await service.restoreBackupStats([
      { bookId: 'legacy', title: 'Legacy', listenSeconds: 28800, updatedAt: now, days: [] },
      { bookId: 'dated', title: 'Dated', listenSeconds: 6300, updatedAt: now, days: [
        { day: '2026-08-31', listenSeconds: 3600 },
        { day: '2026-09-01', listenSeconds: 1800 },
        { day: '2026-09-30', listenSeconds: 900 }
      ] }
    ]);
    const before = await service.getStatsBundle(2);
    assert.equal(before.summary.monthSeconds, 1800);
    assert.equal(before.summary.totalSeconds, 35100);
    await service.addListenSeconds(5, { bookId: 'legacy', title: 'Legacy' }, now);
    assert.equal((await service.getSummary()).monthSeconds, 1805);
    assert.equal(service.getCachedStatsBundle(2).summary.totalSeconds, 35105);
    service = newProcess();
    await service.init(context);
    assert.equal((await service.getStatsBundle(2)).summary.monthSeconds, 1805);
  });
  await check('跨月播放按真实区间分摊，零点整结算归属前一天', async () => {
    await service.resetListeningTime();
    now = new Date(2026, 9, 1, 0, 0, 5).getTime();
    const pending = service.addListenSeconds(15, book, now);
    now += 60000; // 排队等待不改变归属日期。
    await pending;
    let summary = await service.getSummary();
    assert.equal(summary.totalSeconds, 15);
    assert.equal(summary.monthSeconds, 5);
    assert.equal(summary.todaySeconds, 5);
    await service.addListenSeconds(2, book, new Date(2026, 9, 1).getTime());
    assert.equal((await service.getSummary()).monthSeconds, 5);
    assert.equal((await service.getBookStats())[0].days.find(day => day.day === '2026-09-30').listenSeconds, 12);
    now = new Date(2026, 10, 1).getTime();
    summary = (await service.getStatsBundle(1)).summary;
    assert.equal(summary.monthSeconds, 0);
    assert.equal(summary.totalSeconds, 17);
  });
  await check('顶部不等待慢速明细，明细失败与反复刷新不回退统计', async () => {
    let enterDetails, releaseDetails;
    const entered = new Promise(resolve => { enterDetails = resolve; });
    const blocked = new Promise(resolve => { releaseDetails = resolve; });
    const page = statsPage(service, {
      ensureReady: async () => {},
      getHistory: async () => { enterDetails(); await blocked; throw new Error('Offline book details'); }
    });
    const loading = page.loadStats();
    await entered;
    assert.equal(page.totalListenSeconds(), 17);
    assert.equal(page.monthListenSeconds(), 0);
    await service.addListenSeconds(10, book);
    page.statsHandler({});
    assert.equal(page.totalListenSeconds(), 27);
    assert.equal(page.monthListenSeconds(), 10);
    releaseDetails(); await loading;
    for (let i = 0; i < 20; i++) await Promise.resolve();
    await page.loadStats();
    assert.equal(page.totalListenSeconds(), 27);
    assert.equal(page.statsReady, true);
    assert.equal(page.statsError, false);
  });
  await check('backup skips one corrupt statistics record without initializing or rewriting the original stores', async () => {
    const primary = JSON.stringify({ book_usage_revision_v3: 1, book_usage_records_v2: JSON.stringify([
      { bookId: 'valid', title: 'Valid', listenSeconds: 80, updatedAt: now, days: [] }, null, { title: 'No id' }
    ]) });
    const durable = JSON.stringify({ version: 1, revision: 2, records: [null,
      { bookId: 'newer', title: 'Newer', listenSeconds: 90, updatedAt: now, days: [] }, { bookId: 123 }
    ] });
    fs.writeFileSync(primaryPath, primary);
    fs.writeFileSync(snapshotPath, durable);
    const exporting = newProcess();
    const records = await exporting.exportBackupStats(context);
    assert.equal(records.length, 1);
    assert.equal(records[0].bookId, 'newer');
    assert.equal(records[0].listenSeconds, 90);
    assert.equal(fs.readFileSync(primaryPath, 'utf8'), primary);
    assert.equal(fs.readFileSync(snapshotPath, 'utf8'), durable);
    assert.equal(exporting.getCachedStatsBundle(1), undefined);
    fs.unlinkSync(snapshotPath);
    assert.equal((await newProcess().exportBackupStats(context))[0].bookId, 'valid');
    fs.writeFileSync(primaryPath, JSON.stringify({ book_usage_records_v2: 'invalid' }));
    await assert.rejects(newProcess().exportBackupStats(context), /could not be read/);
  });
  console.log(`${passed} statistics persistence checks passed (real temporary files, simulated platform APIs).`);
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
}).finally(() => {
  const resolvedRoot = path.resolve(root);
  if (path.dirname(resolvedRoot) !== path.resolve(os.tmpdir()) ||
      !path.basename(resolvedRoot).startsWith('hsda-stats-test-')) throw new Error('Invalid test cleanup path');
  fs.rmSync(resolvedRoot, { recursive: true, force: true });
});
