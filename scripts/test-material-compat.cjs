const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const MaterialType = { NONE: 0, ADAPTIVE: 100, IMMERSIVE: 101 };
const MaterialLevel = { EXQUISITE: 0, GENTLE: 1, SMOOTH: 2, ADAPTIVE: 10 };
const appearance = { current: { material: 6 }, systemMaterial: 6 };
const deviceInfo = { sdkApiVersion: 26 };
let supported = [100, 101];
let probeFailure = false;
let immersive = true;
let disabled = false;
let probes = 0;
const hdsMaterial = { MaterialType, MaterialLevel, getSystemMaterialTypes() {
  probes++;
  if (probeFailure) throw new Error('unsupported');
  return supported;
} };
const uiMaterial = { MaterialState: { DISABLE: 2 },
  isImmersiveMaterialSupported() {
    probes++;
    if (probeFailure) throw new Error('unsupported');
    return immersive;
  }, getMaterialInfo: () => ({ state: disabled ? 2 : 0 }) };
function load(file, dependencies) {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8')
    .replace(/import lazy /g, 'import ');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
  const exports = {};
  vm.runInNewContext(js, { exports, require: name => {
    assert.ok(name in dependencies, name);
    return dependencies[name];
  }, canIUse: () => true });
  return exports;
}
const { PlatformCompat } = load('utils/PlatformCompat.ets', {
  '@kit.BasicServicesKit': { deviceInfo }, '@kit.ArkUI': { uiMaterial }
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
supported = [];
assert.equal(HdsCompat.material.materialType, 0);
probeFailure = true;
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
supported = [101];
assert.equal(HdsCompat.material.materialType, 101);
assert.equal(PlatformCompat.immersiveMaterial, false);
deviceInfo.sdkApiVersion = 20;
const before = probes;
assert.equal(HdsCompat.material, undefined);
assert.equal(HdsCompat.adaptiveMaterial, undefined);
assert.equal(PlatformCompat.immersiveMaterial, false);
assert.equal(probes, before, 'old systems never call newer material APIs');
console.log('PASS: material selection, device capabilities, probe failure and API guards');
