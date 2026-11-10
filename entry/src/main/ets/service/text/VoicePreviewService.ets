import { common } from '@kit.AbilityKit';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { TextToSpeechState } from '../../model/TextToSpeechState';
import { AudioService } from '../AudioService';
import { AudioFocusService } from '../AudioFocusService';
import { PlaybackCoordinator } from '../PlaybackCoordinator';
import { TextToSpeechService } from './TextToSpeechService';
import { HttpTtsAudioOutput, HttpTtsPlayer } from './HttpTtsPlayer';
import { SpeechPcmBuffer } from './SpeechPcmBuffer';
import { RoleSpeechSample } from '../../model/RoleSpeech';

@ObservedV2
export class VoicePreviewState {
  @Trace active: boolean = false;
  @Trace loading: boolean = false;
  @Trace error: boolean = false;
}

/** 短句试听独占临时输出，不创建书籍会话、记录或续读位置。 */
export class VoicePreviewService {
  readonly state: VoicePreviewState = new VoicePreviewState();
  private generation: number = 0;
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private player: HttpTtsPlayer | null = null;
  private output: HttpTtsAudioOutput | null = null;
  private cancelSynthesis: (() => void) | null = null;
  private timer: number = -1;
  private resumeTicket: number = -1;
  private releasing: Promise<void> = Promise.resolve();
  private finishing: Promise<void> | null = null;
  private readonly stopHandler = (): void => this.stop();

  stop(): void {
    this.generation++;
    this.resumeTicket = -1;
    this.finishing = null;
    this.state.active = false;
    this.state.loading = false;
    if (this.timer !== -1) clearTimeout(this.timer);
    this.timer = -1;
    const cancel = this.cancelSynthesis;
    this.cancelSynthesis = null;
    cancel?.();
    const engine = this.engine;
    this.engine = null;
    try { engine?.stop(); } catch (_error) { /* 已结束。 */ }
    try { engine?.shutdown(); } catch (_error) { /* 引擎已释放。 */ }
    this.player?.cancel();
    this.player = null;
    const outputRelease: Promise<void> = this.output?.release().catch((): void => {}) ?? Promise.resolve();
    this.output = null;
    let focusRelease: Promise<void> = Promise.resolve();
    if (PlaybackCoordinator.stopPreview === this.stopHandler) {
      PlaybackCoordinator.stopPreview = null;
      focusRelease = AudioFocusService.getInstance().release('voice-preview');
    }
    this.releasing = Promise.all([this.releasing, outputRelease, focusRelease]).then((): void => {});
  }

  stopAndResume(): Promise<void> {
    // 弹层关闭、隐藏、销毁共用同一次结束，不能重复撤销恢复凭据。
    if (this.finishing !== null) return this.finishing;
    if (!this.state.active) return Promise.resolve();
    const ticket = this.resumeTicket;
    this.stop();
    const generation = this.generation;
    this.resumeTicket = ticket;
    // 释放期间仍允许后台事件、媒体抢占和新试听取消这次恢复。
    PlaybackCoordinator.stopPreview = this.stopHandler;
    const task = this.releasing.then(async (): Promise<void> => {
      if (generation !== this.generation || PlaybackCoordinator.stopPreview !== this.stopHandler) return;
      PlaybackCoordinator.stopPreview = null;
      this.resumeTicket = -1;
      this.finishing = null;
      await TextToSpeechService.getInstance().resumeAfterPreview(ticket);
    });
    this.finishing = task;
    return task;
  }

  private valid(ticket: number): boolean { return ticket === this.generation && this.state.active; }

  async play(context: common.Context, selected: TextToSpeechState, sample: string): Promise<void> {
    await this.playSequence(context, selected, [new RoleSpeechSample(sample, selected.customTtsId)]);
  }

