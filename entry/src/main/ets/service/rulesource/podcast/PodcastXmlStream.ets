import { PodcastFeed } from '../../../model/Podcast';
import { PodcastFeedParser, PodcastXmlNode } from './PodcastFeedParser';

/** Incremental XML framing. Native XML conversion sees only one direct channel child at a time. */
export class PodcastXmlStream {
  private pending: string = '';
  private stack: string[] = [];
  private fragment: string = '';
  private fragmentDepth: number = 0;
  private metadata: PodcastXmlNode = new PodcastXmlNode();
  private feed: PodcastFeed = new PodcastFeed();
  private seen: Set<string> = new Set();
  private rootSeen: boolean = false;
  private rootClosed: boolean = false;
  private namespaces: string = '';

  constructor(feedUrl: string) { this.feed.feedUrl = feedUrl; }

  append(text: string): void {
    this.pending += text;
    while (this.pending.length > 0) {
      const start = this.pending.indexOf('<');
      if (start < 0) {
        this.capture(this.pending);
        this.pending = '';
        break;
      }
      if (start > 0) {
        this.capture(this.pending.substring(0, start));
        this.pending = this.pending.substring(start);
      }
      let end: number = -1;
      let special: boolean = false;
      if (this.pending.startsWith('<![CDATA[')) {
        const close = this.pending.indexOf(']]>', 9);
        if (close >= 0) end = close + 2;
        special = true;
      } else if (this.pending.startsWith('<!--')) {
        const close = this.pending.indexOf('-->', 4);
        if (close >= 0) end = close + 2;
        special = true;
      } else {
        let quote: string = '';
        for (let index = 1; index < this.pending.length; index++) {
          const value = this.pending.charAt(index);
          if (quote) { if (value === quote) quote = ''; }
          else if (value === '"' || value === "'") quote = value;
          else if (value === '>') { end = index; break; }
        }
      }
      if (end < 0) break;
      const token = this.pending.substring(0, end + 1);
      this.pending = this.pending.substring(end + 1);
      if (special || token.startsWith('<?')) this.capture(token);
      else this.tag(token);
    }
    // This bounds a single malformed XML token, independently of the 500 MB feed budget.
    if (this.pending.length > 8 * 1024 * 1024) throw new Error('podcast_invalid_feed');
  }

  private capture(value: string): void {
    if (this.fragmentDepth === 0) return;
    this.fragment += value;
    if (this.fragment.length > 8 * 1024 * 1024) throw new Error('podcast_invalid_feed');
  }

  private tag(token: string): void {
    if (token.startsWith('<!')) throw new Error('podcast_invalid_feed');
    const closing = token.startsWith('</');
    const match = /^<\/?([\w:.-]+)/.exec(token);
    if (match === null) throw new Error('podcast_invalid_feed');
    const name = match[1];
    const empty = /\/\s*>$/.test(token);
    if (closing) {
      if (this.stack.pop() !== name) throw new Error('podcast_invalid_feed');
      this.capture(token);
      if (this.fragmentDepth > 0 && this.stack.length < this.fragmentDepth) this.consume();
      if (this.stack.length === 0) this.rootClosed = true;
      return;
    }
    if (this.stack.length === 0) {
      if (this.rootSeen || (name !== 'rss' && name !== 'feed')) throw new Error('podcast_invalid_feed');
      this.rootSeen = true;
      const declarations = token.match(/\s+xmlns(?::[\w.-]+)?\s*=\s*(?:"[^"]*"|'[^']*')/g);
      this.namespaces = declarations === null ? '' : declarations.join(' ');
    }
    const parent = this.stack[this.stack.length - 1];
    if (this.fragmentDepth === 0 && ((parent === 'channel' && this.stack.length === 2) ||
      (parent === 'feed' && this.stack.length === 1))) {
      this.fragmentDepth = this.stack.length + 1;
    }
    this.capture(token);
    if (!empty) this.stack.push(name);
    else if (this.fragmentDepth > 0 && this.stack.length < this.fragmentDepth) this.consume();
  }

  private consume(): void {
    const document = PodcastFeedParser.document(`<podcast${this.namespaces}>${this.fragment}</podcast>`);
    const wrapper = document.elements?.find((node: PodcastXmlNode): boolean => node.name === 'podcast');
    const node = wrapper?.elements?.find((item: PodcastXmlNode): boolean => !!item.name);
    if (node === undefined) throw new Error('podcast_invalid_feed');
    if (node.name === 'item' || node.name === 'entry') PodcastFeedParser.appendEpisode(this.feed, node, this.seen);
    else if (['title', 'itunes:author', 'author', 'managingEditor', 'description', 'subtitle', 'itunes:summary',
      'itunes:image', 'image', 'logo', 'icon'].includes(node.name)) {
      // Keep one value per metadata field; item descriptions are released after conversion.
      if (!this.metadata.elements.some((item: PodcastXmlNode): boolean => item.name === node.name)) this.metadata.elements.push(node);
    }
    this.fragment = '';
    this.fragmentDepth = 0;
  }

  finish(): PodcastFeed {
    if (this.pending.trim() || this.stack.length > 0 || !this.rootClosed) throw new Error('podcast_invalid_feed');
    PodcastFeedParser.readMetadata(this.feed, this.metadata);
    return PodcastFeedParser.finish(this.feed);
  }
}
