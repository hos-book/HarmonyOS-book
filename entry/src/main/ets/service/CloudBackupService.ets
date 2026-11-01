import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { cloudSync, fileIo, fileUri } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { AuthService } from './AuthService';
import { DiagnosticLogService } from './DiagnosticLogService';
import { AppBackupService, AppBackupSnapshot } from './AppBackupService';

export enum CloudBackupErrorCode {
  UNAVAILABLE = 1,
  NETWORK,
  BATTERY,
  CLOUD_FULL,
  LOCAL_FULL,
  HOT,
  SERVER,
  TIMEOUT,
  CANCELLED,
  ACCOUNT_CHANGED,
  NO_BACKUP,
  INVALID_BACKUP,
  LOCAL_FAILURE,
  RESTORE_FAILED,
  CLOUD_FILE_FAILURE,
  EXISTING_BACKUP,
  NOT_READY,
  SYSTEM_SERVICE
}

export class CloudBackupError extends Error {
  code: CloudBackupErrorCode;
  systemCode: number;

  constructor(code: CloudBackupErrorCode, systemCode: number = 0) {
    super('Cloud backup operation failed');
    this.code = code;
    this.systemCode = systemCode;
  }
}

export enum CloudBackupPhase {
  IDLE = 0,
  PREPARING,
  SYNCING,
  DOWNLOADING,
  CONFIRMING,
  RESTORING
}

export class CloudBackupInfo {
  exportedAt: number = 0;
  bookCount: number = 0;
  sourceCount: number = 0;

  constructor(snapshot: AppBackupSnapshot) {
    this.exportedAt = snapshot.exportedAt;
    this.bookCount = snapshot.preferences.favorites.length;
    this.sourceCount = snapshot.ruleSources?.length ?? 0;
  }
}

export class CloudBackupOptions {
  previousDigest: string = '';
  protectExisting: boolean = false;
}

export class CloudBackupResult {
  accountId: string = '';
  uploaded: boolean = false;
  exportedAt: number = 0;
  digest: string = '';
}

class CloudBackupFile {
  path: string;
  generation: number;

  constructor(path: string, generation: number) {
    this.path = path;
    this.generation = generation;
  }
}

const SYNC_TIMEOUT_MS: number = 120000;
const MAX_BACKUP_BYTES: number = 32 * 1024 * 1024;
const COPY_BUFFER_BYTES: number = 256 * 1024;
// Stat.location 是位标记：1 本地、2 云端、3 两者都有（API 11 起）。
const LOCATION_CLOUD: number = 2;
const LOCATION_LOCAL_AND_CLOUD: number = 3;

/** 使用系统账号的应用云文件目录；不依赖开发者云存储、密钥或业务服务器。 */
@ObservedV2
export class CloudBackupService {
  private static singleton: CloudBackupService | null = null;

  static get instance(): CloudBackupService {
    // 在装饰器初始化后创建实例，使 @Trace 的时间和进度变化能通知页面。
    if (!CloudBackupService.singleton) CloudBackupService.singleton = new CloudBackupService();
    return CloudBackupService.singleton;
  }

  @Trace busy: boolean = false;
  @Trace phase: CloudBackupPhase = CloudBackupPhase.IDLE;
  @Trace lastBackupAt: number = 0;
  private cancelled: boolean = false;
  private cancelTransfer: (() => void) | null = null;

  /** 只读取已经同步成功的本地元数据，进入页面不会自动上传用户数据。 */
  async refresh(context: common.Context): Promise<void> {
    if (this.busy) return;
    this.lastBackupAt = 0;
    const accountId = AuthService.instance.openID;
    if (!AuthService.instance.isLoggedIn || !accountId) return;
    try {
      const legacyPath = await this.cloudPath(context, accountId);
      const path = await this.latestCloudPath(context, legacyPath, true);
      const snapshot = await AppBackupService.readSnapshot(path);
      if (!this.busy && AuthService.instance.openID === accountId && AuthService.instance.isLoggedIn) {
        this.lastBackupAt = snapshot.exportedAt;
      }
    } catch (_error) { /* 云空间未就绪或本机尚无该备份时保持未知，手动操作会给出具体错误。 */ }
  }

