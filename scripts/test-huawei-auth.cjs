// Real AuthService / PreferenceService with simulated Account Kit and local preferences.
// Usage: DEVECO_HOME=<Release IDE> node scripts/test-huawei-auth.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { randomUUID } = require('node:crypto');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets/service');
const accountKey = 'hw_account_v1';
const identity = { unionID: 'union-account-123456789', openID: 'open-account-123456789', loginAt: 1720000000000 };
const profile = { nickName: '听书的朋友', avatarUri: 'https://example.com/account-avatar' };
const avatarFile = '12345678-1234-1234-1234-123456789abc.img';
const compiled = new Map();

function harness(seed) {
  const values = new Map(seed ? [[accountKey, seed]] : []);
  const logs = [];
  const calls = [];
  const medals = { accountId: '', bindAccount: async (_context, id) => { medals.accountId = id; },
    clearAccount: () => { medals.accountId = ''; } };
  const control = {
    state: 1, stateError: null, readError: false, failFlush: false,
    stateGate: null, loginGate: null,
    avatarDownloadFails: false,
    response: request => ({ state: request.state, data: { ...identity, ...profile, authorizationCode: 'NEVER_STORE_TOKEN' } })
  };
  const store = {
    getSync: (key, fallback) => values.has(key) ? values.get(key) : fallback,
    get: async (key, fallback) => {
      if (control.readError) throw new Error('read failed');
      return values.has(key) ? values.get(key) : fallback;
    },
    put: async (key, value) => { values.set(key, value); },
    delete: async key => { values.delete(key); },
    flush: async () => { if (control.failFlush) throw new Error('disk full'); }
  };
  class HuaweiIDProvider {
    createAuthorizationWithHuaweiIDRequest() { return {}; }
    async getHuaweiIDState(request) {
      calls.push({ type: 'state', request });
      if (control.stateGate) await control.stateGate;
      if (control.stateError) throw control.stateError;
      return { state: control.state };
    }
  }
  class AuthenticationController {
    constructor(context) { assert.ok(context); }
    async executeRequest(request) {
      calls.push({ type: 'login', request });
      assert.equal(request.forceAuthorization, true);
      assert.equal(JSON.stringify(request.scopes), '["profile"]');
      assert.equal(request.permissions, undefined, 'client profile does not request a backend authorization code');
      assert.match(request.state, /^[\da-f-]{36}$/);
      if (control.loginGate) await control.loginGate;
      return control.response(request);
    }
  }
  const cache = new Map();
  function load(name) {
    if (cache.has(name)) return cache.get(name);
    const exports = {};
    cache.set(name, exports);
    if (!compiled.has(name)) {
      compiled.set(name, ts.transpileModule(fs.readFileSync(path.join(root, name + '.ets'), 'utf8'), {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021, experimentalDecorators: true }
      }).outputText);
    }
    vm.runInNewContext(compiled.get(name), {
      exports, ObservedV2: value => value, Trace: () => {},
      require: dependency => {
        if (dependency === './MedalService') return { MedalService: { instance: medals } };
        if (dependency === '../model/GeneralSettings' || dependency === '../model/BookPresentation') return load(dependency);
        if (dependency === './MembershipService') return { MembershipService: { instance: {} } };
        if (dependency === '../model/MembershipState') return { MembershipState: { current: { hasAccess: false } } };
        if (dependency === './ReadingSessionService') return { ReadingSessionService: { init: async () => {} } };
        if (dependency === '@kit.AccountKit') return { authentication: {
          HuaweiIDProvider, AuthenticationController, IdType: { OPEN_ID: 2 },
          State: { UNLOGGED_IN: 0, AUTHORIZED: 1, UNAUTHORIZED: 2 }
        } };
        if (dependency === '@kit.ArkTS') return { util: { generateRandomUUID: randomUUID } };
        if (dependency === '@kit.PerformanceAnalysisKit') return { hilog: {
          info: (...args) => logs.push(args), warn: (...args) => logs.push(args), error: (...args) => logs.push(args)
        } };
        if (dependency === '@kit.ArkData') return { preferences: { getPreferences: async () => store } };
        if (dependency === '@kit.AbilityKit') return { ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: -1 } } };
        if (dependency === '@kit.BasicServicesKit') return { emitter: { emit() {} } };
        if (dependency === '../model/AppAppearance') return { AppAppearance: {
          current: {}, normalizeMaterial: value => value, normalizeAccent: value => value
        } };
        if (dependency === '../model/Book') return {};
        if (dependency === './PreferenceService') return load('PreferenceService');
        if (dependency === './AccountAvatarService') return { AccountAvatarService: {
          download: async (_context, uri) => uri && !control.avatarDownloadFails ? avatarFile : '',
          localUri: async (_context, file) => file ? 'file:///cache/' + file : '',
          remove: async () => {}
        } };
        throw new Error('Unexpected dependency: ' + dependency);
      }
    }, { filename: name + '.ets' });
    return exports;
  }
  const authModule = load('AuthService');
  const prefs = load('PreferenceService').PreferenceService;
  return { auth: authModule.AuthService.instance, codes: authModule.HwAuthErrorCode, prefs, control, values, calls, logs, medals };
}

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

