import { audio } from '@kit.AudioKit';
import { NativeSpeechStreamStatus, createSpeechStream, feedSpeechStream, finishSpeechStream,
  startSpeechStream, cancelSpeechStream, readSpeechPcm, speechStreamStatus } from 'libhsda_core.so';

export class SpeechAudioStream {
  private handle: Object = createSpeechStream();
  private bytes: number = 0;
  private pcmDuration: number = 0;
  private estimatedDuration: number = 0;
  cancelled: boolean = false;

  append(data: ArrayBuffer, sampleRate: number = 0, fraction: number = 0): void {
    if (this.cancelled) return;
    this.bytes += data.byteLength;
    if (this.bytes > 8 * 1024 * 1024) throw new Error('TTS audio budget exceeded');
    feedSpeechStream(this.handle, data, sampleRate);
    if (sampleRate > 0) {
      this.pcmDuration += data.byteLength * 1000 / (sampleRate * 2);
      if (fraction > 0) this.estimatedDuration = this.pcmDuration / fraction;
    }
  }

  finish(): void { if (!this.cancelled) finishSpeechStream(this.handle); }
  start(): void { if (!this.cancelled) startSpeechStream(this.handle); }
  status(): NativeSpeechStreamStatus {
    const value = speechStreamStatus(this.handle);
    if (value.duration === 0) value.duration = this.estimatedDuration;
    return value;
  }
  read(buffer: ArrayBuffer): number { return readSpeechPcm(this.handle, buffer); }
  cancel(): void { this.cancelled = true; cancelSpeechStream(this.handle); }
}

/** Keep one PCM renderer across synthesis segments and chapter boundaries. */
export class SpeechPcmOutput {
  private renderer: audio.AudioRenderer | null = null;
  private stream: SpeechAudioStream | null = null;
  private rate: number = 0;
  private channels: number = 0;
  private mediaFrames: number = 0;
  private speed: number = 1;
  private gain: number = 0;
  private reject: ((error: Error) => void) | null = null;

  setSpeed(speed: number): void {
    this.speed = speed;
    this.renderer?.setSpeed(speed);
  }

  async setGain(gain: number): Promise<void> {
    if (this.renderer !== null) await this.renderer.setLoudnessGain(gain);
    this.gain = gain;
  }

  private async acquire(rate: number, channels: number, onInterrupt: (event: audio.InterruptEvent) => void,
    onDevice: (event: audio.AudioStreamDeviceChangeInfo) => void): Promise<audio.AudioRenderer> {
    if (this.renderer !== null && this.rate === rate && this.channels === channels) return this.renderer;
    await this.releaseRenderer();
    const options: audio.AudioRendererOptions = {
      streamInfo: { samplingRate: rate, channels: channels,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE, encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW },
      rendererInfo: { usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK, rendererFlags: 0 }
    };
    const renderer = await audio.createAudioRenderer(options);
    this.renderer = renderer;
    this.rate = rate;
    this.channels = channels;
    renderer.on('audioInterrupt', onInterrupt);
    renderer.on('outputDeviceChangeWithInfo', onDevice);
    renderer.on('writeData', (buffer: ArrayBuffer): audio.AudioDataCallbackResult => {
      const used = this.stream?.read(buffer) ?? 0;
      if (used === 0) return audio.AudioDataCallbackResult.INVALID;
      this.mediaFrames += used / (channels * 2);
      return audio.AudioDataCallbackResult.VALID;
    });
    renderer.setSpeed(this.speed);
    if (this.gain > 0) renderer.setLoudnessGain(this.gain).catch((): void => {});
    return renderer;
  }

  async play(stream: SpeechAudioStream, onStart: () => void,
    onProgress: ((position: number, duration: number) => void) | null,
    beforePlay: () => Promise<boolean>, onInterrupt: (event: audio.InterruptEvent) => void,
    onDevice: (event: audio.AudioStreamDeviceChangeInfo) => void): Promise<void> {
    stream.start();
    let timer = -1;
    let status = stream.status();
    while (status.rate === 0 || status.queued === 0) {
      if (stream.cancelled) throw new Error('TTS cancelled');
      if (status.error) throw new Error(status.error);
      if (status.done) throw new Error('TTS audio empty');
      await new Promise<void>((resolve): void => { setTimeout(resolve, 20); });
      status = stream.status();
    }
    if (!await beforePlay()) throw new Error('TTS focus cancelled');
    if (stream.cancelled) throw new Error('TTS cancelled');
    const renderer = await this.acquire(status.rate, status.channels, onInterrupt, onDevice);
    if (stream.cancelled) throw new Error('TTS cancelled');
    this.mediaFrames = 0;
    let started = false;
    let draining = false;
    try {
      if (renderer.state !== audio.AudioState.STATE_RUNNING) await renderer.start();
      if (stream.cancelled) throw new Error('TTS cancelled');
      let lastFrame = renderer.getAudioTimestampInfoSync().framePos;
      let position = 0;
      this.stream = stream;
      await new Promise<void>((resolve, reject): void => {
        this.reject = reject;
        const poll = (): void => {
          try {
            if (stream.cancelled) throw new Error('TTS cancelled');
            const status = stream.status();
            if (status.error) throw new Error(status.error);
            const frame = renderer.getAudioTimestampInfoSync().framePos;
            position += frame >= lastFrame ? frame - lastFrame : frame;
            lastFrame = frame;
            if (!started && position > 0) { started = true; onStart(); }
            if (started && status.duration > 0) onProgress?.(position * 1000 / status.rate, status.duration);
            if (status.done && status.queued === 0 && this.mediaFrames > 0) {
              if (!draining) {
                draining = true;
                renderer.drain().then((): void => {
                  if (stream.cancelled) { reject(new Error('TTS cancelled')); return; }
                  if (!started) { started = true; onStart(); }
                  onProgress?.(status.duration, status.duration);
                  resolve();
                }).catch((error: Error): void => { reject(error); });
              }
            }
            timer = setTimeout((): void => { poll(); }, 20);
          } catch (error) { reject(error instanceof Error ? error : new Error(String(error))); }
        };
        poll();
      });
    } finally {
      if (timer >= 0) clearTimeout(timer);
      this.stream = null;
      this.reject = null;
    }
  }

  cancel(): void {
    this.stream?.cancel();
    this.stream = null;
    this.reject?.(new Error('TTS cancelled'));
  }

  private async releaseRenderer(): Promise<void> {
    const renderer = this.renderer;
    this.renderer = null;
    if (renderer !== null) await renderer.release();
  }

  async release(): Promise<void> { this.cancel(); await this.releaseRenderer(); }
}
