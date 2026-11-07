import { batteryInfo } from '@kit.BasicServicesKit';
import { AppFont } from '../theme/Theme';

/** 独立更新页脚状态，不参与正文分页或翻页版本号。 */
@ComponentV2
export struct ReaderStatusIndicator {
  @Param color: ResourceColor = '#6F675E';
  @Local batteryLevel: number = -1;
  private batteryTimer: number = -1;

  aboutToDisappear(): void {
    this.stopBatteryUpdates();
  }

  private refreshBattery(): void {
    try {
      const level = batteryInfo.batterySOC;
      this.batteryLevel = Number.isFinite(level) && level >= 0 && level <= 100 ? Math.round(level) : -1;
    } catch (_e) {
      this.batteryLevel = -1;
    }
  }

  private startBatteryUpdates(): void {
    this.refreshBattery();
    if (this.batteryTimer !== -1) return;
    this.batteryTimer = setInterval((): void => this.refreshBattery(), 30000);
  }

  private stopBatteryUpdates(): void {
    if (this.batteryTimer === -1) return;
    clearInterval(this.batteryTimer);
    this.batteryTimer = -1;
  }

  build() {
    Row({ space: 7 }) {
      Row({ space: 1 }) {
        Text(this.batteryLevel >= 0 ? `${this.batteryLevel}` : '--')
          .width(26).height(14)
          .fontSize(10).fontWeight(FontWeight.Bold)
          .minFontScale(1).maxFontScale(1)
          .fontColor(this.color).textAlign(TextAlign.Center).maxLines(1)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: this.color }).borderRadius(3.5)
        Column().width(2).height(5).borderRadius(1).backgroundColor(this.color).opacity(0.6)
      }
      .alignItems(VerticalAlign.Center)
      .accessibilityGroup(true)
      .accessibilityText($r('app.string.reader_battery_level', this.batteryLevel >= 0 ? `${this.batteryLevel}%` : '--'))
      .id('reader-status-battery')
      TextClock()
        .format('HH:mm')
        .fontSize(AppFont.Caption)
        .fontColor(this.color)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
    .onVisibleAreaChange([0], (visible: boolean): void => {
      if (visible) this.startBatteryUpdates();
      else this.stopBatteryUpdates();
    })
  }
}
