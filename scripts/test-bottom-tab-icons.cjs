// Exercise real icon persistence and image-file ownership with bounded platform doubles.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/BottomTabIconService.ets'), 'utf8');
const code = ts.transpileModule(source, { compilerOptions: {
  target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS, experimentalDecorators: true
} }).outputText;
const roles = { None: 0, Home: 6, Shelf: 7, Record: 8, Profile: 9 };
const directory = '/app/files/bottom_tab_icons';

function storage() {
  return { saved: '', files: new Map([['photo://selected', new Uint8Array(128)]]) };
}

async function launch(disk) {
  const controls = { failFlush: false, failWrite: false, inputSize: 128, outputSize: 128, beforeFlush: undefined };
  let cache = disk.saved;
  const handles = new Map();
  let fd = 0;
  const released = { source: 0, pixels: 0, packer: 0 };
  const imageSizes = [];
  const preferences = {
    get: async () => cache,
    put: async (_key, value) => { cache = value; },
    flush: async () => {
      await controls.beforeFlush?.();
      if (controls.failFlush) throw new Error('disk full');
      disk.saved = cache;
    }
  };
  const fileIo = {
    OpenMode: { READ_ONLY: 0, CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    access: async file => disk.files.has(file),
    mkdir: async file => { disk.files.set(file, null); },
    open: async (file, mode) => {
      if (mode) disk.files.set(file, new Uint8Array());
      if (!disk.files.has(file)) throw Error('missing file');
      const handle = { fd: ++fd };
      handles.set(fd, file);
      return handle;
    },
    stat: async () => ({ size: controls.inputSize }),
    write: async (handle, bytes) => {
      if (controls.failWrite) return 0;
      // Deliberately short writes verify the complete-write loop.
      const count = Math.min(37, bytes.byteLength);
      const file = handles.get(handle);
      disk.files.set(file, new Uint8Array(disk.files.get(file).length + count));
      return count;
    },
    close: async handle => { assert.ok(handles.delete(handle.fd)); },
    unlink: async file => { disk.files.delete(file); }
  };
  const mocks = {
    './MembershipService': { MembershipService: {
      instance: { hasCurrentEntitlement: async () => controls.entitled !== false }
    } },
    '@kit.AbilityKit': {},
    '@kit.ArkData': { preferences: { getPreferences: async () => preferences } },
    '@kit.CoreFileKit': { fileIo },
    '@kit.ImageKit': { image: {
      createImageSource: () => ({
        getImageInfo: async () => ({ size: { width: 4000, height: 2000 } }),
        createPixelMap: async options => {
          assert.equal(options.editable, true);
          imageSizes.push(options.desiredSize);
          return {
            getImageInfo: async () => ({ size: options.desiredSize }),
            crop: async region => {
              assert.equal(region.size.width, region.size.height);
              assert.ok(region.x >= 0 && region.y >= 0);
              assert.ok(region.size.width <= 256);
            },
            release: async () => { released.pixels++; }
          };
        },
        release: async () => { released.source++; }
      }),
      createImagePacker: () => ({
        packing: async (_pixels, options) => {
          assert.equal(options.format, 'image/png', 'retain transparency');
          return new ArrayBuffer(controls.outputSize);
        },
        release: async () => { released.packer++; }
      })
    } },
    '../theme/ThemeIcons': { ThemeIconRole: roles }
  };
  const exports = {};
  const observed = new WeakSet();
  vm.runInNewContext(code, { exports, require: name => {
    assert.ok(Object.hasOwn(mocks, name), name);
    return mocks[name];
  }, ObservedV2: value => class extends value {
    constructor() { super(); observed.add(this); }
  }, Trace: () => {} });
  const service = exports.BottomTabIconService.instance;
  assert.ok(observed.has(service), 'singleton construction must pass through the V2 decorated constructor');
  await service.init({ filesDir: '/app/files' });
  return { service, controls, handles, released, imageSizes, cache: () => cache };
}

function iconFiles(disk) {
  return [...disk.files.keys()].filter(file => file.startsWith(directory + '/'));
}

(async () => {
  const disk = storage();
  let app = await launch(disk);
  assert.equal(app.service.resolve(roles.Home), undefined);
  assert.equal(app.service.hasCustomIcons, false);

  let flushStarted;
  let finishFlush;
  const started = new Promise(resolve => { flushStarted = resolve; });
  const pending = new Promise(resolve => { finishFlush = resolve; });
  app.controls.beforeFlush = async () => { flushStarted(); await pending; };
  const importing = app.service.importIcon(roles.Home, 'photo://selected', () => true);
  await started;
  assert.equal(app.service.resolve(roles.Home), undefined, 'publish only after persistence');
  assert.equal(await app.service.importIcon(roles.Shelf, 'photo://selected', () => true), false,
    'concurrent actions cannot overwrite an in-flight save');
  finishFlush();
  assert.equal(await importing, true);
  app.controls.beforeFlush = undefined;
  const home = app.service.resolve(roles.Home);
  assert.ok(home.startsWith('file://' + directory));
  assert.equal(app.handles.size, 0);
  assert.deepEqual(app.released, { source: 1, pixels: 1, packer: 1 });
  assert.ok(app.imageSizes.every(size => Math.max(size.width, size.height) <= 256));
  assert.equal(disk.files.get(home.slice(7)).length, 128, 'short writes still save the complete image');
  app = await launch(disk);
  assert.equal(app.service.resolve(roles.Home), home, 'selection survives restart');

  app.controls.entitled = false;
  await assert.rejects(app.service.importIcon(roles.Home, 'photo://selected', () => true), /MEMBERSHIP_REQUIRED/);
  assert.equal(app.service.resolve(roles.Home), home, 'membership denial preserves the existing icon');
  assert.deepEqual(iconFiles(disk), [home.slice(7)], 'membership denial cleans the staged icon');
  app.controls.entitled = true;
  app.controls.failFlush = true;
  await assert.rejects(app.service.importIcon(roles.Home, 'photo://selected', () => true), /disk full/);
  assert.equal(app.service.resolve(roles.Home), home);
  assert.equal(app.cache(), disk.saved, 'failed flush rolls back the writable Preferences cache');
  assert.deepEqual(iconFiles(disk), [home.slice(7)], 'failed replacement keeps old image and deletes the new image');
  await assert.rejects(app.service.reset(), /disk full/);
  assert.equal(app.service.resolve(roles.Home), home, 'failed reset preserves image and selection');
  app.controls.failFlush = false;

  assert.equal(await app.service.importIcon(roles.Home, 'photo://selected', () => false), false);
  assert.deepEqual(iconFiles(disk), [home.slice(7)], 'leaving the page during decode discards the image');
  app.controls.failWrite = true;
  await assert.rejects(app.service.importIcon(roles.Shelf, 'photo://selected', () => true), /Incomplete/);
  app.controls.failWrite = false;
  assert.deepEqual(iconFiles(disk), [home.slice(7)]);
  assert.equal(app.handles.size, 0, 'failure closes every image file');

  for (const [field, value, pattern] of [
    ['inputSize', 21 * 1024 * 1024, /input exceeds/],
    ['outputSize', 513 * 1024, /output exceeds/]
  ]) {
    app.controls[field] = value;
    await assert.rejects(app.service.importIcon(roles.Shelf, 'photo://selected', () => true), pattern);
    app.controls[field] = 128;
    assert.deepEqual(iconFiles(disk), [home.slice(7)]);
    assert.equal(app.handles.size, 0);
  }

  await app.service.importIcon(roles.Shelf, 'photo://selected', () => true);
  const shelf = app.service.resolve(roles.Shelf);
  await app.service.importIcon(roles.Home, 'photo://selected', () => true);
  assert.equal(disk.files.has(home.slice(7)), false, 'successful replacement deletes the obsolete image');
  await app.service.reset(roles.Home);
  assert.equal(app.service.resolve(roles.Home), undefined);
  assert.equal(app.service.resolve(roles.Shelf), shelf, 'reset affects only the chosen semantic tab');
  app = await launch(disk);
  assert.equal(app.service.resolve(roles.Shelf), shelf);
  disk.files.delete(shelf.slice(7));
  app = await launch(disk);
  assert.equal(app.service.resolve(roles.Shelf), undefined, 'missing files fall back to theme icons');

  for (const role of [roles.Home, roles.Shelf, roles.Record, roles.Profile]) {
    await app.service.importIcon(role, 'photo://selected', () => true);
  }
  await app.service.reset();
  assert.equal(app.service.hasCustomIcons, false);
  assert.deepEqual(iconFiles(disk), []);
  assert.equal((await launch(disk)).service.hasCustomIcons, false, 'reset persists across restart');
  for (const raw of ['null', '[]', '{broken', JSON.stringify({schemaVersion: 2}),
    JSON.stringify({schemaVersion: 1, home: '../secret.png', shelf: 'https://example.test/a.png'})]) {
    disk.saved = raw;
    assert.equal((await launch(disk)).service.hasCustomIcons, false, 'reject malformed records and external paths');
  }
  console.log('PASS: bottom tab icons persist, roll back, reset, enforce image budgets and release files');
})().catch(error => { console.error(error); process.exitCode = 1; });
