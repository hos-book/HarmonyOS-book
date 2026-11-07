import { common } from '@kit.AbilityKit';
import { fileIo, statfs } from '@kit.CoreFileKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';

export class DiagnosticLogEntry {
  id: string = '';
  time: string = '';
  level: string = 'INFO';
  stage: string = '';
  message: string = '';
}

/** 有界、仅本机保存的诊断记录；不采集书籍正文、账号、Cookie 或文件名。 */
export class DiagnosticLogService {
  private static context: common.Context | null = null;
  private static entries: DiagnosticLogEntry[] = [];
  private static chain: Promise<void> = Promise.resolve();
  private static sequence: number = 0;
  private static storageError: string = '';
  private static enabled: boolean = false;
  private static settings: preferences.Preferences | null = null;
  private static readonly MAX_ENTRIES: number = 200;
  private static readonly MAX_BYTES: number = 2 * 1024 * 1024;

  static init(context: common.Context): void {
    if (DiagnosticLogService.context !== null) return;
    DiagnosticLogService.context = context;
    try {
      DiagnosticLogService.settings = preferences.getPreferencesSync(context, { name: 'diagnostic_settings' });
      DiagnosticLogService.enabled = DiagnosticLogService.settings.getSync('enabled', false) === true;
    } catch (_error) {
      DiagnosticLogService.enabled = false;
    }
    DiagnosticLogService.chain = DiagnosticLogService.restore();
    DiagnosticLogService.info('app.start', `api=${deviceInfo.sdkApiVersion}; device=${deviceInfo.deviceType}`);
  }

  private static path(): string {
    return `${DiagnosticLogService.context?.filesDir}/diagnostic_log.json`;
  }

  static isEnabled(): boolean { return DiagnosticLogService.enabled; }

  static async setEnabled(enabled: boolean): Promise<void> {
    const context = DiagnosticLogService.context;
    if (context === null) throw new Error('Diagnostic logging is not initialized');
    const settings = DiagnosticLogService.settings ??
      preferences.getPreferencesSync(context, { name: 'diagnostic_settings' });
    DiagnosticLogService.settings = settings;
    const previous = DiagnosticLogService.enabled;
    if (!enabled) DiagnosticLogService.enabled = false;
    try {
      settings.putSync('enabled', enabled);
      await settings.flush();
      DiagnosticLogService.enabled = enabled;
    } catch (error) {
      settings.putSync('enabled', previous);
      DiagnosticLogService.enabled = previous;
      throw new Error(DiagnosticLogService.describe(error));
    }
    await DiagnosticLogService.chain;
  }

  private static async restore(): Promise<void> {
    try {
      const path = DiagnosticLogService.path();
      if (!await fileIo.access(path)) return;
      if ((await fileIo.stat(path)).size > DiagnosticLogService.MAX_BYTES) {
        DiagnosticLogService.storageError = 'Saved log exceeded size limit';
        return;
      }
      const saved: DiagnosticLogEntry[] = JSON.parse(await fileIo.readText(path));
      if (!Array.isArray(saved)) throw new Error('Invalid log format');
      DiagnosticLogService.entries = saved.filter((entry: DiagnosticLogEntry): boolean =>
        entry !== null && typeof entry.id === 'string' && typeof entry.time === 'string' &&
        typeof entry.level === 'string' && typeof entry.stage === 'string' && typeof entry.message === 'string')
        .slice(-DiagnosticLogService.MAX_ENTRIES);
    } catch (error) {
      DiagnosticLogService.storageError = DiagnosticLogService.describe(error);
    }
  }

