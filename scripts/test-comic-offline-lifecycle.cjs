const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
function load(relative, mocks, component = false) {
  let source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', relative), 'utf8');
  if (component) source = source.replace('@ComponentV2', '').replace('export struct ', 'export class ')
    .split('\n  build() {')[0] + '\n}';
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, Error, setTimeout, canIUse: () => true,
    WebResourceResponse: Response, require: name => mocks[name] ?? {} });
  return exports;
}
let failTransfer = false;
class Response {
  setResponseData(data) { if (typeof data === 'number' && failTransfer) throw Error('transfer failed'); this.data = data; }
  setResponseCode(code) { this.code = code; }
  setReasonMessage() {} setResponseMimeType() {} setResponseEncoding() {} setResponseHeader() {}
}
const { ComicOfflineTranslationService: service } = load('service/ComicOfflineTranslationService.ets', {});
const owned = new Set();
let nextFd = 100;
const { ComicOfflineTranslationHost: Host } = load('components/ComicOfflineTranslationHost.ets', {
  '@kit.ArkWeb': { webview: { WebviewController: class {} } },
  '@kit.CoreFileKit': { fileIo: {
    OpenMode: { READ_ONLY: 0 },
    openSync() { owned.add(++nextFd); return { fd: nextFd }; },
    closeSync(file) { assert.ok(owned.delete(file.fd), 'must not close a transferred/reused fd'); }
  } },
  '../service/ComicTranslationModelService': { ComicTranslationModelService: { localPath: () => '/models/config.json' } },
  '../service/ComicOfflineTranslationService': { ComicOfflineTranslationService: service }
}, true);
(async () => {
  const host = new Host();
  host.getUIContext = () => ({ getHostContext: () => ({}) });
  const response = host.response(service.ORIGIN + 'models/en-zh/config.json');
  assert.equal(response.code, 200);
  assert.ok(owned.delete(response.data), 'Web consumes and closes the transferred fd');
  host.aboutToDisappear();
  failTransfer = true;
  assert.equal(host.response(service.ORIGIN + 'models/en-zh/config.json').code, 404);
  assert.equal(owned.size, 0, 'failed transfer closes the application-owned fd');

  const items = [{ id: 1, text: 'Hello' }];
  let cancelCalls = 0;
  const detached = { async runJavaScript(script) {
    if (script.includes('typeof')) return 'true';
    if (script.includes('.start')) return 'true';
    if (script.includes('.cancel')) { cancelCalls++; throw Error('destroyed Web'); }
    service.detach(detached);
    return JSON.stringify({ id: 1, status: 'done', translations: [{ id: 1, text: '你好' }] });
  } };
  service.attach(detached);
  await assert.rejects(service.translate(items, 'en-zh', () => true), /cancelled/);
  assert.equal(cancelCalls, 0, 'no late JS call after detach, and no stale success');
  let active = true;
  const attached = { async runJavaScript(script) {
    if (script.includes('typeof') || script.includes('.start')) return 'true';
    if (script.includes('.cancel')) { cancelCalls++; return ''; }
    active = false;
    return '{}';
  } };
  service.attach(attached);
  await assert.rejects(service.translate(items, 'en-zh', () => active), /cancelled/);
  assert.equal(cancelCalls, 1, 'an attached cancelled job still stops its Worker');
  service.detach(attached);
  console.log('comic offline lifecycle: Web FD ownership, transfer failure, detach and cancellation passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
