// Transpile the real importer/parser with the installed Release SDK; simulate only HTTP and ArkTS URL APIs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
let calls = [], responses = [];
let browserResponses = [], systemResponses = [];
async function fallback(channel, address, queue) {
  calls.push({channel,address});
  const value = queue.shift();
  if (typeof value !== 'string') throw new Error('fallback unavailable');
  return value;
}
async function request(channel, address, options) {
  calls.push({ channel, address, options });
  const next = responses.shift();
  if (next instanceof Error) throw next;
  assert.ok(next, 'Unexpected HTTP request');
  return next;
}
const mocks = {
  './LocalRuleSourceDownloadService': {LocalRuleSourceDownloadService:{
    browser: address => fallback('web',address,browserResponses),
    system: address => fallback('download',address,systemResponses)}},
  './light/upstream/core/http/RawHttpTextClient': {RawHttpTextClient:{get:async () => {throw Error('raw unavailable');}}},
  '@kit.ArkTS': { buffer: Buffer, url: { URL: { parseURL: input => {
    const parsed = new URL(input);
    Object.defineProperty(parsed, 'params', { value: parsed.searchParams });
    return parsed;
  } } } },
  '../http/HttpClient': { HttpClient: {
    request: (address, options) => request('rcp', address, options),
    requestLegacy: (address, options) => request('http', address, options)
  } }
};
const cache = new Map();
function load(relative) {
  let file = path.join(root, relative);
  if (!fs.existsSync(file) && file.endsWith('.ets')) file = file.slice(0, -4) + '.ts';
  if (cache.has(file)) return cache.get(file);
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, Error, Map, Set,
    Trace: () => {}, ObservedV2: cls => cls,
    require: key => mocks[key] || load(path.relative(root, path.resolve(path.dirname(file), key + '.ets'))) });
  cache.set(file, module.exports);
  return module.exports;
}
const { LocalRuleSourceRemoteImporter: importer, RuleSourceRemoteImportFailure: failure,
  RuleSourceRemoteImportError: ImportError } = load('service/rulesource/LocalRuleSourceRemoteImporter.ets');
const { LocalRuleSourceImportParser: parser } = load('service/rulesource/LocalRuleSourceImportParser.ets');
const body = JSON.stringify({ value: [
  { bookSourceName: '测试导入定义', bookSourceUrl: '测试来源标识' },
  { bookSourceName: '通用规则示例', bookSourceUrl: 'https://source.example',
    searchUrl: '/search?q={{key}}', loginUi: [{ name: '登录', action: 'login()' }],
    loginUrl: 'function login() {}', jsLib: 'function helper() {}',
    ruleSearch: { bookList: '$.books', name: '$.name', bookUrl: '$.url' } }
] });
const subscription = 'https://subscription.example/sources?key=fixture%2Bvalue%26part&edition=2';
function reset(...values) { calls = []; responses = values; browserResponses=[];systemResponses=[]; }
const response = (body, statusCode = 200) => ({ body, statusCode, headers: {} });
async function rejected(values, expected, count = values.length) {
  reset(...values);
  await assert.rejects(importer.resolve(subscription), error => {
    assert.ok(error instanceof ImportError);
    assert.equal(error.failure, expected);
    assert.ok(!error.message.includes(subscription));
    return true;
  });
  assert.equal(calls.filter(c => ['rcp','http'].includes(c.channel)).length, count);
}
async function main() {
  reset();
  assert.equal(await importer.resolve(body), body);
  assert.equal(calls.length, 0);
  for (const route of ['legado://booksource', 'yuedu://booksource',
    'yuedu://booksource/importonline', 'legado://import/booksource',
    'legado://booksource/importonline/']) {
    const shared = `${route}?src=${encodeURIComponent(subscription)}`;
    reset(response('\uFEFF\n' + body));
    assert.ok(importer.isRemote(shared));
    const report = parser.parse(await importer.resolve(shared));
    assert.equal(report.sources.length, 2);
    assert.equal(report.sources[0].bookSourceUrl, '测试来源标识');
    assert.equal(report.sources[1].loginUrl, 'function login() {}');
    assert.equal(report.sources[1].jsLib, 'function helper() {}');
    assert.equal(report.sources[1].hasSearchCapability(), true);
    assert.equal(calls[0].address, subscription);
    assert.equal(calls[0].options.headers.Accept, 'application/json,text/plain,*/*');
    assert.equal(calls.length, 1);
  }
  for (const route of ['yuedu://booksource/importonline', 'legado://import/booksource']) {
    reset(response(body));
    await importer.resolve(`${route}?src=${encodeURIComponent(encodeURIComponent(subscription))}`);
    assert.equal(calls[0].address, subscription);
    assert.equal(calls.length, 1);
  }
  for (const value of ['legado://booksource', 'legado://rss?src=https%3A%2F%2Fexample.com',
    'yuedu://booksource?src=file%3A%2F%2Fprivate', 'https://user:password@example.com/sources',
    'legado://import/booksource/extra?src=https%3A%2F%2Fexample.com',
    'yuedu://booksource/importonline?src=https%253A%252F%252Fexample.com%25ZZ',
    'legado://import/booksource?src=' + encodeURIComponent('https://example.com/' + 'x'.repeat(16384))]) {
    reset();
    await assert.rejects(importer.resolve(value), e => e.failure === failure.ADDRESS);
    assert.equal(calls.length, 0);
  }
  for (const first of [new Error('transport failure'), response('', 502),
    response('<html>gateway</html>'), response('{broken')]) {
    reset(first, response(body));
    assert.equal(await importer.resolve(subscription), body);
    assert.deepEqual(calls.map(c => c.channel), ['rcp', 'http']);
    assert.ok(calls.every(c => c.address === subscription));
  }
  for (const code of [401, 403]) await rejected([response('', code),response('',code)], failure.AUTH);
  for (const code of [404, 410]) await rejected([response('', code),response('',code)], failure.NOT_FOUND);
  await rejected([response('<html>login</html>'), response('<html>login</html>')], failure.HTML);
  await rejected([response('{broken'), response('plain text')], failure.FORMAT);
  await rejected([new Error('offline'), new Error('offline')], failure.NETWORK);
  const oversized = '中'.repeat(Math.floor(importer.MAX_BYTES / 3) + 1);
  reset();
  await assert.rejects(importer.resolve(oversized), e => e.failure === failure.TOO_LARGE);
  assert.equal(calls.length, 0);
  await rejected([response(oversized)], failure.TOO_LARGE);
  reset(response('',403),response('<html>challenge</html>'));
  browserResponses.push(body);
  assert.equal(await importer.resolve(subscription),body);
  assert.deepEqual(calls.map(c => c.channel),['rcp','http','web']);
  reset(new Error('transport'),new Error('transport'));
  systemResponses.push(body);
  assert.equal(await importer.resolve(subscription),body);
  assert.deepEqual(calls.map(c => c.channel),['rcp','http','web','download']);
  console.log('PASS remote subscription import: sharing, parser handoff, fallback, errors, byte limits');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
