// Exercise real record/session visibility and optional statistics aggregation without touching saved user data.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to the installed Release DevEco Studio');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const read = file => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8').replace(/\r\n/g, '\n');
const fixedNow = new Date(2026, 10, 18, 12).getTime();
class TestDate extends Date {
  constructor(...args) { super(...(args.length ? args : [fixedNow])); }
  static now() { return fixedNow; }
}
function compile(source, context = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source.replace(/^import .*;\n/gm, ''), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText, { exports, Date: TestDate, Set, Map, JSON, ...context });
  return exports;
}
function member(source, name, prefixes = ['private ', 'private async ']) {
  const start = prefixes.map(prefix => source.indexOf(`  ${prefix}${name}(`)).find(index => index >= 0);
  assert.ok(start >= 0, `missing member ${name}`);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
function callback(source, name) {
  const start = source.indexOf(`  private ${name}`);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  };', start) + 5);
}
const { BookPresentation: presentation } = compile(read('model/BookPresentation.ets'));
const { StatsService: stats } = compile(read('service/StatsService.ets'));
const savedStats = [
  { bookId: 'open', listenSeconds: 60, days: [{ day: '2026-11-18', listenSeconds: 60 }] },
  { bookId: 'secret', listenSeconds: 120, days: [{ day: '2026-11-18', listenSeconds: 120 }] },
  { bookId: 'legacy-secret', listenSeconds: 30, days: [{ day: '2026-11-17', listenSeconds: 30 }] },
  { bookId: 'comic', listenSeconds: 20, days: [{ day: '2026-11-17', listenSeconds: 20 }] },
  { bookId: 'unsaved', listenSeconds: 10, days: [{ day: '2026-11-18', listenSeconds: 10 }] },
  { bookId: 'archived-visible', listenSeconds: 40, archived: true, days: [{ day: '2026-11-16', listenSeconds: 40 }] },
  { bookId: 'archived-hidden', listenSeconds: 60, archived: true, days: [{ day: '2026-11-15', listenSeconds: 60 }] }
].map(item => ({ title: item.bookId, author: '', cover: '', updatedAt: fixedNow, ...item }));
stats.initialized = true;
stats.records = savedStats;
const persistedSnapshot = JSON.stringify(savedStats);
const source = read('pages/ReadingStatsPage.ets');
const routes = [];
let detailCaptures = 0;
const { RecordPage } = compile(`export class RecordPage {
  ${callback(source, 'favoritesHandler')}
  ${['shouldShowRecord', 'isRecordHidden', 'hiddenRecordBookIds', 'applyRecordVisibility', 'applyStatsBundle',
    'applyContentFilter', 'filteredRecords', 'openDetail', 'resumeRecord', 'openSessionHistory', 'recordCoverId']
    .map(name => member(source, name)).join('\n')}
}`, { BookPresentation: presentation, StatsService: stats, AppRadius: { Sm: 8 },
  TextReaderRouteParams: { of: bookId => ({ bookId }) },
  OneShotTransitionCoordinator: { getInstance: () => ({
    captureAsync: async () => { detailCaptures++; }, discardPending() {}
  }) },
  PlayerDragTransition: { getInstance: () => ({ captureCover: () => undefined }) }
});
const records = [
  { bookId: 'open', aliasBookIds: ['legacy-open'], isText: false, isComic: false },
  { bookId: 'secret', aliasBookIds: ['secret', 'legacy-secret'], isText: true, isComic: false },
  { bookId: 'comic', aliasBookIds: [], isText: true, isComic: true },
  { bookId: 'unsaved', aliasBookIds: ['legacy-unsaved'], isText: true, isComic: false }
];
const recordSnapshot = JSON.stringify(records);
const ids = values => Array.from(values, item => item.bookId).join('|');
function page(unfavorited = false) {
  const result = Object.assign(new RecordPage(), {
    onlyUnfavorited: unfavorited, loadedRecords: records, loadedFavoriteIds: new Set(['open', 'secret', 'comic']),
    selectedIds: new Set(['secret']), selectMode: true, contentFilter: 0, records: [], rendered: [],
    recordLoadGeneration: 0, recordVisibilityReady: true, reloaded: 0,
    recordDataSource: { setRecords: values => { result.rendered = values; } },
    loadStats: () => { result.reloaded++; }, deletingRecords: false, openingDetail: false,
    playerTransition: { active: false }, recoveryActive: true, visible: true,
    navStack: { pushPathByName: (...args) => routes.push(args), size: () => 0 },
    getUIContext: () => ({ getHostContext: () => ({}) })
  });
  return result;
}
let sessionsRead = 0;
const sessions = ['secret', 'legacy-secret'].map((bookId, index) => ({
  id: `session-${index}`, kind: 'reading', start: { bookId }, end: { bookId }
}));
const sessionSnapshot = JSON.stringify(sessions);
const sessionSource = read('pages/SessionHistoryPage.ets');
const { SessionPage } = compile(`export class SessionPage {
  ${callback(sessionSource, 'favoritesHandler')}
  ${['load', 'isSessionHidden', 'applySessionVisibility', 'jump'].map(name => member(sessionSource, name)).join('\n')}
}`, { BookPresentation: presentation, PreferenceService: { ensureReady: async () => {} },
  ReadingSessionService: { list: async () => { sessionsRead++; return sessions; } } });
