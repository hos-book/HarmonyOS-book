// Run the real network policy, transport guard and download scheduler with controlled network events.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const settings = { audioCacheWifiOnly: false };
const observers = [];
let kind = 'cellular';
let networkQueryFails = false;
let httpCreates = 0;
const requests = [];
const connection = {
  NetBearType: { BEARER_CELLULAR: 0, BEARER_WIFI: 1 },
  getDefaultNetSync() { if (networkQueryFails) throw new Error('network service unavailable'); return { netId: kind === 'none' ? 0 : 1 }; },
  getNetCapabilitiesSync() { return { bearerTypes: kind === 'wifi' ? [1] : kind === 'both' ? [0, 1] : [0] }; },
  createNetConnection() {
    const observer = { callbacks: new Map(), active: false,
      on(event, callback) { this.callbacks.set(event, callback); },
      register(callback) { this.active = true; callback(); },
      unregister(callback) { this.active = false; callback(); } };
    observers.push(observer);
    return observer;
  }
};
function network(next) {
  const previous = kind;
  kind = next;
  for (const observer of observers.filter(item => item.active)) {
    if (previous === 'wifi' && next !== 'wifi') observer.callbacks.get('netLost')?.({ netId: 1 });
    if (next === 'none') observer.callbacks.get('netUnavailable')?.();
    else observer.callbacks.get('netAvailable')?.({ netId: 1 });
  }
}
const files = new Set();
const storeRecords = [];
let autoCompleteDownload = true;
const transfers = [];
class QueueTransport {
  download(options) {
    this.options = options;
    transfers.push(this);
    return autoCompleteDownload ? Promise.resolve(6000) : new Promise((resolve, reject) => {
      this.resolve = resolve; this.reject = reject;
    });
  }
  cancel() { this.cancelled = true; this.reject?.(new Error('cancelled')); }
}
const stubs = {
  'model/GeneralSettings': { GeneralSettings: { current: settings } },
  '@kit.NetworkKit': { connection, http: { RequestMethod: { GET: 0 }, createHttp() {
    httpCreates++;
    const request = { destroyed: false, on() {}, requestInStream() {
      return new Promise((_resolve, reject) => { this.reject = reject; });
    }, destroy() { this.destroyed = true; this.reject?.(new Error('destroyed')); } };
    requests.push(request);
    return request;
  } } },
  '@kit.BasicServicesKit': { emitter: { emit() {} } },
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
  '@kit.MediaKit': { media: {} },
  '@kit.CryptoArchitectureKit': { cryptoFramework: {} },
  '@kit.ArkTS': { util: {} },
  '@kit.CoreFileKit': { statfs: { getFreeSizeSync: () => 1024 * 1024 * 1024 }, fileIo: {
    OpenMode: { READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
    access: async filename => files.has(filename),
    open: async filename => { files.add(filename); return { fd: 1 }; },
    openSync: filename => { files.add(filename); return { fd: 1 }; },
    closeSync() {}, unlinkSync: filename => files.delete(filename),
    close: async () => {}, unlink: async filename => files.delete(filename),
    statSync: () => ({ size: 6000 })
  } },
  'service/DownloadNotificationService': { DownloadNotificationService: {
    setContext() {}, requestPermission: async () => {}, publish: async () => {}, cancel: async () => {}
  } },
  'service/BackgroundTaskService': { BackgroundTaskService: {
    startDataTransfer: async () => {}, stopDataTransfer: async () => {}, isRunning: () => true, hasMode: () => true
  } },
  'service/PreferenceService': { PreferenceService: {} },
  'service/SourceDataService': { SourceDataService: { getSourceByUrl: async () => ({}) } },
  'service/BookSourceService': { BookSourceService: {
    prepareAudioChapter: async () => {}, resolveAudioRequest: async (_source, url) => ({ url: url + '.mp3', headers: {}, resolved: true })
  } },
  'service/DataService': { DataService: { getBookById: async () => null } },
  'utils/SearchCache': { SearchCache: { get: () => undefined } },
  'service/AudioDownloadTransport': { AudioDownloadTransport: QueueTransport }
};
const modules = new Map();
function load(name, forceReal = false) {
  if (!forceReal && stubs[name]) return stubs[name];
  const key = forceReal ? name + ':real' : name;
  if (modules.has(key)) return modules.get(key).exports;
  const module = { exports: {} };
  modules.set(key, module);
  const filename = ['.ets', '.ts'].map(ext => path.join(root, name + ext)).find(fs.existsSync);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, console, setTimeout, clearTimeout, setInterval, clearInterval,
    require: dependency => load(dependency.startsWith('.')
      ? path.posix.normalize(path.posix.join(path.posix.dirname(name), dependency)) : dependency)
  }, { filename });
  return module.exports;
}
const { DownloadPolicy } = load('service/DownloadPolicy');
function recalculate(record) {
  record.downloadedCount = record.chapters.filter(chapter => chapter.status === 'completed').length;
  record.failedCount = record.chapters.filter(chapter => chapter.status === 'failed').length;
  record.totalBytes = record.chapters.reduce((sum, chapter) => sum + chapter.bytes, 0);
  record.status = DownloadPolicy.deriveBookStatus(record.status, record.chapters.map(chapter => chapter.status));
}
const store = {
  init: async () => {}, setContext() {}, normalizeInterruptedTasks: async () => {},
  getBooksSync: () => storeRecords, getBooks: async () => storeRecords,
  getBookSync: id => storeRecords.find(record => record.bookId === id),
  getBook: async id => store.getBookSync(id),
  getChapterSync: (id, chapter) => store.getBookSync(id)?.chapters.find(item => item.chapterId === chapter.id),
  isExpectedFile: (_path, bytes) => bytes > 0,
  getAudioFilePath: (id, url) => '/downloads/' + id + '/' + encodeURIComponent(url),
  ensureBookDir: async () => '/downloads', deleteFileSafely: async () => {},
  saveBook: async record => { recalculate(record); },
  async prepareChapters(book, chapters, canApply) {
    if (canApply && !canApply()) return [];
    let record = store.getBookSync(book.id);
    if (!record) {
      record = { bookId: book.id, title: book.title, author: '', cover: '', sourceUrl: book.sourceUrl,
        bookUrl: '', chapterCount: book.chapters.length, chapters: [], status: 'queued', updatedAt: Date.now() };
      storeRecords.push(record);
    }
    for (const chapter of chapters) if (!record.chapters.some(item => item.chapterId === chapter.id)) {
      record.chapters.push({ chapterId: chapter.id, chapterIndex: chapter.index, title: chapter.title,
        pageUrl: chapter.source.value, audioUrl: '', filePath: '', bytes: 0, status: 'pending' });
    }
    record.status = 'queued'; recalculate(record); return chapters;
  },
  async upsertChapter(book, chapter, status, audioUrl, filePath, bytes, reason, canApply) {
    if (canApply && !canApply()) return null;
    const item = store.getChapterSync(book.id, chapter);
    Object.assign(item, { status, audioUrl, filePath, bytes, failureReason: reason });
    recalculate(store.getBookSync(book.id)); return item;
  }
};
stubs['service/DownloadStore'] = { DownloadStore: store };
const settle = () => new Promise(resolve => setImmediate(resolve));
const finishTasks = async service => { await service.networkPolicyTask; await settle(); await settle(); };
const book = id => ({ id, title: id, sourceUrl: 'https://source.invalid', chapters: [{
  id: id + '-c0', index: 1, title: 'chapter', source: { type: 'url', value: 'https://source.invalid/' + id }
}] });
(async () => {
  const { AudioCacheNetworkPolicy } = load('service/AudioCacheNetworkPolicy');
  const policy = AudioCacheNetworkPolicy.getInstance();
  assert.equal(policy.canTransfer(), true, 'default setting preserves mobile downloads');
  settings.audioCacheWifiOnly = true;
  assert.equal(policy.canTransfer(), false, 'cellular default network is blocked');
  network('wifi'); assert.equal(policy.isAllowed(), true);
  network('both'); assert.equal(policy.isAllowed(), false, 'mixed cellular/WLAN capabilities fail closed');
  network('none'); assert.equal(policy.isAllowed(), false, 'no default network is blocked');
  networkQueryFails = true; network('wifi'); assert.equal(policy.isAllowed(), false, 'network query failures never enable mobile fallback');
  networkQueryFails = false; policy.refresh(); assert.equal(policy.isAllowed(), true);
  console.log('PASS default preference, actual WLAN bearer, no-network and failed-query policy');

  const { AudioDownloadTransport } = load('service/AudioDownloadTransport', true);
  network('cellular');
  const before = httpCreates;
  await assert.rejects(new AudioDownloadTransport().download({ url: 'https://cdn.invalid/a.mp3', headers: {}, finalPath: '/files/a.mp3' }),
    error => error.message === AudioCacheNetworkPolicy.WAITING_WIFI);
  assert.equal(httpCreates, before, 'lower transport cannot create a request on cellular');
  network('wifi');
  const transport = new AudioDownloadTransport();
  const pending = transport.download({ url: 'https://cdn.invalid/a.mp3', headers: {}, finalPath: '/files/a.mp3' });
  const rejection = assert.rejects(pending, error => error.message === AudioCacheNetworkPolicy.WAITING_WIFI);
  await settle(); network('cellular'); await rejection;
  assert.equal(requests.at(-1).destroyed, true, 'switching away from WLAN destroys the active HTTP transfer');
  assert.equal(files.has('/files/a.mp3.part'), false, 'cancelled partial file is cleaned');
  console.log('PASS lower transport blocks before HTTP and destroys/cleans an interrupted download');

  const { SubtitleFiles } = load('service/subtitle/SubtitleFiles');
  const subtitleBefore = httpCreates;
  await assert.rejects(SubtitleFiles.download('https://cdn.invalid/subtitle.mp3', {}, '/files/subtitle.tmp', 1024,
    () => true, () => {}, true), error => error.message === AudioCacheNetworkPolicy.WAITING_WIFI);
  assert.equal(httpCreates, subtitleBefore, 'subtitle audio also blocks before creating HTTP');
  network('wifi');
  const subtitlePending = SubtitleFiles.download('https://cdn.invalid/subtitle.mp3', {}, '/files/subtitle.tmp', 1024,
    () => true, () => {}, true);
  const subtitleRejected = assert.rejects(subtitlePending, error => error.message === AudioCacheNetworkPolicy.WAITING_WIFI);
  await settle(); network('cellular'); await subtitleRejected;
  assert.equal(requests.at(-1).destroyed, true);
  assert.equal(files.has('/files/subtitle.tmp'), false, 'interrupted subtitle audio is removed');
  console.log('PASS subtitle extra-audio WLAN guard, immediate abort and temporary-file cleanup');

  const { DownloadService } = load('service/DownloadService');
  const service = new DownloadService();
  service.hydrateBookDurations = async () => {};
  await service.init({});
  const waiting = book('waiting');
  assert.equal(await service.downloadChapter(waiting, waiting.chapters[0]), 1);
  assert.equal(store.getBookSync(waiting.id).waitingForWifi, true);
  assert.equal(store.getBookSync(waiting.id).status, 'paused');
  assert.equal(transfers.length, 0, 'queued downloads make no extra transfer on cellular');
  network('wifi'); await finishTasks(service);
  assert.equal(store.getBookSync(waiting.id).status, 'completed');
  assert.equal(store.getBookSync(waiting.id).waitingForWifi, false);
  const manual = book('manual');
  await store.prepareChapters(manual, manual.chapters); await service.pauseBook(manual.id);
  network('cellular'); network('wifi'); await finishTasks(service);
  assert.equal(store.getBookSync(manual.id).status, 'paused', 'user-paused downloads do not automatically resume');

  autoCompleteDownload = false;
  const active = book('active');
  await service.downloadChapter(active, active.chapters[0]); await settle();
  const interrupted = transfers.at(-1);
  network('cellular'); await finishTasks(service);
  assert.equal(interrupted.cancelled, true);
  assert.equal(store.getBookSync(active.id).waitingForWifi, true);
  assert.equal(store.getBookSync(active.id).failedCount, 0, 'network-policy pause never becomes a failed chapter');
  autoCompleteDownload = true;
  network('wifi'); await finishTasks(service);
  assert.equal(store.getBookSync(active.id).status, 'completed');
  console.log('PASS waiting queue recovery, active-download cancellation, failure counts and manual-pause ownership');

  network('cellular');
  const restored = book('restored');
  await service.downloadChapter(restored, restored.chapters[0]);
  policy.listeners.clear();
  const restarted = new DownloadService();
  restarted.hydrateBookDurations = async () => {};
  await restarted.init({}); await restarted.restoreDownloads();
  network('wifi'); await finishTasks(restarted);
  assert.equal(store.getBookSync(restored.id).status, 'completed', 'persisted waiting marker restores after a cold start');
  network('cellular');
  const released = book('released');
  await restarted.downloadChapter(released, released.chapters[0]);
  settings.audioCacheWifiOnly = false; policy.refresh(); await finishTasks(restarted);
  assert.equal(store.getBookSync(released.id).status, 'completed', 'turning the option off releases waiting downloads');
  assert.equal(observers.filter(observer => observer.active).length, 0, 'disabled option releases network observation');
  console.log('PASS cold waiting recovery and disabling WLAN restriction without changing playback');
})().catch(error => { console.error(error); process.exitCode = 1; });
