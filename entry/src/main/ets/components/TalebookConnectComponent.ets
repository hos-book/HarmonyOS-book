import { TalebookApiClient } from '../service/rulesource/talebook/TalebookApiClient';
import { TalebookSourceIdentity } from '../service/rulesource/talebook/TalebookSourceIdentity';
import { AppTheme, AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct TalebookConnectComponent {
  @Param sourceUrl: string = '';
  @Event onConnected: () => void = (): void => {};
  @Event onBusy: (busy: boolean) => void = (_busy: boolean): void => {};
  @Event onCancel: () => void = (): void => {};
  @Local address: string = '';
  @Local code: string = '';
  @Local busy: boolean = false;
  @Local errorMessage: ResourceStr = '';
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    if (this.sourceUrl) this.address = TalebookSourceIdentity.origin(this.sourceUrl);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.code = '';
  }

  private async connect(): Promise<void> {
    if (this.busy || !this.address.trim()) return;
    this.busy = true;
    this.onBusy(true);
    this.errorMessage = '';
    try {
      const connection = await TalebookApiClient.connect(this.address, this.code);
      if (!this.active) return;
      await TalebookApiClient.install(connection, this.sourceUrl);
      this.code = '';
      this.onConnected();
    } catch (error) {
      if (this.active) this.errorMessage = error instanceof Error ? error.message : String(error);
    } finally {
      this.busy = false;
      this.onBusy(false);
    }
  }

  build() {
    Scroll() {
      Column({ space: AppSpace.Md }) {
        Text($r('app.string.talebook_title')).fontSize(AppFont.TitleL).fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TextPrimary)
        Text($r('app.string.talebook_address')).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
        TextInput({ text: $$this.address, placeholder: $r('app.string.talebook_address_hint') })
          .type(InputType.Normal).height(48).width('100%').caretColor(AppColor.Brand)
          .fontColor(AppTheme.TextPrimary).placeholderColor(AppTheme.TextSecondary)
          .backgroundColor($r('app.color.source_import_input_background')).borderRadius(AppRadius.Sm)
          .border({ width: 1, color: $r('app.color.source_import_input_border') })
          .enabled(!this.busy && !this.sourceUrl).maxLength(2048)
          .id('rule-source-nas-address')
        Text($r('app.string.talebook_code')).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
        TextInput({ text: $$this.code, placeholder: $r('app.string.talebook_code_hint') })
          .type(InputType.Password).height(48).width('100%').caretColor(AppColor.Brand)
          .fontColor(AppTheme.TextPrimary).placeholderColor(AppTheme.TextSecondary)
          .backgroundColor($r('app.color.source_import_input_background')).borderRadius(AppRadius.Sm)
          .border({ width: 1, color: $r('app.color.source_import_input_border') })
          .enabled(!this.busy).maxLength(256)
          .enterKeyType(EnterKeyType.Done).id('rule-source-nas-code')
          .onSubmit((): void => { this.connect(); })
        if (this.errorMessage) {
          Text(this.errorMessage).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary).width('100%')
        }
        Row({ space: AppSpace.Sm }) {
          Button($r('app.string.common_cancel'), { type: ButtonType.Normal })
            .layoutWeight(1).height(44).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
            .backgroundColor(AppTheme.SettingsBackground).borderRadius(AppRadius.Sm)
            .enabled(!this.busy).onClick((): void => { this.onCancel(); })
          Stack() {
            Button()
              .width('100%').height('100%').backgroundColor(Color.Transparent).borderRadius(AppRadius.Sm)
              .enabled(!this.busy && this.address.trim().length > 0).id('rule-source-nas-submit')
              .accessibilityText(this.busy ? $r('app.string.talebook_connecting') : $r('app.string.talebook_connect'))
              .onClick((): void => { this.connect(); })
            Row({ space: AppSpace.Xs }) {
              if (this.busy) {
                LoadingProgress().width(18).height(18).color(AppColor.Brand)
              }
              Text(this.busy ? $r('app.string.talebook_connecting') : $r('app.string.talebook_connect'))
                .fontSize(AppFont.Body).fontWeight(FontWeight.Medium)
                .fontColor(this.busy || !this.address.trim() ? AppTheme.TextSecondary : AppColor.OnBrand)
            }.justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.None)
              .accessibilityLevel('no-hide-descendants')
          }.layoutWeight(1).height(44).borderRadius(AppRadius.Sm)
            .backgroundColor(this.busy || !this.address.trim() ? AppTheme.SettingsBackground : AppColor.Brand)
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Lg)
    }.width('100%').scrollBar(BarState.Off)
      .constraintSize({ maxHeight: Math.max(160, WindowUtils.getWindowHeightVp() -
        WindowUtils.getStatusBarHeightVp() - WindowUtils.getBottomSafeVp() - 48) })
  }
}
