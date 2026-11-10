const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { randomUUID } = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'reading-excerpts-'));
const database = new DatabaseSync(path.join(temp, 'excerpts.db'));
const control = { failOpen: false, failWrite: false, failQuery: false, cursors: 0 };

function load(file, mocks = {}) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText;
  const exports = {};
  vm.runInNewContext(code, { exports, require: name => {
    assert.ok(name in mocks, name); return mocks[name];
  }, Error });
  return exports;
}

const models = load('model/ReadingExcerpt.ets');
const store = {
  async executeSql(sql, values = []) {
    if (control.failWrite) throw new Error('disk failure');
    database.prepare(sql).run(...values);
  },
  async querySql(sql, values = []) {
    if (control.failQuery) throw new Error('query failure');
    const query = database.prepare(sql);
    const columns = query.columns().map(item => item.name);
    const rows = query.all(...values);
    let position = -1;
    control.cursors++;
    return {
      goToFirstRow() { position = 0; return rows.length > 0; },
      goToNextRow() { return ++position < rows.length; },
      getString(index) { return rows[position][columns[index]]; },
      getLong(index) { return rows[position][columns[index]]; },
      close() { control.cursors--; }
    };
  },
  async close() {}
};
function service() {
  return load('service/text/ReadingExcerptService.ets', {
    '../../model/ReadingExcerpt': models,
    '@kit.ArkTS': { util: { generateRandomUUID: randomUUID } },
    '@kit.ArkData': { relationalStore: { SecurityLevel: { S2: 2 }, async getRdbStore(_context, config) {
      assert.equal(config.encrypt, true);
      assert.equal(config.allowRebuild, false);
      if (control.failOpen) throw new Error('open failure');
      return store;
    } } }
  }).ReadingExcerptService;
}

async function main() {
  const Service = service();
  const book = { id: 'source-book', title: '这么多年', author: '八月长安', cover: 'cover.jpg',
    sourceUrl: 'https://source.test/rules', bookUrl: 'https://source.test/book' };
  const chapter = { id: 'chapter-1', title: '第一章', source: { type: 'url', value: 'https://source.test/chapter/1' } };
  const save = (text = '重要的人越来越少，剩下的人，也就变得越来越重要。', start = 20) =>
    Service.create({}, book, chapter, 0, start, start + text.length, text);
  assert.deepEqual(Array.from(await Service.books({})), []);
  const concurrent = await Promise.all([save(), save()]);
  assert.equal(concurrent.filter(item => item.created).length, 1);
  assert.equal(concurrent[0].excerpt.id, concurrent[1].excerpt.id, 'concurrent duplicates reuse the stored entry');
  assert.equal((await Service.books({}))[0].count, 1);
  assert.equal((await Service.list({}, Service.bookKey(book)))[0].text, concurrent[0].excerpt.text);
  assert.equal((await service().list({}, Service.bookKey(book)))[0].id, concurrent[0].excerpt.id,
    'a fresh service instance restores persisted entries');
  await save('第一段。\n\n第二段。😀', 120);
  assert.equal((await Service.list({}, Service.bookKey(book)))[0].text, '第一段。\n\n第二段。😀');
  const other = { ...book, sourceUrl: 'https://another.test/rules' };
  await Service.create({}, other, chapter, 0, 20, 30, '来自另一书源');
  assert.equal((await Service.books({})).length, 2, 'source identity prevents merging distinct editions');
  assert.notEqual(Service.bookKey({ ...book, sourceUrl: 'a|b', bookUrl: 'c' }),
    Service.bookKey({ ...book, sourceUrl: 'a', bookUrl: 'b|c' }), 'book identities are unambiguous');
  for (let i = 0; i < 55; i++) await save('句子 ' + i, 200 + i * 10);
  const first = await Service.list({}, Service.bookKey(book));
  const second = await Service.list({}, Service.bookKey(book), 50);
  assert.equal(first.length, 50); assert.equal(second.length, 7);
  assert.equal(new Set([...first, ...second].map(item => item.id)).size, 57);
  assert.equal((await Service.books({})).find(item => item.bookKey === Service.bookKey(book)).count, 57);
  assert.equal((await Service.books({}, 0, 1)).length, 1);
  await assert.rejects(Service.list({}, Service.bookKey(book), -1));
  await assert.rejects(Service.list({}, Service.bookKey(book), 0, 101));
  await assert.rejects(save('字'.repeat(20001)), /reading_excerpt_too_long/);
  await assert.rejects(save('   '), /reading_excerpt_invalid/);
  await assert.rejects(save('test', -1), /reading_excerpt_invalid/);
  control.failWrite = true;
  await assert.rejects(save('不能假报成功', 9000), /disk failure/);
  await assert.rejects(Service.remove({}, first[0].id), /disk failure/);
  control.failWrite = false;
  assert.equal((await Service.list({}, Service.bookKey(book)))[0].id, first[0].id);
  await Service.remove({}, first[0].id);
  assert.equal((await Service.books({})).find(item => item.bookKey === Service.bookKey(book)).count, 56);
  control.failQuery = true;
  await assert.rejects(Service.books({}), /query failure/);
  control.failQuery = false;
  control.failOpen = true;
  const Fresh = service();
  await assert.rejects(Fresh.books({}), /open failure/);
  control.failOpen = false;
  assert.equal((await Fresh.books({})).length, 2, 'open failures remain retryable without wiping entries');
  const groups = await Service.books({});
  const reconstructed = Service.toBook(groups[0]);
  assert.equal(Service.bookKey(reconstructed), groups[0].bookKey);
  assert.equal(reconstructed.tocComplete, false);
  assert.equal(control.cursors, 0, 'all query cursors close');
  console.log('reading excerpts passed: persistence, duplicate saves, source isolation, pagination, multiline text, limits and failure recovery');
}

main().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  database.close();
  fs.rmSync(temp, { recursive: true, force: true });
});
