// Real ArkTS policy/service with simulated IAP; real Node ES256 checks for the JWS signature adapter.
// Native HarmonyOS PKIX validation and real purchases require device/sandbox verification.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
let now = Date.now();
class Clock extends Date { constructor(...args) { super(...(args.length ? args : [now])); } static now() { return now; } }
const util = {
  Base64Helper: class { decodeSync(s) { return new Uint8Array(Buffer.from(s, 'base64')); } },
  TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder('utf-8', { fatal: true }).decode(bytes) }) },
  TextEncoder: class { encodeInto(s) { return new Uint8Array(Buffer.from(s)); } }
};
function load(relative, overrides = {}, globals = {}) {
  const exports = {};
  const source = fs.readFileSync(path.join(root, relative), 'utf8')
    .replace(/import lazy /g, 'import ').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  vm.runInNewContext(js, {
    exports, require: name => { if (name in overrides) return overrides[name]; throw new Error('Unexpected import: ' + name); },
    $r: name => name, Date: Clock, Uint8Array, Set, Map, console, canIUse: () => true,
    // Only fast-forward Promise sleep resolvers; operation deadlines and refresh callbacks stay pending.
    setTimeout: (fn, delay) => { if (fn.length > 0 && delay <= 5100) { now += delay; queueMicrotask(fn); } return 1; },
    clearTimeout() {}, ...globals
  }, { filename: relative });
  return exports;
}
const data = load('service/membership/SubscriptionData.ets');
const lifetimeData = load('service/membership/LifetimeData.ets', { './SubscriptionData': data });
const displayData = load('model/MembershipDisplaySnapshot.ets');
const { SubscriptionPolicy: policy } = data;
const clone = value => JSON.parse(JSON.stringify(value));
function lifetime(changes = {}) {
  return { applicationId: '6917615941058168740', environment: 'NORMAL', productId: 'lastVip',
    productType: '1', purchaseToken: 'life-token', purchaseOrderId: 'life-order', finishStatus: '2',
    purchaseTime: now - 50000, signedTime: now - 1000, price: 19800, currency: 'CNY', ...changes };
}
function payload(changes = {}) {
  return {
    environment: 'NORMAL', applicationId: '6917615941058168740', packageName: 'com.huan.listenbook', subGroupId: 'icons',
    lastSubscriptionStatus: {
      status: '1', expiresTime: now + 86400000, renewalInfo: { autoRenewStatusCode: '1' },
      lastPurchaseOrder: { environment: 'NORMAL', applicationId: '6917615941058168740', productId: 'iconMonth', productType: '2',
        purchaseToken: 'token-1', purchaseOrderId: 'order-1', finishStatus: '2', purchaseTime: now - 1000 }
    }, ...changes
  };
}
let count = 0;
async function test(name, fn) { await fn(); count++; console.log('PASS', name); }

