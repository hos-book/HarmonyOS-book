import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { PodcastFeed } from '../../../model/Podcast';

/** Subscription state and feed cache; source definitions stay in rule_sources.db. */
export class PodcastRepository {
  private static store: relationalStore.RdbStore | undefined = undefined;
  private static opening: Promise<void> | undefined = undefined;

  static async init(context: common.BaseContext): Promise<void> {
    if (PodcastRepository.store !== undefined) return;
    if (PodcastRepository.opening === undefined) PodcastRepository.opening = PodcastRepository.open(context);
    try { await PodcastRepository.opening; }
    catch (_error) { PodcastRepository.opening = undefined; throw new Error('podcast_storage_failed'); }
  }

  private static async open(context: common.BaseContext): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: 'podcasts.db', securityLevel: relationalStore.SecurityLevel.S2, encrypt: true, allowRebuild: false
    };
    const store = await relationalStore.getRdbStore(context, config);
    await store.execute('CREATE TABLE IF NOT EXISTS podcast_feeds (' +
      'feed_url TEXT PRIMARY KEY NOT NULL, feed_json TEXT NOT NULL, updated_at INTEGER NOT NULL)');
    PodcastRepository.store = store;
  }

  static async list(): Promise<PodcastFeed[]> {
    if (PodcastRepository.store === undefined) throw new Error('podcast_storage_failed');
    const rows = await PodcastRepository.store.querySql('SELECT feed_json FROM podcast_feeds ORDER BY updated_at DESC');
    const feeds: PodcastFeed[] = [];
    try {
      while (rows.goToNextRow()) {
        const feed: PodcastFeed = JSON.parse(rows.getString(0));
        feeds.push(feed);
      }
    } finally { rows.close(); }
    return feeds;
  }

  static async save(feed: PodcastFeed): Promise<void> {
    if (PodcastRepository.store === undefined) throw new Error('podcast_storage_failed');
    const values: relationalStore.ValuesBucket = {
      feed_url: feed.feedUrl, feed_json: JSON.stringify(feed), updated_at: feed.updatedAt
    };
    await PodcastRepository.store.insert('podcast_feeds', values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  static async unsubscribe(feedUrl: string): Promise<void> {
    if (PodcastRepository.store === undefined) throw new Error('podcast_storage_failed');
    const predicates = new relationalStore.RdbPredicates('podcast_feeds');
    predicates.equalTo('feed_url', feedUrl);
    await PodcastRepository.store.delete(predicates);
  }
}
