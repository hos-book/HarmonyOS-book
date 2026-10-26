// Exercise the actual host facade. Tiling/inference lives in the pinned Light Page HAR.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/service/ComicSuperResolutionService.ets'), 'utf8').replace(/import lazy /g, 'import ');
const settle = async () => { for (let i = 0; i < 40; i++) await Promise.resolve(); };
function harness() {
  const state = { enabled: false, member: true, api: 26, capable: true, active: true,
    size: 1024, fail: false, preferenceFails: false, installed: 0, writes: 0, operation: async () => {} };
  const calls = [], records = [], held = new Set(), timers = new Map();
  let timer = 0;
  const mocks = {
    '@kit.CoreFileKit': { fileIo: { stat: async () => ({ size: state.size }) },
      fileUri: { FileUri: class { constructor(uri) { this.path = uri.slice(7); } } } },
    '@legado/aiengine': { ReaderComicSuperResolution: { enhance: async (url, width, active) => {
      calls.push({ url, width, active });
      assert.equal(held.has(url), true, 'original stays protected during native work');
      assert.ok(state.installed > 0);
      await state.operation();
      if (state.fail) throw Error('native unavailable');
      return `file:///cache/comic_images/sr_fixture_${width}.jpg`;
    } } },
    '../utils/PlatformCompat': { PlatformCompat: { supports: level => state.api >= level } },
    './PreferenceService': { PreferenceService: { getComicSuperResolution: async () => {
      if (state.preferenceFails) throw Error('entitlement unavailable');
      return state.enabled;
    } } },
    '../model/MembershipState': { MembershipState: { current: { get hasAccess() { return state.member; } } } },
    './ComicAiHost': { ComicAiHost: { install: () => { state.installed++; } } },
    './ReaderCacheService': { ReaderCacheService: {
      beginComicWrite: () => { state.writes++; }, endComicWrite: () => { state.writes--; },
      hold: url => held.add(url), unhold: url => held.delete(url), record: async paths => records.push(...paths)
    } }
  };
  const exportsValue = {};
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  } }).outputText, { exports: exportsValue, require: name => {
    assert.ok(name in mocks, `unexpected native implementation dependency: ${name}`); return mocks[name];
  }, canIUse: () => state.capable, console: { warn() {} },
  setTimeout: callback => { timers.set(++timer, callback); return timer; }, clearTimeout: id => timers.delete(id) });
  const service = exportsValue.ComicSuperResolutionService;
  return { state, calls, records, held, timers, service,
    run: (width = 1080, url = 'file:///cache/comic_images/original.jpg') =>
      service.enhance({ cacheDir: '/cache' }, url, () => state.active, width) };
}
(async () => {
  const h = harness();
  assert.equal(await h.run(), '');
  h.state.enabled = true; h.state.api = 20;
  assert.equal(await h.run(), '');
  h.state.api = 26; h.state.capable = false;
  assert.equal(await h.run(), '');
  h.state.capable = true; h.state.member = false;
  assert.equal(await h.run(), '');
  h.state.member = true; h.state.preferenceFails = true;
  assert.equal(await h.run(), '');
  assert.equal(h.calls.length, 0, 'off/unsupported/unverified requests do not initialize HAR');
  h.state.preferenceFails = false;
  for (const url of ['https://source/image.jpg', 'file:///private/image.jpg',
    'file:///cache/comic_images/../private.jpg']) assert.equal(await h.run(1080, url), '');
  for (const width of [NaN, Infinity, 0, 63]) assert.equal(await h.run(width), '');
  h.state.size = 21 * 1024 * 1024;
  assert.equal(await h.run(), '');
  h.state.size = 1024;
  assert.equal(await h.run(1080.2), 'file:///cache/comic_images/sr_fixture_1080.jpg');
  assert.equal(await h.run(1440), 'file:///cache/comic_images/sr_fixture_1440.jpg');
  assert.deepEqual(h.calls.map(call => call.width), [1080, 1440], 'actual display pixels key the HAR cache');
  assert.equal(h.records.length, 2);
  assert.equal(h.state.writes, 0); assert.equal(h.held.size, 0); assert.equal(h.timers.size, 0);
  h.state.fail = true;
  assert.equal(await h.run(), '');
  assert.equal(h.state.writes, 0); assert.equal(h.held.size, 0);
  h.state.fail = false;
  h.state.operation = async () => { h.state.member = false; };
  assert.equal(await h.run(), '', 'late revoked output is not displayed');
  h.state.member = true;
  h.state.operation = async () => { h.state.enabled = false; };
  assert.equal(await h.run(), '', 'disabled output is not displayed');

  const queued = harness(); queued.state.enabled = true;
  let release;
  queued.state.operation = () => new Promise(resolve => { release = resolve; });
  const first = queued.run(); await settle();
  const second = queued.run(); const third = queued.run(); const fourth = queued.run();
  assert.equal(await queued.run(), '', 'pending work is bounded');
  assert.equal(queued.calls.length, 1, 'native jobs remain serial');
  queued.state.active = false; release();
  assert.deepEqual(await Promise.all([first, second, third, fourth]), ['', '', '', '']);
  assert.equal(queued.calls.length, 1, 'stale queued pages never enter the engine');
  assert.equal(queued.held.size, 0);

  const timeout = harness(); timeout.state.enabled = true;
  let finish;
  timeout.state.operation = () => new Promise(resolve => { finish = resolve; });
  const expired = timeout.run(); await settle();
  timeout.timers.values().next().value();
  assert.equal(await expired, '');
  assert.equal(timeout.calls[0].active(), false, 'timeout cancels the next native tile');
  assert.equal(await timeout.run(), '', 'a hung native call cannot start another job');
  finish(); await settle();
  assert.equal(timeout.state.writes, 0); assert.equal(timeout.held.size, 0);
  timeout.state.operation = async () => {};
  assert.match(await timeout.run(), /^file:/, 'completed cleanup permits a later retry');
  console.log('PASS comic SR HAR: display width, source bounds, live permission, queue/timeout cancellation, cache accounting and recovery');
})().catch(error => { console.error(error); process.exitCode = 1; });
