// DEVECO_HOME points to the Release IDE. Uses the real font service with isolated files/preferences.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'reader-fonts-'));
const context = { filesDir: temp.replaceAll('\\', '/') };
const directory = context.filesDir + '/reader_fonts';
fs.mkdirSync(directory);
const values = new Map();
let flushCount = 0;
let failFlushAt = -1;
const undeletable = new Set();
let selectedUris = [], activeFiles = 0, peakFiles = 0, registrations = 0;
const handles = new Map();
const store = {
  getSync: (key, fallback) => values.get(key) ?? fallback,
  putSync: (key, value) => values.set(key, value),
  flush: async () => {
    if (++flushCount === failFlushAt) throw new Error('disk unavailable');
  }
};
const filename = path.resolve(__dirname, '../entry/src/main/ets/service/text/ReaderFontService.ets');
const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const moduleObject = { exports: {} };
vm.runInNewContext(output, { exports: moduleObject.exports, Error, require: name => {
  if (name === '@kit.ArkData') return { preferences: { getPreferences: async () => store } };
  if (name === '@kit.CoreFileKit') return { picker: {
    DocumentSelectOptions: class {},
    DocumentViewPicker: class { async select(options) { assert.equal(options.maxSelectNumber, 50); return selectedUris; } }
  }, fileIo: {
    OpenMode: { READ_ONLY: 0 },
    open: async file => {
      const fd = fs.openSync(file, 'r'); handles.set(fd, file);
      peakFiles = Math.max(peakFiles, ++activeFiles); return { fd };
    },
    close: async file => { fs.closeSync(file.fd); handles.delete(file.fd); activeFiles--; },
    stat: async fd => fs.fstatSync(fd),
    read: async (fd, data, options) => fs.readSync(fd, Buffer.from(data), 0, options.length, 0),
    copyFile: async (fd, destination) => {
      await new Promise(resolve => setTimeout(resolve, handles.get(fd).includes('font-0.') ? 5 : 1));
      fs.copyFileSync(handles.get(fd), destination);
    },
    mkdir: async dir => fs.mkdirSync(dir, { recursive: true }),
    accessSync: file => fs.existsSync(file),
    access: async file => fs.existsSync(file),
    listFile: async dir => fs.readdirSync(dir),
    unlink: async file => {
      if (undeletable.has(file)) throw new Error('file busy');
      fs.unlinkSync(file);
    }
  } };
  if (name === '@kit.ArkGraphics2D') return { text: { FontCollection: {
    getGlobalInstance: () => ({ loadFontSync: () => registrations++ })
  } } };
  throw new Error(`Unexpected dependency: ${name}`);
} }, { filename });
const { ReaderFontService: service } = moduleObject.exports;
const fontPaths = ['a.ttf', 'b.otf', 'c.ttf'].map(name => directory + '/' + name);
const pathsOf = fonts => Array.from(fonts, font => font.path);