async function main() {
  await test('Authenticated cloud offer transport validates configuration, product, expiry and gateway failures', async () => {
    let functionName = '', calls = 0, cloudError = null;
    let desktopWindow = false, supportedApi = true;
    let response = { result: JSON.stringify({ productId: 'lastVip', offerId: 'lifetime_half_2026',
      jwsRepresentation: 'a.b.c', expiresAt: now + 300000 }) };
    const client = load('service/membership/MembershipOfferClient.ets', {
      '../../utils/PlatformCompat': { PlatformCompat: { get desktopWindow() { return desktopWindow; }, supports: () => supportedApi } },
      '@kit.CloudFoundationKit': { cloudFunction: { call: async request => {
        calls++; assert.equal(request.name, 'membership-offer'); assert.equal(request.version, '1');
        assert.equal(request.timeout, 10000);
        assert.deepEqual(JSON.parse(request.data), { productId: 'lastVip', offerId: 'lifetime_half_2026' });
        if (cloudError) throw cloudError;
        return response;
      } } }
    }).MembershipOfferClient;
    const ctx = { resourceManager: { getStringSync: () => functionName } };
    await assert.rejects(client.request(ctx, 'lastVip', 'lifetime_half_2026'), e => e.code === -3);
    assert.equal(calls, 0);
    functionName = 'membership-offer';
    assert.equal(await client.request(ctx, 'lastVip', 'lifetime_half_2026'), 'a.b.c');
    const valid = JSON.parse(response.result);
    response = { result: { ...valid, expiresAt: String(valid.expiresAt) } };
    assert.equal(await client.request(ctx, 'lastVip', 'lifetime_half_2026'), 'a.b.c');
    await assert.rejects(client.request(ctx, 'iconYear', 'lifetime_half_2026'), e => e.code === -3);
    desktopWindow = true; supportedApi = false;
    await assert.rejects(client.request(ctx, 'lastVip', 'lifetime_half_2026'), e => e.code === -3);
    desktopWindow = false; supportedApi = true;
    assert.equal(calls, 2);
    for (const result of [
      { productId: 'iconYear', offerId: 'lifetime_half_2026', jwsRepresentation: 'a.b.c', expiresAt: now + 300000 },
      { productId: 'lastVip', offerId: 'lifetime_half_2026', jwsRepresentation: 'a.b.c', expiresAt: now - 1 },
      { ...valid, expiresAt: 'Infinity' },
      { code: 'OFFER_UNAVAILABLE' },
      null
    ]) {
      response = { result: JSON.stringify(result) };
      await assert.rejects(client.request(ctx, 'lastVip', 'lifetime_half_2026'), e => e.code === -3);
    }
    cloudError = new Error('gateway unavailable');
    await assert.rejects(client.request(ctx, 'lastVip', 'lifetime_half_2026'), e => e.code === -3);
  });
  await test('Known IDs, expiry, cancellation, refund and sandbox separation', () => {
    const p = payload();
    assert.equal(policy.active(policy.validate(p, false, now), now), true);
    p.lastSubscriptionStatus.renewalInfo.autoRenewStatusCode = '0';
    assert.equal(policy.active(policy.validate(p, false, now), now), true);
    for (const status of ['2', '3', '5']) {
      p.lastSubscriptionStatus.status = status;
      assert.equal(policy.active(policy.validate(p, false, now), now), false);
    }
    p.lastSubscriptionStatus.status = '1'; p.lastSubscriptionStatus.expiresTime = now;
    assert.equal(policy.active(policy.validate(p, false, now), now), false);
    const sandbox = payload({ environment: 'SANDBOX' });
    sandbox.lastSubscriptionStatus.lastPurchaseOrder.environment = 'SANDBOX';
    assert.throws(() => policy.validate(sandbox, false, now));
    assert.ok(policy.validate(sandbox, true, now));
    for (const id of ['iconMonths', 'iconYears', 'other']) assert.equal(policy.knownProduct(id), false);
  });
  await test('Reject cross-app, malformed and inconsistent orders', () => {
    for (const mutation of [
      p => p.packageName = 'another.app', p => p.applicationId = '',
      p => { p.applicationId = 'another-app'; p.lastSubscriptionStatus.lastPurchaseOrder.applicationId = 'another-app'; },
      p => p.lastSubscriptionStatus.expiresTime = '9999999999999',
      p => p.lastSubscriptionStatus.lastPurchaseOrder.applicationId = 'another-app',
      p => p.lastSubscriptionStatus.lastPurchaseOrder.productType = '0',
      p => p.lastSubscriptionStatus.lastPurchaseOrder.purchaseToken = '',
      p => p.lastSubscriptionStatus.lastPurchaseOrder.purchaseTime = now + 120000,
      p => p.lastSubscriptionStatus.lastPurchaseOrder.finishStatus = 'unexpected',
      p => p.lastSubscriptionStatus.status = 'unexpected'
    ]) { const p = payload(); mutation(p); assert.throws(() => policy.validate(p, false, now)); }
  });

  const keys = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  let badChain = false, badOid = false, anchorChecked = false;
  const rootCert = { root: true };
  const certificatePublicKey = { getEncoded: () => ({ data: new Uint8Array(keys.publicKey.export({ type: 'spki', format: 'der' })) }) };
  const leafCert = { getPublicKey: () => certificatePublicKey,
    getExtensionsObject: () => ({ getOidList: () => ({ data: [Buffer.from(badOid ? '1.2.3' : '1.3.6.1.4.1.2011.2.415.1.1\0')] }) }) };
  const cert = {
    EncodingFormat: { FORMAT_DER: 0, FORMAT_PEM: 1 }, ExtensionOidType: { EXTENSION_OID_TYPE_UNCRITICAL: 2 },
    createX509Cert: async blob => {
      if (blob.data.length > 100) {
        const bytes = Buffer.from(blob.data);
        const pem = bytes.toString('ascii').startsWith('-----BEGIN CERTIFICATE-----');
        assert.equal(blob.encodingFormat, pem ? 1 : 0, 'Declared encoding must match the real root certificate');
        const actual = new crypto.X509Certificate(bytes);
        assert.equal(actual.fingerprint256, 'DF:21:A3:C0:9F:79:54:57:93:05:F8:5C:64:F8:0C:AD:86:F7:98:53:EE:3A:88:7C:1D:EC:95:D2:18:DF:3A:37');
        return rootCert;
      }
      assert.equal(blob.encodingFormat, 0, 'JWS x5c certificates use DER');
      return leafCert;
    },
    createX509CertChain: certs => ({ validate: async options => {
      assert.equal(certs.length, 2); assert.equal(options.trustAnchors[0].CACert, rootCert);
      assert.equal(options.trustSystemCa, false); assert.match(options.date, /^\d{14}Z$/);
      anchorChecked = true; if (badChain) throw new Error('Untrusted chain');
    } })
  };
  const cryptoFramework = {
    createAsyKeyGenerator: algorithm => {
      assert.equal(algorithm, 'ECC256');
      return { convertKey: async (publicBlob, privateBlob) => {
        assert.equal(privateBlob, null);
        const pubKey = crypto.createPublicKey({ key: Buffer.from(publicBlob.data), type: 'spki', format: 'der' });
        assert.equal(pubKey.asymmetricKeyDetails.namedCurve, 'prime256v1');
        return { pubKey };
      } };
    },
    createVerify: algorithm => {
      assert.equal(algorithm, 'ECC256|SHA256'); let key;
      return { init: async k => {
        assert.notEqual(k, certificatePublicKey, 'Certificate-native keys cannot be passed directly to CryptoFramework');
        assert.equal(k.type, 'public'); key = k;
      }, verify: async (input, signature) => crypto.verify('sha256', input.data, key, signature.data) };
    }
  };
  const { SubscriptionVerifier: verifier } = load('service/membership/SubscriptionVerifier.ets', {
    '@kit.ArkTS': { util }, '@kit.DeviceCertificateKit': { cert }, '@kit.CryptoArchitectureKit': { cryptoFramework },
    './SubscriptionData': data
  });
  const context = { applicationInfo: { debug: false }, resourceManager: { getRawFileContent: async name =>
    new Uint8Array(fs.readFileSync(path.join(root, '../resources/rawfile', name))) } };
  function signed(p, h = {}) {
    const header = Buffer.from(JSON.stringify({ alg: 'ES256', typ: 'JWT', x5c: ['AQ==', 'Ag==', 'Aw=='], ...h })).toString('base64url');
    const body = Buffer.from(JSON.stringify(p)).toString('base64url');
    const input = header + '.' + body;
    const sig = crypto.sign('sha256', Buffer.from(input), { key: keys.privateKey, dsaEncoding: 'ieee-p1363' });
    return JSON.stringify({ jwsSubscriptionStatus: input + '.' + sig.toString('base64url') });
  }
  await test('Real ES256 signatures and integer padding convert correctly', async () => {
    for (let i = 0; i < 32; i++) assert.equal((await verifier.verify(context, signed(payload()))).packageName, 'com.huan.listenbook');
    assert.ok(anchorChecked);
    assert.throws(() => verifier.signatureDer(new Uint8Array(63)));
  });
  await test('Reject altered JWS, algorithm confusion, untrusted chain and missing IAP OID', async () => {
    const envelope = JSON.parse(signed(payload()));
    const parts = envelope.jwsSubscriptionStatus.split('.');
    parts[1] = Buffer.from(JSON.stringify(payload({ applicationId: 'tampered' }))).toString('base64url');
    await assert.rejects(verifier.verify(context, JSON.stringify({ jwsSubscriptionStatus: parts.join('.') })));
    await assert.rejects(verifier.verify(context, signed(payload(), { alg: 'none' })));
    await assert.rejects(verifier.verify(context, signed(payload(), { crit: ['unrecognized'] })));
    badChain = true; await assert.rejects(verifier.verify(context, signed(payload()))); badChain = false;
    badOid = true; await assert.rejects(verifier.verify(context, signed(payload()))); badOid = false;
  });

  function session(developerEnabled = false, displayDisk = new Map(), membershipRequired = true, featureEnabled = true, serviceGlobals = {}) {
    const developer = load('service/membership/DeveloperMembership.ets');
    developer.DeveloperMembership.ENABLED = developerEnabled;
    let defaultsReset = 0;
    const stateModule = load('model/MembershipState.ets', { './MembershipDisplaySnapshot': displayData });
    // 各场景显式设置总开关，不依赖当前发布默认值。
    stateModule.MembershipState.featureEnabled = featureEnabled;
    let displayReadGate = Promise.resolve(), displayReadError = false, displayWriteError = false;
    const displayStore = load('service/membership/MembershipDisplayStore.ets', {
      '../../model/MembershipDisplaySnapshot': displayData,
      '@kit.ArkData': { preferences: { getPreferences: async () => ({
        get: async (key, fallback) => {
          const value = displayDisk.get(key) ?? fallback;
          await displayReadGate;
          if (displayReadError) throw new Error('read failed');
          return value;
        },
        put: async (key, value) => { if (displayWriteError) throw new Error('write failed'); displayDisk.set(key, value); },
        delete: async key => { if (displayWriteError) throw new Error('write failed'); displayDisk.delete(key); },
        flush: async () => {}
      }) } }
    });
    const current = [], unfinished = [], finishes = [], icons = [];
    const lifetimeCurrent = [], lifetimeUnfinished = [], purchases = [], queries = [], productQueries = [];
    let productGate = Promise.resolve(), queryGate = Promise.resolve(), purchaseGate = Promise.resolve(), finishGate = Promise.resolve();
    let queryError = null, finishError = null, purchaseError = null, purchaseCount = 0, manageCount = 0;
    let purchaseData = null, publishPurchase = true, verificationError = null;
    let savedAccount = 'account-1', systemAccount = 'account-1', accountError = null, accountGate = Promise.resolve();
    const accountChecks = [];
    const offerRequests = [];
    let promotion = null, offerError = null;
    let emptyPurchaseList = [];
    const iap = {
      ProductType: { AUTORENEWABLE: 2, NONCONSUMABLE: 1 }, ProductStatus: { VALID: 0 }, PeriodUnit: { MONTH: 2, YEAR: 3, MINUTE: 4 },
      PurchaseQueryType: { CURRENT_ENTITLEMENT: 2, UNFINISHED: 1 }, WindowScreenMode: { FULLSCREEN: 2 },
      IAPErrorCode: { USER_CANCELED: 1001860000, PURCHASE_FINISHED: 1001860053 },
      isSandboxActivated: async () => false, queryEnvironmentStatus: async () => {},
      queryPurchases: async (_, req) => {
        queries.push({ ...req, at: now });
        await queryGate;
        if (queryError) throw queryError;
        const orders = req.productType === 1 ? (req.queryType === 2 ? lifetimeCurrent : lifetimeUnfinished) :
          (req.queryType === 2 ? current : unfinished);
        return { purchaseDataList: orders.length ? orders.map(JSON.stringify) : emptyPurchaseList };
      },
      finishPurchase: async (_, order) => {
        finishes.push(order); await finishGate; if (finishError) throw finishError;
      },
      createPurchase: async (_, req) => {
        purchaseCount++; purchases.push(req); await purchaseGate; if (purchaseError) throw purchaseError;
        if (purchaseData !== null) return { purchaseData: JSON.stringify(purchaseData) };
        if (req.productId === 'lastVip') {
          const order = lifetime(); if (publishPurchase) lifetimeCurrent.push(order);
          return { purchaseData: JSON.stringify(order) };
        }
        const subscription = payload(); subscription.lastSubscriptionStatus.lastPurchaseOrder.productId = req.productId;
        if (publishPurchase) current.push(subscription);
        return { purchaseData: JSON.stringify(subscription) };
      },
      showManagedSubscriptions: async () => { manageCount++; },
      queryProducts: async (_, ids) => {
        productQueries.push(ids);
        await productGate;
        assert.deepEqual(Array.from(ids).sort(), ['iconMonth', 'iconYear', 'lastVip']);
        return [{ id: 'lastVip', type: 1, localPrice: '¥198.00', price: '¥198.00', promotionalOffers: promotion ? [promotion] : [] },
          ...['iconMonth', 'iconYear'].map(id => ({ id, type: 2, price: '¥10.00',
            subscriptionInfo: { periodUnit: id === 'iconMonth' ? 2 : 3, periodCount: 1, groupId: 'icons' } }))];
      }
    };
    const { MembershipService } = load('service/MembershipService.ets', {
      './PreferenceService': { PreferenceService: {
        ensureReady: async () => {}, getHwAccount: async () => savedAccount ? { openID: savedAccount } : null,
        setSearchConcurrency: async count => { assert.equal(count, 3); }
      } },
      './membership/DeveloperMembership': developer,
      './membership/MembershipOfferClient': { MembershipOfferClient: { request: async (_context, productId, offerId) => {
        offerRequests.push({ productId, offerId });
        if (offerError) throw offerError;
        return 'header.payload.signature';
      } } },
      './AutoBackupService': { AutoBackupService: { instance: { resetMembershipDefaults: async () => { defaultsReset++; } } } },
      '@kit.IAPKit': { iap }, '../model/MembershipState': stateModule,
      '@kit.AccountKit': { authentication: {
        IdType: { OPEN_ID: 2 }, State: { UNLOGGED_IN: 0, AUTHORIZED: 1, UNAUTHORIZED: 2 },
        HuaweiIDProvider: class {
          async getHuaweiIDState(request) {
            accountChecks.push(request);
            const state = !systemAccount ? 0 : request.idValue === systemAccount ? 1 : 2;
            await accountGate;
            if (accountError) throw accountError;
            return { state };
          }
        }
      } },
      '@kit.PerformanceAnalysisKit': { hilog: { warn() {}, info() {} } },
      '../utils/PlatformCompat': { PlatformCompat: { wearable: false } },
      './AppIconService': { AppIconService: { instance: { supported: true, membershipRequired, select: async name => icons.push(name) } } },
      './membership/SubscriptionData': data,
      './membership/LifetimeData': lifetimeData,
      '../model/MembershipDisplaySnapshot': displayData,
      './membership/MembershipDisplayStore': displayStore,
      './membership/SubscriptionVerifier': { SubscriptionVerifier: {
        verify: async (_, p) => { if (verificationError) throw verificationError; return JSON.parse(p); },
        verifyLifetime: async (_, p) => { if (verificationError) throw verificationError; return JSON.parse(p); }
      } }
    }, serviceGlobals);
    return { defaultsReset: () => defaultsReset, service: MembershipService.instance, state: stateModule.MembershipState.current,
      offerRequests, setPromotion: value => { promotion = value; }, setOfferError: value => { offerError = value; },
      current, unfinished, finishes, icons, lifetimeCurrent, lifetimeUnfinished, purchases, queries, productQueries,
      setProductGate: gate => { productGate = gate; }, setQueryError: e => { queryError = e; },
      setQueryGate: gate => { queryGate = gate; },
      setPurchaseGate: gate => { purchaseGate = gate; }, setFinishGate: gate => { finishGate = gate; },
      setPurchaseData: value => { purchaseData = value; }, setPublishPurchase: value => { publishPurchase = value; },
      setVerificationError: value => { verificationError = value; },
      accountChecks, setSystemAccount: value => { systemAccount = value; },
      setSavedAccount: value => { savedAccount = value; }, setAccountError: value => { accountError = value; },
      setAccountGate: value => { accountGate = value; },
      displayDisk, displayStore: displayStore.MembershipDisplayStore,
      setDisplayReadGate: gate => { displayReadGate = gate; },
      failDisplayRead: () => { displayReadError = true; }, failDisplayWrite: () => { displayWriteError = true; },
      setFinishError: e => { finishError = e; }, setPurchaseError: e => { purchaseError = e; }, purchaseCount: () => purchaseCount,
      setEmptyPurchaseList: value => { emptyPurchaseList = value; }, manageCount: () => manageCount };
  }
  await test('Huawei promotion price and signature are used together; signing failure never charges regular price', async () => {
    const s = session();
    s.setPromotion({ offerId: 'lifetime_half_2026', localPrice: '¥98.00', microPrice: 98000000, paymentMode: 5 });
    await s.service.load(context);
    const plan = s.service.plans.find(p => p.id === 'lastVip');
    assert.equal(plan.price, '¥98.00');
    assert.equal(plan.regularPrice, '¥198.00');
    s.setOfferError({ code: -3 });
    await s.service.purchase(context, 'lastVip');
    assert.equal(s.purchaseCount(), 0);
    assert.equal(s.service.message, 'app.string.membership_offer_unavailable');
    s.setOfferError(null);
    await s.service.purchase(context, 'lastVip');
    assert.equal(s.purchaseCount(), 1);
    assert.equal(s.purchases[0].promotionalOfferId, 'lifetime_half_2026');
    assert.equal(s.purchases[0].jwsRepresentation, 'header.payload.signature');
  });
  await test('An expired campaign refreshes the displayed plan and stops before the cashier', async () => {
    const s = session();
    s.setPromotion({ offerId: 'lifetime_half_2026', localPrice: '¥39.00', microPrice: 39000000, paymentMode: 5 });
    await s.service.load(context);
    s.setPromotion(null);
    await s.service.purchase(context, 'lastVip');
    assert.equal(s.purchaseCount(), 0);
    assert.equal(s.offerRequests.length, 0);
    assert.equal(s.service.message, 'app.string.membership_offer_changed');
  });
  function subscriptionPage(s) {
    const source = fs.readFileSync(path.join(root, 'pages/MembershipSubscriptionPage.ets'), 'utf8').replace(/\r\n/g, '\n');
    const methods = source.slice(source.indexOf('  private isAnnualUpgrade('), source.indexOf('  @Builder\n  planCard('));
    const exports = {};
    vm.runInNewContext(ts.transpileModule(`class SubscriptionPage {
      agreed = false;
      findPlan(id) { return this.membership.plans.find(plan => plan.id === id); }
      ${methods}
    } exports.SubscriptionPage = SubscriptionPage;`, {
      compilerOptions: { target: ts.ScriptTarget.ES2020 }
    }).outputText, { exports, $r: name => name });
    const page = new exports.SubscriptionPage();
    page.state = s.state; page.membership = s.service;
    return page;
  }
  function iconPage(s, membershipRequired = true) {
    const source = fs.readFileSync(path.join(root, 'pages/AppIconPage.ets'), 'utf8');
    const methods = source.slice(source.indexOf('  private async loadCurrent()'), source.indexOf('  build()'));
    const exports = {}, selected = [], messages = [];
    vm.runInNewContext(ts.transpileModule(`class IconPage {
      loading = false; loadFailed = false; switching = false; current = ''; required = 0;
      onMembershipRequired() { this.required++; }
      getUIContext() { return ui; }
      ${methods}
    } exports.IconPage = IconPage;`, {
      compilerOptions: { target: ts.ScriptTarget.ES2020 }
    }).outputText, { exports, $r: name => name,
      ui: { getHostContext: () => context, getPromptAction: () => ({ showToast: value => messages.push(value.message) }) },
      sendableContextManager: { convertFromContext: c => c, convertToUIAbilityContext: c => c } });
    const page = new exports.IconPage();
    page.membership = s.service; page.memberState = s.state;
    page.service = { supported: true, membershipRequired, getCurrent: async () => selected.at(-1) || '',
      select: async name => { selected.push(name); return name; } };
    return { page, selected, messages };
  }
  await test('Invite icons work for nonmembers during entitlement sync without requesting IAP', async () => {
    const s = session(); s.service.busy = true;
    s.setQueryError({ code: 1001860005 });
    const h = iconPage(s, false);
    await h.page.selectIcon({ name: 'lifewhite' });
    await h.page.selectIcon({ name: 'waveclear' });
    assert.deepEqual(h.selected, ['lifewhite', 'waveclear']);
    assert.equal(h.page.required, 0); assert.equal(s.queries.length, 0);
  });
  await test('Invite icons survive inactive, failed, expired and account-change entitlement callbacks', async () => {
    const s = session(false, new Map(), false);
    await s.service.load(context);
    assert.equal(s.state.active, false);
    s.current.push(payload()); await s.service.refresh(context, true);
    assert.equal(s.state.active, true);
    s.current[0].lastSubscriptionStatus.expiresTime = now - 1;
    await s.service.refresh(context, true);
    assert.equal(s.state.active, false);
    s.setQueryError({ code: 1001860005 }); await s.service.refresh(context, true);
    s.setQueryError(null); s.setSystemAccount('account-2');
    await s.service.refresh(context, true);
    assert.equal(s.state.hasAccess, false);
    assert.ok(s.defaultsReset() > 0, 'other membership restrictions remain enforced');
    assert.deepEqual(s.icons, [], 'callbacks must never reset the invite icon');
  });
  await test('Real icon service enforces membership and supports the invite policy', async () => {
    let enabled = '';
    const state = { hasAccess: false };
    const { AppIconService } = load('service/AppIconService.ets', {
      '@kit.AbilityKit': { bundleManager: {
        getAlternateIcons: async () => [{ iconName: enabled, enabled: true }],
        setAlternateIcon: async name => { enabled = name; }
      } },
      '../utils/PlatformCompat': { PlatformCompat: { supports: () => true } },
      '../model/MembershipState': { MembershipState: { current: state, featureEnabled: true } }
    });
    assert.equal(AppIconService.instance.membershipRequired, true);
    await assert.rejects(AppIconService.instance.select('lifewhite'), /Active icon membership required/);
    assert.equal(await AppIconService.instance.select(''), '');
    state.hasAccess = true;
    assert.equal(await AppIconService.instance.select('lifewhite'), 'lifewhite');
    await assert.rejects(AppIconService.instance.select('invalid'), /Invalid alternate icon/);
    state.hasAccess = false;
    Object.defineProperty(AppIconService.instance, 'membershipRequired', { get: () => false });
    assert.equal(await AppIconService.instance.select('waveclear'), 'waveclear');
  });
  await test('Repeated icon changes reuse valid entitlement beyond the ordinary query cache', async () => {
    const s = session(); s.current.push(payload()); await s.service.refresh(context);
    now += 70000;
    const h = iconPage(s), before = s.queries.length;
    await h.page.selectIcon({ name: 'wave' }); await h.page.selectIcon({ name: 'life' });
    assert.deepEqual(h.selected, ['wave', 'life']);
    assert.equal(s.queries.length, before); assert.equal(h.page.required, 0);
  });
  await test('Icon click while membership is syncing never opens purchase', async () => {
    const s = session(); s.current.push(payload());
    const pending = s.service.refresh(context), h = iconPage(s);
    await h.page.selectIcon({ name: 'wave' });
    assert.equal(h.page.required, 0); assert.equal(h.selected.length, 0);
    await pending; await h.page.selectIcon({ name: 'wave' });
    assert.deepEqual(h.selected, ['wave']);
  });
  await test('Unknown and expired icon entitlements refresh before deciding', async () => {
    const s = session(); s.current.push(payload()); const h = iconPage(s);
    await h.page.selectIcon({ name: 'wave' });
    assert.deepEqual(h.selected, ['wave']); assert.equal(h.page.required, 0);
    s.state.expiresAt = now - 1; s.current.length = 0;
    await h.page.selectIcon({ name: 'life' });
    assert.equal(h.page.required, 1); assert.deepEqual(h.selected, ['wave']);
  });
  await test('Icon query failure shows an error instead of purchase, and retry recovers', async () => {
    const s = session(); s.setQueryError({ code: 1001860005 }); const h = iconPage(s);
    await h.page.selectIcon({ name: 'wave' });
    assert.equal(h.page.required, 0); assert.equal(h.selected.length, 0);
    assert.equal(h.messages.at(-1), 'app.string.membership_network_error');
    assert.equal(h.page.switching, false);
    s.setQueryError(null); s.current.push(payload());
    await h.page.selectIcon({ name: 'wave' }); assert.deepEqual(h.selected, ['wave']);
  });
  await test('Confirmed nonmember opens purchase, while the default icon needs no query', async () => {
    const s = session(), h = iconPage(s);
    await h.page.selectIcon({ name: 'wave' }); assert.equal(h.page.required, 1);
    const before = s.queries.length; h.page.current = 'life';
    await h.page.selectIcon({ name: '' });
    assert.deepEqual(h.selected, ['']); assert.equal(s.queries.length, before);
  });
  await test('Cold entitlement needs two queries, shares concurrent reads and caches verified results', async () => {
    const s = session(); s.current.push(payload());
    const start = now;
    await Promise.all([s.service.refresh(context), s.service.refresh(context)]);
    assert.equal(s.queries.length, 2);
    assert.ok(s.queries.every(q => q.queryType === 2));
    assert.equal(now - start, 5100);
    now += 10000;
    assert.equal(await s.service.hasCurrentEntitlement(), true);
    assert.equal(s.queries.length, 2);
    s.current[0].lastSubscriptionStatus.expiresTime = now - 1;
    s.state.expiresAt = now - 1;
    assert.equal(await s.service.hasCurrentEntitlement(), false);
    assert.equal(s.queries.length, 4);
  });
  await test('Fresh import entitlement rejects revoked access while the five-minute cache is still valid', async () => {
    const s = session(); s.current.push(payload()); await s.service.refresh(context);
    assert.equal(s.state.hasAccess, true);
    s.current.length = 0;
    assert.equal(await s.service.hasCurrentEntitlement(true), false);
    assert.equal(s.queries.length, 4, 'fresh operation queries current orders instead of using cached access');
    assert.equal(s.state.confirmedInactive, true);
  });
  await test('Membership center and settings share valid access and prices beyond sixty seconds', async () => {
    const s = session(); s.current.push(payload()); await s.service.load(context);
    now += 70000;
    await Promise.all([s.service.load(context), s.service.hasCurrentEntitlement(), s.service.load(context)]);
    assert.equal(s.queries.length, 2); assert.equal(s.productQueries.length, 1);
    assert.equal(s.state.active, true);
    now += 5 * 60000;
    await Promise.all([s.service.load(context), s.service.hasCurrentEntitlement()]);
    assert.equal(s.queries.length, 4); assert.equal(s.productQueries.length, 2);
    await s.service.load(context, true);
    assert.equal(s.queries.length, 8, 'manual restore always checks current and unfinished orders');
    assert.equal(s.productQueries.length, 3, 'manual restore refreshes prices explicitly');
  });
  await test('Nonmember cache expires and never hides a later entitlement', async () => {
    const s = session(); await s.service.refresh(context);
    s.service.background(); s.service.foreground(context);
    await s.service.refresh(context); assert.equal(s.queries.length, 2);
    now += 61000; s.current.push(payload());
    assert.equal(await s.service.hasCurrentEntitlement(), true);
    assert.equal(s.queries.length, 4);
  });
  function membershipPage(s, kind) {
    // EntryAbility provides this context before routed pages are shown.
    s.service.abilityContext = context;
    const source = fs.readFileSync(path.join(root, `pages/${kind}.ets`), 'utf8');
    let methods;
    if (kind === 'SettingsPage') {
      methods = source.slice(source.indexOf('  private async requireSearchMembership()'), source.indexOf('  private async clearCache()'))
        .replace(/@Monitor\([^\n]+\)\s*/g, '');
    } else if (kind === 'AccountPage') {
      methods = source.slice(source.indexOf('  private async requireAutoMembership()'), source.indexOf('  private autoFrequency()')) +
        source.slice(source.indexOf('  private async chooseFrequency()'), source.indexOf('  private lastBackupAt()'));
    } else {
      methods = source.slice(source.indexOf('  aboutToAppear()'), source.indexOf('  @Builder'));
    }
    const exports = {}, routes = [], messages = [], saved = [];
    const ui = { getHostContext: () => context,
      getPromptAction: () => ({ showToast: value => messages.push(value.message) }) };
    const prefs = { setSearchConcurrency: async count => {
      if (!await s.service.hasCurrentEntitlement()) throw new Error('MEMBERSHIP_REQUIRED');
      saved.push(count);
    } };
    vm.runInNewContext(ts.transpileModule(`class Page {
      alive = true; checkingSearchMembership = false; checkingMembership = false;
      searchConcurrencyLoading = false; searchConcurrencyLoadFailed = false;
      searchConcurrency = 6; searchConcurrencyDraft = '6'; searchConcurrencyCustom = false;
      agreed = true;
      getUIContext() { return ui; }
      toast(message) { ui.getPromptAction().showToast({ message }); }
      manualAvailable() { return true; }
      ${methods}
    } exports.Page = Page;`, {
      compilerOptions: { target: ts.ScriptTarget.ES2020 }
    }).outputText, { exports, ui, PreferenceService: prefs, $r: name => name,
      MembershipState: { featureEnabled: true },
      SEARCH_CONCURRENCY_OPTIONS: [3, 6, 9, 12], hilog: { warn() {} },
      sendableContextManager: { convertFromContext: c => c, convertToUIAbilityContext: c => c } });
    const page = new exports.Page();
    page.membershipService = s.service; page.membership = kind === 'MembershipSubscriptionPage' ? s.service : s.state;
    page.state = s.state; page.auth = { isLoggedIn: true };
    page.automatic = { configure: async (_, enabled, days) => saved.push({ enabled, days }) };
    page.navStack = { pushPathByName: route => routes.push(route) };
    return { page, routes, messages, saved };
  }
  await test('Settings and backup actions await one cold query and never open purchase while pending', async () => {
    const s = session(); s.current.push(payload());
    const settings = membershipPage(s, 'SettingsPage'), backup = membershipPage(s, 'AccountPage');
    const actions = [settings.page.setSearchConcurrency(9, false), backup.page.setAutomatic(true, 3)];
    assert.equal(settings.routes.length, 0); assert.equal(backup.routes.length, 0);
    await Promise.all(actions);
    assert.equal(s.queries.length, 2);
    assert.deepEqual(settings.saved, [9]); assert.equal(backup.saved.length, 1);
    assert.equal(settings.routes.length, 0); assert.equal(backup.routes.length, 0);
  });
  await test('Settings and backup failures show errors, while confirmed nonmembers open purchase', async () => {
    for (const failed of [true, false]) {
      const s = session(); if (failed) s.setQueryError({ code: 1001860005 });
      const settings = membershipPage(s, 'SettingsPage'), backup = membershipPage(s, 'AccountPage');
      await Promise.all([settings.page.setSearchConcurrency(9, false), backup.page.setAutomatic(true, 3)]);
      for (const h of [settings, backup]) {
        assert.equal(h.saved.length, 0); assert.equal(h.routes.length, failed ? 0 : 1);
        if (failed) assert.equal(h.messages.at(-1), 'app.string.membership_network_error');
      }
    }
  });
  await test('Closed settings and backup pages ignore delayed membership results', async () => {
    const s = session(); s.current.push(payload());
    const settings = membershipPage(s, 'SettingsPage'), backup = membershipPage(s, 'AccountPage');
    const actions = [settings.page.setSearchConcurrency(9, false), backup.page.setAutomatic(true, 3)];
    settings.page.alive = false; backup.page.alive = false;
    await Promise.all(actions);
    assert.equal(settings.saved.length, 0); assert.equal(backup.saved.length, 0);
    assert.equal(settings.routes.length + backup.routes.length, 0);
  });
  await test('Membership center blocks unknown access and retry recovers without restoring orders', async () => {
    const s = session(); const h = membershipPage(s, 'MembershipSubscriptionPage');
    s.setQueryError({ code: 1001860005 }); await s.service.load(context);
    assert.equal(h.page.canSelectPlan('lastVip'), false);
    assert.equal(h.page.canSelectPlan('iconMonth'), false);
    s.setQueryError(null); h.page.retryMembership(); await s.service.refresh(context);
    assert.equal(h.page.canSelectPlan('lastVip'), true);
    assert.ok(s.queries.every(q => q.queryType === 2));
  });
  await test('Slow product prices do not block entitlement, concurrent page loads share prices', async () => {
    const s = session(); s.lifetimeCurrent.push(lifetime());
    let release;
    s.setProductGate(new Promise(resolve => { release = resolve; }));
    const first = s.service.load(context), second = s.service.load(context);
    await s.service.refresh(context);
    assert.equal(s.state.active, true);
    assert.equal(s.service.busy, false);
    assert.equal(s.service.productsLoading, true);
    assert.equal(await s.service.hasCurrentEntitlement(), true);
    release(); await Promise.all([first, second]);
    assert.equal(s.productQueries.length, 1);
    assert.equal(s.service.plans.length, 3);
    assert.equal(s.service.productsLoading, false);
    await s.service.load(context);
    assert.equal(s.productQueries.length, 1);
  });
  await test('Explicit restore checks unfinished orders and a changed foreground account rechecks access', async () => {
    const s = session(); s.lifetimeCurrent.push(lifetime());
    await s.service.load(context, true);
    assert.deepEqual(s.queries.map(q => q.queryType), [2, 2, 1, 1]);
    assert.equal(s.state.active, true);
    s.lifetimeCurrent.length = 0;
    s.setSystemAccount('account-2'); s.setSavedAccount('account-2');
    s.service.background(); s.service.foreground(context);
    assert.equal(s.state.active, true, 'valid badge remains visible while checking the current account');
    assert.equal(s.state.hasAccess, false, 'display snapshot cannot authorize a new operation');
    await s.service.refresh(context);
    assert.equal(s.state.active, false, 'authoritative removal clears the old account display');
    assert.equal(s.state.revalidating, false);
    assert.equal(s.state.confirmedInactive, true);
    assert.equal(s.queries.length, 6);
  });
  await test('Warm foreground waits for the local account check without a spinner or IAP query', async () => {
    const s = session(); s.current.push(payload()); await s.service.refresh(context);
    const product = s.state.productId, color = s.state.nameColor, verifiedAt = s.state.verifiedAt;
    let release; s.setAccountGate(new Promise(resolve => { release = resolve; }));
    s.setQueryGate(new Promise(() => {}));
    now += 10000; s.service.background(); s.service.foreground(context);
    assert.equal(s.state.active, true); assert.equal(s.state.productId, product);
    assert.equal(s.state.nameColor, color); assert.equal(s.state.verifiedAt, verifiedAt);
    assert.equal(s.state.hasAccess, false); assert.equal(s.service.busy, false);
    const settings = membershipPage(s, 'SettingsPage');
    const pending = settings.page.setSearchConcurrency(9, false);
    await Promise.resolve(); assert.equal(settings.saved.length, 0); assert.equal(settings.routes.length, 0);
    release(); await pending;
    assert.equal(s.state.hasAccess, true); assert.equal(s.state.revalidating, false);
    assert.deepEqual(settings.saved, [9]); assert.equal(settings.routes.length, 0);
    assert.equal(s.queries.length, 2);
  });
  await test('Repeated icon changes and desktop returns reuse the same signed result without extending it', async () => {
    for (const id of ['iconMonth', 'iconYear', 'lastVip']) {
      const s = session();
      if (id === 'lastVip') s.lifetimeCurrent.push(lifetime());
      else {
        const subscription = payload(); subscription.lastSubscriptionStatus.lastPurchaseOrder.productId = id;
        s.current.push(subscription);
      }
      await s.service.load(context);
      const verifiedAt = s.state.verifiedAt, checks = s.accountChecks.length;
      const h = iconPage(s);
      for (const name of ['wave', 'life', 'wave']) {
        await h.page.selectIcon({ name });
        now += 10000; s.service.background(); s.service.foreground(context);
        assert.equal(s.service.busy, false);
        await Promise.all([s.service.load(context), s.service.hasCurrentEntitlement()]);
        assert.equal(s.state.hasAccess, true); assert.equal(s.state.verifiedAt, verifiedAt);
      }
      assert.deepEqual(h.selected, ['wave', 'life', 'wave']);
      assert.equal(s.queries.length, 2); assert.equal(s.productQueries.length, 1);
      assert.equal(s.accountChecks.length, checks + 3);
    }
  });
  await test('Foreground never revives an expired, stale or clock-rollback display snapshot', async () => {
    for (const reason of ['subscription', 'stale', 'clock']) {
      const s = session(); s.current.push(payload()); await s.service.refresh(context);
      if (reason === 'subscription') s.state.expiresAt = now - 1;
      else if (reason === 'stale') now += 5 * 60000;
      else now = s.state.verifiedAt - 1000;
      s.service.background(); s.service.foreground(context);
      assert.equal(s.state.active, false);
      assert.equal(s.state.hasAccess, false);
      if (reason === 'clock') now += 10000;
      await s.service.refresh(context);
      assert.equal(s.queries.length, 4, 'expired and clock-rollback results must query IAP');
    }
  });
  await test('Failed foreground validation clears the snapshot without extending its lifetime', async () => {
    const s = session(); s.current.push(payload()); await s.service.refresh(context);
    s.setAccountError({ code: 12300001 });
    s.setQueryError({ code: 1001860005 }); s.service.background(); s.service.foreground(context);
    assert.equal(s.state.active, true); assert.equal(s.state.hasAccess, false);
    await s.service.refresh(context);
    assert.equal(s.state.active, false); assert.equal(s.state.hasAccess, false);
    assert.equal(s.state.revalidating, false); assert.equal(s.state.confirmedInactive, false);
    assert.equal(s.service.message, 'app.string.membership_network_error');
  });
  await test('Missing account binding cannot attach an old entitlement to a newly signed-in account', async () => {
    const s = session(); s.setSavedAccount(''); s.current.push(payload()); await s.service.refresh(context);
    s.setSystemAccount('account-2'); s.setSavedAccount('account-2'); s.current.length = 0;
    s.service.background(); s.service.foreground(context);
    assert.equal(s.state.hasAccess, false);
    await s.service.refresh(context);
    assert.equal(s.queries.length, 4); assert.equal(s.state.hasAccess, false);
    assert.equal(s.state.confirmedInactive, true);
  });
  await test('A local account check failure falls back to IAP without treating login as purchased access', async () => {
    const s = session(); s.current.push(payload()); await s.service.refresh(context);
    s.setAccountError({ code: 12300001 });
    s.service.background(); s.service.foreground(context); await s.service.refresh(context);
    assert.equal(s.queries.length, 4); assert.equal(s.state.hasAccess, true);
    s.setAccountError(null); s.current.length = 0;
    s.service.background(); s.service.foreground(context); await s.service.refresh(context);
    assert.equal(s.queries.length, 6); assert.equal(s.state.hasAccess, false);
  });
  await test('A changed system account during IAP verification cannot bind or grant the older response', async () => {
    const s = session(); s.current.push(payload());
    let release; s.setQueryGate(new Promise(resolve => { release = resolve; }));
    const pending = s.service.refresh(context);
    for (let i = 0; i < 80 && s.queries.length === 0; i++) await Promise.resolve();
    assert.equal(s.queries.length, 1);
    s.setSystemAccount('account-2'); s.setSavedAccount('account-2');
    release(); await pending;
    assert.equal(s.state.hasAccess, false); assert.equal(s.state.displayActive, false);
    assert.equal(s.service.verifiedAccountId, '');
  });
  await test('A late local account result cannot release access after a newer desktop return', async () => {
    const s = session(); s.current.push(payload()); await s.service.refresh(context);
    let releaseAccount, releaseQuery;
    s.setAccountGate(new Promise(resolve => { releaseAccount = resolve; }));
    s.setQueryGate(new Promise(resolve => { releaseQuery = resolve; }));
    s.service.background(); s.service.foreground(context);
    s.setSystemAccount('account-2'); s.setSavedAccount('account-2'); s.current.length = 0;
    s.service.background(); s.service.foreground(context);
    releaseAccount();
    for (let i = 0; i < 100 && s.queries.length === 2; i++) await Promise.resolve();
    assert.equal(s.queries.length, 3); assert.equal(s.state.hasAccess, false);
    releaseQuery(); await s.service.refresh(context);
    assert.equal(s.queries.length, 4); assert.equal(s.state.confirmedInactive, true);
  });
  await test('Manual restore during a local account check still queries current and unfinished orders once', async () => {
    const s = session(); s.current.push(payload()); await s.service.load(context);
    let release; s.setAccountGate(new Promise(resolve => { release = resolve; }));
    s.service.background(); s.service.foreground(context);
    const first = s.service.load(context, true), second = s.service.load(context, true);
    release(); await Promise.all([first, second]);
    assert.deepEqual(s.queries.slice(2).map(q => q.queryType), [2, 2, 1, 1]);
    assert.equal(s.state.hasAccess, true); assert.equal(s.service.busy, false);
  });
  async function settleDisplay() { for (let i = 0; i < 20; i++) await Promise.resolve(); }
  await test('A new process displays persisted membership before IAP completes but cannot use or buy membership', async () => {
    const first = session(); first.current.push(payload()); await first.service.refresh(context);
    const saved = JSON.parse(first.displayDisk.get('snapshot'));
    assert.deepEqual(Object.keys(saved).sort(), ['autoRenew', 'expiresAt', 'productId', 'verifiedAt']);
    now += 10 * 60000;
    const cold = session(false, first.displayDisk); cold.current.push(payload());
    let release; cold.setQueryGate(new Promise(resolve => { release = resolve; }));
    cold.service.foreground(context); await settleDisplay();
    assert.equal(cold.state.displayActive, true); assert.equal(cold.state.displayProductId, 'iconMonth');
    assert.equal(cold.state.nameColor, 'app.color.membership_name_month');
    assert.equal(cold.state.active, false); assert.equal(cold.state.hasAccess, false);
    assert.equal(cold.state.productId, ''); assert.equal(cold.state.verifiedAt, 0);
    const center = membershipPage(cold, 'MembershipSubscriptionPage');
    assert.equal(center.page.canSelectPlan('lastVip'), false);
    release(); await cold.service.refresh(context);
    assert.equal(cold.state.hasAccess, true); assert.equal(cold.state.displayActive, true);
    assert.ok(JSON.parse(cold.displayDisk.get('snapshot')).verifiedAt > saved.verifiedAt);
  });
  await test('Cold authoritative removal or query failure clears both display and disk cache', async () => {
    for (const failed of [false, true]) {
      const first = session(); first.lifetimeCurrent.push(lifetime()); await first.service.refresh(context);
      const cold = session(false, first.displayDisk);
      let release; cold.setQueryGate(new Promise(resolve => { release = resolve; }));
      if (failed) cold.setQueryError({ code: 1001860005 });
      cold.service.foreground(context); await settleDisplay();
      assert.equal(cold.state.displayLifetime, true); assert.equal(cold.state.hasAccess, false);
      release(); await cold.service.refresh(context);
      assert.equal(cold.state.displayActive, false); assert.equal(cold.state.hasAccess, false);
      assert.equal(cold.displayDisk.has('snapshot'), false);
      assert.equal(cold.state.confirmedInactive, !failed);
    }
  });
  await test('Corrupt, expired, oversized and future display records never restore a badge or access', async () => {
    const valid = { productId: 'iconYear', autoRenew: true, expiresAt: now + 86400000, verifiedAt: now - 1000 };
    for (const raw of ['{', 'null', 'x'.repeat(513), JSON.stringify({ ...valid, productId: 'other' }),
      JSON.stringify({ ...valid, expiresAt: now }), JSON.stringify({ ...valid, verifiedAt: now + 1000 }),
      JSON.stringify({ ...valid, verifiedAt: now - 86400000 }), JSON.stringify({ ...valid, autoRenew: 'true' })]) {
      const cold = session(false, new Map([['snapshot', raw]]));
      await cold.service.restoreDisplay(context);
      assert.equal(cold.state.displayActive, false); assert.equal(cold.state.hasAccess, false);
    }
    const cold = session(false, new Map([['snapshot', JSON.stringify(valid)]]));
    await cold.service.restoreDisplay(context); assert.equal(cold.state.displayActive, true);
    now += 86400000; assert.equal(cold.state.displayActive, false); assert.equal(cold.state.hasAccess, false);
  });
  await test('Late disk reads cannot resurrect a badge after a newer account entitlement result', async () => {
    const first = session(); first.lifetimeCurrent.push(lifetime()); await first.service.refresh(context);
    const cold = session(false, first.displayDisk);
    let release; cold.setDisplayReadGate(new Promise(resolve => { release = resolve; }));
    cold.service.foreground(context); await cold.service.refresh(context);
    assert.equal(cold.state.confirmedInactive, true); assert.equal(cold.displayDisk.has('snapshot'), false);
    release(); await settleDisplay(); assert.equal(cold.state.displayActive, false);
  });
  await test('Display storage failure does not block real entitlement and developer exemption is not persisted', async () => {
    const s = session(); s.failDisplayRead(); s.failDisplayWrite(); s.current.push(payload());
    await s.service.refresh(context); assert.equal(s.state.hasAccess, true); assert.equal(s.state.displayActive, true);
    const dev = session(true); await dev.service.refresh({ ...context, applicationInfo: { debug: true } });
    assert.equal(dev.state.hasAccess, true); assert.equal(dev.displayDisk.size, 0);
  });
  await test('Missing or null purchase lists allow first purchase without granting unverified membership', async () => {
    for (const empty of [undefined, null]) {
      const s = session(); s.setEmptyPurchaseList(empty);
      await s.service.load(context);
      assert.equal(s.service.message, 'app.string.membership_inactive');
      assert.equal(s.state.active, false);
      assert.equal(s.finishes.length, 0);
      s.setPurchaseError({ code: 1001860000 });
      await s.service.purchase(context, 'lastVip');
      assert.equal(s.purchaseCount(), 1);
      assert.equal(s.state.active, false);
    }
  });
  await test('Malformed purchase lists still fail closed and block buying', async () => {
    const s = session(); s.setEmptyPurchaseList({});
    await s.service.load(context);
    assert.equal(s.service.message, 'app.string.membership_verification_failed');
    await s.service.purchase(context, 'lastVip');
    assert.equal(s.purchaseCount(), 0);
    assert.equal(s.state.active, false);
  });
  await test('Restore grants once, finishes only after entitlement, and retries acknowledgement', async () => {
    const s = session(); s.current.push(payload()); s.unfinished.push(clone(s.current[0]));
    s.setFinishError({ code: 1001860005 });
    await s.service.refresh(context, true);
    assert.equal(s.state.active, true); assert.equal(s.service.confirmationPending, true);
    const expiry = s.state.expiresAt;
    s.setFinishError(null); s.finishes.length = 0;
    await s.service.refresh(context, true);
    assert.equal(s.state.expiresAt, expiry); assert.equal(s.service.confirmationPending, false);
    assert.equal(s.finishes.length, 1);
    s.current[0].lastSubscriptionStatus.lastPurchaseOrder.finishStatus = '1'; s.unfinished.length = 0; s.finishes.length = 0;
    await s.service.refresh(context, true); assert.equal(s.finishes.length, 0);
  });
  await test('Empty/refunded authoritative query revokes; stale unfinished order cannot resurrect', async () => {
    const s = session(); s.unfinished.push(payload());
    await s.service.refresh(context, true);
    assert.equal(s.state.active, false); assert.equal(s.finishes.length, 0); assert.equal(s.icons.at(-1), '');
    s.current.push(payload()); await s.service.refresh(context, true); assert.equal(s.state.active, true);
    s.current[0].lastSubscriptionStatus.status = '5'; await s.service.refresh(context, true);
    assert.equal(s.state.active, false);
  });
  await test('Offline resets restricted settings and blocks unverified purchase', async () => {
    const s = session(); s.current.push(payload()); await s.service.load(context);
    assert.equal(s.state.active, true); const resets = s.icons.length;
    s.setQueryError({ code: 1001860005 }); await s.service.refresh(context, true);
    assert.equal(s.state.active, false); assert.equal(s.icons.length, resets + 1);
    await s.service.purchase(context, 'iconMonth'); assert.equal(s.purchaseCount(), 0);
  });
  await test('Cancellation does not grant or confirm a purchase', async () => {
    const s = session(); await s.service.load(context); s.setPurchaseError({ code: 1001860000 });
    await s.service.purchase(context, 'iconYear');
    assert.equal(s.purchaseCount(), 1); assert.equal(s.state.active, false); assert.equal(s.finishes.length, 0);
    assert.equal(s.service.message, 'app.string.membership_cancelled');
  });
  await test('Lifetime policy rejects wrong app/type, future, sandbox and revoked orders', () => {
    const p = lifetimeData.LifetimePolicy;
    assert.ok(p.validate(lifetime(), false, now));
    for (const patch of [{ applicationId: 'other' }, { productType: '2' }, { purchaseToken: '' },
      { purchaseTime: now + 120000 }, { signedTime: 0 }, { price: -1 }, { currency: '' }, { environment: 'SANDBOX' }]) {
      assert.throws(() => p.validate(lifetime(patch), false, now));
    }
    assert.equal(p.validate(lifetime({ purchaseOrderRevocationReasonCode: '0' }), false, now), undefined);
    assert.equal(p.validate(lifetime({ revocationTime: now }), false, now), undefined);
    assert.equal(p.validate(lifetime({ productId: 'other' }), false, now), undefined);
  });
  await test('Lifetime JWS uses the same real signature verification and rejects tampering', async () => {
    const jws = JSON.parse(signed(lifetime())).jwsSubscriptionStatus;
    const order = await verifier.verifyLifetime(context, JSON.stringify({ jwsPurchaseOrder: jws }));
    assert.equal(order.productId, 'lastVip');
    const parts = jws.split('.');
    parts[1] = Buffer.from(JSON.stringify(lifetime({ applicationId: 'tampered' }))).toString('base64url');
    await assert.rejects(verifier.verifyLifetime(context, JSON.stringify({ jwsPurchaseOrder: parts.join('.') })));
    await assert.rejects(verifier.verifyLifetime(context, signed(lifetime())));
  });
  await test('Lifetime restores, outranks subscription, acknowledges once and cannot resurrect from unfinished history', async () => {
    const s = session(); s.current.push(payload()); s.lifetimeCurrent.push(lifetime());
    s.lifetimeUnfinished.push(clone(s.lifetimeCurrent[0]));
    s.setFinishError({ code: 1001860005 });
    await s.service.refresh(context, true);
    assert.equal(s.state.active, true); assert.equal(s.state.lifetime, true); assert.equal(s.state.expiresAt, 0);
    assert.equal(s.service.confirmationPending, true);
    assert.equal(s.state.nameColor, 'app.color.membership_name_lifetime');
    s.setFinishError(null); s.finishes.length = 0;
    await s.service.refresh(context, true);
    assert.equal(s.finishes.filter(v => v.productType === 1).length, 1);
    s.lifetimeCurrent.length = 0;
    await s.service.refresh(context, true);
    assert.equal(s.state.lifetime, false); assert.equal(s.state.active, true);
    s.current.length = 0; await s.service.refresh(context, true);
    assert.equal(s.state.active, false); assert.equal(s.state.nameColor, 'sys.color.font_primary');
  });
  await test('Monthly member can buy lifetime once; purchases and acknowledgements use NONCONSUMABLE', async () => {
    const s = session(); s.current.push(payload()); await s.service.load(context);
    assert.equal(s.service.plans.length, 3);
    assert.equal(s.state.nameColor, 'app.color.membership_name_month');
    await s.service.purchase(context, 'lastVip');
    assert.equal(s.purchases[0].productType, 1); assert.equal(s.state.lifetime, true);
    assert.equal(await s.service.hasCurrentEntitlement(), true);
    await s.service.purchase(context, 'lastVip'); await s.service.purchase(context, 'iconYear');
    assert.equal(s.purchaseCount(), 1);
    s.lifetimeCurrent[0].purchaseOrderRevocationReasonCode = '0';
    await s.service.refresh(context, true);
    assert.equal(s.state.lifetime, false);
  });
  await test('Annual upgrade UI requires consent and a matching group; pending changes open management', async () => {
    const s = session(); s.current.push(payload()); await s.service.load(context);
    const page = subscriptionPage(s);
    assert.equal(page.planAction('iconYear'), 'app.string.membership_upgrade_year');
    assert.equal(page.shouldManagePlan('iconYear'), false);
    assert.equal(page.canSelectPlan('iconYear'), false);
    page.agreed = true;
    assert.equal(page.canSelectPlan('iconYear'), true);
    assert.equal(page.shouldManagePlan('iconMonth'), true);
    s.state.pendingProductId = 'iconYear';
    assert.equal(page.planAction('iconYear'), 'app.string.membership_manage');
    assert.equal(page.shouldManagePlan('iconYear'), true);
    s.state.pendingProductId = ''; s.state.subscriptionGroupId = 'other';
    assert.equal(page.canSelectPlan('iconYear'), false);
    s.state.productId = 'lastVip';
    assert.equal(page.canSelectPlan('iconYear'), false);
  });
  await test('Monthly member upgrades through annual cashier and applies only verified annual expiry', async () => {
    const s = session(); s.current.push(payload()); await s.service.load(context); await s.service.confirmationTask;
    const annual = payload(); annual.lastSubscriptionStatus.lastPurchaseOrder.productId = 'iconYear';
    annual.lastSubscriptionStatus.lastPurchaseOrder.purchaseToken = 'annual-token';
    annual.lastSubscriptionStatus.lastPurchaseOrder.purchaseOrderId = 'annual-order';
    annual.lastSubscriptionStatus.expiresTime = now + 365 * 86400000;
    s.setPurchaseData(annual);
    await s.service.purchase(context, 'iconYear'); await s.service.confirmationTask;
    assert.equal(s.purchaseCount(), 1); assert.equal(s.manageCount(), 0);
    assert.equal(s.purchases[0].productType, 2); assert.equal(s.purchases[0].productId, 'iconYear');
    assert.equal(s.state.productId, 'iconYear'); assert.equal(s.state.subscriptionGroupId, 'icons');
    assert.equal(s.state.expiresAt, annual.lastSubscriptionStatus.expiresTime);
    assert.equal(s.state.pendingProductId, ''); assert.equal(s.state.hasAccess, true);
    assert.equal(s.finishes.at(-1).purchaseOrderId, 'annual-order');
  });
  await test('Deferred annual upgrade preserves monthly entitlement and prevents repeat annual purchase', async () => {
    const s = session(); s.current.push(payload()); await s.service.load(context); await s.service.confirmationTask;
    const deferred = clone(s.current[0]);
    deferred.lastSubscriptionStatus.renewalInfo.nextRenewPeriodProductId = 'iconYear';
    s.setPurchaseData(deferred);
    await s.service.purchase(context, 'iconYear'); await s.service.confirmationTask;
    assert.equal(s.purchaseCount(), 1); assert.equal(s.state.productId, 'iconMonth');
    assert.equal(s.state.pendingProductId, 'iconYear'); assert.equal(s.state.hasAccess, true);
    assert.equal(s.state.expiresAt, deferred.lastSubscriptionStatus.expiresTime);
    assert.equal(s.finishes.length, 1, 'deferred switch does not fabricate or acknowledge an annual order');
    s.current[0] = deferred;
    await s.service.purchase(context, 'iconYear');
    assert.equal(s.purchaseCount(), 1); assert.equal(s.manageCount(), 1);
    const cold = session(); cold.current.push(deferred); await cold.service.load(context);
    assert.equal(cold.state.pendingProductId, 'iconYear'); assert.equal(cold.state.productId, 'iconMonth');
    cold.state.clearEntitlement(); assert.equal(cold.state.pendingProductId, '');
  });
  await test('Unrelated groups and missing current product metadata cannot create a second subscription', async () => {
    for (const mode of ['receipt-group', 'product-group', 'missing-month']) {
      const s = session(); s.current.push(payload());
      if (mode === 'receipt-group') s.current[0].subGroupId = 'other';
      await s.service.load(context);
      if (mode === 'product-group') s.service.plans.find(p => p.id === 'iconYear').groupId = 'other';
      if (mode === 'missing-month') s.service.plans = s.service.plans.filter(p => p.id !== 'iconMonth');
      await s.service.purchase(context, 'iconYear');
      assert.equal(s.purchaseCount(), 0); assert.equal(s.state.productId, 'iconMonth');
      assert.equal(s.service.message, 'app.string.membership_upgrade_unavailable');
    }
  });
  await test('Cancelled upgrade preserves monthly access and cancelled or unknown renewal plans are not pending', async () => {
    const s = session(); s.current.push(payload()); await s.service.load(context); await s.service.confirmationTask;
    const expiry = s.state.expiresAt;
    s.setPurchaseError({ code: 1001860000 });
    await s.service.purchase(context, 'iconYear');
    assert.equal(s.purchaseCount(), 1); assert.equal(s.state.productId, 'iconMonth');
    assert.equal(s.state.expiresAt, expiry); assert.equal(s.state.hasAccess, true);
    assert.equal(s.state.pendingProductId, '');
    const status = payload().lastSubscriptionStatus;
    status.renewalInfo = { autoRenewStatusCode: '0', nextRenewPeriodProductId: 'iconYear' };
    assert.equal(policy.pendingProduct(status), '');
    status.renewalInfo = { autoRenewStatusCode: '1', nextRenewPeriodProductId: 'unknown' };
    assert.equal(policy.pendingProduct(status), '');
  });
  await test('Upgrade rejects wrong groups and monthly receipts without a verified annual renewal plan', async () => {
    for (const mode of ['no-change', 'renewal-off', 'wrong-group', 'wrong-product']) {
      const s = session(); s.current.push(payload()); await s.service.load(context); await s.service.confirmationTask;
      const response = clone(s.current[0]);
      if (mode === 'renewal-off') response.lastSubscriptionStatus.renewalInfo =
        { autoRenewStatusCode: '0', nextRenewPeriodProductId: 'iconYear' };
      if (mode === 'wrong-group') {
        response.subGroupId = 'other'; response.lastSubscriptionStatus.lastPurchaseOrder.productId = 'iconYear';
      }
      if (mode === 'wrong-product') response.lastSubscriptionStatus.lastPurchaseOrder.productId = 'unknown';
      s.setPurchaseData(response);
      await s.service.purchase(context, 'iconYear'); await s.service.confirmationTask;
      assert.equal(s.state.productId, 'iconMonth'); assert.equal(s.state.pendingProductId, '');
      assert.equal(s.finishes.length, 1, 'invalid switch receipts must not acknowledge a new purchase');
    }
  });
  await test('Upgrade waits for original delivery and stops when acknowledgement fails', async () => {
    const s = session(); s.current.push(payload()); s.setFinishError({ code: 1001860005 });
    await s.service.load(context); await s.service.confirmationTask;
    await s.service.purchase(context, 'iconYear');
    assert.equal(s.purchaseCount(), 0); assert.equal(s.state.productId, 'iconMonth');
    assert.equal(s.service.message, 'app.string.membership_confirmation_pending');
    s.setFinishError(null);
    await s.service.purchase(context, 'iconYear'); await s.service.confirmationTask;
    assert.equal(s.purchaseCount(), 1); assert.equal(s.state.productId, 'iconYear');
  });
  await test('Lifetime purchase cancellation grants nothing; yearly name color follows verified state', async () => {
    const s = session(); await s.service.load(context); s.setPurchaseError({ code: 1001860000 });
    await s.service.purchase(context, 'lastVip');
    assert.equal(s.purchaseCount(), 1); assert.equal(s.state.active, false); assert.equal(s.finishes.length, 0);
    const p = payload(); p.lastSubscriptionStatus.lastPurchaseOrder.productId = 'iconYear'; s.current.push(p);
    await s.service.refresh(context, true);
    assert.equal(s.state.nameColor, 'app.color.membership_name_year');
    s.setQueryError({ code: 1001860005 }); await s.service.refresh(context, true);
    assert.equal(s.state.nameColor, 'sys.color.font_primary');
  });
  await test('Verified purchase becomes usable immediately despite delayed queries and acknowledgement', async () => {
    for (const id of ['lastVip', 'iconMonth', 'iconYear']) {
      const s = session(); await s.service.load(context);
      s.setPublishPurchase(false);
      let release; s.setFinishGate(new Promise(resolve => { release = resolve; }));
      const before = s.queries.length, started = now;
      await s.service.purchase(context, id);
      assert.equal(s.state.productId, id); assert.equal(s.state.hasAccess, true);
      assert.equal(s.service.busy, false); assert.equal(now, started, 'no query throttle on the success path');
      assert.equal(s.queries.length, before, 'recent preflight and verified receipt avoid six extra queries');
      assert.equal(await s.service.hasCurrentEntitlement(), true);
      await s.service.load(context); assert.equal(s.queries.length, before);
      release(); await s.service.confirmationTask;
      assert.equal(s.finishes.length, 1);
      await s.service.displayWriteTask;
      assert.equal(JSON.parse(s.displayDisk.get('snapshot')).productId, id);
      await s.service.refresh(context, true);
      assert.equal(s.state.hasAccess, false, 'later authoritative revocation still wins');
    }
  });
  await test('Slow foreground acknowledgement releases access and page loading after verification', async () => {
    const s = session(); s.current.push(payload());
    let release; s.setFinishGate(new Promise(resolve => { release = resolve; }));
    s.service.foreground(context); await s.service.refresh(context);
    assert.equal(s.state.hasAccess, true); assert.equal(s.service.busy, false);
    const h = iconPage(s); await h.page.selectIcon({ name: 'wave' });
    assert.deepEqual(h.selected, ['wave']); assert.equal(s.finishes.length, 1);
    release(); await s.service.confirmationTask;
    await s.service.refresh(context, true); await s.service.confirmationTask;
    assert.equal(s.finishes.length, 1, 'stale finishStatus cannot repeat an acknowledged order');
  });
  await test('A known lifetime member needs one current query and retains cached prices across foreground', async () => {
    const s = session(); s.lifetimeCurrent.push(lifetime()); await s.service.load(context);
    await s.service.confirmationTask;
    const before = s.queries.length; now += 10000;
    s.service.background(); s.service.foreground(context); await s.service.load(context);
    assert.equal(s.queries.length, before);
    await s.service.refresh(context, true);
    assert.equal(s.queries.length, before + 1); assert.equal(s.queries.at(-1).productType, 1);
    assert.equal(s.state.hasAccess, true); assert.equal(s.productQueries.length, 1);
    s.lifetimeCurrent.length = 0; s.current.push(payload());
    await s.service.refresh(context, true);
    assert.equal(s.state.productId, 'iconMonth'); assert.equal(s.state.hasAccess, true);
    assert.deepEqual(s.queries.slice(-2).map(q => q.productType), [1, 2]);
  });
  await test('An old preflight refreshes once and concurrent purchase clicks open one cashier', async () => {
    const s = session(); await s.service.load(context); now += 31000;
    let release; s.setPurchaseGate(new Promise(resolve => { release = resolve; }));
    const first = s.service.purchase(context, 'lastVip');
    await s.service.purchase(context, 'lastVip');
    for (let i = 0; i < 80 && s.purchaseCount() === 0; i++) await Promise.resolve();
    assert.equal(s.purchaseCount(), 1); assert.equal(s.queries.length, 4);
    s.service.background(); s.service.foreground(context);
    release(); await first; await s.service.confirmationTask;
    assert.equal(s.state.hasAccess, true); assert.equal(s.queries.length, 4);
  });
  await test('Cashier stays exclusive beyond three minutes and delivers its eventual success', async () => {
    const timers = new Map(); let timerId = 0;
    const s = session(false, new Map(), true, true, {
      setTimeout(fn, delay) {
        if (fn.length > 0 && delay <= 5100) { now += delay; queueMicrotask(fn); return ++timerId; }
        timers.set(++timerId, { fn, due: now + delay }); return timerId;
      },
      clearTimeout(id) { timers.delete(id); }
    });
    await s.service.load(context);
    let release; s.setPurchaseGate(new Promise(resolve => { release = resolve; }));
    const buying = s.service.purchase(context, 'lastVip');
    for (let i = 0; i < 80 && s.purchaseCount() === 0; i++) await Promise.resolve();
    assert.equal(s.purchaseCount(), 1);
    now += 181000;
    for (const [id, timer] of Array.from(timers)) {
      if (timer.due <= now) { timers.delete(id); timer.fn(); }
    }
    for (let i = 0; i < 80; i++) await Promise.resolve();
    assert.equal(s.service.busy, true);
    await s.service.purchase(context, 'lastVip');
    assert.equal(s.purchaseCount(), 1);
    release(); await buying; await s.service.confirmationTask;
    assert.equal(s.state.hasAccess, true); assert.equal(s.finishes.length, 1);
    assert.equal(s.service.busy, false);
  });
  await test('Optional subscription finishStatus does not invalidate current entitlement', async () => {
    const s = session(); const p = payload();
    delete p.lastSubscriptionStatus.lastPurchaseOrder.finishStatus;
    s.current.push(p);
    await s.service.load(context); await s.service.confirmationTask;
    assert.equal(s.state.hasAccess, true); assert.equal(s.finishes.length, 1);
  });
  await test('Rejected purchase signatures, mismatched products and revoked receipts grant nothing', async () => {
    for (const mode of ['signature', 'revoked', 'wrong-product', 'expired']) {
      const s = session(); await s.service.load(context); s.setPublishPurchase(false);
      let id = 'lastVip';
      if (mode === 'signature') s.setVerificationError(new Error('Invalid signature'));
      if (mode === 'revoked') s.setPurchaseData(lifetime({ revocationTime: now }));
      if (mode === 'wrong-product') { id = 'iconYear'; s.setPurchaseData(payload()); }
      if (mode === 'expired') {
        id = 'iconMonth'; const expired = payload(); expired.lastSubscriptionStatus.status = '2';
        s.setPurchaseData(expired);
      }
      await s.service.purchase(context, id); await s.service.confirmationTask;
      assert.equal(s.state.hasAccess, false); assert.equal(s.finishes.length, 0);
      assert.equal(s.displayDisk.has('snapshot'), false);
    }
  });
  await test('Late cashier foreground consumes the verified receipt once, later foreground still checks the account', async () => {
    const s = session(); await s.service.load(context); s.setPublishPurchase(false);
    let release; s.setPurchaseGate(new Promise(resolve => { release = resolve; }));
    const buying = s.service.purchase(context, 'lastVip');
    for (let i = 0; i < 80 && s.purchaseCount() === 0; i++) await Promise.resolve();
    assert.equal(s.purchaseCount(), 1);
    s.service.background(); release(); await buying; await s.service.confirmationTask;
    const before = s.queries.length;
    s.service.foreground(context); await s.service.load(context);
    assert.equal(s.queries.length, before, 'the cashier return cannot erase the new verified receipt');
    assert.equal(s.state.hasAccess, true); assert.equal(s.service.busy, false);
    s.service.background(); s.service.foreground(context); await s.service.refresh(context);
    assert.equal(s.state.hasAccess, true); assert.equal(s.queries.length, before);
    s.setSystemAccount('account-2'); s.setSavedAccount('account-2');
    s.service.background(); s.service.foreground(context); await s.service.refresh(context);
    assert.equal(s.state.hasAccess, false); assert.equal(s.queries.length, before + 2);
  });
  await test('A late acknowledgement failure cannot change a newer revoked entitlement', async () => {
    const s = session(); await s.service.load(context);
    let release; s.setFinishGate(new Promise(resolve => { release = resolve; }));
    s.setFinishError({ code: 1001860005 });
    await s.service.purchase(context, 'lastVip');
    s.lifetimeCurrent.length = 0; await s.service.refresh(context, true);
    assert.equal(s.state.hasAccess, false); assert.equal(s.state.confirmedInactive, true);
    release(); await s.service.confirmationTask;
    assert.equal(s.service.confirmationPending, false); assert.equal(s.state.displayActive, false);
  });
  await test('Concurrent restore requests share current and unfinished queries without locking valid access', async () => {
    const s = session(); s.current.push(payload());
    let release; s.setQueryGate(new Promise(resolve => { release = resolve; }));
    const ordinary = s.service.refresh(context);
    const first = s.service.load(context, true), second = s.service.load(context, true);
    release(); await Promise.all([ordinary, first, second]);
    assert.deepEqual(s.queries.map(q => q.queryType), [2, 2, 1, 1]);
    assert.equal(s.finishes.length, 1); assert.equal(s.state.hasAccess, true);
    for (let i = 1; i < s.queries.length; i++) assert.ok(s.queries[i].at - s.queries[i - 1].at >= 5100);
  });
  await test('Failed purchase acknowledgement retains access and retries once without a spinner', async () => {
    const s = session(); await s.service.load(context); s.setFinishError({ code: 1001860005 });
    await s.service.purchase(context, 'lastVip'); await s.service.confirmationTask;
    assert.equal(s.state.hasAccess, true); assert.equal(s.service.busy, false);
    assert.equal(s.service.confirmationPending, true);
    s.setFinishError(null); await s.service.refresh(context, true); await s.service.confirmationTask;
    assert.equal(s.service.confirmationPending, false); assert.equal(s.finishes.length, 2);
  });
  await test('Missing or unavailable membership resets defaults', async () => {
    const s = session();
    await s.service.refresh(context, true);
    assert.equal(s.state.confirmedInactive, true);
    assert.equal(s.defaultsReset(), 1);
    assert.equal(s.icons.at(-1), '');
    s.setQueryError({ code: 1001860005 });
    await s.service.refresh(context, true);
    assert.equal(s.state.confirmedInactive, false);
    assert.equal(s.defaultsReset(), 2);
  });
  await test('Developer exemption requires explicit opt-in AND a debug application', async () => {
    const production = session(true);
    await production.service.refresh(context, true);
    assert.equal(production.state.hasAccess, false);
    assert.equal(production.state.developerAccess, false);
    const debugContext = { ...context, applicationInfo: { debug: true } };
    const regularDebug = session(false);
    await regularDebug.service.refresh(debugContext, true);
    assert.equal(regularDebug.state.hasAccess, false);
    const developer = session(true);
    await developer.service.refresh(debugContext, true);
    assert.equal(await developer.service.hasCurrentEntitlement(), true);
    assert.equal(developer.state.active, false, 'do not fabricate purchased membership');
    assert.equal(developer.defaultsReset(), 0);
    assert.equal(developer.icons.length, 0);
  });
  await test('Hidden membership grants access offline without IAP, badges or resetting settings', async () => {
    const disk = new Map();
    const s = session(false, disk, false, false);
    s.setSavedAccount(''); s.setSystemAccount(''); s.setQueryError(new Error('offline'));
    assert.equal(s.state.hasAccess, true);
    assert.equal(s.state.active, false, 'free access must not fabricate a purchase');
    assert.equal(s.service.supported, false);
    s.service.foreground(context);
    await s.service.load(context, true);
    await s.service.refresh(context, true, true);
    await s.service.purchase(context, 'lastVip');
    assert.equal(await s.service.manage(context), false);
    assert.equal(await s.service.hasCurrentEntitlement(), true);
    s.state.productId = 'lastVip'; s.state.verifiedAt = now;
    assert.equal(s.state.displayActive, false);
    assert.equal(s.state.nameColor, 'sys.color.font_primary');
    s.state.revalidating = true; s.state.confirmedInactive = true; s.state.clear();
    assert.equal(s.state.hasAccess, true);
    assert.equal(s.queries.length, 0); assert.equal(s.productQueries.length, 0);
    assert.equal(s.purchaseCount(), 0); assert.equal(s.accountChecks.length, 0);
    assert.equal(s.defaultsReset(), 0); assert.equal(s.icons.length, 0);
    assert.equal(s.service.busy, false);
  });
  console.log(`${count} membership regression groups passed`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
