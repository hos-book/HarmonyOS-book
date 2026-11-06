// DEVECO_HOME=<Release IDE> node scripts/test-home-channels.cjs
// Exercise the real service with grouped discovery menus and controlled network replies.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
let revision = 0, loginRevision = 0, entries = [], controls = [], calls = [], fail = '', hold;
let recommendationCalls = [], moreResponder;
const source = { bookSourceUrl: 'https://fixture.invalid', bookSourceName: '综合源',
  enabledExplore: true, exploreUrl: 'native' };
const modules = {
  '../../model/BookSource': {}, '../../model/LocalRuleSource': {},
  '../SourceDataService': { SourceDataService: { getInvalidationCounter: () => revision } },
  '../PreferenceService': {}, '../ranking/RankingService': {},
  './LocalRuleSourceRepository': { LocalRuleSourceRepository: { getLoginRevision: () => loginRevision } },
  './LocalRulePanelService': { LocalRulePanelService: { load: async () => ({ entries, controls }) } },
  '../BookSourceService': { BookSourceService: { getExploreBooksByUrl: async (_source, url, page, limit) => {
    if (limit === 50) {
      recommendationCalls.push({ url, page, limit });
      return moreResponder ? moreResponder(url, page) : { books: [], nextUrl: '' };
    }
    calls.push(url);
    if (hold) await hold;
    if (url === fail) throw new Error('fixture failed');
    return { books: [{ bookUrl: url + '/book', name: url, coverUrl: '' }] };
  } } }
};
const moduleRef = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,
  'service/rulesource/HomeSourceService.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, { module: moduleRef, exports: moduleRef.exports, require: id => modules[id], Map, Set, Date, JSON });
