// Exercise real App background models and storage with bounded HarmonyOS adapters.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const directory = '/app/files/app_backgrounds';

function disk() {
  return { saved: '', files: new Map([['photo://selected', new Uint8Array(128)]]) };
}

async function launch(storage) {
  const controls = { failFlush: false, failWrite: false, failAt: '', originalCode: 0,
    inputSize: undefined, outputSize: 128, outputBytesPerPixel: 0,
    width: 4000, height: 3000, mimeType: 'image/jpeg', orientation: '1',
    orientationMode: 'value', beforeFlush: undefined };
  let cache = storage.saved;
  const handles = new Map();
  let fd = 0;
  const released = { source: 0, pixels: 0, packer: 0 };
  const created = { source: 0, pixels: 0, packer: 0 };
  const decodeSizes = [];
  const transforms = [];
  const formats = [];
  const scales = [];
  const encodeAttempts = [];
  const warnings = [];
  const propertyRequests = [];
  const pixelStates = new WeakMap();
  function fail(stage) {
    if (controls.failAt !== stage) return;
    throw Object.assign(new Error(`simulated ${stage} failure`), { code: controls.originalCode });
  }
  const preferenceStore = {
    get: async () => cache,
    put: async (_key, value) => { cache = value; },
    flush: async () => {
      await controls.beforeFlush?.();
      if (controls.failFlush) throw Error('disk full');
      storage.saved = cache;
    }
  };
  const fileIo = {
    OpenMode: { READ_ONLY: 0, CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    access: async file => storage.files.has(file),
    mkdir: async file => { storage.files.set(file, null); },
    listFile: async file => [...storage.files.keys()].filter(key => key.startsWith(file + '/')).map(key => path.posix.basename(key)),
    open: async (file, mode) => {
      if (!mode) fail('open');
      if (mode) storage.files.set(file, new Uint8Array());
      if (!storage.files.has(file)) throw Error('missing file');
      const handle = { fd: ++fd };
      handles.set(handle.fd, file);
      return handle;
    },
    stat: async handle => {
      fail('stat');
      assert.ok(handles.has(handle), 'stat receives the open file descriptor');
      return { size: controls.inputSize ?? storage.files.get(handles.get(handle)).length };
    },
    write: async (handle, bytes) => {
      fail('write');
      if (controls.failWrite) return 0;
      const count = Math.min(bytes.byteLength > 128 ? 256 * 1024 : 37, bytes.byteLength);
      const file = handles.get(handle);
      // File contents are irrelevant here; keep byte counts so realistic PNG sizes do not make the adapter quadratic.
      storage.files.set(file, { length: storage.files.get(file).length + count });
      return count;
    },
    close: async handle => { assert.ok(handles.delete(handle.fd)); },
    unlink: async file => { storage.files.delete(file); }
  };
  const mocks = {
    '@kit.AbilityKit': {},
    '@kit.ArkData': { preferences: { getPreferences: async () => preferenceStore } },
    '@kit.CoreFileKit': { fileIo },
    '@kit.ImageKit': { image: {
      PropertyKey: { ORIENTATION: 'Orientation' },
      createImageSource: handle => {
        fail('source');
        assert.ok(handles.has(handle), 'decoder receives the open file descriptor');
        created.source++;
        return {
        getImageInfo: async () => ({ size: { width: controls.width, height: controls.height }, mimeType: controls.mimeType }),
        getImageProperty: (key, options) => {
          propertyRequests.push({ key, index: options?.index, defaultValue: options?.defaultValue });
          // The native options parser reads index before constructing its Promise.
          if (!options || !Number.isInteger(options.index) || options.index < 0) {
            throw new Error('async context unwrap failed');
          }
          if (controls.orientationMode === 'syncThrow') throw new Error('async context unwrap failed');
          if (controls.orientationMode === 'reject') {
            return Promise.reject(Object.assign(new Error('The image does not support EXIF decoding'), { code: 62980123 }));
          }
          if (controls.orientationMode === 'undefined') return undefined;
          return Promise.resolve(controls.orientation);
        },
        createPixelMap: async options => {
          fail('decode');
          created.pixels++;
          decodeSizes.push(options.desiredSize);
          const state = { width: options.desiredSize.width, height: options.desiredSize.height };
          const pixels = {
            getImageInfo: async () => ({ size: { ...state }, mimeType: controls.mimeType }),
            flip: async (horizontal, vertical) => { transforms.push(['flip', horizontal, vertical]); },
            rotate: async angle => {
              transforms.push(['rotate', angle]);
              if (angle % 180) [state.width, state.height] = [state.height, state.width];
            },
            scale: async (x, y) => {
              assert.ok(x > 0 && x < 1 && y > 0 && y < 1, 'retry scales down instead of enlarging');
              const before = { ...state };
              state.width = Math.max(1, Math.round(state.width * x));
              state.height = Math.max(1, Math.round(state.height * y));
              scales.push({ before, after: { ...state } });
            },
            release: async () => { released.pixels++; }
          };
          pixelStates.set(pixels, state);
          return pixels;
        },
        release: async () => { released.source++; }
      };
      },
      createImagePacker: () => {
        created.packer++;
        return {
          packToData: async (pixels, options) => {
            fail('pack');
            const size = pixelStates.get(pixels);
            const length = controls.outputBytesPerPixel > 0
              ? Math.ceil(size.width * size.height * controls.outputBytesPerPixel) : controls.outputSize;
            formats.push(options.format);
            encodeAttempts.push({ ...size, bytes: length, format: options.format, bufferSize: options.bufferSize });
            assert.ok(encodeAttempts.length < 32, 'image encoding must be bounded');
            return new ArrayBuffer(length);
          },
          release: async () => { released.packer++; }
        };
      }
    } }
  };
  const loaded = new Map();
  const observed = new WeakSet();
  function load(name) {
    const filename = name.endsWith('.ets') ? name : name + '.ets';
    if (loaded.has(filename)) return loaded.get(filename);
    const exports = {};
    loaded.set(filename, exports);
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
      target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS, experimentalDecorators: true
    } }).outputText;
    vm.runInNewContext(code, { exports, console: { ...console, warn: message => warnings.push(message) }, require: target => {
      if (Object.hasOwn(mocks, target)) return mocks[target];
      assert.ok(target.startsWith('.'), target);
      return load(path.resolve(path.dirname(filename), target));
    }, ObservedV2: value => class extends value {
      constructor() { super(); observed.add(this); }
    }, Trace: () => {} }, { filename });
    return exports;
  }
  const model = load(path.join(root, 'model/AppBackground.ets'));
  const service = load(path.join(root, 'service/AppBackgroundService.ets')).AppBackgroundService.instance;
  assert.ok(observed.has(service), 'singleton is constructed through its V2 decorator');
  await service.init({ filesDir: '/app/files' });
  return { model, service, controls, handles, released, created, decodeSizes, transforms, formats,
    scales, encodeAttempts, warnings, propertyRequests, cache: () => cache };
}

