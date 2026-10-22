// Execute the real ArkTS service with deterministic speech, storage and audio mocks.
// DEVECO_HOME must point to an installed DevEco Studio. No device state is modified.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
function load(relative, dependencies = {}, globals = {}) {
  const file = path.join(root, relative);
  const source = fs.readFileSync(file, 'utf8').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, { module, exports: module.exports, console, Date, Map, Set, Promise, Error,
    $r: id => ({ id }), ...globals, require(name) {
      if (!(name in dependencies)) throw new Error(`Unexpected dependency ${name}`);
      return dependencies[name];
    } }, { filename: file });
  return module.exports;
}
const localImages = load('service/text/LocalTextImage.ets');
const { SpeechTextSegmenter } = load('service/text/SpeechTextSegmenter.ets', { './LocalTextImage': localImages });
const { SpeechPcmBuffer } = load('service/text/SpeechPcmBuffer.ets');
const pcmFormat = { audioType: 'pcm', sampleRate: 16000, sampleBit: 16, audioChannel: 1 };
const model = load('model/TextToSpeechState.ets');
const readerToolsModel = load('model/ReaderTools.ets');
const { SpeechTextHighlighter } = load('service/text/SpeechTextHighlighter.ets');
const { CustomTtsConfig } = load('model/CustomTtsConfig.ets');
const { CustomTtsTemplate: LocalRuleTemplate } = load('service/text/CustomTtsTemplate.ets');
const { CustomTtsConfigParser } = load('service/text/CustomTtsConfigParser.ets', {
  '@kit.NetworkKit': { http: {} },
  '../../model/CustomTtsConfig': { CustomTtsConfig },
  './CustomTtsTemplate': { CustomTtsTemplate: LocalRuleTemplate },
  '../rulesource/LocalRuleQuickJsRuntime': {}
});
const settle = async () => { for (let i = 0; i < 45; i++) await Promise.resolve(); };
const book = (id = 'book', texts = ['第一句。第二句！', '第三句。']) => ({ id, contentType: 'text', title: id,
  sourceUrl: 'https://source.example', bookUrl: `https://book.example/${id}`, author: 'author', cover: '',
  chapters: texts.map((text, index) => ({ id: String(index), title: `章节${index}`, source: { value: `${id}/${index}`, type: 'url' }, text })) });
