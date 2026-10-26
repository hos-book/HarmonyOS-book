// Real ArkTS ranking parsers, caching and matching, with bounded platform substitutes.
// DEVECO_HOME=<Release IDE> node scripts/test-ranking-home.cjs [live-response-directory]
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
function load(relative, modules = {}) {
  const filename = path.join(__dirname, '../entry/src/main/ets', relative);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, { module, exports: module.exports, $r: value => value,
    require: name => { assert.ok(modules[name], `Unexpected import: ${name}`); return modules[name]; }
  }, { filename });
  return module.exports;
}
const model = load('model/Ranking.ets');
const json = load('service/builtin/JsonValue.ets');
const fanqieText = load('service/ranking/FanqieRankingText.ets');
const metadataPolicy = load('utils/BookMetadataPolicy.ts');
const parser = load('service/ranking/RankingParser.ets', {
  '../../model/Ranking': model, '../builtin/JsonValue': json, './FanqieRankingText': fanqieText,
  '../../utils/BookMetadataPolicy': metadataPolicy
});
const { RankingParser } = parser;
const identity = load('utils/BookIdentity.ets');
const disk = new Map();
const storage = { RankingStorage: {
  read: async (_context, key) => disk.get(key) || '',
  write: async (_context, key, content) => disk.set(key, content)
} };
let requests = 0, response = '', networkFail = false, requestOverride;
const { RankingService } = load('service/ranking/RankingService.ets', {
  '../../model/Ranking': model, './RankingParser': parser, './RankingStorage': storage,
  '../builtin/JsonValue': json, '../http/HttpClient': { HttpClient: {
    request: async () => {
      requests++;
      if (requestOverride) return requestOverride();
      if (networkFail) throw Error('offline');
      return { statusCode: 200, body: response };
    }
  } }
});
let sources = [], searchFn = async () => [], concurrency = 2;
const { BookMatchService } = load('service/ranking/BookMatchService.ets', {
  '../../utils/BookIdentity': identity, './RankingStorage': storage, '../builtin/JsonValue': json,
  '../SourceDataService': { SourceDataService: { getEnabledSources: async () => sources } },
  '../BookSourceService': { BookSourceService: { searchBooks: (...args) => searchFn(...args) } },
  '../PreferenceService': { PreferenceService: { getSearchConcurrency: async () => concurrency } }
});
function result(source, name = '夜无疆', type = 'text') {
  return { name, author: '辰东', intro: '作者辰东', bookUrl: '/book/1', sourceUrl: source.bookSourceUrl,
    sourceName: source.bookSourceName, coverUrl: 'https://cover.example/1.jpg', kind: '', lastChapter: '', contentType: type };
}
const qidian = '<a href="//m.qidian.com/book/123/" class="_bookItem_x"><img data-src="//bookcover.yuewen.com/qdbimg/349573/123/180"><h2 class="_title_x">夜无疆</h2><p class="_bookDesc_x">风起&amp;云涌</p><p class="_subTitle_x">辰东 <em>·</em> 玄幻</p></a>';
(async () => {
  const { BookMetadataPolicy: metadata } = metadataPolicy;
  for (const value of [undefined, '', '暂无', 'NaN', NaN, Infinity, -1, 0, 101, '9.5万人', '95/10', '5/5', '101%']) {
    assert.equal(metadata.rating(value), 0, `missing/invalid rating: ${value}`);
  }
  assert.equal(metadata.rating('9.5分'), 9.5);
  for (const [value, expected] of [[95, 9.5], [100, 10], [11, 1.1], ['95分', 9.5], ['95%', 9.5],
    ['95％', 9.5], ['95 / 100', 9.5], ['9/100', 0.9], ['9%', 0.9], ['9.5/10', 9.5]]) {
    assert.equal(metadata.rating(value), expected, `ten-point normalization: ${value}`);
    assert.equal(metadata.rating(metadata.rating(value)), expected, 'normalization must be idempotent');
  }
  for (const label of ['评分：95', '玄幻 | 95分 | 连载中', 'score: 95/100', '评分：95%', 'rating 95％']) {
    assert.equal(metadata.rating(undefined, label), 9.5, label);
  }
  assert.equal(metadata.rating(undefined, '热度95万'), 0);
  assert.equal(metadata.rating(undefined, '排名95'), 0);
  assert.equal(metadata.rating(undefined, '玄幻 | 评分：9.8 | 连载中'), 9.8);
  assert.equal(metadata.rating(undefined, '悬疑,9.2分'), 9.2);
  assert.equal(metadata.rating(undefined, '19.8分'), 1.98);
  assert.equal(metadata.rating(undefined, '热度9.8万'), 0);
  assert.equal(metadata.completed(''), undefined);
  assert.equal(metadata.completed('未知'), undefined);
  assert.equal(metadata.completed('未完结'), false);
  assert.equal(metadata.completed('已完结'), true);
  assert.deepEqual(Array.from(metadata.categories('玄幻|暂无|audio|连载中|玄幻|评分：9.8|热血')), ['玄幻', '热血']);
  const mixedRatingTags = '评分 9.2 · 玄幻奇幻|东方玄幻|剑道';
  assert.equal(metadata.rating(undefined, mixedRatingTags), 9.2);
  assert.deepEqual(Array.from(metadata.categories(mixedRatingTags)), ['玄幻奇幻', '东方玄幻', '剑道']);
  for (const separator of [' ', '\t', '\n', '\u00a0', '·', '•', '・', '●', '▪', ':', '：']) {
    const tags = `玄幻${separator}9.2分${separator}热血|玄幻`;
    assert.equal(metadata.rating(undefined, tags), 9.2);
    assert.deepEqual(Array.from(metadata.categories(tags)), ['玄幻', '热血']);
    assert.equal(metadata.rating(undefined, `玄幻${separator}19.8分`), 1.98);
  }
  assert.deepEqual(Array.from(metadata.categories('2.5次元·轻小说')), ['2.5次元', '轻小说']);
  assert.equal(metadata.rating(undefined, '热度9.8万·玄幻'), 0);
  const deviceTags = '9.9分 科幻 已完结';
  assert.equal(metadata.rating(undefined, deviceTags), 9.9);
  assert.deepEqual(Array.from(metadata.categories(deviceTags)), ['科幻']);
  assert.deepEqual(Array.from(metadata.categories('390.1万字 9.5分 都市 已完结')), ['都市']);
  assert.deepEqual(Array.from(metadata.categories('评分 9.2 分 玄幻奇幻 东方玄幻 剑道')), ['玄幻奇幻', '东方玄幻', '剑道']);
  const htmlTags = '<span>评分&nbsp;9.2</span><span>玄幻</span>&middot;热血';
  assert.equal(metadata.rating(undefined, htmlTags), 9.2);
  assert.deepEqual(Array.from(metadata.categories(htmlTags)), ['玄幻', '热血']);
  assert.deepEqual(Array.from(metadata.categories('评分：9.2\u00a0玄幻\t已完结\n玄幻')), ['玄幻']);
  assert.deepEqual(Array.from(metadata.categories('科幻 已完结2026-04-02 更新：2026/04/02 12:30:00')), ['科幻']);
  assert.deepEqual(Array.from(metadata.categories('科幻 更新时间：2026年4月2日 12：30')), ['科幻']);
  const qd = RankingParser.parse('qidian', 'qd-month', qidian + qidian);
  assert.equal(qd.length, 1, 'duplicate entries are removed without changing ranks');
  assert.equal(qd[0].author, '辰东');
  assert.equal(qd[0].intro, '风起&云涌');
  assert.equal(qd[0].contentType, 'text');
  assert.equal(qd[0].coverUrl, 'https://bookcover.yuewen.com/qdbimg/349573/123/600');
  assert.equal(qd[0].rating, 0, 'no rating stays absent rather than using rank');
  assert.equal(RankingParser.parse('qidian', 'qd-month', '<script>challenge()</script>').length, 0);
  const page = records => '<script id="vite-plugin-ssr_pageContext" type="application/json">' +
    JSON.stringify({ pageContext: { pageProps: { pageData: { records } } } }) + '</script>';
  const completeRecords = [
    { bid: 100, bName: '完本甲', bAuth: '作者甲', state: '完本', desc: '简介' },
    { bid: '101', bName: '连载乙', state: '连载' },
    { bid: '102', bName: '完本丙', state: '已经完本' },
    { bid: 100, bName: '重复甲', state: '完本' },
    { bid: 'javascript:bad', bName: '非法', state: '完本' }
  ];
  const finished = RankingParser.parse('qidian', 'qd-finished', page(completeRecords) + qidian);
  assert.equal(RankingParser.parse('qidian', 'qd-month', page([{ bid: 88, bName: '评分书', score: '9.2' }]))[0].rating, 9.2);
  assert.deepEqual(Array.from(finished, book => book.id), ['qidian:100', 'qidian:102']);
  assert.deepEqual(Array.from(finished, book => book.rank), [1, 3], 'keep source order when filtering records');
  assert.equal(finished[0].author, '作者甲');
  assert.equal(finished[0].coverUrl, 'https://bookcover.yuewen.com/qdbimg/349573/100/600');
  assert.equal(RankingParser.parse('qidian', 'qd-finished', qidian).length, 0,
    'finished board must not pick unrelated page recommendations');
  assert.equal(RankingParser.parse('qidian', 'qd-finished',
    '<script id="vite-plugin-ssr_pageContext">broken</script>' + qidian).length, 0);
  assert.equal(RankingParser.parse('qidian', 'qd-reading',
    page([{ bid: 200, bName: '榜单书', rankNum: 21 }]))[0].rank, 21);
  assert.equal(RankingParser.imageUrl('javascript:alert(1)'), '');
  assert.equal(RankingParser.parse('qidian', 'qd-month', 'x'.repeat(2 * 1024 * 1024 + 1)).length, 0);
  const lr = RankingParser.parse('lrts', 'lr-hot', '<li class="book-item"><a href="/book/42"><img src="https://bookpic.lrts.me/42.png"></a><a class="book-item-name">夜无疆|多人有声剧</a><a class="author">辰东</a>主播：<a>演播甲</a><p class="book-item-desc weaken">简介</p></li>');
  assert.equal(lr[0].narrator, '演播甲');
  const ratedAudio = RankingParser.parse('lrts', 'lr-hot',
    '<li class="book-item"><a href="/book/43"></a><a class="book-item-name">评分有声书</a><span class="score">8.6</span></li>');
  assert.equal(ratedAudio[0].rating, 8.6);
  assert.equal(BookMatchService.keyword(lr[0]), '夜无疆');
  assert.equal(BookMatchService.score(qd[0], { ...result({ bookSourceUrl: 'a' }), name: '另一本书' }), 0,
    'same author must not cause an unrelated book to match');
  const xm = JSON.stringify({ ret: 200, data: { freeAlbumRank: { rankListInfo: [
    { id: 1, albumTitle: '夜无疆', anchorName: '主播乙', cover: '//imagev2.xmcdn.com/1.jpg', albumScore: 9.6 },
    { id: 1, albumTitle: 'duplicate' }, { id: 'bad' }
  ] } } });
  assert.equal(RankingParser.parse('ximalaya', 'xm-free', xm).length, 1);
  assert.equal(RankingParser.parse('ximalaya', 'xm-free', xm)[0].rating, 9.6);
  assert.equal(RankingParser.parse('ximalaya', 'xm-free', '{"ret":400}').length, 0);

  const v3 = albums => JSON.stringify({ ret: 200, data: { rankList: [
    { rankId: 999, albums: [{ id: 999, albumTitle: 'unrelated' }] },
    { rankId: 48, albums }
  ] } });
  const albums = [{ id: 5, albumTitle: '热播书', cover: 'storages/audio/cover.jpg' },
    { id: 5, albumTitle: 'duplicate' }, { id: 'bad', albumTitle: 'invalid' }];
  const hot = RankingParser.parse('ximalaya', 'xm-hot', v3(albums));
  assert.equal(hot.length, 1);
  assert.equal(hot[0].coverUrl, 'https://imagev2.xmcdn.com/storages/audio/cover.jpg');
  assert.equal(RankingParser.parse('ximalaya', 'xm-new', v3(albums)).length, 0);
  assert.equal(RankingParser.parse('ximalaya', 'xm-unknown', xm).length, 0);
  assert.equal(RankingParser.parse('ximalaya', 'xm-hot', v3(Array.from({length: 120},
    (_, id) => ({id, albumTitle: 'book'})))).length, 100);
  for (const platform of ['qidian', 'lrts', 'ximalaya', 'qimao', 'jjwxc', 'fanqie', 'faloo']) {
    assert.equal(RankingService.boards().filter(board => board.platformId === platform).length, 6);
  }
  const categoryResponse = code => JSON.stringify({ code, data: { book_list: [
    { bookId: '7590221243043826712', bookName: '\ue51e\ue449游戏\ue52a\ue49a劲，\ue521挖矿\ue4e9\ue522！',
      author: '\ue459\ue52a易', abstract: '职业\ue4c2挖矿', thumbUri: 'https://cover.example/fq.jpg', currentPos: 7 },
    { bookId: '7590221243043826712', bookName: '重复' },
    { bookId: '1', bookName: '\ue600未知字' },
    { bookId: '2', bookName: '正常书名', author: '\ue600未知作者', currentPos: 10 },
    { bookId: 'javascript:bad', bookName: '非法编号' }
  ] } });
  const fq = RankingParser.parse('fanqie', 'fq-fantasy-reading', categoryResponse(0));
  assert.equal(fq.length, 2);
  assert.equal(fq[0].id, 'fanqie:7590221243043826712', 'large IDs stay lossless strings');
  assert.equal(fq[0].title, '这个游戏不对劲，我挖矿成神！');
  assert.equal(fq[0].author, '道不易');
  assert.equal(fq[0].intro, '职业人挖矿');
  assert.equal(fq[0].rank, 7, 'keep the public category rank');
  assert.equal(fq[1].author, '', 'never display undecoded private characters');
  assert.equal(RankingParser.parse('fanqie', 'fq-fantasy-reading', categoryResponse(1)).length, 0);
  assert.equal(fanqieText.FanqieRankingText.decode('中文 ABC xyz 0123456789'), '中文 ABC xyz 0123456789');
  const fqHot = RankingParser.parse('fanqie', 'fq-hot', JSON.stringify({ book_list: [
    { book_id: '7276384138653862966', book_name: '我不是戏神', author: '三九音域', category: '都市高武',
      thumb_url: 'https://cover.example/hot.jpg' }
  ] }));
  assert.equal(fqHot[0].title, '我不是戏神', 'the existing plain-text hot endpoint stays supported');
  assert.equal(fqHot[0].intro, '都市高武');
  assert.equal(BookMatchService.toBook({ ...result({bookSourceUrl:'source'}), rating: 8.7 }, 'text').rating, 8.7);

  const vip = RankingParser.parse('jjwxc', 'jj-vip', '<tr><td><a href="onebook.php?novelid=123">强推书</a></td><td><a href="oneauthor.php?authorid=45">作者</a></td></tr>');
  assert.equal(vip[0].title, '强推书');
  assert.equal(vip[0].author, '作者');

  response = qidian;
  assert.deepEqual(Array.from(RankingService.boards().slice(0, 3), item => item.id), ['fq-hot', 'fl-month', 'fl-flowers']);
  const monthBoard = () => RankingService.boards().find(item => item.id === 'qd-month');
  let board = monthBoard();
  board = await RankingService.load({}, board, false);
  assert.equal(board.books.length, 1);
  board = await RankingService.cached({}, monthBoard());
  await RankingService.load({}, board, false);
  assert.equal(requests, 1, 'fresh disk cache avoids repeated requests');
  networkFail = true;
  const stale = await RankingService.load({}, board, true);
  assert.equal(stale.books.length, 1, 'failed refresh preserves previous entries');
  assert.equal(stale.stale, true);
  const absent = await RankingService.load({}, RankingService.boards().find(item => item.id === 'lr-hot'), true);
  assert.equal(absent.unavailable, true);
  disk.set('qd-month', 'corrupt json');
  assert.equal((await RankingService.cached({}, monthBoard())).books.length, 0);

  // An unfinished tail cache must not prevent a front board from appearing.
  networkFail = false;
  const originalRead = storage.RankingStorage.read;
  let releaseTail;
  storage.RankingStorage.read = async (context, key) => key === 'xm-free'
    ? new Promise(resolve => { releaseTail = resolve; }) : originalRead(context, key);
  const progressiveUpdates = [];
  const progressiveBoards = ['lr-hot', 'qd-month', 'xm-free'].map(id => RankingService.boards().find(board => board.id === id));
  const progressive = RankingService.loadProgressively({}, progressiveBoards, false,
    item => progressiveUpdates.push(item), () => true);
  while (!releaseTail || !progressiveUpdates.some(item => item.id === 'qd-month')) {
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.ok(progressiveUpdates.find(item => item.id === 'qd-month').books.length > 0);
  releaseTail('');
  await progressive;
  storage.RankingStorage.read = originalRead;

  // Exactly three requests can run; cancellation drops late results and stops scheduling.
  disk.clear();
  const completions = [];
  requestOverride = () => new Promise(resolve => completions.push(() => resolve({ statusCode: 200, body: qidian })));
  let current = true;
  const cancelledUpdates = [];
  const cancelled = RankingService.loadProgressively({}, RankingService.boards(), true,
    item => { cancelledUpdates.push(item); current = false; }, () => current);
  while (completions.length < 3) await new Promise(resolve => setImmediate(resolve));
  assert.equal(completions.length, 3);
  completions[1]();
  while (current) await new Promise(resolve => setImmediate(resolve));
  completions[0]();
  completions[2]();
  await cancelled;
  assert.equal(completions.length, 3, 'cancelled generation cannot schedule remaining boards');
  assert.equal(cancelledUpdates.length, 1, 'late results cannot update a cancelled page');
  requestOverride = undefined;

  const service = new BookMatchService();
  let last;
  await service.search({}, qd[0], '夜无疆', state => { last = state; });
  assert.equal(last.total, 0, 'no-source state is explicit');
  sources = [0, 1, 2, 3].map(i => ({ bookSourceUrl: 'source-' + i, bookSourceName: '来源' + i, bookSourceType: 0 }));
  let running = 0, peak = 0;
  searchFn = async source => {
    running++; peak = Math.max(peak, running);
    await new Promise(resolve => setTimeout(resolve, 2));
    running--;
    if (source.bookSourceUrl === 'source-1') throw Error('broken source');
    return [result(source), result(source), result(source, '夜无疆', 'audio')];
  };
  await service.search({}, qd[0], '夜无疆', state => { last = state; });
  assert.equal(last.completed, 4);
  assert.equal(last.failed, 1);
  assert.equal(last.matches.length, 3, 'dedupe by source and book URL');
  assert.ok(peak <= 2, 'honors search concurrency');
  const chosen = last.matches[2];
  await BookMatchService.remember({}, qd[0], chosen);
  await service.search({}, qd[0], '夜无疆', state => { last = state; });
  assert.equal(last.matches[0].book.sourceUrl, chosen.book.sourceUrl);
  assert.equal(last.matches[0].remembered, true);
  assert.equal(last.matches[0].book.id,
    identity.BookIdentity.onlineTextBookId(chosen.book.sourceUrl, chosen.book.bookUrl));

  searchFn = async source => [result(source), { ...result(source, '夜无疆', 'audio'), bookUrl: '/audio/1' }];
  await service.search({}, qd[0], '夜无疆', state => { last = state; });
  assert.equal(last.matches.filter(match => match.book.contentType === 'text').length, 4);
  assert.equal(last.matches.filter(match => match.book.contentType === 'audio').length, 4,
    'a text ranking must also return matching audio versions for the result groups');
  const audioVersion = last.matches.find(match => match.book.contentType === 'audio');
  assert.equal(audioVersion.book.id,
    identity.BookIdentity.onlineAudioBookId(audioVersion.book.sourceUrl, audioVersion.book.bookUrl));

  concurrency = 1;
  let resolveRequest, called = 0, progressCount = 0;
  searchFn = source => { called++; return new Promise(resolve => { resolveRequest = () => resolve([result(source)]); }); };
  const pending = service.search({}, qd[0], '夜无疆', () => progressCount++);
  while (!resolveRequest) await new Promise(resolve => setImmediate(resolve));
  service.cancel();
  const before = progressCount;
  resolveRequest(); await pending;
  assert.equal(called, 1, 'cancel prevents additional source scheduling');
  assert.equal(progressCount, before, 'late results do not overwrite new selection');

  if (process.argv[2] === '--expanded-live') {
    const boards = RankingService.boards().filter(board => ['fanqie', 'faloo'].includes(board.platformId));
    const results = new Map();
    let cursor = 0;
    const worker = async () => {
      while (cursor < boards.length) {
        const board = boards[cursor++];
        const response = await fetch(board.endpoint, { signal: AbortSignal.timeout(20000), headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
        } });
        assert.equal(response.status, 200, board.id);
        const raw = new TextDecoder(board.platformId === 'faloo' ? 'gb18030' : 'utf-8').decode(await response.arrayBuffer());
        const books = RankingParser.parse(board.platformId, board.id, raw);
        assert.ok(books.length >= 3, `${board.id}: public response must contain real entries`);
        assert.equal(new Set(books.map(book => book.id)).size, books.length);
        assert.ok(books.every(book => book.title && book.coverUrl.startsWith('https://') &&
          !/[\uE000-\uF8FF]/.test(book.title + book.author + book.intro)), board.id);
        if (board.platformId === 'fanqie' && board.id !== 'fq-hot') {
          assert.equal(books.length, Math.min(99, JSON.parse(raw).data.book_list.length), 'decode every real entry');
        }
        results.set(board.id, books);
        console.log(`LIVE ${board.id}: ${books.length} books; first: ${books[0].title}`);
      }
    };
    await Promise.all([worker(), worker(), worker()]);
    const originals = new Map(results.get('fq-hot').map(book => [book.id, book]));
    let verified = 0;
    for (const [id, books] of results) {
      if (!id.startsWith('fq-') || id === 'fq-hot') continue;
      for (const book of books) {
        const original = originals.get(book.id);
        if (!original) continue;
        assert.equal(book.title, original.title, `font mapping must match plain official metadata for ${book.id}`);
        assert.equal(book.author, original.author);
        verified++;
      }
    }
    assert.ok(verified > 0, 'compare decoded names against independent official plain-text metadata');
    console.log(`LIVE verified ${verified} decoded titles/authors against official plain-text metadata`);
  } else if (process.argv[2] === '--qidian-live') {
    for (const board of RankingService.boards().filter(board => board.platformId === 'qidian')) {
      const response = await fetch(board.endpoint, { signal: AbortSignal.timeout(20000) });
      assert.equal(response.status, 200, board.id);
      const bytes = await response.arrayBuffer();
      const encoding = /charset=([^;\s]+)/i.exec(response.headers.get('content-type') || '')?.[1] || 'utf-8';
      const books = RankingParser.parse(board.platformId, board.id, new TextDecoder(encoding).decode(bytes));
      assert.ok(books.length >= 3, `${board.id}: public response must contain real entries`);
      assert.equal(new Set(books.map(book => book.id)).size, books.length);
      assert.ok(books.every(book => book.title && book.coverUrl.startsWith('https://')));
      console.log(`LIVE ${board.id}: ${books.length} books; first: ${books[0].title}`);
    }
  } else if (process.argv[2]) {
    for (const board of RankingService.boards()) {
      const raw = fs.readFileSync(path.join(process.argv[2], board.id + '.txt'), 'utf8');
      const books = RankingParser.parse(board.platformId, board.id, raw);
      assert.ok(books.length >= 3, `${board.id}: public response must contain real entries`);
      assert.ok(books.every(book => book.id && book.title && book.coverUrl.startsWith('https://')));
      console.log(`LIVE ${board.id}: ${books.length} books; first: ${books[0].title}`);
    }
  }
  console.log('PASS ranking parser, cache fallback, matching identity, dedupe, failure isolation and cancellation');
})().catch(error => { console.error(error); process.exitCode = 1; });
