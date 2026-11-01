import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util, url } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { AppBackupService, AppBackupSnapshot } from './AppBackupService';
import { AuthService } from './AuthService';

export class WebDavSettings {
  address: string = '';
  username: string = '';
  password: string = '';
}

export enum WebDavErrorCode { CONFIG, AUTH, NOT_FOUND, NETWORK, SERVER, TOO_LARGE, INVALID, RESTORE, CANCELLED }
export class WebDavBackupError extends Error {
  code: WebDavErrorCode;
  constructor(code: WebDavErrorCode) { super('WebDAV operation failed'); this.code = code; }
}
export enum WebDavPhase { IDLE, PREPARING, CONNECTING, UPLOADING, DOWNLOADING, CONFIRMING, RESTORING }
class WebDavResponse {
  status: number = 0;
  bytes: ArrayBuffer = new ArrayBuffer(0);
}

const MAX_BYTES: number = 32 * 1024 * 1024;
const BACKUP_NAME: string = 'listenbook-backup.json';

/** Credentials stay in a separate encrypted database, outside every exported backup. */
@ObservedV2
export class WebDavBackupService {
  static readonly instance: WebDavBackupService = new WebDavBackupService();
  @Trace busy: boolean = false;
  @Trace phase: WebDavPhase = WebDavPhase.IDLE;
  private cancelled: boolean = false;
  private session: rcp.Session | undefined = undefined;

  private async store(context: common.Context): Promise<relationalStore.RdbStore> {
    const store = await relationalStore.getRdbStore(context, { name: 'webdav_credentials.db',
      securityLevel: relationalStore.SecurityLevel.S2, encrypt: true, allowRebuild: false });
    await store.executeSql('CREATE TABLE IF NOT EXISTS config (id INTEGER PRIMARY KEY, address TEXT, username TEXT, password TEXT)');
    return store;
  }

  async loadSettings(context: common.Context): Promise<WebDavSettings> {
    const store = await this.store(context);
    const rows = await store.querySql('SELECT address, username, password FROM config WHERE id = 1');
    try {
      const settings = new WebDavSettings();
      if (rows.goToFirstRow()) {
        settings.address = rows.getString(0);
        settings.username = rows.getString(1);
        settings.password = rows.getString(2);
      }
      return settings;
    } finally { rows.close(); }
  }

  async saveSettings(context: common.Context, settings: WebDavSettings): Promise<void> {
    const valid = WebDavBackupService.normalize(settings);
    const store = await this.store(context);
    await store.executeSql('INSERT OR REPLACE INTO config (id, address, username, password) VALUES (1, ?, ?, ?)',
      [valid.address, valid.username, valid.password]);
  }

  async clearSettings(context: common.Context): Promise<void> {
    const store = await this.store(context);
    await store.executeSql('DELETE FROM config');
  }

  static normalize(settings: WebDavSettings): WebDavSettings {
    try {
      const parsed = url.URL.parseURL(settings.address.trim());
      if (!['https:', 'http:'].includes(parsed.protocol) || !parsed.hostname || parsed.username || parsed.password ||
        parsed.search || parsed.hash || !settings.username.trim() || settings.username.includes(':') ||
        /[\r\n]/.test(settings.username) || !settings.password) throw new Error('Invalid settings');
      const result = new WebDavSettings();
      result.address = parsed.href.endsWith('/') ? parsed.href : parsed.href + '/';
      result.username = settings.username.trim();
      result.password = settings.password;
      return result;
    } catch (_error) { throw new WebDavBackupError(WebDavErrorCode.CONFIG); }
  }

  async test(settings: WebDavSettings): Promise<void> {
    const config = WebDavBackupService.normalize(settings);
    this.begin();
    try {
      this.phase = WebDavPhase.CONNECTING;
      const result = await this.send(config, config.address, 'PROPFIND',
        '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>');
      if (result.status !== 207) throw new WebDavBackupError(WebDavErrorCode.SERVER);
    } finally { this.end(); }
  }

  async backup(context: common.Context, settings: WebDavSettings): Promise<void> {
    const config = WebDavBackupService.normalize(settings);
    this.begin();
    const staging = `${context.cacheDir}/webdav_export.json`;
    const temporary = `${config.address}.listenbook-${util.generateRandomUUID()}.tmp`;
    let uploaded = false;
    try {
      await AppBackupService.createSnapshot(context, staging, true);
      await AppBackupService.readSnapshot(staging);
      this.checkCancelled();
      const body = await fileIo.readText(staging);
      if (new util.TextEncoder().encodeInto(body).byteLength > MAX_BYTES) throw new WebDavBackupError(WebDavErrorCode.TOO_LARGE);
      this.phase = WebDavPhase.UPLOADING;
      uploaded = true;
      await this.send(config, temporary, 'PUT', body);
      // Publish only after a complete upload; a failed PUT never replaces the previous backup.
      await this.send(config, temporary, 'MOVE', '', config.address + BACKUP_NAME);
      uploaded = false;
    } finally {
      if (uploaded) {
        try { await this.send(config, temporary, 'DELETE', '', '', true); } catch (_error) {}
      }
      await this.remove(staging);
      await this.remove(staging + '.tmp');
      this.end();
    }
  }

