import { audio } from '@kit.AudioKit';
import { DiagnosticLogService } from './DiagnosticLogService';

/** STOP 无系统恢复通知时的 API 20 回退，只在本应用已暂停期间检查活动流。 */
export class ExternalMediaWatcher {
  private streamMgr: audio.AudioStreamManager | null = null;
  private callback: (() => void) | null = null;
  private timer: number = -1;
  private quietSince: number = 0;
  private armedAt: number = 0;
  private readonly usages: audio.StreamUsage[] = [
    audio.StreamUsage.STREAM_USAGE_MUSIC, audio.StreamUsage.STREAM_USAGE_MOVIE,
    audio.StreamUsage.STREAM_USAGE_AUDIOBOOK, audio.StreamUsage.STREAM_USAGE_GAME,
    audio.StreamUsage.STREAM_USAGE_VOICE_COMMUNICATION, audio.StreamUsage.STREAM_USAGE_VIDEO_COMMUNICATION,
    audio.StreamUsage.STREAM_USAGE_VOICE_MESSAGE, audio.StreamUsage.STREAM_USAGE_VOICE_ASSISTANT,
    audio.StreamUsage.STREAM_USAGE_ALARM, audio.StreamUsage.STREAM_USAGE_RINGTONE,
    audio.StreamUsage.STREAM_USAGE_NAVIGATION, audio.StreamUsage.STREAM_USAGE_ACCESSIBILITY,
    audio.StreamUsage.STREAM_USAGE_NOTIFICATION
  ];
  private readonly listener = (_info: audio.AudioRendererChangeInfoArray): void => { this.check(); };

  arm(callback: () => void): void {
    this.disarm();
    try {
      this.streamMgr = audio.getAudioManager().getStreamManager();
      this.streamMgr.on('audioRendererChange', this.listener);
      this.callback = callback;
      this.armedAt = Date.now();
      // 暂停但未释放的 renderer 不代表仍在播放；活动查询覆盖这种情况。
      this.timer = setInterval((): void => { this.check(); }, 1000);
    } catch (error) {
      this.disarm();
      DiagnosticLogService.failure('audio.focus.watch', error);
    }
  }

  disarm(): void {
    if (this.timer >= 0) clearInterval(this.timer);
    this.timer = -1;
    this.callback = null;
    this.quietSince = 0;
    try { this.streamMgr?.off('audioRendererChange', this.listener); } catch (_error) {}
  }

  isArmed(): boolean { return this.callback !== null; }

  private check(): void {
    if (this.callback === null || this.streamMgr === null || Date.now() - this.armedAt < 500) return;
    try {
      for (const usage of this.usages) {
        if (this.streamMgr.isStreamActive(usage)) { this.quietSince = 0; return; }
      }
    } catch (_error) {
      this.quietSince = 0;
      return; // 查询失败不能证明打断已结束。
    }
    const now = Date.now();
    if (this.quietSince === 0) { this.quietSince = now; return; }
    if (now - this.quietSince < 600) return;
    const callback = this.callback;
    this.disarm();
    callback();
  }
}
