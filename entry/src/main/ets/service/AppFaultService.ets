import { errorManager } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hiAppEvent, hilog } from '@kit.PerformanceAnalysisKit';
import { DiagnosticLogService } from './DiagnosticLogService';

class DiagnosticFaultParameters {
  external_log: string[] = [];
}

/** System reports retain the platform's original crash handling across all threads. */
export class AppFaultService {
  private static initialized: boolean = false;
  private static pending: Promise<void> = Promise.resolve();

  static initialize(): void {
    if (AppFaultService.initialized) return;
    AppFaultService.initialized = true;
    try {
      const watcher: hiAppEvent.Watcher = {
        name: 'listenbook_fault_reports',
        appEventFilters: [{ domain: hiAppEvent.domain.OS,
          names: [hiAppEvent.event.APP_CRASH, hiAppEvent.event.APP_FREEZE, hiAppEvent.event.APP_KILLED] }],
        triggerCondition: { row: 1 },
        onTrigger: (_rows: number, _bytes: number, holder: hiAppEvent.AppEventPackageHolder): void => {
          AppFaultService.drain(holder);
        }
      };
      const holder = hiAppEvent.addWatcher(watcher);
      AppFaultService.drain(holder);
    } catch (error) {
      DiagnosticLogService.fault('diagnostic.system_subscription', DiagnosticLogService.describe(error));
    }
    try {
      errorManager.on('globalUnhandledRejectionDetected', (error: errorManager.GlobalError): void => {
        DiagnosticLogService.fault('app.unhandled_rejection',
          `threadType=${error.instanceType}; threadName=${error.instanceName}\n${DiagnosticLogService.describe(error)}`);
      });
    } catch (error) {
      DiagnosticLogService.fault('diagnostic.promise_subscription', DiagnosticLogService.describe(error));
    }
  }

  private static drain(holder: hiAppEvent.AppEventPackageHolder): void {
    try {
      let packet: hiAppEvent.AppEventPackage | null = holder.takeNext();
      while (packet !== null) {
        for (const event of packet.appEventInfos) AppFaultService.receive(event);
        packet = holder.takeNext();
      }
    } catch (error) {
      DiagnosticLogService.fault('diagnostic.system_delivery', DiagnosticLogService.describe(error));
    }
  }

  private static receive(event: hiAppEvent.AppEventInfo): void {
    AppFaultService.pending = AppFaultService.pending.then(async (): Promise<void> => {
      const metadata = JSON.stringify(event.params);
      const params: DiagnosticFaultParameters = JSON.parse(metadata);
      const reports: string[] = [`event=${event.name}; domain=${event.domain}\n${metadata}`];
      const processed: string[] = [];
      for (const path of params.external_log ?? []) {
        try {
          reports.push(`--- System fault log ---\n${await fileIo.readText(path)}`);
          processed.push(path);
        } catch (error) {
          reports.push(`externalLogReadError=${DiagnosticLogService.describe(error)}`);
        }
      }
      await DiagnosticLogService.fault(`app.system.${event.name}`, reports.join('\n\n'));
      for (const path of processed) await fileIo.unlink(path);
    }).catch((error: Error): void => {
      hilog.error(0x0000, 'AppFault', 'Fault report processing failed: %{public}s', DiagnosticLogService.describe(error));
      DiagnosticLogService.fault('diagnostic.system_report', DiagnosticLogService.describe(error));
    });
  }

  static async flush(): Promise<void> { await AppFaultService.pending; }
}
