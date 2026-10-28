// Exercise the real HTTP task across native request/player lifecycle boundaries.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/text/HttpTtsPlayer.ets'), 'utf8');
const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
const requests = [], players = [], files = new Set();
const settle = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
const moduleMock = { exports: {} };
vm.runInNewContext(code, { module: moduleMock, exports: moduleMock.exports, ArrayBuffer, setTimeout, clearTimeout, require(name) {
  if (name === '@kit.NetworkKit') return { http: { createHttp() {
    const req = { request(_url, options) { req.options = options; return new Promise((resolve, reject) => { req.resolve = resolve; req.reject = reject; }); },
      destroy() { req.destroyed = true; } };
    requests.push(req); return req;
  } } };
  if (name === './CustomTtsConfigParser') return { CustomTtsConfigParser: {
    expand: async () => 'https://example.invalid/tts', requestOptions: async () => ({}), usesSpeed: config => config.speedTemplate
  } };
  if (name === '@kit.CoreFileKit') return { fileIo: {
    OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
    async open(file) { files.add(file); return { fd: file }; }, async write(_fd, data) { return data.byteLength; },
    async close() {}, async unlink(file) { files.delete(file); }
  } };
  if (name === '@kit.AudioKit') return { audio: { StreamUsage: { STREAM_USAGE_AUDIOBOOK: 1 },
    InterruptHint: { INTERRUPT_HINT_PAUSE: 1, INTERRUPT_HINT_STOP: 2 } } };
  if (name === '@kit.MediaKit') return { media: { async createAVPlayer() {
    const listeners = new Map();
    const player = { on: (event, callback) => listeners.set(event, callback),
      off: event => listeners.delete(event),
      set fdSrc(value) { listeners.get('stateChange')('initialized'); },
      async prepare() { listeners.get('stateChange')('prepared'); },
      setPlaybackRate(value) { this.rate = value; },
      async play() { listeners.get('stateChange')('playing'); },
      complete() { listeners.get('stateChange')('completed'); },
      async reset() { this.resetCount = (this.resetCount || 0) + 1; },
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
  const ready = task.prepare({}, '第一句。', 1.5); await settle();
  assert.equal(requests.length, 1); assert.equal(players.length, 0);
  respond(requests[0]); await ready;
  assert.equal(task.ready, true); assert.equal(players.length, 0);
  let started = 0;
  const playing = task.speak({ cacheDir: '/cache' }, {}, '第一句。', 1.5, 'first', () => started++, output);
  await settle();
  assert.equal(requests.length, 1); assert.equal(started, 1); assert.equal(players[0].rate, 1.5);
  players[0].complete(); await playing;
  assert.equal(players[0].released, undefined); assert.equal(players[0].resetCount, 1);
  assert.equal(files.size, 0); assert.equal(task.ready, false);

  const next = new HttpTtsPlayer();
  const nextSpeech = next.speak({ cacheDir: '/cache' }, {}, '下一段。', 1, 'next', () => started++, output);
  await settle(); respond(requests[1]); await settle();
  assert.equal(players.length, 1); assert.equal(started, 2);
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
  stopped.cancel(); await stoppedResult;
  assert.equal(players[1].released, true); assert.equal(files.size, 0);
  const retryStart = requests.length;
  const retry = new HttpTtsPlayer(0.01, 1);
  await assert.rejects(retry.prepare({}, '超时重试。', 3), /timed out/);
  assert.equal(requests.length - retryStart, 2, 'retry count is bounded even when the provider never responds');
  assert.ok(requests.slice(retryStart).every(req => req.destroyed && req.options.readTimeout === 10));
  const stopRetry = new HttpTtsPlayer(30, 3);
  const stopRetryResult = stopRetry.prepare({}, '取消重试。', 3);
  const cancelledRetry = assert.rejects(stopRetryResult, /cancelled/);
  await settle();
  requests.at(-1).reject(new Error('offline')); await settle();
  const beforeCancel = requests.length;
  stopRetry.cancel(); await cancelledRetry;
  assert.equal(requests.length, beforeCancel, 'cancellation clears retry backoff without issuing another request');
  console.log('PASS 连续片段复用同一播放器、停止释放、预取不播放、合成去重、取消迟到请求和临时文件释放');
})().catch(error => { console.error(error); process.exitCode = 1; });
