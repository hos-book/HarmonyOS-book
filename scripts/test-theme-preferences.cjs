const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const etsRoot = path.join(__dirname, '../entry/src/main/ets');
const themeKey = 'app_theme_preferences';
const realModules = new Set([
  'model/AppAppearance', 'model/AppThemeBundle', 'model/AppThemeVisual', 'theme/ThemeBundles',
  'theme/bundles/DefaultTheme', 'theme/bundles/PaperTheme', 'theme/bundles/MistTheme', 'theme/bundles/InkTheme', 'service/PreferenceService'
]);
const compiled = new Map();

function compile(name) {
  if (!compiled.has(name)) {
    const source = fs.readFileSync(path.join(etsRoot, name + '.ets'), 'utf8');
    compiled.set(name, ts.transpileModule(source, { compilerOptions: {
      target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS, experimentalDecorators: true
    } }).outputText);
  }
  return compiled.get(name);
}

// Preferences has a writable memory cache. A failed flush leaves put() data in that cache;
// an unrelated later flush must not accidentally persist a rejected appearance change.
function createDisk(entries = []) {
  return { values: new Map(entries) };
}

async function launch(disk, member = true) {
  const cache = new Map(disk.values);
  const controls = { failFlush: false, beforeFlush: undefined, member };
  const membership = { MembershipState: { current: { get hasAccess() { return controls.member; } } } };
  const store = {
    getSync: (key, fallback) => cache.has(key) ? cache.get(key) : fallback,
    get: async (key, fallback) => cache.has(key) ? cache.get(key) : fallback,
    getAll: async () => Object.fromEntries(cache),
    put: async (key, value) => { cache.set(key, value); },
    delete: async key => { cache.delete(key); },
    flush: async () => {
      await controls.beforeFlush?.();
      if (controls.failFlush) throw new Error('simulated disk full');
      disk.values = new Map(cache);
    }
  };
  const mocks = {
    '@kit.ArkData': { preferences: { getPreferences: async () => store } },
    '@kit.AbilityKit': { ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: -1 } } },
    '@kit.BasicServicesKit': { emitter: { emit: () => {} } },
    '../model/GeneralSettings': { GeneralSettings: { current: {} } },
    '../model/BookPresentation': { BookPresentation: { edits: [], groups: [] } },
    '../model/MembershipState': membership,
    './MembershipState': membership,
    './MembershipService': { MembershipService: { instance: { hasCurrentEntitlement: async () => controls.member } } },
    './ReadingSessionService': { ReadingSessionService: { init: () => {} } },
    '../model/Book': {}
  };
  const context = vm.createContext({
    console, Error, ObservedV2: value => value, Trace: () => {}, $r: name => ({ id: name })
  });
  const modules = new Map();
  function load(name) {
    if (modules.has(name)) return modules.get(name);
    assert.ok(realModules.has(name), `Unexpected ETS dependency: ${name}`);
    const exports = {};
    modules.set(name, exports);
    const localRequire = request => {
      if (Object.hasOwn(mocks, request)) return mocks[request];
      const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(name), request));
      return load(resolved);
    };
    vm.runInContext(`(function(exports, require) {\n${compile(name)}\n})`, context,
      { filename: name + '.ets' })(exports, localRequire);
    return exports;
  }
  const preference = load('service/PreferenceService');
  const appearance = load('model/AppAppearance').AppAppearance.current;
  await preference.PreferenceService.init({});
  return {
    service: preference.PreferenceService, Snapshot: preference.PreferenceBackupSnapshot,
    Selection: load('model/AppThemeBundle').AppThemeSelection,
    bundles: load('theme/ThemeBundles').ThemeBundles, appearance, cache, controls, disk
  };
}

function appearanceOf(app) {
  return [app.appearance.themeBundleId, app.appearance.accent, app.appearance.material];
}

function storedSelection(app) {
  return JSON.parse(app.disk.values.get(themeKey));
}

function expectedSelection(id, accent, material) {
  return { schemaVersion: 1, themeBundleId: id, accentColor: accent, materialStyle: material };
}

