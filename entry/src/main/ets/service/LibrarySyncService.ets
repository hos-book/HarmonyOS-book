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
  private lastPromptSyncAt: number = 0;
  private failures: number = 0;
  private retryAt: number = 0;
  private localChanged = (): void => { this.schedule(1500); };
  private remoteChanged = (_data: cloudSync.ChangeData): void => { this.schedule(1500); };

  static supported(context: common.Context): boolean {
    return !PlatformCompat.wearable && PlatformCompat.supports(21) && !!context.cloudFileDir &&
      canIUse('SystemCapability.FileManagement.DistributedFileService.CloudSync.Core');
  }

  setForeground(context: common.Context, foreground: boolean): void {
    if (PlatformCompat.wearable) return;
    this.context = context;
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
    this.enabled = false;
    this.accountId = '';
    this.state = null;
    this.lastSyncedAt = 0;
    this.deferredProgress = 0;
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
      if (!enabled) this.stopWatch();
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
    if (this.task) await this.task;
  }

  resumeAfterManual(): void { this.holds = Math.max(0, this.holds - 1); this.schedule(1500); }

  /** 不等待同步任务，会员核验可能正被该任务等待。已有书架和云端文件均保留。 */
  suspendForMembership(): void {
    if (MembershipState.current.hasAccess) return;
    this.epoch++;
    this.transport.cancel();
    this.stopWatch();
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
    await this.run(true);
  }

  private run(remote: boolean): Promise<void> {
    if (this.task) return this.task;
    if (this.holds > 0 || this.configuring || !this.context || Date.now() < this.retryAt) return Promise.resolve();
    const context = this.context;
    this.task = this.synchronize(context, remote).catch((_error: Error): void => {
      if (!MembershipState.current.hasAccess) { this.suspendForMembership(); return; }
      this.status = LibrarySyncStatus.FAILED;
      this.failures = Math.min(6, this.failures + 1);
      this.retryAt = Date.now() + Math.min(300000, 5000 * Math.pow(2, this.failures));
    }).finally((): void => { this.task = null; this.running = false; });
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
    const ids = new Set(values.map((v: LibrarySyncValue): string => v.bookId));
    for (const book of await DataService.exportBackupBookShells()) {
      if (!ids.has(book.id)) continue;
      const shell = LibrarySyncBook.fromBook(book);
      if (LibrarySyncBook.valid(shell)) values.push(new LibrarySyncValue('book', book.id, JSON.stringify(shell)));
    }
    return values.sort(LibrarySyncModel.order);
  }

  private protectProgress(record: LibrarySyncValue): boolean {
    if (record.kind !== 'play' && record.kind !== 'text') return false;
    if (LibrarySyncActivity.reading.has(record.bookId) || LibrarySyncActivity.playing.has(record.bookId)) return true;
    const player = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, (): PlayerState => new PlayerState());
    if (player?.currentBook?.id === record.bookId && (player.isPlaying || player.isLoading)) return true;
    const speech = TextToSpeechService.getInstance().state;
    return speech.bookId === record.bookId && speech.active;
  }

  private async synchronize(context: common.Context, remote: boolean): Promise<void> {
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
      if (remote) {
        this.watch(context);
        // 回前台可温和触发一次目录刷新，至少间隔 60 秒；上传本身由系统自动触发。
        if (Date.now() - this.lastPromptSyncAt >= 60000) {
          this.lastPromptSyncAt = Date.now();
          await new cloudSync.FileSync().start();
          guard();
        }
        await this.receive(context, state, guard);
        // 下载期间的本机操作必须先记入版本，再执行远端写回。
        local = await this.captureValues(context);
        guard();
        LibrarySyncModel.capture(state, local);
        await this.apply(context, state, local, guard);
      }
      guard();
      await this.publish(context, state, guard);
      guard();
      await this.save(context, state);
      this.lastSyncedAt = state.lastSyncedAt;
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

  private async receive(context: common.Context, state: LibrarySyncState, guard: () => void): Promise<void> {
    const files = await this.transport.list(context, state.ownerKey);
    const names = new Set(files.map((file: LibraryCloudFile): string => file.name));
    this.seen = new Set(Array.from(this.seen).filter((name: string): boolean => names.has(name)));
    const devices = new Set<string>();
    let bytes = 0;
    for (const file of files) {
      guard();
      if (devices.has(file.deviceId)) continue;
      devices.add(file.deviceId);
      if (devices.size > 64) throw new Error('Sync device limit exceeded');
      if (this.seen.has(file.name)) continue;
      const raw = await this.transport.readCloud(`${context.cloudFileDir}/${file.name}`, guard);
      bytes += raw.length;
      if (bytes > 4 * LIBRARY_SYNC_MAX_BYTES) throw new Error('Sync batch too large');
      const incoming = LibrarySyncModel.parse(raw, state.ownerKey);
      if (incoming.deviceId !== file.deviceId) throw new Error('Sync device mismatch');
      guard();
      LibrarySyncModel.merge(state, incoming);
      await this.save(context, state);
      this.seen.add(file.name);
    }
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
    prefs.filter((v: LibrarySyncValue): boolean => v.kind === 'play').forEach((v: LibrarySyncValue): void => {
      LibrarySyncActivity.remotePlayback.add(v.bookId);
    });
    LibrarySyncModel.acknowledge(state, prefs.concat(reading).concat(books));
    state.applying = [];
    await this.save(context, state);
    if (prefs.length || reading.length) emitter.emit('app.history.updated');
  }

  private async publish(context: common.Context, state: LibrarySyncState, guard: () => void): Promise<void> {
    if (state.cloudFile) {
      const path = `${context.cloudFileDir}/${state.cloudFile}`;
      if (await fileIo.access(path) && !await this.transport.confirmed(path)) {
        this.status = LibrarySyncStatus.PENDING;
        return; // 网络断开时合并本机队列，不无限生成云端文件。
      }
      guard();
      if (state.cloudRevision === state.revision && await fileIo.access(path)) {
        state.lastSyncedAt = Date.now();
        this.status = LibrarySyncStatus.SYNCED;
        await this.prune(context, state, guard);
        return;
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
