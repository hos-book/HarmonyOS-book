import { audio } from '@kit.AudioKit';
import { PlatformCompat } from '../utils/PlatformCompat';
import { DiagnosticLogService } from './DiagnosticLogService';
import { ExternalMediaWatcher } from './ExternalMediaWatcher';
import { AudioPlaybackMode, PreferenceService } from './PreferenceService';

/** 有声书与 TTS 共用媒体会话，按所选音频模式处理播放恢复。 */
export class AudioFocusService {
  private static instance: AudioFocusService = new AudioFocusService();
  private session: audio.AudioSessionManager | null = null;
  private owner: string = '';
  private generation: number = 0;
  private interruptionVersion: number = 0;
  private waitingForSystem: boolean = false;
  private waiting: boolean = false;
  private autoResumeEnabled: boolean = true;
  private chain: Promise<void> = Promise.resolve();
  private pausePlayback: (() => void) | null = null;
  private resumePlayback: (() => Promise<void>) | null = null;
  private watcher: ExternalMediaWatcher = new ExternalMediaWatcher();
  private readonly onState = (event: audio.AudioSessionStateChangedEvent): void => {
    const hint = event.stateChangeHint;
    DiagnosticLogService.info('audio.focus', `owner=${this.owner}; hint=${hint}; waiting=${this.waiting}; policy=system`);
    if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE) this.interrupt(false);
    else if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_STOP) this.interrupt(true);
    else if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME) this.restore(true);
    // DUCK/UNDUCK 由系统调整音量；不暂停播放、不取消合成，也不解除另一次暂停。
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
      if (ticket !== this.generation || this.owner !== owner || this.waiting) return;
      const mode = await PreferenceService.getAudioPlaybackMode();
      if (ticket !== this.generation || this.owner !== owner || this.waiting) return;
      this.autoResumeEnabled = mode === AudioPlaybackMode.AutoResume;
      if (this.session === null) {
        this.session = audio.getAudioManager().getSessionManager();
        this.session.on('audioSessionStateChanged', this.onState);
      }
      await this.activateSession(this.session, mode);
    });
    this.chain = task;
    return task;
  }

  applyPlaybackMode(mode: AudioPlaybackMode): Promise<void> {
    this.autoResumeEnabled = mode === AudioPlaybackMode.AutoResume;
    if (!this.autoResumeEnabled) this.cancelRecovery(this.owner);
    const ticket = this.generation;
    const owner = this.owner;
    const session = this.session;
    if (owner.length === 0 || session === null) return Promise.resolve();
    const task = this.chain.catch((): void => {}).then(async (): Promise<void> => {
      if (ticket !== this.generation || this.owner !== owner || this.session !== session) return;
      await this.activateSession(session, mode);
    });
    this.chain = task;
    return task;
  }

  private activateSession(session: audio.AudioSessionManager, mode: AudioPlaybackMode): Promise<void> {
    session.setAudioSessionScene(audio.AudioSessionScene.AUDIO_SESSION_SCENE_MEDIA);
    if (PlatformCompat.supports(26)) {
      session.setAudioSessionBehavior(audio.AudioSessionBehaviorFlags.PAUSE_WHEN_INTERRUPTED);
    }
    const concurrencyMode: audio.AudioConcurrencyMode = mode === AudioPlaybackMode.Coexistence && PlatformCompat.supports(23)
      ? audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS
      : audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT;
    return session.activateAudioSession({ concurrencyMode: concurrencyMode });
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
    // 播放器与会话回调使用同一策略；系统压低音量不改变播放或恢复意图。
  }

  private interrupt(permanent: boolean): void {
    if (!this.owner) return;
    this.interruptionVersion++;
    this.waitingForSystem = !permanent;
    const first = !this.waiting;
    this.waiting = true;
    this.watcher.disarm();
    if (first) this.pausePlayback?.();
    if (!this.autoResumeEnabled) {
      this.cancelRecovery(this.owner);
      return;
    }
    if (permanent) this.watchForEnd();
  }

  private watchForEnd(): void {
    // API 26 由系统决定恢复；活动流查询仅兼容缺少暂停行为标志的旧系统。
    if (PlatformCompat.supports(26)) return;
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
