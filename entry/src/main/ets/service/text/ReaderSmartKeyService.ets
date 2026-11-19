import { inputDevice, KeyCode } from '@kit.InputKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlatformCompat } from '../../utils/PlatformCompat';
import { ReaderVolumeKeyService } from './ReaderVolumeKeyService';

/** API 26 智控键滑动；旧系统或无相应硬件时继续使用触摸/原有翻页方式。 */
export class ReaderSmartKeyService {
  private static detection: Promise<boolean> | null = null;
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

  /** 页面入口和事件订阅共用设备检测结果，旧偏好不能绕过支持检查。 */
  static detectSupport(): Promise<boolean> {
    if (!ReaderSmartKeyService.detection) {
      ReaderSmartKeyService.detection = ReaderSmartKeyService.querySupport();
    }
    return ReaderSmartKeyService.detection;
  }

  private static async querySupport(): Promise<boolean> {
    if (!PlatformCompat.supports(26)) return false;
    const codes: KeyCode[] = [KeyCode.KEYCODE_FINGERPRINT_SLIDE_UP, KeyCode.KEYCODE_FINGERPRINT_SLIDE_DOWN];
    let up = false;
    let down = false;
    try {
      const devices = await inputDevice.getDeviceList();
      for (const id of devices) {
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
    hilog.info(0, 'ReaderSmartKey', 'probe up=%{public}s down=%{public}s', String(up), String(down));
    return up || down;
  }

  private async subscribe(ticket: number): Promise<void> {
    const supported = await ReaderSmartKeyService.detectSupport();
    if (!this.enabled || ticket !== this.generation) return;
    if (!supported) { this.dispose(); return; }
    const codes: KeyCode[] = [KeyCode.KEYCODE_FINGERPRINT_SLIDE_UP, KeyCode.KEYCODE_FINGERPRINT_SLIDE_DOWN];
    this.keys = new ReaderVolumeKeyService(codes[0], codes[1]);
    const subscribed = this.keys.setEnabled(true, (forward: boolean): void => {
      if (this.enabled && ticket === this.generation) {
        hilog.info(0, 'ReaderSmartKey', 'slide %{public}s', forward ? 'down' : 'up');
        this.onTurn(forward);
      }
    });
    if (!subscribed) {
      this.dispose();
      return;
    }
    hilog.info(0, 'ReaderSmartKey', 'slide key subscription registered');
  }

  dispose(): void {
    this.enabled = false;
    this.generation++;
    this.keys?.dispose();
    this.keys = null;
    this.onTurn = (): void => {};
  }
}
