// Exercise real group/recent derivation and the collection gesture/navigation boundary.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const read = file => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8');
function compile(source, context = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source.replace(/^import .*;\r?\n/gm, ''), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, ...context });
  return exports;
}
function method(source, name) {
  let start = source.indexOf(`  private ${name}(`);
  if (start < 0) start = source.indexOf(`  private async ${name}(`);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const { BookPresentation } = compile(read('model/BookPresentation.ets'));
const { ShelfCollectionData: data } = compile(read('model/ShelfCollection.ets'), { BookPresentation });
const audio = { id: 'audio', title: '音频一', author: '', narrator: '', chapterCount: 10,
  chapters: [{ id: 'chapter-a', title: '第一集' }], contentType: 'audio' };
const text = { id: 'text', title: '文本一', author: '', narrator: '', chapterCount: 20,
  chapters: [], contentType: 'text' };
const comic = { id: 'comic', title: '漫画一', author: '', narrator: '', chapterCount: 12,
  chapters: [], contentType: 'comic' };
const noHistory = { ...audio, id: 'unread', title: '未开始' };
BookPresentation.edits = [{ bookId: 'audio', group: '听书' }, { bookId: 'text', group: '阅读' }];
const books = [audio, text, comic, noHistory];
const groups = ['阅读', '听书', '空分组'];
const folders = data.groups(books, groups, new Set(), '');
assert.equal(folders.map(item => item.id).join('|'), [...groups, BookPresentation.UNGROUPED].join('|'));
assert.equal(folders.find(item => item.id === '空分组').books.length, 0, 'empty groups remain visible');
assert.equal(folders.at(-1).books.map(book => book.id).join('|'), 'comic|unread');
assert.equal(data.groups(books, groups, new Set(['audio']), '').find(item => item.id === '听书').books.length, 0);
assert.equal(data.groups(books, groups, new Set(), '文本').map(item => item.id).join('|'), '阅读');
assert.equal(data.groups(books, groups, new Set(), '空分组').length, 1);
assert.equal(data.groups(books, groups, new Set(), '不存在').length, 0);
const records = [{ bookId: 'audio', chapterId: 'chapter-a', updatedAt: 100, progressMs: 100, durationMs: 200 },
  { bookId: 'audio', chapterId: 'chapter-a', updatedAt: 300, progressMs: 150, durationMs: 200 }];
const positions = [{ bookId: 'text', resourceIndex: 2, chapterTitle: '第三章', updatedAt: 250 },
  { bookId: 'comic', resourceIndex: 1, chapterTitle: '第二话', updatedAt: 400 }];
const recent = data.recent([...books, audio], records, positions);
assert.equal(recent.map(item => item.book.id).join('|'), 'comic|audio|text', 'mixed media use actual latest timestamps');
assert.equal(recent[1].progress, 75);
assert.equal(recent[2].progress, 15);
assert.equal(data.recent(books, [], []).length, 0, 'unread books do not masquerade as recent history');
const olderAudio = { ...audio, id: 'audio-old' };
const olderText = { ...text, id: 'text-old' };
const perType = data.recent([...books, olderAudio, olderText],
  [...records, { bookId: 'audio-old', updatedAt: 50, progressMs: 20 }],
  [...positions, { bookId: 'text-old', resourceIndex: 1, chapterTitle: '旧章节', updatedAt: 80 }]);
assert.equal(perType.map(item => item.book.id).join('|'), 'comic|audio|text', 'only the latest book per media type');
assert.equal(data.recent([audio, olderAudio], [...records, { bookId: 'audio-old', updatedAt: 50 }], []).length, 1,
  'missing media types do not create placeholder cards');
assert.equal(data.sameRecent(recent, perType), true, 'identical visible content does not rebuild the cards');
perType[0].chapterTitle = '新的漫画章节';
assert.equal(data.sameRecent(recent, perType), false, 'chapter changes update even when the book is unchanged');
assert.equal(groups.join('|'), '阅读|听书|空分组', 'derivation never mutates persisted group order');
const source = read('pages/FavoritePage.ets');
const { Page } = compile(`export class Page { ${method(source, 'handleShelfTypeSwipe')} }`,
  { GeneralSettings: { current: { swipeSwitchTabs: false } } });
const page = Object.assign(new Page(), { viewMode: 3, visible: true, loading: false, isManaging: false,
  removingBook: false, shelfFilter: 2, selectShelfFilter: () => assert.fail('hidden type filter changed') });
page.handleShelfTypeSwipe({ offsetX: -100, offsetY: 0 });
// A recent audio book can have history without being in the favorites index map.
const resumed = [];
const { RecentPage } = compile(`export class RecentPage { ${method(source, 'handleBookTap')} }`, {
  SearchCache: { put: () => {} }, PlaybackStore: { getInstance: () => ({ isCurrentBook: () => false }) },
  DataService: { resolveChapterIndex: (book, id, title) => book.chapters.findIndex(chapter =>
    chapter.id === id || chapter.title === title) }
});
const recentPage = Object.assign(new RecentPage(), {
  removingBook: false, isManaging: false, isMissingCachedBook: () => false,
  historyMap: { audio: { chapterId: 'old-id', chapterTitle: '第二集', progressMs: 37000 } }, chapterIdxMap: {},
  navStack: { pushPathByName: () => assert.fail('recent audio should resume rather than open details') },
  openShelfPlayer: (...args) => resumed.push(args)
});
recentPage.handleBookTap({ ...audio, chapters: [{ id: 'a1', title: '第一集' }, { id: 'a2', title: '第二集' }] }, 'recent-cover');
assert.equal(resumed[0][0], 'audio');
assert.equal(resumed[0][1], 'recent-cover');
assert.equal(resumed[0][3], 'a2', 'resume resolves the saved chapter for a non-favorite book');
assert.equal(resumed[0][4], 37000);
const { AdaptiveLayout } = compile(read('utils/AdaptiveLayout.ets'));
assert.equal(AdaptiveLayout.navigationUsesColumns(1200, ['shelfCollection']), false, 'folder overlay spans the window');
assert.equal(AdaptiveLayout.navigationUsesColumns(1200, ['detail']), true, 'existing detail split layout is preserved');
const pendingCalls = [];
const { ScrollPage } = compile(`export class ScrollPage { ${method(source, 'handleShelfScroll')} ${method(source, 'finishShelfScroll')} }`,
  { ScrollState: { Idle: 0, Scroll: 1 } });
const scrollPage = Object.assign(new ScrollPage(), { alive: true, visible: true, foreground: true,
  historyRefreshPending: true, recentRefreshPending: true, textRefreshPending: false,
  onContentScroll: () => {}, onHistoryUpdated: () => pendingCalls.push('history'),
  refreshCollectionRecent: () => pendingCalls.push('recent') });
scrollPage.handleShelfScroll(20, 1);
assert.equal(scrollPage.shelfScrolling, true);
assert.equal(pendingCalls.length, 0, 'scroll does not trigger pending data refresh');
scrollPage.finishShelfScroll();
assert.equal(pendingCalls.join('|'), 'history', 'stop coalesces history and recent refresh through one path');
console.log('PASS collection groups, empty/search states, mixed recent history, progress, non-favorite resume, type-filter gesture and wide-window navigation');

const { SwipePage } = compile(`export class SwipePage { ${method(read('pages/MainPage.ets'), 'judgeTabSwipe')} ${method(read('pages/MainPage.ets'), 'handleTabSwipe')} }`, {
  GestureJudgeResult: { REJECT: 'reject', CONTINUE: 'continue' }
});
const switched = [];
const swipePage = Object.assign(new SwipePage(), { generalSettings: { swipeSwitchTabs: true }, currentTab: 1,
  nativeTabIndex: 1, shelfRecentGestureUntil: Number.MAX_SAFE_INTEGER, requestTabChange: index => switched.push(index) });
assert.equal(swipePage.judgeTabSwipe({ tag: 'main-tab-swipe' }), 'reject');
swipePage.handleTabSwipe({ offsetX: -120, offsetY: 0 });
assert.equal(switched.length, 0, 'recent card swipe must not switch the main tab');
swipePage.shelfRecentGestureUntil = 0;
swipePage.handleTabSwipe({ offsetX: -120, offsetY: 0 });
assert.equal(switched[0], 2, 'swipes outside recent cards still switch the main tab');

(async () => {
  const saved = [];
  const { AddPage } = compile(`export class AddPage { ${method(source, 'addCollectionBooks')} }`, {
    BookPresentation,
    PreferenceService: {
      getShelfFavorites: async () => ['unread', 'comic', 'audio'],
      setBookGroup: async (ids, group) => saved.push({ ids: Array.from(ids), group })
    }
  });
  BookPresentation.groups = ['阅读', '听书'];
  BookPresentation.edits = [{ bookId: 'audio', group: '听书' }];
  const addPage = Object.assign(new AddPage(), { shelfGroup: '阅读', favoriteBooks: books,
    favoriteIdsByBookId: new Map(), pendingShelfRemovalIds: new Set(), addingCollectionBooks: false,
    removingBook: false, showCollectionPicker: true, shelfFilter: 2, loadFavorites: async () => {} });
  await addPage.addCollectionBooks(['unread', 'comic', 'audio', 'text']);
  assert.deepEqual(saved, [{ ids: ['comic', 'unread'], group: '阅读' }],
    'only still-favorited and still-ungrouped selected books move; assigned and removed books are preserved');
  assert.equal(addPage.showCollectionPicker, false);
  assert.equal(addPage.shelfFilter, 0, 'newly added books become visible regardless of media type');
  assert.equal(addPage.addingCollectionBooks, false);
  addPage.shelfGroup = '已删除分组';
  await assert.rejects(addPage.addCollectionBooks(['comic']), /no longer available/);
  assert.equal(addPage.addingCollectionBooks, false, 'failed save releases the operation lock');
  assert.equal(saved.length, 1, 'deleted groups are not silently recreated');
  addPage.shelfGroup = '阅读';
  addPage.addingCollectionBooks = true;
  await addPage.addCollectionBooks(['unread']);
  assert.equal(saved.length, 1, 'repeated submission during save is ignored');
  console.log('PASS horizontal recent gesture isolation and ungrouped collection assignment');
})().catch(error => { console.error(error); process.exitCode = 1; });
