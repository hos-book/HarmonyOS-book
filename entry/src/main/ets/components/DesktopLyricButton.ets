import { DesktopLyricState } from '../model/DesktopLyric';
import { AVSessionService } from '../service/AVSessionService';
import { AppColor, AppMaterial } from '../theme/Theme';
import { PlatformCompat } from '../utils/PlatformCompat';
import { MembershipService } from '../service/MembershipService';

@ComponentV2
export struct DesktopLyricButton {
  @Param available: boolean = true;
  @Param color: ResourceColor = '#B3B3B3';
  @Param compact: boolean = false;
  @Local state: DesktopLyricState = AVSessionService.getInstance().desktopLyric;

  private async changeVisibility(): Promise<void> {
    const visible = !this.state.visible;
    if (visible && !await MembershipService.instance.hasCurrentEntitlement()) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_lyric_vip_required') });
      return;
    }
    const success = await AVSessionService.getInstance().setDesktopLyricVisible(visible);
    if (!success) this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_lyric_failed') });
  }

  private async changeLock(): Promise<void> {
    const success = await AVSessionService.getInstance().setDesktopLyricLocked(!this.state.locked);
    if (!success) this.getUIContext().getPromptAction().showToast({ message: $r('app.string.desktop_lyric_failed') });
  }

  private menuOptions(): MenuOptions {
    const options: MenuOptions = { placement: Placement.BottomRight };
    if (PlatformCompat.immersiveMaterial) options.systemMaterial = AppMaterial.Sheet;
    return options;
  }

  build() {
    Button({ type: this.compact ? ButtonType.Circle : ButtonType.Capsule }) {
      if (this.compact) {
        SymbolGlyph($r('sys.symbol.rectangle_on_rectangle')).fontSize(22)
          .fontColor([this.state.visible ? AppColor.Brand : this.color])
      } else {
        Text($r('app.string.desktop_lyric_title')).fontSize(12)
          .fontColor(this.state.visible ? AppColor.Brand : this.color)
      }
    }
      .backgroundColor(Color.Transparent).width(this.compact ? 40 : 64).height(this.compact ? 40 : 44)
      .id('desktop-lyric-menu').accessibilityText($r('app.string.desktop_lyric_title'))
      .bindMenu([
        {
          value: !this.state.supported && this.state.checked ? $r('app.string.desktop_lyric_unsupported') :
            this.state.visible ? $r('app.string.desktop_lyric_hide') : $r('app.string.desktop_lyric_show'),
          enabled: this.state.supported && !this.state.busy && (this.available || this.state.visible),
          action: (): void => { this.changeVisibility(); }
        },
        {
          value: this.state.locked ? $r('app.string.desktop_lyric_unlock') : $r('app.string.desktop_lyric_lock'),
          enabled: this.state.visible && !this.state.busy,
          action: (): void => { this.changeLock(); }
        }
      ], this.menuOptions())
  }
}
