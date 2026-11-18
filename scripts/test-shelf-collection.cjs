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
  if (start < 0) start = source.indexOf(`  get ${name}(`);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const { BookPresentation } = compile(read('model/BookPresentation.ets'));
const { ShelfCollectionData: data, ShelfCollectionGroup } = compile(read('model/ShelfCollection.ets'), { BookPresentation });
const paletteNames = Array.from(read('components/ShelfCollectionFolder.ets').matchAll(/'app\.color\.(collection_\w+_back)'/g),
  match => match[1].slice(0, -5));
const sampleGroups = Array.from({ length: 19 }, (_, i) => `Palette ${i}`);
const sampleFolders = data.groups([], sampleGroups, new Set(), '', true);
assert.equal(paletteNames.length, 20);
assert.equal(new Set(paletteNames).size, 20);
assert.equal(new Set(sampleFolders.slice(0, 19).map(group => group.tint)).size, 19, 'all and the first 18 custom groups differ');
assert.equal(sampleFolders[19].tint, sampleFolders[1].tint, 'custom tints cycle only after 18 groups');
assert.equal(sampleFolders.at(-1).tint, ShelfCollectionGroup.UNGROUPED_TINT);
assert.equal(new Set(sampleFolders.map(group => group.tint)).size, 20);
assert.deepEqual(Array.from(data.ordered(sampleFolders, JSON.stringify([sampleGroups[3], sampleGroups[1]])).slice(0, 2),
  group => group.tint), [3, 1], 'drag order does not recolor folders');
