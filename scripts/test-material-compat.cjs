const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const MaterialType = { NONE: 0, ADAPTIVE: 100, IMMERSIVE: 101 };
const MaterialLevel = { EXQUISITE: 0, GENTLE: 1, SMOOTH: 2, ADAPTIVE: 10 };
const Color = { Transparent: 'transparent' };
const BlurStyle = { NONE: 0, COMPONENT_ULTRA_THIN: 1, COMPONENT_THIN: 2,
  COMPONENT_REGULAR: 3, COMPONENT_THICK: 4, COMPONENT_ULTRA_THICK: 5 };
const ScrollEffectType = { IMMERSIVE_GRADIENT_BLUR: 1, GRADIENT_BLUR: 2 };
const deviceInfo = { sdkApiVersion: 26 };
let supported = [100, 101];
let probeFailure = false;
let immersive = true;
let disabled = false;
let probes = 0;
let globalLevel = MaterialLevel.GENTLE;
const hdsMaterial = { MaterialType, MaterialLevel, getSystemMaterialTypes() {
  probes++;
  if (probeFailure) throw new Error('unsupported');
  return supported;
} };
const uiMaterial = { MaterialState: { DISABLE: 2 }, MaterialLevel,
  getGlobalMaterialLevel() {
    probes++;
    if (probeFailure) throw new Error('unsupported');
    return globalLevel;
  },
  isImmersiveMaterialSupported() {
    probes++;
    if (probeFailure) throw new Error('unsupported');
    return immersive;
  }, getMaterialInfo: () => ({ state: disabled ? 2 : 0 }) };
