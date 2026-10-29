import { Book, Chapter } from '../../../model/Book';
import { PodcastEpisode, PodcastFeed, PodcastIdentity } from '../../../model/Podcast';
import { LocalRuleSourceImportParser } from '../LocalRuleSourceImportParser';
import { LocalRuleSourceImportService } from '../LocalRuleSourceImportService';
import { LocalRuleSourceRepository } from '../LocalRuleSourceRepository';
import { PodcastRepository } from './PodcastRepository';
import { PodcastSourceAdapter } from './PodcastSourceAdapter';
import { DataService } from '../../DataService';
import { SearchCache } from '../../../utils/SearchCache';

class PodcastDetailFields {
  name: string = 'channel>title@text';
  author: string = 'channel>itunes\\:author@text';
  intro: string = 'channel>description@text';
  tocUrl: string = '= book.bookUrl';
}
class PodcastDetailRule { fields: PodcastDetailFields = new PodcastDetailFields(); }
class PodcastExploreFields { name: string = 'title@text'; bookUrl: string = ''; }
class PodcastExploreMenu { title: string = ''; url: string = ''; }
class PodcastExploreRule {
  menus: PodcastExploreMenu[] = [];
  list: string = 'channel, feed';
  fields: PodcastExploreFields = new PodcastExploreFields();
}
class PodcastTocFields { title: string = 'title@text'; url: string = 'enclosure@url'; }
class PodcastTocRule { list: string = 'item'; fields: PodcastTocFields = new PodcastTocFields(); }
class PodcastContentRule { url: string = ''; audio: string = '= chapter.url'; }
class PodcastSourceDefinition {
  sourceFormat: string = 'native';
  name: string = '';
  url: string = '';
  type: string = 'audio';
  group: string = 'RSS';
  enabled: boolean = true;
  enabledExplore: boolean = false;
  podcastVersion: number = 1;
  podcastFeedUrl: string = '';
  explore: PodcastExploreRule = new PodcastExploreRule();
  detail: PodcastDetailRule = new PodcastDetailRule();
  toc: PodcastTocRule = new PodcastTocRule();
  content: PodcastContentRule = new PodcastContentRule();
}

export class PodcastService {
  static async subscriptions(): Promise<PodcastFeed[]> {
    const sources = await LocalRuleSourceRepository.getAll();
    const urls = new Set<string>();
    for (const source of sources) if (PodcastSourceAdapter.matches(source)) urls.add(source.bookSourceUrl);
    const feeds = (await PodcastRepository.list()).filter((feed: PodcastFeed): boolean => urls.has(feed.feedUrl));
    for (const feed of feeds) PodcastSourceAdapter.remember(feed);
    return feeds;
  }

  static async subscribe(feed: PodcastFeed): Promise<void> {
    const existing = await LocalRuleSourceRepository.getByUrl(feed.feedUrl);
    if (existing !== undefined && !PodcastSourceAdapter.matches(existing)) throw new Error('podcast_source_conflict');
    if (existing === undefined) {
      const definition = new PodcastSourceDefinition();
      definition.name = feed.title;
      definition.url = feed.feedUrl;
      definition.podcastFeedUrl = feed.feedUrl;
      // A feed exposes one programme, without advertising a search endpoint.
      const menu = new PodcastExploreMenu();
      menu.title = feed.title;
      menu.url = feed.feedUrl;
      definition.explore.menus = [menu];
      definition.explore.fields.bookUrl = '= ' + JSON.stringify(feed.feedUrl);
      const report = LocalRuleSourceImportParser.parse(JSON.stringify(definition));
      if (report.sources.length !== 1) throw new Error('podcast_subscription_failed: ' + report.message);
      const imported = await LocalRuleSourceImportService.importSources(report.sources);
      if (imported !== 1) throw new Error('podcast_storage_failed');
    }
    await PodcastRepository.save(feed);
    PodcastSourceAdapter.remember(feed);
  }

  static async refresh(feedUrl: string): Promise<PodcastFeed> {
    const source = await LocalRuleSourceRepository.getByUrl(feedUrl);
    if (source === undefined || !PodcastSourceAdapter.matches(source)) throw new Error('podcast_source_missing');
    const feed = await PodcastSourceAdapter.load(feedUrl, true);
    await PodcastRepository.save(feed);
    return feed;
  }

  static async playbackBook(feed: PodcastFeed): Promise<Book> {
    const source = await LocalRuleSourceRepository.getByUrl(feed.feedUrl);
    if (source === undefined || !PodcastSourceAdapter.matches(source)) throw new Error('podcast_source_missing');
    PodcastSourceAdapter.remember(feed);
    const bookId = PodcastIdentity.bookId(feed.feedUrl);
    const chapters: Chapter[] = feed.episodes.map((episode: PodcastEpisode, index: number): Chapter => {
      const chapterUrl = PodcastIdentity.episodeUrl(feed.feedUrl, episode.id);
      const chapter: Chapter = { id: PodcastIdentity.chapterId(bookId, chapterUrl), index: index + 1,
        title: episode.title, duration: episode.durationSeconds,
        source: { type: 'url', value: chapterUrl }, originSourceValue: chapterUrl };
      return chapter;
    });
    const book: Book = { id: bookId, contentType: 'audio', title: feed.title, author: feed.author,
      narrator: feed.author, cover: feed.coverUrl, category: 'RSS', intro: feed.description,
      totalDuration: chapters.reduce((total: number, chapter: Chapter): number => total + chapter.duration, 0),
      chapterCount: chapters.length, rating: 0, tags: ['RSS'], chapters: chapters, tocComplete: true,
      bookUrl: feed.feedUrl, sourceUrl: feed.feedUrl,
      variables: { '__audioTocDefinition': JSON.stringify(['light-source-toc-v1', source.rawSourceJson, source.variable]) } };
    SearchCache.put(book);
    await DataService.upsertCachedBook(book);
    return book;
  }
}
