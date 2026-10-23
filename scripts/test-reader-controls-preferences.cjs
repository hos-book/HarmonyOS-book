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
  assert.equal(await service.getComicVolumeKeyPageTurn(), false, 'volume keys default off');
  assert.equal(await service.getComicReadingMode(), 0);
  assert.equal(await service.getComicChapterBar(false), false, 'migrate the former shared chapter bar once');
  assert.equal(await load().getComicChapterBar(true), false, 'later novel changes cannot alter comic controls');
  await service.setComicVolumeKeyPageTurn(true);
  await service.setComicReadingMode(3);
  await service.setComicChapterBar(true);
  const otherComic = load();
  assert.equal(await otherComic.getComicVolumeKeyPageTurn(), true, 'reopen and other comics share volume preference');
  assert.equal(await otherComic.getComicReadingMode(), 3, 'reading mode is global across comics');
  assert.equal(await otherComic.getComicChapterBar(), true);
  await otherComic.setComicVolumeKeyPageTurn(false);
  assert.equal(await load().getComicVolumeKeyPageTurn(), false, 'disabling is persisted too');
  failFlush = true;
  await assert.rejects(service.setComicVolumeKeyPageTurn(true));
  await assert.rejects(service.setComicReadingMode(1));
  await assert.rejects(service.setComicChapterBar(false));
  assert.equal(await load().getComicVolumeKeyPageTurn(), false);
  assert.equal(await load().getComicReadingMode(), 3);
  assert.equal(await load().getComicChapterBar(), true);
  failFlush = false;
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
  console.log('PASS: comic global mode/volume/controls, defaults, migration, reload, isolation and save rollback; brightness and handedness');
})().catch(error => { console.error(error); process.exitCode = 1; });
