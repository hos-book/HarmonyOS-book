// Run the actual preview service with bounded platform adapters; no network or audio device is needed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };
const settle = async () => { for (let i = 0; i < 16; i++) await Promise.resolve(); };

function harness() {
  const calls = [], engines = [], requests = [], timers = new Map();
  let timerId = 0, engineGate = null, releaseGate = null, owner = '';
  const speech = { active: true, playing: true, generation: 0, resumed: 0, offset: 42,
    pause() { calls.push('pause-speech'); this.playing = false; this.generation++; },
    pauseForPreview() { const playing = this.active && this.playing; this.pause(); return playing ? this.generation : -1; },
    canResumePreview(ticket) { return ticket >= 0 && ticket === this.generation && this.active && !this.playing; },
    async resumeAfterPreview(ticket) { if (this.canResumePreview(ticket)) { this.resumed++; this.playing = true; this.generation++; } }
  };
  const focus = {
    acquire: async (next, stop) => { owner = next; focus.stop = stop; calls.push('focus'); },
    release: async current => { if (owner === current) owner = ''; },
    ensureActive: async current => owner === current,
    handleInterrupt: () => focus.stop()
  };
  const tts = {
    createEngine: async params => {
      const engine = { params, stopped: false, closed: false,
        setListener(listener) { this.listener = listener; },
        speak(text, options) { this.text = text; this.options = options; },
        stop() { this.stopped = true; }, shutdown() { this.closed = true; }
      };
      engines.push(engine);
      if (engineGate) await engineGate.promise;
      return engine;
    }
  };
  class Output {
    constructor(interrupt, unavailable, beforePlay) { this.beforePlay = beforePlay; this.released = false; }
    async setLoudnessGain(gain) { this.gain = gain; return true; }
    async release() { this.released = true; if (releaseGate) await releaseGate.promise; }
  }
  class Player {
    constructor(timeout, retries) { this.timeout = timeout; this.retries = retries; this.pending = deferred(); }
    async speak(context, config, text, speed, id, started, output) {
      this.output = output;
      requests.push({ player: this, config, text, speed, id, started });
      await this.pending.promise;
    }
    async speakAudio(context, buffer, speed, id, started, output) {
      this.output = output;
      requests.push({ player: this, buffer, speed, id, started });
      await this.pending.promise;
    }
    cancel() { this.cancelled = true; this.pending.reject(new Error('cancelled')); this.pending.promise.catch(() => {}); }
  }
  const coordinator = {};
  const mocks = {
    '@kit.CoreSpeechKit': { textToSpeech: tts },
    '@kit.AudioKit': {},
    '../AudioService': { AudioService: { getInstance: () => ({ suspendForSpeech: async () => calls.push('pause-audio') }) } },
    '../AudioFocusService': { AudioFocusService: { getInstance: () => focus } },
    '../PlaybackCoordinator': { PlaybackCoordinator: coordinator },
    './TextToSpeechService': { TextToSpeechService: { getInstance: () => speech } },
    './HttpTtsPlayer': { HttpTtsPlayer: Player, HttpTtsAudioOutput: Output }
  };
  function load(file) {
    const filename = path.join(root, file);
    const exports = {};
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
    }).outputText;
    vm.runInNewContext(code, { exports, ObservedV2: value => value, Trace: () => {},
      setTimeout: callback => { timers.set(++timerId, callback); return timerId; }, clearTimeout: id => timers.delete(id),
      require: name => {
        if (name === '../../model/RoleSpeech') return load('model/RoleSpeech.ets');
        if (name === './SpeechPcmBuffer') return load('service/text/SpeechPcmBuffer.ets');
        if (name in mocks) return mocks[name];
        throw new Error(`Unexpected dependency ${name}`);
      }
    }, { filename });
    return exports;
  }
  const { VoicePreviewService } = load('service/text/VoicePreviewService.ets');
  const service = new VoicePreviewService();
  const selected = { customTtsId: 'two', customTtsConfigs: [{ id: 'one', enabled: true }, { id: 'two', enabled: true }],
    person: 7, language: 'zh-CN', speed: 1.5, loudnessGain: 3, synthesis: { timeoutSeconds: 20 } };
  return { service, selected, calls, engines, requests, timers, coordinator, speech, focus,
    delayRelease: () => releaseGate = deferred(),
    delayEngine: () => engineGate = deferred(), focused: () => owner };
}