function imageFiles(storage) {
  return [...storage.files.keys()].filter(file => file.startsWith(directory + '/'));
}

function deferredFlush(app) {
  let signal, finish;
  const started = new Promise(resolve => { signal = resolve; });
  const waiting = new Promise(resolve => { finish = resolve; });
  app.controls.beforeFlush = async () => { signal(); await waiting; };
  return { started, finish };
}

async function expectImageFailure(app, storage, reason, originalCode = 0) {
  const saved = storage.saved;
  const selection = JSON.stringify(app.service.snapshot());
  const retained = imageFiles(storage);
  await assert.rejects(app.service.importImage('photo://selected', () => true), error => {
    assert.ok(error instanceof app.model.AppBackgroundImportError, 'imports expose a typed failure');
    assert.equal(error.reason, reason);
    assert.equal(error.originalCode, originalCode, 'the platform diagnostic code survives wrapping');
    return true;
  });
  assert.equal(app.service.busy, false, 'a failed import can be retried');
  assert.equal(app.handles.size, 0, 'failed imports close every file handle');
  assert.deepEqual(app.released, app.created, 'failed imports release all successfully created image resources');
  assert.equal(storage.saved, saved, 'failed imports preserve committed Preferences');
  assert.equal(app.cache(), saved, 'failed imports preserve the mutable Preferences cache');
  assert.equal(JSON.stringify(app.service.snapshot()), selection, 'failed imports preserve the active background');
  assert.deepEqual(imageFiles(storage), retained, 'failed imports leave no staged files or remove committed images');
  const warning = app.warnings.at(-1);
  assert.ok(warning.includes(`reason=${reason}`) && warning.includes(`code=${originalCode}`));
  assert.equal(warning.includes('photo://'), false, 'diagnostics omit the selected image URI');
}

