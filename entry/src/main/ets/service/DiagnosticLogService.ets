import { AbilityConstant, bundleManager, common } from '@kit.AbilityKit';
import { fileIo, statfs } from '@kit.CoreFileKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { DiagnosticLogArchive, DiagnosticLogEntry } from './DiagnosticLogArchive';

export { DiagnosticLogEntry } from './DiagnosticLogArchive';

class DiagnosticErrorMetadata {
  code: number | undefined = undefined;
}

/** 本机诊断记录；敏感凭据按统一规则脱敏。 */
export class DiagnosticLogService {
  private static context: common.Context | null = null;
  private static events: DiagnosticLogArchive | null = null;
  private static faults: DiagnosticLogArchive | null = null;
  private static chain: Promise<void> = Promise.resolve();
  private static sequence: number = 0;
  private static storageError: string = '';
  private static enabled: boolean = false;
  private static settings: preferences.Preferences | null = null;
  private static version: string = '';

  static init(context: common.Context): void {
    if (DiagnosticLogService.context !== null) return;
    DiagnosticLogService.context = context;
    DiagnosticLogService.events = new DiagnosticLogArchive(`${context.filesDir}/diagnostic_events`);
    DiagnosticLogService.faults = new DiagnosticLogArchive(`${context.filesDir}/diagnostic_faults`);
    try {
      DiagnosticLogService.settings = preferences.getPreferencesSync(context, { name: 'diagnostic_settings' });
      DiagnosticLogService.enabled = DiagnosticLogService.settings.getSync('enabled', false) === true;
      const bundle = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      DiagnosticLogService.version = `${bundle.name} ${bundle.versionName} (${bundle.versionCode})`;
    } catch (error) {
      DiagnosticLogService.storageError = DiagnosticLogService.describe(error);
    }
    DiagnosticLogService.chain = DiagnosticLogService.initialize().catch((error: Error): void => {
      DiagnosticLogService.storageError = DiagnosticLogService.describe(error);
    });
    DiagnosticLogService.info('app.start', DiagnosticLogService.environment());
  }

  private static async initialize(): Promise<void> {
    await DiagnosticLogService.events?.initialize();
    await DiagnosticLogService.faults?.initialize();
    const legacy = `${DiagnosticLogService.context?.filesDir}/diagnostic_log.json`;
    if (await fileIo.access(legacy)) {
      const entries: DiagnosticLogEntry[] = JSON.parse(await fileIo.readText(legacy));
      for (const entry of entries) await DiagnosticLogService.events?.append(entry);
      await fileIo.unlink(legacy);
    }
  }

  static environment(): string {
    return `app=${DiagnosticLogService.version}; api=${deviceInfo.sdkApiVersion}; ` +
      `os=${deviceInfo.osFullName}; device=${deviceInfo.deviceType}`;
  }

  static isEnabled(): boolean { return DiagnosticLogService.enabled; }