  async restore(context: common.Context, settings: WebDavSettings,
    confirm: (snapshot: AppBackupSnapshot) => Promise<boolean>): Promise<boolean> {
    const config = WebDavBackupService.normalize(settings);
    this.begin();
    const staging = `${context.cacheDir}/webdav_restore.json`;
    const safety = `${context.filesDir}/backup/before_webdav_restore.json`;
    try {
      this.phase = WebDavPhase.DOWNLOADING;
      const response = await this.send(config, config.address + BACKUP_NAME, 'GET');
      if (response.status !== 200 || response.bytes.byteLength === 0) throw new WebDavBackupError(WebDavErrorCode.INVALID);
      await this.write(staging, response.bytes);
      let snapshot: AppBackupSnapshot;
      try { snapshot = await AppBackupService.readSnapshot(staging); }
      catch (_error) { throw new WebDavBackupError(WebDavErrorCode.INVALID); }
      this.checkCancelled();
      this.phase = WebDavPhase.CONFIRMING;
      if (!await confirm(snapshot)) return false;
      this.checkCancelled();
      this.phase = WebDavPhase.PREPARING;
      await AppBackupService.createSnapshot(context, safety, true);
      await AppBackupService.readSnapshot(safety);
      this.checkCancelled();
      this.phase = WebDavPhase.RESTORING;
      try {
        if (!await AppBackupService.restoreSnapshot(context, staging, true)) throw new Error('Missing snapshot');
      } catch (_error) { throw new WebDavBackupError(WebDavErrorCode.RESTORE); }
      return true;
    } finally {
      await this.remove(staging);
      await this.remove(safety + '.tmp');
      this.end();
    }
  }

  cancel(): void {
    if (!this.busy || this.phase === WebDavPhase.RESTORING) return;
    this.cancelled = true;
    this.session?.close();
  }

  private begin(): void {
    if (this.busy) throw new WebDavBackupError(WebDavErrorCode.SERVER);
    AuthService.instance.beginDataOperation(false);
    this.busy = true;
    this.cancelled = false;
    this.phase = WebDavPhase.PREPARING;
  }
  private end(): void {
    this.session = undefined;
    this.busy = false;
    this.phase = WebDavPhase.IDLE;
    AuthService.instance.endDataOperation();
  }
  private checkCancelled(): void {
    if (this.cancelled) throw new WebDavBackupError(WebDavErrorCode.CANCELLED);
  }

  private async send(config: WebDavSettings, address: string, method: string, body: string = '',
    destination: string = '', cleanup: boolean = false): Promise<WebDavResponse> {
    if (!cleanup) this.checkCancelled();
    const token = new util.Base64Helper().encodeToStringSync(
      new util.TextEncoder().encodeInto(`${config.username}:${config.password}`));
    const headers: Record<string, string> = { 'Authorization': `Basic ${token}`, 'Depth': '0',
      'Content-Type': method === 'PROPFIND' ? 'application/xml; charset=utf-8' : 'application/json; charset=utf-8' };
    if (destination) { headers['Destination'] = destination; headers['Overwrite'] = 'T'; }
    const request = new rcp.Request(address, method, headers, body || undefined);
    request.configuration = { transfer: { autoRedirect: false, timeout: { connectMs: 15000, transferMs: cleanup ? 10000 : 60000 } },
      security: { remoteValidation: 'system' } };
    const chunks: Uint8Array[] = [];
    let total = 0;
    let oversized = false;
    const limit = method === 'GET' ? MAX_BYTES : 1024 * 1024;
    const session = rcp.createSession();
    this.session = session;
    request.destination = (chunk: ArrayBuffer): void => {
      total += chunk.byteLength;
      if (total > limit) { oversized = true; session.close(); return; }
      chunks.push(new Uint8Array(chunk));
    };
    try {
      const response = await session.fetch(request);
      if (!cleanup) this.checkCancelled();
      if (oversized) throw new WebDavBackupError(WebDavErrorCode.TOO_LARGE);
      if (response.statusCode === 401 || response.statusCode === 403) throw new WebDavBackupError(WebDavErrorCode.AUTH);
      if (response.statusCode === 404) throw new WebDavBackupError(WebDavErrorCode.NOT_FOUND);
      if (response.statusCode < 200 || response.statusCode >= 300) throw new WebDavBackupError(WebDavErrorCode.SERVER);
      const buffer = new ArrayBuffer(total);
      const bytes = new Uint8Array(buffer);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      const result: WebDavResponse = new WebDavResponse();
      result.status = response.statusCode;
      result.bytes = buffer;
      return result;
    } catch (error) {
      if (!cleanup) this.checkCancelled();
      if (oversized) throw new WebDavBackupError(WebDavErrorCode.TOO_LARGE);
      if (error instanceof WebDavBackupError) throw error;
      throw new WebDavBackupError(WebDavErrorCode.NETWORK);
    } finally { session.close(); if (this.session === session) this.session = undefined; }
  }

  private async write(path: string, bytes: ArrayBuffer): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      let offset = 0;
      while (offset < bytes.byteLength) {
        const written = await fileIo.write(file.fd, bytes.slice(offset));
        if (written <= 0) throw new WebDavBackupError(WebDavErrorCode.INVALID);
        offset += written;
      }
      await fileIo.fsync(file.fd);
    } finally { await fileIo.close(file); }
  }
  private async remove(path: string): Promise<void> { try { await fileIo.unlink(path); } catch (_error) {} }
}
