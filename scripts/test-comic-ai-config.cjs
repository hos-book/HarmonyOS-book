const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
function load(file, require) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, require, setInterval, clearInterval, URL, console });
  return exports;
}
const model = load('model/ComicAiConfig.ets', () => ({}));
const translationModel = load('model/ComicTranslation.ets', () => ({}));
const requests = [], configurations = [];
const saved = new Map();
let failSave = false, closeCount = 0, responses = [], cancelled = false;
const store = {
  execute: async sql => { if (sql.startsWith('DELETE')) saved.delete(Number(sql.match(/id = (\d+)/)[1])); },
  querySql: async sql => {
    if (sql.startsWith('PRAGMA')) return { goToNextRow: () => false, close() {} };
    const row = saved.get(Number(sql.match(/id = (\d+)/)[1]));
    return { goToFirstRow: () => !!row,
      getString: n => [row.base_url, row.api_key, row.model, row.model_list][n], close() {} };
  },
  insert: async (_table, values) => { if (failSave) throw Error('disk full'); saved.set(values.id, { ...values }); }
};
const rcp = {
  Request: class { constructor(address, method, headers, content) { Object.assign(this, { address, method, headers, content }); } },
  createSession: () => ({
    cancel() { cancelled = true; }, close() { closeCount++; },
    async fetch(request) {
      requests.push(request);
      assert.equal(request.configuration.transfer.autoRedirect, false);
      const response = responses.shift();
      if (response.error) throw Error(response.error);
      if (response.cancel) response.cancel();
      const body = new TextEncoder().encode(response.body || JSON.stringify(response.json));
      request.configuration.tracing.httpEventsHandler.onDataReceive(body.buffer);
      if (cancelled) { cancelled = false; throw Error('cancelled'); }
      return { statusCode: response.status || 200 };
    }
  })
};
const { ComicAiConfigService: service } = load('service/ComicAiConfigService.ets', name => {
  if (name.endsWith('ComicTranslation')) return translationModel;
  if (name.endsWith('ComicAiConfig')) return model;
  if (name === '@kit.ArkTS') return { url: { URL }, util: {
    TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } },
    Base64Helper: class { decodeSync(text) { return new Uint8Array(Buffer.from(text, 'base64')); } },
    TextDecoder: class {
    decodeWithStream(bytes) { return new TextDecoder().decode(bytes); }
  } } };
  if (name === '@kit.RemoteCommunicationKit') return { rcp };
  if (name === '@kit.ArkData') return { relationalStore: {
    SecurityLevel: { S2: 2 }, ConflictResolution: { ON_CONFLICT_REPLACE: 1 },
    getRdbStore: async (_ctx, config) => { configurations.push(config); return store; }
  } };
  return {};
});
(async () => {
  assert.equal(service.normalizeBase(' https://example.test/v1/ '), 'https://example.test/v1');
  assert.equal(service.normalizeBase('https://example.test'), 'https://example.test/v1');
  assert.equal(service.normalizeBase('https://example.test/proxy/v1/models'), 'https://example.test/proxy/v1');
  for (const value of ['file:///tmp/a', 'https://key:secret@example.test', 'https://example.test?key=secret']) {
    assert.throws(() => service.normalizeBase(value), /invalid_url/);
  }
  const initial = await service.load({});
  assert.deepEqual([initial.baseUrl, initial.apiKey, initial.model], ['', '', '']);
  assert.equal(configurations[0].encrypt, true);
  assert.equal(configurations[0].allowRebuild, false);
  const draft = new model.ComicAiConfig();
  draft.baseUrl = 'https://example.test'; draft.apiKey = 'fixture-key'; draft.model = 'my-model';
  draft.models = ['chat', 'my-model'];
  await service.save({}, draft);
  const restored = await service.load({});
  assert.deepEqual([restored.baseUrl, restored.apiKey, restored.model], ['https://example.test/v1', 'fixture-key', 'my-model']);
  assert.deepEqual(Array.from(restored.models), ['chat', 'my-model'], 'the complete fetched model list survives reopening');
  assert.equal(service.translate, undefined, 'online translation API was removed');
  failSave = true;
  const replacement = new model.ComicAiConfig();
  replacement.baseUrl = 'https://another.test'; replacement.apiKey = 'replacement-key';
  await assert.rejects(service.save({}, replacement));
  assert.equal((await service.load({})).apiKey, 'fixture-key', 'failed save retains the previous row');
  failSave = false;
  responses = [
    { json: { data: [{ id: 'chat' }, { id: 'gpt-image-fixture' }], has_more: true, last_id: 'cursor' } },
    { json: { data: [{ id: 'chat' }, { id: 'custom' }] } }
  ];
  assert.deepEqual(Array.from(await service.models(draft, () => false)), ['gpt-image-fixture', 'chat', 'custom']);
  assert.ok(requests.at(-1).address.endsWith('?after=cursor'));
  assert.equal(draft.model, 'my-model', 'model discovery never changes the selected model');
  assert.equal(requests[0].headers.Authorization, 'Bearer fixture-key');
  for (const [status, message] of [[401, 'unauthorized'], [403, 'forbidden'], [404, 'not_found'], [429, 'rate_limited'], [302, 'request_failed']]) {
    responses = [{ status, json: { secret: 'fixture-key' } }];
    await assert.rejects(service.models(draft, () => false), new RegExp('comic_ai_' + message));
  }
  responses = [{ error: 'network failed; Authorization: fixture-key' }];
  await assert.rejects(service.models(draft, () => false), error => !error.message.includes('fixture-key'));
  responses = [{ body: '<html>login</html>' }];
  await assert.rejects(service.models(draft, () => false), /invalid_response/);
  responses = [{ json: { data: [{ id: 'same' }], has_more: true } }, { json: { data: [{ id: 'same' }], has_more: true } }];
  await assert.rejects(service.models(draft, () => false), /invalid_response/, 'repeating pagination cannot loop');
  responses = [{ body: 'x'.repeat(2 * 1024 * 1024 + 1) }];
  await assert.rejects(service.models(draft, () => false), /models_too_large/);
  let stop = false;
  responses = [{ json: { data: [{ id: 'stale' }] }, cancel: () => { stop = true; } }];
  await assert.rejects(service.models(draft, () => stop), /cancelled/);
  assert.equal(closeCount, requests.length, 'sessions are released after success, failure and cancellation');
  responses = [{ json: { data: [{ b64_json: Buffer.from('colored-image').toString('base64') }] } }];
  const colored = await service.edit(draft, new Uint8Array([255, 216, 255]).buffer, () => false);
  assert.equal(Buffer.from(colored).toString(), 'colored-image');
  const edit = requests.at(-1);
  assert.equal(edit.method, 'POST');
  assert.equal(edit.address, 'https://example.test/v1/images/edits');
  const posted = Buffer.from(edit.content).toString();
  assert.ok(posted.includes('name="model"\r\n\r\nmy-model'));
  assert.ok(posted.includes('name="image"; filename="page.jpg"'));
  assert.ok(!posted.includes('fixture-key'), 'the secret is sent only in the authorization header');
  responses = [{ json: { data: [{ url: 'https://cdn.test/result.png' }] } }, { body: 'image-data' }];
  await service.edit(draft, new ArrayBuffer(4), () => false);
  assert.equal(requests.at(-1).headers.Authorization, undefined, 'API keys never go to image CDN URLs');
  responses = [{ status: 400, json: {} }];
  await assert.rejects(service.edit(draft, new ArrayBuffer(4), () => false), /edit_unsupported/);
  responses = [{ status: 503, json: {} }];
  await assert.rejects(service.edit(draft, new ArrayBuffer(4), () => false), /model_unavailable/);
  await service.clear({});
  assert.equal((await service.load({})).apiKey, '');
  console.log('comic AI config: encrypted color configuration, model discovery, bounded requests and removed online translation passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
