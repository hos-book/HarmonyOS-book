// Run real source-switch policy with simulated imported sources.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
function load(file, dependencies = {}) {
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,
    '../entry/src/main/ets/', file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { module, exports: module.exports, ObservedV2: value => value, Trace: () => {}, setTimeout, clearTimeout, require: key => {
    assert.ok(dependencies[key], key); return dependencies[key];
  } });
  return module.exports;
}
let sources = [];
let active = 0;
let peak = 0;
let calls = [];
let task;
let cancel = false;
let stalled = '';
let receivedQuery = '';
let resultTitle = '《测试书》';
const { SourceSwitchSearch } = load('service/BookSourceSwitchService.ets', {
  '../model/LocalRuleSource': load('model/LocalRuleSource.ets'),
  '../utils/BookIdentity': load('utils/BookIdentity.ets'),
  '../utils/ChapterTitleFormatter': load('utils/ChapterTitleFormatter.ets'),
  './SourceDataService': { SourceDataService: { getEnabledSources: async () => sources } },
  './BookSourceService': { BookSourceService: { searchBooks: async (source, keyword) => {
    receivedQuery = keyword;
    if (source.bookSourceUrl === stalled) { calls.push(stalled); return new Promise(() => {}); }
    calls.push(source.bookSourceUrl); active++; peak = Math.max(peak, active);
    await new Promise(resolve => setImmediate(resolve));
    active--;
    if (cancel) task.cancelled = true;
    if (source.bookSourceUrl === 'bad') throw new Error('unavailable');
    const item = { name: resultTitle, contentType: source.bookSourceType === 2 ? 'comic' : 'audio', bookUrl: '/book', author: '作者', lastChapter: '第 123 章 更新' };
    return [item, item, { ...item, name: '其他书' }, { ...item, contentType: 'text', bookUrl: '/text' }];
  } } }
});
(async () => {
  const oldBook = { title: '测试书', sourceUrl: 'current', contentType: 'audio' };
  sources = ['current', 'bad', ...Array.from({ length: 12 }, (_, i) => `source-${i}`)]
    .map(bookSourceUrl => ({ bookSourceUrl, bookSourceName: bookSourceUrl, bookSourceType: 1 }));
  task = new SourceSwitchSearch();
  let results = [];
  await task.run(oldBook, books => { results = books; });
  assert.equal(peak, 6);
  assert.equal(task.failed, 1);
  assert.equal(results.length, 12);
  assert.ok(results.every(book => book.latestChapterTitle === '第 123 章 更新'));
  assert.equal(new Set(results.map(book => book.id)).size, 12);
  assert.ok(results.every(book => book.contentType === 'audio'));
  assert.ok(!calls.includes('current'));
  console.log('PASS six concurrent sources, failure isolation, deduplication and audio filtering');
  task = new SourceSwitchSearch();
  sources = sources.map(source => ({ ...source, bookSourceType: 0 }));
  calls = [];
  await task.run({ ...oldBook, contentType: 'text' }, books => { results = books; });
  assert.equal(results.length, 12);
  assert.ok(results.every(book => book.contentType === 'text'));
  assert.equal(task.total, 13);
  console.log('PASS text switching excludes audio editions');
  const originalSources = sources.map(source => ({ ...source, bookSourceType: 1 }));
  sources = [0, 1, 2, 3, 9, undefined].map(bookSourceType => ({
    bookSourceUrl: `kind-${bookSourceType}`, bookSourceName: `kind-${bookSourceType}`, bookSourceType
  }));
  calls = []; task = new SourceSwitchSearch();
  await task.run({ ...oldBook, contentType: 'text' }, books => { results = books; });
  assert.deepEqual(calls.sort(), ['kind-0', 'kind-3']);
  assert.equal(task.total, 2);
  assert.equal(task.completed, 2);
  assert.equal(results.length, 2);
  assert.ok(results.every(book => book.contentType === 'text'));
  calls = []; task = new SourceSwitchSearch();
  await task.run(oldBook, books => { results = books; });
  assert.deepEqual(calls, ['kind-1']);
  assert.equal(task.total, 1);
  assert.equal(results.length, 1);
  assert.equal(results[0].contentType, 'audio');
  calls = []; task = new SourceSwitchSearch();
  await task.run({ ...oldBook, contentType: 'comic' }, books => { results = books; });
  assert.deepEqual(calls, ['kind-2']);
  assert.equal(results.length, 1);
  assert.equal(results[0].contentType, 'comic');
  assert.ok(results[0].id.startsWith('search_comic_'));
  calls = []; task = new SourceSwitchSearch();
  await task.run({ ...oldBook, sourceUrl: 'kind-1' }, books => { results = books; });
  assert.equal(calls.length, 0);
  assert.equal(task.total, 0);
  assert.equal(results.length, 0);
  console.log('PASS only matching source types are requested/counted; comics, unknown and current sources are skipped');
  sources = originalSources;
  task = new SourceSwitchSearch(); calls = []; cancel = true;
  let updates = 0;
  await task.run(oldBook, () => updates++);
  assert.equal(calls.length, 6);
  assert.equal(updates, 1); // initial progress update, no late results
  console.log('PASS dismissing search prevents later batches and stale results');
  cancel = false;
  resultTitle = '测试书（多人有声剧·完整版）';
  task = new SourceSwitchSearch();
  await task.run({ ...oldBook, title: '《测试书》【全集】' }, books => { results = books; });
  assert.equal(receivedQuery, '测试书');
  assert.equal(results.length, 12);
  assert.equal(SourceSwitchSearch.searchKeyword('测试书 | 多人演播'), '测试书');
  assert.equal(SourceSwitchSearch.searchKeyword('测试书（多人演播）'), '测试书');
  console.log('PASS edition suffixes do not hide matching books or pollute search query');
  sources = ['stalled', ...Array.from({ length: 7 }, (_, i) => `fast-${i}`)]
    .map(bookSourceUrl => ({ bookSourceUrl, bookSourceName: bookSourceUrl, bookSourceType: 1 }));
  stalled = 'stalled'; calls = [];
  task = new SourceSwitchSearch(80);
  let advancedBeforeTimeout = false;
  let displayedBeforeSlowSource = false;
  await task.run(oldBook, books => {
    results = books;
    if (calls.includes('fast-6') && task.failed === 0) advancedBeforeTimeout = true;
    if (books.length > 0 && task.completed < task.total && task.failed === 0) displayedBeforeSlowSource = true;
  });
  assert.ok(displayedBeforeSlowSource, 'successful results are published while other sources are still running');
  assert.ok(advancedBeforeTimeout, 'fast workers must advance without waiting for a slow source');
  assert.equal(task.failed, 1);
  assert.equal(task.completed, 8);
  assert.equal(results.length, 7);
  console.log('PASS slow source times out; fast workers continue and keep results');
  sources = [{ bookSourceUrl: 'stalled', bookSourceName: 'stalled', bookSourceType: 1 }];
  task = new SourceSwitchSearch(30000);
  let cancelledRunFinished = false;
  let cancelUpdates = 0;
  const cancelRun = task.run(oldBook, () => cancelUpdates++).then(() => { cancelledRunFinished = true; });
  await new Promise(resolve => setImmediate(resolve));
  task.cancelled = true;
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(cancelledRunFinished, true, 'stop must settle without waiting for the source or 30s timeout');
  await cancelRun;
  assert.equal(cancelUpdates, 1);
  assert.equal(task.completed, 0, 'cancelled sources must not advance progress');
  assert.equal(task.failed, 0, 'cancellation is not a source failure');
  console.log('PASS stop immediately settles stalled search and freezes results/progress');
  sources = []; task = new SourceSwitchSearch();
  await task.run(oldBook, books => { results = books; });
  assert.equal(task.total, 0);
  assert.equal(results.length, 0);
  const target = { title: '测试书', chapters: [{ title: '第一章 开始' }, { title: '第二章 相遇' }] };
  assert.equal(SourceSwitchSearch.matchChapter(oldBook, '第二章相遇', target), 1);
  assert.equal(SourceSwitchSearch.matchChapter(oldBook, '第三章', target), -1);
  target.chapters.push({ title: '第二章相遇' });
  assert.equal(SourceSwitchSearch.matchChapter(oldBook, '第二章 相遇', target), -1);
  assert.equal(SourceSwitchSearch.matchChapter(oldBook, '', target), -1);
  assert.equal(SourceSwitchSearch.locateChapter(oldBook, '不同版本第二集', 1, target), 1);
  assert.equal(SourceSwitchSearch.locateChapter(oldBook, '第三百集', 299, target), 2);
  assert.equal(SourceSwitchSearch.locateChapter(oldBook, '第一章 开始', 2, target), 0);
  assert.equal(SourceSwitchSearch.locateChapter(oldBook, '', -1, target), 0);
  assert.equal(SourceSwitchSearch.locateChapter(oldBook, '', 1, { chapters: [] }), -1);
  console.log('PASS chapter location prefers title, falls back to ordinal and clamps shorter editions');
})().catch(error => { console.error(error); process.exitCode = 1; });
