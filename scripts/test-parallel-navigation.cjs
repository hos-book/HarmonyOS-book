// DEVECO_HOME=<Release IDE> node scripts/test-parallel-navigation.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
function load(source, globals = {}) {
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { module, exports: module.exports, ...globals });
  return module.exports;
}
const { AdaptiveLayout } = load(fs.readFileSync(path.join(root, 'utils/AdaptiveLayout.ets'), 'utf8'));
const source = fs.readFileSync(path.join(root, 'pages/Index.ets'), 'utf8');
const method = source.slice(source.indexOf('  private updateNavigationLayout()'), source.indexOf('  onBackPress()'));
const { Harness } = load(`export class Harness { ${method} }`, { AdaptiveLayout });
const paths = [];
const harness = Object.assign(new Harness(), {
  navigationWidth: 840, parallelNavigation: false, homeCoveredByDetail: false,
  navStack: { getAllPathName: () => paths, size: () => paths.length }
});
harness.updateNavigationLayout();
assert.equal(harness.parallelNavigation, false, 'root home must not leave an empty right pane');
paths.push('detail');
const retained = paths;
harness.homeCoveredByDetail = true;
harness.updateNavigationLayout();
assert.equal(harness.parallelNavigation, true);
assert.equal(harness.homeCoveredByDetail, false, 'master stays visible beside detail');
for (const width of [719, 420, 0, NaN]) {
  harness.navigationWidth = width; harness.updateNavigationLayout();
  assert.equal(harness.parallelNavigation, false);
  assert.equal(paths, retained); assert.deepEqual(paths, ['detail']);
}
harness.navigationWidth = 720; harness.updateNavigationLayout();
assert.equal(harness.parallelNavigation, true, 'unfold restores split without navigating');
for (const immersive of ['reader', 'comicReader', 'player', 'ruleSourceLogin']) {
  paths.push(immersive, 'detail'); harness.updateNavigationLayout();
  assert.equal(harness.parallelNavigation, false, immersive + ' and its descendants stay full width');
  paths.splice(1); harness.updateNavigationLayout();
  assert.equal(harness.parallelNavigation, true, 'return restores split');
}
paths.splice(0); harness.updateNavigationLayout();
assert.equal(harness.parallelNavigation, false);
console.log('PASS empty home, master visibility, fold/unfold stack retention, immersive descendants and return');

const detail = fs.readFileSync(path.join(root, 'pages/BookDetailPage.ets'), 'utf8');
const cleanup = detail.slice(detail.indexOf('  private cleanStackBeforePushPlayer()'), detail.indexOf('  // ==================== 沉浸光感背景'));
const { DetailHarness } = load(`export class DetailHarness { ${cleanup} }`);
for (const routes of [['detail'], ['player', 'detail'], ['search', 'detail', 'player', 'detail']]) {
  const current = [...routes];
  const subject = Object.assign(new DetailHarness(), { navStack: {
    getAllPathName: () => current, clear: () => current.splice(0)
  }});
  subject.cleanStackBeforePushPlayer();
  assert.deepEqual(current, routes.includes('player') ? [] : routes);
}
console.log('PASS player reentry cleanup with native NavBar root');
