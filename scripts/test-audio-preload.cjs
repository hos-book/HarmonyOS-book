// Real cache/import services with controlled transfers and file metadata.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const sizes = new Map();
const transfers = [];
const events = [];
const backgroundModes = [];
const backgroundEvents = new Map();
class Transfer {
  cancelled = false;
  download(options) {
    this.options = options;
    transfers.push(this);
    return new Promise((resolve, reject) => { this.resolve = resolve; this.reject = reject; });
  }
  finish(bytes) { sizes.set(this.options.finalPath, bytes); this.resolve(bytes); }
  cancel() { this.cancelled = true; this.reject(new Error('cancelled')); }
}
const modules = new Map();
const invalidated = [];
const imports = [];
let importFailure = false;
let storedChapters = [];
const source = { bookSourceUrl: 'https://source.invalid', isLocked: false };
const locked = { bookSourceUrl: 'https://locked.invalid', isLocked: true };
const stubs = {
  '@kit.CoreFileKit': { fileIo: {
    statSync: filename => { if (!sizes.has(filename)) throw new Error('missing'); return { size: sizes.get(filename) }; },
    stat: async filename => { if (filename === '/files' || filename === '/cache') return { isDirectory: () => true }; throw new Error('missing'); },
    access: async filename => sizes.has(filename),
    utimes() {}, listFile: async () => [], unlink: async filename => sizes.delete(filename),
    unlinkSync: filename => sizes.delete(filename)
  } },
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
  '@kit.BackgroundTasksKit': { backgroundTaskManager: { on(name, callback) { backgroundEvents.set(name, callback); },
    startBackgroundRunning: async (_context, modes) => {
      backgroundModes.push([...modes]);
      return { continuousTaskId: backgroundModes.length };
    },
    updateBackgroundRunning: async (_context, modes) => backgroundModes.push([...modes]),
    stopBackgroundRunning: async () => backgroundModes.push([]) } },
  '@kit.AbilityKit': { wantAgent: { OperationType: { START_ABILITY: 0 },
    WantAgentFlags: { UPDATE_PRESENT_FLAG: 0 }, getWantAgent: async () => ({}) } },
  'service/DiagnosticLogService': { DiagnosticLogService: { info() {}, failure() {} } },
  'utils/PlatformCompat': { PlatformCompat: { supports: () => false } },
  '@kit.BasicServicesKit': { emitter: { emit: event => events.push(event) } },
  '@kit.MediaKit': { media: {} },
  'service/PreferenceService': { PreferenceService: {} },
  'service/AudioDownloadTransport': { AudioDownloadTransport: Transfer },
  'service/BookSourceService': { BookSourceService: { invalidateAudioTocs: urls => invalidated.push([...urls]),
    resolveAudioRequest: async () => { throw new Error('Cached files must not resolve source requests'); } } },
  'service/SourceDataService': { SourceDataService: { invalidateLocalSources() {} } },
  'service/DataService': { DataService: { historyBookIds: async () => new Set(), invalidateSourceCaches: async (urls, beforeInvalidate) => {
    if (beforeInvalidate) beforeInvalidate('stored-book', storedChapters);
    invalidated.push([...urls]); return ['book'];
  } } },
  'service/rulesource/LocalRuleSourceRepository': { LocalRuleSourceRepository: {
    getAll: async () => [source, locked], upsertImportedBatch: async values => {
      if (importFailure) throw new Error('transaction failed');
      imports.push(values); return values.filter(item => item.bookSourceUrl !== locked.bookSourceUrl).length;
    }
  } }
};
function load(name) {
  if (stubs[name]) return stubs[name];
  if (modules.has(name)) return modules.get(name).exports;
  const module = { exports: {} };
  modules.set(name, module);
  const filename = ['.ets', '.ts'].map(ext => path.join(root, name + ext)).find(fs.existsSync);
  if (!filename) throw new Error(`Module not found: ${name}`);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, console, setTimeout, clearTimeout,
    require: dependency => load(dependency.startsWith('.')
      ? path.posix.normalize(path.posix.join(path.posix.dirname(name), dependency)) : dependency)
  }, { filename });
  return module.exports;
}
(async () => {
  const { ChapterCacheService } = load('service/ChapterCacheService');
  const cache = ChapterCacheService.getInstance();
  cache.setContext({ cacheDir: '/cache', filesDir: '/files' });
  const chapters = [0, 1].map(index => ({ id: `book-c${index}`, index: index + 1, title: `episode ${index}`,
    duration: 0, source: { type: 'url', value: `https://source.invalid/chapter/${index}` } }));
  const book = { id: 'book', sourceUrl: source.bookSourceUrl, chapters };
  cache.audioCache.set(chapters[0].id, { resolvedUrl: 'https://cdn.invalid/audio.mp3', headers: {} });
  assert.equal(cache.isAudioChapterCached(book, chapters[0]), false, 'A resolved URL is not a complete cache');
  await cache.storageMigration;
  const first = cache.downloadFile(book, chapters[0], 'https://cdn.invalid/first.mp3');
  const duplicate = cache.downloadFile(book, chapters[0], 'https://cdn.invalid/first.mp3');
  assert.equal(first, duplicate, 'One transfer per chapter');
  const second = cache.downloadFile(book, chapters[1], 'https://cdn.invalid/second.mp3');
  assert.equal(transfers.length, 2);
  cache.suspendPreload(chapters[0].id);
  assert.equal(transfers[0].cancelled, false, 'Switching keeps target transfer');
  assert.equal(transfers[1].cancelled, true, 'Other transfers release network capacity');
  const waiting = cache.waitForAudioFile(book, chapters[0]);
  transfers[0].finish(6 * 1024 * 1024);
  assert.ok(await waiting);
  await Promise.all([first, second]);
  assert.equal(cache.isAudioChapterCached(book, chapters[0]), true);
  assert.equal(cache.isAudioChapterCached(book, chapters[1]), false);
  assert.ok(events.includes('app.chapter.cache.updated'));
  assert.equal(transfers.length, 2, 'Playing a complete cache does not start a fresh transfer');
  cache.resumePreload();
  console.log('PASS complete-file status, files above 5 MiB, transfer coalescing and selected preload reuse');

  const { SearchCache } = load('utils/SearchCache');
  // Reimport after a cold start must remove files absent from the in-memory cache.
  cache.fileCache.clear();
  storedChapters = [{ ...chapters[0], id: 'stored-book-c0' }];
  const legacy = cache.legacyAudioFilePath(book.id, chapters[0].id);
  const stored = cache.audioFilePath('stored-book', storedChapters[0].source.value);
  const storedLegacy = cache.legacyAudioFilePath('stored-book', storedChapters[0].id);
  const unrelated = cache.audioFilePath('other-book', 'https://other.invalid/chapter');
  for (const filename of [legacy, stored, storedLegacy, unrelated]) sizes.set(filename, 6000);
  SearchCache.put({ ...book, title: 'book', cover: '', variables: { old: 'yes' } });
  SearchCache.put({ ...book, id: 'locked-book', sourceUrl: locked.bookSourceUrl, cover: '', chapters: chapters.slice() });
  const { LocalRuleSourceImportService } = load('service/rulesource/LocalRuleSourceImportService');
  assert.equal(await LocalRuleSourceImportService.importSources([source, locked,
    { bookSourceUrl: 'https://new.invalid' }]), 2);
  assert.deepEqual(invalidated, [[source.bookSourceUrl], [source.bookSourceUrl]]);
  assert.equal(SearchCache.get('book').chapters.length, 0);
  assert.equal(SearchCache.get('locked-book').chapters.length, 2);
  assert.equal(cache.isAudioChapterCached(book, chapters[0]), false);
  for (const filename of [legacy, stored, storedLegacy]) assert.equal(sizes.has(filename), false);
  assert.equal(sizes.has(unrelated), true, 'Other sources retain their audio files');
  importFailure = true;
  await assert.rejects(LocalRuleSourceImportService.importSources([source]), /transaction failed/);
  assert.equal(invalidated.length, 2, 'Failed transactions never reset content caches');
  console.log('PASS source overwrite resets only unlocked existing sources after a successful transaction');

  const settle = () => new Promise(resolve => setImmediate(resolve));
  const makeBook = id => ({ id, sourceUrl: source.bookSourceUrl,
    chapters: Array.from({ length: 6 }, (_, i) => ({ id: `${id}-c${i}`, title: `chapter ${i}`, index: i + 1,
      source: { type: 'url', value: `https://source.invalid/${id}/${i}` } })) });
  const freshCache = async () => {
    const instance = new ChapterCacheService();
    instance.setContext({ cacheDir: '/cache', filesDir: '/files',
      abilityInfo: { bundleName: 'test', name: 'EntryAbility' } });
    await instance.storageMigration;
    instance.setPreloadCount(3);
    return instance;
  };
  const sourceService = stubs['service/BookSourceService'].BookSourceService;
  stubs['service/SourceDataService'].SourceDataService.getSourceByUrl = async () => source;
  sourceService.prepareAudioChapter = async () => {};
  sourceService.getAudioResolveTimeoutMs = (_source, fallback) => fallback;
  const resolved = [];
  sourceService.resolveAudioRequest = async (_source, url, _variables, chapterVariables) => {
    const index = Number(url.split('/').at(-1));
    assert.equal(chapterVariables.chapterName, `chapter ${index}`);
    assert.equal(chapterVariables.chapterIndex, String(index));
    resolved.push(url);
    return { url: `${url}.mp3`, headers: {} };
  };
  const replay = await freshCache();
  replay.setPreloadCount(1);
  const replayBook = makeBook('replay');
  const firstChapter = replayBook.chapters[0];
  const firstUrl = 'https://cdn.invalid/replay-first.mp3';
  replay.rememberAudioRequest(firstChapter.id, firstUrl, { Referer: 'https://source.invalid' });
  const replayStart = transfers.length;
  replay.preloadAudioChapters(replayBook, 0, firstUrl, replay.getAudioHeaders(firstChapter.id));
  await settle();
  assert.equal(transfers.length, replayStart + 1);
  assert.equal(transfers.at(-1).options.url, replayBook.chapters[1].source.value + '.mp3', 'Next chapter starts before saving the current chapter');
  transfers.at(-1).finish(6000);
  await settle();
  assert.equal(transfers.length, replayStart + 2);
  assert.equal(transfers.at(-1).options.url, firstUrl, 'Current chapter follows the nearest next chapter');
  transfers.at(-1).finish(6000);
  assert.ok(await replay.waitForAudioFile(replayBook, replayBook.chapters[1]));
  await settle();
  replay.suspendPreload(firstChapter.id);
  assert.ok(await replay.waitForAudioFile(replayBook, firstChapter), '1 -> 2 -> 1 reuses the complete first file');
  assert.equal(transfers.length, replayStart + 2, 'Returning to chapter 1 starts no new download');
  assert.equal(replay.getAudioUrl(firstChapter.id), firstUrl, 'Foreground URL remains available for fast replay');
  console.log('PASS next chapter priority and chapter 1 -> 2 -> 1 complete-file reuse');

  for (const descending of [false, true]) {
    const ordered = await freshCache();
    const orderedBook = makeBook(`ordered-${descending}`);
    orderedBook.chaptersDescending = descending;
    const current = 0;
    const before = transfers.length;
    ordered.preloadAudioChapters(orderedBook, current);
    ordered.preloadAudioChapters(orderedBook, current);
    await settle();
    assert.equal(ordered.queue.size, 2, 'Repeated triggers deduplicate queued chapters');
    for (let distance = 1; distance <= 3; distance++) {
      assert.equal(transfers.length, before + distance, 'Only one background transfer runs');
      const expected = orderedBook.chapters[current + distance].source.value;
      assert.equal(transfers.at(-1).options.url, `${expected}.mp3`, 'Nearest chapter goes first');
      transfers.at(-1).finish(6000);
      await settle();
    }
    assert.equal(ordered.queue.size, 0);
    assert.equal(ordered.runningCount, 0);
  }
  console.log('PASS next chapter preloading with either TOC order, queue deduplication and serial transfers');

  const stopping = await freshCache();
  const stoppingBook = makeBook('stopping');
  stopping.preloadAudioChapters(stoppingBook, 0);
  await settle();
  const cancelled = transfers.at(-1);
  stopping.setPreloadCount(0);
  await settle();
  assert.equal(cancelled.cancelled, true);
  assert.equal(stopping.queue.size, 0);
  assert.equal(stopping.preloadFailureAt.size, 0, 'User cancellation is not a source failure');
  const deferred = await freshCache();
  let finishResolve;
  sourceService.resolveAudioRequest = () => new Promise(resolve => { finishResolve = resolve; });
  deferred.preloadAudioChapters(makeBook('deferred'), 0);
  await settle();
  const transferCount = transfers.length;
  deferred.setPreloadCount(0);
  deferred.setPreloadCount(3);
  finishResolve({ url: 'https://cdn.invalid/late.mp3', headers: {} });
  await settle();
  assert.equal(transfers.length, transferCount, 'Disabled-generation results cannot start a transfer after reenable');
  assert.equal(deferred.audioCache.size, 0);
  console.log('PASS disable cancels transfers and invalidates late resolution across reenable');

  const resumed = await freshCache();
  const resumedBook = makeBook('resumed');
  sourceService.resolveAudioRequest = async (_source, url) => ({ url: `${url}.mp3`, headers: {} });
  resumed.preloadAudioChapters(resumedBook, 0);
  await settle();
  const firstAttempt = transfers.at(-1);
  resumed.suspendPreload();
  resumed.resumePreload();
  resumed.preloadAudioChapters(resumedBook, 0);
  await settle();
  assert.equal(firstAttempt.cancelled, true);
  assert.equal(transfers.at(-1).options.url, firstAttempt.options.url, 'Fast resume retries the nearest cancelled chapter');
  resumed.setPreloadCount(0);
  await settle();
  console.log('PASS buffer cancellation followed by immediate resume preserves nearest-chapter priority');

  // Take over an in-flight resolver without restarting it or waiting for a full file.
  const takeover = await freshCache();
  const takeoverBook = makeBook('takeover');
  const takeoverChapter = takeoverBook.chapters[1];
  let completeResolve;
  let calls = 0;
  let observedRequest;
  sourceService.resolveAudioRequest = (_source, _url, _variables, _chapterVariables, request) => {
    observedRequest = request;
    calls++;
    return new Promise(resolve => { completeResolve = resolve; });
  };
  takeover.preloadAudioChapters(takeoverBook, 0);
  await settle();
  assert.equal(observedRequest.priority, 0, 'Preload enters the source limiter with background priority');
  const pending = takeover.getPendingAudioResolve(takeoverBook, takeoverChapter);
  assert.ok(pending);
  assert.equal(takeover.getPendingAudioResolve({ ...takeoverBook, sourceUrl: 'other' }, takeoverChapter), undefined);
  assert.equal(takeover.getPendingAudioResolve(takeoverBook,
    { ...takeoverChapter, source: { type: 'url', value: 'https://changed.invalid' } }), undefined);
  takeover.suspendPreload(takeoverChapter.id);
  assert.equal(observedRequest.priority, 2, 'Foreground takeover promotes the original pending request');
  assert.equal(observedRequest.isCancelled(), false);
  assert.equal(await takeover.waitForAudioFile(takeoverBook, takeoverChapter), null);
  assert.equal(takeover.getPendingAudioResolve(takeoverBook, takeoverChapter), pending);
  const beforeTakeover = transfers.length;
  completeResolve({ url: 'https://cdn.invalid/takeover.mp3', headers: { Referer: 'https://source.invalid' } });
  await pending;
  await settle();
  assert.equal(calls, 1);
  assert.equal(takeover.getAudioUrl(takeoverChapter.id), 'https://cdn.invalid/takeover.mp3');
  assert.equal(takeover.getAudioHeaders(takeoverChapter.id).Referer, 'https://source.invalid');
  assert.equal(transfers.length, beforeTakeover, 'Foreground takeover starts no competing full download');
  console.log('PASS in-flight resolve takeover preserves URL/headers and avoids duplicate work');

  for (const action of ['clear', 'switch', 'disable']) {
    const invalid = await freshCache();
    const invalidBook = makeBook('invalid-' + action);
    invalid.preloadAudioChapters(invalidBook, 0);
    await settle();
    if (action === 'clear') invalid.clearChapter(invalidBook.chapters[1].id);
    if (action === 'switch') invalid.suspendPreload(invalidBook.chapters[2].id);
    if (action === 'disable') invalid.setPreloadCount(0);
    assert.equal(observedRequest.isCancelled(), true, `${action} cancels the source request before quota admission`);
    assert.equal(invalid.getPendingAudioResolve(invalidBook, invalidBook.chapters[1]), undefined);
    completeResolve({ url: 'https://cdn.invalid/stale.mp3', headers: {} });
    await settle();
    assert.equal(invalid.getAudioUrl(invalidBook.chapters[1].id), null);
    invalid.setPreloadCount(0);
    // The clear case may already have moved on to the next queued resolver.
    completeResolve({ url: 'https://cdn.invalid/stale.mp3', headers: {} });
    await settle();
  }
  console.log('PASS clear, unrelated chapter switch and disable invalidate in-flight results');

  // A stuck resolver must not prevent the current file or subsequent episodes from caching.
  for (const phase of ['prepare', 'resolve']) {
    const timeoutCache = await freshCache();
    const timeoutBook = makeBook('timeout-' + phase);
    timeoutCache.setPreloadCount(2);
    let releaseStuck;
    const originalPrepare = sourceService.prepareAudioChapter;
    sourceService.getAudioResolveTimeoutMs = () => 20;
    sourceService.prepareAudioChapter = async (_source, _book, chapter) => {
      if (phase === 'prepare' && chapter.id === timeoutBook.chapters[1].id) {
        await new Promise(resolve => { releaseStuck = resolve; });
      }
    };
    sourceService.resolveAudioRequest = async (_source, url) => {
      if (phase === 'resolve' && url === timeoutBook.chapters[1].source.value) {
        return new Promise(resolve => { releaseStuck = resolve; });
      }
      return { url: url + '.mp3', headers: {} };
    };
    const beforeTimeout = transfers.length;
    timeoutCache.preloadAudioChapters(timeoutBook, 0, 'https://cdn.invalid/current-after-timeout.mp3');
    await new Promise(resolve => setTimeout(resolve, 45));
    await settle();
    assert.equal(transfers.length, beforeTimeout + 1);
    assert.equal(transfers.at(-1).options.url, 'https://cdn.invalid/current-after-timeout.mp3');
    assert.equal(timeoutCache.preloadFailureAt.has(timeoutBook.chapters[1].id), true);
    releaseStuck({ url: 'https://cdn.invalid/late.mp3', headers: {} });
    await settle();
    assert.equal(timeoutCache.getAudioUrl(timeoutBook.chapters[1].id), null);
    transfers.at(-1).finish(6000);
    await settle();
    assert.equal(transfers.at(-1).options.url, timeoutBook.chapters[2].source.value + '.mp3');
    transfers.at(-1).finish(6000);
    await settle();
    sourceService.prepareAudioChapter = originalPrepare;
    sourceService.getAudioResolveTimeoutMs = (_source, fallback) => fallback;
  }
  console.log('PASS prepare/resolve timeout releases queue and ignores late results');
  sourceService.resolveAudioRequest = async (_source, url) => ({ url: url + '.mp3', headers: {} });

  const timed = await freshCache();
  const timedBook = makeBook('timed');
  const target = timedBook.chapters[1];
  const timedTask = timed.downloadFile(timedBook, target, 'https://cdn.invalid/slow.mp3');
  await settle();
  const slowTransfer = transfers.at(-1);
  timed.suspendPreload(target.id);
  assert.equal(await timed.waitForAudioFile(timedBook, target), null);
  await timedTask;
  assert.equal(slowTransfer.cancelled, true, 'Incomplete target transfer immediately yields to online playback');
  assert.equal(timed.preloadFailureAt.size, 0);
  console.log('PASS incomplete transfer yields immediately without failure cooldown');

  const expiring = await freshCache();
  expiring.audioCache.set('expired', { resolvedUrl: 'https://cdn.invalid/old',
    headers: { Authorization: 'old' }, timestamp: Date.now() - 6 * 60 * 1000 });
  assert.equal(expiring.getAudioUrl('expired'), null);
  assert.equal(Object.keys(expiring.getAudioHeaders('expired')).length, 0);
  expiring.audioCache.set('fresh', { resolvedUrl: 'https://cdn.invalid/fresh', headers: {}, timestamp: Date.now() });
  assert.equal(expiring.getAudioUrl('fresh'), 'https://cdn.invalid/fresh');
  console.log('PASS URL expiration removes both stale URL and headers');

  const background = load('service/BackgroundTaskService').BackgroundTaskService;
  const pausedCache = await freshCache();
  const pausedBook = makeBook('paused-completion');
  const ctx = pausedCache.appContext;
  await background.start(ctx);
  backgroundEvents.get('continuousTaskCancel')({ id: background.taskId, reason: 1 });
  const cancelledModes = backgroundModes.length;
  await background.ensure(ctx);
  await background.start(ctx);
  assert.equal(backgroundModes.length, cancelledModes, 'Automatic work must respect system cancellation');
  background.resumeAfterUserAction();
  await background.start(ctx);
  assert.equal(background.isRunning(), true, 'Widget play can reacquire a cancelled task with existing owners');
  assert.equal(backgroundModes.length, cancelledModes + 1);
  backgroundEvents.get('continuousTaskSuspend')({ continuousTaskId: background.taskId, suspendReason: 1 });
  await background.ensure(ctx);
  assert.equal(backgroundModes.length, cancelledModes + 1);
  background.resumeAfterUserAction();
  await background.start(ctx);
  assert.equal(backgroundModes.length, cancelledModes + 3, 'Release the suspended task before requesting a replacement');
  console.log('PASS explicit playback recovers cancelled/suspended background owners without automatic rearming');
  await background.startDataTransfer(ctx);
  pausedCache.preloadAudioChapters(pausedBook, 0, 'https://cdn.invalid/current.mp3');
  await settle();
  await background.stop(ctx);
  await background.stopDataTransfer(ctx);
  assert.equal(background.hasMode('audioPlayback'), false);
  assert.equal(background.hasMode('dataTransfer'), true, 'Preload outlives both audio pause and manual download completion');
  const firstPausedTransfer = transfers.length - 1;
  for (let index = 0; index < 4; index++) {
    const transfer = transfers.at(-1);
    assert.equal(transfer.cancelled, false);
    transfer.finish(8192);
    await settle();
    if (index < 3) assert.equal(background.hasMode('dataTransfer'), true, 'Keep data transfer across queued chapters');
  }
  assert.equal(transfers.length - firstPausedTransfer, 4, 'Only current plus configured three chapters are downloaded');
  assert.equal(pausedCache.runningCount, 0);
  assert.equal(background.hasMode('dataTransfer'), false, 'Finite queue releases background mode when finished');
  const reopened = await freshCache();
  for (const chapter of pausedBook.chapters.slice(0, 4)) {
    assert.ok(reopened.getAudioFilePath(pausedBook.id, chapter.id, chapter.source.value), 'Completed paused downloads survive cold start');
  }
  const failedCache = await freshCache();
  const failedBook = makeBook('failed-completion');
  await background.startDataTransfer(ctx);
  failedCache.ensureFileCached(failedBook, failedBook.chapters[0], 'https://cdn.invalid/fail.mp3');
  await settle();
  transfers.at(-1).reject(new Error('network failure'));
  await settle();
  assert.equal(failedCache.transferHeld, false, 'Failure releases the preload owner');
  assert.equal(background.hasMode('dataTransfer'), true, 'Preload failure must not stop manual download');
  await background.stopDataTransfer(ctx);
  assert.equal(background.hasMode('dataTransfer'), false);
  console.log('PASS paused finite queue completes, cold cache survives, and background owners release independently on success/failure');

  sizes.clear();
  const migrationIo = stubs['@kit.CoreFileKit'].fileIo;
  migrationIo.listFile = async dir => [...sizes.keys()].filter(p => path.posix.dirname(p) === dir).map(p => path.posix.basename(p));
  migrationIo.stat = async filename => {
    if (filename === '/files' || filename === '/cache') return { isDirectory: () => true };
    if (!sizes.has(filename)) throw new Error('missing');
    return { size: sizes.get(filename), mtime: 1, isDirectory: () => false, isFile: () => true };
  };
  migrationIo.copyFile = async (from, to) => { sizes.set(to, sizes.get(from)); };
  migrationIo.moveFile = async (from, to) => { sizes.set(to, sizes.get(from)); sizes.delete(from); };
  const migrated = await freshCache();
  const durablePath = migrated.audioFilePath(book.id, chapters[0].source.value);
  const legacyPath = durablePath.replace('/files/', '/cache/');
  sizes.set(legacyPath, 4096);
  migrated.setContext({ cacheDir: '/cache', filesDir: '/files' });
  await migrated.storageMigration;
  assert.equal(sizes.has(legacyPath), false);
  for (const name of sizes.keys()) if (name.startsWith('/cache/')) sizes.delete(name);
  const cold = await freshCache();
  assert.equal(cold.getAudioFilePath(book.id, chapters[0].id, chapters[0].source.value), durablePath);
  await cold.clearAllCache();
  assert.equal(sizes.has(durablePath), false, 'in-app audio cleanup deletes migrated files');
  console.log('PASS audio migration, cold offline reuse after system cleanup and in-app cleanup');
  sizes.clear();
  const io = stubs['@kit.CoreFileKit'].fileIo;
  io.listFile = async () => [...sizes.keys()].map(filename => path.posix.basename(filename));
  io.stat = async filename => ({ size: sizes.get(filename), mtime: filename.includes('old') ? 1 : 2,
    isDirectory: () => false });
  const pinned = '/files/chap_playing.mp3';
  const old = '/files/chap_old.mp3';
  const part = '/files/chap_active.mp3.part';
  const publishing = '/files/chap_publishing.mp3';
  sizes.set(pinned, 3 * 1024 ** 3);
  sizes.set(old, 3 * 1024 ** 3);
  sizes.set(part, 3 * 1024 ** 3);
  sizes.set(publishing, 100 * 1024 * 1024);
  expiring.setPlayingFile(pinned);
  expiring.activeFilePaths.add(publishing);
  await expiring.enforceDiskCacheLimit();
  assert.equal(sizes.has(old), false);
  for (const protectedPath of [pinned, part, publishing]) assert.equal(sizes.has(protectedPath), true);
  console.log('PASS disk eviction excludes partial, playing and publishing files');

  // Exercise the settings cleanup against real files, including cold-start files
  // that have no in-memory cache entry and a recoverable deletion failure.
  const temporary = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'audio-cache-cleanup-'));
  const filesDir = path.join(temporary, 'files').replaceAll('\\', '/');
  const cacheDir = path.join(temporary, 'cache').replaceAll('\\', '/');
  fs.mkdirSync(filesDir);
  fs.mkdirSync(cacheDir);
  const originalIo = { ...io };
  const unlinkCalls = [];
  const pendingUnlinks = [];
  let failingPath = `${filesDir}/chap_failure.mp3`;
  try {
    io.listFile = dir => fs.promises.readdir(dir);
    io.stat = filename => fs.promises.stat(filename);
    io.statSync = filename => fs.statSync(filename);
    io.access = async filename => fs.existsSync(filename);
    io.unlink = filename => {
      unlinkCalls.push(filename);
      if (filename === failingPath) return Promise.reject(new Error('file busy'));
      const task = fs.promises.unlink(filename);
      pendingUnlinks.push(task);
      return task;
    };
    const fixtureFiles = new Map([
      ['chap_indexed.mp3', 4096], ['chap_cold.mp3', 8192], ['chap_playing.mp3', 2048],
      ['chap_publishing.mp3', 3072], ['chap_failure.mp3', 5120], ['chap_active.mp3.part', 1024],
      ['imported.mp3', 2048]
    ]);
    for (const [name, bytes] of fixtureFiles) fs.writeFileSync(`${filesDir}/${name}`, Buffer.alloc(bytes));
    fs.mkdirSync(`${filesDir}/chap_directory.mp3`);
    fs.writeFileSync(`${filesDir}/chap_directory.mp3/keep`, 'directory');
    fs.mkdirSync(`${filesDir}/downloads`);
    fs.writeFileSync(`${filesDir}/downloads/manual.mp3`, Buffer.alloc(8192));
    const cleanup = new ChapterCacheService();
    cleanup.appContext = { filesDir, cacheDir };
    cleanup.setPlayingFile(`${filesDir}/chap_playing.mp3`);
    cleanup.activeFilePaths.add(`${filesDir}/chap_publishing.mp3`);
    for (const id of ['indexed', 'indexed-alias']) {
      cleanup.fileCache.set(id, { filePath: `${filesDir}/chap_indexed.mp3`, bytes: 99, timestamp: 1, pageUrl: id });
    }
    cleanup.fileCache.set('playing', { filePath: cleanup.playingFilePath, bytes: 2048, timestamp: 1, pageUrl: 'playing' });
    assert.equal(ChapterCacheService.CACHE_LIMIT, 5 * 1024 ** 3);
    assert.equal(await cleanup.getCacheUsage(), 22528, 'Usage reads the actual complete audio files, not stale index sizes');
    const vanishingPath = `${filesDir}/chap_vanishing.mp3`;
    fs.writeFileSync(vanishingPath, Buffer.alloc(1536));
    io.stat = filename => {
      if (filename === vanishingPath && fs.existsSync(filename)) fs.unlinkSync(filename);
      return fs.promises.stat(filename);
    };
    const clearing = cleanup.clearAllCache();
    assert.equal(cleanup.clearAllCache(), clearing, 'Concurrent cleanup requests share a single disk operation');
    const cleanupResult = await clearing;
    assert.deepEqual({ ...cleanupResult }, { deleted: 2, failed: 1, releasedBytes: 12288, protectedCount: 2 });
    assert.equal(fs.existsSync(vanishingPath), false, 'Concurrent cancellation is not reported as a failed deletion');
    assert.equal(unlinkCalls.filter(filename => filename.endsWith('/chap_indexed.mp3')).length, 1);
    assert.equal(cleanup.fileCache.has('indexed'), false);
    assert.equal(cleanup.fileCache.has('indexed-alias'), false);
    assert.equal(cleanup.fileCache.has('playing'), true);
    for (const name of ['chap_playing.mp3', 'chap_publishing.mp3', 'chap_failure.mp3',
      'chap_active.mp3.part', 'imported.mp3', 'chap_directory.mp3/keep', 'downloads/manual.mp3']) {
      assert.equal(fs.existsSync(`${filesDir}/${name}`), true, `${name} must be retained`);
    }
    assert.equal(await cleanup.getCacheUsage(), 10240);
    cleanup.setPlayingFile();
    cleanup.activeFilePaths.clear();
    failingPath = '';
    const retried = await cleanup.clearAllCache();
    assert.deepEqual({ ...retried }, { deleted: 3, failed: 0, releasedBytes: 10240, protectedCount: 0 });
    assert.equal(await cleanup.getCacheUsage(), 0);
    console.log('PASS real audio cleanup counts bytes once, retains playing/publishing files and downloads, and reports failed deletions');

    // A transport can finish publishing after cancellation; it must not restore
    // the cleared generation or remove a file that playback has already taken.
    for (const playingAfterCancel of [false, true]) {
      const lateBook = makeBook(`late-clear-${playingAfterCancel}`);
      const lateChapter = lateBook.chapters[0];
      const downloadTask = cleanup.downloadFile(lateBook, lateChapter, 'https://cdn.invalid/late-clear.mp3');
      await settle();
      const lateTransfer = transfers.at(-1);
      lateTransfer.cancel = () => { lateTransfer.cancelled = true; };
      await cleanup.clearAllCache();
      assert.equal(lateTransfer.cancelled, true);
      const finalPath = lateTransfer.options.finalPath;
      if (playingAfterCancel) cleanup.setPlayingFile(finalPath);
      fs.writeFileSync(finalPath, Buffer.alloc(4096));
      lateTransfer.finish(4096);
      await downloadTask;
      await Promise.all(pendingUnlinks);
      assert.equal(cleanup.fileCache.has(lateChapter.id), false, 'Late completion cannot repopulate the cleared cache index');
      assert.equal(fs.existsSync(finalPath), playingAfterCancel);
    }
    console.log('PASS clear cancellation ignores late publication and protects playback takeover');
    io.listFile = async () => { throw new Error('storage unavailable'); };
    await assert.rejects(cleanup.getCacheUsage(), /storage unavailable/);
    await assert.rejects(cleanup.clearAllCache(), /storage unavailable/);
    assert.equal(cleanup.cacheCleanupTask, null, 'A failed scan releases cleanup state for retry');
  } finally {
    Object.assign(io, originalIo);
    fs.rmSync(temporary, { recursive: true, force: true });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
