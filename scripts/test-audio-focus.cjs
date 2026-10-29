const assert = require('node:assert/strict');
const createFixture = require('./audio-focus-fixture.cjs');
const flush = () => new Promise(resolve => setImmediate(resolve));
let passed = 0;
async function check(name, run) { await run(); console.log(`PASS ${name}`); passed++; }
function setup(api = 26, initialMode = 0) {
  let mode = initialMode;
  const pref = { getAudioFocusMode: async () => mode, setAudioFocusMode: async value => { mode = value; } };
  const fixture = createFixture(pref, {}, { supports: version => api >= version });
  return { ...fixture, preference: pref };
}
(async () => {
  await check('共存使用混音，自动恢复使用暂停策略，API 20 不调用新接口', async () => {
    for (const api of [20, 26]) for (const mode of [0, 1]) {
      const f = setup(api, mode);
      await f.focus.acquire('audio', () => {}, async () => {});
      assert.equal(f.calls.find(call => call[0] === 'activate')[1], mode === 1 ? 1 : 3);
      assert.deepEqual(f.calls.filter(call => call[0] === 'behavior'), api === 26 ? [['behavior', mode === 0 ? 4 : 0]] : []);
      await f.focus.release('audio');
    }
  });
  await check('视频或音乐播放两分钟后停止才恢复，来电重新打断取消旧恢复', async () => {
    const f = setup(20); let pauses = 0, resumes = 0;
    await f.focus.acquire('audio', () => pauses++, async () => { resumes++; });
    f.active.add(f.audio.StreamUsage.STREAM_USAGE_MUSIC); f.emit(2);
    f.advance(120000); assert.equal(resumes, 0); assert.equal(f.timers.size, 1);
    const stale = f.focus.watcher.callback;
    f.emit(1); f.active.clear(); f.active.add(f.audio.StreamUsage.STREAM_USAGE_VOICE_COMMUNICATION);
    stale(); await flush();
    assert.equal(resumes, 0, 'old STOP watcher must not resume during a new call');
    f.active.clear(); f.emit(0); await flush();
    assert.equal(resumes, 1); assert.equal(pauses, 1);
    await f.focus.release('audio'); assert.equal(f.timers.size, 0);
  });
  await check('停止通知恢复覆盖保留 renderer 的暂停；活动查询失败保持暂停', async () => {
    const f = setup(20); let resumes = 0;
    await f.focus.acquire('speech', () => {}, async () => { resumes++; });
    f.active.add(f.audio.StreamUsage.STREAM_USAGE_MOVIE); f.emit(2); f.advance(60000);
    const original = f.stream.isStreamActive;
    f.stream.isStreamActive = () => { throw new Error('system unavailable'); };
    f.active.clear(); f.advance(3000); assert.equal(resumes, 0);
    f.stream.isStreamActive = original; f.advance(2000); await flush();
    assert.equal(resumes, 1); assert.equal(f.timers.size, 0);
  });
  await check('等待时切换偏好不抢播，用户取消后旧回调失效', async () => {
    const f = setup(); let resumes = 0;
    await f.focus.acquire('speech', () => {}, async () => { resumes++; });
    f.emit(2); const stale = f.focus.watcher.callback;
    const count = f.calls.length; await f.focus.setMode(1);
    assert.equal(f.calls.length, count); assert.equal(await f.preference.getAudioFocusMode(), 1);
    await f.focus.release('speech'); stale(); f.emit(0); await flush();
    assert.equal(resumes, 0); assert.equal(f.timers.size, 0);
  });
  await check('音频到朗读的会话切换串行完成，旧播放器不能释放新会话', async () => {
    const f = setup();
    await f.focus.acquire('audio', () => {}, async () => {});
    const releasing = f.focus.release('audio');
    const acquiring = f.focus.acquire('speech', () => {}, async () => {});
    await Promise.all([releasing, acquiring]);
    assert.equal(f.session.activated, true);
    const count = f.calls.length;
    await f.focus.release('audio'); assert.equal(f.calls.length, count);
    await f.focus.release('speech'); assert.equal(f.session.activated, false);
  });
  await check('长合成后的空闲超时在出声前重新申请焦点，暂停后不得申请', async () => {
    const f = setup(20, 1);
    await f.focus.acquire('speech', () => {}, async () => {});
    f.emit(3);
    assert.equal(await f.focus.ensureActive('speech'), true);
    assert.equal(f.calls.filter(call => call[0] === 'activate').length, 2);
    f.emit(1);
    assert.equal(await f.focus.ensureActive('speech'), false);
    await f.focus.release('speech');
    assert.equal(await f.focus.ensureActive('speech'), false);
  });
  console.log(`${passed} audio focus regressions passed`);
})().catch(error => { console.error(error); process.exitCode = 1; });
