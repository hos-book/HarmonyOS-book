// Real import parser/orchestrator; platform file I/O, taskpool and persistence are simulated.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
let files = new Map(), handles = new Map(), positions = new Map(), writes = [], opened = [], yields = 0, active = 0, peak = 0;
const io = {
  OpenMode: { READ_ONLY: 0 },
  async open(uri) {
    if (!files.has(uri)) throw new Error('unreadable');
    opened.push(uri); handles.set(uri, files.get(uri)); positions.set(uri, 0);
    peak = Math.max(peak, ++active); return { fd: uri };
  },
  async stat(fd) { return { size: handles.get(fd).length }; },
  async read(fd, output, options) {
    const data = handles.get(fd);
    // Simulate short reads to ensure files are fully reconstructed.
    // CoreFileKit offset is relative to the CURRENT file pointer, not an absolute position.
    const start = positions.get(fd) + (options?.offset || 0);
    const length = Math.max(0, Math.min(4093, output.byteLength, data.length - start));
    new Uint8Array(output).set(data.subarray(start, start + length));
    positions.set(fd, start + length);
    return length;
  },
  async close(file) { assert.ok(handles.delete(file.fd)); active--; }
};
const mocks = {
  '@kit.CoreFileKit': { fileIo: io },
  '@kit.ArkTS': { buffer: Buffer, taskpool: { execute: async (fn, ...args) => fn(...args) } },
  '../../utils/CharsetCodec': { CharsetCodec: { decodeBuffer: b => Buffer.from(b).toString('utf8') } },
  './LocalRuleSourceImportService': { LocalRuleSourceImportService: { importSources: async sources => {
    if (sources.some(s => s.bookSourceUrl === 'https://write-failure')) throw new Error('db failure');
    let count = 0;
    for (const source of sources) {
      assert.equal(typeof source.canExecute, 'function');
      if (source.bookSourceUrl === 'https://locked') continue;
      writes.push(source); count++;
    }
    return count;
  } } }
};
const cache = new Map();
function load(file) {
  if (!fs.existsSync(file) && file.endsWith('.ets')) file = file.slice(0,-4)+'.ts';
  if (cache.has(file)) return cache.get(file);
  const module = { exports: {} };
  const source = fs.readFileSync(file, 'utf8').replace(/^@Concurrent\s*$/gm, '');
  const code = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, Trace: () => {}, ObservedV2: cls => cls, setTimeout: fn => {
    yields++; return setImmediate(fn);
  }, require: key => mocks[key] || load(path.resolve(path.dirname(file), `${key}.ets`)) });
  cache.set(file, module.exports); return module.exports;
}
const { LocalRuleSourceFileImporter: importer } = load(path.join(root,
  'service/rulesource/LocalRuleSourceFileImporter.ets'));
const source = id => ({ bookSourceName: `书源 ${id}`, bookSourceUrl: `https://${id}` });
function reset(entries) {
  files = new Map(entries.map(([uri, body]) => [uri, Buffer.from(body)]));
  handles = new Map(); positions = new Map(); writes = []; opened = []; yields = 0; active = 0; peak = 0;
}
async function run(uris = [...files.keys()]) {
  const result = await importer.importFiles(uris, () => {});
  assert.equal(active, 0); assert.equal(handles.size, 0); assert.ok(peak <= 1);
  return result;
}
(async () => {
  reset([['a', JSON.stringify(source('a'))], ['bad', '{'], ['empty', ''],
    ['locked', JSON.stringify(source('locked'))], ['b', JSON.stringify([source('b')])]]);
  let result = await run(['a', 'a', 'bad', 'missing', 'empty', 'locked', 'b']);
  assert.equal(result.imported, 2); assert.equal(result.skippedFiles, 3);
  assert.equal(result.skippedSources, 1); assert.equal(opened.filter(x => x === 'a').length, 1);
  reset(Array.from({ length: 12 }, (_, i) => [String(i), JSON.stringify(source(i))]));
  result = await run(); assert.equal(result.imported, 10); assert.equal(result.skippedFiles, 2);
  reset([['large', ' '.repeat(importer.MAX_FILE_BYTES + 1)], ['ok', JSON.stringify(source('ok'))]]);
  result = await run(); assert.equal(result.imported, 1); assert.equal(result.skippedFiles, 1);
  reset([['batch', JSON.stringify(Array.from({ length: 20 }, (_, i) => source(i)))],
    ['ok', JSON.stringify(source('ok'))]]);
  result = await run();
  assert.equal(result.imported, 21);
  assert.equal(result.skippedFiles, 0);
  reset(Array.from({ length: 6 }, (_, i) => [String(i),
    JSON.stringify(source(i)) + ' '.repeat(importer.MAX_FILE_BYTES - Buffer.byteLength(JSON.stringify(source(i))))]));
  result = await run(); assert.equal(result.imported, 6); assert.equal(result.skippedFiles, 0);
  assert.equal(result.budgetFiles, 0);
  reset([['a', JSON.stringify(Array.from({ length: 600 }, (_, i) => source(i)))],
    ['b', JSON.stringify(Array.from({ length: 600 }, (_, i) => source(i + 600)))],
    ['c', JSON.stringify(source('last'))]]);
  result = await run(); assert.equal(result.imported, 1201);
  assert.equal(result.skippedSources, 0); assert.equal(result.skippedFiles, 0); assert.ok(yields > 100);
  reset([['fail', JSON.stringify(source('write-failure'))], ['ok', JSON.stringify(source('ok'))]]);
  result = await run(); assert.equal(result.imported, 1); assert.equal(result.skippedFiles, 1);
  console.log('PASS multi-file import: limits, short reads, serial handles, malformed/unreadable files, locked sources, write failure isolation, yielding and model methods');
})().catch(error => { console.error(error); process.exitCode = 1; });
