const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/PreferenceService.ets'), 'utf8');
const code = ts.transpileModule(source, { compilerOptions: {
  target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS
} }).outputText;
const values = new Map([['reader_brightness', 0.73], ['showBrightnessBar', true]]);
const state = { adaptiveHandedness: true };
let failFlush = false;
const store = {
  getSync: (key, fallback) => values.get(key) ?? fallback,
  put: async (key, value) => values.set(key, value),
  flush: async () => { if (failFlush) throw new Error('disk full'); }
};
function load() {
  const exports = {};
  vm.runInNewContext(code, { exports, require: name => name === '../model/GeneralSettings' ?
    { GeneralSettings: { current: state } } : {} });
  exports.PreferenceService.store = store;
  return exports.PreferenceService;
}
(async () => {
  const service = load();
  assert.equal(await service.getComicBrightnessBar(), true);
  assert.equal(await service.getComicBrightness(), -1);
  await service.setComicBrightnessBar(false);
  await service.setComicBrightness(0.42);
  const restarted = load();
  assert.equal(await restarted.getComicBrightnessBar(), false);
  assert.equal(await restarted.getComicBrightness(), 0.42);
  assert.equal(values.get('reader_brightness'), 0.73);
  assert.equal(values.get('showBrightnessBar'), true);
  await service.setComicBrightness(-1);
  assert.equal(await restarted.getComicBrightness(), -1);
  await service.setComicBrightness(2);
  assert.equal(await restarted.getComicBrightness(), 1);
  values.set('comic_brightness', 'bad');
  assert.equal(await restarted.getComicBrightness(), -1);
  await service.setAdaptiveHandedness(false);
  assert.equal(state.adaptiveHandedness, false);
  assert.equal(values.get('adaptive_handedness'), false);
  failFlush = true;
  await assert.rejects(service.setAdaptiveHandedness(true));
  assert.equal(state.adaptiveHandedness, false);
  assert.equal(values.get('adaptive_handedness'), false);
  failFlush = false;
  await service.setAdaptiveHandedness(true);
  assert.equal(state.adaptiveHandedness, true);
  console.log('PASS: comic brightness defaults, reload, isolation, normalization and handedness save/rollback');
})().catch(error => { console.error(error); process.exitCode = 1; });
