// Exercise actual input subscriptions, capability guards and asynchronous disposal.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets/service/text');
const handlers = new Map();
const codes = { KEYCODE_VOLUME_UP: 16, KEYCODE_VOLUME_DOWN: 17,
  KEYCODE_FINGERPRINT_SLIDE_UP: 3233, KEYCODE_FINGERPRINT_SLIDE_DOWN: 3234 };
let api = 26, supported = [true, true], releaseProbe = null, failKey = -1, failProbe = false;
const input = { KeyCode: codes, inputConsumer: {
  on(type, options, callback) {
    assert.equal(type, 'keyPressed'); assert.equal(options.action, 1); assert.equal(options.isRepeat, false);
    if (options.key === failKey) throw new Error('subscription failed');
    handlers.set(options.key, callback);
  },
  off(type, callback) { for (const [key, cb] of handlers) if (cb === callback) handlers.delete(key); }
}, inputDevice: {
  getDeviceList: async () => { if (failProbe) throw new Error('device unavailable'); return [1]; },
  supportKeys: () => releaseProbe ? new Promise(resolve => { releaseProbe.resolve = resolve; }) : Promise.resolve(supported)
} };
function load(name, dependencies) {
  const source = fs.readFileSync(path.join(root, name + '.ets'), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
  const exports = {};
  vm.runInNewContext(code, { exports, require: key => {
    if (key === '@kit.InputKit') return input;
    if (key === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {}, info() {} } };
    if (key.endsWith('/PlatformCompat')) return { PlatformCompat: { supports: version => api >= version } };
    if (dependencies[key]) return dependencies[key];
    throw new Error(key);
  } });
  return exports;
}
const volume = load('ReaderVolumeKeyService', {});
const { ReaderSmartKeyService } = load('ReaderSmartKeyService', { './ReaderVolumeKeyService': volume });
const settle = async () => { for (let i = 0; i < 10; i++) await Promise.resolve(); };
(async () => {
  const smart = new ReaderSmartKeyService();
  const turns = [];
  smart.setEnabled(false, value => turns.push(value)); await settle();
  assert.equal(handlers.size, 0, 'disabled setting subscribes to nothing');
  api = 20; smart.setEnabled(true, value => turns.push(value)); await settle();
  assert.equal(handlers.size, 0, 'API 20 must not touch unsupported key codes');
  api = 26; supported = [false, false];
  smart.setEnabled(true, value => turns.push(value)); await settle();
  assert.equal(handlers.size, 2, 'missing physical key flags must not bypass system interception');
  smart.dispose(); supported = [true, true];
  smart.setEnabled(true, value => turns.push(value)); await settle();
  assert.equal(handlers.size, 2);
  handlers.get(3233)(); handlers.get(3234)(); assert.deepEqual(turns, [false, true]);
  assert.equal(handlers.has(16), false, 'smart keys leave volume alone');
  const late = handlers.get(3234);
  smart.dispose(); late(); assert.equal(turns.length, 2); assert.equal(handlers.size, 0);
  failProbe = true;
  smart.setEnabled(true, value => turns.push(value)); await settle();
  assert.equal(handlers.size, 2, 'device enumeration failure still attempts supported API subscription');
  smart.dispose(); failProbe = false;
  failKey = 3234;
  smart.setEnabled(true, value => turns.push(value)); await settle();
  assert.equal(handlers.size, 0, 'partial subscription failure releases the other direction');
  failKey = -1;
  smart.setEnabled(true, value => turns.push(value)); await settle();
  assert.equal(handlers.size, 2, 'failed activation can retry without toggling a stuck enabled flag');
  smart.dispose();
  releaseProbe = {};
  smart.setEnabled(true, value => turns.push(value)); await settle();
  smart.dispose(); releaseProbe.resolve([true, true]); await settle();
  assert.equal(handlers.size, 0, 'late capability result cannot subscribe after leaving');
  console.log('PASS 智控键默认关闭、API守卫、物理键表缺失回退、系统拦截订阅、失败回滚重试、方向、离页异步取消');
})().catch(error => { console.error(error); process.exitCode = 1; });