  static async setEnabled(enabled: boolean): Promise<void> {
    const context = DiagnosticLogService.context;
    if (context === null) throw new Error('Diagnostic logging requires initialization');
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

  static sanitize(message: string): string {
    return message
      .replace(/(?:https?|file|content):\/\/[^\s"'<>]+/gi, '[uri]')
      .replace(/\/(?:data|storage|mnt)\/[^\s"'<>]+/g, '[path]')
      .replace(/(authorization|cookie|token|password|secret)\s*[:=]\s*[^\s,;]+/gi, '$1=[redacted]');
  }

  static describe(error: Error): string {
    const message = error && typeof error.message === 'string' ? error.message : String(error);
    const metadata: DiagnosticErrorMetadata = error ? JSON.parse(JSON.stringify(error, ['code'])) :
      new DiagnosticErrorMetadata();
    const code = typeof metadata.code === 'number' ? `code=${metadata.code}; ` : '';
    const stack = error && typeof error.stack === 'string' ? error.stack : '';
    return DiagnosticLogService.sanitize(`${code}${error?.name ?? 'Error'}: ${message}` +
      (stack.length > 0 ? `\n${stack}` : ''));
  }

  static info(stage: string, message: string): void {
    if (DiagnosticLogService.enabled) DiagnosticLogService.record('INFO', stage, message.substring(0, 16384), false);
  }

  static failure(stage: string, error: Error, detail: string = ''): void {
    if (DiagnosticLogService.enabled) {
      DiagnosticLogService.record('ERROR', stage, `${detail} ${DiagnosticLogService.describe(error)}`.trim(), false);
    }
  }

  static fault(stage: string, message: string): Promise<void> {
    return DiagnosticLogService.record('ERROR', stage, `${DiagnosticLogService.environment()}\n${message}`, true);
  }

  static lastExit(reason: number, message: string): void {
    const detail = `reason=${reason}; message=${message}`;
    switch (reason) {
      case AbilityConstant.LastExitReason.ABILITY_NOT_RESPONDING:
      case AbilityConstant.LastExitReason.CPP_CRASH:
      case AbilityConstant.LastExitReason.JS_ERROR:
      case AbilityConstant.LastExitReason.APP_FREEZE:
      case AbilityConstant.LastExitReason.PERFORMANCE_CONTROL:
      case AbilityConstant.LastExitReason.RESOURCE_CONTROL:
      case AbilityConstant.LastExitReason.SIGNAL:
        DiagnosticLogService.fault('app.lastExit', detail);
        break;
      default:
        DiagnosticLogService.info('app.lastExit', detail);
    }
  }

  private static record(level: string, stage: string, message: string, fault: boolean): Promise<void> {
    const entry = new DiagnosticLogEntry();
    entry.id = `${Date.now()}_${++DiagnosticLogService.sequence}`;
    entry.time = new Date().toISOString();
    entry.level = level;
    entry.stage = stage;
    entry.message = DiagnosticLogService.sanitize(message);
    if (level === 'ERROR') {
      hilog.error(0x0000, 'AppDiagnostic', '%{public}s %{public}s', stage, entry.message.substring(0, 3000));
    } else {
      hilog.info(0x0000, 'AppDiagnostic', '%{public}s %{public}s', stage, entry.message.substring(0, 3000));
    }
    const task = DiagnosticLogService.chain.then(async (): Promise<void> => {
      const archive = fault ? DiagnosticLogService.faults : DiagnosticLogService.events;
      await archive?.append(entry);
    });
    DiagnosticLogService.chain = task.catch((error: Error): void => {
      DiagnosticLogService.storageError = DiagnosticLogService.describe(error);
    });
    return task;
  }

  static async list(): Promise<DiagnosticLogEntry[]> {
    const task = DiagnosticLogService.chain.then(async (): Promise<DiagnosticLogEntry[]> => {
      const events = await DiagnosticLogService.events?.recent(2000) ?? [];
      const faults = await DiagnosticLogService.faults?.recent(100) ?? [];
      return events.concat(faults).sort((left: DiagnosticLogEntry, right: DiagnosticLogEntry): number =>
        right.time.localeCompare(left.time));
    });
    DiagnosticLogService.chain = task.then((): void => {}).catch((error: Error): void => {
      DiagnosticLogService.storageError = DiagnosticLogService.describe(error);
    });
    return task;
  }

  static getStorageError(): string { return DiagnosticLogService.storageError; }

  static async exportTo(uri: string, onlyErrors: boolean): Promise<void> {
    const task = DiagnosticLogService.chain.then(async (): Promise<void> => {
      const file = await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      const write = async (text: string): Promise<void> => {
        const bytes = new util.TextEncoder().encodeInto(text);
        await fileIo.write(file.fd, bytes.buffer);
      };
      const visit = async (entry: DiagnosticLogEntry): Promise<void> => {
        if (onlyErrors && entry.level !== 'ERROR') return;
        await write(`${entry.time} [${entry.level}] ${entry.stage}\n${entry.message}\n\n`);
      };
      try {
        await write(`ListenBook diagnostic export\n${DiagnosticLogService.environment()}\n` +
          `exportedAt=${new Date().toISOString()}; errorsOnly=${onlyErrors}\n\n=== Fault reports ===\n\n`);
        await DiagnosticLogService.faults?.visit(visit);
        await write('=== Runtime and search logs ===\n\n');
        await DiagnosticLogService.events?.visit(visit);
      } finally { await fileIo.close(file); }
    });
    DiagnosticLogService.chain = task.catch((error: Error): void => {
      DiagnosticLogService.storageError = DiagnosticLogService.describe(error);
    });
    await task;
  }

  static async clear(): Promise<void> {
    const task = DiagnosticLogService.chain.then(async (): Promise<void> => {
      await DiagnosticLogService.events?.clear();
      await DiagnosticLogService.faults?.clear();
      DiagnosticLogService.storageError = '';
    });
    DiagnosticLogService.chain = task.catch((error: Error): void => {
      DiagnosticLogService.storageError = DiagnosticLogService.describe(error);
    });
    await task;
  }

  static async check(): Promise<void> {
    if (!DiagnosticLogService.enabled) return;
    const context = DiagnosticLogService.context;
    if (context === null) return;
    DiagnosticLogService.info('check.runtime', DiagnosticLogService.environment() + '; epub=self');
    try {
      const free = await statfs.getFreeSize(context.filesDir);
      DiagnosticLogService.info('check.storage', `freeMiB=${Math.floor(free / 1024 / 1024)}`);
      if (free < 256 * 1024 * 1024) throw new Error('Free space is below import reserve (256 MiB)');
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
