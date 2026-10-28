// Exercise the real SettingsPage loading methods without an ArkUI renderer.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
if (!process.env.DEVECO_HOME) throw new Error('Set DEVECO_HOME to the Release IDE');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const page = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/SettingsPage.ets'), 'utf8');
const methods = page.slice(page.indexOf('  private async loadPrefs()'), page.indexOf('  private async setDefaultTab('));

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function harness() {
  let search = deferred();
  let localFailure = false;
  const prefs = {
    getColorMode: async () => { if (localFailure) throw new Error('local storage unavailable'); return 1; },
    getDefaultTab: async () => 2,
    getAutoPlayOnLaunch: async () => true,
    getStoredCoverSuperResolution: async () => true,
    getCoverSuperResolution: () => { throw new Error('Settings must not query membership while loading'); },
    getAudioInterruptMode: async () => 1,
    getAudioAutoResume: async () => false,
    getDefaultPlaybackSpeed: async () => 1.5,
    getPreloadChapters: async () => 7,
    getStoredSearchConcurrency: () => search.promise,
    getSearchConcurrency: () => { throw new Error('Settings must not query membership while loading'); }
  };
  const exports = {};
  const source = `class Settings {
    alive = true; preferencesLoadSerial = 0; isLoaded = false;
    membership = { hasAccess: true, confirmedInactive: false }; searchConcurrency = 3;
    generalSettings = { jianjianCompanionEnabled: false };
    ${methods}
  } exports.Settings = Settings;`;
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, PreferenceService: prefs,
    THEME_OPTIONS: [{ mode: -1 }, { mode: 1 }],
    PRELOAD_OPTIONS: [0, 1, 5, 10, -1].map(count => ({ count })),
    SEARCH_CONCURRENCY_OPTIONS: [3, 6, 9, 12] });
  return { page: new exports.Settings(), get search() { return search; },
    nextSearch() { search = deferred(); return search; },
    failLocal(value) { localFailure = value; } };
}

async function tick() { for (let i = 0; i < 12; i++) await Promise.resolve(); }

(async () => {
  const slow = harness();
  await slow.page.loadPrefs();
  assert.equal(slow.page.isLoaded, true, 'local settings are usable while membership is unresolved');
  assert.equal(slow.page.searchConcurrencyLoading, true);
  assert.equal(slow.page.defaultTab, 2);
  assert.equal(slow.page.autoPlayOnLaunch, true);
  assert.equal(slow.page.defaultPlaybackSpeed, 1.5);
  assert.equal(slow.page.defaultPlaybackSpeedDraft, 1.5);
  assert.equal(slow.page.preloadDraft, '7');
  slow.search.resolve(9); await tick();
  assert.equal(slow.page.searchConcurrency, 9);
  assert.equal(slow.page.searchConcurrencyLoading, false);

  const failure = harness();
  failure.failLocal(true); await failure.page.loadPrefs();
  assert.equal(failure.page.preferencesLoadFailed, true);
  assert.equal(failure.page.isLoaded, false);
  failure.search.reject(new Error('search unavailable')); await tick();
  assert.equal(failure.page.searchConcurrencyLoadFailed, true);
  assert.equal(failure.page.searchConcurrencyLoading, false);
  failure.failLocal(false); failure.nextSearch(); await failure.page.loadPrefs();
  assert.equal(failure.page.isLoaded, true, 'local retry does not depend on search recovery');
  assert.equal(failure.page.preferencesLoadFailed, false);
  failure.search.resolve(6); await tick();
  assert.equal(failure.page.searchConcurrency, 6);

  const stale = harness();
  await stale.page.loadPrefs(); const old = stale.search;
  stale.nextSearch(); await stale.page.loadPrefs();
  stale.search.resolve(12); await tick(); old.resolve(6); await tick();
  assert.equal(stale.page.searchConcurrency, 12, 'old requests cannot overwrite a retry');

  const closed = harness();
  const work = closed.page.loadPrefs();
  closed.page.alive = false; closed.page.preferencesLoadSerial++;
  closed.search.resolve(12); await work; await tick();
  assert.equal(closed.page.isLoaded, false);
  assert.equal(closed.page.searchConcurrency, 3, 'closed page ignores late results');

  const revoked = harness(); await revoked.page.loadPrefs();
  revoked.page.membership.hasAccess = false; revoked.page.membership.confirmedInactive = true;
  revoked.search.resolve(12); await tick();
  assert.equal(revoked.page.searchConcurrency, 3, 'late result cannot display revoked custom access');
  await revoked.page.loadPrefs();
  assert.equal(revoked.page.isLoaded, true);
  assert.equal(revoked.page.defaultPlaybackSpeed, 1.5, 'default speed is available without membership');
  const unknown = harness(); await unknown.page.loadPrefs();
  unknown.page.membership.hasAccess = false; unknown.search.resolve(3); await tick();
  assert.equal(unknown.page.searchConcurrencyLoadFailed, false, 'silent entitlement refresh does not turn stored preferences into a load error');
  console.log('PASS settings: slow membership isolation, local values, failure/retry, stale results, closed page and revoked access');
})().catch(error => { console.error(error); process.exitCode = 1; });
