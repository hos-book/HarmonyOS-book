import { inputDevice, KeyCode } from '@kit.InputKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlatformCompat } from '../../utils/PlatformCompat';
import { ReaderVolumeKeyService } from './ReaderVolumeKeyService';

/** API 26 智控键滑动；旧系统或无相应硬件时继续使用触摸/原有翻页方式。 */
export class ReaderSmartKeyService {
  private keys: ReaderVolumeKeyService | null = null;
  private enabled: boolean = false;
  private generation: number = 0;
  private onTurn: (forward: boolean) => void = (): void => {};

  setEnabled(enabled: boolean, onTurn: (forward: boolean) => void): void {
    this.onTurn = onTurn;
    if (!enabled || !PlatformCompat.supports(26)) { this.dispose(); return; }
    if (this.enabled) return;
    this.enabled = true;
    const ticket = ++this.generation;
    this.subscribe(ticket).catch((error: Error): void => {
      hilog.warn(0, 'ReaderSmartKey', 'subscribe failed: %{public}s', String(error));
      if (ticket === this.generation) this.dispose();
    });
  }

  private async subscribe(ticket: number): Promise<void> {
    const codes: KeyCode[] = [KeyCode.KEYCODE_FINGERPRINT_SLIDE_UP, KeyCode.KEYCODE_FINGERPRINT_SLIDE_DOWN];
    let up = false;
    let down = false;
    try {
      const devices = await inputDevice.getDeviceList();
      for (const id of devices) {
        if (!this.enabled || ticket !== this.generation) return;
        try {
          const supported = await inputDevice.supportKeys(id, codes);
          up = up || supported[0] === true;
          down = down || supported[1] === true;
        } catch (_error) { /* 设备可能已断开，继续检查其余输入设备。 */ }
        if (up && down) break;
      }
    } catch (error) {
      hilog.warn(0, 'ReaderSmartKey', 'device probe failed: %{public}s', String(error));
    }
    if (!this.enabled || ticket !== this.generation) return;
    // supportKeys 查询物理设备键表，不将未上报的合成滑动键当成订阅失败。
    // API 26 的 keyPressed 才负责优先消费智控键并拦截系统下拉动作。
    hilog.info(0, 'ReaderSmartKey', 'probe up=%{public}s down=%{public}s', String(up), String(down));
    this.keys = new ReaderVolumeKeyService(codes[0], codes[1]);
    const subscribed = this.keys.setEnabled(true, (forward: boolean): void => {
      if (this.enabled && ticket === this.generation) this.onTurn(forward);
    });
    if (!subscribed) {
      this.dispose();
      return;
    }
    hilog.info(0, 'ReaderSmartKey', 'system key interception active');
  }

  dispose(): void {
    this.enabled = false;
    this.generation++;
    this.keys?.dispose();
    this.keys = null;
    this.onTurn = (): void => {};
  }
}
