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

const transitionMethod = source.slice(source.indexOf('  private oneShotNavigationTransition('),
  source.indexOf('  private playerFadeTransition('));
const NavigationOperation = { PUSH: 1, POP: 2, REPLACE: 3 };
const { TransitionHarness } = load(`export class TransitionHarness { ${transitionMethod} }`, {
  AdaptiveLayout, NavigationOperation,
  OneShotTransitionCoordinator: { getInstance: () => ({ discardPending() {}, canHandle: () => false }) }
});
const transitions = Object.assign(new TransitionHarness(), {
  navigationWidth: 1440, playerDragState: { active: false }
});
const home = { index: -1 };
for (const width of [720, 1440]) {
  transitions.navigationWidth = width;
  for (const name of ['ruleSources', 'settings', 'detail', 'search']) {
    const page = { name, index: 0 };
    for (const [from, to, operation] of [[home, page, NavigationOperation.PUSH],
      [page, home, NavigationOperation.POP]]) {
      const result = transitions.oneShotNavigationTransition(from, to, operation);
      assert.ok(result, `${name}: split entry/exit must override the page slide`);
      let completed = 0;
      result.transition({ finishTransition() { completed++; } });
      assert.equal(completed, 1, `${name}: root transition must complete without waiting for a timer`);
    }
  }
  for (const name of ['reader', 'comicReader', 'ruleSourceLogin']) {
    const page = { name, index: 0 };
    assert.equal(transitions.oneShotNavigationTransition(home, page, NavigationOperation.PUSH), undefined);
    assert.equal(transitions.oneShotNavigationTransition(page, home, NavigationOperation.POP), undefined);
  }
  assert.equal(transitions.oneShotNavigationTransition({ name: 'settings', index: 0 },
    { name: 'ruleSources', index: 1 }, NavigationOperation.PUSH), undefined,
  'navigation within the right column retains its existing transition');
}
transitions.navigationWidth = 420;
assert.equal(transitions.oneShotNavigationTransition(home, { name: 'settings', index: 0 },
  NavigationOperation.PUSH), undefined, 'phone page transitions remain unchanged');
console.log('PASS split root entry/exit completes immediately; phone, immersive and nested transitions retained');

const detail = fs.readFileSync(path.join(root, 'pages/BookDetailPage.ets'), 'utf8');
const cleanup = detail.slice(detail.indexOf('  private async cleanStackBeforePushPlayer()'),
  detail.indexOf('  // ==================== 沉浸光感背景'));
const { DetailHarness } = load(`export class DetailHarness { ${cleanup} }`, {
  OneShotLayoutCallback: class { constructor(callback) { this.callback = callback; } }
});
async function verifyPlayerReentry() {
  for (const routes of [['detail'], ['player', 'detail'], ['search', 'detail', 'player', 'detail']]) {
    const current = [...routes];
    const subject = Object.assign(new DetailHarness(), {
      navStack: {
        getAllPathName: () => current,
        removeByName(name) {
          for (let i = current.length - 1; i >= 0; i--) if (current[i] === name) current.splice(i, 1);
        }
      },
      getUIContext: () => ({ postFrameCallback: frame => frame.callback() })
    });
    await subject.cleanStackBeforePushPlayer();
    assert.deepEqual(current, routes.filter(name => name !== 'player'), 'retain detail as the return target');
  }
  console.log('PASS player reentry removes old players and retains the detail return target');
}
verifyPlayerReentry().catch(error => { console.error(error); process.exitCode = 1; });