  async backup(context: common.Context, options: CloudBackupOptions = new CloudBackupOptions()): Promise<CloudBackupResult> {
    const accountId = this.begin();
    const staging = `${context.cacheDir}/cloud_backup_upload.json`;
    let pending = '';
    let stage = 'account';
    let failureCode = CloudBackupErrorCode.SERVER;
    try {
      await this.assertAccount(context, accountId);
      stage = 'cloud_path';
      failureCode = CloudBackupErrorCode.CLOUD_FILE_FAILURE;
      const legacyPath = await this.cloudPath(context, accountId);
      // 先检查云服务可用性，再生成、放入用户明确要求上传的快照。
      stage = 'sync_before_upload';
      failureCode = CloudBackupErrorCode.SERVER;
      await this.sync(context, accountId);
      await this.assertAccount(context, accountId);
      // 必须先同步远端目录。新安装不能把本地暂时没有文件当作云端没有备份。
      if (options.protectExisting && (await this.cloudFiles(context, legacyPath)).length > 0) {
        throw new CloudBackupError(CloudBackupErrorCode.EXISTING_BACKUP);
      }
      this.phase = CloudBackupPhase.PREPARING;
      stage = 'create_snapshot';
      failureCode = CloudBackupErrorCode.LOCAL_FAILURE;
      await AppBackupService.createSnapshot(context, staging, true);
      stage = 'validate_snapshot';
      const snapshot = await AppBackupService.readSnapshot(staging);
      const result = new CloudBackupResult();
      result.accountId = accountId;
      result.digest = await this.snapshotDigest(snapshot);
      await this.assertAccount(context, accountId);
      if (options.previousDigest && options.previousDigest === result.digest) return result;
      stage = 'copy_to_cloud';
      failureCode = CloudBackupErrorCode.CLOUD_FILE_FAILURE;
      const files = await this.cloudFiles(context, legacyPath);
      const generation = Math.max(snapshot.exportedAt, (files[0]?.generation ?? 0) + 1);
      // 云目录不支持覆盖重命名：每次写入新文件，确认上传后才清理较旧的版本。
      const path = `${legacyPath.slice(0, -5)}_${generation}_${util.generateRandomUUID(false)}.json`;
      pending = `${path}.pending`;
      await this.copyBackupFile(staging, pending);
      await this.assertAccount(context, accountId);
      stage = 'commit_cloud_file';
      await fileIo.moveFile(pending, path);
      pending = '';
      stage = 'sync_upload';
      failureCode = CloudBackupErrorCode.SERVER;
      await this.sync(context, accountId, path);
      await this.assertAccount(context, accountId);
      await this.pruneCloudFiles(context, accountId, legacyPath, path);
      await this.assertAccount(context, accountId);
      this.lastBackupAt = snapshot.exportedAt;
      result.uploaded = true;
      result.exportedAt = snapshot.exportedAt;
      return result;
    } catch (error) {
      const failure = this.normalizeError(error, failureCode);
      this.logFailure('backup', stage, failure);
      throw failure;
    } finally {
      // 只清理当前账号本次写入的临时文件，绝不先删除已确认的备份。
      if (pending && AuthService.instance.isLoggedIn && AuthService.instance.openID === accountId) {
        await this.removeLocal(pending);
      }
      await this.removeLocal(staging);
      await this.removeLocal(`${staging}.tmp`);
      this.end();
    }
  }

