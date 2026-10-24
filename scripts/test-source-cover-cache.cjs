// Run production cache/dispatcher code; count actual materializations across simulated page/process lifetimes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
function load(file, mocks = {}, globals = {}) {
  const exports = {};
  const code = ts.transpileModule(fs.readFileSync(path.join(root, file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { exports, require: name => mocks[name] || {}, console, ...globals });
  return exports;
}
const { SourceCoverUrl } = load('service/rulesource/light/upstream/core/nativesource/SourceCoverUrl.ts');
async function run() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'source-cover-'));
  const fileApi = {
    accessSync: fs.existsSync, mkdirSync: p => fs.mkdirSync(p, { recursive: true }),
    listFileSync: fs.readdirSync,
    statSync: p => { const s = typeof p === 'number' ? fs.fstatSync(p) : fs.statSync(p); return { size: s.size, mtime: s.mtimeMs }; },
    unlinkSync: fs.unlinkSync, OpenMode: { CREATE: 0, WRITE_ONLY: 0, TRUNC: 0 },
    openSync: p => ({ fd: fs.openSync(p, 'w') }),
    writeSync: (fd, buffer) => fs.writeSync(fd, Buffer.from(buffer)),
    closeSync: file => fs.closeSync(typeof file === 'number' ? file : file.fd)
  };
  const cacheMocks = {
    '@ohos.file.fs': { default: fileApi },
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(value) { return Buffer.from(value); } } } },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd() {
      const hash = crypto.createHash('sha256');
      return { async update({ data }) { hash.update(data); }, async digest() { return { data: hash.digest() }; } };
    } } }
  };
  const restart = () => load('service/rulesource/light/LightSourceCoverCache.ts', cacheMocks,
    { AppStorage: { get: () => temp } }).LightSourceCoverCache;
  try {
    let downloads = 0;
    const download = async () => { downloads++; return new Uint8Array([1, 2, 3]); };
    const first = await restart().materialize('source-a:login-1:definition-1:url', download);
    assert.equal(await restart().materialize('source-a:login-1:definition-1:url', download), first);
    assert.equal(downloads, 1, 'process restart reuses disk bytes without download/decryption');
    const changed = await restart().materialize('source-a:login-2:definition-1:url', download);
    assert.notEqual(changed, first, 'login identity isolates cached files');
    fs.unlinkSync(first.replace('file://', ''));
    await restart().materialize('source-a:login-1:definition-1:url', download);
    assert.equal(downloads, 3, 'deleted cache is fetched again');

    let revision = 0, reads = 0, materializations = 0, installed = true;
    const raw = SourceCoverUrl.wrap('https://cover.test/a.jpg', 'https://source.test');
    const mocks = {
      '@ohos.file.fs': { default: fileApi },
      './rulesource/light/upstream/core/nativesource/SourceCoverUrl': { SourceCoverUrl },
      './rulesource/LocalRuleSourceRepository': { LocalRuleSourceRepository: {
        getCoverRevision: () => revision,
        get: async () => { reads++; return installed ? { bookSourceUrl: 'https://source.test' } : undefined; },
        getCoverSessionKey: async () => 'stable-login'
      } },
      './rulesource/light/LightSourceBridge': { LightSourceBridge: { cover: async () => {
        materializations++;
        fs.writeFileSync(first.replace('file://', ''), 'cover');
        return first;
      } } }
    };
    const { SourceCoverService: service } = load('service/SourceCoverService.ets', mocks);
    assert.deepEqual(Array.from(await Promise.all([service.resolve(raw), service.resolve(raw)])), [first, first]);
    assert.equal(reads, 1, 'home/detail requests share the in-flight source read');
    for (let i = 0; i < 20; i++) assert.equal(await service.resolve(raw), first);
    assert.equal(reads, 1, 'rebuilding shelf cards does not read or parse the source again');
    assert.equal(materializations, 1, 'repeated display skips the bridge and hashing');
    fs.unlinkSync(first.replace('file://', ''));
    assert.equal(service.cached(raw), '');
    await service.resolve(raw);
    assert.equal(materializations, 2, 'cleared disk cache is recreated');
    service.invalidate(raw);
    assert.equal(fs.existsSync(first.replace('file://', '')), false);
    await service.resolve(raw);
    assert.equal(materializations, 3, 'image decode failure permits one fresh materialization');
    revision++;
    await service.resolve(raw);
    assert.equal(materializations, 4, 'definition/login changes invalidate the in-memory shortcut');
    revision++; installed = false;
    await assert.rejects(service.resolve(raw), /no longer installed/);
    assert.equal(service.cached(raw), '', 'deleted sources cannot resolve old cached covers');
    console.log('PASS: process restart, page reuse, concurrent requests, deletion, decode retry and source/session invalidation');
  } finally { fs.rmSync(temp, { recursive: true, force: true }); }
}
run().catch(error => { console.error(error); process.exitCode = 1; });
