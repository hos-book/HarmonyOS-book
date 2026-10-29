import { audio } from '@kit.AudioKit';
import { PlatformCompat } from '../utils/PlatformCompat';
import { PreferenceService } from './PreferenceService';
import { DiagnosticLogService } from './DiagnosticLogService';
import { ExternalMediaWatcher } from './ExternalMediaWatcher';

/** 有声书与两种 TTS 共用一个应用级音频会话；只恢复被系统打断的播放。 */
export class AudioFocusService {
  private static instance: AudioFocusService = new AudioFocusService();
  private session: audio.AudioSessionManager | null = null;
  private owner: string = '';
  private generation: number = 0;
  private interruptionVersion: number = 0;
  private waitingForSystem: boolean = false;
  private waitingForUnduck: boolean = false;
  private mode: number = 0;
  private waiting: boolean = false;
  private chain: Promise<void> = Promise.resolve();
  private pausePlayback: (() => void) | null = null;
  private resumePlayback: (() => Promise<void>) | null = null;
  private watcher: ExternalMediaWatcher = new ExternalMediaWatcher();
  private readonly onState = (event: audio.AudioSessionStateChangedEvent): void => {
    const hint = event.stateChangeHint;
    DiagnosticLogService.info('audio.focus', `owner=${this.owner}; hint=${hint}; waiting=${this.waiting}; mode=${this.mode}`);
    if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE) this.interrupt(false);
    else if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_STOP) this.interrupt(true);
    else if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME) this.restore(true);
    else if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_DUCK && this.mode === 0) {
      this.interrupt(false, true);
    } else if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_UNDUCK && this.waitingForUnduck) {
      this.restore();
    }
    else if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_TIME_OUT_STOP) {
      // 无流超时不是抢占；已有恢复意图继续等待外部音频结束。
      if (this.waiting) this.watchForEnd();
    }
  };

  static getInstance(): AudioFocusService { return AudioFocusService.instance; }

  acquire(owner: string, pausePlayback: () => void, resumePlayback: () => Promise<void>): Promise<void> {
    const ticket = ++this.generation;
    this.owner = owner;
    this.pausePlayback = pausePlayback;
    this.resumePlayback = resumePlayback;
    this.waiting = false;
    this.watcher.disarm();
    const task = this.chain.catch((): void => {}).then(async (): Promise<void> => {
      const mode: number = await PreferenceService.getAudioFocusMode();
      if (ticket !== this.generation || this.owner !== owner || this.waiting) return;
      this.mode = mode;
      if (this.session === null) {
        this.session = audio.getAudioManager().getSessionManager();
        this.session.on('audioSessionStateChanged', this.onState);
      }
      this.session.setAudioSessionScene(audio.AudioSessionScene.AUDIO_SESSION_SCENE_MEDIA);
      if (PlatformCompat.supports(26)) {
        this.session.setAudioSessionBehavior(mode === 0
          ? audio.AudioSessionBehaviorFlags.PAUSE_WHEN_INTERRUPTED
          : audio.AudioSessionBehaviorFlags.DEFAULT_BEHAVIOR);
      }
      await this.session.activateAudioSession({ concurrencyMode: mode === 1
        ? audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS
        : audio.AudioConcurrencyMode.CONCURRENCY_PAUSE_OTHERS });
    });
    this.chain = task;
    return task;
  }

  /** 先撤销意图，再串行停用，避免旧播放器的清理停掉后来的播放器。 */
  release(owner: string): Promise<void> {
    if (this.owner !== owner) return Promise.resolve();
    this.generation++;
    this.owner = '';
    this.waiting = false;
    this.pausePlayback = null;
    this.resumePlayback = null;
    this.watcher.disarm();
    const task = this.chain.catch((): void => {}).then(async (): Promise<void> => {
      if (this.session !== null) await this.session.deactivateAudioSession();
    }).catch((error: Error): void => { DiagnosticLogService.info('audio.focus.release', error.message); });
    this.chain = task;
    return task;
  }

  cancelRecovery(owner: string): void {
    if (this.owner === owner && this.waiting) this.release(owner);
  }

  isWaiting(owner: string): boolean { return this.owner === owner && this.waiting; }

  async ensureActive(owner: string): Promise<boolean> {
    if (this.owner !== owner || this.waiting) return false;
    if (this.session?.isAudioSessionActivated()) return true;
    const pausePlayback = this.pausePlayback;
    const resumePlayback = this.resumePlayback;
    if (pausePlayback === null || resumePlayback === null) return false;
    await this.acquire(owner, pausePlayback, resumePlayback);
    return this.owner === owner && !this.waiting;
  }

  handleInterrupt(owner: string, event: audio.InterruptEvent): void {
    if (this.owner !== owner) return;
    if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) this.interrupt(false);
    else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) this.interrupt(true);
    else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) this.restore(true);
    else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_DUCK && this.mode === 0) this.interrupt(false, true);
    else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_UNDUCK && this.waitingForUnduck) this.restore();
  }

  async setMode(mode: number): Promise<void> {
    const previous: number = await PreferenceService.getAudioFocusMode();
    await PreferenceService.setAudioFocusMode(mode);
    this.mode = mode;
    const owner = this.owner;
    const pausePlayback = this.pausePlayback;
    const resumePlayback = this.resumePlayback;
    // 等待中只更新偏好，不因设置操作抢回焦点。
    if (!owner || this.waiting || pausePlayback === null || resumePlayback === null) return;
    try { await this.acquire(owner, pausePlayback, resumePlayback); }
    catch (error) {
      await PreferenceService.setAudioFocusMode(previous);
      this.mode = previous;
      const failure: Error = error;
      throw failure;
    }
  }

  private interrupt(permanent: boolean, duck: boolean = false): void {
    if (!this.owner) return;
    this.interruptionVersion++;
    this.waitingForSystem = !permanent;
    this.waitingForUnduck = duck;
    const first = !this.waiting;
    this.waiting = true;
    this.watcher.disarm();
    if (first) this.pausePlayback?.();
    if (permanent) this.watchForEnd();
  }

  private watchForEnd(): void {
    const ticket = this.generation;
    const interruption = this.interruptionVersion;
    this.watcher.arm((): void => {
      if (ticket === this.generation && interruption === this.interruptionVersion) this.restore();
    });
  }

  private restore(fromSystem: boolean = false): void {
    if (!this.owner || !this.waiting || (fromSystem && !this.waitingForSystem)) return;
    this.waiting = false;
    this.watcher.disarm();
    const resume = this.resumePlayback;
    if (resume !== null) resume().catch((error: Error): void => {
      DiagnosticLogService.info('audio.focus.resume', error.message);
    });
  }
}
