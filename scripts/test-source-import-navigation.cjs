// Exercise the real external import queue and page consumer with an in-memory navigation stack.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.join(__dirname, '../entry/src/main/ets');
function load(source, globals = {}) {
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true }
  }).outputText, { module, exports: module.exports, ObservedV2: value => value, Trace: () => {}, ...globals });
  return module.exports;
}
const { RuleSourceImportQueue } = load(fs.readFileSync(path.join(root,
  'service/rulesource/RuleSourceImportQueue.ets'), 'utf8'));
const page = fs.readFileSync(path.join(root, 'pages/RuleSourcePage.ets'), 'utf8');
const start = page.indexOf('  private async consumeExternalImports()');
const end = page.indexOf('\n  private applyFilters()', start);
assert.ok(start >= 0 && end > start);
const noticeRecords = new Map(), noticeWrites = [];
const { RuleSourceNoticeService } = load(fs.readFileSync(path.join(root,
  'service/rulesource/RuleSourceNoticeService.ets'), 'utf8'), {
  require: () => ({ preferences: { getPreferences: async () => ({
    get: async (key, fallback) => noticeRecords.get(key) ?? fallback,
    put: async (key, value) => { noticeRecords.set(key, value); noticeWrites.push([key, value]); },
    flush: async () => {}
  }) } })
});
const { Consumer } = load(`export class Consumer {${page.slice(start, end)}\n}`, {
  RuleSourceNoticeService, $r: value => value, AppColor: { Brand: '#C4475B' }
});
class Stack {
  constructor(names) { this.names = names; }
  getIndexByName(name) { return this.names.flatMap((value, index) => value === name ? [index] : []); }
  getAllPathName() { return [...this.names]; }
  removeByIndexes(indexes) { this.names = this.names.filter((_, index) => !indexes.includes(index)); }
  moveToTop(name) { const i = this.names.indexOf(name); this.names.splice(i, 1); this.names.push(name); }
  pushPathByName(name) { this.names.push(name); }
}
function consumer(queue, stack) {
  const c = new Consumer();
  Object.assign(c, { externalImports: queue, navStack: stack, pageAttached: true,
    isLoading: false, loadFailed: false, isImporting: false, isBulkTesting: false,
    busySourceUrl: '', isEditMode: false, importDialogKind: '', externalNoticeDeferred: false, errors: [],
    confirmImportNotice: async () => true,
    closeManagement() {}, resetSelection() {}, showImportError(error) { this.errors.push(error); },
    readLocalJson: async uri => uri, persistImportContent: async () => true });
  return c;
}
async function testNotice() {
  function setup(onDialog) {
    const queue = new RuleSourceImportQueue(), stack = new Stack(['home']);
    queue.open(stack, 'file://notice.json');
    const c = consumer(queue, stack), imported = [];
    delete c.confirmImportNotice; // Exercise the real method and versioned Preferences service.
    c.noticeInFlight = false;
    c.getUIContext = () => ({ getHostContext: () => ({}),
      showAlertDialog: options => onDialog(options, c, stack) });
    c.showToast = error => { throw Error(error); };
    c.persistImportContent = async uri => { imported.push(uri); return true; };
    return { c, queue, stack, imported };
  }
  let dialogs = 0;
  const accepted = setup(options => { dialogs++; options.primaryButton.action(); });
  await accepted.c.consumeExternalImports();
  assert.equal(dialogs, 1);
  assert.deepEqual(noticeWrites, [['acknowledged_version', 1]], 'acceptance writes the current notice version');
  assert.deepEqual(accepted.imported, ['file://notice.json']);
  accepted.queue.open(accepted.stack, 'file://next.json');
  await accepted.c.consumeExternalImports();
  assert.equal(dialogs, 1, 'an acknowledged version must not prompt again');
  assert.equal(noticeWrites.length, 1);
  assert.deepEqual(accepted.imported, ['file://notice.json', 'file://next.json']);

  for (const action of ['cancel', 'dismiss', 'leave', 'navigate']) {
    noticeRecords.clear(); noticeWrites.length = 0;
    const declined = setup((options, c, stack) => {
      if (action === 'cancel') options.secondaryButton.action();
      if (action === 'dismiss') options.cancel();
      if (action === 'leave') { c.pageAttached = false; c.noticeResolver(false); }
      if (action === 'navigate') { stack.names.push('settings'); options.primaryButton.action(); }
    });
    await declined.c.consumeExternalImports();
    assert.deepEqual(declined.imported, [], `${action} must not continue importing`);
    assert.equal(declined.queue.hasPending(), true, `${action} must preserve the granted URI`);
    assert.equal(declined.c.isImporting, false);
    assert.equal(declined.c.noticeInFlight, false);
    if (action !== 'navigate') assert.equal(noticeWrites.length, 0, `${action} must not record consent`);
  }
}
async function main() {
  await testNotice();
  const queue = new RuleSourceImportQueue();
  const stack = new Stack(['home']);
  queue.open(stack, 'file://a.json');
  queue.open(stack, 'file://b.json');
  queue.open(stack, 'file://c.json');
  assert.deepEqual(stack.names, ['home', 'ruleSources']);
  const c = consumer(queue, stack), imported = [];
  c.isLoading = true;
  await c.consumeExternalImports();
  assert.equal(queue.hasPending(), true, 'cold-start loading must retain all files');
  c.isLoading = false;
  for (const kind of ['link', 'nas']) {
    c.importDialogKind = kind;
    await c.consumeExternalImports();
    assert.equal(queue.hasPending(), true, 'input dialogs must keep incoming files queued');
    assert.equal(c.isImporting, false, 'waiting for input must not enter loading');
  }
  c.importDialogKind = '';
  let noticeCalls = 0;
  c.confirmImportNotice = async () => { noticeCalls++; return false; };
  await c.consumeExternalImports();
  assert.equal(noticeCalls, 1);
  assert.equal(queue.hasPending(), true, 'cancelling the notice must retain every granted URI');
  assert.equal(c.isImporting, false, 'cancelling must restore the idle state');
  assert.equal(c.externalNoticeDeferred, true, 'timers must not reopen a declined notice');
  assert.equal(queue.tryBegin(), true, 'cancelling must release the consumer lease');
  queue.finish();
  c.confirmImportNotice = async () => { noticeCalls++; return true; };
  await c.consumeExternalImports();
  assert.equal(noticeCalls, 1, 'background checks must wait for an explicit retry');
  assert.equal(queue.hasPending(), true);
  c.externalNoticeDeferred = false; // The visible continue-import action permits another attempt.
  c.persistImportContent = async uri => {
    assert.equal(c.isImporting, true, 'loading must remain active until persistence completes');
    imported.push(uri);
    if (uri === 'file://a.json') {
      queue.open(stack, 'file://d.json');
      await c.consumeExternalImports(); // Reentrant monitor/timer must not start another import.
    }
    if (uri === 'file://b.json') throw new Error('invalid file');
    return true;
  };
  await c.consumeExternalImports();
  assert.equal(noticeCalls, 2);
  assert.deepEqual(imported, ['file://a.json', 'file://b.json', 'file://c.json', 'file://d.json']);
  assert.equal(queue.hasPending(), false);
  assert.equal(c.isImporting, false);
  assert.equal(c.errors.length, 1, 'failed files retain error feedback without opening the removed import sheet');
  assert.equal(c.importDialogKind, '');
  queue.open(stack, 'file://a.json');
  c.persistImportContent = async uri => { imported.push(uri); return true; };
  await c.consumeExternalImports();
  assert.equal(imported.length, 5, 'intentional reimport of the same URI is allowed');
  assert.equal(c.importDialogKind, '', 'successful external imports stay on the source list');
  stack.names.pop();
  assert.deepEqual(stack.names, ['home'], 'one back leaves source management');

  const oldStack = new Stack(['home', 'ruleSources', 'settings', 'ruleSources']);
  queue.open(oldStack, 'file://e.json');
  assert.deepEqual(oldStack.names, ['home', 'settings', 'ruleSources']);
  assert.equal(queue.tryBegin(), true);
  assert.equal(queue.tryBegin(), false, 'only one live page may consume at once');
  queue.finish();
  const latest = consumer(queue, oldStack);
  await latest.consumeExternalImports();
  assert.equal(queue.hasPending(), false);
  console.log('PASS external import single page, FIFO, consent cancellation/retry, cold loading, reentry, failed file isolation and reimport');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
