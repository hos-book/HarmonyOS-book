import { vibrator } from '@kit.SensorServiceKit';
import { TextReadingSettings } from '../../model/TextReading';

/** 单次阅读触觉。能力查询结果缓存；无马达或系统拒绝时不影响翻页。 */
export class ReaderHapticService {
  private static supportedEffects: Map<string, boolean> = new Map();

  static play(value: string): void {
    const level = TextReadingSettings.normalizePageTurnHaptic(value);
    if (level === 'none') return;
    const effectId = level === 'strong' ? 'haptic.effect.hard' :
      level === 'medium' ? 'haptic.effect.sharp' : 'haptic.effect.soft';
    const intensity = level === 'strong' ? 100 : level === 'medium' ? 60 : 30;
    try {
      if (ReaderHapticService.supports(effectId)) {
        // intensity 自 API 12 可用；不支持调强度的硬件使用预置效果本身的力度。
        vibrator.startVibration({ type: 'preset', effectId: effectId, count: 1, intensity: intensity },
          { id: 0, usage: 'touch' }).catch((_error: object): void => {});
      } else {
        const duration = level === 'strong' ? 35 : level === 'medium' ? 20 : 10;
        vibrator.startVibration({ type: 'time', duration: duration },
          { id: 0, usage: 'touch' }).catch((_error: object): void => {});
      }
    } catch (_error) {
      // 同步能力/权限异常也不能中断阅读。
    }
  }

  private static supports(effectId: string): boolean {
    const cached = ReaderHapticService.supportedEffects.get(effectId);
    if (cached !== undefined) return cached;
    let supported = false;
    try { supported = vibrator.isSupportEffectSync(effectId); } catch (_error) {}
    ReaderHapticService.supportedEffects.set(effectId, supported);
    return supported;
  }
}
