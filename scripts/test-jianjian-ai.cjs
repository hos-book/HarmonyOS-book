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
const { JianjianReplyText: ReplyText } = load('utils/JianjianReplyText.ets', {});
assert.equal(ReplyText.display('### 最近情节\n- **楚风**：重逢。[1][2]\n\n### 主要人物'),
  '最近情节\n- 楚风：重逢。[1][2]\n\n主要人物');
assert.equal(ReplyText.display('C#、#话题、编号 #123'), 'C#、#话题、编号 #123');
assert.equal(ReplyText.display('```c\n# define VALUE 1\n```'), '# define VALUE 1');
for (const [reply, expected] of [
  ['**重点**，`**原样**`', '重点，原样'],
  ['**本章总结：\n主角与故人重逢。**\n\n**关键事件**：重逢。[1][2]',
    '本章总结：\n主角与故人重逢。\n\n关键事件：重逢。[1][2]'],
  ['**释义：顷刻指极短的时间。\n例句：顷刻之间。', '释义：顷刻指极短的时间。\n例句：顷刻之间。'],
  ['***顷刻***：极短的时间。**', '顷刻：极短的时间。'],
  [String.raw`\*\*释义\*\*：极短的时间。`, '释义：极短的时间。'],
  ['```markdown\n### **本章概括**\n**人物：\n主角**\n```', '本章概括\n人物：\n主角'],
  ['```\n**释义**：极短的时间。\n```', '释义：极短的时间。'],
  ['保留 2 * 3、#话题和 C#。', '保留 2 * 3、#话题和 C#。']
]) {
  assert.equal(ReplyText.display(reply), expected);
  assert.equal(ReplyText.display(expected), expected, 'plain replies stay unchanged');
}
const { JianjianAiConfig, JianjianAiMessage, JianjianAiPrompts, JIANJIAN_PROMPT_MAX_LENGTH,
  JianjianAiErrorCode: C } = model;
const promptResources = JSON.parse(fs.readFileSync(path.join(root, '../resources/base/element/jianjian_ai.json'), 'utf8'));
const promptContext = { resourceManager: { getStringSync(id) {
  const item = promptResources.string.find(item => 'app.string.' + item.name === id);
  assert.ok(item, id);
  return item.value;
} } };
function fixture() {
  const calls = [];
  let record;
  let cachedModels;
  let prompts;
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
        if (sql.startsWith('INSERT')) {
          if (sql.includes('model_cache')) cachedModels = [...values];
          else if (sql.includes('prompts')) prompts = [...values];
          else record = [...values];
        }
        if (sql.startsWith('DELETE')) {
          if (sql.includes('model_cache')) cachedModels = undefined;
          else if (sql.includes('prompts')) prompts = undefined;
          else record = undefined;
        }
      }, async querySql(sql, values) {
        const row = sql.includes('model_cache') ? cachedModels && cachedModels[0] === values[0] &&
          cachedModels[1] === values[1] ? [cachedModels[2]] : undefined : sql.includes('prompts') ? prompts : record;
        return { goToFirstRow: () => !!row, getString: i => row[i], close() {} };
      } };
    } } }
  };
  const { JianjianAiService: Service } = load('service/JianjianAiService.ets', mocks);
  const config = new JianjianAiConfig();
  Object.assign(config, { address: 'https://provider.test/v1/', apiKey: 'test-key', model: 'z-text' });
  return { Service, client: new Service(), config, control, calls };
}

