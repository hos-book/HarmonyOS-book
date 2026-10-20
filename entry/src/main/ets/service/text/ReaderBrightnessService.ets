import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { TextReadingSettings } from '../../model/TextReading';

/** 仅在正文可见时接管窗口亮度，离页恢复之前的窗口设置。 */
export class ReaderBrightnessService {
  private mainWindow: window.Window | null = null;
  private visible: boolean = false;
  private brightness: number = -1;
  private previous: number = -1;
  private owned: boolean = false;
  private serial: number = 0;
  private queue: Promise<void> = Promise.resolve();
  onFailure: () => void = (): void => {};

  async init(context: common.Context): Promise<void> {
    const ticket = ++this.serial;
    const win = await window.getLastWindow(context);
    if (ticket !== this.serial) return;
    this.mainWindow = win;
    this.apply();
  }

  configure(value: number): void {
    this.brightness = TextReadingSettings.normalizeBrightness(value);
    this.apply();
  }

  setVisible(visible: boolean): void {
    this.visible = visible;
    this.apply();
  }

  private apply(): void {
    const win = this.mainWindow;
    if (win === null) return;
    this.queue = this.queue.then(async (): Promise<void> => {
      if (!this.visible) {
        if (this.owned) {
          await win.setWindowBrightness(this.previous);
          this.owned = false;
        }
        return;
      }
      if (!this.owned) {
        this.previous = win.getWindowProperties().brightness;
        this.owned = true;
      }
      await win.setWindowBrightness(this.brightness);
    }).catch((): void => { if (this.visible) this.onFailure(); });
  }

  dispose(): void {
    this.serial++;
    this.visible = false;
    this.apply();
    this.mainWindow = null;
  }
}
