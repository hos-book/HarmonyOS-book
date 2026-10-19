// Run the real AudioService with simulated platform events, without audio hardware.
// Usage: DEVECO_HOME=<installed IDE> node scripts/test-audio-commands.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ide = process.env.DEVECO_HOME || process.env.DEVECO_PATH;
if (!ide) throw new Error('Set DEVECO_HOME to the installed DevEco Studio directory');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = path.join(__dirname, '../entry/src/main/ets/service/AudioService.ets');
const code = ts.transpileModule(fs.readFileSync(source, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const flush = () => new Promise(resolve => setImmediate(resolve));
const chapterContextModule = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/service/rulesource/ChapterRuleContext.ts'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, { exports: chapterContextModule.exports, module: chapterContextModule });
const audio = {
  InterruptForceType: { INTERRUPT_FORCE: 0, INTERRUPT_SHARE: 1 },
  InterruptHint: { INTERRUPT_HINT_RESUME: 1, INTERRUPT_HINT_PAUSE: 2, INTERRUPT_HINT_STOP: 3 },
  InterruptMode: { SHARE_MODE: 0, INDEPENDENT_MODE: 1 },
  StreamUsage: { STREAM_USAGE_AUDIOBOOK: 14 },
  AudioStreamDeviceChangeReason: {
    REASON_UNKNOWN: 0, REASON_NEW_DEVICE_AVAILABLE: 1,
    REASON_OLD_DEVICE_UNAVAILABLE: 2, REASON_OVERRODE: 3
  }
};

class Watcher {
  armed = false;
  callback = null;
  arm(callback) { this.armed = true; this.callback = callback; }
  disarm() { this.armed = false; this.callback = null; }
  isArmed() { return this.armed; }
}

async function fixture(initialState = 'paused', realUsage = false) {
  const events = new Map();
  const usage = [];
  const usageTimers = new Map();
  const preloadTimers = new Map();
  let preloadTime = 0;
  let preloadTimerId = 1000000;
  let uptime = 0;
  let timerId = 0;
  const savedPositions = [];
  const widgetUpdates = [];
  const player = {
    state: initialState, duration: 180000, currentTime: 42000,
    plays: 0, pauses: 0, seeks: [],
    rates: [], setPlaybackRate(rate) { this.rates.push(rate); },
    on(name, callback) { events.set(name, callback); },
    off(name) { events.delete(name); },
    emit(name, ...values) { events.get(name)?.(...values); },
    transition(state) { this.state = state; this.emit('stateChange', state); },
    async play() { this.plays++; this.transition('playing'); },
    async pause() { this.pauses++; this.transition('paused'); },
    seek(position) { this.seeks.push(position); this.currentTime = position; },
    async release() { this.state = 'released'; }
  };
  const state = {
    isPlaying: initialState === 'playing', isLoading: initialState === 'initialized',
    sleepMode: 0, autoSleepEnabled: false, lastSleepMinutes: 30,
    progressMs: 42000, durationMs: 180000, speed: 1,
    currentBook: { id: 'book-1', chapters: [] },
    currentChapter: { id: 'chapter-1', duration: 180, source: { type: 'file', value: 'fixture' } }
  };
  const session = {
    callbacks: null,
    setCallbacks(callbacks) { this.callbacks = callbacks; },
    restoreAudioCallbacks() {}, async updateMetadata() {},
    async init() {}, async destroy() {}, async updateMetadataDuration() {}
  };
  const playbackStore = { setPlaying() {}, update() {} };
  const cacheCalls = [];
  const backgroundCalls = [];
  const background = {
    resumeAfterUserAction() { backgroundCalls.push('user-resume'); },
    async start() { backgroundCalls.push('start'); },
    async stop() { backgroundCalls.push('stop'); },
    isRunning() { return true; }
  };
  const mediaSources = [];
  const platformCompat = { supports: () => true };
  const cache = {
    getChapterDuration() { return 0; },
    clearChapter(id) { cacheCalls.push(`clear:${id}`); },
    suspendPreload() { cacheCalls.push('suspend'); },
    resumePreload() { cacheCalls.push('resume'); },
    ensureFileCached() { cacheCalls.push('current'); },
    rememberAudioRequest() { cacheCalls.push('remember'); },
    preloadAudioChapters(_book, _index, currentUrl) {
      cacheCalls.push('next');
      if (currentUrl) cacheCalls.push('current');
    },
    isPreloadEnabled() { return true; },
    getPendingAudioResolve() { return undefined; },
    waitForAudioFile: async () => null,
    getAudioUrl: () => null,
    getAudioFilePath: () => null,
    getAudioHeaders: () => ({}),
    setPlayingFile() {}
  };
  const coordinatorModule = { exports: {} };
  const coordinatorCode = ts.transpileModule(fs.readFileSync(
    path.join(path.dirname(source), 'PlaybackCoordinator.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(coordinatorCode, { module: coordinatorModule, exports: coordinatorModule.exports });
  const prefModule = { exports: {} };
  const prefCode = ts.transpileModule(fs.readFileSync(
    path.join(path.dirname(source), 'PreferenceService.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(prefCode, { module: prefModule, exports: prefModule.exports,
    require: name => name === '../model/GeneralSettings'
      ? { GeneralSettings: { current: { historyEnabled: true } } }
      : { ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: -1 } } } });
  const preference = prefModule.exports.PreferenceService;
  const preferenceValues = new Map();
  preference.ensureStore = async () => ({
    get: async (key, fallback) => preferenceValues.get(key) ?? fallback,
    put: async (key, value) => preferenceValues.set(key, value),
    delete: async key => preferenceValues.delete(key), flush: async () => {}
  });
  const modules = {
    './ReadingSessionService': { ReadingSessionService: { checkpoint() {}, end() {} }, SessionLocation: { audio: () => ({}) } },
    './LiveAudioService': { LiveAudioService: { isLive: async () => false } },
    './ChapterCacheService': { ChapterCacheService: { getInstance: () => cache } },
    './SourceDataService': { SourceDataService: { getSourceByUrl: async () => ({}) } },
    './BookSourceService': { BookSourceService: { prepareAudioChapter: async () => {} } },
    './builtin/WebViewAudioExtractor': { getWebViewAudioExtractor: () => ({ cancelPending() { cacheCalls.push('cancel-extractor'); } }) },
    './DownloadService': { DownloadService: { getInstance: () => ({ getDownloadedFilePath: () => null }) } },
    './PlaybackCoordinator': coordinatorModule.exports,
    '@kit.MediaKit': { media: { createAVPlayer: async () => player, SeekMode: { SEEK_PREV_SYNC: 0 },
      BufferingInfoType: { BUFFERING_START: 1, BUFFERING_END: 2 },
      createMediaSourceWithUrl(url, headers) {
        const source = { url, headers, offlineCache: false,
          enableOfflineCache(enable) { this.offlineCache = enable; } };
        mediaSources.push(source);
        return source;
      }
    } },
    '@kit.AudioKit': { audio },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
    '@kit.BasicServicesKit': { emitter: { emit() {} },
      systemDateTime: { TimeType: { STARTUP: 0 }, getUptime: () => uptime } },
    './StatsService': { StatsService: { addListenSeconds: async (seconds, book, endedAt) =>
      usage.push({ seconds, book, endedAt }) } },
    '@kit.AVSessionKit': { avSession: {} },
    '@kit.CoreFileKit': { fileIo: {} },
    '../utils/PlatformCompat': { PlatformCompat: platformCompat },
    '../model/PlayerState': { SleepMode: { Off: 0, Duration: 1, Chapters: 2 }, PlayMode: { Sequence: 0, SingleLoop: 1, ListLoop: 2 } },
    './ExternalMediaWatcher': { ExternalMediaWatcher: Watcher },
    './AVSessionService': { AVSessionService: { getInstance: () => session } },
    './PlaybackStore': { PlaybackStore: { getInstance: () => playbackStore } },
    './BackgroundTaskService': { BackgroundTaskService: background },
    './DiagnosticLogService': { DiagnosticLogService: { info() {}, failure() {} } },
    './DataService': { DataService: { async upsertCachedBook() {},
      resolveChapterIndex: (book, id) => book.chapters.findIndex(ch => ch.id === id) } },
    './PreferenceService': prefModule.exports,
    './WidgetUpdater': { WidgetUpdater: { async optimisticSetPlaying() {},
      async updatePlayerCard(state) {
        widgetUpdates.push({ bookId: state?.currentBook?.id, chapterId: state?.currentChapter?.id,
          playing: state?.isPlaying });
      }
    } }
  };
  const module = { exports: {} };
  const downloadPolicy = { exports: {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(
    path.join(path.dirname(source), 'DownloadPolicy.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { module: downloadPolicy, exports: downloadPolicy.exports });
  modules['./DownloadPolicy'] = downloadPolicy.exports;
  vm.runInNewContext(code, {
    module, exports: module.exports, console,
    setTimeout(callback, delay, ...args) {
      if (delay !== 8000) return setTimeout(callback, delay, ...args);
      const id = ++preloadTimerId;
      preloadTimers.set(id, { callback, due: preloadTime + delay });
      return id;
    },
    clearTimeout(id) { if (!preloadTimers.delete(id)) clearTimeout(id); },
    setInterval: realUsage ? callback => { const id = ++timerId; usageTimers.set(id, callback); return id; } : setInterval,
    clearInterval: realUsage ? id => usageTimers.delete(id) : clearInterval,
    require(name) {
      if (name === './rulesource/ChapterRuleContext') return chapterContextModule.exports;
      if (modules[name]) return modules[name];
      // Unused business dependencies remain unloaded; unexpected calls fail normally.
      if (name.startsWith('./') || name.startsWith('../model/')) return {};
      throw new Error(`Unexpected platform dependency: ${name}`);
    }
  }, { filename: source });
  const service = module.exports.AudioService.getInstance();
  service.state = state;
  service.playerSourceGeneration = service.playGen;
  service.context = {};
  service.persistHistory = async () => { savedPositions.push(state.progressMs); };
  service.syncPlaybackState = () => {};
  service.syncPlaybackStateNow = async () => {};
  if (!realUsage) {
    service.startTick = () => {};
    service.stopTick = () => {};
  }
  service.initAVSession();
  await service.ensurePlayer();
  return { service, player, state, session, savedPositions, events, preference, cacheCalls, widgetUpdates,
    cache, mediaSources, platformCompat, usage, usageTimers, backgroundCalls, background,
    preloadTimers,
    advancePreload(ms) {
      preloadTime += ms;
      for (const [id, timer] of preloadTimers) {
        if (timer.due > preloadTime) continue;
        preloadTimers.delete(id);
        timer.callback();
      }
    },
    advance: ms => { uptime += ms; } };
}

let passed = 0;
async function check(name, test) {
  await test();
  console.log(`PASS ${name}`);
  passed++;
}

(async () => {
  await check('global speed defaults only new books, survives reload, and never overwrites per-book speed', async () => {
    const f = await fixture();
    f.service.persistHistory = Object.getPrototypeOf(f.service).persistHistory;
    const chapter = { id: 'a-1', title: '第一章', duration: 180, source: { type: 'file', value: '/a.mp3' } };
    const book = { id: 'a', chapters: [chapter] };
    const nextChapter = { ...chapter, id: 'a-2' };
    book.chapters.push(nextChapter);
    f.state.currentBook = null;
    f.state.currentChapter = null;
    assert.equal(await f.preference.getDefaultPlaybackSpeed(), 1);
    await f.preference.setDefaultPlaybackSpeed(1.5);
    await f.service.flushBeforeSwitch(book, chapter);
    assert.equal(f.state.speed, 1.5);
    f.state.currentBook = book;
    f.state.currentChapter = chapter;
    await f.service.setSpeed(1.8);
    assert.equal((await f.preference.getProgress('a')).speed, 1.8);
    assert.equal(await f.preference.getDefaultPlaybackSpeed(), 1.5);
    await f.preference.setDefaultPlaybackSpeed(2);
    assert.equal(f.state.speed, 1.8, 'Changing global speed must not change current playback');
    await f.service.flushBeforeSwitch(book, nextChapter);
    assert.equal(f.state.speed, 1.8, 'Chapter switches keep the current book speed');
    const other = { id: 'b', chapters: [chapter] };
    await f.service.flushBeforeSwitch(other, chapter);
    assert.equal(f.state.speed, 2, 'Another new book uses the new global default');
    f.state.currentBook = other;
    await f.service.setSpeed(1);
    assert.equal(await f.preference.getDefaultPlaybackSpeed(), 2, 'Resetting one book to 1x is local');
    f.preference.progressMemo.clear();
    f.state.currentBook = null;
    f.state.currentChapter = null;
    await f.service.flushBeforeSwitch(book, chapter);
    assert.equal(f.state.speed, 1.8, 'Cold restore reads the saved per-book value');
    await f.service.flushBeforeSwitch(other, chapter);
    assert.equal(f.state.speed, 1, 'An explicit 1x must override the global default');
  });
  await check('missing or invalid old speed uses global default and failed global saves roll back', async () => {
    const f = await fixture();
    f.state.currentBook = null;
    f.state.currentChapter = null;
    await f.preference.setDefaultPlaybackSpeed(1.25);
    const chapter = { id: 'old-1', duration: 180 };
    for (const speed of [undefined, null, 0, -1, 'fast']) {
      await f.preference.saveProgress({ bookId: 'old', chapterId: chapter.id, speed });
      f.preference.progressMemo.clear();
      await f.service.flushBeforeSwitch({ id: 'old', chapters: [chapter] }, chapter);
      assert.equal(f.state.speed, 1.25);
    }
    const store = await f.preference.ensureStore();
    f.preference.ensureStore = async () => ({ ...store, flush: async () => { throw new Error('disk full'); } });
    await assert.rejects(f.preference.setDefaultPlaybackSpeed(2), /disk full/);
    assert.equal(await f.preference.getDefaultPlaybackSpeed(), 1.25);
    f.preference.ensureStore = async () => store;
    for (const [input, expected] of [[NaN, 1], [Infinity, 1], [-1, 1], [0.1, 0.5], [4, 3], [1.26, 1.25]]) {
      await f.preference.setDefaultPlaybackSpeed(input);
      assert.equal(await f.preference.getDefaultPlaybackSpeed(), expected);
    }
  });
  await check('widget play restores a lost background task even while AVPlayer still reports playing', async () => {
    const f = await fixture('playing');
    f.background.isRunning = () => false;
    await f.service.play();
    assert.ok(f.backgroundCalls.includes('start'), 'A muted playing renderer may never send another playing event');
    assert.equal(f.player.plays, 0, 'The existing stream must not restart');
  });
  await check('background eligibility is acquired before resuming audio', async () => {
    const f = await fixture('paused');
    let complete;
    let acquired = false;
    f.background.start = () => new Promise(resolve => {
      complete = () => { acquired = true; resolve(); };
    });
    const resume = f.service.play();
    await flush();
    assert.equal(f.player.plays, 0, 'Do not play first and request background eligibility afterwards');
    assert.equal(typeof complete, 'function');
    complete();
    await resume;
    assert.equal(acquired, true);
    assert.equal(f.player.plays, 1);
  });
  await check('pause wins while background eligibility is being acquired', async () => {
    const f = await fixture('paused');
    let complete;
    f.background.start = () => new Promise(resolve => { complete = resolve; });
    const resume = f.service.play();
    await flush();
    await f.service.pause('widget');
    complete();
    await resume;
    assert.equal(f.player.plays, 0);
    assert.ok(f.backgroundCalls.includes('stop'));
  });
  await check('simultaneous widget and lock-screen play share one pending AVPlayer operation', async () => {
    const f = await fixture('paused');
    let complete;
    f.player.play = async () => {
      f.player.plays++;
      await new Promise(resolve => { complete = resolve; });
      f.player.transition('playing');
    };
    const first = f.service.play();
    const second = f.service.play();
    await flush();
    assert.equal(f.player.plays, 1);
    complete();
    await Promise.all([first, second]);
  });
  await check('rejected prepare or play callbacks leave playback stopped without an unhandled rejection', async () => {
    for (const operation of ['prepare', 'play']) {
      const f = await fixture('initialized');
      f.player[operation] = async () => { throw Object.assign(new Error('renderer unavailable'), { code: 5400102 }); };
      f.player.transition(operation === 'prepare' ? 'initialized' : 'prepared');
      await flush();
      assert.equal(f.state.isPlaying, false);
      assert.equal(f.state.isLoading, false);
      assert.ok(f.backgroundCalls.includes('stop'));
    }
  });
  await check('old prepared, time and error callbacks cannot mutate a chapter while reset is pending', async () => {
    const f = await fixture('initialized');
    let finishReset;
    f.player.reset = () => new Promise(resolve => { finishReset = resolve; });
    const chapter = { id: 'new-chapter', source: { type: 'rawfile', value: 'new.mp3' } };
    const book = { id: 'new-book', chapters: [chapter] };
    f.service.resolveAudioUrl = async () => ({ success: true, headers: {} });
    f.service.syncCastMediaSource = () => {};
    f.service.applySource = async () => true;
    const switching = f.service.doPlayChapter(book, chapter, 9000);
    assert.equal(f.service.playerSourceGeneration, -1);
    f.player.transition('prepared');
    f.player.emit('timeUpdate', 1);
    f.player.emit('error', { code: 5400102, message: 'old source' });
    await flush();
    assert.equal(f.player.plays, 0);
    assert.equal(f.state.progressMs, 42000);
    assert.equal(f.state.durationMs, 180000);
    f.player.state = 'idle';
    finishReset();
    await switching;
    assert.equal(f.state.currentChapter, chapter);
    assert.equal(f.state.progressMs, 9000);
    assert.equal(f.state.isLoading, true);
  });
  await check('switching books updates widget before audio URL resolution finishes', async () => {
    const f = await fixture('idle');
    f.player.reset = async () => {};
    const chapter = { id: 'new-chapter', source: { type: 'rawfile', value: 'new.mp3' } };
    const book = { id: 'new-book', chapters: [chapter] };
    let finishResolve;
    f.service.resolveAudioUrl = () => new Promise(resolve => { finishResolve = resolve; });
    f.service.syncCastMediaSource = () => {};
    f.service.applySource = async () => true;
    const switching = f.service.doPlayChapter(book, chapter, 0);
    await flush();
    assert.deepEqual(f.widgetUpdates.at(-1), { bookId: 'new-book', chapterId: 'new-chapter', playing: false });
    finishResolve({ success: true, headers: {} });
    await switching;
  });
  await check('a start waiting for background eligibility cannot play a newly reset player', async () => {
    const f = await fixture('initialized');
    let ready;
    f.background.start = () => new Promise(resolve => { ready = resolve; });
    f.player.transition('prepared');
    await flush();
    assert.equal(typeof ready, 'function');
    f.service.playGen++;
    f.service.playerSourceGeneration = -1;
    f.player.state = 'idle';
    f.state.isLoading = true;
    ready();
    await flush();
    assert.equal(f.player.plays, 0);
    assert.equal(f.state.isLoading, true, 'Cancelled old start must preserve the new loading indicator');
  });
  await check('a newly assigned source still prepares and plays after invalidating the old source', async () => {
    const f = await fixture('paused');
    f.player.reset = async () => { f.player.transition('idle'); };
    f.player.setMediaSource = async () => { f.player.transition('initialized'); };
    f.player.prepare = async () => { f.player.transition('prepared'); };
    f.service.resolveAudioUrl = async () => ({ success: true, headers: {} });
    f.service.syncCastMediaSource = () => {};
    const chapter = { id: 'new', source: { type: 'url', value: 'https://cdn.invalid/new.m4a' } };
    const book = { id: 'new-book', chapters: [chapter] };
    await f.service.doPlayChapter(book, chapter, 0);
    await flush();
    assert.equal(f.service.playerSourceGeneration, f.service.playGen);
    assert.equal(f.state.currentChapter, chapter);
    assert.equal(f.player.plays, 1);
    assert.equal(f.state.isLoading, false);
    assert.equal(f.state.isPlaying, true);
    assert.equal(f.cacheCalls.includes('next'), false, 'New source must not preload during the selection window');
    f.service.cancelPreloadStart();
  });
  await check('queued state events must agree with the current AVPlayer state', async () => {
    const f = await fixture('paused');
    f.events.get('stateChange')('prepared', 1);
    await flush();
    assert.equal(f.player.plays, 0);
    assert.equal(f.state.durationMs, 180000);
    f.player.state = 'idle';
    await f.service.playPlayer(f.player);
    assert.equal(f.player.plays, 0, 'Idle is not a legal play state');
  });
  await check('widget resume re-arms background recovery and restarts the preload window', async () => {
    const f = await fixture('paused');
    f.state.currentBook.chapters = [f.state.currentChapter];
    await f.service.play();
    await new Promise(resolve => setTimeout(resolve, 10));
    f.advancePreload(8000);
    assert.equal(f.backgroundCalls[0], 'user-resume');
    assert.ok(f.backgroundCalls.includes('start'));
    assert.ok(f.cacheCalls.includes('next'));
    const count = f.backgroundCalls.filter(call => call === 'user-resume').length;
    f.service.prepareSleepForPlayback(f.state.currentBook, f.state.currentChapter, true);
    assert.equal(f.backgroundCalls.filter(call => call === 'user-resume').length, count,
      'Automatic continuation must not override a later system suspension');
  });
  await check('cached chapter completion keeps background playback until the next network chapter starts', async () => {
    const f = await fixture('playing');
    const next = { id: 'chapter-2', source: { type: 'url', value: 'https://source.invalid/2' } };
    f.state.currentBook.chapters = [f.state.currentChapter, next];
    let finish;
    f.service.playChapter = async (book, chapter) => {
      assert.equal(chapter, next);
      f.state.isLoading = true;
      await new Promise(resolve => { finish = resolve; });
      f.state.currentChapter = chapter;
      f.player.transition('playing');
    };
    f.player.transition('completed');
    await flush();
    assert.equal(f.backgroundCalls.includes('stop'), false, 'Do not release while resolving an uncached chapter');
    finish(); await flush();
    await new Promise(resolve => setTimeout(resolve, 10));
    f.advancePreload(8000);
    assert.equal(f.state.isPlaying, true);
    assert.equal(f.backgroundCalls.includes('stop'), false);
    assert.ok(f.cacheCalls.includes('next'), 'New chapter schedules the next preload window');
    f.player.transition('completed'); await flush();
    assert.ok(f.backgroundCalls.includes('stop'), 'Real book end must release playback ownership');
  });
  await check('failed automatic continuation releases background playback instead of leaking a task', async () => {
    const f = await fixture('playing');
    f.state.currentBook.chapters = [f.state.currentChapter, { id: 'chapter-2' }];
    f.service.playChapter = async () => { throw new Error('source unavailable'); };
    f.player.transition('completed'); await flush();
    assert.ok(f.backgroundCalls.includes('stop'));
    assert.equal(f.state.isPlaying, false);
  });
  await check('automatic sleep persists last duration, starts on explicit playback and never resets active countdown', async () => {
    const f = await fixture('paused');
    try {
      assert.equal(f.state.autoSleepEnabled, false);
      assert.equal(f.state.lastSleepMinutes, 30);
      assert.equal(f.service.setSleepTimer(45), true);
      await flush();
      f.service.cancelSleepTimer();
      assert.equal(await f.preference.getLastSleepMinutes(), 45);
      await f.service.setAutoSleepEnabled(true);
      assert.equal(await f.preference.getAutoSleepEnabled(), true);
      assert.equal(f.state.sleepMode, 0, 'enabling while paused does not start countdown');
      await f.service.play();
      assert.equal(f.state.sleepMode, 1);
      assert.equal(f.state.sleepMinutes, 45);
      const deadline = f.service.sleepEndTime;
      f.service.prepareSleepForPlayback(f.state.currentBook, f.state.currentChapter, true);
      f.player.transition('playing');
      assert.equal(f.service.sleepEndTime, deadline, 'natural next chapter keeps original deadline');
      await f.service.pause();
      await f.service.play();
      assert.equal(f.service.sleepEndTime, deadline, 'pause/resume does not extend active timer');
      f.service.cancelSleepTimer();
      f.service.prepareSleepForPlayback(f.state.currentBook, f.state.currentChapter, true);
      f.player.transition('playing');
      assert.equal(f.state.sleepMode, 0, 'cancel remains effective through automatic chapters');
      await f.service.pause();
      await f.service.play();
      assert.equal(f.state.sleepMinutes, 45, 'next explicit playback rearms remembered timer');
      await f.service.setAutoSleepEnabled(false);
      f.service.cancelSleepTimer();
      await f.service.pause();
      await f.service.play();
      assert.equal(f.state.sleepMode, 0, 'disabled preference leaves playback untimed');
      await f.preference.setLastSleepMinutes(0);
      assert.equal(await f.preference.getLastSleepMinutes(), 45, 'cancel/invalid values never erase last duration');
      f.service.sleepPreferencesReady = null;
      await f.preference.setAutoSleepEnabled(true);
      await f.service.loadSleepPreferences();
      assert.equal(f.state.autoSleepEnabled, true);
      assert.equal(f.state.lastSleepMinutes, 45, 'preferences reload restores toggle and duration');
    } finally { f.service.cancelSleepTimer(); }
  });
  await check('automatic sleep restores chapter mode and original count across short books and preference reloads', async () => {
    const f = await fixture('paused');
    try {
      f.state.currentBook.chapters = Array.from({ length: 7 }, (_, i) => ({ id: `ch-${i}`, title: `第${i + 1}章`, duration: 180, source: { type: 'file', value: 'fixture' } }));
      f.state.currentChapter = f.state.currentBook.chapters[0];
      assert.equal(f.service.setSleepChapters(5), true);
      await flush();
      assert.equal(await f.preference.getLastSleepMode(), 2);
      assert.equal(await f.preference.getLastSleepChapters(), 5);
      f.service.cancelSleepTimer();
      f.service.sleepPreferencesReady = null;
      await f.service.loadSleepPreferences();
      await f.service.setAutoSleepEnabled(true);
      await f.service.play();
      assert.equal(f.state.sleepMode, 2);
      assert.equal(f.state.sleepChaptersRemaining, 5);
      assert.equal(f.state.sleepTargetTitle, '第5章');
      f.state.sleepChaptersRemaining = 4;
      f.service.prepareSleepForPlayback(f.state.currentBook, f.state.currentChapter, true);
      f.player.transition('playing');
      assert.equal(f.state.sleepChaptersRemaining, 4, 'automatic continuation does not reset chapter countdown');
      f.service.cancelSleepTimer();
      await f.service.pause();
      f.state.currentChapter = f.state.currentBook.chapters[5];
      await f.service.play();
      assert.equal(f.state.sleepChaptersRemaining, 2, 'short book stops at last available chapter');
      assert.equal(f.state.lastSleepChapters, 5);
      assert.equal(await f.preference.getLastSleepChapters(), 5, 'clamping never overwrites remembered five chapters');
      assert.equal(f.service.setSleepTimer(15), true);
      await flush();
      assert.equal(await f.preference.getLastSleepMode(), 1);
      f.service.cancelSleepTimer();
      await f.service.pause();
      await f.service.play();
      assert.equal(f.state.sleepMode, 1);
      assert.equal(f.state.sleepMinutes, 15, 'switching back to minutes replaces the remembered mode');
    } finally { f.service.cancelSleepTimer(); }
  });
  await check('manual reload bypasses same-chapter reuse and retains interrupted position', async () => {
    const f = await fixture('playing');
    const book = f.state.currentBook;
    const chapter = f.state.currentChapter;
    book.sourceUrl = 'imported-source';
    chapter.originSourceValue = 'https://source.test/chapter';
    chapter.source = { type: 'file', value: '/cached-audio' };
    let reloaded;
    let reused = false;
    f.service.canReuseSameChapter = () => true;
    f.service.seekAndPlaySameChapter = async () => { reused = true; };
    f.service.flushBeforeSwitch = async () => {};
    f.service.doPlayChapter = async (...args) => { reloaded = args; };
    await f.service.playChapterAndSeek(book, chapter, 42000, false, true);
    assert.equal(reused, false);
    assert.equal(reloaded[2], 42000);
    assert.equal(reloaded[3], true);
    assert.equal(chapter.source.value, chapter.originSourceValue);
    assert.ok(f.cacheCalls.includes('clear:chapter-1'));
    await f.service.playChapterAndSeek(book, chapter, 42000);
    assert.equal(reused, true);
  });
  await check('HLS, indexed containers and opaque proxies bypass offline cache; known audio keeps caching', async () => {
    const f = await fixture();
    const loaded = [];
    f.player.setMediaSource = async source => { loaded.push(source); };
    const headers = { 'User-Agent': 'radio-fixture', Referer: 'https://radio.test/' };
    for (const live of [true, false]) {
      f.service.liveSource = live;
      assert.equal(await f.service.applySource(f.player,
        { type: 'url', value: 'https://radio.test/stream.m3u8?session=fixture' }, headers), true);
      assert.equal(loaded.at(-1).offlineCache, false);
      assert.equal(loaded.at(-1).headers, headers);
    }
    f.service.liveSource = true;
    await f.service.applySource(f.player, { type: 'url', value: 'https://radio.test/live' });
    assert.equal(loaded.at(-1).offlineCache, false);
    f.service.liveSource = false;
    for (const suffix of ['chapter.m4a', 'chapter.M4A?token=test', 'chapter.m4b', 'chapter.mp4', 'chapter.mov',
      'api.php?token=test', 'stream', 'api.php?filename=chapter.mp3', 'stream#chapter.mp3']) {
      await f.service.applySource(f.player, { type: 'url', value: 'https://audio.test/' + suffix }, headers);
      assert.equal(loaded.at(-1).offlineCache, false, suffix);
      assert.equal(loaded.at(-1).headers, headers);
    }
    await f.service.applySource(f.player, { type: 'url', value: 'https://radio.test/chapter.mp3' });
    assert.equal(loaded.at(-1).offlineCache, true);
    f.platformCompat.supports = () => false;
    await f.service.applySource(f.player, { type: 'url', value: 'https://radio.test/chapter.mp3' });
    assert.equal(loaded.at(-1).offlineCache, false);
  });
  await check('HLS rolling-window duration remains live and normal audio replaces stalled radio', async () => {
    const f = await fixture('initialized');
    f.service.liveSource = true;
    f.player.duration = 60000;
    f.state.currentChapter.source = { type: 'url', value: 'https://radio.test/live.m3u8' };
    f.player.transition('prepared');
    assert.equal(f.state.isLive, true);
    assert.equal(f.state.durationMs, 0);
    const oldStateCallback = f.events.get('stateChange');
    f.player.reset = () => new Promise(() => {});
    f.player.release = () => new Promise(() => {});
    const nextPlayer = { state: 'idle' };
    f.service.ensurePlayer = async () => { f.service.player = nextPlayer; return nextPlayer; };
    f.service.isFastSwitchPath = () => true;
    f.service.resolveAudioUrl = async () => ({ success: true, headers: {} });
    f.service.syncCastMediaSource = () => {};
    f.service.applySource = async () => true;
    const chapter = { id: 'other-chapter', source: { type: 'file', value: '/audio.mp3' } };
    const book = { id: 'other-book', chapters: [chapter] };
    await Promise.race([f.service.doPlayChapter(book, chapter, 0),
      new Promise((_, reject) => setTimeout(() => reject(new Error('radio blocked switch')), 1000))]);
    assert.equal(f.state.currentBook.id, 'other-book');
    assert.equal(f.state.isLive, false);
    oldStateCallback('prepared', 1);
    assert.equal(f.state.isLive, false);
    assert.equal(f.state.currentBook.id, 'other-book');
  });
  await check('live recovery obeys generation and pause and never seeks old stream', async () => {
    const f = await fixture('playing');
    f.state.isLive = true;
    f.service.liveSource = true;
    let reconnects = 0;
    f.service.doPlayChapter = async (_book, _chapter, position) => {
      assert.equal(position, 0); reconnects++;
    };
    f.service.recoverLiveBuffer(f.player, f.service.playGen + 1);
    f.service.pauseRequested = true;
    f.service.recoverLiveBuffer(f.player, f.service.playGen);
    assert.equal(reconnects, 0);
    f.service.pauseRequested = false;
    f.service.recoverLiveBuffer(f.player, f.service.playGen);
    assert.equal(reconnects, 1);
    assert.equal(f.service.player, null);
    assert.deepEqual(f.player.seeks, []);
  });
  await check('live streams start without historical seek, speed or preloading', async () => {
    const f = await fixture('initialized');
    f.state.currentChapter.source = { type: 'url', value: 'https://radio.test/live.m3u8' };
    f.state.currentBook.chapters = [f.state.currentChapter];
    f.player.duration = -1;
    f.state.speed = 1.5;
    f.service.pendingSeek = 80000;
    f.service.resumeTargetMs = 80000;
    f.player.transition('prepared');
    await flush();
    assert.equal(f.player.plays, 1);
    assert.equal(f.state.isLive, true);
    assert.equal(f.state.durationMs, 0);
    assert.equal(f.service.resumeTargetMs, 0);
    await f.service.seek(10000);
    await f.service.seekAndPlaySameChapter(20000);
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.deepEqual(f.player.seeks, []);
    assert.deepEqual(f.cacheCalls, []);
  });
  await check('preload waits for eight stable seconds and obsolete tasks do not start', async () => {
    const f = await fixture('initialized');
    f.state.currentBook.chapters = [f.state.currentChapter];
    assert.deepEqual(f.cacheCalls, []);
    f.player.transition('prepared');
    await flush();
    assert.equal(f.player.plays, 1);
    assert.deepEqual(f.cacheCalls, []);
    f.advancePreload(7999);
    assert.deepEqual(f.cacheCalls, []);
    f.advancePreload(1);
    assert.deepEqual(f.cacheCalls, ['resume', 'next']);
    f.cacheCalls.length = 0;
    f.service.triggerPreload(f.state.currentBook, f.state.currentChapter);
    f.service.playGen++;
    f.advancePreload(8000);
    assert.deepEqual(f.cacheCalls, []);
  });
  await check('repeated preload events share one timer and pause retains the finite cache queue', async () => {
    const f = await fixture('playing');
    f.state.currentBook.chapters = [f.state.currentChapter];
    f.service.triggerPreload(f.state.currentBook, f.state.currentChapter);
    f.advancePreload(4000);
    f.service.triggerPreload(f.state.currentBook, f.state.currentChapter);
    assert.equal(f.preloadTimers.size, 1);
    f.advancePreload(4000);
    assert.deepEqual(f.cacheCalls, []);
    await f.service.pause();
    assert.equal(f.preloadTimers.size, 0);
    assert.ok(f.cacheCalls.includes('next'));
  });
  await check('foreground reuses pending resolution with headers and falls back after failure', async () => {
    for (const success of [true, false]) {
      const f = await fixture('paused');
      const chapter = { id: 'pending', source: { type: 'url', value: 'https://source.test/chapter' } };
      const book = { id: 'book', sourceUrl: 'https://source.test', chapters: [chapter] };
      let complete;
      let resolvedUrl = null;
      let foregroundCalls = 0;
      f.cache.getPendingAudioResolve = () => new Promise(resolve => { complete = () => {
        resolvedUrl = success ? 'https://cdn.test/shared.mp3' : null;
        resolve();
      }; });
      f.cache.getAudioUrl = () => resolvedUrl;
      f.cache.getAudioHeaders = () => ({ Referer: 'https://source.test' });
      f.service.resolveAudioRequestWithTimeout = async () => {
        foregroundCalls++;
        return { url: 'https://cdn.test/fallback.mp3', headers: {} };
      };
      let loadedHeaders;
      f.service.isFastSwitchPath = () => false;
      f.service.resetPlayerForSwitch = async () => {};
      f.service.syncCastMediaSource = () => {};
      f.service.applySource = async (_player, _source, headers) => { loadedHeaders = headers; return true; };
      const resultTask = f.service.doPlayChapter(book, chapter, 0);
      await flush();
      complete();
      await resultTask;
      assert.notEqual(loadedHeaders, undefined);
      assert.equal(f.cacheCalls.includes('cancel-extractor'), false, 'Keep the selected preparse sniffer alive');
      assert.equal(foregroundCalls, success ? 0 : 1);
      assert.equal(chapter.source.value, success ? 'https://cdn.test/shared.mp3' : 'https://cdn.test/fallback.mp3');
      if (success) assert.equal(loadedHeaders.Referer, 'https://source.test');
    }
  });

  await check('rapid chapter changes discard a pending foreground takeover', async () => {
    const f = await fixture('paused');
    const chapter = { id: 'obsolete', source: { type: 'url', value: 'https://source.test/old' } };
    const book = { id: 'book', sourceUrl: 'https://source.test', chapters: [chapter] };
    let complete;
    f.cache.getPendingAudioResolve = () => new Promise(resolve => { complete = resolve; });
    f.service.resolveAudioRequestWithTimeout = async () => { throw new Error('Obsolete chapter must not restart parsing'); };
    const pending = f.service.resolveAudioUrl(book, chapter);
    await flush();
    f.service.playGen++;
    complete();
    const result = await pending;
    assert.equal(result.success, false);
    assert.equal(chapter.source.value, 'https://source.test/old');
  });

  await check('online playback schedules next/current together and buffering gates transfers', async () => {
    const f = await fixture('playing');
    f.state.currentChapter.source = { type: 'url', value: 'https://cdn.invalid/current.mp3' };
    f.state.currentBook.chapters = [f.state.currentChapter];
    f.service.triggerPreload(f.state.currentBook, f.state.currentChapter);
    f.player.emit('bufferingUpdate', 1, 0);
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.deepEqual(f.cacheCalls, ['suspend'], 'Already scheduled prefetch must not run during buffering');
    f.cacheCalls.length = 0;
    f.player.emit('bufferingUpdate', 2, 0);
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.deepEqual(f.cacheCalls, [], 'Buffer recovery also waits for stable playback');
    f.advancePreload(8000);
    assert.deepEqual(f.cacheCalls, ['resume', 'next', 'current']);
    f.cacheCalls.length = 0;
    await f.service.pause();
    f.player.emit('bufferingUpdate', 2, 0);
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.equal(f.cacheCalls.includes('suspend'), false, 'Pausing preserves the cache queue');
    assert.ok(f.cacheCalls.includes('current'), 'Current audio must finish caching after pause');
    assert.ok(f.cacheCalls.includes('next'), 'Configured preload window must finish after pause');
    const callsAfterPause = f.cacheCalls.length;
    f.player.emit('bufferingUpdate', 1, 0);
    f.player.emit('bufferingUpdate', 2, 0);
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.equal(f.cacheCalls.length, callsAfterPause, 'Late buffering events must not cancel or extend paused downloads');
  });
  await check('sleep stop preserves cache work and never resumes playback', async () => {
    const f = await fixture('playing');
    f.state.currentChapter.source = { type: 'url', value: 'https://cdn.invalid/sleep.mp3' };
    f.state.currentBook.chapters = [f.state.currentChapter];
    f.service.finishSleep(false);
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.equal(f.player.state, 'paused');
    assert.equal(f.player.plays, 0);
    assert.equal(f.state.progressMs, 42000);
    assert.equal(f.cacheCalls.includes('suspend'), false);
    assert.ok(f.cacheCalls.includes('current'));
    assert.ok(f.cacheCalls.includes('next'));
    await f.service.release();
    assert.ok(f.cacheCalls.includes('suspend'), 'Explicit release still cancels background work');
  });
  await check('manual play recovers an errored player at the saved position', async () => {
    const f = await fixture('error');
    let resumedAt = -1;
    f.service.resumeFromState = async () => { resumedAt = f.state.progressMs; };
    await f.service.play();
    assert.equal(resumedAt, 42000);
  });
  await check('resolved URL errors retry at the interrupted position', async () => {
    const f = await fixture('playing');
    f.state.currentChapter.source = { type: 'url', value: 'https://example.invalid/audio' };
    f.state.currentChapter.originSourceValue = 'https://example.invalid/chapter';
    let retry = null;
    f.service.playChapterAndSeek = async (_book, _chapter, position, automatic) => { retry = { position, automatic }; };
    f.player.state = 'error';
    f.player.emit('error', { code: 5400103, message: 'simulated failure' });
    await flush();
    assert.deepEqual(retry, { position: 42000, automatic: true });
    retry = null;
    f.state.currentChapter.source = { type: 'url', value: 'https://example.invalid/audio-retry' };
    f.player.emit('error', { code: 5411002, message: 'connection timed out again' });
    await flush();
    assert.equal(retry, null, 'A second connection timeout must not restart the same chapter indefinitely');
  });
  await check('explicit pause prevents automatic URL-error recovery', async () => {
    const f = await fixture('playing');
    f.state.currentChapter.source = { type: 'url', value: 'https://example.invalid/audio' };
    f.state.currentChapter.originSourceValue = 'https://example.invalid/chapter';
    let retries = 0;
    f.service.playChapterAndSeek = async () => { retries++; };
    await f.service.pause();
    f.player.state = 'error';
    f.player.emit('error', { code: 5400103, message: 'simulated failure' });
    await flush();
    assert.equal(retries, 0);
    assert.equal(f.state.isPlaying, false);
  });
  await check('session play/pause are idempotent and preserve the current position', async () => {
    const f = await fixture();
    f.session.callbacks.onPlay();
    await flush();
    f.session.callbacks.onPlay();
    await flush();
    assert.equal(f.player.plays, 1);
    assert.equal(f.player.pauses, 0);
    assert.equal(f.state.progressMs, 42000);
    assert.equal(f.player.seeks.length, 0);
    f.session.callbacks.onPause();
    f.session.callbacks.onPause();
    await flush();
    assert.equal(f.player.pauses, 1);
    assert.equal(f.state.isPlaying, false);
  });
  await check('headset removal pauses; reconnection waits for a session play command', async () => {
    const f = await fixture('playing');
    f.player.emit('audioOutputDeviceChangeWithInfo', { changeReason: 2, devices: [] });
    await flush();
    assert.equal(f.player.state, 'paused');
    assert.ok(f.savedPositions.includes(42000));
    f.player.emit('audioOutputDeviceChangeWithInfo', { changeReason: 1, devices: [] });
    await flush();
    assert.equal(f.player.plays, 0);
    f.session.callbacks.onPlay();
    await flush();
    assert.equal(f.player.state, 'playing');
    assert.equal(f.player.currentTime, 42000);
  });
  await check('new, unknown and user-selected output routes do not pause playback', async () => {
    const f = await fixture('playing');
    for (const changeReason of [0, 1, 3]) {
      f.player.emit('audioOutputDeviceChangeWithInfo', { changeReason, devices: [] });
    }
    await flush();
    assert.equal(f.player.pauses, 0);
  });
  await check('pause during preparation blocks autoplay and resumes at the pending seek', async () => {
    const f = await fixture('initialized');
    f.service.pendingSeek = 42000;
    f.player.emit('audioOutputDeviceChangeWithInfo', { changeReason: 2, devices: [] });
    f.player.transition('prepared');
    await flush();
    assert.equal(f.player.plays, 0);
    assert.equal(f.state.isPlaying, false);
    assert.equal(f.state.isLoading, false);
    f.session.callbacks.onPlay();
    await flush();
    assert.equal(f.player.plays, 1);
    assert.equal(f.player.currentTime, 42000);
  });
  await check('a later pause wins over an already scheduled play', async () => {
    const f = await fixture();
    const play = f.service.play();
    await f.service.pause();
    await play;
    assert.equal(f.player.plays, 0);
    assert.equal(f.state.isPlaying, false);
  });
  await check('session pause cancels external-media and delayed focus recovery', async () => {
    const f = await fixture();
    f.service.pausedByFocus = true;
    f.service.pausedByExternalMedia = true;
    const watcher = f.service.externalWatcher;
    watcher.arm(() => f.service.resumeAfterExternalMedia());
    const staleCallback = watcher.callback;
    f.session.callbacks.onPause();
    f.player.emit('audioInterrupt', { forceType: 1, hintType: 1 });
    staleCallback();
    await flush();
    assert.equal(watcher.isArmed(), false);
    assert.equal(f.player.plays, 0);
  });
  await check('focus recovery still resumes when no explicit pause was requested', async () => {
    const f = await fixture();
    f.player.emit('audioInterrupt', { forceType: 0, hintType: 2 });
    f.player.emit('audioInterrupt', { forceType: 1, hintType: 1 });
    await flush();
    assert.equal(f.player.plays, 1);
  });
  await check('shared pause and stop actually silence playback and preserve position', async () => {
    for (const hintType of [2, 3]) {
      const f = await fixture('playing');
      f.player.emit('audioInterrupt', { forceType: 1, hintType });
      await flush();
      assert.equal(f.player.state, 'paused');
      assert.equal(f.player.pauses, 1);
      assert.equal(f.state.isPlaying, false);
      assert.equal(f.state.progressMs, 42000);
      assert.equal(f.service.pausedByFocus, hintType === 2);
      assert.equal(f.service.pausedByExternalMedia, hintType === 3);
    }
  });
  await check('focus loss blocks late playback and automatic URL-error recovery', async () => {
    for (const forceType of [0, 1]) {
      for (const hintType of [2, 3]) {
        const f = await fixture('playing');
        f.player.emit('audioInterrupt', { forceType, hintType });
        f.player.transition('playing');
        await flush();
        assert.equal(f.player.state, 'paused');
        assert.equal(f.state.isPlaying, false);
        f.state.currentChapter.source = { type: 'url', value: 'https://example.invalid/audio' };
        f.state.currentChapter.originSourceValue = 'https://example.invalid/chapter';
        let retries = 0;
        f.service.playChapterAndSeek = async () => { retries++; };
        f.player.state = 'error';
        f.player.emit('error', { code: 5400103, message: 'interrupted renderer failure' });
        await flush();
        assert.equal(retries, 0);
      }
    }
  });
  await check('a new interruption cancels focus and external-media recovery awaiting a player', async () => {
    for (const external of [false, true]) {
      const f = await fixture('stopped');
      let resolvePlayer;
      f.service.ensurePlayer = () => new Promise(resolve => { resolvePlayer = resolve; });
      let resumes = 0;
      f.service.resumeFromState = async () => { resumes++; };
      f.service.pausedByExternalMedia = external;
      const recovery = external ? f.service.resumeAfterExternalMedia() : f.service.resumeFromInterrupt();
      f.player.emit('audioInterrupt', { forceType: 0, hintType: 2 });
      resolvePlayer(f.player);
      await recovery;
      assert.equal(resumes, 0);
      assert.equal(f.player.plays, 0);
      assert.equal(f.service.pausedByFocus, true);
    }
  });
  await check('a late playing event is paused again after headset removal', async () => {
    const f = await fixture('initialized');
    await f.service.pause();
    f.player.transition('playing');
    await flush();
    assert.equal(f.player.state, 'paused');
    assert.equal(f.state.isPlaying, false);
  });
  await check('release unregisters the output device listener', async () => {
    const f = await fixture();
    await f.service.release();
    assert.equal(f.events.has('audioOutputDeviceChangeWithInfo'), false);
  });
  await check('saving intro 10s at 2s immediately seeks, including paused playback', async () => {
    for (const mode of ['playing', 'paused']) {
      const f = await fixture(mode);
      f.state.progressMs = f.player.currentTime = 2000;
      f.service.applySkipConfigNow('book-1', 10, 0);
      assert.deepEqual(f.player.seeks, [10000]);
      assert.equal(f.state.progressMs, 10000);
      assert.equal(f.player.state, mode);
    }
  });
  await check('saving intro 10s at 11s never rewinds and other books are untouched', async () => {
    const f = await fixture('playing');
    f.state.progressMs = f.player.currentTime = 11000;
    f.service.applySkipConfigNow('book-1', 10, 0);
    f.service.applySkipConfigNow('other-book', 30, 0);
    assert.deepEqual(f.player.seeks, []);
    assert.equal(f.state.progressMs, 11000);
    assert.equal(f.state.currentBook.skipIntro, 10);
  });
  await check('saving outro inside the current tail triggers chapter completion immediately', async () => {
    const f = await fixture('playing');
    f.state.progressMs = f.player.currentTime = 175000;
    let completed = 0;
    f.service.handleChapterEnd = () => completed++;
    f.service.applySkipConfigNow('book-1', 0, 10);
    assert.equal(completed, 1);
    assert.deepEqual(f.player.seeks, []);
  });
  await check('15-second seeking clamps at chapter boundaries and keeps paused playback paused', async () => {
    const f = await fixture('paused');
    f.state.progressMs = f.player.currentTime = 5000;
    await f.service.seekBy(-15000);
    assert.equal(f.state.progressMs, 0);
    f.state.progressMs = f.player.currentTime = 175000;
    await f.service.seekBy(15000);
    assert.equal(f.state.progressMs, 180000);
    assert.equal(f.player.plays, 0);
  });
  await check('sequential playback stops at the final chapter including skipped outro', async () => {
    for (const descending of [false, true]) {
      const f = await fixture('playing');
      const book = f.state.currentBook;
      book.chapters = ['a', 'b'].map(id => ({ id, title: id }));
      book.chaptersDescending = descending;
      book.skipOutro = 10;
      f.state.currentChapter = book.chapters[descending ? 0 : 1];
      f.state.playMode = 0;
      const played = [];
      f.service.playChapter = async (_book, chapter) => played.push(chapter.id);
      f.service.checkSkipOutro(175000);
      await flush();
      assert.equal(f.player.state, 'paused');
      assert.equal(f.state.isPlaying, false);
      assert.equal(played.length, 0);
      f.player.transition('completed');
      await flush();
      assert.equal(f.state.isPlaying, false);
      assert.equal(played.length, 0);
    }
  });
  await check('intro saved during loading updates the pending seek', async () => {
    const f = await fixture('initialized');
    f.state.progressMs = 2000;
    f.service.applySkipConfigNow('book-1', 10, 0);
    assert.equal(f.service.pendingSeek, 10000);
    assert.deepEqual(f.player.seeks, []);
  });
  await check('book order persists independently and all playback directions follow it', async () => {
    const f = await fixture('playing');
    const book = f.state.currentBook;
    book.chapters = ['a', 'b', 'c'].map(id => ({ id, title: id }));
    f.state.currentChapter = book.chapters[1];
    await f.preference.saveTocOrder(book.id, true);
    f.preference.tocOrderMemo.clear();
    await f.preference.applyTocOrder(book);
    assert.equal(book.chaptersDescending, true);
    assert.equal(f.preference.orderedChapters(book).map(ch => ch.id).join(','), 'c,b,a');
    assert.equal(book.chapters.map(ch => ch.id).join(','), 'a,b,c');
    assert.equal(f.preference.chapterStep({ id: 'other' }), 1);
    const played = [];
    f.service.playChapter = async (_book, chapter) => played.push(chapter.id);
    f.service.playChapterFromSavedProgress = f.service.playChapter;
    await f.service.playNext();
    await f.service.playPrevious();
    f.service.autoPlayNext();
    assert.deepEqual(played, ['a', 'c', 'a']);
    assert.equal(f.service.getAvailableSleepChapters(), 2);
    assert.equal(f.service.setSleepChapters(2), true);
    assert.equal(f.state.sleepTargetTitle, 'a');
    f.state.sleepMode = 0;
    f.state.currentChapter = book.chapters[0];
    await f.service.playNext();
    assert.equal(played.length, 3);
    f.state.playMode = 2;
    await f.service.playNext();
    assert.equal(played.at(-1), 'c');
    await f.preference.saveTocOrder(book.id, false);
    assert.equal(f.preference.chapterStep(book), 1);
    await f.service.playNext();
    assert.equal(played.at(-1), 'b');
  });
  await check('统计保留暂停尾段与零碎秒，缓冲和重复暂停不计时', async () => {
    const f = await fixture('playing', true);
    f.service.startTick();
    f.advance(7400);
    f.player.transition('paused');
    assert.equal(f.usage.reduce((n, item) => n + item.seconds, 0), 7);
    f.advance(60000);
    f.service.stopTick();
    f.state.isPlaying = true; f.player.state = 'playing';
    f.service.startTick();
    f.advance(600);
    f.player.emit('bufferingUpdate', 1, 0);
    assert.equal(f.usage.reduce((n, item) => n + item.seconds, 0), 8);
    f.advance(60000);
    f.player.emit('bufferingUpdate', 2, 0);
    f.advance(2000);
    f.player.transition('paused');
    assert.equal(f.usage.reduce((n, item) => n + item.seconds, 0), 10);
    assert.equal(f.usageTimers.size, 0);
  });
  await check('统计按实际经过时间结算，延迟回调和换书不串账', async () => {
    const f = await fixture('playing', true);
    f.service.startTick();
    f.advance(47000);
    f.state.progressMs += 3600000; f.state.speed = 2;
    for (const tick of f.usageTimers.values()) tick();
    assert.equal(f.usage[0].seconds, 47);
    f.advance(3000);
    f.state.currentBook = { id: 'book-2', chapters: [] };
    f.service.startTick();
    f.advance(4000);
    f.service.stopTick();
    assert.equal(f.usage.filter(item => item.book.bookId === 'book-1').reduce((n, item) => n + item.seconds, 0), 50);
    assert.equal(f.usage.filter(item => item.book.bookId === 'book-2').reduce((n, item) => n + item.seconds, 0), 4);
    assert.ok(f.usage.every(item => Number.isFinite(item.endedAt)));
    assert.equal(f.usageTimers.size, 0);
  });
  console.log(`${passed} audio command checks passed`);
})().catch(error => { console.error(error); process.exitCode = 1; });
