import { common } from '@kit.AbilityKit';
import lazy { audio } from '@kit.AudioKit';
import lazy { media } from '@kit.MediaKit';
import { GeneralSettings } from '../../model/GeneralSettings';
import { ReaderHapticService } from '../text/ReaderHapticService';

const TICK_RESOURCE: string = 'ranking_tick.wav';
const FEEDBACK_INTERVAL_MS: number = 80;

/** 榜单手动换书的短音与轻触觉；只在首次交互加载，离屏释放。 */
export class RankingFeedbackService {
  private active: boolean = false;
  private generation: number = 0;
  private pool: media.SoundPool | undefined = undefined;
  private poolGeneration: number = -1;
  private soundId: number = 0;
  private loading: Promise<void> | undefined = undefined;
  private cleanup: Promise<void> = Promise.resolve();
  private closeResource: (() => Promise<void>) | undefined = undefined;
  private failed: boolean = false;
  private lastFeedbackAt: number = 0;

  setActive(active: boolean): void {
    if (active === this.active) return;
    this.active = active;
    if (active) return;
    this.generation++;
    this.soundId = 0;
    this.failed = false;
    this.lastFeedbackAt = 0;
    const loading = this.loading;
    this.loading = undefined;
    const previousCleanup = this.cleanup;
    this.cleanup = this.releaseAfter(previousCleanup, loading);
  }

  play(context: common.Context): void {
    if (!this.active || !GeneralSettings.current.rankingScrollFeedback) return;
    const now: number = Date.now();
    if (now - this.lastFeedbackAt < FEEDBACK_INTERVAL_MS) return;
    this.lastFeedbackAt = now;
    ReaderHapticService.play('weak');
    if (this.soundId > 0) {
      this.playSound();
    } else if ((this.pool === undefined || this.poolGeneration !== this.generation) &&
      this.loading === undefined && !this.failed) {
      const generation = this.generation;
      this.loading = this.prepare(context, generation, this.cleanup).finally((): void => {
        if (generation === this.generation) this.loading = undefined;
      });
    }
  }

  private async prepare(context: common.Context, generation: number, cleanup: Promise<void>): Promise<void> {
    try {
      await cleanup;
      if (!this.active || generation !== this.generation) return;
      // SoundPool 的 MUSIC 短音默认并发混音，不抢占正在播放的听书音频。
      const info: audio.AudioRendererInfo = { usage: audio.StreamUsage.STREAM_USAGE_MUSIC, rendererFlags: 1 };
      const pool = await media.createSoundPool(1, info);
      if (!this.active || generation !== this.generation) {
        await pool.release();
        return;
      }
      this.pool = pool;
      this.poolGeneration = generation;
      const descriptor = await context.resourceManager.getRawFd(TICK_RESOURCE);
      this.closeResource = (): Promise<void> => context.resourceManager.closeRawFd(TICK_RESOURCE);
      if (!this.active || generation !== this.generation) return;
      pool.on('loadComplete', (soundId: number): void => {
        if (!this.active || generation !== this.generation) return;
        this.soundId = soundId;
        // 首次解码慢时丢弃过期反馈，不在手势结束后补播。
        if (Date.now() - this.lastFeedbackAt <= 120) this.playSound();
      });
      pool.on('error', (): void => {
        if (generation !== this.generation) return;
        this.failed = true;
        this.soundId = 0;
      });
      await pool.load(descriptor.fd, descriptor.offset, descriptor.length);
    } catch (_error) {
      if (generation === this.generation) this.failed = true;
    }
  }

  private playSound(): void {
    const pool = this.pool;
    if (!this.active || !GeneralSettings.current.rankingScrollFeedback || pool === undefined || this.soundId <= 0) return;
    try {
      const params: media.PlayParameters = { loop: 0, leftVolume: 0.22, rightVolume: 0.22, priority: 0 };
      pool.play(this.soundId, params).catch((): void => {});
    } catch (_error) { /* 音效不可用时不影响手势和轻触觉。 */ }
  }

  private async releaseAfter(previous: Promise<void>, loading: Promise<void> | undefined): Promise<void> {
    await previous;
    await loading;
    const pool = this.pool;
    const closeResource = this.closeResource;
    this.pool = undefined;
    this.closeResource = undefined;
    if (pool !== undefined) {
      try {
        pool.off('loadComplete');
        pool.off('error');
        await pool.release();
      } catch (_error) { /* 已失效的音频服务继续释放文件句柄。 */ }
    }
    if (closeResource !== undefined) {
      try { await closeResource(); } catch (_error) {}
    }
  }
}
