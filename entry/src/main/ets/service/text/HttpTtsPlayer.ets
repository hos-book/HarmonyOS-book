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

  async acquire(): Promise<media.AVPlayer> {
    if (this.player === null) this.player = await media.createAVPlayer();
    return this.player;
  }

  async finish(player: media.AVPlayer, reusable: boolean): Promise<void> {
    try {
      player.off('stateChange');
      player.off('error');
      player.off('audioInterrupt');
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
    try {
      this.check();
      const url = await CustomTtsConfigParser.expand(config.url, text, speed, false);
      const options = await CustomTtsConfigParser.requestOptions(config, text, speed);
      this.check();
      const request = http.createHttp();
      this.request = request;
      const response = await new Promise<http.HttpResponse>((resolve, reject): void => {
        this.rejectPlayback = reject;
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
      await this.play(player, file.fd, written, speed, onStart, onProgress);
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
    onProgress: ((position: number, duration: number) => void) | null): Promise<void> {
    return new Promise<void>((resolve, reject): void => {
      this.rejectPlayback = reject;
      if (onProgress !== null) {
        player.on('timeUpdate', (position: number): void => {
          if (!this.cancelled && player.state === 'playing') onProgress(position, player.duration);
        });
      }
      player.on('error', (): void => reject(new Error('TTS audio playback failed')));
      player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
        if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
          event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) reject(new Error('TTS audio interrupted'));
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
            player.setPlaybackRate(speed);
            player.play().catch((): void => reject(new Error('TTS audio play failed')));
          } catch (_error) { reject(new Error('TTS audio play failed')); }
        } else if (state === 'playing') {
          onStart();
        } else if (state === 'completed') {
          resolve();
        }
      });
      player.fdSrc = { fd: fd, offset: 0, length: length };
    });
  }
}