(async () => {
  for (const file of fontPaths) fs.writeFileSync(file, 'test-font');
  values.set('catalog', JSON.stringify([
    { path: fontPaths[1], name: '乙' },
    { path: fontPaths[0], name: '甲' },
    { path: fontPaths[0], name: '重复' },
    { path: directory + '/../outside.ttf', name: '越界' }
  ]));
  let fonts = await service.list(context);
  assert.deepEqual(pathsOf(fonts), [fontPaths[1], fontPaths[0], fontPaths[2]]);
  assert.ok(fonts.every(font => font.enabled), 'legacy fonts default to enabled');
  console.log('PASS legacy catalog migration, stable order and duplicate/path filtering');

  await service.setEnabled(context, [fontPaths[0], fontPaths[2]], false);
  assert.deepEqual(pathsOf(await service.listEnabled(context)), [fontPaths[1]]);
  fonts = await service.list(context);
  assert.equal(fonts.length, 3, 'disabled fonts remain manageable');
  assert.ok(fontPaths.every(file => fs.existsSync(file)), 'disabling retains font files');
  await service.setEnabled(context, fontPaths, true);
  assert.equal((await service.listEnabled(context)).length, 3);
  console.log('PASS batch disable/enable persists and reader choices exclude disabled fonts');

  await service.reorder(context, [fontPaths[2], fontPaths[2], 'missing', fontPaths[1]]);
  assert.deepEqual(pathsOf(await service.list(context)), [fontPaths[2], fontPaths[1], fontPaths[0]]);
  assert.deepEqual(pathsOf(await service.listEnabled(context)), [fontPaths[2], fontPaths[1], fontPaths[0]]);
  console.log('PASS reorder survives reload, deduplicates IDs and retains omitted fonts');

  let previous = values.get('catalog');
  failFlushAt = flushCount + 1; // Reading an unchanged catalog no longer flushes it.
  await assert.rejects(service.setEnabled(context, [fontPaths[0]], false), /disk unavailable/);
  assert.equal(values.get('catalog'), previous);
  assert.equal((await service.listEnabled(context)).length, 3);
  previous = values.get('catalog');
  failFlushAt = flushCount + 1;
  await assert.rejects(service.reorder(context, fontPaths), /disk unavailable/);
  assert.equal(values.get('catalog'), previous);
  console.log('PASS failed writes preserve both enabled state and prior order');

  undeletable.add(fontPaths[1]);
  const deleted = await service.removeBatch(context, [fontPaths[0], fontPaths[1]]);
  assert.equal(deleted.failedCount, 1);
  assert.deepEqual(pathsOf(deleted.fonts), [fontPaths[2], fontPaths[1]]);
  assert.ok(!fs.existsSync(fontPaths[0]));
  assert.deepEqual(pathsOf(await service.list(context)), [fontPaths[2], fontPaths[1]]);
  undeletable.clear();
  assert.deepEqual(pathsOf(await service.remove(context, fontPaths[1])), [fontPaths[2]]);
  console.log('PASS partial batch deletion retains failed items and retry removes only selected fonts');

  failFlushAt = flushCount + 1;
  await assert.rejects(service.removeBatch(context, [fontPaths[2]]), /disk unavailable/);
  assert.equal((await service.list(context)).length, 0, 'reload reconciles a deleted file after catalog failure');
  assert.equal((await service.listEnabled(context)).length, 0);
  console.log('PASS deletion failure reconciliation and empty reader choices');

  const inputs = path.join(temp, 'inputs');
  fs.mkdirSync(inputs);
  const data = Buffer.alloc(32); data.writeUInt32BE(0x00010000);
  selectedUris = Array.from({ length: 52 }, (_, index) => {
    const file = path.join(inputs, `font-${index}.ttf`).replaceAll('\\', '/');
    fs.writeFileSync(file, data); return file;
  });
  selectedUris.unshift(selectedUris[0]);
  const beforeImportFlush = flushCount;
  let imported = await service.pick(context);
  assert.equal(imported.fonts.length, 50);
  assert.equal(imported.failures.length, 2);
  assert.deepEqual(Array.from(imported.fonts, font => font.name), Array.from({ length: 50 }, (_, i) => `font-${i}.ttf`));
  assert.equal(peakFiles, 4); assert.equal(activeFiles, 0); assert.equal(handles.size, 0);
  assert.equal(flushCount - beforeImportFlush, 1, 'all successful copies persist in one catalog write');
  assert.equal(registrations, 0, 'import must not decode every font on the UI thread');
  const selected = imported.fonts[0];
  assert.ok(service.register(context, selected.path));
  service.register(context, selected.path);
  assert.equal(registrations, 1, 'the selected font loads once and remains cached');
  const beforeListFlush = flushCount;
  await service.list(context); await service.list(context);
  assert.equal(flushCount, beforeListFlush, 'unchanged reloads do not write preferences');
  console.log('PASS 50-font limit, four concurrent copies, stable order, one flush and lazy font registration');

  const corrupt = path.join(inputs, 'invalid.ttf').replaceAll('\\', '/');
  fs.writeFileSync(corrupt, 'invalid font data');
  selectedUris = [corrupt, selectedUris[1]];
  imported = await service.pick(context);
  assert.equal(imported.fonts.length, 1); assert.equal(imported.failures.length, 1);
  assert.equal(activeFiles, 0);
  const beforeRollback = fs.readdirSync(directory).sort();
  previous = values.get('catalog');
  selectedUris = selectedUris.slice(1);
  failFlushAt = flushCount + 1;
  await assert.rejects(service.pick(context), /disk unavailable/);
  assert.equal(values.get('catalog'), previous);
  assert.deepEqual(fs.readdirSync(directory).sort(), beforeRollback, 'failed catalog save removes new copies only');
  assert.equal(activeFiles, 0);
  console.log('PASS invalid font isolation and complete file/catalog rollback');
})().catch(error => { console.error(error); process.exitCode = 1; })
  .finally(() => fs.rmSync(temp, { recursive: true, force: true }));
