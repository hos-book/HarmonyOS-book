import { taskpool } from '@kit.ArkTS';
import { BookInfo, TocItem } from '../../../model/BookSource';
import { LocalRuleSource } from '../../../model/LocalRuleSource';
import { PodcastFeed, PodcastIdentity } from '../../../model/Podcast';
import { LocalRuleContentResult } from '../LocalRuleRuntimeTypes';
import { PodcastFeedParser } from './PodcastFeedParser';
import { downloadPodcastFeed } from './PodcastFeedWorker';

class PodcastSourceMarker {
  podcastVersion: number = 0;
  podcastFeedUrl: string = '';
}

export class PodcastSourceAdapter {
  private static feeds: Map<string, PodcastFeed> = new Map();
  private static pending: Map<string, Promise<PodcastFeed>> = new Map();

  static matches(source: LocalRuleSource): boolean {
    if (source.engine !== 'light-native' || !source.isAudio()) return false;
    try {
      const marker: PodcastSourceMarker = JSON.parse(source.rawSourceJson);
      return marker.podcastVersion === 1 && marker.podcastFeedUrl === source.bookSourceUrl &&
        PodcastFeedParser.httpUrl(marker.podcastFeedUrl) === marker.podcastFeedUrl;
    } catch (_error) { return false; }
  }

  static remember(feed: PodcastFeed): void {
    PodcastSourceAdapter.feeds.delete(feed.feedUrl);
    PodcastSourceAdapter.feeds.set(feed.feedUrl, feed);
    while (PodcastSourceAdapter.feeds.size > 8) {
      for (const key of PodcastSourceAdapter.feeds.keys()) { PodcastSourceAdapter.feeds.delete(key); break; }
    }
  }

  static async load(feedUrl: string, refresh: boolean = false): Promise<PodcastFeed> {
    const existing = PodcastSourceAdapter.pending.get(feedUrl);
    if (existing !== undefined) return existing;
    const cached = PodcastSourceAdapter.feeds.get(feedUrl);
    if (!refresh && cached !== undefined && Date.now() - cached.updatedAt < 10 * 60000) return cached;
    if (PodcastSourceAdapter.pending.size >= 4) throw new Error('podcast_busy');
    const task = PodcastSourceAdapter.download(feedUrl);
    PodcastSourceAdapter.pending.set(feedUrl, task);
    try {
      const feed = await task;
      PodcastSourceAdapter.remember(feed);
      return feed;
    } finally { PodcastSourceAdapter.pending.delete(feedUrl); }
  }

  private static async download(feedUrl: string): Promise<PodcastFeed> {
    if (PodcastFeedParser.httpUrl(feedUrl) !== feedUrl) throw new Error('podcast_invalid_url');
    const result = String(await taskpool.execute(new taskpool.Task(downloadPodcastFeed, feedUrl)));
    const feed: PodcastFeed = JSON.parse(result);
    return feed;
  }

  static async detail(source: LocalRuleSource): Promise<BookInfo> {
    const feed = await PodcastSourceAdapter.load(source.bookSourceUrl);
    const info: BookInfo = {
      name: feed.title, author: feed.author, coverUrl: feed.coverUrl, intro: feed.description,
      kind: 'RSS', wordCount: '', lastChapter: feed.episodes[0]?.title ?? '', tocUrl: feed.feedUrl
    };
    return info;
  }

  static async toc(source: LocalRuleSource): Promise<TocItem[]> {
    const feed = await PodcastSourceAdapter.load(source.bookSourceUrl);
    return feed.episodes.map((episode): TocItem => {
      const item: TocItem = { name: episode.title, url: PodcastIdentity.episodeUrl(feed.feedUrl, episode.id),
        duration: episode.durationSeconds, updateTime: episode.publishedAt > 0 ? new Date(episode.publishedAt).toISOString() : '' };
      return item;
    });
  }

  static async content(source: LocalRuleSource, chapterUrl: string): Promise<LocalRuleContentResult> {
    const feed = await PodcastSourceAdapter.load(source.bookSourceUrl);
    const episode = feed.episodes.find((item): boolean => PodcastIdentity.episodeUrl(feed.feedUrl, item.id) === chapterUrl);
    if (episode === undefined) throw new Error('podcast_episode_missing');
    const result = new LocalRuleContentResult();
    result.title = episode.title;
    result.audioUrl = episode.audioUrl;
    result.mediaType = 'audio';
    return result;
  }
}
