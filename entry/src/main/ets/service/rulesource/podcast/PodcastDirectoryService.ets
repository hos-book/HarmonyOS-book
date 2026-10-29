import http from '@ohos.net.http';
import { PodcastDirectoryData, PodcastDirectoryEntry } from '../../../model/Podcast';
import { PodcastFeedParser } from './PodcastFeedParser';

/** Public directory metadata only. Audio is fetched from an explicitly selected RSS subscription. */
export class PodcastDirectoryService {
  private static cached: PodcastDirectoryData | undefined = undefined;
  private static updatedAt: number = 0;
  private static pending: Promise<PodcastDirectoryData> | undefined = undefined;
  static readonly URL: string = 'https://getpodcast.xyz/';

  static async load(refresh: boolean = false): Promise<PodcastDirectoryData> {
    if (PodcastDirectoryService.pending !== undefined) return PodcastDirectoryService.pending;
    if (!refresh && PodcastDirectoryService.cached !== undefined && Date.now() - PodcastDirectoryService.updatedAt < 15 * 60000) {
      return PodcastDirectoryService.cached;
    }
    PodcastDirectoryService.pending = PodcastDirectoryService.fetch();
    try {
      const data = await PodcastDirectoryService.pending;
      PodcastDirectoryService.cached = data;
      PodcastDirectoryService.updatedAt = Date.now();
      return data;
    } finally { PodcastDirectoryService.pending = undefined; }
  }

  private static async fetch(): Promise<PodcastDirectoryData> {
    const client = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000, readTimeout: 20000, maxLimit: 2 * 1024 * 1024,
        header: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' }
      };
      const response = await client.request(PodcastDirectoryService.URL, options);
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        console.warn(`[PodcastDirectory] HTTP ${response.responseCode}`);
        throw new Error('podcast_directory_failed');
      }
      return PodcastDirectoryService.parse(response.result);
    } finally { client.destroy(); }
  }

  static parse(html: string): PodcastDirectoryData {
    if (html.length > 2 * 1024 * 1024) throw new Error('podcast_directory_failed');
    const marker = html.indexOf('window.__INITIAL_DATA__');
    const start = html.indexOf('=', marker);
    const end = html.indexOf('</script>', start);
    if (marker < 0 || start < 0 || end < start) throw new Error('podcast_directory_failed');
    const json = html.substring(start + 1, end).trim().replace(/;\s*$/, '');
    const raw: PodcastDirectoryData = JSON.parse(json);
    const data = new PodcastDirectoryData();
    data.rightNow = PodcastDirectoryService.validEntries(raw.rightNow, 20);
    data.featured = PodcastDirectoryService.validEntries(raw.featured, 500);
    data.promoted = PodcastDirectoryService.validEntries(raw.promoted, 20);
    if (data.featured.length === 0 && data.rightNow.length === 0) throw new Error('podcast_directory_failed');
    return data;
  }

  private static validEntries(items: PodcastDirectoryEntry[], limit: number): PodcastDirectoryEntry[] {
    if (!Array.isArray(items)) return [];
    const results: PodcastDirectoryEntry[] = [];
    const seen = new Set<string>();
    for (const item of items) {
      if (item === null || typeof item.title !== 'string' || typeof item.rssUrl !== 'string' || !item.title.trim()) continue;
      const rssUrl = PodcastFeedParser.httpUrl(item.rssUrl);
      if (!rssUrl || seen.has(rssUrl)) continue;
      seen.add(rssUrl);
      const entry = new PodcastDirectoryEntry();
      entry.id = typeof item.id === 'string' ? item.id : rssUrl;
      entry.title = item.title.slice(0, 256);
      entry.rssUrl = rssUrl;
      entry.author = typeof item.author === 'string' ? item.author.slice(0, 256) : '';
      entry.cover = PodcastFeedParser.httpUrl(typeof item.cover === 'string' ? item.cover : '');
      entry.description = typeof item.description === 'string' ? item.description.slice(0, 1500) : '';
      entry.platform = typeof item.platform === 'string' ? item.platform : '';
      entry.tags = Array.isArray(item.tags) ? item.tags.filter((tag: string): boolean => typeof tag === 'string').slice(0, 20) : [];
      if (item.latestEpisode !== null && item.latestEpisode !== undefined && typeof item.latestEpisode.title === 'string') {
        entry.latestEpisode = item.latestEpisode;
      }
      results.push(entry);
      if (results.length >= limit) break;
    }
    return results;
  }
}
