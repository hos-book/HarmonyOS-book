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
const source = { bookSourceUrl: 'https://fixture.invalid', bookSourceName: '综合源',
  enabledExplore: true, exploreUrl: 'native' };
const modules = {
  '../../model/BookSource': {}, '../../model/LocalRuleSource': {},
  '../SourceDataService': { SourceDataService: { getInvalidationCounter: () => revision } },
  '../PreferenceService': {}, '../ranking/RankingService': {},
  './LocalRuleSourceRepository': { LocalRuleSourceRepository: { getLoginRevision: () => loginRevision } },
  './LocalRulePanelService': { LocalRulePanelService: { load: async () => ({ entries, controls }) } },
  '../BookSourceService': { BookSourceService: { getExploreBooksByUrl: async (_source, url) => {
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
  const page = fs.readFileSync(path.join(root, 'pages/HomePage.ets'), 'utf8');
  const loadMethod = page.slice(page.indexOf('  private async loadHomeBlocks('),
    page.indexOf('  private scrollContentToTop('));
  const channelMethods = page.slice(page.indexOf('  private updateHomeChannels('),
    page.indexOf('  private revealCategoryTab('));
  const pageModule = { exports: {} }, saved = [];
  const prefs = { getHomeSourceChannel: async () => '听书',
    setHomeSourceChannel: async (url, channel) => { saved.push([url, channel]); } };
  vm.runInNewContext(ts.transpileModule(`export class Harness { ${loadMethod}\n${channelMethods} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { module: pageModule, exports: pageModule.exports,
    HomeSourceService: service, PreferenceService: prefs, $r: text => text,
    CoverPrefetcher: { prefetchMany() {} }, hilog: { error() {} }, DOMAIN: 0, TAG: 'fixture' });
  service.getSelectedSource = async () => source;
  const harness = Object.assign(new pageModule.exports.Harness(), {
    homeGen: 0, homeSources: [], homeChannels: [], homeBlocks: [], homeCategories: [],
    selectedHomeChannel: '', channelSave: Promise.resolve(),
    channelDataSource: { setItems() {} }, categoryDS: { setBooks() {} },
    updateHomeBlocks(value) { this.homeBlocks = value; },
    updateHomeCategories(value) { this.homeCategories = value; },
    selectCategoryTab(value) { this.selectedCategoryIndex = value; },
    onScrollerReady() {}, showHomeSourceToast() {}
  });
  fixture();
  await harness.loadHomeBlocks();
  assert.equal(harness.selectedHomeChannel, '听书', 'restore saved channel');
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
})().catch(error => { console.error(error); process.exitCode = 1; });
