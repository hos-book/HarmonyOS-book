import { ProfileMenuDestination } from '../components/ProfileMenuDestination';
import { LocalRuleSource } from '../model/LocalRuleSource';
import { LocalRuleDebugResult, LocalRuleDebugService } from '../service/rulesource/LocalRuleDebugService';
import { LocalRuleDiagnostics } from '../service/rulesource/LocalRuleDiagnostics';
import { LocalRuleSourceRepository } from '../service/rulesource/LocalRuleSourceRepository';
import { LocalRuleBrowserLoginCoordinator } from '../service/rulesource/LocalRuleBrowserLoginCoordinator';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { promptAction } from '@kit.ArkUI';
import { fileIo, picker } from '@kit.CoreFileKit';

class DebugLog {
  id: number = 0;
  timestamp: number = 0;
  level: string = 'info';
  stage: string = '';
  message: string = '';
  detail: string = '';
}

interface DebugReport {
  sourceUrl: string;
  sourceName: string;
  stage: string;
  keyword: string;
  testUrl: string;
  logs: DebugLog[];
  result: LocalRuleDebugResult | null;
  exportedAt: string;
}

@ComponentV2
export struct RuleSourceDebugPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param sourceUrl: string = '';
  @Local source: LocalRuleSource | null = null;
  @Local isLoading: boolean = false;
  @Local isRunning: boolean = false;
  @Local currentStage: string = 'search';
  @Local keyword: string = '我的';
  @Local testUrl: string = '';
  @Local debugLogs: DebugLog[] = [];
  @Local debugResult: LocalRuleDebugResult | null = null;
  @Local isExporting: boolean = false;
  @Local safeTop: number = WindowUtils.getStatusBarHeightVp();
  @Local safeBottom: number = WindowUtils.getBottomSafeVp();
  private nextLogId: number = 0;
  private debugVariables: Record<string, string> = {};
  private browserLoginScope: number = 0;
  private safeAreaListener: (top: number, bottom: number) => void = (top, bottom) => {
    this.safeTop = top;
    this.safeBottom = bottom;
  };

  aboutToAppear(): void {
    WindowUtils.addSafeAreaListener(this.safeAreaListener);
    this.loadSource();
  }

  aboutToDisappear(): void {
    this.cancelDebug();
    WindowUtils.removeSafeAreaListener(this.safeAreaListener);
  }

  private async loadSource(): Promise<void> {
    this.isLoading = true;
    try {
      const loaded = await LocalRuleSourceRepository.findByUrl(this.sourceUrl);
      this.source = loaded || null;
      if (!this.source) {
        promptAction.showToast({ message: '书源不存在' });
        this.navStack.pop();
      }
    } catch (error) {
      promptAction.showToast({ message: $r('app.string.rule_source_read_failed') });
      this.navStack.pop();
    } finally {
      this.isLoading = false;
    }
  }

  private addLog(level: string, stage: string, message: string, detail: string = ''): void {
    const log = new DebugLog();
    log.id = this.nextLogId++;
    log.timestamp = Date.now();
    log.level = level;
    log.stage = stage;
    log.message = message;
    log.detail = LocalRuleDiagnostics.redact(detail);
    this.debugLogs = this.debugLogs.concat([log]).slice(-160);
  }

  private clearLogs(): void {
    this.debugLogs = [];
    this.debugResult = null;
  }

  private async runDebug(): Promise<void> {
    const source = this.source;
    if (!source || this.isRunning) return;
    this.clearLogs();
    this.isRunning = true;
    this.debugVariables = LocalRuleDiagnostics.open(event => {
      this.addLog(event.level, event.stage, event.message, event.detail);
    });
    try {
      this.browserLoginScope = LocalRuleBrowserLoginCoordinator.openScope(source.bookSourceUrl);
      this.debugResult = await LocalRuleDebugService.run(source, this.currentStage,
        this.keyword, this.testUrl, this.debugVariables);
    } finally {
      LocalRuleBrowserLoginCoordinator.closeScope(this.browserLoginScope);
      this.browserLoginScope = 0;
      LocalRuleDiagnostics.close(this.debugVariables);
      this.isRunning = false;
    }
  }

  private cancelDebug(): void {
    LocalRuleDiagnostics.cancel(this.debugVariables);
    LocalRuleBrowserLoginCoordinator.cancelScope(this.browserLoginScope, '书源调试已取消');
  }

  private async exportReport(): Promise<void> {
    if (this.isExporting || this.isRunning || this.debugLogs.length === 0) return;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) return;
    this.isExporting = true;
    try {
      const reportText = this.generateDebugReport();
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [`source-debug-${Date.now()}.json`];
      const uris = await new picker.DocumentViewPicker(context).save(options);
      if (uris.length === 0) return;
      const file = await fileIo.open(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE |
        fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(file.fd, reportText);
      } finally {
        await fileIo.close(file);
      }
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.rule_source_report_saved') });
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.rule_source_report_failed') });
    } finally {
      this.isExporting = false;
    }
  }

  private generateDebugReport(): string {
    const report: DebugReport = {
      sourceUrl: this.source?.bookSourceUrl ?? '',
      sourceName: this.source?.bookSourceName ?? '',
      stage: this.currentStage,
      keyword: this.keyword,
      testUrl: this.testUrl,
      logs: this.debugLogs,
      result: this.debugResult,
      exportedAt: new Date().toISOString()
    };
    return LocalRuleDiagnostics.redact(JSON.stringify(report, null, 2));
  }

  build() {
    ProfileMenuDestination({ pageBackground: $r('sys.color.background_secondary') }) {
      Column() {
        // 顶部标题栏
        Row() {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(24)
              .fontColor([$r('sys.color.font_primary')])
          }
            .width(44)
            .height(44)
            .backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.common_back'))
            .onClick(() => { this.cancelDebug(); this.navStack.pop(); })

          Text('书源调试')
            .fontSize(AppFont.TitleL)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: AppSpace.Xs })

          Button($r('app.string.rule_source_export_report'), { type: ButtonType.Normal })
            .fontSize(AppFont.Body)
            .fontColor(this.debugLogs.length > 0 ? AppColor.Brand : $r('sys.color.font_tertiary'))
            .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
            .height(44)
            .constraintSize({ minWidth: 60 })
            .borderRadius(AppRadius.Sm)
            .backgroundColor(Color.Transparent)
            .enabled(this.debugLogs.length > 0 && !this.isRunning && !this.isExporting)
            .onClick(() => this.exportReport())
        }
        .width('100%')
        .height(this.safeTop + 56)
        .padding({
          top: this.safeTop,
          left: AppSpace.Xs,
          right: AppSpace.Md
        })
        .backgroundColor($r('sys.color.background_primary'))

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(AppColor.Brand)
            Text($r('app.string.common_content_loading'))
              .fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary'))
              .margin({ top: AppSpace.Xs })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: AppSpace.Md }) {
              // 书源信息
              this.SourceInfoCard()

              // 调试阶段选择
              this.StageSelector()

              // 输入参数
              this.InputCard()

              // 执行按钮
              Button({ type: ButtonType.Normal }) {
                Row({ space: AppSpace.Xs }) {
                  if (this.isRunning) {
                    LoadingProgress()
                      .width(20)
                      .height(20)
                      .color(AppColor.Brand)
                  }
                  Text(this.isRunning ? $r('app.string.rule_source_debug_stop') :
                    $r('app.string.rule_source_debug_start'))
                    .fontSize(AppFont.BodyL)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.isRunning ? AppColor.Brand : AppColor.OnBrand)
                }
              }
                .width('100%')
                .height(48)
                .borderRadius(AppRadius.Sm)
                .backgroundColor(this.isRunning ? AppColor.BrandSoft : AppColor.Brand)
                .enabled(!this.isExporting && this.source !== null)
                .onClick(() => {
                  if (this.isRunning) this.cancelDebug();
                  else this.runDebug();
                })

              // 调试日志
              if (this.debugLogs.length > 0) {
                this.LogsCard()
              }

              // 调试结果
              if (this.debugResult !== null) {
                this.ResultCard()
              }
            }
            .width('100%')
            .padding({
              left: AppSpace.Md,
              right: AppSpace.Md,
              top: AppSpace.Md,
              bottom: AppSpace.Lg + this.safeBottom
            })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .scrollable(ScrollDirection.Vertical)
          .align(Alignment.Top)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }

  }

  @Builder
  SourceInfoCard() {
    Column({ space: 6 }) {
      Text(this.source?.bookSourceName || '未知书源')
        .fontSize(AppFont.BodyL)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.source?.bookSourceUrl || '')
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(`类型: ${this.source?.bookSourceType === 1 ? '音频' : this.source?.bookSourceType === 0 ? '文本' : '其他'}`)
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
    }
    .width('100%')
    .padding({ bottom: AppSpace.Sm })
    .borderWidth({ bottom: 0.5 })
    .borderColor($r('sys.color.comp_divider'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  StageSelector() {
    Column({ space: AppSpace.Xs }) {
      Text('调试阶段')
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')

      Row() {
        this.StageButton('搜索', 'search')
        this.StageButton($r('app.string.rule_source_explore'), 'explore')
        this.StageButton('详情', 'detail')
        this.StageButton('目录', 'toc')
        this.StageButton(this.source?.bookSourceType === 1 ?
          $r('app.string.rule_source_debug_audio') : $r('app.string.rule_source_debug_content'), 'content')
        this.StageButton('全链路', 'full')
      }
      .width('100%')
      .padding(4)
      .backgroundColor($r('sys.color.comp_background_secondary'))
      .borderRadius(AppRadius.Sm)
    }
    .width('100%')
  }

  @Builder
  StageButton(label: ResourceStr, stage: string) {
    Text(label)
      .fontSize(AppFont.Caption)
      .fontColor(this.currentStage === stage ? AppColor.Brand : $r('sys.color.font_secondary'))
      .layoutWeight(1)
      .height(44)
      .maxLines(1)
      .minFontScale(1)
      .maxFontScale(1.3)
      .textAlign(TextAlign.Center)
      .borderRadius(AppRadius.Xs)
      .backgroundColor(this.currentStage === stage ? AppColor.BrandSoft :
        Color.Transparent)
      .enabled(!this.isRunning && !this.isExporting)
      .onClick(() => {
        if (!this.isRunning) {
          this.currentStage = stage;
          this.clearLogs();
        }
      })
  }

  @Builder
  InputCard() {
    Column({ space: AppSpace.Sm }) {
      if (this.currentStage === 'search' || this.currentStage === 'full') {
        Column({ space: 4 }) {
          Text('搜索关键词')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')

          TextInput({ text: this.keyword, placeholder: '请输入搜索关键词' })
            .width('100%')
            .height(48)
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
            .caretColor(AppColor.Brand)
            .selectedBackgroundColor(AppColor.BrandSoft)
            .backgroundColor($r('sys.color.comp_background_secondary'))
            .borderRadius(AppRadius.Xs)
            .enabled(!this.isRunning && !this.isExporting)
            .onChange((value: string) => { this.keyword = value; })
        }
      }

      if (this.currentStage === 'detail' || this.currentStage === 'toc' || this.currentStage === 'content') {
        Column({ space: 4 }) {
          Text(this.currentStage === 'detail' ? '详情页URL' :
            this.currentStage === 'toc' ? '书籍URL' : '章节URL')
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')

          TextInput({ text: this.testUrl, placeholder: '请输入URL' })
            .width('100%')
            .height(48)
            .fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary'))
            .caretColor(AppColor.Brand)
            .selectedBackgroundColor(AppColor.BrandSoft)
            .backgroundColor($r('sys.color.comp_background_secondary'))
            .borderRadius(AppRadius.Xs)
            .enabled(!this.isRunning && !this.isExporting)
            .onChange((value: string) => { this.testUrl = value; })
        }
      }
    }
    .width('100%')
  }

  @Builder
  LogsCard() {
    Column({ space: 0 }) {
      Row() {
        Text('调试日志')
          .fontSize(AppFont.Caption)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)

        Button($r('app.string.rule_source_debug_clear'), { type: ButtonType.Normal })
          .fontSize(AppFont.Caption)
          .fontColor(AppColor.Brand)
          .height(44)
          .padding({ left: AppSpace.Sm, right: AppSpace.Sm })
          .backgroundColor(Color.Transparent)
          .enabled(!this.isRunning && !this.isExporting)
          .onClick(() => this.clearLogs())
      }
      .width('100%')

      Divider()
        .color($r('sys.color.comp_divider'))

        Column({ space: 0 }) {
          ForEach(this.debugLogs, (log: DebugLog, index: number) => {
            Column({ space: 4 }) {
              Row({ space: AppSpace.Xs }) {
                Text(this.formatTime(log.timestamp))
                  .fontSize(AppFont.Caption)
                  .fontColor($r('sys.color.font_tertiary'))

                Text(`[${log.stage}]`)
                  .fontSize(AppFont.Caption)
                  .fontColor(this.getLogLevelColor(log.level))
                  .fontWeight(FontWeight.Medium)
              }

              Text(log.message)
                .fontSize(AppFont.Body)
                .fontColor(this.getLogLevelColor(log.level))
                .width('100%')
                .copyOption(CopyOptions.LocalDevice)
                .wordBreak(WordBreak.BREAK_ALL)

              if (log.detail) {
                Text(log.detail)
                  .fontSize(AppFont.Caption)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
                  .fontFamily('monospace')
                  .lineHeight(20)
                  .wordBreak(WordBreak.BREAK_ALL)
                  .copyOption(CopyOptions.LocalDevice)
              }
            }
            .width('100%')
            .padding(AppSpace.Sm)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(index % 2 === 0 ? Color.Transparent : $r('sys.color.comp_background_secondary'))
          }, (log: DebugLog) => `${log.id}`)
        }
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  ResultCard() {
    Column({ space: AppSpace.Xs }) {
      Text('调试结果')
        .fontSize(AppFont.Caption)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')

      Text(this.debugResult?.success ? this.debugResult.data :
        this.debugResult?.error ?? '')
        .fontSize(AppFont.Caption)
        .fontColor($r('sys.color.font_secondary'))
        .fontFamily('monospace')
        .width('100%')
        .lineHeight(20)
        .wordBreak(WordBreak.BREAK_ALL)
        .copyOption(CopyOptions.LocalDevice)
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .borderRadius(AppRadius.Xs)
        .padding(AppSpace.Sm)
    }
    .width('100%')
  }

  private formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}:${date.getSeconds().toString().padStart(2, '0')}`;
  }

  private getLogLevelColor(level: string): ResourceStr {
    switch (level) {
      case 'success':
        return '#168A5B';
      case 'warning':
        return '#E89725';
      case 'error':
        return '#D03050';
      default:
        return $r('sys.color.font_secondary');
    }
  }
}