function evaluate(source, dependencies, globals = {}) {
  source = source.replace(/import lazy /g, 'import ').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
  const exports = {};
  vm.runInNewContext(js, { exports, require: name => {
    assert.ok(name in dependencies, name);
    return dependencies[name];
  }, canIUse: () => true, Color, BlurStyle, $r: name => name, ...globals });
  return exports;
}
function load(file, dependencies, globals = {}) {
  return evaluate(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8'), dependencies, globals);
}
const { PlatformCompat } = load('utils/PlatformCompat.ets', {
  '@kit.BasicServicesKit': { deviceInfo }, '@kit.ArkUI': { uiMaterial }
});
const { AppAppearance: appearance } = load('model/AppAppearance.ets', {
  './MembershipState': { MembershipState: { current: { canDisplaySavedTheme: true } } },
  '../utils/PlatformCompat': { PlatformCompat }
});
assert.equal(appearance.current.material, 6, 'initial appearance defaults to follow-system');
const { HdsCompat, CompatibleTabsModifier } = load('utils/HdsCompat.ets', {
  '@kit.UIDesignKit': { hdsMaterial, ScrollEffectType }, './PlatformCompat': { PlatformCompat },
  '../theme/Theme': { AppTheme: { Surface: 'theme.surface' } }, '../model/AppAppearance': { AppAppearance: appearance }
});
for (const [selection, level] of [[6, 10], [2, 0], [3, 1], [4, 2], [6, 10]]) {
  appearance.current.material = selection;
  assert.equal(HdsCompat.material.materialLevel, level);
  assert.equal(HdsCompat.adaptiveMaterial.materialLevel, level, 'main and reader floating bars follow the selection');
  assert.equal(HdsCompat.material.materialType, selection === 6 ? 100 : 101);
}
supported = [100];
appearance.current.material = 2;
assert.equal(HdsCompat.material.materialType, 0, 'ADAPTIVE alone does not prove immersive support');
assert.equal(HdsCompat.materialSupported, false);
supported = [100, 101];
globalLevel = MaterialLevel.SMOOTH;
appearance.current.material = 6;
assert.equal(appearance.current.material, 6, 'render fallback must not rewrite saved preference');
assert.equal(appearance.current.effectiveMaterial, 6, 'low capability must not force the balanced level');
assert.equal(HdsCompat.materialSupported, false);
assert.equal(HdsCompat.material.materialType, 0);
globalLevel = MaterialLevel.EXQUISITE;
assert.equal(HdsCompat.material.materialLevel, MaterialLevel.ADAPTIVE);
supported = [];
assert.equal(HdsCompat.material.materialType, 0);
probeFailure = true;
assert.equal(appearance.current.effectiveMaterial, 6, 'failed queries preserve system selection');
assert.equal(HdsCompat.material.materialType, 0);
assert.equal(PlatformCompat.immersiveMaterial, false);
probeFailure = false;
assert.equal(PlatformCompat.immersiveMaterial, true);
disabled = true;
assert.equal(PlatformCompat.immersiveMaterial, false);
disabled = false;
immersive = false;
assert.equal(PlatformCompat.immersiveMaterial, false);
deviceInfo.sdkApiVersion = 23;
globalLevel = MaterialLevel.SMOOTH;
const beforeLegacyQuery = probes;
assert.equal(appearance.current.effectiveMaterial, 6);
assert.equal(probes, beforeLegacyQuery, 'API 23 never queries API 26 global level');
supported = [101];
assert.equal(HdsCompat.material.materialType, 101);
assert.equal(PlatformCompat.immersiveMaterial, false);
deviceInfo.sdkApiVersion = 20;
const before = probes;
assert.equal(HdsCompat.material, undefined);
assert.equal(HdsCompat.adaptiveMaterial, undefined);
assert.equal(PlatformCompat.immersiveMaterial, false);
assert.equal(appearance.current.effectiveMaterial, 6);
assert.equal(probes, before, 'old systems never call newer material APIs');
deviceInfo.sdkApiVersion = 26;
immersive = true;
uiMaterial.ImmersiveStyle = { ULTRA_THIN: 0, THIN: 1, REGULAR: 2, THICK: 3, ULTRA_THICK: 4 };
uiMaterial.ImmersiveMaterial = class { constructor(options) { this.options = options; } };
uiMaterial.Material = { empty: { empty: true } };
const curves = { cubicBezierCurve: () => null, springMotion: () => null };
const { AppMaterial } = load('theme/Theme.ets', {
  '@kit.ArkUI': { uiMaterial, curves },
  '../model/AppAppearance': { AppAppearance: appearance },
  '../model/AppThemeBundle': {}, '../model/AppThemeVisual': {},
  '../utils/PlatformCompat': { PlatformCompat },
  './ThemeBundles': { ThemeBundles: { resolve: () => ({ accent: '', visual: {
    colors: { brand: '#C4475B', controlFallback: 'theme.controlFallback' }
  } }) } }
}, { ThemeColorMode: { SYSTEM: 0, DARK: 1 }, AdaptiveColor: { AVERAGE: 0 },
  BlurStyleActivePolicy: { FOLLOWS_WINDOW_ACTIVE_STATE: 0 } });
appearance.current.material = 6;
globalLevel = MaterialLevel.GENTLE;
const systemSheet = AppMaterial.Sheet;
assert.equal(systemSheet.options.style, uiMaterial.ImmersiveStyle.THIN);
assert.equal(systemSheet.options.lightEffect, undefined);
globalLevel = MaterialLevel.SMOOTH;
assert.equal(AppMaterial.Sheet, undefined, 'SMOOTH does not reuse a transparent native sheet');
assert.notEqual(AppMaterial.SheetBackground, Color.Transparent);
globalLevel = MaterialLevel.GENTLE;
assert.equal(AppMaterial.Sheet, systemSheet, 'supported devices retain their native material');
appearance.current.material = 3;
assert.equal(AppMaterial.Sheet.options.style, uiMaterial.ImmersiveStyle.REGULAR);
assert.equal(AppMaterial.ReaderSheetThick.options.style, uiMaterial.ImmersiveStyle.THICK);

// Execute the real shelf popup option builders from the screenshot, without rendering the whole page.
const shelfSource = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/FavoritePage.ets'), 'utf8');
const popupMethods = ['groupMenuOptions', 'statusFilterMenuOptions'].map(name => {
  const start = shelfSource.indexOf(`  private ${name}(`);
  assert.ok(start >= 0, name);
  const end = shelfSource.indexOf('\n  }', start);
  assert.ok(end > start, name);
  return shelfSource.slice(start, end + 4);
}).join('\n');
const { ShelfPopupHarness } = evaluate(`export class ShelfPopupHarness { ${popupMethods} }`, {}, {
  AppMaterial, PlatformCompat, AppRadius: { Xl: 24 }, Placement: { BottomRight: 1 }
});
const popupHarness = new ShelfPopupHarness();
function attributes() {
  const values = {};
  const node = {};
  for (const name of ['backgroundColor', 'backgroundBlurStyle', 'systemMaterial', 'shadow',
    'menuBackgroundColor', 'menuBackgroundBlurStyle', 'menuSystemMaterial',
    'barFloatingStyle', 'barBackgroundColor', 'barBackgroundBlurStyle', 'barHeight']) {
    node[name] = value => { values[name] = value; return node; };
  }
  return { node, values };
}
function assertVisibleFallback(reason) {
  for (const selection of [6, 2, 3, 4]) {
    appearance.current.material = selection;
    assert.equal(appearance.current.effectiveMaterial, selection, reason);
    assert.equal(PlatformCompat.immersiveMaterial, false, reason);
    assert.equal(HdsCompat.materialSupported, false, reason);
    assert.equal(HdsCompat.scrollEffect, ScrollEffectType.GRADIENT_BLUR, reason);
    assert.equal(AppMaterial.Sheet, undefined, reason);
    assert.equal(AppMaterial.ReaderSheetThick, undefined, reason);
    assert.equal(AppMaterial.ReaderSheetBlur, BlurStyle.COMPONENT_THICK, reason);
    for (const name of ['groupMenuOptions', 'statusFilterMenuOptions']) {
      const popup = popupHarness[name]();
      assert.equal(popup.popupColor, 'sys.color.comp_background_primary', `${reason}: ${name} has a visible base`);
      assert.equal(popup.systemMaterial, undefined, reason);
      assert.ok(popup.backgroundBlurStyle > BlurStyle.NONE, reason);
    }
    const control = attributes();
    AppMaterial.modifier(AppMaterial.InteractiveThin).applyNormalAttribute(control.node);
    assert.equal(control.values.backgroundColor, 'theme.controlFallback', reason);
    assert.ok(control.values.backgroundBlurStyle > BlurStyle.NONE, reason);
    const menu = attributes();
    AppMaterial.selectModifier().applyNormalAttribute(menu.node);
    assert.equal(menu.values.menuBackgroundColor, 'sys.color.comp_background_primary', reason);
    assert.ok(menu.values.menuBackgroundBlurStyle > BlurStyle.NONE, reason);
    if (deviceInfo.sdkApiVersion >= 26) {
      assert.equal(control.values.systemMaterial, uiMaterial.Material.empty, reason);
      assert.equal(menu.values.menuSystemMaterial, uiMaterial.Material.empty, 'clear previous native menu material');
    } else {
      assert.equal(control.values.systemMaterial, undefined, reason);
      assert.equal(menu.values.menuSystemMaterial, undefined, reason);
    }
    const tabs = attributes();
    new CompatibleTabsModifier({ systemMaterialEffect: HdsCompat.material }, 56).applyNormalAttribute(tabs.node);
    assert.equal(tabs.values.barBackgroundColor, 'theme.surface', reason);
    if (deviceInfo.sdkApiVersion >= 23) assert.equal(tabs.values.barBackgroundBlurStyle, BlurStyle.COMPONENT_REGULAR, reason);
  }
}
globalLevel = MaterialLevel.SMOOTH;
assertVisibleFallback('low-compute device despite positive native support');
globalLevel = MaterialLevel.GENTLE;
immersive = false;
assertVisibleFallback('native material unavailable');
immersive = true;
disabled = true;
assertVisibleFallback('application material disabled');
disabled = false;
probeFailure = true;
assertVisibleFallback('capability probe failed');
probeFailure = false;
supported = [];
for (const api of [20, 23, 25]) {
  deviceInfo.sdkApiVersion = api;
  assertVisibleFallback(`API ${api} without HDS material`);
}
deviceInfo.sdkApiVersion = 26;
supported = [100, 101];
for (const level of [MaterialLevel.EXQUISITE, MaterialLevel.GENTLE]) {
  globalLevel = level;
  appearance.current.material = 6;
  for (const name of ['groupMenuOptions', 'statusFilterMenuOptions']) {
    const popup = popupHarness[name]();
    assert.equal(popup.popupColor, Color.Transparent, 'supported devices do not get an opaque backplate');
    assert.ok(popup.systemMaterial instanceof uiMaterial.ImmersiveMaterial);
    assert.equal(popup.backgroundBlurStyle, undefined);
  }
  const tabs = attributes();
  new CompatibleTabsModifier({ systemMaterialEffect: HdsCompat.material }, 56).applyNormalAttribute(tabs.node);
  assert.equal(tabs.values.barBackgroundColor, Color.Transparent);
  assert.equal(tabs.values.barBackgroundBlurStyle, BlurStyle.NONE);
  assert.equal(HdsCompat.scrollEffect, ScrollEffectType.IMMERSIVE_GRADIENT_BLUR);
}
console.log('PASS: native capability guards, shelf popups, menus, controls, tab backgrounds, all preferences and API 20/23/25/26 fallback');
