import { pasteboard } from '@kit.BasicServicesKit';
import { DiagnosticLogEntry, DiagnosticLogService } from '../service/DiagnosticLogService';
import { AppTheme, AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { FrostedPageHeader } from '../components/FrostedPageHeader';

class LogDataSource implements IDataSource {
  private entries: DiagnosticLogEntry[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.entries.length; }
  getData(index: number): DiagnosticLogEntry { return this.entries[index]; }
  update(entries: DiagnosticLogEntry[]): void {
    this.entries = entries;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((value: DataChangeListener): boolean => value !== listener);
  }
}

@ComponentV2
export struct LogManagementPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Local onlyErrors: boolean = false;
  @Local count: number = 0;
  @Local errorCount: number = 0;
  @Local busy: boolean = false;
  @Local loggingEnabled: boolean = false;
  @Local storageError: string = '';
  private entries: DiagnosticLogEntry[] = [];
  private source: LogDataSource = new LogDataSource();

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context) DiagnosticLogService.init(context);
    this.loggingEnabled = DiagnosticLogService.isEnabled();
    this.refresh();
  }

  private async refresh(): Promise<void> {
    this.entries = await DiagnosticLogService.list();
    this.errorCount = this.entries.filter((entry: DiagnosticLogEntry): boolean => entry.level === 'ERROR').length;
    this.storageError = DiagnosticLogService.getStorageError();
    this.applyFilter();
  }

  private applyFilter(): void {
    const visible = this.entries.filter((entry: DiagnosticLogEntry): boolean => !this.onlyErrors || entry.level === 'ERROR');
    this.count = visible.length;
    this.source.update(visible);
  }

  private async check(): Promise<void> {
    if (this.busy || !this.loggingEnabled) return;
    this.busy = true;
    try { await DiagnosticLogService.check(); await this.refresh(); }
    finally { this.busy = false; }
  }

  private async setLoggingEnabled(enabled: boolean): Promise<void> {
    if (this.busy || enabled === DiagnosticLogService.isEnabled()) return;
    this.busy = true;
    this.loggingEnabled = enabled;
    try {
      await DiagnosticLogService.setEnabled(enabled);
      await this.refresh();
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.log_operation_failed') });
    } finally {
      this.loggingEnabled = DiagnosticLogService.isEnabled();
      this.busy = false;
    }
  }

  private async copy(): Promise<void> {
    try {
      const text = this.entries.filter((entry: DiagnosticLogEntry): boolean => !this.onlyErrors || entry.level === 'ERROR')
        .map((entry: DiagnosticLogEntry): string => `${entry.time} [${entry.level}] ${entry.stage}\n${entry.message}`)
        .join('\n\n');
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.log_copied') });
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.log_operation_failed') });
    }
  }

  private async clear(): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.log_clear'), message: $r('app.string.log_clear_confirm'),
        buttons: [
          { text: $r('app.string.log_cancel'), color: AppTheme.TextSecondary },
          { text: $r('app.string.log_clear'), color: AppColor.Brand }
        ]
      });
      if (result.index !== 1) return;
      await DiagnosticLogService.clear();
      await this.refresh();
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.log_operation_failed') });
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      List({ space: AppSpace.Sm }) {
        ListItem() {
          Column({ space: AppSpace.Md }) {
            Text($r('app.string.log_hint')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
              .width('100%')
            Row({ space: AppSpace.Sm }) {
              Text($r('app.string.log_enabled')).fontSize(AppFont.Body)
                .fontColor(AppTheme.TextPrimary).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.loggingEnabled })
                .selectedColor(AppColor.Brand).enabled(!this.busy)
                .accessibilityText($r('app.string.log_enabled'))
                .onChange((value: boolean): void => { this.setLoggingEnabled(value); })
            }.width('100%')
            Row({ space: AppSpace.Sm }) {
              Button($r('app.string.log_check')).backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
                .layoutWeight(1).enabled(!this.busy && this.loggingEnabled).onClick(() => this.check())
              Button($r('app.string.log_copy')).backgroundColor(AppTheme.Surface)
                .fontColor(AppTheme.TextPrimary).layoutWeight(1).enabled(this.count > 0).onClick(() => this.copy())
              Button($r('app.string.log_clear')).backgroundColor(AppTheme.Surface)
                .fontColor(AppTheme.TextPrimary).layoutWeight(1).enabled(!this.busy).onClick(() => this.clear())
            }.width('100%')
            Row({ space: AppSpace.Sm }) {
              Text($r('app.string.log_count', this.count, this.errorCount)).fontSize(AppFont.Caption)
                .fontColor(AppTheme.TextSecondary).layoutWeight(1)
              Text($r('app.string.log_errors_only')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
              Toggle({ type: ToggleType.Switch, isOn: this.onlyErrors }).selectedColor(AppColor.Brand)
                .onChange((value: boolean): void => { this.onlyErrors = value; this.applyFilter(); })
            }.width('100%')
            if (this.busy) { LoadingProgress().color(AppColor.Brand).width(24).height(24) }
            if (this.storageError.length > 0) {
              Text($r('app.string.log_storage_failed')).fontSize(AppFont.Caption).fontColor(AppTheme.TextPrimary)
            }
          }.width('100%').padding({ bottom: AppSpace.Sm })
        }
        if (this.count === 0) {
          ListItem() {
            Text($r('app.string.log_empty')).fontColor(AppTheme.TextSecondary)
              .width('100%').textAlign(TextAlign.Center).padding(AppSpace.Xl)
          }
        } else {
          LazyForEach(this.source, (entry: DiagnosticLogEntry) => {
            ListItem() {
              Column({ space: AppSpace.Xs }) {
                Text(`${entry.time.replace('T', ' ').replace('Z', ' UTC')}  ${entry.level}`)
                  .fontSize(AppFont.Caption).fontColor(entry.level === 'ERROR' ? AppColor.Brand : AppTheme.TextTertiary)
                Text(entry.stage).fontSize(AppFont.Body).fontWeight(FontWeight.Medium)
                  .fontColor(AppTheme.TextPrimary)
                Text(entry.message).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
                  .copyOption(CopyOptions.LocalDevice).wordBreak(WordBreak.BREAK_ALL)
              }
              .width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Md)
              .borderRadius(AppRadius.Md).backgroundColor(AppTheme.Surface)
            }
          }, (entry: DiagnosticLogEntry): string => entry.id)
        }
      }
      .width('100%').height('100%').padding({ left: AppSpace.Md, right: AppSpace.Md })
      .contentStartOffset(this.headerHeight + AppSpace.Md)
      .contentEndOffset(WindowUtils.getBottomSafeVp() + AppSpace.Sm)
      .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
            .onClick(() => this.navStack.pop())
          Text($r('app.string.log_title')).fontSize(AppFont.Title).fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TextPrimary).layoutWeight(1)
          Text($r('app.string.log_refresh')).fontColor(AppColor.Brand).onClick(() => this.refresh())
        }.width('100%').padding({ left: AppSpace.Md, right: AppSpace.Md,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      }
    }
    .width('100%').height('100%')
    .backgroundColor(AppTheme.SettingsBackground)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
