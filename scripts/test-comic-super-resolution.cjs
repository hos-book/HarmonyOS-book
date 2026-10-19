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
  const state = { enabled: false, api: 26, capable: true, downloads: 0, created: 0,
    destroyed: 0, releasedInput: 0, releasedOutput: 0, releasedSource: 0,
    size: 300, frames: 1, fail: false, active: true, duringProcess: () => {} };
  const files = new Map();
  const settings = new Map();
  const store = { get: async (k, d) => settings.has(k) ? settings.get(k) : d,
    put: async (k, v) => settings.set(k, v), flush: async () => {
      if (state.flushFails) throw Error('disk full');
    } };
  const input = { release: async () => state.releasedInput++ };
  const output = { release: async () => state.releasedOutput++, getImageInfo: async () => ({
    size: { width: state.size * 2, height: state.size * 2 }
  }) };
  const mocks = {
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
    '@kit.CoreFileKit': { fileUri: { getUriFromPath: p => `file://${p}`, FileUri: class { constructor(uri) { this.path = uri.slice(7); } } }, fileIo: {
      stat: async () => ({size: 1024, mtime: 1}), OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 }, access: async p => files.has(p),
      mkdir: async p => files.set(p, null), open: async p => { files.set(p, ''); return { fd: p }; },
      write: async (p, data) => data.byteLength, close: async () => {},
      rename: async (a, b) => { files.set(b, files.get(a)); files.delete(a); },
      unlink: async p => files.delete(p), listFile: async dir => [...files.keys()]
        .filter(p => p.startsWith(`${dir}/`)).map(p => path.posix.basename(p))
    } },
    '@kit.ImageKit': { image: { PixelMapFormat: { RGBA_8888: 1 }, createImageSource: () => ({
      getImageInfo: async () => ({ size: { width: state.size, height: state.size } }),
      getFrameCount: async () => state.frames, createPixelMap: async () => input,
      release: async () => state.releasedSource++
    }), createImagePacker: () => ({ packToData: async () => new ArrayBuffer(64), release: async () => {} }) } },
    '@kit.CoreVisionKit': { imageSuperResolution: { ImageSRAnalyzer: { create: async () => {
      state.created++;
      return { process: async () => {
        await state.duringProcess();
        if (state.fail) throw Error('engine unsupported');
        return { pixelMap: output };
      }, destroy: async () => state.destroyed++ };
    } } } },
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
      canIUse: () => state.capable, console: { warn() {} }, Uint8Array, setTimeout, clearTimeout });
    return exports;
  }
  const preference = load('service/PreferenceService').PreferenceService;
  preference.store = store;
  mocks['./PreferenceService'] = { PreferenceService: preference };
  const service = load('service/ComicSuperResolutionService').ComicSuperResolutionService;
  const run = url => service.enhance({ cacheDir: '/cache' }, url || 'file:///cache/comic_images/cover.jpg', () => state.active);
  return { state, files, preference, service, run };
}
(async () => {
  const h = setup();
  assert.equal(await h.preference.getComicSuperResolution(), false);
  assert.equal(await h.run(), '');
  assert.equal(h.state.downloads, 0, 'off does not download');
  await h.preference.setComicSuperResolution(true);
  h.state.api = 20;
  assert.equal(await h.run(), '');
  assert.equal(h.state.created, 0, 'old systems never enter native engine');
  h.state.api = 26;
  h.state.capable = false;
  assert.equal(await h.run(), '');
  h.state.capable = true;
  assert.match(await h.run(), /^file:\/\/\/cache\/comic_super_resolution_v1\/[a-f0-9]{64}\.jpg$/);
  assert.equal(h.state.created, 1);
  await h.run();
  assert.equal(h.state.created, 1, 'cache hit avoids processing');
  assert.equal(h.state.downloads, 0, 'local comic processing never downloads or uploads images');
  const remote = setup();
  await remote.preference.setComicSuperResolution(true);
  assert.match(await remote.run('https://source/remote.jpg'), /^file:/);
  assert.equal(remote.state.downloads, 1, 'ordinary remote comic images enter the bounded processor');
  assert.equal(h.state.destroyed, 1);
  assert.equal(h.state.releasedInput, 1);
  assert.equal(h.state.releasedOutput, 1);
  h.state.fail = true;
  assert.equal(await h.run('file:///cache/comic_images/fail.jpg'), '');
  assert.equal(h.state.destroyed, 2, 'failed native processing releases engine');
  assert.equal(h.state.releasedInput, 2);
  h.state.fail = false;
  h.state.size = 5000;
  assert.equal(await h.run('file:///cache/comic_images/large.jpg'), '');
  assert.equal(h.state.created, 2, 'already large images skip enhancement');
  h.state.size = 300;
  h.state.frames = 2;
  assert.equal(await h.run('file:///cache/comic_images/animated.gif'), '');
  h.state.frames = 1;
  h.state.duringProcess = () => { h.state.active = false; };
  assert.equal(await h.run('file:///cache/comic_images/leaving.jpg'), '');
  assert.equal(h.state.releasedOutput, 2, 'late output is released after leaving');
  h.state.active = true;
  h.state.duringProcess = () => h.preference.setComicSuperResolution(false);
  assert.equal(await h.run('file:///cache/comic_images/disabled.jpg'), '');
  h.state.duringProcess = () => {};
  await h.preference.setComicSuperResolution(true);
  for (let i = 0; i < 15; i++) await h.run(`file:///cache/comic_images/${i}.jpg`);
  assert.equal([...h.files.keys()].filter(p => p.endsWith('.jpg')).length, 12, 'cache bounded to 12 outputs');
  assert.equal([...h.files.keys()].filter(p => p.endsWith('.tmp')).length, 0);
  h.state.flushFails = true;
  await assert.rejects(h.preference.setComicSuperResolution(false));
  assert.equal(await h.preference.getComicSuperResolution(), true, 'failed save rolls back in-memory preference');
  console.log('Comic super resolution regression passed: opt-in, compatibility, cache, failure, cancellation, cleanup');
})().catch(error => { console.error(error); process.exitCode = 1; });
