const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { randomUUID } = require('node:crypto');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/WebDavBackupService.ets'), 'utf8');
const code = ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021, experimentalDecorators: true
} }).outputText;
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'listenbook-webdav-'));

function fixture() {
  const dir = fs.mkdtempSync(path.join(root, 'case-'));
  const context = { cacheDir: path.join(dir, 'cache'), filesDir: path.join(dir, 'files') };
  fs.mkdirSync(context.cacheDir); fs.mkdirSync(context.filesDir);
  const calls = [], remote = new Map(), handles = new Map();
  const control = { status: 0, failMethod: '', restores: 0, saves: 0, oversized: false, onRequest: null, safetyFailure: false };
  const auth = { dataOperation: false, beginDataOperation(requireLogin) {
    assert.equal(requireLogin, false);
    if (this.dataOperation) throw new Error('busy'); this.dataOperation = true;
  }, endDataOperation() { this.dataOperation = false; } };
  let config;
  const snapshot = { version: 2, exportedAt: 100, preferences: { favorites: ['book'] }, ruleSources: [] };
  const rcp = {
    Request: class { constructor(address, method, headers, content) { Object.assign(this, { address, method, headers, content }); } },
    createSession() { let closed = false; return { close() { closed = true; }, async fetch(req) {
      calls.push(req);
      assert.equal(req.configuration.transfer.autoRedirect, false);
      assert.equal(req.configuration.security.remoteValidation, 'system');
      assert.equal(req.headers.Authorization, 'Basic ' + Buffer.from('reader:密钥').toString('base64'));
      await control.onRequest?.(req);
      if (closed) throw new Error('cancelled');
      let status = 200, data = '';
      if (control.failMethod === req.method) status = control.status || 500;
      else if (req.method === 'PROPFIND') status = 207;
      else if (req.method === 'PUT') { remote.set(req.address, req.content); status = 201; }
      else if (req.method === 'MOVE') {
        assert.ok(remote.has(req.address));
        remote.set(req.headers.Destination, remote.get(req.address)); remote.delete(req.address); status = 204;
      } else if (req.method === 'DELETE') { remote.delete(req.address); status = 204; }
      else if (req.method === 'GET') { if (!remote.has(req.address)) status = 404; else data = remote.get(req.address); }
      if (control.oversized && req.method === 'GET') {
        for (let i = 0; i < 33; i++) { req.destination(new ArrayBuffer(1024 * 1024)); if (closed) throw new Error('closed'); }
      } else if (data) {
        const bytes = new TextEncoder().encode(data);
        for (let offset = 0; offset < bytes.length; offset += 7) req.destination(bytes.slice(offset, offset + 7).buffer);
      }
      return { statusCode: status };
    } }; }
  };
  const fileIo = {
    OpenMode: { CREATE: fs.constants.O_CREAT, WRITE_ONLY: fs.constants.O_WRONLY, TRUNC: fs.constants.O_TRUNC },
    readText: async p => fs.readFileSync(p, 'utf8'), unlink: async p => fs.unlinkSync(p),
    open: async (p, flags) => { const file = { fd: fs.openSync(p, flags) }; handles.set(file.fd, file); return file; },
    write: async (fd, bytes) => fs.writeSync(fd, new Uint8Array(bytes), 0, Math.min(11, bytes.byteLength)),
    close: async file => { fs.closeSync(file.fd); handles.delete(file.fd); }, fsync: async fd => fs.fsyncSync(fd)
  };
  const app = {
    createSnapshot: async (_context, file, strict) => {
      assert.equal(strict, true); if (control.safetyFailure && file.includes('before_')) throw new Error('disk full');
      fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(snapshot)); control.saves++;
    },
    readSnapshot: async file => { const value = JSON.parse(fs.readFileSync(file, 'utf8')); if (value.version !== 2) throw new Error('invalid'); return value; },
    restoreSnapshot: async (_context, file, strict) => {
      assert.equal(strict, true); assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')), snapshot);
      assert.ok(fs.existsSync(path.join(context.filesDir, 'backup/before_webdav_restore.json')));
      control.restores++; return true;
    }
  };
  const mocks = {
    '@kit.ArkTS': { url: { URL: { parseURL: value => new URL(value) } }, util: { generateRandomUUID: randomUUID,
      TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } },
      Base64Helper: class { encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); } } } },
    '@kit.ArkData': { relationalStore: { SecurityLevel: { S2: 2 }, async getRdbStore(_context, options) {
      assert.equal(options.encrypt, true); assert.equal(options.allowRebuild, false);
      return { async executeSql(sql, values) {
        if (sql.startsWith('INSERT')) config = values;
        if (sql.startsWith('DELETE')) config = undefined;
      }, async querySql() { return { goToFirstRow: () => !!config, getString: i => config[i], close() {} }; } };
    } } },
    '@kit.CoreFileKit': { fileIo }, '@kit.RemoteCommunicationKit': { rcp },
    './AuthService': { AuthService: { instance: auth } }, './AppBackupService': { AppBackupService: app }
  };
  const exports = {};
  vm.runInNewContext(code, { exports, require: name => mocks[name] || {}, ObservedV2: value => value,
    Trace() {}, ArrayBuffer, Uint8Array, Error, console });
  const service = exports.WebDavBackupService.instance;
  const settings = new exports.WebDavSettings(); Object.assign(settings, { address: 'https://dav.test/dav/', username: 'reader', password: '密钥' });
  const target = settings.address + 'listenbook-backup.json';
  const settled = () => { assert.equal(service.busy, false); assert.equal(auth.dataOperation, false);
    assert.equal(handles.size, 0); assert.deepEqual(fs.readdirSync(context.cacheDir), []); };
  return { ...exports, service, settings, context, target, calls, remote, control, auth, snapshot, settled };
}

