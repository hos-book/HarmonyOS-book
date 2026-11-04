const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const MaterialType = { NONE: 0, ADAPTIVE: 100, IMMERSIVE: 101 };
const MaterialLevel = { EXQUISITE: 0, GENTLE: 1, SMOOTH: 2, ADAPTIVE: 10 };
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
function load(file, dependencies, globals = {}) {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8')
    .replace(/import lazy /g, 'import ').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
  const exports = {};
  vm.runInNewContext(js, { exports, require: name => {
    assert.ok(name in dependencies, name);
    return dependencies[name];
  }, canIUse: () => true, ...globals });
  return exports;
}
const { PlatformCompat } = load('utils/PlatformCompat.ets', {
  '@kit.BasicServicesKit': { deviceInfo }, '@kit.ArkUI': { uiMaterial }
});
const { AppAppearance: appearance } = load('model/AppAppearance.ets', {
  './MembershipState': { MembershipState: { current: { canDisplaySavedTheme: true } } },
  '../utils/PlatformCompat': { PlatformCompat }
});
const { HdsCompat } = load('utils/HdsCompat.ets', {
  '@kit.UIDesignKit': { hdsMaterial }, './PlatformCompat': { PlatformCompat },
  '../theme/Theme': { AppTheme: {} }, '../model/AppAppearance': { AppAppearance: appearance }
});
for (const [selection, level] of [[6, 10], [2, 0], [3, 1], [4, 2], [6, 10]]) {
  appearance.current.material = selection;
  assert.equal(HdsCompat.material.materialLevel, level);
  assert.equal(HdsCompat.adaptiveMaterial.materialLevel, level, 'main and reader floating bars follow the selection');
  assert.equal(HdsCompat.material.materialType, selection === 6 ? 100 : 101);
}
supported = [100];
appearance.current.material = 2;
assert.equal(HdsCompat.material.materialType, 100, 'adaptive-only device gets supported material');
supported = [100, 101];
globalLevel = MaterialLevel.SMOOTH;
appearance.current.material = 6;
const weakSystem = HdsCompat.material;
assert.equal(appearance.current.material, 6, 'render fallback must not rewrite saved preference');
assert.equal(appearance.current.effectiveMaterial, 3);
appearance.current.material = 3;
assert.deepEqual(weakSystem, HdsCompat.material, 'weak device follows the exact manual balanced HDS path');
appearance.current.material = 4;
assert.equal(HdsCompat.material.materialLevel, MaterialLevel.SMOOTH, 'explicit weak selection is preserved');
appearance.current.material = 6;
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
const curves = { cubicBezierCurve: () => null, springMotion: () => null };
const { AppMaterial } = load('theme/Theme.ets', {
  '@kit.ArkUI': { uiMaterial, curves },
  '../model/AppAppearance': { AppAppearance: appearance },
  '../model/AppThemeBundle': {}, '../model/AppThemeVisual': {},
  '../utils/PlatformCompat': { PlatformCompat },
  './ThemeBundles': { ThemeBundles: { resolve: () => ({ accent: '', visual: { colors: { brand: '#C4475B' } } }) } }
}, { $r: name => name, BlurStyle: {}, ThemeColorMode: { SYSTEM: 0, DARK: 1 }, AdaptiveColor: { AVERAGE: 0 },
  BlurStyleActivePolicy: { FOLLOWS_WINDOW_ACTIVE_STATE: 0 } });
appearance.current.material = 6;
globalLevel = MaterialLevel.GENTLE;
const systemSheet = AppMaterial.Sheet;
assert.equal(systemSheet.options.style, uiMaterial.ImmersiveStyle.THIN);
assert.equal(systemSheet.options.lightEffect, undefined);
globalLevel = MaterialLevel.SMOOTH;
const weakSheet = AppMaterial.Sheet;
assert.notEqual(weakSheet, systemSheet, 'effective level invalidates cached material');
assert.equal(weakSheet.options.style, uiMaterial.ImmersiveStyle.REGULAR);
assert.equal(weakSheet.options.lightEffect.color, '#C4475B');
appearance.current.material = 3;
assert.equal(AppMaterial.Sheet, weakSheet, 'fallback and manual balanced share the same ArkUI material');
assert.equal(AppMaterial.ReaderSheetThick.options.style, uiMaterial.ImmersiveStyle.THICK);
console.log('PASS: HDS/ArkUI balanced fallback, cache, saved preference, fixed sheets, failures and API guards');
