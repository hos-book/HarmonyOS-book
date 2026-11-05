import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { emitter } from '@kit.BasicServicesKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { cloudSync, fileIo, fileUri } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { AuthService } from './AuthService';
import lazy { MembershipService } from './MembershipService';
import { MembershipState } from '../model/MembershipState';
import { PreferenceService, EVT_FAVORITES_CHANGED } from './PreferenceService';
import { DataService } from './DataService';
import { TextReadingProgressService, EVT_TEXT_READING_PROGRESS_CHANGED } from './text/TextReadingProgressService';
import { TextToSpeechService } from './text/TextToSpeechService';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { Book } from '../model/Book';
import { PlatformCompat } from '../utils/PlatformCompat';
import {
  LibrarySyncValue, LibrarySyncModel, LibrarySyncState, LibrarySyncBook, LibrarySyncActivity,
  LIBRARY_SYNC_CHANGED, LIBRARY_SYNC_MAX_BYTES
} from './sync/LibrarySyncModel';
import { LibrarySyncFiles, LibraryCloudFile } from './sync/LibrarySyncFiles';
import { DiagnosticLogService } from './DiagnosticLogService';
import { ReadingSessionService } from './ReadingSessionService';
import { LibraryCloudSync, LibraryCloudIssue } from './sync/LibraryCloudSync';

export enum LibrarySyncStatus { OFF, WAITING, WORKING, PENDING, SYNCED, UNAVAILABLE, FAILED, MEMBERSHIP }

/** 前台订阅、后台仅提交本地变更。与备份共用账号互斥锁，但从不恢复整份快照。 */
@ObservedV2
export class LibrarySyncService {
  private static singleton: LibrarySyncService | null = null;
  static get instance(): LibrarySyncService {
    if (!this.singleton) this.singleton = new LibrarySyncService();
    return this.singleton;
  }

  @Trace enabled: boolean = false;
  @Trace running: boolean = false;
  @Trace configuring: boolean = false;
  @Trace accountId: string = '';
  @Trace status: LibrarySyncStatus = LibrarySyncStatus.OFF;
  @Trace lastSyncedAt: number = 0;
  @Trace deferredProgress: number = 0;
  @Trace lastReceivedAt: number = 0;
  @Trace resumeChecking: boolean = false;
  @Trace resumeUnconfirmed: boolean = false;
  @Trace cloud: LibraryCloudSync = new LibraryCloudSync(
    (): boolean => this.enabled && this.holds === 0 && this.accountId !== '' &&
      AuthService.instance.isLoggedIn && AuthService.instance.openID === this.accountId && MembershipState.current.hasAccess,
    (): void => { this.schedule(500); });
  private context: common.Context | null = null;
  private foreground: boolean = false;
  private timer: number = -1;
  private poll: number = -1;
  private subscribed: boolean = false;
  private cloudUri: string = '';
  private state: LibrarySyncState | null = null;
  private store: preferences.Preferences | null = null;
  private task: Promise<void> | null = null;
  private holds: number = 0;
  private epoch: number = 0;
  private transport: LibrarySyncFiles = new LibrarySyncFiles();
  private seen: Set<string> = new Set();
  private lastSubmitAt: number = 0;
  private rerun: boolean = false;
  private resumeBooks: Set<string> = new Set();
  private failures: number = 0;
  private retryAt: number = 0;
  private lastUploadLog: string = '';
  private localChanged = (): void => { this.schedule(1500); };
  private remoteChanged = (_data: cloudSync.ChangeData): void => { this.schedule(1500); };

  static supported(context: common.Context): boolean {
    return !PlatformCompat.wearable && PlatformCompat.supports(21) && !!context.cloudFileDir &&
      canIUse('SystemCapability.FileManagement.DistributedFileService.CloudSync.Core');
  }