(async () => {
  const f = fixture();
  await f.service.saveSettings(f.context, f.settings);
  assert.equal((await f.service.loadSettings(f.context)).password, '密钥');
  await f.service.clearSettings(f.context);
  assert.equal((await f.service.loadSettings(f.context)).password, '');
  for (const address of ['file:///tmp', 'https://user:pass@dav.test/', 'https://dav.test/?token=1', 'https://dav.test/#x']) {
    assert.throws(() => f.WebDavBackupService.normalize({ ...f.settings, address }), e => e.code === f.WebDavErrorCode.CONFIG);
  }
  await f.service.test(f.settings); f.settled();
  f.remote.set(f.target, 'previous');
  await f.service.backup(f.context, f.settings);
  assert.equal(JSON.parse(f.remote.get(f.target)).version, 2);
  assert.deepEqual(f.calls.slice(-2).map(c => c.method), ['PUT', 'MOVE']);
  assert.equal(f.remote.size, 1); f.settled();
  for (const method of ['PUT', 'MOVE']) {
    f.remote.set(f.target, 'previous'); f.control.failMethod = method;
    await assert.rejects(f.service.backup(f.context, f.settings));
    assert.equal(f.remote.get(f.target), 'previous'); assert.equal(f.remote.size, 1); f.settled();
  }
  f.control.failMethod = '';
  f.remote.set(f.target, JSON.stringify(f.snapshot));
  assert.equal(await f.service.restore(f.context, f.settings, async () => false), false);
  assert.equal(f.control.restores, 0); f.settled();
  assert.equal(await f.service.restore(f.context, f.settings, async () => {
    await assert.rejects(f.service.test(f.settings)); assert.equal(f.auth.dataOperation, true); return true;
  }), true);
  assert.equal(f.control.restores, 1); f.settled();
  f.remote.set(f.target, '{broken');
  await assert.rejects(f.service.restore(f.context, f.settings, async () => { throw new Error('must not confirm'); }),
    e => e.code === f.WebDavErrorCode.INVALID); f.settled();
  f.control.oversized = true;
  await assert.rejects(f.service.restore(f.context, f.settings, async () => true), e => e.code === f.WebDavErrorCode.TOO_LARGE);
  f.control.oversized = false; f.settled();
  for (const status of [401, 403, 404, 302, 500]) {
    f.control.failMethod = 'GET'; f.control.status = status;
    await assert.rejects(f.service.restore(f.context, f.settings, async () => true)); f.settled();
  }
  f.control.failMethod = ''; f.remote.set(f.target, JSON.stringify(f.snapshot));
  f.control.onRequest = async req => { if (req.method === 'PUT') f.service.cancel(); };
  await assert.rejects(f.service.backup(f.context, f.settings), e => e.code === f.WebDavErrorCode.CANCELLED);
  f.settled(); assert.equal(f.remote.size, 1);
  f.control.onRequest = null; f.control.safetyFailure = true;
  await assert.rejects(f.service.restore(f.context, f.settings, async () => true));
  assert.equal(f.control.restores, 1); f.settled();
  console.log('PASS WebDAV configuration isolation, authentication, bounded streaming, atomic publication, failure cleanup, cancellation, confirmation, safety snapshot and operation lock');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => fs.rmSync(root, { recursive: true, force: true }));
