const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
const resource = (id, ...args) => ({ id, args });
function load(relative, mocks) {
  const source = fs.readFileSync(path.join(root, relative), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
  const exports = {};
  vm.runInNewContext(code, { exports, require: name => { assert.ok(name in mocks, name); return mocks[name]; },
    Error, ArrayBuffer, Uint8Array, Set, Map, $r: resource });
  return exports;
}
const model = load('model/JianjianAi.ets', {});
const { JianjianAiConfig, JianjianAiMessage, JianjianAiErrorCode: C } = model;
function fixture() {
  const calls = [];
  let record;
  const control = { status: 200, body: JSON.stringify({ data: [{ id: 'z-text' }, { id: 'embedding-model' }, { id: 'z-text' }] }),
    gate: undefined, failStore: false, oversized: false, closed: 0, responses: [] };
  const rcp = {
    Request: class { constructor(address, method, headers, body) { Object.assign(this, { address, method, headers, body }); } },
    createSession() {
      let closed = false;
      return { close() { if (!closed) control.closed++; closed = true; }, async fetch(request) {
        calls.push(request);
        assert.equal(request.configuration.transfer.autoRedirect, false);
        assert.equal(request.configuration.security.remoteValidation, 'system');
        await control.gate?.();
        if (closed) throw new Error('cancelled');
        if (control.oversized) {
          request.destination(new ArrayBuffer(2 * 1024 * 1024 + 1));
          throw new Error('closed');
        }
        const body = control.responses.length ? control.responses.shift() : control.body;
        const bytes = new TextEncoder().encode(body);
        for (let i = 0; i < bytes.length; i += 7) request.destination(bytes.slice(i, i + 7).buffer);
        return { statusCode: control.status };
      } };
    }
  };
  const mocks = {
    '../model/JianjianAi': model,
    '@kit.ArkTS': { url: { URL: { parseURL: value => new URL(value) } },
      util: { TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) } } },
    '@kit.RemoteCommunicationKit': { rcp },
    '@kit.ArkData': { relationalStore: { SecurityLevel: { S2: 2 }, async getRdbStore(_context, options) {
      assert.equal(options.encrypt, true); assert.equal(options.allowRebuild, false);
      return { async executeSql(sql, values) {
        if (control.failStore) throw new Error('disk failure');
        if (sql.startsWith('INSERT')) record = [...values];
        if (sql.startsWith('DELETE')) record = undefined;
      }, async querySql() { return { goToFirstRow: () => !!record, getString: i => record[i], close() {} }; } };
    } } }
  };
  const { JianjianAiService: Service } = load('service/JianjianAiService.ets', mocks);
  const config = new JianjianAiConfig();
  Object.assign(config, { address: 'https://provider.test/v1/', apiKey: 'test-key', model: 'z-text' });
  return { Service, client: new Service(), config, control, calls };
}