(async () => {
  const storage = disk();
  let app = await launch(storage);
  const { AppBackgroundScene: Scene, AppBackgroundSelection: Selection, AppBackgroundConfig: Config } = app.model;
  for (const scene of [Scene.Home, Scene.Shelf, Scene.Record, Scene.Profile]) {
    assert.equal(app.service.resolve(scene).preset, 'theme', 'initial install preserves each scene’s theme backdrop');
  }
  const draft = app.service.snapshot();
  draft.common.preset = 'paper';
  draft.shelf.followCommon = false;
  draft.shelf.config.preset = 'mist';
  assert.equal(draft.resolve(Scene.Home).preset, 'paper');
  assert.equal(draft.resolve(Scene.Shelf).preset, 'mist');
  draft.shelf.followCommon = true;
  assert.equal(draft.resolve(Scene.Shelf).preset, 'paper');
  draft.shelf.followCommon = false;
  assert.equal(draft.resolve(Scene.Shelf).preset, 'mist', 'following common preserves the independent choice');
  assert.equal(app.service.resolve(Scene.Home).preset, 'theme', 'editing a snapshot cannot publish settings');

  app.controls.orientation = 'Right-top';
  const photo = await app.service.importImage('photo://selected', () => true);
  assert.ok(photo.endsWith('.jpg'));
  assert.equal(storage.saved, '', 'image import only stages a file');
  assert.equal(app.service.resolveImage(Object.assign(new Config(), { imageFile: photo })), `file://${directory}/${photo}`);
  assert.ok(app.decodeSizes.every(size => Math.max(size.width, size.height) <= 2560));
  assert.equal(storage.files.get(`${directory}/${photo}`).length, 128, 'partial writes complete the whole output');
  assert.deepEqual(app.transforms, [['rotate', 90]], 'normalize EXIF orientation before packing');
  assert.deepEqual(app.released, { source: 1, pixels: 1, packer: 1 });
  assert.equal(app.handles.size, 0);
  draft.shelf.config.preset = 'image';
  draft.shelf.config.imageFile = photo;
  await app.service.apply(draft);
  app = await launch(storage);
  assert.equal(app.service.resolve(Scene.Shelf).imageFile, photo);
  assert.equal(app.service.resolve(Scene.Home).preset, 'paper', 'mixed common/independent settings survive restart');

  const hidden = app.service.snapshot();
  hidden.shelf.followCommon = true;
  hidden.shelf.config.preset = 'mist';
  await app.service.apply(hidden);
  assert.ok(storage.files.has(`${directory}/${photo}`), 'hidden independent and temporarily unselected images remain referenced');
  assert.equal(app.service.resolve(Scene.Shelf).preset, 'paper');

  app.controls.mimeType = 'image/png';
  app.controls.orientation = '5';
  const replacement = await app.service.importImage('photo://selected', () => true);
  assert.ok(replacement.endsWith('.png'), 'PNG retains alpha instead of flattening to black');
  assert.deepEqual(app.transforms.slice(-2), [['flip', true, false], ['rotate', 270]]);
  const replace = app.service.snapshot();
  replace.shelf.followCommon = false;
  replace.shelf.config.preset = 'image';
  replace.shelf.config.imageFile = replacement;
  app.controls.failFlush = true;
  await assert.rejects(app.service.apply(replace), /disk full/);
  assert.equal(app.cache(), storage.saved, 'failed flush rolls back the mutable Preferences cache');
  assert.equal(app.service.snapshot().shelf.config.imageFile, photo);
  assert.ok(storage.files.has(`${directory}/${photo}`), 'failed application preserves the last committed image');
  app.controls.failFlush = false;
  await app.service.discardDraft(replace);
  assert.equal(storage.files.has(`${directory}/${replacement}`), false);
  assert.ok(storage.files.has(`${directory}/${photo}`), 'draft cleanup never deletes a committed hidden image');

  const pendingImage = await app.service.importImage('photo://selected', () => true);
  const pendingDraft = app.service.snapshot();
  pendingDraft.profile.followCommon = false;
  pendingDraft.profile.config.preset = 'image';
  pendingDraft.profile.config.imageFile = pendingImage;
  let gate = deferredFlush(app);
  const saving = app.service.apply(pendingDraft);
  await gate.started;
  await app.service.discardDraft(pendingDraft);
  assert.ok(storage.files.has(`${directory}/${pendingImage}`), 'leaving during apply defers deletion of its input image');
  gate.finish();
  await saving;
  app.controls.beforeFlush = undefined;
  assert.ok(storage.files.has(`${directory}/${pendingImage}`), 'successful apply keeps its deferred image');

  const failedImage = await app.service.importImage('photo://selected', () => true);
  const failedDraft = app.service.snapshot();
  failedDraft.home.followCommon = false;
  failedDraft.home.config.preset = 'image';
  failedDraft.home.config.imageFile = failedImage;
  gate = deferredFlush(app);
  app.controls.failFlush = true;
  const failedSave = app.service.apply(failedDraft);
  await gate.started;
  await app.service.discardDraft(failedDraft);
  gate.finish();
  await assert.rejects(failedSave, /disk full/);
  app.controls.beforeFlush = undefined;
  app.controls.failFlush = false;
  assert.equal(storage.files.has(`${directory}/${failedImage}`), false, 'failed apply after departure releases its deferred draft');
  assert.ok(storage.files.has(`${directory}/${pendingImage}`));

  const retained = imageFiles(storage);
  let checks = 0;
  assert.equal(await app.service.importImage('photo://selected', () => ++checks === 1), '');
  assert.deepEqual(imageFiles(storage), retained, 'late image completion is discarded');
  for (const [field, value, reason] of [
    ['inputSize', 21 * 1024 * 1024, app.model.AppBackgroundImportReason.InputTooLarge],
    ['outputSize', 13 * 1024 * 1024, app.model.AppBackgroundImportReason.EncodeFailed]
  ]) {
    app.controls[field] = value;
    await expectImageFailure(app, storage, reason);
    app.controls[field] = field === 'inputSize' ? undefined : 128;
  }
  app.controls.failWrite = true;
  await expectImageFailure(app, storage, app.model.AppBackgroundImportReason.SaveFailed);
  app.controls.failWrite = false;
  assert.deepEqual(imageFiles(storage), retained);
  assert.equal(app.handles.size, 0);

  const reset = app.service.snapshot();
  reset.shelf.config.imageFile = '';
  await app.service.apply(reset);
  assert.equal(storage.files.has(`${directory}/${photo}`), false, 'explicit image removal releases the final reference');
  assert.ok(storage.files.has(`${directory}/${pendingImage}`), 'other pages keep their independent images');
  storage.files.set(`${directory}/background_1_2.jpg`, new Uint8Array(32));
  app = await launch(storage);
  assert.equal(storage.files.has(`${directory}/background_1_2.jpg`), false, 'restart reclaims abandoned draft images');
  storage.files.delete(`${directory}/${pendingImage}`);
  app = await launch(storage);
  assert.equal(app.service.resolve(Scene.Profile).preset, 'theme', 'missing local files fall back to the current theme');

  for (const raw of ['null', '[]', '{broken', JSON.stringify({ schemaVersion: 2 }),
    JSON.stringify({ schemaVersion: 1, common: { preset: 'image', imageFile: '../secret.jpg' } })]) {
    assert.equal(Selection.decode(raw).resolve(Scene.Home).preset, 'theme');
  }
  const bounded = Config.normalize({ preset: 'mist', imageFile: '', veil: Infinity, blur: -8,
    positionX: 999, positionY: -1, scale: 0, surfaceOpacity: 101 });
  assert.equal(bounded.veil, 22);
  assert.equal(bounded.blur, 0);
  assert.equal(bounded.positionX, 100);
  assert.equal(bounded.positionY, 0);
  assert.equal(bounded.scale, 100);
  assert.equal(bounded.surfaceOpacity, 100);

  // Reproduce the reported 2 MiB PNG input independently from its encoded size.
  const pngStorage = disk();
  pngStorage.files.set('photo://selected', new Uint8Array(2 * 1024 * 1024));
  const pngApp = await launch(pngStorage);
  const Reason = pngApp.model.AppBackgroundImportReason;
  pngApp.controls.mimeType = 'image/png';
  const originalPng = await pngApp.service.importImage('photo://selected', () => true);
  assert.ok(originalPng.endsWith('.png'), 'a valid 2 MiB PNG is imported with transparency retained');
  assert.equal(pngStorage.files.get(`${directory}/${originalPng}`).length, 128);
  const pngSelection = pngApp.service.snapshot();
  pngSelection.home.followCommon = false;
  pngSelection.home.config.preset = 'image';
  pngSelection.home.config.imageFile = originalPng;
  await pngApp.service.apply(pngSelection);
  const pngCommitted = pngStorage.saved;
  const pngBefore = JSON.stringify(pngApp.service.snapshot());
  const attemptsBefore = pngApp.encodeAttempts.length;
  pngApp.controls.outputBytesPerPixel = 4;
  const smallerPng = await pngApp.service.importImage('photo://selected', () => true);
  const retried = pngApp.encodeAttempts.slice(attemptsBefore);
  assert.ok(retried[0].bytes > 12 * 1024 * 1024, 'PNG decoding can expand a small source beyond the output budget');
  assert.ok(retried.length > 1 && retried.length < 10, 'oversized PNG output retries within a bounded number of attempts');
  assert.ok(pngApp.scales.length > 0, 'oversized PNG output is reduced before encoding again');
  assert.ok(pngApp.scales.every(({ before, after }) => after.width < before.width && after.height < before.height));
  assert.ok(retried.at(-1).bytes <= 12 * 1024 * 1024);
  assert.equal(pngStorage.files.get(`${directory}/${smallerPng}`).length, retried.at(-1).bytes,
    'the reduced PNG is written completely');
  assert.ok(pngApp.formats.every(format => format === 'image/png'), 'retries retain the PNG format and alpha channel');
  assert.ok(retried.every(attempt => attempt.bufferSize >= attempt.bytes), 'packing reserves enough space for expanded PNG output');
  assert.equal(pngApp.handles.size, 0);
  assert.deepEqual(pngApp.released, pngApp.created);
  assert.equal(pngStorage.saved, pngCommitted, 'reduction stages an image without applying it');
  await pngApp.service.cleanupDraftImages([smallerPng]);
  assert.deepEqual(imageFiles(pngStorage), [`${directory}/${originalPng}`]);
  assert.equal(JSON.stringify(pngApp.service.snapshot()), pngBefore);

  pngApp.controls.outputBytesPerPixel = 0;
  pngApp.controls.outputSize = 13 * 1024 * 1024;
  await expectImageFailure(pngApp, pngStorage, Reason.EncodeFailed);
  pngApp.controls.outputSize = 128;
  for (const [stage, reason, code] of [
    ['open', Reason.ReadFailed, 13900012],
    ['stat', Reason.ReadFailed, 13900005],
    ['source', Reason.DecodeFailed, 62980103],
    ['decode', Reason.DecodeFailed, 62980103],
    ['pack', Reason.EncodeFailed, 62980119],
    ['write', Reason.SaveFailed, 13900011]
  ]) {
    pngApp.controls.failAt = stage;
    pngApp.controls.originalCode = code;
    await expectImageFailure(pngApp, pngStorage, reason, code);
  }
  pngApp.controls.failAt = '';
  pngApp.controls.originalCode = 0;
  pngApp.controls.inputSize = 0;
  await expectImageFailure(pngApp, pngStorage, Reason.InvalidImage);
  pngApp.controls.inputSize = undefined;
  const recoveredPng = await pngApp.service.importImage('photo://selected', () => true);
  await pngApp.service.cleanupDraftImages([recoveredPng]);
  assert.equal(pngApp.service.resolve(pngApp.model.AppBackgroundScene.Home).imageFile, originalPng,
    'a successful retry preserves the previously committed choice until application');
  assert.deepEqual(pngApp.released, pngApp.created);

  const orientationStorage = disk();
  orientationStorage.files.set('photo://selected', new Uint8Array(2 * 1024 * 1024));
  const orientationApp = await launch(orientationStorage);
  orientationApp.controls.mimeType = 'image/png';
  orientationApp.controls.width = 1254;
  orientationApp.controls.height = 1881;
  for (const [value, expected] of [
    ['1', []],
    ['2', [['flip', true, false]]],
    ['3', [['rotate', 180]]],
    ['4', [['flip', false, true]]],
    ['5', [['flip', true, false], ['rotate', 270]]],
    ['6', [['rotate', 90]]],
    ['7', [['flip', true, false], ['rotate', 90]]],
    ['8', [['rotate', 270]]]
  ]) {
    orientationApp.controls.orientation = value;
    const before = orientationApp.transforms.length;
    const name = await orientationApp.service.importImage('photo://selected', () => true);
    assert.ok(name.endsWith('.png'));
    assert.deepEqual(orientationApp.transforms.slice(before), expected, `EXIF orientation ${value} is normalized`);
    await orientationApp.service.cleanupDraftImages([name]);
  }
  // Optional EXIF may fail before a Promise exists, reject asynchronously, or have no value.
  orientationApp.controls.orientation = '6';
  for (const mode of ['syncThrow', 'reject', 'undefined']) {
    orientationApp.controls.orientationMode = mode;
    const before = orientationApp.transforms.length;
    const requestsBefore = orientationApp.propertyRequests.length;
    const name = await orientationApp.service.importImage('photo://selected', () => true);
    assert.ok(name.endsWith('.png'), `${mode} in optional EXIF does not block a valid PNG`);
    assert.equal(orientationStorage.files.get(`${directory}/${name}`).length, 128);
    assert.equal(orientationApp.propertyRequests.length, requestsBefore + 1, 'orientation was requested before using its fallback');
    assert.deepEqual(orientationApp.transforms.slice(before), [], `${mode} defaults to upright without rotation`);
    assert.equal(orientationApp.service.busy, false);
    assert.equal(orientationApp.handles.size, 0);
    assert.deepEqual(orientationApp.released, orientationApp.created);
    await orientationApp.service.cleanupDraftImages([name]);
  }
  assert.ok(orientationApp.propertyRequests.every(request => request.key === 'Orientation' &&
    request.index === 0 && request.defaultValue === '1'), 'native property options explicitly select frame 0 and an upright fallback');
  assert.deepEqual(imageFiles(orientationStorage), []);
  assert.equal(orientationStorage.saved, '', 'EXIF fallback never publishes staged backgrounds');
  console.log('PASS: App backgrounds support isolated drafts, mixed page inheritance, restart, rollback and retained hidden choices');
  console.log('PASS: local image budgets, EXIF/alpha, complete writes, late completion and concurrent apply/discard ownership');
  console.log('PASS: 2 MiB PNG import, bounded transparent PNG reduction, staged error codes, cleanup and committed-background recovery');
  console.log('PASS: native EXIF options, all 8 orientations and upright PNG fallback for synchronous errors, Promise rejection and undefined values');
})().catch(error => { console.error(error); process.exitCode = 1; });
