// Runs the real login-page lifecycle methods with an isolated ArkWeb adapter.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed DevEco Studio');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const filename = path.resolve(__dirname, '../entry/src/main/ets/pages/RuleSourceLoginPage.ets');
let source = fs.readFileSync(filename, 'utf8');
source = source.slice(0, source.indexOf('  build() {')) + '\n}';
source = source.replace(/^import .*;\r?\n/gm, '').replace('@ComponentV2', '')
  .replace('export struct ', 'export class ').replace(/@(Local|Param) /g, '');
const events = [];
let failWrite = false;
let failRead = false;
let mounted = false;
const cookies = new Map();
const exportsObject = {};
const context = {
  exports: exportsObject,
  NavPathStack: class { pop() { events.push('pop'); } },
  RuleSourceLoginRouteParams: class {},
  webview: {
    WebviewController: class {
      clearSslCache() {}
      setCustomUserAgent() {}
      loadUrl(url) {
        assert.equal(cookies.get(url), 'session=existing; Path=/; Secure');
        events.push('load');
      }
      stop() { events.push('stop'); }
    },
    WebCookieManager: {
      clearAllCookiesSync() { cookies.clear(); events.push('clear'); },
      configCookieSync(url, value, incognito) {
        assert.ok(mounted, 'restore must wait for Web attachment');
        assert.equal(incognito, true);
        if (failWrite) throw new Error('unavailable');
        cookies.set(url, value);
        events.push('inject');
      },
      fetchCookieSync() {
        if (failRead) throw new Error('unavailable');
        return 'session=existing';
      }
    }
  },
  LocalRuleSourceRepository: { get: async () => ({}) },
  LocalRuleBrowserLoginCoordinator: { MAX_HTML_LENGTH: 524288, reject() { events.push('reject'); } },
  LocalRuleWebSession: { acquire: async () => 1, release() { events.push('release'); } },
  LocalRuleHttpClient: {
    getStoredCookieRecords: async () => [],
    getStoredCookieHeader: async () => 'session=existing',
    requestOrigin: url => new URL(url).origin
  },
  WindowUtils: { setStatusBarLight() {} },
  $r: value => value
};
const code = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
vm.runInNewContext(code, context, { filename });
function page() {
  const value = new exportsObject.RuleSourceLoginPage();
  value.route = { sourceUrl: 'test-source', loginUrl: 'https://example.com/login',
    initialHtml: '', requestId: '', isValid: () => true };
  value.showToast = () => events.push('toast');
  return value;
}
(async () => {
  const login = page();
  await login.prepareLogin();
  assert.equal(login.ready, true);
  assert.equal(events.length, 0, 'preparation must not touch the unmounted cookie store');
  assert.equal(login.snapshotCookies().length, 0);
  mounted = true;
  login.restoreWebSession();
  assert.deepEqual(events, ['clear', 'inject', 'load']);
  assert.equal(login.snapshotCookies()[0].cookieHeader, 'session=existing');
  failRead = true;
  assert.equal(login.snapshotCookies().length, 0, 'read failure must not erase persisted cookies');
  failRead = false;
  const broken = page();
  await broken.prepareLogin();
  events.length = 0;
  failWrite = true;
  broken.restoreWebSession();
  assert.ok(!events.includes('load'), 'failed restoration must not silently open a logged-out page');
  assert.equal(broken.snapshotCookies().length, 0);
  failWrite = false;
  events.length = 0;
  let finishPersist;
  login.persistOnDisappear = () => new Promise(resolve => { finishPersist = resolve; });
  login.aboutToDisappear();
  assert.ok(!events.includes('release'), 'retain the lease until cookies are persisted');
  finishPersist();
  await Promise.resolve();
  assert.deepEqual(events, ['stop', 'clear', 'release']);
  console.log('PASS: mounted restore, first-request cookies, read/write failure, persist-before-release');
})().catch(error => { console.error(error); process.exitCode = 1; });
