const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const files = new Map([['/cache/comic_images/page.jpg', new Uint8Array([1,2,3]).buffer]]);
const handles = new Map();
let next = 0, requests = 0, active = 0, maxActive = 0, gate, fail = false, badRatio = false;
let resources = 0, holds = 0, writers = 0, decodes = 0, encodes = 0;
let member = true;
let loads = 0, onlineRequests = 0;
let lastOperation;
const config = { baseUrl: 'https://example.test/v1', apiKey: 'fixture', model: 'user-model' };
const configService = {
  revision: 0, load: async () => { loads++; return config; },
  edit: async (selectedConfig, _jpeg, cancelled, targetLanguage) => {
    lastOperation = { targetLanguage, config: selectedConfig };
    requests++; active++; maxActive = Math.max(active, maxActive);
    try {
      if (gate) await gate;
      if (cancelled()) throw Error('comic_ai_cancelled');
      if (fail) throw Error('comic_ai_forbidden');
      return new Uint8Array([255,216,255]);
    } finally { active--; }
  }
};
const perform = configService.edit;
configService.edit = (...args) => { onlineRequests++; return perform(...args); };
const image = {
  createImageSource: value => {
    decodes++;
    resources++;
    return {
      getImageInfo: async () => ({ size: typeof value === 'string' || !badRatio ? { width: 800, height: 1200 } : { width: 800, height: 800 } }),
      getFrameCount: async () => 1,
      createPixelMap: async () => { resources++; return { release: async () => { resources--; } }; },
      release: async () => { resources--; }
    };
  },
  createImagePacker: () => { resources++; encodes++; return { packToData: async () => new Uint8Array([4,5,6]).buffer,
    release: async () => { resources--; } }; },
  PixelMapFormat: { RGBA_8888: 1 }
};
const fileIo = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
  stat: async name => { if (!files.has(name)) throw Error('missing'); return { size: files.get(name).byteLength, mtime: 1 }; },
  access: async name => files.has(name), mkdir: async name => files.set(name, new ArrayBuffer(0)),
  open: async name => { handles.set(++next, name); files.set(name, new ArrayBuffer(0)); return { fd: next }; },
  write: async (fd, bytes) => { files.set(handles.get(fd), bytes); return bytes.byteLength; },
  close: async () => {}, rename: async (a,b) => { files.set(b, files.get(a)); files.delete(a); },
  unlink: async name => { files.delete(name); }
};
const exportsObject = {};
const code = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/service/ComicColorizationService.ets'), 'utf8');
vm.runInNewContext(ts.transpileModule(code, { compilerOptions: { module: ts.ModuleKind.CommonJS,
  target: ts.ScriptTarget.ES2021 } }).outputText, {
  exports: exportsObject, Error, require: name => {
    if (name.endsWith('ComicOfflineTranslationService')) return { ComicOfflineTranslationService: { MODEL: 'offline-fixture', validateDirection: code => { if (!['ja-zh','ko-zh','en-zh','zh-en'].includes(code)) throw Error('comic_offline_language'); } } };
    if (name.endsWith('/model/ComicAiConfig')) return { ComicAiConfig: class { constructor() { this.baseUrl='';this.model='';this.apiKey=''; } } };
    if (name.endsWith('MembershipState')) return { MembershipState: { current: { get hasAccess() { return member; } } } };
    if (name.endsWith('ComicAiConfigService')) return { ComicAiConfigService: configService };
    if (name.endsWith('ComicTranslationService')) return { ComicTranslationService: {
      translatePixels: (pixels, width, height, language, active) => {
        assert.equal(width,800); assert.equal(height,1200);
        return perform({}, pixels, () => !active(), language);
      }
    } };
    if (name.endsWith('ReaderCacheService')) return { ReaderCacheService: { configure() {}, record: async () => {},
      hold() { holds++; }, unhold() { holds--; }, beginComicWrite() { writers++; }, endComicWrite() { writers--; } } };
    if (name === '@kit.ImageKit') return { image };
    if (name === '@kit.CoreFileKit') return { fileIo, fileUri: {
      FileUri: class { constructor(uri) { this.path = uri.slice(7); } }, getUriFromPath: p => 'file://' + p
    } };
    if (name === '@kit.ArkTS') return { buffer: Buffer, util: { TextEncoder: class { encodeInto(t) { return new TextEncoder().encode(t); } } } };
    if (name === '@kit.CryptoArchitectureKit') return { cryptoFramework: { createMd: () => {
      const hash = crypto.createHash('sha256');
      return { update: async blob => hash.update(blob.data), digest: async () => ({ data: hash.digest() }) };
    } } };
    return {};
  }
});
const service = exportsObject.ComicColorizationService;
const context = { cacheDir: '/cache' }, uri = 'file:///cache/comic_images/page.jpg';
(async () => {
  member = false;
  assert.equal(await service.colorize(context, uri, () => true), '');
  assert.equal(requests, 0, 'non-members cannot upload images');
  member = true;
  assert.equal(await service.colorize(context, uri, () => false), '');
  assert.equal(requests, 0);
  const colored = await service.colorize(context, uri, () => true);
  assert.ok(colored.startsWith('file:///cache/comic_colorization_v1/'));
  assert.deepEqual([...new Uint8Array(files.get(uri.slice(7)))], [1,2,3], 'the original file is untouched');
  assert.equal(await service.colorize(context, uri, () => true), colored);
  assert.equal(requests, 1, 'cached pages do not spend another image request');
  member = false;
  assert.equal(await service.colorize(context, uri, () => true), '', 'non-members cannot reuse colored cache');
  assert.equal(requests, 1);
  member = true;
  config.model = 'another-model'; configService.revision++;
  const changed = await service.colorize(context, uri, () => true);
  assert.notEqual(changed, colored, 'cache is separated by endpoint and model');
  assert.equal(requests, 2);
  const beforeTranslation = requests;
  const beforeOnline = onlineRequests, beforeLoads = loads;
  const beforeDecodes = decodes, beforeEncodes = encodes;
  const translated = await service.transform(context, uri, () => true, 'en-zh');
  assert.equal(decodes-beforeDecodes,1,'translation decodes the source only once');
  assert.equal(encodes-beforeEncodes,0,'translation never recompresses before OCR or after local rendering');
  assert.notEqual(translated, changed, 'translation does not reuse the colored image');
  assert.deepEqual(lastOperation, { targetLanguage: 'en-zh', config: {} });
  assert.equal(onlineRequests,beforeOnline,'translation never calls the online image API');
  assert.equal(loads,beforeLoads,'translation never reads API credentials');
  assert.equal(await service.transform(context, uri, () => true, 'en-zh'), translated);
  assert.equal(requests, beforeTranslation + 1, 'revisiting a translated page reuses its cache');
  const english = await service.transform(context, uri, () => true, 'zh-en');
  assert.notEqual(english, translated, 'target languages have separate caches');
  assert.equal(await service.colorize(context, uri, () => true), changed, 'switching back restores the color-only result');
  assert.equal(requests, beforeTranslation + 2);
  assert.deepEqual([...new Uint8Array(files.get(uri.slice(7)))], [1,2,3], 'translation preserves the original');
  await assert.rejects(service.transform(context, uri, () => true, 'invalid'), /offline_language/);
  config.model = 'cancelled-model'; configService.revision++;
  let release, stopped = false;
  gate = new Promise(resolve => { release = resolve; });
  const pending = service.transform(context, uri, () => !stopped, 'ko-zh');
  while (!active) await new Promise(resolve => setImmediate(resolve));
  stopped = true; release();
  assert.equal(await pending, ''); gate = undefined;
  config.model = 'revoked-model'; configService.revision++;
  gate = new Promise(resolve => { release = resolve; });
  const revoked = service.colorize(context, uri, () => true);
  while (!active) await new Promise(resolve => setImmediate(resolve));
  const queued = service.colorize(context, uri, () => true);
  const beforeRevocation = requests;
  member = false; release();
  assert.equal(await revoked, '', 'revocation cancels in-flight application');
  assert.equal(await queued, '', 'queued work rechecks membership');
  assert.equal(requests, beforeRevocation, 'revocation prevents queued upload');
  gate = undefined; member = true;
  config.model = 'bad-model'; configService.revision++; fail = true;
  await assert.rejects(service.colorize(context, uri, () => true), /forbidden/);
  const afterError = requests;
  assert.equal(await service.colorize(context, uri, () => true), '');
  assert.equal(requests, afterError, 'an API failure blocks the rest of the reading queue');
  fail = false; service.resetFailure(); badRatio = true;
  await assert.rejects(service.colorize(context, uri, () => true), /invalid_image/);
  assert.equal(resources, 0); assert.equal(writers, 0); assert.equal(holds, 0);
  assert.equal(maxActive, 1);
  assert.ok(![...files.keys()].some(name => name.endsWith('.tmp')));
  console.log('comic AI images: original preserved, model/language/operation cache isolation, translation cancellation, error circuit breaker and resource release passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
