import { TalebookApiClient } from '../service/rulesource/talebook/TalebookApiClient';
import { TalebookSourceIdentity } from '../service/rulesource/talebook/TalebookSourceIdentity';
import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';

@ComponentV2
export struct TalebookConnectComponent {
  @Param sourceUrl: string = '';
  @Event onConnected: () => void = (): void => {};
  @Event onBusy: (busy: boolean) => void = (_busy: boolean): void => {};
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
          .fontColor($r('sys.color.font_primary'))
        Text($r('app.string.talebook_hint')).fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
        Text($r('app.string.talebook_address')).fontSize(AppFont.Body)
        TextInput({ text: $$this.address, placeholder: $r('app.string.talebook_address_hint') })
          .type(InputType.Normal).height(48).width('100%').caretColor(AppColor.Brand)
          .enabled(!this.busy && !this.sourceUrl).maxLength(2048)
        Text($r('app.string.talebook_code')).fontSize(AppFont.Body)
        TextInput({ text: $$this.code, placeholder: $r('app.string.talebook_code_hint') })
          .type(InputType.Password).height(48).width('100%').caretColor(AppColor.Brand)
          .enabled(!this.busy).maxLength(256)
        Text($r('app.string.talebook_network_hint')).fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
        if (this.errorMessage) {
          Text(this.errorMessage).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary'))
        }
        if (this.busy) {
          LoadingProgress().width(28).height(28).color(AppColor.Brand)
        }
        Button(this.busy ? $r('app.string.talebook_connecting') : $r('app.string.talebook_connect'),
          { type: ButtonType.Normal })
          .width('100%').height(48).backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand)
          .borderRadius(AppRadius.Sm).enabled(!this.busy && this.address.trim().length > 0)
          .onClick(() => this.connect())
      }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpace.Lg)
    }.width('100%').height('100%')
  }
}
