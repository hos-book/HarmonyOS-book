// Exercise real ArkTS scheduling and refresh code with simulated storage/network.
// DEVECO_HOME must point to the Release IDE.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const ets = path.join(__dirname, '../entry/src/main/ets');
const disk = new Map();
let storageFails = false;
let storageOpens = 0;
const store = {
  get: async (key, fallback) => disk.get(key) ?? fallback,
  put: async (key, value) => disk.set(key, value),
  flush: async () => {}
};
function compile(source, globals = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, console: { warn() {} }, ...globals });
  return exports;
}
function restart() {
  return compile(fs.readFileSync(path.join(ets, 'service/ShelfUpdateService.ets'), 'utf8'), {
    require: name => {
      assert.equal(name, '@kit.ArkData');
      return { preferences: { getPreferences: async () => {
        storageOpens++;
        if (storageFails) throw Error('disk unavailable');
        return store;
      } } };
    }
  });
}
(async () => {
  let { ShelfUpdateService: service, ShelfUpdateReport, BookUpdateInfo } = restart();
  const day1 = new Date(2026, 9, 1, 8).getTime();
  const day2 = new Date(2026, 9, 2, 8).getTime();
  let calls = 0;
  const task = async () => {
    calls++;
    const report = new ShelfUpdateReport();
    report.checkedAt = day1;
    report.checkedCount = 1;
    const entry = new BookUpdateInfo();
    entry.bookId = 'book'; entry.title = '测试'; entry.oldCount = 10; entry.newCount = 11;
    report.entries = [entry];
    return report;
  };
  await service.run({}, true, task, day1);
  const opensAfterCheck = storageOpens;
  await service.run({}, true, task, day1 + 3600000);
  assert.equal(calls, 1, 'only one automatic attempt per local calendar day');
  assert.equal(storageOpens, opensAfterCheck, 'warm daily gate needs no storage access');
  assert.equal(service.shouldAutoCheck(day1), false);
  assert.equal(service.shouldAutoCheck(day2), true, 'memory gate expires at the next local date');
  service = restart().ShelfUpdateService;
  await service.run({}, true, task, day1);
  assert.equal(calls, 1, 'process restart preserves the daily gate');
  assert.equal((await service.lastReport({})).entries[0].newCount, 11, 'update list survives restart');
  await service.run({}, false, task, day1);
  assert.equal(calls, 2, 'manual refresh bypasses the daily gate');
  await service.run({}, true, task, day2);
  assert.equal(calls, 3, 'next local calendar day is eligible');
  let release;
  const running = service.run({}, false, () => new Promise(resolve => { release = resolve; }), day2);
  while (!release) await new Promise(resolve => setImmediate(resolve));
  assert.equal(await service.run({}, false, task, day2), undefined, 'manual and silent share one lock');
  release(await task()); await running;
  await assert.rejects(service.run({}, false, async () => { throw Error('offline'); }, day2));
  const before = calls;
  await service.run({}, true, task, day2);
  assert.equal(calls, before, 'failed attempt is not silently retried all day');
  await service.run({}, false, task, day2);
  assert.equal(calls, before + 1, 'failure releases the lock for manual retries');
  storageFails = true;
  assert.equal(await service.run({}, true, task, day2), undefined);
  assert.ok(await service.run({}, false, task, day2), 'manual refresh still works without persistence');
  storageFails = false;
  disk.set('report_v1', '{bad');
  assert.equal((await service.lastReport({})).entries.length, 0);

  // Transpile the production refresh method; no duplicated refresh algorithm.
  const page = fs.readFileSync(path.join(ets, 'pages/FavoritePage.ets'), 'utf8');
  const helpers = page.slice(page.indexOf('function cloneChapter'), page.indexOf('@ComponentV2'));
  const refresh = page.slice(page.indexOf('  private async checkOnlineBooks'), page.indexOf('  private getProgressText'));
  let active = 0, peak = 0;
  const saved = [];
  const { Harness } = compile(`${helpers}\nexport class Harness {\n${refresh}\n}`, {
    BookUpdateInfo, ShelfUpdateReport,
    SourceDataService: { getSourceByUrl: async url => url === 'source' ? { bookSourceUrl: 'source' } : undefined },
    BookSourceService: {
      getBookInfo: async (_source, url) => {
        active++; peak = Math.max(peak, active);
        await new Promise(resolve => setImmediate(resolve));
        active--;
        if (url === 'fail') throw Error('source failure');
        return { lastChapter: '第二章', coverUrl: 'https://fixture/new-cover.jpg' };
      },
      getBookToc: async () => [{ name: '第一章', url: '/1' }, { name: '第二章', url: '/2' }]
    },
    DataService: { upsertCachedBook: async book => saved.push(book) },
    SearchCache: { put() {} }, BookCoverPolicy: { setDetail(book, url) { book.cover = url; } }
  });
  const harness = new Harness();
  harness.alive = true;
  harness.isRefreshing = false;
  harness.getChapterCount = book => book.chapters.length;
  harness.syncFavoriteBook = () => {};
  const books = Array.from({ length: 8 }, (_, i) => ({ id: `b${i}`, title: `book${i}`, cover: '',
    bookUrl: i === 3 ? 'fail' : `url${i}`, sourceUrl: 'source', contentType: i % 2 ? 'text' : 'audio',
    chapterCount: 1, chapters: [{ id: `b${i}-c0`, title: '第一章', source: { type: 'url', value: '/1' } }] }));
  const report = await harness.checkOnlineBooks(books);
  assert.equal(peak, 3, 'book refresh concurrency is bounded');
  assert.equal(report.failedCount, 1);
  assert.equal(report.entries.length, 7, 'one failed source does not block other books');
  assert.equal(saved.length, 7);
  assert.equal(books[0].chapters.length, 1, 'source snapshots are not mutated');
  assert.equal(report.entries[0].oldCount, 1);
  assert.equal(report.entries[0].newCount, 2);
  assert.equal(report.entries[0].latestChapter, '第二章');
  const unchanged = { ...saved.find(book => book.id === 'b0'), cover: 'https://fixture/existing-cover.jpg' };
  saved.length = 0;
  const noChange = await harness.checkOnlineBooks([unchanged]);
  assert.equal(noChange.updatedCount, 0, 'a different returned cover alone is not a shelf update');
  assert.equal(saved.length, 0, 'existing covers do not trigger unnecessary persistence or UI reload');
  console.log('PASS shelf daily gate, restart, manual retry, persistence, concurrency and failure isolation');
})().catch(error => { console.error(error); process.exitCode = 1; });