const service = moduleRef.exports.HomeSourceService;
function fixture() {
  entries = [];
  for (const [group, count] of [['小说', 8], ['漫画', 6], ['听书', 18], ['影视', 6]]) {
    entries.push({ title: group, url: '', type: 'group' });
    for (let i = 0; i < count; i++) entries.push({ title: i ? '分类' + i : '全部',
      url: '/' + group + '/' + i, type: 'category', group });
  }
  calls = []; revision++;
}
(async () => {
  fixture();
  controls = [
    { id: 'mode', title: '模式', discoveryFilter: true, options: ['小说模式', '漫画模式'], action: 'set:mode' },
    { id: 'channel', title: '频道', discoveryFilter: true, options: ['男频', '女频'], action: 'set:channel' },
    { id: 'server', title: '服务器', options: ['private'], action: 'set:server' }
  ];
  const all = await service.loadHome(source);
  assert.deepEqual(Array.from(all.filters, item => item.id), ['mode', 'channel'],
    'preserve declared filter layers without exposing settings');
  assert.deepEqual(Array.from(all.channels), ['小说', '漫画', '听书']);
  assert.equal(all.categories.length, 32);
  assert.equal(all.blocks.length, 4);
  assert.deepEqual(calls.slice(0, 3), ['/小说/0', '/漫画/0', '/听书/0']);
  assert.ok(calls.every(url => !url.includes('影视')));
  calls = [];
  const audio = await service.loadHome(source, false, () => {}, '听书');
  assert.equal(audio.categories.length, 18);
  assert.ok(audio.categories.every(category => category.group === '听书'));
  assert.ok(calls.every(url => url.includes('听书')));
  calls = [];
  assert.equal(await service.loadHome(source), all, 'channel cache must not replace the aggregate');
  assert.equal(await service.loadHome(source, false, () => {}, '听书'), audio);
  assert.equal(calls.length, 0);
  const video = await service.loadHome(source, false, () => {}, '影视');
  assert.equal(video.channel, '', 'a saved video channel falls back to the aggregate');
  assert.equal(video.blocks.length, 4);
  assert.equal(video.categories.length, 32);
  assert.ok(!video.channels.includes('影视'));
  assert.ok(calls.every(url => !url.includes('影视')), 'filtered video must not execute as text');
  fail = '/漫画/0'; revision++;
  const partial = await service.loadHome(source);
  assert.equal(partial.blocks.length, 3, 'one failed channel cannot stop the rest');
  fail = ''; calls = []; loginRevision++;
  await service.loadHome(source);
  assert.equal(calls.length, 4, 'login changes invalidate channel caches');
  fixture();
  let release;
  hold = new Promise(resolve => { release = resolve; });
  const slow = service.loadHome(source, false, () => {}, '听书');
  await new Promise(resolve => setImmediate(resolve));
  const comic = service.loadHome(source, false, () => {}, '漫画');
  const sameAudio = service.loadHome(source, false, () => {}, '听书');
  release(); hold = undefined;
  const [a, c, a2] = await Promise.all([slow, comic, sameAudio]);
  assert.equal(a, a2, 'same channel shares in-flight work');
  assert.equal(a.channel, '听书'); assert.equal(c.channel, '漫画');
  assert.equal(calls.length, 8, 'different channels load independently without duplicate requests');
  entries = [{ title: '历史', url: '/history' }, { title: '热门', url: '/hot' }]; revision++; calls = [];
  const plain = await service.loadHome(source, false, () => {}, '已删除频道');
  assert.equal(plain.channel, ''); assert.equal(plain.channels.length, 0);
  assert.deepEqual(calls, ['/history', '/hot']);
  assert.equal(plain.blocks[0].title, '历史');
  entries = []; revision++;
  assert.equal((await service.loadHome(source)).blocks.length, 0);
  // Run the real page loading/switching methods: a slow old channel must never repaint a new one.
  const page = fs.readFileSync(path.join(root, 'pages/HomePage.ets'), 'utf8').replace(/\r\n/g, '\n');
  const loadMethod = page.slice(page.indexOf('  private async loadHomeBlocks('),
    page.indexOf('  private scrollContentToTop('));
  const channelMethods = page.slice(page.indexOf('  private updateHomeChannels('),
    page.indexOf('  private revealCategoryTab('));
  const filterMethod = page.slice(page.indexOf('  private async selectHomeFilter('),
    page.indexOf('  @Builder\n  private buildCategorySheet('));
  const filterItemClass = page.slice(page.indexOf('class HomeFilterOptionItem {'),
    page.indexOf('class HomeCategoryDataSource '));
  const filterMenuMethods = page.slice(page.indexOf('  private updateHomeFilters('),
    page.indexOf('  @Computed\n  get homeFilterMenuListMaxHeight('));
  const pageModule = { exports: {} }, saved = [];
  let filterAction = async () => {};
  const prefs = { getHomeSourceChannel: async () => '听书',
    setHomeSourceChannel: async (url, channel) => { saved.push([url, channel]); } };
  vm.runInNewContext(ts.transpileModule(`${filterItemClass}\nexport class Harness { ${loadMethod}\n${channelMethods}\n${filterMethod}\n${filterMenuMethods} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { module: pageModule, exports: pageModule.exports,
    HomeSourceService: service, PreferenceService: prefs, $r: text => text,
    LocalRulePanelService: { act: (...args) => filterAction(...args) },
    CoverPrefetcher: { prefetchMany() {} }, hilog: { error() {} }, DOMAIN: 0, TAG: 'fixture' });
  service.getSelectedSource = async () => source;
  const harness = Object.assign(new pageModule.exports.Harness(), {
    homeGen: 0, homeSources: [], homeChannels: [], homeBlocks: [], homeCategories: [], moreRecommendations: [],
    selectedHomeChannel: '', channelSave: Promise.resolve(),
    homeFilters: [], homeFilterMenuVisible: false, homeFilterGroupMenuVisible: false,
    homeFilterKeyword: '', homeFilterGroup: '', homeFilterMatchCount: 0,
    homeFilterMenuData: { items: [], setItems(items) { this.items = items; } },
    homeFilterGroupMenuData: { items: [], setItems(items) { this.items = items; } },
    homeFilterMenuScroller: { scrollTo() {} },
    channelDataSource: { setItems() {} }, categoryDS: { setBooks() {} },
    updateHomeBlocks(value) { this.homeBlocks = value; },
    updateMoreRecommendations(value) { this.moreRecommendations = value; },
    updateHomeCategories(value) { this.homeCategories = value; },
    selectCategoryTab(value) { this.selectedCategoryIndex = value; },
    onScrollerReady() {}, showHomeSourceToast() {}
  });
  fixture();
  await harness.loadHomeBlocks();
  assert.equal(harness.selectedHomeChannel, '听书', 'restore saved channel');
  const menuFilters = [
    { id: 'mode', title: '模式', group: ' 推荐 ', value: 'text',
      options: ['全部', '听书'], optionValues: ['text', 'audio'] },
    { id: 'audience', title: '频道', group: '', value: '',
      options: ['全部', 'Sci-Fi', 'Sci-Fi', '无有效值'], optionValues: ['', 'male', 'female'] },
    { id: 'sort', title: '排序', group: '推荐', value: 'hot',
      options: ['热门'], optionValues: ['hot'] }
  ];
  harness.updateHomeFilters(menuFilters);
  harness.toggleHomeFilterMenu();
  assert.deepEqual(Array.from(harness.homeFilterGroupMenuData.items), ['', '推荐', '频道'],
    'use source groups in order, falling back to control titles without duplicate groups');
  assert.equal(harness.homeFilterMatchCount, 6, 'empty values remain valid and unmapped options are omitted');
  assert.equal(new Set(harness.homeFilterMenuData.items.map(item => item.key)).size, 6,
    'identical labels in different controls or with different values must retain separate identities');
  harness.homeFilterGroup = '频道';
  harness.filterHomeOptions('  SCI-fi  ');
  assert.deepEqual(Array.from(harness.homeFilterMenuData.items, item => item.value), ['male', 'female'],
    'search and group intersect while preserving labels and source values');
  const optionKey = harness.homeFilterMenuData.items[0].key;
  harness.filterHomeOptions('推荐');
  assert.equal(harness.homeFilterMatchCount, 0, 'search must not escape the selected group');
  harness.homeFilterGroup = '';
  harness.filterHomeOptions('推荐');
  assert.equal(harness.homeFilterMatchCount, 3, 'group names can be searched across their controls');
  harness.filterHomeOptions('频道');
  assert.equal(harness.homeFilterMenuData.items[1].key, optionKey, 'filtering must not change option identity');
  harness.toggleHomeFilterMenu();
  harness.toggleHomeFilterMenu();
  assert.equal(harness.homeFilterKeyword, '');
  assert.equal(harness.homeFilterGroup, '');
  assert.equal(harness.homeFilterMatchCount, 6, 'reopening restores all options');
  harness.homeFilterGroupMenuVisible = true;
  harness.updateHomeFilters([]);
  assert.equal(harness.homeFilterMenuVisible, false);
  assert.equal(harness.homeFilterGroupMenuVisible, false);
  assert.equal(harness.homeFilterMenuData.items.length, 0, 'source reset removes stale selectable options');
  console.log('PASS source group fallback, combined category search, stable option mapping and source reset');
  // The discovery menu is ready before recommendation requests complete.
  const filter = { id: 'mode', value: 'male', discoveryFilter: true,
    options: ['男频', '女频'], optionValues: ['male', 'female'], action: 'set:mode' };
  controls = [filter]; fixture();
  hold = new Promise(resolve => { release = resolve; });
  const loadingPage = harness.loadHomeBlocks();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(harness.loadingHome, true);
  assert.equal(harness.homeFilters[0], filter, 'filters arrive while preview books are still pending');
  let finishSave, filterCalls = 0, replacementLoad;
  filterAction = async () => {
    filterCalls++;
    await new Promise(resolve => { finishSave = resolve; });
    revision++;
    replacementLoad = harness.loadHomeBlocks(false, false, '漫画');
  };
  const selection = harness.selectHomeFilter(filter, 'female');
  assert.equal(filterCalls, 1, 'ready filter must be selectable while recommendations are loading');
  assert.equal(harness.savingHomeFilter, true);
  await harness.selectHomeFilter(filter, 'male');
  assert.equal(filterCalls, 1, 'only the save operation prevents duplicate selection');
  finishSave(); await selection;
  release(); hold = undefined;
  await Promise.all([loadingPage, replacementLoad]);
  assert.equal(harness.savingHomeFilter, false);
  assert.equal(harness.selectedHomeChannel, '漫画');
  assert.ok(harness.homeBlocks.every(block => block.moreUrl.includes('漫画')),
    'recommendations from before the filter change must not overwrite the refreshed page');
  const previous = filter.value;
  filterAction = async () => { throw new Error('save failed'); };
  await harness.selectHomeFilter(filter, 'male');
  assert.equal(filter.value, previous, 'failed filter saves restore the previous selection');
  assert.equal(harness.savingHomeFilter, false, 'failed saves release the click lock');
  console.log('PASS loading-time filter selection, duplicate save guard, stale preview isolation and save rollback');
  hold = new Promise(resolve => { release = resolve; });
  const oldPage = harness.switchHomeChannel('小说');
  await new Promise(resolve => setImmediate(resolve));
  const newPage = harness.switchHomeChannel('漫画');
  release(); hold = undefined;
  await Promise.all([oldPage, newPage, harness.channelSave]);
  assert.equal(harness.selectedHomeChannel, '漫画');
  assert.ok(harness.homeCategories.every(category => category.group === '漫画'));
  assert.ok(harness.homeBlocks.every(block => block.moreUrl.includes('漫画')));
  assert.equal(saved.at(-1)[1], '漫画', 'rapid selections persist in order');
  assert.equal(harness.loadingHome, false);
  console.log('PASS page channel restore, rapid switching, stale response guard and ordered preference saves');
  console.log('PASS grouped discovery, balanced previews, independent channel cache/pending requests, failures, unsupported video, login invalidation and ordinary/empty sources');
  const book = id => ({ name: 'Book ' + id, bookUrl: '/books/' + id,
    sourceUrl: source.bookSourceUrl, author: 'Author', intro: 'Summary', coverUrl: '' });
  entries = [{ title: '全部', url: '/more' }]; revision++; recommendationCalls = [];
  moreResponder = async (_url, page) => ({
    books: [{ ...book('preview'), bookUrl: '/more/book' },
      ...Array.from({ length: 30 }, (_, index) => book((page - 1) * 30 + index))],
    nextUrl: '/more?page=' + (page + 1), nextPage: page + 1
  });
  const progressiveCounts = [];
  const fifty = await service.loadHome(source, false, content => progressiveCounts.push(content.moreRecommendations.length));
  assert.equal(fifty.moreRecommendations.length, 50, 'fill fifty extra books from source-provided next pages');
  assert.equal(new Set(fifty.moreRecommendations.map(item => item.bookUrl)).size, 50);
  assert.ok(fifty.moreRecommendations.every(item => item.bookUrl !== '/more/book'), 'exclude preview duplicates');
  assert.ok(progressiveCounts.includes(30), 'publish partial results before all fifty are available');
  assert.equal(fifty.moreLoading, false);
  assert.equal(recommendationCalls.length, 2);
  assert.equal(recommendationCalls[1].url, '/more?page=2');
  assert.equal(await service.loadHome(source), fifty, 'cache includes the extra recommendations');
  assert.equal(recommendationCalls.length, 2, 'cached homepage does not repeat extra requests');

  entries = [{ title: '失败分类', url: '/bad' }, { title: '正常分类', url: '/good' }];
  revision++; recommendationCalls = [];
  let activeMore = 0, peakMore = 0;
  moreResponder = async url => {
    activeMore++; peakMore = Math.max(peakMore, activeMore);
    await new Promise(resolve => setImmediate(resolve));
    activeMore--;
    if (url === '/bad') throw new Error('more failed');
    return { books: [book(1), book(2), book(3)], nextUrl: '' };
  };
  const partialMore = await service.loadHome(source);
  assert.equal(partialMore.blocks.length, 2, 'extra loading failure preserves all preview sections');
  assert.equal(partialMore.moreRecommendations.length, 3, 'available books survive another category failure');
  assert.equal(partialMore.moreFailed, true);
  assert.equal(peakMore, 2, 'extra discovery is limited to two concurrent requests');

  entries = [{ title: '循环页', url: '/loop' }]; revision++; recommendationCalls = [];
  moreResponder = async () => ({ books: [book(1), book(2)], nextUrl: '/loop' });
  const looping = await service.loadHome(source);
  assert.equal(looping.moreRecommendations.length, 2);
  assert.equal(recommendationCalls.length, 2, 'repeated page data stops pagination');
  revision++; recommendationCalls = [];
  moreResponder = async (_url, page) => ({ books: [book(page)], nextUrl: '/loop' });
  const bounded = await service.loadHome(source);
  assert.equal(recommendationCalls.length, 8, 'a source with endless next pages respects the request budget');
  assert.equal(bounded.moreRecommendations.length, 8, 'short sources never fabricate books to reach fifty');
  assert.ok(recommendationCalls.every(call => call.limit === 50));

  revision++; recommendationCalls = [];
  let releaseMore;
  moreResponder = async () => {
    await new Promise(resolve => { releaseMore = resolve; });
    return { books: [book('obsolete')], nextUrl: '/loop' };
  };
  const obsoleteMore = service.loadHome(source);
  await new Promise(resolve => setImmediate(resolve));
  revision++;
  releaseMore();
  const obsolete = await obsoleteMore;
  assert.equal(obsolete.moreRecommendations.length, 0, 'source invalidation discards pending extra results');
  assert.equal(recommendationCalls.length, 1, 'source invalidation stops subsequent requests');
  moreResponder = undefined;
  console.log('PASS fifty source recommendations, pagination, progressive updates, preview deduplication, cache, partial failure, concurrency, budgets and invalidation');

  const widthGetter = page.slice(page.indexOf('  get contentWidth():'),
    page.indexOf('  @Computed\n  get homeCategoryNavHeight()'));
  const rowMethods = page.slice(page.indexOf('  private updateMoreRecommendations('),
    page.indexOf('  /** 首板块按每页三条分组')).replace(/^\s*@Monitor\([^\n]*\)\n/gm, '\n');
  const layoutSource = fs.readFileSync(path.join(root, 'utils/AdaptiveLayout.ets'), 'utf8');
  const mediumWidth = Number(layoutSource.match(/MEDIUM_WIDTH: number = (\d+)/)[1]);
  const layoutModule = { exports: {} };
  vm.runInNewContext(ts.transpileModule(`export class LayoutHarness { ${widthGetter}\n${rowMethods} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { module: layoutModule, exports: layoutModule.exports,
    AdaptiveLayout: { MEDIUM_WIDTH: mediumWidth }, JSON, Math });
  const rowData = { items: [], setItems(items) { this.items = items; } };
  const layout = Object.assign(new layoutModule.exports.LayoutHarness(), {
    viewportWidth: 360, leftSafeVp: 0, rightSafeVp: 0,
    moreRecommendations: [], moreRecommendationColumns: 1, moreRecommendationDataSource: rowData
  });
  layout.updateMoreRecommendations(fifty.moreRecommendations);
  const bookUrls = Array.from(fifty.moreRecommendations, item => item.bookUrl);
  const phoneKeys = Array.from(rowData.items, row => layout.moreRecommendationRowKey(row));
  for (const [width, columns] of [[320, 1], [599, 1], [600, 2], [840, 2], [1200, 2], [360, 1]]) {
    layout.viewportWidth = width;
    layout.onMoreRecommendationWidthChanged();
    assert.equal(layout.moreRecommendationColumns, columns, `columns at ${width}vp`);
    assert.equal(rowData.items.length, Math.ceil(50 / columns));
    assert.deepEqual(Array.from(rowData.items.flat(), item => item.bookUrl), bookUrls,
      'resizing preserves all books and their source order');
  }
  assert.deepEqual(Array.from(rowData.items, row => layout.moreRecommendationRowKey(row)), phoneKeys,
    'returning to a narrow window restores stable business keys');
  layout.viewportWidth = 640; layout.leftSafeVp = 24; layout.rightSafeVp = 24;
  layout.onMoreRecommendationWidthChanged();
  assert.equal(layout.moreRecommendationColumns, 1, 'safe areas participate in the breakpoint');
  layout.leftSafeVp = 0; layout.rightSafeVp = 0;
  layout.onMoreRecommendationWidthChanged();
  layout.updateMoreRecommendations(fifty.moreRecommendations.slice(0, 49));
  assert.equal(rowData.items.at(-1).length, 1, 'odd book counts retain the last book');
  console.log('PASS phone/tablet/split-screen widths, safe areas, order, stable row keys and odd counts');
})().catch(error => { console.error(error); process.exitCode = 1; });
