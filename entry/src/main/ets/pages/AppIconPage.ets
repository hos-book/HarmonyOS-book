import { AppColor, AppFont, AppRadius, AppSpace } from '../theme/Theme';
import { AppIconOption, AppIconService } from '../service/AppIconService';
import { sendableContextManager } from '@kit.AbilityKit';
import { MembershipService } from '../service/MembershipService';
import { MembershipState } from '../model/MembershipState';

/** 主题会员页内的图标选择区，保留原文件名，不再注册独立路由。 */
@ComponentV2
export struct AppIconPage {
  @Event onMembershipRequired: () => void = () => {};
  @Local current: string = '';
  @Local loading: boolean = true;
  @Local switching: boolean = false;
  @Local loadFailed: boolean = false;
  @Local membership: MembershipService = MembershipService.instance;
  @Local memberState: MembershipState = MembershipState.current;
  private service: AppIconService = AppIconService.instance;
  private options: AppIconOption[] = this.service.getOptions();

  aboutToAppear(): void {
    this.loadCurrent();
  }

  @Monitor('membership.busy')
  private onMembershipUpdated(): void {
    if (this.service.membershipRequired && !this.membership.busy && !this.switching) this.loadCurrent();
  }

  private async loadCurrent(): Promise<void> {
    this.loading = true;
    this.loadFailed = false;
    try {
      this.current = await this.service.getCurrent();
    } catch (_error) {
      this.loadFailed = true;
    } finally {
      this.loading = false;
    }
  }

  private async selectIcon(option: AppIconOption): Promise<void> {
    if (this.switching || !this.service.supported || this.loading || this.loadFailed ||
      (this.service.membershipRequired && this.membership.busy) || this.current === option.name) return;
    this.switching = true;
    try {
      // 切换图标复用仍有效的已验签权益；未知或过期时才合并查询。
      if (this.service.membershipRequired && option.name !== '' && !this.memberState.hasAccess) {
        const host = this.getUIContext().getHostContext();
        if (!host) return;
        const context = sendableContextManager.convertToUIAbilityContext(sendableContextManager.convertFromContext(host));
        await this.membership.refresh(context);
        if (!this.memberState.hasAccess) {
          if (this.memberState.confirmedInactive) {
            this.onMembershipRequired();
          } else {
            this.getUIContext().getPromptAction().showToast({ message: this.membership.message });
          }
          return;
        }
      }
      this.current = await this.service.select(option.name);
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.app_icon_changed') });
    } catch (_error) {
      // 再次读取实际状态，覆盖“设置成功但查询暂时失败”的情况。
      await this.loadCurrent();
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.app_icon_change_failed') });
    } finally {
      this.switching = false;
    }
  }

  build() {
    Column({ space: AppSpace.Md }) {
      Row({ space: AppSpace.Sm }) {
        Text($r('app.string.app_icon_title'))
          .fontSize(AppFont.BodyL)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        if (this.loading || this.switching || (this.service.membershipRequired && this.membership.busy)) {
          LoadingProgress().width(24).height(24).color(AppColor.Brand)
        }
      }
      .width('100%')
      if (this.loadFailed) {
        Button($r('app.string.app_icon_retry'))
          .fontColor(AppColor.Brand)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .enabled(!this.loading && !this.switching)
          .onClick(() => this.loadCurrent())
      }
      GridRow({ columns: 3, gutter: { x: 12, y: 16 } }) {
        ForEach(this.options, (option: AppIconOption) => {
          GridCol() {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 8 }) {
                Stack({ alignContent: Alignment.BottomEnd }) {
                  Image(option.preview)
                    .width('100%')
                    .aspectRatio(1)
                    .objectFit(ImageFit.Contain)
                    .borderRadius(20)
                    .clip(true)
                  if (this.service.supported && !this.loading && !this.loadFailed && this.current === option.name) {
                    Stack({ alignContent: Alignment.Center }) {
                      SymbolGlyph($r('sys.symbol.checkmark'))
                        .fontSize(14)
                        .fontWeight(FontWeight.Bold)
                        .fontColor([Color.White])
                    }
                    .width(24)
                    .height(24)
                    .backgroundColor('#222222')
                    .border({ width: 2, color: Color.White })
                    .borderRadius(12)
                    .margin({ right: 4, bottom: 4 })
                    .hitTestBehavior(HitTestMode.None)
                    .accessibilityText($r('app.string.app_icon_current'))
                  }
                }
                .width('100%')
                Text(option.label)
                  .fontSize(AppFont.Body)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (MembershipState.featureEnabled && option.name !== '') {
                  Text(this.service.membershipRequired ? $r('app.string.membership_icon_exclusive') :
                    $r('app.string.app_icon_invite_free')).fontSize(AppFont.Caption)
                    .fontColor($r('sys.color.font_secondary'))
                }
              }
              .width('100%')
              .padding({ left: 6, right: 6, top: 6, bottom: 10 })
            }
            .width('100%')
            .padding(0)
            .borderRadius(AppRadius.Lg)
            .backgroundColor($r('sys.color.comp_background_primary'))
            .enabled(this.service.supported && !this.switching &&
              !this.loading && !this.loadFailed && (!this.service.membershipRequired || !this.membership.busy))
            .accessibilityText(option.label)
            .onClick(() => this.selectIcon(option))
          }
        }, (option: AppIconOption) => option.name || 'default')
      }
    }
    .width('100%')
  }
}
