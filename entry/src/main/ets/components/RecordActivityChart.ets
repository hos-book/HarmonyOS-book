import { ActivityDay } from '../service/StatsService';
import { PreferenceService } from '../service/PreferenceService';
import { AppColor, AppCurve, AppTheme, AppRadius } from '../theme/Theme';
import { ContentTypeColor } from '../theme/ContentTypeColor';
import { RecordCardBackdrop } from './RecordCardBackdrop';

/** 近七个本地自然日的真实阅听时长，按漫画、阅读、有声书堆叠。 */
@ComponentV2
export struct RecordActivityChart {
  @Param days: ActivityDay[] = [];
  @Param ready: boolean = false;
  @Param failed: boolean = false;
  @Event onRetry: () => void = (): void => {};
  @Local expanded: boolean = true;
  @Local expansionProgress: number = 1;
  @Local cardWidth: number = 0;
  @Local selectedDay: string = '';
  @Local barsProgress: number = 0;
  private alive: boolean = false;
  private loadGeneration: number = 0;
  private interactionRevision: number = 0;
  private savedExpanded: boolean = true;

  aboutToAppear(): void {
    this.alive = true;
    this.loadExpanded();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.loadGeneration++;
  }

  private async loadExpanded(): Promise<void> {
    const generation: number = ++this.loadGeneration;
    const revision: number = this.interactionRevision;
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) throw new Error('Activity chart context unavailable');
      await PreferenceService.ensureReady(context);
      const expanded: boolean = await PreferenceService.getRecordHeatmapExpanded();
      if (!this.alive || generation !== this.loadGeneration || revision !== this.interactionRevision) return;
      this.savedExpanded = expanded;
      this.expanded = expanded;
      this.expansionProgress = expanded ? 1 : 0;
      if (expanded) this.revealBars();
    } catch (_error) {
      if (this.alive && generation === this.loadGeneration && revision === this.interactionRevision) {
        if (this.expanded) this.revealBars();
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_load_failed') });
      }
    }
  }

  private animateExpanded(expanded: boolean): void {
    this.expanded = expanded;
    this.getUIContext().animateTo({ duration: 280, curve: Curve.Friction }, (): void => {
      this.expansionProgress = expanded ? 1 : 0;
    });
    if (expanded) this.revealBars();
    else this.barsProgress = 0;
  }

  private revealBars(): void {
    this.barsProgress = 0;
    this.getUIContext().animateTo({ duration: 460, delay: 50, curve: AppCurve.SpringSoft }, (): void => {
      this.barsProgress = 1;
    });
  }

  @Monitor('ready')
  onStatsReady(): void {
    if (this.ready && this.expanded) this.revealBars();
  }

  private async saveExpanded(expanded: boolean, revision: number): Promise<void> {
    try {
      await PreferenceService.setRecordHeatmapExpanded(expanded);
      this.savedExpanded = expanded;
    } catch (_error) {
      if (this.alive) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
      }
      let restored: boolean = this.savedExpanded;
      try { restored = await PreferenceService.getRecordHeatmapExpanded(); }
      catch (_readError) { /* 保存失败已提示，无法重读时保留最近成功值。 */ }
      if (this.alive && revision === this.interactionRevision) {
        this.savedExpanded = restored;
        this.animateExpanded(restored);
      }
    }
  }

  private toggleExpanded(): void {
    const expanded: boolean = !this.expanded;
    const revision: number = ++this.interactionRevision;
    this.animateExpanded(expanded);
    this.saveExpanded(expanded, revision);
  }

  private plotHeight(): number { return this.cardWidth >= 840 ? 112 : 88; }
  private bodyHeight(): number { return this.plotHeight() + 50; }
  private maximumCardHeight(): number { return 44 + this.bodyHeight() + 12; }
  private currentCardHeight(): number { return 44 + (this.bodyHeight() + 12) * this.expansionProgress; }

  private total(day: ActivityDay): number {
    return day.comicSeconds + day.readingSeconds + day.audioSeconds;
  }

  @Computed
  private get weekComicSeconds(): number {
    return this.days.reduce((sum: number, day: ActivityDay): number => sum + day.comicSeconds, 0);
  }

  @Computed
  private get weekReadingSeconds(): number {
    return this.days.reduce((sum: number, day: ActivityDay): number => sum + day.readingSeconds, 0);
  }

  @Computed
  private get weekAudioSeconds(): number {
    return this.days.reduce((sum: number, day: ActivityDay): number => sum + day.audioSeconds, 0);
  }

  @Computed
  private get weekSeconds(): number {
    return this.weekComicSeconds + this.weekReadingSeconds + this.weekAudioSeconds +
      this.days.reduce((sum: number, day: ActivityDay): number => sum + day.unclassifiedSeconds, 0);
  }

  @Computed
  private get maximumSeconds(): number {
    return Math.max(60, ...this.days.map((day: ActivityDay): number => this.total(day)));
  }

  @Computed
  private get selectedValues(): ActivityDay | undefined {
    return this.days.find((day: ActivityDay): boolean => day.day === this.selectedDay);
  }

  @Computed
  private get selectionLabel(): ResourceStr {
    const day = this.selectedValues;
    return day === undefined ? $r('app.string.record_chart_title') :
      $r('app.string.record_chart_selected_title', this.shortDate(day));
  }

  @Computed
  private get selectionSeconds(): number {
    const day = this.selectedValues;
    return day === undefined ? this.weekSeconds : this.total(day) + day.unclassifiedSeconds;
  }

  private isToday(day: ActivityDay): boolean {
    return day.day === this.days[this.days.length - 1]?.day;
  }

  private dayLabel(day: ActivityDay): ResourceStr {
    return this.isToday(day) ? $r('app.string.record_date_today') :
      $r('app.string.record_chart_day', Number(day.day.split('-')[2]));
  }

  private shortDate(day: ActivityDay): string {
    const parts: string[] = day.day.split('-');
    return parts.length === 3 ? `${Number(parts[1])}.${Number(parts[2])}` : '';
  }

  private duration(seconds: number): Resource {
    if (seconds > 0 && seconds < 60) return $r('app.string.record_chart_under_minute');
    if (seconds < 3600) return $r('app.string.record_chart_minutes', Math.floor(seconds / 60));
    return $r('app.string.record_summary_duration', Math.floor(seconds / 3600), Math.floor(seconds % 3600 / 60));
  }

  private selectDay(day: ActivityDay): void {
    this.setSelectedDay(this.selectedDay === day.day ? '' : day.day);
  }

  private setSelectedDay(day: string): void {
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, (): void => {
      this.selectedDay = day;
    });
  }

  private seriesColor(kind: number): ResourceColor {
    return ContentTypeColor.chartOf(kind === 0 ? 'comic' : kind === 1 ? 'text' : 'audio');
  }

  private seriesLabel(kind: number): Resource {
    if (kind === 0) return $r('app.string.comic_type');
    if (kind === 1) return $r('app.string.record_chart_reading');
    return $r('app.string.search_type_audio');
  }

  @LocalBuilder
  buildHeader() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.calendar')).fontSize(14).fontColor([AppColor.Brand]).accessibilityLevel('no')
        Text(this.selectionLabel).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TextPrimary).maxLines(1)
        Text(this.ready && !this.failed ? this.duration(this.selectionSeconds) : $r('app.string.record_stats_pending'))
          .fontSize(12).fontColor(AppTheme.TextSecondary).layoutWeight(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(12).fontColor([AppTheme.IconSecondary])
          .rotate({ angle: 180 * this.expansionProgress }).accessibilityLevel('no')
      }.width('100%').height(44)
    }.width('100%').height(44).padding(0).backgroundColor(Color.Transparent)
      .stateEffect(false).hoverEffect(HoverEffect.None)
      .accessibilityText(this.expanded ? $r('app.string.record_chart_collapse') : $r('app.string.record_chart_expand'))
      .onClick((): void => this.toggleExpanded())
  }

  @LocalBuilder
  buildDay(day: ActivityDay) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        Column() {
          if (this.total(day) > 0) {
            Column({ space: 0 }) {
              if (day.audioSeconds > 0) {
                Row().width('100%').height(day.audioSeconds / this.maximumSeconds * this.plotHeight())
                  .backgroundColor(this.seriesColor(2))
              }
              if (day.readingSeconds > 0) {
                Row().width('100%').height(day.readingSeconds / this.maximumSeconds * this.plotHeight())
                  .backgroundColor(this.seriesColor(1))
              }
              if (day.comicSeconds > 0) {
                Row().width('100%').height(day.comicSeconds / this.maximumSeconds * this.plotHeight())
                  .backgroundColor(this.seriesColor(0))
              }
            }
            .width(this.cardWidth >= 600 ? 18 : 14)
            .borderRadius({ topLeft: 4, topRight: 4, bottomLeft: 1, bottomRight: 1 }).clip(true)
            .scale({ x: 1, y: this.barsProgress, centerY: '100%' })
            .opacity(this.selectedDay.length === 0 || this.selectedDay === day.day ? 1 : 0.4)
          } else {
            Row().width(this.cardWidth >= 600 ? 18 : 14).height(2).borderRadius(1)
              .backgroundColor(AppTheme.Divider)
          }
        }.height(this.plotHeight()).width('100%').justifyContent(FlexAlign.End)
        Text(this.dayLabel(day)).fontSize(11).height(22).padding({ left: 5, right: 5 })
          .fontColor(this.selectedDay === day.day || this.isToday(day) ? AppTheme.TextPrimary : AppTheme.TextSecondary)
          .fontWeight(this.selectedDay === day.day || this.isToday(day) ? FontWeight.Medium : FontWeight.Normal)
          .backgroundColor(this.selectedDay === day.day ? $r('app.color.record_chart_selected') : Color.Transparent)
          .borderRadius(6)
      }.width('100%').height(this.plotHeight() + 26)
    }.layoutWeight(1).height(this.plotHeight() + 26).padding(0).borderRadius(8)
      .backgroundColor(Color.Transparent).stateEffect(false).hoverEffect(HoverEffect.None)
      .accessibilitySelected(this.selectedDay === day.day)
      .accessibilityText($r('app.string.record_chart_day_accessibility', this.shortDate(day)))
      .onClick((): void => this.selectDay(day))
  }

  @LocalBuilder
  buildChart() {
    Column({ space: 0 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          Divider().color(AppTheme.Divider).strokeWidth(0.5)
          Blank()
          Divider().color(AppTheme.Divider).strokeWidth(0.5)
          Blank()
          Divider().color(AppTheme.Divider).strokeWidth(0.5)
        }.width('100%').height(this.plotHeight()).opacity(0.35).hitTestBehavior(HitTestMode.None)
        Row({ space: 4 }) {
          ForEach(this.days, (day: ActivityDay): void => { this.buildDay(day) }, (day: ActivityDay): string => day.day)
        }.width('100%').height(this.plotHeight() + 26)
      }.width('100%').height(this.plotHeight() + 26)
      Row({ space: 12 }) {
        ForEach([0, 1, 2], (kind: number): void => {
          Row({ space: 4 }) {
            Row().width(6).height(6).borderRadius(2).backgroundColor(this.seriesColor(kind))
            Text(this.seriesLabel(kind)).fontSize(11).fontColor(AppTheme.TextSecondary)
          }
        }, (kind: number): string => `activity-kind-${kind}`)
      }.width('100%').height(24).justifyContent(FlexAlign.End)
        .accessibilityText($r('app.string.record_chart_reset'))
        .onClick((): void => this.setSelectedDay(''))
    }.width('100%').constraintSize({ maxWidth: 920 })
  }

  @LocalBuilder
  buildPending() {
    Column({ space: 8 }) {
      if (this.failed) {
        Text($r('app.string.record_stats_read_failed')).fontSize(12).fontColor(AppTheme.TextSecondary)
        Button({ type: ButtonType.Capsule }) {
          Text($r('app.string.common_retry')).fontSize(12).fontColor(AppTheme.TextPrimary)
        }.height(30).padding({ left: 16, right: 16 }).backgroundColor(Color.Transparent)
          .onClick((): void => this.onRetry())
      } else {
        LoadingProgress().width(22).height(22).color(AppColor.Brand)
        Text($r('app.string.record_stats_loading')).fontSize(12).fontColor(AppTheme.TextSecondary)
      }
    }.width('100%').height(this.bodyHeight()).justifyContent(FlexAlign.Center)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      RecordCardBackdrop({ cardHeight: this.maximumCardHeight() })
      Column() {
        this.buildHeader()
        Column() {
          if (this.ready && !this.failed) this.buildChart()
          else this.buildPending()
        }.width('100%').alignItems(HorizontalAlign.Center)
          .hitTestBehavior(this.expanded ? HitTestMode.Default : HitTestMode.None)
          .accessibilityLevel(this.expanded ? 'auto' : 'no-hide-descendants')
      }.width('100%').height(this.maximumCardHeight())
        .padding({ left: 16, right: 16, bottom: 12 })
    }.width('100%').height(this.currentCardHeight())
      .border({ width: 0.5, color: AppColor.GlassStroke }).borderRadius(AppRadius.Lg).clip(true)
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        const width: number = Number(size.width);
        if (Number.isFinite(width) && width > 0 && Math.abs(width - this.cardWidth) > 0.5) this.cardWidth = width;
      })
  }
}
