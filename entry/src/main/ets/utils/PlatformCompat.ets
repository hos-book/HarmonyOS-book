import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { uiMaterial } from '@kit.ArkUI';

/** 最低支持 API 20；按接口引入版本选择实现，不能用编译版本判断设备能力。 */
export class PlatformCompat {
  static get wearable(): boolean {
    return deviceInfo.deviceType === 'wearable';
  }

  static get desktopWindow(): boolean {
    return deviceInfo.deviceType === '2in1';
  }

  static supports(apiVersion: number): boolean {
    return deviceInfo.sdkApiVersion >= apiVersion;
  }

  static get immersiveMaterial(): boolean {
    // SMOOTH 是设备算力档，不是系统设置的“弱”；这类设备统一用可见底色回退。
    if (!PlatformCompat.supports(26)) return false;
    try {
      return uiMaterial.isImmersiveMaterialSupported() &&
        uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE &&
        uiMaterial.getGlobalMaterialLevel() !== uiMaterial.MaterialLevel.SMOOTH;
    } catch (_error) {
      return false;
    }
  }

  static get floatingTabs(): boolean {
    return PlatformCompat.supports(23);
  }
}

/** Grid 的内容偏移从 API 22 开始支持；API 20 用内边距保护首尾内容。 */
export class CompatibleGridInsets implements AttributeModifier<GridAttribute> {
  private top: number;
  private bottom: number;
  private horizontal: number;

  constructor(top: number, bottom: number, horizontal: number) {
    this.top = top;
    this.bottom = bottom;
    this.horizontal = horizontal;
  }

  applyNormalAttribute(instance: GridAttribute): void {
    if (PlatformCompat.supports(22)) {
      instance.padding({ left: this.horizontal, right: this.horizontal })
        .contentStartOffset(this.top).contentEndOffset(this.bottom);
    } else {
      instance.padding({ left: this.horizontal, right: this.horizontal, top: this.top, bottom: this.bottom });
    }
  }
}