  static sanitize(message: string): string {
    return message
      .replace(/(?:https?|file|content):\/\/[^\s"'<>]+/gi, '[uri]')
      .replace(/\/(?:data|storage|mnt)\/[^\s"'<>]+/g, '[path]')
      .replace(/(authorization|cookie|token|password|secret)\s*[:=]\s*[^\s,;]+/gi, '$1=[redacted]')
      .substring(0, 1500);
  }

  static describe(error: BusinessError): string {
    const message = error && typeof error.message === 'string' ? error.message : String(error);
    const code = error && typeof error.code === 'number' ? `code=${error.code}; ` : '';
    return DiagnosticLogService.sanitize(code + message);
  }

  static info(stage: string, message: string): void {
    DiagnosticLogService.record('INFO', stage, message);
  }

  static failure(stage: string, error: BusinessError, detail: string = ''): void {
    if (!DiagnosticLogService.enabled) return;
    DiagnosticLogService.record('ERROR', stage, `${detail} ${DiagnosticLogService.describe(error)}`.trim());
  }

  private static record(level: string, stage: string, message: string): void {
    if (!DiagnosticLogService.enabled) return;
    const entry = new DiagnosticLogEntry();
    entry.id = `${Date.now()}_${++DiagnosticLogService.sequence}`;
    entry.time = new Date().toISOString();
    entry.level = level;
    entry.stage = stage;
    entry.message = DiagnosticLogService.sanitize(message);
    if (level === 'ERROR') {
      hilog.error(0x0000, 'AppDiagnostic', '%{public}s %{public}s', stage, entry.message);
    } else {
      hilog.info(0x0000, 'AppDiagnostic', '%{public}s %{public}s', stage, entry.message);
    }
    DiagnosticLogService.chain = DiagnosticLogService.chain.then(async (): Promise<void> => {
      if (!DiagnosticLogService.enabled) return;
      DiagnosticLogService.entries.push(entry);
      DiagnosticLogService.entries = DiagnosticLogService.entries.slice(-DiagnosticLogService.MAX_ENTRIES);
      await DiagnosticLogService.persist();
    }).catch((error: BusinessError): void => {
      DiagnosticLogService.storageError = DiagnosticLogService.describe(error);
    });
  }

  private static async persist(): Promise<void> {
    if (DiagnosticLogService.context === null) return;
    const path = DiagnosticLogService.path();
    const file = await fileIo.open(`${path}.tmp`,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try { await fileIo.write(file.fd, JSON.stringify(DiagnosticLogService.entries)); }
    finally { await fileIo.close(file); }
    await fileIo.moveFile(`${path}.tmp`, path);
    DiagnosticLogService.storageError = '';
  }

  static async list(): Promise<DiagnosticLogEntry[]> {
    await DiagnosticLogService.chain;
    return DiagnosticLogService.entries.slice().reverse();
  }

  static getStorageError(): string { return DiagnosticLogService.storageError; }

  static async clear(): Promise<void> {
    const task = DiagnosticLogService.chain.then(async (): Promise<void> => {
      DiagnosticLogService.entries = [];
      await DiagnosticLogService.persist();
    });
    DiagnosticLogService.chain = task.catch((error: BusinessError): void => {
      DiagnosticLogService.storageError = DiagnosticLogService.describe(error);
    });
    await task;
  }

  static async check(): Promise<void> {
    if (!DiagnosticLogService.enabled) return;
    const context = DiagnosticLogService.context;
    if (context === null) return;
    DiagnosticLogService.info('check.runtime', `api=${deviceInfo.sdkApiVersion}; device=${deviceInfo.deviceType}; ` +
      'epub=self');
    try {
      const free = await statfs.getFreeSize(context.filesDir);
      DiagnosticLogService.info('check.storage', `freeMiB=${Math.floor(free / 1024 / 1024)}`);
      if (free < 256 * 1024 * 1024) throw new Error('Free space is below import reserve (256 MiB)');
      // 实际写入并读取独立探针，不触碰书架或书籍文件。
      const path = `${context.cacheDir}/diagnostic_probe.tmp`;
      const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try { await fileIo.write(file.fd, 'ok'); } finally { await fileIo.close(file); }
      try {
        if (await fileIo.readText(path) !== 'ok') throw new Error('Storage readback failed');
      } finally { await fileIo.unlink(path); }
      DiagnosticLogService.info('check.storage', 'read/write OK');
    } catch (error) { DiagnosticLogService.failure('check.storage', error); }
    await DiagnosticLogService.chain;
  }
}
