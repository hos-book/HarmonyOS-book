import { RankingCategorySetting, RankingPreferences } from '../service/ranking/RankingPreferences';
import { RankingPlatform } from '../model/Ranking';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';

@ComponentV2
export struct RankingSettingsComponent {
  @Local categories: RankingCategorySetting[] = [];
  @Local saving: boolean = false;
  @Local failed: boolean = false;
  @Local expanded: boolean = false;

  aboutToAppear(): void { this.load(); }

  private async load(): Promise<void> {
    try { this.categories = await RankingPreferences.load(); this.failed = false; }
    catch (_error) { this.failed = true; }
  }

  private async change(id: string, direction: number, enabled?: boolean): Promise<void> {
    if (this.saving) return;
    const next = this.categories.map((item: RankingCategorySetting): RankingCategorySetting =>
      new RankingCategorySetting(new RankingPlatform(item.id, item.name), item.enabled));
    const index = next.findIndex((item: RankingCategorySetting): boolean => item.id === id);
    if (index < 0) return;
    if (enabled !== undefined) next[index].enabled = enabled;
    else {
      const target = index + direction;
      if (target < 0 || target >= next.length) return;
      const item = next.splice(index, 1)[0];
      next.splice(target, 0, item);
    }
    this.saving = true;
    try { await RankingPreferences.save(next); this.categories = next; }
    catch (_error) {
      this.categories = this.categories.slice();
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ranking_settings_save_failed') });
    } finally { this.saving = false; }
  }

  build() {
    Column({ space: AppSpace.Xs }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.ranking_settings_title')).fontSize(AppFont.BodyL)
            .fontColor(AppTheme.TextPrimary).layoutWeight(1).textAlign(TextAlign.Start)
          SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(16).fontColor([AppTheme.TextTertiary])
        }.width('100%').padding(AppSpace.Md)
      }.width('100%').constraintSize({ minHeight: 56 })
      .backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg)
      .accessibilityText($r('app.string.ranking_settings_title'))
      .accessibilityDescription(this.expanded ? $r('app.string.ranking_settings_collapse') :
        $r('app.string.ranking_settings_expand'))
      .onClick((): void => { this.expanded = !this.expanded; })
      if (this.expanded) {
      Column() {
        Text($r('app.string.ranking_settings_desc')).fontSize(AppFont.Caption)
          .fontColor(AppTheme.TextSecondary).padding(AppSpace.Md).width('100%')
        if (this.failed) {
          Button($r('app.string.ranking_settings_retry')).onClick((): void => { this.load(); })
        }
        ForEach(this.categories, (item: RankingCategorySetting, index: number) => {
          Row({ space: AppSpace.Xs }) {
            Text(item.name).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary).layoutWeight(1)
            Button($r('app.string.ranking_move_up'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontSize(AppFont.Caption).fontColor(AppColor.Brand).enabled(index > 0 && !this.saving)
              .onClick((): void => { this.change(item.id, -1); })
            Button($r('app.string.ranking_move_down'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontSize(AppFont.Caption).fontColor(AppColor.Brand).enabled(index < this.categories.length - 1 && !this.saving)
              .onClick((): void => { this.change(item.id, 1); })
            Toggle({ type: ToggleType.Switch, isOn: item.enabled }).selectedColor(AppColor.Brand)
              .enabled(!this.saving).accessibilityText(item.name)
              .onChange((value: boolean): void => { if (value !== item.enabled) this.change(item.id, 0, value); })
          }.width('100%').padding({ left: AppSpace.Md, right: AppSpace.Md, top: AppSpace.Xs, bottom: AppSpace.Xs })
        }, (item: RankingCategorySetting): string => `${item.id}:${item.enabled}`)
      }.width('100%').backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg)
      }
    }.width('100%').alignItems(HorizontalAlign.Start).margin({ bottom: AppSpace.Lg })
  }
}
