import { emitter } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { DownloadService, DownloadUpdatePayload, EVT_DOWNLOAD_UPDATED } from '../service/DownloadService';
import { DownloadExportResult, DownloadExportService } from '../service/DownloadExportService';
import { DownloadBookRecord, DownloadBookStatus } from '../service/DownloadStore';
import { DownloadPolicy } from '../service/DownloadPolicy';
import { AppCurve, AppFont, AppMotion, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { CoverImage } from '../components/CoverImage';
import { CoverDecoration } from '../components/CoverDecoration';
import { WindowUtils } from '../utils/WindowUtils';

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

@ComponentV2
struct DownloadBookItem {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookId: string = '';
  @Local available: boolean = true;
  @Local status: DownloadBookStatus = 'idle';
  @Local downloadedCount: number = 0;
  @Local failedCount: number = 0;
  @Local totalCount: number = 0;
  @Local totalBytes: number = 0;
  @Local progressPercent: number = 0;
  @Local failureText: string = '';
  @Local exporting: boolean = false;

  private downloadHandler = (evt: emitter.EventData): void => {
    const data = evt.data as DownloadUpdatePayload;
    if (!data || data.bookId === this.bookId || data.bookId === '') {
      this.syncState();
    }
  };

  aboutToAppear(): void {
    this.syncState();
    emitter.on(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
  }

  aboutToDisappear(): void {
    emitter.off(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
  }

  private record(): DownloadBookRecord | null {
    return DownloadService.getInstance().getBookStatus(this.bookId);
  }

  private syncState(): void {
    const record = this.record();
    if (!record) {
      this.available = false;
      return;
    }
    const progress = DownloadService.getInstance().getBookProgress(record.bookId);
    const failed = record.chapters.find((item) => item.status === 'failed');
    this.available = true;
    this.status = record.status;
    this.downloadedCount = record.downloadedCount;
    this.failedCount = record.failedCount;
    this.totalCount = record.chapters.filter((item) => item.status !== 'deleted').length;
    this.totalBytes = record.totalBytes;
    this.progressPercent = progress.progressPercent;
    this.failureText = failed ? DownloadPolicy.failureText(failed.failureCode
      ?? DownloadPolicy.classifyFailure(failed.failureReason)) : '下载失败，请重试';
  }

  private statusText(): string {
    if (this.status === 'paused') return `已暂停 · ${this.downloadedCount}/${this.totalCount}`;
    if (this.status === 'downloading' || this.status === 'queued') {
      return `下载中 · ${this.downloadedCount}/${this.totalCount} · ${Math.round(this.progressPercent)}%`;
    }
    if (this.failedCount > 0) {
      return `${this.downloadedCount}/${this.totalCount} · 失败 ${this.failedCount} · ${this.failureText}`;
    }
    return `已完成 · ${this.downloadedCount}/${this.totalCount}`;
  }

  private showToast(message: ResourceStr): void {
    try { this.getUIContext().getPromptAction().showToast({ message }); } catch (_e) { /* ignore */ }
  }

  private async pause(record: DownloadBookRecord): Promise<void> {
    try {
      await DownloadService.getInstance().pauseBook(record.bookId);
      this.syncState();
    } catch (_e) {
      this.showToast($r('app.string.download_pause_failed'));
    }
  }

  private async resume(record: DownloadBookRecord): Promise<void> {
    try {
      await DownloadService.getInstance().resumeBook(record.bookId);
      this.syncState();
    } catch (_e) {
      this.showToast($r('app.string.download_resume_failed'));
    }
  }

  private confirmDelete(record: DownloadBookRecord): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除下载',
      message: `删除《${record.title}》的全部离线音频？不会移出书架。`,
      buttons: [
        { text: '取消', color: '#8F8F8F' },
        { text: '删除', color: '#D03050' }
      ]
    }).then((result) => {
      if (result.index !== 1) return;
      DownloadService.getInstance().deleteBookDownload(record.bookId)
        .catch(() => this.showToast($r('app.string.download_delete_failed')));
    }).catch(() => { /* ignore */ });
  }

  private openBook(record: DownloadBookRecord): void {
    this.navStack.pushPathByName('detail', record.bookId);
  }

  private async exportBook(record: DownloadBookRecord): Promise<void> {
    if (this.exporting || record.downloadedCount === 0) return;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.exporting = true;
    try {
      const result: DownloadExportResult = await DownloadExportService.exportBook(context, record);
      if (result.exportedCount === 0 && result.failedCount === 0) return;
      if (result.failedCount === 0) {
        this.showToast($r('app.string.download_export_success', result.exportedCount));
      } else {
        this.showToast($r('app.string.download_export_partial', result.exportedCount, result.failedCount));
      }
    } catch (_e) {
      // Closing the system picker without selecting a location is a normal cancellation.
    } finally {
      this.exporting = false;
    }
  }

  build() {
    if (this.available && this.record()) {
      this.buildRecord(this.record()!)
    }
  }

  @Builder
  buildRecord(record: DownloadBookRecord) {
    Column({ space: AppSpace.Sm }) {
      Row({ space: AppSpace.Md }) {
        this.buildCover(record)
        Column({ space: 4 }) {
          Text(record.title)
            .fontSize(AppFont.BodyL)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(record.author || '未知作者')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
          Text(this.statusText())
            .fontSize(AppFont.Caption)
            .fontColor(this.failedCount > 0 ? '#D03050' : $r('sys.color.font_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(formatBytes(this.totalBytes))
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.openBook(record))

      Progress({ value: this.progressPercent, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(6)
        .color(this.failedCount > 0 ? '#D03050' : '#0A84FF')
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .animation({ duration: AppMotion.Slow, curve: AppCurve.Standard })

      Row({ space: AppSpace.Sm }) {
        if (this.status === 'downloading' || this.status === 'queued') {
          this.buildAction($r('sys.symbol.pause_fill'), '暂停', () => this.pause(record), false)
        } else if (this.status === 'paused' || this.failedCount > 0) {
          this.buildAction($r('sys.symbol.play_fill'), this.failedCount > 0 ? '重试' : '继续',
            () => this.resume(record), false)
        }
        if (this.downloadedCount > 0) {
          this.buildAction($r('sys.symbol.arrow_right'), this.exporting ? '导出中' : '导出',
            () => { this.exportBook(record); }, false)
        }
        this.buildAction($r('sys.symbol.trash'), '删除', () => this.confirmDelete(record), true)
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding(AppSpace.Md)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(AppRadius.Lg)
  }

  @Builder
  buildCover(record: DownloadBookRecord) {
    Stack() {
      if (AppTheme.IllustratedPlaceholders) {
        CoverImage({ title: record.title, author: record.author,
          localPlaceholder: record.bookId.startsWith('import_'), imgWidth: 52, imgHeight: 68,
          useFixedHeight: true, radius: AppRadius.Sm, themedDecoration: false })
      }
      if (record.cover && record.cover.startsWith('http')) {
        Image(record.cover)
          .width(52)
          .height(68)
          .objectFit(ImageFit.Cover)
          .borderRadius(AppRadius.Sm)
      } else if (record.cover && (record.cover.startsWith('/') || record.cover.startsWith('file://'))) {
        Image('file://' + record.cover.replace(/^file:\/\//, ''))
          .width(52)
          .height(68)
          .objectFit(ImageFit.Cover)
          .borderRadius(AppRadius.Sm)
      } else if (!AppTheme.IllustratedPlaceholders) {
        Stack() {
          SymbolGlyph($r('sys.symbol.arrow_down_circle'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_tertiary')])
        }
        .width(52)
        .height(68)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(AppRadius.Sm)
      }
      CoverDecoration({ radius: AppRadius.Sm })
    }.width(52).height(68)
  }

  @Builder
  buildAction(icon: Resource, text: string, action: () => void, danger: boolean) {
    Row({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([danger ? '#D03050' : $r('sys.color.font_secondary')])
      Text(text)
        .fontSize(AppFont.Caption)
        .fontColor(danger ? '#D03050' : $r('sys.color.font_secondary'))
    }
    .height(32)
    .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(AppRadius.Md)
    .onClick(() => action())
  }
}

@ComponentV2
export struct DownloadManagerPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local refreshTick: number = 0;

  private downloadHandler = (evt: emitter.EventData): void => {
    const data = evt.data as DownloadUpdatePayload;
    if (data?.progressOnly) return;
    this.refreshTick = this.refreshTick + 1;
  };

  aboutToAppear(): void {
    this.refreshTick = this.refreshTick + 1;
    emitter.on(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
  }

  aboutToDisappear(): void {
    emitter.off(EVT_DOWNLOAD_UPDATED, this.downloadHandler);
  }

  private records(): DownloadBookRecord[] {
    if (this.refreshTick < 0) return [];
    return DownloadService.getInstance().getAllBookStatuses()
      .filter((item: DownloadBookRecord) => item.chapters.some((chapter) => chapter.status !== 'deleted'))
      .sort((a: DownloadBookRecord, b: DownloadBookRecord) => b.updatedAt - a.updatedAt);
  }

  private totalBytes(): number {
    return this.records().reduce((sum: number, item: DownloadBookRecord) => sum + item.totalBytes, 0);
  }

  build() {
    Column() {
      this.buildHeader()
      if (this.records().length === 0) {
        this.buildEmpty()
      } else {
        List({ space: AppSpace.Sm }) {
          ForEach(this.records(), (record: DownloadBookRecord) => {
            ListItem() {
              DownloadBookItem({ navStack: this.navStack, bookId: record.bookId })
            }
          }, (record: DownloadBookRecord) => record.bookId)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Xl })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildHeader() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24)
        .fontColor([$r('sys.color.font_primary')])
        .onClick(() => this.navStack.pop())
      Column({ space: 2 }) {
        Text('下载管理')
          .fontSize(AppFont.TitleL)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Bold)
        Text(`${this.records().length} 本 · ${formatBytes(this.totalBytes())}`)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: AppSpace.Sm })
    }
    .width('100%')
    .padding({
      top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
      left: AppSpace.Md,
      right: AppSpace.Md,
      bottom: AppSpace.Md
    })
  }

  @Builder
  buildEmpty() {
    Column({ space: AppSpace.Sm }) {
      SymbolGlyph($r('sys.symbol.arrow_down_circle'))
        .fontSize(42)
        .fontColor([$r('sys.color.font_tertiary')])
      Text($r('app.string.download_empty'))
        .fontSize(AppFont.BodyL)
        .fontColor($r('sys.color.font_secondary'))
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

}