for (const mode of ['base', 'dark']) {
  const file = path.join(__dirname, '../entry/src/main/resources', mode, 'element/color.json');
  const resources = new Map(JSON.parse(fs.readFileSync(file, 'utf8')).color.map(entry => [entry.name, entry.value]));
  for (const name of paletteNames) {
    for (const part of ['back', 'top', 'front', 'ink']) {
      assert.match(resources.get(`${name}_${part}`) ?? '', /^#(?:[\dA-F]{6}|[\dA-F]{8})$/i, `${mode}: ${name}_${part}`);
    }
  }
  assert.equal(new Set(paletteNames.map(name => resources.get(`${name}_front`))).size, 20, `${mode}: distinct front colors`);
}
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
const folderIds = items => items.map(item => item.id).join('|');
const originalFolderIds = folderIds(folders);
assert.equal(folderIds(data.ordered(folders, JSON.stringify(['听书', '已删除', '听书', '阅读']))),
  ['听书', '阅读', '空分组', BookPresentation.UNGROUPED].join('|'),
  'saved duplicates/deleted groups are ignored and newly added folders append in source order');
assert.equal(folderIds(folders), originalFolderIds, 'applying saved order never mutates the derived folder array');
assert.equal(folderIds(data.ordered(folders, '[]')), originalFolderIds, 'missing saved order preserves default order');
for (const stored of ['', '{broken', 'null', '{}', '42', '"阅读"']) {
  assert.equal(folderIds(data.ordered(folders, stored)), originalFolderIds,
    `damaged/non-array order safely falls back: ${stored}`);
}
assert.equal(folderIds(data.ordered(folders, JSON.stringify([null, 1, {}, ['阅读'], '听书']))),
  ['听书', '阅读', '空分组', BookPresentation.UNGROUPED].join('|'),
  'malformed saved array entries cannot replace or duplicate real folders');
assert.equal(data.ordered([], '["阅读"]').length, 0, 'deleted last folder cannot be recreated by stale order');
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
  const viewSource = read('components/ShelfCollectionView.ets');
  const { HomeRecommendationDataSource } = compile(read('utils/HomeRecommendationDataSource.ets'));
  const { CollectionView } = compile(`export class CollectionView {
    ${method(viewSource, 'updateGroups')} ${method(viewSource, 'renderGroups')} ${method(viewSource, 'draggableGroups')}
    ${method(viewSource, 'beginDrag')} ${method(viewSource, 'finishDrag')}
    ${method(viewSource, 'reorder')} ${method(viewSource, 'updateWidth')}
  }`, { AdaptiveLayout, ShelfCollectionData: data, setTimeout, clearTimeout, $r: key => key });
  const orderSaves = [];
  const visibleFolders = folders.slice();
  let renderedFolders = [];
  let reloads = 0;
  const pendingOrderSaves = [];
  let failureToast = 0;
  const folderSource = new HomeRecommendationDataSource();
  folderSource.registerDataChangeListener({ onDataReloaded: () => {
    reloads++;
    renderedFolders = Array.from({ length: folderSource.totalCount() }, (_, index) => folderSource.getData(index));
  } });
  const collectionView = Object.assign(new CollectionView(), {
    groups: [new ShelfCollectionGroup('', 0), ...visibleFolders], reorderEnabled: true, wideRecent: false, recentIndex: 2,
    renderedGroups: [], savedOrder: [], pendingOrderSaves: 0, orderSaveTask: Promise.resolve(),
    dragging: false, draggingGroupId: '', dropTimer: -1, dragAppearanceTimer: -1,
    onRecentTouch: () => {}, data: folderSource,
    getUIContext: () => ({ getPromptAction: () => ({ showToast: () => { failureToast++; } }) }),
    onReorder: ids => new Promise((resolve, reject) => {
      orderSaves.push(Array.from(ids));
      pendingOrderSaves.push({ resolve, reject });
    })
  });
  collectionView.updateGroups();
  assert.equal(renderedFolders.some(group => group.id === ''), false, 'All Books is outside the move data source');
  collectionView.updateWidth(599);
  assert.equal(collectionView.wideRecent, false, 'compact container retains recent carousel');
  collectionView.updateWidth(600);
  assert.equal(collectionView.wideRecent, true, 'wide container displays all recent cards in a row');
  assert.equal(collectionView.recentIndex, 0, 'resizing clears stale carousel position');
  collectionView.updateWidth(500);
  assert.equal(collectionView.wideRecent, false, 'folding back restores compact presentation');
  collectionView.beginDrag(1);
  assert.equal(collectionView.draggingGroupId, '', 'appearance reset waits until the native long-press callback exits');
  await new Promise(resolve => setTimeout(resolve, 2));
  assert.equal(collectionView.draggingGroupId, visibleFolders[1].id, 'native item index maps to the folder data without a header offset');
  const beforeDragReloads = reloads;
  collectionView.groups = visibleFolders.slice();
  collectionView.updateGroups();
  assert.equal(reloads, beforeDragReloads, 'host refresh cannot reload native drag placeholders');
  collectionView.finishDrag();
  assert.equal(collectionView.draggingGroupId, '', 'drop clears the reactive drag appearance');
  const saveOrder = collectionView.reorder(3, 0);
  assert.equal(renderedFolders[0].id, BookPresentation.UNGROUPED, 'ungrouped folder can be moved too');
  assert.equal(visibleFolders[0].id, '阅读', 'optimistic reorder never mutates host params');
  const saveNext = collectionView.reorder(0, 1);
  assert.equal(folderIds(renderedFolders), ['阅读', BookPresentation.UNGROUPED, '听书', '空分组'].join('|'),
    'a rapid second drop uses the current visible order while the first save is pending');
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(orderSaves.length, 1, 'preference writes are serialized');
  pendingOrderSaves.shift().resolve();
  await saveOrder;
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(orderSaves.length, 2);
  assert.equal(folderIds(renderedFolders), orderSaves[1].join('|'), 'older save cannot overwrite the latest visible drop');
  pendingOrderSaves.shift().resolve();
  await saveNext;
  assert.equal(folderIds(renderedFolders), orderSaves[1].join('|'),
    'completed save keeps the accepted order even before @Param has synchronized');
  collectionView.groups = orderSaves[1].map(id => visibleFolders.find(group => group.id === id));
  collectionView.updateGroups();
  collectionView.onReorder = async () => { throw new Error('disk full'); };
  await collectionView.reorder(0, 2);
  assert.equal(folderIds(renderedFolders), orderSaves[1].join('|'), 'save failure restores the last committed order');
  assert.equal(failureToast, 1, 'failed persistence is reported');
  collectionView.reorderEnabled = false;
  await collectionView.reorder(0, 2);
  assert.equal(failureToast, 1, 'search result order cannot overwrite the complete folder order');
  if (collectionView.dropTimer !== -1) clearTimeout(collectionView.dropTimer);
  console.log('PASS recent width switching, native drag data refresh isolation, immediate and consecutive folder drops, serialized saves and failed-save rollback');

  let finishHostSave;
  const settings = { shelfCollectionOrder: '["阅读","关闭分组","听书","空分组","__ungrouped__"]',
    showAllShelfGroup: true, showUngroupedShelfGroup: true, isShelfGroupVisible: group => group !== '关闭分组' };
  const { OrderPage } = compile(`export class OrderPage {
    ${method(source, 'shelfGroupOrder')} ${method(source, 'saveCollectionOrder')} ${method(source, 'saveShelfGroupOrder')}
    ${method(source, 'visibleGroupOptions')} ${method(source, 'collectionGroups')}
  }`, {
    BookPresentation, ShelfCollectionData: data,
    PreferenceService: { setShelfCollectionOrder: ids => new Promise((resolve, reject) => {
      finishHostSave = { resolve: () => { settings.shelfCollectionOrder = JSON.stringify(ids); resolve(); }, reject };
    }) }
  });
  const previousOrder = settings.shelfCollectionOrder;
  const host = Object.assign(new OrderPage(), { shelfDisplaySettings: settings, shelfBooks: books,
    pendingShelfRemovalIds: new Set(), shelfKeyword: '',
    shelfGroups: ['阅读', '关闭分组', '听书', '空分组'] });
  assert.equal(host.shelfGroupOrder.join('|'), '|阅读|关闭分组|听书|空分组|__ungrouped__', 'legacy bookroom order keeps All Books first');
  const requestedOrder = visibleFolders.map(folder => folder.id).reverse();
  const mergedOrder = ['', ...requestedOrder];
  mergedOrder.splice(2, 0, '关闭分组');
  const hostSave = host.saveCollectionOrder(requestedOrder);
  assert.equal(host.shelfGroupOrder.join('|'), mergedOrder.join('|'), 'both views see the pending order with disabled slots intact');
  assert.equal(folderIds(host.collectionGroups), ['', ...requestedOrder].join('|'), 'bookroom follows before flush');
  assert.equal(settings.shelfCollectionOrder, previousOrder, 'committed preferences do not change before flush');
  finishHostSave.reject(new Error('disk full'));
  await assert.rejects(hostSave, /disk full/);
  assert.equal(settings.shelfCollectionOrder, previousOrder, 'host failure restores the previous preference immediately');
  assert.equal(folderIds(host.collectionGroups), ['','阅读','听书','空分组',BookPresentation.UNGROUPED].join('|'),
    'failed save also restores bookroom display');
  const hostSuccess = host.saveCollectionOrder(requestedOrder);
  finishHostSave.resolve();
  await hostSuccess;
  assert.equal(settings.shelfCollectionOrder, JSON.stringify(mergedOrder));
  const managerOrder = ['', '关闭分组', '听书', '空分组', '阅读', BookPresentation.UNGROUPED];
  const managerSave = host.saveShelfGroupOrder(managerOrder);
  assert.equal(folderIds(host.collectionGroups), managerOrder.filter(id => id !== '关闭分组').join('|'),
    'manager order immediately controls the same visible bookroom folders');
  finishHostSave.resolve();
  await managerSave;
  await assert.rejects(host.saveCollectionOrder(requestedOrder.slice(1)), /Invalid collection order/);
  console.log('PASS host order commits before persistence and rolls back on failure');

  const saved = [];
  const { AddPage } = compile(`export class AddPage {
    ${method(source, 'shelfBooks')} ${method(source, 'matchesShelfVisibility')}
    ${method(source, 'addCollectionBooks')} }`, {
    BookPresentation,
    PreferenceService: {
      getShelfFavorites: async () => ['unread', 'comic', 'audio'],
      setBookGroup: async (ids, group) => saved.push({ ids: Array.from(ids), group })
    }
  });
  BookPresentation.groups = ['阅读', '听书'];
  BookPresentation.edits = [{ bookId: 'audio', group: '听书' }];
  const addPage = Object.assign(new AddPage(), { shelfGroup: '阅读', favoriteBooks: books,
    hiddenShelf: false, hiddenShelfUnlocked: true,
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
