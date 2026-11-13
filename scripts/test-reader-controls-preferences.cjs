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
const state = { adaptiveHandedness: true, swipeSwitchTabs: true };
let failFlush = false;
const store = {
  getSync: (key, fallback) => values.get(key) ?? fallback,
  get: async (key, fallback) => values.get(key) ?? fallback,
  has: async key => values.has(key),
  hasSync: key => values.has(key),
  delete: async key => values.delete(key),
  put: async (key, value) => values.set(key, value),
  flush: async () => { if (failFlush) throw new Error('disk full'); }
};
function load() {
  const exports = {};
  vm.runInNewContext(code, { exports, require: name => {
    if (name === '../model/GeneralSettings') return { GeneralSettings: { current: state } };
    if (name === '@kit.ArkData') return { preferences: { getPreferences: async () => store } };
    if (name === '@kit.BasicServicesKit') return { emitter: { emit() {} } };
    if (name === '../model/AppAppearance') return { AppAppearance: { current: { themeBundleId: 'default' } } };
    if (name === './ReadingSessionService') return { ReadingSessionService: { init() {} } };
    if (name === '../model/BookPresentation') return { BookPresentation: { edits: [], groups: [] } };
    return {};
  } });
  exports.PreferenceService.store = store;
  exports.PreferenceService.decodeThemeSelection = () => ({});
  exports.PreferenceService.publishThemeSelection = () => {};
  return exports.PreferenceService;
}
(async () => {
  const service = load();
  await service.setMiniPlayerHideMinutes(-1);
  assert.equal(state.miniPlayerHideMinutes, -1);
  assert.equal(values.get('mini_player_hide_minutes'), -1, 'disabled persists independently of always-visible');
  await service.setMiniPlayerHideMinutes(0);
  assert.equal(state.miniPlayerHideMinutes, 0);
  await assert.rejects(service.setMiniPlayerHideMinutes(-2));
  await service.setSelectionMenu('copy,listen,excerpt', 'share');
  assert.equal(values.get('reader_selection_menu'), 'copy,listen,excerpt|share');
  assert.equal(state.selectionMenuHidden, 'share');
  failFlush = true;
  await assert.rejects(service.setSelectionMenu('listen,copy', 'copy'));
  assert.equal(state.selectionMenuHidden, 'share', 'failed save preserves the active menu');
  assert.equal(values.get('reader_selection_menu'), 'copy,listen,excerpt|share');
  failFlush = false;
  assert.equal(await service.getComicVolumeKeyPageTurn(), false, 'volume keys default off');
  assert.equal(await service.getComicReadingMode(), 0);
  assert.equal(await service.getComicPageLayout(), 1, 'whole image fits the screen by default');
  assert.equal(await service.getComicPageOverlap(), 10);
  await service.setComicPageLayout(2);
  await service.setComicPageOverlap(30);
  assert.equal(await load().getComicPageLayout(), 2);
  assert.equal(await load().getComicPageOverlap(), 30);
  await assert.rejects(service.setComicPageLayout(3));
  await assert.rejects(service.setComicPageOverlap(99));
  assert.equal(await service.getComicTranslationDirection(), 'ja-zh');
  for (const direction of ['ja-zh','ko-zh','en-zh','zh-en']) {
    await service.setComicTranslationDirection(direction);
    assert.equal(await load().getComicTranslationDirection(), direction, 'translation direction survives reopening');
  }
  await assert.rejects(service.setComicTranslationDirection('invalid'));
  assert.equal(await load().getComicTranslationDirection(), 'zh-en');
  assert.equal(await service.getComicChapterBar(false), false, 'migrate the former shared chapter bar once');
  assert.equal(await load().getComicChapterBar(true), false, 'later novel changes cannot alter comic controls');
  await service.setComicVolumeKeyPageTurn(true);
  await service.setComicReadingMode(3);
  await service.setComicChapterBar(true);
  const otherComic = load();
  assert.equal(await otherComic.getComicVolumeKeyPageTurn(), true, 'reopen and other comics share volume preference');
  assert.equal(await otherComic.getComicReadingMode(), 3, 'reading mode is global across comics');
  await service.setComicReadingMode(2, 'comic-a');
  assert.equal(await load().getComicReadingMode('comic-a'), 2, 'per-book mode survives reopening');
  assert.equal(await load().getComicReadingMode('comic-b'), 3, 'unset books follow the global default');
  await service.setComicReadingMode(1);
  assert.equal(await service.getComicReadingMode('comic-a'), 2, 'default changes preserve book overrides');
  assert.equal(await service.getComicReadingMode('comic-b'), 1);
  assert.equal(await service.hasComicReadingMode('comic-a'), true);
  await service.resetComicReadingMode('comic-a');
  assert.equal(await service.hasComicReadingMode('comic-a'), false);
  assert.equal(await load().getComicReadingMode('comic-a'), 1, 'reset resumes following the default');
  await service.setComicReadingMode(3);
  assert.equal(await otherComic.getComicChapterBar(), true);
  await otherComic.setComicVolumeKeyPageTurn(false);
  assert.equal(await load().getComicVolumeKeyPageTurn(), false, 'disabling is persisted too');
  failFlush = true;
  await assert.rejects(service.setComicTranslationDirection('en-zh'));
  assert.equal(await load().getComicTranslationDirection(), 'zh-en', 'failed direction save rolls back');
  await assert.rejects(service.setComicVolumeKeyPageTurn(true));
  await assert.rejects(service.setComicReadingMode(1));
  await assert.rejects(service.setComicPageLayout(0));
  await assert.rejects(service.setComicPageOverlap(0));
  assert.equal(await load().getComicPageLayout(), 2, 'failed layout save rolls back');
  assert.equal(await load().getComicPageOverlap(), 30, 'failed overlap save rolls back');
  await assert.rejects(service.setComicChapterBar(false));
  assert.equal(await load().getComicVolumeKeyPageTurn(), false);
  assert.equal(await load().getComicReadingMode(), 3);
  assert.equal(await load().getComicChapterBar(), true);
  failFlush = false;
  values.set('comic_translation_direction', 'unsupported');
  assert.equal(await service.getComicTranslationDirection(), 'ja-zh', 'invalid persisted direction falls back');
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
  const reboot = async () => {
    const service = load();
    service.store = null;
    state.swipeSwitchTabs = true;
    await service.init({});
    return service;
  };
  await reboot();
  assert.equal(state.swipeSwitchTabs, true, 'fresh installation defaults to tab swipes');
  await service.setSwipeSwitchTabs(false);
  assert.equal(state.swipeSwitchTabs, false, 'saved choice immediately updates shared state');
  assert.equal(values.get('swipe_switch_tabs'), false);
  await reboot();
  assert.equal(state.swipeSwitchTabs, false, 'disabled choice survives actual preference initialization');
  failFlush = true;
  await assert.rejects(service.setSwipeSwitchTabs(true));
  assert.equal(state.swipeSwitchTabs, false);
  assert.equal(values.get('swipe_switch_tabs'), false, 'failed save restores the previous stored value');
  failFlush = false;
  await service.setSwipeSwitchTabs(true);
  await reboot();
  assert.equal(state.swipeSwitchTabs, true, 'enabled choice also survives a restart');
  console.log('PASS: swipe mode default, live update, restart persistence and failed-save rollback');
  console.log('PASS: comic global mode/volume/controls, defaults, migration, reload, isolation and save rollback; brightness and handedness');
})().catch(error => { console.error(error); process.exitCode = 1; });
