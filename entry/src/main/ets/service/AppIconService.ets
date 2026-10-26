import { bundleManager } from '@kit.AbilityKit';
import { PlatformCompat } from '../utils/PlatformCompat';
import { MembershipState } from '../model/MembershipState';

export class AppIconOption {
  name: string;
  label: Resource;
  preview: Resource;

  constructor(name: string, label: Resource, preview: Resource) {
    this.name = name;
    this.label = label;
    this.preview = preview;
  }
}

/** 系统保存桌面图标选择；始终从系统读取，不在偏好设置中伪造成功状态。 */
export class AppIconService {
  private static readonly shared: AppIconService = new AppIconService();
  private changing: boolean = false;

  static get instance(): AppIconService {
    return AppIconService.shared;
  }

  get supported(): boolean {
    return PlatformCompat.supports(26);
  }

  /** 非默认图标要求有效会员权益，系统能力检查独立保留。 */
  get membershipRequired(): boolean {
    return MembershipState.featureEnabled;
  }

  getOptions(): AppIconOption[] {
    return [
      new AppIconOption('', $r('app.string.app_icon_default'), $r('app.media.app_icon_legacy')),
      new AppIconOption('leather', $r('app.string.app_icon_leather'), $r('app.media.app_icon_leather_legacy')),
      new AppIconOption('enamel', $r('app.string.app_icon_enamel'), $r('app.media.app_icon_enamel_legacy')),
      new AppIconOption('ink', $r('app.string.app_icon_ink'), $r('app.media.app_icon_ink_legacy')),
      new AppIconOption('clay', $r('app.string.app_icon_clay'), $r('app.media.app_icon_clay_legacy')),
      new AppIconOption('glass', $r('app.string.app_icon_glass'), $r('app.media.app_icon_glass_legacy')),
      new AppIconOption('origami', $r('app.string.app_icon_origami'), $r('app.media.app_icon_origami_legacy')),
      new AppIconOption('embroidery', $r('app.string.app_icon_embroidery'), $r('app.media.app_icon_embroidery_legacy')),
      new AppIconOption('retro', $r('app.string.app_icon_retro'), $r('app.media.app_icon_retro_legacy')),
      new AppIconOption('cartoon', $r('app.string.app_icon_cartoon'), $r('app.media.app_icon_cartoon_legacy')),
      new AppIconOption('cartooncat', $r('app.string.app_icon_cartooncat'), $r('app.media.app_icon_cartooncat_legacy')),
      new AppIconOption('cartoondog', $r('app.string.app_icon_cartoondog'), $r('app.media.app_icon_cartoondog_legacy')),
      new AppIconOption('wave', $r('app.string.app_icon_wave'), $r('app.media.app_icon_wave_legacy')),
      new AppIconOption('life', $r('app.string.app_icon_life'), $r('app.media.app_icon_life_legacy')),
      new AppIconOption('lifewhite', $r('app.string.app_icon_lifewhite'), $r('app.media.app_icon_lifewhite_legacy')),
      new AppIconOption('waveberry', $r('app.string.app_icon_waveberry'), $r('app.media.app_icon_waveberry_legacy')),
      new AppIconOption('waveorange', $r('app.string.app_icon_waveorange'), $r('app.media.app_icon_waveorange_legacy')),
      new AppIconOption('wavegraphite', $r('app.string.app_icon_wavegraphite'), $r('app.media.app_icon_wavegraphite_legacy')),
      new AppIconOption('wavepurple', $r('app.string.app_icon_wavepurple'), $r('app.media.app_icon_wavepurple_legacy')),
      new AppIconOption('waveclear', $r('app.string.app_icon_waveclear'), $r('app.media.app_icon_waveclear_legacy'))
    ];
  }

  async getCurrent(): Promise<string> {
    if (!this.supported) return '';
    const icons = await bundleManager.getAlternateIcons();
    const current = icons.find((icon: bundleManager.AlternateIconInfo) => icon.enabled);
    return current ? current.iconName : '';
  }

  async select(name: string): Promise<string> {
    if (!this.supported) throw new Error('Alternate icons require API 26');
    if (this.membershipRequired && name !== '' && !MembershipState.current.hasAccess) {
      throw new Error('Active icon membership required');
    }
    if (this.changing) throw new Error('Icon change in progress');
    if (!this.getOptions().some((option: AppIconOption) => option.name === name)) {
      throw new Error('Invalid alternate icon');
    }
    this.changing = true;
    try {
      const current = await this.getCurrent();
      if (this.membershipRequired && name !== '' && !MembershipState.current.hasAccess) {
        throw new Error('Active icon membership required');
      }
      if (current === name) return current;
      await bundleManager.setAlternateIcon(name);
      const applied = await this.getCurrent();
      if (applied !== name) throw new Error('Alternate icon was not applied');
      return applied;
    } finally {
      this.changing = false;
    }
  }
}
