const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));

function harness() {
  const calls = [];
  const appearance = { accent: '', material: 3 };
  const member = { hasAccess: true, confirmedInactive: false };
  let entitled = true;
  let failSave = false;
  const prefs = {
    setAccentColor: async value => { if (failSave) throw Error('disk full'); calls.push(['accent', value]); appearance.accent = value; },
    setPreloadChapters: async value => { if (failSave) throw Error('disk full'); calls.push(['preload', value]); },
    setSearchConcurrency: async value => { if (failSave) throw Error('disk full'); calls.push(['search', value]); }
  };
  const context = vm.createContext({
    exports: {}, $r: id => ({ id }),
    AppAppearance: { current: appearance, defaultAccent: '#C4475B',
      normalizeAccent: value => /^#[0-9A-F]{6}$/i.test(value.trim()) ? value.trim().toUpperCase() : '' },
    GeneralSettings: { current: {} }, MembershipState: { current: member, featureEnabled: true },
    MembershipService: { instance: { hasCurrentEntitlement: async () => entitled, busy: false, message: 'verify' } },
    ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: -1 } },
    ReaderCacheUsage: class {}, PreferenceService: prefs,
    ChapterCacheService: { getInstance: () => ({ setPreloadCount: value => calls.push(['cache', value]) }) },
    AudioService: { getInstance: () => ({ refreshPreload: () => calls.push(['refresh']) }) },
    PRELOAD_OPTIONS: [0, 1, 5, 10, -1].map(count => ({ count })),
    SEARCH_CONCURRENCY_OPTIONS: [3, 6, 9, 12], hilog: { warn() {} }
  });
  function load(file, name) {
    const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8');
    const start = source.indexOf(`export struct ${name}`);
    const end = source.indexOf('  @Builder', start);
    assert.ok(start >= 0 && end > start);
    const logic = source.slice(start, end).replace('export struct', 'export class')
      .replace(/@(Local|Param|Event)\s+/g, '').replace(/^\s*@Monitor\([^\n]*\)\s*$/gm, '') + '\n}';
    const output = ts.transpileModule(logic, { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
    } }).outputText;
    context.NavPathStack = class { pushPathByName() {} };
    vm.runInContext(`(() => { ${output}\n })()`, context);
    const instance = new context.exports[name]();
    instance.getUIContext = () => ({ getPromptAction: () => ({ showToast() {} }) });
    return instance;
  }
  return { calls, appearance, member,
    accent: () => load('components/AppearanceSettingsComponent.ets', 'AppearanceSettingsComponent'),
    settings: () => load('pages/SettingsPage.ets', 'SettingsPage'),
    revoke: () => { entitled = false; member.hasAccess = false; member.confirmedInactive = true; },
    expireDuringCheck: () => { entitled = false; }, fail: () => { failSave = true; } };
}

async function tick() { for (let i = 0; i < 12; i++) await Promise.resolve(); }

(async () => {
  const h = harness();
  const accent = h.accent();
  accent.selectAccent('#2869B8');
  assert.equal(h.appearance.accent, '', 'choosing a preset does not change the live theme');
  assert.equal(h.calls.length, 0);
  await accent.applyCustomAccent();
  assert.equal(h.appearance.accent, '#2869B8');
  accent.selectAccent('');
  assert.equal(h.appearance.accent, '#2869B8');
  await accent.applyCustomAccent();
  assert.equal(h.appearance.accent, '', 'default preset preserves its default semantic value');
  accent.customHex = '#bad';
  await accent.applyCustomAccent();
  assert.equal(accent.colorInvalid, true);
  assert.equal(h.calls.length, 2, 'invalid draft is not persisted');
  const cancelled = h.accent();
  cancelled.selectAccent('#008577');
  assert.equal(h.appearance.accent, '', 'discarding an edited component leaves global appearance unchanged');

  const page = h.settings();
  page.isLoaded = true; page.alive = true; page.searchConcurrencyLoading = false;
  page.choosePreload(3);
  assert.equal(page.preloadDraft, '10');
  assert.equal(page.preloadCount, 1);
  assert.equal(h.calls.length, 2, 'preload preset does not touch preferences or player cache');
  page.submitPreload(); await tick();
  assert.equal(page.preloadCount, 10);
  assert.deepEqual(h.calls.slice(-3), [['preload', 10], ['cache', 10], ['refresh']]);
  const beforeSearch = h.calls.length;
  await page.chooseSearchConcurrency(3);
  assert.equal(page.searchConcurrencyDraft, '12');
  assert.equal(page.searchConcurrency, 3);
  assert.equal(h.calls.length, beforeSearch, 'member selection remains a draft');
  await page.submitSearchConcurrency();
  assert.equal(page.searchConcurrency, 12);
  assert.deepEqual(h.calls.at(-1), ['search', 12]);

  const beforeDenied = h.calls.length;
  h.revoke();
  await page.chooseSearchConcurrency(1);
  await page.submitSearchConcurrency();
  assert.equal(h.calls.length, beforeDenied, 'nonmember cannot select or commit');
  const expired = harness(); const expPage = expired.settings();
  expPage.alive = true; expPage.searchConcurrencyLoading = false;
  expPage.searchConcurrencyDraft = '9'; expired.expireDuringCheck();
  await expPage.submitSearchConcurrency();
  assert.equal(expired.calls.length, 0, 'apply rechecks entitlement even if the visible state was previously active');
  h.fail(); accent.selectAccent('#2869B8'); await accent.applyCustomAccent();
  assert.equal(h.appearance.accent, '', 'failed apply does not change the live theme');
  console.log('PASS: preset drafts, explicit apply, default color, invalid input, cancel, preload side effects, membership denial and expiry, failed save');
})().catch(error => { console.error(error); process.exitCode = 1; });
