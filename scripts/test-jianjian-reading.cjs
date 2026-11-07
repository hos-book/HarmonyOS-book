const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
function load(relative, mocks = {}, globals = {}, page = false) {
  let source = fs.readFileSync(path.join(root, relative), 'utf8');
  if (page) source = source.slice(0, source.indexOf('  @Builder'))
    .replace(/@(?:ComponentV2|Param|Local)\s*/g, '').replace(/^\s*@Monitor\([^\n]*\)\s*$/gm, '')
    .replace('export struct ', 'export class ') + '\n getUIContext() { return ui; }\n}';
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
  const exports = {};
  vm.runInNewContext(code, { exports, require: name => { assert.ok(name in mocks, name); return mocks[name]; },
    Error, Set, Map, Date, setTimeout, clearTimeout, $r: (id, ...args) => ({ id, args }), ...globals });
  return exports;
}
const model = load('model/JianjianAi.ets');
const images = load('service/text/LocalTextImage.ets');
const { JianjianChatRoute: Route, JianjianChatItem: Item } = model;
const book = { id: 'b1', title: '同名书', sourceUrl: 'https://source-a.test', bookUrl: 'https://source-a.test/book/1',
  contentType: 'text', chapters: Array.from({ length: 5 }, (_, i) => ({ id: 'c' + i, title: '第' + (i + 1) + '章', source: { value: 'chapter/' + i } })) };
const route = Object.assign(new Route(), { bookId: book.id, sourceUrl: book.sourceUrl, bookUrl: book.bookUrl, chapterIndex: 2, charOffset: 12 });
function session(chapter, from, to, kind = 'reading') {
  return { kind, start: { bookId: book.id, chapterId: 'c' + chapter, chapterIndex: chapter, position: from },
    end: { bookId: book.id, chapterId: 'c' + chapter, chapterUrl: 'chapter/' + chapter, chapterIndex: chapter, position: to } };
}
let sessions = [session(0, 0, 15), session(0, 10, 24), session(2, 3, 20), session(3, 0, 20), session(1, 0, 20, 'audio')];
const cache = new Map([['chapter/0', '甲'.repeat(10) + '张三发现钥匙' + '乙'.repeat(8) + '未读秘密'],
  ['chapter/1', '仅预读的内容'], ['chapter/2', '跳过的' + '已经读过的段落正文' + '绝对不能透露的结局'], ['chapter/3', '未读章节秘密']]);
const reads = [];
const { JianjianBookContextService: Context } = load('service/JianjianBookContextService.ets', {
  '../model/JianjianAi': model,
  './ReadingSessionService': { ReadingSessionService: { list: async () => sessions } },
  './text/OnlineTextContentCache': { OnlineTextContentCache: { key: (_s, _b, c) => c,
    read: async (_c, key) => { reads.push(key); return cache.get(key); } } },
  './text/LocalTextImage': images
});
const records = new Map();
let failWrite = false;
const rdb = { '@kit.ArkData': { relationalStore: { SecurityLevel: { S2: 2 }, async getRdbStore(_context, options) {
  assert.equal(options.name, 'jianjian_chats.db'); assert.equal(options.encrypt, true);
  return { async executeSql(sql, values) {
    if (sql.startsWith('CREATE')) return;
    if (failWrite) throw new Error('disk failure');
    if (sql.startsWith('INSERT')) records.set(values[0], values[1]);
    else if (sql.includes('WHERE id = ?')) records.delete(values[0]);
    else while (records.size > 100) records.delete(records.keys().next().value);
  }, async querySql(_sql, values) { const raw = records.get(values[0]); return { goToFirstRow: () => raw !== undefined,
    getString: () => raw, close() {} }; } };
} } }, '../model/JianjianAi': model };
const newStore = () => load('service/JianjianChatStore.ets', rdb).JianjianChatStore;
const Store = newStore();
const careValues = new Map();
let flushCount = 0;
const careMocks = { '@kit.ArkData': { preferences: { getPreferences: async () => ({
  getSync: (key, fallback) => careValues.get(key) ?? fallback, put: async (key, value) => careValues.set(key, value),
  flush: async () => { flushCount++; }
}) } } };
const newCare = () => load('service/JianjianCareService.ets', careMocks).JianjianCareService;

