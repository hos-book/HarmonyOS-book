// Real cloud/backup services, temporary local files, simulated system cloud callbacks.
// Usage: DEVECO_HOME=<Release IDE> <Release IDE>/tools/node/node scripts/test-cloud-backup.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { createHash, randomUUID } = require('node:crypto');
const ide = process.env.DEVECO_HOME;
if (!ide) throw new Error('Set DEVECO_HOME to a Release IDE');
const ts = require(path.join(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '../entry/src/main/ets');
const compiled = new Map();
const fixtures = [];

function snapshot() {
  return {
    version: 2, exportedAt: 1780000000000,
    preferences: {
      favorites: ['online-book'], history: [], lastPlayed: null, progresses: [], skipConfigs: [],
      colorMode: -1, materialStyle: 0, accentColor: '', defaultTab: 0,
      autoPlayOnLaunch: false, audioInterruptMode: 0, audioAutoResume: true, homeGridColumns: 3, preloadChapters: 1
    },
    books: [], stats: [], ruleSources: []
  };
}

function harness() {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'listenbook-cloud-'));
  fixtures.push(base);
  const context = { filesDir: path.join(base, 'files'), cacheDir: path.join(base, 'cache'), cloudFileDir: path.join(base, 'cloud') };
  for (const value of Object.values(context)) fs.mkdirSync(value);
  const control = {
    member: true,
    auto: true, startError: 0, startErrors: [], sourceError: false, restoreError: false,
    remoteOnly: false, uploadState: 4, identity: 'account-A', stopCount: 0, downloadStopCount: 0,
    cloudWrites: 0, localRestores: 0, confirmed: 0,
    sources: [], restoredSources: [], selectUris: [], saveUris: [], pickerError: false,
    maxRead: Infinity, maxWrite: Infinity, fileWriteError: false, flushError: false, snapshotShortWrite: false,
    pickerCalls: 0, restoreCount: 0, selectedData: null, backupPreferences: snapshot().preferences,
    backupStats: [], backupBooks: [], restoredBooks: [], speechReloads: 0,
    cloudCopyUnsupported: false, cloudWriteError: 0, cloudStateError: 0, onCloudWrite: null,
    initialCompleted: false, fileStates: new Map(), autoSettingsFlushError: false
  };
  const preferenceStores = new Map();
  const stored = name => {
    if (!preferenceStores.has(name)) preferenceStores.set(name, new Map());
    return preferenceStores.get(name);
  };
  const preferences = { getPreferences: async (_context, { name }) => {
    const values = stored(name);
    return {
      get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
      put: async (key, value) => values.set(key, value),
      delete: async key => values.delete(key),
      getSync: (key, fallback) => values.has(key) ? values.get(key) : fallback,
      putSync: (key, value) => values.set(key, value),
      deleteSync: key => values.delete(key),
      getAll: async () => Object.fromEntries(values),
      flush: async () => {
        if (name === 'auto_backup_local' && control.autoSettingsFlushError) throw new Error('settings disk full');
      }
    };
  } };
  const syncTasks = [], downloadTasks = [], timers = new Map(), intervals = new Map();
  let timerId = 0;
  const auth = {
    isLoggedIn: true, openID: 'account-A', dataOperation: false,
    async restore() { control.restoreCount++; this.openID = control.identity; this.isLoggedIn = !!control.identity; },
    beginDataOperation(requireLogin = true) {
      if (this.dataOperation || (requireLogin && !this.isLoggedIn)) throw new Error('Account is busy or unavailable');
      this.dataOperation = true;
    },
    endDataOperation() { this.dataOperation = false; }
  };
  class FileSync {
    on(_event, listener) {
      this.listener = listener;
      if (control.initialCompleted) this.emit(4, 0);
    }
    off(_event, listener) { assert.equal(this.listener, listener); this.listener = null; }
    async start() {
      syncTasks.push(this);
      const nextError = control.startErrors.shift();
      if (nextError) throw { code: nextError };
      if (control.startError) throw { code: control.startError };
      if (control.auto) queueMicrotask(() => this.emit(4, 0));
    }
    emit(state, error) { this.listener?.({ state, error }); }
    async stop() { control.stopCount++; }
  }
  class CloudFileCache {
    on(_event, listener) { this.listener = listener; }
    off(_event, listener) { assert.equal(this.listener, listener); this.listener = null; }
    async start(uri) { this.uri = uri; downloadTasks.push(this); }
    emit(state, error = 0, uri = this.uri) {
      if (state === 1 && uri === this.uri) control.remoteOnly = false;
      this.listener?.({ state, error, uri, processed: 1, size: 1 });
    }
    async stop() { control.downloadStopCount++; }
  }
  const documentPath = path.join(base, 'document.json');
  const documentUri = 'document://selected-backup';
  const resolveDocument = p => p === documentUri ? documentPath : p;
  const handles = new Map();
  const picker = {
    DocumentSaveOptions: class {}, DocumentSelectOptions: class {},
    DocumentViewPicker: class {
      constructor(ctx) { assert.equal(ctx, context); }
      async save(options) {
        control.pickerCalls++;
        assert.match(options.newFileNames[0], /^listenbook-backup-\d+\.json$/);
        assert.equal(options.fileSuffixChoices[0], '.json');
        if (control.pickerError) throw new Error('picker unavailable');
        for (const uri of control.saveUris) fs.writeFileSync(resolveDocument(uri), '');
        return control.saveUris;
      }
      async select(options) {
        control.pickerCalls++;
        assert.equal(options.maxSelectNumber, 1);
        assert.equal(options.fileSuffixFilters[0], '.json');
        if (control.pickerError) throw new Error('picker unavailable');
        return control.selectUris;
      }
    }
  };
  const fileIo = {
    OpenMode: { READ_ONLY: 0, READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
    access: async p => fs.existsSync(p), mkdir: p => fsp.mkdir(p), listFile: p => fsp.readdir(p),
    open: async (p, mode) => {
      const resolved = resolveDocument(p);
      const fd = fs.openSync(resolved, mode === 0 ? 'r' : 'w+');
      handles.set(fd, resolved);
      return { fd };
    },
    read: async (fd, buffer, options) => {
      assert.equal(options.offset, undefined, 'file position advances without cumulative offset');
      return fs.readSync(fd, Buffer.from(buffer), 0, Math.min(options.length, control.maxRead), null);
    },
    write: async (fd, data, options) => {
      assert.equal(options?.offset, undefined);
      if (control.fileWriteError && handles.get(fd) === documentPath) throw new Error('disk full');
      if (handles.get(fd)?.startsWith(context.cloudFileDir)) {
        if (control.cloudWriteError) throw { code: control.cloudWriteError };
        control.cloudWrites++;
        control.onCloudWrite?.();
      }
      const bytes = Buffer.from(data);
      const length = options ? Math.min(options.length, control.maxWrite) :
        control.snapshotShortWrite ? Math.floor(bytes.length / 2) : bytes.length;
      return fs.writeSync(fd, bytes, 0, length);
    },
    close: async file => { fs.closeSync(file.fd); handles.delete(file.fd); },
    fsync: async fd => {
      if (control.flushError) throw new Error('flush failed');
      fs.fsyncSync(fd);
    },
    readText: p => fsp.readFile(p, 'utf8'), unlink: p => fsp.unlink(p),
    moveFile: async (src, dest) => {
      // Matches the device cloud directory: rename succeeds for a new name, rejects replacement with EINVAL.
      if (dest.startsWith(context.cloudFileDir) && fs.existsSync(dest)) throw { code: 13900020 };
      await fsp.rename(src, dest);
    },
    copyFile: async (src, dest) => {
      if (control.cloudCopyUnsupported &&
        (src.startsWith(context.cloudFileDir) || dest.startsWith(context.cloudFileDir))) throw { code: 13900042 };
      if (dest.startsWith(context.cloudFileDir)) control.cloudWrites++;
      await fsp.copyFile(src, dest);
    },
    stat: async p => {
      const stat = typeof p === 'number' ? fs.fstatSync(p) : await fsp.stat(p);
      return { size: stat.size, isFile: () => stat.isFile(), location: control.remoteOnly ? 2 : 3 };
    }
  };
  const cloudSync = {
    FileSync, CloudFileCache,
    SyncState: { UPLOADING: 0, UPLOAD_FAILED: 1, DOWNLOADING: 2, DOWNLOAD_FAILED: 3, COMPLETED: 4, STOPPED: 5 },
    ErrorType: { NO_ERROR: 0, NETWORK_UNAVAILABLE: 1, WIFI_UNAVAILABLE: 2, BATTERY_LEVEL_LOW: 3,
      BATTERY_LEVEL_WARNING: 4, CLOUD_STORAGE_FULL: 5, LOCAL_STORAGE_FULL: 6, DEVICE_TEMPERATURE_TOO_HIGH: 7 },
    State: { RUNNING: 0, COMPLETED: 1, FAILED: 2, STOPPED: 3 },
    FileState: { INITIAL_AFTER_DOWNLOAD: 0, UPLOADING: 1, STOPPED: 2, TO_BE_UPLOADED: 3, UPLOAD_SUCCESS: 4, UPLOAD_FAILURE: 5 },
    DownloadErrorType: { NETWORK_UNAVAILABLE: 2, LOCAL_STORAGE_FULL: 3 },
    getCoreFileSyncState: uri => {
      if (control.cloudStateError) throw { code: control.cloudStateError };
      return control.fileStates.get(path.normalize(uri.slice('file://'.length))) ?? control.uploadState;
    }
  };
  const modules = new Map();
  function load(relative) {
    if (modules.has(relative)) return modules.get(relative);
    const exports = {};
    modules.set(relative, exports);
    if (!compiled.has(relative)) {
      compiled.set(relative, ts.transpileModule(fs.readFileSync(path.join(root, relative + '.ets'), 'utf8'), {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021, experimentalDecorators: true }
      }).outputText);
    }
    vm.runInNewContext(compiled.get(relative), {
      exports, console, $r: name => ({ id: name }), ObservedV2: value => value, Trace: () => {},
      setTimeout: cb => { const id = ++timerId; timers.set(id, cb); return id; },
      clearTimeout: id => timers.delete(id),
      setInterval: cb => { const id = ++timerId; intervals.set(id, cb); return id; },
      clearInterval: id => intervals.delete(id),
      require: name => {
        if (name === './MembershipService') return { MembershipService: { instance: {
          hasCurrentEntitlement: async () => control.member
        } } };
        if (name === '../model/MembershipState') return { MembershipState: { current: {
          get active() { return control.member; },
            get hasAccess() { return control.member; },
            get confirmedInactive() { return !control.member; }
        } } };
        if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {}, debug() {} } };
        if (name === '@kit.ArkData') return { preferences };
        if (name === '@kit.AbilityKit') return { ConfigurationConstant: { ColorMode: { COLOR_MODE_NOT_SET: -1 } } };
        if (name === '../model/AppAppearance') return { AppAppearance: {
          current: { material: 0, accent: '' }, normalizeMaterial: value => value, normalizeAccent: value => value
        } };
        if (name === '@kit.BasicServicesKit') return { emitter: { emit() {}, on() {} } };
        if (name === '@kit.CoreFileKit') return { fileIo, picker, cloudSync, fileUri: { getUriFromPath: p => 'file://' + p } };
        if (name === '@kit.ArkTS') return { util: {
          TextEncoder: class { encodeInto(s) { return new Uint8Array(Buffer.from(s)); } }, generateRandomUUID: () => randomUUID()
        } };
        if (name === '@kit.CryptoArchitectureKit') return { cryptoFramework: { createMd: () => {
          const hash = createHash('sha256'); return { update: async blob => hash.update(blob.data), digest: async () => ({ data: hash.digest() }) };
        } } };
        if (name === './AuthService') return { AuthService: { instance: auth } };
        if (name === './DiagnosticLogService') return { DiagnosticLogService: {
          info() {}, describe: error => error?.message || String(error), sanitize: text => text
        } };
        if (name === './AppBackupService') return load('service/AppBackupService');
        if (name === './PreferenceService') return {
          PreferenceBackupSnapshot: class { constructor() { Object.assign(this, snapshot().preferences); } },
          PreferenceService: {
            init: async () => {}, exportBackupSnapshot: async () => control.backupPreferences,
            restoreBackupSnapshot: async data => {
              control.localRestores++; control.selectedData = data;
              if (control.restoreError) throw new Error('disk full');
            }
          }
        };
        if (name === './StatsService') return { StatsService: {
          init: async () => {}, getCachedStatsBundle: () => ({ summary: { totalSeconds: control.backupStats.reduce((n, v) => n + v.listenSeconds, 0) } }),
          exportBackupStats: async () => control.backupStats, restoreBackupStats: async records => {
            control.backupStats = records; control.localRestores++; }
        } };
        if (name === './DataService') return { DataService: {
          setContext: () => {}, exportBackupBookShells: async () => control.backupBooks,
          restoreBackupBookShells: async (books, strict) => {
            assert.equal(strict, true); control.restoredBooks = books; control.localRestores++;
          }
        } };
        if (name === './SourceDataService') return { SourceDataService: { invalidateLocalSources() {} } };
        if (name === './rulesource/LocalRuleSourceImportService') return { LocalRuleSourceImportService: {
          importSources: async sources => { control.restoredSources = sources; return sources.length; }
        } };
        if (name === './rulesource/LocalRuleSourceRepository') return { LocalRuleSourceRepository: {
          init: async () => { if (control.sourceError) throw new Error('source database unavailable'); },
          getAll: async () => control.sources,
          upsertImportedBatch: async sources => { control.restoredSources = sources; return sources.length; }
        } };
        if (name === './rulesource/guangyu/GuangYuSourceIdentity') return { GuangYuSourceIdentity: { isSourceUrl: () => false } };
        if (name === './rulesource/shushan/ShuShanSourceIdentity') return { ShuShanSourceIdentity: { isSourceUrl: () => false } };
        if (name === '../model/LocalRuleSource') return load('model/LocalRuleSource');
        if (name === './BookSource' || name === '../model/Book') return {};
        if (name === './TextToSpeechService') return { TextToSpeechService: {
          reloadSettings: async () => { control.speechReloads++; }
        } };
        if (name.startsWith('.')) return load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), name)));
        throw new Error('Unexpected dependency: ' + name);
      }
    }, { filename: relative + '.ets' });
    return exports;
  }
  const module = load('service/CloudBackupService');
  const service = module.CloudBackupService.instance;
  const localModule = load('service/LocalBackupService');
  const local = localModule.LocalBackupService.instance;
  const legacyCloudPath = (account = auth.openID) => path.join(context.cloudFileDir, 'listenbook_' + createHash('sha256').update(account).digest('hex') + '.json');
  const cloudPath = (account = auth.openID) => {
    const legacy = legacyCloudPath(account);
    const prefix = path.basename(legacy, '.json') + '_';
    const versions = fs.readdirSync(context.cloudFileDir).filter(name => name.startsWith(prefix) && name.endsWith('.json'))
      .sort((a, b) => Number(b.slice(prefix.length).split('_')[0]) - Number(a.slice(prefix.length).split('_')[0]));
    return versions.length ? path.join(context.cloudFileDir, versions[0]) : legacy;
  };
  const seed = (data = snapshot(), account) => fs.writeFileSync(cloudPath(account), JSON.stringify(data));
  const settled = () => {
    assert.equal(service.busy, false);
    assert.equal(local.busy, false);
    assert.equal(auth.dataOperation, false);
    assert.equal(handles.size, 0);
    assert.equal(timers.size, 0);
    assert.equal(intervals.size, 0);
    for (const task of [...syncTasks, ...downloadTasks]) assert.equal(task.listener, null);
  };
  return { context, control, auth, service, codes: module.CloudBackupErrorCode, seed, cloudPath,
    local, localCodes: localModule.LocalBackupErrorCode, documentPath, documentUri,
    syncTasks, downloadTasks, timers, intervals, settled, load, stored };
}

async function until(predicate) {
  for (let i = 0; i < 400 && !predicate(); i++) await new Promise(resolve => setTimeout(resolve, 5));
  assert.ok(predicate(), 'expected asynchronous operation to start');
}


module.exports = { assert, fs, path, fixtures, snapshot, harness, until };
