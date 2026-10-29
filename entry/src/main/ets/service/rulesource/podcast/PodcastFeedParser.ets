import convertxml from '@ohos.convertxml';
import { url } from '@kit.ArkTS';
import { PodcastEpisode, PodcastFeed, PodcastIdentity } from '../../../model/Podcast';

class PodcastXmlAttributes {
  url: string = '';
  href: string = '';
  type: string = '';
  rel: string = '';
}

export class PodcastXmlNode {
  name: string = '';
  text: string = '';
  cdata: string = '';
  attributes: PodcastXmlAttributes = new PodcastXmlAttributes();
  elements: PodcastXmlNode[] = [];
}

/** Bounded native XML conversion; called exclusively by the taskpool worker. */
export class PodcastFeedParser {
  static readonly MAX_BYTES: number = 500 * 1024 * 1024;

  static parse(xmlText: string, feedUrl: string): PodcastFeed {
    if (xmlText.length > PodcastFeedParser.MAX_BYTES) throw new Error('podcast_feed_too_large');
    if (/<!\s*(DOCTYPE|ENTITY)/i.test(xmlText)) {
      throw new Error('podcast_invalid_feed');
    }
    return PodcastFeedParser.fromDocument(PodcastFeedParser.document(xmlText), feedUrl);
  }

  static document(xmlText: string): PodcastXmlNode {
    const options: convertxml.ConvertOptions = {
      trim: true, ignoreDeclaration: true, ignoreInstruction: true, ignoreComment: true,
      ignoreDoctype: true, declarationKey: 'declaration', instructionKey: 'instruction',
      attributesKey: 'attributes', textKey: 'text', cdataKey: 'cdata', doctypeKey: 'doctype',
      commentKey: 'comment', parentKey: 'parent', typeKey: 'type', nameKey: 'name', elementsKey: 'elements'
    };
    const root: PodcastXmlNode = JSON.parse(JSON.stringify(new convertxml.ConvertXML()
      .fastConvertToJSObject(xmlText, options)));
    return root;
  }

  static fromDocument(root: PodcastXmlNode, feedUrl: string): PodcastFeed {
    const rss = PodcastFeedParser.child(root, 'rss');
    const channel = rss === undefined ? PodcastFeedParser.child(root, 'feed') : PodcastFeedParser.child(rss, 'channel');
    if (channel === undefined) throw new Error('podcast_invalid_feed');
    const feed = new PodcastFeed();
    feed.feedUrl = feedUrl;
    PodcastFeedParser.readMetadata(feed, channel);
    const seen = new Set<string>();
    for (const node of channel.elements ?? []) PodcastFeedParser.appendEpisode(feed, node, seen);
    return PodcastFeedParser.finish(feed);
  }

  static readMetadata(feed: PodcastFeed, channel: PodcastXmlNode): void {
    feed.title = PodcastFeedParser.value(channel, ['title']).slice(0, 256);
    feed.author = PodcastFeedParser.value(channel, ['itunes:author', 'author', 'managingEditor']).slice(0, 256);
    feed.description = PodcastFeedParser.value(channel, ['description', 'subtitle', 'itunes:summary']).slice(0, 3000);
    feed.coverUrl = PodcastFeedParser.cover(channel, feed.feedUrl);
    feed.updatedAt = Date.now();
  }

