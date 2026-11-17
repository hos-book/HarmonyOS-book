// Exercise the page's real refresh transaction with controlled source and storage timing.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/BookDetailPage.ets'), 'utf8').replace(/\r\n/g, '\n');
const start = source.indexOf('  private async refreshBook()');
const end = source.indexOf('  private retryLoadBook()', start);
assert.ok(start >= 0 && end > start);
const compiled = ts.transpileModule('class Page {' + source.slice(start, end) + '} exports.Page = Page;', {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText;
const chapter = id => ({ id, title: id, index: 1, duration: 0, source: { type: 'url', value: id } });
const book = (contentType = 'audio', id = 'book') => ({
  id, contentType, title: 'Old title', author: 'Author', cover: 'cover', tags: [],
  chapters: [chapter('old')], tocComplete: true, chapterCount: 1, bookUrl: '/detail',
  sourceUrl: 'source', intro: 'Old introduction', skipIntro: 0, skipOutro: 0
});
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
function harness(initial = book()) {
  const request = deferred(), cache = new Map([[initial.id, initial]]);
  const calls = [], saved = [], notices = [], errors = [];
  const exports = {};
  const stored = book(initial.contentType, initial.id);
  stored.title = 'Local metadata';
  const localChapters = [chapter('local-a'), chapter('local-b')];
  const bridge = {
    load(kind, value) { calls.push([kind, value]); cache.set(value.id, { ...value, chapters: [], tocComplete: false }); return request.promise; }
  };
  const preferences = {
    async applyTocOrder(value) { value.chaptersDescending = true; },
    async applySkipConfig(value) { value.skipIntro = 12; value.skipOutro = 9; }
  };
  vm.runInNewContext(compiled, {
    exports, Error, $r: value => value,
    DETAIL_LOG_DOMAIN: 0, DETAIL_LOG_TAG: 'detail',
    hilog: { warn: (...args) => errors.push(args) },
    BookSourceService: {
      loadAudioBook: value => bridge.load('audio', value),
      loadTextBook: value => bridge.load('text', value)
    },
    SearchCache: { put: value => cache.set(value.id, value) },
    DataService: {
      async getBookById(context, id) { calls.push(['local-book', id]); return stored; },
      async getChaptersForBook(id) { calls.push(['local-toc', id]); return localChapters; },
      async upsertCachedBook(value) { saved.push(value); }
    },
    PreferenceService: preferences,
    BookPresentation: { apply(value) { value.title = 'My title'; value.cover = 'my-cover'; return value; } }
  });
  const page = new exports.Page();
  Object.assign(page, {
    book: initial, bookId: initial.id, detailActive: true, refreshing: false,
    loadingDetail: false, resolvingBook: false, loadingToc: false, deferEntry: false, tocGeneration: 0,
    loadFailed: false, tocFailed: false, debugInfo: '',
    lastHistory: { chapterId: 'old', position: 32 }, textReadingProgress: { resourceIndex: 0, offset: 18 },
    isFavorite: true,
    getUIContext: () => ({ getHostContext: () => ({}) }),
    resolveSourceName: url => calls.push(['source-name', url]), showToast: message => notices.push(message)
  });
  return { page, request, cache, calls, saved, notices, preferences, localChapters, stored };
}
(async () => {
  for (const kind of ['audio', 'text', 'comic']) {
    const h = harness(book(kind)), old = h.page.book;
    const history = h.page.lastHistory, progress = h.page.textReadingProgress;
    const pending = h.page.refreshBook();
    assert.equal(h.calls[0][0], kind === 'audio' ? 'audio' : 'text', 'complete cached TOC still calls source');
    assert.equal(h.page.refreshing, true);
    assert.equal(h.page.book, old, 'keep rendered content while source loads');
    assert.notEqual(h.calls[0][1], old, 'never pass the rendered book to a mutating source');
    await h.page.refreshBook(); assert.equal(h.calls.length, 1, 'duplicate refresh is ignored');
    h.request.resolve({ ...book(kind), intro: 'New introduction', chapterCount: 99, chapters: [chapter('new-a'), chapter('new-b')] });
    await pending;
    assert.equal(h.page.book.intro, 'New introduction');
    assert.equal(h.page.book.chapterCount, 2);
    assert.equal(h.page.book.chapters[1].id, 'new-b');
    assert.equal(h.page.book.chaptersDescending, true);
    assert.equal(h.page.book.title, 'My title');
    assert.equal(h.page.book.cover, 'my-cover');
    if (kind === 'audio') assert.equal(h.page.book.skipIntro, 12);
    assert.equal(h.page.lastHistory, history); assert.equal(h.page.textReadingProgress, progress);
    assert.equal(h.page.isFavorite, true); assert.equal(h.page.refreshing, false);
    assert.equal(h.saved.length, 1); assert.equal(h.cache.get(old.id), h.page.book);
    assert.deepEqual(h.notices, ['app.string.book_detail_refresh_success']);
  }
  for (const failure of ['network', 'empty', 'incomplete']) {
    const h = harness(), original = h.page.book;
    const pending = h.page.refreshBook();
    if (failure === 'network') h.request.reject(new Error('offline'));
    else h.request.resolve({ ...book(), chapters: failure === 'empty' ? [] : [chapter('partial')], tocComplete: failure !== 'incomplete' });
    await pending;
    assert.equal(h.page.book, original);
    assert.equal(h.cache.get(original.id).chapters[0].id, 'old');
    assert.equal(h.saved.length, 0); assert.equal(h.page.refreshing, false);
    assert.equal(h.page.loadFailed, false);
    assert.deepEqual(h.notices, ['app.string.book_detail_refresh_failed']);
  }
  for (const change of ['leave', 'generation', 'source', 'identity']) {
    const h = harness(), pending = h.page.refreshBook();
    if (change === 'leave') h.page.detailActive = false;
    if (change === 'generation') h.page.tocGeneration++;
    if (change === 'source') h.page.book = { ...book(), sourceUrl: 'other' };
    if (change === 'identity') h.page.bookId = 'other';
    const current = h.page.book;
    h.request.resolve({ ...book(), intro: 'late' });
    await pending;
    assert.equal(h.page.book, current); assert.equal(h.saved.length, 0);
    assert.equal(h.notices.length, 0); assert.equal(h.page.refreshing, false);
  }
  const latePreference = harness(), gate = deferred();
  latePreference.preferences.applyTocOrder = () => gate.promise;
  const awaitingPreference = latePreference.page.refreshBook();
  latePreference.request.resolve(book());
  for (let i = 0; i < 8; i++) await Promise.resolve();
  latePreference.page.detailActive = false; gate.resolve();
  await awaitingPreference; assert.equal(latePreference.saved.length, 0);

  const local = harness(book('text', 'import_local'));
  await local.page.refreshBook();
  assert.deepEqual(local.calls.slice(0, 2).map(call => call[0]), ['local-book', 'local-toc']);
  assert.equal(local.page.book.chapters.length, 2);
  assert.equal(local.stored.chapters[0].id, 'old', 'persistent metadata object is not mutated');
  const missing = harness(book('comic', 'import_missing'));
  missing.localChapters.length = 0;
  await missing.page.refreshBook();
  assert.equal(missing.page.book.chapters[0].id, 'old'); assert.equal(missing.saved.length, 0);

  for (const flag of ['refreshing', 'resolvingBook', 'loadingDetail', 'loadingToc', 'deferEntry']) {
    const h = harness(); h.page[flag] = true; await h.page.refreshBook(); assert.equal(h.calls.length, 0, flag);
  }
  console.log('PASS detail refresh: audio/text/comic force reload, atomic content replacement, duplicate/loading guards, failure fallback, stale response isolation, local TOC, presentation/preferences/progress retention');
})().catch(error => { console.error(error); process.exitCode = 1; });
