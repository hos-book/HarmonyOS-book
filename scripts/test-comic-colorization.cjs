const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));

const uri = 'file:///cache/comic_images/page.jpg';
const importedUri = 'file:///files/ebooks/import_fixture/image_0_1.img';
const files = new Map([[uri.slice(7), new Uint8Array([1, 2, 3]).buffer]]);
const handles = new Map();
let next = 0, resources = 0, holds = 0, writers = 0, decodes = 0;
let member = true, supported = true, fail = false, activeJobs = 0, maxActive = 0;
let gate, engineCalls = 0, translations = 0, idleReleases = 0, lastLanguage = '';
let installedHost, workerPath, decodedPath;
let foregroundEvents = 0, engineForeground = true, memoryNotifications = 0, preparations = 0, preparationActive;
let reconciles = 0, afterEngineResult;
const recorded = [];
const engine = {
  ComicColorModels: { missingBytes() { return 0; }, async download() {} },
  AiRuntime: { install(host) { installedHost = host; } },
  ComicColorizer: {
    releaseIdleWorker() { idleReleases++; },
    setAppForeground(value) { foregroundEvents++; engineForeground = value; },
    onMemoryPressure() { memoryNotifications++; },
    async prepare(context, active) {
      assert.equal(context.cacheDir, '/cache');
      preparations++;
      preparationActive = active;
    },
    async colorize(context, source, active) {
      engineCalls++;
      assert.ok(source === uri || source === importedUri, 'pass the original cached or imported image to the HAR');
      assert.equal(context.cacheDir, '/cache');
      assert.ok(installedHost.isAllowed('colorization'));
      activeJobs++; maxActive = Math.max(maxActive, activeJobs);
      try {
        if (gate) await gate;
        if (!active()) throw Error('cancelled');
        if (fail) throw Error('native failure');
        const target = '/cache/comic_images/color_engine_page.jpg';
        files.set(target, new Uint8Array([4, 5, 6]).buffer);
        installedHost.noteComicWrite();
        if (afterEngineResult) afterEngineResult();
        return { uri: 'file://' + target };
      } finally { activeJobs--; }
    }
  }
};
const fileIo = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
  stat: async name => { if (!files.has(name)) throw Error('missing'); return { size: files.get(name).byteLength, mtime: 1 }; },
  access: async name => files.has(name), mkdir: async name => files.set(name, new ArrayBuffer(0)),
  open: async name => { handles.set(++next, name); files.set(name, new ArrayBuffer(0)); return { fd: next }; },
  write: async (fd, bytes) => { files.set(handles.get(fd), bytes); return bytes.byteLength; },
  close: async () => {}, rename: async (a, b) => { files.set(b, files.get(a)); files.delete(a); },
  unlink: async name => { files.delete(name); }
};
const cache = {
  configure() {}, reconcile() { reconciles++; }, record: async paths => { recorded.push(...paths); },
  hold() { holds++; }, unhold() { holds--; },
  beginComicWrite() { writers++; }, endComicWrite() { writers--; }
};
const sdk = {
  '@kit.AbilityKit': { AbilityConstant: { MemoryLevel: { MEMORY_LEVEL_MODERATE: 0 } } },
  '@kit.ArkTS': {
    buffer: Buffer, util: { TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } } },
    worker: { ThreadWorker: class { constructor(script) { workerPath = script; } } }
  },
  '@kit.CoreFileKit': { fileIo, fileUri: {
    FileUri: class { constructor(value) { this.path = value.slice(7); } }, getUriFromPath: value => 'file://' + value
  } },
  '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd: () => {
    const hash = crypto.createHash('sha256');
    return { update: async blob => hash.update(blob.data), digest: async () => ({ data: hash.digest() }),
      updateSync: blob => hash.update(blob.data), digestSync: () => ({ data: hash.digest() }) };
  } } },
  '@kit.ImageKit': { image: {
    PixelMapFormat: { RGBA_8888: 1 },
    createImageSource(source) {
      decodedPath = source;
      resources++; decodes++;
      return {
        getImageInfo: async () => ({ size: { width: 800, height: 1200 } }), getFrameCount: async () => 1,
        createPixelMap: async () => { resources++; return { release: async () => { resources--; } }; },
        release: async () => { resources--; }
      };
    }
  } }
};
function load(name, extra = {}) {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service', name + '.ets'), 'utf8');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source.replace(/import lazy /g, 'import '), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, Error, canIUse: () => supported, require(name) {
    if (name === '@legado/aiengine') return engine;
    if (name.endsWith('MembershipState')) return { MembershipState: { current: { get hasAccess() { return member; } } } };
    if (name.endsWith('ReaderCacheService')) return { ReaderCacheService: cache };
    if (name in extra) return extra[name];
    if (name in sdk) return sdk[name];
    throw Error('Unexpected dependency: ' + name);
  } });
  return exports;
}
const hostModule = load('ComicAiHost');
const { ComicColorizationService: service } = load('ComicColorizationService', {
  './ComicAiHost': hostModule,
  './ComicOfflineTranslationService': { ComicOfflineTranslationService: {
    MODEL: 'offline-fixture', validateDirection(value) {
      if (!['ja-zh', 'ko-zh', 'en-zh', 'zh-en'].includes(value)) throw Error('comic_offline_language');
    }
  } },
  './ComicTranslationService': { ComicTranslationService: { async translatePixels(_pixels, width, height, language, active) {
    assert.equal(width, 800); assert.equal(height, 1200);
    translations++; lastLanguage = language;
    if (!active()) throw Error('cancelled');
    return new Uint8Array([255, 216, 255]);
  } } }
});
const context = { cacheDir: '/cache', filesDir: '/files' };
const waitForEngine = async () => { while (!activeJobs) await new Promise(resolve => setImmediate(resolve)); };
(async () => {
  hostModule.ComicAiHost.setAppForeground(false);
  hostModule.ComicAiHost.onMemoryPressure(0);
  assert.equal(foregroundEvents, 0, 'app lifecycle must not activate an unused engine');
  assert.equal(memoryNotifications, 0);
  hostModule.ComicAiHost.setAppForeground(true);
  member = false;
  assert.equal(await service.colorize(context, uri, () => false), '');
  assert.equal(engineCalls, 0);
  assert.equal(await service.colorize(context, uri, () => true), '', 'non-member cannot invoke coloring directly');
  assert.equal(engineCalls, 0, 'denied requests never reach the engine');
  member = true;
  const colored = await service.colorize(context, uri, () => true);
  assert.ok(colored.startsWith('file:///cache/comic_images/color_'));
  assert.ok(recorded.includes(colored));
  assert.equal(reconciles, 0, 'a successful engine write must not invalidate the entire cache index');
  assert.equal(decodes, 0, 'image conversion belongs to the external engine');
  assert.equal(installedHost.isAllowed('translation'), false, 'existing translation stays independent');
  await assert.rejects(installedHost.downloadImage('https://example.test/image.jpg'), /local_image_required/);
  installedHost.createColorWorker();
  assert.equal(workerPath, 'entry/ets/workers/ComicColorWorker.ets');
  member = false;
  assert.equal(installedHost.isAllowed('colorization'), false, 'HAR host also checks membership');
  assert.equal(await service.colorize(context, uri, () => true), '', 'cached colorization cannot bypass membership');
  assert.equal(await service.transform(context, uri, () => true, 'en-zh'), '', 'translation still requires membership');
  assert.equal(await service.transform(context, uri, () => true, 'en-zh', true), '', 'combined translation requires membership');
  member = true;
  const translated = await service.transform(context, uri, () => true, 'en-zh');
  assert.notEqual(translated, colored);
  assert.equal(lastLanguage, 'en-zh');
  assert.equal(decodes, 1);
  assert.equal(await service.transform(context, uri, () => true, 'en-zh'), translated);
  assert.equal(translations, 1);
  assert.notEqual(await service.transform(context, uri, () => true, 'zh-en'), translated);
  files.set(importedUri.slice(7), new Uint8Array([7, 8, 9]).buffer);
  const beforeLocal = engineCalls;
  assert.equal(await service.colorize(context, importedUri, () => true), colored);
  assert.equal(engineCalls, beforeLocal + 1, 'imported EPUB reaches the coloring engine');
  assert.ok(await service.transform(context, importedUri, () => true, 'en-zh'));
  assert.deepEqual([...new Uint8Array(files.get(importedUri.slice(7)))], [7, 8, 9], 'original EPUB image is preserved');
  const beforeInvalid = engineCalls;
  for (const invalid of ['file:///files/ebooks/import_fixture/0.txt',
    'file:///files/ebooks/import_fixture/../image_0_1.img',
    'file:///files/ebooks_other/import_fixture/image_0_1.img']) {
    assert.equal(await service.colorize(context, invalid, () => true), '');
  }
  assert.equal(engineCalls, beforeInvalid, 'only imported image files are accepted');
  const beforeCombined = engineCalls;
  const combined = await service.transform(context, importedUri, () => true, 'en-zh', true);
  assert.equal(engineCalls, beforeCombined + 1, 'both enabled runs colorization');
  assert.equal(decodedPath, colored.slice(7), 'translation paints onto the colored output');
  assert.notEqual(combined, colored, 'both enabled returns the translated colored image');
  assert.notEqual(combined, translated, 'combined cache is distinct from translation-only cache');
  assert.equal(await service.transform(context, importedUri, () => true, 'en-zh', true), combined);
  assert.equal(await service.colorize(context, importedUri, () => true), colored, 'turning translation off keeps coloring');
  assert.equal(await service.transform(context, uri, () => true, 'en-zh', false), translated, 'turning coloring off keeps translation');
  await assert.rejects(service.transform(context, uri, () => true, 'invalid'), /offline_language/);

  let resultActive = true;
  afterEngineResult = () => { resultActive = false; };
  const recordsBeforeCancel = recorded.length;
  assert.equal(await service.colorize(context, uri, () => resultActive), '');
  assert.equal(recorded.length, recordsBeforeCancel + 1, 'a written result is accounted even when the reader leaves before delivery');
  assert.equal(reconciles, 0);
  afterEngineResult = undefined;

  let release;
  gate = new Promise(resolve => { release = resolve; });
  const translationsBeforeCancel = translations;
  const stale = service.transform(context, importedUri, () => true, 'en-zh', true);
  await waitForEngine();
  const queued = service.colorize(context, uri, () => true);
  const calls = engineCalls;
  service.release(); release();
  assert.equal(await stale, '', 'closing discards the in-flight result');
  assert.equal(translations, translationsBeforeCancel, 'cancelled coloring never starts the translation stage');
  assert.equal(await queued, '', 'closing invalidates pending jobs');
  assert.equal(engineCalls, calls);
  assert.equal(idleReleases, 1);
  assert.equal(reconciles, 1, 'cancellation without a returned path reconciles possible engine leftovers');
  gate = new Promise(resolve => { release = resolve; });
  const freeColor = service.colorize(context, uri, () => true);
  await waitForEngine(); member = false; release();
  assert.equal(await freeColor, '', 'revocation discards in-flight colorization');
  member = true;
  gate = new Promise(resolve => { release = resolve; });
  const revoked = service.transform(context, uri, () => true, 'en-zh', true);
  await waitForEngine(); member = false; release();
  assert.equal(await revoked, '', 'membership revocation still discards translated results');
  gate = undefined; member = true; fail = true;
  await assert.rejects(service.colorize(context, uri, () => true), /comic_ai_color_failed/);
  assert.equal(await service.colorize(context, uri, () => true), '', 'one failure stops the current batch');
  fail = false; service.resetFailure();
  assert.equal(await service.colorize(context, uri, () => true), colored, 're-enabling permits retry');
  supported = false; service.resetFailure();
  await assert.rejects(service.colorize(context, uri, () => true), /color_unsupported/);
  assert.deepEqual([...new Uint8Array(files.get(uri.slice(7)))], [1, 2, 3]);
  assert.equal(resources, 0); assert.equal(holds, 0); assert.equal(writers, 0); assert.equal(maxActive, 1);
  assert.ok(![...files.keys()].some(name => name.endsWith('.tmp')));
  supported = true;
  member = false;
  service.prepare(context, () => true);
  member = true;
  service.prepare(context, () => false);
  assert.equal(preparations, 0, 'non-members and inactive readers cannot warm up');
  service.prepare(context, () => true);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(preparations, 1);
  assert.equal(preparationActive(), true);
  member = false;
  assert.equal(preparationActive(), false, 'membership revocation cancels warmup');
  member = true;
  service.release();
  assert.equal(preparationActive(), false, 'closing invalidates pending preparation');
  const modelData = new Uint8Array(1024 * 1024 + 37).fill(7);
  let rawClosed = 0;
  const modelContext = {filesDir:'/files',cacheDir:'/cache',resourceManager:{
    async getRawFd(name) { assert.equal(name,'comic-colorizer/alac.ms'); return {fd:900,offset:71,length:modelData.length}; },
    async closeRawFd() { rawClosed++; }
  }};
  const modelHost = new hostModule.ComicAiHost(modelContext);
  const originalWrite = fileIo.write;
  fileIo.read = async (fd, chunk, options) => {
    assert.equal(fd,900);
    const start = options.offset - 71;
    const part = modelData.subarray(start,start+chunk.byteLength);
    new Uint8Array(chunk).set(part); return part.length;
  };
  fileIo.write = async (fd, chunk) => {
    const file = handles.get(fd), previous = new Uint8Array(files.get(file));
    const size = Math.min(12345,chunk.byteLength); // Real files may accept a short write.
    const combined = new Uint8Array(previous.length+size);
    combined.set(previous);combined.set(new Uint8Array(chunk,0,size),previous.length);
    files.set(file,combined.buffer); return size;
  };
  const modelPath='/files/comic_colorizer/alac-fp16-v4.ms.part';
  const progress=[];
  await modelHost.downloadColorModel('alac.ms',modelPath,modelData.length,()=>true,n=>progress.push(n));
  assert.deepEqual(new Uint8Array(files.get(modelPath)),modelData);
  assert.equal(progress.at(-1),modelData.length);assert.equal(rawClosed,1);
  await assert.rejects(modelHost.downloadColorModel('alac.ms',modelPath,modelData.length,()=>true,()=>{member=false;}));
  assert.equal(rawClosed,2,'revocation closes the package resource');
  member=true; fileIo.write=originalWrite;
  console.log('comic model assets: bounded copies, resource offsets, partial writes and membership revocation passed');
  hostModule.ComicAiHost.setAppForeground(false);
  assert.equal(engineForeground, false, 'background reaches the installed engine');
  hostModule.ComicAiHost.onMemoryPressure(0);
  assert.equal(memoryNotifications, 1);
  hostModule.ComicAiHost.setAppForeground(true);
  assert.equal(engineForeground, true);
  const releasesBeforeModerate = idleReleases;
  hostModule.ComicAiHost.onMemoryPressure(0);
  assert.equal(idleReleases, releasesBeforeModerate + 1, 'foreground moderate memory releases once');
  assert.equal(memoryNotifications, 1, 'moderate notification does not disable reuse for sixty seconds');
  hostModule.ComicAiHost.onMemoryPressure(1);
  hostModule.ComicAiHost.onMemoryPressure(2);
  assert.equal(memoryNotifications, 3, 'low and critical memory retain the engine cooldown');
  for (const level of [3, 4, 5, 6, 99]) hostModule.ComicAiHost.onMemoryPressure(level);
  assert.equal(memoryNotifications, 8, 'hidden/background and unknown notifications stay conservative');
  console.log('comic AI HAR integration: local-only input, live permissions, cancellation, retry and existing translation passed');
  console.log('comic AI warmup: permission/reader gates, cancellation, lazy engine activation and app lifecycle passed');
  console.log('comic AI memory levels: foreground moderate releases once; low/critical/background keep cooldown');
})().catch(error => { console.error(error); process.exitCode = 1; });