function harness(memory = new Map()) {
  let uptime = 0;
  const engines = [], spoken = [], timers = new Map(), cached = new Map(), stats = [], httpSpoken = [], httpPrepared = [], systemSpoken = [], widgets = [];
  let id = 0, failContent = false, createDeferred = null, focusCallback = null, deviceCallback = null;
  const coordinator = load('service/PlaybackCoordinator.ets');
  const session = { callbacks: null, paused: false, setSpeechCallbacks(cbs) { this.callbacks = cbs; },
    restoreAudioCallbacks() {}, endSpeechPlayback() { this.paused = true; },
    init: async () => {}, updateMetadata: async () => {}, updatePlaybackState: async () => {} };
  const audioSession = { on: (_event, cb) => { focusCallback = cb; }, off: () => { focusCallback = null; },
    activateAudioSession: async () => {}, deactivateAudioSession: async () => {} };
  const routing = { on: (_event, _flag, cb) => { deviceCallback = cb; }, off: () => { deviceCallback = null; } };
  const tts = { listVoices: async () => [{ person: 13, language: 'zh-CN', style: 'interaction-broadcast', description: 'female', status: 'INSTALLED' }],
    createEngine: async () => {
      if (createDeferred) await createDeferred;
      const engine = { listener: null, closed: false, setListener(listener) { this.listener = listener; },
        stop() {}, shutdown() { this.closed = true; }, speak(text, params) {
          spoken.push({ engine, text, id: params.requestId, speed: params.extraParams.speed });
          assert.equal(params.extraParams.playType, 0);
          assert.equal(params.extraParams.soundChannel, 1);
          this.listener.onStart(params.requestId, pcmFormat);
          this.listener.onData(params.requestId, new ArrayBuffer(320), { sequence: 0, audioType: 'pcm' });
          this.listener.onComplete(params.requestId, { type: 0 });
        } };
      engines.push(engine); return engine;
    } };
  const dependencies = {
    '../WidgetUpdater': { WidgetUpdater: { updateSpeechCard: async (book, state) => widgets.push({
      bookId: book.id, chapterIndex: state.chapterIndex, charOffset: state.charOffset,
      isPlaying: state.playing && !state.loading }) } },
    './TextReadingProgressService': { TextReadingProgressService: { save: async () => {} } },
    '../../model/TextReading': load('model/TextReading.ets', { './ReaderTheme': load('model/ReaderTheme.ets') }),
    './SpeechPcmBuffer': { SpeechPcmBuffer },
    '../DiagnosticLogService': { DiagnosticLogService: { info() {} } },
    '../ReadingSessionService': { ReadingSessionService: { checkpoint() {}, end() {} }, SessionLocation: { audio: () => ({}) } },
    '@kit.BasicServicesKit': { systemDateTime: { TimeType: { STARTUP: 0 }, getUptime: () => uptime } },
    '../../model/CustomTtsConfig': { CustomTtsConfig },
    './CustomTtsConfigParser': { CustomTtsConfigParser },
    './HttpTtsPlayer': { HttpTtsAudioOutput: class { async release() {} }, HttpTtsPlayer: class {
      ready = false;
      async speakAudio(_ctx, buffer, speed, id, onStart) {
        assert(speed >= 1 && speed <= 1.5);
        assert.equal(new DataView(buffer).getUint32(0, false), 0x52494646);
        if (this.cancelled) throw new Error('cancelled');
        onStart();
        await new Promise((resolve, reject) => {
          this.reject = reject;
          systemSpoken.push({ id, speed, complete: resolve });
        });
      }
      prepare(config, text, speed) {
        if (!this.preparation) this.preparation = Promise.resolve().then(() => {
          if (this.cancelled) throw new Error('cancelled');
          this.ready = true; httpPrepared.push({ config, text, speed, task: this });
        });
        return this.preparation;
      }
      async speak(_ctx, config, text, speed, id, onStart) {
        await this.prepare(config, text, speed);
        await new Promise((resolve, reject) => {
          this.reject = reject;
          httpSpoken.push({ config, text, speed, id, onStart, complete: resolve, fail: reject, task: this });
        });
      }
      cancel() { this.cancelled = true; this.ready = false; this.reject?.(new Error('cancelled')); }
    } },
    '@kit.ArkData': { preferences: { getPreferences: async () => ({ getSync: (key, fallback) => memory.get(key) ?? fallback,
      putSync: (key, value) => memory.set(key, value), deleteSync: key => memory.delete(key), flush: async () => {} }) } },
    '@kit.CoreSpeechKit': { textToSpeech: tts },
    '@kit.AudioKit': { audio: { getAudioManager: () => ({ getSessionManager: () => audioSession, getRoutingManager: () => routing }),
      AudioSessionDeactivatedReason: { DEACTIVATED_TIMEOUT: 1 }, DeviceFlag: { OUTPUT_DEVICES_FLAG: 1 }, DeviceChangeType: { DISCONNECT: 1 }, AudioConcurrencyMode: { CONCURRENCY_DEFAULT: 0 } } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn() {}, info() {} } },
    '../../model/TextToSpeechState': model,
    '../AudioService': { AudioService: { getInstance: () => ({ suspendForSpeech: async () => {} }) } },
    '../AVSessionService': { AVSessionService: { getInstance: () => session } },
    '../BackgroundTaskService': { BackgroundTaskService: { startSpeech: async () => {}, stopSpeech: async () => {}, isRunning: () => true } },
    '../PlaybackCoordinator': coordinator,
    '../PreferenceService': { PreferenceService: { isFavorite: async () => false, toggleFavorite: async () => true,
      applyTocOrder: async () => {} } },
    '../StatsService': { StatsService: { addListenSeconds: async (seconds, value) => stats.push([seconds, value]) } },
    '../DataService': { DataService: { upsertCachedBook: async () => {} } },
    '../BookSourceService': { BookSourceService: { getTextChapterContent: async (value, url) => {
      if (failContent) throw new Error('network');
      return { content: value.chapters.find(ch => ch.source.value === url).text };
    } } },
    './OnlineTextContentCache': { OnlineTextContentCache: { key: (...parts) => parts.join('|'),
      read: async (_ctx, key) => cached.get(key), write: async (_ctx, key, text) => cached.set(key, text) } },
    './OnlineTextPaginator': { OnlineTextPaginator: { normalizeContent: value => value } },
    './SpeechTextSegmenter': { SpeechTextSegmenter }
  };
  dependencies['../../model/ReaderTools'] = readerToolsModel;
  dependencies['./ReaderToolsService'] = load('service/text/ReaderToolsService.ets', {
    '../../model/ReaderTools': readerToolsModel,
    '@kit.ArkData': dependencies['@kit.ArkData'],
    '@kit.ArkTS': { util: {} },
    '../rulesource/LocalRuleQuickJsRuntime': { LocalRuleQuickJsRequest: class {}, LocalRuleQuickJsRuntime: {
      async execute(request) { return { success: true, value: String(vm.runInNewContext(request.script, {}, { timeout: 100 })) }; }
    } }
  });
  const { TextToSpeechService } = load('service/text/TextToSpeechService.ets', dependencies, {
    setTimeout: (callback, delay) => { const key = ++id; timers.set(key, { callback, delay }); return key; },
    clearTimeout: key => timers.delete(key), setInterval: (callback, delay) => { const key = ++id; timers.set(key, { callback, delay }); return key; },
    clearInterval: key => timers.delete(key)
  });
  const service = TextToSpeechService.getInstance();
  const context = { resourceManager: { getStringSync: key => key } };
  return { service, tts, memory, spoken, systemSpoken, engines, timers, session, httpSpoken, httpPrepared, stats, widgets,
    advance: ms => { uptime += ms; }, coordinator: coordinator.PlaybackCoordinator,
    init: () => service.initialize(context), reloadSettings: () => TextToSpeechService.reloadSettings(context),
    failContent: value => { failContent = value; },
    deferEngine: value => { createDeferred = value; }, focus: (reason = 0) => focusCallback?.({ reason }),
    unplug: () => deviceCallback?.({ type: 1 }),
    async complete(type = 1, request = spoken.at(-1)) {
      if (type === 0) { request.engine.listener.onComplete(request.id, { type }); return; }
      await settle();
      systemSpoken.find(item => item.id === request.id)?.complete();
      await settle();
    } };
}
let passed = 0;
async function check(name, action) { await action(); console.log(`PASS ${name}`); passed++; }
(async () => {
  await check('替换正文用于朗读，存储原文坐标，关闭规则后重启仍回到同一句', async () => {
    const memory = new Map();
    const rule = new readerToolsModel.ReaderReplaceRule();
    Object.assign(rule, { id: 'ad', pattern: '广告', replacement: '', bookId: 'book' });
    memory.set('data', JSON.stringify({ bookmarks: [], rules: [rule] }));
    const b = book('book', ['前文。广告\n下一句。末句。']);
    const originalOffset = b.chapters[0].text.indexOf('下一句');
    const h = harness(memory); await h.init();
    await h.service.start(b, 0, originalOffset); await settle();
    assert.equal(h.spoken.at(-1).text.trim(), '下一句。');
    assert.ok(!h.service.currentChapterContent().includes('广告'));
    h.service.pause();
    assert.equal(JSON.parse(memory.get('position_book')).charOffset, originalOffset);
    memory.set('data', JSON.stringify({ bookmarks: [], rules: [] }));
    const restored = harness(memory); await restored.init();
    await restored.service.start(b, 0, 0, true); await settle();
    assert.equal(restored.spoken.at(-1).text.trim(), '下一句。');
    assert.equal(restored.service.currentRawOffset(), originalOffset);
  });
  await check('朗读在前后台同步卡片书籍、章节和暂停恢复状态', async () => {
    const h = harness(); await h.init();
    await h.service.start(book(), 0, 0); await settle();
    assert.equal(h.widgets.at(-1).bookId, 'book');
    assert.equal(h.widgets.at(-1).isPlaying, true);
    h.service.setForeground(false);
    h.service.pause(); await settle();
    assert.equal(h.widgets.at(-1).isPlaying, false, 'background pause still reaches cards');
    await h.service.resume(); await settle();
    assert.equal(h.widgets.at(-1).isPlaying, true);
    await h.service.moveChapter(1); await settle();
    assert.equal(h.widgets.at(-1).chapterIndex, 1);
  });
  await check('恢复朗读备份后刷新已初始化的设置，不创建引擎或启动播放', async () => {
    const h = harness(); await h.init();
    h.memory.set('speed', 1.5); h.memory.set('follow', false); h.memory.set('person', 21);
    await h.reloadSettings();
    assert.equal(h.service.state.speed, 1.5);
    assert.equal(h.service.state.follow, false);
    assert.equal(h.service.state.person, 21);
    assert.equal(h.service.state.playing, false);
    assert.equal(h.engines.length, 0);
  });
  await check('默认中文女声兼容语言和编号别名，内置音色无需下载即显示已选择', async () => {
    const h = harness(); await h.init();
    h.tts.listVoices = async () => [{ person: 0, language: 'zh_CN', style: 'interaction-broadcast', status: 'NOT_INSTALLED' },
      { person: 21, language: 'zh-CN', style: 'interaction-broadcast', status: 'INSTALLED' }];
    await h.service.refreshVoices();
    const [female, male] = h.service.state.voices;
    assert.equal(female.installed, true);
    assert.equal(h.service.state.isVoiceSelected(female), true);
    assert.equal(h.service.state.isVoiceSelected(male), false);
    await h.service.selectVoice(male);
    assert.equal(h.service.state.isVoiceSelected(female), false);
    assert.equal(h.service.state.isVoiceSelected(male), true);
    h.service.state.person = 0;
    h.service.state.language = 'zh_CN';
    assert.equal(h.service.state.isVoiceSelected({ person: 13, language: 'zh-CN' }), true);
    assert.equal(h.service.state.isVoiceSelected({ person: 13, language: 'en-US' }), false);
  });
  await check('只展示中文音色，历史英文选择恢复默认中文且不允许重新选英文', async () => {
    const h = harness(new Map([['language', 'en-US'], ['person', 8]]));
    await h.init();
    assert.equal(h.service.state.language, 'zh-CN');
    assert.equal(h.service.state.person, 13);
    const english = { id: 'en-US:8:interaction-broadcast', person: 8, language: 'en-US', style: 'interaction-broadcast', installed: true };
    h.tts.listVoices = async () => [english, { person: 13, language: 'zh_CN', style: 'interaction-broadcast', status: 'INSTALLED' }];
    await h.service.refreshVoices();
    assert.equal(h.service.state.voices.length, 1);
    assert.equal(h.service.state.voices[0].language, 'zh_CN');
    await h.service.selectVoice(english);
    assert.equal(h.service.state.person, 13);
    await settle();
    assert.equal(h.memory.get('language'), 'zh-CN');
  });
  await check('下载成功立即更新音色行，旧查询结果不能回退或重复下载', async () => {
    const h = harness(); await h.init();
    const info = { person: 21, language: 'zh-CN', style: 'interaction-broadcast', description: 'male', status: 'NOT_INSTALLED' };
    h.tts.listVoices = async () => [info];
    let downloads = 0;
    h.tts.downloadVoice = (_params, callback) => {
      downloads++;
      callback(null, { on(event, handler) { if (event === 'complete') handler(); } });
    };
    await h.service.refreshVoices();
    const row = h.service.state.voices[0];
    await h.service.selectVoice(row);
    assert.equal(row.installed, true);
    assert.equal(h.service.state.person, 21);
    await h.service.refreshVoices();
    assert.equal(h.service.state.voices[0], row);
    assert.equal(row.installed, true);
    await h.service.selectVoice(row);
    assert.equal(downloads, 1);
  });
  await check('已有行响应系统安装状态更新，下载失败不误标记已安装', async () => {
    const h = harness(); await h.init();
    const info = { person: 21, language: 'zh-CN', style: 'interaction-broadcast', description: 'male', status: 'NOT_INSTALLED' };
    h.tts.listVoices = async () => [info];
    h.tts.downloadVoice = (_params, callback) => callback({ code: 1, message: 'failed' });
    await h.service.refreshVoices();
    const row = h.service.state.voices[0];
    await h.service.selectVoice(row);
    assert.equal(row.installed, false);
    assert.equal(h.service.state.person, 13);
    assert.equal(h.service.state.downloadingVoice, '');
    info.status = 'INSTALLED';
    await h.service.refreshVoices();
    assert.equal(h.service.state.voices[0], row);
    assert.equal(row.installed, true);
  });
  await check('分句保留原文字符偏移，长句不拆开代理对', async () => {
    const text = '  你好。”\n下一句！' + '文'.repeat(177) + '😀' + '字'.repeat(220);
    const parts = SpeechTextSegmenter.split(text);
    for (const part of parts) {
      assert.equal(text.slice(part.start, part.end).trim(), part.text);
      assert(!/^[\uDC00-\uDFFF]/.test(part.text)); assert(!/[\uD800-\uDBFF]$/.test(part.text));
      assert(part.end - part.start < 190);
    }
    assert.equal(SpeechTextSegmenter.indexAt(parts, parts[0].end), 1);
    assert.equal(SpeechTextSegmenter.indexAt(parts, text.length), parts.length);
  });
  await check('合成完成不提前翻句，播放完成才跨句和跨章', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0);
    await h.complete(0); assert.equal(h.spoken.length, 1);
    await h.complete(); assert.equal(h.spoken[1].text, '第二句！');
    await h.complete(); await settle(); assert.equal(h.spoken[2].text, '第三句。');
    assert.equal(h.service.state.chapterIndex, 1);
    await h.complete(); await settle(); assert.equal(h.service.state.playing, false); h.service.stop();
  });
  await check('倒序目录下手动和自动朗读仍按正文前进，首尾不越界', async () => {
    const h = harness(); await h.init();
    const b = book('descending', ['第一章。', '第二章。', '第三章。']);
    b.chaptersDescending = true;
    await h.service.start(b, 1, 0); await settle();
    await h.service.moveChapter(1); await settle();
    assert.equal(h.service.state.chapterIndex, 2);
    await h.service.moveChapter(1); await settle();
    assert.equal(h.service.state.chapterIndex, 2);
    await h.service.moveChapter(-1); await settle();
    assert.equal(h.service.state.chapterIndex, 1);
    await h.complete(); await settle();
    assert.equal(h.service.state.chapterIndex, 2);
    await h.complete(); await settle();
    assert.equal(h.service.state.playing, false);
    await h.service.start(b, 0, 0); await settle();
    await h.service.moveChapter(-1); await settle();
    assert.equal(h.service.state.chapterIndex, 0);
    h.service.stop();
  });
  await check('暂停恢复当前句，旧回调与重复完成不能推进新请求', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 5);
    const old = h.spoken.at(-1); h.service.pause(); await h.service.resume();
    assert.equal(h.spoken.at(-1).text, old.text);
    await h.complete(1, old); assert.equal(h.service.state.chapterIndex, 0);
    const current = h.spoken.at(-1); await h.complete(1, current); await h.complete(1, current); await settle();
    assert.equal(h.spoken.length, 3); h.service.stop();
  });
  await check('重启后按章节 URL 恢复，目录重排不串章', async () => {
    const h = harness(); await h.init(); const b = book(); await h.service.start(b, 0, 5); h.service.stop();
    const next = harness(h.memory); await next.init(); b.chapters.reverse();
    await next.service.start(b, 0, 0, true);
    assert.equal(next.service.state.chapterIndex, 1); assert.equal(next.spoken[0].text, '第二句！'); next.service.stop();
  });
  await check('停止时取消尚未创建完成的引擎，不意外出声', async () => {
    const h = harness(); await h.init(); let finish;
    h.deferEngine(new Promise(resolve => { finish = resolve; }));
    const starting = h.service.start(book(), 0, 0); await settle(); h.service.stop(); finish(); await starting;
    assert.equal(h.spoken.length, 0); assert(h.engines.every(engine => engine.closed));
  });
  await check('读完本章停止，保留跨进程的章节末尾位置', async () => {
    const h = harness(); await h.init(); h.service.setSleep(0, true); await h.service.start(book(), 0, 0);
    await h.complete(); await h.complete(); await settle();
    assert.equal(h.service.state.chapterIndex, 0); assert.equal(h.service.state.playing, false);
    assert.equal(h.service.state.charOffset, '第一句。第二句！'.length); h.service.stop();
  });
  await check('音频抢占停止朗读、清理定时器并暂停系统播控', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0); h.service.setSleep(15);
    await h.coordinator.useAudio(); assert.equal(h.service.state.active, false);
    assert.equal(h.service.state.playing, false); assert.equal(h.timers.size, 0); assert(h.session.paused);
  });
  await check('耳机拔出与焦点丢失暂停，不自动外放续读', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0); h.unplug();
    assert.equal(h.service.state.playing, false); await h.service.resume(); h.focus();
    assert.equal(h.service.state.playing, false); h.service.stop();
  });
  await check('离线读缓存；正文失败停留当前章且能重试', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0); h.service.stop();
    h.failContent(true); await h.service.start(book(), 0, 0); assert.equal(h.service.state.playing, true);
    await h.service.start(book('other'), 0, 0); assert.equal(h.service.state.playing, false);
    assert(h.service.state.error.includes('content_error'));
    h.failContent(false); await h.service.resume(); assert.equal(h.service.state.playing, true); h.service.stop();
  });
  await check('语速切换持久化，正在播放时从当前句继续', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0); h.service.setSpeed(1.5); await settle();
    assert.equal(h.spoken.at(-1).speed, 1.5); assert.equal(h.spoken.length, 2);
    assert.equal(h.memory.get('speed'), 1.5); h.service.stop();
  });
  await check('三倍速使用两倍合成和一点五倍播放，重启保持三倍速', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0);
    h.service.setSpeed(3); await settle();
    assert.equal(h.service.state.speed, 3);
    assert.equal(h.spoken.at(-1).speed, 2);
    assert.equal(h.systemSpoken.at(-1).speed, 1.5);
    assert.equal(h.memory.get('speed'), 3);
    h.service.stop();
    const restored = harness(h.memory); await restored.init();
    assert.equal(restored.service.state.speed, 3);
    restored.service.setSpeed(4);
    assert.equal(restored.service.state.speed, 3);
    restored.service.stop();
  });
  await check('初始化超时后可重试，迟到的引擎被释放', async () => {
    const h = harness(); await h.init(); let finish;
    h.deferEngine(new Promise(resolve => { finish = resolve; }));
    const pending = h.service.start(book(), 0, 0); await settle();
    const timeout = [...h.timers.values()].find(timer => timer.delay === 20000);
    assert(timeout); timeout.callback(); await pending;
    assert.equal(h.service.state.loading, false); assert(h.service.state.error);
    finish(); await settle(); assert(h.engines.every(engine => engine.closed));
    h.deferEngine(null); await h.service.resume(); assert.equal(h.service.state.playing, true); h.service.stop();
  });
  await check('稍后的朗读请求优先于仍在等待释放焦点的音频请求', async () => {
    const h = harness(); let finish;
    h.coordinator.speechActive = true;
    h.coordinator.stopSpeech = () => {
      h.coordinator.speechActive = false;
      return new Promise(resolve => { finish = resolve; });
    };
    const audioClaim = h.coordinator.useAudio();
    h.coordinator.speechActive = true; finish();
    assert.equal(await audioClaim, false); assert.equal(h.coordinator.speechActive, true);
  });
  await check('截止时间在下一句前检查，后台计时器延迟也不继续朗读', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0);
    h.service.setSleep(15); h.service.sleepDeadline = Date.now() - 1;
    await h.complete(); assert.equal(h.spoken.length, 1); assert.equal(h.service.state.playing, false);
    assert.equal(h.service.state.remainingSeconds, 0); h.service.stop();
  });
  await check('会话空闲超时不停止独立进程 TTS，真实抢占仍暂停', async () => {
    const h = harness(); await h.init(); await h.service.start(book(), 0, 0);
    h.focus(1); assert.equal(h.service.state.playing, true);
    await h.complete(); assert.equal(h.spoken.length, 2);
    h.focus(0); assert.equal(h.service.state.playing, false); h.service.stop();
  });
  await check('自然段高亮映射缩进、跨页交集和表情，不波及相邻段落', async () => {
    const source = '你好。\n  世界😀！\n下一段。';
    const display = '　　你好。\n　　世界😀！\n　　下一段。';
    const start = source.indexOf('世');
    const end = source.indexOf('\n下一段');
    const range = SpeechTextHighlighter.displayRange(display, source, start, end);
    assert.equal(display.slice(range.start, range.end), '世界😀！');
    const continued = SpeechTextHighlighter.displayRange('　　后半段。\n　　下一段。', '后半段。\n下一段。', -8, 4);
    assert.equal(continued.start, 2); assert.equal(continued.end, 6);
    const nextPage = SpeechTextHighlighter.displayRange('这一页。', '这一页。', 10, 20);
    assert.equal(nextPage.start, -1);
    const previousPage = SpeechTextHighlighter.displayRange('这一页。', '这一页。', -20, -1);
    assert.equal(previousPage.start, -1);
    const emoji = SpeechTextHighlighter.displayRange('😀！', '😀！', 1, 2);
    assert.equal(emoji.start, 0); assert.equal(emoji.end, 2);
  });
  await check('同段多句保持整段选中，下一段才换高亮且没有逐字刷新定时器', async () => {
    const h = harness(); await h.init();
    const content = '第一句。第二句。\n\n  第三句😀！';
    const listener = () => {};
    h.service.addListener(listener);
    await h.service.start(book('paragraph', [content]), 0, 0);
    assert.equal(h.service.state.highlightOffset, 0);
    assert.equal(h.service.state.highlightEnd, content.indexOf('\n'));
    const firstEnd = h.service.state.highlightEnd;
    await h.complete();
    assert.equal(h.service.state.highlightOffset, 0);
    assert.equal(h.service.state.highlightEnd, firstEnd);
    assert.equal(h.service.state.charOffset, content.indexOf('第二句'));
    await h.complete();
    assert.equal(h.service.state.highlightOffset, content.lastIndexOf('\n') + 1);
    assert.equal(h.service.state.highlightEnd, content.length);
    assert.ok([...h.timers.values()].every(timer => timer.delay !== 80));
    h.service.setForeground(false); h.service.setForeground(true);
    assert.ok([...h.timers.values()].every(timer => timer.delay !== 80));
    h.service.pause(); assert.equal(h.service.state.highlightEnd, content.length);
    h.service.stop(); assert.equal(h.service.state.highlightOffset, -1); assert.equal(h.service.state.highlightEnd, -1);
    h.service.removeListener(listener);
  });
  await check('自定义音色导入去重、保存选中项、重启恢复及删除回退', async () => {
    const h = harness(); await h.init();
    const configs = CustomTtsConfigParser.parse(JSON.stringify([
      { name: '关山', url: 'https://tts.example?text={{speakText}}&voice=1' },
      { name: '筱潇', url: 'https://tts.example?text={{speakText}}&voice=2' }
    ]));
    await h.service.importCustomTts(configs); await h.service.importCustomTts([configs[1]]);
    assert.equal(h.service.state.customTtsConfigs.length, 2);
    assert.equal(h.service.state.customTtsId, configs[1].id);
    const restored = harness(h.memory); await restored.init();
    assert.equal(restored.service.state.customTtsId, configs[1].id);
    await restored.service.removeCustomTts(configs[1].id);
    assert.equal(restored.service.state.customTtsId, '');
    assert.equal(restored.service.state.customTtsConfigs.length, 1);
    h.service.stop(); restored.service.stop();
  });
  await check('HTTP 音色等待音频出声才进入播放；切换和暂停隔离迟到回调', async () => {
    const h = harness(); await h.init();
    const configs = CustomTtsConfigParser.parse(JSON.stringify([
      { name: '甲', url: 'https://tts.example?text={{speakText}}&voice=1' },
      { name: '乙', url: 'https://tts.example?text={{speakText}}&voice=2' }
    ]));
    await h.service.importCustomTts(configs);
    await h.service.start(book('book', ['第一句。\n第二句！', '第三句。']), 0, 0); await settle();
    assert.equal(h.engines.length, 0); assert.equal(h.service.state.loading, true);
    assert.equal(h.service.state.playing, false);
    const old = h.httpSpoken.at(-1);
    old.onStart(); assert.equal(h.service.state.playing, true);
    await h.service.selectCustomTts(configs[0].id); await settle();
    assert.equal(old.task.cancelled, true);
    old.onStart(); old.complete(); await settle();
    assert.equal(h.service.state.playing, false);
    const current = h.httpSpoken.at(-1);
    assert.equal(current.config.id, configs[0].id);
    current.onStart(); current.complete(); await settle();
    assert.equal(h.httpSpoken.at(-1).text, '第二句！');
    h.service.pause(); const paused = h.httpSpoken.length;
    h.httpSpoken.at(-1).onStart(); await settle();
    assert.equal(h.service.state.playing, false); assert.equal(h.httpSpoken.length, paused);
    h.service.stop();
  });
  await check('自定义请求失败保留位置与选择，重试成功后可以切回系统语音', async () => {
    const h = harness(); await h.init();
    const configs = CustomTtsConfigParser.parse('{"name":"甲","url":"https://tts.example?text={{text}}"}');
    await h.service.importCustomTts(configs); await h.service.start(book('book', ['第一句。\n第二句！', '第三句。']), 0, 0); await settle();
    h.httpSpoken.at(-1).fail(new Error('offline')); await settle();
    assert.equal(h.service.state.playing, false); assert.equal(h.service.state.loading, false);
    assert.equal(h.service.state.customTtsId, configs[0].id); assert.ok(h.service.state.error);
    await h.service.resume(); await settle(); h.httpSpoken.at(-1).onStart();
    await h.service.selectCustomTts(''); await settle();
    assert.equal(h.service.state.customTtsId, ''); assert.equal(h.spoken.at(-1).text, '第一句。');
    h.service.stop();
  });
  await check('删除本地书清除朗读位置，停止后的迟到回调不能复活记录', async () => {
    const h = harness(); await h.init();
    const b = book();
    await h.service.start(b, 0, 0); await settle();
    h.memory.set('position_other', 'keep');
    await h.service.removeSavedPositions({}, [b.id]);
    assert.equal(h.service.state.active, false);
    assert.equal(h.service.state.bookId, '');
    h.service.stop(); await settle();
    assert.equal(h.memory.has('position_' + b.id), false);
    assert.equal(h.memory.get('position_other'), 'keep');
  });
  await check('句号前已预取后续两句，切句直接使用音频且不闪加载', async () => {
    const h = harness(); await h.init();
    const configs = CustomTtsConfigParser.parse('{"name":"甲","url":"https://tts.example?text={{text}}"}');
    await h.service.importCustomTts(configs);
    await h.service.start(book('prefetch', ['第一句。\n第二句。\n第三句。\n第四句。']), 0, 0); await settle();
    assert.deepEqual(h.httpPrepared.map(item => item.text), ['第一句。', '第二句。', '第三句。']);
    assert.equal(h.httpSpoken.length, 1); // prefetch never starts another player
    h.httpSpoken[0].onStart(); h.httpSpoken[0].complete(); await settle();
    assert.equal(h.httpSpoken.at(-1).text, '第二句。');
    assert.equal(h.service.state.loading, false);
    assert.equal(h.httpPrepared.filter(item => item.text === '第二句。').length, 1);
    assert.equal(h.httpPrepared.at(-1).text, '第四句。');
    assert.equal(h.service.httpTasks.size, 3);
    h.service.pause(); await settle();
    assert.equal(h.service.httpTasks.size, 0);
    assert.ok(h.httpPrepared.slice(1).every(item => item.task.cancelled));
    await h.service.resume(); await settle();
    assert.equal(h.httpSpoken.at(-1).text, '第二句。');
    h.service.stop();
  });
  await check('连续问号和数字脚注不会提交空语音，系统与导入音色保留正文位置', async () => {
    const content = '“安魂谣？？？”【10】猛地转头看向城市废墟，“是谁在唱安魂谣？？”\n[11]\n“是个男人的声音……不是那位？”';
    for (const http of [false, true]) {
      const segments = SpeechTextSegmenter.split(content, http);
      assert.ok(segments.length > 1);
      assert.ok(segments.every(item => /[\u4e00-\u9fff]/.test(item.text)));
      assert.ok(segments.every(item => !/【10】|\[11\]/.test(item.text)));
      assert.equal(segments.at(-1).paragraphStart, content.indexOf('“是个男人'));
      assert.equal(segments.at(-1).end, content.length);
    }
    const h = harness(); await h.init();
    await h.service.start(book('footnote', [content]), 0, 0); await settle();
    for (let i = 0; i < 10 && h.service.state.playing; i++) {
      assert.ok(/[\u4e00-\u9fff]/.test(h.spoken.at(-1).text));
      await h.complete();
    }
    assert.equal(h.service.state.error, '');
    assert.equal(h.service.state.charOffset, content.length);
    h.service.stop();
  });
  await check('HTTP 同段短句合并，保留自然段和字符位置，跳过纯标点请求', async () => {
    const content = '“嘶！”有人惊呼。怎么回事？他愣住了。\n下一段。还有一句！\n……\n最后。';
    const segments = SpeechTextSegmenter.split(content, true);
    assert.equal(segments.length, 3);
    assert.equal(segments[0].text, '“嘶！”有人惊呼。怎么回事？他愣住了。');
    assert.equal(segments[1].text, '下一段。还有一句！');
    assert.equal(segments[1].start, content.indexOf('下一段'));
    assert.equal(segments[2].text, '最后。');
    assert.equal(segments[2].paragraphStart, content.indexOf('最后'));
    const long = SpeechTextSegmenter.split('长'.repeat(179) + '😀。短句。再一句。', true);
    assert.equal(long.map(item => item.text).join(''), '长'.repeat(179) + '😀。短句。再一句。');
    assert.ok(long.every(item => item.text.length <= 182));
  });
  await check('朗读统计只累计实际播报，重复开始不丢时长，暂停不重复结算', async () => {
    const h = harness(); await h.init();
    await h.service.start(book(), 0, 0); await settle();
    h.advance(2500);
    const request = h.spoken.at(-1);
    request.engine.listener.onStart(request.id, pcmFormat);
    h.advance(1500);
    h.service.pause();
    assert.equal(h.stats.reduce((n, item) => n + item[0], 0), 4);
    h.advance(60000); h.service.pause();
    assert.equal(h.stats.reduce((n, item) => n + item[0], 0), 4);
  });
  console.log(`${passed} TTS regressions passed`);
})().catch(error => { console.error(error); process.exitCode = 1; });