(async () => {
  const h = harness();
  let task = h.service.play({}, h.selected, '试听示例');
  await settle();
  assert.equal(h.requests[0].config.id, 'two', 'preview uses the selected imported voice');
  assert.equal(h.requests[0].speed, 1.5);
  assert.deepEqual(h.calls, ['pause-speech', 'pause-audio', 'focus']);
  assert.equal(h.service.state.loading, true);
  h.requests[0].started();
  assert.equal(h.service.state.loading, false, 'loading finishes only when playback starts');
  h.requests[0].player.pending.resolve();
  await task;
  assert.equal(h.service.state.active, false);
  assert.equal(h.focused(), '');
  assert.equal(h.timers.size, 0);
  assert.equal(h.coordinator.stopPreview, null);

  task = h.service.play({}, h.selected, '旧试听');
  await settle();
  h.selected.customTtsId = 'one';
  const newer = h.service.play({}, h.selected, '新试听');
  await settle();
  await task;
  assert.equal(h.requests[1].player.cancelled, true);
  assert.equal(h.requests[2].config.id, 'one');
  assert.equal(h.service.state.active, true, 'late old cleanup does not stop the newly selected voice');
  h.requests[1].started();
  assert.equal(h.service.state.loading, true, 'old playback callbacks are ignored');
  h.coordinator.stopPreview();
  await newer;
  assert.equal(h.service.state.active, false, 'audio handoff cancels preview');

  task = h.service.play({}, h.selected, '超时试听');
  await settle();
  [...h.timers.values()][0]();
  await task;
  assert.equal(h.service.state.error, true);
  assert.equal(h.service.state.active, false);
  assert.equal(h.timers.size, 0);

  const s = harness();
  s.selected.customTtsId = '';
  const systemTask = s.service.play({}, s.selected, '系统音色');
  await settle();
  const engine = s.engines[0];
  assert.equal(engine.params.person, 7);
  assert.equal(engine.params.language, 'zh-CN');
  const id = engine.options.requestId;
  engine.listener.onStart(id, { audioType: 'pcm', sampleBit: 16, sampleRate: 16000, audioChannel: 1 });
  engine.listener.onData(id, new Uint8Array([0, 1, 2, 3]).buffer, { audioType: 'pcm', sequence: 0 });
  engine.listener.onComplete(id, { type: 0 });
  await settle();
  assert.equal(s.requests.length, 1, 'system PCM is played through the existing bounded audio output');
  assert.equal(s.requests[0].buffer.byteLength, 48);
  s.service.stop();
  await systemTask;
  assert.equal(engine.closed, true);

  const late = harness();
  late.selected.customTtsId = '';
  const gate = late.delayEngine();
  const pending = late.service.play({}, late.selected, '取消初始化');
  await settle();
  late.service.stop();
  await pending;
  gate.resolve();
  await settle();
  assert.equal(late.engines[0].closed, true, 'engine arriving after page exit is immediately released');
  assert.equal(late.engines[0].text, undefined, 'late engine cannot begin speaking');
  assert.equal(late.requests.length, 0);

  const disabled = harness();
  disabled.selected.customTtsConfigs[1].enabled = false;
  await disabled.service.play({}, disabled.selected, '无效选择');
  assert.equal(disabled.service.state.error, true);
  assert.equal(disabled.engines.length, 0, 'an unavailable imported voice never silently switches to a system voice');
  const sequence = harness();
  const sequenceTask = sequence.service.playSequence({}, sequence.selected,
    [{ text: '旁白', voiceId: 'one' }, { text: '人物对白', voiceId: 'two' }], true);
  await settle();
  assert.equal(sequence.requests[0].config.id, 'one');
  sequence.requests[0].player.pending.resolve();
  await settle();
  assert.equal(sequence.requests[1].config.id, 'two');
  assert.equal(sequence.speech.resumed, 0, 'no resume between different characters');
  sequence.requests[1].player.pending.resolve();
  await sequenceTask;
  assert.equal(sequence.speech.resumed, 1);
  assert.equal(sequence.speech.offset, 42, 'preview leaves the reading position untouched');

  const local = harness();
  const localId = 'local-kokoro-v1_1:3';
  const piperId = 'local-piper-xiaoya-v1:0';
  local.selected.customTtsId = localId;
  local.selected.customTtsConfigs.push({ id: localId, provider: 'local-kokoro',
    modelId: 'kokoro-int8-v1_1', speakerId: 3, enabled: true });
  local.selected.customTtsConfigs.push({ id: piperId, provider: 'local-piper',
    modelId: 'piper-xiaoya-int8-v1', speakerId: 0, enabled: true });
  const localTask = local.service.playSequence({}, local.selected,
    [{ text: '本地旁白', voiceId: localId }, { text: '本地人物对白', voiceId: piperId }], true);
  await settle();
  assert.equal(local.requests[0].config.speakerId, 3, 'preview passes the local speaker to the shared synthesis path');
  assert.equal(local.engines.length, 0);
  local.requests[0].player.pending.resolve(); await settle();
  assert.equal(local.requests[1].config.provider, 'local-piper');
  assert.equal(local.requests[1].config.modelId, 'piper-xiaoya-int8-v1');
  assert.equal(local.requests[1].config.speakerId, 0);
  local.requests[1].player.pending.resolve(); await localTask;
  assert.equal(local.speech.resumed, 1);
  assert.equal(local.speech.offset, 42);

  const closing = harness();
  const closingTask = closing.service.playSequence({}, closing.selected, [{ text: '关闭', voiceId: 'one' }], true);
  await settle();
  const release = closing.delayRelease();
  const close1 = closing.service.stopAndResume();
  const close2 = closing.service.stopAndResume();
  assert.equal(close1, close2, 'closing, hiding and destruction share one completion');
  await settle();
  assert.equal(closing.speech.resumed, 0, 'wait for audio release before resuming');
  release.resolve();
  await Promise.all([closingTask, close1, close2]);
  assert.equal(closing.speech.resumed, 1);

  const rapid = harness();
  const oldPreview = rapid.service.playSequence({}, rapid.selected, [{ text: '旧', voiceId: 'one' }], true);
  await settle();
  const rapidGate = rapid.delayRelease();
  const oldEnd = rapid.service.stopAndResume();
  const newPreview = rapid.service.playSequence({}, rapid.selected, [{ text: '新', voiceId: 'two' }], true);
  rapidGate.resolve();
  await settle();
  await oldEnd;
  assert.equal(rapid.speech.resumed, 0, 'old cleanup cannot resume under a newer preview');
  assert.equal(rapid.service.state.active, true);
  rapid.requests[1].player.pending.resolve();
  await Promise.all([oldPreview, newPreview]);
  assert.equal(rapid.speech.resumed, 1, 'replacement inherits the original playing intent');

  for (const reason of ['paused', 'manual-pause', 'switch-book', 'background', 'focus-interrupt']) {
    const cancelled = harness();
    if (reason === 'paused') cancelled.speech.playing = false;
    const cancelledTask = cancelled.service.playSequence({}, cancelled.selected, [{ text: '取消恢复', voiceId: 'one' }], true);
    await settle();
    const gate = cancelled.delayRelease();
    const end = cancelled.service.stopAndResume();
    if (reason === 'manual-pause') cancelled.speech.pause();
    if (reason === 'switch-book') { cancelled.speech.generation++; cancelled.speech.offset = 5; }
    if (reason === 'background') cancelled.service.stop();
    if (reason === 'focus-interrupt') cancelled.coordinator.stopPreview?.();
    gate.resolve();
    await Promise.all([cancelledTask, end]);
    assert.equal(cancelled.speech.resumed, 0, reason + ' cancels auto resume');
  }
  const empty = harness();
  await empty.service.playSequence({}, empty.selected, [{ text: '  ', voiceId: '' }], true);
  assert.equal(empty.calls.length, 0, 'empty preview does not disturb playback');
  console.log('PASS preview sequences, single resume, replacement, interruption and position preservation');
  console.log('PASS selected HTTP/system voice preview, cancellation, replacement, timeout, late engine cleanup and playback isolation');
})().catch(error => { console.error(error); process.exitCode = 1; });
