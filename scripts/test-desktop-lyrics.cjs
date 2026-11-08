// Real LRC conversion and AVSession lifecycle; platform IPC is simulated, no device is modified.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
function load(name, imports = {}) {
  const source = fs.readFileSync(path.join(root, name), 'utf8').replace(/import lazy /g, 'import ').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const module = { exports: {} };
  const code = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  } }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, console, Date, Promise, Map, Set,
    $r: id => ({ id }), require: name => {
      if (!(name in imports)) throw new Error(`Missing dependency: ${name}`);
      return imports[name];
    }
  });
  return module.exports;
}
const subtitles = load('model/AudioSubtitle.ets');
const lyric = load('model/DesktopLyric.ets', { './AudioSubtitle': subtitles });
const flush = async () => { for (let i = 0; i < 25; i++) await Promise.resolve(); };
function fixture(api = 26, supported = true) {
  const calls = [];
  const membership = { hasAccess: true };
  let revokeMembership;
  const coordinator = { speechActive: false };
  let visible = false, locked = false, enabled = false, visibilityCallback;
  let enableWait = null, failShow = false;
  const native = new Proxy({
    async setAVMetadata(value) {
      // Native AVSession treats a present-but-undefined duration as invalid metadata.
      if ('duration' in value && !Number.isFinite(value.duration)) throw new Error('get metaData failed');
      calls.push(['metadata', { ...value }]);
    },
    async enableDesktopLyric(value) {
      if (value && enableWait) await enableWait;
      enabled = value; calls.push(['enable', value]);
    },
    async setDesktopLyricVisible(value) {
      if (value && failShow) throw new Error('native show failed');
      visible = value; calls.push(['visible', value]); visibilityCallback?.(value);
    },
    async isDesktopLyricVisible() { return visible; },
    async setDesktopLyricState(value) { locked = value.isLocked; },
    async getDesktopLyricState() { return { isLocked: locked }; },
    onDesktopLyricVisibilityChanged(callback) { visibilityCallback = callback; },
    async setAVPlaybackState(value) { calls.push(['playback', value]); },
    async destroy() { calls.push(['destroy']); },
  }, { get(target, key) { return key === 'then' ? undefined : key in target ? target[key] : () => {}; } });
  const avSession = { createAVSession: async () => native,
    isDesktopLyricSupported: async () => { calls.push(['supported']); return supported; },
    PlaybackState: { PLAYBACK_STATE_PAUSE: 3, PLAYBACK_STATE_PLAY: 2 },
    LoopMode: { LOOP_MODE_SEQUENCE: 0, LOOP_MODE_LIST: 1, LOOP_MODE_SINGLE: 2 }
  };
  const { AVSessionService } = load('service/AVSessionService.ets', {
    './MembershipService': { MembershipService: { instance: { hasCurrentEntitlement: async () => membership.hasAccess } } },
    '../model/MembershipState': { MembershipState: { current: membership } },
    './membership/MembershipFeatureLease': { MembershipFeatureLease: class {
      start(revoke) { revokeMembership = revoke; }
      stop() { revokeMembership = undefined; }
    } },
    './SourceCoverService': { SourceCoverService: { isEncoded: () => false } },
    './LocalBookCoverService': { LocalBookCoverService: { resolve: async () => '' } },
    './CoverPrefetcher': { CoverPrefetcher: { loadOriginal: async () => new ArrayBuffer(0) } },
    './PlaybackCoordinator': { PlaybackCoordinator: coordinator },
    '../model/DesktopLyric': lyric,
    '@kit.AVSessionKit': { avSession },
    '../utils/PlatformCompat': { PlatformCompat: { supports: n => api >= n, wearable: false } },
    '@kit.ImageKit': {}, '@kit.NetworkKit': {}, '@kit.CoreFileKit': {},
    '@kit.AbilityKit': { wantAgent: { getWantAgent: async () => ({}),
      OperationType: { START_ABILITY: 0 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 0 } } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn() {}, error() {} } }
  });
  const service = AVSessionService.getInstance();
  const context = { abilityInfo: { bundleName: 'fixture', name: 'EntryAbility' },
    resourceManager: { getStringSync: () => '正在准备字幕' } };
  const book = { id: 'book', title: '测试书', author: '作者', cover: '' };
  const chapter = { id: 'chapter', title: '第一章', duration: 120 };
  service.coverCache.set('avsession://cover-placeholder', {});
  return { service, coordinator, calls, book, chapter, membership,
    revoke() { membership.hasAccess = false; revokeMembership?.(); },
    async ready() { await service.init(context); await service.updateMetadata(book, chapter); },
    userHide() { visible = false; visibilityCallback(false); },
    setEnableWait(promise) { enableWait = promise; },
    setFailShow(value) { failShow = value; },
    enabled: () => enabled,
    visible: () => visible
  };
}
async function main() {
  const vip = fixture();
  await vip.ready();
  vip.membership.hasAccess = false;
  assert.equal(await vip.service.setDesktopLyricVisible(true), false);
  assert.equal(vip.enabled(), false, 'nonmember cannot enable native lyrics');
  vip.membership.hasAccess = true;
  assert.equal(await vip.service.setDesktopLyricVisible(true), true);
  vip.revoke(); await flush();
  assert.equal(vip.visible(), false, 'membership expiry hides the window');
  assert.equal(vip.enabled(), false, 'membership expiry disables native lyrics');
  assert.equal(lyric.DesktopLyricText.stamp(61234), '[01:01.23]');
  assert.equal(lyric.DesktopLyricText.stamp(NaN), '[00:00.00]');
  assert.equal(lyric.DesktopLyricText.clean('[01:00.00]文本\n下一句'), '［01:00.00］文本 下一句');
  const cues = Array.from({ length: 120 }, (_, i) => new subtitles.SubtitleCue(String(i), i * 2000, i * 2000 + 1000, `句${i}`));
  const lrc = lyric.DesktopLyricText.audio(cues, 161500);
  assert(lrc.includes('[02:40.00]句80'));
  assert(lrc.includes('[02:41.00] '), 'silent gaps clear the old cue');
  assert(!lrc.includes(']句0\n'), 'seeking into a distant silent gap keeps the nearby timeline');
  assert(lyric.DesktopLyricText.audio(cues, 1000).length < 16000, 'bounded metadata payload');
  const content = '第一句。第二句！' + '长'.repeat(150);
  assert.equal(lyric.DesktopLyricText.speech(content, 5), '第二句！');
  assert.equal(lyric.DesktopLyricText.speech('\n  第一行。第二行。', 0), '第一行。');
  assert.equal(lyric.DesktopLyricText.speech('第一行。第二行。', NaN), '第一行。');
  assert.equal(lyric.DesktopLyricText.speech(content, 9), lyric.DesktopLyricText.speech(content, 15), 'no per-character sliding');

  for (const [api, supported] of [[20, true], [26, false]]) {
    const f = fixture(api, supported); await f.ready();
    assert.equal(await f.service.setDesktopLyricVisible(true), false);
    assert(!f.calls.some(x => x[0] === 'enable'));
    if (api === 20) assert(!f.calls.some(x => x[0] === 'supported'));
  }
  const f = fixture(); await f.ready();
  f.service.updateDesktopLyric('book', 'chapter', '[00:00.00]正文');
  assert.equal(await f.service.setDesktopLyricVisible(true), true);
  const enabledAt = f.calls.findIndex(x => x[0] === 'enable');
  assert(f.calls.slice(0, enabledAt).some(x => x[0] === 'metadata' && x[1].lyric === '[00:00.00]正文'));
  await f.service.updatePlaybackState(false, 3500, 1.5, 120000);
  assert.equal(f.visible(), true, 'pausing retains desktop lyrics');
  assert.equal(f.calls.filter(x => x[0] === 'destroy').length, 0);
  await f.service.updateMetadataDuration(130000);
  assert.equal(f.calls.filter(x => x[0] === 'metadata').at(-1)[1].lyric, '[00:00.00]正文');
  assert.equal(await f.service.setDesktopLyricLocked(true), true);
  assert.equal(f.service.desktopLyric.locked, true);
  f.userHide();
  await f.service.updateMetadata(f.book, f.chapter);
  assert.equal(f.service.desktopLyric.visible, false, 'metadata refresh cannot reopen a user-hidden window');
  f.coordinator.speechActive = true;
  f.service.updateDesktopLyric('book', 'chapter', '[00:00.00]朗读正文', true);
  await f.service.updateMetadata(f.book, f.chapter, true);
  assert.equal(await f.service.setDesktopLyricVisible(true), true);
  f.service.updateDesktopLyric('book', 'chapter', '[00:00.00]旧音频字幕');
  await f.service.updateMetadata(f.book, f.chapter, true);
  assert.equal(f.calls.filter(x => x[0] === 'metadata').at(-1)[1].lyric, '[00:00.00]朗读正文');
  await f.service.closeDesktopLyric(); await flush();
  assert.equal(f.visible(), false); assert.equal(f.enabled(), false);
  assert.equal(f.calls.filter(x => x[0] === 'metadata').at(-1)[1].lyric, '');

  const failure = fixture(); await failure.ready(); failure.setFailShow(true);
  assert.equal(await failure.service.setDesktopLyricVisible(true), false);
  assert.equal(failure.service.desktopLyric.busy, false);
  failure.setFailShow(false);
  assert.equal(await failure.service.setDesktopLyricVisible(true), true);

  const speech = fixture(); await speech.ready();
  speech.coordinator.speechActive = true;
  speech.chapter.duration = 0;
  await speech.service.updatePlaybackState(true, 0, 1.35, 0, false, true);
  speech.service.updateDesktopLyric('book', 'chapter', '[00:00.00]正在朗读第一句。', true);
  await speech.service.updateMetadata(speech.book, speech.chapter, true);
  assert.equal(await speech.service.setDesktopLyricVisible(true), true, 'TTS with unknown duration can show desktop lyrics');
  speech.service.updateDesktopLyric('book', 'chapter', '[00:00.00]正在朗读第二句。', true);
  await flush();
  const speechMetadata = speech.calls.filter(x => x[0] === 'metadata').at(-1)[1];
  assert.equal(speechMetadata.lyric, '[00:00.00]正在朗读第二句。');
  assert.equal(speechMetadata.singleLyricText, '正在朗读第二句。');
  assert.equal('duration' in speechMetadata, false, 'omit unknown duration instead of sending undefined');
  await speech.service.updatePlaybackState(false, 0, 1.35, 0, false, true);
  assert.equal(speech.visible(), true, 'TTS pause retains the current lyric');
  speech.coordinator.speechActive = false;
  await speech.service.updateMetadata(speech.book, speech.chapter);
  assert.equal(speech.calls.filter(x => x[0] === 'metadata').at(-1)[1].singleLyricText, '', 'audio takeover clears speech single line');

  const racing = fixture(); await racing.ready();
  let release;
  racing.setEnableWait(new Promise(resolve => { release = resolve; }));
  const opening = racing.service.setDesktopLyricVisible(true);
  await flush();
  await racing.service.closeDesktopLyric(); release(); await opening;
  assert.equal(racing.enabled(), false, 'stop wins over a late native enable');
  assert.equal(racing.visible(), false);
  console.log('PASS desktop lyric LRC, capability fallback, pause, metadata merge, ownership, hide/lock, failure and stop race');
}
let finished = false;
process.on('beforeExit', () => { if (!finished) { console.error('Desktop lyric checks did not finish'); process.exitCode = 1; } });
main().then(() => { finished = true; }).catch(error => { finished = true; console.error(error); process.exitCode = 1; });
