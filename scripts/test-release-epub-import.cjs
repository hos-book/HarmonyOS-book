// Exercise the actual obfuscated caller and exports produced by a Release build.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const product = process.argv[2] || 'release';
const root = path.resolve(__dirname, '..');
const cache = JSON.parse(fs.readFileSync(path.join(root, `build/outputs/${product}/symbol/release/entry/entry-nameCache.json`)));
const compiledRoot = path.join(root, `entry/build/${product}/cache/default/default@CompileArkTS/esmodule/release`);
function compiled(relative) {
  const source = `entry/src/main/ets/${relative}`;
  const mapped = source.split('/').map(part => cache.FileNameCache[part] || part).join('/');
  return fs.readFileSync(path.join(compiledRoot, mapped + '.ts'), 'utf8');
}
function evaluate(source, requireModule, globals = {}) {
  const exports = {};
  const code = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText;
  vm.runInNewContext(code, { exports, require: requireModule, canIUse: () => true, ...globals });
  return exports;
}
(async () => {
  const parserCode = compiled('service/text/EpubParserService');
  let calls = 0;
  const handler = { getBookInfo: () => ({ bookTitle: '发布包 EPUB', bookCreator: '测试作者' }),
    getCover: () => 'cover.jpg', getSpineList: () => [{ href: 'chapter.xhtml' }] };
  const parser = evaluate(parserCode, name => {
    assert.equal(name, '@hms:core.readerservice.bookParser');
    return { bookParser: { getDefaultHandler: async filename => {
      assert.equal(filename, '/fixture.epub'); calls++; return handler;
    } } };
  });
  const callerCode = compiled('service/LocalBookImportService');
  const caller = ts.createSourceFile('import.ts', callerCode, ts.ScriptTarget.Latest, true);
  const service = caller.statements.find(node => ts.isClassDeclaration(node) &&
    node.members.some(m => m.name?.getText(caller) === 'openEpub'));
  assert.ok(service, 'Release import service must contain openEpub');
  const method = service.members.find(m => m.name?.getText(caller) === 'openEpub');
  const parserFile = cache.FileNameCache.EpubParserService || 'EpubParserService';
  const { ImportProbe } = evaluate(`export class ImportProbe { ${method.getText(caller)} }`, name => {
    assert.ok(name.endsWith(`/${parserFile}&`), 'dynamic import must resolve to the compiled parser module');
    return parser;
  });
  const result = await ImportProbe.openEpub({}, '/fixture.epub');
  assert.equal(result, handler);
  assert.equal(result.getBookInfo().bookCreator, '测试作者');
  assert.equal(result.getCover(), 'cover.jpg');
  assert.equal(result.getSpineList().length, 1);
  assert.equal(calls, 1);
  const readerCode = compiled('pages/ReaderPage');
  const componentCode = compiled('components/EpubReaderComponent');
  const component = ts.createSourceFile('reader.ts', componentCode, ts.ScriptTarget.Latest, true);
  const exports = new Set(component.statements.filter(node => node.modifiers?.some(m => m.kind === ts.SyntaxKind.ExportKeyword))
    .map(node => node.name?.getText(component)));
  for (const name of ['createEpubReaderController', 'createEpubReaderBuilder']) {
    assert.ok(readerCode.includes('.' + name + '('));
    assert.ok(exports.has(name), `Release reader export missing: ${name}`);
  }
  console.log('PASS: obfuscated EPUB import reaches parser and metadata/cover/chapters; reader dynamic exports match');
})().catch(error => { console.error(error); process.exitCode = 1; });