(async () => {
  const empty = harness();
  await empty.auth.restore({});
  assert.equal(empty.auth.isLoggedIn, false);
  assert.equal(empty.calls.length, 0, 'first launch must not trigger account authorization');
  assert.throws(() => empty.auth.beginDataOperation(), error => error.code === empty.codes.LOGIN_OUT);
  empty.auth.beginDataOperation(false);
  assert.equal(empty.auth.dataOperation, true, 'local backup does not require login');
  await assert.rejects(empty.auth.login({}), error => error.code === empty.codes.REQUEST_REFUSE);
  assert.throws(() => empty.auth.beginDataOperation(false), error => error.code === empty.codes.REQUEST_REFUSE);
  empty.auth.endDataOperation();
  const loggedIn = await empty.auth.login({});
  assert.equal(empty.auth.isLoggedIn, true);
  assert.equal(loggedIn.openID, identity.openID);
  assert.equal(empty.medals.accountId, identity.openID);
  assert.deepEqual(Object.keys(JSON.parse(empty.values.get(accountKey))).sort(), ['avatarFile', 'loginAt', 'nickName', 'openID', 'unionID']);
  assert.equal(empty.auth.nickName, profile.nickName);
  assert.equal(empty.auth.avatarUri, 'file:///cache/' + avatarFile);
  assert.equal(empty.values.get(accountKey).includes('https://'), false, 'temporary avatar URL is not persisted');
  const restored = harness(empty.values.get(accountKey));
  await restored.auth.restore({});
  assert.equal(restored.auth.isLoggedIn, true);
  assert.equal(restored.auth.nickName, profile.nickName);
  assert.equal(restored.auth.avatarUri, 'file:///cache/' + avatarFile);
  assert.equal(restored.calls[0].request.idValue, identity.openID);
  assert.equal(restored.auth.maskedId().includes(identity.openID), false);
  assert.equal(JSON.stringify(empty.logs).includes(identity.openID), false);
  assert.equal(JSON.stringify(empty.logs).includes('NEVER_STORE_TOKEN'), false);

  empty.auth.beginDataOperation();
  await assert.rejects(empty.auth.logout(), error => error.code === empty.codes.REQUEST_REFUSE);
  await assert.rejects(empty.auth.login({}), error => error.code === empty.codes.REQUEST_REFUSE);
  empty.auth.endDataOperation();
  const avatarFailed = harness();
  avatarFailed.control.avatarDownloadFails = true;
  await avatarFailed.auth.login({});
  assert.equal(avatarFailed.auth.isLoggedIn, true);
  assert.equal(avatarFailed.auth.nickName, profile.nickName);
  assert.equal(avatarFailed.auth.avatarUri, '');
  const legacy = harness(JSON.stringify(identity));
  await legacy.auth.restore({});
  assert.equal(legacy.auth.isLoggedIn, true);
  assert.equal(legacy.auth.nickName, '');
  assert.equal(legacy.calls.filter(call => call.type === 'login').length, 0, 'legacy cache does not pop profile consent at startup');

  for (const state of [0, 2]) {
    const changed = harness(JSON.stringify(identity));
    changed.control.state = state;
    await changed.auth.restore({});
    assert.equal(changed.auth.isLoggedIn, false);
    assert.equal(changed.medals.accountId, '');
    assert.equal(changed.values.has(accountKey), false, 'system logout/switch clears stale identity');
  }
  const retry = harness(JSON.stringify(identity));
  retry.control.stateError = { code: 12300001 };
  await retry.auth.restore({});
  assert.equal(retry.auth.isLoggedIn, false);
  assert.ok(retry.values.has(accountKey));
  retry.control.stateError = null;
  await retry.auth.restore({});
  assert.equal(retry.auth.isLoggedIn, true, 'failed restore remains retryable');

  for (const raw of ['null', '[]', '{}', '{bad', '1', JSON.stringify({ ...identity, openID: 3 }),
    JSON.stringify({ ...identity, unionID: ' ' }), JSON.stringify({ ...identity, loginAt: -1 })]) {
    const invalid = harness(raw);
    await invalid.auth.restore({});
    assert.equal(invalid.auth.isLoggedIn, false);
    assert.equal(invalid.calls.length, 0, 'corrupt cache never becomes an account request');
  }
  for (const response of [request => ({ data: identity }),
    request => ({ state: 'wrong', data: identity }),
    request => ({ state: request.state }),
    request => ({ state: request.state, data: { ...identity, openID: '' } })]) {
    const invalid = harness();
    invalid.control.response = response;
    await assert.rejects(invalid.auth.login({}), error => error.code === invalid.codes.INVALID_RESPONSE);
    assert.equal(invalid.auth.isLoggedIn, false);
    assert.equal(invalid.auth.logging, false);
    assert.equal(invalid.values.has(accountKey), false);
  }
  for (const code of [1001502012, 1001502005, 1001500001]) {
    const failed = harness();
    failed.control.response = () => { throw { code }; };
    await assert.rejects(failed.auth.login({}), error => error.code === code);
    assert.equal(failed.auth.logging, false);
    assert.equal(failed.auth.isLoggedIn, false);
    failed.control.response = request => ({ state: request.state, data: identity });
    await failed.auth.login({});
    assert.equal(failed.auth.isLoggedIn, true);
    assert.notEqual(failed.calls[0].request.state, failed.calls[1].request.state);
  }

  const concurrent = harness();
  const loginGate = deferred();
  concurrent.control.loginGate = loginGate.promise;
  const login = concurrent.auth.login({});
  await assert.rejects(concurrent.auth.login({}), error => error.code === concurrent.codes.REQUEST_REFUSE);
  await assert.rejects(concurrent.auth.logout(), error => error.code === concurrent.codes.REQUEST_REFUSE);
  loginGate.resolve();
  await login;
  assert.equal(concurrent.calls.filter(call => call.type === 'login').length, 1);

  const race = harness(JSON.stringify(identity));
  const stateGate = deferred();
  race.control.stateGate = stateGate.promise;
  const restore = race.auth.restore({});
  const logout = race.auth.logout();
  stateGate.resolve();
  await Promise.all([restore, logout]);
  assert.equal(race.auth.isLoggedIn, false, 'late restore must not undo logout');
  assert.equal(race.values.has(accountKey), false);
  race.values.set('favorite_book_ids', '["book-1"]');
  await race.auth.logout();
  assert.equal(race.values.get('favorite_book_ids'), '["book-1"]');

  const storage = harness();
  storage.control.failFlush = true;
  await assert.rejects(storage.auth.login({}), error => error.code === storage.codes.STORAGE);
  assert.equal(storage.auth.isLoggedIn, false);
  assert.equal(storage.auth.logging, false);
  assert.equal(storage.values.has(accountKey), false, 'failed save must roll back the preference cache');
  storage.control.failFlush = false;
  await storage.auth.login({});
  storage.control.failFlush = true;
  await assert.rejects(storage.auth.logout(), error => error.code === storage.codes.STORAGE);
  assert.equal(storage.auth.isLoggedIn, true, 'failed logout must not report success');
  assert.equal(storage.auth.logging, false);
  assert.equal(JSON.parse(storage.values.get(accountKey)).openID, identity.openID, 'failed logout retains cached identity');
  console.log('PASS: login, restore, account switch/logout, retry, invalid cache/state, cancellation, concurrency, storage failures');
})().catch(error => { console.error(error); process.exitCode = 1; });
