const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { randomUUID } = require('node:crypto');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const values = new Map();
let failFlush = false;
const store = {
  getSync: (key, fallback) => values.has(key) ? values.get(key) : fallback,
  async put(key, value) { values.set(key, value); },
  async flush() { if (failFlush) throw new Error('injected storage failure'); }
};
const modules = new Map();
function load(file) {
  const filename = path.resolve(root, file.endsWith('.ets') ? file : file + '.ets');
  if (modules.has(filename)) return modules.get(filename);
  const exports = {}; modules.set(filename, exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, console, Error, require(name) {
    if (name === '@kit.ArkData') return { preferences: { getPreferences: async () => store } };
    if (name === '@kit.ArkTS') return { util: { generateRandomUUID: randomUUID } };
    if (name.endsWith('/LocalRuleQuickJsRuntime')) return {
      LocalRuleQuickJsRequest: class {}, LocalRuleQuickJsRuntime: {
        async execute(request) {
          try { return { success: true, value: String(vm.runInNewContext(request.script, {}, { timeout: 100 })) }; }
          catch (error) { return { success: false, errorMessage: error.message }; }
        }
      }
    };
    if (name.startsWith('@')) return {};
    return load(path.resolve(path.dirname(filename), name));
  } }, { filename });
  return exports;
}
const { ReaderToolsService: service } = load('service/text/ReaderToolsService');
const { ReaderBookmark, ReaderReplaceRule } = load('model/ReaderTools');
const { ReaderReplaceImport } = load('service/text/ReaderReplaceImport');
function rule(pattern, replacement = '', regex = false, bookId = 'book') {
  const result = new ReaderReplaceRule();
  Object.assign(result, { id: randomUUID(), pattern, replacement, isRegex: regex, bookId });
  return result;
}
(async () => {
  const ctx = {};
  const ad = rule('广告');
  const rename = rule('(张)(三)', '$1小$2', true);
  await service.saveRule(ctx, ad);
  await service.saveRule(ctx, rename);
  const raw = '前文广告正文张三结尾';
  const result = await service.render(ctx, 'book', raw);
  assert.equal(result.content, '前文正文张小三结尾');
  const rawEnd = raw.indexOf('结尾');
  const displayEnd = result.content.indexOf('结尾');
  assert.equal(result.toDisplay(rawEnd), displayEnd);
  assert.equal(result.toRaw(displayEnd), rawEnd);
  assert.equal(result.toRaw(result.content.length), raw.length);
  assert.equal((await service.render(ctx, 'other', raw)).content, raw);
  rename.enabled = false;
  await service.saveRule(ctx, rename);
  assert.equal((await service.render(ctx, 'book', raw)).content, '前文正文张三结尾');
  const global = rule('正文', '$1', false, '');
  await service.saveRule(ctx, global);
  assert.equal((await service.render(ctx, 'other', raw)).content, '前文广告$1张三结尾');
  const marker = '\uFFF9/files/ebooks/import_test/image_0_0.img\uFFFB';
  const imageRule = rule('image', 'broken', false, '');
  const imageDoc = await service.render(ctx, 'book', 'image' + marker + 'image', [imageRule]);
  assert.equal(imageDoc.content, 'broken' + marker + 'broken');
  assert.equal(imageDoc.toRaw(imageDoc.content.length), ('image' + marker + 'image').length);
  const zero = await service.render(ctx, 'book', '甲乙', [rule('(?=乙)', '新增', true)]);
  assert.equal(zero.content, '甲新增乙');
  assert.equal(zero.toRaw(3), 1);
  assert.equal(zero.toDisplay(1), 3);
  await assert.rejects(service.saveRule(ctx, rule('(', '', true)), /reader_replace_invalid/);
  const slow = await service.render(ctx, 'book', 'a'.repeat(60) + '!', [rule('(a+)+$', '', true)]);
  assert.equal(slow.failed, true);
  assert.equal(slow.content, 'a'.repeat(60) + '!');
  const mark = new ReaderBookmark();
  Object.assign(mark, { id: randomUUID(), bookId: 'book', chapterId: 'chapter', chapterUrl: 'https://book/chapter',
    chapterTitle: '标题', charOffset: rawEnd, preview: '结尾', createdAt: Date.now() });
  await Promise.all([service.addBookmark(ctx, mark), service.addBookmark(ctx, mark)]);
  assert.equal((await service.bookmarks(ctx, 'book')).length, 1);
  const imported = ReaderReplaceImport.parse('\uFEFF[{"name":"删广告","pattern":"广告","replacement":"","isRegex":false},' +
    '{"pattern":"(张)(三)","replacement":"$1小$2","isEnabled":false}]');
  assert.equal(imported[1].isRegex, true);
  assert.equal(imported[1].enabled, false);
  assert.equal(await service.importRules(ctx, imported, 'import-rules'), 2);
  const storedIds = (await service.rules(ctx)).map(r => r.id);
  assert.equal(new Set(storedIds).size, storedIds.length, 'import assigns unique IDs');
  assert.equal(await service.importRules(ctx, imported, 'import-rules'), 0, 'repeat import must not duplicate rules');
  assert.equal((await service.render(ctx, 'import-rules', '广告张三')).content, '张三');
  assert.equal((await service.render(ctx, 'unrelated', '广告张三')).content, '广告张三');
  assert.equal(ReaderReplaceImport.parse('{"rules":[{"pattern":"a"}]}').length, 1);
  assert.equal(ReaderReplaceImport.parse('{"pattern":"a","isRegex":false}')[0].isRegex, false);
  for (const input of ['null', '[]', '{"rules":{}}', '[null]', '[{"pattern":5}]', '[{"pattern":"a","enabled":0}]']) {
    assert.throws(() => ReaderReplaceImport.parse(input), /reader_replace_import_invalid/);
  }
  for (const scope of [{ scopeContent: false }, { scopeSource: true }, { scope: '某书' }, { excludeScope: '某书' }]) {
    assert.throws(() => ReaderReplaceImport.parse(JSON.stringify([{ pattern: 'x', ...scope }])), /scope_error/);
  }
  assert.throws(() => ReaderReplaceImport.parse(JSON.stringify(Array.from({ length: 201 }, () => ({ pattern: 'x' })))), /reader_tools_limit/);
  const beforeImportFailure = values.get('data');
  await assert.rejects(service.importRules(ctx, [rule('valid'), rule('(', '', true)], 'book'), /reader_replace_invalid/);
  assert.equal(values.get('data'), beforeImportFailure, 'invalid batch must not partially save');
  failFlush = true;
  await assert.rejects(service.importRules(ctx, [rule('save-failure')], 'book'), /reader_tools_storage_error/);
  failFlush = false;
  assert.equal(values.get('data'), beforeImportFailure, 'failed import restores previous data');
  await assert.rejects(service.importRules(ctx, Array.from({ length: 200 }, (_, i) => rule('limit' + i)), 'book'), /reader_tools_limit/);
  assert.equal(values.get('data'), beforeImportFailure, 'rule cap applies to existing plus imported entries atomically');
  const saved = values.get('data');
  failFlush = true;
  await assert.rejects(service.deleteRule(ctx, ad.id), /injected/);
  assert.equal(values.get('data'), saved, 'failed save restores previous data');
  failFlush = false;
  await service.deleteRule(ctx, ad.id);
  assert.equal((await service.render(ctx, 'book', raw)).content, '前文广告$1张三结尾');
  await service.removeBookmark(ctx, mark.id);
  assert.equal((await service.bookmarks(ctx, 'book')).length, 0);
  const local = new ReaderBookmark();
  Object.assign(local, mark, { id: randomUUID(), bookId: 'import_local' });
  await service.addBookmark(ctx, local);
  await service.restore(ctx, { bookmarks: [mark], rules: [] });
  assert.equal((await service.bookmarks(ctx, 'import_local')).length, 1);
  assert.equal((await service.bookmarks(ctx, 'book')).length, 1);
  console.log('PASS bookmark persistence/deduplication/restore, failed writes, literal and regex rules, scope, disable/delete, raw offsets, image preservation and bounded execution');
})().catch(error => { console.error(error); process.exitCode = 1; });
