// Exercise the real service with deterministic native engine and file adapters.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
function setup() {
  const state = { member: true, membershipFails: false, enabled: false, api: 26, capable: true, downloads: 0, created: 0,
    releasedInput: 0, releasedSource: 0, writes: 0, widths: [], decoded: [],
    size: 300, frames: 1, fail: false, active: true, duringProcess: () => {} };
  const files = new Map();
  const settings = new Map();
  const store = { get: async (k, d) => settings.has(k) ? settings.get(k) : d,
    put: async (k, v) => settings.set(k, v), flush: async () => {
      if (state.flushFails) throw Error('disk full');
    } };
  const input = { release: async () => state.releasedInput++ };
  const mocks = {
    '../model/MembershipState': { MembershipState: { current: { get hasAccess() { return state.member; } } } },
    './MembershipService': { MembershipService: { instance: { hasCurrentEntitlement: async () => {
      if (state.membershipFails) throw new Error('verification unavailable');
      return state.member;
    } } } },
    './ComicAiHost': { ComicAiHost: { install() {} } },
    './ReaderCacheService': { ReaderCacheService: { configure() {},
      beginComicWrite() { state.writes++; }, endComicWrite() { state.writes--; },
      hold() {}, unhold() {}, record: async () => {} } },
    '@kit.AbilityKit': { ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: -1 } } },
    '@kit.BasicServicesKit': { emitter: { emit: () => {} } },
    '@kit.ArkData': { preferences: {} },
    '@kit.ArkTS': { buffer: { from: Buffer.from }, util: { TextEncoder: class {
      encodeInto(text) { return new Uint8Array(Buffer.from(text)); }
    } } },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd: () => {
      const hash = crypto.createHash('sha256');
      return { update: async ({ data }) => hash.update(data), digest: async () => ({ data: hash.digest() }) };
    } } },
    '@kit.CoreFileKit': { fileUri: { getUriFromPath: p => `file://${p}`,
      FileUri: class { constructor(uri) { this.path = uri.slice(7); } } }, fileIo: {
      OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 }, access: async p => files.has(p),
      mkdir: async p => files.set(p, null), open: async p => { files.set(p, ''); return { fd: p }; },
      write: async (p, data) => data.byteLength, close: async () => {},
      stat: async () => ({ size: 64 }), copyFile: async (_a, b) => files.set(b, 'enhanced'),
      rename: async (a, b) => { files.set(b, files.get(a)); files.delete(a); },
      unlink: async p => files.delete(p), listFile: async dir => [...files.keys()]
        .filter(p => p.startsWith(`${dir}/`)).map(p => path.posix.basename(p))
    } },
    '@kit.ImageKit': { image: { PixelMapFormat: { RGBA_8888: 1 }, createImageSource: () => ({
      getImageInfo: async () => ({ size: { width: state.size, height: state.size } }),
      getFrameCount: async () => state.frames, createPixelMap: async options => {
        state.decoded.push(options.desiredSize); return input;
      },
      release: async () => state.releasedSource++
    }), createImagePacker: () => ({ packToData: async () => new ArrayBuffer(64), release: async () => {} }) } },
    '@legado/aiengine': { ReaderComicSuperResolution: { enhance: async (url, width, active) => {
      state.created++;
      state.widths.push(width);
      assert.match(url, /\.input$/);
      assert.equal(state.writes, 1);
      assert.equal(active(), true);
      await state.duringProcess();
      if (state.fail) throw Error('engine unsupported');
      return 'file:///cache/comic_images/sr_fixture.jpg';
    } } },
    '../utils/PlatformCompat': { PlatformCompat: { supports: n => state.api >= n } },
    './CoverPrefetcher': { CoverPrefetcher: { loadOriginal: async () => {
      state.downloads++; return new ArrayBuffer(4);
    } } }
  };
  function load(relative) {
    const source = fs.readFileSync(path.join(root, relative + '.ets'), 'utf8').replace(/import lazy /g, 'import ');
    const exports = {};
    const js = ts.transpileModule(source, { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
    } }).outputText;
    vm.runInNewContext(js, { exports, require: name => mocks[name] || {},
      canIUse: () => state.capable, console: { warn() {}, info() {} }, Uint8Array });
    return exports;
  }
  const preference = load('service/PreferenceService').PreferenceService;
  preference.store = store;
  mocks['./PreferenceService'] = { PreferenceService: preference };
  const service = load('service/CoverSuperResolutionService').CoverSuperResolutionService;
  const run = url => service.enhance({ cacheDir: '/cache' }, url || 'https://source/cover.jpg', () => state.active);
  return { state, files, preference, service, run };
}
(async () => {
  // Exercise the actual UI binding against the service: displayed files are local,
  // but enhancement must retain the source URL (including imported-source tokens).
  const playerSource = fs.readFileSync(path.join(root, 'components/PlayerCoverImage.ets'), 'utf8');
  const binding = playerSource.match(/EnhancedPlayerCover\(\{ url: (.+) \}\)/);
  assert.ok(binding, 'player must wire its cover to enhancement');
  const boundUrl = new Function(`return (${binding[1]});`);
  const player = { url: 'https://source/cover.jpg', fallback: 'https://source/fallback.jpg',
    resolvedUrl: 'file:///cache/source_covers/main.img',
    resolvedFallback: 'file:///cache/source_covers/fallback.img',
    failedKey: '', requestKey: () => 'main-request' };
  const wired = setup();
  await wired.preference.setCoverSuperResolution(true);
  assert.equal(boundUrl.call(player), player.url);
  assert.match(await wired.run(boundUrl.call(player)), /^file:/, 'cached displayed cover reaches native SR');
  assert.equal(wired.state.created, 1);
  player.failedKey = player.requestKey();
  assert.equal(boundUrl.call(player), player.fallback);
  assert.match(await wired.run(boundUrl.call(player)), /^file:/, 'failed main cover enhances the fallback');
  assert.equal(wired.state.created, 2);
  player.resolvedFallback = '';
  assert.equal(boundUrl.call(player), player.url, 'unresolved fallback must not replace the main source');

  const gate = setup();
  gate.state.member = false;
  await assert.rejects(gate.preference.setCoverSuperResolution(true), /MEMBERSHIP_REQUIRED/);
  assert.equal(await gate.run(), '');
  assert.equal(gate.state.created, 0);
  gate.state.member = true;
  await gate.preference.setCoverSuperResolution(true);
  assert.match(await gate.run(), /^file:/);
  const created = gate.state.created;
  gate.state.member = false;
  assert.equal(await gate.preference.getCoverSuperResolution(), false, 'saved switch cannot bypass membership');
  assert.equal(await gate.run(), '', 'cached enhanced image is blocked without membership');
  assert.equal(gate.state.created, created);
  await gate.preference.setCoverSuperResolution(false);
  gate.state.member = true;
  await gate.preference.setCoverSuperResolution(true);
  gate.state.membershipFails = true;
  assert.equal(await gate.run(), '', 'verification failure falls back to original');
  gate.state.membershipFails = false;
  gate.state.duringProcess = () => { gate.state.member = false; };
  assert.equal(await gate.run('https://source/revoked.jpg'), '', 'revoked membership discards in-flight output');
  assert.equal(gate.state.writes, 0);

  const h = setup();
  assert.equal(await h.preference.getCoverSuperResolution(), false);
  assert.equal(await h.run(), '');
  assert.equal(h.state.downloads, 0, 'off does not download');
  await h.preference.setCoverSuperResolution(true);
  h.state.api = 20;
  assert.equal(await h.run(), '');
  assert.equal(h.state.created, 0, 'old systems never enter native engine');
  h.state.api = 26;
  h.state.capable = false;
  assert.equal(await h.run(), '');
  h.state.capable = true;
  assert.match(await h.run(), /^file:\/\/\/cache\/cover_super_resolution_v2\/[a-f0-9]{64}\.jpg$/);
  assert.equal(h.state.created, 1);
  await h.run();
  assert.equal(h.state.downloads, 1, 'cache hit avoids downloading and processing');
  assert.equal(h.state.writes, 0);
  assert.equal(h.state.releasedSource, 1);
  h.state.fail = true;
  assert.equal(await h.run('https://source/fail.jpg'), '');
  assert.equal(h.state.writes, 0, 'failed native processing ends the cache write');
  assert.equal(h.state.releasedSource, 2);
  h.state.fail = false;
  h.state.size = 1500;
  assert.match(await h.run('https://source/large.jpg'), /^file:/);
  assert.equal(h.state.widths.at(-1), 1500, '1500px blurry cover must exceed HAR minimum gain');
  assert.equal(h.state.decoded.length, 0, '1500px original is not downsampled');
  h.state.size = 4096;
  assert.match(await h.run('https://source/oversized.jpg'), /^file:/);
  assert.equal(h.state.decoded[0].width, 2048, 'large cover uses bounded decoding');
  assert.equal(h.state.releasedInput, 1);
  h.state.size = 10000;
  const beforeBomb = h.state.created;
  assert.equal(await h.run('https://source/bomb.jpg'), '');
  assert.equal(h.state.created, beforeBomb, 'decompression budget enforced');
  h.state.size = 300;
  h.state.frames = 2;
  assert.equal(await h.run('https://source/animated.gif'), '');
  h.state.frames = 1;
  h.state.duringProcess = () => { h.state.active = false; };
  assert.equal(await h.run('https://source/leaving.jpg'), '');
  assert.equal(h.state.writes, 0, 'late output releases cache write after leaving');
  h.state.active = true;
  h.state.duringProcess = () => h.preference.setCoverSuperResolution(false);
  assert.equal(await h.run('https://source/disabled.jpg'), '');
  h.state.duringProcess = () => {};
  await h.preference.setCoverSuperResolution(true);
  for (let i = 0; i < 15; i++) await h.run(`https://source/${i}.jpg`);
  assert.equal([...h.files.keys()].filter(p => p.endsWith('.jpg')).length, 12, 'cache bounded to 12 outputs');
  assert.equal([...h.files.keys()].filter(p => p.endsWith('.tmp')).length, 0);
  assert.equal([...h.files.keys()].filter(p => p.endsWith('.input')).length, 0, 'staged original always removed');
  h.state.flushFails = true;
  await assert.rejects(h.preference.setCoverSuperResolution(false));
  assert.equal(await h.preference.getCoverSuperResolution(), true, 'failed save rolls back in-memory preference');
  console.log('Cover super resolution regression passed: opt-in, compatibility, cache, failure, cancellation, cleanup');
})().catch(error => { console.error(error); process.exitCode = 1; });
