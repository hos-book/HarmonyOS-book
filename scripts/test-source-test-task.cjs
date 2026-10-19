// Real task owner with controlled background/notification adapters; no device data changes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const tick = () => new Promise(resolve => setImmediate(resolve));
function setup() {
  const notices = [], interruptions = new Set();
  let release, stopped = 0, cancelled = false, runs = 0, rejectRun = false, permission;
  class Progress { total = 0; completed = 0; passed = 0; failed = 0; }
  class Report { total = 0; cancelled = false; }
  const background = {
    subscribeInterruption: listener => interruptions.add(listener),
    unsubscribeInterruption: listener => interruptions.delete(listener),
    resumeAfterUserAction() {}, startDataTransfer: async () => {},
    stopDataTransfer: async () => { stopped++; }
  };
  const dependencies = {
    '@kit.NotificationKit': { notificationManager: {
      SlotType: { SERVICE_INFORMATION: 1 }, ContentType: { NOTIFICATION_CONTENT_BASIC_TEXT: 0 },
      isNotificationEnabled: async () => true,
      addSlot: async () => { if (permission) await permission; },
      publish: async notice => notices.push(notice)
    } },
    '../BackgroundTaskService': { BackgroundTaskService: background },
    '../SourceDataService': { SourceDataService: { invalidateLocalSources() {} } },
    './LocalRuleSourceBulkTester': {
      LocalRuleSourceBulkTestProgress: Progress, LocalRuleSourceBulkTestReport: Report,
      LocalRuleSourceBulkTester: { createDefault: () => ({
        cancel: () => { cancelled = true; },
        async run(sources, keyword, update) {
          runs++;
          if (rejectRun) throw Error('fixture failure');
          const progress = new Progress(); progress.total = sources.length;
          progress.completed = 1; progress.passed = 1; update(progress);
          await new Promise(resolve => { release = resolve; });
          const report = new Report(); report.total = sources.length; report.cancelled = cancelled;
          return report;
        }
      }) }
    }
  };
  const exports = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,
    '../entry/src/main/ets/service/rulesource/SourceTestTaskService.ets'), 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText, { exports, require: name => dependencies[name] || {}, $r: id => ({ id }) });
  const service = exports.SourceTestTaskService;
  service.setContext({ resourceManager: { getStringSync: (id, ...args) => [id, ...args].join('|') } });
  return { service, notices, interruptions, release: () => release(), runs: () => runs,
    stopped: () => stopped, fail: () => { rejectRun = true; }, holdPermission: value => { permission = value; } };
}
(async () => {
  const h = setup(); let updates = 0;
  const listener = () => updates++;
  h.service.subscribe(listener);
  const task = h.service.start([{}, {}], 'fixture', 'search');
  await tick();
  assert.equal(h.service.state.running, true);
  assert.equal(h.service.state.progress.completed, 1);
  h.service.unsubscribe(listener);
  await h.service.start([{}], 'duplicate', 'search');
  assert.equal(h.runs(), 1, 'reopening a page cannot start a duplicate task');
  const previousUpdates = updates;
  h.service.cancel(); h.release(); await task; await tick();
  assert.equal(updates, previousUpdates, 'leaving the page detaches the listener');
  assert.equal(h.service.state.report.cancelled, true);
  assert.equal(h.stopped(), 1);
  assert.equal(h.interruptions.size, 0);
  assert.ok(h.notices.at(-1).content.normal.text.includes('source_manage_test_cancelled'));

  const before = setup(); let allow;
  before.holdPermission(new Promise(resolve => { allow = resolve; }));
  const pending = before.service.start([{}], 'fixture', 'search');
  await tick(); before.service.cancel(); allow(); await pending; await tick();
  assert.equal(before.runs(), 0, 'cancellation during permission setup prevents network tests');
  assert.equal(before.service.state.report.cancelled, true);
  assert.equal(before.stopped(), 1);

  const interrupted = setup();
  const interruptedTask = interrupted.service.start([{}], 'fixture', 'search');
  await tick(); for (const listener of interrupted.interruptions) listener();
  interrupted.release(); await interruptedTask;
  assert.equal(interrupted.service.state.report.cancelled, true, 'system interruption stops new work');

  const failure = setup(); failure.fail();
  await failure.service.start([{}], 'fixture', 'search'); await tick();
  assert.equal(failure.service.state.failed, true);
  assert.equal(failure.service.state.running, false);
  assert.equal(failure.stopped(), 1);
  assert.ok(failure.notices.at(-1).content.normal.text.includes('rule_source_bulk_operation_failed'));
  console.log('PASS service-owned detection, page detach, duplicate start, permission cancellation, system interruption and terminal notifications');
})().catch(error => { console.error(error); process.exitCode = 1; });