  async playSequence(context: common.Context, selected: TextToSpeechState, samples: RoleSpeechSample[],
    restoreSpeech: boolean = false): Promise<void> {
    if (!samples.slice(0, 6).some((sample: RoleSpeechSample): boolean => sample.text.trim().length > 0)) return;
    const speech = TextToSpeechService.getInstance();
    const inheritedTicket = restoreSpeech && speech.canResumePreview(this.resumeTicket) ? this.resumeTicket : -1;
    PlaybackCoordinator.stopPreview?.();
    this.stop();
    const ticket = this.generation;
    const configs = selected.customTtsConfigs.slice();
    const defaultVoice = selected.customTtsId;
    const person = selected.person;
    const language = selected.language;
    const speed = selected.speed;
    this.state.error = false;
    this.state.active = true;
    this.state.loading = true;
    PlaybackCoordinator.stopPreview = this.stopHandler;
    // 试听不重试长时间请求；用户可停止后再次试听。
    const timeout = Math.max(5, Math.min(30, selected.synthesis.timeoutSeconds));
    this.timer = setTimeout((): void => {
      if (this.valid(ticket)) {
        this.state.error = true;
        if (restoreSpeech) this.stopAndResume().catch((): void => {});
        else this.stop();
      }
    }, (timeout * 4 + 30) * 1000);
    const output = new HttpTtsAudioOutput(
      (event: audio.InterruptEvent): void => AudioFocusService.getInstance().handleInterrupt('voice-preview', event),
      (): void => this.stop(),
      async (): Promise<boolean> => this.valid(ticket) && await AudioFocusService.getInstance().ensureActive('voice-preview'));
    this.output = output;
    try {
      if (restoreSpeech) this.resumeTicket = inheritedTicket >= 0 ? inheritedTicket : speech.pauseForPreview();
      else speech.pause();
      await this.releasing;
      if (!this.valid(ticket)) return;
      await AudioService.getInstance().suspendForSpeech();
      if (!this.valid(ticket)) return;
      await AudioFocusService.getInstance().acquire('voice-preview', (): void => this.stop(), async (): Promise<void> => {});
      if (!this.valid(ticket)) return;
      await output.setLoudnessGain(selected.loudnessGain);
      if (!this.valid(ticket)) return;
      const started = (): void => { if (this.valid(ticket)) this.state.loading = false; };
      let budget = 300;
      let index = 0;
      for (const sample of samples.slice(0, 6)) {
        if (!this.valid(ticket) || budget <= 0) return;
        const text = sample.text.trim().slice(0, budget);
        if (!text) continue;
        budget -= text.length;
        const voiceId = sample.voiceId || defaultVoice;
        const config = configs.find((item): boolean => item.id === voiceId && item.enabled);
        if (voiceId && config === undefined) throw new Error('Selected voice unavailable');
        const id = `preview${Date.now()}n${ticket}p${index++}`;
        // 每个片段使用独立请求，不能复用上一人物的已合成音频。
        const segmentPlayer = new HttpTtsPlayer(timeout, 0);
        this.player = segmentPlayer;
        try {
          if (config !== undefined) await segmentPlayer.speak(context, config, text, speed, id, started, output);
          else {
            const buffer = await this.synthesize(person, language, text, Math.min(2, speed), id, ticket);
            if (!this.valid(ticket)) return;
            await segmentPlayer.speakAudio(context, buffer, Math.max(1, speed / 2), id, started, output);
          }
        } finally { segmentPlayer.cancel(); }
      }
    } catch (_error) {
      if (this.valid(ticket)) this.state.error = true;
    } finally {
      if (this.valid(ticket)) {
        if (restoreSpeech) await this.stopAndResume();
        else this.stop();
      }
      await output.release();
    }
  }

  private synthesize(person: number, language: string, sample: string, speed: number,
    id: string, ticket: number): Promise<ArrayBuffer> {
    try { this.engine?.shutdown(); } catch (_error) { /* 上一段的独立引擎已结束。 */ }
    this.engine = null;
    return new Promise<ArrayBuffer>((resolve, reject): void => {
      const pcm = new SpeechPcmBuffer();
      let finished = false;
      const fail = (): void => {
        if (finished) return;
        finished = true;
        pcm.reset();
        reject(new Error('Voice preview synthesis failed'));
      };
      this.cancelSynthesis = fail;
      const params: textToSpeech.CreateEngineParams = {
        person: person, language: language, online: 1, extraParams: { 'name': 'ListenBookVoicePreview' }
      };
      textToSpeech.createEngine(params).then((engine: textToSpeech.TextToSpeechEngine): void => {
        if (!this.valid(ticket) || finished) { engine.shutdown(); return; }
        this.engine = engine;
        const listener: textToSpeech.SpeakListener = {
          onStart: (requestId: string, response: textToSpeech.StartResponse): void => {
            if (requestId !== id || !this.valid(ticket) || finished) return;
            try { pcm.configure(response); } catch (_error) { fail(); }
          },
          onData: (requestId: string, data: ArrayBuffer, response: textToSpeech.SynthesisResponse): void => {
            if (requestId !== id || !this.valid(ticket) || finished) return;
            try { pcm.append(data, response); } catch (_error) { fail(); }
          },
          onComplete: (requestId: string, response: textToSpeech.CompleteResponse): void => {
            if (requestId !== id || response.type !== 0 || !this.valid(ticket) || finished) return;
            try {
              const buffer = pcm.toWave();
              finished = true;
              this.cancelSynthesis = null;
              pcm.reset();
              resolve(buffer);
            } catch (_error) { fail(); }
          },
          onStop: (requestId: string, _response: textToSpeech.StopResponse): void => { if (requestId === id) fail(); },
          onError: (requestId: string, _code: number, _message: string): void => { if (requestId === id) fail(); }
        };
        engine.setListener(listener);
        const speak: textToSpeech.SpeakParams = { requestId: id, extraParams: {
          'queueMode': 0, 'speed': speed, 'volume': 1, 'pitch': 1, 'languageContext': language,
          'audioType': 'pcm', 'soundChannel': 1, 'playType': 0
        } };
        engine.speak(sample, speak);
      }).catch((): void => fail());
    });
  }
}
