// Exercise the real HTTP task across native request/player lifecycle boundaries.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/text/HttpTtsPlayer.ets'), 'utf8');
const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
const requests = [], players = [], files = new Set();
const gainRequests = [];
const localSynthesis = [];
let localGate = null;
const settle = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
const moduleMock = { exports: {} };
vm.runInNewContext(code, { module: moduleMock, exports: moduleMock.exports, ArrayBuffer, Uint8Array, setTimeout, clearTimeout, require(name) {
  if (name === '../../model/OfflineTtsCatalog') return {
    isOfflineTtsProvider: provider => provider === 'local-kokoro' || provider === 'local-piper'
  };
  if (name === '../../utils/PlatformCompat') return { PlatformCompat: { supports: () => true } };
  if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {} } };
  if (name === '@kit.NetworkKit') return { http: { createHttp() {
    const listeners = new Map();
    const req = { on: (name, callback) => listeners.set(name, callback), off: name => listeners.delete(name),
      chunk: data => listeners.get('dataReceive')?.(data),
      end: () => listeners.get('dataEnd')?.(),
      requestInStream(_url, options) { req.options = options; return new Promise((resolve, reject) => {
        req.status = resolve;
        req.resolve = response => {
          const bytes = typeof response.result === 'string' ? Uint8Array.from(Buffer.from(response.result)).buffer : response.result;
          req.chunk(bytes); req.end(); resolve(response.responseCode);
        };
        req.reject = reject;
      }); },
      destroy() { req.destroyed = true; } };
    requests.push(req); return req;
  } } };
  if (name === './CustomTtsConfigParser') return { CustomTtsConfigParser: {
    expand: async () => 'https://example.invalid/tts', requestOptions: async () => ({}),
    usesSpeed: config => config.provider === 'local-kokoro' || config.provider === 'local-piper' || config.speedTemplate
  } };
  if (name === './OfflineTtsService') return { OfflineTtsService: { instance: {
    async synthesize(config, text, speed, cancelled) {
      localSynthesis.push({ config, text, speed, cancelled });
      if (localGate) return localGate.promise;
      return new ArrayBuffer(48);
    }
  } } };
  if (name === '@kit.CoreFileKit') return { fileIo: {
    OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
    async open(file) { files.add(file); return { fd: file }; }, async write(_fd, data) { return data.byteLength; },
    async close() {}, async unlink(file) { files.delete(file); }
  } };
  if (name === '@kit.AudioKit') return { audio: { StreamUsage: { STREAM_USAGE_AUDIOBOOK: 1 },
    InterruptHint: { INTERRUPT_HINT_PAUSE: 1, INTERRUPT_HINT_STOP: 2 } } };
  if (name === '@kit.MediaKit') return { media: { SeekMode: { SEEK_PREV_SYNC: 0 }, async createAVPlayer() {
    const listeners = new Map();
    const player = { state: 'idle', on: (event, callback) => listeners.set(event, callback),
      off: event => listeners.delete(event),
      set fdSrc(value) { listeners.get('stateChange')('initialized'); },
      async prepare() { this.state = 'prepared'; listeners.get('stateChange')('prepared'); },
      setLoudnessGain(gain) { return new Promise((resolve, reject) => gainRequests.push({ gain, resolve, reject })); },
      setPlaybackRate(value) { this.rate = value; },
      seek(value) { this.seekPosition = value; },
      async play() { this.state = 'playing'; listeners.get('stateChange')('playing'); },
      complete() { this.state = 'completed'; listeners.get('stateChange')('completed'); },
      async reset() { this.state = 'idle'; this.resetCount = (this.resetCount || 0) + 1; },
      async release() { this.released = true; } };
    players.push(player); return player;
  } } };
  throw new Error(`Unexpected dependency ${name}`);
} });
const { HttpTtsPlayer, HttpTtsAudioOutput } = moduleMock.exports;
const respond = req => req.resolve({ responseCode: 200, result: new ArrayBuffer(24) });
(async () => {
  const task = new HttpTtsPlayer();
  const output = new HttpTtsAudioOutput();
  assert.equal(await output.setLoudnessGain(12), true);
  const ready = task.prepare({}, '第一句。', 1.5); await settle();
  assert.equal(requests.length, 1); assert.equal(players.length, 0);
  respond(requests[0]); await ready;
  assert.equal(task.ready, true); assert.equal(players.length, 0);
  let started = 0;
  const playing = task.speak({ cacheDir: '/cache' }, {}, '第一句。', 1.5, 'first', () => started++, output);
  await settle();
  assert.equal(requests.length, 1); assert.equal(started, 1); assert.equal(players[0].rate, 1.5);
  output.setPlaybackSpeed(2); output.setPlaybackSpeed(0.75);
  assert.equal(players[0].rate, 0.75);
  assert.equal(requests.length, 1, 'changing playback rate must not synthesize again');
  players[0].duration = 10000;
  assert.equal(output.seekRatio(0.6), true);
  assert.equal(players[0].seekPosition, 6000);
  assert.equal(output.seekRatio(0.1), true);
  assert.equal(players[0].seekPosition, 1000);
  assert.equal(requests.length, 1, 'seeking inside prepared audio must not synthesize again');
  assert.equal(gainRequests[0].gain, 12, 'first segment starts while native gain promise remains pending');
  players[0].complete(); await playing;
  assert.equal(players[0].released, undefined); assert.equal(players[0].resetCount, 1);
  assert.equal(files.size, 0); assert.equal(task.ready, false);

  const next = new HttpTtsPlayer();
  const nextSpeech = next.speak({ cacheDir: '/cache' }, {}, '下一段。', 1, 'next', () => started++, output);
  await settle(); output.setPlaybackSpeed(2); respond(requests[1]); await settle();
  assert.equal(players[0].rate, 2, 'speed changed during synthesis survives late audio preparation');
  assert.equal(players.length, 1); assert.equal(started, 2);
  assert.equal(gainRequests[1].gain, 12, 'next segment restores gain without waiting for either native promise');
  gainRequests[0].reject(new Error('late native failure'));
  gainRequests[1].resolve();
  await settle();
  players[0].complete(); await nextSpeech;
  assert.equal(players[0].resetCount, 2); assert.equal(files.size, 0);
  await output.release(); assert.equal(players[0].released, true);

  const cancelled = new HttpTtsPlayer();
  const pending = cancelled.prepare({}, '旧音色。', 1);
  const rejected = assert.rejects(pending, /cancelled/);
  await settle(); cancelled.cancel(); await rejected;
  respond(requests[2]); await settle();
  assert.equal(cancelled.ready, false); assert.equal(requests[2].destroyed, true);
  assert.equal(players.length, 1); assert.equal(files.size, 0);

  const stopped = new HttpTtsPlayer();
  const speech = stopped.speak({ cacheDir: '/cache' }, { speedTemplate: true }, '正在朗读。', 2, 'second', () => {}, output);
  const stoppedResult = assert.rejects(speech, /cancelled/);
  await settle(); respond(requests[3]); await settle();
  assert.equal(players[1].rate, 1); // synthesis already applied the speed
  assert.equal(gainRequests[2].gain, 12, 'stale failure must not roll back a later gain restoration');
  gainRequests[2].resolve();
  stopped.cancel(); await stoppedResult;
  assert.equal(players[1].released, true); assert.equal(files.size, 0);
  const hangingOutput = new HttpTtsAudioOutput();
  const oldPlayer = await hangingOutput.acquire();
  oldPlayer.reset = () => new Promise(() => {});
  oldPlayer.release = () => new Promise(() => {});
  await hangingOutput.finish(oldPlayer, true);
  const replacement = await hangingOutput.acquire();
  assert.notEqual(replacement, oldPlayer, 'hung cleanup cannot block subsequent playback or reuse a stale player');
  await hangingOutput.release();
  const retryStart = requests.length;
  const retry = new HttpTtsPlayer(0.01, 1);
  await assert.rejects(retry.prepare({}, '超时重试。', 3), /timed out/);
  assert.equal(requests.length - retryStart, 2, 'retry count is bounded even when the provider never responds');
  assert.ok(requests.slice(retryStart).every(req => req.destroyed && req.options.readTimeout === 40));
  const stopRetry = new HttpTtsPlayer(30, 3);
  const stopRetryResult = stopRetry.prepare({}, '取消重试。', 3);
  const cancelledRetry = assert.rejects(stopRetryResult, /cancelled/);
  await settle();
  requests.at(-1).reject(new Error('offline')); await settle();
  const beforeCancel = requests.length;
  stopRetry.cancel(); await cancelledRetry;
  assert.equal(requests.length, beforeCancel, 'cancellation clears retry backoff without issuing another request');
  for (const [status, kind, body] of [
    [401, 'auth', ''], [403, 'auth', '<html>private</html>'], [400, 'config', 'bad config'],
    [500, 'voice', JSON.stringify({ error: { code: 'hd_synthesis_failed', message: 'secret' } })],
    [200, 'audio', '<html>not audio</html>']
  ]) {
    const start = requests.length;
    const task = new HttpTtsPlayer(30, 3);
    const done = assert.rejects(task.prepare({}, '测试。', 1), error => error.kind === kind && !error.message.includes('secret'));
    await settle();
    const bytes = Uint8Array.from(Buffer.from(body));
    requests.at(-1).resolve({ responseCode: status, result: bytes.buffer });
    await done;
    assert.equal(requests.length - start, 1, `${kind} must not retry`);
    assert.equal(requests.at(-1).destroyed, true);
  }
  const recovering = new HttpTtsPlayer(30, 1);
  const recovery = recovering.prepare({}, '服务恢复。', 1);
  await settle();
  requests.at(-1).resolve({ responseCode: 503, result: '<html>unavailable</html>' });
  await new Promise(resolve => setTimeout(resolve, 350));
  respond(requests.at(-1)); await recovery;
  assert.equal(recovering.ready, true);
  const slow = new HttpTtsPlayer(0.025, 0);
  const slowResult = slow.prepare({}, '持续传输不应被空闲超时截断。', 1);
  await settle();
  const slowRequest = requests.at(-1);
  slowRequest.status(200);
  for (let i = 0; i < 4; i++) {
    await new Promise(resolve => setTimeout(resolve, 15));
    slowRequest.chunk(new ArrayBuffer(12));
  }
  slowRequest.end(); await slowResult;
  assert.equal(slow.ready, true, 'audio arriving beyond the old total timeout still completes');
  const stalled = new HttpTtsPlayer(0.015, 0);
  const stalledResult = assert.rejects(stalled.prepare({}, '半途停止传输。', 1), /timed out/);
  await settle(); requests.at(-1).status(200); requests.at(-1).chunk(new ArrayBuffer(12));
  await stalledResult;
  assert.equal(stalled.ready, false, 'partial audio must never become playable');
  const oversized = new HttpTtsPlayer(30, 0);
  const sizeResult = assert.rejects(oversized.prepare({}, '超限。', 1), e => e.kind === 'audio');
  await settle(); requests.at(-1).chunk(new ArrayBuffer(8 * 1024 * 1024 + 1));
  await sizeResult;
  const localConfig = { id: 'local-kokoro-v1_1:3', provider: 'local-kokoro', modelId: 'kokoro-int8-v1_1', speakerId: 3 };
  const requestCount = requests.length;
  const local = new HttpTtsPlayer();
  await local.prepare(localConfig, '本地角色说话。', 1.5);
  assert.equal(local.ready, true);
  assert.equal(requests.length, requestCount, 'local synthesis must not create HTTP requests');
  assert.equal(localSynthesis.at(-1).config.speakerId, 3);
  const localOutput = new HttpTtsAudioOutput();
  const playerCount = players.length;
  let localStarted = 0;
  const localSpeech = local.speak({ cacheDir: '/cache' }, localConfig, '本地角色说话。', 1.5,
    'local', () => localStarted++, localOutput);
  await settle();
  assert.equal(localSynthesis.length, 1, 'prepared local audio is consumed without synthesizing twice');
  assert.equal(players.length, playerCount + 1);
  assert.equal(players.at(-1).rate, 1, 'native rate is not applied again by the player');
  assert.equal(localStarted, 1);
  players.at(-1).complete(); await localSpeech; await localOutput.release();
  assert.equal(files.size, 0);
  let finishLocal;
  localGate = { promise: new Promise(resolve => { finishLocal = resolve; }) };
  const lateLocal = new HttpTtsPlayer();
  const latePreparation = lateLocal.prepare(localConfig, '取消后不出声。', 1);
  const lateRejected = assert.rejects(latePreparation, /cancelled/);
  await settle(); lateLocal.cancel();
  assert.equal(localSynthesis.at(-1).cancelled(), true);
  finishLocal(new ArrayBuffer(48)); await lateRejected;
  assert.equal(lateLocal.ready, false, 'late native audio cannot become ready after cancellation');
  assert.equal(players.length, playerCount + 1, 'cancelled local synthesis never opens an audio player');
  assert.equal(requests.length, requestCount);
  localGate = null;
  for (const name of ['chaowen', 'xiaoya']) {
    const config = { id: `local-piper-${name}-v1:0`, provider: 'local-piper', modelId: `piper-${name}-int8-v1`, speakerId: 0 };
    const task = new HttpTtsPlayer();
    const beforeRequests = requests.length;
    await task.prepare(config, 'Piper 本地人物对白。', 1.25);
    assert.equal(task.ready, true);
    assert.equal(requests.length, beforeRequests);
    assert.equal(localSynthesis.at(-1).config.modelId, config.modelId);
    assert.equal(localSynthesis.at(-1).config.speakerId, 0);
    const audio = new HttpTtsAudioOutput();
    const speaking = task.speak({ cacheDir: '/cache' }, config, 'Piper 本地人物对白。', 1.25, name, () => {}, audio);
    await settle();
    assert.equal(players.at(-1).rate, 1, 'Piper native speed is applied only once');
    players.at(-1).complete(); await speaking; await audio.release();
    assert.equal(files.size, 0);
  }
  console.log('PASS Piper超文/小雅按modelId与speaker零HTTP分流，音频复用且语速只应用一次');
  console.log('PASS 本地speaker原样分流、零HTTP请求、合成音频复用及取消迟到本地结果');
  console.log('PASS 连续片段复用同一播放器、停止释放、预取不播放、合成去重、取消迟到请求和临时文件释放');
})().catch(error => { console.error(error); process.exitCode = 1; });
