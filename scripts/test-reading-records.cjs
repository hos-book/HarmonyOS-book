// Exercise the real record-page data/filter/navigation methods with reading and audio fixtures.
const vm = require('node:vm');
const { assert, fs, path, fixtures, harness } = require('./backup-test-harness.cjs');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));

(async () => {
  const h = harness();
  const model = h.load('model/TextReading');
  const progress = h.load('service/text/TextReadingProgressService').TextReadingProgressService;
  const policy = h.load('service/ListeningHistoryPolicy');
  const books = new Map([
    ['novel', { id: 'novel', contentType: 'text', title: 'Read book', author: 'Author', sourceUrl: 'source',
      bookUrl: 'novel', chapterCount: 500, chapters: [] }],
    ['unfavorited', { id: 'unfavorited', contentType: 'text', title: 'Unfavorited', author: 'Author',
      sourceUrl: 'source', bookUrl: 'unfavorited', chapterCount: 100, chapters: [] }],
    ['audio', { id: 'audio', contentType: 'audio', title: 'Audio book', sourceUrl: 'source',
      bookUrl: 'audio', chapterCount: 10, chapters: [] }]
  ]);
  const routes = [], removedStats = [], removedHistory = [], removedAudio = [];
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/ReadingStatsPage.ets'), 'utf8');
  const viewClasses = source.slice(source.indexOf('@ObservedV2'), source.indexOf('const MINI_TITLE_BAR_HEIGHT'));
  const methods = source.slice(source.indexOf('  private shouldShowRecord('), source.indexOf('  private totalListenSeconds(')) +
    source.slice(source.indexOf('  private async deleteSelected('), source.indexOf('  build()'));
  const exported = {};
  vm.runInNewContext(ts.transpileModule(viewClasses + `\nexport class RecordPage {${methods}}`, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS, experimentalDecorators: true }
  }).outputText, {
    exports: exported, ObservedV2: value => value, Trace: () => {}, LocalBuilder: () => {}, ...policy, ...model,
    TextReadingProgressService: progress,
    StatsService: { removeBookStats: async ids => removedStats.push(...ids) },
    PreferenceService: { getProgress: async () => null, removeHistory: async id => removedHistory.push(id),
      removeProgress: async id => removedAudio.push(id) },
    DataService: { getBooks: async () => [...books.values()], getBookById: async (_ctx, id) => books.get(id) },
    SearchCache: { get: () => undefined },
    DiagnosticLogService: { info() {} },
    Curve: { FastOutSlowIn: 0 }
  });
  const page = new exported.RecordPage();
  Object.assign(page, { onlyUnfavorited: false, selectMode: false,
    navStack: { pushPathByName: (...args) => routes.push(args) },
    getUIContext: () => ({ getHostContext: () => h.context, animateTo: (_options, action) => action() }),
    clearSelection() { this.selectedIds = new Set(); }, loadStats: async () => {} });
  const position = model.TextReadingPosition.atChar('novel', 419, '', 1234, 0, 'Chapter 420');
  position.updatedAt = 300;
  const unfavorited = model.TextReadingPosition.atChar('unfavorited', 30, '', 88, 0, 'Chapter 31');
  unfavorited.updatedAt = 100;
  await progress.save(h.context, position);
  await progress.save(h.context, unfavorited);
  const audio = { bookId: 'audio', chapterId: 'audio-c2', progressMs: 500, durationMs: 1000, updatedAt: 200 };
  const records = await page.buildRecordViews(h.context,
    [{ bookId: 'novel', title: 'Read book', listenSeconds: 60, updatedAt: 150 }], [audio], await progress.getAll(h.context));
  assert.deepEqual(Array.from(records, record => record.bookId), ['novel', 'audio', 'unfavorited']);
  assert.equal(records[0].isText, true);
  assert.equal(records[0].chapterTitle, 'Chapter 420');
  assert.equal(records[0].progressPercent, 84);
  assert.equal(records[0].listenSeconds, 60, 'reading does not fabricate listening time');
  assert.equal(records[1].isText, false);
  const favorites = new Set(['novel', 'audio']);
  assert.deepEqual(Array.from(records.filter(item => page.shouldShowRecord(item, favorites)), item => item.bookId), ['novel', 'audio']);
  page.onlyUnfavorited = true;
  assert.deepEqual(Array.from(records.filter(item => page.shouldShowRecord(item, favorites)), item => item.bookId), ['unfavorited']);
  await page.resumeRecord(records[0]);
  assert.equal(routes[0][0], 'reader');
  assert.equal(routes[0][1].bookId, 'novel');
  assert.equal(routes[0][1].resourceIndex, -1, 'reader restores the stored character anchor');
  await page.resumeRecord(records[1]);
  assert.equal(routes[1][0], 'player');
  assert.equal(routes[1][1].progressMs, 500);
  page.records = records;
  page.selectedIds = new Set(['novel']);
  await page.deleteSelected(['novel']);
  assert.equal(await progress.get(h.context, 'novel'), null);
  assert.equal((await progress.get(h.context, 'unfavorited')).charOffset, 88);
  assert.deepEqual(removedStats, ['novel']);
  assert.deepEqual(removedHistory, ['novel']);
  assert.deepEqual(removedAudio, ['novel']);
  const missing = await page.buildRecordViews(h.context, [], [
    { bookId: 'deleted-source-book', chapterId: 'chapter-1', chapterTitle: 'Retained chapter',
      progressMs: 250, durationMs: 1000, updatedAt: 100, sourceUrl: 'deleted-source', bookUrl: 'old-book' }
  ], []);
  assert.equal(missing.length, 1);
  assert.equal(missing[0].chapterTitle, 'Retained chapter');
  assert.equal(missing[0].progressPercent, 25);
  assert.equal(page.shouldShowRecord(missing[0], new Set()), true);
  console.log('PASS: missing book/source cache retains unfavorited history and progress without throwing');
  books.set('search_comic_fixture', { id: 'search_comic_fixture', contentType: 'comic', title: 'Comic',
    sourceUrl: 'comic-source', bookUrl: 'comic', chapterCount: 12, chapters: [] });
  const comicPosition = model.TextReadingPosition.of('search_comic_fixture', 3, 'comic:rtl', 7, 'Episode 4');
  await progress.save(h.context, comicPosition);
  const comicRecords = await page.buildRecordViews(h.context, [], [], [comicPosition]);
  assert.equal(comicRecords[0].isComic, true);
  assert.equal(comicRecords[0].isText, true, 'comic uses reading progress, never audio progress');
  await page.resumeRecord(comicRecords[0]);
  assert.equal(routes.at(-1)[0], 'comicReader');
  assert.equal((await progress.get(h.context, comicPosition.bookId)).pageOffset, 7);
  page.records = [...records, ...comicRecords];
  page.recordDataSource = { setRecords: values => { page.visible = values; } };
  page.contentFilter = 3;
  page.applyContentFilter();
  assert.deepEqual(Array.from(page.visible, item => item.bookId), ['search_comic_fixture']);
  page.contentFilter = 2;
  page.applyContentFilter();
  assert.equal(page.visible.some(item => item.isComic), false);
  console.log('PASS: comic page progress, separate comic/text groups and comic reader resume route');
  console.log('PASS: mixed reading/audio history, ordering, favorite filters, reading/player routes, progress and deletion');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  for (const dir of fixtures) fs.rmSync(dir, { recursive: true, force: true });
});
