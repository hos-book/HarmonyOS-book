import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { fileIo } from '@kit.CoreFileKit';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { CustomTtsConfigParser } from './CustomTtsConfigParser';

/** 一次连续朗读复用同一个播放器，切段只 reset，停止时才 release。 */
export class HttpTtsAudioOutput {
  private player: media.AVPlayer | null = null;
  private onInterrupt: ((event: audio.InterruptEvent) => void) | null;
  private onDeviceUnavailable: (() => void) | null;
  private beforePlay: (() => Promise<boolean>) | null;

  constructor(onInterrupt: ((event: audio.InterruptEvent) => void) | null = null,
    onDeviceUnavailable: (() => void) | null = null, beforePlay: (() => Promise<boolean>) | null = null) {
    this.onInterrupt = onInterrupt;
    this.onDeviceUnavailable = onDeviceUnavailable;
    this.beforePlay = beforePlay;
  }

  async preparePlayback(): Promise<boolean> {
    return this.beforePlay === null ? true : await this.beforePlay();
  }

  handleInterrupt(event: audio.InterruptEvent): boolean {
    if (this.onInterrupt === null) return false;
    this.onInterrupt(event);
    return true;
  }

  handleDeviceChange(info: audio.AudioStreamDeviceChangeInfo): void {
    if (info.changeReason === audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE) {
      this.onDeviceUnavailable?.();
    }
  }

  async acquire(): Promise<media.AVPlayer> {
    if (this.player === null) this.player = await media.createAVPlayer();
    return this.player;
  }

  async finish(player: media.AVPlayer, reusable: boolean): Promise<void> {
    try {
      player.off('stateChange');
      player.off('error');
      player.off('audioInterrupt');
      player.off('audioOutputDeviceChangeWithInfo');
      player.off('timeUpdate');
    } catch (_error) { reusable = false; }
    if (this.player !== player) return;
    if (reusable) {
      try { await player.reset(); return; }
      catch (_error) { /* 重置失败时丢弃实例，下次重新创建。 */ }
    }
    await this.release();
  }

  async release(): Promise<void> {
    const player = this.player;
    this.player = null;
    if (player !== null) await player.release().catch((): void => {});
  }
}

/** 合成可提前执行；播放复用会话输出，取消释放预取音频和迟到结果。 */
export class HttpTtsPlayer {
  private cancelled: boolean = false;
  private request: http.HttpRequest | null = null;
  private rejectPlayback: ((error: Error) => void) | null = null;
  private preparation: Promise<void> | null = null;
  private preparedAudio: ArrayBuffer | null = null;

  private timeoutSeconds: number;
  private retries: number;
  constructor(timeoutSeconds: number = 30, retries: number = 2) {
    this.timeoutSeconds = timeoutSeconds;
    this.retries = retries;
  }

  get ready(): boolean { return this.preparedAudio !== null && !this.cancelled; }

  cancel(): void {
    this.cancelled = true;
    this.request?.destroy();
    this.request = null;
    this.preparedAudio = null;
    this.rejectPlayback?.(new Error('TTS cancelled'));
  }

  private check(): void {
    if (this.cancelled) throw new Error('TTS cancelled');
  }

  prepare(config: CustomTtsConfig, text: string, speed: number): Promise<void> {
    if (this.preparation === null) this.preparation = this.synthesize(config, text, speed);
    return this.preparation;
  }

  private async synthesize(config: CustomTtsConfig, text: string, speed: number): Promise<void> {
    for (let attempt = 0; attempt <= this.retries; attempt++) {
      this.check();
      try { await this.synthesizeOnce(config, text, speed); return; }
      catch (error) {
        this.check();
        if (attempt >= this.retries) throw new Error(String(error));
        await new Promise<void>((resolve, reject): void => {
          const timer = setTimeout((): void => { this.rejectPlayback = null; resolve(); }, 300 * (attempt + 1));
          this.rejectPlayback = (reason: Error): void => { clearTimeout(timer); reject(reason); };
        });
      }
    }
  }

  private async synthesizeOnce(config: CustomTtsConfig, text: string, speed: number): Promise<void> {
    let timeout = -1;
    try {
      this.check();
      const url = await CustomTtsConfigParser.expand(config.url, text, speed, false);
      const options = await CustomTtsConfigParser.requestOptions(config, text, speed);
      options.connectTimeout = this.timeoutSeconds * 1000;
      options.readTimeout = this.timeoutSeconds * 1000;
      this.check();
      const request = http.createHttp();
      this.request = request;
      const response = await new Promise<http.HttpResponse>((resolve, reject): void => {
        this.rejectPlayback = reject;
        timeout = setTimeout((): void => {
          reject(new Error('TTS request timed out'));
          request.destroy();
        }, this.timeoutSeconds * 1000);
        request.request(url, options).then(resolve, reject);
      });
      this.rejectPlayback = null;
      this.check();
      request.destroy();
      this.request = null;
      if (response.responseCode < 200 || response.responseCode >= 300 ||
        !(response.result instanceof ArrayBuffer) || response.result.byteLength === 0 ||
        response.result.byteLength > 8 * 1024 * 1024) throw new Error('Invalid TTS audio response');
      this.preparedAudio = response.result;
    } finally {
      if (timeout >= 0) clearTimeout(timeout);
      this.rejectPlayback = null;
      this.request?.destroy();
      this.request = null;
    }
  }

