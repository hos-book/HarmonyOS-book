import { PlatformCompat } from '../../utils/PlatformCompat';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { fileIo } from '@kit.CoreFileKit';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { CustomTtsConfigParser } from './CustomTtsConfigParser';
import { hilog } from '@kit.PerformanceAnalysisKit';

class TtsErrorDetail {
  code: string = '';
}
class TtsErrorResponse {
  error: TtsErrorDetail = new TtsErrorDetail();
}

class TtsStreamResponse {
  status: number = 0;
  data: ArrayBuffer = new ArrayBuffer(0);
}

/** 仅保留分类与状态码，不向日志或界面泄露服务响应、正文和令牌。 */
export class HttpTtsFailure extends Error {
  kind: string;
  retryable: boolean;

  constructor(kind: string, retryable: boolean, status: number = 0) {
    super(kind === 'network' ? 'TTS network request failed or timed out' : `TTS ${kind} HTTP ${status}`);
    this.kind = kind;
    this.retryable = retryable;
  }

  static response(status: number, body: string | ArrayBuffer): HttpTtsFailure {
    if (status === 401 || status === 403) return new HttpTtsFailure('auth', false, status);
    if (status === 429) return new HttpTtsFailure('rate', true, status);
    // 只读取有界 ASCII 错误代码；服务端 message 不用于展示。
    let text = typeof body === 'string' ? body.slice(0, 16384) : '';
    if (body instanceof ArrayBuffer && body.byteLength <= 16384) {
      const bytes = new Uint8Array(body);
      for (let i = 0; i < bytes.length; i++) text += String.fromCharCode(bytes[i]);
    }
    try {
      const value: TtsErrorResponse = JSON.parse(text);
      const code = value?.error?.code;
      if (code === 'hd_synthesis_failed' || code === 'voice_not_found' || code === 'voice_unavailable' ||
        code === 'unsupported_voice') return new HttpTtsFailure('voice', false, status);
    } catch (_error) { /* 非 JSON 响应按 HTTP 状态分类。 */ }
    if (status === 408) return new HttpTtsFailure('network', true, status);
    if (status >= 500) return new HttpTtsFailure('server', true, status);
    return new HttpTtsFailure('config', false, status);
  }
}

/** 一次连续朗读复用同一个播放器，切段只 reset，停止时才 release。 */
export class HttpTtsAudioOutput {
  private playbackSpeed: number = 1;

  setPlaybackSpeed(speed: number): void {
    this.playbackSpeed = speed;
    const player = this.player;
    if (player !== null && ['prepared', 'playing', 'paused'].includes(player.state)) {
      player.setPlaybackRate(speed);
    }
  }

  applyPlaybackSpeed(player: media.AVPlayer): void {
    player.setPlaybackRate(this.playbackSpeed);
  }

  seekRatio(ratio: number): boolean {
    const player = this.player;
    if (player === null || player.state !== 'playing' || !Number.isFinite(player.duration) || player.duration <= 0) return false;
    try {
      player.seek(Math.floor(Math.max(0, Math.min(0.999, ratio)) * player.duration), media.SeekMode.SEEK_PREV_SYNC);
      return true;
    } catch (_error) { return false; }
  }

  private async boundedCleanup(operation: Promise<void>): Promise<boolean> {
    let timer = -1;
    try {
      return await Promise.race([operation.then((): boolean => true).catch((): boolean => false),
        new Promise<boolean>((resolve): void => { timer = setTimeout((): void => resolve(false), 1500); })]);
    } finally { if (timer !== -1) clearTimeout(timer); }
  }
  private loudnessGain: number = 0;
  private gainOperation: number = 0;

  async setLoudnessGain(gain: number): Promise<boolean> {
    if (!PlatformCompat.supports(21) || !Number.isFinite(gain) || gain < 0 || gain > 24) return false;
    const previous = this.loudnessGain;
    this.loudnessGain = Math.round(gain);
    const operation = ++this.gainOperation;
    const player = this.player;
    if (player === null || !['prepared', 'playing', 'paused', 'completed'].includes(player.state)) return true;
    let timer: number = -1;
    try {
      const completion = player.setLoudnessGain(this.loudnessGain).then((): boolean => true).catch((): boolean => {
        if (operation === this.gainOperation) this.loudnessGain = previous;
        return false;
      });
      const bounded = new Promise<boolean>((resolve): void => { timer = setTimeout((): void => resolve(true), 1500); });
      return await Promise.race([completion, bounded]);
    } catch (_error) {
      if (operation === this.gainOperation) this.loudnessGain = previous;
      return false;
    } finally { if (timer !== -1) clearTimeout(timer); }
  }