(async () => {
  const context = await Context.collect({}, book, route, () => true);
  assert.equal(context.chapterCount, 2);
  assert.ok(!reads.includes('chapter/1') && !reads.includes('chapter/3'), 'preloaded and unread chapters are never read as context');
  const evidence = Context.evidence(Context.select(context, '张三找到什么？', false));
  assert.ok(evidence.includes('张三发现钥匙'));
  for (const secret of ['未读秘密', '绝对不能', '仅预读', '跳过的', '未读章节']) assert.ok(!evidence.includes(secret), secret);
  const selected = Context.select(context, '', true);
  assert.equal(Context.citations('结论 [1]，假的引用 [999]', selected).length, 1);
  assert.equal(Context.citations('没有出处 [999]', selected).length, 0);
  assert.equal(Context.resolveCitation(book, selected[0]), 0);
  assert.equal(Context.resolveCitation({ ...book, chapters: [] }, selected[0]), -1);
  assert.equal(Context.ranges(book, Object.assign(new Route(), route, { sourceUrl: 'other' }), sessions).length, 0);
  sessions = [session(0, 0, 100), session(0, 20, 2), session(2, 0, 500)];
  const rewind = Object.assign(new Route(), route, { chapterIndex: 0, charOffset: 5 });
  assert.equal(Context.ranges(book, rewind, sessions)[0].end, 5);
  assert.equal(Context.ranges(book, rewind, sessions).length, 1, 'rewind does not infer unread intervals');
  cache.set('chapter/0', '字\uFFF9/data/storage/private/image.img\uFFFB' + '可读内容');
  const noPath = await Context.collect({}, book, Object.assign(new Route(), rewind, { charOffset: 20 }), () => true);
  assert.ok(!Context.evidence(Context.select(noPath, '', true)).includes('/data/'), 'even a boundary inside an image marker must not expose a local path');
  assert.equal((await Context.collect({}, book, route, () => false)).excerpts.length, 0);
  cache.delete('chapter/0');
  assert.ok((await Context.collect({}, book, route, () => true)).missingChapters > 0);
  cache.set('chapter/0', '甲'.repeat(300000));
  sessions = [session(0, 0, 300000)];
  const bounded = await Context.collect({}, book, Object.assign(new Route(), rewind, { charOffset: 300000 }), () => true);
  assert.equal(bounded.limited, true);
  assert.ok(Context.select(bounded, '', true).reduce((n, e) => n + e.text.length, 0) <= 8800);

  const firstKey = Store.key(route);
  const secondKey = Store.key(Object.assign(new Route(), route, { sourceUrl: 'https://source-b.test' }));
  assert.notEqual(firstKey, secondKey);
  assert.notEqual(firstKey, Store.key(new Route()));
  const pair = [new Item('u1', 'user', '甲书问题'), new Item('a1', 'assistant', '甲书回答')];
  pair[1].references = Context.citations('[1]', selected);
  await Store.save({}, firstKey, pair);
  await Store.save({}, secondKey, [new Item('u2', 'user', '乙书问题'), new Item('a2', 'assistant', '乙书回答')]);
  assert.equal((await newStore().load({}, firstKey))[1].content, '甲书回答', 'completed turns survive a service restart');
  assert.equal((await Store.load({}, firstKey))[1].references[0].chapterId, 'c0');
  assert.equal(Store.decode(JSON.stringify([...pair, new Item('pending', 'user', '取消的请求')])).length, 2);
  failWrite = true; await assert.rejects(Store.save({}, firstKey, [])); failWrite = false;
  assert.equal((await Store.load({}, firstKey)).length, 2, 'failed writes preserve existing conversation');
  await Store.clear({}, firstKey);
  assert.equal((await Store.load({}, firstKey)).length, 0);
  assert.equal((await Store.load({}, secondKey)).length, 2, 'clear does not affect another source');

  const Care = newCare();
  const at = (day, hour, minute = 0) => new Date(2026, 10, day, hour, minute);
  assert.equal(Care.nightKey(at(7, 22, 59)), ''); assert.equal(Care.nightKey(at(8, 5)), '');
  assert.equal(Care.nightKey(at(7, 23)), Care.nightKey(at(8, 4, 59)));
  assert.equal(await Care.claim({}, at(7, 23), () => false), false);
  const duplicate = await Promise.all([Care.claim({}, at(7, 23), () => true), Care.claim({}, at(7, 23), () => true)]);
  assert.equal(duplicate.filter(Boolean).length, 1); assert.equal(flushCount, 1);
  assert.equal(await newCare().claim({}, at(8, 1), () => true), false, 'same night after restart and midnight');
  assert.equal(await Care.claim({}, at(8, 23), () => true), true);

  // Exercise the actual page controller, including a late network result after cancellation.
  let resolveReply;
  let calls = 0;
  let writes = 0;
  const client = class { cancel() {} async chat() { calls++; return new Promise(resolve => { resolveReply = resolve; }); } };
  client.loadConfig = async () => Object.assign(new model.JianjianAiConfig(), { address: 'https://ai.test/v1', apiKey: 'fixture', model: 'fixture' });
  client.errorText = () => 'error';
  const ui = { getHostContext: () => ({ resourceManager: { getStringSync: id => id } }),
    getPromptAction: () => ({ showDialog: async () => ({ index: 1 }) }) };
  const { JianjianChatPage: Page } = load('pages/JianjianChatPage.ets', {
    '../model/JianjianAi': model, '../service/JianjianAiService': { JianjianAiService: client },
    '../service/JianjianChatStore': { JianjianChatStore: { key: r => Store.key(r), load: (...args) => Store.load(...args),
      save: async (...args) => { writes++; return Store.save(...args); }, clear: (...args) => Store.clear(...args) } },
    '../service/JianjianBookContextService': { JianjianBookContextService: Context },
    '../service/DataService': { DataService: {} }, '../utils/SearchCache': { SearchCache: {} },
    '@kit.BasicServicesKit': { emitter: {} }, '../model/TextReading': { EVT_READER_JUMP_CHAPTER: 'jump' },
    '../theme/Theme': { AppTheme: {}, AppColor: {} },
    '../utils/ListDataSource': { ListDataSource: class { setItems() {} } },
    '../utils/WindowUtils': { WindowUtils: { getStatusBarHeightVp: () => 0 } }
  }, { ui, NavPathStack: class {}, Scroller: class { scrollEdge() {} }, Edge: { Bottom: 1 } }, true);
  const page = new Page(); page.alive = true; page.sessionKey = Store.key(new Route());
  await page.initialize(); page.input = '被取消的提问';
  const pending = page.send(); page.cancel(); resolveReply('迟到回复'); await pending;
  assert.equal(writes, 0); assert.equal(page.items.length, 0); assert.equal(page.input, '被取消的提问');
  const retry = page.send(); resolveReply('成功回复'); await retry;
  assert.equal(writes, 1); assert.equal(calls, 2); assert.equal(page.items.length, 2);
  page.aboutToDisappear();
  const reopened = new Page(); reopened.alive = true; reopened.sessionKey = Store.key(new Route()); await reopened.initialize();
  assert.equal(reopened.items.length, 2); assert.equal(reopened.items[1].content, '成功回复');
  await reopened.clearHistory(); assert.equal((await Store.load({}, reopened.sessionKey)).length, 0);
  reopened.aboutToDisappear();
  console.log('PASS: read interval/source isolation, unread truncation, bounded retrieval, image privacy, citations, encrypted conversation restore/clear/failure, cancellation, nightly frequency across midnight and restart');
})().catch(error => { console.error(error); process.exitCode = 1; });
