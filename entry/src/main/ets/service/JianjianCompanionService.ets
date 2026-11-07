import { common } from '@kit.AbilityKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { PlayerState, PLAYER_STATE_KEY, SleepMode } from '../model/PlayerState';
import { PreferenceService } from './PreferenceService';
import { StatsService } from './StatsService';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';

export class JianjianCompanionInfo {
  greeting: ResourceStr = $r('app.string.jianjian_reply_company');
  summary: ResourceStr = $r('app.string.jianjian_stats_unavailable');
  expression: number = 7;
  suggestImport: boolean = false;
  suggestSources: boolean = false;
}

/** Local feedback only: opening or tapping the companion never sends an AI request. */
export class JianjianCompanionService {
  static async feedback(context: common.Context): Promise<JianjianCompanionInfo> {
    const info = new JianjianCompanionInfo();
    let hasHistory: boolean = true;
    try {
      await StatsService.init(context);
      const stats = await StatsService.getStatsBundle(1);
      const minutes = Math.floor(stats.summary.todaySeconds / 60);
      info.summary = $r('app.string.jianjian_today_summary', minutes, stats.streak);
      info.greeting = minutes > 0 ? $r('app.string.jianjian_today_feedback', minutes) : $r('app.string.jianjian_ready_feedback');
      hasHistory = stats.records.length > 0;
      if (stats.streak >= 3) {
        info.greeting = $r('app.string.jianjian_streak_feedback', stats.streak);
        info.expression = 8;
      }
    } catch (_error) { /* Keep a neutral greeting when local statistics are unavailable. */ }
    try {
      const favorites = await PreferenceService.getFavorites();
      info.suggestImport = !hasHistory && favorites.length === 0;
      const sources = await LocalRuleSourceRepository.getAll();
      info.suggestSources = info.suggestImport && sources.length === 0;
      if (info.suggestImport) info.greeting = $r('app.string.jianjian_first_book');
    } catch (_error) { /* A storage error is not an empty library. */ }
    const player = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, (): PlayerState => new PlayerState());
    if (player?.isPlaying) {
      info.greeting = player.sleepMode !== SleepMode.Off ? $r('app.string.jianjian_sleep_feedback') :
        $r('app.string.jianjian_listening_feedback');
      info.expression = player.sleepMode !== SleepMode.Off ? 3 : 7;
    }
    return info;
  }

  static quietRoute(route: string): boolean {
    return ['reader', 'comicReader', 'player', 'ruleSourceLogin', 'jianjianChat', 'jianjianAiSettings'].includes(route);
  }
}