  restoreLoudness(): void {
    // 部分设备已应用增幅但 Promise 不返回；切段不能等待 1500ms 的设置超时。
    // 设置方法自行处理失败及过期回调，仍在 play 前提交增幅。
    if (this.loudnessGain > 0) this.setLoudnessGain(this.loudnessGain);
  }

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
      try { if (await this.boundedCleanup(player.reset())) return; }
      catch (_error) { /* 重置失败时丢弃实例，下次重新创建。 */ }
    }
    await this.release();
  }

  async release(): Promise<void> {
    const player = this.player;
    this.player = null;
    if (player !== null) {
      try { await this.boundedCleanup(player.release()); } catch (_error) { /* 已失效的实例不再复用。 */ }
    }
  }
}

/** 合成可提前执行；播放复用会话输出，取消释放预取音频和迟到结果。 */
export class HttpTtsPlayer {
  private static sequence: number = 0;
  private readonly taskId: number = ++HttpTtsPlayer.sequence;
  private stage: string = 'created';

  private trace(stage: string): void {
    this.stage = stage;
    hilog.info(0x0000, 'SpeechQueue', 'task=%{public}d stage=%{public}s', this.taskId, stage);
  }
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
    this.trace('cancel:' + this.stage);
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
    if (this.preparation === null) {
      hilog.info(0x0000, 'SpeechQueue', 'task=%{public}d chars=%{public}d', this.taskId, text.length);
      this.preparation = this.synthesize(config, text, speed);
    }
    return this.preparation;
  }

  private async synthesize(config: CustomTtsConfig, text: string, speed: number): Promise<void> {
    for (let attempt = 0; attempt <= this.retries; attempt++) {
      this.check();
      try { await this.synthesizeOnce(config, text, speed); return; }
      catch (error) {
        this.trace('failed:' + (error instanceof HttpTtsFailure ? error.kind : 'preparation'));
        this.check();
        if (!(error instanceof HttpTtsFailure)) throw new HttpTtsFailure('config', false);
        if (!error.retryable || attempt >= this.retries) throw error;
        await new Promise<void>((resolve, reject): void => {
          const timer = setTimeout((): void => { this.rejectPlayback = null; resolve(); }, 300 * (attempt + 1));
          this.rejectPlayback = (reason: Error): void => { clearTimeout(timer); reject(reason); };
        });
      }
    }
  }

  private async synthesizeOnce(config: CustomTtsConfig, text: string, speed: number): Promise<void> {
    try {
      this.check();
      this.trace('template');
      const url = await CustomTtsConfigParser.expand(config.url, text, speed, false);
      const options = await CustomTtsConfigParser.requestOptions(config, text, speed);
      options.connectTimeout = this.timeoutSeconds * 1000;
      // 系统 readTimeout 是整次传输期限，不能用它充当无数据超时。
      options.readTimeout = Math.min(480000, this.timeoutSeconds * 4000);
      this.check();
      const request = http.createHttp();
      this.request = request;
      this.trace('request');
      const response = await this.receiveAudio(request, url, options);
      this.rejectPlayback = null;
      this.check();
      request.destroy();
      this.request = null;
      if (response.status < 200 || response.status >= 300) {
        throw HttpTtsFailure.response(response.status, response.data);
      }
      if (response.data.byteLength === 0) throw new HttpTtsFailure('audio', false);
      const bytes = new Uint8Array(response.data);
      let first = 0;
      while (first < Math.min(bytes.length, 64) && bytes[first] <= 32) first++;
      if (bytes[first] === 123 || bytes[first] === 91 || bytes[first] === 60) {
        const failure = HttpTtsFailure.response(200, response.data);
        throw failure.kind === 'voice' ? failure : new HttpTtsFailure('audio', false);
      }
      this.preparedAudio = response.data;
      this.trace('ready');
    } finally {
      this.rejectPlayback = null;
      this.request?.destroy();
      this.request = null;
    }
  }

  /** 收到数据即延长空闲期限；保留总时限、8 MiB 上限和取消，完整接收后才交给播放器。 */
  private receiveAudio(request: http.HttpRequest, url: string,
    options: http.HttpRequestOptions): Promise<TtsStreamResponse> {
    let idleTimer = -1;
    let totalTimer = -1;
    let settled = false;
    const chunks: Uint8Array[] = [];
    return new Promise<TtsStreamResponse>((resolve, reject): void => {
      let bytes = 0;
      let status = -1;
      let ended = false;
      const fail = (error: Error | HttpTtsFailure): void => {
        if (settled) return;
        hilog.info(0x0000, 'SpeechQueue', 'task=%{public}d transfer-failed bytes=%{public}d ended=%{public}s status=%{public}d',
          this.taskId, bytes, String(ended), status);
        settled = true;
        reject(error);
      };
      const resetIdle = (): void => {
        if (idleTimer >= 0) clearTimeout(idleTimer);
        idleTimer = setTimeout((): void => fail(new HttpTtsFailure('network', true)), this.timeoutSeconds * 1000);
      };
      const finish = (): void => {
        if (settled || !ended || status < 0) return;
        settled = true;
        const response = new TtsStreamResponse();
        response.data = new ArrayBuffer(bytes);
        const data = new Uint8Array(response.data);
        let offset = 0;
        for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
        response.status = status;
        resolve(response);
      };
      this.rejectPlayback = fail;
      resetIdle();
      totalTimer = setTimeout((): void => fail(new HttpTtsFailure('network', true)),
        Math.min(480000, this.timeoutSeconds * 4000));
      request.on('dataReceive', (chunk: ArrayBuffer): void => {
        if (settled || this.cancelled || chunk.byteLength === 0) return;
        bytes += chunk.byteLength;
        if (bytes > 8 * 1024 * 1024) { fail(new HttpTtsFailure('audio', false)); return; }
        chunks.push(new Uint8Array(chunk));
        resetIdle();
      });
      request.on('dataEnd', (): void => { ended = true; finish(); });
      request.requestInStream(url, options).then((code: number): void => {
        status = code;
        finish();
      }, (): void => fail(new HttpTtsFailure('network', true)));
    }).finally((): void => {
      settled = true;
      if (idleTimer >= 0) clearTimeout(idleTimer);
      if (totalTimer >= 0) clearTimeout(totalTimer);
      chunks.length = 0;
      try { request.off('dataReceive'); request.off('dataEnd'); } catch (_error) { /* 已取消的请求可能已销毁。 */ }
    });
  }

  async speak(context: common.Context, config: CustomTtsConfig, text: string, speed: number,
    requestId: string, onStart: () => void, output: HttpTtsAudioOutput,
    onProgress: ((position: number, duration: number) => void) | null = null): Promise<void> {
    output.setPlaybackSpeed(CustomTtsConfigParser.usesSpeed(config) ? 1 : speed);
    await this.prepare(config, text, speed);
    this.trace('consume');
    const buffer = this.preparedAudio;
    if (buffer === null) throw new Error('TTS audio unavailable');
    await this.speakAudio(context, buffer, CustomTtsConfigParser.usesSpeed(config) ? 1 : speed,
      requestId, onStart, output, onProgress, true);
  }

  async speakAudio(context: common.Context, buffer: ArrayBuffer, speed: number,
    requestId: string, onStart: () => void, output: HttpTtsAudioOutput,
    onProgress: ((position: number, duration: number) => void) | null = null, preserveSpeed: boolean = false): Promise<void> {
    if (!preserveSpeed) output.setPlaybackSpeed(speed);
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
      await this.play(player, file.fd, written, onStart, onProgress, output);
      completed = true;
      this.trace('played');
    } finally {
      this.rejectPlayback = null;
      this.request?.destroy();
      this.request = null;
      this.preparedAudio = null;
      if (player !== null) await output.finish(player, completed && !this.cancelled);
      if (file !== null) await fileIo.close(file).catch((): void => {});
      if (createdFile) await fileIo.unlink(path).catch((): void => {});
      this.trace('cleaned');
    }
  }

  private play(player: media.AVPlayer, fd: number, length: number, onStart: () => void,
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
            const duration = Number.isFinite(player.duration) && player.duration > 0 ? player.duration / 0.5 : 300000;
            playbackTimeout = setTimeout((): void => reject(new Error('TTS playback timed out')),
              Math.max(30000, Math.min(7200000, duration + 30000)));
            output.applyPlaybackSpeed(player);
            output.preparePlayback().then(async (ready: boolean): Promise<void> => {
              this.check();
              if (!ready) throw new Error('TTS focus cancelled');
              output.restoreLoudness();
              this.check();
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