(async () => {
  const disk = createDisk([['accent_color', '#123abc'], ['material_style', 5]]);
  let app = await launch(disk);
  assert.deepEqual(appearanceOf(app), ['default', '#123ABC', 4], 'legacy custom appearance survives upgrade');
  assert.equal(disk.values.has(themeKey), false, 'initialization does not overwrite legacy preferences');

  const paper = app.bundles.resolve('paper-study');
  const migratedInk = await launch(createDisk([[themeKey,
    JSON.stringify(new app.Selection('ink-wash', '#A34335', 3))]]));
  assert.deepEqual(appearanceOf(migratedInk), ['ink-wash', '#80612E', 3], 'old ink recommendation follows the new palette');
  const customizedInk = await launch(createDisk([[themeKey,
    JSON.stringify(new app.Selection('ink-wash', '#2255AA', 4))]]));
  assert.deepEqual(appearanceOf(customizedInk), ['ink-wash', '#2255AA', 4], 'custom ink accent and material survive upgrade');
  let startFlush;
  let finishFlush;
  const flushing = new Promise(resolve => { startFlush = resolve; });
  const releaseFlush = new Promise(resolve => { finishFlush = resolve; });
  app.controls.beforeFlush = async () => { startFlush(); await releaseFlush; };
  const apply = app.service.applyThemeBundle(paper.id);
  await flushing;
  assert.deepEqual(appearanceOf(app), ['default', '#123ABC', 4], 'publish only after successful persistence');
  finishFlush();
  await apply;
  app.controls.beforeFlush = undefined;
  assert.deepEqual(appearanceOf(app), [paper.id, paper.accent, paper.material]);
  assert.deepEqual(storedSelection(app), expectedSelection(paper.id, paper.accent, paper.material));

  await Promise.all([
    app.service.applyThemeBundle('paper-study'),
    app.service.setAccentColor('#2255aa'),
    app.service.setMaterialStyle(4)
  ]);
  assert.deepEqual(appearanceOf(app), ['paper-study', '#2255AA', 4], 'queued changes keep every selected field');
  assert.deepEqual(storedSelection(app), expectedSelection('paper-study', '#2255AA', 4));
  app = await launch(disk);
  assert.deepEqual(appearanceOf(app), ['paper-study', '#2255AA', 4], 'fresh process restores the complete selection');

  const beforeFailure = disk.values.get(themeKey);
  app.controls.failFlush = true;
  await assert.rejects(app.service.applyThemeBundle('default'), /disk full/);
  assert.deepEqual(appearanceOf(app), ['paper-study', '#2255AA', 4], 'failed apply keeps the visible theme');
  assert.equal(app.cache.get(themeKey), beforeFailure, 'failed apply rolls back the Preferences cache');
  assert.equal(disk.values.get(themeKey), beforeFailure);
  app.controls.failFlush = false;
  await app.service.setDefaultTab(2);
  assert.equal(disk.values.get(themeKey), beforeFailure, 'an unrelated successful flush cannot persist the failed theme');
  await app.service.setMaterialStyle(2);
  assert.deepEqual(appearanceOf(app), ['paper-study', '#2255AA', 2], 'a failed write does not poison the save queue');
  await assert.rejects(app.service.applyThemeBundle('removed-theme'), /Unknown theme/);
  assert.deepEqual(appearanceOf(app), ['paper-study', '#2255AA', 2]);

  for (const raw of ['{broken', 'null', '[]', '{"schemaVersion":2}', 'x'.repeat(2049)]) {
    const invalid = await launch(createDisk([
      ['accent_color', '#123ABC'], ['material_style', 2], [themeKey, raw]
    ]));
    assert.deepEqual(appearanceOf(invalid), ['default', '#123ABC', 2], 'invalid stored records fall back to legacy settings');
  }
  const unknown = await launch(createDisk([[themeKey,
    JSON.stringify(new app.Selection('removed-theme', '#335577', 4))]]));
  assert.deepEqual(appearanceOf(unknown), ['default', '#335577', 4], 'unknown bundles retain valid custom overrides on the default bundle');
  const invalidOverrides = await launch(createDisk([[themeKey,
    JSON.stringify(new app.Selection('paper-study', 'invalid-color', 99))]]));
  assert.deepEqual(appearanceOf(invalidOverrides), ['paper-study', '', 3], 'invalid overrides normalize safely');

  const snapshot = await app.service.exportBackupSnapshot();
  assert.ok(snapshot.themeSelection instanceof app.Selection, 'export uses the real selection data carrier');
  assert.deepEqual(JSON.parse(JSON.stringify(snapshot.themeSelection)), expectedSelection('paper-study', '#2255AA', 2));
  const restored = await launch(createDisk());
  await restored.service.restoreBackupSnapshot(JSON.parse(JSON.stringify(snapshot)));
  assert.deepEqual(appearanceOf(restored), ['paper-study', '#2255AA', 2]);
  assert.deepEqual(appearanceOf(await launch(restored.disk)), ['paper-study', '#2255AA', 2], 'restored snapshot survives restart');

  const legacy = new restored.Snapshot();
  legacy.accentColor = '#778899';
  legacy.materialStyle = 4;
  await restored.service.restoreBackupSnapshot(legacy);
  assert.deepEqual(appearanceOf(restored), ['default', '#778899', 4], 'pre-theme backup defaults to the default bundle and preserves overrides');
  assert.deepEqual(storedSelection(restored), expectedSelection('default', '#778899', 4));
  await restored.service.restoreBackupSnapshot(new restored.Snapshot());
  assert.deepEqual(appearanceOf(restored), ['default', '', 3], 'old backup without appearance preferences gets safe defaults');

  const failedRestore = await launch(createDisk([['accent_color', '#123ABC'], ['material_style', 4]]));
  failedRestore.controls.failFlush = true;
  await assert.rejects(failedRestore.service.restoreBackupSnapshot(JSON.parse(JSON.stringify(snapshot))), /disk full/);
  assert.deepEqual(appearanceOf(failedRestore), ['default', '#123ABC', 4], 'failed restore keeps the current appearance');
  failedRestore.controls.failFlush = false;
  await failedRestore.service.setDefaultTab(1);
  assert.deepEqual(appearanceOf(await launch(failedRestore.disk)), ['default', '#123ABC', 4],
    'failed restore must roll back legacy appearance keys before an unrelated flush');

  // Every registered bundle participates in persistence and backup without special-case IDs.
  const registry = restored.bundles.list();
  assert.equal(registry.length, 4);
  assert.equal(new Set(registry.map(bundle => bundle.id)).size, registry.length);
  for (const bundle of registry) {
    await restored.service.applyThemeBundle(bundle.id);
    assert.deepEqual(appearanceOf(restored), [bundle.id, bundle.accent, bundle.material]);
    assert.deepEqual(appearanceOf(await launch(restored.disk)), [bundle.id, bundle.accent, bundle.material]);
    const saved = await restored.service.exportBackupSnapshot();
    const fresh = await launch(createDisk());
    await fresh.service.restoreBackupSnapshot(JSON.parse(JSON.stringify(saved)));
    assert.deepEqual(appearanceOf(fresh), [bundle.id, bundle.accent, bundle.material]);
    await fresh.service.setAccentColor('#123456');
    await fresh.service.setMaterialStyle(4);
    await fresh.service.applyThemeBundle(bundle.id);
    assert.deepEqual(appearanceOf(fresh), [bundle.id, bundle.accent, bundle.material],
      'reapplying the current bundle restores its own accent and material');
    assert.deepEqual(appearanceOf(await launch(fresh.disk)), [bundle.id, bundle.accent, bundle.material],
      'reapplied bundle palette survives restart');
    await fresh.service.setAccentColor('#123456');
    await fresh.service.setMaterialStyle(4);
    await fresh.service.resetThemeBundleOverrides();
    assert.deepEqual(appearanceOf(fresh), [bundle.id, bundle.accent, bundle.material]);
  }

  const restricted = await launch(createDisk([[themeKey, JSON.stringify(new app.Selection('paper-study', '#2255AA', 4))]]), false);
  assert.equal(restricted.appearance.themeBundleId, 'default', 'stored VIP theme cannot activate before verification');
  await assert.rejects(restricted.service.applyThemeBundle('paper-study'), /MEMBERSHIP_REQUIRED/);
  await restricted.service.restoreBackupSnapshot(snapshot);
  assert.equal(restricted.appearance.themeBundleId, 'default', 'backup restore cannot activate VIP themes');
  await restricted.service.applyThemeBundle('default');
  await restricted.service.setAccentColor('#123456');
  await restricted.service.setMaterialStyle(4);
  assert.deepEqual(appearanceOf(restricted), ['default', '#123456', 4], 'basic appearance stays free');
  restricted.controls.member = true;
  await restricted.service.applyThemeBundle('paper-study');
  restricted.controls.member = false;
  assert.equal(restricted.appearance.themeBundleId, 'default', 'revocation immediately hides the active VIP bundle');
  restricted.controls.member = true;
  assert.equal(restricted.appearance.themeBundleId, 'paper-study', 'verified membership restores the chosen bundle');
  console.log('PASS: theme persistence, rollback, restore and VIP enforcement');
})().catch(error => { console.error(error); process.exitCode = 1; });