  static appendEpisode(feed: PodcastFeed, node: PodcastXmlNode, seen: Set<string>): void {
      if (node.name !== 'item' && node.name !== 'entry') return;
      const enclosure = (node.elements ?? []).find((item: PodcastXmlNode): boolean =>
        item.name === 'enclosure' || (item.name === 'link' && item.attributes?.rel === 'enclosure'));
      const declaredType = enclosure?.attributes?.type ?? '';
      if (declaredType && !declaredType.startsWith('audio/') && declaredType !== 'application/octet-stream') return;
      const audioUrl = PodcastFeedParser.httpUrl(enclosure?.attributes?.url || enclosure?.attributes?.href || '', feed.feedUrl);
      if (!audioUrl) return;
      const episode = new PodcastEpisode();
      episode.title = PodcastFeedParser.value(node, ['title']).slice(0, 512);
      if (!episode.title) return;
      const guid = PodcastFeedParser.value(node, ['guid', 'id']) || audioUrl;
      episode.id = PodcastIdentity.key(feed.feedUrl + '\n' + guid);
      if (seen.has(episode.id)) return;
      seen.add(episode.id);
      episode.feedUrl = feed.feedUrl;
      episode.feedTitle = feed.title;
      episode.audioUrl = audioUrl;
      episode.coverUrl = PodcastFeedParser.cover(node, feed.feedUrl) || feed.coverUrl;
      episode.description = PodcastFeedParser.value(node, ['description', 'summary', 'itunes:summary']).slice(0, 1500);
      const published = Date.parse(PodcastFeedParser.value(node, ['pubDate', 'published', 'updated']));
      episode.publishedAt = Number.isFinite(published) ? published : 0;
      episode.durationSeconds = PodcastFeedParser.duration(PodcastFeedParser.value(node, ['itunes:duration', 'duration']));
      feed.episodes.push(episode);
  }

  static finish(feed: PodcastFeed): PodcastFeed {
    if (!feed.title) throw new Error('podcast_invalid_feed');
    if (feed.episodes.length === 0) throw new Error('podcast_no_audio');
    for (const episode of feed.episodes) {
      episode.feedTitle = feed.title;
      if (!episode.coverUrl) episode.coverUrl = feed.coverUrl;
    }
    feed.episodes.sort((left: PodcastEpisode, right: PodcastEpisode): number => right.publishedAt - left.publishedAt);
    return feed;
  }

  static httpUrl(value: string, base: string = ''): string {
    if (!value.trim() || value.length > 8192 || /[\r\n\\]/.test(value)) return '';
    try {
      const parsed = base ? url.URL.parseURL(value.trim(), base) : url.URL.parseURL(value.trim());
      if ((parsed.protocol !== 'https:' && parsed.protocol !== 'http:') || !parsed.hostname || parsed.username || parsed.password) return '';
      parsed.hash = '';
      return parsed.toString();
    } catch (_error) { return ''; }
  }

  private static child(node: PodcastXmlNode, name: string): PodcastXmlNode | undefined {
    return (node.elements ?? []).find((item: PodcastXmlNode): boolean => item.name === name);
  }

  private static text(node: PodcastXmlNode, depth: number = 0): string {
    if (depth > 8) return '';
    let result: string = (node.text ?? '') + (node.cdata ?? '');
    for (const child of node.elements ?? []) {
      result += PodcastFeedParser.text(child, depth + 1);
      if (result.length > 16000) break;
    }
    return result.slice(0, 16000);
  }

  private static value(node: PodcastXmlNode, names: string[]): string {
    for (const name of names) {
      const child = PodcastFeedParser.child(node, name);
      if (child === undefined) continue;
      const value = PodcastFeedParser.text(child).replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ')
        .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/\s+/g, ' ').trim();
      if (value) return value;
    }
    return '';
  }

  private static cover(node: PodcastXmlNode, base: string): string {
    const image = PodcastFeedParser.child(node, 'itunes:image') ?? PodcastFeedParser.child(node, 'image');
    const value = image?.attributes?.href || (image === undefined ? '' : PodcastFeedParser.value(image, ['url'])) ||
      PodcastFeedParser.value(node, ['logo', 'icon']);
    return PodcastFeedParser.httpUrl(value, base);
  }

  private static duration(value: string): number {
    const parts = value.trim().split(':');
    if (parts.length > 3 || parts.some((part: string): boolean => !/^\d+(\.\d+)?$/.test(part))) return 0;
    let seconds: number = 0;
    for (const part of parts) seconds = seconds * 60 + Number(part);
    return Number.isFinite(seconds) ? Math.min(7 * 86400, Math.max(0, Math.floor(seconds))) : 0;
  }
}
