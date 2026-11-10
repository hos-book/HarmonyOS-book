// Real TTS file importer/parser; file picker and platform I/O are simulated in memory.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const files = new Map(), handles = new Map(), modules = new Map();
let selected = [], active = 0, peak = 0, nextFd = 0, opened = [];
const io = {
  OpenMode: { READ_ONLY: 0 },
  async open(uri) {
    if (!files.has(uri)) throw new Error('unreadable');
    const fd = ++nextFd;
    handles.set(fd, { uri, position: 0 }); opened.push(uri);
    peak = Math.max(peak, ++active);
    return { fd };
  },
  async stat(fd) { return { size: files.get(handles.get(fd).uri).length }; },
  async read(fd, output, options) {
    const state = handles.get(fd), data = files.get(state.uri);
    await new Promise(resolve => setTimeout(resolve, state.uri === 'voice-0' ? 3 : 0));
    const count = Math.min(37, options?.length ?? output.byteLength, data.length - state.position);
    new Uint8Array(output).set(data.subarray(state.position, state.position + count));
    state.position += count;
    return count;
  },
  async close(file) { assert.ok(handles.delete(file.fd)); active--; }
};
const mocks = {
  '@kit.CoreFileKit': { fileIo: io, picker: {
    DocumentSelectOptions: class {},
    DocumentViewPicker: class {
      async select(options) { assert.equal(options.maxSelectNumber, 50); return selected; }
    }
  } },
  '@kit.ArkTS': { util: { TextDecoder: { create: (_encoding, options) => {
    const decoder = new TextDecoder('utf-8', options);
    return { decodeWithStream: bytes => decoder.decode(bytes) };
  } } } },
  '@kit.NetworkKit': { http: {} },
  '../rulesource/LocalRuleQuickJsRuntime': {}
};
function load(file) {
  if (modules.has(file)) return modules.get(file);
  const module = { exports: {} };
  modules.set(file, module.exports);
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, require: key =>
    mocks[key] || load(path.resolve(path.dirname(file), key + '.ets')) });
  return module.exports;
}
const { CustomTtsImportService: importer } = load(path.join(root, 'service/text/CustomTtsImportService.ets'));
const config = name => ({ name, url: 'https://tts.example/speak?text={{text}}' });
(async () => {
  for (let index = 0; index < 51; index++) files.set(`voice-${index}`, Buffer.from(JSON.stringify(config(`音色 ${index}`))));
  selected = [...files.keys()]; selected.unshift(selected[0]);
  let result = await importer.pick({});
  assert.equal(result.configs.length, 50); assert.equal(result.failedFiles, 1);
  assert.deepEqual(Array.from(result.configs, item => item.name), Array.from({ length: 50 }, (_, i) => `音色 ${i}`));
  assert.equal(opened.length, 50); assert.equal(peak, 4); assert.equal(active, 0); assert.equal(handles.size, 0);
  console.log('PASS 50-file cap, URI deduplication, four concurrent reads, short reads and deterministic order');

  files.set('bad-json', Buffer.from('{'));
  files.set('bad-utf8', Buffer.from([0xff, 0xfe, 0xff]));
  files.set('empty', Buffer.alloc(0));
  files.set('oversized', Buffer.alloc(1024 * 1024 + 1));
  files.set('multi', Buffer.from(JSON.stringify(Array.from({ length: 25 }, (_, i) => config(`目录 ${i}`)))));
  selected = ['bad-json', 'voice-0', 'bad-utf8', 'missing', 'empty', 'oversized', 'multi'];
  result = await importer.pick({});
  assert.equal(result.failedFiles, 5); assert.equal(result.configs.length, 26);
  assert.equal(result.configs[0].name, '音色 0'); assert.equal(result.configs[25].name, '目录 24');
  assert.equal(active, 0); assert.equal(handles.size, 0);
  selected = []; result = await importer.pick({});
  assert.equal(result.configs.length, 0); assert.equal(result.failedFiles, 0);
  console.log('PASS malformed/oversized/unreadable isolation, multi-voice JSON and canceled picker');
})().catch(error => { console.error(error); process.exitCode = 1; });
