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
  private readonly stopHandler = (): void => this.stop();

  stop(): void {
    this.generation++;
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
    this.output?.release();
    this.output = null;
    if (PlaybackCoordinator.stopPreview === this.stopHandler) {
      PlaybackCoordinator.stopPreview = null;
      AudioFocusService.getInstance().release('voice-preview');
    }
  }

  private valid(ticket: number): boolean { return ticket === this.generation && this.state.active; }

  async play(context: common.Context, selected: TextToSpeechState, sample: string): Promise<void> {
    PlaybackCoordinator.stopPreview?.();
    this.stop();
    const ticket = this.generation;
    const config = selected.customTtsConfigs.find((item): boolean => item.id === selected.customTtsId && item.enabled);
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
      if (this.valid(ticket)) { this.stop(); this.state.error = true; }
    }, (timeout * 4 + 30) * 1000);
    const output = new HttpTtsAudioOutput(
      (event: audio.InterruptEvent): void => AudioFocusService.getInstance().handleInterrupt('voice-preview', event),
      (): void => this.stop(),
      async (): Promise<boolean> => this.valid(ticket) && await AudioFocusService.getInstance().ensureActive('voice-preview'));
    const player = new HttpTtsPlayer(timeout, 0);
    this.output = output;
    this.player = player;
    try {
      if (selected.customTtsId && config === undefined) throw new Error('Selected voice unavailable');
      TextToSpeechService.getInstance().pause();
      await AudioService.getInstance().suspendForSpeech();
      if (!this.valid(ticket)) return;
      await AudioFocusService.getInstance().acquire('voice-preview', (): void => this.stop(), async (): Promise<void> => {});
      if (!this.valid(ticket)) return;
      await output.setLoudnessGain(selected.loudnessGain);
      if (!this.valid(ticket)) return;
      const id = `preview${Date.now()}n${ticket}`;
      const started = (): void => { if (this.valid(ticket)) this.state.loading = false; };
      if (config !== undefined) {
        await player.speak(context, config, sample.slice(0, 300), speed, id, started, output);
      } else {
        const buffer = await this.synthesize(person, language, sample.slice(0, 300), Math.min(2, speed), id, ticket);
        if (!this.valid(ticket)) return;
        await player.speakAudio(context, buffer, Math.max(1, speed / 2), id, started, output);
      }
    } catch (_error) {
      if (this.valid(ticket)) this.state.error = true;
    } finally {
      if (this.valid(ticket)) this.stop();
      player.cancel();
      await output.release();
    }
  }

  private synthesize(person: number, language: string, sample: string, speed: number,
    id: string, ticket: number): Promise<ArrayBuffer> {
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
