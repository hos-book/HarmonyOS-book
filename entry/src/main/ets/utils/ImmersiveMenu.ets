import { AppMaterial, AppSpace } from '../theme/Theme';
import { PlatformCompat } from './PlatformCompat';

/** 与设置页 Select 共用材质，圆角、阴影和进出场动画交给原生 Menu。 */
export class ImmersiveMenu {
  static options(onDismiss: () => void, placement: Placement = Placement.BottomRight): MenuOptions {
    const options: MenuOptions = {
      placement: placement,
      enableArrow: false,
      backgroundColor: AppMaterial.SheetBackground,
      onWillDisappear: onDismiss
    };
    if (PlatformCompat.immersiveMaterial) {
      options.backgroundBlurStyle = BlurStyle.NONE;
      options.systemMaterial = AppMaterial.Sheet;
    } else {
      options.backgroundBlurStyle = AppMaterial.SheetBlur;
    }
    if (PlatformCompat.supports(23)) {
      options.keyboardAvoidMode = MenuKeyboardAvoidMode.TRANSLATE_AND_RESIZE;
    }
    return options;
  }

  /** 菜单内可连续搜索、筛选和切换布局；最终选择由各业务回调显式关闭。 */
  static keepOpen(event: TouchEvent): void {
    event.stopPropagation();
  }

  static width(containerWidth: number, preferred: number = 360): number {
    // 为原生菜单栅格限制、外层留白和内部圆角预留空间，内容不能按整个页面铺满。
    return Math.min(preferred, Math.max(1, containerWidth - AppSpace.Md * 4));
  }

  static height(containerHeight: number, preferred: number = 560): number {
    return Math.min(preferred, Math.max(1, containerHeight * 0.68));
  }

  static selection(selected: boolean): ResourceColor {
    return selected ? $r('sys.color.comp_background_tertiary') : Color.Transparent;
  }
}