  private async snapshotDigest(snapshot: AppBackupSnapshot): Promise<string> {
    const exportedAt = snapshot.exportedAt;
    snapshot.exportedAt = 0;
    const content = JSON.stringify(snapshot);
    snapshot.exportedAt = exportedAt;
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: new util.TextEncoder().encodeInto(content) });
    const result = await digest.digest();
    let value = '';
    for (const byte of result.data) value += byte.toString(16).padStart(2, '0');
    return value;
  }

  async restore(context: common.Context, confirm: (info: CloudBackupInfo) => Promise<boolean>): Promise<boolean> {
    const accountId = this.begin();
    const staging = `${context.cacheDir}/cloud_backup_restore.json`;
    let stage = 'account';
    let failureCode = CloudBackupErrorCode.SERVER;
    try {
      await this.assertAccount(context, accountId);
      stage = 'cloud_path';
      failureCode = CloudBackupErrorCode.CLOUD_FILE_FAILURE;
      const legacyPath = await this.cloudPath(context, accountId);
      stage = 'sync_before_restore';
      failureCode = CloudBackupErrorCode.SERVER;
      await this.sync(context, accountId);
      await this.assertAccount(context, accountId);
      stage = 'inspect_cloud_file';
      const path = await this.latestCloudPath(context, legacyPath);
      const stat = await fileIo.stat(path);
      const state = cloudSync.getCoreFileSyncState(fileUri.getUriFromPath(path));
      if ((stat.location & LOCATION_CLOUD) === 0 ||
        (state !== cloudSync.FileState.UPLOAD_SUCCESS && state !== cloudSync.FileState.INITIAL_AFTER_DOWNLOAD)) {
        throw new CloudBackupError(CloudBackupErrorCode.SERVER);
      }
      if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_BACKUP_BYTES) {
        throw new CloudBackupError(CloudBackupErrorCode.INVALID_BACKUP);
      }
      if (stat.location === LOCATION_CLOUD) {
        stage = 'download';
        await this.download(context, accountId, fileUri.getUriFromPath(path));
      }
      await this.assertAccount(context, accountId);
      stage = 'copy_from_cloud';
      failureCode = CloudBackupErrorCode.CLOUD_FILE_FAILURE;
      await this.copyBackupFile(path, staging);
      stage = 'validate_snapshot';
      let snapshot: AppBackupSnapshot;
      try {
        snapshot = await AppBackupService.readSnapshot(staging);
      } catch (_error) {
        throw new CloudBackupError(CloudBackupErrorCode.INVALID_BACKUP);
      }
      this.lastBackupAt = snapshot.exportedAt;
      this.phase = CloudBackupPhase.CONFIRMING;
      stage = 'confirm_restore';
      if (!await confirm(new CloudBackupInfo(snapshot))) return false;
      await this.assertAccount(context, accountId);
      this.phase = CloudBackupPhase.PREPARING;
      // 放在 filesDir，不进入云目录，失败后仍保留恢复前的本机快照。
      stage = 'safety_snapshot';
      failureCode = CloudBackupErrorCode.LOCAL_FAILURE;
      await AppBackupService.createSnapshot(context, `${context.filesDir}/backup/before_cloud_restore.json`, true);
      await this.assertAccount(context, accountId);
      this.phase = CloudBackupPhase.RESTORING;
      stage = 'restore_snapshot';
      try {
        if (!await AppBackupService.restoreSnapshot(context, staging, true)) {
          throw new Error('Empty backup');
        }
      } catch (error) {
        throw new CloudBackupError(CloudBackupErrorCode.RESTORE_FAILED,
          typeof error.code === 'number' ? error.code : 0);
      }
      return true;
    } catch (error) {
      const failure = this.normalizeError(error, failureCode);
      this.logFailure('restore', stage, failure);
      throw failure;
    } finally {
      await this.removeLocal(staging);
      this.end();
    }
  }

  cancel(): void {
    if (!this.busy || this.phase === CloudBackupPhase.RESTORING) return;
    this.cancelled = true;
    this.cancelTransfer?.();
  }

  private begin(): string {
    AuthService.instance.beginDataOperation();
    this.busy = true;
    this.cancelled = false;
    this.phase = CloudBackupPhase.PREPARING;
    return AuthService.instance.openID;
  }

  private end(): void {
    this.cancelTransfer = null;
    this.busy = false;
    this.phase = CloudBackupPhase.IDLE;
    AuthService.instance.endDataOperation();
  }

  private async cloudPath(context: common.Context, accountId: string): Promise<string> {
    if (!context.cloudFileDir) throw new CloudBackupError(CloudBackupErrorCode.UNAVAILABLE);
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: new util.TextEncoder().encodeInto(accountId) });
    const result = await digest.digest();
    let accountKey = '';
    for (const byte of result.data) accountKey += byte.toString(16).padStart(2, '0');
    // 系统账号云空间本身隔离，再按授权账号区分文件，防止系统换号后的旧缓存误恢复。
    return `${context.cloudFileDir}/listenbook_${accountKey}.json`;
  }

  private async cloudFiles(context: common.Context, legacyPath: string): Promise<CloudBackupFile[]> {
    const legacyName = legacyPath.slice(legacyPath.lastIndexOf('/') + 1);
    const prefix = `${legacyName.slice(0, -5)}_`;
    const files: CloudBackupFile[] = [];
    for (const name of await fileIo.listFile(context.cloudFileDir)) {
      if (name === legacyName) {
        files.push(new CloudBackupFile(legacyPath, 0));
      } else if (name.startsWith(prefix)) {
        const suffix = name.slice(prefix.length);
        if (!new RegExp('^[0-9]+_[0-9a-f-]{36}\\.json$').test(suffix)) continue;
        const generation = Number(suffix.slice(0, suffix.indexOf('_')));
        if (Number.isSafeInteger(generation) && generation > 0) {
          files.push(new CloudBackupFile(`${context.cloudFileDir}/${name}`, generation));
        }
      }
    }
    return files.sort((left: CloudBackupFile, right: CloudBackupFile): number => right.generation - left.generation);
  }

  private async latestCloudPath(context: common.Context, legacyPath: string, localOnly: boolean = false): Promise<string> {
    const files = await this.cloudFiles(context, legacyPath);
    if (files.length === 0) throw new CloudBackupError(CloudBackupErrorCode.NO_BACKUP);
    for (const file of files) {
      const stat = await fileIo.stat(file.path);
      if ((stat.location & LOCATION_CLOUD) === 0 || (localOnly && stat.location !== LOCATION_LOCAL_AND_CLOUD)) continue;
      const state = cloudSync.getCoreFileSyncState(fileUri.getUriFromPath(file.path));
      if (state === cloudSync.FileState.UPLOAD_SUCCESS || state === cloudSync.FileState.INITIAL_AFTER_DOWNLOAD) {
        return file.path;
      }
    }
    throw new CloudBackupError(CloudBackupErrorCode.SERVER);
  }

  private async pruneCloudFiles(context: common.Context, accountId: string, legacyPath: string, currentPath: string): Promise<void> {
    try {
      let retained = 0;
      for (const file of await this.cloudFiles(context, legacyPath)) {
        await this.assertAccount(context, accountId);
        if (file.path === currentPath) continue;
        const stat = await fileIo.stat(file.path);
        const state = cloudSync.getCoreFileSyncState(fileUri.getUriFromPath(file.path));
        if ((stat.location & LOCATION_CLOUD) === 0 || (state !== cloudSync.FileState.UPLOAD_SUCCESS &&
          state !== cloudSync.FileState.INITIAL_AFTER_DOWNLOAD)) continue;
        if (retained++ === 0) continue;
        await fileIo.unlink(file.path);
      }
    } catch (error) {
      // 本次已确认上传，清理失败不影响备份成功，也不继续删除。
      this.logFailure('backup', 'prune_old_files', this.normalizeError(error, CloudBackupErrorCode.CLOUD_FILE_FAILURE));
    }
  }

  private async assertAccount(context: common.Context, accountId: string): Promise<void> {
    if (this.cancelled) throw new CloudBackupError(CloudBackupErrorCode.CANCELLED);
    await AuthService.instance.restore(context);
    if (!AuthService.instance.isLoggedIn || AuthService.instance.openID !== accountId) {
      this.lastBackupAt = 0;
      throw new CloudBackupError(CloudBackupErrorCode.ACCOUNT_CHANGED);
    }
    if (this.cancelled) throw new CloudBackupError(CloudBackupErrorCode.CANCELLED);
  }

  private async sync(context: common.Context, accountId: string, uploadPath: string = ''): Promise<void> {
    this.phase = CloudBackupPhase.SYNCING;
    const task = new cloudSync.FileSync();
    let success = false;
    try {
      await new Promise<void>((resolve, reject) => {
        let done = false;
        let started = false;
        let completed = false;
        let pendingProgress: cloudSync.SyncProgress | null = null;
        let timeout: number = -1;
        let accountCheck: number = -1;
        let uploadCheck: number = -1;
        let retryTimer: number = -1;
        let startRetries: number = 0;
        const finish = (error: CloudBackupError | null): void => {
          if (done) return;
          done = true;
          clearTimeout(timeout);
          clearInterval(accountCheck);
          clearInterval(uploadCheck);
          clearTimeout(retryTimer);
          try { task.off('progress', onProgress); } catch (_error) { }
          this.cancelTransfer = null;
          if (error) reject(error);
          else resolve();
        };
        const checkUpload = (): void => {
          if (done || !started || !completed) return;
          if (!uploadPath) {
            finish(null);
            return;
          }
          try {
            const state = cloudSync.getCoreFileSyncState(fileUri.getUriFromPath(uploadPath));
            if (state === cloudSync.FileState.UPLOAD_SUCCESS) finish(null);
            else if (state === cloudSync.FileState.UPLOAD_FAILURE) finish(new CloudBackupError(CloudBackupErrorCode.SERVER));
          } catch (error) {
            if (error.code !== 13900002 && error.code !== 13900010) finish(this.normalizeError(error));
          }
        };
        const onProgress = (progress: cloudSync.SyncProgress): void => {
          if (done) return;
          if (!started) {
            pendingProgress = progress;
            return;
          }
          if (progress.error !== cloudSync.ErrorType.NO_ERROR) {
            finish(this.syncError(progress.error));
          } else if (progress.state === cloudSync.SyncState.COMPLETED) {
            // 回调可能只是上一次同步的状态，本次文件仍处于待上传或上传中。
            completed = true;
            checkUpload();
          } else if (progress.state === cloudSync.SyncState.UPLOAD_FAILED ||
            progress.state === cloudSync.SyncState.DOWNLOAD_FAILED) {
            finish(new CloudBackupError(CloudBackupErrorCode.SERVER));
          } else if (progress.state === cloudSync.SyncState.STOPPED) {
            finish(new CloudBackupError(CloudBackupErrorCode.CANCELLED));
          }
        };
        this.cancelTransfer = (): void => finish(new CloudBackupError(CloudBackupErrorCode.CANCELLED));
        timeout = setTimeout(() => finish(new CloudBackupError(CloudBackupErrorCode.TIMEOUT)), SYNC_TIMEOUT_MS);
        accountCheck = setInterval(() => {
          this.assertAccount(context, accountId).catch((error: CloudBackupError) => finish(error));
        }, 5000);
        if (uploadPath) uploadCheck = setInterval(checkUpload, 1000);
        const startTask = (): void => {
          if (done) return;
          this.assertAccount(context, accountId).then((): Promise<void> => {
            if (done) return Promise.resolve();
            return task.start();
          }).then((): void => {
            if (done) return;
            started = true;
            if (pendingProgress !== null) onProgress(pendingProgress);
          }).catch((error: BusinessError | CloudBackupError): void => {
            if (done) return;
            // 登录/网络切换后的云服务初始化可能短暂未就绪；只重试这一种启动错误。
            if (!(error instanceof CloudBackupError) && error.code === 22400001 && startRetries < 2) {
              startRetries++;
              pendingProgress = null;
              console.warn(`[CloudBackupService] stage=sync_start_retry attempt=${startRetries} systemCode=22400001`);
              DiagnosticLogService.info('cloud.sync.retry', `attempt=${startRetries}; systemCode=22400001`);
              retryTimer = setTimeout(startTask, startRetries === 1 ? 1000 : 3000);
              return;
            }
            finish(this.normalizeError(error));
          });
        };
        try {
          task.on('progress', onProgress);
          startTask();
        } catch (error) {
          finish(this.normalizeError(error));
        }
      });
      success = true;
    } finally {
      if (!success) {
        try { await task.stop(); } catch (_error) { }
      }
    }
  }

  private async download(context: common.Context, accountId: string, uri: string): Promise<void> {
    this.phase = CloudBackupPhase.DOWNLOADING;
    const task = new cloudSync.CloudFileCache();
    let success = false;
    try {
      await new Promise<void>((resolve, reject) => {
        let done = false;
        let timeout: number = -1;
        let accountCheck: number = -1;
        const finish = (error: CloudBackupError | null): void => {
          if (done) return;
          done = true;
          clearTimeout(timeout);
          clearInterval(accountCheck);
          try { task.off('progress', onProgress); } catch (_error) { }
          this.cancelTransfer = null;
          if (error) reject(error);
          else resolve();
        };
        const onProgress = (progress: cloudSync.DownloadProgress): void => {
          if (progress.uri !== uri) return;
          if (progress.state === cloudSync.State.COMPLETED) finish(null);
          else if (progress.state === cloudSync.State.STOPPED) {
            finish(new CloudBackupError(CloudBackupErrorCode.CANCELLED));
          } else if (progress.state === cloudSync.State.FAILED) {
            const code = progress.error === cloudSync.DownloadErrorType.NETWORK_UNAVAILABLE
              ? CloudBackupErrorCode.NETWORK : progress.error === cloudSync.DownloadErrorType.LOCAL_STORAGE_FULL
                ? CloudBackupErrorCode.LOCAL_FULL : CloudBackupErrorCode.SERVER;
            finish(new CloudBackupError(code));
          }
        };
        this.cancelTransfer = (): void => finish(new CloudBackupError(CloudBackupErrorCode.CANCELLED));
        timeout = setTimeout(() => finish(new CloudBackupError(CloudBackupErrorCode.TIMEOUT)), SYNC_TIMEOUT_MS);
        accountCheck = setInterval(() => {
          this.assertAccount(context, accountId).catch((error: CloudBackupError) => finish(error));
        }, 5000);
        try {
          task.on('progress', onProgress);
          task.start(uri).catch((error: BusinessError) => finish(this.normalizeError(error)));
        } catch (error) {
          finish(this.normalizeError(error));
        }
      });
      success = true;
    } finally {
      if (!success) {
        try { await task.stop(uri); } catch (_error) { }
      }
    }
  }

  private syncError(error: cloudSync.ErrorType): CloudBackupError {
    let code = CloudBackupErrorCode.SERVER;
    if (error === cloudSync.ErrorType.NETWORK_UNAVAILABLE || error === cloudSync.ErrorType.WIFI_UNAVAILABLE) {
      code = CloudBackupErrorCode.NETWORK;
    } else if (error === cloudSync.ErrorType.BATTERY_LEVEL_LOW || error === cloudSync.ErrorType.BATTERY_LEVEL_WARNING) {
      code = CloudBackupErrorCode.BATTERY;
    } else if (error === cloudSync.ErrorType.CLOUD_STORAGE_FULL) code = CloudBackupErrorCode.CLOUD_FULL;
    else if (error === cloudSync.ErrorType.LOCAL_STORAGE_FULL) code = CloudBackupErrorCode.LOCAL_FULL;
    else if (error === cloudSync.ErrorType.DEVICE_TEMPERATURE_TOO_HIGH) code = CloudBackupErrorCode.HOT;
    return new CloudBackupError(code);
  }

  private normalizeError(error: BusinessError | CloudBackupError,
    fallback: CloudBackupErrorCode = CloudBackupErrorCode.SERVER): CloudBackupError {
    if (error instanceof CloudBackupError) return error;
    const code = typeof error.code === 'number' ? error.code : 0;
    // IPC 故障不等于应用未开通云同步，不能引导用户反复切换账号/开关。
    if (code === 13600001) return new CloudBackupError(CloudBackupErrorCode.SYSTEM_SERVICE, code);
    if (code === 22400001) return new CloudBackupError(CloudBackupErrorCode.NOT_READY, code);
    if (code === 201 || code === 801 || code === 13900012) {
      return new CloudBackupError(CloudBackupErrorCode.UNAVAILABLE, code);
    }
    if (code === 22400002 || code === 13900044) return new CloudBackupError(CloudBackupErrorCode.NETWORK, code);
    if (code === 22400003) return new CloudBackupError(CloudBackupErrorCode.BATTERY, code);
    if (code === 22400005) return new CloudBackupError(CloudBackupErrorCode.SERVER, code);
    // FileIO 的 ENOSPC 是 13900025；13900028 实际为 Too many links。
    if (code === 13900025) return new CloudBackupError(CloudBackupErrorCode.LOCAL_FULL, code);
    return new CloudBackupError(fallback, code);
  }

  private logFailure(operation: string, stage: string, error: CloudBackupError): void {
    // 不记录云文件路径、账号标识或备份内容，保留定位所需的阶段与系统错误码。
    console.error(`[CloudBackupService] operation=${operation} stage=${stage} category=${error.code} systemCode=${error.systemCode}`);
    DiagnosticLogService.info('cloud.operation.failed',
      `operation=${operation}; stage=${stage}; category=${error.code}; systemCode=${error.systemCode}`);
  }

  /** 云目录使用普通读写，避免快捷复制所需的文件系统扩展操作；同时处理短读、短写。 */
  private async copyBackupFile(source: string, target: string): Promise<void> {
    const input = await fileIo.open(source, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(input.fd);
      if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_BACKUP_BYTES) {
        throw new CloudBackupError(CloudBackupErrorCode.INVALID_BACKUP);
      }
      const output = await fileIo.open(target,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        const buffer = new ArrayBuffer(COPY_BUFFER_BYTES);
        let total = 0;
        while (true) {
          if (this.cancelled) throw new CloudBackupError(CloudBackupErrorCode.CANCELLED);
          const length = await fileIo.read(input.fd, buffer, { length: buffer.byteLength });
          if (length === 0) break;
          if (length < 0 || length > buffer.byteLength || total + length > stat.size) {
            throw new CloudBackupError(CloudBackupErrorCode.INVALID_BACKUP);
          }
          let written = 0;
          while (written < length) {
            if (this.cancelled) throw new CloudBackupError(CloudBackupErrorCode.CANCELLED);
            const remaining = buffer.slice(written, length);
            const count = await fileIo.write(output.fd, remaining, { length: remaining.byteLength });
            if (count <= 0 || count > remaining.byteLength) {
              throw new CloudBackupError(CloudBackupErrorCode.CLOUD_FILE_FAILURE);
            }
            written += count;
          }
          total += length;
        }
        if (total !== stat.size) throw new CloudBackupError(CloudBackupErrorCode.INVALID_BACKUP);
        await fileIo.fsync(output.fd);
      } finally {
        await fileIo.close(output);
      }
    } finally {
      await fileIo.close(input);
    }
  }

  private async removeLocal(path: string): Promise<void> {
    try { await fileIo.unlink(path); } catch (_error) { }
  }
}