(async () => {
  const { Service, client, config, control, calls } = fixture();
  for (const [input, expected] of [
    ['https://provider.test', 'https://provider.test/v1'],
    ['https://provider.test/v1/', 'https://provider.test/v1'],
    ['https://provider.test/openai/v1/chat/completions', 'https://provider.test/openai/v1'],
    ['http://127.0.0.1:8080/v1/models', 'http://127.0.0.1:8080/v1'],
    ['https://provider.test/compatible-mode/v1', 'https://provider.test/compatible-mode/v1']
  ]) {
    const value = Object.assign(new JianjianAiConfig(), config, { address: input });
    assert.equal(Service.normalize(value).address, expected);
  }
  for (const address of ['file:///tmp/key', 'https://user:pass@provider.test/v1', 'https://provider.test/v1?key=x', 'https://provider.test/v1#key']) {
    assert.throws(() => Service.normalize(Object.assign(new JianjianAiConfig(), config, { address })), e => e.code === C.CONFIG);
  }
  assert.throws(() => Service.normalize(Object.assign(new JianjianAiConfig(), config, { apiKey: 'x\r\nHeader: y' })), e => e.code === C.CONFIG);
  assert.throws(() => Service.normalize(Object.assign(new JianjianAiConfig(), config, { model: '' }), true), e => e.code === C.MODEL);
  await Service.saveConfig({}, config);
  const loaded = await Service.loadConfig({});
  assert.equal(loaded.apiKey, config.apiKey); assert.equal(loaded.model, config.model);
  control.failStore = true;
  await assert.rejects(Service.saveConfig({}, Object.assign(new JianjianAiConfig(), config, { model: 'changed' })));
  control.failStore = false;
  assert.equal((await Service.loadConfig({})).model, config.model);
  await Service.clearConfig({}); assert.equal((await Service.loadConfig({})).apiKey, '');
  const models = await client.listModels(config);
  assert.deepEqual(Array.from(models), ['embedding-model', 'z-text'], 'do not filter providers or model families');
  assert.equal(calls[0].address, 'https://provider.test/v1/models');
  assert.equal(calls[0].headers.Authorization, 'Bearer test-key');
  assert.throws(() => Service.parseModels('{"models":[]}'), e => e.code === C.INVALID);
  assert.equal(Service.parseModels('{"data":[]}').length, 0);
  control.body = JSON.stringify({ choices: [{ message: { content: '你好，一起读书吧。' } }] });
  const messages = Array.from({ length: 40 }, (_, i) => new JianjianAiMessage(i % 2 ? 'assistant' : 'user', 'turn-' + i));
  messages.push(new JianjianAiMessage('user', '聊聊阅读'));
  assert.equal(await client.chat(config, messages, 'Only user-provided conversation.'), '你好，一起读书吧。');
  const request = calls.at(-1);
  assert.equal(request.address, 'https://provider.test/v1/chat/completions');
  const body = JSON.parse(request.body);
  assert.equal(body.model, 'z-text'); assert.equal(body.stream, false);
  assert.ok(body.messages.length <= 21); assert.equal(body.messages[1].role, 'user');
  assert.equal(body.messages.at(-1).content, '聊聊阅读');
  assert.deepEqual(Object.keys(body).sort(), ['messages', 'model', 'stream']);
  assert.ok(!request.body.includes('test-key'));
  assert.throws(() => Service.parseReply('{"choices":[]}'), e => e.code === C.INVALID);
  assert.throws(() => Service.parseReply('{"choices":[{"message":{"content":null}}]}'), e => e.code === C.INVALID);
  assert.equal(Service.parseReply('{"choices":[{"message":{"content":null,"refusal":"无法回答"}}]}'), '无法回答');
  for (const [status, code] of [[401,C.AUTH],[403,C.AUTH],[404,C.ENDPOINT],[429,C.LIMIT],[500,C.SERVER],[302,C.SERVER]]) {
    control.status = status;
    await assert.rejects(client.listModels(config), e => e.code === code);
  }
  control.status = 200; control.oversized = true;
  await assert.rejects(client.listModels(config), e => e.code === C.TOO_LARGE);
  control.oversized = false;
  let release;
  control.gate = () => new Promise(resolve => { release = resolve; });
  const pending = client.listModels(config);
  client.cancel(); release();
  await assert.rejects(pending, e => e.code === C.CANCELLED);
  control.gate = undefined;
  control.body = '{"data":[{"id":"restored"}]}';
  assert.deepEqual(Array.from(await client.listModels(config)), ['restored'], 'a cancelled call must not poison the next request');
  assert.equal(control.closed, calls.length, 'every session is released');

  const player = { isPlaying: false, sleepMode: 0 };
  const state = { minutes: 12, streak: 1, records: [{}], favorites: ['book'], sources: [{}], failed: false };
  const { JianjianCompanionService: Companion } = load('service/JianjianCompanionService.ets', {
    '@kit.ArkUI': { AppStorageV2: { connect: () => player } },
    '../model/PlayerState': { PlayerState: class {}, PLAYER_STATE_KEY: 'player', SleepMode: { Off: 0 } },
    './StatsService': { StatsService: { async init() { if (state.failed) throw new Error('unavailable'); },
      async getStatsBundle() { return { summary: { todaySeconds: state.minutes * 60 }, streak: state.streak, records: state.records }; } } },
    './PreferenceService': { PreferenceService: { getFavorites: async () => state.favorites } },
    './rulesource/LocalRuleSourceRepository': { LocalRuleSourceRepository: { getAll: async () => state.sources } }
  });
  let info = await Companion.feedback({});
  assert.equal(info.greeting.id, 'app.string.jianjian_today_feedback'); assert.equal(info.greeting.args[0], 12);
  state.streak = 3; info = await Companion.feedback({}); assert.equal(info.expression, 8);
  player.isPlaying = true; player.sleepMode = 1;
  assert.equal((await Companion.feedback({})).greeting.id, 'app.string.jianjian_sleep_feedback');
  player.isPlaying = false; state.streak = 0; state.records = []; state.favorites = []; state.sources = [];
  info = await Companion.feedback({}); assert.equal(info.suggestImport, true); assert.equal(info.suggestSources, true);
  state.failed = true; info = await Companion.feedback({}); assert.equal(info.suggestImport, false);
  for (const route of ['reader','comicReader','player','ruleSourceLogin','jianjianChat','jianjianAiSettings']) assert.equal(Companion.quietRoute(route), true);
  for (const route of ['','settings','stats']) assert.equal(Companion.quietRoute(route), false);
  console.log('PASS: AI configuration, encrypted storage contract, model list, bounded chat, auth/errors/cancellation, local feedback and quiet routes');
})().catch(error => { console.error(error); process.exitCode = 1; });
