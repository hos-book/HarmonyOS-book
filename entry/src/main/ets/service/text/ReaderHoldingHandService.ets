import { motion } from '@kit.MultimodalAwarenessKit';

/** 仅在正文可见时监听握持；不支持的设备保留默认侧边。 */
export class ReaderHoldingHandService {
  private subscribed: boolean = false;
  onChange: (left: boolean) => void = (): void => {};
  private readonly handler = (status: motion.HoldingHandStatus): void => {
    if (!this.subscribed) return;
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) this.onChange(true);
    else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) this.onChange(false);
  };

  setVisible(visible: boolean): void {
    if (!visible) {
      if (!this.subscribed) return;
      this.subscribed = false;
      try { motion.off('holdingHandChanged', this.handler); } catch (_error) { /* 保持静态布局 */ }
      return;
    }
    if (this.subscribed || !canIUse('SystemCapability.MultimodalAwareness.Motion')) return;
    this.subscribed = true;
    try { motion.on('holdingHandChanged', this.handler); }
    catch (_error) { this.subscribed = false; }
  }
}