(async () => {
  const { Service, client, config, control, calls } = fixture();
  const defaults = Service.defaultPrompts(promptContext);
  assert.ok(defaults.chat.includes('简简') && defaults.book.includes('引用数据'));
  assert.deepEqual(await Service.loadPrompts(promptContext), defaults, 'old installations use the built-in prompts');
  const custom = Object.assign(new JianjianAiPrompts(), { chat: '以简洁的中文交流。\n先给结论。', book: '用编号讨论已读情节。' });
  await Service.savePrompts(promptContext, custom);
  assert.deepEqual(await Service.loadPrompts(promptContext), custom, 'prompts persist without AI credentials');
  assert.equal(calls.length, 0, 'editing prompts never contacts the provider');
  control.failStore = true;
  await assert.rejects(Service.savePrompts(promptContext, defaults));
  control.failStore = false;
  assert.deepEqual(await Service.loadPrompts(promptContext), custom, 'failed saves preserve both saved prompts');
  await assert.rejects(Service.savePrompts(promptContext, Object.assign(new JianjianAiPrompts(), custom,
    { chat: '字'.repeat(JIANJIAN_PROMPT_MAX_LENGTH + 1) })), e => e.code === C.PROMPT);
  assert.deepEqual(await Service.loadPrompts(promptContext), custom);
  const restoredChat = await Service.savePrompts(promptContext, Object.assign(new JianjianAiPrompts(), custom, { chat: ' \n ' }));
  assert.equal(restoredChat.chat, defaults.chat, 'blank chat restores the built-in text');
  assert.equal(restoredChat.book, custom.book, 'restoring one prompt preserves the other');
  const restoredBook = await Service.savePrompts(promptContext, Object.assign(new JianjianAiPrompts(), custom, { book: '' }));
  assert.equal(restoredBook.chat, custom.chat);
  assert.equal(restoredBook.book, defaults.book);
  await Service.savePrompts(promptContext, custom);
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
  assert.deepEqual(Array.from(await Service.loadCachedModels({}, loaded)), [], 'old configs without a cache still load');
  const completeCatalog = Array.from({ length: 250 }, (_, i) => 'provider-model-' + i);
  completeCatalog.push('z-text', 'embedding-model');
  await Service.saveCachedModels({}, config, completeCatalog);
  const reopenedConfig = await Service.loadConfig({});
  assert.deepEqual(Array.from(await Service.loadCachedModels({}, reopenedConfig)), [...completeCatalog].sort(),
    'reopening settings restores the full persisted catalog, without a network request');
  assert.equal(calls.length, 0);
  assert.deepEqual(Array.from(await Service.loadCachedModels({}, Object.assign(new JianjianAiConfig(), config,
    { address: 'https://other-provider.test/v1' }))), [], 'never show another provider\'s models');
  assert.deepEqual(Array.from(await Service.loadCachedModels({}, Object.assign(new JianjianAiConfig(), config,
    { apiKey: 'another-key' }))), [], 'model catalog is scoped to the API key');
  await Service.saveConfig({}, Object.assign(new JianjianAiConfig(), config, { model: 'embedding-model' }));
  assert.deepEqual(Array.from(await Service.loadCachedModels({}, await Service.loadConfig({}))), [...completeCatalog].sort(),
    'changing the selected model keeps the catalog');
  await Service.saveConfig({}, config);
  control.failStore = true;
  await assert.rejects(Service.saveConfig({}, Object.assign(new JianjianAiConfig(), config, { model: 'changed' })));
  await assert.rejects(Service.saveCachedModels({}, config, ['replacement']));
  control.failStore = false;
  assert.equal((await Service.loadConfig({})).model, config.model);
  assert.deepEqual(Array.from(await Service.loadCachedModels({}, config)), [...completeCatalog].sort(),
    'a failed refresh does not discard the saved models');
  await Service.saveCachedModels({}, config, ['refreshed', 'z-text', 'refreshed']);
  assert.deepEqual(Array.from(await Service.loadCachedModels({}, config)), ['refreshed', 'z-text']);
  await Service.clearConfig({}); assert.equal((await Service.loadConfig({})).apiKey, '');
  assert.deepEqual(await Service.loadPrompts(promptContext), custom, 'clearing credentials keeps custom prompts');
  assert.deepEqual(Array.from(await Service.loadCachedModels({}, config)), [], 'clear removes cached models and credentials');
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
  assert.equal(body.messages[0].role, 'system');
  assert.ok(body.messages[0].content.startsWith('Only user-provided conversation.\n\n'));
  assert.match(body.messages[0].content, /纯文本/);
  assert.match(body.messages[0].content, /保留段落和引用编号/);
  assert.ok(body.messages.length <= 21); assert.equal(body.messages[1].role, 'user');
  assert.equal(body.messages.at(-1).content, '聊聊阅读');
  assert.deepEqual(Object.keys(body).sort(), ['messages', 'model', 'stream']);
  assert.ok(!request.body.includes('test-key'));
  const selectedPrompt = await Service.conversationPrompt(promptContext, false, 'must-not-be-sent');
  assert.equal(selectedPrompt, custom.chat, 'ordinary chat uses the saved prompt without book evidence');
  await client.chat(config, [new JianjianAiMessage('user', '你好')], selectedPrompt);
  assert.ok(JSON.parse(calls.at(-1).body).messages[0].content.startsWith(custom.chat + '\n\n'));
  const evidence = '{"reference":"1","text":"已读片段"}';
  const bookPrompt = await Service.conversationPrompt(promptContext, true, evidence);
  assert.ok(bookPrompt.startsWith(custom.book + '\n\n'));
  assert.ok(bookPrompt.endsWith('\n' + evidence));
  await Service.savePrompts(promptContext, defaults);
  assert.equal(await Service.conversationPrompt(promptContext, false), defaults.chat,
    'the next request picks up restored defaults without restarting');
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
  for (const route of ['reader','comicReader','player','ruleSourceLogin','jianjianChat','jianjianAiSettings','jianjianPromptSettings']) assert.equal(Companion.quietRoute(route), true);
  for (const route of ['','settings','stats']) assert.equal(Companion.quietRoute(route), false);
  console.log('PASS: AI configuration, encrypted storage contract, model list, bounded chat, auth/errors/cancellation, local feedback and quiet routes');
})().catch(error => { console.error(error); process.exitCode = 1; });