(async () => {
  presentation.edits = [{ bookId: 'legacy-secret', hidden: true }, { bookId: 'archived-hidden', hidden: true }];
  const ordinary = page();
  ordinary.favoritesHandler({});
  assert.equal(ids(ordinary.records), 'open|comic', 'canonical record is hidden when an alias is hidden');
  assert.equal(ids(ordinary.rendered), 'open|comic');
  assert.equal(ordinary.selectedIds.size, 0, 'hidden records leave the active batch selection');
  assert.equal(ordinary.selectMode, false);
  assert.equal(ordinary.totalSeconds, 130, 'visible archived time remains; hidden canonical/alias time is omitted');
  assert.equal(ordinary.streak, 3);
  assert.equal(ordinary.recordLoadGeneration, 1, 'visibility changes invalidate an older pending load');
  ordinary.contentFilter = 2; ordinary.applyContentFilter();
  assert.equal(ordinary.rendered.length, 0, 'the text filter cannot reveal hidden records');
  ordinary.contentFilter = 3; ordinary.applyContentFilter();
  assert.equal(ids(ordinary.rendered), 'comic');
  ordinary.selectMode = false;
  await ordinary.openDetail(records[1]);
  await ordinary.resumeRecord(records[1]);
  ordinary.openSessionHistory(records[1]);
  assert.equal(routes.length, 0, 'stale row actions cannot reopen hidden records');
  assert.equal(detailCaptures, 0);
  const unsaved = page(true);
  unsaved.favoritesHandler({});
  assert.equal(ids(unsaved.records), 'unsaved');
  presentation.edits = presentation.assignHidden(['legacy-unsaved'], true);
  unsaved.favoritesHandler({});
  assert.equal(unsaved.records.length, 0, 'unfavorited history applies the same alias filter');
  presentation.edits = presentation.assignHidden(['legacy-secret', 'legacy-unsaved', 'archived-hidden'], false);
  ordinary.contentFilter = 0;
  ordinary.favoritesHandler({}); unsaved.favoritesHandler({});
  assert.equal(ids(ordinary.records), 'open|secret|comic', 'restore immediately republishes the original history');
  assert.equal(ids(unsaved.records), 'unsaved');
  assert.equal(ordinary.totalSeconds, 340);
  ordinary.openSessionHistory(records[1]);
  assert.equal(routes.at(-1)[0], 'sessionHistory');

  const all = await stats.getStatsBundle(4);
  const visible = await stats.getStatsBundle(4, new Set(['secret', 'legacy-secret', 'archived-hidden']));
  assert.equal(all.summary.totalSeconds, 340, 'default statistics for other features keep all actual duration');
  assert.equal(all.records.length, 5, 'archived entries remain outside the visible record list');
  assert.equal(all.streak, 4);
  assert.equal(visible.summary.totalSeconds, 130);
  assert.equal(visible.summary.monthSeconds, 130);
  assert.equal(visible.streak, 3);
  assert.equal(visible.heatDays[0].seconds, 0);
  assert.equal(visible.records.length, 3);
  assert.equal(JSON.stringify(stats.records), persistedSnapshot, 'display aggregation never edits persisted durations');
  assert.equal(JSON.stringify(records), recordSnapshot, 'visibility does not rewrite history or progress views');
  console.log('PASS record/alias hiding, restore, filters, selections, stale entry guards and archived/statistics display isolation');

  presentation.edits = presentation.assignHidden(['secret'], true);
  const history = Object.assign(new SessionPage(), {
    bookIds: '["secret","legacy-secret"]', requestedBookIds: [], allEntries: [],
    visible: true, loadGeneration: 0, jumping: false, count: 0, shown: [],
    records: { update: values => { history.shown = values; } },
    getUIContext: () => ({ getHostContext: () => ({}) })
  });
  await history.load();
  assert.equal(history.count, 0, 'direct session-history routes cannot expose a hidden book');
  assert.equal(history.allEntries.length, 2, 'session data is retained for restore');
  await history.jump(sessions[0], sessions[0].start);
  assert.equal(history.jumping, false, 'hidden session locations cannot start a jump');
  presentation.edits = presentation.assignHidden(['secret'], false);
  history.favoritesHandler({});
  assert.equal(history.count, 2);
  assert.equal(sessionsRead, 1, 'restore can reuse the unmodified loaded session data');
  presentation.edits = presentation.assignHidden(['legacy-secret'], true);
  history.favoritesHandler({});
  assert.equal(history.shown.length, 0, 'hiding any requested alias hides the whole book session group');
  assert.equal(JSON.stringify(sessions), sessionSnapshot, 'hiding never removes real sessions');
  console.log('PASS direct session history load, canonical/alias visibility events, jump guard and nondestructive restore');
})().catch(error => { console.error(error); process.exitCode = 1; });
