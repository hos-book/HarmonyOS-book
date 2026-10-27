const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/PreferenceService.ets'), 'utf8');
const start = source.indexOf('  static async setJianjianCompanionEnabled(');
const end = source.indexOf('  static async getComicVolumeKeyPageTurn(', start);
assert.ok(start >= 0 && end > start);
const method = source.slice(start, end);

function fixture(initial) {
  const settings = { current: { jianjianCompanionEnabled: initial } };
  let cached = initial;
  let persisted = initial;
  const notifications = [];
  let finish;
  const store = {
    getSync: () => cached,
    put: async (_key, value) => { cached = value; },
    flush: () => new Promise((resolve, reject) => {
      finish = fail => {
        if (fail) reject(new Error('disk unavailable'));
        else { persisted = cached; resolve(); }
      };
    })
  };
  const exports = {};
  vm.runInNewContext(ts.transpileModule(`export class PreferenceService {
    static async ensureStore() { return store; }
    ${method}
  }`, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText,
  { exports, store, GeneralSettings: settings, KEY_JIANJIAN_COMPANION_ENABLED: 'jianjian_companion_enabled',
    EVT_JIANJIAN_COMPANION_CHANGED: 'app.jianjian.companion.changed',
    emitter: { emit: () => notifications.push(settings.current.jianjianCompanionEnabled) } });
  return { service: exports.PreferenceService, settings, get cached() { return cached; },
    get persisted() { return persisted; }, notifications, finish: fail => finish(fail) };
}

(async () => {
  for (const initial of [false, true]) {
    for (const fail of [false, true]) {
      const f = fixture(initial);
      const saving = f.service.setJianjianCompanionEnabled(!initial);
      // 让真实异步 setter 到达挂起的 flush，验证它不能阻塞人物显示/隐藏。
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(f.settings.current.jianjianCompanionEnabled, !initial, 'visibility changes before flush completes');
      assert.equal(f.persisted, initial, 'disk write is still pending');
      assert.deepEqual(f.notifications, [!initial], 'root navigation is notified before disk writes finish');
      f.finish(fail);
      if (fail) {
        await assert.rejects(saving, /Failed to save companion preference/);
        assert.equal(f.settings.current.jianjianCompanionEnabled, initial, 'failed write restores visibility');
        assert.equal(f.cached, initial, 'failed write restores preference cache');
        assert.equal(f.persisted, initial);
        assert.deepEqual(f.notifications, [!initial, initial], 'root navigation is notified on rollback');
      } else {
        await saving;
        assert.equal(f.persisted, !initial, 'successful save survives a subsequent preference read');
      }
    }
  }
  console.log('PASS: immediate companion enable/disable while saving; persistence and failure rollback (4 cases)');
})().catch(error => { console.error(error); process.exitCode = 1; });
