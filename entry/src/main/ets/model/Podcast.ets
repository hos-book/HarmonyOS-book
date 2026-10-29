/** RSS metadata. Playback positions remain owned by the existing playback store. */
export class PodcastEpisode {
  id: string = '';
  feedUrl: string = '';
  feedTitle: string = '';
  coverUrl: string = '';
  title: string = '';
  description: string = '';
  audioUrl: string = '';
  publishedAt: number = 0;
  durationSeconds: number = 0;
}

export class PodcastFeed {
  feedUrl: string = '';
  title: string = '';
  author: string = '';
  description: string = '';
  coverUrl: string = '';
  updatedAt: number = 0;
  episodes: PodcastEpisode[] = [];
}

export class PodcastDirectoryEpisode {
  title: string = '';
  poster: string = '';
  publishedAt: string = '';
  duration: string = '';
}

export class PodcastDirectoryEntry {
  id: string = '';
  title: string = '';
  author: string = '';
  cover: string = '';
  description: string = '';
  platform: string = '';
  tags: string[] = [];
  rssUrl: string = '';
  latestEpisode: PodcastDirectoryEpisode = new PodcastDirectoryEpisode();
}

export class PodcastDirectoryData {
  rightNow: PodcastDirectoryEntry[] = [];
  featured: PodcastDirectoryEntry[] = [];
  promoted: PodcastDirectoryEntry[] = [];
}

export class PodcastIdentity {
  /** Two independent 32-bit hashes keep persisted identifiers short and independent of list order. */
  static key(value: string): string {
    let first: number = 2166136261;
    let second: number = 5381;
    for (let index = 0; index < value.length; index++) {
      first = Math.imul(first ^ value.charCodeAt(index), 16777619);
      second = Math.imul(second, 33) ^ value.charCodeAt(index);
    }
    return (first >>> 0).toString(16).padStart(8, '0') + (second >>> 0).toString(16).padStart(8, '0');
  }

  static bookId(feedUrl: string): string { return 'podcast_' + PodcastIdentity.key(feedUrl); }
  static episodeUrl(feedUrl: string, episodeId: string): string { return feedUrl + '#podcast=' + episodeId; }
  static chapterId(bookId: string, chapterUrl: string): string {
    return bookId + '-p' + PodcastIdentity.key(chapterUrl);
  }
}