  async speak(context: common.Context, config: CustomTtsConfig, text: string, speed: number,
    requestId: string, onStart: () => void, output: HttpTtsAudioOutput,
    onProgress: ((position: number, duration: number) => void) | null = null): Promise<void> {
    await this.prepare(config, text, speed);
    const buffer = this.preparedAudio;
    if (buffer === null) throw new Error('TTS audio unavailable');
    await this.speakAudio(context, buffer, CustomTtsConfigParser.usesSpeed(config) ? 1 : speed,
      requestId, onStart, output, onProgress);
  }

  async speakAudio(context: common.Context, buffer: ArrayBuffer, speed: number,
    requestId: string, onStart: () => void, output: HttpTtsAudioOutput,
    onProgress: ((position: number, duration: number) => void) | null = null): Promise<void> {
    const path = `${context.cacheDir}/custom_${requestId}.audio`;
    let file: fileIo.File | null = null;
    let player: media.AVPlayer | null = null;
    let createdFile = false;
    let completed = false;
    try {
      this.check();
      file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      createdFile = true;
      this.check();
      const written = await fileIo.write(file.fd, buffer);
      this.preparedAudio = null;
      if (written !== buffer.byteLength) throw new Error('Incomplete TTS audio');
      this.check();
      player = await output.acquire();
      this.check();
      await this.play(player, file.fd, written, speed, onStart, onProgress, output);
      completed = true;
    } finally {
      this.rejectPlayback = null;
      this.request?.destroy();
      this.request = null;
      this.preparedAudio = null;
      if (player !== null) await output.finish(player, completed && !this.cancelled);
      if (file !== null) await fileIo.close(file).catch((): void => {});
      if (createdFile) await fileIo.unlink(path).catch((): void => {});
    }
  }

  private play(player: media.AVPlayer, fd: number, length: number, speed: number, onStart: () => void,
    onProgress: ((position: number, duration: number) => void) | null, output: HttpTtsAudioOutput): Promise<void> {
    let playbackTimeout = -1;
    return new Promise<void>((resolve, reject): void => {
      this.rejectPlayback = reject;
      playbackTimeout = setTimeout((): void => reject(new Error('TTS player prepare timed out')), 30000);
      if (onProgress !== null) {
        player.on('timeUpdate', (position: number): void => {
          if (!this.cancelled && player.state === 'playing') onProgress(position, player.duration);
        });
      }
      player.on('error', (): void => reject(new Error('TTS audio playback failed')));
      player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
        if (this.cancelled) return;
        if (output.handleInterrupt(event)) return;
        if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
          event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) reject(new Error('TTS audio interrupted'));
      });
      player.on('audioOutputDeviceChangeWithInfo', (info: audio.AudioStreamDeviceChangeInfo): void => {
        if (!this.cancelled) output.handleDeviceChange(info);
      });
      player.on('stateChange', (state: media.AVPlayerState): void => {
        if (this.cancelled) { reject(new Error('TTS cancelled')); return; }
        if (state === 'initialized') {
          try {
            player.audioRendererInfo = { usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK, rendererFlags: 0 };
            player.prepare().catch((): void => reject(new Error('TTS audio prepare failed')));
          } catch (_error) { reject(new Error('TTS audio prepare failed')); }
        } else if (state === 'prepared') {
          try {
            // 批量音频可超过旧的 150 秒固定期限，按真实媒体时长设置有界保护。
            clearTimeout(playbackTimeout);
            const duration = Number.isFinite(player.duration) && player.duration > 0 ? player.duration / speed : 150000;
            playbackTimeout = setTimeout((): void => reject(new Error('TTS playback timed out')),
              Math.max(30000, Math.min(7200000, duration + 30000)));
            player.setPlaybackRate(speed);
            output.preparePlayback().then(async (ready: boolean): Promise<void> => {
              this.check();
              if (!ready) throw new Error('TTS focus cancelled');
              await player.play();
            }).catch((): void => reject(new Error('TTS audio play failed')));
          } catch (_error) { reject(new Error('TTS audio play failed')); }
        } else if (state === 'playing') {
          onStart();
        } else if (state === 'completed') {
          resolve();
        }
      });
      player.fdSrc = { fd: fd, offset: 0, length: length };
    }).finally((): void => { if (playbackTimeout >= 0) clearTimeout(playbackTimeout); });
  }
}