  setForeground(context: common.Context, foreground: boolean): void {
    if (PlatformCompat.wearable) return;
    this.context = context;
    LibrarySyncActivity.beforeResume = (bookId: string): Promise<void> => this.prepareResume(bookId);
    this.foreground = foreground;
    if (this.poll >= 0) clearInterval(this.poll);
    this.poll = -1;
    if (foreground) {
      if (!this.subscribed) {
        emitter.on(EVT_FAVORITES_CHANGED, this.localChanged);
        emitter.on(EVT_TEXT_READING_PROGRESS_CHANGED, this.localChanged);
        emitter.on(LIBRARY_SYNC_CHANGED, this.localChanged);
        this.subscribed = true;
      }
      this.poll = setInterval((): void => this.schedule(0), 30000);
      this.schedule(2000);
    } else {
      this.stopWatch();
      if (this.timer >= 0) clearTimeout(this.timer);
      this.timer = -1;
      // 不取消已经写入系统云目录的上传；系统自行在网络恢复后继续。
    }
  }

  async background(context: common.Context): Promise<void> {
    this.setForeground(context, false);
    if (this.task) await this.task;
    await this.run(false);
  }

  private schedule(delay: number): void {
    if (!this.context || this.holds > 0 || (!this.foreground && !this.enabled) || this.timer >= 0) return;
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.run(this.foreground);
    }, Math.max(delay, this.retryAt - Date.now()));
  }

  private async key(accountId: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: new util.TextEncoder().encodeInto(accountId) });
    const digest = await md.digest();
    return Array.from(digest.data).map((byte: number): string => byte.toString(16).padStart(2, '0')).join('');
  }

  async refresh(context: common.Context): Promise<void> {
    this.context = context;
    if (this.running || this.configuring) return;
    try { await this.load(context); } catch (_error) { this.status = LibrarySyncStatus.FAILED; }
  }

  private async load(context: common.Context, reload: boolean = false): Promise<void> {
    const accountId = AuthService.instance.isLoggedIn ? AuthService.instance.openID : '';
    if (!reload && accountId === this.accountId && this.state) return;
    if (this.store && this.accountId && accountId !== this.accountId) {
      this.store.putSync('owner', '');
      await this.store.flush();
    }
    this.stopWatch();
    this.cloud.close();
    this.enabled = false;
    this.accountId = '';
    this.state = null;
    this.lastSyncedAt = 0;
    this.deferredProgress = 0;
    this.lastReceivedAt = 0;
    this.resumeUnconfirmed = false;
    this.seen.clear();
    this.status = LibrarySyncStatus.OFF;
    if (!accountId) return;
    const key = await this.key(accountId);
    const store = await preferences.getPreferences(context, { name: 'library_sync_local_v1' });
    if (!AuthService.instance.isLoggedIn || AuthService.instance.openID !== accountId) return;
    this.store = store;
    const lastOwner = store.getSync('owner', '');
    if (typeof lastOwner === 'string' && lastOwner && lastOwner !== key) {
      store.putSync('owner', '');
      await store.flush();
    }
    const dir = `${context.filesDir}/library_sync`;
    if (!await fileIo.access(dir)) await fileIo.mkdir(dir);
    const path = `${dir}/${key}.json`;
    let state = new LibrarySyncState();
    if (await fileIo.access(path)) {
      const raw = await LibrarySyncFiles.read(path);
      LibrarySyncModel.parse(raw, key);
      const saved: LibrarySyncState = JSON.parse(raw);
      if (!Array.isArray(saved.baseline) || !Array.isArray(saved.applying) ||
        !Number.isSafeInteger(saved.clock) || typeof saved.cloudFile !== 'string' ||
        (saved.cloudFile && !saved.cloudFile.startsWith(`library_v1_${key}_${saved.deviceId}_`)) ||
        saved.cloudFile.includes('/') || saved.cloudFile.includes('\\')) throw new Error('Invalid local sync state');
      state = saved;
    } else {
      state.ownerKey = key;
      state.deviceId = util.generateRandomUUID(false);
    }
    if (!AuthService.instance.isLoggedIn || AuthService.instance.openID !== accountId) return;
    this.state = state;
    this.accountId = accountId;
    // 应用书架目前是本机共享库。换账号后必须重新显式开启，不能静默上传上一账号的数据。
    this.enabled = store.getSync('owner', '') === key && store.getSync(`enabled_${key}`, false) === true;
    this.lastSyncedAt = state.lastSyncedAt;
    this.status = this.enabled ? LibrarySyncStatus.WAITING : LibrarySyncStatus.OFF;
  }

  async setEnabled(context: common.Context, enabled: boolean): Promise<void> {
    if (this.configuring) return;
    await this.pauseForManual();
    this.configuring = true;
    try {
      this.context = context;
      await AuthService.instance.restore(context);
      // 清除旧内存，重新读取当前账号设置。
      await this.load(context, true);
      const state = this.state;
      const store = this.store;
      if (!state || !store || !this.accountId) throw new Error('Login required');
      if (enabled && !await MembershipService.instance.hasCurrentEntitlement()) {
        this.suspendForMembership();
        throw new Error('Membership required');
      }
      if (enabled && !LibrarySyncService.supported(context)) {
        this.status = LibrarySyncStatus.UNAVAILABLE;
        throw new Error('Cloud sync unavailable');
      }
      const accountId = this.accountId;
      const guard = (): void => {
        this.assertCurrent(accountId, state);
        if (enabled) this.assertMembership();
      };
      guard();
      if (enabled && store.getSync('owner', '') !== state.ownerKey) {
        const values = await this.captureValues(context);
        guard();
        state.baseline = [];
        // 用户明确选择合并当前本机书架；已有远端编辑仍有更高优先级。
        LibrarySyncModel.capture(state, values, true);
        await this.save(context, state);
      }
      guard();
      const previous = store.getSync(`enabled_${state.ownerKey}`, false);
      const previousOwner = store.getSync('owner', '');
      try {
        store.putSync(`enabled_${state.ownerKey}`, enabled);
        if (enabled) store.putSync('owner', state.ownerKey);
        await store.flush();
      } catch (error) {
        store.putSync(`enabled_${state.ownerKey}`, previous);
        store.putSync('owner', previousOwner);
        throw new Error('Cannot save sync settings');
      }
      guard();
      this.enabled = enabled;
      this.status = enabled ? LibrarySyncStatus.WAITING : LibrarySyncStatus.OFF;
      if (!enabled) { this.stopWatch(); this.cloud.close(); }
    } finally {
      this.configuring = false;
      this.resumeAfterManual();
    }
    if (enabled) this.schedule(0);
  }

  async pauseForManual(): Promise<void> {
    this.holds++;
    this.epoch++;
    this.transport.cancel();
    this.cloud.close();
    if (this.task) await this.task;
  }

  resumeAfterManual(): void { this.holds = Math.max(0, this.holds - 1); this.schedule(1500); }

  /** 不等待同步任务，会员核验可能正被该任务等待。已有书架和云端文件均保留。 */
  suspendForMembership(): void {
    if (MembershipState.current.hasAccess) return;
    this.epoch++;
    this.transport.cancel();
    this.stopWatch();
    this.cloud.close();
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
    this.status = LibrarySyncStatus.MEMBERSHIP;
    if (MembershipState.current.confirmedInactive) {
      this.enabled = false;
      if (this.store && this.state) {
        this.store.putSync(`enabled_${this.state.ownerKey}`, false);
        this.store.flush().catch((): void => { /* 下次同步仍须重新核验权益。 */ });
      }
    }
  }

  private assertMembership(): void {
    if (MembershipState.current.hasAccess) return;
    this.suspendForMembership();
    throw new Error('Membership required');
  }

  async syncNow(): Promise<void> {
    this.retryAt = 0;
    if (this.task) await this.task;
    await this.run(true, 8000);
  }

  private async prepareResume(bookId: string): Promise<void> {
    if (!LibrarySyncValue.online(bookId) || !this.context || !this.enabled || this.holds > 0 ||
      this.accountId !== AuthService.instance.openID || !MembershipState.current.hasAccess) return;
    const accountId = this.accountId;
    const epoch = this.epoch;
    this.resumeBooks.add(bookId);
    this.resumeChecking = true;
    let timer: number = -1;
    try {
      const operation = async (): Promise<void> => {
        if (this.task) await this.task;
        if (epoch !== this.epoch || accountId !== this.accountId || !this.resumeBooks.has(bookId)) return;
        await this.run(true, 3500);
      };
      await Promise.race<void>([operation(), new Promise<void>((resolve): void => {
        timer = setTimeout(resolve, 4500);
      })]);
      this.resumeUnconfirmed = this.cloud.issue !== LibraryCloudIssue.NONE || this.lastReceivedAt === 0 ||
        this.cloud.lastCompletedAt === 0 || this.lastReceivedAt < this.cloud.lastCompletedAt || this.running;
    } finally {
      if (timer >= 0) clearTimeout(timer);
      this.resumeBooks.delete(bookId);
      this.resumeChecking = this.resumeBooks.size > 0;
    }
  }

  private run(remote: boolean, waitMs: number = 0): Promise<void> {
    if (this.task) { this.rerun = true; return this.task; }
    if (this.holds > 0 || this.configuring || !this.context || Date.now() < this.retryAt) return Promise.resolve();
    const context = this.context;
    this.task = this.synchronize(context, remote, waitMs).catch((error: Error): void => {
      DiagnosticLogService.info('library.sync.failed', error.message);
      if (!MembershipState.current.hasAccess) { this.suspendForMembership(); return; }
      this.status = LibrarySyncStatus.FAILED;
      this.failures = Math.min(6, this.failures + 1);
      this.retryAt = Date.now() + Math.min(300000, 5000 * Math.pow(2, this.failures));
    }).finally((): void => {
      this.task = null;
      this.running = false;
      if (this.rerun) { this.rerun = false; this.schedule(1500); }
    });
    return this.task;
  }

  private assertCurrent(accountId: string, state: LibrarySyncState): void {
    if (!accountId || !AuthService.instance.isLoggedIn || AuthService.instance.openID !== accountId ||
      this.accountId !== accountId || this.state !== state) throw new Error('Sync account changed');
  }

  private async save(context: common.Context, state: LibrarySyncState): Promise<void> {
    await LibrarySyncFiles.write(`${context.filesDir}/library_sync/${state.ownerKey}.json`, JSON.stringify(state));
  }

  private async captureValues(context: common.Context): Promise<LibrarySyncValue[]> {
    const values = await PreferenceService.exportLibrarySyncValues();
    for (const position of await TextReadingProgressService.getAll(context)) {
      if (LibrarySyncValue.online(position.bookId)) values.push(new LibrarySyncValue('text', position.bookId, JSON.stringify(position)));
    }
    for (const session of await ReadingSessionService.exportLibrarySyncValues()) values.push(session);
    const ids = new Set(values.map((v: LibrarySyncValue): string => v.bookId));
    for (const book of await DataService.exportBackupBookShells()) {
      if (!ids.has(book.id)) continue;
      const shell = LibrarySyncBook.fromBook(book);
      if (LibrarySyncBook.valid(shell)) values.push(new LibrarySyncValue('book', book.id, JSON.stringify(shell)));
    }
    return values.sort(LibrarySyncModel.order);
  }

  private protectProgress(record: LibrarySyncValue): boolean {
    if (record.kind !== 'play' && record.kind !== 'text' && record.kind !== 'history') return false;
    const player = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, (): PlayerState => new PlayerState());
    if (player?.currentBook?.id === record.bookId && (player.isPlaying || player.isLoading)) return true;
    const speech = TextToSpeechService.getInstance().state;
    if (speech.bookId === record.bookId && (speech.playing || speech.loading)) return true;
    if (this.resumeBooks.has(record.bookId)) return false;
    return LibrarySyncActivity.reading.has(record.bookId) || LibrarySyncActivity.playing.has(record.bookId) ||
      (speech.bookId === record.bookId && speech.active);
  }

  private async synchronize(context: common.Context, remote: boolean, waitMs: number = 0): Promise<void> {
    if (AuthService.instance.logging || AuthService.instance.restoring || AuthService.instance.dataOperation) return;
    await AuthService.instance.restore(context);
    await this.load(context);
    const state = this.state;
    if (!this.enabled || !state) return;
    if (!await MembershipService.instance.hasCurrentEntitlement()) {
      this.suspendForMembership();
      return;
    }
    this.assertMembership();
    if (!LibrarySyncService.supported(context)) { this.status = LibrarySyncStatus.UNAVAILABLE; return; }
    if (AuthService.instance.dataOperation || this.holds > 0) return;
    AuthService.instance.beginDataOperation();
    this.running = true;
    this.status = LibrarySyncStatus.WORKING;
    const accountId = this.accountId;
    const epoch = this.epoch;
    const guard = (): void => {
      this.assertCurrent(accountId, state);
      this.assertMembership();
      if (epoch !== this.epoch) throw new Error('Sync cancelled');
    };
    try {
      let local = await this.captureValues(context);
      guard();
      // 崩溃恢复：已经应用但尚未确认落盘的远端值不应被再标记为本机编辑。
      const actual = new Map<string, string>();
      local.forEach((v: LibrarySyncValue): void => { actual.set(LibrarySyncValue.key(v), v.value); });
      LibrarySyncModel.acknowledge(state, state.applying.filter((v: LibrarySyncValue): boolean =>
        (actual.get(LibrarySyncValue.key(v)) ?? '') === v.value));
      state.applying = [];
      LibrarySyncModel.capture(state, local, state.records.length === 0 && state.baseline.length === 0);
      await this.save(context, state);
      guard();
      let receivedAll = true;
      if (remote) {
        this.watch(context);
        // start resolve 不代表完成；续听/手动检查限时等待真实回调，普通轮询不阻塞。
        await this.cloud.request(waitMs);
        guard();
        const received = await this.receive(context, state, guard);
        receivedAll = received;
        // 下载期间的本机操作必须先记入版本，再执行远端写回。
        local = await this.captureValues(context);
        guard();
        LibrarySyncModel.capture(state, local);
        await this.apply(context, state, local, guard);
        if (received) {
          this.lastReceivedAt = Date.now();
          if (this.cloud.lastCompletedAt > 0 && this.cloud.issue === LibraryCloudIssue.NONE) this.resumeUnconfirmed = false;
        }
      }
      guard();
      await this.publish(context, state, guard);
      guard();
      await this.save(context, state);
      this.lastSyncedAt = state.lastSyncedAt;
      if (!receivedAll || this.cloud.issue !== LibraryCloudIssue.NONE) throw new Error('Cloud synchronization pending recovery');
      this.failures = 0;
      this.retryAt = 0;
    } finally { AuthService.instance.endDataOperation(); }
  }

  private watch(context: common.Context): void {
    if (!this.foreground || this.cloudUri) return;
    const uri = fileUri.getUriFromPath(context.cloudFileDir);
    try { cloudSync.registerChange(uri, true, this.remoteChanged); this.cloudUri = uri; }
    catch (_error) { /* 部分云空间版本不支持目录通知，保留前台 30 秒检查。 */ }
  }

  private stopWatch(): void {
    if (this.cloudUri) { try { cloudSync.unregisterChange(this.cloudUri); } catch (_error) { } }
    this.cloudUri = '';
  }

  private async receive(context: common.Context, state: LibrarySyncState, guard: () => void): Promise<boolean> {
    let files: LibraryCloudFile[] = [];
    try { files = await this.transport.list(context, state.ownerKey); }
    catch (error) {
      guard();
      DiagnosticLogService.info('library.sync.receive.failed', 'Cloud directory unavailable');
      this.status = LibrarySyncStatus.FAILED;
      return false;
    }
    const names = new Set(files.map((file: LibraryCloudFile): string => file.name));
    this.seen = new Set(Array.from(this.seen).filter((name: string): boolean => names.has(name)));
    const devices = new Set<string>();
    const received = new Set<string>();
    let complete = true;
    let bytes = 0;
    let attempts = 0;
    const attemptsByDevice = new Map<string, number>();
    for (const file of files) {
      guard();
      if (file.deviceId === state.deviceId || received.has(file.deviceId)) continue;
      devices.add(file.deviceId);
      if (devices.size > 64) throw new Error('Sync device limit exceeded');
      if (this.seen.has(file.name)) { received.add(file.deviceId); continue; }
      const deviceAttempts = attemptsByDevice.get(file.deviceId) ?? 0;
      if (deviceAttempts >= 2) { complete = false; continue; }
      if (++attempts > 64) { complete = false; break; }
      attemptsByDevice.set(file.deviceId, deviceAttempts + 1);
      try {
        const raw = await this.transport.readCloud(`${context.cloudFileDir}/${file.name}`, guard);
        bytes += raw.length;
        if (bytes > 4 * LIBRARY_SYNC_MAX_BYTES) throw new Error('Sync batch too large');
        const incoming = LibrarySyncModel.parse(raw, state.ownerKey);
        if (incoming.deviceId !== file.deviceId) throw new Error('Sync device mismatch');
        guard();
        LibrarySyncModel.merge(state, incoming);
        await this.save(context, state);
        this.seen.add(file.name);
        received.add(file.deviceId);
      } catch (error) {
        guard();
        complete = false;
        DiagnosticLogService.info('library.sync.receive.failed', 'Remote snapshot unavailable; other devices continue');
        if (bytes > 4 * LIBRARY_SYNC_MAX_BYTES) break;
      }
    }
    return complete;
  }

  private async apply(context: common.Context, state: LibrarySyncState, local: LibrarySyncValue[], guard: () => void): Promise<void> {
    const values = new Map<string, string>();
    local.forEach((v: LibrarySyncValue): void => { values.set(LibrarySyncValue.key(v), v.value); });
    const changed = state.records.filter((v: LibrarySyncValue): boolean => (values.get(LibrarySyncValue.key(v)) ?? '') !== v.value);
    this.deferredProgress = changed.filter((v: LibrarySyncValue): boolean => this.protectProgress(v)).length;
    const applicable = changed.filter((v: LibrarySyncValue): boolean => !this.protectProgress(v));
    state.applying = applicable;
    await this.save(context, state);
    guard();
    const shells: Book[] = [];
    const books: LibrarySyncValue[] = [];
    for (const item of applicable) {
      if (item.kind !== 'book') continue;
      if (item.value) {
        const parsed: LibrarySyncBook = JSON.parse(item.value);
        // JSON.parse 不具有原型方法，显式构造后转换。
        const shell = new LibrarySyncBook();
        shell.id = parsed.id; shell.title = parsed.title; shell.author = parsed.author;
        shell.narrator = parsed.narrator; shell.cover = parsed.cover; shell.contentType = parsed.contentType;
        shell.bookUrl = parsed.bookUrl; shell.sourceUrl = parsed.sourceUrl; shell.chapterCount = parsed.chapterCount;
        shells.push(shell.toBook());
      }
      books.push(item);
    }
    if (shells.length > 0) await DataService.restoreBackupBookShells(shells, true);
    guard();
    const safe = applicable.filter((v: LibrarySyncValue): boolean => !this.protectProgress(v));
    const prefs = await PreferenceService.applyLibrarySyncValues(safe, local, guard);
    guard();
    const reading = await TextReadingProgressService.applyLibrarySyncValues(context, safe, local, guard);
    guard();
    const sessions = await ReadingSessionService.applyLibrarySyncValues(safe, local, guard);
    guard();
    prefs.filter((v: LibrarySyncValue): boolean => v.kind === 'play').forEach((v: LibrarySyncValue): void => {
      LibrarySyncActivity.remotePlayback.add(v.bookId);
    });
    reading.forEach((v: LibrarySyncValue): void => { LibrarySyncActivity.remoteText.add(v.bookId); });
    LibrarySyncModel.acknowledge(state, prefs.concat(reading).concat(books).concat(sessions));
    state.applying = [];
    await this.save(context, state);
    if (prefs.length || reading.length || sessions.length) emitter.emit('app.history.updated');
  }

  private async publish(context: common.Context, state: LibrarySyncState, guard: () => void): Promise<void> {
    let superseded = '';
    if (state.cloudFile) {
      const path = `${context.cloudFileDir}/${state.cloudFile}`;
      if (await fileIo.access(path)) {
        const upload = await this.transport.uploadState(path);
        guard();
        const signature = `${state.cloudRevision}/${upload.location}/${upload.state}`;
        if (signature !== this.lastUploadLog) {
          this.lastUploadLog = signature;
          DiagnosticLogService.info('library.sync.upload', `revision/state=${signature}, local=${state.revision}`);
        }
        if (!upload.confirmed) {
          const generation = /_([0-9]+)_[0-9a-f-]{36}\.json$/.exec(state.cloudFile);
          const submittedAt = generation ? Number(generation[1]) : Date.now();
          this.status = upload.state === cloudSync.FileState.UPLOAD_FAILURE || upload.state === cloudSync.FileState.STOPPED ?
            LibrarySyncStatus.FAILED : LibrarySyncStatus.PENDING;
          // 不抢占正在上传的文件。长时间未排入上传/失败的文件重新提交最新快照，最多五分钟一次。
          if (upload.state === cloudSync.FileState.UPLOADING || Date.now() - submittedAt < 300000 ||
            this.cloud.issue !== LibraryCloudIssue.NONE) return;
          superseded = path;
          DiagnosticLogService.info('library.sync.republish', `cloud=${state.cloudRevision}, local=${state.revision}`);
        } else {
          if (state.confirmedCloudFile !== state.cloudFile) {
            state.lastSyncedAt = Date.now();
            state.confirmedCloudFile = state.cloudFile;
          }
          if (state.cloudRevision === state.revision) {
            this.status = LibrarySyncStatus.SYNCED;
            await this.prune(context, state, guard);
            return;
          }
        }
      }
    }
    if (Date.now() - this.lastSubmitAt < 15000) { this.status = LibrarySyncStatus.PENDING; return; }
    const name = `library_v1_${state.ownerKey}_${state.deviceId}_${Date.now()}_${util.generateRandomUUID(false)}.json`;
    guard();
    const content = LibrarySyncModel.encode(state);
    await LibrarySyncFiles.write(`${context.cloudFileDir}/${name}`, content, true, guard);
    guard();
    state.cloudFile = name;
    state.cloudRevision = state.revision;
    this.lastSubmitAt = Date.now();
    this.status = LibrarySyncStatus.PENDING;
    // 先落盘替代快照指针，再清理已失效的待传文件，离线不会无限堆积。
    await this.save(context, state);
    guard();
    if (superseded) {
      try { await fileIo.unlink(superseded); }
      catch (_error) { DiagnosticLogService.info('library.sync.cleanup', 'Superseded pending file retained'); }
    }
    DiagnosticLogService.info('library.sync.published', `revision=${state.cloudRevision}, records=${state.records.length}`);
  }

  private async prune(context: common.Context, state: LibrarySyncState, guard: () => void): Promise<void> {
    const own = (await this.transport.list(context, state.ownerKey))
      .filter((v: LibraryCloudFile): boolean => v.deviceId === state.deviceId);
    // 仅在最新完整快照确认上云后删除本设备的旧代；删除标记始终包含在完整快照中。
    for (const file of own.slice(2)) {
      guard();
      if (file.name !== state.cloudFile) await fileIo.unlink(`${context.cloudFileDir}/${file.name}`);
    }
  }
}
